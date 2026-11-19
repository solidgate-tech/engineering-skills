# Auto-approve config

Two optional files. `gate.py` loads both. Invalid JSON, unknown keys, wrong types or out-of-range
values fail the gate (`config: <error>`), so a broken config never loosens anything.

**User-side**: `~/.claude/mr-review/config.json` (override the path with `MR_TOOLKIT_REVIEW_CONFIG`):

```json
{
  "defaults": { "max_lines": 150, "weight_tests": 0.2 },
  "repos": { "acme/web-app": { "deny": ["apps/payments/**"] }, "acme/auth-service": { "auto_approve": false } }
}
```

**In-repo**: `.mr-review.json` at the repo root, owned by the repo's maintainers:

```json
{ "max_lines": 300, "deny": ["billing/**"] }
```

It is read from the project's **default branch**. It is never read from the MR head or the
target branch, because a stacked MR targets the author's own branch, where they could loosen it.
An MR that changes `.mr-review.json` is never auto-approved.

## Keys

| Key | Default | Range | Meaning |
| --- | --- | --- | --- |
| `auto_approve` | `true` | bool | `false` turns auto-approve off for the repo |
| `max_lines` | `200` | ≥ 1 | budget of weighted changed lines (added + removed) |
| `weight_tests` | `0.25` | 0-1 | weight of a test line: tests and test support (`*.pom.*`, `*.fixture.*`, `__mocks__/`, `testdata/`, `conftest.py`) |
| `weight_docs` | `0.1` | 0-1 | weight of a docs line (`.md`, `.mdx`, `.rst`) |
| `min_score` | `12` | 3-15 | minimum confidence + risk + coverage |
| `min_factor` | `3` | 1-5 | minimum for each factor |
| `deny` | `[]` | globs | extra paths that block auto-approve |

Size is one budget: `code + tests × weight_tests + docs × weight_docs ≤ max_lines`. A test or docs
line carries less risk than an implementation line, but a big test diff still uses up part of the
budget. With the defaults, 6 lines of code plus 418 lines of test migration come to 110.5 and pass,
while 150 lines of code plus 600 lines of tests come to 300 and fail.
Lockfiles are on the denylist, so they never reach the size check. Files GitLab marks as generated
don't count at all. GitLab sets that flag from `.gitattributes` and from generator file names
(`*.pb.go`, `*.min.js`, …). `.gitattributes` is denied, so an MR can't mark its own files, and the
brief checks that each generated-flagged file really is generated output.

## Precedence

Built-in, then user `defaults`, then user `repos["group/project"]`, then the in-repo file.

- **Scalars**: the last level that sets a key wins, so the repo file wins.
- **`deny`**: union of all levels plus the built-in list. Patterns are only ever added.
- **`auto_approve: false`** at any level wins. Neither side can switch the other's opt-out back on.

## Built-in denylist

These paths are never auto-approved, whatever the scores. A small diff there can change what runs,
how it's built or deployed, or who can access what, and the reviewer can't see that effect in the
diff. The full list is `BUILTIN_DENY` in `scripts/gate.py`.

| Why | Node | Go | Python | Kotlin / JVM |
| --- | --- | --- | --- | --- |
| Dependencies pull in unreviewed code | `package.json`, lockfiles, `.npmrc`, `.yarnrc*`, `pnpm-workspace.yaml` | `go.mod`, `go.sum`, `go.work*`, `vendor/` | `requirements*.txt`, `constraints*.txt`, `pyproject.toml`, `poetry.lock`, `uv.lock`, `Pipfile*`, `setup.py`, `setup.cfg`, `pip.conf` | `*.gradle(.kts)`, `gradle.properties`, `gradle/` (version catalog, wrapper), `gradlew*`, `pom.xml`, `mvnw*`, `.mvn/` |
| Toolchain version | `.nvmrc`, `.node-version` | `.go-version` | `.python-version` | — |
| Data migrations | `migrations/`, `*.sql` | `migrations/`, `*.sql` | `migrations/`, `*.sql` | `db/migration/` (Flyway), `db/changelog/` (Liquibase), `*.sql` |

All stacks: `.tool-versions`, `.gitmodules` and any submodule or symlink entry (a submodule bump
is a 2-line diff that swaps in a whole other codebase), CI and build (`.gitlab-ci.yml`, `.gitlab/`,
`.github/`, `Makefile`, `Dockerfile*`), deploy (`helm/`, `k8s/`, `terraform/`, `*.tf`), and access
(`auth/`, `security/`, `.env*`, `CODEOWNERS`, `.mr-review.json`, `.gitattributes`).

Globs are case-insensitive. A pattern without `/` matches the file name anywhere. `**/x/**`
matches the directory `x` at any depth, including the root.
