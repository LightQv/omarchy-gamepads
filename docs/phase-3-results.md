# Phase 3 Results

**Phase:** Shared service and compact panel  
**Date:** 2026-09-07  
**Result:** Complete

## Delivered

- One shared QML service and helper process for all plugin entry points.
- Strict immutable protocol reducer with controller selection and formatting helpers.
- Bounded incremental NDJSON framing, traffic budgets, startup timeout, and restart backoff.
- Graceful helper shutdown, final-frame draining, and actionable dependency errors.
- Bar icon with connected count, backend warning state, and low-battery state.
- Bar-owned compact panel with controller vitals, multi-controller selection, retry, and Details actions.
- Keyboard navigation and panel coordination using current Omarchy controls.
- Minimal standalone Details window with bounded payload parsing and synchronized host lifecycle.
- Deterministic two-controller fixture, 14 reducer tests, and eight isolated Quickshell service smoke cases.

## Safety Bounds

- `Service.qml` is the sole owner of the helper process.
- Helper launch uses an argv list and a manifest-relative script path without a shell.
- Input frames, pending output, stderr, and per-interval traffic are bounded.
- Malformed handshakes, sequences, schemas, and controller/control values are rejected.
- Repeated helper failures use capped exponential backoff and dependency failures do not restart-loop.
- Production QML exposes no replay path or command override.
- Controller names render as plain text after backend privacy filtering.

## Verification

- `omarchy plugin validate .`: passed.
- `scripts/lint-qml.sh`: passed.
- `scripts/test-service.sh`: replay, final-frame exit, oversized-frame, startup-timeout, dependency-retry, restart-limit, structured startup-error, and runtime-exit cases passed.
- `node --test tests/model.test.js`: 14 tests passed.
- `python -m compileall -q scripts tests`: passed.
- `python -m unittest discover -s tests -v`: 29 tests passed.
- Live shell loaded the plugin from its local symlink and maintained one helper process.
- Live Switch Pro state displayed one wired controller with a full battery.
- Escape closed the compact popup using keyboard input only.
- Enter on Details closed the compact popup, opened the standalone panel, and transferred focus.
- Escape closed the standalone panel and synchronized shell state.
- Gruvbox and Catppuccin Latte rendered the compact panel with their active theme colors.
- Current Omarchy shell logs contained no warning or error attributed to `lightqv.gamepads`.

## Environment Notes

- Only one monitor was connected, so per-monitor routing was inspected against installed shell source and exercised on the active monitor; physical multi-monitor acceptance remains a release check.
- Quickshell `FloatingWindow` creates a normal Wayland toplevel. The current Hyprland policy tiles `org.quickshell` windows unless a matching user/system rule floats them; this matches the first-party dev-gallery integration pattern.
- External IPC summons may not receive compositor focus without a Wayland activation token. The in-shell keyboard path from the compact panel requests activation and passed keyboard-only acceptance.

## Remaining Work

- Phase 4 adds the full controller-tab application, profile contract, overview, and input-test modes.
- Multi-monitor physical acceptance remains pending because the development machine currently exposes one active monitor.
- Steam Input coexistence, suspend/resume, and broader theme/monitor coverage remain release-hardening checks.
