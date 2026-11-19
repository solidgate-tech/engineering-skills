---
name: mr-nudge
description: Nudges reviewers on the user's open GitLab merge requests via personal Slack DMs. Use when the user wants to ping/remind/nudge/follow-up-with reviewers on their MRs — e.g. "nudge my MR reviewers", "remind people to review my MRs", "ping reviewers on stale MRs". The skill lists the user's open MRs, groups them by reviewer, looks each reviewer up in Slack by email, shows the planned DMs once, and on approval sends a personal DM (not a channel post) to each. With MR_NUDGE_CONFIRM=0 it skips the preview and sends immediately (fire-and-forget). Output is a one-line receipt per DM.
---

# Nudge MR Reviewers

## What this skill does

Sends personal Slack DMs to reviewers of the user's open GitLab MRs. By default it shows the planned DMs (recipient, MR count, message) once and sends after a single approval. If `MR_NUDGE_CONFIRM=0` is set, the user has opted out of the preview: when invoked, just send.

GitLab host from `$GITLAB_HOST` (else glab's configured host); reviewer GitLab username → `<username>@$EMAIL_DOMAIN` for Slack lookup when the GitLab profile has no public email.

## Default behavior — when invoked with no specifics

Nudge **every reviewer on every open authored MR**, one DM per reviewer (grouping all their MRs into a single message). One preview, then send (or just send with `MR_NUDGE_CONFIRM=0`).

## Variants — when the user specified scope

Match these from the invoking message; otherwise use the default above.

- **Single MR** — user gave an MR URL or said "the X MR". Run `scripts/get_mr.sh <ref>`. Nudge only that MR's reviewers.
- **Stale only** — user said "stale", "old", "haven't been touched". Drop MRs with `hours_since_update < 24` (or `< 48` for "really stale").
- **Specific people** — user named reviewers ("just Alex", "Alex and Sam"). Match by name/username; nudge only those.

## Workflow

### 1. Fetch

```bash
scripts/list_my_mrs.sh                    # all my open authored MRs (no drafts, no archived projects)
scripts/get_mr.sh <url|namespace/proj!iid>  # one specific MR
```

JSON shape per MR: `iid`, `title`, `web_url`, `hours_open`, `hours_since_update`, `has_conflicts`, `user_notes_count`, `reviewers: [{username, name, email}]`.

### 2. Filter & group

- Drop MRs with `reviewers: []`.
- Apply variant filters (stale / specific people).
- **Group by reviewer**: one DM per person, listing all their MRs — never multiple DMs to the same person in one batch.
- Skip anyone already pinged earlier in **this session**, unless the user explicitly says "again".

### 3. Look up each reviewer in Slack

Search with the Slack MCP server's `slack_search_users` tool using the reviewer's `email`. Email search often finds nothing. Then search by the surname from `name` and keep the result whose email matches. That match's user ID = the `channel_id` for the DM. If neither search finds a match, report it in the receipt and skip — don't guess.

Read the match's status with the Slack MCP server's `slack_read_user_profile` tool. If it says they're away ("day off", "Off sick", "Vacationing", "OOO"), don't DM them. Report `🌴 <name> — away (<status>), not nudged; swap the reviewer` in the receipt.

### 4. Compose & send

Send with the Slack MCP server's `slack_send_message` tool, passing `channel_id=<reviewer_user_id>`.

Tone: friendly, brief, casual, not pushy. Slack markdown: `*bold*`, `_italic_`, `<url|label>` for links. 1–6 lines.

**One MR**:

```text
Hey! Got a min to review this when you can?
<{web_url}|{repo_path} !{iid}>: {title}
🙏
```

**Multiple MRs same reviewer**:

```text
Hey! Got a few MRs waiting on you when you have a sec —
• <{web_url_1}|{repo_path_1} !{iid_1}>
• <{web_url_2}|{repo_path_2} !{iid_2}>
🙏
```

**If all titles are identical** (batch rollouts like CodeRabbit configs): say so once at the top and just list the repo+iid links — don't repeat the title 8 times.

```text
Hey! Got a batch of identical {short description} MRs waiting on you — should be quick rubber-stamps:
• <url|repo !iid>
• <url|repo !iid>
🙏
```

Context lines — add ONLY when the condition is true. Otherwise omit entirely:

- If `has_conflicts == true`: append "(has conflicts now, but the rest is reviewable)".
- If `hours_open >= 72` AND this person has not been pinged in the last 24h: include "been open a few days".
- If the user supplied their own context (e.g. "blocking launch"): include it verbatim in the body.

### 5. Receipt

After all DMs are sent, output a tight summary — one line per DM:

```text
✅ Alex Doe (11 MRs) → https://<workspace>.slack.com/...
✅ Sam Kim (5 MRs) → https://<workspace>.slack.com/...
⚠️  Jordan Lee — Slack lookup failed, skipped
```

That's the entire interaction: at most one preview, then the receipt. No follow-up questions.

## Environment

- `glab` authenticated to your GitLab host. Scripts use `$GITLAB_HOST`, else glab's configured host.
- Scripts run from any directory (use the GitLab API, no repo needed).
- Override email domain with `EMAIL_DOMAIN=<domain>` if needed.

## Don't

- **Don't ask more than once.** One preview, one approval. With `MR_NUDGE_CONFIRM=0`, no preview at all: send immediately on invocation.
- **Don't post to a channel.** DMs only.
- **Don't @-mention the recipient inside their own DM.** Redundant.
- **Don't send duplicate DMs** to the same person in one batch — group first.
- **Don't include MR descriptions, diff stats, or checklists.** Title + link is enough.
- **Don't re-ping someone already pinged earlier in this session** unless the user says "again".
