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
- `semanticParts`: mapping from every expected control to a stable visual part name.
- `animation`: profile-specific visual parameters.
- `thresholds`: profile-specific diagnostic thresholds; Phase 4 leaves these empty.
- `knownLimitations`: concise profile limitations.

All expected controls must have semantic mappings. Registry validation rejects malformed IDs, unsafe labels, parent-directory view paths, incomplete mappings, and ambiguous equal-specificity matches.

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
