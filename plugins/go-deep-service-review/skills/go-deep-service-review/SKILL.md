---
name: go-deep-service-review
description: Use when the user asks for a deep, multi-agent review of a whole Go service for production defects — lost context propagation, IO without timeouts, decisions on untyped errors, unchecked batch partial failures, leaked transactions/rows/bodies, goroutines that cannot stop, app init/close order, SQL write pitfalls — or names go-deep-service-review. Token-heavy; not for reviewing a diff or a PR.
---

# Go deep service review

Review a Go service for a closed set of defects that are easy to miss in code review and expensive in production. You orchestrate: scope the run with the user, resolve shared facts once, fan the checks out to subagents, and reconcile their YAML into one report.

`REFS` is the absolute path of the `references/` directory next to this file. Read `REFS/findings.md` now — it is the output contract you reconcile against. The check files are for the subagents, who read them by path: do not paste them into prompts, and read one yourself only if you have to run its units without a subagent tool.

Run from the service's repository root. Everything is written to `service-review/` there: `facts.md`, `findings.yaml`, `report.md`, and the lint-seed files if produced. Do not commit them unless asked.

## Checks

|family|pass|check file|types|
|---|---|---|---|
|`context`|chain trace|`context-timeout.md`|`ctx_not_propagated`, `ctx_new_non_derived`, `async_helper_incomplete`|
|`timeout`|chain trace|`context-timeout.md`|`io_unbounded`, `deadline_not_reaching_payload`, `timeout_inversion`, `shutdown_grace_mismatch`|
|`error_handling`|sweep|`error-handling.md`|`err_relabel_untyped`, `err_decision_untyped`, `batch_partial_failure_unchecked`|
|`resources`|sweep|`resources.md`|`tx_rollback_missing`, `tx_rollback_err_unchecked`, `rows_err_unchecked`, `resource_not_closed`|
|`concurrency`|sweep|`concurrency.md`|`goroutine_no_stop`|
|`sql`|sweep|`sql.md`|`sql_updated_at_missing`, `sql_from_in_modify` (review note)|
|`app_lifecycle`|setup review|`app-lifecycle.md`|`app_resource_not_closed`, `app_close_order`, `app_init_order`|

## 1. Ask what to run

Show the Checks table and ask which families to run. There is no default: nothing else happens until the user picks. Say what each pass costs — a chain trace is one agent per entry point (`context` and `timeout` share it), a sweep is one agent per package batch, the setup review is one agent. The user may narrow the sweeps to sub-paths; chain traces follow the chain wherever it goes.

## 2. Resolve facts

Write `service-review/facts.md` with the keys the selected families need, one entry per key: `key: value — source file:line — certainty high|medium|unresolved`. Resolve them from code and config, not from names — findings cite these keys. On a large service delegate this to one agent: give it the rows it must resolve and the entry format.

