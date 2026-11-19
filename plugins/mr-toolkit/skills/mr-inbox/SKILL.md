---
name: mr-inbox
argument-hint: "[--analyze-only] [--auto-approve] [--mine|--reviews] [mr-url ...]"
description: Clear everything on GitLab that waits on the user in one sitting. Covers authored MRs with red pipelines, conflicts, needed rebases or unresolved reviewer comments, plus MRs waiting on their review. It analyzes every MR in parallel with read-only subagents, runs the safe fixes by itself (flaky retry, conflict-free rebase, missing pipeline, nudging reviewers silent for 8 working hours by default), collects every other decision into one approval screen, applies approved code fixes in per-MR worktrees, and gives risk/hotspot briefs for the reviews (with --auto-approve, low-risk reviews that pass mr-review's gate get approved). Use when the user asks "go through my MRs", "what needs me", "clear my MR inbox", "handle my MRs", "MR sweep", "fix all my MRs", "morning MR pass", "mr-inbox", or wants to deal with several MRs at once. Prefer it over mr-unblock whenever more than one MR is involved.
---

# MR Inbox

Clear every MR that waits on the user in one pass, with the fewest context switches:
**analyze everything → auto-fix the safe stuff → one decision screen → execute in background
while the user reads review briefs → one final report.**

Nothing changes on GitLab or in code until analysis of _all_ MRs has finished. The user sees
each MR once, on the decision screen.

**Everything per authored MR comes from `mr-unblock`**: the analysis brief, the auto actions,
the decision options, execution and posting rules. Those are its _(contract)_ sections. **Everything per review MR comes from `mr-review`**: the brief, the
scores, the gate, approving and logging (its _(contract)_ sections). This skill adds the fan-out,
priority order and the combined screen. Don't restate either skill's rules
here: follow their sections, so a fix there fixes both skills.

`PLUGIN_SKILLS="${CLAUDE_PLUGIN_ROOT}/skills"`. If `CLAUDE_PLUGIN_ROOT` is unset (the skill
was run from a checkout), use the parent directory of this SKILL.md's folder instead. Resolve
it to an absolute path once and pass it to subagents: they don't inherit either one.

## Arguments

- `--analyze-only`: stop after the decision screen is rendered. Run no auto actions and no
  writes of any kind. Use it for dry runs and when the user only asks "what needs me".
- `--auto-approve`: in Phase 3, approve the review MRs that mr-review finds eligible.
  `--analyze-only` wins over it.
- `--mine` / `--reviews`: limit to authored MRs / the review queue.
- MR URLs: only those MRs. Skip `inventory.sh` and build the list from
  `glab mr view <iid> -R <repo> --output json`. Kind is `authored` when `author.username`
  matches `glab api user`, or when the user is an assignee and not a reviewer; otherwise `review`.
  An assignee-only MR also gets `assigned: true` and `author_username`, as `inventory.sh` sets them.

## Phase 1 — Inventory (main thread)

```bash
bash "$PLUGIN_SKILLS/mr-inbox/scripts/inventory.sh"
```

Returns authored MRs plus the pending review queue. Authored MRs include `not_approved`,
`ci_still_running` and `unchecked` ones: GitLab reports only the first blocker, so these can
still hide red CI, conflicts or open threads. Drafts are already excluded. MRs assigned to the
user but authored by someone else (often a bot) come as `kind: "authored"` with
`assigned: true`: the user owns them, so they go through mr-unblock like their own. Anyone can
assign an MR to the user, so these get **no auto actions** (see Phase 3). Show `author_username`
next to the title on the decision screen.

Don't analyze two kinds of MR. Just list them on the decision screen:

- `do_not_merge == true` (a `DO NOT MERGE` / `DON'T MERGE`-style label): show "🚫 label",
  take no action, send no nudge. This check wins over every rule below.
- Authored MRs with `hint == "merge"`: mergeable. Show "ready → `/mr-deliver`". The user
  delivers their own MRs themselves.

Create a run dir: the session scratchpad if you have one, else `~/.cache/mr-toolkit/runs/<ts>/`.
Print one line (`5 authored · 2 reviews — analyzing…`) and go on. Empty → "Inbox zero." Stop.

## Phase 2 — Parallel analysis (read-only subagents)

In **one message**, spawn one background subagent per MR. Don't use worktree isolation.
Analysis needs no checkout, and a worktree per MR would cost a `pnpm install` each.

- authored → brief: `$PLUGIN_SKILLS/mr-unblock/references/analyze.md`, report
  `<run>/<repo-slug>-<iid>.json`
- review → brief: `$PLUGIN_SKILLS/mr-review/references/analyze.md`, outputs `<run>/review-<repo-slug>-<iid>.md`
  and `<run>/<repo-slug>-<iid>.json`

Put the brief's full path and the inputs (`REPO`, `IID`, `WEB_URL`, `PLUGIN_SKILLS`, output
paths, plus `ASSIGNED=true` and `AUTHOR_USERNAME` for `assigned: true` MRs) in the prompt, and tell each subagent to read the brief first. Mark every prompt
**read-only** in its first line: an analysis agent that writes to GitLab breaks the promise
this skill makes.

