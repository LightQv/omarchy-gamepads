"""SDL3 gamepad backend and versioned NDJSON protocol."""

from __future__ import annotations

import ctypes
import json
import os
from pathlib import Path
import queue
import re
import signal
import stat
import sys
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Iterable, TextIO


PROTOCOL_VERSION = 1
MAX_COMMAND_BYTES = 16_384
MAX_FIXTURE_BYTES = 65_536
MAX_REPLAY_BYTES = 8 * 1024 * 1024
MAX_REPLAY_MESSAGES = 10_000
MAX_CONTROLLERS = 32
MAX_DEFERRED_CONTROLLERS = 32
COMMAND_QUEUE_SIZE = 64
COMMANDS_PER_TICK = 16
MAX_SDL_EVENTS_PER_POLL = 256
AXIS_FLUSH_INTERVAL = 1 / 60
METADATA_REFRESH_INTERVAL = 5.0

BUTTON_NAMES = (
    "south",
    "east",
    "west",
    "north",
    "back",
    "guide",
    "start",
    "left_stick",
    "right_stick",
    "left_shoulder",
    "right_shoulder",
    "dpad_up",
    "dpad_down",
    "dpad_left",
    "dpad_right",
    "misc1",
    "right_paddle1",
    "left_paddle1",
    "right_paddle2",
    "left_paddle2",
    "touchpad",
    "misc2",
    "misc3",
    "misc4",
    "misc5",
    "misc6",
)

AXIS_NAMES = (
    "leftx",
    "lefty",
    "rightx",
    "righty",
    "left_trigger",
    "right_trigger",
)

FORBIDDEN_KEYS = {
    "address",
    "bluetoothaddress",
    "devicepath",
    "mac",
    "path",
    "serial",
    "serialnumber",
    "username",
}

MAC_PATTERN = re.compile(r"(?i)(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}")
DEVICE_PATH_PATTERN = re.compile(r"/dev/(?:input/[A-Za-z0-9._-]+|hidraw[0-9]+)")
HOME_PATTERN = re.compile(r"/home/[^/\s]+")
PRIVATE_PATH_PATTERN = re.compile(r"/(?:root|Users/[^/\s]+|run/user/[0-9]+|sys/(?:class|devices))(?:/[^\s]*)?")
EVENT_PATH_PATTERN = re.compile(r"/dev/input/event[0-9]+")
CONTROLLER_ID_PATTERN = re.compile(r"[1-9][0-9]{0,19}")
CODE_PATTERN = re.compile(r"[a-z][a-z0-9_]{0,63}")
TYPE_NAME_PATTERN = re.compile(r"[a-z0-9][a-z0-9_-]{0,63}")
HEX_ID_PATTERN = re.compile(r"[0-9a-f]{4}")
UNSAFE_TEXT_PATTERN = re.compile(r"[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]")
BATTERY_LEVELS = {"critical", "low", "normal", "high", "full", "unknown"}
BATTERY_STATES = {"charging", "charged", "on_battery", "no_battery", "unknown"}


class ProtocolError(ValueError):
    """Raised when an inbound command or replay message is invalid."""


class DependencyError(RuntimeError):
    """Raised when the SDL runtime cannot be loaded."""


class BackendError(RuntimeError):
    """Raised when SDL cannot initialize."""


def configure_pysdl_environment() -> None:
    """Select the system SDL library and disable PySDL3 network behavior."""
    os.environ["SDL_BINARY_PATH"] = "/usr/lib"
    os.environ["SDL_DISABLE_METADATA"] = "1"
    os.environ["SDL_DOWNLOAD_BINARIES"] = "0"
    os.environ["SDL_CHECK_VERSION"] = "0"
    os.environ["SDL_DOC_GENERATOR"] = "0"
    os.environ["SDL_CHECK_BINARY_VERSION"] = "0"
    os.environ["SDL_LOG_LEVEL"] = "3"


def load_sdl() -> Any:
    """Load PySDL3 only after applying the safe runtime environment."""
    configure_pysdl_environment()
    try:
        from sdl3 import SDL
    except (ImportError, OSError, PermissionError) as error:
        raise DependencyError("SDL3 Python bindings are unavailable.") from error
    try:
        binary = ctypes.CDLL("/usr/lib/libSDL3.so")
        get_mapping = binary.SDL_GetGamepadMappingForID
        get_mapping.argtypes = [ctypes.c_uint32]
        get_mapping.restype = ctypes.c_void_p
        free = binary.SDL_free
        free.argtypes = [ctypes.c_void_p]
        free.restype = None

        def read_mapping(instance_id: int) -> str:
            pointer = get_mapping(instance_id)
            if not pointer:
                return ""
            try:
                return ctypes.string_at(pointer).decode("utf-8", "replace")
            finally:
                free(pointer)

        SDL._omarchy_read_gamepad_mapping = read_mapping
    except (AttributeError, OSError) as error:
        raise DependencyError("The system SDL3 library is unavailable.") from error
    return SDL


