"use strict";

var DIAGNOSTIC_STATUSES = ["passed", "warning", "not_detected", "incomplete", "unavailable"];
var DIAGNOSTIC_PHASES = [
  "idle", "baseline_waiting", "baseline_capturing", "digital",
  "analog_left", "analog_right", "review"
];
var REPORT_THRESHOLD_NAMES = [
  "baselineDurationMs", "digitalTriggerPress", "digitalTriggerRelease",
  "centerOffsetWarning", "neutralJitterWarning", "minimumPositiveRange",
  "minimumNegativeRange", "movementDetection"
];
var REPORT_WARNING_CODES = [
  "controller_limit", "dependency_missing", "initialization_failed",
  "mapping_failed", "open_failed", "unsupported_device"
];

function diagnosticInitialState() {
  return {
    phase: "idle",
    status: "incomplete",
    connected: false,
    interrupted: false,
    controllerId: "",
    controller: {},
    profileId: "",
    profileName: "",
    labels: {},
    retryTarget: "",
    thresholds: {},
    digitalControls: [],
    analogControls: [],
    results: {},
    baseline: { samples: 0, held: {}, axes: {} },
    currentButtons: {},
    currentAxes: {}
  };
}

function hasOwn(value, key) {
  return value !== null && value !== undefined
    && Object.prototype.hasOwnProperty.call(value, key);
}

function plainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}

function copyMap(value) {
  var result = {};
  var source = plainObject(value) ? value : {};
  var keys = Object.keys(source);
  for (var i = 0; i < keys.length; i++) result[keys[i]] = source[keys[i]];
  return result;
}

function copyResults(results) {
  var copied = {};
  var keys = Object.keys(results || {});
  for (var i = 0; i < keys.length; i++) {
    var item = results[keys[i]];
    copied[keys[i]] = {
      control: item.control,
      kind: item.kind,
      status: item.status,
      available: item.available,
      offered: item.offered,
      pressed: item.pressed,
      released: item.released,
      baselineHeld: item.baselineHeld,
      center: item.center,
      noise: item.noise,
      minimum: item.minimum,
      maximum: item.maximum,
      negative: item.negative,
      positive: item.positive,
      samples: item.samples
    };
  }
  return copied;
}

function copyBaseline(baseline) {
  var axes = {};
  var keys = Object.keys((baseline || {}).axes || {});
  for (var i = 0; i < keys.length; i++) {
    var metric = baseline.axes[keys[i]];
    axes[keys[i]] = {
      count: metric.count,
      sum: metric.sum,
      minimum: metric.minimum,
      maximum: metric.maximum
    };
  }
  return {
    samples: Number((baseline || {}).samples || 0),
    held: copyMap((baseline || {}).held),
    axes: axes
  };
}

function copyDiagnosticState(state) {
  return {
    phase: state.phase,
    status: state.status,
    connected: state.connected,
    interrupted: state.interrupted,
    controllerId: state.controllerId,
    controller: copyMap(state.controller),
    profileId: state.profileId,
    profileName: state.profileName,
    labels: copyMap(state.labels),
    retryTarget: state.retryTarget,
    thresholds: copyMap(state.thresholds),
    digitalControls: state.digitalControls.slice(),
    analogControls: state.analogControls.slice(),
    results: copyResults(state.results),
    baseline: copyBaseline(state.baseline),
    currentButtons: copyMap(state.currentButtons),
    currentAxes: copyMap(state.currentAxes)
  };
}

function stringList(value) {
  if (!Array.isArray(value)) return [];
  var result = [];
  for (var i = 0; i < value.length; i++) {
    if (typeof value[i] === "string" && result.indexOf(value[i]) === -1) result.push(value[i]);
  }
  return result;
}

function availableMap(controller, kind) {
  var capabilities = plainObject(controller.capabilities) ? controller.capabilities : {};
  return stringList(capabilities[kind]);
}

function threshold(state, name, fallback) {
  var value = Number((state.thresholds || {})[name]);
  return isFinite(value) ? value : fallback;
}

function digitalResult(control, available) {
  return {
    control: control,
    kind: "digital",
    status: available ? "incomplete" : "unavailable",
    available: available,
    offered: false,
    pressed: false,
    released: false,
    baselineHeld: false,
    center: null,
    noise: null,
    minimum: null,
    maximum: null,
    negative: false,
    positive: false,
    samples: 0
  };
}

