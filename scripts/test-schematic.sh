#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
if (( $# > 1 )); then
  printf '%s\n' 'Usage: bash scripts/test-schematic.sh [preview-output-directory]' >&2
  exit 1
fi
if ! command -v quickshell >/dev/null 2>&1; then
  printf '%s\n' 'Quickshell is required for the schematic smoke test.' >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-schematic.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
output_dir=${1:-$test_root/renders}
mkdir -p -- "$output_dir"
output_dir=$(realpath -- "$output_dir")
cp -- "$repo_root/tests/qml/SchematicSmoke.qml" "$test_root/shell.qml"
cp -a -- "$repo_root" "$test_root/Plugin"
ln -s -- /usr/share/omarchy/shell/Commons "$test_root/Commons"
ln -s -- /usr/share/omarchy/shell/Ui "$test_root/Ui"

set +e
output=$(SCHEMATIC_TEST_OUTPUT="$output_dir" timeout 15s quickshell --no-color --path "$test_root/shell.qml" 2>&1)
status=$?
set -e
if (( status != 0 )) || [[ $output != *'SCHEMATIC_SMOKE_OK'* || $output == *'.qml:'* || $output == *'TypeError'* ]]; then
  printf '%s\n' "$output" >&2
  exit 1
fi

printf '%s\n' 'Schematic input, palette, resize, and lifecycle checks passed.'
