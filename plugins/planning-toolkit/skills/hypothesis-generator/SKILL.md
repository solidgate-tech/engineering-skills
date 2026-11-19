---
name: hypothesis-generator
description: >
  Generate multiple well-formed IF–THEN–BECAUSE hypotheses from a problem statement, user insight, or engineering challenge, oriented to platform-engineering quarter planning. Use this skill whenever the user wants to explore solution space for a problem, generate hypotheses to prioritize, brainstorm approaches to a challenge, or prepare hypotheses for quarter planning. Trigger when the user says things like "generate hypotheses for...", "what could we test to solve...", "help me come up with hypotheses about...", "we have this problem, what should we try?", or shares a problem statement and wants testable ideas. Always generate a diverse set covering different approaches — don't cluster around one solution type.
---

# Hypothesis Generator

Generate a diverse, well-formed set of IF–THEN–BECAUSE hypotheses from a problem statement, oriented to platform-engineering quarter planning. Each hypothesis must be immediately testable, ladder to a metric family the team tracks, cover a distinct approach, and clear the quality gates before being shown.

---

## Before you start

**Ask which mode the user wants:**
- **Focused** — one strong hypothesis for a known problem.
- **Shortlist** — 3–5 options spanning different approaches to choose from.

If unspecified, default to a **shortlist of 3–5** (never more than 5). Don't dump 6–10 throwaway hypotheses that get discarded.

**Two hard prohibitions:**
- **Never look up a template.** The IF–THEN–BECAUSE template is defined in this skill — generate directly.
- **Never compute ICE.** Impact/Confidence/Effort is scored by the team, not by this skill. Do not invent or estimate ICE scores. If a slot is expected, emit `ICE: (team to score)` and nothing more.

### Where to start — two entry points

Figure out which one the user is bringing, and ask if it's unclear.

**A. Problem-first (a defined problem).** The user names an existing, agreed problem. Capture:
- **Statement** — the problem itself
- **Outcome** — the desired end state
- **Component** — the area it belongs to (e.g. Authentication, CI pipeline, Design system, Notifications, Audit log)
- **Impacted audience** — who feels it

Then:
- Treat the Statement + Outcome as **fixed** — don't re-derive the problem or substitute a different one.
- Scope every hypothesis to the named **Component**.
- Every IF must be a concrete step toward the defined **Outcome**.
- If the user gives only a Statement, ask for (or infer and flag) its Outcome and Component before generating.

**B. Idea-first (no defined problem, just ideas).** The user has one or more rough ideas/solutions but no agreed problem. Work backward:
- For each idea, name the **problem it implies** and the **Component** it touches.
- State that inferred problem back to the user explicitly so they can correct it before you generate.
- Then turn the idea into a proper hypothesis — the idea is a candidate IF; you still supply the measurable THEN and the falsifiable BECAUSE.

In both cases the **Outcome is only the qualitative target** — the THEN must still add a measurable metric (Step 3) so the hypothesis is falsifiable. A feature-state outcome alone does not satisfy the THEN gate.

---

## Framework Reference

Every hypothesis follows IF–THEN–BECAUSE:

**IF** — a single, shippable change (not a tech-stack checklist)  
**THEN** — a measurable outcome: a real metric the team tracks, with direction and magnitude (from → to)  
**BECAUSE** — the falsifiable belief that makes the causal link plausible

Every hypothesis must ladder its THEN to one **metric family** (see the matrix in Step 2).

---

## Generation Strategy

### Step 1 — Extract the problem core
Before generating, identify:
- **Who** feels the problem (which team, service, or user group)
- **What** it costs (a metric, dev time, an incident class, a compliance gap)
- **Where** in the system/pipeline it happens (CI stage, endpoint, SDK, UI screen)
- **Why** it might be happening (multiple competing causes)

If the problem statement is ambiguous, state your interpretation explicitly before proceeding.

**If the problem already comes with a defined Outcome, Component, and audience**, Step 1 is already answered — use them as given and go straight to divergence (Step 2). Don't re-litigate the problem.

### Step 2 — Diverge across metric families
Every hypothesis must move a metric in one of these families. They follow public frameworks — DORA for delivery and stability, SPACE for developer experience, HEART for product — so they map onto most teams' dashboards. Use this matrix to span different families — aim for coverage, not clustering on one:

| Metric family | Lens question | Example metrics to anchor THEN |
|---|---|---|
| **Delivery** (DORA throughput) | Are we shipping slower than we could? | Lead time for changes, Deployment frequency, CI pipeline duration, Merge-request review time |
| **Stability** (DORA stability, SRE) | Do changes and services hold up in production? | Change failure rate, Failed-deployment recovery time, SLO attainment / availability, Latency P95/P99 |
| **Developer experience** (SPACE) | Is everyday engineering work harder than it needs to be? | Developer satisfaction score, Hours lost to friction per week, Time to first merged change for new hires, Build and test wait time |
| **Security** | Is access controlled, audited, and patched? | Time to remediate critical vulnerabilities, Audit-log coverage %, Share of dependencies on supported versions, Share of repos with secret scanning |
| **Product** (HEART) | Do people adopt and succeed with what we ship? | Adoption rate, Activation rate, Task success rate, Time on task, Retention |

Don't force all families — only use ones genuinely relevant to the problem. 3–5 hypotheses is the ideal range for a shortlist (or 1 in focused mode). The listed metrics are starting points: when the team already tracks an equivalent under its own name, use the team's name. Generalize beyond the list only when the problem genuinely needs it, and still name the family it ladders to.

