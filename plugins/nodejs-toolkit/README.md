# nodejs-toolkit

## pnpm-audit-fix

Fixes `pnpm audit` findings in a fixed order of preference:

1. **Drop** the dependency if nothing needs it.
2. **Update** to the minimum version that resolves the advisory.
3. **Override** a transitive dependency.
4. **Ignore** the advisory, with a recorded reason, when no fix exists.

Before touching anything new, it re-checks existing overrides and ignores and removes the ones that are no longer needed. After each change it runs the project's `test`, `build` and `lint` scripts when they exist.

Overrides and ignores are written to `pnpm-workspace.yaml`, with the reason for each in a YAML comment above it. Ignores use GHSA IDs (`auditConfig.ignoreGhsas`), because the audit report no longer carries CVE IDs.

If `package.json` still has a `pnpm` field, the skill first moves its settings to `pnpm-workspace.yaml` and converts `ignoreCves` to `ignoreGhsas`. pnpm 12 ignores that field, so whatever it held is not in effect until it is moved.

## Usage

Ask Claude to fix the audit, e.g. "fix pnpm audit" or "clean up our dependency CVEs", from the project root.

Audit commands use `--registry=https://registry.npmjs.org` by default, because many private mirrors do not serve audit data. Tell the agent if yours does.

## Requirements

- `pnpm` 12
- `rg` (optional; falls back to `grep`)