function analogResult(control, available) {
  var result = digitalResult(control, available);
  result.kind = "analog";
  return result;
}

function startSession(controller, profile) {
  if (!plainObject(controller) || typeof controller.id !== "string"
      || !plainObject(profile) || typeof profile.id !== "string") return diagnosticInitialState();

  var state = diagnosticInitialState();
  var expectedButtons = stringList(profile.expectedButtons);
  var expectedAxes = stringList(profile.expectedAxes);
  var buttonCapabilities = availableMap(controller, "buttons");
  var axisCapabilities = availableMap(controller, "axes");
  var triggerType = profile.triggerType === "digital" ? "digital" : "analog";

  state.phase = "baseline_waiting";
  state.connected = true;
  state.controllerId = controller.id;
  state.controller = copyMap(controller);
  state.profileId = profile.id;
  state.profileName = typeof profile.displayName === "string" ? profile.displayName : profile.id;
  state.labels = copyMap(profile.labels);
  state.thresholds = copyMap(profile.thresholds);
  state.currentButtons = copyMap(controller.buttons);
  state.currentAxes = copyMap(controller.axes);

  for (var buttonIndex = 0; buttonIndex < expectedButtons.length; buttonIndex++) {
    var button = expectedButtons[buttonIndex];
    state.digitalControls.push(button);
    state.results[button] = digitalResult(button, buttonCapabilities.indexOf(button) !== -1);
  }
  for (var axisIndex = 0; axisIndex < expectedAxes.length; axisIndex++) {
    var axis = expectedAxes[axisIndex];
    var digitalTrigger = triggerType === "digital" && /_trigger$/.test(axis);
    if (digitalTrigger) {
      state.digitalControls.push(axis);
      state.results[axis] = digitalResult(axis, axisCapabilities.indexOf(axis) !== -1);
    } else {
      state.analogControls.push(axis);
      state.results[axis] = analogResult(axis, axisCapabilities.indexOf(axis) !== -1);
    }
  }
  return state;
}

function addBaselineSample(state) {
  var next = copyDiagnosticState(state);
  next.baseline.samples++;
  for (var digitalIndex = 0; digitalIndex < next.digitalControls.length; digitalIndex++) {
    var control = next.digitalControls[digitalIndex];
    if (!next.results[control].available) continue;
    var held = /_trigger$/.test(control)
      ? Number(next.currentAxes[control] || 0) >= threshold(next, "digitalTriggerPress", 0.65)
      : next.currentButtons[control] === true;
    if (held) next.baseline.held[control] = true;
  }
  for (var analogIndex = 0; analogIndex < next.analogControls.length; analogIndex++) {
    var axis = next.analogControls[analogIndex];
    if (!next.results[axis].available) continue;
    var value = Number(next.currentAxes[axis]);
    if (!isFinite(value)) continue;
    var metric = next.baseline.axes[axis] || {
      count: 0, sum: 0, minimum: value, maximum: value
    };
    metric.count++;
    metric.sum += value;
    metric.minimum = Math.min(metric.minimum, value);
    metric.maximum = Math.max(metric.maximum, value);
    next.baseline.axes[axis] = metric;
  }
  return next;
}

function startBaseline(state) {
  if (!state || state.phase !== "baseline_waiting" || !state.connected) return state;
  var next = copyDiagnosticState(state);
  next.phase = "baseline_capturing";
  return addBaselineSample(next);
}

function inputValuesValid(message) {
  if (!plainObject(message) || message.type !== "input" || typeof message.id !== "string") return false;
  if (message.buttons !== undefined && !plainObject(message.buttons)) return false;
  if (message.axes !== undefined && !plainObject(message.axes)) return false;
  var buttons = Object.keys(message.buttons || {});
  for (var i = 0; i < buttons.length; i++) {
    if (typeof message.buttons[buttons[i]] !== "boolean") return false;
  }
  var axes = Object.keys(message.axes || {});
  for (var j = 0; j < axes.length; j++) {
    var value = message.axes[axes[j]];
    if (typeof value !== "number" || !isFinite(value) || value < -1 || value > 1) return false;
  }
  return true;
}

