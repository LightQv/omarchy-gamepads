# Omarchy Gamepads

Omarchy Gamepads is an Omarchy shell plugin for controller vitals, interactive visualization, and guided input diagnostics. Nintendo Switch Pro Controller support is the initial target.

The repository currently contains the protocol version 1 backend, shared QML service, native compact bar panel, and a floating Details window with physical-controller tabs, a unified profile-aware workspace, and bottom `Live Input` and `Guided Diagnostic` views. The interactive 3D model remains under development.

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

## Controller Profiles

Detailed controller behavior is isolated in `profiles/`. The initial Switch Pro profile defines SDL matching, Nintendo-style labels, expected controls, semantic visual-part names, provisional diagnostic thresholds, and the visual component contract. SDL-recognized controllers without a detailed profile still receive a tab and generic vitals. See [`docs/controller-profile.md`](docs/controller-profile.md).

## Guided Diagnostics

A single bordered, stable-height surface begins with `Live Input` and `Guided Diagnostic` tabs, separated from the selected view by the same spacing used below the controller tabs. Live places both stick plots first and on the left, with button-style controls on the right. Switch controls follow their physical-profile order from B through ZR; unknown mapped controls follow the profile controls. ZL/ZR remain threshold-highlighted but show their live `0.00` to `1.00` values instead of checkbox markers. Other checkbox-style markers stay left of their labels across both modes. Each stick dot follows live input continuously while its plot box highlights only at the movement threshold. The centralized panel key catcher routes Left/Right or `h`/`l` to the mode tabs. Every overflowing viewport uses Omarchy-style directional edge fades: each fade appears only while more content remains beyond that edge. This covers the compact panel, controller tabs, controller information, Live buttons, and the Guided checklist. The guided diagnostic captures a neutral baseline, verifies post-baseline press and release edges, automatically advances completed stages, visualizes live stick range progress, and presents immutable results before export. Results use `passed`, `warning`, `not_detected`, `incomplete`, and `unavailable`; they do not assert that hardware is broken. Export is always explicit and atomically publishes each private JSON/Markdown report pair in a unique directory under `~/.local/state/omarchy-gamepads/reports/`.

## Validation

```bash
omarchy plugin validate .
scripts/lint-qml.sh
scripts/test-service.sh
scripts/test-panel.sh
bash tests/test_window_placement.sh
node --test tests/model.test.js tests/profile.test.js tests/diagnostics.test.js
python -m compileall -q scripts tests
python -m unittest discover -s tests -v
```

The service and panel smoke tests require Quickshell and an installed Omarchy shell at `/usr/share/omarchy/shell`. They cover selected-controller streaming, tab hotplug behavior, persistent profile visuals, diagnostic lifecycle and disconnect handling, unsupported profiles, unified live input, and host-close cleanup. Details-window placement uses the `hyprctl` and `jq` tools included with Omarchy to float, center, and move the existing window to the active workspace; its `1120x760` target is capped to the focused monitor's usable logical area, and its process-scoped pre-map rule is disabled immediately after placement.

## Security

- The helper runs as the logged-in user.
- It does not use exclusive input grabs.
- It does not require root, broad input-group membership, or blanket udev rules.
- SDL decides which devices qualify as gamepads.
- The helper does not query serial numbers or Bluetooth addresses, and its protocol has no fields for persistent identifiers or raw device paths.
- Device-provided product names are bounded and redacted for recognizable private paths and addresses, but should not be treated as anonymous if a vendor embeds unique text.
- Reports are projected through a strict allowlist and omit session IDs, serials, addresses, device paths, usernames, home paths, and unrelated controllers.
- The report directory is created only after explicit export; directories use mode `0700` and atomically written files use mode `0600`.
- PySDL3 network checks, documentation generation, and native-library downloads are disabled before import.

## License

MIT
