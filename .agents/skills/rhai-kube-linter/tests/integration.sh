#!/usr/bin/env bash
# Exercise both workflow entry points and the standalone lint script with Go doubles.
set -uo pipefail

skill="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
root="$(mktemp -d "${TMPDIR:-/tmp}/kube-linter-tests.XXXXXX")" || exit 1
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/bin"
passes=0
failures=0

check() {
  local label="$1"
  shift
  if "$@"; then
    passes=$((passes + 1))
    printf 'PASS %s\n' "$label"
  else
    failures=$((failures + 1))
    printf 'FAIL %s\n' "$label"
  fi
}

cat > "$root/bin/go" <<'GO'
#!/usr/bin/env bash
set -uo pipefail
[ . -ef "$TEST_CONSUMER" ] && [ -z "$GOFLAGS" ] && [ "$GOWORK" = off ] || exit 97
case "$2" in
  helm.sh/helm/v4/cmd/helm@v4.3.2|sigs.k8s.io/kustomize/kustomize/v5@v5.8.1)
    renderer="$2"
    if [[ "$renderer" = helm.sh/* ]]; then
      [ "$*" = 'run helm.sh/helm/v4/cmd/helm@v4.3.2 template demo charts/demo --namespace test --include-crds -f values production.yaml' ] &&
        [ "$#" -eq 10 ] || exit 98
    else
      [ "$*" = 'run sigs.k8s.io/kustomize/kustomize/v5@v5.8.1 build --enable-helm overlays/prod' ] || exit 98
    fi
    printf 'render\n' >> "$TEST_CALLS"
    case "$TEST_SCENARIO" in
      render-error) printf 'renderer diagnostic\n' >&2; exit 2 ;;
      empty-render) printf '---\n# empty\n'; exit 0 ;;
    esac
    if [ "$TEST_SCENARIO" = later-profile ] && [[ "$renderer" = helm.sh/* ]]; then exit 2; fi
    printf 'apiVersion: v1\nkind: Pod\nmetadata:\n  name: test\n'
    ;;
  golang.stackrox.io/kube-linter/cmd/kube-linter@v0.8.3)
    printf 'lint\n' >> "$TEST_CALLS"
    shift 2
    text='' sarif=''
    while [ "$#" -gt 0 ]; do
      if [ "$1" = --format ] && [ "$3" = --output ]; then
        case "$2" in plain) text="$4" ;; sarif) sarif="$4" ;; *) exit 99 ;; esac
        shift 4
      else
        rendered="$1"
        shift
      fi
    done
    [ -n "$text" ] && [ -n "$sarif" ] || exit 99
    case "$TEST_SCENARIO" in
      missing) exit 0 ;;
      malformed) printf 'KubeLinter\n' > "$text"; printf 'invalid SARIF\n' > "$sarif"; exit 0 ;;
      zero-checks)
        printf 'KubeLinter\n' > "$text"
        printf '{"version":"2.1.0","runs":[{"tool":{"driver":{"rules":[]}},"invocations":[{"executionSuccessful":true}],"results":[]}]}\n' > "$sarif"
        exit 0
        ;;
      clean|later-profile)
        printf 'KubeLinter\nNo lint errors found\n' > "$text"
        printf '{"version":"2.1.0","runs":[{"tool":{"driver":{"name":"kube-linter","rules":[{"id":"latest-tag"}]}},"invocations":[{"executionSuccessful":true}],"results":[]}]}\n' > "$sarif"
        exit 0
        ;;
    esac
    check=latest-tag
    message='native diagnostic: image is mutable'
    status=1
    case "$TEST_SCENARIO" in
      cel-error) message='error evaluating CEL check expression: unavailable';;
      schema-error) message='error while processing resource: schema unavailable';;
      invalid-load) check=failed-to-load-object ;;
      wrong-exit) status=2 ;;
      wrong-stderr) printf 'unexpected tool failure\n' >&2 ;;
      contradiction) status=0 ;;
      log-format) message=$'first\n::error::embedded ##[error] syntax' ;;
    esac
    if [ "$TEST_SCENARIO" != missing-text ]; then printf '%s\n' "$message" > "$text"; fi
    jq -n --arg check "$check" --arg message "$message" --arg rendered "$rendered" '{
      version:"2.1.0",
      runs:[{tool:{driver:{name:"kube-linter",rules:[{id:"latest-tag"}]}},
             invocations:[{executionSuccessful:false}],
             results:[{ruleId:$check,message:{text:$message},locations:[{physicalLocation:
               {artifactLocation:{uri:$rendered},region:{startLine:1}},
               logicalLocations:[{name:"test",kind:"Object Name"},{name:"",kind:"Object Namespace"},
                 {name:"",kind:"GVK/Group"},{name:"v1",kind:"GVK/Version"},{name:"Pod",kind:"GVK/Kind"}]}]}]}]
    }' > "$sarif"
    if [ "$TEST_SCENARIO" = finding ]; then printf 'Error: found 1 lint errors\nexit status 1\n' >&2; fi
    exit "$status"
    ;;
  *) exit 99 ;;
esac
GO
chmod +x "$root/bin/go"

specialize_script() {
  local consumer="$1" renderers="$2" renderer
  mkdir -p "$consumer/scripts"
  printf 'checks: {}\n' > "$consumer/.kube-linter.yaml"
  # The profile entries must be committed files: SARIF findings are
  # attributed to them by the combine step.
  mkdir -p "$consumer/charts/demo" "$consumer/overlays/prod"
  printf '# chart\n' > "$consumer/charts/demo/Chart.yaml"
  printf '# overlay\n' > "$consumer/overlays/prod/kustomization.yaml"
  awk '
    /__PLACEHOLDER_RENDER_PROFILES__/ { exit }
    { print }
  ' "$skill/templates/lint-manifests.sh.tmpl" | sed \
    -e 's|__PLACEHOLDER_CONFIG_PATH__|.kube-linter.yaml|g' \
    -e 's|__PLACEHOLDER_KUBE_LINTER_PIN__|v0.8.3|g' > "$consumer/scripts/lint-manifests.sh"
  for renderer in $renderers; do
    case "$renderer" in
      helm) printf '%s\n' 'lint_profile chart charts/demo/Chart.yaml helm.sh/helm/v4/cmd/helm@v4.3.2 template demo charts/demo --namespace test --include-crds -f "values production.yaml"' ;;
      kustomize) printf '%s\n' 'lint_profile overlay overlays/prod/kustomization.yaml sigs.k8s.io/kustomize/kustomize/v5@v5.8.1 build --enable-helm overlays/prod' ;;
    esac >> "$consumer/scripts/lint-manifests.sh"
  done
  sed -n '/__PLACEHOLDER_RENDER_PROFILES__/,$ { /__PLACEHOLDER_RENDER_PROFILES__/d; p; }' \
    "$skill/templates/lint-manifests.sh.tmpl" >> "$consumer/scripts/lint-manifests.sh"
}

check_workflow() {
  local variant="$1" command="$2" workflow="$root/$1.yml"
  sed -e 's|__PLACEHOLDER_DEFAULT_BRANCH__|main|g' \
    -e 's|__PLACEHOLDER_GO_VERSION__|1.27.3|g' \
    -e "s|__PLACEHOLDER_LINT_COMMAND__|$command|g" \
    "$skill/templates/github-actions.yml.tmpl" > "$workflow"
  GOFLAGS='' GOWORK=off go run github.com/mikefarah/yq/v4@v4.54.3 eval -o=json '.' "$workflow" > "$workflow.json" || return 1
  jq -e --arg command "$command" --arg dir '${{ runner.temp }}/kube-linter' '
    .permissions == {"contents":"read","security-events":"write"}
    and (.on | has("pull_request") and has("workflow_dispatch") and .push.branches == ["main"])
    and (.jobs."kube-linter" |
      .env == {"KUBE_LINTER_FAIL_ON_FINDINGS":"true"}
      and (.steps | length == 4
        and .[0].uses == "actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1"
        and .[0].with."persist-credentials" == false
        and .[1].uses == "actions/setup-go@d8cbb8045d7f43706b9177cceb36c1f91a6644d5"
        and .[1].with."go-version" == "1.27.3"
        and .[2] == {"name":"Lint manifests","id":"lint","run":$command,
                     "env":{"KUBE_LINTER_SARIF_DIR":$dir}}
        and .[3].uses == "github/codeql-action/upload-sarif@915412ff23e8b7659517e607487dbeae018f2934"
        and .[3].if == "${{ !cancelled() && steps.lint.outputs.sarif-ready == \u0027true\u0027 }}"
        and .[3].with.sarif_file == ($dir + "/report.sarif")))
  ' "$workflow.json" >/dev/null || return 1
  jq -er '.jobs."kube-linter".steps[2].run' "$workflow.json" > "$root/$variant.sh"
}

run_case() {
  local variant="$1" renderers="$2" scenario="$3" mode="$4" expected="$5"
  local dir="$root/$variant-$renderers-$scenario-$mode"
  local consumer="$dir/consumer" status lint_calls profile_count=0 renderer log="$dir/log"
  mkdir -p "$dir/scratch"
  specialize_script "$consumer" "$renderers"
  if [ "$variant" = make ]; then cp "$skill/templates/Makefile.tmpl" "$consumer/Makefile"; fi
  printf 'prior step summary\n' > "$dir/summary"
  : > "$dir/calls"
  : > "$dir/outputs"
  (
    export PATH="$root/bin:$PATH" TMPDIR="$dir/scratch" GITHUB_ACTIONS=true GITHUB_STEP_SUMMARY="$dir/summary"
    export TEST_CONSUMER="$consumer" TEST_SCENARIO="$scenario" TEST_CALLS="$dir/calls"
    if [ "$mode" = unset ]; then unset KUBE_LINTER_FAIL_ON_FINDINGS
    else export KUBE_LINTER_FAIL_ON_FINDINGS="$mode"
    fi
    if [ "$variant" = direct ]; then
      unset KUBE_LINTER_SARIF_DIR GITHUB_OUTPUT
      /bin/bash "$consumer/scripts/lint-manifests.sh"
    else
      export KUBE_LINTER_SARIF_DIR="$dir/sarif" GITHUB_OUTPUT="$dir/outputs"
      cd "$consumer" || exit 99
      /bin/bash -e -o pipefail "$root/$variant.sh"
    fi
  ) > "$log" 2>&1
  status=$?
  if [ "$expected" = 0 ]; then [ "$status" -eq 0 ] || { cat "$log"; return 1; }
  else [ "$status" -ne 0 ] && [ "$status" -lt 3 ] || { cat "$log"; return 1; }
  fi
  [ "$(cat "$dir/summary")" = 'prior step summary' ] && [ -z "$(ls -A "$dir/scratch")" ] || return 1
  [ ! -e "$dir/sarif/work" ] || return 1
  if grep -Eq '^[[:space:]]*::|##\[' "$log"; then return 1; fi
  for renderer in $renderers; do profile_count=$((profile_count + 1)); done
  lint_calls="$profile_count"
  case "$scenario" in
    render-error|empty-render) lint_calls=0 ;;
    later-profile) lint_calls=$((profile_count - 1)) ;;
  esac
  if [ "$mode" = invalid ] || [ -z "$mode" ]; then
    [ ! -s "$dir/calls" ] && grep -qF 'must be' "$log"
    return
  fi
  [ "$(grep -cx render "$dir/calls")" -eq "$profile_count" ] &&
    [ "$(grep -cx lint "$dir/calls")" -eq "$lint_calls" ] || return 1
  case "$variant:$scenario" in
    make:clean|make:finding|script:clean|script:finding)
      grep -qxF 'sarif-ready=true' "$dir/outputs" &&
        jq -e --argjson count "$profile_count" \
             --argjson entries '{"chart":"charts/demo/Chart.yaml","overlay":"overlays/prod/kustomization.yaml"}' '
          .version == "2.1.0" and (.runs | length == $count)
          and ([.runs[].automationDetails.id] | unique | length == $count)
          and all(.runs[];
                  (.automationDetails.id | rtrimstr("/") | split("/") | last) as $p
                  | all(.results[].locations[].physicalLocation;
                        .artifactLocation.uri == $entries[$p] and .region.startLine == 1))
          and all(.runs[].results[];
                  .partialFingerprints.primaryLocationLineHash == (.ruleId + ":Pod//test"))
        ' "$dir/sarif/report.sarif" >/dev/null || return 1
      ;;
    *) [ ! -s "$dir/outputs" ] && [ ! -e "$dir/sarif/report.sarif" ] || return 1 ;;
  esac
  case "$scenario:$mode" in
    clean:*) grep -qF 'clean (' "$log" ;;
    finding:false) grep -qF 'WARNING [' "$log" && grep -qF 'native diagnostic: image is mutable' "$log" ;;
    finding:*) grep -qF 'ERROR [' "$log" && grep -qF 'native diagnostic: image is mutable' "$log" ;;
    later-profile:*) grep -qF 'render failed' "$log" && grep -qF '[overlay] clean' "$log" ;;
    log-format:*) grep -qF 'kube-linter:   ::error::embedded # #[error] syntax' "$log" ;;
    *) grep -qF 'ERROR [' "$log" ;;
  esac
}

check 'make workflow' check_workflow make 'make lint-manifests'
check 'direct Bash workflow' check_workflow script 'bash ./scripts/lint-manifests.sh'
for variant in make script; do
  for renderers in helm kustomize 'helm kustomize'; do
    check "$variant [$renderers] clean" run_case "$variant" "$renderers" clean true 0
    check "$variant [$renderers] strict findings" run_case "$variant" "$renderers" finding true 1
    check "$variant [$renderers] advisory findings" run_case "$variant" "$renderers" finding false 0
    for mode in true false; do
      check "$variant [$renderers] operational error ($mode)" run_case "$variant" "$renderers" cel-error "$mode" 1
    done
  done
done
check 'default policy is strict' run_case direct helm finding unset 1
check 'invalid policy fails before rendering' run_case direct helm clean invalid 1
check 'empty policy fails before rendering' run_case direct helm clean '' 1
check 'later profile runs after render failure' run_case direct 'helm kustomize' later-profile false 1
check 'diagnostics remain plain text' run_case direct kustomize log-format false 0
for scenario in render-error empty-render invalid-load schema-error missing missing-text malformed zero-checks wrong-exit wrong-stderr contradiction; do
  check "$scenario fails in advisory mode" run_case direct kustomize "$scenario" false 1
done

printf '%s passed, %s failed\n' "$passes" "$failures"
[ "$failures" -eq 0 ]
