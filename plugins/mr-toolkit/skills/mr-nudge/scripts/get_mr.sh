#!/usr/bin/env bash
# Fetch a single GitLab MR's details + reviewers, matching the shape from
# list_my_mrs.sh. Useful when the user references one specific MR.
#
# Usage:
#   get_mr.sh <mr_url>
#   get_mr.sh <namespace/project>!<iid>
#
# Env:
#   GITLAB_HOST   default: glab's configured host
#   EMAIL_DOMAIN  default: domain of `git config user.email`
set -euo pipefail

GITLAB_HOST="${GITLAB_HOST:-$(glab config get host 2>/dev/null || echo gitlab.com)}"
EMAIL_DOMAIN="${EMAIL_DOMAIN:-$(git config user.email 2>/dev/null | sed -n 's/.*@//p')}"

for cmd in glab jq python3; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "$cmd not found — install it before running this script" >&2
    exit 1
  fi
done

if [[ $# -lt 1 ]]; then
  echo "usage: $0 <mr_url|namespace/project!iid>" >&2
  exit 2
fi

input="$1"

if [[ "$input" =~ ^https?://[^/]+/(.+)/-/merge_requests/([0-9]+)([/?#].*)?$ ]]; then
  path="${BASH_REMATCH[1]}"
  iid="${BASH_REMATCH[2]}"
elif [[ "$input" =~ ^(.+)!([0-9]+)$ ]]; then
  path="${BASH_REMATCH[1]}"
  iid="${BASH_REMATCH[2]}"
else
  echo "could not parse '$input' — pass a full MR URL or 'namespace/project!iid'" >&2
  exit 2
fi

if [[ -z "$path" || ! "$iid" =~ ^[0-9]+$ ]]; then
  echo "invalid MR identifier '$input' — path must be non-empty and iid must be numeric" >&2
  exit 2
fi

encoded_path=$(python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.argv[1], safe=""))' "$path")

GITLAB_HOST="$GITLAB_HOST" glab api "projects/$encoded_path/merge_requests/$iid" \
  | jq --arg domain "$EMAIL_DOMAIN" --argjson now "$(date +%s)" '
      {
        iid, project_id, title, web_url,
        created_at, updated_at,
        hours_since_update: (($now - (.updated_at | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 3600 | floor),
        hours_open:        (($now - (.created_at | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 3600 | floor),
        draft, blocking_discussions_resolved, has_conflicts, user_notes_count,
        reviewers: [.reviewers[] | {
          username, name,
          email: (if ((.public_email // "") != "") then .public_email else (.username + "@" + $domain) end)
        }]
      }
    '