def safe_text(value: Any, *, limit: int = 512) -> str:
    """Return bounded text with local hardware and user identifiers removed."""
    if isinstance(value, bytes):
        value = value.decode("utf-8", "replace")
    text = str(value or "")
    text = UNSAFE_TEXT_PATTERN.sub("", text)
    text = MAC_PATTERN.sub("<redacted-address>", text)
    text = DEVICE_PATH_PATTERN.sub("<redacted-device>", text)
    text = HOME_PATTERN.sub("/home/<redacted>", text)
    text = PRIVATE_PATH_PATTERN.sub("<redacted-path>", text)
    return text[:limit]


def sanitize_public(value: Any) -> Any:
    """Recursively remove forbidden fields and redact sensitive string values."""
    if isinstance(value, dict):
        return {
            str(key): sanitize_public(item)
            for key, item in value.items()
            if str(key).replace("_", "").lower() not in FORBIDDEN_KEYS
        }
    if isinstance(value, list):
        return [sanitize_public(item) for item in value]
    if isinstance(value, tuple):
        return [sanitize_public(item) for item in value]
    if isinstance(value, (str, bytes)):
        return safe_text(value)
    return value


def parse_command(line: str) -> dict[str, Any]:
    """Parse and validate one plugin-to-helper command."""
    if len(line.encode("utf-8")) > MAX_COMMAND_BYTES:
        raise ProtocolError("Command exceeds the line-length limit.")
    try:
        command = json.loads(line, parse_constant=_reject_json_constant)
    except (json.JSONDecodeError, RecursionError, ValueError) as error:
        raise ProtocolError("Command is not valid JSON.") from error
    if not isinstance(command, dict):
        raise ProtocolError("Command must be a JSON object.")

    name = command.get("command")
    if name == "snapshot" or name == "shutdown":
        return {"command": name}
    if name == "setStreaming" and type(command.get("enabled")) is bool:
        return {"command": name, "enabled": command["enabled"]}
    if name == "subscribe":
        ids = command.get("ids")
        if not isinstance(ids, list) or len(ids) > 32:
            raise ProtocolError("subscribe.ids must be an array of at most 32 IDs.")
        if any(not isinstance(item, str) or not CONTROLLER_ID_PATTERN.fullmatch(item) for item in ids):
            raise ProtocolError("subscribe.ids contains an invalid controller ID.")
        if len(set(ids)) != len(ids):
            raise ProtocolError("subscribe.ids must not contain duplicates.")
        return {"command": name, "ids": ids}
    raise ProtocolError("Unknown or invalid command.")


def _reject_json_constant(value: str) -> None:
    raise ValueError(f"Invalid JSON constant: {value}")


def _require_keys(value: dict[str, Any], required: set[str]) -> None:
    if set(value) != required:
        raise ProtocolError("Message contains missing or unknown fields.")


def validate_public_message(message: Any) -> None:
    """Validate the stable portions of a protocol version 1 output message."""
    if not isinstance(message, dict) or not isinstance(message.get("type"), str):
        raise ProtocolError("Message must be an object with a type.")
    message_type = message["type"]
    if message_type == "hello":
        _require_keys(message, {"type", "protocol", "backend", "version"})
        if message.get("protocol") != PROTOCOL_VERSION:
            raise ProtocolError("Unsupported protocol version.")
        if (
            message.get("backend") != "sdl3"
            or not isinstance(message.get("version"), str)
            or not re.fullmatch(r"(?:unavailable|[0-9]+\.[0-9]+\.[0-9]+)", message["version"])
        ):
            raise ProtocolError("Invalid hello message.")
        return
    if message_type == "error":
        _require_keys(message, {"type", "code", "message"})
        if (
            not isinstance(message.get("code"), str)
            or not CODE_PATTERN.fullmatch(message["code"])
            or not isinstance(message.get("message"), str)
            or not 1 <= len(message["message"]) <= 512
        ):
            raise ProtocolError("Invalid error message.")
        return
    if type(message.get("sequence")) is not int or message["sequence"] < 1:
        raise ProtocolError("State messages require a positive sequence number.")
    if message_type == "snapshot":
        _require_keys(message, {"type", "sequence", "controllers"})
        if not isinstance(message.get("controllers"), list) or len(message["controllers"]) > 32:
            raise ProtocolError("Invalid snapshot message.")
        for controller in message["controllers"]:
            validate_controller(controller)
        controller_ids = [controller["id"] for controller in message["controllers"]]
        if len(controller_ids) != len(set(controller_ids)):
            raise ProtocolError("Snapshot controller IDs must be unique.")
    elif message_type == "controller":
        _require_keys(message, {"type", "sequence", "controller"})
        validate_controller(message.get("controller"))
    elif message_type == "removed":
        _require_keys(message, {"type", "sequence", "id"})
        validate_controller_id(message.get("id"))
    elif message_type == "input":
        _require_keys(message, {"type", "sequence", "id", "buttons", "axes"})
        validate_controller_id(message.get("id"))
        buttons = message.get("buttons", {})
        axes = message.get("axes", {})
        if not isinstance(buttons, dict) or any(
            key not in BUTTON_NAMES or type(value) is not bool for key, value in buttons.items()
        ):
            raise ProtocolError("Invalid input buttons.")
        if not isinstance(axes, dict) or any(
            key not in AXIS_NAMES
            or not isinstance(value, (int, float))
            or isinstance(value, bool)
            or not (0.0 <= value <= 1.0 if key.endswith("trigger") else -1.0 <= value <= 1.0)
            for key, value in axes.items()
        ):
            raise ProtocolError("Invalid input axes.")
        if not buttons and not axes:
            raise ProtocolError("Input message must contain a delta.")
    else:
        raise ProtocolError("Unknown message type.")


