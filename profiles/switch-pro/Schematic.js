"use strict";

// One authored front/above drawing, in a 900 x 480 logical canvas.
var buttons = [
  { control: "left_trigger", label: "ZL", x: 205, y: 27, w: 133, h: 42,
    path: "M 5 40 L 15 10 Q 18 2 32 2 L 118 2 Q 130 2 130 12 L 130 40 Z" },
  { control: "right_trigger", label: "ZR", x: 562, y: 27, w: 133, h: 42,
    path: "M 3 40 L 3 12 Q 3 2 15 2 L 101 2 Q 115 2 118 10 L 128 40 Z" },
  { control: "left_shoulder", label: "L", x: 145, y: 82, w: 193, h: 43,
    path: "M 3 40 Q 10 9 41 4 Q 103 -1 190 4 L 190 39 Q 100 34 3 40 Z" },
  { control: "right_shoulder", label: "R", x: 562, y: 82, w: 193, h: 43,
    path: "M 3 4 Q 90 -1 152 4 Q 183 9 190 40 Q 93 34 3 39 Z" },
  { control: "north", label: "X", x: 630, y: 137, w: 52, h: 48, round: true },
  { control: "west", label: "Y", x: 576, y: 183, w: 52, h: 48, round: true },
  { control: "east", label: "A", x: 684, y: 183, w: 52, h: 48, round: true },
  { control: "south", label: "B", x: 630, y: 229, w: 52, h: 48, round: true },
  { control: "back", label: "−", x: 375, y: 154, w: 40, h: 30 },
  { control: "start", label: "+", x: 485, y: 154, w: 40, h: 30 },
  { control: "misc1", label: "▣", x: 380, y: 218, w: 32, h: 28 },
  { control: "guide", label: "⌂", x: 488, y: 218, w: 32, h: 28, round: true },
  { control: "dpad_up", label: "↑", x: 324, y: 245, w: 36, h: 34 },
  { control: "dpad_left", label: "←", x: 288, y: 279, w: 36, h: 34 },
  { control: "dpad_right", label: "→", x: 360, y: 279, w: 36, h: 34 },
  { control: "dpad_down", label: "↓", x: 324, y: 313, w: 36, h: 34 }
];

var sticks = [
  { control: "left_stick", label: "L3", axisX: "leftx", axisY: "lefty", x: 245, y: 204 },
  { control: "right_stick", label: "R3", axisX: "rightx", axisY: "righty", x: 560, y: 294 }
];

function hasControl(controller, kind, name) {
  var values = controller && controller.capabilities ? controller.capabilities[kind] : null;
  return Array.isArray(values) && values.indexOf(name) !== -1;
}

function axis(controller, name, minimum) {
  var value = controller && controller.axes ? controller.axes[name] : 0;
  return typeof value === "number" && isFinite(value) ? Math.max(minimum, Math.min(1, value)) : 0;
}

function threshold(profile, name, fallback) {
  var value = profile && profile.thresholds ? profile.thresholds[name] : undefined;
  return typeof value === "number" && isFinite(value) && value >= 0 && value <= 1 ? value : fallback;
}

function resultStatus(controller, profile, diagnostic, control) {
  if (!controller || !profile || !diagnostic || diagnostic.phase === "idle"
      || diagnostic.controllerId !== controller.id || diagnostic.profileId !== profile.id) return "";
  var result = diagnostic.results && diagnostic.results[control];
  return result && typeof result.status === "string" ? result.status : "";
}

function digitalState(controller, profile, diagnostic, name) {
  var trigger = name === "left_trigger" || name === "right_trigger";
  var available = hasControl(controller, trigger ? "axes" : "buttons", name);
  var amount = available ? (trigger ? axis(controller, name, 0)
    : (controller.buttons && controller.buttons[name] === true ? 1 : 0)) : 0;
  return {
    available: available,
    active: available && (trigger ? amount >= threshold(profile, "digitalTriggerPress", 0.75) : amount === 1),
    status: resultStatus(controller, profile, diagnostic, name)
  };
}

function pairStatus(first, second) {
  if (first === "warning" || second === "warning") return "warning";
  if (first === "not_detected" || second === "not_detected") return "not_detected";
  if (first === "passed" && second === "passed") return "passed";
  return "";
}

function project(controller, profile, diagnostic) {
  var controls = {};
  var stickStates = {};
  for (var i = 0; i < buttons.length; i++) {
    var name = buttons[i].control;
    controls[name] = digitalState(controller, profile, diagnostic, name);
  }
  for (var j = 0; j < sticks.length; j++) {
    var stick = sticks[j];
    controls[stick.control] = digitalState(controller, profile, diagnostic, stick.control);
    var available = hasControl(controller, "axes", stick.axisX) && hasControl(controller, "axes", stick.axisY);
    var x = available ? axis(controller, stick.axisX, -1) : 0;
    var y = available ? axis(controller, stick.axisY, -1) : 0;
    var detection = threshold(profile, "movementDetection", 0.2);
    stickStates[stick.control] = {
      available: available, x: x, y: y,
      active: available && (Math.abs(x) >= detection || Math.abs(y) >= detection),
      status: pairStatus(resultStatus(controller, profile, diagnostic, stick.axisX),
        resultStatus(controller, profile, diagnostic, stick.axisY))
    };
  }
  return { controls: controls, sticks: stickStates };
}
