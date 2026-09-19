# Summary

Describe the change and link its tracking issue when applicable.

## Validation

- [ ] The change is focused and contains no unrelated functionality.
- [ ] I added or updated deterministic tests where behavior changed.
- [ ] I updated user-facing documentation and known limitations where needed.
- [ ] I ran the applicable validation checks in `CONTRIBUTING.md` and listed any omissions below.
- [ ] I removed serial numbers, Bluetooth addresses, usernames, and device paths from logs, fixtures, and reports.

Validation omissions or environment limitations:

## Controller profiles

Delete this section when the pull request does not add or change a controller profile.

- [ ] The linked issue identifies the exact controller model and available connection methods.
- [ ] Matchers use SDL type and, when needed, vendor and product IDs, not display names.
- [ ] Matcher scope is consistent with the tested hardware and advertised support.
- [ ] Tests and replay fixtures cover matching, controls, and diagnostic behavior.
- [ ] Every claimed connection method was physically tested on the stated hardware.
- [ ] Untested methods, unavailable capabilities, and known limitations are documented.
- [ ] The change does not add drivers, privileged setup, runtime downloads, unrelated UI work, or 3D assets.

### Physical verification

| Model | VID:PID | SDL type | Connection | Result and limitations |
| --- | --- | --- | --- | --- |
|  |  |  |  |  |
