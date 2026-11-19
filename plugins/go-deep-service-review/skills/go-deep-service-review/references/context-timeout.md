# `context` and `timeout` — chain trace

One agent traces one entry point. The two families share the trace; emit only the types of the families named in your prompt.

Facts used: `ctx_types`, `db.statement_timeout`, `client.<name>.*`, `server.<name>.request_deadline`, `shutdown.grace`, `dep.<module>`.

## Trace procedure

1. **Start from the entry point's ctx.** net/http → `r.Context()` · gRPC/connect → first argument · echo → `c.Request().Context()` · gin → `c.Request.Context()` · queue consumer → the callback's ctx · producer/scheduler → its own root (see the async-root rule).
2. **Traverse via interfaces and imports.** Implementations often have no import link to the interface — grep by method signature; `var _ Iface = (*impl)(nil)` pins implementations. Disambiguate same-named siblings through the import alias or the wiring before tracing.
3. **Identify the terminal IO for this chain.** The sink varies per chain: a `Notify*`/`webhook*` name may mean an outbox row inside a transaction. Never infer a sink from a name or carry one over from another chain.
4. **Descend to the concrete driver leaf**, into `vendor/` or the module cache (location in `dep.<module>`).
5. **Sample when homogeneous.** More than ~8 implementations of the same shape → trace the spine plus three of them and set `coverage.sampled: true`.
6. **Stay on the chain.** Error handling, resource closing and goroutine lifetime in shared code belong to the sweeps.

A **context-carrying type** is a struct embedding `context.Context` (listed in `ctx_types`); treat it as a context.

## Rules

- **Wrapper rule.** For a decorator/wrapper that creates a deadline, read the call-site closure, not just the wrapper.
- **Async-root rule.** A library or in-repo scheduler/consumer that creates its own root context at start-up is sanctioned — do not flag `ctx_new_non_derived`. Trace the bridge into the per-message work; if that work has no deadline it is `io_unbounded`.
- **What counts as a bound.** An inherited ctx deadline counts. `http.Server` Read/Write/Idle timeouts do **not** — they do not put a deadline on the handler's ctx. Only something that does counts (`http.TimeoutHandler`, timeout middleware; see `server.<name>.request_deadline`).
- **`context.WithoutCancel`** drops the parent's deadline as well as its cancellation. IO under it needs a new deadline, otherwise it is `io_unbounded`.
- Context must reach every branch doing IO or async work, including channel `select`s. A niladic method that does IO synchronously is in scope even though it has no ctx parameter.
- Record every leaf you prove bounded for all callers under `verified_correct`.

## Types — `context`

**`ctx_not_propagated`** · Critical — An IO/async call on the chain receives a bare `context.Background()`/`TODO()` or no ctx while a parent ctx is in scope.
*Not a defect:* fire-and-forget goroutine with a detached ctx whose result is not awaited; synchronous ctx-less dependency bounded by construction config (cite the fact).
*Verify:* read the call site and the callee signature; show the parent ctx is reachable there.
*Fix:* thread the parent ctx into the IO/async call.

**`ctx_new_non_derived`** · High — A new root context is created mid-chain and derived from (`WithTimeout(context.Background(), d)`, `WithCancel(context.TODO())`) where a parent exists: the work has a deadline but no longer follows the caller's cancellation.
*Not a defect:* sanctioned async root (rule above).
*Verify:* trace the chain to the site; for async roots read the channel/defer/errgroup bridge.
*Fix:* derive from the parent ctx.

**`async_helper_incomplete`** · High — An async helper (in-repo code that runs work in a goroutine and hands back a future, channel or `Await`) whose result the chain waits on fails one of: parent ctx passed in, result awaited, the await selects on `ctx.Done()`.
*Not a defect:* fire-and-forget use where nothing on the chain waits for the result.
*Verify:* read the helper body and the call site.
*Fix:* parent ctx in, result awaited, await selects `ctx.Done()`.

## Types — `timeout`

**`io_unbounded`** · Critical — A concrete driver leaf does IO with no deadline: none inherited, none on the path, none in `facts.md` (statement timeout, client timeout, non-zero library default). Flag only when all three are absent. `defect_site` = the in-repo call that hands the ctx to the leaf.
*Not a defect:* any one bound exists. A cache-fronted read is unbounded only on a cold cache → `confidence: medium`, described as conditional.
*Verify:* trace entry point → leaf reading each hop; cite the fact key that shows no bound in `depends_on_fact`.
*Fix:* add a deadline at the handler, service or leaf.

**`deadline_not_reaching_payload`** · High — A wrapper taking `func()`/`func() error` creates `WithTimeout` internally, but the closure passed in captures the outer ctx.
*Not a defect:* the closure receives the derived ctx as a parameter.
*Verify:* read the wrapper body and the call-site closure.
*Fix:* pass the derived ctx into the closure.

**`timeout_inversion`** · Medium — An inner literal deadline is ≥ the enclosing literal deadline.
*Not a defect:* either value is config/env-driven.
*Verify:* read both literals on the chain.
*Fix:* make the inner deadline shorter than the enclosing one.

**`shutdown_grace_mismatch`** · Low — Work deliberately detached from shutdown cancellation (`context.WithoutCancel` plus a new deadline, or a sanctioned root with a per-message deadline) has a deadline longer than `shutdown.grace`: the process exits before the work can finish.
*Verify:* read the site; cite the fact.
*Fix:* align the deadline with the shutdown grace.
