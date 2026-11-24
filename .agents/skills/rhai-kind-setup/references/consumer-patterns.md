# Consumer integration patterns

Learning material for Step 1a discovery: integration shapes observed in
real consumers, with the evidence they were learned from. Use them to
recognize similar shapes in an unfamiliar consumer — they are examples,
not an install list, and never a substitute for the consumer's own
evidence.

## Patterns

### 1. Unconditional watch — hard requirement

The controller wires `Owns`/`Watches`/`For` on an external-API type with
no guard. The manager's cache start fails when the CRD is absent, so the
operator cannot run.

- Evidence: feast-module-operator `595996b` (last verified 2026-11),
  `internal/controller/feastoperator/feastoperator_controller.go:115`
  — `Owns(&promv1.ServiceMonitor{})`, unconditional in `NewReconciler`.
- Discovery: **hard** candidate; include.

### 2. Bootstrap read with missing-API fallback, conditional watcher

Setup GETs a singleton (for example `APIServer` named `cluster`); a
`NoMatchError` (API not served) selects a fallback and suppresses the
watcher; `NotFound` (API served, object missing) selects the fallback but
still registers the watcher. Other errors propagate.

- Evidence: feast-module-operator `595996b` (last verified 2026-11), `pkg/manager/tls.go:127-170`
  (`loadTLSProfile`), `:41-69` (`registerTLSProfileWatcher` gated on
  `Watchable`), through the framework entry in
  [known-dependencies.md](known-dependencies.md).
- Discovery: **soft** for the read (verified fallback), hard for the
  watcher once registered. Include — with the CRD present, the
  OpenShift branch runs instead of the fallback.

### 3. The same integration, vendored in-repo

Pattern 2's shape does not require a framework dependency: the identical
watcher (For the `APIServer` singleton, name predicate, no leader
election) can live in the consumer's own tree.

- Evidence: opendatahub-io/kserve `1eaf4ae` (last verified 2026-11),
  `pkg/tls/distro/watcher.go` (`ProfileWatcher` `For(&configv1.APIServer{})`,
  name predicate `cluster`), `pkg/tls/distro/profile_events.go`.
- Discovery: recognize the shape wherever it lives — dependency,
  vendored, or hand-written. Same candidate, same labels.

### 4. Runtime CRD-availability guard around a watch

Setup probes discovery (`IsCrdAvailable(config, groupVersion, kind)`) and
registers the `Owns`/`Watches` only when the CRD exists, logging and
skipping otherwise. The guard exists precisely so the integration turns
on when the API is present.

- Evidence: opendatahub-io/kserve `1eaf4ae` (last verified 2026-11),
  `pkg/controller/v1alpha1/inferencegraph/controller_setup_odh.go`
  (Route `Owns` behind `IsCrdAvailable`), `pkg/controller/v1alpha2/llmisvc/controller_setup_odh.go:84-90`
  (PodMonitor and ServiceMonitor `Owns`, each behind its own probe),
  `pkg/utils/utils.go:217` (`IsCrdAvailable`).
- Discovery: candidate with the guard recorded; **include by default**.
  On a bare cluster the guarded branch is dead; installing the CRD is
  what makes the consumer's OpenShift path run.

### 5. Build-tag-gated platform integration

OpenShift usage compiles only into a specific build (`//go:build distro`
files with `_odh` suffixes and `_default` counterparts). The vanilla
build of the same module contains none of it.

- Evidence: opendatahub-io/kserve `1eaf4ae` (last verified 2026-11), file pairs such as
  `controller_setup_odh.go` / `controller_setup_default.go` in
  `pkg/controller/v1alpha1/inferencegraph/` and
  `pkg/controller/v1alpha2/llmisvc/`; the Route reconciler
  `openshift_route_reconciler_odh.go` (constructs and owns `route/v1`
  Route objects for raw-deployment graphs).
- Discovery: reachability depends on the build variant. Record which
  build the evidence comes from and ask the user which build the
  consumer actually runs before excluding anything as
  build-tag-unreachable.

### 6. Annotation and comment references are not traffic

Strings like `serving.knative.openshift.io/enablePassthrough` — an
annotation the platform consumes — and OpenShift mentions in comments
appear in code that never calls an OpenShift API.

- Evidence: kserve/kserve `a91730b` (last verified 2026-11),
  `pkg/constants/constants.go:129` and the passthrough in
  `pkg/controller/v1alpha1/inferencegraph/knative_reconciler.go:200-202`;
  upstream has no `openshift/api` or monitoring dependency at all.
- Discovery: no candidate from annotations, comment text, or string
  constants. Record them as investigated leads only.

