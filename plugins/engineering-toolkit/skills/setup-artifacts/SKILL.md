---
name: setup-artifacts
description: "Sets up the places in a repository where AI agents put the artifacts they produce: gitignored scratch dirs for plans, specs and ideas, committed ADR and SDD indexes, and the AGENTS.md rules that bind agents to them. Migrates existing ADRs and SDDs into the unified format. Use when bootstrapping a repo for AI-assisted work, when an agent asks where plans or specs go, or when ADRs/SDDs live in ad-hoc places. Trigger terms: set up artifacts, AI artifacts, where do plans go, docs/plans, docs/specs, docs/ideas, bootstrap docs/adr, bootstrap docs/sdd, migrate ADRs, migrate SDDs, gitignore plans, set up docs for AI, where to put plans or specs, AGENTS.md artifact rules."
---

## When to use

| Run it                                                        | Skip it                                          |
| ------------------------------------------------------------- | ------------------------------------------------ |
| Repo has no agreed place for AI plans / specs / ideas         | Writing one ADR or SDD — use those skills directly |
| Adding one more place (e.g. `ideas`) to a repo that has some  | Content of a plan or spec — other skills write it |
| ADRs or design docs live in ad-hoc folders or formats         | Runbooks, guides, other docs                      |

Running it again is safe: anything already in place is left alone.

## Places

| Place   | Path          | Kind      | Format owner                                  |
| ------- | ------------- | --------- | --------------------------------------------- |
| `ideas` | `docs/ideas/` | scratch   | `templates/scratch-README.md`                 |
| `specs` | `docs/specs/` | scratch   | `templates/scratch-README.md`                 |
| `plans` | `docs/plans/` | scratch   | `templates/scratch-README.md`                 |
| `adr`   | `docs/adr/`   | committed | `architecture-decision-records` skill         |
| `sdd`   | `docs/sdd/`   | committed | `software-design-document` skill              |

Scratch = only `README.md` is tracked, everything else is gitignored. Committed = numbered records plus an index.

**The ADR and SDD skills own everything about their records**: document template, frontmatter, index README, row
format, status lifecycle. Never write any of it from memory and never keep a copy here — consult the owning skill and
take the piece from it. If that skill is not available in this session, stop and ask the user to install the whole
`engineering-toolkit` plugin.

---

## Mechanical process

### 1. Detect

Run in the target repo and keep the results:

```bash
git rev-parse --show-toplevel
git remote get-url origin              # service name = last path segment without .git; fallback: top-level dir name
ls docs/ AGENTS.md CLAUDE.md 2>/dev/null
git ls-files docs/ideas docs/specs docs/plans           # tracked files the ignore rule would NOT untrack
git ls-files --cached --others --exclude-standard | grep -iE '(^|/)(adrs?|decisions|sdds?|design(-docs?)?|rfcs?)/|(^|/)(adr|sdd)-?[0-9]'
```

A place counts as **set up** when its README (and, for `sdd`, `0000-template.md`) exists and either matches what
step 4 would write, or contains all of it plus repository-specific additions (a prior merge). A file the user chose
to keep earlier is reported as `skip — kept`, never re-prompted. Anything the last command finds that is not already a correctly formatted record in `docs/adr/` or
`docs/sdd/` is a **migration candidate**. Index READMEs and `0000-template.md` are never candidates.

### 2. Select

Ask one multi-select question listing the five places; mark set-up ones as "already set up". Default selection: all
places not yet set up. Then confirm the service name once: `<service-name>` lower-case kebab (e.g. `payments-api`),
`<PREFIX>` upper-case (`PAYMENTS-API`).

### 3. Migrate

Only if step 1 found candidates for a selected committed place: follow [`MIGRATION.md`](./MIGRATION.md) before step 4.

### 4. Plan, then apply

Build the full change list first and show it: path, action (`create` / `append` / `skip — already set up` /
`conflict — diff below`). **Then stop and end your turn.** Write nothing until the user replies with approval —
naming the places to set up is not approval of the change list. Skip this stop only when the user's request already
says to apply without confirmation. For every conflict offer three choices:

- **merge** (recommended) — the rendered version, plus everything repository-specific from the existing file carried
  over verbatim: extra paragraphs, extra promotion targets (e.g. a `conventions.md` link), extra rules. Index
  table columns, frontmatter keys and `alias` values (`<service-name>-<kind>`) always follow the owning skill or
  template — they are never merge candidates, even when the repo uses another convention elsewhere
- **replace** — the rendered version only; list what would be lost
- **keep** — leave the file as is

For each selected place:

- **Scratch place** — render `templates/scratch-README.md` into `docs/<place>/README.md` using the fill-ins below.
- **`adr`** — create `docs/adr/README.md` from the `architecture-decision-records` skill's Index README section.
- **`sdd`** — create `docs/sdd/README.md` from the `software-design-document` skill's Index README section, and
  `docs/sdd/0000-template.md` as a verbatim copy of that skill's template with only `<service-name>` replaced.

Then, once, across all places that exist after this run (selected now or set up before):

- **`.gitignore`** — for each scratch place, ensure these two exact lines exist; append missing ones under one
  comment `# AI-generated scratch artifacts — see AGENTS.md "AI-Generated Artifacts"`:
  ```gitignore
  /docs/<place>/*
  !/docs/<place>/README.md
  ```
  The `/*` form is required: a bare `docs/<place>/` ignores the directory itself and git never applies the `!` line.