function captureDigitalEdge(next, control, wasActive, isActive) {
  var result = next.results[control];
  if (!result || !result.available) return;
  if (!wasActive && isActive) result.pressed = true;
  if (wasActive && !isActive && result.pressed) result.released = true;
}

function analogPhaseFor(control) {
  return /^right/.test(control) ? "analog_right" : "analog_left";
}

function captureAnalog(next, control, value) {
  var result = next.results[control];
  if (!result || !result.available || next.phase !== analogPhaseFor(control)) return;
  result.minimum = result.minimum === null ? value : Math.min(result.minimum, value);
  result.maximum = result.maximum === null ? value : Math.max(result.maximum, value);
  result.samples++;
  var center = result.center === null ? 0 : result.center;
  var movement = threshold(next, "movementDetection", 0.2);
  if (value <= center - movement) result.negative = true;
  if (value >= center + movement) result.positive = true;
}

function ingestInput(state, message) {
  if (!state || !state.connected || !inputValuesValid(message)
      || message.id !== state.controllerId) return state;
  if (["baseline_capturing", "digital", "analog_left", "analog_right"].indexOf(state.phase) === -1) return state;
  var next = copyDiagnosticState(state);
  var buttonKeys = Object.keys(message.buttons || {});
  var axisKeys = Object.keys(message.axes || {});

  for (var buttonIndex = 0; buttonIndex < buttonKeys.length; buttonIndex++) {
    var button = buttonKeys[buttonIndex];
    if (next.retryTarget !== "" && next.retryTarget !== button) continue;
    var oldButton = next.currentButtons[button] === true;
    var newButton = message.buttons[button] === true;
    next.currentButtons[button] = newButton;
    if (next.phase === "digital") captureDigitalEdge(next, button, oldButton, newButton);
  }

  for (var axisIndex = 0; axisIndex < axisKeys.length; axisIndex++) {
    var axis = axisKeys[axisIndex];
    if (next.retryTarget !== "" && next.retryTarget !== axis) continue;
    var oldValue = Number(next.currentAxes[axis] || 0);
    var newValue = message.axes[axis];
    next.currentAxes[axis] = newValue;
    var result = next.results[axis];
    if (next.phase === "digital" && result && result.kind === "digital") {
      var press = threshold(next, "digitalTriggerPress", 0.65);
      var release = threshold(next, "digitalTriggerRelease", 0.35);
      var wasActive = result.pressed && !result.released ? oldValue > release : oldValue >= press;
      var isActive = wasActive ? newValue > release : newValue >= press;
      captureDigitalEdge(next, axis, wasActive, isActive);
    } else if (result && result.kind === "analog") {
      captureAnalog(next, axis, newValue);
    }
  }
  return next.phase === "baseline_capturing" ? addBaselineSample(next) : next;
}

function finishBaseline(state) {
  if (!state || state.phase !== "baseline_capturing") return state;
  var next = copyDiagnosticState(state);
  for (var digitalIndex = 0; digitalIndex < next.digitalControls.length; digitalIndex++) {
    var digital = next.results[next.digitalControls[digitalIndex]];
    digital.baselineHeld = next.baseline.held[digital.control] === true;
    digital.offered = digital.available;
    digital.pressed = false;
    digital.released = false;
  }
  for (var analogIndex = 0; analogIndex < next.analogControls.length; analogIndex++) {
    var analog = next.results[next.analogControls[analogIndex]];
    var metric = next.baseline.axes[analog.control];
    if (!analog.available || !metric || metric.count === 0) continue;
    analog.center = metric.sum / metric.count;
    analog.noise = metric.maximum - metric.minimum;
  }
  next.phase = "digital";
  return next;
}

function digitalStatus(result, disconnected) {
  if (!result.available) return "unavailable";
  if (!result.offered) return "incomplete";
  if (disconnected && !(result.pressed && result.released)) return "incomplete";
  if (result.pressed && result.released) return result.baselineHeld ? "warning" : "passed";
  if (result.pressed || result.baselineHeld) return "incomplete";
  return "not_detected";
}

