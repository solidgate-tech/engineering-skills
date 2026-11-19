---
name: roadmap-generator
description: >
  Build a lean initiative roadmap around a problem and the hypotheses the team will test against it. Output is a compact Markdown document — Outcome, Source (problem provenance), Hypotheses (IF–THEN–BECAUSE), and a Roadmap milestone table (Milestone | Goal | Roles | Estimate in sprints). Use whenever the user wants to turn a problem or hypotheses into a delivery roadmap, clean up a draft, or prepare one for team review. Trigger on "create a roadmap", "build a roadmap for this problem", "roadmap this", "clean up these milestones", "prepare a roadmap for review", or a problem/hypotheses shared with a request for delivery structure. Use this skill whenever a problem or hypothesis is present and the user wants any delivery plan, even if they don't say "roadmap".
---

# Roadmap Generator

Turn a **problem** — and the hypotheses to test against it — into a lean, reviewable roadmap. Anchored on the problem; each hypothesis is a track toward the outcome.

---

## Before you start

- **The format is built into this skill** — don't look it up elsewhere; generate directly.
- **Ask the user to share what they have:** the **problem** + its **outcome** (desired end state), the **source** behind it (impact · what hurts · refs such as ticket or survey IDs), the **hypotheses**, the **team available** (work-types + count, e.g. *"1 FE, 2 BE"*), the **sprints available** (for the span/fit check), and rough **per-milestone estimates in sprints**.
- **Ask the output format** — plain text or Markdown (default Markdown).
- Produce a draft to react to; don't interrogate. Fill gaps with sensible defaults and mark them for the user to correct.

---

## Output structure

The title is the **problem**. Then exactly these sections — nothing else:

1. **Outcome** — one line, the desired end state.
2. **Source** — where the problem comes from: impact · what hurts · refs.
3. **Hypotheses** — `#1..N`, each IF–THEN–BECAUSE.
4. **Roadmap** — a **Team:** line (work-types available), the milestone table, then a **Span:** line (total length + whether it fits).

No Success Criteria, kill criteria, dependencies, ICE, or SDD sections — keep it lean.

---

## Template

```markdown
# [Problem ID — short title]

## Outcome
[Desired end state, one sentence.]

## Source
- **Impact:** [who it hurts · scope, e.g. "4 product teams · top-voted item in the developer survey"]
- **What hurts:** [the concrete friction today]
- **Refs:** [ticket or survey IDs · discovery notes]

## Hypotheses
**#1:** IF [single change], THEN [metric] [rises/drops] from [baseline] to [target], BECAUSE [falsifiable belief].
**#2:** IF …, THEN …, BECAUSE …

## Roadmap
**Team:** [work-types available for this roadmap, e.g. 1 FE, 2 BE]

| Milestone | Goal | Roles | Estimate |
| --- | --- | --- | --- |
| M1 | [state that becomes true — "Users can X" / "Y now does Z"] | 1 FE, 2 BE | 0.5 sprint |
| M2 | … | … | … |

**Span:** [total, e.g. ~3 sprints (mostly serial) — fits the quarter]
```

---

## Rules

- **Problem-anchored.** Lead with the problem and its Outcome. Hypotheses are the tracks toward that outcome — reproduce them as given in IF–THEN–BECAUSE (convert rough wording cleanly). Don't re-grade hypothesis quality; that's the hypothesis skills' job. If a THEN is a feature state ("X is shipped") rather than a metric moving from a baseline to a target, mark it `[THEN needs a metric]` and suggest `hypothesis-critic` instead of rewriting it here.
- **Goal = state that becomes true. This is a hard requirement — never a task.**
  - Write it as a capability or system state that now exists, verifiable by anyone without asking the DRI.
  - The test: can someone confirm it by using the product or reading a dashboard — not by reading code or asking "is it done?"
  - Prefer: subject + can/is/does + what changed.

  | ✅ Good (state / capability) | ❌ Bad (task / activity) |
  |---|---|
  | New users can sign up with email or an invite link, with email verification | Build registration endpoints |
  | Admins can export any report as CSV from the report page | Implement CSV export |
  | Every service's logs are searchable in one place by request ID | Set up centralized logging |
  | Users can navigate search results with a sticky header | Add sticky header |
  | One shared lint config applies monorepo-wide; CI lints only changed files | Migrate packages to the shared lint config |

  If you catch yourself writing a verb like *add, set up, implement, migrate, configure, create, build* — stop. Rewrite as the state that results from that action.
- **Team line** heads the Roadmap — the work-types available (`Team: 1 FE, 2 BE`). Every milestone's **Roles** must come from it; if a milestone needs a work-type not on the Team line, flag it as a capacity gap, don't invent the role.
- **Roles = work-types + count** the milestone needs: `1 FE`, `2 BE`, `1 FS (js/ts)`, `1 Designer`. Always include a count, even for part-time/advisory roles (`1 Designer (part-time)`).
- **Estimate in sprints** (`0.5 sprint`, `1 sprint`, …), per milestone. Ask the user; propose drafts if absent.
- **Span line** closes the Roadmap — the total calendar length (account for what runs in parallel vs serial) and whether it fits the available sprints. If it overflows the quarter, say so plainly; don't pad or pretend it fits.
- **As few milestones as the work needs** — don't pad; merge granular ones; order so a prerequisite lands first.
- **No verification / measurement / sign-off milestone** — the result is tracked in the background, never its own milestone. The last milestone is the last delivery.
- **One problem and several hypotheses → one shared Roadmap.** Order milestones so a prerequisite hypothesis lands first; note inline if one gates another.