def validate_controller_id(controller_id: Any) -> None:
    if not isinstance(controller_id, str) or not CONTROLLER_ID_PATTERN.fullmatch(controller_id):
        raise ProtocolError("Invalid controller ID.")


def validate_controller(controller: Any) -> None:
    """Validate a public controller object without over-constraining extensions."""
    if not isinstance(controller, dict):
        raise ProtocolError("Controller must be an object.")
    _require_keys(
        controller,
        {
            "id",
            "name",
            "family",
            "sdlType",
            "vendorId",
            "productId",
            "connection",
            "battery",
            "capabilities",
            "buttons",
            "axes",
        },
    )
    validate_controller_id(controller.get("id"))
    if not isinstance(controller.get("name"), str) or not 1 <= len(controller["name"]) <= 128:
        raise ProtocolError("Controller name is required.")
    if UNSAFE_TEXT_PATTERN.search(controller["name"]):
        raise ProtocolError("Controller name contains control characters.")
    if not isinstance(controller.get("family"), str) or not TYPE_NAME_PATTERN.fullmatch(controller["family"]):
        raise ProtocolError("Invalid controller family.")
    if not isinstance(controller.get("sdlType"), str) or not TYPE_NAME_PATTERN.fullmatch(controller["sdlType"]):
        raise ProtocolError("Invalid SDL controller type.")
    if not isinstance(controller.get("vendorId"), str) or not HEX_ID_PATTERN.fullmatch(controller["vendorId"]):
        raise ProtocolError("Invalid controller vendor ID.")
    if not isinstance(controller.get("productId"), str) or not HEX_ID_PATTERN.fullmatch(controller["productId"]):
        raise ProtocolError("Invalid controller product ID.")
    if not isinstance(controller.get("connection"), str) or controller["connection"] not in {
        "wired",
        "wireless",
        "unknown",
    }:
        raise ProtocolError("Invalid controller connection.")
    battery = controller.get("battery")
    if not isinstance(battery, dict) or type(battery.get("available")) is not bool:
        raise ProtocolError("Invalid controller battery.")
    _require_keys(battery, {"available", "percent", "level", "state"})
    percent = battery.get("percent")
    if percent is not None and (type(percent) is not int or not 0 <= percent <= 100):
        raise ProtocolError("Invalid battery percentage.")
    if battery.get("level") is not None and (
        not isinstance(battery["level"], str) or battery["level"] not in BATTERY_LEVELS
    ):
        raise ProtocolError("Invalid battery level.")
    if not isinstance(battery.get("state"), str) or battery["state"] not in BATTERY_STATES:
        raise ProtocolError("Invalid battery state.")
    capabilities = controller.get("capabilities")
    if not isinstance(capabilities, dict):
        raise ProtocolError("Invalid controller capabilities.")
    _require_keys(capabilities, {"buttons", "axes"})
    capability_buttons = capabilities["buttons"]
    capability_axes = capabilities["axes"]
    if (
        not isinstance(capability_buttons, list)
        or len(capability_buttons) > len(BUTTON_NAMES)
        or any(not isinstance(button, str) for button in capability_buttons)
        or len(capability_buttons) != len(set(capability_buttons))
        or any(button not in BUTTON_NAMES for button in capability_buttons)
    ):
        raise ProtocolError("Invalid button capabilities.")
    if (
        not isinstance(capability_axes, list)
        or len(capability_axes) > len(AXIS_NAMES)
        or any(not isinstance(axis, str) for axis in capability_axes)
        or len(capability_axes) != len(set(capability_axes))
        or any(axis not in AXIS_NAMES for axis in capability_axes)
    ):
        raise ProtocolError("Invalid axis capabilities.")
    buttons = controller.get("buttons")
    axes = controller.get("axes")
    if (
        not isinstance(buttons, dict)
        or set(buttons) != set(capability_buttons)
        or any(type(value) is not bool for value in buttons.values())
    ):
        raise ProtocolError("Invalid controller buttons.")
    if not isinstance(axes, dict) or set(axes) != set(capability_axes) or any(
        not isinstance(value, (int, float))
        or isinstance(value, bool)
        or not (0.0 <= value <= 1.0 if key.endswith("trigger") else -1.0 <= value <= 1.0)
        for key, value in axes.items()
    ):
        raise ProtocolError("Invalid controller axes.")


