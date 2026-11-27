---
name: rhai-kube-linter
description: Onboard a repository with Helm or Kustomize manifests to kube-linter and analyze kube-linter failures. Recommend the best evidence-based combination of kube-linter checks for the repository's actual manifests, classify findings with manifest evidence, propose narrowly scoped exceptions, and propose approval-gated onboarding (config, shared lint script, Makefile target, GitHub Actions workflow). Use when asked to set up or run kube-linter, choose kube-linter checks, lint Helm charts or Kustomize overlays, or interpret kube-linter findings — including RBAC findings for operators and RHAI module operators that deploy other operators. Not for fixing or rewriting manifests, deploying to clusters, Go source linting, or general security audits.
---

# RHAI kube-linter onboarding and failure analysis

Assess a repository's Helm or Kustomize manifests, recommend the
kube-linter check combination that fits them, analyze failures with
evidence, and — only after explicit approval — onboard the repository
with a config and one shared lint entry point used identically locally
and in CI. This skill never implements a linter, renderer, or RBAC
analyzer; it runs kube-linter and reasons about its output.

## Hard limits

- **Assessment and proposals only until approved.** Never write consumer files
  without explicit approval of the exact proposed file set/diff; grown scope
  needs renewed approval. Sole exception, disclosed and never authored: the
  Kustomize chart-pull renderer cache (see the Kustomize recipe) — state it
  before rendering such a root, record it in the report's provenance, and
  never author, edit, or clean it up.
- **Never fix, rewrite, or annotate manifests** — not even to silence a
  finding; `ignore-check.kube-linter.io/<check>` annotation exceptions are
  proposals for the team to apply, never edits you make.
- **Never weaken checks to get green.** Every omission, exclusion, or
  exception needs manifest evidence and rationale; necessary operator
  permissions are evidence to explain, not grounds for blanket RBAC
  exemptions.
- **No cluster access, deployment, or runtime testing.** A finding is not
  proof of live behavior; a pass is not proof of runtime correctness.
- **No history investigation, chart regeneration, or application-source
  debugging** to explain a finding — evidence is the linted/rendered
  resources plus checked-in chart, overlay, and configuration.
- **No Secret values or credentials** in reports or examples.

If asked to do any of these, decline and record it as a proposed next step.

## Workflow

1. **Discover scope.** Lint targets (chart roots, Kustomize
   roots/overlays), rendering profiles, repository role, and existing
   lint entry points and configs. Read only checked-in files; never run
   mutating targets to discover scope. For RHAI modules and operands,
   the deploying operator's checked-in config is the authority for
   actual manifest locations (see
   [recipes/module-operator.md](recipes/module-operator.md)).
2. **Load recipes** per the routing table — only what the content justifies.
3. **Render and inspect** each profile per its format recipe.
4. **Propose checks and assess failures.** Build the check-selection
   matrix from the inspected renders and observed diagnostics — never
   from source YAML alone; classify findings from the final lint.
