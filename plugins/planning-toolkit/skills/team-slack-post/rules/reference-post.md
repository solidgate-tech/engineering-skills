---
name: reference-post
description: Annotated reference post — the style anchor for every team-slack-post output
---

# Reference post (style anchor)

Every draft is measured against this. After writing, re-read this file and ask: *does my output feel like this?* If not, revise.

## The post

> :wrench: **We fixed the tsconfig mess so you don't have to**
>
> **What was the problem?**
> Have you ever set up a new app or lib and wondered - which `tsconfig` do I extend? What does `compilerOptions` actually do here? Do I copy it from another project? Which one? Should I care?
>
> It was frustrating. The answer was always "copy from another project" — but which one, and which parts actually matter?
>
> The reality was that every project in the monorepo declared its own compiler options by hand - copied from somewhere, tweaked over time, and slowly drifting from everything else. There was no single right answer to "which config do I use" because they were all subtly different. On top of that, adding a new internal package required updating two separate places - the `alias-sync` Vite plugin and the tsconfig paths - and if they got out of sync, you'd end up with imports that worked in the IDE but silently broke in CI.
>
> **How it affects you**
> - **You will never need to think about what to use and how.** All configurations are created and ready for each environment. Setting up a new app or lib? You just use the right one and move on.
> - **No more mysterious internal package resolution.** Internal packages now work reliably everywhere — in the IDE, in CI, and in your local builds.
> - **One place to find everything.** All shared TypeScript configuration lives in a single, documented location. If something looks off or you're curious, that's the only place you need to check.
>
> **What do you need to do?**
> 1. In your `tsconfig.json`, replace the `extends` value with the right preset — `@acme/tsconfigs/react`, `@acme/tsconfigs/node`, `@acme/tsconfigs/test`, or `@acme/tsconfigs/storybook`.
> 2. Remove the `alias-sync` plugin from your `vite.config.ts`:
>    ```ts
>    // delete this line
>    aliasSync()
>    ```
> 3. Make sure your internal `@acme/*` imports are listed as `workspace:*` dependencies in `package.json`, then run:
>    ```
>    pnpm install
>    ```
> 4. If your `tsconfig.json` still has a `paths` block pointing to `@acme/*` packages, delete it — path mapping is now handled automatically.
>
> Full migration guide is linked in the PR.
>
> **What it opens**
> Remote build caching -> faster pipelines for everyone. Incremental builds, parallel task execution, shared cache across local machines and CI. Only what actually changed gets rebuilt.
>
> **What did we do?**
> - **Full pnpm workspaces adoption** - all `@acme/*` packages declared as proper `workspace:*` dependencies; the graph is fully visible to every tool.
> - **Deprecation of alias-sync** - the Vite plugin is removed; resolution goes through `node_modules` natively.
> - **Shared `@acme/tsconfigs` package** - single source of truth for TypeScript config, with ready-to-use presets: `react`, `node`, `test`, `storybook`.

## Why this works — section by section

### Title

- `We fixed the tsconfig mess so you don't have to`
- Names the *mess* (the pain), not `@acme/tsconfigs` (the solution)
- The "so you don't have to" framing puts the contributor at the center

### What was the problem?

- Opens with a question the reader has actually asked: *"which `tsconfig` do I extend?"*
- Second paragraph lands the emotional beat ("It was frustrating") — validates the reader's feeling before going into technical detail
- Third paragraph gets concrete about the failure mode (IDE-vs-CI drift) without using jargon like "module resolution" or "path mapping"

### How it affects you

- Three bullets, each starts with what *you* gain
- Bold labels are the headline; the explanation follows in plain language
- Bullet 3 ("One place to find everything") tells the reader where to look next — useful, not a sales pitch

### What do you need to do?

- Numbered steps because order matters — contributors must not run step 3 before step 2
- Each step names exactly what to touch: the file, the key, the line — not "update your config"
- Commands in fenced blocks so they can be copy-pasted without hunting for them in prose
- Closes with a pointer to deeper docs — keeps the post short while giving an escape hatch to anyone who needs more context
- The section is present here because the tsconfig migration has breaking changes: keeping the wrong `extends` or leaving `alias-sync` in place causes silent CI failures. A post without this section would leave contributors stranded.

### What it opens

- Concrete unlock (remote build caching), concrete outcome (faster pipelines)
- Not "better DX", not "improved velocity" — those are vague benefits, not unlocks

### What did we do?

- Three bullets of actual technical work
- First time `pnpm workspaces`, `Vite plugin`, `workspace:*` appear — and that's correct
- Each bullet ends with the *consequence* ("the graph is fully visible to every tool"), not just the change

## Tone calibration

- **Slack-native**: casual, warm, direct. Emoji on the title and welcome on section openers.
- **Contributor-first throughout**: every sentence asks *does this help the reader, or is it just explaining my work?*
- **Plain language outside sections 4 and 6**: a contributor who has never touched the package graph should still understand sections 1, 2, 3, and 5.
- **60-second skim**: if it doesn't fit, cut. The ADR/PR is one click away for anyone who wants more.

### Voice in "What do you need to do?"

This section is the only place where the post shifts from describing to instructing. Keep it imperative ("Run", "Replace", "Delete", "Add") — not passive ("should be updated", "needs to be changed"). The contributor is in action mode here; match their mindset. Technical specifics (package names, file names, CLI flags) are permitted and required in this section — but only in service of the action, not as architecture explanation.
