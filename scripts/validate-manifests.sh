#!/usr/bin/env bash
# Checks that the marketplace catalog, every plugin manifest and every skill
# are well-formed and agree with each other. Requires jq.
set -euo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

fail() { echo "::error::$*"; status=1; }
status=0

catalog=.claude-plugin/marketplace.json
jq empty "$catalog" || { echo "::error::$catalog is not valid JSON"; exit 1; }

while IFS=$'\t' read -r name src license; do
  dir="${src#./}"
  manifest="$dir/.claude-plugin/plugin.json"
  [[ -f "$manifest" ]] || { fail "$name: missing $manifest"; continue; }
  jq empty "$manifest" || { fail "$name: $manifest is not valid JSON"; continue; }

  [[ "$(jq -r .name "$manifest")" == "$name" ]] || fail "$name: name differs in $manifest"
  [[ "$license" == "Apache-2.0" ]] || fail "$name: marketplace entry must declare license Apache-2.0"
  [[ -f "$dir/README.md" ]] || fail "$name: missing $dir/README.md"

  while IFS= read -r skill; do
    head -1 "$skill" | grep -qx -- '---' || { fail "$skill: missing frontmatter"; continue; }
    fm=$(awk 'NR>1 && /^---$/ {exit} NR>1' "$skill")
    grep -qE '^name: *[a-z0-9-]+ *$' <<<"$fm" || fail "$skill: frontmatter needs a kebab-case name"
    grep -qE '^description: *.+' <<<"$fm" || fail "$skill: frontmatter needs a description"
  done < <(find "$dir" -name SKILL.md)
done < <(jq -r '.plugins[] | [.name, .source, (.license // "")] | @tsv' "$catalog")

for dir in plugins/*/; do
  dir="${dir%/}"
  jq -e --arg s "./$dir" '.plugins | any(.source == $s)' "$catalog" >/dev/null \
    || fail "$dir is not listed in $catalog"
done

[[ $status -eq 0 ]] && echo "validate-manifests: ok ($(jq '.plugins | length' "$catalog") plugins)"
exit $status
