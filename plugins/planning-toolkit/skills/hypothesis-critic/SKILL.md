---
name: hypothesis-critic
description: >
  Give structured, constructive criticism on a business, product, or platform-engineering hypothesis using the IF–THEN–BECAUSE framework. Use this skill whenever the user shares a hypothesis and asks for feedback, critique, review, or improvement — even if they just say "what do you think of this hypothesis?" or "can you improve this?". Also trigger when the user pastes something that looks like a hypothesis (contains "if", "then", "because", or a causal structure) and seems to want evaluation. Always apply this skill before helping rewrite or improve a hypothesis.
---

# Hypothesis Critic

Give constructive, specific criticism on hypothesis wording using the IF–THEN–BECAUSE framework. Be direct, practical, and actionable — not just diagnostic. Hold every hypothesis to the same standard a well-formed one would meet: a single shippable change, a measurable outcome on a real metric, and a falsifiable belief.

---

## Framework Reference

A well-formed hypothesis has three parts:

**IF** — a single, shippable change (not a tech-stack checklist)  
**THEN** — a measurable outcome: a real team-tracked metric, with direction and magnitude (from → to)  
**BECAUSE** — the falsifiable belief that makes the causal link plausible

The THEN must ladder to one **metric family**. Use this catalogue (DORA for delivery and stability, SPACE for developer experience, HEART for product) when judging whether the metric is real and which family it serves:

| Metric family | Example metrics |
|---|---|
| **Delivery** | Lead time for changes, Deployment frequency, CI pipeline duration, Merge-request review time |
| **Stability** | Change failure rate, Failed-deployment recovery time, SLO attainment / availability, Latency P95/P99 |
| **Developer experience** | Developer satisfaction score, Hours lost to friction per week, Time to first merged change for new hires, Build and test wait time |
| **Security** | Time to remediate critical vulnerabilities, Audit-log coverage %, Share of dependencies on supported versions, Share of repos with secret scanning |
| **Product** | Adoption rate, Activation rate, Task success rate, Time on task, Retention |

Teams often track these under their own names — accept the team's equivalent. If the hypothesis is genuinely in another domain, judge the metric on the same principle — is it real, tracked, and tied to a direction + magnitude — rather than forcing it into this table.

---

## Evaluation Rubric

Score each dimension and give specific feedback:

### 1. IF clause
- ❌ Vague if it names a category ("improve the release process") instead of a specific change
- ❌ **Tech-stack enumeration** — an implementation checklist ("Husky + lint-staged + tsc + CI lint") is not a hypothesis change. Say so and collapse it to the single change being made ("run type checks on changed packages in a pre-push hook").
- ❌ Weak if it doesn't specify who/what is affected (the segment, service, or screen) when relevant
- ✅ Strong if the team could ship exactly this without further clarification

### 2. THEN clause
- ❌ **Feature-state outcome** (most common failure) — describes a shipped feature or deliverable, not a measured result: "the new pipeline is live", "teams can see assignments", "increase observability", "migrated to the new framework". A THEN that the IF makes automatically true is tautological and untestable.
- ❌ Vague if the metric isn't real or tracked ("engagement", "satisfaction")
- ❌ Weak if direction is missing ("CFR will change")
- ❌ Weak if no baseline or target magnitude is referenced
- ✅ Strong if it reads "[real team metric] will [increase/decrease] from [baseline] to [target]" and that metric ladders to a family (Delivery / Stability / Developer experience / Security / Product)

### 3. BECAUSE clause
- ❌ Missing entirely
- ❌ **Restatement of the problem** — apply the discriminator: *"Would this BECAUSE still be true after the IF ships?"* If yes, it's just the problem restated ("slow pipelines hurt productivity"), not a belief being tested. A real BECAUSE names a specific assumption that the outcome could prove wrong.
- ❌ Trivially obvious ("because faster pipelines are better")
- ❌ Multiple beliefs bundled with "and"
- ✅ Strong if it names a specific, potentially wrong belief about user behavior, system behavior, or where a problem actually originates

### 4. Falsifiability
- ❌ No threshold where the hypothesis would be proven wrong
- ✅ Strong if there's an implicit or explicit "if X doesn't move, we stop / we were wrong"

### 5. Scope
- ❌ Multiple variables tested simultaneously
- ✅ One change, one outcome

---

## Output Format

Structure your critique as follows:

**Overall verdict** — one sentence: is this hypothesis ready, needs minor work, or needs a rewrite?

**IF** — [✅ / ⚠️ / ❌] brief judgment + specific issue if any

**THEN** — [✅ / ⚠️ / ❌] brief judgment + specific issue if any

**BECAUSE** — [✅ / ⚠️ / ❌] brief judgment + specific issue if any

**Falsifiability** — [✅ / ⚠️ / ❌] brief judgment

**Top 1–2 improvements** — concrete, specific rewrites or questions to answer before the hypothesis is ready

**Suggested rewrite** — always offer a stronger version, even if the original is mostly good. Show exactly what changed and why.

---

## Tone Guidelines

- Be direct, not harsh. Name the problem, not the person.
- Lead with what works before what doesn't (unless nothing works).
- Always end with a rewrite — criticism without a path forward is just noise.
- If the hypothesis is genuinely strong, say so clearly. Don't invent problems.
- Use the language of the user's domain (don't translate "change failure rate" to "stability" — keep their metric names).
- Keep it compact. Each rubric judgment is one or two sentences; the rewritten hypothesis is a single IF–THEN–BECAUSE sentence (one line, not three). Say only what's needed to make the issue and the fix clear — no padding.

---

## Example

**Input hypothesis:**
> IF we split the monolith into microservices, THEN the monolith will be split, BECAUSE the monolith is bad.

**Output:**

**Overall verdict:** Needs a rewrite — the THEN is tautological and the BECAUSE just restates the problem, so there's nothing to test yet.

**IF** ⚠️ "Split the monolith into microservices" is a program, not one shippable change. Name the first concrete step (extract the notifications module into its own independently deployable service) so it can ship and be measured on its own.

**THEN** ❌ "The monolith will be split" is a **feature-state outcome** — it restates the IF. Once you ship the split it's automatically true, so it can't be measured or falsified. Name the metric the split exists to move — for a decomposition that's usually how often the owning team can ship (Delivery: deployment frequency).

**BECAUSE** ❌ "The monolith is bad" survives the discriminator — it's still believed after the split ships, so it's a problem statement, not a testable belief. What specifically do you believe the monolith *causes* that a separate service fixes?

**Falsifiability** ❌ Nothing here could come back false.

**Top improvements:**
1. Replace the feature-state THEN with a Delivery metric and a from→to target — deployment frequency for the team that owns notifications. Keep change failure rate on the dashboard as a guardrail, not as a second THEN.
2. Rewrite the BECAUSE into a belief about *where that team's changes actually wait* (the shared monolith release vs. their own review and tests), which the outcome can prove wrong.

**Suggested rewrite:**
> IF we extract the notifications module from the monolith into its own independently deployable service, THEN the notifications team's deployment frequency will rise from ~1 per week to at least 1 per day within the quarter, BECAUSE their changes wait mostly on the shared monolith release, not on their own review or tests.
