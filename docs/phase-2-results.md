# Phase 2 Results

**Phase:** Backend protocol and replay fixtures  
**Date:** 2026-09-06  
**Result:** Complete

## Delivered

- Frozen newline-delimited JSON protocol version 1.
- Safe PySDL3 bootstrap using the packaged system SDL library.
- SDL Gamepad enumeration and admission.
- Session-scoped controller identity.
- Initial snapshots and controller metadata updates.
- Immediate button deltas and frame-coalesced axis deltas.
- Hot-add, hot-remove, remap, and power-update handling.
- Snapshot, streaming, subscription, and shutdown commands.
- Switch Pro Capture correction through SDL mapping `misc1:b4`.
- Udev transport fallback and correlated kernel power-supply fallback.
- Deterministic USB, Bluetooth, hotplug, dependency-error, empty, and rejected-device fixtures.
- Strict replay validation and final privacy filtering.

## Safety Bounds

- Commands are framed with bounded reads and a bounded queue.
- Command processing and SDL event processing have per-loop budgets.
- Axis events retain only the latest value per controller between frames.
- Replay accepts only bounded regular non-symlink files.
- Replay schemas use an allowlist and reject unknown producer fields.
- Non-finite JSON values and invalid control/axis ranges are rejected.
- Buffered axis state is discarded before controller removal is emitted.
- SDL handles and subsystems are cleaned up on shutdown and initialization failure.
- PySDL3 version checks, downloads, documentation generation, and stdout logging are disabled before import.

## Verification

- `omarchy plugin validate .`: passed.
- `scripts/lint-qml.sh`: passed with the Omarchy `qs.*` import shim.
- `python -m compileall -q scripts tests`: passed.
- `python -m unittest discover -s tests -v`: 29 tests passed.
- All six replay fixtures validated and produced deterministic canonical output.
- Live startup emitted a valid SDL `3.4.14` handshake and one initial snapshot.
- Live malformed-command recovery emitted a protocol error and continued running.
- Live snapshot reported the Switch Pro Controller as wired, charging, and coarse capacity `full` without exposing private identifiers.
- Live streaming emitted 846 input deltas during the acceptance sample.
- Live B presses appeared as `south`.
- Live Capture presses appeared as `misc1`.
- Live left-stick X and Y each reached normalized `-1.0` and `1.0`.
- Live shutdown exited with status 0 and empty standard error.

Review hardening also verified controller admission limits, enumeration failure cleanup, remap buffering cleanup, descriptor-based replay opening, strict startup sequencing, and duplicate-controller rejection.

## Remaining Work

- Phase 3 must supervise the helper and apply bounded restart behavior in QML.
- Steam Input coexistence remains a release-hardening check.
- Suspend/resume remains a release-hardening check.
- Bluetooth production-helper behavior should be rechecked after SDL, PySDL3, kernel, or mapping database upgrades.