5. **Summarize the assessment** using the [assessment checklist](#assessment-checklist).
6. **Approval gate.** Present the proposed file set/diff; write nothing to the
   consumer repository until approved (the disclosed renderer-owned
   chart-cache write excepted under Hard limits).
7. **Onboard** the approved config, lint script, and
   Makefile/workflow using actual repository facts.
8. **Rerun** the canonical entry point CI will use; confirm the result matches
   the assessment.

## Recipe routing (lazy loading)

Load the applicable format recipe(s) first, then the single most-specific
repository recipe; load the entry-point recipe before proposing onboarding
files. Load both format recipes only when both formats are in scope. A
module operator does not automatically need the ordinary operator recipe.

**Mixed repositories:** when the lint targets include both a controller
and plain application workloads, load the operator (or module-operator)
recipe for the controller targets **and** the application recipe for the
application targets — operator-recipe noise exclusions are scoped to
controller manifests and must never suppress checks application
workloads require.

| Load | When the repository/target actually contains |
|---|---|
| [recipes/helm.md](recipes/helm.md) | A Helm chart (`Chart.yaml`) as a lint target |
| [recipes/kustomize.md](recipes/kustomize.md) | Kustomize roots, overlays, or bases as lint targets |
| [recipes/application.md](recipes/application.md) | Plain application workloads — also the non-controller targets of a mixed repository |
| [recipes/operator.md](recipes/operator.md) | A controller managing its own CRDs that does not install other operators |
| [recipes/module-operator.md](recipes/module-operator.md) | A module operator deploying other operators/operands (detected from manifest content, not repository names) |
| [recipes/entry-point.md](recipes/entry-point.md) | Always, before proposing onboarding files (workflow step 6) — the lint scripts, Makefile, and workflow contract |

**Uncertainty rule:** if unresolved role or profile facts would change which
recipes apply, the lint targets, or the proposed configuration, ask the
consumer before proceeding with that decision — do not guess by loading a
broader recipe set. Missing *external* evidence (e.g. operand RBAC in
another repository) is reported as unknown while independent, confirmed
scope is assessed.

## Canonical command contract

- Run kube-linter via pinned `go run`:
  `GOFLAGS= GOWORK=off go run golang.stackrox.io/kube-linter/cmd/kube-linter@v0.8.3 lint …`.
  Pin by **module version**, never an unpinned module or moving ref — the
  recorded command is the evidence of what ran, and the Go toolchain
  checksum-verifies module downloads. `GOFLAGS=`/`GOWORK=off` keep the
  invocation standalone. A missing Go toolchain or unreachable module
  proxy is a missing prerequisite, not a pass. (Container execution was
  deferred: the distroless image lacks CA certificates, breaking
  schema-validation.)
- **Record the module pin in every report.** A source-built binary
  self-reports version `development` — the pin is the evidence, not the
  version output.
- Keep raw renders/reports in fresh private scratch outside the consumer tree.
  See the [entry-point recipe](recipes/entry-point.md) for scratch cleanup
  and tool prerequisites. Only `schema-validation`
  downloads schemas.
- **Run invocations from bash files, never zsh one-liners.** zsh applies
  history modifiers inside double quotes (its `:r` once rewrote `$var:ro`
  to `…varo`), masquerading as tool bugs.
- Render Helm charts and Kustomize roots externally; never lint them directly.
  Pins, provenance, and caller-owned Helm are in the format recipes; onboarding
  is in [recipes/entry-point.md](recipes/entry-point.md).

## Check-selection policy

- Start from the attributed baseline in
  [templates/kube-linter.yaml](templates/kube-linter.yaml): the OpenDataHub
  operator configuration (revision recorded in the file), with
  `doNotAutoAddDefaults: true`, `addAllBuiltIn: false`, a categorized
  include-list, and the custom CEL checks `no-system-group-binding`,
  `sa-subject-namespace`, and `sa-subject-exists`.
- **The baseline is a candidate set to adapt, not a policy to copy.** Every
  enable, omission, preservation of an existing consumer check, or
  customization needs manifest evidence and rationale in the check-selection
  matrix. The baseline's comments are that project's policy intentions — not
  proof of immutable tags, complete secret protection, or CIS/RHAI compliance.
- **Record every adaptation inline in the proposed config.** A disabled,
  omitted, or customized check carries its rationale in the config itself:
  the manifest evidence, the trade-off (what signal is lost), and what
  still guards the concern. Include-list entries stay in place so the
  re-arm path is one deleted line. A config that silently drops checks is
  not a valid adaptation.
- Extra built-in checks are candidates when the manifests justify them; an
  all-built-ins dump is never recommended.
- Preserve existing consumer kube-linter configuration, custom checks, and
  annotations; explain proposed differences rather than replacing them.
- Exceptions: propose the narrowest workable scope — object-level
  annotation exceptions are described for the team to apply; a global
  exclusion needs explicit scope and rationale. Never exempt all operator
  RBAC or remove required permissions just to pass.

## Failure semantics

`KUBE_LINTER_FAIL_ON_FINDINGS` defaults to `true`; `false` downgrades only
selected-check findings. Invalid values and operational/mixed results fail.
See [recipes/entry-point.md](recipes/entry-point.md).

## Evidence discipline

- **Prove every check and renderer claim with a reproducer.** A
  fires/silent or coverage claim is established only by a minimal
  fixture — a positive control that must fire and negative controls
  that must stay silent — run through the pinned linter; never by
  source reading or documentation alone. In validation, static traces
  twice mispredicted firing (`no-rolling-update-strategy` fires on an
  absent strategy type; `dnsconfig-options` fires on every pod without
  dnsConfig), and a fixture corrected an overclaim in this skill's own
  template comments (`dangling-servicemonitor` validates selectors,
  not endpoint ports). Renderer-behavior claims get the same
  treatment: minimal repro, pinned render, compare output.
- `tests/custom-checks.sh` runs the fixture controls in `tests/fixtures/`
  for the custom CEL checks — the template by default, or any config
  adapted from it as an argument. Verify adaptations this way:
  hand-copied CEL expressions are where typos slip in (one adaptation
  compared a RoleBinding's namespace with itself and silenced the
  cross-namespace control).
- Evaluate structured results together with exit status and stderr. Count
  finding entries and use object metadata for attribution.
- A NetworkPolicy selects pods by pod-template labels — a Deployment's
  own metadata labels are insufficient evidence (controller/operand
  distinction guidance: the module-operator recipe).
- Do not infer live policy behavior solely from static diagnostics,
  empty-versus-explicit namespace serialization, or generated-looking
  paths (report the observation without investigating provenance).
- Missing or external operand RBAC, runtime-generated objects, aggregation,
  inherited permissions, admission behavior, and platform defaults are
  coverage gaps unless statically established — never claim kube-linter
  validates effective runtime RBAC containment.
- Per profile: never concatenate alternative overlays or charts into a fake
  deployment context to silence cross-resource checks.

## Assessment checklist

Summarize in the conversation and write a file only when requested.

- **Scope.** Role, profiles, rendering inputs and provenance, exact pinned commands.
- **Check selection.** Decisions and manifest evidence.
- **Findings.** Profile, check, resource, evidence, and classification
  (observed issue, expected requirement, rendering/tool limit, or unresolved).
- **Outcome.** Findings policy, stage exit statuses, and coverage gaps.
- **Proposals.** Narrow exceptions with rationale, onboarding diff, and canonical command.

## Maintenance

The script prints diagnostics and the workflow uploads SARIF. When changing
a pin, verify affected checks, flags, and rendering, then record the reason.
See the [entry-point recipe](recipes/entry-point.md).
