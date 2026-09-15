const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

function load(name) {
  const context = vm.createContext({});
  vm.runInContext(fs.readFileSync(path.join(__dirname, "../profiles/switch-pro", name), "utf8"), context);
  return context;
}

const Drawing = load("Schematic.js");
const profile = load("Profile.js").profile;

function controller() {
  return {
    id: "11",
    capabilities: { buttons: Array.from(profile.expectedButtons), axes: Array.from(profile.expectedAxes) },
    buttons: Object.fromEntries(profile.expectedButtons.map(name => [name, false])),
    axes: Object.fromEntries(profile.expectedAxes.map(name => [name, 0]))
  };
}

function pressed(projection) {
  return Object.keys(projection.controls).filter(name => projection.controls[name].active).sort();
}

test("the schematic binds every Switch Pro control and its positional face labels", () => {
  const controls = Array.from(Drawing.buttons, spec => spec.control).concat(Array.from(Drawing.sticks, spec => spec.control));
  assert.equal(new Set(controls).size, 18);
  assert.deepEqual(controls.sort(), Array.from(profile.expectedButtons).concat(["left_trigger", "right_trigger"]).sort());
  const axes = Array.from(Drawing.sticks).flatMap(spec => [spec.axisX, spec.axisY]);
  assert.deepEqual(axes.sort(), ["leftx", "lefty", "rightx", "righty"]);
  for (const [control, label] of Object.entries({ south: "B", east: "A", west: "Y", north: "X" })) {
    assert.equal(Drawing.buttons.find(spec => spec.control === control).label, label);
  }
});

test("every digital input lights independently and releases without changing its source", () => {
  for (const name of profile.expectedButtons.concat(["left_trigger", "right_trigger"])) {
    const source = controller();
    if (name.endsWith("_trigger")) source.axes[name] = 1;
    else source.buttons[name] = true;
    const before = JSON.stringify(source);
    assert.deepEqual(pressed(Drawing.project(source, profile, null)), [name]);
    assert.equal(JSON.stringify(source), before);
    if (name.endsWith("_trigger")) source.axes[name] = 0;
    else source.buttons[name] = false;
    assert.deepEqual(pressed(Drawing.project(source, profile, null)), []);
  }
});

test("simultaneous presses and fractional triggers agree with profile thresholds", () => {
  const source = controller();
  source.buttons.east = true;
  source.buttons.left_shoulder = true;
  source.buttons.right_stick = true;
  source.axes.left_trigger = 0.74;
  source.axes.right_trigger = 0.75;
  assert.deepEqual(pressed(Drawing.project(source, profile, null)), ["east", "left_shoulder", "right_stick", "right_trigger"]);
  const adjusted = { ...profile, thresholds: { ...profile.thresholds, digitalTriggerPress: 0.7 } };
  assert.equal(Drawing.project(source, adjusted, null).controls.left_trigger.active, true);
});

test("stick motion and clicks stay independent with bounded down-positive input", () => {
  const source = controller();
  source.axes.leftx = 0.19;
  source.axes.lefty = 0.2;
  source.axes.rightx = -2;
  source.axes.righty = 4;
  source.buttons.left_stick = true;
  const result = Drawing.project(source, profile, null);
  assert.equal(result.sticks.left_stick.x, 0.19);
  assert.equal(result.sticks.left_stick.y, 0.2);
  assert.equal(result.sticks.left_stick.active, true);
  assert.equal(result.sticks.right_stick.x, -1);
  assert.equal(result.sticks.right_stick.y, 1);
  assert.equal(result.controls.left_stick.active, true);
  assert.equal(result.controls.right_stick.active, false);
  source.axes.lefty = 0;
  assert.equal(Drawing.project(source, profile, null).sticks.left_stick.active, false);
});

test("absent capabilities and malformed values cannot create a live highlight", () => {
  const source = controller();
  source.capabilities.buttons = source.capabilities.buttons.filter(name => name !== "south");
  source.capabilities.axes = source.capabilities.axes.filter(name => name !== "lefty");
  source.buttons.south = true;
  source.buttons.east = "true";
  source.axes.leftx = 1;
  source.axes.rightx = NaN;
  source.axes.righty = "1";
  source.axes.left_trigger = Infinity;
  source.axes.right_trigger = -1;
  const result = Drawing.project(source, profile, null);
  assert.deepEqual(pressed(result), []);
  assert.equal(result.controls.south.available, false);
  assert.equal(result.sticks.left_stick.available, false);
  assert.equal(result.sticks.left_stick.active, false);
  assert.equal(result.sticks.right_stick.x, 0);
  assert.equal(result.sticks.right_stick.y, 0);
  assert.deepEqual(pressed(Drawing.project(null, profile, null)), []);
});

test("diagnostic marks are scoped to the tested controller and profile, separately from live input", () => {
  const source = controller();
  const diagnostic = { phase: "review", controllerId: source.id, profileId: profile.id, results: {
    east: { status: "passed" }, left_trigger: { status: "warning" },
    leftx: { status: "passed" }, lefty: { status: "incomplete" },
    rightx: { status: "passed" }, righty: { status: "not_detected" }
  } };
  const before = JSON.stringify(diagnostic);
  const result = Drawing.project(source, profile, diagnostic);
  assert.equal(result.controls.east.status, "passed");
  assert.equal(result.controls.east.active, false);
  assert.equal(result.controls.left_trigger.status, "warning");
  assert.equal(result.sticks.left_stick.status, "");
  assert.equal(result.sticks.right_stick.status, "not_detected");
  assert.equal(JSON.stringify(diagnostic), before);
  for (const changes of [{ controllerId: "12" }, { profileId: "other" }, { phase: "idle" }]) {
    const unrelated = Drawing.project(source, profile, { ...diagnostic, ...changes });
    assert.equal(unrelated.controls.east.status, "");
    assert.equal(unrelated.sticks.right_stick.status, "");
  }
  diagnostic.results.lefty.status = "passed";
  assert.equal(Drawing.project(source, profile, diagnostic).sticks.left_stick.status, "passed");
});
