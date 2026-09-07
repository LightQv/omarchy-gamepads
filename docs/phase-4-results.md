# Phase 4 Results

**Phase:** Floating app and profile contract  
**Date:** 2026-09-07  
**Result:** Complete

## Delivered

- One tab per connected SDL controller, keyed by connection-session ID rather than name or family.
- Stable tab selection across unrelated additions, metadata updates, direct removals, and replacement snapshots.
- Native keyboard-focusable controller tabs with duplicate-name numbering and overflow reveal behavior.
- Validated controller-profile registry with deterministic specificity scoring and ambiguous-match rejection.
- Initial Switch Pro profile with Nintendo-style labels, expected controls, trigger semantics, visual-part mappings, and a lightweight visual component contract.
- Overview and live Input Test modes with keyboard mode switching and non-diagnostic live button/axis display.
- Generic vitals and a clear detailed-profile-unavailable state for recognized controllers without a profile.
- Selected-controller high-rate streaming only while Details is visible, with cleanup on close, service replacement, empty state, and component destruction.
- Stable low-frequency tab and axis identity projections that avoid rebuilding delegates for every input frame.
- Bounded line, page, Home, and End scrolling plus an Escape hierarchy that leaves Input Test before closing Details.

## Profile Safety

- Profiles cannot match by display name or connection-session ID.
- Every matcher must constrain SDL type or family; vendor and product IDs are refinements only.
- Product-specific matching requires a vendor ID.
- View paths are bundled relative QML paths and reject parent-directory traversal.
- Labels are bounded and reject control and bidirectional text characters.
- Every expected button and axis requires a semantic visual-part mapping.
- Equal-specificity matches from different profiles fail closed instead of depending on registration order.

## Verification

- `omarchy plugin validate .`: passed.
- `scripts/lint-qml.sh`: passed.
- `scripts/test-service.sh`: nine replay, supervision, dependency, error, limit, and streaming lifecycle cases passed.
- `scripts/test-panel.sh`: tabs, duplicate names, hotplug, neighboring selection, unsupported profile, modes, scrolling, streaming cleanup, and host lifecycle passed.
- `tests/test_window_placement.sh`: passed.
- `node --test tests/model.test.js tests/profile.test.js`: 20 tests passed.
- `python -m compileall -q scripts tests`: passed.
- `python -m unittest discover -s tests -v`: 29 tests passed, including all committed replay fixtures.
- Senior correctness review and security review approved the final implementation.
- Live shell restart loaded one helper and one wired Nintendo Switch Pro Controller.
- Live Details opened floating at `680x560` on the active workspace.
- Keyboard-only Tab, Right, and Enter opened Input Test; Page Down reached every live axis and the End action.
- The first Escape returned from Input Test to Overview; the second closed Details and synchronized shell state.
- Current shell logs contained no warning or error attributed to `lightqv.gamepads`.

## Environment Notes

- One physical controller and one monitor were available. Duplicate controllers, unsupported controllers, hotplug, and selected removal were exercised through deterministic QML and protocol fixtures.
- Quickshell runtime smoke tests remain local because the portable Ubuntu CI runner does not provide the installed Omarchy/Quickshell runtime. CI enforces manifest validation, QML lint, backend tests, JavaScript model/profile tests, and placement tests.
- Steam Input coexistence, suspend/resume, physical multi-controller hotplug, and physical multi-monitor behavior remain release-hardening checks.

## Remaining Work

- Phase 5 adds neutral capture, guided digital and analog checks, diagnostic statuses, retry behavior, and privacy-safe reports.
- Phase 6 replaces the lightweight visual component with the interactive Qt Quick 3D prototype while preserving this phase's semantic profile contract.
