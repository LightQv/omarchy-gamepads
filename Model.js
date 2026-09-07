"use strict";

var MAX_CONTROLLERS = 32;
var MAX_NAME_LENGTH = 128;
var BUTTON_NAMES = [
  "south", "east", "west", "north", "back", "guide", "start",
  "left_stick", "right_stick", "left_shoulder", "right_shoulder",
  "dpad_up", "dpad_down", "dpad_left", "dpad_right", "misc1",
  "right_paddle1", "left_paddle1", "right_paddle2", "left_paddle2",
  "touchpad", "misc2", "misc3", "misc4", "misc5", "misc6"
];
var AXIS_NAMES = ["leftx", "lefty", "rightx", "righty", "left_trigger", "right_trigger"];
var TYPE_NAME_PATTERN = /^[a-z0-9][a-z0-9_-]{0,63}$/;
var CODE_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;
var UNSAFE_TEXT_PATTERN = /[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/;

function initialState() {
  return {
    status: "starting",
    backendVersion: "",
    helloAccepted: false,
    snapshotAccepted: false,
    lastSequence: 0,
    controllers: [],
    selectedId: "",
    lastErrorCode: "",
    lastErrorMessage: ""
  };
}

function isObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isFiniteNumber(value) {
  return typeof value === "number" && isFinite(value);
}

function copyObject(value) {
  var result = Object.create(null);
  var keys = Object.keys(value);
  for (var i = 0; i < keys.length; i++) result[keys[i]] = value[keys[i]];
  return result;
}

function nameMap(names) {
  var result = Object.create(null);
  for (var i = 0; i < names.length; i++) result[names[i]] = true;
  return result;
}

function hasOwn(value, key) {
  return Object.prototype.hasOwnProperty.call(value, key);
}

function copyState(state) {
  return {
    status: state.status,
    backendVersion: state.backendVersion,
    helloAccepted: state.helloAccepted,
    snapshotAccepted: state.snapshotAccepted,
    lastSequence: state.lastSequence,
    controllers: state.controllers.slice(),
    selectedId: state.selectedId,
    lastErrorCode: state.lastErrorCode,
    lastErrorMessage: state.lastErrorMessage
  };
}

function accepted(state) {
  return { accepted: true, error: "", state: state };
}

function rejected(state, error) {
  return { accepted: false, error: error, state: state };
}

function validString(value, maximum, allowEmpty) {
  return typeof value === "string"
    && value.length <= maximum
    && (allowEmpty || value.length > 0);
}

function validId(value) {
  return typeof value === "string" && /^[1-9][0-9]{0,19}$/.test(value);
}

function validControlList(value, allowed) {
  if (!Array.isArray(value) || value.length > allowed.length) return false;
  var allowedNames = nameMap(allowed);
  var seen = Object.create(null);
  for (var i = 0; i < value.length; i++) {
    var name = value[i];
    if (typeof name !== "string" || !hasOwn(allowedNames, name) || hasOwn(seen, name)) return false;
    seen[name] = true;
  }
  return true;
}

function axisInRange(name, value) {
  if (!isFiniteNumber(value)) return false;
  return name.indexOf("trigger") !== -1
    ? value >= 0 && value <= 1
    : value >= -1 && value <= 1;
}

function normalizedController(raw) {
  if (!isObject(raw) || !validId(raw.id) || !validString(raw.name, MAX_NAME_LENGTH, false)) return null;
  if (UNSAFE_TEXT_PATTERN.test(raw.name)) return null;
  if (typeof raw.family !== "string" || !TYPE_NAME_PATTERN.test(raw.family)) return null;
  if (typeof raw.sdlType !== "string" || !TYPE_NAME_PATTERN.test(raw.sdlType)) return null;
  if (typeof raw.vendorId !== "string" || !/^[0-9a-f]{4}$/.test(raw.vendorId)) return null;
  if (typeof raw.productId !== "string" || !/^[0-9a-f]{4}$/.test(raw.productId)) return null;
  if (["wired", "wireless", "unknown"].indexOf(raw.connection) === -1) return null;
  if (!isObject(raw.battery) || typeof raw.battery.available !== "boolean") return null;
  if (raw.battery.percent !== null
      && (!Number.isInteger(raw.battery.percent) || raw.battery.percent < 0 || raw.battery.percent > 100)) return null;
  if (raw.battery.level !== null
      && ["critical", "low", "normal", "high", "full", "unknown"].indexOf(raw.battery.level) === -1) return null;
  if (["charging", "charged", "on_battery", "no_battery", "unknown"].indexOf(raw.battery.state) === -1) return null;
  if (!isObject(raw.capabilities)
      || !validControlList(raw.capabilities.buttons, BUTTON_NAMES)
      || !validControlList(raw.capabilities.axes, AXIS_NAMES)) return null;
  if (!isObject(raw.buttons) || !isObject(raw.axes)) return null;

  var buttonCapabilities = nameMap(raw.capabilities.buttons);
  var buttons = Object.create(null);
  var i;
  var buttonKeys = Object.keys(raw.buttons);
  if (buttonKeys.length !== raw.capabilities.buttons.length) return null;
  for (i = 0; i < buttonKeys.length; i++) {
    var button = buttonKeys[i];
    if (!hasOwn(buttonCapabilities, button) || typeof raw.buttons[button] !== "boolean") return null;
    buttons[button] = raw.buttons[button];
  }

  var axisCapabilities = nameMap(raw.capabilities.axes);
  var axes = Object.create(null);
  var axisKeys = Object.keys(raw.axes);
  if (axisKeys.length !== raw.capabilities.axes.length) return null;
  for (i = 0; i < axisKeys.length; i++) {
    var axis = axisKeys[i];
    if (!hasOwn(axisCapabilities, axis) || !axisInRange(axis, raw.axes[axis])) return null;
    axes[axis] = raw.axes[axis];
  }

  return {
    id: raw.id,
    name: raw.name,
    family: raw.family,
    sdlType: raw.sdlType,
    vendorId: raw.vendorId,
    productId: raw.productId,
    connection: raw.connection,
    battery: {
      available: raw.battery.available,
      percent: raw.battery.percent,
      level: raw.battery.level,
      state: raw.battery.state
    },
    capabilities: {
      buttons: raw.capabilities.buttons.slice(),
      axes: raw.capabilities.axes.slice()
    },
    buttons: buttons,
    axes: axes
  };
}

function controllerIndex(controllers, id) {
  for (var i = 0; i < controllers.length; i++) {
    if (controllers[i].id === id) return i;
  }
  return -1;
}

function normalizeSelection(state, previousIndex) {
  if (controllerIndex(state.controllers, state.selectedId) !== -1) return;
  if (state.controllers.length === 0) {
    state.selectedId = "";
    return;
  }
  var index = previousIndex === undefined ? 0 : Math.min(previousIndex, state.controllers.length - 1);
  state.selectedId = state.controllers[Math.max(0, index)].id;
}

function reduceHello(state, message) {
  if (state.helloAccepted) return rejected(state, "duplicate hello");
  if (message.backend !== "sdl3" || message.protocol !== 1 || typeof message.version !== "string"
      || !/^(?:unavailable|[0-9]+\.[0-9]+\.[0-9]+)$/.test(message.version))
    return rejected(state, "unsupported backend handshake");
  var next = copyState(state);
  next.helloAccepted = true;
  next.backendVersion = message.version;
  return accepted(next);
}

function reduceError(state, message) {
  if (!state.helloAccepted) return rejected(state, "error before hello");
  if (typeof message.code !== "string" || !CODE_PATTERN.test(message.code)
      || !validString(message.message, 512, false) || UNSAFE_TEXT_PATTERN.test(message.message))
    return rejected(state, "invalid error message");
  var next = copyState(state);
  next.lastErrorCode = message.code;
  next.lastErrorMessage = message.message;
  if (message.code === "dependency_missing") next.status = "dependency-error";
  return accepted(next);
}

function validateSequence(state, message) {
  return Number.isSafeInteger(message.sequence)
    && message.sequence > 0
    && message.sequence > state.lastSequence;
}

function reduceSnapshot(state, message) {
  if (!Array.isArray(message.controllers) || message.controllers.length > MAX_CONTROLLERS)
    return rejected(state, "invalid snapshot");
  var controllers = [];
  var ids = Object.create(null);
  for (var i = 0; i < message.controllers.length; i++) {
    var controller = normalizedController(message.controllers[i]);
    if (!controller || hasOwn(ids, controller.id)) return rejected(state, "invalid snapshot controller");
    ids[controller.id] = true;
    controllers.push(controller);
  }
  var next = copyState(state);
  next.controllers = controllers;
  next.snapshotAccepted = true;
  next.lastSequence = message.sequence;
  next.status = "ready";
  normalizeSelection(next);
  return accepted(next);
}

function reduceController(state, message) {
  var controller = normalizedController(message.controller);
  if (!controller) return rejected(state, "invalid controller");
  var next = copyState(state);
  var index = controllerIndex(next.controllers, controller.id);
  if (index === -1) {
    if (next.controllers.length >= MAX_CONTROLLERS) return rejected(state, "controller limit exceeded");
    next.controllers.push(controller);
  } else {
    next.controllers[index] = controller;
  }
  next.lastSequence = message.sequence;
  normalizeSelection(next);
  return accepted(next);
}

function reduceRemoved(state, message) {
  if (!validId(message.id)) return rejected(state, "invalid removed controller id");
  var next = copyState(state);
  var index = controllerIndex(next.controllers, message.id);
  if (index !== -1) next.controllers.splice(index, 1);
  next.lastSequence = message.sequence;
  normalizeSelection(next, index === -1 ? undefined : index);
  return accepted(next);
}

function reduceInput(state, message) {
  if (!validId(message.id) || !isObject(message.buttons) || !isObject(message.axes))
    return rejected(state, "invalid input message");
  var index = controllerIndex(state.controllers, message.id);
  if (index === -1) return rejected(state, "input for unknown controller");
  var current = state.controllers[index];
  var buttons = copyObject(current.buttons);
  var axes = copyObject(current.axes);
  var allowedButtons = nameMap(current.capabilities.buttons);
  var allowedAxes = nameMap(current.capabilities.axes);
  var i;
  var buttonKeys = Object.keys(message.buttons);
  var axisKeys = Object.keys(message.axes);
  if (buttonKeys.length === 0 && axisKeys.length === 0) return rejected(state, "empty input delta");
  for (i = 0; i < buttonKeys.length; i++) {
    var button = buttonKeys[i];
    if (!hasOwn(allowedButtons, button) || typeof message.buttons[button] !== "boolean")
      return rejected(state, "invalid button delta");
    buttons[button] = message.buttons[button];
  }
  for (i = 0; i < axisKeys.length; i++) {
    var axis = axisKeys[i];
    if (!hasOwn(allowedAxes, axis) || !axisInRange(axis, message.axes[axis]))
      return rejected(state, "invalid axis delta");
    axes[axis] = message.axes[axis];
  }
  var updated = copyObject(current);
  updated.buttons = buttons;
  updated.axes = axes;
  var next = copyState(state);
  next.controllers[index] = updated;
  next.lastSequence = message.sequence;
  return accepted(next);
}

function reduceMessage(state, message) {
  if (!isObject(state) || !isObject(message) || typeof message.type !== "string")
    return rejected(state, "message is not an object");
  if (message.type === "hello") return reduceHello(state, message);
  if (message.type === "error") return reduceError(state, message);
  if (!state.helloAccepted) return rejected(state, "state message before hello");
  if (!validateSequence(state, message)) return rejected(state, "invalid sequence");
  if (!state.snapshotAccepted && message.type !== "snapshot") return rejected(state, "state message before snapshot");
  if (message.type === "snapshot") return reduceSnapshot(state, message);
  if (message.type === "controller") return reduceController(state, message);
  if (message.type === "removed") return reduceRemoved(state, message);
  if (message.type === "input") return reduceInput(state, message);
  return rejected(state, "unknown message type");
}

function selectController(state, id) {
  if (controllerIndex(state.controllers, id) === -1) return state;
  var next = copyState(state);
  next.selectedId = id;
  return next;
}

function cycleSelection(state, delta) {
  if (state.controllers.length === 0) return state;
  var index = controllerIndex(state.controllers, state.selectedId);
  if (index < 0) index = 0;
  var step = delta < 0 ? -1 : 1;
  var nextIndex = (index + step + state.controllers.length) % state.controllers.length;
  return selectController(state, state.controllers[nextIndex].id);
}

function selectedController(state) {
  var index = controllerIndex(state.controllers, state.selectedId);
  return index === -1 ? null : state.controllers[index];
}

function batteryLabel(controller) {
  if (!controller || !controller.battery || !controller.battery.available) return "Battery unavailable";
  if (controller.battery.percent !== null) return controller.battery.percent + "%";
  if (controller.battery.level) {
    var level = controller.battery.level.replace(/_/g, " ");
    return level.charAt(0).toUpperCase() + level.slice(1);
  }
  return "Battery available";
}

function batteryStateLabel(controller) {
  if (!controller || !controller.battery || !controller.battery.available) return "";
  if (controller.battery.state === "charging") return "Charging";
  if (controller.battery.state === "charged") return "Charged";
  if (controller.battery.state === "on_battery") return "On battery";
  if (controller.battery.state === "no_battery") return "No battery";
  return "Power state unknown";
}

function batteryFraction(controller) {
  if (!controller || !controller.battery || !controller.battery.available) return -1;
  if (controller.battery.percent !== null) return controller.battery.percent / 100;
  var fractions = { critical: 0.1, low: 0.2, normal: 0.5, high: 0.8, full: 1 };
  return hasOwn(fractions, controller.battery.level) ? fractions[controller.battery.level] : -1;
}

function batteryIsLow(controller) {
  if (!controller || !controller.battery || !controller.battery.available) return false;
  if (controller.battery.percent !== null) return controller.battery.percent <= 20;
  return controller.battery.level === "critical" || controller.battery.level === "low";
}

function connectionLabel(controller) {
  if (!controller) return "Unknown connection";
  if (controller.connection === "wired") return "Wired";
  if (controller.connection === "wireless") return "Wireless";
  return "Unknown connection";
}
