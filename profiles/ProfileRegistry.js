.import "switch-pro/Profile.js" as SwitchPro

"use strict";

var PROFILE_ID_PATTERN = /^[a-z0-9][a-z0-9-]{0,63}$/;
var TYPE_PATTERN = /^[a-z0-9][a-z0-9_-]{0,63}$/;
var CONTROL_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;
var PART_PATTERN = /^[a-z][a-z0-9_]{0,63}$/;
var VIEW_PATTERN = /^[A-Za-z0-9][A-Za-z0-9_\/-]{0,126}\.qml$/;
var UNSAFE_TEXT_PATTERN = /[\u0000-\u001f\u007f-\u009f\u202a-\u202e\u2066-\u2069]/;
var THRESHOLD_KEYS = [
  "baselineDurationMs", "digitalTriggerPress", "digitalTriggerRelease",
  "centerOffsetWarning", "neutralJitterWarning", "minimumPositiveRange",
  "minimumNegativeRange", "movementDetection"
];
var registeredProfiles = [SwitchPro.profile];

function validStringList(values, pattern) {
  if (!Array.isArray(values) || values.length === 0 || values.length > 64) return false;
  var seen = Object.create(null);
  for (var i = 0; i < values.length; i++) {
    if (typeof values[i] !== "string" || !pattern.test(values[i]) || seen[values[i]]) return false;
    seen[values[i]] = true;
  }
  return true;
}

function validateMatcher(matcher) {
  if (!matcher || typeof matcher !== "object" || Array.isArray(matcher)) return false;
  var familyConstrained = false;
  if (matcher.sdlTypes !== undefined) {
    if (!validStringList(matcher.sdlTypes, TYPE_PATTERN)) return false;
    familyConstrained = true;
  }
  if (matcher.families !== undefined) {
    if (!validStringList(matcher.families, TYPE_PATTERN)) return false;
    familyConstrained = true;
  }
  if (matcher.vendorId !== undefined) {
    if (typeof matcher.vendorId !== "string" || !/^[0-9a-f]{4}$/.test(matcher.vendorId)) return false;
  }
  if (matcher.productId !== undefined) {
    if (typeof matcher.productId !== "string" || !/^[0-9a-f]{4}$/.test(matcher.productId)) return false;
    if (matcher.vendorId === undefined) return false;
  }
  return familyConstrained;
}

function validateThresholds(thresholds) {
  if (!thresholds || typeof thresholds !== "object" || Array.isArray(thresholds)) return false;
  var keys = Object.keys(thresholds);
  if (keys.length !== THRESHOLD_KEYS.length) return false;
  for (var i = 0; i < THRESHOLD_KEYS.length; i++) {
    var key = THRESHOLD_KEYS[i];
    if (!Object.prototype.hasOwnProperty.call(thresholds, key)) return false;
    if (typeof thresholds[key] !== "number" || !isFinite(thresholds[key])) return false;
  }
  if (thresholds.baselineDurationMs < 1000 || thresholds.baselineDurationMs > 2000
      || Math.floor(thresholds.baselineDurationMs) !== thresholds.baselineDurationMs) return false;
  for (var normalizedIndex = 1; normalizedIndex < THRESHOLD_KEYS.length; normalizedIndex++) {
    var value = thresholds[THRESHOLD_KEYS[normalizedIndex]];
    if (value < 0 || value > 1) return false;
  }
  if (thresholds.digitalTriggerRelease >= thresholds.digitalTriggerPress) return false;
  if (thresholds.movementDetection >= thresholds.minimumPositiveRange
      || thresholds.movementDetection >= thresholds.minimumNegativeRange) return false;
  return true;
}

function validateProfile(profile) {
  if (!profile || typeof profile !== "object" || Array.isArray(profile)) return false;
  if (typeof profile.id !== "string" || !PROFILE_ID_PATTERN.test(profile.id)) return false;
  if (typeof profile.displayName !== "string" || profile.displayName.length === 0 || profile.displayName.length > 128) return false;
  if (!Array.isArray(profile.matchers) || profile.matchers.length === 0 || profile.matchers.length > 16) return false;
  for (var i = 0; i < profile.matchers.length; i++) {
    if (!validateMatcher(profile.matchers[i])) return false;
  }
  if (!validStringList(profile.expectedButtons, CONTROL_PATTERN)) return false;
  if (!validStringList(profile.expectedAxes, CONTROL_PATTERN)) return false;
  if (["digital", "analog"].indexOf(profile.triggerType) === -1) return false;
  if (typeof profile.viewComponent !== "string" || !VIEW_PATTERN.test(profile.viewComponent)
      || profile.viewComponent.indexOf("..") !== -1) return false;
  if (!profile.labels || typeof profile.labels !== "object" || Array.isArray(profile.labels)) return false;
  if (!profile.semanticParts || typeof profile.semanticParts !== "object" || Array.isArray(profile.semanticParts)) return false;
  if (!profile.animation || typeof profile.animation !== "object" || Array.isArray(profile.animation)) return false;
  if (!validateThresholds(profile.thresholds)) return false;
  var labelKeys = Object.keys(profile.labels);
  for (var labelIndex = 0; labelIndex < labelKeys.length; labelIndex++) {
    var label = profile.labels[labelKeys[labelIndex]];
    if (!CONTROL_PATTERN.test(labelKeys[labelIndex]) || typeof label !== "string" || label.length === 0
        || label.length > 64 || UNSAFE_TEXT_PATTERN.test(label)) return false;
  }
  var controls = profile.expectedButtons.concat(profile.expectedAxes);
  for (var controlIndex = 0; controlIndex < controls.length; controlIndex++) {
    var part = profile.semanticParts[controls[controlIndex]];
    if (typeof part !== "string" || !PART_PATTERN.test(part)) return false;
  }
  return true;
}

function matcherScore(controller, matcher) {
  var score = 0;
  if (matcher.sdlTypes !== undefined) {
    if (matcher.sdlTypes.indexOf(controller.sdlType) === -1) return -1;
    score += 4;
  }
  if (matcher.families !== undefined) {
    if (matcher.families.indexOf(controller.family) === -1) return -1;
    score += 2;
  }
  if (matcher.vendorId !== undefined) {
    if (matcher.vendorId !== controller.vendorId) return -1;
    score += 8;
  }
  if (matcher.productId !== undefined) {
    if (matcher.productId !== controller.productId) return -1;
    score += 8;
  }
  return score;
}

function resolveProfile(controller, profiles) {
  if (!controller || typeof controller !== "object") return null;
  var best = null;
  var bestScore = -1;
  var tied = false;
  for (var i = 0; i < profiles.length; i++) {
    var profile = profiles[i];
    if (!validateProfile(profile)) continue;
    for (var j = 0; j < profile.matchers.length; j++) {
      var score = matcherScore(controller, profile.matchers[j]);
      if (score > bestScore) {
        best = profile;
        bestScore = score;
        tied = false;
      } else if (score >= 0 && score === bestScore && best && best.id !== profile.id) {
        tied = true;
      }
    }
  }
  return bestScore < 0 || tied ? null : best;
}

function profileFor(controller) {
  return resolveProfile(controller, registeredProfiles);
}

function labelFor(profile, control) {
  if (profile && profile.labels && typeof profile.labels[control] === "string") return profile.labels[control];
  var words = String(control || "").replace(/_/g, " ");
  return words.length === 0 ? "Unknown control" : words.charAt(0).toUpperCase() + words.slice(1);
}

function allProfiles() {
  return registeredProfiles.slice();
}
