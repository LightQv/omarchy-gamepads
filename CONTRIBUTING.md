# Contributing

Keep changes focused, privacy-safe, and testable without physical hardware.

## Validation

Before submitting a change, run these checks from an Omarchy workstation with
Qt QML tooling, Node.js, and Python available:

```bash
omarchy plugin validate .
scripts/check-release-metadata.sh
scripts/lint-qml.sh
bash tests/test_window_placement.sh
node --test tests/*.test.js
python -m compileall -q scripts tests
python -B -m unittest discover -s tests -v
```

On an Omarchy workstation with Quickshell installed, also run:

```bash
scripts/test-service.sh
scripts/test-panel.sh
scripts/test-schematic.sh
```

The QML lint script uses an import-path shim because Omarchy's `qs.*` imports
need the installed shell source and plugin entry-point names can shadow shared
components. Keep state decisions in pure JavaScript reducers where practical so
they remain testable without a running shell.

The Switch Pro visual is a 2D QML schematic. Its static shell texture is separate
from live control items, and its layout/input projection lives in
`profiles/switch-pro/Schematic.js`. Keep the drawing event-driven and preserve
theme bindings, individual controls, and controller-scoped diagnostic marks.

`scripts/test-schematic.sh [output-directory]` exercises the native drawing and
can keep synthetic dark, light, monochrome, pressed, released, diagnostic, and
compact previews for inspection. Without a directory its outputs are temporary.
The [visual work archive](docs/visual-work-archive.md) preserves the retired 3D work.

## Controller Profiles

Controller-specific behavior belongs in explicit profiles or narrowly matched
SDL mapping corrections. Include deterministic fixtures and profile tests for
new controls or protocol behavior. Record the transport, mapped SDL type, and
observable capabilities used during physical verification.

Follow [`docs/controller-profile.md`](docs/controller-profile.md) for profile
matching, control labels, and diagnostic thresholds. A new visual implementation
should be agreed separately and keep diagnostics independent of rendering.

Do not include serial numbers, Bluetooth addresses, usernames, raw device
paths, or unredacted diagnostic reports in fixtures or issues.

## Safety

Do not add root services, exclusive grabs, broad input permissions, runtime
downloads, or persisted hardware identifiers. Changes to helper execution,
protocol validation, report export, or filesystem access require an explicit
security review.

Release work must complete [`docs/release-checklist.md`](docs/release-checklist.md).
