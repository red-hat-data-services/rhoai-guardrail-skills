# Detection signals

Signal catalogs for Step 1a's platform-dependency detection. The workflow
file keeps the procedure; this file holds the full signal lists and the
dependent-module source ladder. New signals require recorded evidence
(repository, revision, files, and the observed behavior) before they are
added here.

## Cert-manager requirement

Detect admission or conversion webhooks whose CA is injected by
cert-manager. Signals, in order of strength:

1. `cert-manager.io/inject-ca-from` annotations on webhook
   configurations or on CRD conversion stanzas.
2. A `config/certmanager` kustomize component wired into what is
   actually deployed (present in the tree but unreferenced by the
   deployed kustomization is not wired).
3. A Helm chart dependency on cert-manager.
4. A `Certificate` resource in deployed manifests.

A scaffolded `config/webhook` directory that the deployed kustomization
does not reference is a **lead, not a requirement** — verify the wiring
like any other candidate. When wired, the requirement is **hard**: the
CRDs alone issue no certificates, so the webhooks never serve without the
controller.

## Service-ca certificate requirement

Detect workloads that mount a Secret only OpenShift's service-ca operator
would create. Signals, in order of strength:

1. A pod-spec volume mounting `secretName: X` **plus** a Service in the
   same namespace annotated
   `service.beta.openshift.io/serving-cert-secret-name: X`. The pair is a
   **hard** requirement: on Kind nothing creates the Secret, so the pod
   blocks in `ContainerCreating` with `FailedMount`. This pair is the
   trigger for offering `setup-service-certs.sh`.
2. The annotation without a matching mount is a **lead only** — on Kind
   the annotation is inert. Report it; generate nothing.

Namespace and timing caveats:

- The Secret is namespace-scoped, so the stand-in must be created in the
  namespace of the **mounting pod** — not whatever namespace a kustomize
  overlay declares. A deploying operator can override namespaces at apply
  time (observed: an overlay declaring one namespace while the deploying
  operator applied its release into its own). Trace the namespace through
  the manifests' actual apply path; when an override is possible, record
  the target namespace as a verification point for the user.
- Prefer creating the certificate **before** the workload is scheduled —
  `FailedMount` blocks pod startup and adds noise and delay, and operands
  often appear dynamically (for example, when a module CR is created), so
  generation-time detection followed by pre-creation is the predictable
  timing. It is not the only workable one: the kubelet retries mounting
  missing required Secrets, so a Secret created after scheduling — with
  the name and namespace the pod's volume references — normally unblocks
  the pod without a restart. Pre-creation avoids the FailedMount window;
  it is not a correctness requirement.

Exclude the stand-in when another creator is evidenced for the same
Secret: a cert-manager `Certificate`, or the operator's own self-signed
certificate logic.

## Dependent-module APIs

Guards or startup discovery checks that reference *another operator's*
API group — for example a `Has<Name>CRD()` flag feeding an unstructured
watch, mapper, or client call. Map the referenced group/version/kind like
any other candidate, then resolve its CRD source in order:

1. The owning operator's Go API module, added as a new `CRD_MODULES` row
   — only after Step 3 verifies the pinned controller-gen generates the
   needed CRD from its types. Investigate the owning operator's source
   under the same rule as the consumer's (Step 1a preamble): as the user
   provides it, never assuming a clone or directory convention.
2. If no source can be located or verified, and only with the user's
   explicit confirmation, a **synthetic permissive CRD** — the right
   group, version, kind, plural, and scope with
   `x-kubernetes-preserve-unknown-fields: true` and a status subresource,
   installed from the synthetic table. The stub is an extreme measure:
   the API server accepts and stores objects with no schema validation,
   defaulting, or controllers, and the report must label it as such.
   Never stub an API that a known source module can generate.
