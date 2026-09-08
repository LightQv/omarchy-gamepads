const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const repositoryRoot = path.join(__dirname, "..");
const contract = JSON.parse(fs.readFileSync(
  path.join(repositoryRoot, "models/switch-pro/asset-contract.json"), "utf8"
));
const profileContext = {};
vm.createContext(profileContext);
vm.runInContext(
  fs.readFileSync(path.join(repositoryRoot, "profiles/switch-pro/Profile.js"), "utf8"),
  profileContext,
  { filename: "profiles/switch-pro/Profile.js" }
);

const finiteVector = (value, length = 3) => Array.isArray(value)
  && value.length === length
  && value.every(Number.isFinite);

function assertExactKeys(value, expected) {
  assert.deepEqual(Object.keys(value).sort(), [...expected].sort());
}

test("asset contract matches the frozen profile inventory", () => {
  const names = contract.parts.map((part) => part.name);
  assert.deepEqual(names, Array.from(profileContext.profile.modelParts));
  assert.equal(new Set(names).size, names.length);
});

test("asset hierarchy preserves composable stick pivots", () => {
  const parts = new Map(contract.parts.map((part) => [part.name, part]));
  assert.equal(parts.get("left_stick").type, "EMPTY");
  assert.equal(parts.get("right_stick").type, "EMPTY");
  assert.equal(parts.get("button_left_stick").parent, "left_stick");
  assert.equal(parts.get("button_right_stick").parent, "right_stick");

  for (const part of contract.parts) {
    assertExactKeys(part, ["name", "type", "parent", "motion", "neutralTransform"]);
    assert.match(part.name, /^[a-z][a-z0-9_]*$/);
    assert.ok(["MESH", "EMPTY"].includes(part.type));
    assert.ok(part.parent === "controller_root" || parts.has(part.parent));
    assert.ok(Object.hasOwn(contract.motion, part.motion));
    assertExactKeys(part.neutralTransform, ["position", "rotationDegrees", "scale", "pivot"]);
    assert.ok(finiteVector(part.neutralTransform.position));
    assert.ok(finiteVector(part.neutralTransform.rotationDegrees));
    assert.ok(finiteVector(part.neutralTransform.scale));
    assert.ok(part.neutralTransform.scale.every((value) => value > 0));
    assert.ok(finiteVector(part.neutralTransform.pivot));

    const ancestors = new Set([part.name]);
    let parent = part.parent;
    while (parent !== "controller_root") {
      assert.equal(ancestors.has(parent), false, `cycle at ${part.name}`);
      ancestors.add(parent);
      parent = parts.get(parent).parent;
    }
  }
});

