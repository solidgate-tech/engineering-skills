---
name: mr-deliver
description: Deliver an opened GitLab MR to the default branch autonomously — watch pipelines & approval, auto-rebase, retry flaky jobs, merge (or enqueue on a merge train), monitor the default-branch pipeline. Optional per-repo e2e-impact gate. Trigger phrases "deliver MR", "merge this MR when ready", or whenever the user passes an MR URL/reference and asks to land it.
argument-hint: <mr-url-or-reference>
disable-model-invocation: false
---

# MR Deliver: $ARGUMENTS

Drive an opened MR to the default branch (`<trunk>`) autonomously. Stop only at ⏸️ STOP markers — this skill runs autonomously by design, overriding any global "ask before acting" rule.

## Configuration

- GitLab host: `$GITLAB_HOST`, else glab's configured host. CLI `glab`.
- `<trunk>`: the project's default branch (`glab repo view -R <repo> -F json | jq -r .default_branch`).
- Squash: on by default; per-repo `squash: false` in `repos.json` keeps the project's own merge setting.

Per-repo: local clone path in `~/.claude/mr-deliver/repos.json` (see State below).

**Polling**: `ScheduleWakeup` for waits ≥60 s, `Bash sleep` only when the next action is a few seconds away. Cadences: pipelines `60s`, approvals/threads `60s`.
`ScheduleWakeup` works only in `/loop` mode. Outside it, run one background `Bash` watch loop (`run_in_background: true`) that exits on the state you wait for, and act on its completion notice. Pipe `glab api` straight into `jq`: storing JSON in a variable and `echo`ing it breaks under zsh, whose `echo` turns `\n` inside strings into raw newlines and jq rejects the result.

**Auto-resume after push**: After ANY push to the MR branch (rebase or fix commit), immediately call `ScheduleWakeup 60s` with prompt `/mr-deliver <mr-url>` so the skill wakes up and re-enters Phase 2 without user intervention.

**Wake-up entry point**: If `state-<repo>-<mr>.json` already exists when the skill starts, skip Phase 1 validation (MR was already checked) and jump straight to Phase 2 watch loop.

**Flaky retries**: per-job, max 3, tracked in state file.

## State

Persistent files in `~/.claude/mr-deliver/` (create the directory on first run):

- `repos.json` — per-repo config. Schema:
  ```json
  {
    "<gitlab-group>/<repo>": {
      "local_path": "/absolute/path/to/local/clone",
      "squash": true,
      "e2e_impact": false
    }
  }
  ```
  - `squash` (default `true`) — `false` leaves squash off: Phase 1 doesn't turn it on, and Phase 3 merges without `--squash` / `squash=true`.
  - `e2e_impact` (default `false`) — `true` runs the repo's own `e2e-impact` skill (a project skill that predicts which e2e tests the diff breaks) before merging (Phase 2.5).

  Example:
  ```json
  {
    "acme/billing-api": {
      "local_path": "/Users/<you>/code/billing-api"
    },
    "acme/web-app": {
      "local_path": "/Users/<you>/code/web-app",
      "e2e_impact": true
    }
  }
  ```
- `state-<repo>-<mr>.json` — current run state: `{ source_branch, merge_train, retries: { "<job-id>": N } }`. Delete on Phase 5 completion.

Missing repo entry on first run → ⏸️ STOP, ask user for `local_path` and whether the repo has an `e2e-impact` skill, write entry.

## Inputs

`$ARGUMENTS`:

- Full MR URL → parse repo + number
- `repo!number` (e.g. `billing-api!1234`)
- Empty → resolve via `glab mr view` on current branch

Use `--repo <group/repo>` (`-R`) on every `glab` call.

---

## Phase 1 — Resolve MR

```bash
glab mr view <mr-number> -R <repo> --output json
```

Show: title, source→target, reviewers, squash flag, pipeline status, approvals, unresolved threads.

**Validate MR state before proceeding:**

