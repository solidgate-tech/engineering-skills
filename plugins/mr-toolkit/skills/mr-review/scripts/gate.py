#!/usr/bin/env python3
"""Hard gates + score thresholds deciding whether a review MR may be auto-approved.

Usage: gate.py --repo group/proj --iid 123 --scores 5,4,4 --verdict approve   -> prints JSON
       gate.py --self-test
"""
import argparse
import json
import os
import re
import subprocess
import sys
from fnmatch import fnmatchcase
from pathlib import Path
from urllib.parse import quote, urlparse

# max_lines is a budget of weighted lines: a test or docs line carries less risk than a code line
BUILTIN = {"auto_approve": True, "max_lines": 200, "weight_tests": 0.25, "weight_docs": 0.1,
           "min_score": 12, "min_factor": 3}
# Paths where a small, harmless-looking diff changes what runs, how it is built or deployed, or what
# data and access look like. The reviewer can't judge that effect from the diff alone, so no score
# can approve these.
BUILTIN_DENY = [
    # dependencies + toolchain: a one-line bump pulls in code nobody reviewed
    "package.json", "pnpm-lock.yaml", "package-lock.json", "yarn.lock", ".npmrc", ".yarnrc*", "pnpm-workspace.yaml",
    "go.mod", "go.sum", "go.work", "go.work.sum", "**/vendor/**",
    "requirements*.txt", "constraints*.txt", "pyproject.toml", "poetry.lock", "uv.lock", "Pipfile*",
    "setup.py", "setup.cfg", "pip.conf",
    "*.gradle", "*.gradle.kts", "gradle.properties", "**/gradle/**", "gradlew*", "pom.xml", "mvnw*", "**/.mvn/**",
    "Cargo.*", "Gemfile*", ".gitmodules",
    ".tool-versions", ".python-version", ".nvmrc", ".node-version", ".go-version",
    # build, CI and deploy: runs with pipeline secrets or changes production
    ".gitlab-ci.yml", ".gitlab/**", ".github/**", "Makefile", "Dockerfile*",
    "**/helm/**", "**/k8s/**", "**/terraform/**", "*.tf",
    # data: schema and data migrations (Go/Python migrations/, Flyway db/migration, Liquibase)
    "**/migrations/**", "**/migration/**", "**/db/changelog/**", "*.sql",
    # access: auth code, secrets, ownership, this gate's own config
    "**/auth/**", "**/security/**", ".env*", "CODEOWNERS", ".mr-review.json", ".gitattributes",
]
SPECIAL_MODES = {"160000": "submodule", "120000": "symlink"}
RANGES = {"max_lines": (1, 100_000), "weight_tests": (0, 1), "weight_docs": (0, 1), "min_score": (3, 15), "min_factor": (1, 5)}
DOCS = ["*.md", "*.mdx", "*.rst"]  # by extension only: a .js file under docs/ is still code
TESTS = ["*.test.*", "*.spec.*", "*_spec.*", "*_test.go", "test_*.py", "*_test.py",
         "**/__tests__/**", "**/e2e/**", "**/tests/**", "**/test/**", "**/spec/**",
         # test support, only names prod code doesn't use: `*.driver.*` and `fixtures/` would give a DB
         # driver or seed data the test cap
         "*.pom.*", "*.fixture.*", "**/__mocks__/**", "**/testdata/**", "conftest.py"]
# JS/TS (jest, vitest, playwright), Python (pytest, unittest), Go, Kotlin/JVM (JUnit, Kotest)
SKIP_MARKERS = re.compile(r"\.(skip|only|todo)\b|skipIf|xfail|\bx(it|test|describe|should|context)\b"
                          r"|\bt\.Skip|@Disabled|@Ignore|enabled\s*=\s*false")
ASSERTION = re.compile(r"\bexpect\(|\bassert|\brequire\.|\bshould|\bt\.(Error|Fatal)|\bverify\(")
DO_NOT_MERGE = re.compile(r"do(n.?t|[ _-]?not)[ _-]?merge", re.I)  # same regex as mr-inbox/scripts/inventory.sh
FACTORS = ("confidence", "risk", "coverage")


