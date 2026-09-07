const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "Diagnostics.js"), "utf8");
const Diagnostics = {};
vm.createContext(Diagnostics);
vm.runInContext(source, Diagnostics, { filename: "Diagnostics.js" });

const SwitchPro = {};
vm.createContext(SwitchPro);
vm.runInContext(
  fs.readFileSync(path.join(__dirname, "..", "profiles", "switch-pro", "Profile.js"), "utf8"),
  SwitchPro,
  { filename: "profiles/switch-pro/Profile.js" }
);

const buttons = ["south", "north", "left_stick"];
const axes = ["leftx", "lefty", "rightx", "righty", "left_trigger"];
const profile = {
  id: "test-pad",
  displayName: "Test Pad Profile",
  expectedButtons: buttons,
  expectedAxes: axes,
  triggerType: "digital",
  thresholds: {
    baselineDurationMs: 1500,
    digitalTriggerPress: 0.7,
    digitalTriggerRelease: 0.3,
    centerOffsetWarning: 0.12,
    neutralJitterWarning: 0.06,
    minimumPositiveRange: 0.75,
    minimumNegativeRange: 0.75,
    movementDetection: 0.2
  }
};

function controller(overrides = {}) {
  return Object.assign({
    id: "41",
    name: "Test Controller",
    family: "test",
    sdlType: "testpad",
    vendorId: "1234",
    productId: "5678",
    connection: "wired",
    battery: { available: true, percent: 80, level: "high", state: "charging" },
    capabilities: { buttons: buttons.slice(), axes: axes.slice() },
    buttons: { south: false, north: false, left_stick: false },
    axes: { leftx: 0, lefty: 0, rightx: 0, righty: 0, left_trigger: 0 }
  }, overrides);
}

function input(id, changedButtons = {}, changedAxes = {}) {
  return { type: "input", id, buttons: changedButtons, axes: changedAxes };
}

function replayFixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
    .trim().split("\n").map((line) => JSON.parse(line));
}

function baseline(state, samples = [{ leftx: 0.01, lefty: -0.01, rightx: 0, righty: 0 }]) {
  state = Diagnostics.startBaseline(state);
  for (const sample of samples) state = Diagnostics.ingest(state, input("41", {}, sample));
  return Diagnostics.finishBaseline(state);
}

function exerciseDigital(state) {
  for (const name of buttons) {
    state = Diagnostics.ingest(state, input("41", { [name]: true }));
    state = Diagnostics.ingest(state, input("41", { [name]: false }));
  }
  state = Diagnostics.ingest(state, input("41", {}, { left_trigger: 0.8 }));
  state = Diagnostics.ingest(state, input("41", {}, { left_trigger: 0.5 }));
  state = Diagnostics.ingest(state, input("41", {}, { left_trigger: 0.2 }));
  return state;
}

function exerciseAxis(state, name) {
  state = Diagnostics.ingest(state, input("41", {}, { [name]: -0.9 }));
  return Diagnostics.ingest(state, input("41", {}, { [name]: 0.9 }));
}

function successfulSession() {
  let state = baseline(Diagnostics.startSession(controller(), profile));
  state = exerciseDigital(state);
  state = Diagnostics.advancePhase(state);
  state = exerciseAxis(state, "leftx");
  state = exerciseAxis(state, "lefty");
  state = Diagnostics.advancePhase(state);
  state = exerciseAxis(state, "rightx");
  state = exerciseAxis(state, "righty");
  return Diagnostics.advancePhase(state);
}

test("completes every expected control without mutating prior states", () => {
  const waiting = Diagnostics.startSession(controller(), profile);
  const capturing = Diagnostics.startBaseline(waiting);
  assert.equal(waiting.phase, "baseline_waiting");
  assert.equal(capturing.phase, "baseline_capturing");

  const state = successfulSession();
  assert.equal(state.phase, "review");
  assert.equal(state.status, "passed");
  assert.deepEqual(Object.keys(state.results).sort(), buttons.concat(axes).sort());
  for (const result of Object.values(state.results)) assert.equal(result.status, "passed");
});

test("a control held during baseline needs a fresh edge pair and remains a warning", () => {
  const held = controller({
    buttons: { south: true, north: false, left_stick: false }
  });
  let state = baseline(Diagnostics.startSession(held, profile));
  state = Diagnostics.ingest(state, input("41", { south: false }));
  assert.equal(state.results.south.pressed, false);
  state = Diagnostics.ingest(state, input("41", { south: true }));
  state = Diagnostics.ingest(state, input("41", { south: false }));
  state = Diagnostics.finalize(state);
  assert.equal(state.results.south.baselineHeld, true);
  assert.equal(state.results.south.status, "warning");
});