|key|needed by|content|
|---|---|---|
|`layout`|always|module path; where handlers, business logic, IO clients/repositories and setup/wiring live; generated-code and mock paths; migrations/schema directory|
|`ctx_types`|context, timeout|context-carrying types — grep `context.Context` in struct bodies, **read each** to confirm embedding|
|`db.statement_timeout`|timeout, concurrency|from code or DSN/env, and deployment config if it is in the repo; source + effective value|
|`client.<name>.*`|timeout, concurrency|per-client timeouts including **zero-value library defaults**; note code-default vs env mismatch|
|`server.<name>.request_deadline`|timeout|whether a deadline is put on the request ctx (`http.TimeoutHandler`, timeout middleware/interceptor) and its value. `http.Server` Read/Write timeouts do not count|
|`shutdown.grace`|timeout|how long the process waits for in-flight work on shutdown (server `Shutdown` timeout, consumer drain timeout)|
|`dep.<module>`|context, timeout, concurrency, app_lifecycle|each IO client library: **pinned** `go.mod` version, source location (`vendor/` or module cache), whether its calls are bounded by default|
|`io_ifaces.<pkg>`|error_handling|repository/client interfaces the business logic depends on — the only callees whose errors are in scope|
|`errors.sentinels.<pkg>`|error_handling|per `io_ifaces` package: exported `Err*` vars / typed errors; which driver errors are mapped (`pgx.ErrNoRows`, `sql.ErrNoRows`, `redis.Nil`, pg `23505`, gRPC codes); `single_class: true` only if the underlying errors are provably one class (e.g. a pure network client with no status mapping)|
|`batch.sites`|error_handling|call sites of batch APIs that report per-entry failures in the response, and in-repo wrappers around them; per API the field that carries the failures. E.g. SQS `SendMessageBatch`/`DeleteMessageBatch`/`ChangeMessageVisibilityBatch` (`Failed`, including v1 `WithContext` variants), SNS `PublishBatch`, DynamoDB `BatchWriteItem`, Kinesis `PutRecords`, bulk indexing|
|`tx.helpers`|resources|in-repo transaction helpers (`WithTx`, `RunInTx`, …): does the body defer rollback, filter the tx-closed sentinel, handle panic|
|`resources.closer_helpers`|resources|in-repo helpers that close bodies/rows/readers|
|`sql.exec_sites`|sql|how SQL reaches the driver: driver methods in use (`ExecContext`, `QueryxContext`, `NamedExecContext`, pgx `Exec`/`Query`, …), query builders, embedded `.sql` files|
|`sql.tables_with_updated_at`|sql|from the migrations/schema; per table note any database mechanism that sets the column and for which statements: trigger, `ON UPDATE CURRENT_TIMESTAMP`, column default (`INSERT` only)|
|`app.setup_roots`|app_lifecycle|setup entry files/functions (`main`, wiring, `Run`/`New`/`init*`); lifecycle framework in use, if any|
|`app.close_mechanism`|app_lifecycle|how closes execute and in what order: `defer` chain (LIFO); close-func slice (read the loop — forward = FIFO, reverse = LIFO); framework hooks or a custom helper (read the source). Also when closes run relative to runners stopping|
|`goroutine.runners`|concurrency, app_lifecycle|supervisors and worker pools (errgroup, framework runners, consumers): how each is stopped on shutdown|

## 3. Pick entry points (`context` / `timeout` only)

List the service's entry points — HTTP/RPC handlers, queue consumers, scheduled jobs — as `name | file:line | kind | criticality | methods in this chain | description`. Name the exact method set when one struct backs many endpoints; check generated code before assuming a large surface.

`criticality`: `hot` — a caller or a live message flow waits on it; `batch` — cron, backfill, bulk processing; `unknown` otherwise.

Show the table and ask which entry points to trace.

## 4. Run the passes

Spawn the units in parallel. Each prompt is exactly this:

```
You are one unit of a Go service review of <repo root>.
Read first: REFS/findings.md, REFS/<check file> [one per selected family in this pass], <repo root>/service-review/facts.md
Families: <selected families for this pass>
Unit: <see below>
Return only the YAML defined in findings.md.
```

|pass|units|`Unit:` line|
|---|---|---|
|chain trace|one agent per selected entry point, at most 4 at a time|entry point name, `file:line`, method set|
|sweep|one agent per batch of packages (about 50 non-test Go files). Every package in scope — the whole module by default, `cmd/` and setup code included — is swept exactly once, for all selected sweep families|the package directories; path to `lint-seeds.txt` if produced|
|setup review|one agent|`app.setup_roots`|

Sweeps confirm grep seeds by reading, so a cheaper model is enough for them (`model: sonnet` in Claude Code). Chain traces and the setup review use the session model.

**Lint seeds.** If `resources` is selected and `golangci-lint` v2 is on `PATH`, write the config below and run it once before the sweeps (add `--modules-download-mode=vendor` if `vendor/` exists). Exit code 1 only means it reported issues. If the output is typecheck errors instead of linter hits, skip lint seeds and say so in the report header.

```bash
golangci-lint run -c service-review/golangci.seed.yml --path-mode=abs ./... > service-review/lint-seeds.txt
```

```yaml
# service-review/golangci.seed.yml
version: "2"
run: {tests: false}
linters:
  default: none
  enable: [bodyclose, rowserrcheck]
  settings:
    rowserrcheck:
      packages: [github.com/jackc/pgx/v5, github.com/jmoiron/sqlx]  # pgx is NOT checked without this
issues: {max-issues-per-linter: 0, max-same-issues: 0}              # defaults truncate output
```

