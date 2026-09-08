# Backend Protocol Version 1

The helper exchanges newline-delimited JSON over standard input and output. Each line is one UTF-8 JSON object. Standard output is reserved for protocol messages; diagnostics may use standard error.

Protocol version 1 is the stable v1 release contract. Producers emit only documented fields; consumers should ignore unknown optional fields for forward compatibility. New required fields or changed semantics require a new protocol version.

## Startup

The first message is a handshake:

```json
{"backend":"sdl3","protocol":1,"type":"hello","version":"3.4.14"}
```

`version` is the loaded SDL library version. It is `unavailable` when initialization cannot reach SDL. A live successful helper immediately follows the handshake with a full snapshot.

## State Messages

State messages contain a positive, monotonically increasing `sequence` number. Sequence numbers are scoped to one helper process.

Snapshot:

```json
{"controllers":[],"sequence":1,"type":"snapshot"}
```

Controller added or metadata changed:

```json
{"controller":{},"sequence":2,"type":"controller"}
```

Controller removed:

```json
{"id":"12","sequence":3,"type":"removed"}
```

Input delta:

```json
{"axes":{"leftx":0.42},"buttons":{},"id":"12","sequence":4,"type":"input"}
```

Button deltas are emitted immediately while streaming. Axis events are coalesced to at most one latest-value delta per controller and approximately one display frame. Sticks use `[-1.0, 1.0]`; triggers use `[0.0, 1.0]`.

## Controller Object

```json
{
  "id": "12",
  "name": "Nintendo Switch Pro Controller",
  "family": "switch-pro",
  "sdlType": "switchpro",
  "vendorId": "057e",
  "productId": "2009",
  "connection": "wireless",
  "battery": {
    "available": true,
    "percent": null,
    "level": "full",
    "state": "on_battery"
  },
  "capabilities": {
    "buttons": ["south", "misc1"],
    "axes": ["leftx", "lefty"]
  },
  "buttons": {
    "south": false,
    "misc1": false
  },
  "axes": {
    "leftx": 0.0,
    "lefty": 0.0
  }
}
```

- `id` is SDL's decimal instance ID and is valid only for the current connection session.
- `connection` is `wired`, `wireless`, or `unknown`.
- `battery.percent` is an integer from 0 through 100 or `null`.
- `battery.level` is a lower-case kernel capacity level such as `critical`, `low`, `normal`, `high`, or `full`, or `null`.
- `battery.state` is `charging`, `charged`, `on_battery`, `no_battery`, or `unknown`.
- `battery.available` is true when any meaningful power value is available.
- Button names describe physical positions rather than printed labels.
- Capability arrays define which state keys are meaningful for that controller.

SDL is authoritative for controller admission, hotplug, family, and normalized input. Read-only udev and kernel power-supply metadata may supplement unknown SDL transport and power values for the same accepted controller.

## Errors

Errors are unsequenced and do not invalidate prior state:

```json
{"code":"invalid_command","message":"Command is not valid JSON.","type":"error"}
```

Repeated identical errors are limited to one every five seconds. Stable codes currently include:

- `dependency_missing`
- `controller_limit`
- `initialization_failed`
- `invalid_command`
- `mapping_failed`
- `open_failed`

Consumers must handle unknown future error codes.

At most 32 gamepads are admitted at once. Additional devices produce a rate-limited `controller_limit` error and are ignored until capacity is available.

## Commands

Request a full snapshot:

```json
{"command":"snapshot"}
```

Enable or disable input deltas:

```json
{"command":"setStreaming","enabled":true}
```

Restrict input deltas to connected controller IDs. An empty list suppresses all input deltas. Metadata and removal messages remain global.

```json
{"command":"subscribe","ids":["12","15"]}
```

Shut down after flushing queued axis changes:

```json
{"command":"shutdown"}
```

Commands are limited to 16 KiB. Malformed JSON, unknown commands, invalid values, duplicate IDs, and subscriptions to unknown IDs produce a rate-limited `invalid_command` error without terminating the helper.

Closing standard input, `SIGINT`, and `SIGTERM` also request clean shutdown.

## Privacy

The helper does not query controller serial numbers or Bluetooth addresses, and the protocol has no fields for serials, usernames, or raw device paths. The emitter applies a final recursive field allowlist and redacts recognizable addresses and private Linux/macOS paths. Controller names are bounded device-provided product labels and should not be treated as anonymous if a vendor embeds unique text in a product name.

## Replay

Replay fixtures contain the same public messages as live mode, including the initial handshake:

```bash
python scripts/gamepad-helper.py --replay tests/fixtures/switch-pro-usb.ndjson
```

Replay accepts regular, non-symlink files up to 8 MiB and 10,000 messages. It rejects malformed messages, incomplete schemas, unknown fields, non-monotonic state sequences, unsafe fields, and lines over 64 KiB. Valid fixture output is deterministic and exits without accessing SDL or hardware.
