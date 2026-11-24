# CRD schema fidelity

Step 3's comparison procedure for catching silent divergence between the
pinned controller-gen output and the CRD manifest the source module
itself ships. The identity, plural, and scope checks catch the wrong
resource; this comparison catches a **weaker schema** — the committed
manifest often enforces validation the Go markers alone do not
reproduce.

## Why regeneration can diverge

controller-gen derives a CRD from Go types and kubebuilder markers, but
projects post-process that output: feature-gate merges, manual override
fragments, hand-added CEL rules, enums, required fields, and printer
columns. Observed (openshift/api `v0.0.0-20261002115817-f8795cdde518`
under controller-gen v0.20.1): the committed
`routes.route.openshift.io` manifest carries `allOf`/`anyOf` structural
constraints, and the committed `apiservers.config.openshift.io` (Default
variant) carries `x-kubernetes-validations` CEL rules, `required`, and
`enum` constraints — none present in the regenerated output. The
regenerated CRDs accept a strict superset of what production OpenShift
accepts.

## Locating the shipped manifest

Inside the pinned module's resolved source directory (the module-cache
path Step 3 already resolves), search in order:

1. The package directory's `zz_generated.crd-manifests/` (the
   openshift/api layout) and `config/crd/bases/` (the kubebuilder
   layout).
2. Any `.yaml`/`.yml` file in the module whose `metadata.name` equals
   the selected CRD name.

The manifest must come from the same module and pinned version as the
generated output — never from the consumer's checkout or another
release. A module may ship none (the Prometheus Operator monitoring
module and the mlflow-operator api module ship Go types only): record
"no shipped manifest; regeneration is the only source" and stop there.

## What may be installed

Only a **complete, single-document** CustomResourceDefinition with the
expected `metadata.name` may become a shipped-manifest override (a
`SHIPPED_MANIFESTS` row). Fragment and merge inputs are evidence-only
and are never installed:

- `manual-override-crd-manifests/` and
  `zz_generated.featuregated-crd-manifests/` files are fragments — no
  `spec.group`/`names`/`scope` of their own.
- Feature-gate variants (for example `apiservers-Default.crd.yaml` vs
  `-CustomNoUpgrade`) are pre-merged payloads; the Default variant is
  the production payload and the only variant ever offered.
- Multi-document files are rejected outright.

## Normalization and comparison

Strip what legitimately differs, then compare semantic content:

1. Delete `metadata.annotations."controller-gen.kubebuilder.io/version"`
   from both sides (generated and committed manifests come from
   different controller-gen versions).
2. Convert both to canonical JSON with sorted keys and compare. Any
   local YAML/JSON tooling may be used — this is generation-time
   verification, not script runtime.

## Outcomes

- **Identical** → record verified-against-shipped.
- **Cosmetic-only differences** (annotations such as
  `api-approved.openshift.io`, labels, `description` text) → record and
  proceed with the generated manifest.
- **Schema-relevant differences** (anything under
  `spec.versions[].schema`, `subresources`, `conversion`, `required`,
  `enum`, `x-kubernetes-*`, printer columns, or `spec.scope`) → surface
  the diff at the Step 3 checkpoint. When the committed manifest is
  complete and single-document, offer it as the install source — the
  generated script then installs the committed manifest verbatim
  instead of the regenerated one. Otherwise the choice is accepting the
  weaker generated schema or dropping the resource. Never hand-edit a
  generated manifest to force a match, and never silently prefer either
  side.

The generated script re-verifies at runtime what generation verified:
each override row's file is checked to be a single complete
CustomResourceDefinition with the expected name and a valid scope before
it replaces the generated output. Regeneration is deterministic — the
same pinned controller-gen over the same pinned modules — so a
generation-time comparison remains valid at runtime.
