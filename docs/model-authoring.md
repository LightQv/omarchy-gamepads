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

### Toolchain

Phase 7 asset maintainers use Blender 5.2, Qt Quick 3D 6.11.2 Balsam, and
Assimp 6 from the official Arch repositories. Verify the local installation
with `scripts/check-model-toolchain.sh`. Blender and Assimp are build-time tools
only; runtime users continue to need only Qt Quick 3D.

Blender is the canonical editable source. Export GLB only as temporary
interchange input, then use Balsam to condition committed Qt `.mesh` runtime
assets. Do not load GLB dynamically or require asset importers at runtime.

`asset-contract.json` records neutral transforms in Qt Quick 3D coordinates and
the local motion axis for each semantic part. The export pipeline must inspect
Balsam's generated QML to map source objects to conditioned mesh files, verify
that mapping against the contract, and write it to `runtime/manifest.json`.
Generated QML is then discarded. Hand-owned runtime QML keeps the semantic
nodes and animation bindings; asset validation checks its mesh paths and neutral
transforms against the contract before the prototype is replaced.

### Repository Layout

- `models/switch-pro/source/` contains the original editable `.blend` file.
- `models/switch-pro/runtime/` contains conditioned `.mesh` files and their
  deterministic manifest.
- `models/switch-pro/review/` contains selected fixed-camera review renders.
- `models/switch-pro/asset-contract.json` freezes hierarchy, bounds, and budgets.
- `models/switch-pro/REFERENCES.md` records measurements and visual references.
- `models/switch-pro/LICENSE.md` records asset redistribution terms.

Temporary GLB, Balsam-generated QML, Blender backups, work files, and turntable
frame sequences are not committed.
