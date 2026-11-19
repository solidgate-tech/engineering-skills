# Output contract

Return **YAML only** as your final message: `findings:` and `coverage:`, plus `verified_correct:` (chain traces) and `out_of_scope:` when you have entries. No narrative.

## Rules

1. **Closed set.** Emit only types defined in the check file(s) you were given, and only for the families named in your prompt. Anything else you notice goes into `out_of_scope` as a one-liner.
2. **Every finding is verified.** Follow the type's *Verify* step. `evidence` and `verification_note` are required; a finding without them is discarded.
3. **Not-a-defect clauses win.** If one applies, do not emit the finding.
4. **Seeds are not findings.** A grep or linter hit is a place to read. A linter miss is not evidence of correctness.
5. **Read one hop up before flagging in a sweep.** The type check, close, rollback or stop signal is often in the immediate caller.
6. **Use `facts.md`.** Cite every fact you rely on in `depends_on_fact`. A fact marked `unresolved` caps the finding at `confidence: low`.
7. **Exclusions.** Skip `*_test.go`, generated code and mocks (paths in fact `layout`). `vendor/` is excluded from sweeps only — a chain trace must descend into it.

**IO call** means any RPC/HTTP client call, database driver call, queue or stream operation (Kafka, RabbitMQ, SQS), object store or cache call.

## Finding

```yaml
findings:
  - type: io_unbounded                # from your check file
    defect_site: internal/x/svc.go:40 # where the fix lands
    leaf_site: internal/x/repo.go:72  # the IO driver call — chain traces only, otherwise null
    severity: Critical                # the type's base severity from the check file, unchanged
    confidence: high
    chains: [cancel-order, renew]     # entry points that reach it — chain traces only, otherwise []
    depends_on_fact: [db.statement_timeout]
    evidence: [internal/x/svc.go:40, internal/x/repo.go:72, vendor/github.com/jackc/pgx/v5/conn.go:611]
    verification_note: traced cancel→svc.Cancel→repo.Update→pgx.Exec; no WithTimeout on path; db.statement_timeout unset
    description: <=1 sentence, what is wrong
    fix_hint: <the type's fix, refined if useful>
```

`verification_note` is one sentence: what was read and what settled it.

## Confidence

|value|meaning|
|---|---|
|`high`|Read end to end; proven from code or `facts.md`|
|`medium`|Conditional (e.g. only on a cold cache), rests on a medium-certainty fact, or established on a sample|
|`low`|A required fact is unresolved|

## Verified-correct (chain traces only)

A leaf you proved bounded **for every caller**: the deadline is set at the leaf itself, or a fact bounds it (statement timeout, client timeout). A deadline inherited from this chain's handler does not qualify. The orchestrator uses these to drop an `io_unbounded` another chain raised on the same leaf.

```yaml
verified_correct:
  - leaf_site: internal/queue/producer.go:72
    claim: bounded via context.WithTimeout at the leaf
    evidence: internal/queue/producer.go:70
    chain: create-order
```

## Coverage and out-of-scope

```yaml
coverage:
  sampled: true                    # true if you traced or read a sample instead of everything
  gaps: ["3 of 11 Notifier impls traced (homogeneous, sampled)"]
out_of_scope:
  - internal/x/cache.go:18 — mutex held across an HTTP call
```
