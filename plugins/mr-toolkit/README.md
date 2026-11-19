# mr-toolkit

The whole GitLab merge-request loop, driven from Claude Code with `glab`.

| Skill | What it does | Author |
|---|---|---|
| `/mr-inbox` | Analyzes every MR that needs you in parallel, auto-fixes the safe parts, and gives you one decision screen. `--auto-approve` approves low-risk reviews through the `mr-review` gate. | Nikita Popov |
| `/mr-review` | Reviews one MR: risk/hotspot brief with clickable links, confidence/risk/coverage scores, and a deterministic gate (`scripts/gate.py`) before any auto-approve. | Nikita Popov |
| `/mr-create` | Rebases, pushes and opens an MR with a description that tells reviewers only what the title, ticket and diff don't. | Andrii Valenia |
| `/mr-deliver` | Drives an opened MR to merge: watches pipelines and approvals, rebases, retries flaky jobs, merges (or enqueues on a merge train), watches the default-branch pipeline. | Artem Krysan, Nikita Popov |
| `/mr-unblock` | Collects everything blocking the current MR (CI, conflicts, threads, approvals) and resolves what it can in a worktree. | Nikita Popov |
| `/mr-split` | Splits a large change into a stack of focused MRs with [git-spice](https://abhinav.github.io/git-spice/). | Arsenii Andrieiev |
| `/mr-nudge` | DMs reviewers of your open MRs on Slack, one message per reviewer. | Max Baginskiy |
| `/mr-to-review` | Your review queue. | Max Baginskiy |
| `/mr-ready` | Your authored MRs that are ready to merge or blocked on you. | Max Baginskiy |

## Requirements

- [`glab`](https://gitlab.com/gitlab-org/cli) authenticated to your GitLab, `jq`, `python3`
- `git-spice` for `/mr-split`
- A Slack MCP server for `/mr-nudge`

## Configuration

| Variable / file | Used by | Default |
|---|---|---|
| `GITLAB_HOST` | all | glab's configured host (`glab config get host`) |
| `EMAIL_DOMAIN` | `/mr-nudge` | domain of `git config user.email`; used when a reviewer has no public email |
| `MR_NUDGE_CONFIRM=0` | `/mr-nudge` | unset: preview once, then send |
| `JIRA_BASE_URL`, `JIRA_KEY_PATTERN` | `/mr-create`, `/mr-inbox` | no Jira link; `[A-Z][A-Z0-9]+-[0-9]+` |
| `MR_TOOLKIT_CLONE_ROOT`, `MR_TOOLKIT_WORKTREES` | `/mr-unblock`, `/mr-inbox` | `~/workspace`, `~/.cache/mr-toolkit/worktrees` |
| `MR_TOOLKIT_NUDGE_AFTER_HOURS`, `MR_TOOLKIT_WORK_HOURS` | `/mr-unblock`, `/mr-inbox` | `8` working hours of reviewer silence before a nudge; working day `9-18` local, Mon–Fri |
| `MR_TOOLKIT_REVIEW_CONFIG` | `/mr-review` | `~/.claude/mr-review/config.json` (see `skills/mr-review/references/config.md`) |
| `~/.claude/mr-deliver/repos.json` | `/mr-deliver` | asks for the local clone path on first run per repo |

## Safety

- Auto-approve is opt-in (`--auto-approve`) and passes a deterministic gate first: size caps, no CI/build/dependency files, no weakened tests, not your own commits.
- `/mr-deliver` is autonomous by design once you invoke it, and stops at explicit ⏸️ points: draft or closed MR, ambiguous rebase conflicts, a real CI failure, a rejected push, a failed merge, missing config.
