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

Phase 7 asset maintainers use Blender 5.2, Qt Quick 3D 6.11.2 Balsam, Assimp 6,
Bubblewrap, `python-pillow`, and `python-numpy` from the official Arch repositories. Verify the local
installation with `scripts/check-model-toolchain.sh`. Blender, Assimp, and
Bubblewrap are build-time tools only; runtime users continue to need only Qt
Quick 3D.

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
- `models/switch-pro/REFERENCES.md` records published dimensions, source roles,
  and visual-reference constraints.
- `models/switch-pro/LICENSE.md` records asset redistribution terms.
- `models/switch-pro/milestones/geometry-v1/` records the accepted geometry milestone
  and compact section evidence; the Git tag preserves its complete source/tool tree.
- Ignored `models/switch-pro/references-local/` keeps private original photographs
  and photo comparison sheets outside disposable scratch space.
- Ignored `models/switch-pro/work/` contains only regenerable staging/candidates.

### Source Checkpoint

Run `scripts/build-switch-pro-model.sh` to rebuild the canonical `.blend`,
validate its semantic hierarchy and budgets, and refresh the fixed-camera
review renders. Outputs are built and validated in an ignored staging directory
before rollback-backed promotion replaces the prior checkpoint. A semantic scene
digest covers transforms, geometry, topology, and materials; unchanged rebuilds
retain the existing `.blend` container because Blender metadata is byte-variable.
The builder uses shared section cages, photo-constrained palm surfaces and molded
control profiles. `photo_shape_profiles.json` records the bounded palm quadric and
exterior conditioning settings; `photo_profiles.py` evaluates its sections against
the calibrated front-width rail. The grips sweep rearward independently of the
central rear-to-front underside roll and narrow front lip.

The three body cages are unified with a bounded voxel operation, smoothed and
triangle-conditioned, then partitioned at curved front/rear cover seams. The
closed components receive original atlas coordinates and ordinary geometric
normals; internal closing-wall edges are sharp. The tapered LED insert, windows
and grip-end fasteners are fitted to the final supporting surface. All nineteen
control mesh shapes retain their previous fingerprints. The original
color/roughness/normal atlases are packed into the source. The color atlas is
sRGB; the data maps are linear. Reference-image
coordinates and the independent foreground mask are versioned under `tools/`.
Photographs are not imported as geometry or runtime textures.

Every Blender invocation runs in an aggregate memory, swap, task, CPU, and time
bounded systemd scope without network access, inherited environment variables,
capabilities, or unrelated repository files in a Bubblewrap filesystem and PID
sandbox. A retained byte-variable
`.blend` is copied into staging and fully revalidated before it can replace the
newly generated candidate. Validation records the exact source SHA-256, rejects
hidden or executable datablocks, collection instancing/visibility changes, and
non-contract transforms, enforces geometry resource limits and consistently
wound closed topology per mesh island, and
binds that result to the promoted checkpoint. Packed image bytes, UVs, and corner
normals are covered by the semantic digest. Only the three bounded original
PBR images and their exact material connections are accepted. CI uses the checksum-pinned
official Blender build to validate the committed source independently and
exercises harmless adversarial validator mutations.

The stakeholder accepted source `ca8d4995…` as the gray-geometry milestone on
2026-09-11. Tag `switch-pro-geometry-v1` preserves the complete final source and
matching recipe. The recipe generates the current shape directly, without
replaying historical attempts. `milestones/geometry-v1/README.md` explains clean
rebuilds, isolated candidate review, later geometry rework and legacy recovery.
Small historical baseline measurements remain useful regression evidence; old
experimental sources/renders/scripts reside in one verified external archive.
Their prior decisions are documented in `phase-7-results.md` and the source-bound
`review-decision.json`. Material development follows geometry acceptance; final
source appearance approval precedes GLB/Balsam conversion and runtime replacement.

