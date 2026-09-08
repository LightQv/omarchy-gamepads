const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function load(relativePath) {
  const context = {};
  vm.createContext(context);
  vm.runInContext(fs.readFileSync(path.join(__dirname, "..", relativePath), "utf8"), context, { filename: relativePath });
  return context;
}

const Visual = load("VisualState.js");
const SwitchPro = load("profiles/switch-pro/Profile.js");
const profile = SwitchPro.profile;

function controller(id = "12") {
  return {
    id,
    buttons: { south: true, left_stick: true },
    axes: { leftx: 0.5, lefty: -0.75, rightx: 0, righty: 0, left_trigger: 0.8, right_trigger: 0 }
  };
}

function diagnostic(phase = "digital", id = "12") {
  return {
    phase,
    controllerId: id,
    profileId: profile.id,
    results: {
      south: { kind: "digital", available: true, pressed: true, released: true, status: "passed" },
      leftx: { kind: "analog", available: true, negative: true, positive: true, status: "warning" },
      lefty: { kind: "analog", available: true, negative: true, positive: false, status: "incomplete" }
    }
  };
}

test("separates overview, diagnostic, and matching review modes", () => {
  assert.equal(Visual.interactionMode(controller(), profile, { phase: "idle" }), "overview");
  assert.equal(Visual.interactionMode(controller(), profile, diagnostic()), "diagnostic");
  assert.equal(Visual.interactionMode(controller(), profile, diagnostic("review")), "review");
  assert.equal(Visual.interactionMode(controller("99"), profile, diagnostic("review")), "overview");
});

test("projects buttons, digital triggers, and paired stick axes", () => {
  const projected = Visual.project(controller(), profile, diagnostic());
  assert.equal(projected.parts.button_b.amount, 1);
  assert.equal(projected.parts.button_b.completed, true);
  assert.equal(projected.parts.button_left_stick.amount, 1);
  assert.equal(projected.parts.button_zl.amount, 0.8);
  assert.equal(projected.parts.button_zl.active, true);
  assert.equal(projected.parts.left_stick.x, 0.5);
  assert.equal(projected.parts.left_stick.y, -0.75);
  assert.equal(projected.parts.left_stick.active, true);
  assert.equal(projected.parts.left_stick.completed, false);
});

test("scopes immutable review status to the tested controller", () => {
  const matching = Visual.project(controller(), profile, diagnostic("review"));
  assert.equal(matching.parts.button_b.status, "passed");
  assert.equal(matching.parts.left_stick.status, "warning");
  const other = Visual.project(controller("99"), profile, diagnostic("review"));
  assert.equal(other.parts.button_b.status, "");
  assert.equal(other.parts.left_stick.status, "");
});

test("requires both stick axes and uses deterministic status severity", () => {
  const partial = Visual.project(controller(), profile, diagnostic("review"));
  assert.equal(partial.parts.left_stick.completed, false);
  assert.equal(partial.parts.left_stick.status, "warning");

  const reversed = diagnostic("review");
  reversed.results.leftx.status = "passed";
  reversed.results.lefty.status = "not_detected";
  const projected = Visual.project(controller(), profile, reversed);
  assert.equal(projected.parts.left_stick.status, "not_detected");
});

test("clamps malformed live input without mutating sources", () => {
  const source = controller();
  source.axes.leftx = 4;
  source.axes.left_trigger = -2;
  const before = JSON.stringify(source);
  const projected = Visual.project(source, profile, diagnostic());
  assert.equal(projected.parts.left_stick.x, 1);
  assert.equal(projected.parts.button_zl.amount, 0);
  assert.equal(JSON.stringify(source), before);
});

test("declares a state for every model part", () => {
  const projected = Visual.project(controller(), profile, diagnostic());
  assert.deepEqual(Object.keys(projected.parts), Array.from(profile.modelParts));
});

test("projects every expected control into its semantic part", () => {
  for (const control of profile.expectedButtons) {
    const source = controller();
    source.buttons = { [control]: true };
    source.axes = {};
    const state = Visual.project(source, profile, { phase: "idle" }).parts[profile.semanticParts[control]];
    assert.equal(state.amount, 1, control);
    assert.equal(state.active, true, control);
  }
  for (const control of profile.expectedAxes) {
    const source = controller();
    source.buttons = {};
    source.axes = { [control]: 0.8 };
    const state = Visual.project(source, profile, { phase: "idle" }).parts[profile.semanticParts[control]];
    if (control.endsWith("_trigger")) assert.equal(state.amount, 0.8, control);
    else if (control.endsWith("x")) assert.equal(state.x, 0.8, control);
    else assert.equal(state.y, 0.8, control);
  }
});
