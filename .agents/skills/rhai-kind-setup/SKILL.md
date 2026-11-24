---
name: rhai-kind-setup
description: >
  Generate standalone Bash scripts that install selected OpenShift and
  Prometheus Operator CRDs, set up test TLS serving certificates, and/or
  install a pinned cert-manager controller (Helm) on an existing
  Kind cluster. Use when the user asks for OpenShift or Prometheus
  Operator CRDs on Kind, Kind/OpenShift compatibility, a service-ca
  certificate stand-in on Kind, cert-manager for webhook-serving
  operators, or developing against OpenShift APIs without a full
  OpenShift install. Generation only: this skill writes scripts and
  never runs them or contacts a cluster. Not for creating or
  configuring Kind clusters (use dev-kind-setup), provisioning real
  OpenShift, emulating platform behavior, or managing cert-manager
  issuers or certificate policies.
user-invocable: true
allowed-tools:
  - Read
  - Glob
  - Grep
  - Bash
  - Write
  - Edit
---

# Kind OpenShift Compatibility Scripts

Generate one to three standalone Bash scripts into a user-chosen
destination so the project can use **selected OpenShift and Prometheus
Operator APIs** — and, when its webhooks need it, **cert-manager** — on
an **existing Kind cluster**, not an OpenShift emulation:

| Template (relative to this skill) | Generated file | Purpose |
| --- | --- | --- |
| [templates/scripts/install-openshift-crds.sh.tmpl](templates/scripts/install-openshift-crds.sh.tmpl) | `install-openshift-crds.sh` | Regenerate selected OpenShift and Prometheus Operator CRDs with a pinned controller-gen and apply them to the named cluster |
| [templates/scripts/install-cert-manager.sh.tmpl](templates/scripts/install-cert-manager.sh.tmpl) | `install-cert-manager.sh` | Install the cert-manager controller from a pinned jetstack Helm chart on the named cluster |
| [templates/scripts/setup-service-certs.sh.tmpl](templates/scripts/setup-service-certs.sh.tmpl) | `setup-service-certs.sh` | Create or reuse a test CA and a CA-signed 30-day serving certificate for a Service |

The generated filename is the template filename without `.tmpl`. Generate
the scripts the user selected: the cert-manager installer is offered when
discovery (Step 1a) shows the consumer requires cert-manager or the user
asks for it; the service-cert stand-in when discovery shows a workload
mounts a service-ca-annotated Secret.

For the CRD installer the skill defaults to **broad, evidence-backed
coverage**: every API the consumer actually uses is offered, including
optional and guarded paths, so its OpenShift-only code paths run during
its own tests on Kind. The cert-manager installer covers a different
gap: webhooks whose CA cert-manager injects need the **controller** —
the CRDs alone issue no certificates.

## Hard boundaries

- **Generation only.** Skill use collects settings, verifies selections
  locally, and writes scripts. Invoking a generated script is a separate,
  explicit user action — never execute one "to check it works", and make
  no cluster, kubectl, or Kind call during generation. Local pinned
  controller-gen runs in private scratch are allowed.
- **No OpenShift emulation.** Installing a CRD makes the API server accept
  and store objects; it provides no OpenShift controllers.
- **Existing Kind cluster only.** The generated scripts verify the exact
  named cluster through Kind before any mutation, never create or
  reconfigure a cluster, and never fall back to the ambient kubectl
  context.
- **Standalone output.** Generated scripts import neither this skill, each
  other, nor any unshipped helper. They run under Bash (3.2-compatible)
  and each checks only the prerequisites it uses.
- **No invention of defaults.** Pins and settings come from the user's
  project metadata where unambiguous, otherwise from the user — never
  from reference projects such as ODH or Feast.

## Prerequisites

External prerequisites: **Bash, Go, kubectl** (1.22 or newer, for
server-side apply), **Helm 3** for the cert-manager installer,
**OpenSSL** for the certificate script, **jq** where JSON extraction is
needed, and the **container engine** backing the named Kind cluster
(whichever engine kind selects in the user's environment — Docker,
Podman, or nerdctl). Never install prerequisites automatically.

TLS operations must work with native macOS LibreSSL and Linux OpenSSL:
the templates avoid modern-only flags such as `verify -verify_hostname`
or `x509 -ext`; do not introduce such flags or a compatibility
framework when adapting them.

All tool invocations use exact pins via `go run`, for example
`go run sigs.k8s.io/kind@<version>` — never `@latest`, unpinned
fallback, or binary downloads. The one exception is the host `helm`
binary (no `go run` form): the cert-manager installer requires a Helm
3.13+ client (its preflight reads an existing release's chart with
`helm get metadata`, added in 3.13) and pins the install by passing the
exact chart version to `helm --version`.

## Workflow

### Step 1 — Collect selection and destination

Take from the request, or ask for:

1. **Script selection** — CRD installer, certificate script, cert-manager
   installer, or any combination.
2. **Destination directory** for the generated file(s); one already
   provided in the request is sufficient — do not re-ask.

If a target file already exists, show the proposed edits and wait for
explicit approval — never silently overwrite.

**Checkpoint:** selection and destination are known before anything is
written. If either is missing, ask — do not guess.

### Step 1a — Discover candidate resources and platform dependencies

Skip this step for certificate-only requests. Investigate the consumer's
source as the user provides it — the skill defines no clone or directory
convention; ask where the source lives before scanning if it is not at
hand.

