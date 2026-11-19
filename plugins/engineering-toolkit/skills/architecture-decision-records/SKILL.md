---
name: architecture-decision-records
description: "Creates and maintains Architecture Decision Records (ADRs) that capture the context and rationale behind significant technical decisions. Use when making or documenting architectural choices, technology selections, design trade-offs, or conventions that affect the whole team. Trigger terms: ADR, architecture decision, tech choice, design decision, document decision, record convention. To bootstrap docs/adr or migrate existing ADRs, use setup-artifacts."
---

## When to use

| Write ADR                                 | Skip ADR               |
| ----------------------------------------- | ---------------------- |
| Adopting a new framework or library       | Minor version upgrades |
| Choosing between architectural patterns   | Bug fixes              |
| Establishing repo-wide conventions        | Implementation details |
| API or integration design choices         | Routine maintenance    |
| Replacing or deprecating a prior decision | Configuration changes  |
| Security or data-handling approach        | Small refactors        |

An ADR is warranted when all three are true: hard to reverse, surprising without context, and the result of a real trade-off between alternatives.

---

## Mechanical process

If the request is vague, ask for missing context before drafting:

```text
WHAT I NEED TO DRAFT THIS ADR:
1. What problem or limitation triggered this decision?
2. What options were considered (at least 2)?
3. What was actually decided?
4. Who are the authors / reviewers?
5. Is there a Jira epic to link?
→ Answer what you know; I'll fill in the rest.
```

Only ask for what's missing — if most context is already present, proceed.

