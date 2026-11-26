# rhoai-guardrail-skills

Guardrail skills for RHOAI component repositories, kept in the tool-agnostic
`.agents/skills/` layout. Each skill is self-contained (`SKILL.md` plus
supporting files), so it can be loaded by any agent that supports the layout.

## Skills

### Component Build Release Check (`.agents/skills/component-build-release-check/`)

Generates PR-time checks for a component's build and release path. It starts
from the images Konflux builds via the repository's `.tekton` targets, then
validates hermetic build inputs, image runtime, operator integration, manifest
and RBAC contracts, and the downstream variant contract.

Every generated check is fault-injected against the component's real Jira
failure history, and the PR description lists both what the check now catches
and what it cannot.

After linking, invoke the skill in Claude Code:

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

### RHAI kube-linter (`.agents/skills/rhai-kube-linter/`)

Onboards a repository's Helm charts or Kustomize overlays to kube-linter. It
assesses the actual manifests, recommends an evidence-based check combination,
classifies findings, proposes narrowly scoped exceptions, and proposes
approval-gated onboarding files: a config, one shared lint script, a Makefile
target, and a GitHub Actions workflow.

The skill only assesses and proposes until the exact file set is approved. It
never edits manifests, weakens checks to get green, or accesses a cluster.

### RHAI Kind setup (`.agents/skills/rhai-kind-setup/`)

Generates standalone Bash scripts that make selected OpenShift and Prometheus
Operator APIs available on an existing Kind cluster. It can install selected
CRDs, create a service-ca certificate stand-in, and install a pinned
cert-manager controller from Helm.

Generation only: the skill writes scripts and never runs them or contacts a
cluster.

## Using with Claude Code

Claude Code only discovers project skills under `.claude/skills/`. Link the
skills in this checkout before invoking them:

```bash
mkdir -p .claude/skills
for skill in .agents/skills/*/; do
  name="$(basename "$skill")"
  ln -sfn "../../.agents/skills/$name" ".claude/skills/$name"
done
```

The links are local-only and ignored by Git; `.agents/skills/` remains the
source of truth.

## Linting

Skills and `AGENTS.md` are linted with [skillsaw](https://skillsaw.org) in CI
by `.github/workflows/skillsaw.yml`. Run the same check locally:

```bash
make lint
```

The `Makefile` pins the skillsaw image by digest and prefers Podman when its
machine is running, otherwise Docker.

## Provenance

`component-build-release-check` was moved from
`antowaddle/Red-Hat-Quality-Tiger-Team` at commit `4274243`, where it lived at
`.claude/skills/konflux-build-simulator/`, and then synced with the learnings
merged upstream in `antowaddle/Red-Hat-Quality-Tiger-Team#41`. Apart from the
rename, the tool-agnostic skip token, and the review fixes in the import PR,
the checks are unchanged. It now lives in `.agents/skills/` so it is linted by
skillsaw like the other skills.
