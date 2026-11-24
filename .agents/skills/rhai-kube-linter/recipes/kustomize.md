# Kustomize assessment recipe

**Load this recipe when** a lint target is a Kustomize root, overlay, or base:
a directory containing `kustomization.yaml`, `kustomization.yml`, or
`Kustomization`. Do not load it for Helm charts or plain manifest directories.

## Step 1 — Discover deployable roots, not all YAML

Identify what is actually deployed versus what is a base, patch, or fixture:

- Start from deployment entry points: docs, README, Makefile deploy targets,
  CI pipelines, operator install instructions. Do not recursively lint every
  YAML file in the repository.
- Overlays (`overlays/*/kustomization.yaml`) are deployable profiles; bases
  and patch files are inputs to them. Bases are **not** standalone complete
  deployments — never lint a base as if it were one; findings from a bare base
  can be misleading (missing namespace patches, missing resources). Exception:
  a base **is** a deployable profile when the deployment entry points identify
  it as the deployed root — a documented Makefile/CI/install invocation that
  runs `kustomize build` on the base itself, with no overlay. Select it like
  any other evidenced root; the no-overlay default never overrides deployment
  evidence.
- Record each root with its purpose: deployable overlay, base, or fixture.
- Discover all three entry-point filenames: `kustomization.yaml`,
  `kustomization.yml`, and `Kustomization` — every one of them renders
  through the same external path in Step 2.

**Select overlays by deployment context.** Repositories often ship several
overlays for different deployment targets (e.g. `odh`, `rhoai`, `openshift`).
Do not assess all of them by default — determine which overlay(s) are actually
deployed:

- When a consumer deploys the repository (a module operator, the ODH operator,
  or a platform integration), read that consumer's checked-in manifests and
  controller configuration to find which overlay it selects (overlay constants,
  vendored operand config, install scripts). Scope the assessment to the
  overlay(s) that deployment context uses.
- When the repository is deployed standalone or through multiple contexts,
  identify the documented deployment targets; if the relevant overlay cannot
  be established from checked-in facts, ask the consumer which profile
  matters rather than guessing.
- Every selected overlay is still assessed as its own isolated profile per
  Step 3.

**Namespace transformer and binding subjects.** A root's top-level
`namespace:` fills not only object namespaces but also ServiceAccount
`subjects[].namespace` in rendered RoleBindings and ClusterRoleBindings —
a fragment checked in with a namespace-less subject can be completed (and
made valid) by its consuming overlay, so verify by rendering before
calling it a defect. The flip side: the subject's namespace is whatever
the consuming overlay sets — if the controller actually runs elsewhere,
the binding is silently ineffective. Check the rendered subject namespace
against the workload's actual namespace.

**namePrefix and reference rewriting.** `namePrefix`/`nameSuffix` rename
objects and rewrite references to them together — including ServiceAccount
`subjects[].name` in RoleBindings/ClusterRoleBindings and pod
`serviceAccountName` (the NameReference transformer) — in the validated
build topologies (prefix at the root, on an inner child, differing
per-sibling prefixes; a root patch targeting the raw name still matches).
A prefix cannot strand a binding on the unprefixed name in those
topologies; the residual defect class is a hardcoded subject matching
nothing in the corpus, which passes through every transformer verbatim and
is caught by the baseline's `sa-subject-exists` on rendered output. Prove
transformer-behavior claims with a minimal repro rendered by the pinned
Kustomize — not documentation.

## Step 2 — Render every root externally with pinned Kustomize

Every selected root — whatever its entry-point filename — renders through
the pinned standalone Kustomize CLI into one scratch multi-document file,
which kube-linter then lints. There is no native rendering path and no
filename-dependent exception: kube-linter v0.8.3's bundled detection
recognizes only the lowercase filenames and silently lints a
`Kustomization` root as raw untransformed YAML (the gap that motivated
uniform external rendering — historical context, not an operational path).

```
GOFLAGS= GOWORK=off go run sigs.k8s.io/kustomize/kustomize/v5@<pin> build --enable-helm <root> > <scratch>/profile.yaml
```

Then lint the rendered file with pinned kube-linter, using the same `go run`
pattern:

```
GOFLAGS= GOWORK=off go run golang.stackrox.io/kube-linter/cmd/kube-linter@v0.8.3 \
  lint --config <config> --format json --output <scratch>/report.json <scratch>/profile.yaml
```