1. **Number** — scan `docs/adr/` for the highest `NNNN-*.md`, use the next one
2. **File** — create `docs/adr/NNNN-short-kebab-title.md` from [`TEMPLATE.md`](./TEMPLATE.md)
3. **Frontmatter** — fill `created_at` (today), `review_deadline` (+14 days), `status: "WIP"`, `authors` (from `git log --format="%an <%ae>" -1`), and `tier` only if the org uses availability tiers (else leave it empty)
4. **Index** — add a row to the ADR table in `docs/adr/README.md` (create it from [Index README](#index-readme) if missing):

   ```markdown
   | [NNNN](./NNNN-short-kebab-title.md) | Short Descriptive Title | WIP | YYYY-MM-DD |
   ```

   The date is `created_at`. Keep the Status cell in sync with the frontmatter when the status changes.
5. **Assumptions** — after drafting, state any assumptions made so the author can correct them before review
6. **Ordering** — order decisions by impact: the decision that causes the most harm if wrong goes first. Order Context
   and Rationale by reasoning dependency: what others build on comes first. Rationale order may therefore differ from
   Decision order; citations keep them linked
7. **Decision structure** — if the decision list exceeds five items, group by concern using `###` subheadings

---

## Three writing principles

Every section rule in this skill derives from one of three principles. Apply the principle; don't memorise the rules.

### 1. Problems before decisions

Context is a list of named problems, not an architectural description. Write it so a reader can point to each sentence and ask "which decision solves this?" Draft Context first. After writing Decision, audit every decision against Context — any decision without a backing problem requires adding the problem to Context first. A decision with no named problem in Context is a decision without a reason.

> Do not write "we considered X because..." in Context — that belongs in Rationale.

**Context items are premises.** Number them. Each is a fact or constraint that is true before any decision in this ADR
and stands on its own. A problem that exists only because of a decision below is a derived constraint, not a premise:
cite it in Rationale as following from that decision, or keep it in Context after the premises, marked
`(conditional on Decision N)`.

Order Context by reasoning dependency — foundational constraints first, the ones that build on them after — never by
discovery chronology ("first we tried X, then found Y").

```text
Before
  Context:  1. Entity history is not searchable: events are stored under the acting admin.
            2. Owners live in different domain services.
            3. A lookup per audited call costs latency.
  Decision: 1. Resolve owners centrally, one lookup per object type.
            2. Owner resolution MUST be fast.

After
  Context:  1. Entity history is not searchable: events are stored under the acting admin.
            2. Owners live in different domain services.
  Decision: 1. Resolve owners centrally, one lookup per object type.
            2. Owner resolution MUST run off the request path.
  Rationale:
    **Central registry (Decision 1; Context 1, 2):** ...
    **Off the request path (Decision 2; follows from Decision 1):** a lookup per audited call adds latency ...
```

Context 3 existed only because of Decision 1, and Decision 2 restated it as a goal.

### 2. Decisions are positive statements; rejected alternatives are Rationale

The Decision section states what you are doing, using RFC 2119 keywords (`MUST` / `SHOULD` / `MAY`). Reasoning, trade-offs, and rejected alternatives all belong in Rationale.

Each decision is a conclusion drawn from premises, not a premise restated. "Lookups are slow" → "lookups MUST be fast"
is a goal: state what you do to meet it. In Rationale, head each decision's reasoning with what it rests on:
`**Name (Decision N; Context A, B):**`, or `(Decision N; follows from Decision M)` for a decision that answers a
derived constraint.

Choose the weakest keyword that correctly describes the constraint's durability. MUST closes a door permanently; SHOULD leaves it open with a strong preference. Overusing MUST encodes false certainty and forecloses legitimate future alternatives.

Mechanism details also belong in Rationale, not Decision: specific tool names, command syntax, file paths, and endpoint names describe how a constraint is currently implemented, not the constraint itself. A decision states a durable constraint; Rationale may describe its current implementation.

**Negative constraints in Decision** must guard an active positive decision against reversion. A negative that stands alone — without a corresponding positive decision it protects — is a rejected alternative and belongs in Rationale.

Test: can you point to the positive decision it guards? If not, move it to Rationale as **Why not [alternative]**.

For every significant alternative, add an explicit **Why not [alternative]:** subsection in Rationale directly after the decision's main reasoning:

```text
**Use ConnectRPC (Decision 1; Context 1):** Generates TypeScript types from proto, eliminating
schema drift between frontend and backend contracts.

**Why not REST + OpenAPI:** Required maintaining two separate schemas
that drifted in practice and caused client/server type mismatches.
```

### 3. Both sides of every trade-off must be visible

Consequences split into **Easier** (what improves) and **Harder** (what gets worse or is introduced). If Harder is empty, you haven't thought hard enough.

---

## Review checklist

### Before submitting

- [ ] Every decision traces to a named problem in Context — no unbacked decisions
- [ ] No decision is a direct consequence of another decision already in the list — implied results belong in Rationale, not as standalone decisions. A decision that chooses how to meet a constraint another decision created is still a decision
- [ ] Context holds premises only: no item exists because of a decision in this ADR unless marked `(conditional on Decision N)`, and items follow dependency order, not discovery order
- [ ] No decision restates a single Context item as MUST/SHOULD
- [ ] Every Context item is cited by at least one Rationale heading — an uncited item is noise or a missing decision
- [ ] Every Decision number is cited in a Rationale heading with the Context items it rests on (or the decision it follows from)
- [ ] Decision section contains only positive MUST/SHOULD/MAY statements — no rationale, no rejected alternatives encoded as MUST NOT
- [ ] Rationale has a **Why not X:** subsection for each significant alternative considered
- [ ] Consequences has at least one item in **Harder**
- [ ] Fault tolerance: operational dependencies documented, or section omitted
- [ ] SLO/SLI: service commitments defined, or section omitted
- [ ] Security: PCI DSS/sensitive data impact assessed, or section omitted
- [ ] Each insight appears once — if two sections or formats cover the same ground, cut one
- [ ] Related ADRs linked in Resources

### During review

- [ ] At least 2 relevant engineers have reviewed
- [ ] Affected teams were consulted
- [ ] Any new infrastructure dependencies documented

### After acceptance

- [ ] Status updated to `Accepted`, `approved_at` filled in
- [ ] Row in `docs/adr/README.md` updated
- [ ] Superseded ADRs updated with a link to this one

---

## Common patterns

### Deprecating a prior decision

Add the old ADR number to `supersedes` in frontmatter and note in Resources. Open Consequences > **Easier** with "Resolves issue from ADR-NNNN."

### Establishing a convention

Keep scope narrow — one pattern per ADR. Use `SHOULD` rather than `MUST` for conventions that allow project-level deviation.

### RFC mode

Draft Context + proposed Decision only, mark `status: WIP`. Complete Rationale and Consequences once consensus forms before merging.

---

## Document structure

Use [`TEMPLATE.md`](./TEMPLATE.md) as the starting document. It contains the full frontmatter schema and all required sections.

Status lifecycle: `WIP → Accepted → Deprecated → Superseded` (or `WIP → Rejected`). Never edit an Accepted ADR's decisions — write a new ADR to supersede it.

`parent` in every ADR is `<service-name>-adrs` — the repository name in lower-case kebab (e.g. `payments-api-adrs`). It
matches the `alias` of the index below.

---

## Index README

`docs/adr/README.md` lists every ADR in the repository. Create it with this content when it is missing; `<PREFIX>` is
the service name upper-cased (e.g. `PAYMENTS-API`):

```markdown
---
title: "[<PREFIX>] Architecture Decision Records"
alias: "<service-name>-adrs"
---

# Architecture Decision Records

Significant technical decisions for <service-name>, with the context and trade-offs behind them. Write new ones with
the `architecture-decision-records` skill.

| # | Title | Status | Created |
|---|-------|--------|---------|
| — | _none yet_ | | |

Status lifecycle: `WIP → Accepted → Deprecated → Superseded` (or `WIP → Rejected`). An accepted ADR's decisions are
never edited — write a new ADR that supersedes it.
```

Replace the `_none yet_` row with the first real row. Rows are ordered by number.
