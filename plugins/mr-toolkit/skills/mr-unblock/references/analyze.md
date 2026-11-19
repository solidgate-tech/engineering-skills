# Analyze one authored MR (subagent brief)

You analyze **one** MR the user authored and write a plan. You are strictly read-only:
no `glab` write calls (no POST/PUT/DELETE, no `retry`, `rebase`, `note`, `update`), no
`git push`, no checkout or edits in any clone. `git fetch` and `git show origin/<branch>:<path>`
are fine: they update remote refs and don't touch the user's working tree.

Inputs from the orchestrator: `REPO`, `IID`, `WEB_URL`, `PLUGIN_SKILLS` (absolute path to
mr-toolkit's `skills/`), `OUT` (report path). For an MR the user owns as assignee while someone
else (often a bot) authored it: `ASSIGNED=true` and `AUTHOR_USERNAME`.

## 1. Blockers

```bash
MR_IID=$IID MR_REPO=$REPO bash "$PLUGIN_SKILLS/mr-unblock/scripts/fetch_blockers.sh"
```

Export **both** vars. With only one set, the script targets the current branch's MR.
Merged or closed → write `{"state": "<state>", "actions": []}` and stop.

## 2. Classify each blocker

- **Draft** → `mark_ready` (needs you). Never auto: drafts are often intentional.
- **Behind target, no conflicts** → `rebase_api` (auto). Three exceptions:
  - The project merges with merge commits (`glab api projects/<enc> | jq .merge_method` is
    `merge`) → being behind blocks nothing. No action.
  - The project has merge trains (`glab api projects/<enc> | jq .merge_trains_enabled` is
    `true`) → being behind blocks nothing: the train tests the merged result. A rebase only
    restarts CI. No action.
  - Another open MR targets this MR's source branch (a stacked child:
    `glab api "projects/<enc>/merge_requests?state=opened&target_branch=<source>"`) → rebasing
    moves the base under the child, and the child's diff then shows the parent's old commits
    again. Use `"auto": false` and name the child in `detail`. A child that already merged
    into this branch doesn't count.
- **Conflicts** → `rebase_local` (needs you). Put in `detail` how far behind the branch is and
  which target-branch commits touch the MR's files (`glab mr diff` file list against
  `glab api projects/<enc>/repository/compare?from=<source>&to=<target>`). The fix agent
  finds the exact conflicting hunks in its worktree.
- **Pipeline failed**: for each failed job, run `glab ci trace <id> -R $REPO | tail -150` and classify
  it with the "Flaky vs real" table in `$PLUGIN_SKILLS/mr-unblock/SKILL.md`.
  - Flaky → `retry_job` (auto).
  - Real → `fix_code` (needs you). Find the root cause. Quote the decisive 3-10 log lines,
    name the files involved and describe the fix concretely. Read the code at the MR head
    through the API (`glab api projects/<enc>/repository/files/<enc-path>/raw?ref=<source>`) or
    `git show` in a local clone.
  - The job fails the same way on the target branch too (check the latest target pipeline)
    → not caused by this MR. Say so and propose `retry_job` or `skip`, not `fix_code`.
- **Pipeline not run** (`null`, `unknown`, `skipped`, `canceled`) → `trigger_pipeline` (auto).
  In-flight (`created`, `waiting_for_resource`, `preparing`, `waiting_for_callback`, `pending`,
  `running`, `canceling`, `scheduled`) → a pipeline exists, never trigger a duplicate. Note it.
  `manual` → a human has to start it. Note it, no action.
- **Unresolved discussions**: fetch the full threads with
  `glab api projects/<enc>/merge_requests/$IID/discussions/<id>`.
  - Last note is the user's (the MR author, or the assignee when `ASSIGNED` is true):
    - Thread opened by a bot (Cursor Bugbot, CodeRabbit, Renovate, any `bot` user) → `resolve`,
      with the user's reply as evidence. A bot never resolves its own thread.
    - Human reviewer → the reviewer owes a reply, so it's not on the user. Skip.
  - Reviewer asks for a change → `fix_code`. Give `discussion_ids` and a drafted `reply` to post
    after the push (e.g. "Done in <sha>: …"). The `<sha>` placeholder gets filled at execution.
  - Question or disagreement, no code change → `reply` with the text in `reply`. Match the thread's
    language and tone, and keep it short. State only what you verified (a job status, a line you
    read). An inferred cause goes in `detail`, not in the reply the user will post under their name. If a real design decision is needed, say so in
    `detail` instead of guessing.
  - Already addressed in a later commit → `resolve` with evidence (commit sha or file:line).
- **No reviewers assigned** (`glab mr view $IID -R $REPO --output json | jq '.reviewers'` is
  empty, MR not a draft). Nobody can approve or be nudged until someone is assigned, so set
  `nudge: false`. First check that the project runs review roulette: look at the system notes
  of its ~10 most recent MRs for `requested review from` by a bot or service account
  (`glab api "projects/<enc>/merge_requests?state=all&per_page=10"`, then `/notes` for each).
  - Roulette present → `reroll_reviewers` (auto).
  - No roulette (e.g. a project whose bot only sets the assignee) →
    `assign_reviewer` (needs you). Suggest 1-3 candidates from people who recently reviewed or
    approved MRs touching the same files (`glab api "projects/<enc>/repository/commits?path=<file>"`,
    then those commits' MRs). Leave out anyone who is away (see "Reviewer availability"
    below). The user picks one.
