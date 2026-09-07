from __future__ import annotations

import ctypes
import io
import json
import os
from pathlib import Path
import tempfile
import unittest

from scripts.gamepad_backend import (
    AxisCoalescer,
    BackendError,
    CommandReader,
    Controller,
    Helper,
    ProtocolEmitter,
    ProtocolError,
    SDLBackend,
    configure_pysdl_environment,
    load_replay,
    normalize_axis,
    parse_command,
    replay,
    sanitize_public,
)


FIXTURES = Path(__file__).parent / "fixtures"


class FakeDeviceEvent(ctypes.Structure):
    _fields_ = [("type", ctypes.c_uint32), ("which", ctypes.c_int32)]


class FakeEvent(ctypes.Union):
    _fields_ = [("type", ctypes.c_uint32), ("gdevice", FakeDeviceEvent)]


class FakeSDL:
    SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS = b"SDL_JOYSTICK_ALLOW_BACKGROUND_EVENTS"
    SDL_INIT_GAMEPAD = 0x2000
    SDL_INIT_EVENTS = 0x4000
    SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO = 7
    SDL_JOYSTICK_CONNECTION_UNKNOWN = 0
    SDL_JOYSTICK_CONNECTION_WIRED = 1
    SDL_JOYSTICK_CONNECTION_WIRELESS = 2
    SDL_POWERSTATE_UNKNOWN = 0
    SDL_POWERSTATE_ON_BATTERY = 1
    SDL_POWERSTATE_NO_BATTERY = 2
    SDL_POWERSTATE_CHARGING = 3
    SDL_POWERSTATE_CHARGED = 4
    SDL_EVENT_GAMEPAD_AXIS_MOTION = 0x650
    SDL_EVENT_GAMEPAD_BUTTON_DOWN = 0x651
    SDL_EVENT_GAMEPAD_BUTTON_UP = 0x652
    SDL_EVENT_GAMEPAD_ADDED = 0x653
    SDL_EVENT_GAMEPAD_REMOVED = 0x654
    SDL_EVENT_GAMEPAD_REMAPPED = 0x655
    SDL_EVENT_JOYSTICK_BATTERY_UPDATED = 0x607
    SDL_Event = FakeEvent

    def __init__(self) -> None:
        self.ids = (ctypes.c_int32 * 1)(7)
        self.opened: list[int] = []
        self.closed_handles: list[object] = []
        self.mapping: bytes | None = None
        self.quit_called = False
        self.events: list[tuple[int, int]] = []
        self.handle = object()
        self.init_success = True
        self.connection_state = self.SDL_JOYSTICK_CONNECTION_UNKNOWN
        self.power_state = self.SDL_POWERSTATE_UNKNOWN
        self.power_percent = -1
        self.failed_open_ids: set[int] = set()

    def SDL_SetHint(self, _name, _value):
        return True

    def SDL_Init(self, _flags):
        return self.init_success

    def SDL_GetVersion(self):
        return 3_004_014

    def SDL_GetGamepads(self, count):
        count._obj.value = 1
        return self.ids

    def SDL_free(self, _value):
        return None

    def SDL_IsGamepad(self, instance_id):
        return instance_id == 7

    def SDL_GetGamepadVendorForID(self, _instance_id):
        return 0x057E

    def SDL_GetGamepadProductForID(self, _instance_id):
        return 0x2009

    def SDL_GetGamepadMappingForID(self, _instance_id):
        return b"guid,Nintendo Switch Pro Controller,a:b0,platform:Linux,"

    def SDL_SetGamepadMapping(self, _instance_id, mapping):
        self.mapping = mapping
        return True

    def SDL_OpenGamepad(self, instance_id):
        self.opened.append(instance_id)
        if instance_id in self.failed_open_ids:
            return None
        return self.handle

    def SDL_CloseGamepad(self, handle):
        self.closed_handles.append(handle)

    def SDL_GetGamepadPath(self, _handle):
        return b"/dev/input/event9"

    def SDL_GetGamepadType(self, _handle):
        return self.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO

    def SDL_GetGamepadStringForType(self, _gamepad_type):
        return b"switchpro"

    def SDL_GamepadHasButton(self, _handle, index):
        return index in {0, 15}

    def SDL_GamepadHasAxis(self, _handle, index):
        return index in {0, 4}

    def SDL_GetGamepadButton(self, _handle, _index):
        return False

    def SDL_GetGamepadAxis(self, _handle, _index):
        return 0

    def SDL_GetGamepadConnectionState(self, _handle):
        return self.connection_state

    def SDL_GetGamepadPowerInfo(self, _handle, percent):
        percent._obj.value = self.power_percent
        return self.power_state

    def SDL_GetGamepadName(self, _handle):
        return b"Nintendo Switch Pro Controller"

    def SDL_GetGamepadVendor(self, _handle):
        return 0x057E

    def SDL_GetGamepadProduct(self, _handle):
        return 0x2009

    def SDL_PollEvent(self, event):
        if not self.events:
            return False
        event_type, which = self.events.pop(0)
        event._obj.gdevice.type = event_type
        event._obj.gdevice.which = which
        return True

    def SDL_Quit(self):
        self.quit_called = True


