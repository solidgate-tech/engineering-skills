# `concurrency` — goroutine sweep

Facts used: `goroutine.runners`, `client.<name>.*`, `db.statement_timeout`, `dep.<module>`.

Seeds: `go func`, `go [a-zA-Z_.]+\(`, `errgroup` / `.Go(` calls.

## Type

**`goroutine_no_stop`** · High — A goroutine (`go` statement, `errgroup` or pool `.Go`) that has neither a strictly bounded lifecycle nor an exit on a clear signal. Covers one-shot goroutines too.
- **Bounded** = every blocking op inside (IO, channel send/recv, `select`, `Wait`, `Sleep`, lock) is bounded by a deadline/ctx, a buffered or guaranteed counterpart, or finite input, and every loop terminates.
- **Signalled** = `ctx.Done()`, a done/quit channel, a channel closed by its owner on shutdown, or an errgroup/supervisor ctx — and the signal is actually reachable at every blocking point.

*Not a defect:* the above holds; a supervisor, scheduler or consumer loop that owns its root context and is stopped on shutdown (cite `goroutine.runners`).
*Verify:* read the goroutine body, each blocking op in it, and where its stop signal is created and closed.
*Fix:* bound every blocking op, or add an exit on `ctx.Done()` / a done channel / a closed channel.

**Floor:** `verification_note` names the unbounded blocking op or non-terminating loop and states why no stop signal reaches it. Cannot name one → not a defect.

## Procedure

1. Read the goroutine body (and the function if `go f(...)`), one hop into helpers it blocks in.
2. List every blocking op and loop and find its bound: ctx/deadline passed in and honoured; a buffered channel with guaranteed capacity or a receiver that always drains; finite input (`range` over a slice, or a channel its owner closes — cite the `close`); `select` with a `ctx.Done()`/done case.
3. Loops (`for {}`, ticker, `for range ch`) need an exit reachable from the stop signal, and the signal must be closed/cancelled on shutdown (trace it to the setup code or `goroutine.runners`).
4. One-shot goroutines doing ctx-less or `context.Background()` IO with no client timeout are unbounded → flag (cite the `client.<name>.*` / `db.statement_timeout` / `dep.<module>` fact if a bound is relied on).

```go
// goroutine_no_stop — loop never exits; ticker never stopped
go func() {
    t := time.NewTicker(time.Minute)
    for range t.C { s.refresh(context.Background()) }
}()

// goroutine_no_stop — send blocks forever if the receiver returned early
ch := make(chan result)
go func() { ch <- s.fetch(ctx) }()
select { case r := <-ch: return r; case <-ctx.Done(): return ctx.Err() }  // fix: make(chan result, 1)

// NOT a defect
go func() {
    t := time.NewTicker(time.Minute); defer t.Stop()
    for { select { case <-ctx.Done(): return; case <-t.C: s.refresh(ctx) } }
}()
```
