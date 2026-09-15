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
  knownLimitations: []
};
