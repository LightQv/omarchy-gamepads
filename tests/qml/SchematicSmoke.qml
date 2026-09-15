pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Window
import Quickshell
import "Plugin/profiles/switch-pro" as SwitchPro
import "Plugin/profiles/switch-pro/Profile.js" as Profile
import "Plugin/profiles/switch-pro/Schematic.js" as Drawing

ShellRoot {
    id: root

    property int step: 0
    property int inputIndex: 0
    property bool waiting: false
    property bool valid: true
    property color foreground: "#cdd6f4"
    property color background: "#1e1e2e"
    property color accent: "#89b4fa"
    property color urgent: "#f38ba8"
    property color muted: "#6c7086"
    property bool lowContrastPress: false
    readonly property var digitalNames: Drawing.buttons.map(function (spec) { return spec.control; })
        .concat(Drawing.sticks.map(function (spec) { return spec.control; }))
    readonly property string outputDir: Quickshell.env("SCHEMATIC_TEST_OUTPUT")

    function expect(condition, label) {
        if (!condition) {
            valid = false;
            console.error("Schematic check failed: " + label);
        }
    }

    function input(held, axes) {
        var buttons = {};
        var values = {};
        Profile.profile.expectedButtons.forEach(function (name) { buttons[name] = held.indexOf(name) !== -1; });
        Profile.profile.expectedAxes.forEach(function (name) { values[name] = held.indexOf(name) !== -1 ? 1 : 0; });
        Object.keys(axes || {}).forEach(function (name) { values[name] = axes[name]; });
        return { id: "11", capabilities: { buttons: Profile.profile.expectedButtons, axes: Profile.profile.expectedAxes },
            buttons: buttons, axes: values };
    }

    function findItem(item, name) {
        if (item.objectName === name) return item;
        var children = item.children || [];
        for (var i = 0; i < children.length; i++) {
            var found = findItem(children[i], name);
            if (found) return found;
        }
        return null;
    }

    function capture(name) {
        waiting = true;
        if (!surface.grabToImage(function (result) {
            root.expect(result.saveToFile(root.outputDir + "/" + name + ".png"), "save " + name);
            root.waiting = false;
            root.step++;
        })) {
            expect(false, "grab " + name);
            waiting = false;
            step++;
        }
    }

    Window {
        id: window
        visible: true
        width: 640
        height: 360
        flags: Qt.Tool | Qt.FramelessWindowHint | Qt.WindowDoesNotAcceptFocus
        color: root.background
        title: "Gamepads schematic check"

        Rectangle {
            id: surface
            width: view.width
            height: view.height
            color: root.background

            SwitchPro.Schematic {
                id: view
                width: 630
                height: 350
                controller: root.input([], {})
                profile: Profile.profile
                active: window.visible
                foreground: root.foreground
                background: root.background
                accent: root.accent
                urgent: root.urgent
                muted: root.muted
                pressedColor: root.lowContrastPress ? background : foreground
            }
        }
    }

    Timer {
        interval: 80
        running: true
        repeat: true
        onTriggered: {
            if (root.waiting) return;
            if (root.step === 0) {
                root.expect(view.drawingScale > 0 && view.contrast(view.signalColor, view.signalText) >= 4.5, "dark contrast and layout");
                root.capture("neutral");
            } else if (root.step === 1) {
                view.controller = root.input([root.digitalNames[root.inputIndex]], {});
                root.step++;
            } else if (root.step === 2) {
                root.digitalNames.forEach(function (name) {
                    var item = root.findItem(view, name);
                    root.expect(!!item, "rendered input " + name);
                    if (!item) return;
                    var state = "inputState" in item ? item.inputState : item.click;
                    root.expect(state.active === (name === root.digitalNames[root.inputIndex]), "independent rendered input " + name);
                    if ("fill" in item && state.active)
                        root.expect(item.fill === view.signalColor, "filled press " + name);
                });
                root.inputIndex++;
                root.step = root.inputIndex < root.digitalNames.length ? 1 : 3;
            } else if (root.step === 3) {
                view.controller = root.input(["east", "left_trigger", "right_shoulder", "left_stick"],
                    { leftx: 0.6, lefty: -0.4, rightx: -0.5, righty: 0.7 });
                root.step++;
            } else if (root.step === 4) {
                root.expect(view.projection.sticks.left_stick.y === -0.4 && view.projection.sticks.right_stick.x === -0.5, "independent stick travel");
                root.capture("pressed");
            } else if (root.step === 5) {
                view.controller = root.input([], {});
                root.step++;
            } else if (root.step === 6) {
                root.expect(root.digitalNames.every(function (name) { return !view.controlState(name).active; }), "complete release");
                root.expect(Drawing.sticks.every(function (spec) {
                    var state = view.projection.sticks[spec.control];
                    return state.x === 0 && state.y === 0 && !state.active;
                }), "both sticks return exactly to center");
                root.capture("released");
            } else if (root.step === 7) {
                view.diagnosticState = { phase: "review", controllerId: "11", profileId: "switch-pro", results: {
                    east: { status: "passed" }, left_trigger: { status: "warning" },
                    leftx: { status: "passed" }, lefty: { status: "passed" }, righty: { status: "not_detected" }
                } };
                root.step++;
            } else if (root.step === 8) {
                root.capture("diagnostic");
            } else if (root.step === 9) {
                root.foreground = "#4c4f69";
                root.background = "#eff1f5";
                root.accent = "#1e66f5";
                root.urgent = "#d20f39";
                root.muted = "#9ca0b0";
                view.controller = root.input(["west", "right_trigger"], {});
                root.step++;
            } else if (root.step === 10) {
                root.expect(view.contrast(view.signalColor, view.signalText) >= 4.5, "light contrast");
                root.capture("light");
            } else if (root.step === 11) {
                root.foreground = "#cacccc";
                root.background = "#101315";
                root.accent = root.foreground;
                root.muted = "#707880";
                root.lowContrastPress = true;
                view.diagnosticState = { phase: "idle" };
                root.step++;
            } else if (root.step === 12) {
                root.expect(view.signalColor === view.foreground && view.contrast(view.signalColor, view.signalText) >= 4.5, "monochrome low-contrast press fallback");
                root.capture("monochrome");
            } else if (root.step === 13) {
                view.width = 360;
                view.height = 140;
                root.step++;
            } else if (root.step === 14) {
                root.expect(view.drawingScale > 0 && view.drawingScale * 900 <= view.width, "compact framing");
                root.capture("compact");
            } else if (root.step === 15) {
                window.visible = false;
                root.step++;
            } else {
                root.expect(!view.active && root.digitalNames.every(function (name) { return !view.controlState(name).active; }), "hidden input work is disabled");
                view.pressedColor = Qt.rgba(1, 1, 1, 0);
                root.expect(view.signalColor === view.foreground, "transparent pressed theme role retains a visible signal");
                console.log(root.valid ? "SCHEMATIC_SMOKE_OK" : "SCHEMATIC_SMOKE_FAILED");
                Qt.quit();
            }
        }
    }
}