class ProtocolEmitter:
    """Write privacy-filtered protocol messages with monotonic state sequences."""

    def __init__(self, stream: TextIO, clock: Callable[[], float] = time.monotonic) -> None:
        self.stream = stream
        self.clock = clock
        self.sequence = 0
        self.last_errors: dict[tuple[str, str], float] = {}

    def emit(self, message: dict[str, Any]) -> None:
        safe_message = sanitize_public(message)
        validate_public_message(safe_message)
        self.stream.write(json.dumps(safe_message, separators=(",", ":"), sort_keys=True, allow_nan=False) + "\n")
        self.stream.flush()

    def hello(self, version: str) -> None:
        self.emit({"type": "hello", "protocol": PROTOCOL_VERSION, "backend": "sdl3", "version": version})

    def state(self, message_type: str, **fields: Any) -> None:
        self.sequence += 1
        self.emit({"type": message_type, "sequence": self.sequence, **fields})

    def error(self, code: str, message: str) -> None:
        safe_code = re.sub(r"[^a-z0-9_]", "_", code.lower())[:64] or "backend_error"
        safe_message = safe_text(message)
        key = (safe_code, safe_message)
        now = self.clock()
        if now - self.last_errors.get(key, float("-inf")) < 5.0:
            return
        self.last_errors[key] = now
        self.emit({"type": "error", "code": safe_code, "message": safe_message})


@dataclass
class Controller:
    """Internal controller state; path and handle never enter public messages."""

    id: str
    name: str
    family: str
    sdl_type: str
    vendor_id: str
    product_id: str
    connection: str
    battery: dict[str, Any]
    capabilities: dict[str, list[str]]
    buttons: dict[str, bool]
    axes: dict[str, float]
    handle: Any = field(repr=False)
    device_path: str | None = field(default=None, repr=False)

    def public(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "name": self.name,
            "family": self.family,
            "sdlType": self.sdl_type,
            "vendorId": self.vendor_id,
            "productId": self.product_id,
            "connection": self.connection,
            "battery": dict(self.battery),
            "capabilities": {
                "buttons": list(self.capabilities["buttons"]),
                "axes": list(self.capabilities["axes"]),
            },
            "buttons": dict(self.buttons),
            "axes": dict(self.axes),
        }


def normalize_axis(name: str, raw_value: int) -> float:
    """Normalize SDL's signed 16-bit values to the protocol's axis ranges."""
    if name.endswith("trigger"):
        return round(max(0.0, min(1.0, raw_value / 32767.0)), 6)
    divisor = 32768.0 if raw_value < 0 else 32767.0
    return round(max(-1.0, min(1.0, raw_value / divisor)), 6)


def _read_key_values(path: Path, prefix: str = "") -> dict[str, str]:
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except (OSError, ValueError):
        return {}
    values: dict[str, str] = {}
    for line in lines:
        if prefix and not line.startswith(prefix):
            continue
        content = line[len(prefix) :] if prefix else line
        key, separator, value = content.partition("=")
        if separator:
            values[key] = value
    return values


def read_linux_metadata(device_path: str | None) -> tuple[str | None, dict[str, Any] | None]:
    """Read transport and power data correlated to one SDL evdev path."""
    if not device_path or not EVENT_PATH_PATTERN.fullmatch(device_path):
        return None, None

    transport: str | None = None
    try:
        stat_result = os.stat(device_path)
        udev_path = Path("/run/udev/data") / f"c{os.major(stat_result.st_rdev)}:{os.minor(stat_result.st_rdev)}"
        properties = _read_key_values(udev_path, "E:")
        bus = properties.get("ID_BUS", "").lower()
        transport = {"usb": "wired", "bluetooth": "wireless"}.get(bus)
    except OSError:
        pass

    event_name = Path(device_path).name
    try:
        device_node = (Path("/sys/class/input") / event_name / "device").resolve(strict=True)
    except (OSError, RuntimeError):
        return transport, None

    power_data: dict[str, Any] | None = None
    for ancestor in (device_node, *device_node.parents):
        power_directory = ancestor / "power_supply"
        try:
            supplies = sorted(power_directory.iterdir())
        except OSError:
            continue
        for supply in supplies:
            values = _read_key_values(supply / "uevent")
            if values.get("POWER_SUPPLY_TYPE") != "Battery":
                continue
            percent_text = values.get("POWER_SUPPLY_CAPACITY")
            parsed_percent = int(percent_text) if percent_text and percent_text.isdigit() else None
            percent = parsed_percent if parsed_percent is not None and 0 <= parsed_percent <= 100 else None
            level = values.get("POWER_SUPPLY_CAPACITY_LEVEL", "").lower() or None
            if level not in BATTERY_LEVELS:
                level = None
            status = values.get("POWER_SUPPLY_STATUS", "").lower()
            state = {
                "charging": "charging",
                "full": "charged",
                "discharging": "on_battery",
                "not charging": "on_battery",
            }.get(status, "unknown")
            power_data = {
                "available": percent is not None or level is not None or state != "unknown",
                "percent": percent,
                "level": level,
                "state": state,
            }
            break
        if power_data is not None:
            break
    return transport, power_data


