#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
  printf '%s\n' "Quickshell is required for the panel smoke test." >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-panel.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

cp -- "$repo_root/tests/qml/PanelLifecycleSmoke.qml" "$test_root/shell.qml"
cp -a -- "$repo_root" "$test_root/Plugin"
ln -s -- "/usr/share/omarchy/shell/Commons" "$test_root/Commons"
ln -s -- "/usr/share/omarchy/shell/Ui" "$test_root/Ui"

set +e
output=$(timeout 10s quickshell --no-color --path "$test_root/shell.qml" 2>&1)
status=$?
set -e

if (( status != 0 )) || [[ $output != *"PANEL_LIFECYCLE_SMOKE_OK"* ]]; then
  printf '%s\n' "$output" >&2
  exit 1
fi

printf '%s\n' "Panel lifecycle smoke test passed."