def make_controller(controller_id: str = "7") -> Controller:
    return Controller(
        id=controller_id,
        name="Test Controller",
        family="standard",
        sdl_type="standard",
        vendor_id="1234",
        product_id="5678",
        connection="wired",
        battery={"available": False, "percent": None, "level": None, "state": "unknown"},
        capabilities={"buttons": ["south"], "axes": ["leftx"]},
        buttons={"south": False},
        axes={"leftx": 0.0},
        handle=object(),
    )


class EnvironmentTests(unittest.TestCase):
    def test_bootstrap_forces_safe_pysdl_settings(self):
        previous = {key: os.environ.get(key) for key in (
            "SDL_BINARY_PATH",
            "SDL_DISABLE_METADATA",
            "SDL_DOWNLOAD_BINARIES",
            "SDL_CHECK_VERSION",
            "SDL_DOC_GENERATOR",
            "SDL_CHECK_BINARY_VERSION",
            "SDL_LOG_LEVEL",
        )}
        try:
            os.environ["SDL_DOWNLOAD_BINARIES"] = "1"
            os.environ["SDL_CHECK_VERSION"] = "1"
            configure_pysdl_environment()
            self.assertEqual(os.environ["SDL_BINARY_PATH"], "/usr/lib")
            self.assertEqual(os.environ["SDL_DISABLE_METADATA"], "1")
            self.assertEqual(os.environ["SDL_DOWNLOAD_BINARIES"], "0")
            self.assertEqual(os.environ["SDL_CHECK_VERSION"], "0")
            self.assertEqual(os.environ["SDL_DOC_GENERATOR"], "0")
            self.assertEqual(os.environ["SDL_CHECK_BINARY_VERSION"], "0")
            self.assertEqual(os.environ["SDL_LOG_LEVEL"], "3")
        finally:
            for key, value in previous.items():
                if value is None:
                    os.environ.pop(key, None)
                else:
                    os.environ[key] = value


