const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const repositoryRoot = path.join(__dirname, "..");
const contract = JSON.parse(fs.readFileSync(
  path.join(repositoryRoot, "models/switch-pro/asset-contract.json"), "utf8"
));
const modelRoot = path.join(repositoryRoot, "models/switch-pro");
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

function sha256(filePath) {
  return crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex");
}

function sectionAt(profile, z) {
  const byHeight = new Map();
  for (const [y, height] of profile.outlineYZ) {
    const [front, rear] = byHeight.get(height) ?? [Infinity, -Infinity];
    byHeight.set(height, [Math.min(y, front), Math.max(y, rear)]);
  }
  const rail = [...byHeight].sort((a, b) => a[0] - b[0]);
  const next = rail.findIndex(([height]) => height >= z);
  assert.ok(next > 0, "the actual skin must span every requested section height");
  const [lowZ, low] = rail[next - 1];
  const [highZ, high] = rail[next];
  return low.map((value, i) => value + (high[i] - value) * (z - lowZ) / (highZ - lowZ));
}

function rearAt(profile, z) {
  return sectionAt(profile, z)[1];
}

function assertRegularFile(filePath, maximumBytes) {
  const stats = fs.lstatSync(filePath);
  assert.equal(stats.isSymbolicLink(), false, `${filePath} must not be a symlink`);
  assert.equal(stats.isFile(), true, `${filePath} must be a regular file`);
  assert.ok(stats.size > 0 && stats.size <= maximumBytes, `${filePath} has an unsafe size`);
}

