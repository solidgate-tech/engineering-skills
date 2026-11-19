---
name: investigation
description: How to investigate a change before drafting a team-slack-post
---

# Investigation procedure

Run this between "user gave you a starting point" and "first draft". Do not skip — drafts written from a one-liner read as marketing, not as a message from a teammate.

## Goal

From the code and history, derive **four things**:

1. What the contributor used to have to do manually
2. What is now gone, automated, or simplified
3. What new capabilities or patterns are unlocked
4. **What the contributor must actively do to adopt this change** — specific commands, file edits, config keys to add/remove, imports to update

Each item maps to a post section: 1→§2 (problem), 2→§3 (affects you), 3→§5 (opens), 4→§4 (action). If item 4 yields nothing — zero steps required — omit section 4.

## Commands

```bash
# If they gave a branch or commit range
git log --oneline <ref>
git diff <ref> --stat
git show <ref> --stat

# Look for ADRs or decision docs anywhere in the repo
find . -name "*.md" -path "*/adr/*" -o -name "*.md" -path "*/decisions/*" | head -20
git log --all --oneline -- "*adr*" "*decision*"
```

## Files to read

Always check (when relevant to the diff):
- Dependency and workspace manifests (`package.json`, `pnpm-workspace.yaml`, `go.mod`, `pyproject.toml`, `Cargo.toml`, …) — dependency shape
- Build and CI pipeline config (`turbo.json`, `Makefile`, `.gitlab-ci.yml`, `.github/workflows/`, …) — pipeline shape
- Config files touched by the diff (`tsconfig*.json`, `vite.config.*`, linter configs, etc.)
- Migration scripts or codemods in `scripts/` or `tools/` directories touched by the diff
- `CHANGELOG.md` — especially entries marked "deprecated", "removed", or "breaking"
- `MIGRATION.md` or `migration-guide.md` anywhere in touched packages
- `README.md` sections titled "Upgrading" or "Migration"
- ADRs / decision docs surfaced above

## Deriving "What do you need to do?"

Before drafting section 4, check each of these. Any "yes" makes the section required:

- **Breaking changes** — does any export, import path, config key, or CLI command change? Note old→new.
- **Required commands** — must the contributor run a dependency install (`pnpm install`, `go mod download`, …), a codemod, or a migration script? Note the exact invocation.
- **Owned config changes** — are any files the contributor owns (not platform-owned) affected? Name the key/field.
- **Deadline** — is there a date by which action is required? Note it if present.
- **Automation** — does a script handle any step? If yes, that step becomes "run X" rather than a manual edit.

Omit section 4 if every check is "no"; if any check is "yes", section 4 is required. Format findings as an ordered list — this becomes the skeleton of the section.

## When to ask the user

After investigation, ask **one focused question** only if a critical piece is still unclear:
- Who was hurting most? (e.g. "was this mostly app teams or lib authors?")
- What was the specific incident that triggered this? (only if section 2 needs the anchor)

Don't ask for things you can derive from the code or git history.

## Anti-patterns

- Writing from the user's one-line description without reading the diff
- Asking the user to summarize the technical work — that's section 6, and you should be able to derive it
- Reading only the PR title and going straight to drafting
- Skipping the "What do you need to do?" derivation step and assuming the change is transparent — always check for breaking changes explicitly