Wait for all of them, then read the JSON reports. Don't re-analyze in the main thread.
A report missing or malformed → rerun that one agent once, then list it as `analysis failed`.

## Phase 3 — Auto actions (skip with `--analyze-only`)

For every authored report, run its auto actions per mr-unblock "Phase 2 — Auto actions",
including its `held` rule. Collect the MRs with `nudge: true` into a single `/mr-nudge` call.
Skip this for `assigned: true` MRs: their auto actions and nudges become decision-screen
questions instead, next to the author's username.

For every review report: with `--auto-approve`, run mr-review "Approve"; without
it, run mr-review "Log" with `flag_off`.
Report the result in one line per MR.

## Phase 4 — Decision screen

**Order: closest to merging first.** The table, the questions, execution and the review
walkthrough all use this order. Oldest first within a rank:

1. Mergeable authored MRs
2. Authored MRs that are approved and blocked only by auto actions or running CI, and reviews
   auto-approved in Phase 3
3. Authored MRs that are approved and need a fix from the user (the fix unblocks the merge)
4. Reviews where `my_approval_unblocks` and the pipeline is green
5. Authored MRs that need a fix and still need approval
6. Other reviews
7. Authored MRs waiting on reviewers (nudged or not yet due)
8. 🚫 DO NOT MERGE

Table columns. Link everything that has a URL:

