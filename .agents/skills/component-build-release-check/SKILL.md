---
name: component-build-release-check
description: Use when a component is built by Konflux `.tekton` targets and needs PR-time build validation, or when adding hermetic, manifest, operator, or downstream-variant checks to a component repo. Generates checks from the images Konflux builds, then proves each against the component's real Jira failure history instead of producing generic green checks.
---

# Component Build Release Check Skill

Generates PR-time checks for a component's build and release path, starting from
the images Konflux builds. It works from evidence, not a checklist: it mines the
component's Jira breakages, classifies what this repo can catch, and
fault-injects every check so a green result is proof rather than decoration.

## When to Use

- A component is built by Konflux `.tekton` targets and has no PR-time build validation.
- A repo needs hermetic, packaging, manifest, operator, or downstream-variant checks before merge.
- A workflow reports green while Konflux or the consuming operator still breaks.
- Do not use it to claim RHOAI platform-operator (`DataScienceCluster`) coverage; emit the handoff described in `instructions.md` instead.

## Usage

```bash
/component-build-release-check [repository-url]
```

Examples: `.../odh-dashboard`, `.../kserve`, `.../kubeflow/training-operator`.

## How It Works

**Read [`instructions.md`](instructions.md) before generating anything.** The
procedure, thresholds, fault-injection requirements and environment traps live
there; this file is the summary. Then read the [`LEARNINGS.md`](LEARNINGS.md)
entries that govern the checks you are generating — start from this index
instead of reading all 2,000 lines:

| Generating | Read |
|---|---|
| Skip gate, summary job, required status checks | *A green check that never ran is worse than no check*; *Workflow correctness lessons from the model-registry onboarding review* |
| Hermetic Go/Python preflight | *`pip` cannot prove a Python hermetic build, `uv` can*; *Porting the simulator to a Go + Python repo*; *a hermetic build must not mutate the checkout* |
| Tool downloads and installation | *Security Hardening Best Practices* §4; *the skill shipped the defects it was meant to catch* |
| Manifest, kustomize and kubeconform checks | *a rendered manifest is not a runnable container*; *kubeconform `statusError` is fail-open* |
| Operator integration in Kind | *Operator reconcile smoke test — image clobber, silent rollout failures, and missing overlays*; *Operator-Integration in Vanilla Kind* |
| Fault injection | *Fault injection is the only evidence a check works* |
| Jira evidence and scope | *Find the Jira component before claiming there is no history*; *the biggest historical failure class is often the one called out of scope* |

The checksum section is current: every downloaded tool is verified against its
published digest. The older "attempted but removed" text is superseded and any
entry that still says otherwise records a defect, not a recipe.

The PR description carries two tables: what these checks catch, and what they
still cannot. A check that passes without failing on its injected fault is not
evidence. Platform-operator-only failures are listed in Appendix A and
`LEARNINGS.md`; the full inventory and repo-type check sets are in the
`instructions.md` appendices.

### Generated Artifacts

1. **`.github/workflows/pr-build-validation.yml`** — PR workflow with one skip gate and a required summary job
2. **`scripts/validate-build.sh`** — reusable local validation script
3. **`manifests/pr-testing/`** — test manifests when an operator consumer exists
4. **`docs/pr-build-validation.md`** — setup and troubleshooting

## Check Coverage

See `instructions.md` Appendix A for the full inventory and ticket references.

- **Evidence:** Jira breakage mining, catchability classification, fault injection.
- **Hermetic inputs:** lockfile protocols, Go/Python offline preflight, pnpm store.
- **Build and runtime:** every Konflux build variant, container startup, health, crashloops, non-root.
- **Manifests:** kustomize, kubeconform, generated drift, RBAC identity, manifest path contracts.
- **Operator:** Kind integration, external operator at a pinned commit, reconcile evidence.
- **Frontend:** Module Federation output and load checks.
- **Platform handoff:** detect `DataScienceCluster`-only shipping and emit a follow-up.

## Not Covered

- Platform-operator reconciliation (`DataScienceCluster` conditions, Managed state, operator-rendered manifest paths).
- Cluster RBAC/SCC, networking, storage, and upgrade paths.
- Broken Python wheels unless the image is actually run and modules imported.

## Time Estimate

- Basic Docker build: 30–45 minutes
- With operator integration: 1–2 hours
- All validations: 2–3 hours

## Requirements

- Repository with a Dockerfile
- GitHub Actions enabled
- Public or accessible repository

## Files

- `SKILL.md` — routing summary and scope
- `instructions.md` — procedure, appendices, per-repo-type check sets
- `LEARNINGS.md` — why each check exists; failures and rejected approaches
