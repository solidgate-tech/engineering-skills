#!/usr/bin/env bash
# List the current user's open GitLab MRs with reviewers, in a shape ready
# for nudging via Slack DM. Filters out drafts and MRs in archived projects.
#
# Output: JSON array. Each MR has:
#   iid, project_id, title, web_url, created_at, updated_at,
#   hours_since_update, hours_open,
#   blocking_discussions_resolved, has_conflicts, user_notes_count,
#   reviewers: [{username, name, email}]
#
# Reviewer email falls back to "<username>@$EMAIL_DOMAIN" when public_email is empty.
#
# Env:
#   GITLAB_HOST   default: glab's configured host
#   EMAIL_DOMAIN  default: domain of `git config user.email`
#   PER_PAGE      default: 50
#   INCLUDE_DRAFTS  set to 1 to include drafts
set -euo pipefail

GITLAB_HOST="${GITLAB_HOST:-$(glab config get host 2>/dev/null || echo gitlab.com)}"
EMAIL_DOMAIN="${EMAIL_DOMAIN:-$(git config user.email 2>/dev/null | sed -n 's/.*@//p')}"
PER_PAGE="${PER_PAGE:-100}"
INCLUDE_DRAFTS="${INCLUDE_DRAFTS:-0}"

if ! command -v glab >/dev/null 2>&1; then
  echo "glab not found — install via 'brew install glab' and authenticate to $GITLAB_HOST" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found — install via 'brew install jq'" >&2
  exit 1
fi

draft_filter='select(.draft == false)'
if [[ "$INCLUDE_DRAFTS" == "1" ]]; then
  draft_filter='.'
fi

base=$(GITLAB_HOST="$GITLAB_HOST" glab api --paginate "merge_requests?scope=created_by_me&state=opened&non_archived=true&per_page=$PER_PAGE" \
  | jq -s '[add[]]')

# Client-side archived-project filter: GitLab's MergeRequestsFinder doesn't
# always respect non_archived=true when scope=created_by_me, so we look up each
# unique project's archived flag in parallel and drop matching MRs.
if [[ "$(jq 'length' <<<"$base")" != "0" ]]; then
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  for pid in $(jq -r '[.[].project_id] | unique | .[]' <<<"$base"); do
    (
      archived=$(GITLAB_HOST="$GITLAB_HOST" glab api "projects/$pid" 2>/dev/null | jq -r '.archived // false')
      jq -nc --arg id "$pid" --argjson a "$archived" '{($id): $a}' > "$tmpdir/$pid"
    ) &
  done
  wait
  archived_map=$(jq -cs 'add // {}' "$tmpdir"/*)
  base=$(jq --argjson m "$archived_map" '[.[] | select($m[(.project_id|tostring)] != true)]' <<<"$base")
fi

jq --arg domain "$EMAIL_DOMAIN" --argjson now "$(date +%s)" "
      [.[] | $draft_filter | {
        iid, project_id, title, web_url,
        created_at, updated_at,
        hours_since_update: ((\$now - (.updated_at | sub(\"\\\\.[0-9]+Z$\"; \"Z\") | fromdate)) / 3600 | floor),
        hours_open:        ((\$now - (.created_at | sub(\"\\\\.[0-9]+Z$\"; \"Z\") | fromdate)) / 3600 | floor),
        draft, blocking_discussions_resolved, has_conflicts, user_notes_count,
        reviewers: [.reviewers[] | {
          username, name,
          email: (if ((.public_email // \"\") != \"\") then .public_email else (.username + \"@\" + \$domain) end)
        }]
      }]
    " <<<"$base"
