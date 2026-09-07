#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
  printf '%s\n' "Quickshell is required for the service smoke test." >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-service.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

run_case() {
  local name=$1
  local harness=$2
  local helper=$3
  local marker=$4
  local case_root="$test_root/$name"
  local output
  local status

  mkdir -p -- "$case_root"
  cp -- "$repo_root/tests/qml/$harness" "$case_root/shell.qml"
  cp -a -- "$repo_root" "$case_root/Plugin"
  cp -- "$repo_root/tests/helpers/$helper" "$case_root/Plugin/scripts/gamepad-helper.py"
  ln -s -- "/usr/share/omarchy/shell" "$case_root/qs"

  set +e
  output=$(PLUGIN_ROOT="$case_root/Plugin" timeout 10s quickshell --no-color --path "$case_root/shell.qml" 2>&1)
  status=$?
  set -e

  if (( status != 0 )) || [[ "$output" != *"$marker"* ]]; then
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

run_case replay ServiceSmoke.qml replay-service-helper.py SERVICE_SMOKE_OK
run_case exit ServiceExitSmoke.qml exiting-service-helper.py SERVICE_EXIT_SMOKE_OK
run_case oversized ServiceFailureSmoke.qml oversized-service-helper.py SERVICE_FAILURE_SMOKE_OK
run_case timeout ServiceTimeoutSmoke.qml hanging-service-helper.py SERVICE_TIMEOUT_SMOKE_OK
run_case dependency ServiceDependencySmoke.qml dependency-recovery-service-helper.py SERVICE_DEPENDENCY_SMOKE_OK
run_case limit ServiceLimitSmoke.qml replay-service-helper.py SERVICE_LIMIT_SMOKE_OK
run_case startup-error ServiceStartupErrorSmoke.qml startup-error-service-helper.py SERVICE_STARTUP_ERROR_SMOKE_OK
run_case runtime-exit ServiceRuntimeExitSmoke.qml runtime-warning-exit-service-helper.py SERVICE_RUNTIME_EXIT_SMOKE_OK
run_case streaming ServiceStreamingSmoke.qml streaming-service-helper.py SERVICE_STREAMING_SMOKE_OK
run_case diagnostics ServiceDiagnosticsSmoke.qml replay-service-helper.py SERVICE_DIAGNOSTICS_SMOKE_OK

printf '%s\n' "Service replay and supervision smoke tests passed."