class SDLBackend:
    """Own SDL gamepads and translate their events into protocol-ready state."""

    def __init__(
        self,
        sdl: Any | None = None,
        metadata_reader: Callable[[str | None], tuple[str | None, dict[str, Any] | None]] = read_linux_metadata,
        clock: Callable[[], float] = time.monotonic,
    ) -> None:
        self.sdl = sdl or load_sdl()
        self.metadata_reader = metadata_reader
        self.clock = clock
        self.controllers: dict[str, Controller] = {}
        self.deferred_ids: set[int] = set()
        self.pending_events: list[tuple[str, Any]] = []
        self.last_metadata_refresh = clock()
        self.closed = False

        self.sdl.SDL_SetHint(self.sdl.SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, b"1")
        if not self.sdl.SDL_Init(self.sdl.SDL_INIT_GAMEPAD | self.sdl.SDL_INIT_EVENTS):
            self.sdl.SDL_Quit()
            self.closed = True
            raise BackendError("SDL gamepad initialization failed.")
        try:
            self._enumerate()
        except Exception:
            self.close()
            raise

    @property
    def version(self) -> str:
        value = int(self.sdl.SDL_GetVersion())
        return f"{value // 1_000_000}.{value // 1_000 % 1_000}.{value % 1_000}"

    def _enumerate(self) -> None:
        count = ctypes.c_int()
        instance_ids = self.sdl.SDL_GetGamepads(ctypes.byref(count))
        if not instance_ids:
            raise BackendError("SDL gamepad enumeration failed.")
        try:
            for index in range(count.value):
                instance_id = int(instance_ids[index])
                if len(self.controllers) >= MAX_CONTROLLERS:
                    self._defer(instance_id)
                    continue
                self._open(instance_id)
            if self.deferred_ids:
                self.pending_events.append(
                    ("error", ("controller_limit", "Additional gamepads were ignored by the safety limit."))
                )
        finally:
            if instance_ids:
                self.sdl.SDL_free(instance_ids)

    def _open(self, instance_id: int) -> Controller | None:
        controller_id = str(instance_id)
        if controller_id in self.controllers:
            return self.controllers[controller_id]
        if len(self.controllers) >= MAX_CONTROLLERS:
            self._defer(instance_id)
            self.pending_events.append(
                ("error", ("controller_limit", "Additional gamepads were ignored by the safety limit."))
            )
            return None
        if not self.sdl.SDL_IsGamepad(instance_id):
            return None

        self._patch_switch_capture(instance_id)
        handle = self.sdl.SDL_OpenGamepad(instance_id)
        if not handle:
            self.pending_events.append(("error", ("open_failed", "SDL could not open a recognized gamepad.")))
            return None

        try:
            controller = self._build_controller(instance_id, handle)
        except Exception:
            self.sdl.SDL_CloseGamepad(handle)
            raise
        self.controllers[controller_id] = controller
        return controller

    def _defer(self, instance_id: int) -> None:
        if instance_id in self.deferred_ids or len(self.deferred_ids) >= MAX_DEFERRED_CONTROLLERS:
            return
        self.deferred_ids.add(instance_id)

    def _patch_switch_capture(self, instance_id: int) -> None:
        if (
            int(self.sdl.SDL_GetGamepadVendorForID(instance_id)) != 0x057E
            or int(self.sdl.SDL_GetGamepadProductForID(instance_id)) != 0x2009
        ):
            return
        if hasattr(self.sdl, "_omarchy_read_gamepad_mapping"):
            mapping = self.sdl._omarchy_read_gamepad_mapping(instance_id)
        else:
            mapping = _decode(self.sdl.SDL_GetGamepadMappingForID(instance_id))
        if not mapping or "misc1:" in mapping:
            return
        patched = f"{mapping.rstrip(',')},misc1:b4,".encode()
        if not self.sdl.SDL_SetGamepadMapping(instance_id, patched):
            self.pending_events.append(
                ("error", ("mapping_failed", "SDL could not apply the Switch Pro Capture mapping."))
            )

    def _build_controller(self, instance_id: int, handle: Any) -> Controller:
        device_path = _decode(self.sdl.SDL_GetGamepadPath(handle)) or None
        mapped_type = int(self.sdl.SDL_GetGamepadType(handle))
        type_name = (_decode(self.sdl.SDL_GetGamepadStringForType(mapped_type)) or "unknown").lower()
        family = "switch-pro" if mapped_type == self.sdl.SDL_GAMEPAD_TYPE_NINTENDO_SWITCH_PRO else type_name

        supported_buttons = [
            name for index, name in enumerate(BUTTON_NAMES) if self.sdl.SDL_GamepadHasButton(handle, index)
        ]
        supported_axes = [name for index, name in enumerate(AXIS_NAMES) if self.sdl.SDL_GamepadHasAxis(handle, index)]
        buttons = {
            name: bool(self.sdl.SDL_GetGamepadButton(handle, BUTTON_NAMES.index(name)))
            for name in supported_buttons
        }
        axes = {
            name: normalize_axis(name, int(self.sdl.SDL_GetGamepadAxis(handle, AXIS_NAMES.index(name))))
            for name in supported_axes
        }
        connection, battery = self._metadata(handle, device_path)

        return Controller(
            id=str(instance_id),
            name=safe_text(self.sdl.SDL_GetGamepadName(handle), limit=128) or "Unknown gamepad",
            family=family,
            sdl_type=type_name,
            vendor_id=f"{int(self.sdl.SDL_GetGamepadVendor(handle)):04x}",
            product_id=f"{int(self.sdl.SDL_GetGamepadProduct(handle)):04x}",
            connection=connection,
            battery=battery,
            capabilities={"buttons": supported_buttons, "axes": supported_axes},
            buttons=buttons,
            axes=axes,
            handle=handle,
            device_path=device_path,
        )

    def _metadata(self, handle: Any, device_path: str | None) -> tuple[str, dict[str, Any]]:
        connection_value = int(self.sdl.SDL_GetGamepadConnectionState(handle))
        connection = {
            self.sdl.SDL_JOYSTICK_CONNECTION_WIRED: "wired",
            self.sdl.SDL_JOYSTICK_CONNECTION_WIRELESS: "wireless",
        }.get(connection_value, "unknown")

        percent = ctypes.c_int(-1)
        power_value = int(self.sdl.SDL_GetGamepadPowerInfo(handle, ctypes.byref(percent)))
        power_state = {
            self.sdl.SDL_POWERSTATE_ON_BATTERY: "on_battery",
            self.sdl.SDL_POWERSTATE_NO_BATTERY: "no_battery",
            self.sdl.SDL_POWERSTATE_CHARGING: "charging",
            self.sdl.SDL_POWERSTATE_CHARGED: "charged",
        }.get(power_value, "unknown")
        battery = {
            "available": power_state != "unknown" or 0 <= percent.value <= 100,
            "percent": percent.value if 0 <= percent.value <= 100 else None,
            "level": None,
            "state": power_state,
        }

        fallback_connection, fallback_battery = self.metadata_reader(device_path)
        if connection == "unknown" and fallback_connection:
            connection = fallback_connection
        if fallback_battery and power_state != "no_battery":
            if battery["percent"] is None:
                battery["percent"] = fallback_battery.get("percent")
            if battery["level"] is None:
                battery["level"] = fallback_battery.get("level")
            if battery["state"] == "unknown":
                battery["state"] = fallback_battery.get("state", "unknown")
            battery["available"] = (
                battery["percent"] is not None
                or battery["level"] is not None
                or battery["state"] != "unknown"
            )
        return connection, battery

    def poll(self) -> list[tuple[str, Any]]:
        events, self.pending_events = self.pending_events, []
        event = self.sdl.SDL_Event()
        processed = 0
        while processed < MAX_SDL_EVENTS_PER_POLL and self.sdl.SDL_PollEvent(ctypes.byref(event)):
            processed += 1
            event_type = int(event.type)
            if event_type == self.sdl.SDL_EVENT_GAMEPAD_ADDED:
                instance_id = int(event.gdevice.which)
                if str(instance_id) in self.controllers:
                    continue
                controller = self._open(instance_id)
                if controller:
                    events.append(("controller", controller.public()))
            elif event_type == self.sdl.SDL_EVENT_GAMEPAD_REMOVED:
                instance_id = int(event.gdevice.which)
                controller_id = str(instance_id)
                self.deferred_ids.discard(instance_id)
                controller = self.controllers.pop(controller_id, None)
                if controller:
                    self.sdl.SDL_CloseGamepad(controller.handle)
                    events.append(("removed", controller_id))
                    self._admit_deferred(events)
            elif event_type in {self.sdl.SDL_EVENT_GAMEPAD_BUTTON_DOWN, self.sdl.SDL_EVENT_GAMEPAD_BUTTON_UP}:
                controller_id = str(int(event.gbutton.which))
                button_index = int(event.gbutton.button)
                controller = self.controllers.get(controller_id)
                if controller and 0 <= button_index < len(BUTTON_NAMES):
                    name = BUTTON_NAMES[button_index]
                    if name in controller.buttons:
                        value = bool(event.gbutton.down)
                        controller.buttons[name] = value
                        events.append(("input", (controller_id, {name: value}, {})))
            elif event_type == self.sdl.SDL_EVENT_GAMEPAD_AXIS_MOTION:
                controller_id = str(int(event.gaxis.which))
                axis_index = int(event.gaxis.axis)
                controller = self.controllers.get(controller_id)
                if controller and 0 <= axis_index < len(AXIS_NAMES):
                    name = AXIS_NAMES[axis_index]
                    if name in controller.axes:
                        value = normalize_axis(name, int(event.gaxis.value))
                        controller.axes[name] = value
                        events.append(("input", (controller_id, {}, {name: value})))
            elif event_type == self.sdl.SDL_EVENT_GAMEPAD_REMAPPED:
                instance_id = int(event.gdevice.which)
                controller_id = str(instance_id)
                controller = self.controllers.get(controller_id)
                if controller:
                    self._patch_switch_capture(instance_id)
                    rebuilt = self._build_controller(instance_id, controller.handle)
                    self.controllers[controller_id] = rebuilt
                    events.append(("controller", rebuilt.public()))
            elif event_type == self.sdl.SDL_EVENT_JOYSTICK_BATTERY_UPDATED:
                self._refresh_metadata(events, {str(int(event.jbattery.which))})

        if self.clock() - self.last_metadata_refresh >= METADATA_REFRESH_INTERVAL:
            self._refresh_metadata(events)
        return events

    def _admit_deferred(self, events: list[tuple[str, Any]]) -> None:
        for instance_id in sorted(tuple(self.deferred_ids)):
            if len(self.controllers) >= MAX_CONTROLLERS:
                break
            self.deferred_ids.discard(instance_id)
            if not self.sdl.SDL_IsGamepad(instance_id):
                continue
            controller = self._open(instance_id)
            if controller:
                events.append(("controller", controller.public()))

    def _refresh_metadata(
        self,
        events: list[tuple[str, Any]],
        controller_ids: set[str] | None = None,
    ) -> None:
        self.last_metadata_refresh = self.clock()
        for controller in self.controllers.values():
            if controller_ids is not None and controller.id not in controller_ids:
                continue
            connection, battery = self._metadata(controller.handle, controller.device_path)
            if connection != controller.connection or battery != controller.battery:
                controller.connection = connection
                controller.battery = battery
                events.append(("controller", controller.public()))

    def close(self) -> None:
        if self.closed:
            return
        for controller in self.controllers.values():
            self.sdl.SDL_CloseGamepad(controller.handle)
        self.controllers.clear()
        self.deferred_ids.clear()
        self.sdl.SDL_Quit()
        self.closed = True


