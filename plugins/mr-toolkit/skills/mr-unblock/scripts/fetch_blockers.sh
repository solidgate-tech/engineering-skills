#!/usr/bin/env bash
# Fetch all blockers for the MR on the current branch (or $MR_IID in $MR_REPO).
# Outputs a JSON object:
#   mr          – core MR fields
#   pipeline    – { status, web_url, failed_jobs: [{id, name, web_url}] }
#   discussions – [ { id, resolved, author, first_line, notes_count } ]
#   approvals   – { approved, approvals_left, approved_by: [username] }
#
# Env:
#   GITLAB_HOST   default: glab's configured host
#   MR_IID        override MR number (skip auto-detect)
#   MR_REPO       repo path, e.g. "acme/web-app" (required when MR_IID is set)
set -euo pipefail

GITLAB_HOST="${GITLAB_HOST:-$(glab config get host 2>/dev/null || echo gitlab.com)}"

if ! command -v glab >/dev/null 2>&1; then
  echo '{"error":"glab not found"}' >&2; exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo '{"error":"jq not found"}' >&2; exit 1
fi

# ── Resolve MR ──────────────────────────────────────────────────────────────
if [[ -n "${MR_IID:-}" && -n "${MR_REPO:-}" ]]; then
  repo="$MR_REPO"