- **`AGENTS.md`** — render `templates/agents-section.md` and insert it immediately before the first `## ` heading
  (end of file if there is none). If a `## AI-Generated Artifacts` section already exists and differs, show the
  diff and ask. No `AGENTS.md`: create it as `# <service-name> AI Agent Rules` + the section. If `CLAUDE.md` exists
  and does not mention `AGENTS.md`, propose adding the line `See [AGENTS.md](AGENTS.md).` — ask before editing it.
- **`docs/README.md`** — only if it exists and contains a table: add one row per group that exists and is not
  already listed:
  ```markdown
  | [ADRs](adr/README.md) · [SDDs](sdd/README.md) | Decision records and designs |
  | [Ideas](ideas/README.md) · [Specs](specs/README.md) · [Plans](plans/README.md) | Where AI-generated working notes go (gitignored) |
  ```
  List only the places that exist.
- **GitLab labels** (optional, GitLab projects only) — for `adr` / `sdd`, ensure the project has label `ADR` / `SDD` (`glab label list --per-page 100`);
  in the change list as `label ADR` with `create` or `skip — exists`. Create with the exact `glab label create`
  command from the `mr-toolkit:mr-create` skill's MR Labels section — same color and description everywhere, so
  merge-time metrics can filter on them. Failure never stops the run; report it as a manual follow-up with the command.

### 5. Verify and report

```bash
git check-ignore -q docs/<place>/probe.md && echo ok          # must print ok for each scratch place
git check-ignore -q docs/<place>/README.md || echo ok         # must print ok for each scratch place
```

Check every relative link in the files you wrote resolves (`test -e`). Report: created, migrated, skipped, and manual
follow-ups (tracked scratch files, `CLAUDE.md` pointer, anything the user declined).

---

## Fill-ins

"Exists" below means: set up after this run. Drop a line whose target does not exist — never leave a dead link.

| Placeholder             | Value                                                                                  |
| ----------------------- | -------------------------------------------------------------------------------------- |
| `{{service}}`           | Confirmed `<service-name>` (e.g. `payments-api`)                                            |
| `{{PREFIX}}`            | `<service-name>` upper-cased (e.g. `PAYMENTS-API`)                                          |
| `{{Kind}}` / `{{kind}}` | `Ideas`/`ideas`, `Specs`/`specs`, `Plans`/`plans`                                      |
| `{{purpose}}` ideas     | `idea one-pagers — problem framing, directions considered, assumptions to validate and a Not Doing list` |
| `{{purpose}}` specs     | `specifications — requirements, acceptance criteria and behavior notes written before the code` |
| `{{purpose}}` plans     | `implementation plans — how a change will be made`                                     |
| `{{promotion-list}}`    | Bullets, in this order: `- a decision with real trade-offs → an [ADR](../adr/README.md)` (if `adr`); `- a design that is expensive to reverse → an [SDD](../sdd/README.md)` (if `sdd`); `- a rule other contributors must follow → [AGENTS.md](../../AGENTS.md)` (always) |
| `{{siblings-line}}`     | `Ideas live in [docs/ideas/](../ideas/README.md), specs in [docs/specs/](../specs/README.md), plans in [docs/plans/](../plans/README.md).` — only the other existing scratch places; omit if none. Ideas README appends: `An idea that is picked up moves into a spec or a plan.` (only those that exist) |
| `{{scratch-bullets}}`   | One per existing scratch place: `- **Ideas** (what problem is worth solving) → \`docs/ideas/<jira-key>-<short-kebab-title>.md\``, `- **Specs** (what a change must do) → …`, `- **Plans** (how a change will be made) → …` |
| `{{promotion-sentence}}`| Exactly: `a decision with real trade-offs to an [ADR](docs/adr/README.md), a design that is expensive to reverse to an [SDD](docs/sdd/README.md), a rule others must follow to this file.` — drop the ADR/SDD clauses whose place does not exist |
| `{{records-line}}`      | If `adr` or `sdd` exists: `Write ADRs in [docs/adr/](docs/adr/README.md) with the \`architecture-decision-records\` skill and SDDs in [docs/sdd/](docs/sdd/README.md) with the \`software-design-document\` skill. Agents may draft these records, carefully: only when asked or when a decision clearly warrants one, with \`status: "WIP"\` and the requester as author; never set \`approved_at\` or a final status — acceptance happens in human review — and mark anything inferred rather than decided as an open question.` — only the existing ones (in the caution, name only those); omit if neither |

Put each fill-in exactly where its placeholder is, on its own line as in the template; do not re-wrap surrounding text.

No scratch place exists → the `AGENTS.md` section is the heading plus `{{records-line}}` only.

---

## Rules

- **MUST** detect, show the change list, and wait for the user's approval before writing anything (step 4).
- **MUST** keep reruns a no-op: compare the rendered content with what is on disk; equal → skip silently.
- **NEVER** overwrite an existing README, `AGENTS.md` section, `CLAUDE.md` or `.gitignore` line — show a diff and ask.
- **NEVER** run `git rm`, `git add -f` or `git commit` in the target repo. If a scratch dir already has tracked files,
  report them and let the user decide; the ignore rule does not untrack them.
- **NEVER** add repository-specific content the repo does not already have; on merge, carry over only what the
  existing file already says.
- **NEVER** invent ADR/SDD formats — take them from the owning skill (see Places).

## Checklist

- [ ] Service name confirmed; aliases are `<service-name>-<kind>`, kind plural: `ideas`, `specs`, `plans`, `adrs`, `sdds`
- [ ] Every selected place has its README; `sdd` also has `0000-template.md`
- [ ] `.gitignore` has both lines per scratch place; `check-ignore` probes pass
- [ ] `AGENTS.md` section lists exactly the existing places
- [ ] No dead relative links in any written file
- [ ] Migration (if any) approved and applied per `MIGRATION.md`
- [ ] Second run reports nothing to do