def _decode(value: Any) -> str:
    if not value:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", "replace")
    return str(value)


class AxisCoalescer:
    """Keep only the latest axis value per controller until the next frame."""

    def __init__(self, interval: float = AXIS_FLUSH_INTERVAL, clock: Callable[[], float] = time.monotonic) -> None:
        self.interval = interval
        self.clock = clock
        self.last_flush = clock()
        self.pending: dict[str, dict[str, float]] = {}

    def add(self, controller_id: str, axes: dict[str, float]) -> None:
        self.pending.setdefault(controller_id, {}).update(axes)

    def drain(self, *, force: bool = False) -> list[tuple[str, dict[str, float]]]:
        now = self.clock()
        if not force and now - self.last_flush < self.interval:
            return []
        values = list(self.pending.items())
        self.pending = {}
        self.last_flush = now
        return values

    def clear(self) -> None:
        self.pending.clear()

    def discard(self, controller_id: str) -> None:
        self.pending.pop(controller_id, None)


class CommandReader(threading.Thread):
    """Read blocking stdin without delaying SDL event processing."""

    def __init__(self, stream: TextIO) -> None:
        super().__init__(daemon=True, name="gamepad-command-reader")
        self.stream = stream
        self.commands: queue.Queue[str | ProtocolError | None] = queue.Queue(maxsize=COMMAND_QUEUE_SIZE)

    def run(self) -> None:
        try:
            stream: Any = getattr(self.stream, "buffer", self.stream)
            while True:
                line = stream.readline(MAX_COMMAND_BYTES + 2)
                if not line:
                    break
                has_newline = line.endswith(b"\n") if isinstance(line, bytes) else line.endswith("\n")
                oversized = len(line) > MAX_COMMAND_BYTES or not has_newline
                if oversized and not has_newline:
                    while line and not has_newline:
                        line = stream.readline(MAX_COMMAND_BYTES + 2)
                        has_newline = line.endswith(b"\n") if isinstance(line, bytes) else line.endswith("\n")
                if oversized:
                    self.commands.put(ProtocolError("Command exceeds the line-length limit."))
                    continue
                if isinstance(line, bytes):
                    try:
                        line = line.decode("utf-8")
                    except UnicodeDecodeError:
                        self.commands.put(ProtocolError("Command is not valid UTF-8."))
                        continue
                self.commands.put(line)
        except (OSError, ValueError):
            self.commands.put(ProtocolError("Command input could not be read."))
        finally:
            self.commands.put(None)


