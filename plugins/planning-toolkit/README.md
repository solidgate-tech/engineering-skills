# planning-toolkit

Quarter planning for engineering teams, from problem to announcement. The generators write hypotheses and roadmaps to one standard, and the critics check them against it.

| Skill | What it does | Authors |
|---|---|---|
| `hypothesis-generator` | Turns a problem statement, or a rough idea traced back to its problem, into 3–5 IF–THEN–BECAUSE hypotheses. Each THEN is tied to a DORA, SPACE, security or product metric, and each hypothesis names its riskiest assumption and the smallest test that could disprove it. | Nikita Popov, Artem Lebedev |
| `hypothesis-critic` | Reviews one hypothesis clause by clause (one shippable change, a measured outcome rather than a feature state, a falsifiable belief) and ends with a rewrite. | Nikita Popov, Artem Lebedev |
| `roadmap-generator` | Builds a lean roadmap anchored on a problem: Outcome, Source, Hypotheses, and a milestone table whose goals are verifiable states, with roles, sprint estimates and whether it fits the quarter. | Artem Lebedev |
| `roadmap-critic` | Reviews a roadmap for a real problem and outcome, milestones that trace to hypotheses, goals written as states rather than tasks, and capacity that adds up. | Nikita Popov, Artem Lebedev |
| `team-slack-post` | Drafts a contributor-facing Slack post about a tooling or platform change: pain first, plain language, exact migration steps. Text only; it never posts. | Yurii Prokopchuk |

## How they fit together

Start from a problem. If you only have an idea, `hypothesis-generator` names the problem it implies and checks it with you first. Generate a shortlist of hypotheses and run the ones you keep through `hypothesis-critic`. Hand the problem and the surviving hypotheses to `roadmap-generator`, which turns them into milestones the team can staff, then let `roadmap-critic` challenge the plan before it goes to review. When a milestone ships a change other engineers have to adopt, `team-slack-post` writes the announcement. Each skill also works on its own.

The critics apply the same rules the generators write to: one change per IF, a THEN that moves a tracked metric from a baseline to a target, a BECAUSE the result could prove wrong, and milestone goals that anyone can verify without asking the owner.

## Requirements

None. The skills work on text in the conversation and never contact Slack, Jira or Confluence. `team-slack-post` reads the change with `git` when you point it at a branch, commit or directory.
