# Helm chart assessment recipe

**Load this recipe when** a lint target is a Helm chart: a directory containing
`Chart.yaml` (or a packaged chart `.tgz`). Do not load it for Kustomize roots
or plain manifest directories.

## Step 1 — Establish chart facts from checked-in artifacts

Read, without executing anything:

- `Chart.yaml` — name, version, `apiVersion`, declared `dependencies`.
- `values.yaml` — defaults. Note keys that gate conditional resources
  (`{{- if .Values.x }}`) and any `namespace`-style keys the chart itself
  takes — a chart-level namespace value and the release namespace are
  **distinct inputs** (verified: a chart whose NetworkPolicies read
  `.Values.namespace` while workloads fall back to `.Release.Namespace`
  renders the policies namespace-less under defaults but namespaced when the
  value is set).
- `templates/` — workload kinds, pod-template labels, service accounts,
  probes, resources, security contexts, conditional blocks, hooks.
- `crds/` — chart CRDs; `helm install` always applies them, so the lint
  render includes them via `--include-crds` (Helm 4 defaults it to false).
- Documented deployment profiles — README, values files, Makefile/deploy
  scripts, CI invocations. These are the source of the rendering profile:
  release name, namespace, values files, `--set-string`-style overrides in
  their documented order.

**Remote inputs.** The pinned renderer fetches remote inputs (values URLs,
remote chart dependencies, `http(s)://` references) exactly as the
documented invocation specifies. Record each remote input and its source in
the report's provenance — the pin plus the recorded inputs are the record
of what ran. The pin plus URL does not identify mutable content: a remote
input on a moving ref (branch) can change between assessment and CI, so
record its resolved revision or content digest, and a digest of each
rendered profile, so later runs are comparable.

Record each fact with its source path — this becomes the source/profile
mapping in the report.

## Step 2 — Resolve the rendering profile

**Values resolution order:**

