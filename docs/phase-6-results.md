# Phase 6 Results

## Implemented

- A dependency-safe `SwitchProView.qml` wrapper that keeps Qt Quick 3D below a
  nested dynamic-loader boundary.
- An actionable missing-module fallback that leaves vitals, live input, and
  guided diagnostics available.
- A controlled-primitives Switch Pro scene with an explicit camera, offscreen
  `View3D`, moderate MSAA, and a two-light rig.
- Stable semantic nodes for every declared shell, grip, button, D-pad, shoulder,
  trigger, stick, and stick-click part.
- Pure `VisualState.js` projection for bounded live values, profile mappings,
  diagnostic completion, and controller-scoped immutable review status.
- Separate overview, diagnostic, and review modes. Overview uses controller
  sticks for presentation; diagnostics fix the camera and animate model parts.
- Pointer drag and wheel interaction plus `W`/`A`/`S`/`D`, `Q`/`E`, `+`/`-`,
  and `R` keyboard controls and a pointer-accessible reset action.
- Strict model-part, semantic mapping, animation, limitation, and threshold
  validation for controller profiles.
- Scene unloading with the Details lifecycle and no second streaming owner or
  backend process.

## Dependencies

- Omarchy `4.0.2-1`.
- Quickshell `0.3.1-1`.
- Qt Declarative `6.11.2-1`.
- Qt Quick 3D `6.11.2-1` from the official Arch repository.
- Portable CI scene checks use pinned `PySide6-Addons==6.11.2`.
- Portable missing-module checks use pinned `PySide6-Essentials==6.11.2`.

Before installing Qt Quick 3D, the native panel smoke verified that the outer
Details component remained usable and exposed the visualization fallback. A
fresh Essentials-only environment later confirmed that the loader test accepts
only the expected missing `QtQuick3D` module error. The matching Addons
environment loaded the real scene successfully.

## Automated Validation

- Profile tests cover exact semantic coverage, undeclared and stale mappings,
  duplicate model parts, overlapping controls, and animation boundaries.
- Visual-state tests cover all expected Switch Pro controls, normalized input
  clamping, overview/diagnostic/review separation, mismatched session IDs,
  paired-stick completion, and deterministic result-status severity.
- QML panel smoke coverage verifies scene readiness, runtime semantic binding,
  camera mutation and reset, diagnostic camera rejection, review scoping,
  unsupported profiles, hotplug, and close/reopen cleanup.
- Strict scene lint keeps Quick 3D imports and types outside the broad host
  metadata exclusions required by the complete Omarchy plugin lint.
- Portable CI has separate Quick3D-present and Quick3D-absent jobs.
- Existing backend, service, diagnostics, placement, metadata, privacy, and
  shell-syntax checks remain unchanged and passing.

## Performance

A native 60-second Quickshell stress run drove immutable controller updates at
approximately 60 Hz. The first 30 seconds exercised overview camera movement;
the second 30 seconds exercised fixed-camera diagnostic part animation.

```text
measured frames: 3710
input updates: 3739
median frame time: 16.13 ms
p95 frame time: 16.34 ms
```

The p95 result remains below the Phase 6 limit of 33 ms, with no observed input
backlog, binding loop, renderer warning, or plugin-attributed shell error.

## Live Integration

- A clean shell restart loaded the enabled development plugin and one connected
  wireless Switch Pro controller into the shared Details window.
- The scene rendered at the normal `1120x760` size and remained usable at the
  `760x540` minimum.
- The controller profile, live axes, semantic scene, camera guidance, and reset
  action rendered together without changing the existing header, tabs, or
  diagnostic surface.
- Dedicated camera keys do not conflict with arrows, `h`/`j`/`k`/`l`, Tab,
  Enter, Space, Escape, PageUp/PageDown, Home, or End.
- Existing Phase 5 USB and Bluetooth input verification uses the same normalized
  controller schema consumed by the transport-independent visual projection.
- No system theme was changed during Phase 6 validation.

## Known Prototype Limitations

- Geometry is intentionally built from controlled primitives and is not the
  production-quality Switch Pro model.
- The scene uses compact status text and motion/highlight feedback rather than
  texture-based control legends.
- Native Quickshell panel and performance tests remain workstation checks until
  a suitable Arch/Omarchy CI runner is available; portable CI covers scene
  loading, strict lint, semantic projection, and missing-module behavior.

The Phase 6 exit criteria are satisfied. Every expected input maps to a declared
and implemented visible part, camera and diagnostic animation modes are
separate, native rendering remains responsive, and the semantic contract is
frozen for Phase 7 production-model replacement.
