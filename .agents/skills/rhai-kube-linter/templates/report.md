# kube-linter assessment report — <repository>

<!--
Template for the assessment/failure-analysis report produced by the
rhai-kube-linter skill. Fill every section; write "none" rather than deleting
a section. Keep raw JSON reports and renders in scratch space outside the
consumer repository, or in a git-ignored in-repository directory — the lint
scripts enforce this fail-closed (an in-repository report directory must be
git-ignored, verified with git check-ignore, or the run aborts). Reference
them by relative path only if the consumer wants them kept.

**Raw evidence is private scratch.** Rendered manifests, JSON/plain
machine reports, and renderer/linter stderr may contain Secret material:
keep them in gitignored scratch with restrictive permissions, never print
or upload them (including as CI artifacts), and share only sanitized
summaries. Human-facing reports carry findings, not raw documents.

Required classification vocabulary for Findings:
  - observed issue        : a real defect in the assessed manifests
  - expected requirement  : the check fired, but the behavior is legitimate
                            for this repository's role (explain why, with
                            manifest evidence)
  - rendering/tool limit  : artifact of how the linter rendered or evaluated
                            the input, not a statement about live behavior
  - unresolved            : evidence is insufficient to classify
-->

- **Date:** <YYYY-MM-DD>
- **Assessed by:** <agent/user>
- **kube-linter:** `golang.stackrox.io/kube-linter/cmd/kube-linter@v0.8.3` (record the module pin verbatim; a source-built binary self-reports `development` — the pin is the evidence, not the version output)
- **Renderers:** `helm.sh/helm/v4/cmd/helm@v4.3.2` and `sigs.k8s.io/kustomize/kustomize/v5@<pin-as-run>` (record verbatim; a compatible repository pin may replace the fallback `v5.8.1`); Kustomize chart inflation always uses the pinned provision `helm.sh/helm/v4/cmd/helm@<pin>` (the pin is the evidence; a go-installed binary self-reports an unstamped version)

## 1. Scope, profiles, and commands

- **Repository:** <path/URL>
- **Lint targets:** <exact chart roots / Kustomize roots, and which lint script covers each>
- **Rendering profiles assessed:** <e.g. chart X with documented install values (source: Makefile deploy target); overlay Y rendered with pinned Kustomize — one line each, kept separate, with values/flags provenance per profile>
- **Renderer/linter stage status:** <per profile: render outcome, then lint outcome — distinguish failed-render/no-lint from failed-with-findings; note any remote inputs the renderer fetched, each with its resolved revision or content digest, plus the rendered profile's digest>
- **Exact commands run:** <verbatim, with working directory — renderer and linter separately>
- **Exit status and stderr summary:** <per command, per stage>

## 2. Selected recipes

- Format: <recipes/helm.md and/or recipes/kustomize.md — why>
- Repository role: <recipes/application.md | recipes/operator.md | recipes/module-operator.md — why, citing manifest evidence>
- Role/profile facts that were uncertain and how they were resolved: <or "none">

## 3. Check-selection matrix

Starting point: the attributed baseline (`templates/kube-linter.yaml`,
OpenDataHub operator revision `4558b26044ce3ed76719e6fb3461357decb5a0b6`).
Existing consumer checks preserved: <list, or "none found">.

| Check / category | Decision | Manifest evidence | Rationale |
|---|---|---|---|
| <check> | enable / omit / preserve / customize | <what in the manifests bears on it> | <why this decision> |

Address every baseline check and any extra built-in candidates the manifests
justify. "It fails" is never a rationale for omission.

## 4. Findings

| # | Profile | Check | Kind / namespace / name | Source or rendered path | Evidence (concise) | Classification |
|---|---|---|---|---|---|---|
| 1 | <profile> | <check> | <kind/ns/name> | <path> | <one-line evidence> | observed issue / expected requirement / rendering/tool limit / unresolved |

Per finding, add a short note below the table when the one-line evidence is
not enough. Distinguish what the linter covers from what is only a
recommendation here. Map every finding back through source profile →
values/flags → rendered manifest → JSON/plain report so the team can
reproduce it verbatim. JSON reports: `Reports[]` with `.Check`,
`.Diagnostic.Message`, `.Object.Metadata.FilePath`, `.Object.K8sObject.*`;
`Summary` has no total-object count — never infer counts from nonexistent
fields. Evaluate reports together with exit status and stderr.

## 5. Proposed exceptions

All entries are PROPOSALS. Do not apply manifest annotations or config
exclusions; the team applies them after review.

| Object (kind/ns/name) or config scope | Check | Proposed mechanism | Justification |
|---|---|---|---|
| <object or scope> | <check> | <annotation `ignore-check.kube-linter.io/<check>` / config exclusion, with exact scope> | <why this narrow exception is justified> |

## 6. Uncertainties and coverage limits

- **Runtime limits:** static lint only — no cluster access, no deployment
  test, no admission, no network reachability, no proof of effective runtime
  RBAC or live NetworkPolicy behavior.
- **Rendering limits:** <e.g. dynamic install-time inputs unavailable
  (image refs, platform env) — run is partial, not exact as-installed;
  remote renderer inputs fetched but provenance recorded; install/upgrade or
  conditional branches not selected by the documented profile;
  defaults-only comparison not run; CRDs treated as …>
- **Unresolved evidence:** <e.g. operand RBAC lives in another repository;
  role aggregation not statically established>
- **Questions for the team:** <or "none">

## 7. Proposed onboarding files and canonical command

Nothing below is applied until explicitly approved.

- `<path>` — <new file / amendment, one-line summary>
- `<path>` — …
- Proposed diffs: <scratch location or inline>

Canonical local and CI command (identical in both):
- Makefile present: `make <lint-target>` — the GitHub Actions workflow calls
  this same target, never a direct script or container invocation.
- No Makefile: `<exact script invocation>` — local users and the workflow run
  the same script.

## 8. Run outcome

- **Result:** <pass / failed with N findings across M profiles>
- **Aggregate behavior:** <all profiles attempted; later diagnostics retained
  after early failures; exit status nonzero when any profile failed>
- **Report availability:** <JSON report paths in scratch>
- **Next steps (proposals only):** <or "none">