test("reports center drift, baseline noise, and deficient range as warnings", () => {
  let state = Diagnostics.startSession(controller(), profile);
  state = baseline(state, [
    { leftx: 0.2, lefty: 0, rightx: 0, righty: 0 },
    { leftx: 0.3, lefty: 0, rightx: 0, righty: 0 }
  ]);
  state = Diagnostics.advancePhase(exerciseDigital(state));
  state = Diagnostics.ingest(state, input("41", {}, { leftx: -0.3 }));
  state = Diagnostics.ingest(state, input("41", {}, { leftx: 0.5 }));
  state = Diagnostics.finalize(state);
  assert.equal(state.results.leftx.status, "warning");
  assert.ok(state.results.leftx.center > profile.thresholds.centerOffsetWarning);
  assert.ok(state.results.leftx.noise > profile.thresholds.neutralJitterWarning);
});

test("distinguishes missing, partial, and unavailable input", () => {
  const limited = controller({
    capabilities: { buttons: ["south", "left_stick"], axes: ["leftx", "lefty", "rightx", "righty"] }
  });
  let state = baseline(Diagnostics.startSession(limited, profile));
  state = Diagnostics.ingest(state, input("41", { south: true }));
  state = Diagnostics.finalize(state);
  assert.equal(state.results.north.status, "unavailable");
  assert.equal(state.results.left_trigger.status, "unavailable");
  assert.equal(state.results.south.status, "incomplete");
  assert.equal(state.results.left_stick.status, "not_detected");
  assert.equal(state.results.leftx.status, "incomplete");
});

test("treats one-sided analog movement as a warning", () => {
  let state = baseline(Diagnostics.startSession(controller(), profile));
  state = Diagnostics.advancePhase(exerciseDigital(state));
  state = Diagnostics.ingest(state, input("41", {}, { leftx: 0.9 }));
  state = Diagnostics.finalize(state);
  assert.equal(state.results.leftx.status, "warning");
});

test("early review leaves stages that were never offered incomplete", () => {
  const state = Diagnostics.finalize(baseline(Diagnostics.startSession(controller(), profile)));
  assert.equal(state.results.south.status, "not_detected");
  assert.equal(state.results.leftx.status, "incomplete");
  assert.equal(state.results.rightx.status, "incomplete");
});

test("canceling an active session preserves connection and records an incomplete review", () => {
  let state = Diagnostics.cancelSession(baseline(Diagnostics.startSession(controller(), profile)));
  assert.equal(state.phase, "review");
  assert.equal(state.connected, true);
  assert.equal(state.status, "incomplete");
  state = Diagnostics.finalize(state);
  assert.equal(state.status, "incomplete");
  assert.equal(state.results.south.status, "incomplete");
});

test("retry resets only one digital or analog control", () => {
  let state = successfulSession();
  state = Diagnostics.retryControl(state, "south");
  assert.equal(state.phase, "digital");
  assert.equal(state.results.south.status, "incomplete");
  assert.equal(state.results.north.status, "passed");
  state = Diagnostics.ingest(state, input("41", { south: true }));
  state = Diagnostics.ingest(state, input("41", { south: false }));
  state = Diagnostics.finalize(state);
  assert.equal(state.results.south.status, "passed");

  state = Diagnostics.retryControl(state, "rightx");
  assert.equal(state.phase, "analog_right");
  assert.equal(state.results.rightx.minimum, null);
  assert.equal(state.results.righty.status, "passed");
  const rightySamples = state.results.righty.samples;
  state = Diagnostics.ingest(state, input("41", {}, { righty: 0 }));
  assert.equal(state.results.righty.samples, rightySamples);
  state = Diagnostics.finalize(exerciseAxis(state, "rightx"));
  assert.equal(state.results.rightx.status, "passed");
});

test("session remains bound to its original controller through selection changes", () => {
  let state = baseline(Diagnostics.startSession(controller(), profile));
  const ignored = Diagnostics.ingest(state, input("99", { south: true }));
  assert.equal(ignored, state);
  assert.equal(Diagnostics.disconnect(state, "99"), state);
  state = Diagnostics.disconnect(state, "41");
  assert.equal(state.connected, false);
  assert.equal(state.phase, "review");
  assert.equal(state.status, "incomplete");
  assert.equal(Diagnostics.retryControl(state, "south"), state);
});