class Helper:
    """Coordinate commands, SDL events, subscriptions, and protocol output."""

    def __init__(self, backend: SDLBackend, emitter: ProtocolEmitter) -> None:
        self.backend = backend
        self.emitter = emitter
        self.streaming = False
        self.subscriptions: set[str] | None = None
        self.axes = AxisCoalescer()
        self.running = True

    def snapshot(self) -> None:
        controllers = [controller.public() for controller in self.backend.controllers.values()]
        self.emitter.state("snapshot", controllers=controllers)

    def handle_command(self, command: dict[str, Any]) -> None:
        name = command["command"]
        if name == "snapshot":
            self.snapshot()
        elif name == "setStreaming":
            self.streaming = command["enabled"]
            if not self.streaming:
                self.axes.clear()
        elif name == "subscribe":
            unknown = set(command["ids"]) - self.backend.controllers.keys()
            if unknown:
                raise ProtocolError("subscribe.ids contains an unknown controller ID.")
            self.subscriptions = set(command["ids"])
            self.axes.clear()
        elif name == "shutdown":
            self.running = False

    def handle_backend_event(self, event_type: str, payload: Any) -> None:
        if event_type == "controller":
            self.axes.discard(payload["id"])
            self.emitter.state("controller", controller=payload)
        elif event_type == "removed":
            self.axes.discard(payload)
            self.emitter.state("removed", id=payload)
            if self.subscriptions is not None:
                self.subscriptions.discard(payload)
        elif event_type == "error":
            self.emitter.error(*payload)
        elif event_type == "input" and self.streaming:
            controller_id, buttons, axes = payload
            if self.subscriptions is not None and controller_id not in self.subscriptions:
                return
            if buttons:
                self.emitter.state("input", id=controller_id, buttons=buttons, axes={})
            if axes:
                self.axes.add(controller_id, axes)

    def flush_axes(self, *, force: bool = False) -> None:
        for controller_id, axes in self.axes.drain(force=force):
            self.emitter.state("input", id=controller_id, buttons={}, axes=axes)


