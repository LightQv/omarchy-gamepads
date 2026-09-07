# Contributing

Keep changes focused, privacy-safe, and testable without physical hardware.

Before submitting a change, run:

```bash
omarchy plugin validate .
scripts/lint-qml.sh
python -m compileall -q scripts tests
python -m unittest discover -s tests -v
```

The QML lint script must run from its own wrapper because Omarchy's `qs.*` imports need an import-path shim and plugin entry-point names can shadow shared component names. Keep state decisions in pure JavaScript reducers where practical so they can be tested without a running shell.

Controller-specific behavior belongs in explicit profiles or narrowly matched SDL mapping corrections. Do not add root services, exclusive grabs, broad input permissions, runtime downloads, or persisted hardware identifiers.

Record new hardware observations without serial numbers, Bluetooth addresses, usernames, or raw device paths. Add deterministic replay fixtures for protocol changes.