def matches(path, patterns):
    """Case-insensitive glob: `**/x` also matches at the root, slash-free patterns match the basename."""
    path = path.lower()
    base = path.rsplit("/", 1)[-1]
    for pat in map(str.lower, patterns):
        globs = [pat, pat[3:]] if pat.startswith("**/") else [pat]
        target = path if "/" in pat else base
        if any(fnmatchcase(target, g.replace("**", "*")) for g in globs):
            return True
    return False


def merge_config(*levels):
    """built-in < each level in order. Scalars: last wins. deny: union. auto_approve: any false wins."""
    out = {**BUILTIN, "deny": list(BUILTIN_DENY)}
    for lvl in levels:
        if not isinstance(lvl, dict):
            raise ValueError(f"expected an object, got {type(lvl).__name__}")
        for key, val in lvl.items():
            if key == "deny":
                if not (isinstance(val, list) and all(isinstance(p, str) for p in val)):
                    raise ValueError("deny must be a list of glob strings")
            elif key not in BUILTIN:
                raise ValueError(f"unknown key {key!r}")
            elif type(val) is not type(BUILTIN[key]) and not (type(BUILTIN[key]) is float and type(val) is int):
                # `type is` so True isn't accepted as an int; ints are fine where a float is expected
                raise ValueError(f"{key} must be {type(BUILTIN[key]).__name__}")
            elif key in RANGES and not RANGES[key][0] <= val <= RANGES[key][1]:
                raise ValueError(f"{key} must be within {RANGES[key]}")
        out = {**out, **{k: v for k, v in lvl.items() if k != "deny"},
               "deny": out["deny"] + lvl.get("deny", []),
               "auto_approve": out["auto_approve"] and lvl.get("auto_approve", True)}
    return out


def kind(path):
    return "docs" if matches(path, DOCS) else "tests" if matches(path, TESTS) else "code"


def diff_lines(diff, sign):
    # GitLab /diffs bodies start at the first @@ hunk, with no ---/+++ file headers to skip
    return [ln[1:] for ln in diff.splitlines() if ln.startswith(sign)]


def merge_ref(mr):
    return f"refs/merge-requests/{mr['iid']}/merge"


