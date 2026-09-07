# Phase 5 Results

## Implemented

- Profile-owned, strictly validated provisional Switch Pro thresholds.
- A pure diagnostic reducer bound to the original session controller.
- Timed neutral baseline capture for held controls, center offset, and observed noise.
- Free-order post-baseline press/release checks for all mapped digital controls, including digital trigger hysteresis.
- Independent center, minimum, maximum, positive, and negative observations for both stick axes.
- Fixed `passed`, `warning`, `not_detected`, `incomplete`, and `unavailable` outcomes with non-failure language.
- Per-control retry while the tested controller remains connected.
- Incomplete review after cancellation, helper interruption, or original-controller disconnect.
- A full-width diagnostic tray beneath the persistent information and visual panes.
- Keyboard actions, active-session close confirmation, and controller-selection locking.
- Explicit JSON and Markdown export with an allowlisted report projection, private permissions, no-follow directory traversal, and collision-safe atomic publication.
- Deterministic success, drift, missing-input, and disconnect fixtures.

## Automated Validation

- Pure diagnostic tests cover successful completion, held baseline input, drift/noise/range warnings, unavailable controls, missing and partial input, one-sided movement, retry, cancellation, disconnect, status vocabulary, and report privacy.
- QML service smoke coverage verifies direct accepted-edge ingestion and original-controller disconnect handling.
- QML panel smoke coverage verifies selection locking and the active-session close hierarchy.
- Python export tests verify export-only directory creation, private permissions, atomic cleanup, and malformed-payload rejection.

## Live Integration

- A clean Omarchy shell restart loaded one helper and the connected wired Switch Pro controller.
- Details opened floating at `960x680` with the compact start tray and unchanged header/device row.
- Keyboard-only Tab and Enter started the session and completed the timed neutral baseline.
- The digital tray showed all 18 controls, completion count, and the next expected control without hiding the persistent information or visual panes.
- Escape opened the active-session confirmation; Right and Space ended the test and produced an incomplete review with all 22 untested controls classified as `incomplete` rather than `not_detected`.
- Escape from review closed Details, synchronized the host, retained exactly one helper, and produced no plugin-attributed shell warning.
- No report was written during live layout/lifecycle validation.

## Physical Acceptance

- Complete guided Switch Pro sessions passed over USB and Bluetooth.
- All mapped digital controls, digital triggers, stick axes, and stick clicks were detected through the guided workflow.
- Keyboard-only completion and review worked with both transports.
- Disconnect/incomplete behavior remains covered by deterministic service, reducer, and panel tests.

The Phase 5 exit criteria are satisfied. Thresholds remain conservative initial values and can be refined as observations from additional hardware accumulate.
