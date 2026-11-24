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
3. **Render and inspect.** Render every selected profile with the pinned
   external renderer into one scratch multi-document file per profile;
   inspect the rendered resources before adapting checks.
4. **Propose checks and assess failures.** Build the check-selection
   matrix from the inspected renders and observed diagnostics — never
   from source YAML alone; classify findings from the final lint.
5. **Report** from [templates/report.md](templates/report.md).
6. **Approval gate.** Present the proposed file set/diff; write nothing to the
   consumer repository until approved (the disclosed renderer-owned
   chart-cache write excepted under Hard limits).
7. **Onboard.** Apply the approved config, script, Makefile amendment, and
   workflow, specialized from actual repository facts.
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
- **The linter runs on the host.** Read-only-ness is procedural: write
  reports only to the designated report directory, never to consumer paths.
  Only the `schema-validation` check (when enabled) downloads schemas at
  runtime.
- **Run invocations from bash files, never zsh one-liners.** zsh applies
  history modifiers inside double quotes (its `:r` once rewrote `$var:ro`
  to `…varo`), masquerading as tool bugs.
- **External rendering is required for every Helm chart and Kustomize
  root** — never pass a chart directory or root directly to kube-linter.
  Each profile renders into one scratch multi-document file, linted only
  after the render succeeds. Pinned render commands, remote-input
  fetching, provenance digests, and chart-inflation Helm provisioning
  live in the format recipes; the scaffolded entry point (scripts,
  Makefile, workflow, templates) in
  [recipes/entry-point.md](recipes/entry-point.md).

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

Local and CI runs share success/nonzero semantics: the must-fail list,
success traps, and flags live in
[recipes/entry-point.md](recipes/entry-point.md) and the format recipes.

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
- Evaluate JSON reports together with exit status and stderr (report
  fields and classification vocabulary:
  [templates/report.md](templates/report.md)).
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

## Report

Produce the report from [templates/report.md](templates/report.md), which
defines the required sections, finding classifications, and evidence
handling.

## Output and maintenance

**Evaluation records are opt-in.** Deliver assessment results in the
conversation, structured per the report template — never write
evaluation records to the filesystem unless the user explicitly asks,
and then where they direct.

**Raw evidence is private scratch** — confidentiality rules in
[templates/report.md](templates/report.md).

Re-verify check names, flags, and rendering behavior against the pinned
releases when changing any pin, and record the change with rationale
(pins live in the lint scripts —
[recipes/entry-point.md](recipes/entry-point.md)).
