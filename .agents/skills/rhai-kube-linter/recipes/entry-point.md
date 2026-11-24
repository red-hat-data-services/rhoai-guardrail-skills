# Onboarding entry-point recipe

**Load this recipe when** proposing onboarding files (SKILL.md workflow
step 6): the shared lint entry point, its scripts, and the Makefile /
workflow integration. It applies to every repository regardless of format
or repository role, alongside the format and repository recipes.

## Lint scripts

- **Two renderer scripts, scaffolded per repository need:**
  `scripts/lint-helm.sh` (Helm charts) and `scripts/lint-kustomize.sh`
  (Kustomize roots). Scaffold only the ones the repository uses — a
  Helm-only repository gets only `lint-helm.sh`. Plain-YAML targets
  without a renderer are not scaffolded.
- **Each lint script owns the pin, config path, lint targets, rendering
  details, and lint flags for its renderer; workflows must not duplicate
  them.**
- **Lint scripts are Bash 3.2 compatible** — indexed arrays and functions,
  no associative arrays or namerefs; validate specialization with an
  actual Bash 3.2 interpreter, not only the default `bash` on PATH.
- Reuse an existing equivalent entry point unchanged when it meets the
  canonical command contract (SKILL.md), documenting its exact command.
  If an existing script does not conform, propose adaptations for
  approval — never silently replace it or add a duplicate wrapper.

## Failure semantics

Local and CI runs share success/nonzero semantics; the scripts must fail
on selected-check violations, rendering failures, invalid or unparseable
resources, empty targets, zero enabled checks, malformed or missing
reports, and tool invocation failures.

**Success traps** (verified against the pinned releases):

- A config with **zero enabled checks can exit successfully before
  rendering anything** — treat "no checks enabled" as a failure.
- Empty input can pass silently without `--fail-if-no-objects-found`.
- v0.8.3 invalid-resource handling uses the deprecated
  `--fail-on-invalid-resource` flag; verify flags against the pinned
  release, not default-branch docs.
- When aggregating profiles, run every independent profile even if an
  earlier one fails; keep later diagnostics and combine failures. An
  early abort that drops later evidence is a defect.
- Reset and check stale render/report artifacts before each profile; a
  failed or partial render is never linted.
- Helm render-failure semantics (normal-mode `required`/`fail` aborts,
  unselected install/upgrade branches) and Kustomize render-failure
  semantics live in the format recipes.

## Makefile and CI integration

- **Makefile present:** local instructions and GitHub Actions both call
  its lint target (default `lint-manifests`), whose recipe lists only the
  lint scripts the repository needs, each invoked through `bash` (the
  scaffolded scripts are committed non-executable). Statuses aggregate
  across scripts — every listed script runs even if an earlier one fails,
  and the target fails if any script failed — matching the profile
  aggregation rule above. The workflow must never bypass it with a direct
  script call or a direct `go run` invocation. An absent Go toolchain is
  a missing prerequisite, not permission to bypass.
- **No Makefile:** local users and Actions invoke the same
  repository-local lint scripts through `bash`, keeping only the lines
  the repository needs and aggregating statuses the same way. Do not
  create a Makefile just for this skill.

## Maintenance

Re-verify check names, flags, and rendering behavior against the pinned
releases (kube-linter, Helm, Kustomize) when changing any pin in a lint
script, and record pin changes with rationale.

## Templates

Onboarding templates — specialize from actual repository facts before use:
[../templates/lint-helm.sh.tmpl](../templates/lint-helm.sh.tmpl),
[../templates/lint-kustomize.sh.tmpl](../templates/lint-kustomize.sh.tmpl),
[../templates/Makefile.tmpl](../templates/Makefile.tmpl),
[../templates/github-actions-make.yml.tmpl](../templates/github-actions-make.yml.tmpl),
[../templates/github-actions-script.yml.tmpl](../templates/github-actions-script.yml.tmpl).