### 7. Fork and upstream diverge

A consumer fork can carry platform integrations the upstream module
lacks (or vice versa). Never assume the upstream shape.

- Evidence: kserve/kserve `a91730b` (last verified 2026-11) — no OpenShift API traffic; the
  opendatahub-io fork `1eaf4ae` (last verified 2026-11) — Routes, APIServer watcher, PodMonitor
  and ServiceMonitor behind distro build tags.
- Discovery: always inspect the consumer's actual source — its module
  path, `replace` directives, and build tags — and say which source the
  evidence came from.

### 8. Per-kind evidence, never family-wide

Two consumers of the same API family needed different subsets: feast
watches only ServiceMonitor; the kserve distro build owns PodMonitor and
ServiceMonitor.

- Evidence: the citations above.
- Discovery: one candidate per kind with its own evidence; never select
  a whole group or module because one kind is used.

### 9. Webhook CA injection via cert-manager — and its scaffolded look-alike

Admission or conversion webhooks annotated
`cert-manager.io/inject-ca-from` need the cert-manager **controller**, not
just its CRDs: nothing issues the `Certificate`, so the webhook never
serves. The kubebuilder shape (`config/certmanager` + `config/webhook`
wired into the deployed kustomization) is the common wiring.

- Evidence (required): opendatahub-io/kserve `1eaf4ae` (last verified 2026-11) —
  `config/default/kustomization.yaml` includes `../certmanager/kserve`
  and `../webhook`; `cert-manager.io/inject-ca-from` annotations in
  `config/webhook/localmodel/manifests.yaml` and the CRD cainjection
  patches; `apiVersion: cert-manager.io/v1` Certificates under
  `config/certmanager/`.
- Evidence (look-alike): feast-module-operator `595996b` (last verified 2026-11) —
  `config/webhook/` contains only a kustomization: no `manifests.yaml`,
  and `config/default/kustomization.yaml` does not reference it; the
  chart generator handles webhook GVKs generically. Scaffolded but
  unwired → no requirement.
- Discovery: verify the wiring — what the deployed kustomization
  includes, annotations on actually-deployed manifests, chart
  dependencies — never the mere presence of a scaffolded directory.
  **Hard** when wired; offer the cert-manager installer.

### 10. Dependent-module APIs and the synthetic-stub escape hatch

A consumer may integrate with *another operator's* CRDs behind a discovery
guard, and for a **module operator** the requirements may live in the
workload it deploys, not in its own repository: the module applies a second-level
operator whose guards and watches are the real requirements. Discover at
every level — the operator, its applied overlays, and the deployed
operator's own source (pinned by image or release metadata).

- Evidence: feast-module-operator `595996b` (last verified 2026-11) deploys
  `quay.io/feastdev/feast-operator:0.68.0` (source feast-dev/feast `v0.68.0`)
  — the deployed operator's `SetIsOpenShift`/`HasServiceMonitorCRD`/
  `HasMlflowCRD` discovery checks (startup `ServerGroups()` scan) gate a
  Route reconciler, ServiceMonitor creation, and an unstructured
  `Watches` on `mlflow.opendatahub.io/v1, Kind=MLflow` with a mapper
  (`internal/controller/services/util.go`,
  `featurestore_controller.go:288-300`). The module's own Route RBAC
  marker existed only for the deployed workload's benefit.
- Discovery: guards referencing foreign API groups are candidates like any
  other. Resolve the CRD source in order: the owning operator's Go API
  module (verified through controller-gen like any source), or — only with
  explicit user confirmation, when no source can be located or verified — a
  **synthetic permissive CRD** (right group/version/kind/plural/scope,
  `x-kubernetes-preserve-unknown-fields: true`, status subresource). The
  stub is the extreme measure: prefer the owning operator's Go API module
  for any API it can generate, and fall back to the stub only when no
  source can be located or verified.
- Platform-dependent overlays change the applied set: the feast module's
  rhoai overlay applies a ServiceMonitor and OpenShift TLS RBAC that the
  odh overlay does not — record which overlay the evidence comes from.

## Maintenance

New patterns require recorded evidence (repository, revision, files,
symbols) exactly like the entries above. Every entry carries its
evidence revision and a last-verified date. Relying on a pattern for a
selection decision records that reliance — and the pattern's
last-verified date — in the generation record; when the cited
repository's current revision has moved well past the evidence
revision, re-verify the cited behavior at a current revision before
relying on it, or flag the reliance as unverified. Shapes are stable;
cited files, lines, and guard details are not. Re-verify cited behavior
when a consumer resolves a different revision, and record mismatches as
gaps rather than best-effort guesses.
