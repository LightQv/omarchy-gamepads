#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_shell=${OMARCHY_SHELL_PATH:-/usr/share/omarchy/shell}

if command -v pyside6-qmllint >/dev/null 2>&1; then
  qmllint=$(command -v pyside6-qmllint)
elif [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  qmllint=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
  qmllint=$(command -v qmllint)
else
  printf '%s\n' "Qt 6 qmllint is required (Arch: qt6-declarative; other systems: PySide6-Essentials)." >&2
  exit 1
fi

if [[ ! -d "$omarchy_shell/Ui" || ! -d "$omarchy_shell/Commons" ]]; then
  printf 'Omarchy shell QML modules not found at %s\n' "$omarchy_shell" >&2
  exit 1
fi

import_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-qml.XXXXXX")
trap 'rm -rf -- "$import_root"' EXIT
ln -s "$omarchy_shell" "$import_root/qs"

shopt -s globstar nullglob
qml_files=("$repo_root"/**/*.qml)
if (( ${#qml_files[@]} == 0 )); then
  printf '%s\n' "No QML files found." >&2
  exit 1
fi

# Running outside the plugin directory prevents entry-point filenames from
# shadowing shared qs.Ui component names. Dynamic Quickshell host properties
# and unqualified access through unavailable CI-only Quickshell host metadata
# are excluded; all other warnings fail the check.
cd -- "$(dirname -- "$repo_root")"
"$qmllint" \
  --ignore-settings \
  -W 0 \
  --import disable \
  --missing-property disable \
  --missing-type disable \
  --unresolved-type disable \
  --unqualified disable \
  -I "$import_root" \
  "${qml_files[@]}"

# The profile scene has no Quickshell types, so its imports and Quick 3D types
# can be checked without the host-metadata exclusions required above.
"$qmllint" \
  --ignore-settings \
  -W 0 \
  "$repo_root/profiles/switch-pro/SwitchProScene.qml"
