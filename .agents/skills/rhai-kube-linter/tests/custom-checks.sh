#!/usr/bin/env bash
# Fixture controls for the custom CEL checks: a positive control that must
# fire and negative controls that must stay silent, run through the pinned
# kube-linter.
#
# Usage: tests/custom-checks.sh [config]
#
# Defaults to the skill's template. Pass a config adapted from it (for
# example a repository's .kube-linter.yaml) to verify the adaptation:
# hand-copying CEL expressions is where subtle typos slip in unnoticed —
# one adaptation compared a RoleBinding's namespace with itself, which
# silenced the cross-namespace control.
#
# Requires go; downloads the pinned kube-linter on first use.
set -euo pipefail

skill="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config="${1:-$skill/templates/kube-linter.yaml}"
version="v0.8.3"

[ -f "$config" ] || { printf 'config not found: %s\n' "$config" >&2; exit 2; }

out='' status=0
run() { # fixture: lint it; combined output in $out, exit status in $status
  out="$(env GOFLAGS= GOWORK=off go run "golang.stackrox.io/kube-linter/cmd/kube-linter@$version" lint \
    --config "$config" --format plain "$1" 2>&1)" && status=0 || status=$?
}

failures=0
assert() { # label expected-count fixture
  local label="$1" expected="$2" fixture="$3" count
  run "$fixture"
  count="$(grep -c 'check: sa-subject-exists' <<<"$out" || true)"
  if [ "$status" -gt 1 ]; then
    printf 'FAIL %s: kube-linter exited %s (operational failure)\n' "$label" "$status" >&2
    failures=$((failures + 1))
  elif [ "$count" -eq "$expected" ]; then
    printf 'PASS %s: %s finding(s)\n' "$label" "$count"
  else
    printf 'FAIL %s: %s finding(s), expected %s\n' "$label" "$count" "$expected" >&2
    failures=$((failures + 1))
  fi
}

assert 'cross-namespace subject fires' 1 "$skill/tests/fixtures/sa-subject-exists-positive.yaml"
assert 'same-namespace and explicit-namespace subjects stay silent' 0 "$skill/tests/fixtures/sa-subject-exists-negative.yaml"

exit "$failures"
