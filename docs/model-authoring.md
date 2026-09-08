# Model Authoring Contract

The Phase 6 Switch Pro scene uses original controlled primitives to freeze the
runtime contract before production asset work. Phase 7 may replace the geometry
but must not change controller semantics, panel APIs, or visual-state data.

## Coordinates And Scale

- Use a right-handed Qt Quick 3D scene with positive X to the controller's right,
  positive Y toward its top edge, and positive Z toward the viewer.
- Center the complete controller near the scene origin in its neutral pose.
- Keep model dimensions near the prototype's logical scale so the existing
  camera range remains useful.
- Apply input movement in each part's local coordinate system.
- Keep every animated origin at the mechanical pivot or travel axis.

## Required Parts

`profiles/switch-pro/Profile.js` is the authoritative ordered part inventory.
Shell and grip nodes establish structure; every mapped button, direction,
trigger, stick, and stick click must produce a visible transform or redundant
highlight. Left and right stick X/Y axes intentionally share their stick part,
while stick clicks use separate nested parts so tilt and depression compose.

## Runtime Boundary

- `SwitchProView.qml` remains the dependency-safe public wrapper.
- `SwitchProScene.qml` owns the replaceable Qt Quick 3D scene.
- `VisualState.js` owns presentation projection and remains geometry-agnostic.
- Do not put diagnostic policy, SDL mappings, or persistent controller identity
  into model assets.
- Use moderate antialiasing, controlled materials and lights, and no required
  post-processing.
- Rendering and animation must stop when `renderActive` is false.

## Phase 7 Assets

Commit original source geometry, deterministic authoring and export scripts,
runtime assets, validation output, and explicit redistribution terms. Validate
node names, bounds, transforms, pivots, material count, and runtime scale before
replacing the prototype.
