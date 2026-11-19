---
name: mr-unblock
argument-hint: "[mr-url-or-iid] [--analyze-only] (optional; defaults to current branch)"
description: Collect all blockers preventing one of the user's MRs from merging (unresolved discussions, failed pipeline jobs, conflicts, stale rebase, missing reviewers, silent reviewers, draft status). Find the root cause of each, run the safe fixes by itself, ask once for everything else, then apply code fixes in place or in a worktree and push safely. Use when the user asks "unblock my MR", "fix my MR blockers", "what's stopping my MR", "resolve MR issues", "mr-unblock", or similar, for a single MR. For several MRs at once use mr-inbox, which runs this skill's flow in parallel.
---

# MR Unblock

The single-MR engine of mr-toolkit: **analyze → auto actions → one decision → execute →
re-check**. `mr-inbox` runs this same flow across many MRs. It uses the sections marked
_(contract)_ directly, so keep them self-contained and change them here only.

`PLUGIN_SKILLS="${CLAUDE_PLUGIN_ROOT}/skills"`. If `CLAUDE_PLUGIN_ROOT` is unset (the skill
was run from a checkout), use the parent directory of this SKILL.md's folder instead. Pass it
as an absolute path to subagents.

## Inputs (`$ARGUMENTS`)

- Full MR URL → parse repo + iid
- `!<iid>` or bare number → repo = the current repo's `origin`:
  `git remote get-url origin | sed -E 's#^[a-z+]+://[^/]+/##; s#^[^@]*@[^:/]+:##; s#\.git$##'`
- Empty → the open MR of the current branch
  (`glab mr list --source-branch "$(git branch --show-current)" --output json`)
- `--analyze-only` → stop after the plan is shown. Make no writes of any kind.

## Phase 1 — Analyze _(contract: `references/analyze.md`)_

Spawn **one** subagent with `references/analyze.md` and the inputs it lists: `REPO`, `IID`,
`WEB_URL`, `PLUGIN_SKILLS`, and a report path in the session scratchpad (or
`~/.cache/mr-toolkit/runs/<ts>/`). A subagent keeps the CI traces and thread dumps out of
this context. The analysis is read-only and returns a JSON report with `actions[]`.

Merged or closed → report the state and stop.

## Flaky vs real _(contract)_

How to classify a failed job trace:

| Verdict   | Trace signals                                                                                                                                                                                                                                           |
| --------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Flaky** | `connection refused`, `i/o timeout`, `dial tcp`, `EAI_AGAIN`, `runner system failure`, `Job failed (system failure)`, `manifest unknown`, `429 Too Many Requests`, testcontainers timeout, port-already-in-use, infra-level `context deadline exceeded` |
| **Real**  | `FAIL:`, `expected … got …`, `AssertionError`, compile error, lint error, clear app-level error                                                                                                                                                         |

A job that fails the same way on the target branch is not caused by the MR. Don't file it
under `fix_code`.

## Phase 2 — Auto actions _(contract)_

Skip this phase with `--analyze-only`. Run the report's `auto: true` actions without asking,
except those marked `held: true`:

| type               | command                                                                                                                                                 |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `rebase_api`       | `glab mr rebase <iid> -R <repo>`                                                                                                                        |
| `trigger_pipeline` | `glab api --method POST "projects/<enc-repo>/merge_requests/<iid>/pipelines"`                                                                           |
| `retry_job`        | `glab ci retry <job-id> -R <repo>`                                                                                                                      |
| `reroll_reviewers` | `glab mr update <iid> -R <repo> --draft`, then `glab mr update <iid> -R <repo> --ready`. The draft→ready toggle re-triggers review roulette             |
| nudge              | report has `nudge: true` → invoke `/mr-nudge <web_url>`. A caller handling many MRs passes them all to one invocation: mr-nudge groups DMs per reviewer |

`held: true` marks an auto rebase or retry on an MR that also has a proposed fix. If the fix is
approved, it rebases in its checkout (no race with the push) and the push restarts CI anyway.
If the fix is skipped, run the held actions after the decision.

Print one line per action run.

## Phase 3 — Decide _(contract: the option sets)_

