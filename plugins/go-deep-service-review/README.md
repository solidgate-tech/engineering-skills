# go-deep-service-review

A multi-agent review of a Go service for a **closed set** of defects that are easy to miss in code review and expensive in production:

| Check | Looks for |
|---|---|
| `context` | context not propagated to IO or async calls, new root contexts mid-chain |
| `timeout` | IO with no deadline anywhere on the path, deadlines that never reach the call |
| `error_handling` | business decisions taken on untyped errors, unchecked partial failures of batch APIs (e.g. SQS `SendMessageBatch`) |
| `resources` | missing transaction rollback, unchecked `rows.Err()`, unclosed bodies/rows/readers |
| `concurrency` | goroutines that cannot be stopped |
| `app_lifecycle` | setup init order, close order, resources never closed |
| `sql` | writes that skip `updated_at` when the database does not set it; joins inside `UPDATE`/`DELETE`, listed as worth a look rather than as defects |

You pick the checks. The skill resolves shared facts about the service once (timeouts, error sentinels, close mechanism), fans the checks out to subagents, then reconciles their results. Every finding carries its evidence and how it was verified; each check also defines what is **not** a defect, to keep false positives down. The output is one report with a findings table.

## Usage

```
/go-deep-service-review
```

Run it from the service's repository root. Artifacts are written to `service-review/`: `facts.md`, `findings.yaml`, `report.md`.

## Requirements

- An agent harness with subagents (built for Claude Code; without subagents the units run one at a time)
- `golangci-lint` v2 on `PATH` (optional; seeds the `resources` check)

## Cost

Several subagents read the code in parallel. A full run on a mid-size service uses noticeably more tokens than a single-agent review, so pick only the checks you need.

## Severity

| Level | Meaning |
|---|---|
| Critical | Unbounded or uncancellable IO; outage or resource-exhaustion risk |
| High | Wrong behaviour that will hide or produce incidents |
| Medium | Degrades debuggability or correctness in edge cases |
| Low | Minor; fix opportunistically |

Findings reached from a request-path entry point are raised one level; findings reached only from batch jobs are lowered one level.

## Not covered

- Retry-policy correctness
- Setup that fails midway without closing already-created resources
- Diff or incremental review — every run reviews the code as it is

## Layout

```
skills/go-deep-service-review/
  SKILL.md                  orchestration: what to ask, what to spawn, how to reconcile and report
  references/findings.md    output contract every review agent follows
  references/*.md           check files: definition, not-a-defect, how to verify, fix
```

To tune a check, edit its file in `references/`. To add one, also add its row to the Checks table, the facts it needs to the facts table, and any required-note rule to the Validate step in `SKILL.md`.