- **Approvals missing, nothing else** → no actions. `waiting_on: "reviewers"`.

**Counting approvals.** `approvals_left` adds up the open approval rules, but one person
eligible in several rules (`*` and `/apps/admin/`, say) satisfies them all with one approval.
So `approvals_left: 2` with one assigned reviewer doesn't mean a second reviewer is needed.
Count per rule instead, from `glab api projects/<enc>/merge_requests/$IID/approval_state`. For
each rule with `approved: false`:

- needed = `approvals_required - (approved_by | length)`;
- available = assigned reviewers who haven't approved yet and are eligible: the rule is
  `any_approver`, or they are in its `eligible_approvers`.

A rule is short when available < needed. Propose `assign_reviewer` only for short rules, and
name the rule and the missing count in `detail`. Candidates are that rule's
`eligible_approvers` minus its `approved_by`, the assigned reviewers, and bots or service
accounts. If the rule is `any_approver`, or that leaves nobody or more than 3 people, use the
file-history method from "No roulette" above. Suggest at most 3 and leave out anyone who is
away. No short rule → no extra reviewer, whatever `approvals_left` says.

**Reviewer silence (for the auto-nudge).** When `waiting_on` is `"reviewers"` (approval
missing, or the reviewer owes a thread reply), find `waiting_since`. The nudge clock counts
from when the review was assigned, not from the last change: take the system note
`requested review from @<reviewer>`, or the time the MR left draft if that is later. Commits
and rebases don't reset it. Any note or approval from that reviewer after that point means
they responded: `nudge: false`. If they then owe a thread reply, count from the user's reply
in that thread. Otherwise:
`python3 "$PLUGIN_SKILLS/mr-unblock/scripts/working_hours.py" <waiting_since>` ≥ `${MR_TOOLKIT_NUDGE_AFTER_HOURS:-8}` → `nudge: true`.
Put the reviewers you'd nudge in `nudge_reviewers`.

**Reviewer availability.** Before you wait on a reviewer or nudge one, check their Slack
status. Search with the Slack MCP server's `slack_search_users` tool for the surname from GitLab's `name`
field and match on the `<username>@<domain>` email: searching by email often finds nothing.
Then read the status with the Slack MCP server's `slack_read_user_profile` tool. A status that says
they're away ("day off", "Off sick", "Vacationing", "OOO") means they can't review today:

- Leave them out of `nudge_reviewers`.
- Propose `assign_reviewer` with `"remove": "<username>"`. Take candidates from the approval
  rules that still need approvals (`glab api projects/<enc>/merge_requests/$IID/approval_state`,
  `.rules[].eligible_approvers`). A path rule like `/docs/ownership/` can narrow the pool to
  one or two people, so that rule decides the candidates. Leave out bots and service
  accounts, and check each candidate's Slack status too. "In a meeting" counts as available.

If Slack isn't connected, say so in `detail` and go on without the check.

Don't auto-resolve anything. Never classify ambiguous conflicts or failures as flaky.

## 3. Dedupe

- An `auto: true` `rebase_api` or a `rebase_local` restarts the pipeline, so drop `retry_job`
  on that MR. A non-auto `rebase_api` runs only on the user's explicit Rebase choice: keep
  `retry_job` beside it and never mark it held. Next to `fix_code` or `rebase_local` it
  folds into the fix: if approved, the fix rebases in its worktree instead of a server-side
  rebase racing the push. It still carries the "stacked child needs a restack" warning.
- `fix_code` or `rebase_local` present → keep any `auto: true` `rebase_api` / `retry_job`,
  but set `"held": true` on them. They only run if the user skips the fix: the fix rebases in its
  worktree and its push restarts CI anyway.
- Several `fix_code` items on one MR → merge them into one entry with a combined plan.
  One worktree and one push per MR.

## 4. Write the report

Write JSON to `$OUT`:

```json
{
  "kind": "authored",
  "repo": "acme/web-app",
  "iid": 9558,
  "title": "…",
  "web_url": "…",
  "source_branch": "…",
  "target_branch": "master",
  "waiting_on": "me",
  "approvals_left": 1,
  "pipeline": "failed",
  "nudge": false,
  "nudge_reviewers": [],
  "waiting_since": null,
  "summary": "Red CI: checkout test-func assertion on new label; audit is flaky (registry 429).",
  "actions": [
    {
      "type": "fix_code",
      "auto": false,
      "detail": "…root cause + concrete plan…",
      "files": ["apps/checkout/src/…"],
      "evidence": "…log lines…",
      "discussion_ids": [],
      "reply": null,
      "checks": "pnpm --filter @acme/checkout test-func <spec>"
    },
    {
      "type": "retry_job",
      "auto": true,
      "job_id": 123,
      "detail": "audit: 429 from registry"
    }
  ]
}
```

`type` is one of: `mark_ready`, `rebase_api`, `rebase_local`, `retry_job`, `trigger_pipeline`,
`reroll_reviewers`, `assign_reviewer` (with `candidates: [username]`, plus `remove: username`
when it replaces an absent reviewer), `fix_code`, `reply`, `resolve`. `auto: true` only for `rebase_api`,
`retry_job`, `trigger_pipeline`, `reroll_reviewers`.
`waiting_on` is `"me"` if any action exists, otherwise `"reviewers"`.

Return exactly one line to the orchestrator: `<repo> !<iid> — <summary>`.