Show every non-auto action in **one** `AskUserQuestion` call (up to 4 questions; a report
has already merged its `fix_code` items into one). Each question carries the concrete plan:
root cause, files, and drafted reply text, so the user can decide without opening GitLab.

| action                      | options                                                                                                 |
| --------------------------- | ------------------------------------------------------------------------------------------------------- |
| `fix_code` / `rebase_local` | **Fix & push (Recommended)** · Fix, hold push (I'll look at the diff) · Skip                            |
| `reply` / `resolve`         | **Post as drafted (Recommended)** · Skip                                                                |
| `rebase_api`, `auto: false` | Rebase (stacked child needs a restack after) · **Skip (Recommended)**                                   |
| `mark_ready`                | Mark ready · **Keep draft (Recommended)**                                                               |
| `assign_reviewer`           | one option per candidate (first = Recommended) · Skip (with `remove`: Keep <who>). "Other" = a username |

"Other" = the user edits the plan or reply. Apply their text literally.
With `--analyze-only`, print the plan as text instead and stop.

## Phase 4 — Execute _(contract: `references/execute.md` + posting rules)_

1. **Code** (`fix_code`, `rebase_local`):
   ```bash
   bash "$PLUGIN_SKILLS/mr-unblock/scripts/worktree.sh" <repo> <source_branch> <iid>
   ```
   This returns the user's own checkout when it already sits clean on that branch at
   origin's head (`in_place: true`, no reinstall). Otherwise it creates a detached worktree,
   cloning the repo if needed. Hand the JSON, the approved plan and `push`/`hold` to a
   subagent running `references/execute.md`.
2. **`rebase_api`** (`auto: false`, approved): `glab mr rebase <iid> -R <repo>` only when the MR
   has no approved code action; otherwise the code fix rebases in its checkout. Either way, tell
   the user the stacked child needs a restack.
   **`mark_ready`**: `glab mr update <iid> -R <repo> --ready`.
   **`assign_reviewer`**: `glab mr update <iid> -R <repo> --reviewer +<username>`. With
   `remove` (it replaces an absent reviewer): `--reviewer=-<remove>,+<username>`.
3. **Replies and resolves**:
   ```bash
   glab api --method POST "projects/<enc>/merge_requests/<iid>/discussions/<id>/notes" --field body="<reply>"
   glab api --method PUT  "projects/<enc>/merge_requests/<iid>/discussions/<id>" --field resolved=true
   ```
   - Replies that belong to a `fix_code` are posted only after the push. Fill in `<sha>`, then
     resolve those threads.
   - `resolve` actions: resolve as planned.
   - Reply-only threads stay open, because the reviewer closes them. Exception: bot threads
     (Cursor Bugbot, CodeRabbit, Renovate, any `bot` user). A bot never resolves, so reply,
     then resolve.

## Phase 5 — Re-check

Re-run `fetch_blockers.sh` with `MR_IID` and `MR_REPO` exported. Export both: with only one
set, the script targets the current branch's MR. After a `reroll_reviewers`, confirm
reviewers are assigned (`glab mr view <iid> -R <repo> --output json | jq '.reviewers | length'`).
Roulette acts within seconds, so wait ~30s first. Still zero → propose `assign_reviewer`
right away (same candidate logic as `analyze.md`) instead of just reporting it. Report what is left, or:

```
✅ All resolvable blockers cleared. MR !<iid> should be mergeable (pending CI + approval).
```

## Rules

- Never merge (that's `mr-deliver`) or approve.
- Never `--force` (use `--force-with-lease` against the explicit `base_sha`) or `--no-verify`.
- Never resolve a human reviewer's thread that only got a reply.
- Drafts become ready only on an explicit `mark_ready` choice. `reroll_reviewers` toggles an
  MR that is already ready and leaves it ready.
- One MR = one checkout = one push.

## Environment

`glab` authenticated to your GitLab host, `jq`, `python3`, SSH access for cloning.
Env: `MR_TOOLKIT_CLONE_ROOT` (default `~/workspace`), `MR_TOOLKIT_WORKTREES`
(default `~/.cache/mr-toolkit/worktrees`).
