const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "..", "Model.js"), "utf8");
const Model = {};
vm.createContext(Model);
vm.runInContext(source, Model, { filename: "Model.js" });

function fixture(name) {
  return fs.readFileSync(path.join(__dirname, "fixtures", name), "utf8")
    .trim()
    .split("\n")
    .map(JSON.parse);
}

function reduceAll(messages) {
  let state = Model.initialState();
  for (const message of messages) {
    const result = Model.reduceMessage(state, message);
    assert.equal(result.accepted, true, result.error);
    state = result.state;
  }
  return state;
}

test("requires a supported hello before state", () => {
  const state = Model.initialState();
  const early = Model.reduceMessage(state, { type: "snapshot", sequence: 1, controllers: [] });
  assert.equal(early.accepted, false);
  assert.equal(early.error, "state message before hello");

  const unsupported = Model.reduceMessage(state, {
    type: "hello", backend: "sdl3", protocol: 2, version: "3.4.14"
  });
  assert.equal(unsupported.accepted, false);
});

test("enforces protocol controller ids and safe sequences", () => {
  let state = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2));
  for (const id of ["0", "01", "1".repeat(21)]) {
    assert.equal(Model.reduceMessage(state, {
      type: "removed", id, sequence: 2
    }).accepted, false);
  }
  assert.equal(Model.reduceMessage(state, {
    type: "removed", id: "3", sequence: Number.MAX_SAFE_INTEGER + 1
  }).accepted, false);
});

test("loads a deterministic snapshot and defaults selection", () => {
  const state = reduceAll(fixture("two-switch-pro.ndjson").slice(0, 2));
  assert.equal(state.status, "ready");
  assert.equal(state.controllers.length, 2);
  assert.equal(state.selectedId, "11");
  assert.equal(Model.selectedController(state).connection, "wired");
});

test("merges input without mutating prior state", () => {
  const messages = fixture("two-switch-pro.ndjson");
  const before = reduceAll(messages.slice(0, 2));
  const result = Model.reduceMessage(before, messages[2]);
  assert.equal(result.accepted, true);
  assert.equal(before.controllers[1].buttons.south, false);
  assert.equal(result.state.controllers[1].buttons.south, true);
});

test("keeps selection by id and chooses adjacent controller on removal", () => {
  const messages = fixture("two-switch-pro.ndjson");
  let state = reduceAll(messages.slice(0, 2));
  state = Model.selectController(state, "12");
  assert.equal(state.selectedId, "12");

  const removeFirst = Model.reduceMessage(state, messages[3]);
  assert.equal(removeFirst.accepted, true);
  assert.equal(removeFirst.state.selectedId, "12");

  const removeSelected = Model.reduceMessage(removeFirst.state, {
    type: "removed", id: "12", sequence: 4
  });
  assert.equal(removeSelected.state.selectedId, "");
});

test("cycles controller selection", () => {
  let state = reduceAll(fixture("two-switch-pro.ndjson").slice(0, 2));
  state = Model.cycleSelection(state, 1);
  assert.equal(state.selectedId, "12");
  state = Model.cycleSelection(state, 1);
  assert.equal(state.selectedId, "11");
  state = Model.cycleSelection(state, -1);
  assert.equal(state.selectedId, "12");
});

test("rejects stale sequences and unknown controllers", () => {
  const state = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2));
  assert.equal(Model.reduceMessage(state, {
    type: "removed", id: "3", sequence: 1
  }).accepted, false);
  assert.equal(Model.reduceMessage(state, {
    type: "input", id: "99", sequence: 2, buttons: {}, axes: {}
  }).accepted, false);
});

test("rejects invalid input values without changing state", () => {
  const state = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2));
  const result = Model.reduceMessage(state, {
    type: "input", id: "3", sequence: 2, buttons: {}, axes: { leftx: 2 }
  });
  assert.equal(result.accepted, false);
  assert.equal(result.state, state);
  assert.equal(state.lastSequence, 1);
});

test("replaces metadata on controller updates", () => {
  const state = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2));
  const changed = JSON.parse(JSON.stringify(state.controllers[0]));
  changed.connection = "wireless";
  changed.battery.state = "on_battery";
  const result = Model.reduceMessage(state, {
    type: "controller", sequence: 2, controller: changed
  });
  assert.equal(result.accepted, true);
  assert.equal(result.state.controllers[0].connection, "wireless");
  assert.equal(state.controllers[0].connection, "wired");
});

test("requires complete capability state", () => {
  const messages = fixture("switch-pro-usb.ndjson").slice(0, 2);
  const incomplete = JSON.parse(JSON.stringify(messages[1]));
  delete incomplete.controllers[0].buttons.south;
  let state = Model.initialState();
  state = Model.reduceMessage(state, messages[0]).state;
  assert.equal(Model.reduceMessage(state, incomplete).accepted, false);
});

test("rejects inherited object names and disruptive labels", () => {
  const state = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2));
  const prototypeField = JSON.parse(
    '{"type":"input","id":"3","sequence":2,"buttons":{},"axes":{"constructor":0}}'
  );
  assert.equal(Model.reduceMessage(state, prototypeField).accepted, false);

  const message = fixture("switch-pro-usb.ndjson")[1];
  message.controllers[0].name = "Controller\u202eabc";
  let initial = Model.reduceMessage(Model.initialState(), fixture("switch-pro-usb.ndjson")[0]).state;
  assert.equal(Model.reduceMessage(initial, message).accepted, false);
});

test("accepts later snapshots as heartbeat replacements", () => {
  const state = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2));
  const replacement = fixture("switch-pro-usb.ndjson")[1];
  replacement.sequence = 2;
  replacement.controllers[0].connection = "wireless";
  const result = Model.reduceMessage(state, replacement);
  assert.equal(result.accepted, true);
  assert.equal(result.state.controllers[0].connection, "wireless");
  assert.equal(result.state.selectedId, "3");
});

test("surfaces permanent dependency errors", () => {
  const state = reduceAll(fixture("dependency-error.ndjson"));
  assert.equal(state.status, "dependency-error");
  assert.equal(state.lastErrorCode, "dependency_missing");
});

test("formats nullable battery and connection state", () => {
  const usb = reduceAll(fixture("switch-pro-usb.ndjson").slice(0, 2)).controllers[0];
  assert.equal(Model.batteryLabel(usb), "Full");
  assert.equal(Model.batteryStateLabel(usb), "Charging");
  assert.equal(Model.batteryFraction(usb), 1);
  assert.equal(Model.connectionLabel(usb), "Wired");

  const unavailable = reduceAll(fixture("switch-pro-hotplug.ndjson").slice(0, 3)).controllers[0];
  assert.equal(Model.batteryLabel(unavailable), "Battery unavailable");
  assert.equal(Model.batteryStateLabel(unavailable), "");
  assert.equal(Model.batteryFraction(unavailable), -1);
  assert.equal(Model.connectionLabel(unavailable), "Unknown connection");
  assert.equal(Model.batteryIsLow(usb), false);

  const low = JSON.parse(JSON.stringify(usb));
  low.battery.level = "low";
  assert.equal(Model.batteryIsLow(low), true);
  assert.equal(Model.batteryFraction(low), 0.2);

  low.battery.percent = 15;
  low.battery.state = "on_battery";
  assert.equal(Model.batteryFraction(low), 0.15);
  assert.equal(Model.batteryStateLabel(low), "On battery");
});
