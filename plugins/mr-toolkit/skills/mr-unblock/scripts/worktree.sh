#!/usr/bin/env bash
# Get a checkout of an MR's source branch to fix it in, cloning the repo on demand.
#
# Usage: worktree.sh <repo-path> <source-branch> <iid>
#   e.g. worktree.sh acme/web-app feat-foo 1234
#
# Prints JSON: {path, clone, base_sha, branch, in_place}.
#   in_place=true  → the user's own clone has this branch checked out, clean and equal to
#                    origin: fix right there (deps already installed). Never remove it.
#   in_place=false → a detached worktree under $MR_TOOLKIT_WORKTREES. Detached on purpose:
#                    the user's clone may have the branch checked out (dirty or ahead), and
#                    `worktree add <branch>` would refuse or fight it.
# Push either way with
#   git push --force-with-lease=refs/heads/<branch>:<base_sha> origin HEAD:refs/heads/<branch>
#
# Env:
#   GITLAB_HOST             default: glab's configured host
#   MR_TOOLKIT_CLONE_ROOT   where existing clones are searched (depth 3) and new ones
#                           created as <root>/<repo-path>. default: ~/workspace
#   MR_TOOLKIT_WORKTREES    default: ~/.cache/mr-toolkit/worktrees
set -euo pipefail

repo="${1:?repo path}"; branch="${2:?source branch}"; iid="${3:?iid}"
host="${GITLAB_HOST:-$(glab config get host 2>/dev/null || echo gitlab.com)}"
root="${MR_TOOLKIT_CLONE_ROOT:-$HOME/workspace}"
wt_root="${MR_TOOLKIT_WORKTREES:-$HOME/.cache/mr-toolkit/worktrees}"

# Serialize per repo: parallel fix agents on one clone would race on git's index/fetch
# locks (and on the initial clone). mkdir is atomic; macOS has no flock.
# ponytail: a SIGKILLed run leaves the lock behind; rmdir it by hand (path in the error).
mkdir -p "$wt_root"
lock="$wt_root/.lock-${repo//\//-}"
for ((i = 0; i < 300; i++)); do mkdir "$lock" 2>/dev/null && break; sleep 1; done
(( i < 300 )) || { echo "timed out waiting for $lock; remove it if stale" >&2; exit 1; }
trap 'rmdir "$lock"' EXIT

# Existing clone = any repo under $root whose origin ends in <host>[:/]<repo>(.git)
clone=""
while IFS= read -r gitdir; do
  dir="$(dirname "$gitdir")"
  url="$(git -C "$dir" remote get-url origin 2>/dev/null || true)"
  if [[ "$url" =~ ${host}[:/]([0-9]+/)?${repo}(\.git)?$ ]]; then clone="$dir"; break; fi
done < <(find "$root" -maxdepth 3 -name .git -type d -not -path '*/node_modules/*' 2>/dev/null)

if [[ -z "$clone" ]]; then
  clone="$root/$repo"
  git clone --quiet "git@$host:$repo.git" "$clone" >&2
fi

git -C "$clone" fetch --quiet origin "+refs/heads/$branch:refs/remotes/origin/$branch"
remote_sha="$(git -C "$clone" rev-parse "origin/$branch")"

emit() {
  jq -n --arg path "$1" --arg clone "$clone" --arg branch "$branch" --arg sha "$remote_sha" \
    --argjson in_place "$2" \
    '{path: $path, clone: $clone, base_sha: $sha, branch: $branch, in_place: $in_place}'
}

if [[ "$(git -C "$clone" branch --show-current)" == "$branch" \
      && -z "$(git -C "$clone" status --porcelain)" \
      && "$(git -C "$clone" rev-parse HEAD)" == "$remote_sha" ]]; then
  emit "$clone" true
  exit 0
fi

path="$wt_root/${repo//\//-}-$iid"
if [[ -e "$path" ]]; then
  echo "worktree path already exists: $path — inspect it, then 'git -C $clone worktree remove $path'" >&2
  exit 1
fi
git -C "$clone" worktree add --quiet --detach "$path" "origin/$branch"
emit "$path" false
