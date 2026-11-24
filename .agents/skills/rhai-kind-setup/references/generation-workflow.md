# Generation workflow detail

Detailed procedures for the rhai-kind-setup skill's generation steps.
SKILL.md carries the entry points and the checkpoints; read the section
for the step being executed before performing it. The hard boundaries —
generation only, no cluster calls, no invention of defaults — apply
throughout.

## Step 1a — Discovery procedure

Skip for certificate-only requests.

Investigate the consumer's source as the user provides it — their working
copy or a path they name. The skill defines no clone or directory
convention: never assume one, and ask where the source lives before
scanning if it is not at hand. The same rule covers any other repository
opened during the investigation, such as a dependent-module API's owning
operator.

Investigate which OpenShift and monitoring APIs the consumer actually
uses, directly or through a dependency, and whether it requires
cert-manager, so the selection is evidence-backed instead of guessed.
[consumer-patterns.md](consumer-patterns.md) records integration shapes
observed in real consumers — use it to recognize similar shapes,
including guarded, vendored, and build-tag variants, applying their
last-verified tags: stale evidence is re-verified or flagged before a
pattern is relied on for a selection:

1. Scan the consumer's controllers, managers, bootstrap/main setup,
   webhooks, e2e setup, deployment manifests, and Helm charts for API
   traffic: typed and dynamic/unstructured client calls, watches (`For`,
   `Owns`, `Watches`), and invoked helpers. Imports, scheme
   registration, comments, and RBAC markers are search leads only — not
   proof of traffic, and this is not a permission audit.
2. Map findings to CRD source modules: `*.openshift.io` groups →
   `github.com/openshift/api`; `monitoring.coreos.com` → the Prometheus
   Operator monitoring module. Never select a whole group or module, and
   do not add the other monitoring kinds just because one is used.
3. When a framework dependency is wired in, consult
   [known-dependencies.md](known-dependencies.md). Match the actual
   call site and its arguments/guards, verify the entry at the
   consumer's resolved version, apply the entry's staleness gate (a
   resolved version the entry's recorded verification does not cover is
   re-verified at that version or surfaced as a question — never
   silently reused), and follow only the recorded relationships. There
   is no generic dependency traversal: a `go.mod` entry without wired
   usage of a listed integration is not a hit, and an unmatched
   integration is reported as an open question — never silently skipped
   or recursively scanned.
4. Detect a **cert-manager requirement** using the signal catalog in
   [detection-signals.md](detection-signals.md). When the wiring is
   verified the requirement is **hard** — the CRDs alone issue no
   certificates, so the webhooks never serve without the controller.
5. Detect a **service-ca certificate requirement** using the signal
   catalog in [detection-signals.md](detection-signals.md): a workload
   volume mounting a Secret named by a Service's
   `service.beta.openshift.io/serving-cert-secret-name` annotation
   cannot schedule on Kind (FailedMount). The annotation alone is a
   report-only lead; a confirmed mount offers the service-cert
   stand-in for the mounting pod's namespace.
6. Detect **dependent-module APIs** — guards or startup discovery checks
   that reference *another operator's* API group — and resolve each
   through the source ladder in
   [detection-signals.md](detection-signals.md): the owning operator's
   Go API module first; a synthetic permissive CRD only as the extreme,
   user-confirmed fallback. Never stub an API a known source module can
   generate.
7. Present the deduplicated candidates: group/version and Kind, source
   module and pin, origin (consumer code or dependency), evidence (file
   and call), activation/fallback guard, and whether absence is **hard**
   (operation or startup fails), **soft** (verified missing-API
   fallback), or unresolved. Include the cert-manager and service-ca
   findings. Labels describe impact only — never an include/exclude
   filter, never a runtime table field.
8. Report unresolved cases — unknown wrappers, dynamic GVKs, unreadable
   guards — as questions, resolved with the user before finalizing the
   affected selection. Never treat uninspected as unused; never claim
   exhaustive reachability.

**Default disposition:** include every evidenced use, including guarded
or optional paths — those paths are exactly what API-surface fidelity
exists to exercise. Exclude only no-traffic scheme registration, unused
test fixtures, and demonstrably inactive paths, recording each exclusion.
A fixture that a selected test applies (for example an e2e
ServiceMonitor manifest) is itself a use: its API stays selected so the
test can apply it on Kind. An evidenced cert-manager requirement offers
the cert-manager installer. An evidenced service-ca mount offers the
service-cert stand-in. Keep the deprecated-resource policy in the Step 2
checklist and disclose what it excluded.

## Step 2 — Collection checklist

Read the consumer project's metadata (typically `go.mod`) and adopt pins
that are **unambiguous** there: `sigs.k8s.io/kind`,
`github.com/openshift/api`, `sigs.k8s.io/controller-tools`, and — when
Prometheus Operator CRDs are selected — the CRD-only API module
`github.com/prometheus-operator/prometheus-operator/pkg/apis/monitoring`.
Ask the user for anything absent or ambiguous; never fall back to a
reference project's versions.

Collect, per script:

