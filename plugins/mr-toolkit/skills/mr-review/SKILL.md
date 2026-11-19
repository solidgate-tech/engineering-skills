---
name: mr-review
argument-hint: "<mr-url> [--auto-approve]"
description: Reviews one GitLab MR where the user is a reviewer. Writes a risk/hotspot brief with clickable links, scores confidence, risk and test coverage, and with --auto-approve approves low-risk changes (docs, safe refactors, test fixes, small toggled changes) that also pass deterministic gates, leaving an audit note on the MR. Every review ends as approve, request changes or comment: findings go out as a resolvable review once the user picks the state. Use when the user asks "review this MR", "review !123", "brief me on this MR", "can I approve this", "auto-approve if safe", "mr-review", or pastes the link of an MR they review. For several MRs at once, prefer mr-inbox.
---

# MR Review

One MR, one brief, and one **end state**: every review closes as `approved`,
`requested_changes` or a published comment. An auto-approval happens only when **both** hold:
the LLM scores clear the thresholds, and `gate.py` finds no hard blocker (red pipeline, open
threads, size, denied paths, weakened tests, opt-out). Every other end state is the user's pick.

`PLUGIN_SKILLS="${CLAUDE_PLUGIN_ROOT}/skills"`. If `CLAUDE_PLUGIN_ROOT` is unset (run from a
checkout), use the parent directory of this SKILL.md's folder. Resolve it to an absolute path once
and pass it to subagents, which inherit neither.

## Arguments

- `<mr-url>`: required. `REPO` is the path between the host and `/-/merge_requests/`, `IID` the
  number after it.
- `--auto-approve`: approve when eligible, with no confirmation. Every other GitLab write goes
  through **Review**, after the user picks the end state.

## Flow

1. `glab api projects/<enc>/merge_requests/<iid>`. If the author is the user (`glab api user`),
   say "your own MR → `/mr-unblock`" and stop. If the author is Renovate, write the dependency brief
   (see analyze.md); it is never auto-approved.
2. Run dir: the session scratchpad, else `~/.cache/mr-toolkit/runs/<ts>/`.
3. Spawn **one** subagent, first prompt line **read-only**. Have it read
   `$PLUGIN_SKILLS/mr-review/references/analyze.md` first, and pass `REPO`, `IID`, `WEB_URL`,
   `PLUGIN_SKILLS`, `OUT_MD=<run>/review-<repo-slug>-<iid>.md`, `OUT=<run>/<repo-slug>-<iid>.json`.
   A subagent keeps the diff out of the main context, and it is the same unit mr-inbox fans out.
4. Read `OUT`. Show the MR link, the brief path, the gist, the verdict, the three scores, and
   `eligible` or `not eligible: <reasons>` (Renovate: no scores or gate; show `never auto-approved`).
5. With `--auto-approve`, run **Approve**. Without it, run **Log** with `flag_off`.
6. Not auto-approved (no flag, or **Approve** skipped it): run **Review**. The
   step is done when the MR shows one of the end states that **Review** step 5 checks.

## Review _(contract)_

Closes the MR on an end state. mr-inbox Phase 5 runs this section too. Input: the report JSON
and its brief.

1. Re-fetch the user's reviewer state (`projects/<enc>/merge_requests/<iid>/reviewers`), threads
   and commits since the brief. Done when there are no commits newer than the end state: report
   it. The end state is `approved`, `requested_changes` or `reviewed` (however it was set), or
   below 19.2 a note of the user's carrying `<!-- mr-review:comment -->` (step 4). Other notes of
   the user's don't count. A `<!-- mr-review:requested_changes -->` note while the state isn't
   `requested_changes` means the mutation in step 4 failed: rerun only that mutation, then step 5.
   New commits: carry on, so a fresh review can replace it (e.g. lift a
   `requested_changes`). Commits since the brief: regenerate the brief (Flow step 3) before
   drafting. List the user's pending `draft_notes`: publishing sends all of
   them, so show them in step 3.
