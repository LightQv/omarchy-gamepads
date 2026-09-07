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
  assert.equal(Registry.validateProfile(SwitchPro.profile), true);
});
