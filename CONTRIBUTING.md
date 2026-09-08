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
```

The QML lint script uses an import-path shim because Omarchy's `qs.*` imports
need the installed shell source and plugin entry-point names can shadow shared
components. Keep state decisions in pure JavaScript reducers where practical so
they remain testable without a running shell.

## Controller Profiles

Controller-specific behavior belongs in explicit profiles or narrowly matched
SDL mapping corrections. Include deterministic fixtures and profile tests for
new controls or protocol behavior. Record the transport, mapped SDL type, and
observable capabilities used during physical verification.

Do not include serial numbers, Bluetooth addresses, usernames, raw device
paths, or unredacted diagnostic reports in fixtures or issues.

## Safety

Do not add root services, exclusive grabs, broad input permissions, runtime
downloads, or persisted hardware identifiers. Changes to helper execution,
protocol validation, report export, or filesystem access require an explicit
security review.

Release work must complete [`docs/release-checklist.md`](docs/release-checklist.md).
