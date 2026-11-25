# rhoai-guardrail-skills

Guardrail skills for RHOAI component repositories, packaged for Claude Code.

## Skills

### Component Build Release Check (`.claude/skills/component-build-release-check/`)

Generates PR-time checks for a component's build and release path. It starts
from the images Konflux builds via the repository's `.tekton` targets, then
validates hermetic build inputs, image runtime, operator integration, manifest
and RBAC contracts, and the downstream variant contract.

Every generated check is fault-injected against the component's real Jira
failure history, and the PR description lists both what the check now catches
and what it cannot.

```bash
/component-build-release-check https://github.com/org/repo
```

Outputs:

- `.github/workflows/pr-build-validation.yml`
- `scripts/validate-build.sh`
- `docs/pr-build-validation.md`
- `manifests/pr-testing/` when the component is consumed by an operator

The generated workflow is a starting point that the component repository owns,
and is expected to be edited in place after it lands.

## Provenance

`component-build-release-check` was moved from
`antowaddle/Red-Hat-Quality-Tiger-Team` at commit `4274243`, where it lived at
`.claude/skills/konflux-build-simulator/`, and then synced with the learnings
merged upstream in `antowaddle/Red-Hat-Quality-Tiger-Team#41`. Apart from the
rename, the tool-agnostic skip token and the review fixes in this PR, the
checks are unchanged.
