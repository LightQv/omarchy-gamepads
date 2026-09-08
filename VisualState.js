"use strict";

var ACTIVE_PHASES = [
  "baseline_waiting", "baseline_capturing", "digital", "analog_left", "analog_right"
];

function finiteNumber(value, fallback) {
  var number = Number(value);
  return isFinite(number) ? number : fallback;
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, finiteNumber(value, 0)));
}

function diagnosticMatches(controller, profile, diagnostic) {
  return !!controller && !!profile && !!diagnostic
    && String(controller.id || "") !== ""
    && String(controller.id || "") === String(diagnostic.controllerId || "")
    && String(profile.id || "") === String(diagnostic.profileId || "");
}

function interactionMode(controller, profile, diagnostic) {
  if (!diagnosticMatches(controller, profile, diagnostic)) return "overview";
  var phase = String(diagnostic.phase || "idle");
  if (ACTIVE_PHASES.indexOf(phase) !== -1) return "diagnostic";
  return phase === "review" ? "review" : "overview";
}

function emptyPartState() {
  return {
    active: false,
    amount: 0,
    x: 0,
    y: 0,
    completed: false,
    status: ""
  };
}

function copyPartState(state) {
  return {
    active: state.active,
    amount: state.amount,
    x: state.x,
    y: state.y,
    completed: state.completed,
    status: state.status
  };
}

function resultComplete(result) {
  if (!result || result.available === false) return false;
  return result.kind === "analog"
    ? result.negative === true && result.positive === true
    : result.pressed === true && result.released === true;
}

function statusPriority(status) {
  return {
    "": 0,
    passed: 1,
    unavailable: 2,
    incomplete: 3,
    not_detected: 4,
    warning: 5
  }[status] || 0;
}

function aggregateMappedResults(parts, profile, results, mode) {
  var controls = (profile.expectedButtons || []).concat(profile.expectedAxes || []);
  var grouped = {};
  for (var controlIndex = 0; controlIndex < controls.length; controlIndex++) {
    var control = controls[controlIndex];
    var part = profile.semanticParts[control];
    if (!grouped[part]) grouped[part] = [];
    grouped[part].push(control);
  }
  var partNames = Object.keys(grouped);
  for (var partIndex = 0; partIndex < partNames.length; partIndex++) {
    var partName = partNames[partIndex];
    var mappedControls = grouped[partName];
    var completed = mappedControls.length > 0;
    var status = "";
    for (var mappedIndex = 0; mappedIndex < mappedControls.length; mappedIndex++) {
      var result = results[mappedControls[mappedIndex]];
      completed = completed && resultComplete(result);
      var candidate = mode === "review" && result ? String(result.status || "") : "";
      if (statusPriority(candidate) > statusPriority(status)) status = candidate;
    }
    parts[partName].completed = completed;
    parts[partName].status = status;
  }
}

function project(controller, profile, diagnostic) {
  var mode = interactionMode(controller, profile, diagnostic);
  var parts = {};
  var modelParts = profile && Array.isArray(profile.modelParts) ? profile.modelParts : [];
  for (var partIndex = 0; partIndex < modelParts.length; partIndex++)
    parts[modelParts[partIndex]] = emptyPartState();

  if (!controller || !profile) return { mode: mode, parts: parts };
  var buttons = controller.buttons || {};
  var axes = controller.axes || {};
  var mappings = profile.semanticParts || {};
  var thresholds = profile.thresholds || {};
  var movement = finiteNumber(thresholds.movementDetection, 0.2);
  var triggerPress = finiteNumber(thresholds.digitalTriggerPress, 0.75);
  var results = diagnosticMatches(controller, profile, diagnostic) ? diagnostic.results || {} : {};

  var buttonNames = profile.expectedButtons || [];
  for (var buttonIndex = 0; buttonIndex < buttonNames.length; buttonIndex++) {
    var button = buttonNames[buttonIndex];
    var buttonPart = mappings[button];
    if (!parts[buttonPart]) continue;
    var pressed = buttons[button] === true;
    parts[buttonPart].active = pressed;
    parts[buttonPart].amount = pressed ? 1 : 0;
  }

  var axisNames = profile.expectedAxes || [];
  for (var axisIndex = 0; axisIndex < axisNames.length; axisIndex++) {
    var axis = axisNames[axisIndex];
    var axisPart = mappings[axis];
    if (!parts[axisPart]) continue;
    var value = clamp(axes[axis], -1, 1);
    var state = copyPartState(parts[axisPart]);
    if (axis === "leftx" || axis === "rightx") state.x = value;
    else if (axis === "lefty" || axis === "righty") state.y = value;
    else {
      state.amount = clamp(value, 0, 1);
      state.active = state.amount >= triggerPress;
    }
    state.active = state.active || Math.abs(state.x) >= movement || Math.abs(state.y) >= movement;
    parts[axisPart] = state;
  }

  aggregateMappedResults(parts, profile, results, mode);

  return { mode: mode, parts: parts };
}