test("asset limits and motion conventions are complete", () => {
  assertExactKeys(contract, [
    "schemaVersion", "units", "referenceDimensions", "coordinateSystem", "root",
    "bounds", "sceneEnvelope", "budgets", "motion", "parts", "conversion",
    "manifestSchema", "runtime"
  ]);
  assert.equal(contract.schemaVersion, 2);
  assert.equal(contract.units.name, "logical_scene_unit");
  assert.ok(Number.isFinite(contract.units.millimetersPerUnit));
  assert.ok(contract.units.millimetersPerUnit > 0);
  assertExactKeys(contract.referenceDimensions, [
    "model", "publisher", "title", "canonicalUrl", "accessed", "measurementKind",
    "millimeters"
  ]);
  assert.equal(contract.referenceDimensions.model, "HAC-013");
  assert.equal(contract.referenceDimensions.publisher, "Nintendo");
  assert.equal(contract.referenceDimensions.title, "Nintendo Switch Pro Controller");
  assert.equal(
    contract.referenceDimensions.canonicalUrl,
    "https://www.nintendo.com/sg/hardware/switch/accessories/procon.html"
  );
  assert.match(contract.referenceDimensions.accessed, /^\d{4}-\d{2}-\d{2}$/);
  assert.equal(contract.referenceDimensions.measurementKind, "maximum_overall_dimensions");
  assert.deepEqual(contract.referenceDimensions.millimeters, {
    width: 152,
    height: 106,
    depth: 60
  });
  assertExactKeys(contract.coordinateSystem, ["blender", "qtQuick3D", "blenderToQt"]);
  assert.deepEqual(contract.coordinateSystem.blenderToQt, ["x", "z", "-y"]);
  assertExactKeys(contract.root, ["name", "neutralTransform"]);
  assert.equal(contract.root.name, "controller_root");
  assertExactKeys(contract.root.neutralTransform, ["position", "rotationDegrees", "scale", "pivot"]);
  assert.deepEqual(contract.root.neutralTransform, {
    position: [0, 0, 0],
    rotationDegrees: [0, 0, 0],
    scale: [1, 1, 1],
    pivot: [0, 0, 0]
  });

  assertExactKeys(contract.bounds, [
    "space", "aggregateTarget", "aggregateTolerance", "projectToleranceMillimeters",
    "tolerancePolicy", "centerTolerance"
  ]);
  assert.equal(contract.bounds.space, "qt_neutral_logical_scene_units");
  assert.equal(contract.bounds.projectToleranceMillimeters, 1.5);
  assert.equal(
    contract.bounds.tolerancePolicy,
    "authoring_allowance_for_reference_and_export_rounding"
  );
  assertExactKeys(contract.bounds.aggregateTarget, ["width", "height", "depth"]);
  assertExactKeys(contract.bounds.aggregateTolerance, ["width", "height", "depth"]);
  assertExactKeys(contract.sceneEnvelope, ["space", "width", "height", "depth"]);
  assert.equal(contract.sceneEnvelope.space, contract.bounds.space);
  for (const dimension of ["width", "height", "depth"]) {
    const envelope = contract.sceneEnvelope[dimension];
    const expectedTarget = contract.referenceDimensions.millimeters[dimension]
      / contract.units.millimetersPerUnit;
    const expectedTolerance = contract.bounds.projectToleranceMillimeters
      / contract.units.millimetersPerUnit;
    const target = contract.bounds.aggregateTarget[dimension];
    const tolerance = contract.bounds.aggregateTolerance[dimension];
    assertExactKeys(envelope, ["minimum", "maximum"]);
    assert.ok(envelope.minimum > 0 && envelope.minimum < envelope.maximum);
    assert.ok(Math.abs(target - expectedTarget) < 0.000001);
    assert.ok(Math.abs(tolerance - expectedTolerance) < 0.000001);
    assert.ok(target - tolerance >= envelope.minimum);
    assert.ok(target + tolerance <= envelope.maximum);
  }
  assert.ok(contract.bounds.centerTolerance >= 0);

  const budgets = contract.budgets;
  for (const value of Object.values(budgets)) {
    assert.ok(Number.isInteger(value));
    assert.ok(value > 0);
  }
  assert.ok(budgets.maximumTrianglesPerMesh <= budgets.maximumTriangles);
  assertExactKeys(contract.motion, ["fixed", "depress", "stick"]);
  assert.deepEqual(contract.motion.fixed, { kind: "fixed" });
  assertExactKeys(contract.motion.depress, ["kind", "localAxis", "distanceProfileField"]);
  assert.equal(contract.motion.depress.kind, "translation");
  assert.deepEqual(contract.motion.depress.localAxis, [0, 0, -1]);
  assert.equal(contract.motion.depress.distanceProfileField, "animation.digitalTravel");
  assertExactKeys(contract.motion.stick, ["kind", "xInput", "yInput"]);
  assert.equal(contract.motion.stick.kind, "rotation");
  assertExactKeys(contract.motion.stick.xInput, ["localAxis", "degreesProfileField"]);
  assertExactKeys(contract.motion.stick.yInput, ["localAxis", "degreesProfileField"]);
  assert.deepEqual(contract.motion.stick.xInput.localAxis, [0, -1, 0]);
  assert.deepEqual(contract.motion.stick.yInput.localAxis, [1, 0, 0]);
  assert.equal(contract.motion.stick.xInput.degreesProfileField, "animation.stickTiltDegrees");
  assert.equal(contract.motion.stick.yInput.degreesProfileField, "animation.stickTiltDegrees");
  assert.equal(contract.parts.filter((part) => part.motion === "stick").length, 2);
});

