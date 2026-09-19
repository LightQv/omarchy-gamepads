# Contributing

Keep changes focused, privacy-safe, and testable without physical hardware.

## Validation

Before submitting a change, run the applicable checks from an Omarchy
workstation with Qt QML tooling, Node.js, and Python available. State any checks
you could not run in the pull request; CI repeats the portable checks.

```bash
omarchy plugin validate .
scripts/check-release-metadata.sh
scripts/lint-qml.sh
bash tests/test_window_placement.sh
node --test tests/*.test.js
python -m compileall -q scripts tests
python -B -m unittest discover -s tests -v
```

For runtime or interface changes, also run these lifecycle checks on an Omarchy
workstation with Quickshell installed. A maintainer must run them before merge
when a contributor cannot:

```bash
scripts/test-service.sh
scripts/test-panel.sh
```

The QML lint script uses an import-path shim because Omarchy's `qs.*` imports
need the installed shell source and plugin entry-point names can shadow shared
components. Keep state decisions in pure JavaScript reducers where practical so
they remain testable without a running shell.

## Controller Profiles

Open a [controller support issue](https://github.com/lightqv/omarchy-gamepads/issues/new)
before implementing a profile. Identify the exact controller model, available
connection methods, and whether you can physically test the change. This keeps
work coordinated and prevents duplicate or overly broad profiles.

Keep each pull request focused on one related controller family. A controller
profile is mergeable only when it:

- Implements the contract in [`docs/controller-profile.md`](docs/controller-profile.md).
- Matches on SDL type and, when needed, vendor and product IDs rather than the controller display name.
- Keeps matcher breadth consistent with the tested hardware and advertised support; broad SDL-type matching does not make every matching device physically verified.
- Defines hardware labels, expected buttons and axes, trigger behavior, diagnostic thresholds, and known limitations.
- Includes deterministic profile tests and sanitized replay fixtures under `tests/fixtures/` so reviewers can validate behavior without the hardware.
- Records the exact model, connection method, mapped SDL type, vendor and product IDs, observable capabilities, and relevant Omarchy and SDL versions used during physical verification.
- Physically verifies every connection method claimed as supported and documents untested methods as limitations.
- Passes the repository validation commands and updates user-facing support documentation.

Record physical verification in the pull request using this format:

| Model | VID:PID | SDL type | Connection | Result and limitations |
| --- | --- | --- | --- | --- |
| Exact model | Non-unique IDs | SDL mapping | USB, Bluetooth, or receiver | Observed behavior |

Hardware testers do not need to construct fixtures. Post the non-private fields
and observations requested in the issue; the profile author can convert them
into deterministic protocol messages following
[`docs/backend-protocol.md`](docs/backend-protocol.md). Validate committed
fixtures with the Python and Node.js test commands above.

Draft pull requests may be used to coordinate an implementation awaiting
hardware testing. An unverified profile must not be merged or advertised as
supported.

Do not include controller drivers, root services, custom input permissions,
runtime downloads, unrelated interface changes, or 3D assets in a profile pull
request. Discuss a narrowly matched SDL mapping correction in the issue before
implementing it.

Vendor and product IDs are expected because they identify a model, not one
physical unit. Do not include serial numbers, Bluetooth addresses, usernames,
raw device paths, or unredacted diagnostic reports in fixtures or issues.

## Safety

Do not add root services, exclusive grabs, broad input permissions, runtime
downloads, or persisted hardware identifiers. Changes to helper execution,
protocol validation, report export, or filesystem access require an explicit
security review.

Release work must complete [`docs/release-checklist.md`](docs/release-checklist.md).