function analogStatus(state, result, disconnected) {
  if (!result.available) return "unavailable";
  if (!result.offered) return "incomplete";
  if (result.center === null || disconnected && !(result.negative && result.positive)) return "incomplete";
  if (!result.negative && !result.positive) return "not_detected";
  if (!result.negative || !result.positive) return "warning";
  var centerWarning = threshold(state, "centerOffsetWarning", 0.15);
  var noiseWarning = threshold(state, "neutralJitterWarning", 0.08);
  var negativeRange = threshold(state, "minimumNegativeRange", 0.75);
  var positiveRange = threshold(state, "minimumPositiveRange", 0.75);
  var warning = Math.abs(result.center) > centerWarning || result.noise > noiseWarning
    || result.minimum === null || result.maximum === null
    || result.minimum > -negativeRange || result.maximum < positiveRange;
  return warning ? "warning" : "passed";
}

function evaluateResults(state, disconnected) {
  var next = copyDiagnosticState(state);
  var controls = next.digitalControls.concat(next.analogControls);
  var hasAvailable = false;
  var hasWarning = false;
  var hasMissing = false;
  var hasIncomplete = false;
  for (var i = 0; i < controls.length; i++) {
    var result = next.results[controls[i]];
    result.status = result.kind === "digital"
      ? digitalStatus(result, disconnected)
      : analogStatus(next, result, disconnected);
    hasAvailable = hasAvailable || result.available;
    hasWarning = hasWarning || result.status === "warning";
    hasMissing = hasMissing || result.status === "not_detected";
    hasIncomplete = hasIncomplete || result.status === "incomplete";
  }
  next.status = disconnected || hasIncomplete ? "incomplete"
    : (!hasAvailable ? "unavailable"
      : (hasMissing ? "not_detected" : (hasWarning ? "warning" : "passed")));
  return next;
}

function advancePhase(state) {
  if (!state || !state.connected) return state;
  if (state.retryTarget !== "") return finalize(state);
  var next = copyDiagnosticState(state);
  if (next.phase === "digital") {
    next.phase = "analog_left";
    markAnalogOffered(next, "analog_left");
  } else if (next.phase === "analog_left") {
    next.phase = "analog_right";
    markAnalogOffered(next, "analog_right");
  } else if (next.phase === "analog_right") {
    next.phase = "review";
    return evaluateResults(next, false);
  }
  return next;
}

function markAnalogOffered(state, phase) {
  for (var i = 0; i < state.analogControls.length; i++) {
    var result = state.results[state.analogControls[i]];
    if (result.available && analogPhaseFor(result.control) === phase) result.offered = true;
  }
}

function finalize(state) {
  if (!state || state.phase === "idle") return state;
  var next = copyDiagnosticState(state);
  next.phase = "review";
  next.retryTarget = "";
  return evaluateResults(next, next.interrupted || !next.connected);
}

function cancelSession(state) {
  if (!state || state.phase === "idle" || state.phase === "review") return state;
  var next = copyDiagnosticState(state);
  next.interrupted = true;
  next.phase = "review";
  return evaluateResults(next, true);
}

function retryControl(state, control) {
  if (!state || state.phase !== "review" || !state.connected || !hasOwn(state.results, control)) return state;
  var old = state.results[control];
  if (!old.available) return state;
  var next = copyDiagnosticState(state);
  var replacement = old.kind === "digital" ? digitalResult(control, true) : analogResult(control, true);
  replacement.baselineHeld = old.baselineHeld;
  replacement.offered = true;
  replacement.center = old.center;
  replacement.noise = old.noise;
  next.results[control] = replacement;
  next.retryTarget = control;
  next.phase = old.kind === "digital" ? "digital" : analogPhaseFor(control);
  next.status = "incomplete";
  return next;
}

function disconnect(state, controllerId) {
  if (!state || state.phase === "idle" || controllerId !== state.controllerId) return state;
  var next = copyDiagnosticState(state);
  next.connected = false;
  next.interrupted = true;
  next.phase = "review";
  return evaluateResults(next, true);
}