test("conversion and runtime contracts are deterministic and safe", () => {
  const blender = contract.conversion.blender;
  assert.equal(blender.supportedVersion, "5.2.x");
  assert.equal(blender.format, "GLB");
  assert.equal(blender.exportYUp, true);
  for (const setting of [
    "exportAnimations", "exportCameras", "exportLights", "exportTangents",
    "exportExtras", "exportApply"
  ]) assert.equal(blender[setting], false);
  assert.equal(blender.compression, "none");

  const balsam = contract.conversion.balsam;
  assert.equal(balsam.qtQuick3DVersion, "6.11.2");
  assert.equal(balsam.assimpMajorVersion, 6);
  assert.deepEqual(balsam.arguments, []);
  assert.deepEqual(balsam.forbiddenOptions, [
    "preTransformVertices", "optimizeGraph", "optimizeMeshes"
  ]);
  assert.equal(contract.conversion.generatedQmlPolicy, "verify_mesh_mapping_then_discard");
  assert.equal(contract.conversion.runtimeQmlPolicy, "hand_owned_semantic_nodes_use_manifest_meshes");

  const safeRelativePath = /^(?!\/)(?!.*(?:^|\/)\.\.(?:\/|$))[a-z0-9][a-z0-9./-]*$/;
  assert.equal(contract.runtime.canonicalSource, "source/switch-pro.blend");
  assert.equal(contract.runtime.temporaryWorkspace, "work");
  assert.equal(contract.runtime.temporaryInterchange, "work/switch-pro.glb");
  assert.equal(contract.runtime.conditionedDirectory, "runtime/meshes");
  assert.equal(contract.runtime.conditionedFormat, "mesh");
  assert.equal(contract.runtime.manifest, "runtime/manifest.json");
  for (const value of Object.values(contract.runtime)) {
    assert.equal(typeof value, "string");
    assert.match(value, safeRelativePath);
  }

  const manifest = contract.manifestSchema;
  assert.equal(manifest.schemaVersion, 1);
  assert.deepEqual(manifest.requiredTopLevelFields, [
    "schemaVersion", "toolchain", "sourceSha256", "contractSha256", "meshes"
  ]);
  assert.deepEqual(manifest.requiredToolchainFields, [
    "blender", "qtQuick3D", "balsam", "assimp"
  ]);
  assert.deepEqual(manifest.requiredMeshFields, [
    "part", "path", "sha256", "triangles", "materialSlots", "bounds"
  ]);
  assert.doesNotThrow(() => new RegExp(manifest.sha256Pattern));
  assert.match("0".repeat(64), new RegExp(manifest.sha256Pattern));
  assert.doesNotThrow(() => new RegExp(manifest.meshPathPattern));
  assert.match("meshes/button_a.mesh", new RegExp(manifest.meshPathPattern));
  assert.equal(manifest.meshCoverage, "all_mesh_parts_exactly_once");
  assert.deepEqual(manifest.uniqueMeshFields, ["part", "path"]);
  assert.equal(manifest.boundsSpace, "part_local_logical_scene_units");
  assert.deepEqual(manifest.boundsFields, ["minimum", "maximum"]);
  assert.equal(manifest.boundsVectorLength, 3);
  assert.deepEqual(manifest.fieldTypes, {
    schemaVersion: "integer",
    toolchain: "object",
    sourceSha256: "string",
    contractSha256: "string",
    meshes: "array",
    "mesh.part": "string",
    "mesh.path": "string",
    "mesh.sha256": "string",
    "mesh.triangles": "positive_integer",
    "mesh.materialSlots": "positive_integer",
    "mesh.bounds": "object"
  });

  const meshParts = contract.parts.filter((part) => part.type === "MESH").map((part) => part.name);
  assert.equal(new Set(meshParts).size, meshParts.length);
  assert.equal(meshParts.length, contract.parts.length - 2);
});