- `state` must be `opened` — if `merged`/`closed`/`locked` → ⏸️ STOP, report state to user.
- `work_in_progress` / `draft` must be `false` — if draft → ⏸️ STOP, ask user to mark ready.

If squash is off and the repo's `squash` isn't `false`: `glab mr update <mr-number> -R <repo> --squash-before-merge`. If that fails → ⏸️ STOP.

Read the project's merge settings:

```bash
glab api "projects/<url-encoded-repo>" | jq '{merge_method, merge_trains_enabled, merge_trains_skip_train_allowed}'
```

`merge_trains_enabled == true` → `merge_train: true` in state. This switches 2.1, 2.2 and Phase 3 to their merge-train paths. A direct `glab mr merge` on such a project fails with `422 Branch cannot be merged` unless skipping the train is allowed.

Load/create `repos.json` entry. Initialize `state-*.json`.

---

## Phase 2 — Watch loop

Exit when **all**: pipeline=success, approved (≥1 non-author), threads resolved, mergeable. Run 2.1→2.4 each iteration; `ScheduleWakeup` 60s between iterations.

### 2.1 — Rebase if needed

```bash
glab mr view <mr-number> -R <repo> --output json | jq '{diverged: .diverged_commits_count, conflicts: .has_conflicts}'
```

**Merge train** (`merge_train: true`): being behind blocks nothing — the train tests the MR on top of the latest target and fast-forwards it. Do not rebase: it only restarts CI. Rebase only on `has_conflicts == true`.

Otherwise, if behind `<trunk>` or conflicts:

```bash
cd <local_path> && git fetch origin && git checkout <source-branch> && git rebase origin/<trunk>
```

**Conflict autonomous resolution** when intent is clear:

- Independent regions on both sides → keep both
- Pure formatting on one side → take the other
- Generated code (`*.pb.go`, `bsr/*`, lockfiles) → take incoming, then re-run generator (`buf generate`, `go mod tidy`, etc.)

Ambiguous (overlapping logic, schema collisions, same business rule) → `git rebase --abort` and ⏸️ STOP with conflicting hunks.

After rebase: `git push --force-with-lease origin <source-branch>`. Never plain `--force`. If rejected → ⏸️ STOP.

**After force-push: wait for the new pipeline** before 2.2 (avoid stale-success read). Record push timestamp, poll with `Bash sleep 30`:

```bash
glab pipeline list -R <repo> --ref <source-branch> --per-page 1 --output json | jq '.[0] | {id, sha, created_at}'
```

Proceed when `created_at` newer than push or `sha` matches new HEAD.

### 2.2 — Pipeline

Read the MR's own pipeline, not the branch's:

```bash
glab api "projects/<url-encoded-repo>/merge_requests/<mr-number>" | jq '.head_pipeline | {id, ref, sha, status, web_url}'
```

With merged-results pipelines (`ref` = `refs/merge-requests/<mr>/merge`) the pipeline `sha` is the merge ref, not the branch HEAD, and `glab ci status -b <source-branch>` shows a different (or no) pipeline. Fetch jobs with `glab api "projects/<enc>/pipelines/<id>/jobs?per_page=100"`.

- `running`/`pending` → schedule next check (60s).
- `success` → mark ok.
- `manual` → if all required jobs green and only optional manual remains, treat as success. Otherwise ⏸️ STOP.
- `failed`/`canceled` → triage below.

**Flaky triage.** Fetch trace: `glab ci trace <job-id> -R <repo>`.

| Verdict   | Trace signals                                                                                                                                                                                                                                                                                                                                  |
| --------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Flaky** | `connection refused/reset`, `i/o timeout`, `dial tcp`, `EAI_AGAIN`, `runner system failure`, `Job failed (system failure)`, `manifest unknown`, `429 Too Many Requests`, testcontainers startup timeout, port-already-in-use, kafka rebalance timeout in IT, infra-level `context deadline exceeded`, timeout-killed without assertion failure |
| **Real**  | `FAIL:`, `expected … got …`, `AssertionError`, compile/lint error, clear app-level error                                                                                                                                                                                                                                                       |

