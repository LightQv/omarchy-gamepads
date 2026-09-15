# Release Checklist

Run this checklist against the exact commit intended for release.

## Metadata

- Manifest, changelog, and tag use the same semantic version.
- README installation links target the canonical repository.
- Runtime dependencies and tested versions are current.
- The changelog contains a dated release section.
- Screenshot assets represent the release commit and contain no private data.

## Automated Validation

```bash
omarchy plugin validate .
scripts/check-release-metadata.sh
scripts/lint-qml.sh
scripts/test-service.sh
scripts/test-panel.sh
scripts/test-schematic.sh
bash tests/test_window_placement.sh
node --test tests/*.test.js
python -m compileall -q scripts tests
python -B -m unittest discover -s tests -v
bash -n scripts/clear-details-window-rule scripts/place-details-window \
  scripts/lint-qml.sh scripts/prepare-details-window scripts/test-panel.sh \
  scripts/test-service.sh scripts/test-schematic.sh \
  tests/test_window_placement.sh
git diff --check
```

## Clean Checkout

- Clone the release candidate into a new temporary directory.
- Confirm no generated files or symlinks are tracked.
- Run manifest validation, metadata checks, QML lint, and portable tests there.
- Install dependencies before adding the plugin; the plugin manager does not
  run hooks or install packages.
- Add, enable, update, disable, and remove the plugin through Omarchy's plugin
  commands when testing from the published repository.

## Live Omarchy Validation

- Restart the shell and confirm exactly one gamepad helper runs.
- Open and close the compact panel and Details repeatedly.
- Confirm Details floats, centers, follows the active workspace, and fits the
  focused monitor's usable area.
- Verify no plugin-attributed QML warnings, binding loops, or script errors.
- Verify keyboard-only controller selection, live input, diagnostics, review,
  retry, export, and close behavior.
- Verify minimum `760x540` Details layout and all directional scroll fades.
- Verify every schematic button, independent stick motion/clicks, simultaneous
  input, release, and controller-scoped diagnostic marks.
- Verify live palette updates and readable highlights in dark, light, and
  monochrome themes, including the compact diagram layout.
- Verify schematic unload/reopen and the generic unsupported-profile fallback.
- Verify live controls and guided diagnostics work without a visual renderer.
- Verify at least one dark and one light Omarchy theme.

## Physical Acceptance

- Complete a Switch Pro diagnostic over USB.
- Complete a Switch Pro diagnostic over Bluetooth.
- Reconnect and hotplug during normal use.
- Verify disconnect produces an incomplete review during an active diagnostic.
- Check Steam Input coexistence before and during a game where practical.
- Check suspend and resume while a controller is connected.
- Check multiple controllers and monitors when hardware is available.

## Release

- Review the final diff for secrets, private identifiers, and generated files.
- Obtain correctness, security, and Omarchy integration approval.
- Tag the validated commit as `v<version>`.
- Push `main` and the tag, then confirm GitHub Actions passes.
- Publish release notes from the matching changelog section.
