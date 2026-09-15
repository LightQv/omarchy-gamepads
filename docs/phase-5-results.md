# Phase 5 Results

> Historical implementation record. The current Details layout places Live Input and Guided Diagnostic together in the right pane.

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
- Bottom `Live Input` and `Guided Diagnostic` modes with live input selected whenever Details opens without an existing diagnostic.
- A single bordered, stable-height surface with mode tabs as its first row, no external section title, and controller-tab-matched spacing below the tabs.
- A sticks-first Live layout with both plots on the left and button-style controls on the right in profile-defined order, followed by unprofiled controls.
- Numeric `0.00` to `1.00` ZL/ZR values with press-threshold highlighting, movement-threshold highlighting for stick plot boxes, and continuously moving stick dots.
- Consistent checkbox-style rows with markers left and labels right for non-trigger controls across Live and Guided, plus wrapped Guided controls and threshold-aware automatic stage progression.
- Tab/Shift+Tab controller cycling plus spatial arrow and `h`/`j`/`k`/`l` navigation across input modes, retry selection, and guided actions through the centralized panel key catcher.
- Bottom-right review actions and immutable completed results across later connection changes.
- Reusable Omarchy-style directional edge fades for every overflowing viewport: compact content, controller tabs, controller information, Live buttons, and the Guided checklist.

## Automated Validation

- Pure diagnostic tests cover successful completion, automatic and manual progression, threshold boundaries, held baseline input, drift/noise/range warnings, unavailable controls, missing and partial input, one-sided movement, retry, cancellation, active disconnect, immutable review, status vocabulary, and report privacy.
- QML service smoke coverage verifies direct accepted-edge ingestion and distinct active-session and completed-review disconnect handling.
- QML panel smoke coverage verifies centralized keyboard mode selection, stable mode height, live control and stick threshold states, active selection locking, review selection unlocking, and the active-session close hierarchy.
- Python export tests verify export-only directory creation, private permissions, atomic cleanup, and malformed-payload rejection.

## Live Integration

- A clean Omarchy shell restart loaded one helper and the connected wired Switch Pro controller.
- Details opened floating at `1120x760` with `Live Input` selected and the unchanged header/device row.
- Keyboard-only arrows or `h`/`j`/`k`/`l` and Enter selected `Guided Diagnostic` through the panel key catcher, started the session, and completed the timed neutral baseline; Tab/Shift+Tab remained dedicated to controller cycling.
- The digital tray showed all 18 controls wrapped across two rows, completion count, and the next expected control without hiding the persistent information or visual panes.
- The stick stage showed live X/Y values, a two-dimensional position marker, and independent full-range direction indicators.
- Switching to `Live Input` during an active test preserved the session and displayed an explicit running-test indicator.
- Review actions remained pinned to the bottom right and the review identified the frozen tested controller and transport.
- At the `760x540` minimum, both main panes remained usable and every constrained viewport showed a theme-derived fade only where more content remained in that direction.
- Escape opened the active-session confirmation; Right and Space ended the test and produced an incomplete review with all 22 untested controls classified as `incomplete` rather than `not_detected`.
- Escape from review closed Details, synchronized the host, retained exactly one helper, and produced no plugin-attributed shell warning.
- No report was written during live layout/lifecycle validation.

## Physical Acceptance

- Complete guided Switch Pro sessions passed over USB and Bluetooth.
- All mapped digital controls, digital triggers, stick axes, and stick clicks were detected through the guided workflow.
- Keyboard-only completion and review worked with both transports.
- Disconnect/incomplete behavior remains covered by deterministic service, reducer, and panel tests.

The Phase 5 exit criteria are satisfied. Thresholds remain conservative initial values and can be refined as observations from additional hardware accumulate.