1. **The consumer's documented install invocation, first.** Makefile deploy
   targets, CI, install docs, operator code that renders the chart.
   Reproduce its values files and typed overrides verbatim — repeated `-f`
   files in order (later files win; earlier files' untouched keys survive)
   and `--set-string` overriding files (all verified under the pinned
   Helm 4). Record where every input came from.
2. **Minimal generated lint values, only when no documented invocation
   exists anywhere.** Scratch-only, minimal (namespace plus whatever the
   chart requires to render), each input's source or explicit assumption
   documented. Never add an override just to remove a finding.
3. **Defaults-only comparison — optional.** The chart's own `values.yaml`
   alone is a legitimate extra diagnostic run (it shows what the chart
   ships), never a required second profile. If normal rendering requires
   values that are unavailable, do not fabricate a defaults pass.

**Render-relevant translation of install commands.** Translate only
rendering inputs: release name, `--namespace`, values files, typed
overrides, `--api-versions`/`--kube-version` capabilities, and — only when
the documented profile selects them — `--is-upgrade`, hook handling. The
lint render always passes `--include-crds` (chart CRDs are part of what
`helm install` deploys; omitting them would be a silent coverage gap).
Never forward deployment flags (`--wait`, timeouts, cluster
credentials); record what was omitted. Install/upgrade/conditional branches
not selected by the documented profile are coverage limits, not covered
behavior.

**Dynamic install-time inputs** (image refs resolved at deploy, cluster
state, platform environment) are not available statically. Record them as
coverage limits; a run using a checked-in fallback value is partial
coverage, not exact as-installed evidence.

## Step 3 — Render externally with pinned Helm 4

Every chart renders through the pinned Helm 4 CLI into one scratch
multi-document file, which kube-linter then lints:

```
GOFLAGS= GOWORK=off go run helm.sh/helm/v4/cmd/helm@v4.3.2 template \
  <release> <chart-root> --namespace <ns> [-f values...] [--set-string k=v...] \
  > <scratch>/profile.yaml
```

- Helm 4 is required even when the consumer uses Helm 3 — document
  compatibility differences, never silently downgrade. The Helm 4 module
  needs Go >= 1.26. See the entry-point recipe for consumer prerequisites.
  The pinned invocation is the evidence of what rendered.
- External rendering runs in **normal mode**: `required`/`fail` template
  errors abort the render (verified: nonzero exit, error naming the
  template and value, zero bytes of output). A failed render blocks the
  profile — never lint partial or empty output, and never fall back to
  kube-linter's native chart rendering.
- Verify flags against the pinned binary (`template --help`), not
  default-branch docs.
- Build the invocation with safe Bash argument arrays — repeated `-f` and
  `--set-string` flags and values with spaces survive verbatim; never
  `eval` or whitespace-split a command string.
- Dependencies declared in `Chart.yaml` must already be vendored under
  `charts/`; the render does not fetch them. Missing dependencies are
  blocked coverage — never run `helm dependency update`.
- Chart plugins and post-renderers are not executed; report them as limits.

## Step 4 — Verify what was actually assessed

Findings are **positive evidence only**: the JSON report's `Reports[]`
entries (and their `.Object.Metadata.FilePath`) appear exclusively for
objects a check produced a diagnostic on. A cleanly assessed object has no
entry — absence from the findings never proves a resource was not assessed.

To positively enumerate what the render loaded, run a separate analysis-only
inventory pass on the same pinned linter against the rendered file with an
always-firing custom CEL check:

```yaml
customChecks:
  - name: inventory
    description: "analysis-only: enumerate assessed objects"
    remediation: "n/a"
    template: "cel-expression"
    params:
      check: |
        "assessed"
```

Completeness caveat: kube-linter skips objects carrying
`kube-linter.io/ignore-all` or `ignore-check.kube-linter.io/<check>`
annotations before any check evaluates, so an ignore-annotated object is
absent from inventory findings too. With an external render this is now
directly searchable — account for such annotations in the rendered file
before treating inventory absence as evidence; otherwise the coverage
conclusion stays **unknown**.

## Interpretation pitfalls

- **Namespace inputs are distinct.** The release namespace (`--namespace`)
  and a chart-level namespace value are different knobs. Serialize nothing
  by assumption: a namespace absent from the rendered YAML does **not**
  prove a live defect — Helm/Kubernetes apply release-namespace defaulting
  at install time, which static assessment does not simulate. Never rewrite
  rendered namespaces or weaken a check to make the artifact disappear;
  classify with the render as evidence.
- **NetworkPolicy:** a policy selects pods by **pod-template labels** in its
  effective namespace — a Deployment's own metadata labels are insufficient
  evidence. Do not infer live policy behavior from `""` versus explicit
  namespace serialization.
- **Externally provided objects:** service accounts, CRDs, policies, or
  operator-created workloads that live outside the chart are not in the
  render. `non-existent-service-account` on an out-of-chart account is a
  rendering-context observation, not proof the account is missing at install
  time — classify accordingly and state the assumption.
- **Conditional resources:** findings cover the selected rendering profile.
  Say so explicitly in the report; do not present them as findings for every
  installation profile.
- **Hooks:** hook manifests that render are assessed like any other object;
  note their install/upgrade-only semantics when classifying findings.

## Extra check candidates (only with manifest evidence)

- `dangling-service`, `dangling-networkpolicy`,
  `dangling-networkpolicypeer-podselector`, `mismatching-selector` — when the
  render includes the full related set (workloads + Services + policies) in
  one context.
- `liveness-port` / `readiness-port` — when probes and container ports are
  both declared.
- `minimum-three-replicas`, `no-anti-affinity`, `no-node-affinity`,
  `no-rolling-update-strategy` — for HA-class services where the chart's
  replicas/topology justifies them.
- Do not force cross-resource checks on partial bundles (e.g. a chart that
  only renders policies while workloads live elsewhere).

## Handoff

Use the [assessment checklist](../SKILL.md#assessment-checklist) and retain
the mapping between chart, profile, and values. The shared entry point uses
pinned Helm 4 with `--include-crds` and lints the rendered file.
