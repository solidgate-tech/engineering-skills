#!/usr/bin/env bash
# Blocks internal references from landing in this public repository.
#
# Built-in patterns cover anything that identifies internal infrastructure or
# people. Internal names that must not be listed in a public file (services,
# repos, teams) are supplied privately via LEAK_DENYLIST_FILE: one extended
# regex per line, '#' comments allowed. CI reads it from a secret.
#
# Usage: scripts/check-leaks.sh [path ...]   (default: all tracked files)
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

patterns=(
  # Internal hosts.
  'git\.solidgate\.com'
  '[A-Za-z0-9-]+\.solidgate\.(internal|local|io)'
  'solidgate\.(slack\.com|atlassian\.net)'
  # Code that assumes the company host (public URLs are allow-listed below).
  'solidgate\.com/'
  # Internal Jira project key; use PROJ-123 in examples.
  '(^|[^A-Za-z0-9])DEV-[0-9X]{3,}'
  # Company e-mail addresses.
  '[A-Za-z0-9._%+-]+@solidgate\.com'
  # Slack channel / user / team IDs.
  '(^|[^A-Za-z0-9])[CGDUTW]0[A-Z0-9]{8,10}([^A-Za-z0-9]|$)'
  # Cloud account identifiers.
  'arn:aws:[a-z0-9-]+:[a-z0-9-]*:[0-9]{12}:'
  '[0-9]{12}\.dkr\.ecr\.'
  # RFC 1918 addresses.
  '(^|[^0-9.])10\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}'
  '(^|[^0-9.])172\.(1[6-9]|2[0-9]|3[01])\.[0-9]{1,3}\.[0-9]{1,3}'
  '(^|[^0-9.])192\.168\.[0-9]{1,3}\.[0-9]{1,3}'
)

# Public addresses that are fine to mention; stripped before matching.
allow='(opensource|security)@solidgate\.com|https?://(www\.|docs\.|hub\.)?solidgate\.com|solidgate-tech\.github\.io'

if [[ -n "${LEAK_DENYLIST_FILE:-}" ]]; then
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    patterns+=("$line")
  done < "$LEAK_DENYLIST_FILE"
fi

if [[ $# -gt 0 ]]; then
  files=("$@")
else
  files=()
  while IFS= read -r f; do files+=("$f"); done < <(git ls-files)
fi

status=0
scanned=0
for f in "${files[@]}"; do
  # The script itself necessarily contains the patterns; skip binaries.
  [[ "$f" == "scripts/check-leaks.sh" || ! -f "$f" ]] && continue
  grep -Iq . "$f" || continue
  scanned=$((scanned + 1))
  text=$(sed -E "s#${allow}##g" "$f")
  for p in "${patterns[@]}"; do
    if hits=$(grep -nE -- "$p" <<<"$text"); then
      while IFS= read -r h; do
        echo "${f}:${h}"
      done <<<"$hits"
      status=1
    fi
  done
done

if [[ $status -eq 0 ]]; then
  echo "check-leaks: clean (${scanned} files, ${#patterns[@]} patterns)"
else
  echo "check-leaks: internal references found (see above)" >&2
fi
exit $status
