#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
omarchy_shell=${OMARCHY_SHELL_PATH:-/usr/share/omarchy/shell}

if [[ -x /usr/lib/qt6/bin/qmllint ]]; then
  qmllint=/usr/lib/qt6/bin/qmllint
elif command -v qmllint >/dev/null 2>&1; then
  qmllint=$(command -v qmllint)
else
  printf '%s\n' "Qt 6 qmllint is required (Arch: qt6-declarative; Ubuntu: qt6-declarative-dev-tools)." >&2
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
# and unavailable CI-only Quickshell modules are excluded; all other warnings
# fail the check.
cd -- "$(dirname -- "$repo_root")"
qmllint_help=$("$qmllint" --help)
lint_args=(--ignore-settings --import disable -I "$import_root")

if [[ $qmllint_help == *"--max-warnings"* ]]; then
  lint_args+=(-W 0)
fi

if [[ $qmllint_help == *"--missing-property"* ]]; then
  lint_args+=(--missing-property disable --missing-type disable --unresolved-type disable)
else
  lint_args+=(--property disable --type disable)
fi

"$qmllint" "${lint_args[@]}" "${qml_files[@]}"
