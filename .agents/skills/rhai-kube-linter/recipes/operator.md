# Ordinary operator repository recipe

**Load this recipe when** the repository ships a controller/operator that
manages its own custom resources (kubebuilder-style `config/` layout, CRDs, a
controller manager Deployment) and does **not** install other operators or
operands. If the manifests declare deploying other operators or operands,
switch to the module-operator recipe. Compose with the Helm and/or Kustomize
format recipe.

## What an operator legitimately needs

Assess these areas from the checked-in manifests; each maps to baseline or
candidate checks:

- **Controller identity:** dedicated service account (not `default`), explicit
  `serviceAccountName` in the manager pod template.
- **RBAC scope:** role bindings matched to what the controller watches and
  manages — namespace-scoped roles for namespaced operands, ClusterRoles only
  for cluster-scoped or watch-across-namespaces needs. Record API groups,
  resources, verbs, and `resourceNames` scoping.
- **Workload hygiene on the manager pod:** liveness/readiness probes
  (kubebuilder scaffolds `/healthz` and `/readyz` — a missing probe is usually
  a real gap), resource requests/limits, non-root security context,
  `readOnlyRootFilesystem`, no privilege escalation.
- **Availability:** leader election is normal for controllers; a single
  replica with leader election enabled is a deliberate design, not
  automatically a `minimum-three-replicas` defect.
- **Network:** a NetworkPolicy for the controller's own pods, selected by the
  manager pod-template labels (not the Deployment's metadata labels); metrics
  access considered in the policy.
- **Webhooks (if present):** cert-manager or manual certificates, Service
  ports, and the `ValidatingWebhookConfiguration`/`MutatingWebhookConfiguration`
  objects.

## Interpreting RBAC findings — necessary access vs unrelated breadth

- `access-to-secrets`, `access-to-create-pods`: the controller may genuinely
  watch or create these. Classify as expected requirement **only** when the
  checked-in RBAC and the controller's documented/watched resources support
  it; an unrelated broad grant stays an observed issue.
- `wildcard-in-rules`: wildcards scoped to the operator's own CRD API group
  are common and usually acceptable (record the group); wildcards across core
  or unrelated API groups need justification.
- `cluster-admin-role-binding`: essentially never justified for an ordinary
  operator; treat as an observed issue unless the repository demonstrates a
  specific requirement.
- A single replica or legitimate secret access does **not** justify a global
  exclusion of `minimum-three-replicas` or `access-to-secrets`. If HA is
  genuinely not required, propose a narrow, object-level exception with
  justification instead.
- **Subject completeness is covered only by the baseline's custom check.**
  v0.8.3 has no builtin check for a ServiceAccount subject missing its
  `namespace`, and the OpenAPI schema does not require it (the rule lives
  in API-server validation code, which rejects a ClusterRoleBinding with
  such a subject on apply; a RoleBinding subject without a namespace is
  valid — it defaults to the binding's own namespace). The baseline's
  `sa-subject-namespace` CEL custom check (templates/kube-linter.yaml) is
  scoped to ClusterRoleBindings accordingly and catches it statically; if
  the consumer's config lacks an equivalent, propose it. A namespace-less
  subject may be a deliberate fragment completed by the consuming
  Kustomize overlay (see the Kustomize recipe) — classify against the
  composition context.
- **Subject existence is covered only by the baseline's custom check.**
  v0.8.3 has no builtin check for a binding subject naming a
  ServiceAccount that no manifest creates (`non-existent-service-account`
  covers only pod specs), and such a binding renders and schema-validates
  cleanly while granting nothing once applied. The baseline's
  `sa-subject-exists` CEL custom check (templates/kube-linter.yaml)
  catches it on rendered output; it stays silent when the corpus contains
  no ServiceAccounts at all, so platform-managed fragments remain
  lintable. Kustomize `namePrefix` cannot produce this defect — the
  NameReference transformer rewrites subjects to the referenced object's
  final name in every build topology — only a hardcoded subject that
  matches nothing does (a split build, a post-hoc replacement, or a
  hand-written reference).
- **A grant on the manager role is not necessarily manager-used.**
  Operators commonly provision RBAC for the workloads they deploy (for
  example, a Role for a cronjob ServiceAccount that execs into an init
  pod). When the manager's own demonstrable behavior does not cover a
  grant, classify the manager-held copy as unproven excess and note that
  workload-facilitation may explain it — that lives in controller logic
  and needs the consumer to confirm.

## Extra check candidates (with evidence)

Every firing/noise classification recorded here was confirmed with a
reproducer — a minimal fixture with a positive control that must fire
and negative controls that must stay silent, run with the pinned
kube-linter. Static source traces are hypotheses, not evidence; in
validation they mispredicted two of the checks below.

- `no-rolling-update-strategy` — confirmed to fire on a Deployment with
  no explicit `spec.strategy` (absent type does not match the required
  regex). Absence defaults to RollingUpdate, so this encodes a
  make-it-explicit policy preference, not a defect.
- `no-node-affinity` — confirmed to fire when affinity is unset. For a
  single-replica leader-elected controller this is deliberate deferral
  (feast's scaffold carries a commented-out affinity TODO); treat as
  informational. `no-anti-affinity` — confirmed to fire from 2 replicas
  without inter-pod anti-affinity, silent at 1 replica or unset.
- `dangling-service`, `mismatching-selector` — silent on confirmed
  renders where Services and selectors are wired correctly; candidates
  only when a profile actually renders the related deployment set.
- Confirmed noise on idiomatic operator controller manifests — do not
  propose for controller targets: `dnsconfig-options` (fires on every pod
  without dnsConfig), `restart-policy` (fires on every Deployment
  omitting the redundant `restartPolicy: Always`),
  `minimum-three-replicas` (fires on the deliberate single replica of a
  leader-elected controller). These exclusions are scoped to controller
  resources only — application workloads in the same repository are
  assessed per the application recipe, which may require these checks
  (`dnsconfig-options` when `dnsConfig` is set, `minimum-three-replicas`
  for HA-class services).

## Handoff

Map observations to check decisions, narrow exception proposals, and concise
evidence per the report template. Route onboarding through the shared
entry-point contract. Do not audit Go source to explain RBAC; the manifests
and documentation are the evidence base.
