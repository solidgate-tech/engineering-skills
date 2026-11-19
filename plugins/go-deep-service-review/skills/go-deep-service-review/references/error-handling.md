# `error_handling` — sweep

Facts used: `io_ifaces.<pkg>`, `errors.sentinels.<pkg>`, `batch.sites`.

Seeds: call sites of `io_ifaces.*` methods → read the `err != nil` branch. `batch.sites` → the batch section.

## Types

**`err_relabel_untyped`** · Medium — A generic `err != nil` is re-wrapped with text that names an error class, without `errors.Is/As`. Misleads operators; no behaviour change.
*Fix:* check `errors.Is/As` against the callee's sentinel before naming the cause.

**`err_decision_untyped`** · High — A business decision is taken inside a generic `err != nil` branch, conflating two or more error classes.
*Fix:* branch on `errors.Is/As`; return the untyped error unchanged.

*Verify (both):* the procedure below; its steps 1–4 are the not-a-defect clauses.

**`batch_partial_failure_unchecked`** · High — see the batch section.

## Procedure for `err_*` (per call site)

In scope: errors returned by `io_ifaces.*` methods (repository/client interfaces), wherever the call site is. Out of scope: errors from parsing/validation (`json.Unmarshal`, `strconv`, validators) — one class, any error = bad input; fail-fast branches in setup code and `main`.

1. Identify the callee package → look up `errors.sentinels.<pkg>`. If `single_class: true` → **stop, not a defect**.
2. Read the `err != nil` branch (and any `if err == nil { … } else` inversion). Classify it:
    - **neutral** — `return err` / `return fmt.Errorf("<verb>: %w", err)` with a neutral verb / log or count it and return the error / `return nil, err` in a loop that aborts the loop / map to a generic failure (HTTP 500, `codes.Internal`). → **not a defect**.
    - **relabel** — the wrap text names an error class: `not found|no rows|missing|already exists|duplicate|conflict|invalid|expired|forbidden|unauthorized|timeout|unavailable`. → candidate `err_relabel_untyped`.
    - **decision** — the branch does any of (closed list):
      a. calls a different dependency or method as fallback (`Create` after failed `Get`, secondary cache, default provider);
      b. returns success (`return x, nil`, `return nil`) — swallow;
      c. `continue` in a per-item loop — skip-and-proceed;
      d. maps to a specific business error / status code (`connect.CodeNotFound`, gRPC `codes.NotFound`, HTTP 404/409, `ErrUserMissing`) — changes what the caller sees, not just text;
      e. mutates state — sets a flag, writes cache, publishes an event, enqueues a retry to a different queue;
      f. retries the same call more than once *without* a retry policy object (ad-hoc loop). Retry through a policy/library is out of scope.
      → candidate `err_decision_untyped`.
3. **Guard check.** Decision/relabel inside `if errors.Is(err, X)` / `errors.As(err, &t)` / a typed `switch` → **not a defect**. An exhaustive `Is` chain whose final `else` does a neutral return → not a defect. A final `else` that itself takes a decision → still a candidate (it conflates everything not matched).
4. **Conflation floor.** Name **two** concrete error classes that reach this branch and that a correct implementation would handle differently. One comes from `errors.sentinels.<pkg>` (or a driver error the package leaks, e.g. `pgx.ErrNoRows`); the other is an infrastructure class (ctx cancel/deadline, connection error, driver internal). Cannot name two → **not a defect**.
5. **One hop.** If the callee collapses *every* driver error into one sentinel (e.g. always `return ErrRepo` — such a package is not `single_class`), the conflation is in the callee: `defect_site` = the callee's mapping line, `fix_hint` = "distinguish `pgx.ErrNoRows` in `<pkg>`". Do not flag the caller.
6. Emit. `verification_note`: `"<callee>.<method> exposes <sentinel|driver err> vs <infra class>; branch <decision letter> on either"`.

A swallow or skip (b, c) on a write path: say so in `description`; severity stays High.

```go
// err_relabel_untyped — any error becomes "not found"
user, err := r.repo.Get(ctx, userID)
if err != nil {
    return User{}, fmt.Errorf("user not found: %w", err)
}

// err_decision_untyped (a) — creates on timeout, on conn error, on anything
user, err := r.repo.Get(ctx, userID)
if err != nil {
    user, err = r.repo.Create(ctx, newUser)
}

// err_decision_untyped (d) — every failure reported as NotFound to the client
if err != nil {
    return nil, connect.NewError(connect.CodeNotFound, err)
}

// NOT a defect — guarded
user, err := r.repo.Get(ctx, userID)
if errors.Is(err, repo.ErrNotFound) {
    user, err = r.repo.Create(ctx, newUser)
} else if err != nil {
    return User{}, fmt.Errorf("get user: %w", err)
}

// NOT a defect — neutral wrap
if err != nil {
    return User{}, fmt.Errorf("get user %s: %w", userID, err)
}

// NOT a defect — single_class callee (pure HTTP client, returns only transport errors)
if err := c.metrics.Push(ctx, batch); err != nil {
    log.Warn(...); return nil   // swallow, but nothing to distinguish
}
```

## Batch partial failure — `batch_partial_failure_unchecked`

A batch API reports per-entry failures in its response, separately from the top-level error, and the call site handles the top-level `err` only. Top-level `err == nil` does **not** mean every entry succeeded. The sites and the field that carries the failures are in `batch.sites`. Applies to in-repo wrappers too — follow a wrapper one hop up to where the per-entry result is (or is not) consumed.

Example: SQS `SendMessageBatch` / `DeleteMessageBatch` / `ChangeMessageVisibilityBatch` return failed entries only in `out.Failed` (`Id`, `Code`, `SenderFault`). The same shape: SNS `PublishBatch` (`Failed`), DynamoDB `BatchWriteItem` (`UnprocessedItems`), Kinesis `PutRecords` (`FailedRecordCount`), a search engine's bulk endpoint (`errors: true`).

*Not a defect (any one):* failed entries retried with a bound and final failures surfaced; an error returned that names the failed entries; log/metric only on a method the caller provably treats as best-effort (cite the caller).
*Verify:* read the batch call site, every use of the output, and the caller's handling of the return.
*Fix:* inspect the per-entry result; retry failed entries (bounded) or return an error naming them.

`description` names the consequence: lost writes or messages for a send/put; duplicate processing for a failed delete/ack, because the entry is redelivered.

```go
// batch_partial_failure_unchecked — partial failures silently dropped
out, err := c.sqs.SendMessageBatch(ctx, in)
if err != nil {
    return fmt.Errorf("send batch: %w", err)
}
return nil

// NOT a defect — surfaced
out, err := c.sqs.SendMessageBatch(ctx, in)
if err != nil {
    return fmt.Errorf("send batch: %w", err)
}
if len(out.Failed) > 0 {
    return fmt.Errorf("send batch: %d of %d failed: %s", len(out.Failed), len(in.Entries), failedIDs(out.Failed))
}
```
