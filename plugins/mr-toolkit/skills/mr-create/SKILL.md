---
name: mr-create
description: |
  Default skill for creating GitLab merge requests with `glab`. THIS IS THE SKILL TO INVOKE for any natural-language request to push the current branch up for review on GitLab — prefer over any generic git/PR/jira workflow skill.

  HARD TRIGGERS (invoke immediately, do not ask): "create MR", "open MR", "make MR", "submit MR", "do MR", "MR this", "MR please", "let's MR", "push MR", "push and MR", "open a merge request", "create merge request", "submit for review", "push this up", "push this up for review", "ready for review on GitLab", "ship MR", "MR it", "open an MR", "ready an MR", "create an MR", "/mr-create", "/mr".

  Also trigger on Ukrainian variants: "створи MR", "зроби MR", "пушни на MR", "відправ на ревʼю".

  DO NOT auto-invoke without an explicit MR request in the user's CURRENT message. Finishing a feature, committing, or pushing is NOT a trigger. An MR created earlier in this same conversation does NOT authorize creating another one — the next MR needs its own fresh explicit ask. When the user just finished work and said nothing about an MR, STOP and let them ask.

  Always rebases the branch on top of the latest target (main/master) before pushing — keeps the MR diff clean and avoids "this branch is N commits behind" noise.
---

# GitLab Merge Request

Rebase, push, create MR via `glab`, return the URL.

## Scope — ONE explicit request = ONE MR

This skill handles **exactly one MR: the current branch, for the explicit request that invoked it**. When done (step 6), **STOP and return control to the user.**

- **Every MR needs its own fresh explicit ask.** A user asking for an MR earlier in the conversation does NOT authorize the next one. Later, when they finish another feature, do NOT infer "they'll want an MR too" — wait for them to say so.
- **Finishing work ≠ requesting an MR.** Completing a feature, committing, or pushing is not a trigger. Hand control back; let the user invoke the skill again when they're ready.
- **Never chain.** Do not create a second MR, switch branches, or start the next one on your own — even mid-stack, even if more work is obviously waiting.
- Silence is not consent. When unsure whether the user asked, assume they didn't and stop.

## Defaults

- **Assignee**: `@me` (glab resolves server-side to the authenticated user)
- **Reviewers**: none by default, so CODEOWNERS or the project's approval rules assign them. If the user names reviewers, pass `--reviewer <user>,<user>`.
- **Target branch**: the remote's default (HEAD) branch from step 1.

## Workflow

### 1. Detect target + Jira key

```bash
git branch --show-current
git remote show origin | grep "HEAD branch"
```

Jira key from branch name matching `$JIRA_KEY_PATTERN` (default `[A-Z][A-Z0-9]+-[0-9]+`), e.g. `PROJ-123_short-title`.

### 2. Rebase on latest target — ALWAYS

```bash
git fetch origin <target>
git rebase origin/<target>
git log --oneline HEAD@{1}..origin/<target> 2>/dev/null | head -10   # show what came in
```

Conflict → **STOP**, report conflicting paths, ask. Don't auto-resolve, don't skip.

### 3. Show diff summary

```bash
git log --oneline origin/<target>..HEAD
git diff origin/<target>...HEAD --stat | tail -1
```

### 4. Push

```bash
git push -u origin <branch>                          # first push
git push --force-with-lease origin <branch>          # post-rebase
```

Never plain `--force`.

### 5. Create MR