class ProtocolTests(unittest.TestCase):
    def test_parse_supported_commands(self):
        self.assertEqual(parse_command('{"command":"snapshot","ignored":true}'), {"command": "snapshot"})
        self.assertEqual(
            parse_command('{"command":"setStreaming","enabled":true}'),
            {"command": "setStreaming", "enabled": True},
        )
        self.assertEqual(
            parse_command('{"command":"subscribe","ids":["7","12"]}'),
            {"command": "subscribe", "ids": ["7", "12"]},
        )

    def test_rejects_malformed_and_oversized_commands(self):
        invalid = (
            "not-json",
            "[]",
            '{"command":"setStreaming","enabled":1}',
            '{"command":"subscribe","ids":["7","7"]}',
            '{"command":"subscribe","ids":["../../7"]}',
            '{"command":"unknown"}',
            " " * 16_385,
        )
        for line in invalid:
            with self.subTest(line=line[:40]), self.assertRaises(ProtocolError):
                parse_command(line)

    def test_emitter_sequences_and_filters_private_data(self):
        output = io.StringIO()
        emitter = ProtocolEmitter(output)
        emitter.state("snapshot", controllers=[])
        emitter.emit(
            {
                "type": "error",
                "code": "probe",
                "message": "failed at /dev/input/event9 for AA:BB:CC:DD:EE:FF",
                "serial": "secret",
            }
        )
        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(messages[0]["sequence"], 1)
        self.assertNotIn("serial", messages[1])
        self.assertNotIn("/dev/input", messages[1]["message"])
        self.assertNotIn("AA:BB", messages[1]["message"])

    def test_identical_errors_are_rate_limited(self):
        now = [10.0]
        output = io.StringIO()
        emitter = ProtocolEmitter(output, clock=lambda: now[0])
        emitter.error("failure", "same")
        emitter.error("failure", "same")
        now[0] += 5.0
        emitter.error("failure", "same")
        self.assertEqual(len(output.getvalue().splitlines()), 2)

    def test_sanitizer_removes_nested_forbidden_fields(self):
        value = sanitize_public({"device": {"serialNumber": "x", "name": "safe"}})
        self.assertEqual(value, {"device": {"name": "safe"}})

    def test_protocol_rejects_negative_trigger_and_unknown_fields(self):
        output = io.StringIO()
        emitter = ProtocolEmitter(output)
        with self.assertRaises(ProtocolError):
            emitter.state("input", id="7", buttons={}, axes={"left_trigger": -0.1})
        with self.assertRaises(ProtocolError):
            emitter.emit({"type": "error", "code": "failure", "message": "bad", "owner": "alice"})

    def test_command_reader_bounds_oversized_frames(self):
        reader = CommandReader(io.BytesIO(b"x" * 20_000 + b"\n"))
        reader.start()
        first = reader.commands.get(timeout=1)
        self.assertIsInstance(first, ProtocolError)
        self.assertIsNone(reader.commands.get(timeout=1))


class AxisTests(unittest.TestCase):
    def test_normalization_clamps_sticks_and_triggers(self):
        self.assertEqual(normalize_axis("leftx", -32768), -1.0)
        self.assertEqual(normalize_axis("leftx", 32767), 1.0)
        self.assertEqual(normalize_axis("left_trigger", -32768), 0.0)
        self.assertEqual(normalize_axis("left_trigger", 32767), 1.0)

    def test_coalescer_retains_latest_axis_value(self):
        now = [0.0]
        coalescer = AxisCoalescer(interval=0.1, clock=lambda: now[0])
        coalescer.add("7", {"leftx": 0.1})
        coalescer.add("7", {"leftx": 0.8, "lefty": -0.5})
        self.assertEqual(coalescer.drain(), [])
        now[0] = 0.1
        self.assertEqual(coalescer.drain(), [("7", {"leftx": 0.8, "lefty": -0.5})])


