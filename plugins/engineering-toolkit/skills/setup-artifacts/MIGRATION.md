# Migrating existing ADRs and SDDs

Loaded from step 3 of [`SKILL.md`](./SKILL.md) when detection finds decision or design documents that are not yet
correctly formatted records in `docs/adr/` or `docs/sdd/`. The target format — template, frontmatter, index README,
row format, status lifecycle — comes from the `architecture-decision-records` and `software-design-document` skills.
Consult them; never reconstruct the format from memory.

**Core rule: move, never rewrite.** Migration changes where a record lives and how it is structured, never what it
says. No rewording, no summarizing, no merging of paragraphs, no dropped text. An `Accepted` / `Approved` record's
decisions are especially untouchable: reformatting is allowed, changing meaning is not.

## 1. Classify

For each candidate decide ADR or SDD using the "When to use" tables of the two skills: one decision with its rationale
→ ADR; a full design (requirements, solution, roadmap) → SDD. A file that is neither (runbook, meeting notes) is not
migrated — report it. Ask about anything ambiguous.

Candidates already in `docs/adr/` or `docs/sdd/` are migrated in place: only their frontmatter, headings and index
are brought in line.

## 2. Number

- Keep the existing number if the file has one and it does not collide within its target directory.
- On collision the record with the earlier `created_at` keeps the number; the other gets the next free one.
- Records without a number get the next free numbers, in chronological order of creation date (see step 3).
- `0000` is reserved for the SDD template.
- File name: `NNNN-short-kebab-title.md`, title taken from the document's own heading.

## 3. Map frontmatter

Fill the owning skill's template frontmatter from what the document already says. Never invent a value: unknown keys
stay empty (`reviewers: []`, `epic:`, `tier:`).

| Key          | Source                                                                                      |
| ------------ | ------------------------------------------------------------------------------------------- |
| `title`      | Existing heading, with the `[ADR]` / `[SDD]` prefix the template uses                       |
| `alias`      | File name without `NNNN-` and `.md`                                                         |
| `parent`     | `<service-name>-adrs` / `<service-name>-sdds`                                               |
| `status`     | Mapping below                                                                               |
| `authors`    | Existing author field; else first-commit author: `git log --diff-filter=A --format='%an <%ae>' -- <file> \| tail -1` |
| `created_at` | Existing date field; else first-commit date: `git log --diff-filter=A --format=%as -- <file> \| tail -1` |
| `approved_at`| Existing approval / decision date for final statuses; else empty                            |
| `review_deadline` | Existing value; else empty                                                             |

**Status mapping.** A status already in the owning skill's lifecycle is kept as is (including SDD `In review`).
Final statuses from other conventions map one-to-one:
- ADR: `Accepted`, `Deprecated`, `Superseded`, `Rejected`.
- SDD: `Approved`, `Deprecated`, `Superseded`, `Rejected`. An ADR-style `Accepted` on an SDD becomes `Approved`.

Anything else — `Proposed`, `Draft`, `RFC`, `In discussion`, unknown or missing — becomes `WIP` and is
flagged **needs review** in the mapping table, so the user decides per record.

## 4. Map the body

Move each existing section under the template heading it matches (e.g. MADR "Context and Problem Statement" →
`## Context`, "Decision Outcome" → `## Decision`, "Pros and Cons of the Options" → `## Rationale`). Keep the original
text verbatim under the new heading.

- Content with no matching section goes under `## Resources` (ADR) or `## Notes` (SDD), in original order.
- Template sections the record never had get one line: `_Not recorded at the time of the decision._` — never
  fabricated content.
- Drop the template's HTML guidance comments from migrated files; they are for new documents.

## 5. Show the mapping table — approval gate

Before writing anything, show one table and the per-file diffs:

| Old path | New path | # | Type | Old status → New status | Notes |
| -------- | -------- | - | ---- | ----------------------- | ----- |
| `docs/decisions/001-use-kafka.md` | `docs/adr/0001-use-kafka.md` | 0001 | ADR | Accepted → Accepted | |
| `docs/design/retry.md` | `docs/sdd/0001-retry.md` | 0001 | SDD | — → WIP | **needs review** |

**Then stop and end your turn.** Move or write nothing until the user approves; they may change any row.

## 6. Move and rewrite

- Tracked file: `git mv <old> <new>` (keeps history), then write the reformatted content to `<new>`.
- Untracked file: plain `mv`.
- Never `git rm`, never `git commit`. Leave an emptied old directory in place only if it still holds non-migrated
  files; otherwise remove the empty directory.

## 7. Index and links

- Rebuild `docs/adr/README.md` / `docs/sdd/README.md` from the owning skill's Index README section, one row per
  record ordered by number, `Created` = `created_at`. If the index already existed, carry over any extra prose it had
  (the merge rule from step 4 of `SKILL.md`); the table columns are always the skill's.
- Fix inbound links across the repo: `git grep -l '<old-path-or-filename>'` and rewrite each link to the new relative
  path. Report links outside the repo (Confluence, Jira) as manual follow-ups — they cannot be fixed from here.

## Verify

- Every original paragraph is still present: for each migrated file, compare the old text (`git show HEAD:<old>` for tracked
  files; for untracked ones, a copy saved to the scratchpad before `mv`) with the new one after stripping frontmatter, headings and blank lines; nothing from the old side may be missing.
- Every index row links to an existing file, and every record has a row.
- `git grep` for each old path returns nothing but historical mentions the user chose to keep.