If flaky AND retries[<job-id>] < 3:

```bash
glab ci retry <job-id> -R <repo>
```

Increment counter in state file. Inform: `🔁 Retrying flaky <name> (N/3): <reason>`. Continue loop.

Otherwise (real failure or budget exhausted) → ⏸️ STOP with job name, last ~30 lines of trace, classification reason.

### 2.3 — Approval

> ⚠️ Do **not** rely on `glab mr view` for approvals — its `approved_by` / `approvals_left` fields are often stale or null even when the MR is approved. Always use the approvals endpoint:

```bash
glab api "projects/<url-encoded-repo>/merge_requests/<mr-number>/approvals" | jq '{approved, left: .approvals_left, by: [.approved_by[].user.username]}'
```

URL-encode the repo path (`/` → `%2F`), e.g. `acme%2Fweb-app`.

Approved when `approved == true` AND `approvals_left == 0`. Otherwise keep waiting (60s). Do not ping reviewer.

### 2.4 — Unresolved threads

```bash
glab mr view <mr-number> -R <repo> --output json | jq '{notes: .user_notes_count, blocking: .blocking_discussions_resolved}'
```

If `blocking == false`: list unresolved threads (author + first line) **once**; re-list only if set changes. Poll 60s.

### 2.5 — e2e impact (only if `e2e_impact: true`)

Once 2.2–2.4 pass, run the repo's `e2e-impact` skill on the MR (once per HEAD sha; record `e2e_impact_sha` in state).

- No affected tests → continue.
- Predicted breaks → ⏸️ STOP with the affected tests and suggested fixes. A sandbox deploy to run the e2e suite is the user's call; don't start one.

---

## Phase 3 — Merge

```bash
glab mr merge <mr-number> -R <repo> --squash --remove-source-branch --yes
```

Failure → ⏸️ STOP with exact error. Otherwise re-fetch MR to confirm merged.

**Merge train** (`merge_train: true`): enqueue instead of merging.

```bash
glab api -X POST "projects/<enc>/merge_trains/merge_requests/<mr-number>" -F auto_merge=true -F squash=true
```

`auto_merge=true` joins the train once the current MR pipeline passes. Confirm with `merge_when_pipeline_succeeds == true` on the MR. Then poll the car until it merges:

```bash
glab api "projects/<enc>/merge_trains/merge_requests/<mr-number>" | jq '{status, pipeline: .pipeline.status}'
```

- `status` `merged` → Phase 4.
- Train pipeline failed, or the MR drops off the train (`merge_when_pipeline_succeeds` back to `false` while `state` is `opened`) → triage the train pipeline as in 2.2. Flaky → re-enqueue (counts against that job's retry budget). Real → ⏸️ STOP.

---

## Phase 4 — Default-branch pipeline

```bash
glab pipeline list -R <repo> --ref <trunk> --per-page 1
glab ci status -R <repo> -b <trunk>
```

Use the pipeline for the merge commit (`squash_commit_sha` / `merge_commit_sha` from the MR). Wait for its deploy jobs to succeed. If that pipeline has no deploy job for the change (docs-only, nothing affected) → go to Phase 5: nothing to deploy. Apply Phase 2.2 flaky triage (retry up to 3/job). **Real failure on `<trunk>` → ⏸️ STOP immediately** (code already merged). `ScheduleWakeup` for waits.

---

## Phase 5 — Report

> Enter only after Phase 4 is fully green, or Phase 4 found nothing to deploy. Always runs: it ends every delivery.

Send concise summary to user: MR delivered, merge SHA, `<trunk>` pipeline link. Delete `state-<repo>-<mr>.json`.

---

## Hard rules

- Stop only at ⏸️ STOP.
- Never `--force` (use `--force-with-lease`), `--no-verify`, or skip signing.
- Never resolve threads or reply to review comments from this skill.
- Never `git add -A` / `git add .` — stage selectively during conflict resolution.