def load_replay(path: Path) -> list[dict[str, Any]]:
    """Load a deterministic fixture containing public protocol messages."""
    try:
        descriptor = os.open(path, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK)
    except OSError as error:
        raise ProtocolError("Replay fixture is not accessible.") from error
    try:
        path_stat = os.fstat(descriptor)
        if not stat.S_ISREG(path_stat.st_mode):
            raise ProtocolError("Replay fixture must be a regular file, not a symlink.")
        if path_stat.st_size > MAX_REPLAY_BYTES:
            raise ProtocolError("Replay fixture exceeds the total-size limit.")
        fixture = os.fdopen(descriptor, "rb")
    except Exception:
        os.close(descriptor)
        raise

    messages: list[dict[str, Any]] = []
    last_sequence = 0
    total_bytes = 0
    with fixture:
        line_number = 0
        while True:
            line = fixture.readline(MAX_FIXTURE_BYTES + 2)
            if not line:
                break
            line_number += 1
            total_bytes += len(line)
            if total_bytes > MAX_REPLAY_BYTES:
                raise ProtocolError("Replay fixture exceeds the total-size limit.")
            if len(line) > MAX_FIXTURE_BYTES or not line.endswith(b"\n"):
                raise ProtocolError(f"Fixture line {line_number} is too long.")
            if not line.strip():
                continue
            try:
                message = json.loads(line, parse_constant=_reject_json_constant)
            except (json.JSONDecodeError, UnicodeDecodeError, RecursionError, ValueError) as error:
                raise ProtocolError(f"Fixture line {line_number} is invalid JSON.") from error
            validate_public_message(message)
            if message.get("type") == "hello" and messages:
                raise ProtocolError("Fixture may contain only one initial hello message.")
            sequence = message.get("sequence")
            if sequence is not None:
                if sequence <= last_sequence:
                    raise ProtocolError("Fixture sequences must increase monotonically.")
                last_sequence = sequence
            if sanitize_public(message) != message:
                raise ProtocolError("Fixture contains private or unsafe data.")
            messages.append(message)
            if len(messages) > MAX_REPLAY_MESSAGES:
                raise ProtocolError("Replay fixture contains too many messages.")
    if not messages or messages[0].get("type") != "hello":
        raise ProtocolError("Fixture must begin with a hello message.")
    if messages[0].get("version") != "unavailable" and (
        len(messages) < 2 or messages[1].get("type") != "snapshot"
    ):
        raise ProtocolError("A successful replay must begin with hello and snapshot messages.")
    state_sequences = [message["sequence"] for message in messages if "sequence" in message]
    if state_sequences and state_sequences[0] != 1:
        raise ProtocolError("The first replay state sequence must be 1.")
    return messages


def replay(path: Path, output: TextIO) -> int:
    for message in load_replay(path):
        output.write(json.dumps(message, separators=(",", ":"), sort_keys=True, allow_nan=False) + "\n")
    output.flush()
    return 0


def run_live(input_stream: TextIO = sys.stdin, output_stream: TextIO = sys.stdout) -> int:
    emitter = ProtocolEmitter(output_stream)
    try:
        backend = SDLBackend()
    except DependencyError:
        emitter.hello("unavailable")
        emitter.error("dependency_missing", "SDL3 Python bindings are unavailable.")
        return 2
    except BackendError:
        emitter.hello("unavailable")
        emitter.error("initialization_failed", "SDL3 gamepad initialization failed.")
        return 3
    except Exception:
        emitter.hello("unavailable")
        emitter.error("initialization_failed", "SDL3 gamepad initialization failed.")
        return 3

    helper = Helper(backend, emitter)
    reader = CommandReader(input_stream)
    stop_requested = threading.Event()

    def request_stop(_signum: int, _frame: Any) -> None:
        stop_requested.set()

    previous_handlers: dict[int, Any] = {}
    if threading.current_thread() is threading.main_thread():
        for signum in (signal.SIGINT, signal.SIGTERM):
            previous_handlers[signum] = signal.signal(signum, request_stop)

    try:
        emitter.hello(backend.version)
        helper.snapshot()
        reader.start()
        while helper.running and not stop_requested.is_set():
            for event_type, payload in backend.poll():
                helper.handle_backend_event(event_type, payload)
            helper.flush_axes()

            for _ in range(COMMANDS_PER_TICK):
                try:
                    line = reader.commands.get_nowait()
                except queue.Empty:
                    break
                if line is None:
                    helper.running = False
                    break
                if isinstance(line, ProtocolError):
                    emitter.error("invalid_command", str(line))
                    continue
                try:
                    helper.handle_command(parse_command(line))
                except ProtocolError as error:
                    emitter.error("invalid_command", str(error))
            time.sleep(0.004 if helper.streaming else 0.02)
        helper.flush_axes(force=True)
        return 0
    finally:
        backend.close()
        for signum, handler in previous_handlers.items():
            signal.signal(signum, handler)