- **All scripts:** existing Kind cluster name; exact Kind version. The
  container engine is deliberately not collected: kind selects its
  engine from the environment (`KIND_EXPERIMENTAL_PROVIDER` when set,
  otherwise autodetection), the generated scripts never set or force it,
  and the same generated script must work in any environment with any
  provider — the cluster name is the only cluster identity.
- **CRD installer additionally:** exact versions of every CRD source
  module (`github.com/openshift/api`, plus the Prometheus Operator
  monitoring module when its CRDs are selected); exact controller-gen
  version; the exact yq version for the installer's structured manifest
  edits — resolve the latest stable upstream release at generation time
  and state it, the same rule as the cert-manager chart version, never
  floating; the confirmed Step 1a resource selection — for each CRD,
  the source module, API group/version, Kind, source package, output
  file, and resource scope. Exclude **deprecated** resources by
  default: check each selected resource's Go type in the pinned module
  for a resource-level `Deprecated` doc comment (for example
  `DeploymentConfig` in `apps/v1/types.go`) and drop it unless the user
  explicitly asks for it; field-level deprecation comments and
  `legacy.go`/`register.go` boilerplate do not count. If a deprecated
  resource was found reachable in Step 1a, flag it and ask instead of
  silently dropping it. For confirmed synthetic stubs, collect the
  group, version, Kind, plural, and scope of each — each stub requires
  the user's explicit confirmation.
- **Certificate script additionally:** namespace; Service name; TLS
  Secret name; CA ConfigMap name; cluster DNS domain — ask when the
  domain is customized rather than assuming `cluster.local`.
- **Cert-manager installer additionally:** the exact cert-manager chart
  version. Resolve the latest stable upstream release at generation
  time (from the upstream release feed — a generation-time lookup, not
  a cluster call), state it, and confirm with the user; adopt the
  consumer's own pin instead when discovery found one (for example a
  Helm chart dependency or a pinned deployment manifest). The version
  is always baked and passed to `helm --version` — never a floating
  install.

## Step 3 — Local verification procedure (CRD installer only)

Before writing any script, verify the resource selection in private
scratch:

1. Resolve each selected CRD source module's location —
   `github.com/openshift/api` or the Prometheus Operator monitoring
   module — via Go module metadata, never hand-built GOPATH strings,
   inside an isolated scratch directory so the consumer's `go.mod`,
   `go.sum`, workspace settings, and module-cache sources remain
   untouched. Pinned module downloads are allowed; edits to
   module-cache sources are not.
2. Inspect the pinned modules' authoritative definitions/generated
   manifests to establish each selected CRD's identity, plural, served
   version, and resource scope.
3. Run the pinned controller-gen in the same scratch and confirm the
   selected outputs are produced and match the verified identities and
   scopes. Generating a package may produce sibling definitions in
   scratch; only the explicitly selected CRD files are applied by the
   generated script.
4. Compare each selected CRD's generated manifest against the source
   module's own committed CRD manifest when one exists, following
   [schema-fidelity.md](schema-fidelity.md). Schema-relevant
   differences are surfaced with the diff at the checkpoint; a complete
   single-document committed manifest may be chosen as the install
   source for its resource (the generated script installs it
   verbatim), while fragment and feature-gate-merge manifests are
   evidence only.
5. Bake the **verified** mappings into the script. Encode only specific
   verified scope corrections — ODH's `fetch-external-crds` corrects
   `Ingress`/`Authentication` (`config.openshift.io`) and `OAuthClient`
   (`oauth.openshift.io`) to `Cluster`. Treat that as evidence to
   verify against the pinned output, not as an install list, and never
   rewrite `Namespaced` to `Cluster` globally.

No cluster calls and no execution of generated scripts happen in this
step.

Confirmed synthetic stubs are exempt from the generated-output
requirement (they have no source module by definition): each is
verified separately for group, version, Kind, plural, and scope, and is
never blocked for lacking controller-gen output.

## Step 4 — Table pruning and substitution detail

- For the CRD installer, retain `CRD_MODULES` rows only for the source
  modules of the confirmed selection, so a single-family request (only
  OpenShift, or only monitoring) requires no unrelated version pin and
  leaves no unreplaced placeholder. When the pruned row is the table's
  last, move the closing quote onto the new last row — the table stays
  a valid backslash-continued string. This is a content adaptation of
  the rendered script — never an edit to the template itself. The
  synthetic table substitutes the same way: rows joined by newlines
  with no trailing newline (the template's closing quote lands on the
  last substituted row), and an empty substitution leaves a table with
  no entries, which the script safely skips.

## Step 5 — First-run network needs

- The CRD installer downloads the pinned `sigs.k8s.io/kind`,
  `sigs.k8s.io/controller-tools`, and CRD source modules
  (`github.com/openshift/api` and the Prometheus Operator monitoring
  module when used).
- The certificate script downloads the pinned `sigs.k8s.io/kind`
  module.
- The cert-manager script downloads the pinned `sigs.k8s.io/kind`
  module, the jetstack Helm repository index, and the pinned chart (the
  index and chart land in the script's private scratch, not the user's
  Helm state).
- Downloads go to the shared Go module cache — cached sources are never
  edited or removed — and the go-invoking scripts clear `GOWORK` and
  `GOFLAGS` on every `go` invocation.