Follow the discovery procedure in
[references/generation-workflow.md](references/generation-workflow.md):
scan for real API traffic (imports, scheme registration, comments, and
RBAC markers are leads only), map findings to CRD source modules, apply
[references/known-dependencies.md](references/known-dependencies.md),
[references/consumer-patterns.md](references/consumer-patterns.md), and
[references/detection-signals.md](references/detection-signals.md) with
their staleness gates, and present deduplicated candidates with
evidence and hard/soft/unresolved labels.

**Checkpoint:** the user has confirmed the final resource selection —
additions, opt-outs, the cert-manager installer and service-cert stand-in
decisions, and open
questions answered.

### Step 2 — Resolve pins and settings

Read the consumer project's metadata (typically `go.mod`) and adopt pins
that are **unambiguous** there; ask the user for anything absent or
ambiguous — never fall back to a reference project's versions. Collect
the per-script settings from the checklist in
[references/generation-workflow.md](references/generation-workflow.md):
cluster name and exact Kind version for all scripts (the container
engine is deliberately not collected — the cluster name is the only
cluster identity); CRD source-module, controller-gen, and yq versions
plus the confirmed selection and deprecated-resource policy for the CRD
installer; the namespace/Service/Secret/ConfigMap tuple and DNS domain
for the certificate script; the exact cert-manager chart version for
the cert-manager installer — always baked, never a floating install.

**Checkpoint:** every pin and setting is resolved to an exact value;
ambiguity blocks generation until the user answers.

### Step 3 — Verify locally (CRD installer only)

Before writing any script, verify the resource selection in private
scratch — no cluster calls, no script execution. Follow the procedure
in [references/generation-workflow.md](references/generation-workflow.md):
resolve each CRD source module via Go module metadata in an isolated
scratch, verify identities and scopes against the pinned modules, run
the pinned controller-gen, and compare with the source module's
committed manifests per
[references/schema-fidelity.md](references/schema-fidelity.md).

**Checkpoint:** every selected CRD has a verified identity, plural,
served version, scope, and controller-gen output path, plus a recorded
schema-fidelity outcome. Missing output, unsupported generation,
invalid manifest, or unresolved scope blocks generation — never worked
around by ad hoc manifest copying or API-schema emulation.

### Step 4 — Generate

Adapt the selected template(s) to the collected values:

- Substitute the `%%NAME%%` placeholders with shell-safe values and
  reject the output if any placeholder remains unresolved — `%%` never
  occurs in the script bodies otherwise (unlike `{{`), so "no `%%`
  remains" is an exact render-completeness check.
- Keep all settings grouped at the top of each generated script for
  user review and adjustment.
- For the CRD installer, retain `CRD_MODULES` rows only for the source
  modules of the confirmed selection; follow the table-pruning and
  synthetic-substitution rules in
  [references/generation-workflow.md](references/generation-workflow.md).
- Preserve the template's operational structure: linear named steps,
  quoted paths and values, preserved command errors, bounded waits,
  restricted key-file permissions, and a trap removing the script's
  private scratch directory (a unique `mktemp -d`, mode 700, removed on
  exit); no kubeconfigs, private keys, or generated Secrets are
  persisted to the destination.

### Step 5 — Report and hand off

After writing the file(s), report:

1. What was written, where, and the verified mappings/settings baked in.
2. **Suggested invocation commands** — exact and copy-pasteable, but **not
   executed** by the skill.
3. First-run network needs per script (pinned Go modules; the jetstack
   Helm repository index and chart for the cert-manager installer) —
   the detail is in
   [references/generation-workflow.md](references/generation-workflow.md).
4. The runtime behavior
   ([references/script-runtime-behavior.md](references/script-runtime-behavior.md))
   and the limitations below.
5. For the CRD installer, the discovery outcome: confirmed selections
   with their hard/soft labels and evidence, exclusions with reasons,
   and unresolved coverage limits. Any synthetic permissive CRD is
   listed explicitly with its group/version/kind and an unmissable
   warning: it is a storage-only stub — no schema validation,
   defaulting, or controllers — and the consumer's integration may
   fail at runtime against it, which is exactly what the test exists
   to reveal.

## What the generated scripts do at runtime

All scripts are existing-Kind-only and fail safe: they verify the exact
named cluster through the pinned kind CLI, pass a private scratch
kubeconfig to every cluster call (the ambient context is never used),
complete reads before any mutation, and stop with reported partial
state on failure — never rollback, delete, or force conflicts.
Per-script detail is in
[references/script-runtime-behavior.md](references/script-runtime-behavior.md);
read it before answering questions about what a generated script will
do.

## Limitations

- No OpenShift controllers, webhooks, or platform behavior — CRDs are
  stored, not reconciled.
- Synthetic permissive CRDs are storage-only stubs for APIs without a
  known CRD source: no schema validation, defaulting, or controllers —
  an extreme measure, confirmed case by case.
- Certificates are test stand-ins with a 30-day leaf; no renewal,
  rotation, or trust-store modification.
- cert-manager installs from the upstream jetstack Helm chart at the
  pinned version; the skill manages no issuers and never upgrades past
  the baked version (re-generate to move). Installing the controller is
  not an OpenShift compatibility claim.
- Existing Kind clusters only; the scripts never create or reconfigure
  a cluster, and the skill does not execute them, validate them against
  a live cluster, or install prerequisites.
