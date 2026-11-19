---
name: mr-ready
description: List the user's open authored GitLab MRs where the AUTHOR has the next action — either ready to merge or blocked on something the author can fix (rebase, CI, discussions). Excludes MRs waiting on reviewers (use mr-nudge for those). Use when the user asks "what's ready to merge", "what MRs can I move on with", "ready to ship", "what do I need to do on my MRs", "what's actionable", "show me mergeable MRs". Output is a two-section scannable table — Ready and Blocked-on-me — sorted oldest-first, no JSON dump.
---

# MR Actionable

## What this skill does

Lists the user's open authored MRs on GitLab where they have the next move. Read-only. Two buckets:

- **Ready** — `detailed_merge_status == "mergeable"`. Just hit merge.
- **Blocked-on-me** — author-actionable blockers: rebase, CI, discussions, requested changes, etc.

Excluded: drafts, MRs in archived projects, MRs waiting on reviewer approval (`not_approved`), and ephemeral states (`unchecked`, `ci_still_running`, `approvals_syncing`). For "waiting on reviewer" → use `mr-nudge`.

## Workflow

### 1. Fetch

```bash
scripts/list_actionable.sh
```

Returns `{ ready: [...], blocked: [...] }`. Each MR includes `iid`, `title`, `web_url`, `hours_open`, `hours_since_update`, `detailed_merge_status`, `has_conflicts`, `blocking_discussions_resolved`, and an `action` hint (`merge`, `rebase`, `fix-ci`, `resolve-discussions`, `address-feedback`, `push-commits`, `fix-external-checks`).

### 2. Present

Two tables, ready first. If a bucket is empty, omit its section entirely.

**✅ Ready to merge (N)**
| Age | Repo !iid | Title |
|---|---|---|

**🔧 Blocked on you (N)**
| Age | Repo !iid | Title | Action |
|---|---|---|---|

Where:
- **Age** — `hours_open`: `<24h` → `Nh`, otherwise `Nd` (round down).
- **Repo !iid** — extract the path from `web_url` (between the GitLab host and `/-/merge_requests/`); link to `web_url`.
- **Title** — truncate to ~60 chars with `…` if longer.
- **Action** — the `action` field, plain text (e.g. `rebase`, `fix-ci`).

Above the tables, give a one-liner: `N ready to merge · M waiting on you.` If both are empty: "Nothing actionable right now — your authored MRs are all either drafts or waiting on review."

#### Sample rendered output

```text
2 ready to merge · 3 blocked on you.

**✅ Ready to merge (2)**

| Age | Repo !iid | Title |
|---|---|---|
| 6d | [acme/infra-alerts !13](https://gitlab.example.com/acme/infra-alerts/-/merge_requests/13) | chore: add/update .coderabbit.yaml |
| 3d | [acme/api-spec !44](https://gitlab.example.com/acme/api-spec/-/merge_requests/44) | feat: document /v2/invoices endpoint |

**🔧 Blocked on you (3)**

| Age | Repo !iid | Title | Action |
|---|---|---|---|
| 2d | [acme/event-ingestor !2](https://gitlab.example.com/acme/event-ingestor/-/merge_requests/2) | feat: add retry logic | fix-ci |
| 1d | [acme/search-indexer !26](https://gitlab.example.com/acme/search-indexer/-/merge_requests/26) | refactor: extract query parser | resolve-discussions |
| 18h | [acme/admin !421](https://gitlab.example.com/acme/admin/-/merge_requests/421) | chore: update deps | rebase |
```

### 3. After-listing actions — only if the user asks

Don't proactively offer these. Wait for the user to direct.

- "merge them all" → destructive; ALWAYS confirm explicitly before running `glab mr merge`.
- "show diff for !N" → `glab mr diff` or `glab mr view`.
- "rebase the rebase ones" → `glab mr rebase --merge-request <iid>` per MR; confirm first.
- "what's blocking !N" → re-fetch that MR's `detailed_merge_status` and explain.

## Environment

- `glab` authenticated to your GitLab host. Script uses `$GITLAB_HOST`, else glab's configured host.
- Runs from any directory.

## Don't

- **Don't merge anything.** This is a listing skill. Even if the user says "ready to merge" — they're asking what's ready, not "merge them now". Wait for explicit "merge them" / "merge !N" before acting.
- **Don't rebase, retry CI, or push commits.** All of those are destructive. List them; let the user direct.
- **Don't include MRs waiting on review.** Those belong to `mr-nudge`. If the user wants both views, run both skills.
- **Don't dump raw JSON.** Render tables.
- **Don't show the full `detailed_merge_status` enum value** in the user-facing table — use the friendlier `action` hint.
