#!/usr/bin/env bash
# List open GitLab MRs where the current user is assigned as a reviewer.
# Each MR is augmented with LOC diff stats — fetched in parallel per MR
# so the wall time is bounded by the slowest single /changes call (~1s),
# not the queue size.
#
# Output: JSON array, sorted oldest-first (highest hours_open first). Each MR has:
#   iid, project_id, title, web_url,
#   author: {username, name},
#   created_at, updated_at, hours_open, hours_since_update,
#   has_conflicts, blocking_discussions_resolved,
#   user_notes_count, upvotes, downvotes, labels,
#   source_branch, target_branch,
#   additions, deletions, files_changed  # null if the diff fetch fails
#
# Always excluded:
#   - drafts (not ready for review)
#   - MRs in archived projects (you can't merge them anyway)
#   - MRs the current user has already approved (your review action is done)
#
# Env:
#   GITLAB_HOST        default: glab's configured host
#   GITLAB_USERNAME    default: auto-detected via `glab api user`
#   PER_PAGE           default: 100  (GitLab REST cap)
#   SKIP_LOC           set to 1 to skip the per-MR /changes calls
#   LOC_PARALLELISM    default: 10   (concurrent /changes and /approvals calls)
set -euo pipefail

GITLAB_HOST="${GITLAB_HOST:-$(glab config get host 2>/dev/null || echo gitlab.com)}"
PER_PAGE="${PER_PAGE:-100}"
SKIP_LOC="${SKIP_LOC:-0}"
LOC_PARALLELISM="${LOC_PARALLELISM:-10}"

if ! command -v glab >/dev/null 2>&1; then
  echo "glab not found — install via 'brew install glab' and authenticate to $GITLAB_HOST" >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found — install via 'brew install jq'" >&2
  exit 1
fi

USERNAME="${GITLAB_USERNAME:-}"
if [[ -z "$USERNAME" ]]; then
  USERNAME=$(GITLAB_HOST="$GITLAB_HOST" glab api user 2>/dev/null | jq -r '.username // empty')
fi
if [[ -z "$USERNAME" ]]; then
  echo "Could not determine GitLab username — set GITLAB_USERNAME=<your username>" >&2
  exit 1
fi

base=$(GITLAB_HOST="$GITLAB_HOST" glab api --paginate "merge_requests?scope=all&reviewer_username=$USERNAME&state=opened&non_archived=true&per_page=$PER_PAGE" \
  | jq -s --argjson now "$(date +%s)" '
      [add[] | select(.draft == false) | {
        iid, project_id, title, web_url,
        author: {username: .author.username, name: .author.name},
        created_at, updated_at,
        hours_open:         (($now - (.created_at | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 3600 | floor),
        hours_since_update: (($now - (.updated_at | sub("\\.[0-9]+Z$"; "Z") | fromdate)) / 3600 | floor),
        has_conflicts, blocking_discussions_resolved,
        user_notes_count, upvotes, downvotes, labels,
        source_branch, target_branch
      }]
    ')

if [[ "$(jq 'length' <<<"$base")" == "0" ]]; then
  echo '[]'
  exit 0
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

# Client-side archived-project filter: the GitLab MergeRequestsFinder doesn't
# always respect non_archived=true when scope filters are applied, so we look
# up each unique project's archived flag in parallel and drop matching MRs.
project_ids=$(jq -r '[.[].project_id] | unique | .[]' <<<"$base")
mkdir -p "$tmpdir/projects"
for pid in $project_ids; do
  (
    archived=$(GITLAB_HOST="$GITLAB_HOST" glab api "projects/$pid" 2>/dev/null | jq -r '.archived // false')
    jq -nc --arg id "$pid" --argjson a "$archived" '{($id): $a}' > "$tmpdir/projects/$pid"
  ) &
done
wait
archived_map=$(jq -cs 'add // {}' "$tmpdir"/projects/*)
base=$(jq --argjson m "$archived_map" '[.[] | select($m[(.project_id|tostring)] != true)]' <<<"$base")

if [[ "$(jq 'length' <<<"$base")" == "0" ]]; then
  echo '[]'
  exit 0
fi

# Fan out per-MR /approvals (always) and /changes (unless SKIP_LOC). Each job
# emits the merged JSON only if the current user is NOT in approved_by; that
# way an MR I've already approved drops out before we waste a /changes call.
mkdir -p "$tmpdir/mrs"
idx=0
running=0
while IFS= read -r mr; do
  idx=$((idx + 1))
  (
    pid=$(jq -r '.project_id' <<<"$mr")
    iid=$(jq -r '.iid' <<<"$mr")
    approved_by_me=$(GITLAB_HOST="$GITLAB_HOST" glab api "projects/$pid/merge_requests/$iid/approvals" 2>/dev/null \
      | jq --arg u "$USERNAME" 'any(.approved_by[]?; .user.username == $u)' 2>/dev/null \
      || printf 'false')
    if [[ "$approved_by_me" == "true" ]]; then
      exit 0
    fi
    if [[ "$SKIP_LOC" == "1" ]]; then
      printf '%s' "$mr" > "$tmpdir/mrs/$idx"
      exit 0
    fi
    stats=$(GITLAB_HOST="$GITLAB_HOST" glab api "projects/$pid/merge_requests/$iid/changes" 2>/dev/null \
      | jq '{
          additions:     ([(.changes // [])[].diff | split("\n")[] | select(startswith("+") and (startswith("+++") | not))] | length),
          deletions:     ([(.changes // [])[].diff | split("\n")[] | select(startswith("-") and (startswith("---") | not))] | length),
          files_changed: ((.changes // []) | length)
        }' 2>/dev/null \
      || printf '%s' '{"additions":null,"deletions":null,"files_changed":null}')
    jq -nc --argjson m "$mr" --argjson s "$stats" '$m + $s' > "$tmpdir/mrs/$idx"
  ) </dev/null &
  running=$((running + 1))
  # ponytail: waits for the whole batch (bash 3.2 has no `wait -n`); a slow MR stalls its batch.
  if (( running >= LOC_PARALLELISM )); then
    wait
    running=0
  fi
done < <(jq -c '.[]' <<<"$base")
wait

shopt -s nullglob
files=("$tmpdir"/mrs/*)
if (( ${#files[@]} == 0 )); then
  echo '[]'
else
  cat "${files[@]}" | jq -s 'sort_by(-.hours_open)'
fi
