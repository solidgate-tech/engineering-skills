---
name: team-slack-post
description: >
  Draft a contributor-facing Slack post about a technical infrastructure or
  platform change. Use when shipping a tooling, build or platform change,
  deprecation, migration, or DX improvement and you need to communicate it to the
  engineers who build on it in a casual, human-first way. Produces the post
  text only; it never posts to Slack.
---

# Team Slack Post

Draft a Slack post that tells contributors what changed in their tooling, why it matters to them, and what they need to do. The output is text for the user to post; this skill never sends anything.

## When to use

Trigger on any of:
- "write a Slack post for the team", "announce this change", "team post for X"
- "how do we communicate this migration / deprecation / refactor"
- User pastes a PR description, ADR, changelog, commit hash, or branch name and asks for a team-facing summary
- User points at a directory or diff and asks for an announcement

Don't use for:
- External announcements or customer-facing release notes
- End-user product documentation
- Status updates ("what's the team doing this week")
- Incident postmortems

## Non-negotiables

Read these before drafting. Every post must satisfy all of them.

1. **Get a starting point first.** If the user already gave one (a PR link or description, branch, commit, directory, diff, ADR or changelog), use it. Otherwise, before any tool call, ask: *"What changed? Paste a PR link, branch name, commit hash, or point me at the right directory."* and wait for the answer.
2. **Investigate before writing.** Read the diff, ADRs, configs. Do not write from the user's one-line summary alone. See [rules/investigation.md](rules/investigation.md).
3. **Produce five or six sections, in this order**: Title → What was the problem? → How it affects you → What do you need to do? → What it opens → What did we do? — **Include section 4 when**: deprecated import, changed config key, renamed export, required CLI command, removed dependency, changed file location. **Omit only when**: zero migration steps, fully backwards-compatible.
4. **Lead with pain, not solution.** Title and section 2 name the friction the contributor felt. Never name the solution before naming the pain.
5. **Use second person everywhere except section 6.** "You", "your" in sections 1-5. "We" only in "What did we do?".
6. **Technical terms in section 4 (action-scoped only: exact file/command/key) and section 6 (unrestricted). All other sections: plain language.** No unexplained acronyms, package names, or tool names in sections 1-3 or 5.
7. **"What did we do?" is always last.** The contributor cares least about implementation.
8. **Readable in 60 seconds.** If a contributor can't skim it that fast, cut.

## Section checklist

### 1. Title
- Format: `**[Verb] the [thing] so you don't have to [deal with it]**`
- Emoji on the title line
- Names the problem, not the solution
- Good: `**We fixed the tsconfig mess so you don't have to**`
- Bad: `**Introducing @acme/tsconfigs**` — solution-first, do not ship

### 2. What was the problem?
- Opens with a direct question the contributor has actually asked themselves ("Have you ever...", "Ever wondered...")
- 2-3 short paragraphs
- Describes friction, confusion, wasted time — not the root cause

### 3. How it affects you
- Bullet list, 2-4 items
- Each bullet: **bold label** + plain-language explanation
- Every bullet answers: *what does the contributor gain or stop suffering from?*
- No implementation details, no package names
- If this section would naturally include an action step ("you'll need to update..."), move that step to "What do you need to do?" instead

### 4. What do you need to do? *(conditional — see non-negotiable #3 for include/omit triggers)*

- Numbered list of steps (not bullets — order matters)
- Each step: one imperative action ("Run X", "Replace Y with Z", "Delete the X key from your config")
- Commands in inline code or fenced blocks — never buried in prose
- If a migration script exists, link or quote it; if a guide exists, link it at the end
- Maximum 6 steps; if more, point to an external migration guide

### 5. What it opens
- 1-3 sentences, no bullets
- Forward-looking: what does this change make possible next?
- Concrete > vague: "faster CI via remote caching" beats "better DX"
- Include unless there is genuinely nothing this unlocks. If you skip it, the post feels truncated — default to including it.

### 6. What did we do?
- Bullet list of the actual technical work
- Only section that uses "we" for narrator voice
- Technical terms unrestricted here; action-scoped terms (exact file/command/key) also permitted in section 4
- Keep concise — contributors who care will open the ADR/PR
- Always last

## Anti-patterns (never ship these)

- Opening with "We are excited to announce..."
- Naming the solution before the pain
- Anything technical or action-requiring in "How it affects you" — section 3 is plain-language gains only
- Passive voice ("this was caused by", "it has been updated")
- Vague benefits ("improves developer experience", "reduces friction")
- "What did we do?" before any other section
- Vague or prose-embedded action steps — name the exact file/command/key; commands get their own code block, never buried in a sentence
- Including "What do you need to do?" for a purely additive change where nothing breaks without it

## Self-check before sending

- [ ] Title names the pain, not the solution
- [ ] Section 2 opens with a question the contributor has actually asked
- [ ] Section 3 bullets are gains only — no actions, no package names
- [ ] Section 4 present if and only if the change requires contributor steps; every step is imperative and commands are in code blocks
- [ ] No technical terms outside sections 4 and 6
- [ ] "What did we do?" is last
- [ ] Reads in 60 seconds

Compare against [rules/reference-post.md](rules/reference-post.md) if any box is uncertain.

## Deep procedures

- [rules/investigation.md](rules/investigation.md) — How to dig into a change from a PR link, branch, or directory
- [rules/reference-post.md](rules/reference-post.md) — Full reference post with annotations explaining why each section works
