# Development Instructions

Follow `docs/release-checklist.md` and the architecture contracts in `docs/`.

For every implementation phase:

1. Load the Omarchy skill before development and again for the phase-exit review.
2. Read the relevant skill guide and compare against the installed Omarchy shell source and representative first-party plugins.
3. Treat `/usr/share/omarchy/` as read-only.
4. Run the phase-appropriate manifest, QML, automated, and shell-context checks.
5. Resolve documented Omarchy integration findings before advancing phases.
6. Revalidate assumptions after an Omarchy upgrade.
