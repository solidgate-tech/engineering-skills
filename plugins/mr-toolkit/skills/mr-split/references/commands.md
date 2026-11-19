# git-spice Command Reference

## Setup
| Command | Description |
|---|---|
| `gs repo init --trunk <default-branch>` | Initialize repo (always pass --trunk) |
| `gs auth status` | Check GitLab/GitHub login |
| `gs auth login` | Authenticate |

## Branch Management
| Command | Description |
|---|---|
| `gs branch create <name> -m "<msg>"` | Create branch, commit staged files, track |
| `gs branch track <name> --base <base>` | Reparent branch to a different base |
| `gs branch checkout <name>` | Switch to a tracked branch |
| `gs branch edit` | Interactive rebase for current branch only |
| `gs branch delete <name>` | Delete branch and untrack |

## Navigation
| Command | Description |
|---|---|
| `gs ls` | Show full stack tree |
| `gs up` | Move up one branch in stack |
| `gs down` | Move down one branch in stack |

## Restack
| Command | Description |
|---|---|
| `gs upstack restack` | Rebase all branches above current onto it |
| `gs downstack restack` | Rebase current branch onto updated base |

## Submit
| Command | Description |
|---|---|
| `gs upstack submit --fill` | Submit current branch + all above as MRs |
| `gs stack submit --fill` | Submit entire stack (includes base branch) |
| `gs branch submit --fill` | Submit only current branch as MR |
| `gs upstack submit --dry-run` | Preview what would be submitted |
