# Solidgate Engineering Skills

Agent skills that Solidgate engineers use every day, published as a [Claude Code plugin marketplace](https://code.claude.com/docs/en/plugin-marketplaces).

These are not demos. They come from our internal marketplace, where teams across the company write and share the skills they actually work with. We publish the ones that are useful outside Solidgate. More on how we use AI: [solidgate-tech.github.io](https://solidgate-tech.github.io/#ai).

## Plugins

| Plugin | What it does | Authors |
|---|---|---|
| [mr-toolkit](plugins/mr-toolkit) | The whole GitLab merge-request loop: inbox triage, gated AI review, MR creation, autonomous delivery, unblocking, stacked MRs, reviewer nudges. | Nikita Popov, Max Baginskiy, Artem Krysan, Andrii Valenia, Arsenii Andrieiev |
| [go-deep-service-review](plugins/go-deep-service-review) | Multi-agent review of a Go service for a closed set of production defects, with evidence for every finding. | Artem Polubok |
| [engineering-toolkit](plugins/engineering-toolkit) | ADRs and design documents written by interview, AI-artifact folder setup. | Nikita Popov |
| [planning-toolkit](plugins/planning-toolkit) | IF–THEN–BECAUSE hypotheses tied to DORA/SPACE metrics, lean roadmaps, critics for both, and announcement posts for shipped changes. | Nikita Popov, Artem Lebedev, Yurii Prokopchuk |
| [nodejs-toolkit](plugins/nodejs-toolkit) | Fixes `pnpm audit` findings in a safe, fixed order. | Ihor Huliashchyi |

## Install

In Claude Code:

```shell
/plugin marketplace add solidgate-tech/engineering-skills
/plugin install mr-toolkit@solidgate-engineering
```

Other agents that read `SKILL.md` files (Cursor, Codex and others) can use the [skills CLI](https://skills.sh/docs/cli):

```shell
npx skills add https://github.com/solidgate-tech/engineering-skills
```

Each plugin's README lists its requirements and configuration, and credits the author of each skill where a plugin has more than one.

## Looking for payment integration?

Skills for integrating with the Solidgate payment API live in [solidgate-agent-skills](https://github.com/solidgate-tech/solidgate-agent-skills).

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md). To report a security issue, see [SECURITY.md](SECURITY.md).

## License

[Apache License 2.0](LICENSE). Copyright 2026 GTWS Tech Limited.
