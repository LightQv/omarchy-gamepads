"use strict";

var profile = {
  id: "switch-pro",
  displayName: "Switch Pro Controller",
  matchers: [
    { sdlTypes: ["switchpro"] }
  ],
  labels: {
    south: "B",
    east: "A",
    west: "Y",
    north: "X",
    back: "Minus",
    start: "Plus",
    guide: "Home",
    misc1: "Capture",
    leftx: "Left stick X",
    lefty: "Left stick Y",
    rightx: "Right stick X",
    righty: "Right stick Y",
    left_trigger: "ZL",
    right_trigger: "ZR",
    left_shoulder: "L",
    right_shoulder: "R",
    left_stick: "Left stick",
    right_stick: "Right stick"
  },
  expectedButtons: [
    "south", "east", "west", "north", "back", "start", "misc1", "guide",
    "left_stick", "right_stick", "dpad_up", "dpad_down", "dpad_left",
    "dpad_right", "left_shoulder", "right_shoulder"
  ],
  expectedAxes: ["leftx", "lefty", "rightx", "righty", "left_trigger", "right_trigger"],
  triggerType: "digital",
  viewComponent: "switch-pro/SwitchProView.qml",
  semanticParts: {
    south: "button_b",
    east: "button_a",
    west: "button_y",
    north: "button_x",
    dpad_up: "dpad_up",
    dpad_down: "dpad_down",
    dpad_left: "dpad_left",
    dpad_right: "dpad_right",
    left_shoulder: "button_l",
    right_shoulder: "button_r",
    back: "button_minus",
    start: "button_plus",
    guide: "button_home",
    misc1: "button_capture",
    left_stick: "button_left_stick",
    right_stick: "button_right_stick",
    leftx: "left_stick",
    lefty: "left_stick",
    rightx: "right_stick",
    righty: "right_stick",
    left_trigger: "button_zl",
    right_trigger: "button_zr"
  },
  animation: {
    digitalTravel: 0.06,
    stickTiltDegrees: 14
  },
  // Provisional SDL-normalized values; physical testing should refine them.
  thresholds: {
    baselineDurationMs: 1500,
    digitalTriggerPress: 0.75,
    digitalTriggerRelease: 0.25,
    centerOffsetWarning: 0.15,
    neutralJitterWarning: 0.05,
    minimumPositiveRange: 0.75,
    minimumNegativeRange: 0.75,
    movementDetection: 0.2
  },
  knownLimitations: [
    "Interactive 3D visualization is planned for version 2."
  ]
};
