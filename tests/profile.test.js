const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function loadScript(relativePath, context) {
  const source = fs.readFileSync(path.join(__dirname, "..", relativePath), "utf8")
    .replace(/^\.import[^\n]*\n/, "");
  vm.createContext(context);
  vm.runInContext(source, context, { filename: relativePath });
}

const SwitchPro = {};
loadScript("profiles/switch-pro/Profile.js", SwitchPro);
const Registry = { SwitchPro };
loadScript("profiles/ProfileRegistry.js", Registry);

const switchProController = {
  sdlType: "switchpro",
  family: "switch-pro",
  vendorId: "057e",
  productId: "2009"
};

test("resolves the Switch Pro profile and semantic labels", () => {
  const profile = Registry.profileFor(switchProController);
  assert.equal(profile.id, "switch-pro");
  assert.equal(Registry.labelFor(profile, "south"), "B");
  assert.equal(profile.semanticParts.south, "button_b");
  assert.deepEqual(Array.from(profile.expectedButtons), [
    "south", "east", "west", "north", "back", "start", "misc1", "guide",
    "left_stick", "right_stick", "dpad_up", "dpad_down", "dpad_left",
    "dpad_right", "left_shoulder", "right_shoulder"
  ]);
  assert.deepEqual(Array.from(profile.expectedAxes), [
    "leftx", "lefty", "rightx", "righty", "left_trigger", "right_trigger"
  ]);
  assert.equal(profile.modelParts.includes("left_stick"), true);
  assert.equal(profile.modelParts.includes("button_right_stick"), true);
});

test("provides valid profile-owned diagnostic thresholds", () => {
  const thresholds = SwitchPro.profile.thresholds;
  assert.deepEqual(Object.keys(thresholds).sort(), [
    "baselineDurationMs", "centerOffsetWarning", "digitalTriggerPress",
    "digitalTriggerRelease", "minimumNegativeRange", "minimumPositiveRange",
    "movementDetection", "neutralJitterWarning"
  ]);
  assert.equal(Registry.validateProfile(SwitchPro.profile), true);
  assert.ok(thresholds.digitalTriggerRelease < thresholds.digitalTriggerPress);
  assert.ok(thresholds.movementDetection < thresholds.minimumPositiveRange);
  assert.ok(thresholds.movementDetection < thresholds.minimumNegativeRange);
});

test("returns no profile for an unknown SDL type", () => {
  assert.equal(Registry.profileFor({
    sdlType: "xboxone", family: "xbox", vendorId: "045e", productId: "02ea"
  }), null);
});

test("prefers a refined matcher and rejects ambiguous matches", () => {
  const generic = Object.assign({}, SwitchPro.profile, { id: "generic-switch" });
  const exact = Object.assign({}, SwitchPro.profile, {
    id: "exact-switch",
    matchers: [{ sdlTypes: ["switchpro"], vendorId: "057e", productId: "2009" }]
  });
  assert.equal(Registry.resolveProfile(switchProController, [generic, exact]).id, "exact-switch");
  assert.equal(Registry.resolveProfile(switchProController, [generic, Object.assign({}, generic, { id: "other" })]), null);
});

test("rejects malformed profile contracts", () => {
  const malformed = Object.assign({}, SwitchPro.profile, { id: "Not Valid" });
  assert.equal(Registry.validateProfile(malformed), false);
  const missingView = Object.assign({}, SwitchPro.profile, { viewComponent: "../Outside.qml" });
  assert.equal(Registry.validateProfile(missingView), false);
  const missingMapping = Object.assign({}, SwitchPro.profile, {
    semanticParts: Object.assign({}, SwitchPro.profile.semanticParts)
  });
  delete missingMapping.semanticParts.left_trigger;
  assert.equal(Registry.validateProfile(missingMapping), false);
  const vendorOnly = Object.assign({}, SwitchPro.profile, { matchers: [{ vendorId: "057e" }] });
  assert.equal(Registry.validateProfile(vendorOnly), false);
  const productOnly = Object.assign({}, SwitchPro.profile, {
    matchers: [{ sdlTypes: ["switchpro"], productId: "2009" }]
  });
  assert.equal(Registry.validateProfile(productOnly), false);
  const undeclaredPart = Object.assign({}, SwitchPro.profile, {
    semanticParts: Object.assign({}, SwitchPro.profile.semanticParts, { south: "button_missing" })
  });
  assert.equal(Registry.validateProfile(undeclaredPart), false);
  const staleMapping = Object.assign({}, SwitchPro.profile, {
    semanticParts: Object.assign({}, SwitchPro.profile.semanticParts, { turbo: "button_a" })
  });
  assert.equal(Registry.validateProfile(staleMapping), false);
  const overlappingControl = Object.assign({}, SwitchPro.profile, {
    expectedAxes: SwitchPro.profile.expectedAxes.concat(["south"])
  });
  assert.equal(Registry.validateProfile(overlappingControl), false);
  assert.equal(Registry.validateProfile(SwitchPro.profile), true);
});

test("rejects malformed animation and model-part contracts", () => {
  function withAnimation(changes) {
    return Object.assign({}, SwitchPro.profile, {
      animation: Object.assign({}, SwitchPro.profile.animation, changes)
    });
  }

  assert.equal(Registry.validateProfile(withAnimation({ digitalTravel: 0 })), false);
  assert.equal(Registry.validateProfile(withAnimation({ stickTiltDegrees: 46 })), false);
  assert.equal(Registry.validateProfile(withAnimation({ transitionDurationMs: 50.5 })), false);
  assert.equal(Registry.validateProfile(withAnimation({ unexpected: 1 })), false);
  const missing = withAnimation({});
  delete missing.animation.digitalTravel;
  assert.equal(Registry.validateProfile(missing), false);
  assert.equal(Registry.validateProfile(Object.assign({}, SwitchPro.profile, {
    modelParts: SwitchPro.profile.modelParts.concat(["button_a"])
  })), false);
});

test("rejects malformed or unsafe diagnostic thresholds", () => {
  function withThresholds(changes) {
    return Object.assign({}, SwitchPro.profile, {
      thresholds: Object.assign({}, SwitchPro.profile.thresholds, changes)
    });
  }

  assert.equal(Registry.validateProfile(withThresholds({ centerOffsetWarning: NaN })), false);
  assert.equal(Registry.validateProfile(withThresholds({ neutralJitterWarning: Infinity })), false);
  assert.equal(Registry.validateProfile(withThresholds({ movementDetection: 1.01 })), false);
  assert.equal(Registry.validateProfile(withThresholds({ baselineDurationMs: 999 })), false);
  assert.equal(Registry.validateProfile(withThresholds({
    digitalTriggerRelease: SwitchPro.profile.thresholds.digitalTriggerPress
  })), false);
  assert.equal(Registry.validateProfile(withThresholds({
    movementDetection: SwitchPro.profile.thresholds.minimumPositiveRange
  })), false);

  const missing = withThresholds({});
  delete missing.thresholds.minimumNegativeRange;
  assert.equal(Registry.validateProfile(missing), false);
  assert.equal(Registry.validateProfile(withThresholds({ unexpected: 0.1 })), false);
});