test("all emitted result statuses use the fixed vocabulary", () => {
  const allowed = new Set(["passed", "warning", "not_detected", "incomplete", "unavailable"]);
  const states = [successfulSession(), Diagnostics.finalize(baseline(Diagnostics.startSession(controller(), profile)))];
  for (const state of states) {
    assert.ok(allowed.has(state.status));
    for (const result of Object.values(state.results)) assert.ok(allowed.has(result.status));
  }
});

test("report projection is deterministic and excludes or redacts private data", () => {
  const privateController = controller({
    id: "secret-session-id",
    name: "Pad from /home/alice/private",
    serial: "SERIAL-SECRET",
    mac: "aa:bb:cc:dd:ee:ff",
    path: "/dev/input/event9",
    username: "alice"
  });
  let state = Diagnostics.startSession(privateController, profile);
  state = Diagnostics.disconnect(state, "secret-session-id");
  const metadata = {
    pluginVersion: "1.0.0",
    omarchyVersion: "4.0.2",
    kernelVersion: "7.1.9",
    sdlVersion: "3.4.14",
    username: "alice",
    serial: "SERIAL-SECRET",
    backendWarningCodes: ["mapping_failed", "AA-BB-CC-DD-EE-FF", "serial_ABC123"],
    unrelated: { path: "/tmp/private" }
  };
  const first = Diagnostics.createReport(state, metadata);
  const second = Diagnostics.createReport(state, metadata);
  assert.equal(JSON.stringify(first), JSON.stringify(second));
  const json = JSON.stringify(first);
  for (const secret of ["secret-session-id", "SERIAL-SECRET", "aa:bb:cc:dd:ee:ff", "/home/alice", "/dev/input", "/sys/class", "/etc/private", "/tmp/private"]) {
    assert.equal(json.includes(secret), false, secret);
  }
  assert.deepEqual(Object.keys(first.controller).sort(), [
    "battery", "connection", "family", "name", "productId", "sdlType",
    "supportedAxes", "supportedButtons", "vendorId"
  ]);
  assert.equal(Diagnostics.formatReport(state, metadata).includes("secret-session-id"), false);
  assert.equal(first.controller.name, "Test Pad Profile");
  assert.equal(first.controller.battery.available, true);
  assert.equal(first.controller.battery.state, "charging");
  assert.equal(first.backendWarningCodes.join(","), "mapping_failed,backend_warning");
});

test("diagnostic replay fixtures drive success, warning, missing, and disconnect outcomes", () => {
  const success = replayFixture("diagnostic-success.ndjson");
  let state = Diagnostics.startSession(success[1].controllers[0], SwitchPro.profile);
  state = Diagnostics.finishBaseline(Diagnostics.startBaseline(state));
  for (const message of success.slice(2, 6)) state = Diagnostics.ingest(state, message);
  state = Diagnostics.advancePhase(state);
  for (const message of success.slice(6, 8)) state = Diagnostics.ingest(state, message);
  state = Diagnostics.advancePhase(state);
  for (const message of success.slice(8)) state = Diagnostics.ingest(state, message);
  state = Diagnostics.advancePhase(state);
  assert.equal(state.status, "passed");

  const drift = replayFixture("diagnostic-drift-warning.ndjson");
  state = Diagnostics.startBaseline(Diagnostics.startSession(drift[1].controllers[0], SwitchPro.profile));
  state = Diagnostics.finishBaseline(Diagnostics.ingest(state, drift[2]));
  state = Diagnostics.advancePhase(state);
  state = Diagnostics.ingest(Diagnostics.ingest(state, drift[3]), drift[4]);
  state = Diagnostics.finalize(state);
  assert.equal(state.results.leftx.status, "warning");

  const missing = replayFixture("diagnostic-missing-button.ndjson");
  state = Diagnostics.finishBaseline(Diagnostics.startBaseline(
    Diagnostics.startSession(missing[1].controllers[0], SwitchPro.profile)
  ));
  state = Diagnostics.ingest(Diagnostics.ingest(state, missing[2]), missing[3]);
  state = Diagnostics.finalize(state);
  assert.equal(state.results.south.status, "passed");
  assert.equal(state.results.east.status, "not_detected");

  const disconnected = replayFixture("diagnostic-disconnect.ndjson");
  state = Diagnostics.finishBaseline(Diagnostics.startBaseline(
    Diagnostics.startSession(disconnected[1].controllers[0], SwitchPro.profile)
  ));
  state = Diagnostics.ingest(state, disconnected[2]);
  state = Diagnostics.disconnect(state, disconnected[3].id);
  assert.equal(state.status, "incomplete");
  assert.equal(state.connected, false);
});
