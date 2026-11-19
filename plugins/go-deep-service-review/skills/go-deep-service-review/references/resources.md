# `resources` — sweep

Facts used: `tx.helpers`, `resources.closer_helpers`.

Seeds:
- `Begin(` / `BeginTx(` / `BeginTxx(`
- `.Next()` loops
- `.Do(` / `http.Get` / `http.Post` / `GetObject(` / `os.Open` / `Acquire(` / `Prepare`
- the lines for your packages in the lint-seeds file, if your prompt names one. It only carries `bodyclose` and `rowserrcheck` hits, so it supplements the grep seeds and never replaces them.

## Types

**`tx_rollback_missing`** · High — A transaction is begun (`Begin`/`BeginTx`/`BeginTxx`) with no rollback guaranteed on every non-commit exit (early return, panic).
*Not a defect:* `defer` rollback right after the `Begin` error check; transaction run through an in-repo helper whose body defers rollback (cite `tx.helpers`).
*Verify:* read the begin site, every return path, and the helper body if one is used.
*Fix:* `defer` a rollback right after a successful `Begin`.

**`tx_rollback_err_unchecked`** · Low — A deferred rollback exists but its error is discarded (`defer tx.Rollback(ctx)`, `_ = tx.Rollback(ctx)`) or not filtered against the tx-closed sentinel (a rollback after commit returns it), so real rollback failures (broken connection) vanish, or every committed transaction logs noise.
*Not a defect:* the error is checked, `pgx.ErrTxClosed` / `sql.ErrTxDone` is ignored and any other error is logged or returned; the helper does so (cite `tx.helpers`).
*Verify:* read the deferred rollback and the helper body if one is used.
*Fix:* in the deferred rollback ignore only the tx-closed sentinel; log or return any other error.

**`rows_err_unchecked`** · High — A `rows.Next()` loop (pgx `Rows`, `*sql.Rows`, `*sqlx.Rows`) has no `rows.Err()` check after it on the success path; an iteration error ends the loop early and a truncated result is returned as success.
*Not a defect:* `rows.Err()` checked after the loop; pgx collector helpers (`pgx.CollectRows`, `CollectOneRow`, `ForEachRow`), which check internally; `sqlx` `Select`/`Get`.
*Verify:* read the loop and every exit after it.
*Fix:* check `rows.Err()` after the `Next()` loop.

**`resource_not_closed`** · High — An acquired closeable is not closed on every path: `*http.Response.Body` (also when unread or on non-2xx), pgx `Rows`/`*sql.Rows`/`*sqlx.Rows`, `io.ReadCloser` (S3 `GetObject` body, files, gzip/zip readers), prepared statements, pgx pool `Acquire` connections (`Release`).
*Not a defect:* closed via `defer` or on every path including errors; closed through a helper in `resources.closer_helpers`; ownership handed to a callee/struct that closes it (cite the closing line); rows fully iterated (`Next()` returns false → pgx and `database/sql` close them) **and** no `break`/`return` inside the loop; `resp` on an `err != nil` path.
*Verify:* read the acquisition, every return, and the closer.
*Fix:* `defer x.Close()` right after the error check on acquisition.

## Examples

```go
// tx_rollback_missing — early return leaves tx open, conn held, locks kept
tx, err := r.pool.Begin(ctx)
if err != nil { return err }
if _, err := tx.Exec(ctx, q); err != nil { return err }
return tx.Commit(ctx)

// tx_rollback_err_unchecked — rollback present, error discarded
defer tx.Rollback(ctx)

// NOT a defect
tx, err := r.pool.Begin(ctx)
if err != nil { return fmt.Errorf("begin: %w", err) }
defer func() {
    if rbErr := tx.Rollback(ctx); rbErr != nil && !errors.Is(rbErr, pgx.ErrTxClosed) {
        l.Error("rollback", zap.Error(rbErr))
    }
}()

// rows_err_unchecked — iteration error returns a truncated slice as success
rows, err := r.pool.Query(ctx, q)
if err != nil { return nil, err }
defer rows.Close()
for rows.Next() { ... }
return out, nil

// resource_not_closed
resp, err := c.http.Do(req)
if err != nil { return err }
if resp.StatusCode != http.StatusOK { return errStatus }   // body leaked
```