Pick labels per [MR Labels](#mr-labels) from the project's list:

```bash
glab label list --per-page 100
```

```bash
glab mr create \
  --source-branch <branch> --target-branch <target> \
  --title "<title>" \
  --description "$(cat <<'EOF'
<body>
EOF
)" \
  --assignee @me \
  --label "<label>,<label>"      # omit when no label applies
```

### 6. Return the MR URL on its own line.

Below it: `Labels: feature, ADR` (or `Labels: none`). If the project has labels outside the type, lifecycle and never-apply lists (e.g. `needs-qa`), add `Other labels here: <names>` so the user can add them by hand.

---

## MR Title

Conventional commits + Jira key, under 70 chars.

```text
feat(PROJ-123): short imperative description
fix(PROJ-123): ...
refactor(PROJ-123): ...
chore: ...       # no Jira key
```

Never `WIP`, `small fix`, `updates`.

---

## MR Labels

Apply only labels that exist in the project's list. A failed fetch or label step never blocks the MR — create it without labels.

**Type — exactly one**, judged from the diff. None fits (docs-only, chore) → no type label.

| Label | Diff… |
|-------|-------|
| `feature` | adds or extends behavior |
| `bugfix` | fixes incorrect behavior |
| `hotfix` | only if the user said "hotfix" or the branch starts with `hotfix/` |
| `refactoring` | restructures code, no behavior change |
| `tests` | touches only tests or test infra |
| `devops` | CI, deploy, infra, config |

**Lifecycle — added on top of the type**, decided by path, not judgment: diff touches `docs/adr/**` → `ADR`, `docs/sdd/**` → `SDD`. These MRs live longer by design; the label lets merge-time metrics exclude them. Missing in the project → create it (the only labels this skill ever creates; on failure skip it and print the error line):

```bash
glab label create --name ADR --color "#6F42C1" --description "Architecture Decision Record. Long review lifecycle; exclude from time-to-merge."
glab label create --name SDD --color "#1F78D1" --description "Software Design Document. Long review lifecycle; exclude from time-to-merge."
```

**Never apply:** labels that claim how the work was done (e.g. `ai`), that trigger deploys or block merging (e.g. `DO NOT MERGE`), that belong to CI or QA (coverage, QA status), or that are named after a Jira key. Any label outside these lists: suggest only (step 6).

---

## MR Description

**Job: give reviewers context they can't get from the title, Jira link, or diff. If a sentence could be derived from any of those, delete it.**

Structure:

1. **Jira link line** if the branch has a Jira key (`$JIRA_BASE_URL`, e.g. `https://acme.atlassian.net`):
   `[PROJ-123]($JIRA_BASE_URL/browse/PROJ-123)`
2. **1–3 sentence product summary** — *only if title doesn't say it all.* Skip for cleanups, flag removals, dep bumps.
3. **Reviewer notes** (bullets) — non-obvious things a reviewer would miss: silent behavioral changes, deploy ordering / migration coupling / flag state, follow-ups, intentional gaps, things that look like regressions but aren't.

Omit any section without content. Two-line descriptions are fine.

### Do NOT include

- File-count tables, "N files changed" — GitLab shows this.
- Diff narration ("added function X to file Y").
- Test plan / checklist sections.
- Local verification status ("lint passes", "tests pass locally", "typecheck clean", "ran build"). CI is the source of truth — this is noise.
- Restating Jira — link, don't paraphrase.
- "Generated by" / "Co-authored by Claude".
- Title-restating filler.

### Examples

**Good — flag cleanup:**

```markdown
[PROJ-101](https://acme.atlassian.net/browse/PROJ-101)

Fully rolled out as of 2026-04-28. No runtime change.
```

**Good — behavior change worth knowing:**

```markdown
[PROJ-102](https://acme.atlassian.net/browse/PROJ-102)

Switches the orders-api client from per-call retries to a shared retry budget so a flapping downstream can't blow up p99.

- Budget defaults match previous client-side defaults; no env change.
- Metric `orders_client_retries_total` → `orders_client_retry_budget_consumed_ratio`. Dashboard update in [PROJ-103](https://acme.atlassian.net/browse/PROJ-103), shipping right after.
- New client logs warning (not error) when budget exhausted — intentional, alerts cover the ratio.
```

**Good — small refactor:**

```markdown
[PROJ-104](https://acme.atlassian.net/browse/PROJ-104)

Extracts the onboarding step resolver into its own module so it can be unit-tested without booting the action layer.
```

**Bad:**

```markdown
## Summary
| Component | Change |
|-----------|--------|
| Router    | 3 files |

This MR refactors the payment routing engine to support multi-currency
fallback chains. The previous implementation failed silently when...
```

(All of it derives from diff/title/Jira.)

---

## Length heuristic

| Change | Description shape | Total |
|--------|-------------------|-------|
| Trivial (flag, typo, dep bump) | Jira link + maybe 1 sentence | ~2 lines |
| Standard feature | Jira link + 1–2 sentence summary + 0–3 notes | ~6–10 lines |
| Cross-cutting / behavior change | Jira link + paragraph + bulleted notes | ≤15 lines |

>15 lines → MR is too big, split it. Trunk-based development: short branches, small MRs.
