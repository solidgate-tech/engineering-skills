---
name: mr-to-review
description: Show open GitLab MRs that need the user's review action. Use when the user asks "what do I need to review", "my review queue", "MRs waiting on me", "what reviews are pending", "anything to review", or similar. Lists MRs where the user is a reviewer AND has not already approved, sorted oldest-first, with author / age / conflict / discussion-resolved status. Drafts, archived-project MRs, and MRs the user has already approved are always excluded — this is the *pending* review queue, not the full reviewer list. Output is a compact scannable table — no actions, just visibility.
---

# My Review Queue

## What this skill does

Lists open GitLab MRs waiting on the user's review. Read-only. The output is meant to give the user a fast picture of their pending review load.

## Workflow

### 1. Fetch

```bash
scripts/list_review_queue.sh
```

Always excluded: drafts, MRs in archived projects, and MRs you've already approved (your review action is done — go merge them).

JSON shape per MR (sorted oldest-first by `hours_open`):
- `iid`, `project_id`, `title`, `web_url`
- `author: {username, name}`
- `hours_open`, `hours_since_update`
- `has_conflicts`, `blocking_discussions_resolved`
- `user_notes_count`, `upvotes`, `downvotes`
- `source_branch`, `target_branch`
- `additions`, `deletions`, `files_changed` — diff stats from one extra API call per MR. Set `SKIP_LOC=1` to skip those calls if the queue is large and you don't need LOC.

### 2. Present

Render a compact table sorted oldest-first. Default columns:

| Age | Author | Repo !iid | Title | LOC | Notes |
|---|---|---|---|---|---|

Where:
- **Age** — `hours_open` formatted humanely: `<24h` as `Nh`, `>=24h` as `Nd` (round down).
- **Author** — `author.name` (just the first name is fine if names are long).
- **Repo !iid** — extract from `web_url` (the path between the GitLab host and `/-/merge_requests/`); make it a clickable link to `web_url`.
- **Title** — truncate to ~60 chars with `…` if longer.
- **LOC** — `+{additions} −{deletions}` in `{files_changed}f` format (e.g. `+42 −3 (5f)`). Show `?` if any field is null.
- **Notes** — small badges only when relevant: `⚠️ conflicts`, `🗣 N comments` (if `user_notes_count > 0`), `🚫 unresolved` (if `blocking_discussions_resolved == false`), `👍N / 👎N` (if non-zero).

Above the table, give a one-line summary: `N MRs to review — oldest is Xd, newest is Yh.` If the result is empty, say so clearly: "Inbox zero — nothing assigned to you for review." and stop.

#### Sample rendered output

```text
3 MRs to review — oldest is 4d, newest is 2h.

| Age | Author | Repo !iid | Title | LOC | Notes |
|---|---|---|---|---|---|
| 4d | Alex D. | [acme/metrics-exporter !3](https://gitlab.example.com/acme/metrics-exporter/-/merge_requests/3) | chore: bump terraform version | +12 −3 (2f) | 🚫 unresolved |
| 18h | Sam K. | [acme/auth-service !207](https://gitlab.example.com/acme/auth-service/-/merge_requests/207) | feat: add pagination | +148 −12 (5f) | 🗣 4 comments |
| 2h | Jordan M. | [acme/config-loader !7](https://gitlab.example.com/acme/config-loader/-/merge_requests/7) | refactor: split config loader | +88 −41 (3f) | ⚠️ conflicts |
```

### 3. Common follow-ups (don't pre-empt — just be ready)

The user might next ask:
- "open the oldest" / "show me #N" → open URL or `glab mr view`
- "what's in <repo> !<iid>" → fetch diff with `glab api projects/.../merge_requests/<iid>/changes` or `glab mr diff`
- "anything trivial?" → look for small diffs, single-file changes, identical-title batch MRs
- "filter to <repo>" / "filter to <author>" → re-filter the existing JSON, don't re-fetch

These are not part of this skill's core job. Just present the queue and stop.

## Environment

- `glab` authenticated to your GitLab host. Script auto-detects username via `glab api user`.
- Override with `GITLAB_USERNAME=<user>` or `GITLAB_HOST=<host>` if needed.

## Don't

- **Don't take action.** This is a read-only listing skill. Don't approve, comment, or merge — even if the user hints at it. They'll ask explicitly.
- **Don't include drafts.** Ever. They're not ready for review.
- **Don't dump raw JSON** — render a table. The user wants to scan, not parse.
- **Don't show full URLs in the table** — use the linked `repo !iid` form. Full URLs are noise.
- **Don't show description bodies, diff stats, or pipeline trees.** Title + key flags is the right amount of info.
