# Phase 4 Results

> Historical implementation record. The current Details layout and profile contract supersede the visual-pane design described below.

**Phase:** Floating app and profile contract  
**Date:** 2026-09-07  
**Result:** Complete

## Delivered

- One tab per connected SDL controller, keyed by connection-session ID rather than name or family.
- Stable tab selection across unrelated additions, metadata updates, direct removals, and replacement snapshots.
- Native keyboard-focusable controller tabs with duplicate-name numbering and overflow reveal behavior.
- Validated controller-profile registry with deterministic specificity scoring and ambiguous-match rejection.
- Initial Switch Pro profile with Nintendo-style labels, expected controls, trigger semantics, visual-part mappings, and a lightweight visual component contract.
- Unified split-pane workspace with persistent controller information, live textual input, and a profile visual.
- Generic vitals and a clear detailed-profile-unavailable state for recognized controllers without a profile.
- Selected-controller high-rate streaming only while Details is visible, with cleanup on close, service replacement, empty state, and component destruction.
- Stable low-frequency tab and axis identity projections that avoid rebuilding delegates for every input frame.
- Independent bounded information-pane scrolling plus direct Escape closure until Phase 5 introduces real subordinate diagnostic state.
- Monitor-aware `960x680` target sizing that preserves both panes and caps placement to the focused monitor's usable logical area.

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
- `scripts/test-panel.sh`: tabs, duplicate names, hotplug, neighboring selection, persistent profile visuals, unsupported fallback, unified live input, streaming cleanup, and host lifecycle passed.
- `tests/test_window_placement.sh`: default and constrained-monitor placement passed.
- `node --test tests/model.test.js tests/profile.test.js`: 20 tests passed.
- `python -m compileall -q scripts tests`: passed.
- `python -m unittest discover -s tests -v`: 29 tests passed, including all committed replay fixtures.
- Senior correctness review and security review approved the final implementation.
- Live shell restart loaded one helper and one wired Nintendo Switch Pro Controller.
- Live Details opened floating at `960x680` on the active workspace.
- The native header and device-tab row remained fixed above the information and visual panes.
- Escape closed Details and synchronized shell state; Phase 5 will add an active-session confirmation level.
- Current shell logs contained no warning or error attributed to `lightqv.gamepads`.

## Environment Notes

- One physical controller and one monitor were available. Duplicate controllers, unsupported controllers, hotplug, and selected removal were exercised through deterministic QML and protocol fixtures.
- Quickshell runtime smoke tests remain local because the portable Ubuntu CI runner does not provide the installed Omarchy/Quickshell runtime. CI enforces manifest validation, QML lint, backend tests, JavaScript model/profile tests, and placement tests.
- Steam Input coexistence, suspend/resume, physical multi-controller hotplug, and physical multi-monitor behavior remain release-hardening checks.

## Remaining Work

- Phase 5 adds neutral capture, guided digital and analog checks, diagnostic statuses, retry behavior, and privacy-safe reports.
- Phase 6 replaces the lightweight visual component with the interactive Qt Quick 3D prototype while preserving this phase's semantic profile contract.
