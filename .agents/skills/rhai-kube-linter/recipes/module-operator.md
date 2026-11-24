# Module operator recipe (RHAI)

**Load this recipe when** the repository's manifests declare deployment of
other operators or operands — bundled operator manifests inside the repo,
roles granting access to another operator's CRDs, or install logic whose
checked-in artifacts reference operand resources. Detect this from manifest
**content**, never from repository names. Compose with the Helm and/or
Kustomize format recipe; the ordinary-operator recipe is not automatically
needed.

## Locating module and operand manifests

**A module's manifest location is defined by the ODH operator, not by
repository convention.** When the target is an RHAI module, read the
opendatahub-operator's `manifests-config.yaml` (repository root): each
`components.<name>` entry gives the per-platform (`odh`/`rhoai`) `repo`,
`ref` (branch@commit), and `sourcePath` of the module's actual manifests:

```yaml
components:
  kserve-module-operator:
    odh:
      repo: opendatahub-io/kserve
      ref: release-v0.17@ac6709afdebd062793cb49d0465190c175662513
      sourcePath: kserve-module/config
```

Read the config at the revision matching the deployed operator release, and
lint at the pinned commit, not the branch head. If the module is not listed,
ask the consumer where the deployment actually sources its manifests rather
than guessing from repository layout.

**A module operand's deployed manifests are defined by the related module
operator.** When the target is an operand that a module operator deploys,
that module operator's checked-in controller configuration and vendored
operand config are the authority for which overlays and manifests are
actually deployed — see "Which operand overlay is deployed is the module's
choice" below. Assessing the operand repository in isolation cannot
establish this.

## Separate the three workload classes

Keep these distinct by pod-template labels, service accounts, namespaces, and
bundle boundaries — conflation here poisons every downstream conclusion:

1. **Module controller** — the operator this repository ships (e.g. its own
   Deployment in its own namespace).
2. **Deployed operand operators** — the operators/operands the module
   installs (their manifests may be bundled in this repo or referenced).
3. **Operand-created workloads** — resources the operand operators create at
   runtime; they are not in any render.

A NetworkPolicy shipped by the module targets the **module controller's** pods
when its selector matches class 1's pod-template labels — verify against the
actual pod template, not workload metadata labels and not the operand's
labels.

**Which operand overlay is deployed is the module's choice.** When the operand
repository ships multiple Kustomize overlays (e.g. `odh`, `rhoai`,
`openshift`), the relevant one is determined by what the module operator — or
the ODH operator deploying the module — actually selects. Read the module's
checked-in controller configuration and vendored operand config to identify
the deployed overlay(s) (e.g. overlay constants, operand manifests copied from
a specific overlay), and scope any operand context to those overlays. Do not
assume every overlay in the operand repository is deployed.

## Why a module operator's permissions can legitimately be broad

Kubernetes RBAC escalation rules (see
<https://kubernetes.io/docs/reference/access-authn-authz/rbac/#restrictions-on-role-creation-or-update>):

- **Role creation/update:** you cannot create or update a Role/ClusterRole
  containing permissions you do not already hold, unless you are authorized to
  `escalate` roles.
- **Role binding:** you cannot bind a role to a subject unless you hold every
  permission in that role, unless you are authorized to `bind` it.

A module operator that installs an operand's RBAC therefore either (a) holds
every permission the operand roles grant — its own role legitimately
encompasses the operand's permissions — or (b) carries `escalate`/`bind`
authorization. Pattern (a) is the preferred design. Consequences for
assessment:

- `access-to-secrets`, `access-to-create-pods`, or broad verbs on the module
  controller can be the **necessary consequence of pattern (a)** — classify as
  expected requirement when the operand's checked-in roles demonstrably
  require them.
- Never recommend adding `escalate` or `bind` as a default fix, and never
  recommend stripping installation-required permissions just to pass a check.
- Expected role-installation permissions do **not** excuse unrelated broad
  grants: `cluster-admin-role-binding`, wildcards outside the operand's API
  groups, or permissions in namespaces the module does not manage remain
  observed issues.

## Static containment analysis (manual — kube-linter does not do this)

kube-linter's access checks are risk signals, not a containment proof. The
containment comparison is yours, and it is static:

- Compare the module controller's checked-in Roles/ClusterRoles against the
  operand's checked-in roles: API groups, resources, verbs, `resourceNames`
  scoping, non-resource URLs, and namespace vs cluster scope.
- Check for `aggregationRule` ClusterRoles — aggregated permissions are not
  visible in the role's `rules` alone.
- Report the **smallest demonstrated gap** conservatively. If operand RBAC
  lives in another repository, is generated at runtime, or bindings are
  created dynamically, that evidence is missing: report it as unresolved
  coverage. Never claim the running service account lacks a grant solely
  because one checked-in role file does not contain it.
- Keep this analysis explicitly separate in the report from what kube-linter
  checked — recommendations vs enforced coverage.

## Check interpretation in module context

- `no-system-group-binding`: ClusterRoleBindings to `system:*` groups grant
  broad platform-principal access; flag as observed issue.
- `wildcard-in-rules`: scoped to the operand's CRD groups → likely expected
  requirement (record the groups); `*` on `*` or core groups → investigate as
  unrelated breadth.
- Probes/resources/security context on the **module controller** pod follow
  the ordinary-operator recipe's guidance; findings on bundled operand
  manifests are reported against the operand, with its own classification.
- Propose exceptions narrowly: object-level annotation exceptions or
  tightly-scoped config exclusions with justification. Never propose
  exempting all operator RBAC.

## Handoff

Record the three workload classes, the containment comparison (or its missing
evidence), per-check classifications, and narrow exception proposals per the
report template. Route onboarding through the shared entry-point contract. No
history investigation, source debugging, or manifest edits — static manifest
evidence only.
