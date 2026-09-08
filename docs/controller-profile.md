# Controller Profile Contract

Controller profiles describe controller-family behavior without changing the SDL helper or general UI. The registry lives in `profiles/ProfileRegistry.js`; profile definitions live in a family-specific directory under `profiles/`.

## Required Fields

- `id`: stable lowercase profile identifier.
- `displayName`: bounded user-facing profile name.
- `matchers`: one or more SDL type, family, vendor, or product constraints.
- `labels`: semantic control labels shown in the UI.
- `expectedButtons` and `expectedAxes`: controls expected from the profile.
- `triggerType`: `digital` or `analog`.
- `viewComponent`: bundled QML component below `profiles/`.
- `modelParts`: ordered, unique inventory of stable visual part names.
- `semanticParts`: mapping from every expected control to a stable visual part name.
- `animation`: profile-specific visual parameters.
- `thresholds`: profile-specific diagnostic thresholds.
- `knownLimitations`: concise profile limitations.

All expected controls must have semantic mappings to declared model parts. Registry validation rejects malformed IDs, unsafe labels, parent-directory view paths, missing or extra mappings, malformed animation or thresholds, and ambiguous equal-specificity matches.

## Visual Contract

The profile view is loaded dynamically and must not make the rest of Details
depend on Qt Quick 3D. It receives the selected controller, profile, diagnostic
state, interaction mode, render-active state, and Omarchy theme roles. It
exposes scene readiness, semantic-binding validity, implemented part names,
camera state, `handleCameraKey()`, and `resetView()`.

The Switch Pro animation schema uses `digitalTravel` in scene units,
`stickTiltDegrees` in degrees, and an integer `transitionDurationMs`. The
registry bounds all three values. Trigger travel remains proportional to its
normalized SDL axis even though Switch triggers use digital diagnostic
hysteresis.

Overview mode maps controller sticks to model presentation. Diagnostic mode
holds a stable camera and maps live input to semantic parts. Review mode adds
immutable result status only when both controller and profile IDs match the
completed session. Scene nodes and production assets must preserve the declared
part inventory; QML IDs are not used as an external lookup API.

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
- Treat the semantic part names as a compatibility contract for later 3D assets.
- Keep Quick 3D imports below the dependency-safe profile-view loader boundary.
- Stop or destroy rendering work when the Details window is hidden.