else
  branch=$(git branch --show-current 2>/dev/null || echo "")
  if [[ -z "$branch" ]]; then
    echo '{"error":"not in a git repo"}' >&2; exit 1
  fi

  remote_url=$(git remote get-url origin 2>/dev/null || echo "")
  # Use python3 for portability: BSD sed (macOS) does not support GNU 't' branch label
  repo=$(python3 -c "
import sys, re
url = sys.argv[1].strip()
# strip scheme+host (https://host/, ssh://git@host[:port]/) or scp-style (git@host:)
path = re.sub(r'^[a-zA-Z][a-zA-Z0-9+.-]*://[^/]+/', '', url)
if path == url:
    path = re.sub(r'^[^/]*?@[^:/]+:', '', url)
path = re.sub(r'\.git$', '', path).strip('/')
# full namespace: everything after the host, minus .git — may nest arbitrarily deep
print(path if '/' in path else '')
" "$remote_url")

  if [[ -z "$repo" ]]; then
    echo '{"error":"could not parse repo from remote URL: '"$remote_url"'"}' >&2; exit 1
  fi

  encoded_repo_tmp=$(python3 -c "import sys; print(sys.argv[1].replace('/', '%2F'))" "$repo")
  encoded_branch=$(python3 -c "import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1]))" "$branch")

  mr_json=$(GITLAB_HOST="$GITLAB_HOST" glab api \
    "projects/$encoded_repo_tmp/merge_requests?source_branch=$encoded_branch&state=opened" \
    2>/dev/null || echo "[]")
  MR_IID=$(echo "$mr_json" | jq -r '.[0].iid // empty')

  if [[ -z "$MR_IID" ]]; then
    echo '{"error":"no open MR found for current branch"}' >&2; exit 1
  fi
fi

encoded_repo=$(python3 -c "import sys; print(sys.argv[1].replace('/', '%2F'))" "$repo")
base="projects/$encoded_repo/merge_requests/$MR_IID"

# ── Fetch in parallel ────────────────────────────────────────────────────────
tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

GITLAB_HOST="$GITLAB_HOST" glab api "$base?include_diverged_commits_count=true" > "$tmpdir/mr.json" &
pid_mr=$!
GITLAB_HOST="$GITLAB_HOST" glab api "$base/discussions?per_page=100" > "$tmpdir/discussions.json" &
pid_disc=$!
GITLAB_HOST="$GITLAB_HOST" glab api "$base/approvals" > "$tmpdir/approvals.json" &
pid_appr=$!

# wait on each PID individually — bare `wait` masks a failed child
for spec in "mr:$pid_mr" "discussions:$pid_disc" "approvals:$pid_appr"; do
  if ! wait "${spec#*:}"; then
    echo '{"error":"failed to fetch '"${spec%%:*}"' for '"$repo"'!'"$MR_IID"'"}' >&2; exit 1
  fi
done

mr_data=$(cat "$tmpdir/mr.json")
discussions_data=$(cat "$tmpdir/discussions.json")
approvals_data=$(cat "$tmpdir/approvals.json")

# ── Pipeline: prefer the MR merge pipeline over the branch pipeline ──────────
# The MR merge pipeline runs on refs/merge-requests/<iid>/merge and is the one
# that actually gates merging. The branch pipeline can be green while the merge
# pipeline is failed (e.g. merge conflicts introduce new lint/test failures).
#
# Strategy:
#   1. Query merge_requests/<iid>/pipelines — these are MR-associated pipelines.
#      Pick the latest one whose ref starts with "refs/merge-requests/" (detached
#      merge pipeline). If none exists, fall back to the latest MR pipeline of
#      any ref (which may be a branch pipeline from an external trigger).
#   2. Walk into child/downstream pipelines via bridges to collect ALL failed jobs,
#      since monorepos often chain parent→child pipelines (each app as a bridge target).

mr_pipelines=$(GITLAB_HOST="$GITLAB_HOST" glab api \
  "$base/pipelines?per_page=20" 2>/dev/null || echo "[]")

# Prefer the most recent merge-ref pipeline; fall back to the most recent any-ref pipeline.
pipeline_data=$(echo "$mr_pipelines" | jq '
  (map(select(.ref | startswith("refs/merge-requests/"))) | sort_by(.id) | reverse | .[0])
  // (sort_by(.id) | reverse | .[0])
  // {}')
pipeline_id=$(echo "$pipeline_data" | jq -r '.id // empty')

# Collect failed jobs from a pipeline, recursively walking child pipelines via bridges.
# ponytail: child pipelines are queried against the parent's $encoded_repo, so
# cross-project downstreams resolve to the wrong project (their jobs are skipped,
# and any trace/retry the skill suggests would target the parent). Fine for
# same-project child pipelines, the common case. To lift: thread each
# bridge's .downstream_pipeline.project_id through the recursion and store it per
# failed-job record for `glab ci trace`/`retry`.
collect_failed_jobs() {
  local pid="$1"
  local jobs failed bridges child_pid

  jobs=$(GITLAB_HOST="$GITLAB_HOST" glab api \
    "projects/$encoded_repo/pipelines/$pid/jobs?per_page=100" 2>/dev/null || echo "[]")

  # Direct failed jobs (non-bridge)
  failed=$(echo "$jobs" | jq '[.[] | select(.status == "failed") | {id, name, status, web_url, failure_reason}]')

  # Walk failed bridges into child pipelines
  bridges=$(GITLAB_HOST="$GITLAB_HOST" glab api \
    "projects/$encoded_repo/pipelines/$pid/bridges?per_page=100" 2>/dev/null || echo "[]")

  while IFS= read -r child_pid; do
    [[ -z "$child_pid" || "$child_pid" == "null" ]] && continue
    child_failed=$(collect_failed_jobs "$child_pid")
    failed=$(jq -n --argjson a "$failed" --argjson b "$child_failed" '$a + $b')
  done < <(echo "$bridges" | jq -r '.[] | select(.status == "failed") | .downstream_pipeline.id // empty')

  echo "$failed"
}

failed_jobs="[]"
if [[ -n "$pipeline_id" && "$pipeline_id" != "null" ]]; then
  failed_jobs=$(collect_failed_jobs "$pipeline_id")
fi

# If the top-level pipeline status is success but child pipelines failed,
# report the true status as "failed".
effective_status=$(echo "$pipeline_data" | jq -r '.status // "unknown"')
if [[ "$effective_status" == "success" && "$(echo "$failed_jobs" | jq 'length')" -gt 0 ]]; then
  effective_status="failed"
fi

pipeline=$(jq -n \
  --argjson p "$pipeline_data" \
  --argjson fj "$failed_jobs" \
  --arg st "$effective_status" \
  '{status: $st, web_url: ($p.web_url // null), failed_jobs: $fj}')

# ── Discussions: unresolved, non-system notes only ──────────────────────────
discussions=$(echo "$discussions_data" | jq '
  [.[]
    | select(.notes[0].system == false)
    | select(.resolvable == true and .resolved == false)
    | {
        id,
        author: .notes[0].author.username,
        first_line: (.notes[0].body | split("\n")[0] | .[0:120]),
        notes_count: (.notes | length)
      }
  ]')

# ── Approvals ────────────────────────────────────────────────────────────────
approvals=$(echo "$approvals_data" | jq '{
  approved,
  approvals_left,
  approved_by: [.approved_by[].user.username]
}')

# ── Assemble ─────────────────────────────────────────────────────────────────
jq -n \
  --argjson mr "$mr_data" \
  --argjson pipeline "$pipeline" \
  --argjson discussions "$discussions" \
  --argjson approvals "$approvals" \
  '{
    mr: {
      iid: $mr.iid,
      title: $mr.title,
      web_url: $mr.web_url,
      state: $mr.state,
      draft: ($mr.draft // $mr.work_in_progress // false),
      source_branch: $mr.source_branch,
      target_branch: $mr.target_branch,
      detailed_merge_status: $mr.detailed_merge_status,
      has_conflicts: ($mr.has_conflicts // false),
      blocking_discussions_resolved: ($mr.blocking_discussions_resolved // true),
      diverged_commits_count: ($mr.diverged_commits_count // 0),
      repo: ($mr.web_url | capture("^https?://[^/]+/(?<p>.+)/-/merge_requests/") | .p)
    },
    pipeline: $pipeline,
    discussions: $discussions,
    approvals: $approvals
  }'