def hard_gates(mr, files, discussions, me, cfg, overflow, pipeline_parents, commits):
    reasons = []
    if not cfg["auto_approve"]:
        reasons.append("opt-out: auto_approve is false for this repo")
    head = mr["diff_refs"]["head_sha"]
    pipe = mr.get("head_pipeline") or {}
    if pipe.get("status") != "success":
        reasons.append(f"pipeline: {pipe.get('status', 'none')}")
    elif pipe.get("sha") != head and not (pipe.get("ref") == merge_ref(mr) and head in pipeline_parents):
        reasons.append("pipeline: not run on the head commit")
    if mr.get("draft"):
        reasons.append("state: draft")
    if mr.get("has_conflicts"):
        reasons.append("state: conflicts")
    if mr.get("approved_by_me"):
        reasons.append("state: already approved by you")
    if any(DO_NOT_MERGE.search(lb) for lb in mr.get("labels", [])):
        reasons.append("state: do-not-merge label")
    author = mr["author"]["username"]
    if author == me["username"] or "renovate" in author.lower():
        reasons.append(f"author: {author}")
    mine = {e.lower() for e in me["emails"] if e}
    if any((c.get(k) or "").lower() in mine for c in commits for k in ("author_email", "committer_email")):
        reasons.append("author: the MR contains your own commits")
    if any(n.get("resolvable") and not n.get("resolved") for d in discussions for n in d.get("notes", [])):
        reasons.append("threads: unresolved discussion")

    paths = [p for f in files for p in {f["new_path"], f["old_path"]}]
    lines = {"code": 0, "tests": 0, "docs": 0}
    for f in files:
        # generated files don't count. GitLab sets generated_file from .gitattributes (denied below, so the
        # MR can't mark its own files) and from generator file names such as *.pb.go. The brief checks those.
        if not f.get("generated_file"):
            lines[kind(f["new_path"])] += len(diff_lines(f["diff"], "+")) + len(diff_lines(f["diff"], "-"))
    budget = lines["code"] + lines["tests"] * cfg["weight_tests"] + lines["docs"] * cfg["weight_docs"]
    blind = [f["new_path"] for f in files if not f["diff"] and not f.get("renamed_file")]
    if overflow:
        reasons.append("size: diff too large for GitLab to return")
    elif blind:
        reasons.append(f"size: no text diff (binary or mode change): {', '.join(blind)}")
    elif budget > cfg["max_lines"]:
        reasons.append(f"size: {budget:g} > {cfg['max_lines']} "
                       f"(code {lines['code']}, tests {lines['tests']}, docs {lines['docs']})")
    denied = [p for p in paths if matches(p, cfg["deny"])]
    denied += [f"{f['new_path']} ({SPECIAL_MODES[m]})" for f in files
               for m in {f.get("a_mode"), f.get("b_mode")} if m in SPECIAL_MODES]
    if denied:
        reasons.append(f"denylist: {', '.join(sorted(set(denied)))}")

    moved = [f["old_path"] for f in files if not f.get("deleted_file")
             and matches(f["old_path"], TESTS) and not matches(f["new_path"], TESTS)]
    if moved:
        reasons.append(f"tests weaken: moved out of test paths, so no longer run: {', '.join(moved)}")
    tests = [f for f in files if matches(f["new_path"], TESTS)]
    added = [ln for f in tests for ln in diff_lines(f["diff"], "+")]
    removed = [ln for f in tests for ln in diff_lines(f["diff"], "-")]
    if removed and not added:  # a replaced test file is a migration; whether cases got lost is the coverage score
        reasons.append("tests weaken: tests removed and none added")
    if any(SKIP_MARKERS.search(ln) for ln in added):
        reasons.append("tests weaken: skip/only marker added")
    if sum(map(bool, map(ASSERTION.search, removed))) > sum(map(bool, map(ASSERTION.search, added))):
        reasons.append("tests weaken: more assertions removed than added")
    return reasons


def score_reasons(scores, verdict, cfg):
    reasons = [] if verdict == "approve" else [f"scores: verdict {verdict}"]
    reasons += [f"scores: {f} {scores[f]} < {cfg['min_factor']}" for f in FACTORS if scores[f] < cfg["min_factor"]]
    total = sum(scores[f] for f in FACTORS)
    if total < cfg["min_score"]:
        reasons.append(f"scores: sum {total} < {cfg['min_score']}")
    return reasons


def config_error(head, err):
    return {"pass": False, "eligible": False, "reasons": [f"config: {err}"], "head_sha": head, "config": None}


def gate(mr, files, discussions, me, levels, scores, verdict, overflow=False, pipeline_parents=(), commits=()):
    """pass = hard gates only; eligible = hard gates + scores. Invalid config fails closed.
    me: {"username", "emails"}. pipeline_parents: parent shas of a merged-results pipeline's commit
    (empty for branch pipelines)."""
    head = mr["diff_refs"]["head_sha"]
    try:
        cfg = merge_config(*levels)
    except ValueError as e:
        return config_error(head, e)
    hard = hard_gates(mr, files, discussions, me, cfg, overflow, pipeline_parents, commits)
    reasons = hard + score_reasons(scores, verdict, cfg)
    return {"pass": not hard, "eligible": not reasons, "reasons": reasons, "head_sha": head, "config": cfg}


def user_levels(user_cfg, repo):
    """~/.claude/mr-review/config.json → [defaults, repos[repo]]."""
    if not isinstance(user_cfg, dict) or set(user_cfg) - {"defaults", "repos"}:
        raise ValueError(f"{USER_CONFIG}: only 'defaults' and 'repos' keys are allowed")
    repos = user_cfg.get("repos", {})
    if not isinstance(repos, dict):
        raise ValueError(f"{USER_CONFIG}: 'repos' must be an object keyed by group/project")
    by_path = {k.lower(): v for k, v in repos.items()}  # GitLab paths are case-insensitive
    return [user_cfg.get("defaults", {}), by_path.get(repo.lower(), {})]


