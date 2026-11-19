# `app_lifecycle` — setup review

One agent reviews the service's setup code. Scope = `app.setup_roots` plus one hop into each inventoried resource's constructor and close method (including `vendor/` or the module cache, location in `dep.<module>`).

Facts used: `app.setup_roots`, `app.close_mechanism`, `goroutine.runners`, `dep.<module>`.

Setup must construct dependencies before dependents and close them in reverse dependency order; runners must stop before anything they use is closed. Judge by dependency edges, not by strict LIFO.

## Types

**`app_resource_not_closed`** · High — A value constructed during setup whose type has `Close`/`Shutdown`/`Stop`/`Release`/`Flush`, and for which no close is deferred, registered or run on any shutdown path. `defect_site` = the constructor line.
*Not a defect:* closed by an owner it was handed to (cite the owner's close); the method is a documented no-op or the type holds no OS/network resource (cite the method body).
*Fix:* register a close for it in the setup's close mechanism.

**`app_close_order`** · High — A resource is closed while a dependent can still use it: a dependent built from it (constructor argument, option, captured in a closure) is closed after it, or a runner using it (server, consumer, scheduler, background worker) has not stopped before it closes. `defect_site` = the close/registration line that runs too early.
*Not a defect:* the effective order respects every dependency edge even if it is not strictly LIFO; the dependent holds no reference past its own stop (cite).
*Fix:* close dependents before dependencies — register closes LIFO (defer / reverse registration).

**`app_init_order`** · High — A dependency is used before it is ready: passed or captured while still nil/zero (a struct field read in a constructor or runner before it is assigned), or a runner started (`go`, `errgroup.Go`) before a dependency it uses is constructed. `defect_site` = the use/start line.
*Not a defect:* lazy access that only happens after init completes, proven by the call order (cite).
*Fix:* construct dependencies before dependents; start runners only after every dependency is ready.

*Verify (all three):* build the inventory below and read each type's close method.

**Floor for `app_close_order`:** `verification_note` names the dependency edge (`A uses B`), the close mechanism, and the effective execution order of both closes. Never infer order from source position alone.

## Procedure

1. **Inventory.** From `app.setup_roots`, list every value constructed during setup whose type has `Close`/`Shutdown`/`Stop`/`Release`/`Flush` (read the method set): DB pools and `stdlib.OpenDBFromPool` handles, Kafka/SQS/Redis clients and transports, message writers, caches with background workers, tracer/metric exporters. Per item: construct site, **deps** (inventory items passed as constructor args/options or captured in closures), close site, mechanism.
2. **Runners.** List servers, consumers, schedulers and background workers: start site, deps, how and when they stop (ctx cancel, `Shutdown`, `Close`), and whether the code waits for them (`errgroup.Wait()`, `wg.Wait()`) before resource closes run.
3. **Effective close order.** Start from `app.close_mechanism`, then resolve per site:
    - `defer` → LIFO within a function; a function's defers run before its caller's.
    - close-func slice → as the loop iterates.
    - lifecycle framework or runner group → as its source says, not as its name suggests. If closes run before the wait for runners, a runner's `Close` must itself block until the runner has stopped using its deps.
4. **Check edges.** For every `A uses B`: A closes/stops before B closes → ok; otherwise `app_close_order`. Inventory item with no close on any shutdown path → `app_resource_not_closed`.
5. **Init order.** For every `A uses B`: B is constructed (non-nil, assigned) before A is constructed or started. Watch for reads of struct fields assigned later, runners launched before setup returns, and options capturing a variable reassigned afterwards → `app_init_order`.

```go
// app_close_order — FIFO slice; pool closed while the *sql.DB built on it is still open
closers = append(closers, dbPool.Close)
closers = append(closers, func() { _ = sqlDB.Close() })   // sqlDB ← stdlib.OpenDBFromPool(dbPool)
for _, f := range closers { f() }                          // runs dbPool.Close first

// app_close_order — resources closed before runners stop
defer app.deps.close()
go app.runHTTPServer(ctx)                                  // not awaited; server still serving when deps.close runs

// app_resource_not_closed — writer never closed; buffered messages lost on shutdown
w := &kafka.Writer{Addr: kafka.TCP(brokers...), Topic: topic}

// app_init_order — handler captures app.deps.orders before app.deps is assigned
h := handler.New(app.deps.orders)                          // nil here
app.deps = deps{orders: svc}

// NOT a defect — FIFO slice whose registration order already respects every edge
closers = append(closers, func() { _ = sqlDB.Close() })   // sqlDB → dbPool
closers = append(closers, dbPool.Close)
```

Not this check: a deadline longer than the shutdown grace is `shutdown_grace_mismatch`; a runner goroutine that cannot stop is `goroutine_no_stop`.