2. Draft the review from the brief, addressed to the author, in the user's voice with no 🤖
   marker: one **thread** per finding that sits on a line the MR adds, plus a **summary** note
   only when it carries something the threads and the end state don't.
   - A thread holds one Risk, Convention violation or nit (prefixed `Nit:`): the problem, the
     broken rule and the fix. Anchor it only to a `+` line of the MR diff at the head sha
     (`glab api .../merge_requests/<iid>/diffs`), so each finding can be resolved on its own.
   - The summary holds the findings with no added line to anchor to (unchanged code, another
     repo, merge order, earlier threads) as numbered items with their head-sha link, plus your
     position when the threads don't make it clear (e.g. which finding blocks). Drop it when it
     would only restate the end state ("approving", "LGTM") or point at the threads ("one nit
     inline"): GitLab already shows both.
   - Save it as `<run>/comment-<repo-slug>-<iid>.md`: the summary first if there is one, then
     each thread after a `<!-- thread: <path>:<line> -->` line. Verdict `approve` with no
     findings: the draft is empty.
   - **Voice.** Write the way an engineer writes to another engineer. The brief is structured;
     the posted text is not a copy of it:
     - Don't narrate the review's structure ("threads are inline", "not anchored to a line"), and
       don't use templates: no bold headline per thread, no `Fix:` label. A summary is 1-2
       sentences of your position, then the unanchored items in plain words.
     - Keep each thread a few lines: the problem, one concrete scenario, the suggestion. Say
       each thing once: a later thread refers to an earlier one instead of repeating it.
     - A `slip` is stated directly. A `call` starts from the author's intent and asks for
       context before proposing anything else ("Is the idea that …? That works when …; here …").
       Say whether it blocks or is your preference.
     - Name the concern, not how to deliver it: whether it lands here, in a follow-up or as a
       ticket is the author's call.
     - Only the brief's `teach` findings (at most two) also get "right when" and the precedent.
       Keep the rest short. Add a first-person story ("I tried X, it failed because Y") only
       when the brief or the user's own notes give a real source for it. Never make one up.
     - Leave room to disagree: a finding the author can argue with is better than an order.
3. Ask in **one** `AskUserQuestion` call, so the user never has to open the draft file to decide:
   - **Findings** (multiSelect): each thread and summary item is its own option, with a short
     label and a one-line description (`path:line` and the fix). A question takes 2-4 options, so
     split findings evenly (5 → 3 + 2, never 4 + 1), at most 3 questions, nits grouped last. With
     more than 12, fold the nits into one "All nits" option. A single finding gets "Skip it" as its
     second option.
   - **End state**: approve, comment or request changes, the only three options. Default from the
     verdict: `approve` → approve, `nits` → comment, `changes` → request changes, marked
     "(Recommended)".

   Rebuild the draft from the picked findings. Text the user types under "Other" is their own
   finding: add it in their words, anchored to a line when they name one. A question about a
   finding ("why is this a problem?") is not a pick: answer it, fix or drop the finding if the
   user is right, and ask again. An empty draft is valid only for approve: comment or request
   changes with no findings picked means the user writes the note first.

4. Post it. Comment and request changes publish the draft as a review, so every note is a
   resolvable thread. First re-check the MR's head sha equals the report's `head_sha`; if not,
   go back to step 1. Never POST an empty note. Post each thread as a draft note anchored to
   its line, with the shas from the MR's `diff_refs`. glab rejects `-f 'position[…]'` fields, so
   send a JSON body:
   ```bash
   glab api "projects/<enc>/merge_requests/<iid>" | jq --rawfile note <thread.md> \
     --arg p <path> --argjson l <line> '{note: $note, position: (.diff_refs
       + {position_type: "text", old_path: $p, new_path: $p, new_line: $l})}' > <thread.json>
   glab api -X POST "projects/<enc>/merge_requests/<iid>/draft_notes" \
     -H 'Content-Type: application/json' --input <thread.json>
   ```
   GitLab accepts a draft on a line outside the diff and returns it with `line_code: null`, which
   doesn't render as a diff thread. When `line_code` is null, delete that draft
   (`-X DELETE .../draft_notes/<id>`) and move the thread into the summary as a numbered item with
   its link, creating the summary if there was none. Then end the summary with the hidden line
   `<!-- mr-review:<comment|requested_changes> -->` for the picked state, so step 1 can tell this
   review from other notes. With no summary, add that line to the first thread that kept its
   `line_code` instead (`-X PUT .../draft_notes/<id>` with the note plus the line). Post the
   summary, if there is one, and publish all of them as one review:
   ```bash
   glab api -X POST "projects/<enc>/merge_requests/<iid>/draft_notes" -F note=@<summary.md>
   glab api -X POST "projects/<enc>/merge_requests/<iid>/draft_notes/bulk_publish"
   ```
   REST `bulk_publish` gains `reviewer_state` only in GitLab 19.2 (`glab api version`); older
   servers drop it silently, so the note alone leaves the state at `review_started`. On 19.2+, pass
   `-f reviewer_state=<requested_changes|reviewed>` to `bulk_publish` and skip the rest of this
   paragraph. Below 19.2, request changes sets the state with the GraphQL mutation backed by the
   same `UpdateReviewerStateService`:
   ```bash
   glab api graphql -f query='mutation { mergeRequestRequestChanges(input:
     {projectPath: "<repo>", iid: "<iid>"}) { errors } }'   # errors must be []
   ```
   Below 19.2, comment stops at the published note: no REST or GraphQL call sets `reviewed`, so
   `review_started` plus the `mr-review:comment` note is the comment end state. Approve
   publishes the draft first when it isn't empty, then
   `glab mr approve <iid> -R <repo> --sha <head_sha>`. A sha rejection means new commits:
   report it and go back to step 1 after a fresh brief.
5. Check `.../reviewers` shows the picked state (`review_started` for comment below GitLab 19.2).
   When a non-empty draft was published, also check `.../discussions` shows the summary, if any,
   and every thread with `resolvable: true`, the threads with a `position`. Report the state and the note
   links, if any.

## Approve _(contract)_

mr-inbox Phase 3 runs this section for every review report. Input: the report JSON.

1. `scores` is null (Renovate): skip without logging. `gate.eligible` is false or `gate` is
   null: skip and log `not_eligible`.
2. **Re-run the gate** with the report's own scores. Never trust the report's boolean alone:
   ```bash
   python3 "$PLUGIN_SKILLS/mr-review/scripts/gate.py" --repo <repo> --iid <iid> \
     --scores <c>,<r>,<v> --verdict <verdict>
   ```
   Approve only if it prints `"eligible": true` **and** its `head_sha` equals the report's
   `gate.head_sha`. A different sha means new commits since analysis: log `skipped_sha` and report
   `skipped: new commits since analysis`. Anything else that's not eligible: log `not_eligible`
   with the fresh reasons.
3. Approve, pinned to the analysed commit (GitLab rejects it if the head moved in between):
   ```bash
   glab mr approve <iid> -R <repo> --sha <gate.head_sha>
   ```
   A sha rejection gets logged as `skipped_sha`. Any other error gets reported, with no retry and no note.
4. Post exactly one note:
   `glab mr note <iid> -R <repo> -m "🤖 Auto-approved via mr-review — confidence <c> · risk <r> · coverage <v>. <summary>."`
5. Log `approved`.

## Log _(contract)_

One line per scored MR, so thresholds can be tuned from real data. Only the orchestrator writes it:

```bash
mkdir -p ~/.cache/mr-toolkit && jq -c --arg action <approved|skipped_sha|not_eligible|flag_off> \
  '{ts: (now | todate), repo, iid, head_sha: .gate.head_sha, scores, verdict,
    eligible: .gate.eligible, reasons: .gate.reasons, action: $action}' <report.json> \
  >> ~/.cache/mr-toolkit/review-log.jsonl
```

Skip it for Renovate reports (`scores` is null).

## Config

Per-repo thresholds, extra denied paths and opt-outs: see [references/config.md](references/config.md).

## Rules

- Never merge. Approve through **Approve** (`--auto-approve`) or through **Review** when the
  user picks approve. Never on the user's own MRs. Renovate MRs only through **Review**.
- The skill posts two kinds of note: the audit note from **Approve**, and the review from
  **Review**, after the user picks its end state. Findings go out as a `draft_notes` review,
  one thread per finding anchored to its diff line, so the author can resolve each one.
- The analysis subagent stays read-only. It must not run `glab` write calls, approve, or post anything.
- Don't re-score an MR to get it past the gate. Report the reasons instead.

## Environment

`glab` (authenticated to your GitLab host), `jq`, `python3`. Outside a checkout, set
`GITLAB_HOST` or rely on glab's configured host.
