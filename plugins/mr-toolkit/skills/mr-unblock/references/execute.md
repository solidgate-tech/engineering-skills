# Execute an approved plan for one MR (mr-unblock / mr-inbox)

You apply an **approved** plan to one of the user's MRs. The user approved it on the decision
screen, so don't reopen the plan. If reality contradicts it (the root cause is different,
or the fix needs a design choice), stop and report back instead of improvising.

Inputs from the caller: `REPO`, `IID`, `WT` (the JSON from `scripts/worktree.sh`:
`path`, `base_sha`, `branch`, `in_place`), `PLAN` (the approved actions from the report, plus any edits
the user made), `PUSH` (`push` or `hold`), `OUT` (result path).

## Steps

1. `cd` into `WT.path`. Read the repo's `AGENTS.md`/`CLAUDE.md`, plus the local `AGENTS.md` of
   each package you touch. They define setup (e.g. `pnpm install`, Node version), checks and
   commit format. `WT.in_place == true` means this is the user's own checkout. Dependencies
   are usually installed already, so skip setup unless a check fails on missing deps. Leave
   it the way you found it if you stop: abort a failed rebase, keep no stray files.
2. If the plan has `rebase_local`, a held `rebase_api` or an approved `rebase_api`, rebase first: `git fetch origin <target>`,
   `git rebase origin/<target>`. Resolve only conflicts whose intent is clear from both sides.
   A non-trivial conflict → `git rebase --abort`, report the hunks, stop.
3. Apply the fix. Keep it to the minimal diff that addresses the plan.
4. Run the checks named in the plan, plus the repo's fast loop for the touched packages
   (typecheck, lint, unit tests). A check that still fails → one more attempt at the root
   cause, then stop and report. Never skip hooks (`--no-verify`) or weaken a test to pass.
5. Commit in the repo's commit format. If there is a ticket key, take it from the branch name
   or earlier commits.
6. `PUSH == push`:
   `git push --force-with-lease=refs/heads/<branch>:<base_sha> origin HEAD:refs/heads/<branch>`.
   Plain fast-forward pushes work the same way. If the lease rejects the push, someone pushed
   in the meantime: stop and report, don't re-fetch and force.
   `PUSH == hold`: leave the commit local and report the path.
7. Worktree (`in_place == false`) and pushed → `git -C <WT.clone> worktree remove <WT.path>`.
   Never remove an in-place checkout.

Write to `OUT`:

```json
{
  "repo": "…",
  "iid": 0,
  "status": "pushed|held|stopped",
  "sha": "…",
  "checks": "what ran + result",
  "note": "why stopped / what the user should look at",
  "worktree": "<path>"
}
```

Return one line: `<repo> !<iid> — <status> <sha>: <note>`.
