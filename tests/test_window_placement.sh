#!/usr/bin/env bash

set -euo pipefail

repo_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-gamepads-window.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT
mock_log="$test_root/hyprctl.log"

if /bin/bash "$repo_root/scripts/prepare-details-window" 'invalid token' >/dev/null 2>&1; then
  printf '%s\n' "prepare-details-window accepted an invalid token" >&2
  exit 1
fi
if /bin/bash "$repo_root/scripts/place-details-window" 'invalid token' >/dev/null 2>&1; then
  printf '%s\n' "place-details-window accepted an invalid token" >&2
  exit 1
fi
if /bin/bash "$repo_root/scripts/clear-details-window-rule" 'invalid token' >/dev/null 2>&1; then
  printf '%s\n' "clear-details-window-rule accepted an invalid token" >&2
  exit 1
fi

(
  source "$repo_root/scripts/prepare-details-window"
  hyprctl_call() {
    printf 'eval:%s\n' "${2:-}" >>"$mock_log"
  }
  prepare_details_window "first-attempt"
)

(
  source "$repo_root/scripts/place-details-window"
  hyprctl_call() {
    case ${1:-} in
      eval)
        printf 'eval:%s\n' "${2:-}" >>"$mock_log"
        ;;
      activeworkspace)
        printf '%s\n' '{"id":-99,"name":"special:gamepads"}'
        ;;
      clients)
        printf '[{"address":"0xabc123","pid":%s,"class":"org.quickshell","title":"Gamepad Details","floating":false,"workspace":{"id":2,"name":"2"}},' "$PPID"
        printf '%s\n' '{"address":"0xdead","pid":999,"class":"org.quickshell","title":"Gamepad Details","floating":false,"workspace":{"id":2,"name":"2"}}]'
        ;;
      dispatch)
        printf 'dispatch:%s\n' "${2:-}" >>"$mock_log"
        ;;
      *)
        return 1
        ;;
    esac
  }
  place_details_window "first-attempt"
)

(
  source "$repo_root/scripts/clear-details-window-rule"
  hyprctl_call() {
    printf 'eval:%s\n' "${2:-}" >>"$mock_log"
  }
  clear_details_window_rules "cancelled-attempt" "stale-instance"
)

log=$(<"$mock_log")
for expected in \
  'title = "^Gamepad Details$"' \
  'name = "lightqv-gamepad-details-' \
  '-first-attempt"' \
  'pid = "^' \
  'float = true' \
  'workspace = "special:gamepads"' \
  'window = "address:0xabc123"' \
  'hl.dsp.window.float' \
  'hl.dsp.window.resize' \
  'hl.dsp.window.center' \
  'hl.dsp.focus' \
  'enabled = false' \
  'name = "lightqv-gamepad-details-cancelled-attempt"' \
  'name = "lightqv-gamepad-details-stale-instance"'; do
  if [[ $log != *"$expected"* ]]; then
    printf 'Missing placement action: %s\n' "$expected" >&2
    exit 1
  fi
done

if [[ $log == *"0xdead"* ]]; then
  printf '%s\n' "Placement targeted a same-title window from another process" >&2
  exit 1
fi

printf '%s\n' "Details window placement tests passed."