Review rendering uses CPU Cycles and generates six orthographic geometry views,
front/top/rear/underside perspective views, historical low-side/low-front camera
views, six user-photo-aligned views, a dark-background front perspective, and a
12-frame turntable. Every current review uses a uniform gray material override;
packed textures, normal maps, and translucency do not influence these geometry
images. Turntable framing fits the full orbit, and processing rejects frames
whose alpha silhouette reaches the four-pixel image border. The
offline comparison tool aligns the actual rendered alpha mask to the independent
photo segmentation. It composites review images at 1024 × 768, writes fit
evidence, and produces an animated GIF and contact sheet. `geometryEvidence` in
`review/fit.json` includes summed body-mesh volume, selected center/grip-column
depth probes in logical units, control-shape hashes, and longitudinal skin
profiles at X = 0 and X = 2.16, plus `waistProfile` at X = 1.25 and bilateral
`handleProfiles` at X = ±2.16. They use each body mesh's largest connected
island to exclude fixed details. They record sampled Y/Z boundaries, bottom
positions, and the depth span within 0.03 units of the lowest point. These are
model comparison measurements, not calibrated physical-controller measurements.

Rear refinement is applied to the dense conditioned exterior in `photo_profiles.py`
before decimation and cover partitioning. It samples the old rear across the
center width and shapes one convex wedge through the cap/underside boundary.
Handle depth and curvature use independent controls: a small compression toward
the rearward rail and an inward upper-back curve, with broad root/heel fades.
Increasing positive rear Y makes the handle thicker; do not use outward bulge as
a proxy for stronger curvature. Inspect bilateral depth stations and rear tangent
rotation separately. Preserve the improved central rear through baseline section
samples, and retain the heel anchor and front-view width. Shaping after decimation can
produce horizontal bands. Always inspect both center and side-waist sections;
the source-bound JavaScript checks reject profile reversals and abrupt tangent
changes at their former cap/rim joins.

`owned_photo_landmarks.json` pins the nine user JPEGs, EXIF normalization, crops,
visible grip outlines and control/body-marker observations.
`owned_photo_cameras.json` records the viewing matrices and residuals. All five
side/bottom/oblique poses are fitted jointly with the palm surface. The oblique
was incorporated after a four-view diagnostic candidate exposed a nearer-grip
mismatch. These are reconstruction fits rather than independent validation.
The retry holds those poses and annotations fixed while incorporating stakeholder
surface feedback. The front has an independent control-landmark fit.
These handheld alignments and silhouette statistics are not manufacturing
measurements or overall-fidelity scores.

`render_review.py` exports the actual Blender view-projection matrices and
main-skin projections into staging. `compare_owned_reference.py` compares these
with the numerical annotations and writes `review/owned-fit.json` and the
photograph-free `review/owned-silhouettes.png`. The checkpoint hashes these
artifacts and all contributing tools/data. A normal offline build requires no
photograph files. Temporary projection arrays are removed with staging.

The private `references-local/geometry-v1/reference-comparison.png` shows each
photograph beside the previous rear revision and accepted gray source, using
identical cameras. `milestones/geometry-v1/rear-sections.png` shows bridge/waist/grip
sections and `handle-sections.png` annotates bilateral thickness. Original photos
remain under `references-local/owned/` and `references-local/public/`. The reusable
`tools/iterate_model.py` produces isolated candidates; `tools/compare_photo_views.py`
verifies source/image/photo hashes and writes new private comparison sheets. See
`tools/README.md` for commands. These references and the legacy archive are not
required for normal rebuilds or numerical regression tests.
The ambiguous Nintendo Life low-front boundary is excluded from current contour
fitting; its earlier camera remains a historical comparison. Unchanged rebuilds
exercise adversarial validation before promotion.

CPU Cycles and denoising do not guarantee byte-identical PNG/GIF output between
runs. The checkpoint hashes each generated image; semantic source retention is
independent of render-byte reproducibility.

Temporary GLB, Balsam-generated QML, Blender backups, work files, and turntable
frame sequences are not committed.
