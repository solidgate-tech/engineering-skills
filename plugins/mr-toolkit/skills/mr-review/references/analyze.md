# Review brief for one MR (subagent brief, used by mr-review and mr-inbox)

The user is a reviewer on this MR. The orchestrator turns your brief into the review comment
the user confirms and posts, so the brief must hold every finding with its link, rule and fix.
**Post nothing**: no notes, no approvals, no thread replies, no
`glab` write calls. Approving is the orchestrator's job, not yours.

Inputs from the orchestrator: `REPO`, `IID`, `WEB_URL`, `PLUGIN_SKILLS`, `OUT_MD` (brief path),
`OUT` (JSON path).

**Links.** Write every file reference in the brief as a clickable link to the MR head commit,
e.g. ``[`path:line`](<project_web_url>/-/blob/<head_sha>/<path>#L<line>)``. `head_sha` is
`diff_refs.head_sha` from `glab mr view`. Link commits and other MRs too. The user reads this
next to GitLab and should be one click from each finding.

**Renovate MRs** (author is the Renovate bot): the brief answers one question: is it safe
to merge? Check the changelog or release notes of
each bumped package for breaking changes, whether the repo uses the changed APIs, and CI
status. Keep it short: verdict, one line per bumped package, and anything that blocks
merging. Skip section 3 for them: Renovate MRs are never auto-approved here.

## 1. Context

```bash
export GITLAB_HOST="${GITLAB_HOST:-$(glab config get host)}"   # you may run outside a checkout
glab mr view $IID -R $REPO --output json      # title, description, author, branches
glab mr diff $IID -R $REPO                     # the change
glab api "projects/<enc>/merge_requests/$IID/discussions?per_page=100"   # existing threads
```

If the user already left threads, check whether the author addressed them (later commits,
replies). That is the re-review part: report each earlier thread as addressed, partly
addressed or ignored.

Conventions come from the target repo, not from your defaults. Fetch whichever of these exist
at the target branch: root `AGENTS.md`/`CLAUDE.md`, the `AGENTS.md` of each touched
`apps/<x>/` or `libs/<x>/` directory, and `.claude/rules/*.md` that relate to the changed file
types (e.g. `playwright.md` for page tests):

```bash
glab api "projects/<enc>/repository/files/<url-encoded-path>/raw?ref=<target>"
```

For surrounding code the diff doesn't show, read files at the MR head the same way
(`ref=<source>`).

## 2. Analyze

Look for what a strong senior reviewer on this team would flag, ordered by impact:

- **Risks**: correctness bugs, broken edge cases, data loss, security (auth, input validation,
  secrets), concurrency, backwards-incompatible API/contract changes, migrations, performance
  cliffs. Each one needs a concrete failure scenario, not "might be an issue".
- **Hotspots**: where review attention should go. The 2-5 places in the diff with the most
  logic or risk, as `path:line`, each with a one-line reason. Also mention the parts that are
  safe to skim (generated code, renames, lockfile), so the user can skip them.
- **Convention violations**: cite the rule you're applying (file + rule) for each one. No
  citation = it's your taste, so drop it or file it under "nits".
- **Tests**: is the changed behaviour covered? Is the test at the right level for this repo's
  rules (unit vs page test)? Name the missing cases.

Verify before you claim. If a finding depends on code outside the diff, read that code.
Leave out anything you couldn't confirm, or label it `unverified`.

**Judgement, not only defects.** The review should teach judgement, not demand compliance, so give
each Risk and Convention violation:

- **Kind**: `slip` when it's plainly wrong whatever the intent (off-by-one, missing `await`, typo),
  or `call` when it's a trade-off the author made on purpose.
- **Intent** (`call` only): the author's likely reasoning, taken from the description, threads,
  commit messages or the code. Mark it `guess` when nothing states it.
- **Right when**: the circumstances in which the current choice would be correct, and what tips
  it the other way here.
- **Precedent**: a real earlier case, linked: a commit or MR that tried this, an incident, an ADR,
  a gotcha in an `AGENTS.md`. Search `git log`/`blame` on the touched paths and merged MRs on the
  same files. Nothing found means no precedent. Never invent one.

Then mark at most **two** findings as `teach`: the ones where the reasoning will carry over to
other MRs. Prefer the repo's own conventions, history and incidents over generic best practice.

**Verdict.** `changes` when a risk or a cited convention violation in the code needs fixing.
`nits` when the code should change before merge, but it isn't a blocker. `approve` otherwise.
Process issues that the code can't fix, such as the branch name, the commit message format or the
MR title, go under Nits but don't move the verdict off `approve`.

## 3. Score and gate

Score three factors, each an integer 1-5, with a one-line justification per factor that points
at evidence (a file, a test, a rule). Score what you verified, not what the description claims.

| Score | Confidence: the whole effect is understood | Risk (5 = safest) | Coverage |
| --- | --- | --- | --- |
| 5 | mechanical or trivial, full effect visible in the diff | no runtime effect (docs, comments, test-only) | no behaviour change, or every changed rule/branch is asserted by tests in the diff |
| 4 | understood after reading the touched code outside the diff | runtime code, but behaviour-preserving, or off by default behind a toggle | changed behaviour asserted, one minor gap (e.g. an assertion weaker than the repo's rules ask), or existing tests exercise it (name them) |
| 3 | understood, one minor `unverified` point | small behaviour change, narrow blast radius | changed behaviour partly covered (a rule or edge case untested), or a test migration dropped a case that used to be covered; gaps named |
| 2 | intent or side effects unclear | any risk you listed, or it touches money, auth or data paths | changed behaviour has no test |
| 1 | can't tell what it does | contract or API change, migration, concurrency | tests removed with nothing replacing them, or skipped/weakened |

Files the diff API flags `generated_file` are left out of the size cap. Check that each one really
is generator output: a `Code generated … DO NOT EDIT` header, or a source file (`.proto`, an OpenAPI
spec) changed in the same MR. A hand-written file that only carries a generator-style name is a
risk: list it, which caps `risk` at 2.

Coverage is about what **this MR changes**. A test file replaced by another one (say Vitest to
Playwright) isn't a loss in itself: compare the cases, and name each one that didn't make it across.

If you listed 1 or more **Risks**, `risk` is at most 2. When torn between two scores, take the
lower one: a wrong low score costs the user a review, a wrong high score ships a bug unreviewed.

Then run the deterministic gate (read-only). `<verdict>` is `approve`, `nits` or `changes`:

```bash
python3 "$PLUGIN_SKILLS/mr-review/scripts/gate.py" --repo $REPO --iid $IID \
  --scores <confidence>,<risk>,<coverage> --verdict <verdict>
```

Copy its JSON output into the report's `gate` field as-is (drop `config`). Exit code 1 means
glab failed: set `gate` to `{"pass": false, "eligible": false, "reasons": ["gate: <stderr>"]}`.
Don't argue with the gate's reasons, and don't re-score to get past it.

## 4. Write the brief

`OUT_MD` (markdown, for the user to read in the editor next to the MR):

```markdown
# <repo> !<iid> — <title>

<author> · +A −D in F files · <web_url>

**Gist:** 1-2 sentences on what the change does and whether the approach is sound.
**Suggested verdict:** approve | approve with nits | request changes (reason)
**Scores:** confidence N · risk N · coverage N — **auto-approve:** eligible | not eligible: <gate reasons>

- confidence N: <justification>
- risk N: <justification>
- coverage N: <justification>

## Risks

1. `path:line` — problem. Failure scenario. Suggested fix.
   - slip | call · intent: … (guess) · right when: … · precedent: <link> · teach

## Hotspots

- `path:line` — why to look here
- Safe to skim: …

## Convention violations

- `path:line` — violates <rule file>: "<rule>". Fix.
  - slip | call · intent: … · right when: … · precedent: <link> · teach

## Tests

…

## Earlier threads (re-review)

- <thread first line> — addressed in <sha> | still open because …

## Nits (optional)
```

Omit empty sections. `approvals_left` comes from
`glab api "projects/<enc>/merge_requests/$IID/approvals"`. It adds up the open approval rules,
and one person eligible in several rules (`*` and `/apps/admin/`, say) satisfies them all at once,
so `approvals_left: 2` can still mean one approval is enough. `my_approval_unblocks` is true when
at least one rule is still open, the user hasn't approved, and the user's approval closes every
open rule:

```bash
glab api "projects/<enc>/merge_requests/$IID/approval_state" | jq --arg me "<username>" '
  [.rules[] | select(.approved | not)] as $open
  | ($open | length) > 0
    and all(.rules[]; all(.approved_by[]; .username != $me))
    and ($open | all((.approvals_required - (.approved_by | length)) == 1
        and (.rule_type == "any_approver" or any(.eligible_approvers[]; .username == $me))))'
```

Renovate briefs have no scores line. `OUT` (JSON for the orchestrator;
`scores`, `score_reasons` and `gate` are `null` for Renovate):

```json
{
  "kind": "review",
  "repo": "…",
  "iid": 0,
  "title": "…",
  "web_url": "…",
  "head_sha": "<diff_refs.head_sha the brief was written against>",
  "author": "…",
  "verdict": "approve|nits|changes",
  "approvals_left": 0,
  "pipeline": "success",
  "my_approval_unblocks": true,
  "risks": 0,
  "violations": 0,
  "summary": "one line",
  "brief": "<OUT_MD>",
  "scores": { "confidence": 5, "risk": 4, "coverage": 4 },
  "score_reasons": { "confidence": "…", "risk": "…", "coverage": "…" },
  "gate": { "pass": true, "eligible": true, "reasons": [], "head_sha": "…" }
}
```

Return one line: `<repo> !<iid> — <verdict> · <eligible|not eligible|renovate>: <summary>`.
