# Known dependency integrations

Bounded, evidence-backed lookup for APIs a consumer uses **indirectly**
through a framework dependency, replacing generic dependency traversal.
Each entry records an integration that hides OpenShift or monitoring API
traffic behind a setup call, so discovery can attribute it without
recursively scanning the module graph.

## How to use this table

1. Match the consumer's **actual wiring** — the setup call site and its
   arguments/guards — not just an import or a `go.mod` entry.
2. Verify the entry at the consumer's **resolved version** (honor
   `replace`, vendor, and workspace selection). The versions recorded
   here are what was inspected; they are evidence, never defaults.
   **Staleness gate:** a resolved version matching a recorded Verified
   version reuses the entry; a patch-level difference (same
   major.minor) reuses it with the resolved version recorded in the
   generation record; any other difference is re-verified at the
   resolved version (recording the new evidence here) or surfaced as a
   question — never silently extrapolated.
3. Follow only the relationships an entry explicitly records (including
   recorded aliases). An integration that does not match an entry is an
   open question for the user — never a reason to recurse into unknown
   packages or to silently skip the finding.
4. If the resolved source cannot be inspected or does not match the
   recorded behavior, report a gap and ask; do not assume compatibility.

## Entries

| Module / package | Integration and call-site match | Affected API (CRD) | Activation / fallback behavior | Verified version(s) | Source evidence |
| --- | --- | --- | --- | --- | --- |
| `github.com/opendatahub-io/odh-platform-utilities/framework`, package `tls` | Consumer registers `SecurityProfileWatcher` via `SetupWithManager`, fed by `Load`/`LoadWithAdherence`/`LoadResult` or a consumer-side loader of the same shape | `config.openshift.io/v1` `APIServer` (`apiservers.config.openshift.io`) | Profile-only helpers (`ProfileSpecFromSecurityProfile`, `ConfigFromProfile`, `strictTLSProfileSpec`, …) make **no** API calls. Loaders GET `APIServer` named `cluster`: API absent (`NoMatchError`) → Intermediate fallback, **not watchable** (watcher not registered); object missing (`NotFound`) → Intermediate fallback, **watchable**; other errors can propagate to startup failure. When registered, the watcher `For`s `APIServer` and fails without the CRD — hard for the watcher itself | framework `v0.4.0` (last verified 2026-11); alias target `github.com/openshift/controller-runtime-common` `v0.0.0-20261026124434-bdfc411d93cd` (last verified 2026-11) | framework `tls/watcher.go`, `tls/apiserver.go`; controller-runtime-common `pkg/tls/controller.go` (`SetupWithManager`, `For(&configv1.APIServer{})`, name predicate `cluster`) |

### Recorded alias

Framework `tls.SecurityProfileWatcher` is a **type alias** for
`github.com/openshift/controller-runtime-common/pkg/tls.SecurityProfileWatcher`;
the watch implementation lives in controller-runtime-common. This
relationship is part of the entry above. It is not a license to recurse
into other packages of either module.

## Limitations

- Installing the `APIServer` CRD does not create the `cluster` object,
  does not select Strict TLS adherence, and does not change platform or
  feature gates. API-surface fidelity can expose relevant consumer code
  paths (and their failures) — it does not guarantee OpenShift behavior.
- Entries age: dependency updates can change symbols or fallback
  behavior. The staleness gate above turns aging into an explicit
  re-verification or a question, never a silent reuse; a mismatch is a
  reported gap, not a best-effort guess.
- New entries require recorded evidence (module, version, files/symbols
  inspected) — never a speculative row.

## Maintenance

When a consumer's resolved version differs from the recorded one,
re-verify the cited symbols/behavior at that version and record the new
evidence here. Do not widen the table to cover unverified integrations.