- **MR**: `[repo !iid](web_url)`. Use the short repo name.
- **Title**: truncated to about 50 characters.
- **Jira**: `[PROJ-123]($JIRA_BASE_URL/browse/PROJ-123)` from `jira`, or `—`.
- **Age**: the `age` field (`Nh` under 48h, `Nd` above).
- **State**, **Proposed**.
- **Next**: what moves this MR forward, and who does it.
  - `auto` (done in Phase 3)
  - `/mr-unblock`: fixes, rebases, replies and resolves. mr-inbox runs mr-unblock's flow
    for them after your OK. If the user skips here, `/mr-unblock <url>` does the same job
    standalone.
  - `reroll` (review roulette re-triggered)
  - `/mr-deliver`
  - `/mr-nudge` (sent, or due in Nh)
  - `auto-approved` (mr-review approved it in Phase 3)
  - `eligible → --auto-approve` (passes mr-review's gate; rerun with the flag, or review it)
  - `you: review`
  - `wait: CI`

```
📥 11 MRs · 2 auto · 3 need your call · 5 reviews · 1 🚫

| MR | Title | Jira | Age | State | Proposed | Next |
|---|---|---|---|---|---|---|
| [web-app !9557](…) | feat: checkout button retries | [PROJ-7](…) | 9h | approved, flaky unit | ✅ retried | auto |
| [web-app !9522](…) | feat(PROJ-412): vendor build cache | [PROJ-412](…) | 38h | approved, stale stack | rebuild on main, 3 commits | `/mr-unblock` |
| [web-app !9561](…) | docs: sandbox preview config | — | 5h | review, docs only | approve · 5/5/5 | auto-approved |
| [web-app !9546](…) | feat(PROJ-388): manage admin roles | [PROJ-388](…) | 17h | review, your approval unblocks | changes · 3 risks | you: review |
| [admin !3545](…) | feat: add extra preview deploy slots | — | 7d | Bugbot thread, no reviewer | reply + resolve · ✅ reroll | `/mr-unblock` · auto |
| [web-app !5939](…) | … | — | 209d | 🚫 DON'T MERGE | — | — |
```

Then show the "needs you" MRs in priority order, up to 4 questions per `AskUserQuestion`
call and one question per MR. Use mr-unblock's "Phase 3 — Decide" option sets and plan
content. When an MR has several non-auto actions, pick the option set of its heaviest one
(code > reply > rebase > mark_ready) and put the others in the plan text. A bundled non-auto
rebase then runs only if the user picks it via "Other".
With `--analyze-only`, render the table and the plans as text and stop there.

## Phase 5 — Execute in background, reviews in foreground

1. **Approved actions**: execute each MR per mr-unblock "Phase 4 — Execute". Code fixes run
   as background subagents (`worktree.sh` + `execute.md`), at most 3 at a time, since each
   new worktree installs dependencies. An in-place checkout doesn't count against the cap.
   Post replies and resolves right away, except the ones tied to a pending push.
2. **While fixes run**, walk the user through the review briefs (not the auto-approved ones), one
   per message, in priority order: link to the MR, path to the `.md` brief, gist, verdict,
   top risk. Right before each one, re-fetch its live state
   (`glab api projects/<enc>/merge_requests/<iid>/approvals`, plus new commits and notes since
   the brief). The run takes long enough for the user to approve or comment in the meantime.
   Say so instead of asking them to decide again. For each brief, run mr-review "Review": the
   user picks approve, request changes or comment, and the review is posted with that state. Waiting
   time on fixes turns into review time: that's the point of this ordering.

When a fix agent finishes, finish its MR per mr-unblock Phase 4. `pushed` → post its replies
(with `<sha>`) and resolve its threads. `held` / `stopped` → report the checkout path.

## Phase 6 — Report

Re-run `inventory.sh`, and do mr-unblock's "Phase 5 — Re-check" reviewer check for every
rerolled MR. Then close with:

```
✅ Done: !9522 rebased · !9558 fixed (a1b2c3d) + audit retried · admin !3545 2 replies posted
⏸ Held: !9518 — diff at ~/.cache/mr-toolkit/worktrees/acme-web-app-9518
⏳ Waiting on others: !9557 (reviewer reply) · pipelines running on !9522, !9558
✅ Auto-approved: web-app !9561 (5/5/5) · skipped: admin !3550 (new commits since analysis)
📝 Reviews: acme/auth-service !207 — requested changes · admin !3551 — commented
📣 Nudged: @alex (admin !3545)
```

Link every MR in the report the same way as on the decision screen.

## Rules

- Never merge or approve, except for mr-review "Approve" in Phase 3 with `--auto-approve`, and mr-review "Review" in Phase 5 when the user picks approve.
  Review comments go out only through mr-review "Review", with the state the user picked.
- mr-unblock's rules apply to every authored MR, and mr-review's rules to every review MR.
- Everything outside the Phase 3 auto actions goes through the decision screen,
  including replies and resolves on the user's own MRs.

## Environment

Same as mr-unblock (`glab`, `jq`, `python3`, SSH, `MR_TOOLKIT_*` env). Run `glab` from a
clone of a repo on your GitLab host, or export `GITLAB_HOST=<your-gitlab-host>`. From anywhere
else (the run dir, say) `-R <repo>` resolves against gitlab.com and fails with `Unauthenticated`. Run dirs default to
`~/.cache/mr-toolkit/runs/<ts>/` when there is no session scratchpad.
