#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

if ! command -v quickshell >/dev/null 2>&1; then
  printf '%s\n' "Quickshell is required for the Quick 3D performance test." >&2
  exit 1
fi

test_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-quick3d.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

mkdir -p -- "$test_root/Plugin/profiles/switch-pro"
cp -- "$repo_root/tests/qml/Quick3DPerformanceSmoke.qml" "$test_root/shell.qml"
cp -- "$repo_root/VisualState.js" "$test_root/Plugin/VisualState.js"
cp -- "$repo_root/profiles/switch-pro/Profile.js" "$test_root/Plugin/profiles/switch-pro/Profile.js"
cp -- "$repo_root/profiles/switch-pro/SwitchProScene.qml" "$test_root/Plugin/profiles/switch-pro/SwitchProScene.qml"
output_file="$test_root/output.log"
: >"$output_file"
chmod 600 "$output_file"

set +e
timeout 75s quickshell --no-color --path "$test_root/shell.qml" 2>&1 \
  | /usr/bin/dd bs=1024 count=1025 status=none >"$output_file"
pipeline_status=("${PIPESTATUS[@]}")
status=${pipeline_status[0]}
set -e
output_size=$(stat -c %s "$output_file")
if (( status != 0 )); then
  printf 'Quick 3D performance process failed with status %s and %s output bytes.\n' "$status" "$output_size" >&2
  /usr/bin/tail -n 40 "$output_file" >&2
  exit 1
fi
if (( output_size >= 1048576 )); then
  printf '%s\n' "Quick 3D performance output exceeded 1 MiB." >&2
  /usr/bin/tail -n 40 "$output_file" >&2
  exit 1
fi
output=$(<"$output_file")

if (( status != 0 )) || [[ $output != *"QUICK3D_PERFORMANCE_OK"* ]]; then
  printf '%s\n' "$output" >&2
  exit 1
fi

printf '%s\n' "$output" | /usr/bin/grep 'QUICK3D_PERFORMANCE '
