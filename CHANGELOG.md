# Changelog

All notable changes to this project will be documented here.

## [Unreleased]

- Add a fixed front/above Switch Pro schematic with accent-colored contours,
  dithered grips, monospace labels, and live theme updates.
- Highlight independent and simultaneous inputs, move stick caps separately from
  clicks, and show controller-scoped diagnostic marks with theme-safe contrast.
- Add native schematic input, palette, compact-layout, and lifecycle checks with
  optional synthetic previews.
- Preserve the complete geometry/material work through shoulder revision 4 and the
  3D prototype in a verified external recovery archive, including private references,
  exact recipes, review history, uncommitted work, and Git history.
- Retire the 3D prototype and camera controls while keeping controller profiles
  focused on input and guided diagnostics.
- Remove archived authoring files and dedicated Blender/Quick 3D checks from the active
  repository, and retain compact archive and restoration documentation.

## [1.0.0] - 2026-09-08

- Add the Omarchy plugin foundation.
- Add protocol version 1 and the SDL3 backend helper.
- Add deterministic USB, Bluetooth, hotplug, error, and rejection fixtures.
- Add udev transport and kernel power-supply fallbacks.
- Add bounded command, event, replay, privacy, and cleanup safeguards.
- Add the shared QML service, native compact panel, and floating Details lifecycle.
- Add physical-controller tabs, validated Switch Pro profiles, and unified live input.
- Add hotplug-safe selection and visible selected-controller streaming.
- Refine Details into persistent information and reserved visualization panes with monitor-aware sizing for guided diagnostics.
- Add profile-driven guided diagnostics, reviewable status results, deterministic fixtures, and explicit privacy-safe report export.
- Separate live input from guided diagnostics inside one stable bordered surface with first-row mode tabs, sticks-first live layout, threshold-aware stick and digital-trigger highlights, consistent left-side checkbox markers, centralized keyboard navigation, automatic stage progression, and immutable completed reviews.
- Refine the diagnostic surface with no external section title, controller-tab-matched content spacing, `Guided Diagnostic` terminology, profile-defined Switch control order, and numeric ZL/ZR values.
- Add Omarchy-style directional edge fades to every overflowing compact and Details viewport.
- Dedicate Tab/Shift+Tab to controller cycling and use one spatial arrow or `h`/`j`/`k`/`l` cursor for Details modes, retry selection, and guided actions.
- Bound deferred SDL controller admission and reuse one race-safe dynamic Details window rule.
- Prepare the non-3D feature set as the stable v1 release.

[Unreleased]: https://github.com/lightqv/omarchy-gamepads/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/lightqv/omarchy-gamepads/releases/tag/v1.0.0