---

## Output style — keep it compact

Emit **only the filled sections** — no preamble, no explanation of your choices, no closing commentary. One line per table cell, each as few words as carry the meaning. Omit anything with nothing to say.

---

## Samples

Three filled roadmaps for a fictional company, Acme. Match the one closest to the work in front of you.

### Sample 1 — Problem with several hypotheses (DX / local dev)

```markdown
# P3 — Engineers queue for shared staging to test any change

## Outcome
Engineers validate most changes on their own machine before pushing.

## Source
- **Impact:** all 6 Acme product teams · top-voted item in the Q2 developer survey.
- **What hurts:** the Acme web app can't run locally (it needs a dozen backend services and real sign-in), so the loop is "implement → push → wait for CI → deploy to shared staging → click through". A 15-minute CI cycle stands in for instant local feedback, avoidable lint and type failures clog the pipeline, and teams queue for the two shared staging environments.
- **Refs:** PROJ-412 · developer survey Q2 #1, #4.

## Hypotheses
**#1:** IF engineers can run the web app locally against mocked backend services, THEN median time from first commit to merge drops from ~3 days to ~2 days, BECAUSE most of that time is the push → staging → fix loop, not waiting for review.
**#2:** IF lint, type checks and unit tests run on changed packages in a pre-push hook, THEN the share of CI runs failing on lint or type errors drops from ~25% to under 5%, BECAUSE those failures come from checks engineers skip locally, not from differences between laptops and CI.
**#3:** IF every merge request gets its own short-lived preview environment, THEN median wait for a staging slot drops from ~4 h to under 15 min, BECAUSE most staging bookings are for manual click-through checks a preview environment can host.

## Roadmap
**Team:** 1 FE, 2 BE

| Milestone | Goal | Roles | Estimate |
| --- | --- | --- | --- |
| M1 | The web app runs locally against mocked backend services with one command | 1 FE, 1 BE | 1 sprint |
| M2 | A pre-push hook runs lint, type checks and unit tests on changed packages | 1 FE | 0.5 sprint |
| M3 | Every merge request gets a short-lived preview environment that reuses M1's service mocks | 2 BE | 1.5 sprints |

**Span:** ~2.5 sprints (M2 and M3 run in parallel after M1) — fits the quarter.
```

### Sample 2 — Single hypothesis with real design work

```markdown
# P8 — Every team rebuilds the same settings pages

## Outcome
Teams ship settings pages from a shared kit instead of building them from scratch.

## Source
- **Impact:** 4 Acme product teams · slow, inconsistent settings UI.
- **What hurts:** every new settings page re-implements the same forms, tables and empty states, so one page takes about two weeks to ship and each looks slightly different.
- **Refs:** PROJ-388 · Q2 design review notes.

## Hypotheses
**#1:** IF teams build settings pages from a shared kit of components plus ready-made list and detail pages, THEN median time to ship a new settings page drops from ~10 working days to ~4, BECAUSE most settings pages follow the same list-and-detail pattern a default can cover.

## Roadmap
**Team:** 1 FE, 1 BE, 1 Designer (part-time)

| Milestone | Goal | Roles | Estimate |
| --- | --- | --- | --- |
| M1 | Component API + Figma kit agreed (real design work) | 1 FE, 1 Designer (part-time) | 0.5 sprint |
| M2 | Shared components available for use (package + Storybook) | 1 FE | 1 sprint |
| M3 | Ready-made list and detail pages, backed by a generic settings API, available to every team | 1 FE, 1 BE | 0.5 sprint |

**Span:** ~2 sprints (serial) — fits the quarter; BE and Designer part-time, free for other work.
```

### Sample 3 — Two hypotheses, one gating the other

```markdown
# P12 — Merged work waits days for the weekly release

## Outcome
Merged changes reach customers the same day, and a bad one is cheap to undo.

## Source
- **Impact:** all Acme backend teams · merged work waits up to 5 days to ship.
- **What hurts:** services deploy in one weekly batch because rolling back a single service is manual and slow; one bad change holds up the whole batch.
- **Refs:** PROJ-503 · last three incident reviews.

## Hypotheses
**#1:** IF any service can be rolled back to its previous release with one command, THEN failed-deployment recovery time drops from ~60 min to under 10 min, BECAUSE most of today's recovery time goes into rebuilding the previous version, not into diagnosing the failure.
**#2:** IF services deploy automatically on merge instead of in the weekly batch, THEN lead time for changes drops from ~4 days to under 1 day, BECAUSE merged work waits longest in the weekly batch, not in review or CI.
_#1 gates #2 — teams accept deploy-on-merge only once a bad deploy is cheap to undo, so its milestone lands first._

## Roadmap
**Team:** 2 BE, 1 DevOps

| Milestone | Goal | Roles | Estimate |
| --- | --- | --- | --- |
| M1 | Any service can be rolled back to its previous release with one command | 1 BE, 1 DevOps | 1 sprint |
| M2 | Three pilot services deploy automatically on merge | 1 BE, 1 DevOps | 0.5 sprint |
| M3 | All backend services deploy on merge; the weekly batch is retired | 2 BE | 1 sprint |

**Span:** ~2.5 sprints (serial — #1 gates #2) — fits the quarter.
```