class SDLBackendTests(unittest.TestCase):
    def test_enumerates_mapped_gamepads_patches_capture_and_cleans_up(self):
        fake = FakeSDL()
        observed_paths: list[str | None] = []

        def metadata(path):
            observed_paths.append(path)
            return "wired", {"available": True, "percent": None, "level": "full", "state": "charging"}

        backend = SDLBackend(sdl=fake, metadata_reader=metadata)
        controller = backend.controllers["7"]
        public = controller.public()

        self.assertEqual(fake.opened, [7])
        self.assertIn(b"misc1:b4", fake.mapping)
        self.assertEqual(observed_paths, ["/dev/input/event9"])
        self.assertEqual(public["connection"], "wired")
        self.assertEqual(public["battery"]["state"], "charging")
        self.assertEqual(public["capabilities"]["buttons"], ["south", "misc1"])
        self.assertNotIn("device_path", public)
        self.assertNotIn("handle", public)

        backend.close()
        backend.close()
        self.assertEqual(fake.closed_handles, [fake.handle])
        self.assertTrue(fake.quit_called)

    def test_unknown_removal_event_does_not_crash(self):
        fake = FakeSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        fake.events.append((fake.SDL_EVENT_GAMEPAD_REMOVED, 999))
        self.assertEqual(backend.poll(), [])
        backend.close()

    def test_queued_initial_add_does_not_emit_duplicate(self):
        fake = FakeSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        fake.events.append((fake.SDL_EVENT_GAMEPAD_ADDED, 7))
        self.assertEqual(backend.poll(), [])
        self.assertEqual(fake.opened, [7])
        backend.close()

    def test_remap_rebuilds_and_emits_controller_state(self):
        fake = FakeSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        fake.events.append((fake.SDL_EVENT_GAMEPAD_REMAPPED, 7))
        events = backend.poll()
        self.assertEqual(events[0][0], "controller")
        self.assertEqual(events[0][1]["id"], "7")
        backend.close()

    def test_partial_sdl_power_merges_kernel_capacity_level(self):
        fake = FakeSDL()
        fake.power_state = fake.SDL_POWERSTATE_CHARGING
        backend = SDLBackend(
            sdl=fake,
            metadata_reader=lambda _path: (
                "wired",
                {"available": True, "percent": None, "level": "full", "state": "charging"},
            ),
        )
        self.assertEqual(backend.controllers["7"].battery["state"], "charging")
        self.assertEqual(backend.controllers["7"].battery["level"], "full")
        backend.close()

    def test_failed_initialization_quits_sdl(self):
        fake = FakeSDL()
        fake.init_success = False
        with self.assertRaises(BackendError):
            SDLBackend(sdl=fake)
        self.assertTrue(fake.quit_called)

    def test_failed_enumeration_quits_sdl(self):
        class FailedEnumerationSDL(FakeSDL):
            def SDL_GetGamepads(self, count):
                count._obj.value = 0
                return None

        fake = FailedEnumerationSDL()
        with self.assertRaises(BackendError):
            SDLBackend(sdl=fake)
        self.assertTrue(fake.quit_called)

    def test_enumeration_enforces_controller_limit(self):
        class ManyGamepadsSDL(FakeSDL):
            def __init__(self):
                super().__init__()
                self.ids = (ctypes.c_int32 * 33)(*range(1, 34))

            def SDL_GetGamepads(self, count):
                count._obj.value = 33
                return self.ids

            def SDL_IsGamepad(self, _instance_id):
                return True

        fake = ManyGamepadsSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        self.assertEqual(len(backend.controllers), 32)
        self.assertEqual(backend.deferred_ids, {33})
        self.assertEqual(backend.pending_events[0][1][0], "controller_limit")
        backend.close()

    def test_removal_admits_deferred_controller(self):
        class ManyGamepadsSDL(FakeSDL):
            def __init__(self):
                super().__init__()
                self.ids = (ctypes.c_int32 * 33)(*range(1, 34))

            def SDL_GetGamepads(self, count):
                count._obj.value = 33
                return self.ids

            def SDL_IsGamepad(self, _instance_id):
                return True

        fake = ManyGamepadsSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        fake.events.append((fake.SDL_EVENT_GAMEPAD_REMOVED, 1))
        events = backend.poll()
        self.assertEqual([event[0] for event in events[-2:]], ["removed", "controller"])
        self.assertIn("33", backend.controllers)
        self.assertEqual(len(backend.controllers), 32)
        backend.close()

    def test_open_failure_does_not_consume_controller_capacity(self):
        class ManyGamepadsSDL(FakeSDL):
            def __init__(self):
                super().__init__()
                self.ids = (ctypes.c_int32 * 33)(*range(1, 34))
                self.failed_open_ids = {1}

            def SDL_GetGamepads(self, count):
                count._obj.value = 33
                return self.ids

            def SDL_IsGamepad(self, _instance_id):
                return True

        fake = ManyGamepadsSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        self.assertEqual(len(backend.controllers), 32)
        self.assertNotIn("1", backend.controllers)
        self.assertIn("33", backend.controllers)
        self.assertFalse(backend.deferred_ids)
        backend.close()

    def test_poll_has_a_fixed_event_budget(self):
        fake = FakeSDL()
        backend = SDLBackend(sdl=fake, metadata_reader=lambda _path: (None, None))
        fake.events.extend((fake.SDL_EVENT_GAMEPAD_REMOVED, 999) for _ in range(300))
        self.assertEqual(backend.poll(), [])
        self.assertEqual(len(fake.events), 44)
        backend.close()


