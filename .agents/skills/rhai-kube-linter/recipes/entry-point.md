# Onboarding entry-point recipe

**Load this recipe when** proposing the lint script, Makefile target, and
GitHub Actions workflow in the onboarding file set.

## Lint script

Copy the [lint template](../templates/lint-manifests.sh.tmpl) to
`scripts/lint-manifests.sh`. Specialize the config path, kube-linter module
pin, and renderer calls. Reuse an existing equivalent entry point when it
meets the canonical command contract.

Replace `__PLACEHOLDER_RENDER_PROFILES__` with one `lint_profile` call per
deployment context. Each call takes a unique profile name, a repository-relative
entry-point file, the pinned renderer module, and its argument list. The entry
must be a file committed to the repository — the combined SARIF report
attributes every finding of the profile to it, because the renders are
disposable scratch outside the checkout and Code Scanning can neither display
nor fingerprint locations that reference them. The
script runs from the consumer repository root. Use the documented Helm
release, namespace, values, and overrides, preserving argument boundaries
and order. Include only calls for the consumer's selected targets.

```bash
lint_profile chart charts/app/Chart.yaml \
  helm.sh/helm/v4/cmd/helm@v4.3.2 template app charts/app \
  --namespace app --include-crds -f 'values production.yaml'

lint_profile overlay overlays/production/kustomization.yaml \
  sigs.k8s.io/kustomize/kustomize/v5@v5.8.1 build --enable-helm overlays/production
```

The script uses Bash 3.2 or later, jq, and a Go version compatible with the
selected module pins. Helm 4 requires Go 1.26 or later. Kustomize uses Helm
from the caller's PATH when a root inflates charts. See the format recipes
for rendering and provenance.

## Failure semantics

`KUBE_LINTER_FAIL_ON_FINDINGS` controls findings in both local and CI runs.

| Value | Selected-check findings only | Operational error or mixed result |
|---|---|---|
| unset or `true` | fail | fail |
| `false` | warn and succeed | fail |
| empty or any other value | configuration error | configuration error |

A profile must render successfully before linting. The script runs
kube-linter once per profile and prints its plain-text output. It checks
the SARIF, exit status, and tool diagnostics before applying the findings
policy. Independent profiles run even after a failure. Rendered manifests
stay in disposable scratch.

## Makefile and CI

- If a Makefile exists, reuse its manifest lint target when it meets the
  canonical command contract above. Propose adapting an incompatible target
  in the onboarding diff. If the Makefile has no manifest lint target, append
  the [Makefile target](../templates/Makefile.tmpl). The workflow and local
  users call the same target.
- Otherwise use `bash ./scripts/lint-manifests.sh` directly in both places.
- In the [workflow template](../templates/github-actions.yml.tmpl), fill
  in the default branch, Go version, and canonical lint command. Use the
  SARIF upload step on GitHub Code Scanning-enabled repositories.
- GitHub Actions uploads the complete SARIF report after the lint step,
  including when strict findings fail it. Each profile has its own
  category, and every result's location is the profile's entry-point file
  (one committed path per profile — an approximation, since a render
  combines several source files). Each result also carries a partial
  fingerprint — written to `partialFingerprints.primaryLocationLineHash`,
  the only key Code Scanning consumes — built from its rule ID and object
  identity, so two objects failing the same check in one profile do not
  merge into a single alert.
