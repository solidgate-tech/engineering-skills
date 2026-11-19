#!/usr/bin/env bash
# One list of every open MR that may need the user: authored MRs the author can
# move (incl. not_approved / ci_still_running ones, whose red CI / threads GitLab
# hides behind the first blocker), MRs assigned to the user that someone else (often a bot)
# authored, plus the pending review queue.
#
# Output: JSON array, oldest-first. Each item:
#   kind: "authored" | "review", repo, iid, title, web_url, hours_open, age,
#   jira (ticket key from title/branch or null), labels, do_not_merge,
#   hint (authored: mr-ready action; review: null), assigned (authored only: true when the
#   user is only the assignee), author (review and assigned only), author_username (assigned only),
#   source_branch, target_branch/additions/deletions/files_changed (review only)
# An MR you both authored and review is listed once, as "authored". An assigned MR you also
# review is listed once, as "review".
#
# Env: GITLAB_HOST, GITLAB_USERNAME (passed through to the sibling scripts),
#      JIRA_KEY_PATTERN (default [A-Z][A-Z0-9]+-[0-9]+)
set -euo pipefail

skills="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

authored=$(INCLUDE_WAITING=1 bash "$skills/mr-ready/scripts/list_actionable.sh")
assigned=$(SCOPE=assigned_to_me INCLUDE_WAITING=1 bash "$skills/mr-ready/scripts/list_actionable.sh")
review=$(bash "$skills/mr-to-review/scripts/list_review_queue.sh")

jq -n --arg pat "${JIRA_KEY_PATTERN:-[A-Z][A-Z0-9]+-[0-9]+}" --argjson a "$authored" --argjson g "$assigned" --argjson r "$review" '
  def repo: .web_url | capture("^https?://[^/]+/(?<p>.+)/-/merge_requests/") | .p;
  def age: if .hours_open < 48 then "\(.hours_open)h" else "\(.hours_open / 24 | floor)d" end;
  def jira: [(.title, .source_branch // "") | scan($pat)
             | select(test("^(ADR|SDD|RFC|CVE|ISO|UTF|SHA|RS|ES)-") | not)] | first // null;
  def common: {
    repo: repo, iid, title, web_url, hours_open, age: age, jira: jira,
    labels: (.labels // []),
    do_not_merge: any((.labels // [])[]; test("do(n.?t|[ _-]?not)[ _-]?merge"; "i")),
    source_branch
  };
  def unseen($seen): . as $m | select(any($seen[]; .repo == $m.repo and .iid == $m.iid) | not);
  [($a.ready + $a.blocked)[] | common + {kind: "authored", assigned: false, hint: .action}] as $auth
  | ($auth + [
      $r[] | common + {kind: "review", hint: null, author: .author.name,
                       target_branch, additions, deletions, files_changed}
      | unseen($auth)
    ]) as $mine
  | $mine + [
      ($g.ready + $g.blocked)[]
      | common + {kind: "authored", assigned: true, author, author_username, hint: .action}
      | unseen($mine)
    ]
  | sort_by(-.hours_open)'