class HelperTests(unittest.TestCase):
    def test_streaming_filters_and_coalesces_input(self):
        class Backend:
            controllers = {"7": make_controller("7"), "8": make_controller("8")}

        output = io.StringIO()
        helper = Helper(Backend(), ProtocolEmitter(output))
        helper.handle_command({"command": "setStreaming", "enabled": True})
        helper.handle_command({"command": "subscribe", "ids": ["7"]})
        helper.handle_backend_event("input", ("8", {"south": True}, {}))
        helper.handle_backend_event("input", ("7", {"south": True}, {}))
        helper.handle_backend_event("input", ("7", {}, {"leftx": 0.25}))
        helper.flush_axes(force=True)
        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual(len(messages), 2)
        self.assertEqual(messages[0]["buttons"], {"south": True})
        self.assertEqual(messages[1]["axes"], {"leftx": 0.25})

    def test_subscribe_rejects_unknown_controller(self):
        class Backend:
            controllers = {"7": make_controller()}

        helper = Helper(Backend(), ProtocolEmitter(io.StringIO()))
        with self.assertRaises(ProtocolError):
            helper.handle_command({"command": "subscribe", "ids": ["8"]})

    def test_removal_discards_buffered_axis_input(self):
        class Backend:
            controllers = {"7": make_controller()}

        output = io.StringIO()
        helper = Helper(Backend(), ProtocolEmitter(output))
        helper.handle_command({"command": "setStreaming", "enabled": True})
        helper.handle_backend_event("input", ("7", {}, {"leftx": 0.5}))
        helper.handle_backend_event("removed", "7")
        helper.flush_axes(force=True)
        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([message["type"] for message in messages], ["removed"])

    def test_controller_rebuild_discards_buffered_axis_input(self):
        class Backend:
            controllers = {"7": make_controller()}

        output = io.StringIO()
        helper = Helper(Backend(), ProtocolEmitter(output))
        helper.handle_command({"command": "setStreaming", "enabled": True})
        helper.handle_backend_event("input", ("7", {}, {"leftx": 0.5}))
        helper.handle_backend_event("controller", make_controller().public())
        helper.flush_axes(force=True)
        messages = [json.loads(line) for line in output.getvalue().splitlines()]
        self.assertEqual([message["type"] for message in messages], ["controller"])


class ReplayTests(unittest.TestCase):
    def test_all_committed_fixtures_are_valid_and_deterministic(self):
        fixture_paths = sorted(FIXTURES.glob("*.ndjson"))
        self.assertGreaterEqual(len(fixture_paths), 6)
        for path in fixture_paths:
            with self.subTest(path=path.name):
                messages = load_replay(path)
                output = io.StringIO()
                replay(path, output)
                expected = "".join(
                    json.dumps(message, separators=(",", ":"), sort_keys=True) + "\n"
                    for message in messages
                )
                self.assertEqual(output.getvalue(), expected)

    def test_replay_rejects_non_monotonic_sequences(self):
        content = (
            '{"type":"hello","protocol":1,"backend":"sdl3","version":"3.4.14"}\n'
            '{"type":"snapshot","sequence":2,"controllers":[]}\n'
            '{"type":"snapshot","sequence":2,"controllers":[]}\n'
        )
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "invalid.ndjson"
            path.write_text(content, encoding="utf-8")
            with self.assertRaises(ProtocolError):
                load_replay(path)

    def test_replay_rejects_symlinks(self):
        with tempfile.TemporaryDirectory() as directory:
            link = Path(directory) / "fixture.ndjson"
            link.symlink_to(FIXTURES / "no-controller.ndjson")
            with self.assertRaises(ProtocolError):
                load_replay(link)

    def test_replay_rejects_boolean_sequence_repeated_hello_and_duplicate_ids(self):
        hello = '{"type":"hello","protocol":1,"backend":"sdl3","version":"3.4.14"}'
        controller = make_controller().public()
        invalid_messages = (
            [json.loads(hello), {"type": "snapshot", "sequence": True, "controllers": []}],
            [json.loads(hello), {"type": "snapshot", "sequence": 1, "controllers": []}, json.loads(hello)],
            [json.loads(hello), {"type": "snapshot", "sequence": 1, "controllers": [controller, controller]}],
        )
        with tempfile.TemporaryDirectory() as directory:
            for index, messages in enumerate(invalid_messages):
                path = Path(directory) / f"invalid-{index}.ndjson"
                path.write_text(
                    "".join(json.dumps(message, separators=(",", ":")) + "\n" for message in messages),
                    encoding="utf-8",
                )
                with self.subTest(index=index), self.assertRaises(ProtocolError):
                    load_replay(path)


if __name__ == "__main__":
    unittest.main()