- **Reuse the repository's existing Kustomize pin only when it is a `v5.x`
  pin** (many operator repos pin a Kustomize version in their Makefile).
  The render command's module path is
  `sigs.k8s.io/kustomize/kustomize/v5`, and Go rejects a `/v5` module path
  paired with a `v4.x` (or older) version — a repository pinning, say,
  `v4.5.7` cannot be substituted in. For any non-v5 pin, use the fallback
  pin `v5.8.1` and record the difference (and the repository's own pin) in
  the report's provenance. The pinned invocation is the evidence of what
  rendered.
- `GOFLAGS=`/`GOWORK=off` keep the version-qualified `go run` standalone,
  insulated from the consumer's Go configuration. The linter runs on the
  host — keep report outputs in the designated scratch directory and never
  write to consumer paths (the renderer's chart-pull cache is the sole
  exception; see the `--enable-helm` bullet). Pin by module version, never
  an unpinned module.
- **`--enable-helm` is passed on every render.** A root whose kustomization
  declares `helmCharts` fails the build without it (`must specify
  --enable-helm`); roots without chart generators are unaffected. Chart
  inflation shells out to `helm` from PATH (verified against the pinned
  v5.8.1: it execs `helm version --short` as a gate and accepts Helm 4.3.2).
  Chart reach is not locally enumerable — a chart can arrive through a
  local base outside any scanned directory, a remote base, or a
  component — so the lint script installs the pinned Helm binary (the
  same module pin chart rendering uses, via `go install` into scratch)
  and prepends it to PATH on every run: inflation always runs the
  recorded version, never a host helm, and a chart-free repository pays
  one unused binary in scratch. Provisioning requires the Go toolchain
  (Go >= 1.26 for the Helm 4 pin) and downloads the module on first use
  (network access to the module proxy). Record the resolved version in
  the report. Remote chart repositories are
  fetched by that path: record them in the report's provenance like any
  remote input. The pull writes the chart into the
  root's chart home (`helmGlobals.chartHome` if set, else `<root>/charts/`)
  — the one renderer-owned write into the consumer tree. It cannot be
  redirected (kustomize rejects a chart home outside the root), it happens
  even when the render subsequently fails, and it is not cleaned up (a
  pulled chart is indistinguishable from a checked-in one). Disclose the
  write before rendering such a root (Hard limits), report it in the
  provenance, and propose gitignoring the chart home or vendoring the
  chart during onboarding.
- **Remote inputs are fetched by the renderer.** Remote references (URLs,
  `http(s)://`) are fetched by the pinned Kustomize exactly as the
  consumer's kustomization specifies. Record remote references in the
  report's provenance — the pin plus the recorded inputs are the record of
  what ran. A remote input on a moving ref (branch) can change between
  assessment and CI with the same pin and URL: record its resolved revision
  or content digest, and a digest of each rendered profile, so later runs
  are comparable.
- The standalone CLI tolerates paths the bundled renderer cannot (including
  `@` in directory names and spaces when properly quoted) — still verify the
  transformation's effect is visible in the rendered file before claiming
  the root was rendered.

Rules for explicit rendering:

- **One multi-document file per profile.** In v0.8.3, ordinary YAML files
  are grouped into lint contexts by containing directory, so writing a
  profile's render across several directories does **not** produce one
  related-resource context. Assemble the whole profile into a single
  multi-document file so cross-resource checks see the full set.
- **Alternative overlays stay isolated.** Render and lint each overlay
  separately; never concatenate overlays into one file to silence
  cross-resource diagnostics.
- A failed `kustomize build` is a non-success outcome; preserve stderr and
  do not fall back to raw-directory linting of the same root. Empty or
  comment-only renders are failures too, not passes.

## Step 3 — Assess per profile

- Lint each **selected** overlay (per the deployment-context rule in Step 1)
  as its own profile (e.g. `overlays/odh`, `overlays/rhoai`) with its own
  render and report section. Keep the profile's related resources —
  workloads, Services, NetworkPolicies, RoleBindings — together in one
  context.
- Record which root produced each finding (`.Object.Metadata.FilePath` in the
  JSON report shows the rendered file; keep the mapping back to the source
  root/overlay).

## Interpretation pitfalls

- **Namespace handling:** Kustomize namespaces are explicit in the render.
  `use-namespace` findings reflect the overlay's actual `namespace:` field —
  classify with that evidence, not assumptions about install-time behavior.
- **Generators and replacements:** `configMapGenerator`, `replacements`, and
  `patches` are applied during rendering; findings reference generated names
  (e.g. `name-hash` suffixes). Map them back to sources for the report.
- **Cross-resource checks:** `dangling-service`, `dangling-networkpolicy`,
  `mismatching-selector` are strong candidates when a profile renders the full
  related deployment set into one context — which is exactly why the
  single-file rule above matters. A NetworkPolicy selects pods by
  **pod-template labels**; verify selectors against pod templates, not
  workload metadata labels.
- **CRDs and custom resources:** CRs in a render are only schema-validated if
  kube-linter has a schema for them; report unsupported kinds as limits.

## Extra check candidates (only with manifest evidence)

- `dangling-service`, `dangling-networkpolicy`,
  `dangling-networkpolicypeer-podselector`, `mismatching-selector` — when the
  profile renders workloads plus their Services/policies together.
- `no-rolling-update-strategy`, `no-anti-affinity` — for HA-class controllers
  the overlay actually deploys with >1 replica or that warrant HA.
- `pdb-min-available` / `pdb-max-unavailable` — when the profile includes
  PodDisruptionBudgets.

## Handoff

Classify findings per the report template, keep the root/overlay-to-render
mapping, and route onboarding through the shared entry-point contract:
`scripts/lint-kustomize.sh` renders every root with the pinned Kustomize
and lints the rendered file — there is no native directory target and no
CI-specific path.