function assertReviewPng(filePath) {
  const image = fs.readFileSync(filePath);
  assert.equal(image.subarray(0, 8).toString("hex"), "89504e470d0a1a0a");
  let offset = 8;
  let sawHeader = false;
  let sawEnd = false;
  while (offset < image.length) {
    assert.ok(offset + 12 <= image.length, `${filePath} has a truncated PNG chunk`);
    const length = image.readUInt32BE(offset);
    const end = offset + 12 + length;
    assert.ok(end <= image.length, `${filePath} has an invalid PNG chunk length`);
    const type = image.subarray(offset + 4, offset + 8).toString("ascii");
    if (type === "IHDR") {
      assert.equal(offset, 8);
      assert.equal(length, 13);
      assert.equal(image.readUInt32BE(offset + 8), 1024);
      assert.equal(image.readUInt32BE(offset + 12), 768);
      assert.equal(image[offset + 16], 8);
      assert.equal(image[offset + 17], 2);
      sawHeader = true;
    }
    if (type === "IEND") {
      assert.equal(length, 0);
      assert.equal(end, image.length);
      sawEnd = true;
    }
    offset = end;
  }
  assert.equal(sawHeader, true, `${filePath} lacks IHDR`);
  assert.equal(sawEnd, true, `${filePath} lacks IEND`);
  return image;
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

test("asset front landmarks preserve the calibrated asymmetric controller layout", () => {
  const parts = new Map(contract.parts.map((part) => [part.name, part]));
  const expected = {
    left_stick: [-1.49, 0.74],
    right_stick: [0.73, 0.01],
    dpad_base: [-0.83, 0.01],
    button_x: [1.43, 1.11],
    button_a: [1.84, 0.74],
    button_b: [1.43, 0.37],
    button_y: [1.02, 0.74],
    button_minus: [-0.67, 1.17],
    button_plus: [0.67, 1.17],
    button_capture: [-0.38, 0.74],
    button_home: [0.38, 0.74]
  };
  for (const [name, position] of Object.entries(expected)) {
    assert.deepEqual(parts.get(name).neutralTransform.position.slice(0, 2), position);
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

test("source model checkpoint has reproducible tooling and review views", () => {
  for (const relativePath of [
    "models/switch-pro/asset-contract.json",
    "scripts/build-switch-pro-model.sh",
    "scripts/check-model-toolchain.sh"
  ]) assertRegularFile(path.join(repositoryRoot, relativePath), 1024 * 1024);
  for (const relativePath of [
    "source/switch-pro.blend",
    "tools/build_model.py",
    "tools/validate_model.py",
    "tools/render_review.py",
    "tools/test_validator.py",
    "tools/write_checkpoint.py",
    "checkpoint.json",
    "review/front.png",
    "review/rear.png",
    "review/left.png",
    "review/right.png",
    "review/perspective.png"
  ]) {
    const filePath = path.join(modelRoot, relativePath);
    const maximumBytes = relativePath.endsWith(".blend")
      ? contract.budgets.maximumSourceBytes
      : relativePath.endsWith(".png") ? 8 * 1024 * 1024 : 1024 * 1024;
    assertRegularFile(filePath, maximumBytes);
  }

  const builder = fs.readFileSync(path.join(modelRoot, "tools/build_model.py"), "utf8");
  assert.doesNotMatch(builder, /(?:https?:\/\/|bpy\.ops\.wm\.(?:append|link)|import_scene)/);
  assert.match(builder, /geometry_origin.*original_project_surface_cages/);

  const checkpoint = JSON.parse(fs.readFileSync(
    path.join(modelRoot, "checkpoint.json"), "utf8"
  ));
  assertExactKeys(checkpoint, [
    "schemaVersion", "contractSha256", "toolSha256", "source", "validation", "reviews",
    "referenceFit", "ownedReferenceFit", "animation", "reviewDecision"
  ]);
  assert.equal(checkpoint.schemaVersion, 1);
  assert.equal(checkpoint.contractSha256, sha256(path.join(modelRoot, "asset-contract.json")));
  assertExactKeys(checkpoint.toolSha256, [
    "models/switch-pro/tools/build_model.py",
    "models/switch-pro/tools/surface_maps.py",
    "models/switch-pro/tools/photo_profiles.py",
    "models/switch-pro/tools/photo_shape_profiles.json",
    "models/switch-pro/tools/owned_photo_landmarks.json",
    "models/switch-pro/tools/owned_photo_cameras.json",
    "models/switch-pro/tools/compare_owned_reference.py",
    "models/switch-pro/tools/reference_landmarks.json",
    "models/switch-pro/tools/reference_front_mask.json",
    "models/switch-pro/tools/compare_reference.py",
    "models/switch-pro/tools/validate_model.py",
    "models/switch-pro/tools/render_review.py",
    "models/switch-pro/tools/iterate_model.py",
    "models/switch-pro/tools/iterate_scene.py",
    "models/switch-pro/tools/compare_photo_views.py",
    "models/switch-pro/tools/test_validator.py",
    "models/switch-pro/tools/write_checkpoint.py",
    "scripts/build-switch-pro-model.sh",
    "scripts/check-model-toolchain.sh"
  ]);
  for (const [name, digest] of Object.entries(checkpoint.toolSha256)) {
    assert.equal(digest, sha256(path.join(repositoryRoot, name)));
  }
  assert.deepEqual(Object.keys(checkpoint.source).sort(), ["path", "sha256"]);
  assert.equal(checkpoint.source.path, "source/switch-pro.blend");
  assert.equal(
    checkpoint.source.sha256,
    sha256(path.join(modelRoot, checkpoint.source.path))
  );
  assertExactKeys(checkpoint.validation, [
    "sourceSha256", "sceneSha256", "semanticParts", "meshes", "triangles",
    "materials", "bounds", "center"
  ]);
  assert.equal(checkpoint.validation.sourceSha256, checkpoint.source.sha256);
  assert.match(checkpoint.validation.sceneSha256, /^[a-f0-9]{64}$/);
  assert.equal(checkpoint.validation.semanticParts, contract.parts.length);
  assert.equal(
    checkpoint.validation.meshes,
    contract.parts.filter((part) => part.type === "MESH").length
  );
  assert.ok(checkpoint.validation.triangles > 0);
  assert.ok(checkpoint.validation.triangles <= contract.budgets.maximumTriangles);
  assert.ok(checkpoint.validation.materials > 0);
  assert.ok(checkpoint.validation.materials <= contract.budgets.maximumMaterials);
  for (const dimension of ["width", "height", "depth"]) {
    assert.ok(Math.abs(
      checkpoint.validation.bounds[dimension] - contract.bounds.aggregateTarget[dimension]
    ) <= contract.bounds.aggregateTolerance[dimension]);
  }
  assert.ok(checkpoint.validation.center.every(
    (value) => Math.abs(value) <= contract.bounds.centerTolerance
  ));
  const expectedReviews = {
    front: "review/front.png",
    rear: "review/rear.png",
    left: "review/left.png",
    right: "review/right.png",
    perspective: "review/perspective.png",
    "perspective-dark": "review/perspective-dark.png",
    top: "review/top.png",
    bottom: "review/bottom.png",
    "rear-perspective": "review/rear-perspective.png",
    "top-perspective": "review/top-perspective.png",
    "bottom-perspective": "review/bottom-perspective.png",
    "low-side-perspective": "review/low-side-perspective.png",
    "low-front-perspective": "review/low-front-perspective.png",
    "owned-front": "review/owned-front.png",
    "owned-left": "review/owned-left.png",
    "owned-right": "review/owned-right.png",
    "owned-bottom": "review/owned-bottom.png",
    "owned-inverted-bottom": "review/owned-inverted-bottom.png",
    "owned-rear-quarter": "review/owned-rear-quarter.png",
    "owned-silhouettes": "review/owned-silhouettes.png",
    silhouette: "review/silhouette.png",
    turntable: "review/turntable.png"
  };
  assertExactKeys(checkpoint.reviews, Object.keys(expectedReviews));
  for (const [name, review] of Object.entries(checkpoint.reviews)) {
    assert.equal(review.path, expectedReviews[name]);
    const reviewPath = path.join(modelRoot, review.path);
    assertRegularFile(reviewPath, 8 * 1024 * 1024);
    assert.equal(review.sha256, sha256(reviewPath), `${name} review hash must match`);
    const image = assertReviewPng(reviewPath);
    for (const chunk of ["eXIf", "iTXt", "tEXt", "tIME", "zTXt"]) {
      assert.equal(image.includes(Buffer.from(chunk)), false, `${name} must omit ${chunk}`);
    }
  }
});

test("reference-fit evidence records geometry acceptance separately from material approval", () => {
  const checkpoint = JSON.parse(fs.readFileSync(path.join(modelRoot, "checkpoint.json"), "utf8"));
  const references = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/reference_landmarks.json"), "utf8"));
  for (const [name, expectedPath] of Object.entries({
    referenceFit: "review/fit.json", ownedReferenceFit: "review/owned-fit.json",
    animation: "review/turntable.gif", reviewDecision: "review-decision.json"
  })) {
    assert.equal(checkpoint[name].path, expectedPath);
    const filePath = path.join(modelRoot, expectedPath);
    assertRegularFile(filePath, 8 * 1024 * 1024);
    assert.equal(checkpoint[name].sha256, sha256(filePath));
  }
  const fit = JSON.parse(fs.readFileSync(path.join(modelRoot, checkpoint.referenceFit.path), "utf8"));
  assert.equal(fit.referenceSha256, references.sources.front.sha256);
  assert.equal(fit.reviewAppearance, "neutral_gray_geometry");
  assert.deepEqual(fit.turntableReview, { frames: 12, clearBorderPixels: 4, borderChecksPass: true });
  assert.equal(fit.referenceMaskSha256, sha256(path.join(modelRoot, "tools/reference_front_mask.json")));
  assert.ok(fit.intersectionPixels > 0 && fit.intersectionPixels <= fit.unionPixels);
  assert.ok(Math.abs(fit.frontSilhouetteIoU - fit.intersectionPixels / fit.unionPixels) < 0.000001);
  assert.deepEqual(Object.keys(fit.controlCenterErrorWidthFractions).sort(), Object.keys(references.controlCentersPixels).sort());
  assert.equal(fit.maximumControlCenterErrorWidthFraction, Math.max(...Object.values(fit.controlCenterErrorWidthFractions)));
  assert.equal(fit.imageSpaceChecksPass,
    fit.frontSilhouetteIoU >= references.acceptance.minimumFrontSilhouetteIoU
      && fit.maximumControlCenterErrorWidthFraction <= references.acceptance.maximumControlCenterErrorWidthFraction);
  assert.equal(fit.imageSpaceChecksPass, true, "the accepted front must retain its fit guardrail");
  const decision = JSON.parse(fs.readFileSync(path.join(modelRoot, checkpoint.reviewDecision.path), "utf8"));
  assert.equal(checkpoint.reviewDecision.appliesToSource, decision.sourceSha256 === checkpoint.source.sha256);
  assert.equal(checkpoint.reviewDecision.appliesToSource, true);
  assert.equal(decision.decision, "geometry_accepted");
  assert.equal(decision.reviewer, "stakeholder");
  assert.equal(decision.recommendation, "proceed_to_materials");
  assert.equal(decision.milestone, "geometry");
  assert.equal(decision.materialReview, "not_started");
  assert.deepEqual(references.acceptance.reviewMilestones, ["geometry", "materials"]);
  assert.equal(decision.previousCandidate.decision, "geometry_rejected");
  assert.ok(decision.previousCandidate.rejectionReasons.length > 0);
  assert.equal(decision.acceptedGeometryBaseline.decision, "partial_geometry_acceptance");
  assert.deepEqual(decision.acceptedGeometryBaseline.acceptedViews, ["front", "top", "rear"]);
  assert.equal(decision.earlierGeometryCandidate.decision, "front_top_accepted");
  assert.deepEqual(decision.earlierGeometryCandidate.acceptedViews, ["front", "top"]);
  assert.equal(decision.earlierRejectedCandidate.decision, "reject_for_production");
  assert.notEqual(decision.previousCandidate.sourceSha256, checkpoint.source.sha256);
  const baseline = decision.refinementBaseline;
  const shape = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/photo_shape_profiles.json"), "utf8"));
  assert.equal(baseline.decision, "geometry_refinement_requested");
  assert.equal(baseline.sourceSha256, shape.rearRefinement.baselineSourceSha256);
  assert.equal(baseline.sourceSha256, decision.comparisonEvidence.baselineSourceSha256);
  assert.equal(decision.discardedAttempt.decision, "discarded_by_stakeholder");
  assert.notEqual(baseline.sourceSha256, decision.discardedAttempt.sourceSha256);
  const geometry = fit.geometryEvidence;
  assert.ok(Number.isFinite(geometry.summedBodyVolume) && geometry.summedBodyVolume > 0);
  const controlShapes = geometry.controlShapeSha256;
  const controls = contract.parts.filter((part) => part.type === "MESH"
    && !["shell", "left_grip", "right_grip"].includes(part.name)).map((part) => part.name);
  assertExactKeys(controlShapes, controls);
  for (const hash of Object.values(controlShapes)) assert.match(hash, /^[a-f0-9]{64}$/);
  const controlDigest = crypto.createHash("sha256")
    .update(JSON.stringify(Object.entries(controlShapes).sort())).digest("hex");
  assert.equal(controlDigest, baseline.controlShapesDigest);
  assert.ok(geometry.sections.length > 0);
  let previousHeight = -Infinity;
  for (const section of geometry.sections) {
    assert.ok(Number.isFinite(section.height) && section.height > previousHeight);
    previousHeight = section.height;
    for (const depth of [section.centerDepth, section.gripDepth]) {
      assert.ok(depth === null || (Number.isFinite(depth) && depth > 0));
    }
  }
  assert.ok(Math.abs(decision.comparisonEvidence.bodyVolumeChangeFraction
    - (geometry.summedBodyVolume / baseline.summedBodyVolume - 1)) < 0.000001);
  assertExactKeys(geometry.longitudinalProfiles, ["bridge", "rightGrip"]);
  for (const [name, profile] of Object.entries(geometry.longitudinalProfiles)) {
    const previous = baseline.longitudinalProfiles[name];
    assert.equal(profile.planeX, previous.planeX);
    assert.equal(profile.nearMinimumRise, previous.nearMinimumRise);
    for (const points of [profile.outlineYZ, profile.undersideYZ]) {
      assert.ok(points.length > 50);
      for (const point of points) {
        assert.equal(point.length, 2);
        assert.ok(point.every((value) => Number.isFinite(value) && Math.abs(value) < 4));
      }
    }
    assert.equal(profile.minimumZ, Math.min(...profile.undersideYZ.map((point) => point[1])));
    const near = profile.undersideYZ.filter((point) => point[1] <= profile.minimumZ + profile.nearMinimumRise);
    assert.ok(Math.abs(profile.nearMinimumDepthSpan - (near.at(-1)[0] - near[0][0])) < 0.000001);
    assert.ok(Math.abs(decision.comparisonEvidence.minimumPositionShiftY[name]
      - (profile.minimumPositionY - previous.minimumPositionY)) < 0.000001);
  }
  assert.ok(Math.abs(geometry.longitudinalProfiles.rightGrip.minimumPositionY
    - baseline.longitudinalProfiles.rightGrip.minimumPositionY) < 0.02,
    "handle thinning must preserve the baseline rearward grip-end position");
  assert.ok(geometry.longitudinalProfiles.bridge.minimumPositionY < -0.3,
    "the central underside retains its forward lip");
  const gif = fs.readFileSync(path.join(modelRoot, checkpoint.animation.path));
  assert.match(gif.subarray(0, 6).toString(), /^GIF8[79]a$/);
  assert.equal(gif.readUInt16LE(6), 384);
  assert.equal(gif.readUInt16LE(8), 288);
  assert.equal(gif[gif.length - 1], 0x3b);
});

test("rebuilt rear mesh tapers continuously through the central and side-waist joins", () => {
  const fit = JSON.parse(fs.readFileSync(path.join(modelRoot, "review/fit.json"), "utf8"));
  const geometry = fit.geometryEvidence;
  for (const profile of [geometry.longitudinalProfiles.bridge, geometry.waistProfile]) {
    // These are authoring guardrails for the requested shape, not measurements
    // of manufacturing accuracy. Evaluate the built skin, not its input curve.
    assert.ok(rearAt(profile, 0) < 0.36, "the mid-height rear must form a slimmer wedge");
    assert.ok(rearAt(profile, 0.6) - rearAt(profile, 0) > 0.20, "the taper must start above the underside");
    const angles = [];
    for (let step = 0; step < 31; step++) {
      const z = -0.65 + step * 0.05;
      const slope = (rearAt(profile, z + 0.05) - rearAt(profile, z)) / 0.05;
      assert.ok(slope > 0, "rear profile must not reverse at the former cap/rim join");
      angles.push(Math.atan(slope));
    }
    for (let i = 1; i < angles.length; i++) {
      assert.ok(Math.abs(angles[i] - angles[i - 1]) < 6 * Math.PI / 180,
        "a rear section must not contain a sharp kink or a narrow transition band");
    }
    assert.ok(angles[0] > angles.at(-1) + 20 * Math.PI / 180,
      "the lower turn must be stronger than the upper taper");
  }
  assert.equal(geometry.waistProfile.planeX, 1.25);
  const baseline = JSON.parse(fs.readFileSync(path.join(modelRoot, "review-decision.json"), "utf8")).refinementBaseline;
  for (const [name, samples] of Object.entries(baseline.centralRearSamplesZY)) {
    const profile = name === "waist" ? geometry.waistProfile : geometry.longitudinalProfiles[name];
    for (const [z, y] of samples) {
      assert.ok(Math.abs(rearAt(profile, z) - y) < 0.001,
        "handle refinement must preserve the improved central rear within mesh simplification tolerance");
    }
  }
});

test("both handle skins are shallower with a stronger continuous root-to-palm turn", () => {
  const geometry = JSON.parse(fs.readFileSync(path.join(modelRoot, "review/fit.json"), "utf8")).geometryEvidence;
  const baseline = JSON.parse(fs.readFileSync(path.join(modelRoot, "review-decision.json"), "utf8")).refinementBaseline;
  assertExactKeys(geometry.handleProfiles, ["leftGrip", "rightGrip"]);
  assert.deepEqual(geometry.handleProfiles.rightGrip, geometry.longitudinalProfiles.rightGrip);
  for (const [name, profile] of Object.entries(geometry.handleProfiles)) {
    assert.equal(profile.planeX, name === "leftGrip" ? -2.16 : 2.16);
    for (const [z, oldDepth] of baseline.handleDepthsMillimeters[name]) {
      const [front, rear] = sectionAt(profile, z);
      const depth = (rear - front) * contract.units.millimetersPerUnit;
      const reduction = 1 - depth / oldDepth;
      assert.ok(reduction > 0.04 && reduction < 0.30, "thin every sampled region without flattening the palm");
      if (z >= -0.3 && z <= 0.6) {
        assert.ok(oldDepth - depth > 4, "the upper/middle handle must be measurably shallower");
      }
    }
    const turn = (Math.atan((rearAt(profile, 0.85) - rearAt(profile, 0.60)) / 0.25)
      - Math.atan((rearAt(profile, 0) - rearAt(profile, -0.35)) / 0.35)) * 180 / Math.PI;
    assert.ok(turn > baseline.handleRearTurnDegrees[name] + 20 && turn < 55,
      "a thinner section must also have a stronger, bounded root-to-palm curve");
    let previousAngle;
    for (let step = 0; step < 36; step++) {
      const z = -0.9 + step * 0.05;
      const angle = Math.atan((rearAt(profile, z + 0.05) - rearAt(profile, z)) / 0.05);
      if (previousAngle !== undefined) {
        assert.ok(Math.abs(angle - previousAngle) < 10 * Math.PI / 180,
          "the handle rear must not introduce a sharp transition band");
      }
      previousAngle = angle;
    }
  }
});

test("reference comparison cameras reproduce their declared landmark residuals", () => {
  const references = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/reference_landmarks.json"), "utf8"));
  const points = references.perspectiveComparisonPolicy.worldCenters;
  assert.equal(points.length, references.perspectiveComparisonPolicy.landmarkOrder.length);
  assertExactKeys(references.perspectiveComparisons, ["low-side-perspective", "low-front-perspective"]);
  for (const view of Object.values(references.perspectiveComparisons)) {
    const source = references.sources[view.source];
    const [x0, y0, x1, y1] = view.crop;
    assert.ok(x0 >= 0 && y0 >= 0 && x1 <= source.size[0] && y1 <= source.size[1]);
    const width = x1 - x0;
    const height = y1 - y0;
    assert.ok(width > 0 && height > 0);
    assert.ok(view.lensMillimeters > 0);
    assert.equal(view.controlFaceCentersPixels.length, points.length);
    const matrix = view.rotationMatrix;
    for (let a = 0; a < 3; a++) {
      for (let b = 0; b < 3; b++) {
        const dot = matrix.reduce((sum, row) => sum + row[a] * row[b], 0);
        assert.ok(Math.abs(dot - (a === b ? 1 : 0)) < 0.000001);
      }
    }
    const errors = points.map((point, index) => {
      const relative = point.map((value, axis) => value - view.location[axis]);
      const local = [0, 1, 2].map((axis) => relative.reduce((sum, value, row) => sum + value * matrix[row][axis], 0));
      assert.ok(local[2] < 0, "comparison landmarks must be in front of the camera");
      const focal = view.lensMillimeters * width / 36;
      const projected = [width / 2 + focal * local[0] / -local[2], height / 2 - focal * local[1] / -local[2]];
      const observed = view.controlFaceCentersPixels[index];
      return Math.hypot(projected[0] - (observed[0] - x0), projected[1] - (observed[1] - y0));
    });
    const rms = Math.sqrt(errors.reduce((sum, error) => sum + error ** 2, 0) / errors.length);
    assert.ok(Math.abs(rms - view.fitRmsPixels) < 0.0001);
    assert.ok(Math.abs(Math.max(...errors) - view.fitMaximumErrorPixels) < 0.0001);
    assert.ok(rms / width < 0.01, "camera alignment must retain its control-landmark fit");
  }
});

test("owned photograph cameras preserve their normalization and declared projections", () => {
  const references = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/owned_photo_landmarks.json"), "utf8"));
  const cameras = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/owned_photo_cameras.json"), "utf8"));
  const fit = JSON.parse(fs.readFileSync(path.join(modelRoot, "review/owned-fit.json"), "utf8"));
  assertExactKeys(references.sources, [
    "straight_front", "straight_back", "straight_top", "straight_top_2", "left_side",
    "ride_side", "straight_bottom", "upside_down_straight_bottom", "quarter_bottom_back"
  ]);
  for (const source of Object.values(references.sources)) {
    assert.match(source.sha256, /^[a-f0-9]{64}$/);
    assert.match(source.filename, /^[a-z0-9_]+\.jpeg$/);
    assert.ok(source.role.length > 0);
  }
  const normalization = references.normalization;
  assert.equal(normalization.applyExifOrientation, true);
  const [normalizedWidth, normalizedHeight] = normalization.orientationNormalizedSize;
  const [x0, y0, x1, y1] = normalization.cropAfterNormalization;
  const [width, height] = normalization.canonicalSize;
  const principal = normalization.principalPointPixels;
  assert.ok(x0 >= 0 && y0 >= 0 && x1 <= normalizedWidth && y1 <= normalizedHeight);
  assert.ok(x1 > x0 && y1 > y0);
  assert.ok(Math.abs(principal[0] - (normalizedWidth / 2 - x0) * width / (x1 - x0)) < 0.000001);
  assert.ok(Math.abs(principal[1] - (normalizedHeight / 2 - y0) * height / (y1 - y0)) < 0.000001);
  assertExactKeys(cameras, Object.keys(references.views));
  for (const [name, camera] of Object.entries(cameras)) {
    const view = references.views[name];
    const matrix = camera.rotationMatrix;
    assert.equal(matrix.length, 3);
    assert.ok(matrix.every((row) => row.length === 3 && row.every(Number.isFinite)));
    assert.ok(camera.location.length === 3 && camera.location.every(Number.isFinite));
    assert.ok(camera.lensMillimeters > 0);
    for (let a = 0; a < 3; a++) {
      for (let b = 0; b < 3; b++) {
        const dot = matrix.reduce((sum, row) => sum + row[a] * row[b], 0);
        assert.ok(Math.abs(dot - (a === b ? 1 : 0)) < 0.000001);
      }
    }
    const determinant = matrix[0][0] * (matrix[1][1] * matrix[2][2] - matrix[1][2] * matrix[2][1])
      - matrix[0][1] * (matrix[1][0] * matrix[2][2] - matrix[1][2] * matrix[2][0])
      + matrix[0][2] * (matrix[1][0] * matrix[2][1] - matrix[1][1] * matrix[2][0]);
    assert.ok(Math.abs(determinant - 1) < 0.000001);
    const vp = fit.views[name].viewProjectionMatrix;
    assert.ok(vp.length === 4 && vp.every((row) => row.length === 4 && row.every(Number.isFinite)));
    assert.equal(camera.projectedAnchors.length, view.anchors.length);
    const errors = view.anchors.map((anchor, index) => {
      const relative = anchor.world.map((value, axis) => value - camera.location[axis]);
      const local = [0, 1, 2].map((axis) => relative.reduce((sum, value, row) => sum + value * matrix[row][axis], 0));
      assert.ok(local[2] < 0);
      const focal = camera.lensMillimeters * width / 36;
      const projected = [principal[0] + focal * local[0] / -local[2], principal[1] - focal * local[1] / -local[2]];
      assert.ok(Math.hypot(...projected.map((value, axis) => value - camera.projectedAnchors[index][axis])) < 0.00001);
      const point = [...anchor.world, 1];
      const clip = vp.map((row) => row.reduce((sum, value, axis) => sum + value * point[axis], 0));
      assert.ok(clip[3] > 0);
      const rendered = [(0.5 + 0.5 * clip[0] / clip[3]) * width, (0.5 - 0.5 * clip[1] / clip[3]) * height];
      assert.ok(Math.hypot(...projected.map((value, axis) => value - rendered[axis])) < 0.002,
        `${name} Blender projection must match the recorded camera and crop`);
      return Math.hypot(...projected.map((value, axis) => value - anchor.pixel[axis]));
    });
    const rms = Math.sqrt(errors.reduce((sum, value) => sum + value ** 2, 0) / errors.length);
    assert.ok(Math.abs(rms - camera.fitRmsPixels) < 0.00001);
    assert.ok(Math.abs(Math.max(...errors) - camera.fitMaximumErrorPixels) < 0.00001);
  }
});

test("owned contour evidence binds source bytes and declares reconstruction fits", () => {
  const checkpoint = JSON.parse(fs.readFileSync(path.join(modelRoot, "checkpoint.json"), "utf8"));
  const references = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/owned_photo_landmarks.json"), "utf8"));
  const cameras = JSON.parse(fs.readFileSync(path.join(modelRoot, "tools/owned_photo_cameras.json"), "utf8"));
  const fit = JSON.parse(fs.readFileSync(path.join(modelRoot, "review/owned-fit.json"), "utf8"));
  const decision = JSON.parse(fs.readFileSync(path.join(modelRoot, "review-decision.json"), "utf8"));
  assert.equal(fit.sourceSha256, checkpoint.source.sha256);
  assert.equal(fit.landmarksSha256, sha256(path.join(modelRoot, "tools/owned_photo_landmarks.json")));
  assert.equal(fit.camerasSha256, sha256(path.join(modelRoot, "tools/owned_photo_cameras.json")));
  assert.equal(fit.profileSha256, sha256(path.join(modelRoot, "tools/photo_shape_profiles.json")));
  assert.deepEqual(fit.maskSize, references.normalization.canonicalSize);
  assert.equal(fit.maskMethod, "main_connected_grip_skin_triangle_raster_and_manual_photo_polygon");
  assertExactKeys(fit.views, Object.keys(references.views));
  let fitted = 0;
  const [width, height] = fit.maskSize;
  for (const [name, view] of Object.entries(fit.views)) {
    assert.equal(view.source, references.views[name].source);
    assert.equal(view.sourcePhotoSha256, references.sources[view.source].sha256);
    assert.equal(view.alignmentRole, cameras[name].alignmentRole);
    assert.ok(["joint_reconstruction_fit", "independent_control_fit"].includes(view.alignmentRole));
    assert.equal(view.cameraLandmarkRmsPixels, cameras[name].fitRmsPixels);
    if (view.alignmentRole === "joint_reconstruction_fit") fitted++;
    assertExactKeys(view.parts, Object.keys(references.views[name].gripOutlines));
    for (const part of Object.values(view.parts)) {
      for (const key of ["intersectionPixels", "unionPixels", "observedPixels", "projectedPixels"]) {
        assert.ok(Number.isSafeInteger(part[key]) && part[key] > 0 && part[key] <= width * height);
      }
      assert.ok(part.intersectionPixels <= Math.min(part.observedPixels, part.projectedPixels));
      assert.equal(part.unionPixels, part.observedPixels + part.projectedPixels - part.intersectionPixels);
      assert.ok(Math.abs(part.silhouetteIoU - part.intersectionPixels / part.unionPixels) < 0.000001);
      assert.match(part.observedMaskSha256, /^[a-f0-9]{64}$/);
      assert.match(part.projectedMaskSha256, /^[a-f0-9]{64}$/);
      const [low, high] = part.projectedBounds;
      assert.ok(low.every(Number.isFinite) && high.every(Number.isFinite));
      assert.ok(low[0] >= 2 && low[1] >= 2 && high[0] <= width - 2 && high[1] <= height - 2);
    }
  }
  assert.equal(fitted, 5);
  assert.equal(fit.views["owned-rear-quarter"].alignmentRole, "joint_reconstruction_fit");
  assert.equal(fit.views["owned-front"].alignmentRole, "independent_control_fit");
  assert.equal(decision.comparisonEvidence.ownedSideMaskIoU.left, fit.views["owned-left"].parts.left_grip.silhouetteIoU);
  assert.equal(decision.comparisonEvidence.ownedSideMaskIoU.right, fit.views["owned-right"].parts.right_grip.silhouetteIoU);
  for (const part of ["left_grip", "right_grip"]) {
    assert.equal(decision.comparisonEvidence.ownedRearObliqueMaskIoU[part],
      fit.views["owned-rear-quarter"].parts[part].silhouetteIoU);
  }
  assert.equal(decision.decision, "geometry_accepted");
});

test("accepted geometry milestone is recoverable independently of disposable work", () => {
  const decision = JSON.parse(fs.readFileSync(path.join(modelRoot, "review-decision.json"), "utf8"));
  const geometry = JSON.parse(fs.readFileSync(path.join(modelRoot, "review/fit.json"), "utf8")).geometryEvidence;
  assert.equal(decision.geometryMilestone, "milestones/geometry-v1/milestone.json");
  const milestone = JSON.parse(fs.readFileSync(path.join(modelRoot, decision.geometryMilestone), "utf8"));
  const checkpoint = JSON.parse(fs.readFileSync(path.join(modelRoot, "checkpoint.json"), "utf8"));
  assert.equal(milestone.milestone, "switch-pro-geometry-v1");
  assert.equal(milestone.decision, "geometry_accepted");
  assert.equal(milestone.reviewer, "stakeholder");
  assert.deepEqual(milestone.source, checkpoint.source);
  assert.equal(milestone.sceneSha256, checkpoint.validation.sceneSha256);
  assert.equal(milestone.contractSha256, checkpoint.contractSha256);
  assert.equal(milestone.source.sha256, decision.sourceSha256);
  assertExactKeys(milestone.evidenceSha256, ["handle-sections.png", "rear-sections.png", "section-checks.json"]);
  for (const [name, hash] of Object.entries(milestone.evidenceSha256)) {
    const evidencePath = path.join(modelRoot, "milestones/geometry-v1", name);
    assertRegularFile(evidencePath, 8 * 1024 * 1024);
    assert.equal(sha256(evidencePath), hash);
  }
  const measurements = JSON.parse(fs.readFileSync(path.join(modelRoot, "milestones/geometry-v1/section-checks.json"), "utf8"));
  assert.equal(measurements.sourceSha256, milestone.source.sha256);
  assert.equal(measurements.baselineSourceSha256, decision.refinementBaseline.sourceSha256);
  for (const [name, data] of Object.entries(measurements.handles)) {
    for (const sample of data.current.depths) {
      const [front, rear] = sectionAt(geometry.handleProfiles[name], sample.heightZ);
      assert.ok(Math.abs(sample.depthMillimeters - (rear - front) * contract.units.millimetersPerUnit) < 0.000001);
    }
  }
  assert.equal(decision.legacyArchive, "milestones/geometry-v1/legacy-archive.json");
  const archive = JSON.parse(fs.readFileSync(path.join(modelRoot, decision.legacyArchive), "utf8"));
  assert.equal(archive.requiredForRebuild, false);
  assert.match(archive.archiveSha256, /^[a-f0-9]{64}$/);
  assert.match(archive.manifestSha256, /^[a-f0-9]{64}$/);
  assert.ok(archive.verifiedFiles > 0);
  const ignored = fs.readFileSync(path.join(repositoryRoot, ".gitignore"), "utf8");
  assert.ok(ignored.includes("/models/switch-pro/work/"));
  assert.ok(ignored.includes("/models/switch-pro/references-local/"));
});