function safeText(value) {
  var text = String(value === undefined || value === null ? "" : value);
  text = text.replace(/\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b/gi, "[redacted]");
  text = text.replace(/(?:~\/|\/(?:home|Users|dev|sys|proc|run|tmp)\/)[^\s\"',;)]*/g, "[redacted]");
  text = text.replace(/(^|[\s(\"'=])\/(?:[^\/\s]+\/)*[^\s\"',;)]*/g, "$1[redacted]");
  return text.replace(/[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/g, "");
}

function safeOptional(value) {
  return typeof value === "string" || typeof value === "number" ? safeText(value) : "";
}

function reportBattery(battery) {
  var source = plainObject(battery) ? battery : {};
  return {
    available: source.available === true,
    state: safeOptional(source.state)
  };
}

function reportResult(result) {
  var projected = {
    control: safeText(result.control),
    kind: result.kind,
    status: DIAGNOSTIC_STATUSES.indexOf(result.status) !== -1 ? result.status : "incomplete",
    available: result.available
  };
  if (result.kind === "digital") {
    projected.pressed = result.pressed;
    projected.released = result.released;
    projected.baselineHeld = result.baselineHeld;
  } else {
    projected.center = result.center;
    projected.noise = result.noise;
    projected.minimum = result.minimum;
    projected.maximum = result.maximum;
    projected.negative = result.negative;
    projected.positive = result.positive;
    projected.samples = result.samples;
  }
  return projected;
}

function createReport(state, metadata) {
  var source = state || diagnosticInitialState();
  var controller = source.controller || {};
  var environment = plainObject(metadata) ? metadata : {};
  var thresholds = {};
  for (var thresholdIndex = 0; thresholdIndex < REPORT_THRESHOLD_NAMES.length; thresholdIndex++) {
    var thresholdName = REPORT_THRESHOLD_NAMES[thresholdIndex];
    if (typeof source.thresholds[thresholdName] === "number" && isFinite(source.thresholds[thresholdName])) {
      thresholds[thresholdName] = source.thresholds[thresholdName];
    }
  }
  var controls = source.digitalControls.concat(source.analogControls);
  var results = [];
  for (var resultIndex = 0; resultIndex < controls.length; resultIndex++) {
    results.push(reportResult(source.results[controls[resultIndex]]));
  }
  var warningCodes = [];
  if (Array.isArray(environment.backendWarningCodes)) {
    for (var warningIndex = 0; warningIndex < environment.backendWarningCodes.length; warningIndex++) {
      var warningCode = String(environment.backendWarningCodes[warningIndex] || "");
      var projectedCode = REPORT_WARNING_CODES.indexOf(warningCode) !== -1 ? warningCode : "backend_warning";
      if (warningCode !== "" && warningCodes.indexOf(projectedCode) === -1) {
        warningCodes.push(projectedCode);
      }
    }
  }
  return {
    schemaVersion: 1,
    profileId: safeText(source.profileId),
    status: DIAGNOSTIC_STATUSES.indexOf(source.status) !== -1 ? source.status : "incomplete",
    controller: {
      name: safeOptional(source.profileName),
      family: safeOptional(controller.family),
      sdlType: safeOptional(controller.sdlType),
      vendorId: safeOptional(controller.vendorId),
      productId: safeOptional(controller.productId),
      connection: safeOptional(controller.connection),
      battery: reportBattery(controller.battery),
      supportedButtons: stringList((controller.capabilities || {}).buttons).map(safeText),
      supportedAxes: stringList((controller.capabilities || {}).axes).map(safeText)
    },
    environment: reportEnvironment(environment),
    thresholds: thresholds,
    backendWarningCodes: warningCodes,
    results: results
  };
}

function reportEnvironment(environment) {
  var projected = {};
  var names = ["pluginVersion", "omarchyVersion", "kernelVersion", "sdlVersion"];
  for (var i = 0; i < names.length; i++) {
    var value = safeOptional(environment[names[i]]);
    if (value !== "") projected[names[i]] = value;
  }
  return projected;
}

function formatReport(state, metadata) {
  var report = createReport(state, metadata);
  var lines = [
    "Omarchy Gamepads diagnostic report",
    "Status: " + report.status,
    "Profile: " + report.profileId,
    "Controller: " + report.controller.name,
    ""
  ];
  for (var i = 0; i < report.results.length; i++) {
    lines.push(report.results[i].control + ": " + report.results[i].status);
  }
  return lines.join("\n");
}

// Short aliases keep QML call sites readable while retaining descriptive API names.
function initialState() { return diagnosticInitialState(); }
function ingest(state, message) { return ingestInput(state, message); }
function report(state, metadata) { return createReport(state, metadata); }