def overflowed(files, changes_count):
    """True when GitLab didn't return every file in full (per-file truncation, or fewer files than it counts)."""
    return (any(f.get("too_large") or f.get("collapsed") for f in files)
            or not str(changes_count).isdigit() or int(changes_count) != len(files))


# --- I/O ----------------------------------------------------------------------

USER_CONFIG = Path(os.environ.get("MR_TOOLKIT_REVIEW_CONFIG", Path.home() / ".claude" / "mr-review" / "config.json"))


def glab_json(path, paginate=False):
    cmd = ["glab", "api", path] + (["--paginate"] if paginate else [])
    out = subprocess.run(cmd, capture_output=True, text=True)
    if out.returncode:
        raise RuntimeError(f"glab api {path}: {out.stderr.strip()}")
    if not paginate:
        return json.loads(out.stdout)
    items, pos, dec = [], 0, json.JSONDecoder()  # --paginate prints one JSON array per page, back to back
    while pos < len(out.stdout.rstrip()):
        page, pos = dec.raw_decode(out.stdout, pos)
        if not isinstance(page, list):
            raise RuntimeError(f"glab api {path}: expected a JSON array, got {type(page).__name__}")
        items += page
        while pos < len(out.stdout) and out.stdout[pos].isspace():
            pos += 1
    return items


def repo_config(enc, ref):
    """.mr-review.json at the default branch. Absent → {}. Not the target branch: a stacked MR targets the
    author's own feature branch, where they could loosen the rules."""
    path = f"projects/{enc}/repository/files/.mr-review.json/raw?ref={quote(ref, safe='')}"
    out = subprocess.run(["glab", "api", path], capture_output=True, text=True)
    if out.returncode:
        if "404 File Not Found" in out.stderr:  # any other 404 (project, ref) is an error, not "no config"
            return {}
        raise RuntimeError(f"glab api {path}: {out.stderr.strip()}")
    try:
        return json.loads(out.stdout)
    except json.JSONDecodeError as e:
        raise ValueError(f".mr-review.json@{ref}: {e}")


def load_levels(repo, enc, ref):
    try:
        user = json.loads(USER_CONFIG.read_text()) if USER_CONFIG.exists() else {}
    except json.JSONDecodeError as e:
        raise ValueError(f"{USER_CONFIG}: {e}")
    return user_levels(user, repo) + [repo_config(enc, ref)]


def parse_scores(text):
    vals = [int(v) for v in text.split(",")]
    if len(vals) != 3 or not all(1 <= v <= 5 for v in vals):
        raise argparse.ArgumentTypeError("expected confidence,risk,coverage, each 1-5")
    return dict(zip(FACTORS, vals))


def main():
    ap = argparse.ArgumentParser(description="Auto-approve gate for one review MR (read-only).")
    ap.add_argument("--repo", required=True, help="group/project")
    ap.add_argument("--iid", required=True, type=int)
    ap.add_argument("--scores", required=True, type=parse_scores, help="confidence,risk,coverage e.g. 5,4,4")
    ap.add_argument("--verdict", required=True, choices=("approve", "nits", "changes"))
    args = ap.parse_args()

    enc = quote(args.repo, safe="")
    base = f"projects/{enc}/merge_requests/{args.iid}"
    mr = glab_json(base)
    files = glab_json(f"{base}/diffs?per_page=100", paginate=True)
    discussions = glab_json(f"{base}/discussions?per_page=100", paginate=True)
    user = glab_json("user")
    # every address a commit of mine can carry: primary, commit email, confirmed secondaries, the noreply one
    noreply = f"{user['id']}-{user['username']}@users.noreply.{urlparse(user['web_url']).hostname}"
    extra = [e["email"] for e in glab_json("user/emails?per_page=100", paginate=True) if e.get("confirmed_at")]
    me = {"username": user["username"], "emails": [user.get("email"), user.get("commit_email"), noreply, *extra]}
    commits = glab_json(f"{base}/commits?per_page=100", paginate=True)
    approvers = glab_json(f"{base}/approvals")["approved_by"]
    mr = {**mr, "approved_by_me": any(a["user"]["username"] == me["username"] for a in approvers)}
    project = glab_json(f"projects/{enc}")
    pipe = mr.get("head_pipeline") or {}
    parents = (glab_json(f"projects/{enc}/repository/commits/{pipe['sha']}")["parent_ids"]
               if pipe.get("ref") == merge_ref(mr) else [])
    try:
        levels = load_levels(project["path_with_namespace"], enc, project["default_branch"])
    except ValueError as e:
        result = config_error(mr["diff_refs"]["head_sha"], e)
    else:
        result = gate(mr, files, discussions, me, levels, args.scores, args.verdict, overflowed(files, mr.get("changes_count")), parents, commits)
    print(json.dumps(result, indent=2))