Without a subagent tool, work through the same units yourself, one at a time.

## 5. Reconcile

You do this yourself, in this order. Nothing disappears silently: every removed finding goes to `dropped:` with a reason.

1. **Validate.** Drop as `invalid` a finding whose type is outside the selected families, whose `evidence` or `verification_note` is missing, or whose note misses what its type requires: `err_decision_untyped` names two conflated error classes; `goroutine_no_stop` names the unbounded blocking op or loop; `app_close_order` names the dependency edge and the effective close order.
2. **Dedup** on `(type, defect_site)`, except `io_unbounded` on `(type, leaf_site)` — a shared unbounded leaf reached by many chains is one fix; two handlers dropping ctx before the same repository method are two fixes. Keep the entry with the highest confidence, union `chains` and `evidence`, drop the rest as `duplicate`.
3. **Cross-check `io_unbounded`.** If a `verified_correct` entry names the same `leaf_site`, read the evidence line it cites. If it shows a bound that holds for every caller, drop the finding as `contradicted`.
4. **Adjust severity** on the scale Low < Medium < High < Critical, by the criticality of the entry points in `chains`: any is `hot` → one step up (`severity_modifier: hot_path`); all are `batch` → one step down (`batch_path`); otherwise unchanged. Findings with no chains, and `sql_from_in_modify`, are never adjusted.
5. **Group** findings that share one root cause (same helper, same missing pattern across a package): give them a `group_id` and a `root_cause`; group severity = highest member.
6. **Owner.** If the repository has a CODEOWNERS file, set `owner_hint` from it.
7. Write `service-review/findings.yaml` with `findings:`, `dropped:`, `coverage_gaps:` (unit + gap, from the agents' `coverage`) and `out_of_scope:`. Then write `service-review/report.md` from it.

## 6. Report

No prose beyond the header line and table cells; cells ≤ ~120 chars, truncated with `…`. Sort by severity, then file. Omit empty sections.

- **Findings** — ungrouped findings. `Sev` shows the modifier when one applied. `What` = `description`, `Verified` = `verification_note`.
- **Groups** — one row per group; members: first 3, then `+N`.
- **Worth a look** — `sql_from_in_modify` entries. They are review notes: never in Findings, Groups or Counts.
- **Counts** — every reported finding including group members, after adjustment.

```
# Service review — <repo> @ <short-sha> — <date>
Checks: timeout, error_handling, resources, sql · Entry points traced: 5 · Packages swept: 12 · Sampled units: 1 · Dropped: 2 (1 invalid, 1 contradicted) · Lint seeds: yes

## Findings
| # | Sev | Type | Defect site | What | Verified | Fix | Conf | Chains | Owner |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Critical | io_unbounded | internal/x/svc.go:40 | UPDATE runs with no deadline | svc→repo→pgx.Exec, no WithTimeout; db.statement_timeout unset | add deadline at service | high | cancel-order, renew | @team-a |
| 2 | High | err_decision_untyped | internal/y/svc.go:88 | creates a user on any Get error | repo.Get exposes ErrNotFound vs ctx/conn errors; branch (a) on either | errors.Is(err, ErrNotFound) | high | — | @team-b |

## Groups
| G | Sev | Root cause | Members | Owner |
|---|---|---|---|---|
| G1 | High | Next() loops without rows.Err() across internal/store | internal/store/a.go:12, internal/store/b.go:30, internal/store/c.go:9, +3 | @team-a |

## Worth a look
| # | Site | What to check |
|---|---|---|
| 1 | internal/store/sessions.go:51 | UPDATE … FROM users: confirm one users row per session |

## Counts
| Type | Critical | High | Medium | Low |
|---|---|---|---|---|

## Coverage gaps
| Unit | Gap |
|---|---|
| chain renew | 3 of 11 Notifier impls traced (homogeneous, sampled) |

## Noticed outside the selected checks (unverified)
- internal/x/cache.go:18 — mutex held across an HTTP call
```

After writing the report, give the user the header line, the top findings, and the path to `report.md`.
