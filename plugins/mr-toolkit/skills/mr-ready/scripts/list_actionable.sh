#!/usr/bin/env bash
# List the user's open authored MRs where the AUTHOR has the next action —
# either ready to merge, or blocked on something the author can fix.
# Excludes MRs waiting on reviewers (use mr-nudge for that).
#
# Output: JSON object grouped by bucket:
#   {
#     "ready":   [...],   # detailed_merge_status == "mergeable"
#     "blocked": [...]    # author-actionable blockers (rebase, CI, discussions, etc.)
#   }
#
# Excluded entirely:
#   - not_approved (waiting on reviewer), draft, unchecked, ci_still_running, approvals_syncing
#   - MRs in archived projects (can't be merged anyway)
#
# Each MR has:
#   iid, project_id, title, web_url,
#   created_at, updated_at, hours_open, hours_since_update,
#   detailed_merge_status, merge_status,
#   has_conflicts, blocking_discussions_resolved,
#   user_notes_count, upvotes, downvotes, labels, source_branch, author, author_username,
#   action      # one-word hint of what to do (merge, rebase, fix-ci, resolve-discussions, etc.)
#
# Env:
#   GITLAB_HOST      default: glab's configured host
#   PER_PAGE         default: 50
#   INCLUDE_WAITING  set to 1 to keep not_approved / ci_still_running / unchecked MRs in
#                    "blocked" — GitLab reports only the first blocker, so these may also
#                    have red CI, conflicts or open threads (used by mr-inbox)
#   SCOPE            default: created_by_me. assigned_to_me lists MRs assigned to the user,
#                    e.g. bot-authored ones they own (used by mr-inbox)
set -euo pipefail

GITLAB_HOST="${GITLAB_HOST:-$(glab config get host 2>/dev/null || echo gitlab.com)}"
PER_PAGE="${PER_PAGE:-100}"
INCLUDE_WAITING="${INCLUDE_WAITING:-0}"
SCOPE="${SCOPE:-created_by_me}"

if ! command -v glab >/dev/null 2>&1; then
  echo "glab not found — install via 'brew install glab' and authenticate to $GITLAB_HOST" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found — install via 'brew install jq'" >&2
  exit 1
fi

base=$(GITLAB_HOST="$GITLAB_HOST" glab api --paginate "merge_requests?scope=$SCOPE&state=opened&non_archived=true&per_page=$PER_PAGE" \
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

jq --argjson now "$(date +%s)" --arg include_waiting "$INCLUDE_WAITING" '
      def shape:
        {
          iid, project_id, title, web_url,
          created_at, updated_at,
          hours_open:         (($now - (.created_at | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 3600 | floor),
          hours_since_update: (($now - (.updated_at | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 3600 | floor),
          detailed_merge_status, merge_status,
          has_conflicts, blocking_discussions_resolved,
          user_notes_count, upvotes, downvotes,
          labels, source_branch,
          author: .author.name, author_username: .author.username,
          action: (
            .detailed_merge_status as $s
            | if $s == "mergeable" then "merge"
              elif $s == "need_rebase" or $s == "conflict" or $s == "broken_status" then "rebase"
              elif $s == "ci_must_pass" or $s == "pipeline_must_succeed" then "fix-ci"
              elif $s == "discussions_not_resolved" then "resolve-discussions"
              elif $s == "requested_changes" then "address-feedback"
              elif $s == "commits_status" then "push-commits"
              elif $s == "external_status_checks" then "fix-external-checks"
              elif $s | IN("not_approved", "unchecked", "ci_still_running") then "check-blockers"
              else $s
              end
          )
        };

      def is_skipped:
        .draft == true
        or (.detailed_merge_status == "approvals_syncing")
        or ((.detailed_merge_status | IN("not_approved", "unchecked", "ci_still_running")) and $include_waiting != "1");

      [.[] | select(is_skipped | not) | shape]
      | {
          ready:   [.[] | select(.detailed_merge_status == "mergeable")] | sort_by(-.hours_open),
          blocked: [.[] | select(.detailed_merge_status != "mergeable")] | sort_by(-.hours_open)
        }
    ' <<<"$base"
