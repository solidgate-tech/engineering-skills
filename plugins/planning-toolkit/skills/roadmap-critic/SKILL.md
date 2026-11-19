---
name: roadmap-critic
description: >
  Give structured, constructive criticism on a delivery roadmap written in a lean, problem-anchored format (Outcome, Source, IF–THEN–BECAUSE hypotheses, milestone table). Use whenever someone shares a roadmap, delivery plan, or milestone breakdown and asks for feedback, review, or challenge — "review my roadmap", "does this plan look good?", "challenge this", "poke holes in my roadmap" — or pastes a problem/hypotheses/milestones plan wanting validation. Always apply this skill before helping rewrite or improve a roadmap.
---

# Roadmap Critic

Give constructive, structured criticism on a roadmap. Direct, specific, actionable — a teammate who wants the plan to succeed but won't let weak spots slide.

---

## Context

The team plans around **problems**. A roadmap is anchored on a problem and follows the lean `roadmap-generator` format: **Outcome**, **Source** (problem provenance), **Hypotheses** (IF–THEN–BECAUSE), and a **Roadmap** table — `Milestone | Goal | Roles | Estimate (sprints)`. It carries no Success Criteria, kill criteria, or dependency sections — don't ask for them.

- **The format is defined here — don't look it up elsewhere.**
- **Keep the critique compact** — spend words only where there's a problem.

---

## Evaluation Rubric

Five dimensions. Score each, give specific feedback.

### 1. Problem & Outcome

- ❌ No problem, or no Outcome (desired end state)
- ⚠️ Outcome is vague or restates the problem
- ✅ Clear problem; Outcome is a concrete end state

### 2. Source

- ❌ No provenance — the problem is asserted with no impact, friction, or refs
- ⚠️ Named but thin (no scope, no refs)
- ✅ Impact · what hurts · refs make the problem real and sized

### 3. Hypotheses & traceability

- ❌ No hypothesis, or not in IF–THEN–BECAUSE
- ❌ A milestone serves no hypothesis (would survive hypothesis invalidation → cut it)
- ⚠️ Hypothesis wording loose, but the shape holds
- ✅ Each hypothesis IF–THEN–BECAUSE; every milestone traces to one
- _Don't re-grade hypothesis quality (metric rigor etc.) — that's the hypothesis-critic's job. Here, only structure + traceability._

### 4. Milestones

- ❌ **Goal is a task, not a state** — starts with an action verb (*add, set up, implement, migrate, configure, create, build*) or describes work rather than the resulting capability/state. This is the most common failure. Rewrite as what becomes true: *"Users can X"* / *"System now does Y"* / *"Z replaces W monorepo-wide"*.
- ❌ A separate verification / measurement / sign-off milestone (shouldn't exist — result tracked in background)
- ❌ Padding — more milestones than the work needs, or out-of-order (prerequisite after its dependent)
- ⚠️ Goals reasonable but not independently verifiable without asking the DRI
- ✅ Each Goal is a state or capability that now exists — verifiable by anyone from the product or a dashboard, no DRI needed; prerequisite-first

**Challenge:** "Could someone confirm milestone N by using the product or reading a dashboard — not by asking 'is it done?'"

### 5. Capacity & span

- ❌ No **Team:** line (work-types available), or a milestone Role not on the Team line (capacity gap)
- ❌ No Estimate, or no **Span:** line — or the span overflows the available sprints with no flag
- ⚠️ Roles vague (no count), Estimate not in sprints, or span unstated
- ✅ Team line present; every Role drawn from it; Estimate in sprints per milestone; Span stated and fits (or the overflow is flagged honestly)

---

## Output Format

Compact. No preamble, no summary of the roadmap back to the user.

**Overall verdict** — one sentence: ready to present, needs refinement, or needs significant rework?

Then one line per dimension:

**[Dimension]** [✅ / ⚠️ / ❌] — passing dimensions get a bare ✅; spend words only on ⚠️/❌, naming the specific issue.

Then, only if non-empty:

**Top fixes** — highest-impact changes, ranked, concrete ("M2 Goal is an activity — restate as 'a pre-push hook runs lint and type checks'").
**Suggested rewrite** — show the exact change only for the weakest parts (a reworded Goal, a dropped verification milestone, a corrected Role).

---

## Tone

- Direct, not harsh — a teammate, not a gatekeeper.
- Name the problem specifically — "M3 Goal is an activity" beats "milestones need work".
- Lead with what's strong (unless the roadmap is fundamentally broken).
- If it's solid, say so. Don't invent problems.
- Use the team's own domain language. Keep each judgment to 1–2 sentences.

---

## Escalation Signals

Critical blockers — unacceptable for team review:

- No problem or no Outcome
- No hypothesis, or a hypothesis not in IF–THEN–BECAUSE
- A milestone unconnected to any hypothesis
- All or most Goals are tasks ("add X", "set up Y") — no state or capability described
- No **Team:** line, or a milestone Role the team doesn't have, or no Estimate at all
- No **Span:** line, or a span that overflows the available sprints unflagged
- A separate verification/measurement milestone, or milestones stretched past the work

---

## Sample

**Input roadmap:**

> # Make search faster
> Hypotheses: If we move search to a dedicated search engine, things improve.
> Roadmap:
> | Milestone | Goal | Roles | Estimate |
> | M1 | Set up search cluster | BE | — |
> | M2 | Migrate indexes | BE | — |
> | M3 | Testing & sign-off | BE | — |

**Output:**

**Overall verdict:** Needs significant rework — no Outcome or Source, the hypothesis isn't IF–THEN–BECAUSE, Goals are activities, and there's a sign-off milestone that shouldn't exist.

**Problem & Outcome** ❌ Title is a wish, not a problem, and there's no Outcome. State the problem (what's slow, for whom, what it costs) and the end state.

**Source** ❌ No impact, friction, or refs — nothing sizes the problem.

**Hypotheses & traceability** ❌ "things improve" isn't IF–THEN–BECAUSE. Rewrite as e.g. *"IF product search is served from a dedicated search engine, THEN search P95 latency drops from ~2 s to under 300 ms, BECAUSE most of the latency comes from full-text queries on the primary database."*

**Milestones** ❌ All Goals are tasks, not states — "Set up search cluster" / "Migrate indexes" are implementation steps, not capabilities. M3 is a verification milestone that shouldn't exist. Rewrite as states: "Product search is served from the search engine in staging"; drop M3.

**Capacity & span** ❌ No Team line, Roles have no count, every Estimate is blank, and there's no Span.

**Top fixes:**
1. Add an Outcome ("Search results appear without a noticeable wait") and a Source (impact · what hurts · refs).
2. Rewrite the hypothesis in IF–THEN–BECAUSE.
3. Restate Goals as states, drop the sign-off milestone, add a Team line + sprint Estimates, and close with a Span.

**Suggested rewrite** _(Roadmap)_:

**Team:** 2 BE

| Milestone | Goal | Roles | Estimate |
| --- | --- | --- | --- |
| M1 | Product search is served from the search engine in staging, in sync with the database | 2 BE | 1 sprint |
| M2 | 10% of production search traffic is served from the search engine behind a flag | 1 BE | 0.5 sprint |
| M3 | All production search traffic is served from the search engine; the database search path is gone | 1 BE | 0.5 sprint |

**Span:** ~2 sprints (serial) — fits the quarter.