# --- self-test fixtures -------------------------------------------------------

def _file(path, diff="@@ -1 +1 @@\n-a\n+b\n", old=None):
    return {"new_path": path, "old_path": old or path, "diff": diff}


def _mr(**over):
    mr = {
        "iid": 7, "author": {"username": "alice"}, "draft": False, "has_conflicts": False, "labels": [],
        "diff_refs": {"head_sha": "abc"}, "head_pipeline": {"status": "success", "sha": "abc"},
    }
    return {**mr, **over}


def _run(files=None, mr=None, discussions=(), levels=(), scores=(5, 5, 5), verdict="approve", overflow=False,
         parents=(), commits=(), me=None):
    s = dict(zip(("confidence", "risk", "coverage"), scores))
    me = me or {"username": "me", "emails": ["me@x.com"]}
    return gate(mr or _mr(), files or [_file("README.md")], list(discussions), me, list(levels), s, verdict,
                overflow, list(parents), list(commits))


def _fails(reason_prefix, **kw):
    out = _run(**kw)
    assert not out["eligible"], out
    assert any(r.startswith(reason_prefix) for r in out["reasons"]), (reason_prefix, out["reasons"])
    return out


def self_test():
    big = lambda n: "@@ -1 +1 @@\n" + "+x\n" * n
    # all-green: docs-only at 800 lines, refactor, test fix
    assert _run(files=[_file("docs/guide.md", big(800))])["eligible"]
    assert _run(files=[_file("src/user.ts"), _file("src/user.test.ts", "@@\n+expect(a).toBe(1)\n")], scores=(5, 4, 4))["eligible"]
    assert _run(files=[_file("src/user.spec.ts", "@@\n-expect(a).toBe(1)\n+expect(a).toBe(2)\n")], scores=(5, 5, 4))["eligible"]
    out = _run()
    assert out["pass"] and out["reasons"] == [] and out["head_sha"] == "abc"

    # hard gates
    _fails("opt-out", levels=[{"auto_approve": False}])
    _fails("pipeline", mr=_mr(head_pipeline={"status": "failed", "sha": "abc"}))
    _fails("pipeline", mr=_mr(head_pipeline={"status": "success", "sha": "old"}))
    _fails("pipeline", mr=_mr(head_pipeline=None))
    _fails("state", mr=_mr(draft=True))
    _fails("state", mr=_mr(has_conflicts=True))
    _fails("state", mr=_mr(labels=["DON'T MERGE"]))
    _fails("author", mr=_mr(author={"username": "me"}))
    _fails("author", mr=_mr(author={"username": "renovate-bot"}))
    _fails("threads", discussions=[{"notes": [{"resolvable": True, "resolved": False}]}])
    assert _run(discussions=[{"notes": [{"resolvable": True, "resolved": True}, {"resolvable": False}]}])["eligible"]
    _fails("size", files=[_file("src/a.ts", big(201))])
    _fails("size", files=[_file("docs/a.md", big(2001))])  # 2001 * 0.1 > 200
    # one weighted budget: code*1 + tests*0.25 + docs*0.1 <= 200, generated files not counted
    assert _run(files=[_file("docs/a.md", big(300)), _file("src/a.ts")], scores=(5, 4, 4))["eligible"]
    assert _run(files=[_file("src/form.tsx", big(6)), _file("src/form.page.test.ts", big(205)),
                       _file("src/form.pom.ts", big(73)), _file("src/form.driver.tsx", "@@\n" + "-x\n" * 33),
                       _file("src/form.test.tsx", "@@\n" + "-x\n" * 107) | {"deleted_file": True}],
                scores=(4, 4, 4))["eligible"]  # small fix + large test: 6 code lines + 418 test lines
    _fails("size", files=[_file("src/a.test.ts", big(801))])  # 200.25
    _fails("size", files=[_file("src/a.ts", big(150)), _file("src/b.ts", big(51))])
    _fails("size", files=[_file("src/a.ts", big(150)), _file("src/a.test.ts", big(600))])  # 150 + 150: tests eat the budget
    assert _run(files=[_file("src/a.ts", big(10)), _file("src/a.test.ts", big(700))], scores=(5, 4, 4))["eligible"]
    out = _run(files=[_file("src/a.ts", big(150)), _file("src/a.test.ts", big(600))])
    assert "size: 300 > 200 (code 150, tests 600, docs 0)" in out["reasons"], out["reasons"]
    assert _run(files=[_file("src/a.ts", big(250))], levels=[{"weight_tests": 1, "max_lines": 300}],
                scores=(5, 4, 4))["eligible"]  # int weight accepted
    assert _run(files=[_file("src/gen/api.pb.go", big(5000)) | {"generated_file": True}], scores=(5, 4, 4))["eligible"]
    _fails("denylist", files=[_file(".gitattributes")])  # else an MR could mark its own files generated
    for path in ("src/db/postgres.driver.ts", "src/fixtures/seed.ts"):
        _fails("size", files=[_file(path, big(500))])  # ambiguous names stay code
    for path in ("src/pages/login.pom.ts", "pkg/parser/testdata/input.json", "tests/conftest.py",
                 "src/__mocks__/api.ts", "src/test/fixtures/user.json", "src/user.fixture.ts"):
        assert _run(files=[_file(path, big(500))], scores=(5, 4, 4))["eligible"], path  # test support → test cap
    _fails("size", overflow=True)
    for path in ("db/migrations/001.sql", "apps/x/package.json", ".gitlab-ci.yml", "src/auth/token.go",
                 "pnpm-lock.yaml", "go.sum", "Dockerfile.prod", ".env.local", ".mr-review.json", "helm/values.yaml", "auth/session.go", "migrations/001.go"):
        _fails("denylist", files=[_file(path)])
    _fails("denylist", files=[_file("src/new.go", old="src/auth/old.go")])  # rename out of a denied dir
    _fails("denylist", files=[_file("payments/refund.go")], levels=[{"deny": ["payments/**"]}])
    _fails("tests weaken", files=[_file("src/a.test.ts", "@@\n+it.skip('x', () => {})\n")])
    _fails("tests weaken", files=[_file("pkg/a_test.go", "@@\n+\tt.Skip(\"flaky\")\n")])
    _fails("tests weaken", files=[_file("src/a.test.ts", "@@\n-expect(a).toBe(1)\n-expect(b).toBe(2)\n+expect(a).toBe(1)\n")])
    assert _run(files=[_file("src/stream.ts", "@@\n+stream.skip(1)\n")], scores=(5, 4, 4))["eligible"]  # prod code: no test markers

    # scores
    _fails("scores", verdict="nits")
    _fails("scores", scores=(5, 5, 2))  # sum 12 but one factor < 3 → veto
    _fails("scores", scores=(4, 4, 3))  # every factor ≥ 3 but sum 11 < 12
    assert _run(scores=(4, 4, 4))["eligible"]
    out = _run(mr=_mr(draft=True), scores=(5, 5, 5))
    assert not out["pass"] and not out["eligible"]
    out = _run(verdict="changes")
    assert out["pass"] and not out["eligible"]  # pass = hard gates only

    # config merge
    assert merge_config({"max_lines": 100}, {"max_lines": 300})["max_lines"] == 300  # repo (last) wins
    cfg = merge_config({"deny": ["a/**"]}, {"deny": ["b/**"]})
    assert {"a/**", "b/**", "**/migrations/**"} <= set(cfg["deny"])  # union incl. built-in
    assert merge_config({"auto_approve": False}, {"auto_approve": True})["auto_approve"] is False  # sticky opt-out
    assert merge_config({"auto_approve": True}, {"auto_approve": False})["auto_approve"] is False
    for bad in ({"max_line": 1}, {"max_lines": "200"}, {"deny": "a/**"}, {"auto_approve": "no"}, {"min_score": True}):
        try:
            merge_config(bad)
            raise AssertionError(f"accepted {bad}")
        except ValueError:
            pass
    _fails("config", levels=[{"max_line": 1}])  # invalid config fails closed
    _fails("config", levels=["not a dict"])

    # user-side config file → levels
    user = {"defaults": {"max_lines": 100}, "repos": {"g/p": {"auto_approve": False}}}
    assert user_levels(user, "g/p") == [{"max_lines": 100}, {"auto_approve": False}]
    assert user_levels(user, "other/p") == [{"max_lines": 100}, {}]
    assert user_levels({}, "g/p") == [{}, {}]
    for bad in ({"default": {}}, {"repos": []}, []):
        try:
            user_levels(bad, "g/p")
            raise AssertionError(f"accepted {bad}")
        except ValueError:
            pass

    # merged-results pipelines run on refs/merge-requests/<iid>/merge, whose commit has head as a parent
    merged = lambda ref: _mr(head_pipeline={"status": "success", "sha": "m1", "ref": ref})
    assert _run(mr=merged("refs/merge-requests/7/merge"), parents=["base", "abc"])["eligible"]
    _fails("pipeline", mr=merged("refs/merge-requests/7/merge"), parents=["base", "old"])  # stale merge pipeline
    _fails("pipeline", mr=merged("refs/merge-requests/8/merge"), parents=["base", "abc"])  # another MR's ref

    # bypass regressions (security review)
    for path in ("src/Auth/token.go", "DB/Migrations/001.go", "dockerfile", "deploy/helm/values.yaml",
                 "infra/terraform/main.tf", "apps/x/k8s/deploy.yaml"):
        _fails("denylist", files=[_file(path)])
    _fails("size", files=[_file("assets/blob.bin", diff="")])  # binary / mode-only: line count unknown
    assert _run(files=[_file("src/b.ts", diff="", old="src/a.ts") | {"renamed_file": True}], scores=(5, 4, 4))["eligible"]
    _fails("tests weaken", files=[_file("src/a.test.ts", "@@\n-it('x', () => {})\n") | {"deleted_file": True}])
    # a test file replaced by another one is a migration, not weakening; coverage is the score's job
    assert _run(files=[_file("src/a.test.ts", "@@\n-it('x', () => { expect(a) })\n") | {"deleted_file": True},
                       _file("e2e/a.spec.ts", "@@\n+test('x', () => { expect(a) })\n")], scores=(5, 4, 4))["eligible"]
    _fails("tests weaken", files=[_file("src/a.ts", old="src/a.test.ts")])  # renamed out of test paths
    for line in ("@pytest.mark.skip", "xtest('a', f)", "t.SkipNow()", "@Ignore", "test.skipIf(ci)('a', f)", "it.todo('a')"):
        _fails("tests weaken", files=[_file("tests/test_a.py", f"@@\n+{line}\n")])
    _fails("tests weaken", files=[_file("spec/models/user_spec.rb", "@@\n+xit 'works'\n+describe.skip\n")])
    assert overflowed([{"diff": "@@\n+a\n"}], "2")  # GitLab says 2 files, we got 1
    assert overflowed([{"diff": "@@\n+a\n"}], "1000+")
    assert not overflowed([{"diff": "@@\n+a\n"}], "1")
    for bad in ({"min_score": 2}, {"min_factor": 0}, {"min_factor": 6}, {"max_lines": 0},
                {"weight_tests": 2}, {"weight_docs": -0.1}, {"weight_tests": True}, {"max_lines_tests": 800}):
        try:
            merge_config(bad)
            raise AssertionError(f"accepted {bad}")
        except ValueError:
            pass

    # round 2 (security review)
    _fails("size", files=[_file("src/a.ts", "@@\n" + "+++x\n" * 201)])  # added lines starting with "++"
    _fails("tests weaken", files=[_file("src/a.test.ts", "@@\n---expect(a)\n---expect(b)\n+expect(a)\n")])
    _fails("size", files=[_file("docs/evil.js", big(300))])  # code in docs/ gets the code cap
    _fails("author", commits=[{"author_email": "alice@x.com"}, {"author_email": "Me@X.com"}])  # own commits
    _fails("author", commits=[{"author_email": "alice@x.com", "committer_email": "me@x.com"}])  # I committed
    _fails("author", commits=[{"author_email": "me@alt.com"}], me={"username": "me", "emails": ["me@x.com", "me@alt.com"]})
    assert _run(commits=[{"author_email": "alice@x.com", "committer_email": "alice@x.com"}])["eligible"]
    user = {"repos": {"Acme/Web-App": {"auto_approve": False}}}
    assert user_levels(user, "acme/web-app")[1] == {"auto_approve": False}  # repo keys case-insensitive

    # round 3 (security review): supply chain
    for path in (".gitmodules", "requirements.txt", "requirements-dev.txt", "pyproject.toml", "poetry.lock",
                 "Pipfile.lock", "Cargo.toml", "Gemfile.lock", ".npmrc", ".yarnrc.yml", "pnpm-workspace.yaml",
                 ".github/workflows/ci.yml"):
        _fails("denylist", files=[_file(path)])
    _fails("denylist", files=[_file("vendor/lib", "@@\n-Subproject commit a\n+Subproject commit b\n") | {"b_mode": "160000"}])
    _fails("denylist", files=[_file("docs/link.md", "@@\n+../.env\n") | {"b_mode": "120000"}])
    _fails("size", files=[_file("notes.txt", big(300))])  # .txt is not docs

    # Go / Python / Kotlin-JVM stacks
    for path in ("go.work", "go.work.sum", "vendor/modules.txt", "services/foo/vendor/github.com/x/y.go", "setup.py", "setup.cfg", "uv.lock",
                 "constraints.txt", "pip.conf", "build.gradle.kts", "app/build.gradle", "settings.gradle.kts",
                 "gradle.properties", "gradle/libs.versions.toml", "gradle/wrapper/gradle-wrapper.properties",
                 "gradlew", "pom.xml", "mvnw", ".mvn/wrapper/maven-wrapper.properties", "Makefile",
                 "src/main/resources/db/migration/V2__add_col.kt", "src/main/resources/db/changelog/001.yaml",
                 ".tool-versions", ".python-version", ".nvmrc", ".go-version"):
        _fails("denylist", files=[_file(path)])
    for line in ("@pytest.mark.xfail", "test(\"a\").config(enabled = false) {", "xshould(\"work\") {"):
        _fails("tests weaken", files=[_file("src/test/kotlin/ATest.kt", f"@@\n+{line}\n")])
    for removed in ("a shouldBe 1", "t.Errorf(\"got %v\", got)", "t.Fatalf(\"x\")", "self.assertEqual(a, 1)"):
        _fails("tests weaken", files=[_file("pkg/a_test.go", f"@@\n-{removed}\n")])

    _fails("state", mr=_mr(approved_by_me=True))  # nothing to do: already approved

    # /diffs entries GitLab didn't return in full → overflow
    assert not overflowed([{"diff": "@@\n+a\n", "too_large": False, "collapsed": False}], "1")
    assert overflowed([{"diff": "", "too_large": True}], "1")
    assert overflowed([{"diff": "", "collapsed": True}], "1")
    print("ok")


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        self_test()
    else:
        try:
            main()
        except RuntimeError as e:  # glab failure: no verdict, the caller treats the MR as not eligible
            sys.exit(f"gate.py: {e}")
