# Omarchy Gamepads

Omarchy Gamepads is an Omarchy shell plugin for controller vitals, interactive visualization, and guided input diagnostics. Nintendo Switch Pro Controller support is the initial target.

The repository currently contains the protocol version 1 backend, shared QML service, compact bar panel, and a minimal Details window. Input visualization and guided diagnostics remain under development.

## Installation

Omarchy plugins run as unsandboxed code inside the long-running `omarchy-shell` process. Review the repository before installing it. The plugin manager clones and validates plugins but does not install their runtime dependencies.

Install from a trusted Git URL, then enable the plugin:

```bash
omarchy plugin add <git-url>
omarchy plugin enable lightqv.gamepads
```

The bar widget defaults to the right section and can be moved with `omarchy bar move lightqv.gamepads --section right`. Its button opens the compact vitals popup. The Details action, or `omarchy-shell shell summon lightqv.gamepads`, opens the independent panel. Both interfaces use one shared service and one helper process.

## Runtime Dependencies

Install dependencies from the official repositories:

```bash
omarchy pkg add python-pysdl3 qt6-quick3d
```

Qt Quick 3D is not needed while running only the backend tests. Blender is an optional maintainer dependency and is never required at runtime.

## Backend

Run the live helper:

```bash
python scripts/gamepad-helper.py
```

The helper communicates using newline-delimited JSON on standard input and output. See [`docs/backend-protocol.md`](docs/backend-protocol.md).

## Validation

```bash
omarchy plugin validate .
scripts/lint-qml.sh
scripts/test-service.sh
node --test tests/model.test.js
python -m compileall -q scripts tests
python -m unittest discover -s tests -v
```

The service smoke test requires Quickshell and an installed Omarchy shell at `/usr/share/omarchy/shell`.

## Security

- The helper runs as the logged-in user.
- It does not use exclusive input grabs.
- It does not require root, broad input-group membership, or blanket udev rules.
- SDL decides which devices qualify as gamepads.
- The helper does not query serial numbers or Bluetooth addresses, and its protocol has no fields for persistent identifiers or raw device paths.
- Device-provided product names are bounded and redacted for recognizable private paths and addresses, but should not be treated as anonymous if a vendor embeds unique text.
- PySDL3 network checks, documentation generation, and native-library downloads are disabled before import.

## License

MIT
