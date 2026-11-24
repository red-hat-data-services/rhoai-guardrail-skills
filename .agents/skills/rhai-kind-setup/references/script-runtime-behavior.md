# Generated script runtime behavior

What each generated script does when the user runs it. The workflow file
summarizes the common guarantees; this file holds the per-script detail.
Read it before answering questions about what a generated script will or
will not do.

## Common guarantees

- **Existing-Kind-only target guard.** Every script verifies the exact
  named cluster through the pinned kind CLI, obtains its kubeconfig into
  private scratch, and passes it explicitly to **every** cluster
  invocation (kubectl and helm); the ambient context and global
  kubeconfig are never used or changed.
- **Reads before writes.** Reads complete before any mutation — a read
  failure stops with zero writes; a later failure may leave explicitly
  reported partial state, no rollback.
- **Private scratch.** A unique `mktemp -d` directory (mode 700, removed
  on exit via trap) holds kubeconfigs, private keys, generated manifests,
  and any tool state; nothing private is persisted to the destination.

## install-openshift-crds.sh

**API storage, not controllers.** A CRD makes the API server accept and
store objects of that kind, and the API server applies defaults declared
in the CRD schema itself. No OpenShift controllers exist in Kind, so
controller-driven defaulting, status population, and reconciliation
never happen.

**Flow:** the complete selected set is generated in private scratch
before any write, and every generated manifest is identity-checked
there — exactly one CustomResourceDefinition document with the expected
name and a valid scope, mirroring the shipped-manifest checks; committed
shipped manifests chosen during generation
then replace the generated file for their resources (copied verbatim
from the pinned module cache, after being verified as a single complete
CustomResourceDefinition with the expected name and a valid scope); the
verified per-resource scope corrections are applied to the generated
manifests as structured edits (a pinned yq sets and reads back
`spec.scope`, immune to controller-gen output formatting changes);
then each CRD is applied with
`kubectl apply --server-side` (kubectl 1.22+; client-side apply's
last-applied annotation exceeds the API server's 256KB limit on large CRD
schemas) and waited on with a bounded `Established` timeout — never
forced conflicts, stripped validation, or delete/recreate. An apply or
wait failure stops with explicitly reported partial state.

**Synthetic stubs:** confirmed synthetic permissive CRDs are rendered in
scratch before the first apply and applied the same way; they accept and
store any spec/status with no validation or reconciliation, and no
defaulting — their schema declares no defaults. A read-only preflight
before the first write classifies every synthetic CRD name: a stub is
applied only when no CRD with that name exists, or when the existing CRD
is itself a synthetic stub — exactly one version whose schema holds
nothing but `type: object` and
`x-kubernetes-preserve-unknown-fields: true`; any other stored schema,
including a real CRD that also sets the preserve-unknown-fields flag, or
a read failure, stops the script with zero writes. A stub never replaces
an existing schema.

## setup-service-certs.sh

**TLS stand-in, not the real service-ca.** On OpenShift, `service-ca`
injects and rotates certificates signed by the cluster CA. The script
instead creates a **local test CA** and a CA-signed **30-day** serving
certificate with SANs for `<service>.<namespace>.svc` and
`<service>.<namespace>.svc.<cluster-dns-domain>`. No CA signing key is
kept for renewal; there is no injector, rotation daemon, trust-store
change, or cert-manager dependency. The configured tuple is exactly:
namespace (creation allowed if absent), Service (need not exist — the
certificate covers its DNS names), TLS Secret, CA ConfigMap, and cluster
DNS domain.

**Certificate reuse policy:** neither object exists → create the Secret
(type `kubernetes.io/tls`, keys `tls.crt`/`tls.key`) and the ConfigMap
(key `service-ca.crt` with the matching public CA certificate). Both
exist and pass validation → leave both unchanged: object type and keys;
matching key pair; a trusted, unexpired chain valid for TLS-server
purpose; a non-CA leaf (basicConstraints CA:TRUE is rejected —
`openssl verify -purpose sslserver` alone accepts a CA certificate
that also carries serverAuth and the expected SANs); both Service DNS
identities present as SANs. Client-auth-only
and CN-only certificates fail. Anything else — one object missing,
validation failure, expiry — exits nonzero with actionable diagnostics;
existing material is never replaced or deleted. Authorization or network
errors are never treated as absence; a partial creation failure stops
with an explicit report, no rollback.

## install-cert-manager.sh

**Flow:** the named Kind cluster is verified through the pinned kind CLI
and a private kubeconfig exported into scratch, passed to every kubectl
and helm invocation; helm's repository configuration and cache also stay
in the private scratch, so the user's global helm state is never read or
changed. A read-only preflight refuses to take over cert-manager APIs
that exist without the script's Helm release, and refuses to upgrade a
same-named release that was installed from a different chart; both
preflight reads fail closed — only an exact NotFound or
release-not-found result counts as absence, and any other read error
(Forbidden, timeout, transient) stops the script with zero writes. The
release's chart identity is read with `helm get metadata` (helm 3.13+,
the first version with that command; `helm status` strips chart
information from its output entirely), and a release whose chart
identity cannot be read is never upgraded — an installation made by
other means is the user's to manage. Installation is
`helm upgrade --install` with the baked chart version and
`crds.enabled=true`, preserving an existing release's user-supplied
values (`--reuse-values`; a fresh install has none to reuse), followed
by bounded waits for the release's deployments to be Available and the
`certificates.cert-manager.io` CRD to
be Established. Failures leave explicitly reported partial state; nothing
is uninstalled, rolled back, deleted, or force-conflicted. Re-running
upgrades in place to the same pinned version and never moves beyond it.
cert-manager issues certificates; the script configures no Issuers,
ClusterIssuers, or Certificates.
