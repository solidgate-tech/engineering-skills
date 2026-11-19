---
name: mr-split
description: Split uncommitted changes into a stack of focused branches and open all MRs with dependencies set using git-spice (gs). Use when the user wants to split a large changeset into multiple MRs, create stacked branches from uncommitted work, or submit a branch stack to GitLab/GitHub. Triggers on phrases like "split into branches", "create stacked MRs", "stack my changes", or explicit /mr-split invocations.
---

# mr-split: Stack Branches & Submit MRs

## Workflow

### 1. Setup

```bash
which gs && gs --version          # verify installed (brew install abhinav/tap/git-spice)
git symbolic-ref -q refs/remotes/origin/HEAD >/dev/null || git remote set-head origin -a   # origin/HEAD unset in some clones
trunk=$(git symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')          # main, master, …
gs repo init --trunk "$trunk"     # idempotent; always pass --trunk to avoid TTY prompt
gs auth status                    # confirm GitLab/GitHub login
```

### 2. Analyse Changes

```bash
git diff --stat HEAD              # shows +/- lines per file
```

Present the file list with line counts to the user. Ask how they want to group files into branches.

**Grouping rules:**
- Aim for **≤ 500 lines per branch**. A file that alone exceeds 500 lines gets its own branch.
- `file.go` and `file_test.go` always stay together — they are one logical unit regardless of combined size.
- Keep implementation and its unit tests in the same branch; only functional/integration tests may go in a separate branch.

**Ordering rules (dependencies first):**
- If branch B uses types/functions defined in branch A, A must come before B in the stack — otherwise B won't compile on its own.
- Example: `dto.go` defines types used by `processor.go` → dto branch is first, processor branch is second.
- Always trace import dependencies when deciding order; the stack must be buildable at every level.

Propose a concrete ordered list with branch names and file assignments, then confirm with the user before proceeding.

### 3. Stash Everything

```bash
git stash --include-untracked
```

### 4. Create Branches (repeat per branch)

Apply only the files for this branch from the stash, then create:

```bash
git checkout stash@{0} -- <file1> <file2> ...   # stages files automatically
git status --short                               # verify staged correctly
gs branch create <branch-name> -m "<message>"   # flag is -m, not --commit-message
```

> `git checkout stash@{0} -- <file>` stages the stashed version without popping the stash — safe to call repeatedly.

### 5. Fix Base (worktree branches only)

If you created branches while on a branch other than `$trunk` (e.g. a Claude Code worktree branch like `claude/hardcore-nobel-7ee37b`), git-spice tracks that branch as the base. Fix it:

```bash
gs ls                                                    # confirm stack shows worktree branch as base
gs branch checkout feat/<first-branch>                   # navigate to the first feature branch
gs branch track feat/<first-branch> --base "$trunk"      # reparent to trunk
gs ls                                                    # verify trunk is now base
```

### 6. Drop the Stash

```bash
git stash drop stash@{0}
```

### 7. Submit All MRs

```bash
gs upstack submit --fill    # --fill uses commit messages; --no-prompt fails in non-TTY
```

Each MR targets the branch below it as its base — dependencies are set automatically.

---

## Navigation & Updates

```bash
gs ls                        # show full stack
gs up / gs down              # move between branches
gs branch checkout <name>    # jump to a specific branch

# After editing a middle branch:
gs upstack restack           # rebase all branches above current
gs stack submit --fill       # push updates to all MRs
```

## Gotchas

| Problem | Fix |
|---|---|
| `gs repo init` prompts for trunk | Always pass `--trunk "$trunk"` |
| `gs branch create --commit-message` fails | Use `-m` |
| `gs stack` not found | Use `gs ls` |
| `gs upstack submit` fails: base not submitted | Run `gs branch track <first> --base "$trunk"` |
| `gs upstack submit --no-prompt` fails | Use `--fill` instead |
| `gs stack submit` creates MR for empty worktree base | Navigate to first real branch, use `gs upstack submit` |

## Command Reference

See [references/commands.md](references/commands.md) for the full gs command list.

## Documentation

- Official docs: https://abhinav.github.io/git-spice/
- Getting started: https://abhinav.github.io/git-spice/start/stack/