### Step 3 — Write each clause to clear its gate

These are **blocking gates, not soft preferences**. Do not show a hypothesis to the user until every gate passes — rewrite first.

**IF gate**
- Names a single, shippable change. ✅ "run type checks on changed packages in a pre-push hook"
- ❌ Reject tech-stack enumeration: "Husky + lint-staged + tsc + CI lint". If the IF reads as an implementation checklist, collapse it to the one change being made.
- Include the affected segment/service when the change is targeted.

**THEN gate**
- Must name a concrete number that would visibly move on a **named dashboard metric** — `from → to`, or a relative range when no baseline exists.
- ❌ Reject feature-state outcomes: "the new pipeline is live", "teams can see assignments", "increase observability". Those describe a shipped feature, not a measured outcome.
- The metric must be a real metric the team tracks that ladders to one family (Step 2).
- Tie to a timeframe where it matters ("within the quarter").

**BECAUSE gate**
- Discriminator: *"Would this statement still be true after IF ships?"* If yes, it's a restatement of the problem — not a falsifiable belief. Rewrite it into the specific, potentially-wrong assumption being tested.
- One belief only — no "and".

### Step 4 — Contrastive reference (calibrate against these)

| Clause | ✅ Strong | ❌ Weak |
|---|---|---|
| THEN | "pipeline time drops from ~40 min to ~20–25 min" | "we will increase observability" |
| THEN | "time to ship a navigation change drops from ~5 h to ~1 h" | "improve stability and unlock features" (no number) |
| BECAUSE | "most pipeline time is spent rebuilding packages that haven't changed" | "slow pipelines hurt productivity" (restates the problem) |
| IF | "replace per-app navigation with one shared side-nav component" | "Husky + lint-staged + tsc + CI lint" (stack list) |

---

## Output Format

**Keep every hypothesis compact and precise.** The whole hypothesis is a **single sentence** — one `IF …, THEN …, BECAUSE …` line, not three. Each supporting line (Metric family, Riskiest assumption, Suggested minimum test) is one line. Include exactly enough to understand and test it — no padding, no multi-paragraph justifications. A reader should grasp the whole thing at a glance.

### Problem interpretation
One sentence: restate what you understood the core problem to be. Flag any assumptions made.

### Hypotheses

For each hypothesis:

**H[N] — [2–4 word label describing the approach]**
> IF [single shippable change], THEN [team metric] will [direction] from [baseline] to [target] [timeframe], BECAUSE [specific falsifiable belief].

**Metric family:** the one family this moves most (Delivery / Stability / Developer experience / Security / Product), with the metric in brackets. Note a secondary only if the change genuinely spans two.  
**Riskiest assumption:** the belief in BECAUSE that is most likely to be wrong.  
**Suggested minimum test:** the smallest experiment that could invalidate this hypothesis.  
*(Label speculative high-upside bets `[Bold bet]` rather than softening the wording.)*

---

### Coverage map
After all hypotheses, map each to its metric family — this helps the team see if they're over-indexed on one family.

| Hypothesis | Metric family |
|---|---|
| H1 — [label] | Delivery |
| H2 — [label] | Security |
| ... | ... |

---

### What's not covered
Call out 1–2 families that were intentionally skipped and briefly why — this prevents the team from assuming the list is exhaustive.

---

## Tone & Style

- Be specific enough that an engineer could write a ticket from each hypothesis without asking a follow-up question
- Don't hedge excessively — commit to a direction even under uncertainty
- Favor metrics the team already tracks over inventing new ones
- Never generate duplicate hypotheses that test the same root cause
- Be compact — a hypothesis is one IF–THEN–BECAUSE sentence plus one-line support, not an essay. Trim anything that isn't needed to understand or test it

---

## Example

**Input:** "Our monorepo CI pipeline takes ~40 minutes, slowing every release."

**Problem interpretation:** End-to-end CI time on the frontend monorepo is the primary bottleneck on release velocity — work is rebuilt from scratch on every run regardless of what actually changed.

---

**H1 — Remote build caching**
> IF we enable a remote build cache shared by every CI run on the monorepo, THEN median end-to-end pipeline time will drop from ~40 min to ~20–25 min within the quarter, BECAUSE most of today's ~40 min is spent rebuilding packages that haven't changed since the last green run.

**Metric family:** Delivery (CI pipeline duration → lead time for changes).  
**Riskiest assumption:** the cache hit rate is high enough in practice that most runs actually skip rebuilds.  
**Suggested minimum test:** turn the remote cache on for the three slowest packages for two weeks; compare their median build time and cache hit rate with the two weeks before.

---

**H2 — Catch breakage before main**
> IF we run Playwright end-to-end tests for the five user flows behind most rollbacks on every merge request, THEN the monorepo's change failure rate will drop from ~18% to under 10% within the quarter, BECAUSE most failed changes break at integration points between packages that component tests don't exercise.

**Metric family:** Stability (change failure rate).  
**Riskiest assumption:** the failing flows are integration-level defects, not unit-level ones.  
**Suggested minimum test:** classify the root cause of the last 20 rollbacks; if fewer than half are integration defects, drop this hypothesis before writing a single test.

---

**Coverage map**

| Hypothesis | Metric family |
|---|---|
| H1 — Remote build caching | Delivery |
| H2 — Catch breakage before main | Stability |

**What's not covered:** Security (no access-control or audit hypothesis — this pipeline-speed problem doesn't touch it) and Product (CI time is invisible to end users; any effect on them would show up only indirectly, through faster releases).
