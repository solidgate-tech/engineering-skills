# Contributing

Thanks for your interest. Issues and pull requests are welcome.

## Licensing of contributions

This project is licensed under the [Apache License 2.0](LICENSE). By
submitting a contribution you agree that it is licensed under the same terms
(section 5 of the license).

Sign off every commit to certify the
[Developer Certificate of Origin](https://developercertificate.org/):

```shell
git commit -s -m "feat(mr-toolkit): ..."
```

## Layout

```
.claude-plugin/marketplace.json     catalog of all plugins
plugins/<plugin>/
  .claude-plugin/plugin.json        plugin manifest
  README.md                         what it does, requirements, configuration
  skills/<skill>/SKILL.md           one skill per directory
  agents/, commands/, scripts/      optional
```

## Rules for skills

- **No organisation-specific values.** Hostnames, Slack workspaces, Jira
  projects, team names and the like come from configuration (environment
  variables or a first-run setup step), never from the skill text. Examples
  use `example.com`, `acme/`, `PROJ-123`.
- **Ask before acting.** Anything that writes outside the working tree, sends a
  message or changes a remote system must either confirm with the user or say
  plainly in its description that it does not.
- **Keep third-party content attributed.** If a skill adapts material from
  another project, keep the original license and add it to [NOTICE](NOTICE).

## Before opening a pull request

```shell
scripts/validate-manifests.sh
scripts/check-leaks.sh
```

Both run in CI.
