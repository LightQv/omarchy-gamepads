# Controller Profile Contract

Controller profiles describe controller-family behavior without changing the SDL helper or general UI. The registry lives in `profiles/ProfileRegistry.js`; profile definitions live in a family-specific directory under `profiles/`.

## Required Fields

- `id`: stable lowercase profile identifier.
- `displayName`: bounded user-facing profile name.
- `matchers`: one or more SDL type, family, vendor, or product constraints.
- `labels`: semantic control labels shown in the UI.
- `expectedButtons` and `expectedAxes`: controls expected from the profile.
- `triggerType`: `digital` or `analog`.
- `thresholds`: profile-specific diagnostic thresholds.
- `knownLimitations`: concise profile limitations.

Registry validation rejects malformed IDs, unsafe labels, duplicate or overlapping
button/axis lists, malformed thresholds, and ambiguous equal-specificity matches.

## Controller Visuals

Profiles describe controller input and diagnostics independently of rendering.
For the `switch-pro` profile, Details loads `profiles/switch-pro/Schematic.qml`
while open. The fixed 2D layout and pure input projection are in `Schematic.js`.
This family-specific drawing consumes the selected controller, profile thresholds,
and diagnostic state directly; it adds no required profile fields.

The diagram covers all 18 digital controls (including stick clicks and triggers)
and four stick axes. Missing capabilities are muted. Buttons highlight on live
input; trigger and movement highlights use the same thresholds as Live Input.
Stick caps preserve down-positive SDL Y and clamp malformed values safely.
Guided result marks require both the selected controller ID and profile ID to
match the diagnostic session. Click and paired-axis results remain independent.

Body contours and dithering use `Color.accent`; labels use the shell font. Presses
use the themed pressed-state color, with a foreground fallback for transparent or
low-contrast colors and an inverted label. Passed results use `✓`; warnings and
undetected inputs use `Color.urgent` and `!`. The static shell canvas only redraws
for palette/visibility changes; live controls update as ordinary 2D items. The
loader destroys the drawing when Details closes or selects an unsupported profile.

Native coverage and preview capture are provided by `scripts/test-schematic.sh`.
The retired visual contract and 3D sources remain in the [external archive](visual-work-archive.md).

## Diagnostic Thresholds

Threshold values are SDL-normalized and profile-owned. The required schema contains `baselineDurationMs`, digital trigger press/release hysteresis, center-offset and neutral-jitter warning levels, independent positive and negative minimum ranges, and a movement-detection threshold. The registry requires a one-to-two-second integer baseline, finite normalized values, trigger release below trigger press, and movement detection below both range targets.

The initial Switch Pro values are conservative and provisional. They only classify observations from the current test and never modify SDL or system calibration. Physical USB and Bluetooth testing should refine them over time.

## Matching

Each matcher can constrain `sdlTypes`, `families`, `vendorId`, and `productId`. More specific matches outrank generic matches. Equal-scoring matches from different profiles are treated as ambiguous and return no detailed profile rather than relying on registration order.

The initial Switch Pro profile matches SDL's normalized `switchpro` type. Vendor and product IDs are available for future refinements but are not required, allowing compatible controllers identified by SDL to use the profile.

## Extension Rules

- Do not add backend logic for labels, visuals, or diagnostic thresholds.
- Do not match on controller display names.
- Keep session IDs out of profiles; they identify connected instances, not hardware families.
- Render unsupported SDL controllers with generic vitals instead of forcing a profile.
- Add registry tests, replay fixtures, and physical test notes with every new profile.
- Keep guided diagnostics and controller admission independent of future visuals.
