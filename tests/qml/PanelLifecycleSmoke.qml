pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Plugin" as Plugin
import "Plugin/components" as Components
import "Plugin/Diagnostics.js" as Diagnostics

// qmllint disable unqualified

ShellRoot {
    id: root

    property string hiddenId: ""
    property int phase: 0
    property bool valid: true
    property string failures: ""

    function expect(condition, label) {
        if (condition)
            return;
        valid = false;
        failures += (failures === "" ? "" : ", ") + label;
    }

    function initialDiagnosticState() {
        return Diagnostics.initialState();
    }

    function startDiagnosticSession(controller, profile) {
        return Diagnostics.startSession(controller, profile);
    }

    function cancelDiagnosticSession(state) {
        return Diagnostics.cancelSession(state);
    }

    function controller(id, name, sdlType, family) {
        return {
            id: id,
            name: name,
            family: family,
            sdlType: sdlType,
            vendorId: sdlType === "switchpro" ? "057e" : "045e",
            productId: sdlType === "switchpro" ? "2009" : "02ea",
            connection: id === "12" ? "wireless" : "wired",
            battery: {
                available: true,
                percent: id === "12" ? 60 : 80,
                level: "normal",
                state: id === "12" ? "on_battery" : "charging"
            },
            capabilities: {
                buttons: ["south", "east", "west", "north", "back", "guide", "start", "left_stick", "right_stick", "left_shoulder", "right_shoulder", "dpad_up", "dpad_down", "dpad_left", "dpad_right", "misc1", "right_paddle1", "left_paddle1", "right_paddle2", "left_paddle2", "touchpad", "misc2", "misc3", "misc4", "misc5", "misc6"],
                axes: ["leftx", "lefty", "rightx", "righty", "left_trigger", "right_trigger"]
            },
            buttons: {
                south: false
            },
            axes: {
                leftx: 0,
                lefty: 0,
                rightx: 0,
                righty: 0,
                left_trigger: 0,
                right_trigger: 0
            }
        };
    }

    QtObject {
        id: fakeService

        property var controllers: [root.controller("11", "Nintendo Switch Pro Controller", "switchpro", "switch-pro"), root.controller("12", "Nintendo Switch Pro Controller", "switchpro", "switch-pro")]
        property var controllerTabs: tabProjection()
        property string selectedId: "11"
        property string streamingId: ""
        property int clearCount: 0
        readonly property int connectedCount: controllers.length
        readonly property var selectedController: selected()
        property bool backendWarning: false
        property string health: "ready"
        property string lastErrorMessage: ""
        property var diagnosticState: root.initialDiagnosticState()

        function tabProjection() {
            return controllers.map(function (controller) {
                return {
                    id: controller.id,
                    name: controller.name,
                    family: controller.family,
                    sdlType: controller.sdlType
                };
            });
        }

        function selected() {
            for (var i = 0; i < controllers.length; i++) {
                if (controllers[i].id === selectedId)
                    return controllers[i];
            }
            return null;
        }

        function selectController(id) {
            for (var i = 0; i < controllers.length; i++) {
                if (controllers[i].id === id) {
                    selectedId = id;
                    return;
                }
            }
        }

        function cycleSelection(delta) {
            if (controllers.length < 2)
                return;
            var index = 0;
            for (var i = 0; i < controllers.length; i++) {
                if (controllers[i].id === selectedId) {
                    index = i;
                    break;
                }
            }
            var step = delta < 0 ? -1 : 1;
            selectedId = controllers[(index + step + controllers.length) % controllers.length].id;
        }

        function addController(controller) {
            controllers = controllers.concat([controller]);
            controllerTabs = tabProjection();
        }

        function removeController(id) {
            var next = [];
            var removedIndex = -1;
            for (var i = 0; i < controllers.length; i++) {
                if (controllers[i].id === id)
                    removedIndex = i;
                else
                    next.push(controllers[i]);
            }
            controllers = next;
            controllerTabs = tabProjection();
            if (selectedId === id)
                selectedId = next.length === 0 ? "" : next[Math.min(Math.max(0, removedIndex), next.length - 1)].id;
        }

        function updateSelectedInput(leftX, leftTrigger) {
            var next = controllers.slice();
            for (var i = 0; i < next.length; i++) {
                if (next[i].id !== selectedId)
                    continue;
                var updated = Object.assign({}, next[i]);
                updated.buttons = Object.assign({}, next[i].buttons, {
                    south: true
                });
                updated.axes = Object.assign({}, next[i].axes, {
                    leftx: leftX === undefined ? 0.5 : leftX,
                    left_trigger: leftTrigger === undefined ? 1 : leftTrigger
                });
                next[i] = updated;
                break;
            }
            controllers = next;
        }

        function setStreamingRequest(consumer, ids) {
            if (consumer !== "floating-panel")
                return false;
            if (ids === null || ids === undefined) {
                streamingId = "";
                clearCount++;
            } else {
                streamingId = ids[0];
            }
            return true;
        }

        function beginDiagnostics(controller, profile) {
            diagnosticState = root.startDiagnosticSession(controller, profile);
            return diagnosticState.phase === "baseline_waiting";
        }

        function cancelDiagnostics() {
            diagnosticState = root.cancelDiagnosticSession(diagnosticState);
        }

        function resetDiagnostics() {
            diagnosticState = root.initialDiagnosticState();
        }
    }

    QtObject {
        id: fakeShell

        function hide(id) {
            root.hiddenId = id;
            panel.close();
        }
    }

    Item {
        visible: false
        width: 100
        height: 100

        Flickable {
            id: verticalFadeViewport
            anchors.fill: parent
            contentWidth: width
            contentHeight: 200
        }

        Components.ScrollEdgeFades {
            id: verticalFades
            anchors.fill: parent
            flickable: verticalFadeViewport
        }
    }

    Item {
        visible: false
        width: 100
        height: 100

        Flickable {
            id: horizontalFadeViewport
            anchors.fill: parent
            contentWidth: 200
            contentHeight: height
        }

        Components.ScrollEdgeFades {
            id: horizontalFades
            anchors.fill: parent
            flickable: horizontalFadeViewport
            orientation: Qt.Horizontal
        }
    }

    Plugin.Panel {
        id: panel
        shell: fakeShell
        service: fakeService
        manifest: {
            id: "lightqv.gamepads";
        }
    }

    Component.onCompleted: {
        panel.open('{"view":"gamepads","controllerId":"11"}');
        panel.open('{"view":"gamepads","controllerId":"12"}');
    }

    Timer {
        interval: 30
        repeat: true
        running: true
        onTriggered: {
            if (!panel.opened)
                return;
            if (root.phase === 0) {
                root.expect(verticalFades.startOpacity === 0 && verticalFades.endOpacity > 0, "vertical fade at start");
                verticalFadeViewport.contentY = 50;
                root.expect(verticalFades.startOpacity > 0 && verticalFades.endOpacity > 0, "vertical fades in middle");
                verticalFadeViewport.contentY = 100;
                root.expect(verticalFades.startOpacity > 0 && verticalFades.endOpacity === 0, "vertical fade at end");
                verticalFadeViewport.contentHeight = 100;
                root.expect(verticalFades.startOpacity === 0 && verticalFades.endOpacity === 0, "vertical fades hidden without overflow");
                root.expect(horizontalFades.startOpacity === 0 && horizontalFades.endOpacity > 0, "horizontal fade at start");
                horizontalFadeViewport.contentX = 50;
                root.expect(horizontalFades.startOpacity > 0 && horizontalFades.endOpacity > 0, "horizontal fades in middle");
                horizontalFadeViewport.contentX = 100;
                root.expect(horizontalFades.startOpacity > 0 && horizontalFades.endOpacity === 0, "horizontal fade at end");
                horizontalFadeViewport.contentWidth = 100;
                root.expect(horizontalFades.startOpacity === 0 && horizontalFades.endOpacity === 0, "horizontal fades hidden without overflow");
                root.expect(panel.tabCount === 2, "initial tabs");
                root.expect(fakeService.selectedId === "12", "payload selection");
                root.expect(panel.selectedProfileId === "switch-pro", "profile selection");
                root.expect(panel.streamingControllerId === "12", "initial streaming");
                root.expect(panel.visualProfileActive, "persistent profile visual");
                root.expect(panel.informationFits, "default information fit");
                root.expect(panel.visualPaneWidth >= 360, "visual pane minimum");
                root.expect(panel.defaultWindowWidth === 1120 && panel.defaultWindowHeight === 760, "expanded default size");
                root.expect(panel.selectedBottomView === "live", "live input opens selected");
                root.expect(panel.guidedDiagnosticTitle === "GUIDED DIAGNOSTIC", "guided diagnostic title");
                root.expect(panel.liveButtonCount === panel.controller.capabilities.buttons.length, "all live buttons represented");
                root.expect(panel.liveDigitalControlCount === panel.controller.capabilities.buttons.length + 2, "digital triggers join live buttons");
                root.expect(JSON.stringify(panel.liveDigitalControlNames.slice(0, 18)) === JSON.stringify([
                    "south", "east", "west", "north", "back", "start", "misc1", "guide",
                    "left_stick", "right_stick", "dpad_up", "dpad_down", "dpad_left", "dpad_right",
                    "left_shoulder", "right_shoulder", "left_trigger", "right_trigger"
                ]), "profile controls use requested order");
                root.expect(panel.liveDigitalControlNames[18] === "right_paddle1", "unprofiled controls follow profile controls");
                root.expect(panel.pressedButtonsLabel() === "None", "live button summary");
                var liveContentHeight = panel.inputContentHeight;
                panel.moveFocusRegion(1);
                root.expect(panel.liveButtonsScrollable, "maximum live buttons remain scrollable");
                panel.handleNavigation(0, 1);
                root.expect(panel.liveButtonScrollPosition > 0, "keyboard scrolls live buttons");
                panel.handleNavigation(1, 0);
                root.expect(panel.selectedBottomView === "guided", "keyboard guided view selection");
                root.expect(panel.inputContentHeight === liveContentHeight, "mode content height stable");
                panel.handleNavigation(-1, 0);
                root.expect(panel.selectedBottomView === "live", "keyboard live view selection");
                panel.moveFocusRegion(-1);
                root.expect(fakeService.beginDiagnostics(panel.controller, panel.controllerProfile), "diagnostic start");
                root.expect(panel.diagnosticPhase === "baseline_waiting", "diagnostic waiting phase");
                root.expect(panel.selectedBottomView === "guided", "diagnostic selects guided view");
                panel.selectController("11");
                root.expect(fakeService.selectedId === "12", "diagnostic selection lock");
                panel.open('{"view":"gamepads","controllerId":"11"}');
                root.expect(fakeService.selectedId === "12", "diagnostic payload selection lock");
                fakeService.selectController("11");
                root.expect(fakeService.streamingId === "12", "diagnostic streaming binding");
                fakeService.selectController("12");
                panel.handleCloseRequest();
                root.expect(panel.opened && panel.cancelConfirmationOpen, "diagnostic close confirmation");
                panel.confirmDiagnosticCancel();
                root.expect(panel.diagnosticPhase === "review" && fakeService.diagnosticState.status === "incomplete", "diagnostic cancel review");
                panel.selectController("11");
                root.expect(fakeService.selectedId === "11", "review selection unlocked");
                fakeService.selectController("12");
                fakeService.resetDiagnostics();
                root.expect(panel.selectedBottomView === "live", "reset selects live input");
                panel.moveFocusRegion(-1);
                panel.handleNavigation(-1, 0);
                root.expect(fakeService.selectedId === "11", "keyboard device navigation");
                root.phase = 1;
                return;
            }
            if (root.phase === 1) {
                root.expect(panel.streamingControllerId === "11", "selection streaming");
                fakeService.updateSelectedInput(0.19, 0.74);
                root.phase = 11;
                return;
            }
            if (root.phase === 11) {
                root.expect(panel.axisValue("leftx") === "0.19", "unified live input");
                root.expect(panel.liveButtonIsPressed("south"), "live button state");
                root.expect(!panel.liveButtonIsPressed("left_trigger"), "digital trigger below threshold");
                root.expect(panel.liveControlIndicator("left_trigger") === "0.74", "digital trigger shows numeric value below threshold");
                root.expect(!panel.liveLeftStickActive && !panel.liveRightStickActive, "sticks below movement threshold");
                fakeService.updateSelectedInput(0.2, 0.75);
                root.phase = 12;
                return;
            }
            if (root.phase === 12) {
                root.expect(panel.liveButtonIsPressed("left_trigger"), "digital trigger at threshold");
                root.expect(panel.liveControlIndicator("left_trigger") === "0.75", "digital trigger shows numeric value at threshold");
                root.expect(panel.liveLeftStickActive && !panel.liveRightStickActive, "stick at movement threshold");
                root.expect(panel.streamingControllerId === "11", "input preserves streaming");
                fakeService.addController(root.controller("13", "Xbox Wireless Controller", "xboxone", "xbox"));
                root.expect(fakeService.selectedId === "11", "hotplug selection stability");
                fakeService.selectController("13");
                root.phase = 2;
                return;
            }
            if (root.phase === 2) {
                root.expect(panel.tabCount === 3, "hotplug tabs");
                root.expect(panel.selectedProfileId === "", "unsupported profile");
                root.expect(!panel.visualProfileActive, "unsupported visual fallback");
                root.expect(panel.streamingControllerId === "13", "unsupported streaming");
                fakeService.removeController("13");
                root.phase = 3;
                return;
            }
            if (root.phase === 3) {
                root.expect(fakeService.selectedId === "12", "neighbor selection");
                root.expect(panel.streamingControllerId === "12", "neighbor streaming");
                fakeService.removeController("11");
                fakeService.removeController("12");
                root.phase = 4;
                return;
            }
            if (root.phase === 4) {
                root.expect(panel.tabCount === 0, "empty tabs");
                root.expect(!panel.controller, "empty controller");
                root.expect(panel.streamingControllerId === "", "empty streaming");
                root.expect(fakeService.clearCount > 0, "stream cleanup");
                fakeService.addController(root.controller("21", "Nintendo Switch Pro Controller", "switchpro", "switch-pro"));
                fakeService.selectedId = "21";
                panel.handleCloseRequest();
                root.expect(!panel.opened && root.hiddenId === "lightqv.gamepads", "host close");
                root.expect(fakeService.streamingId === "", "close streaming");
                root.phase = 5;
                Qt.callLater(function () {
                    panel.open('{"view":"gamepads","controllerId":"21"}');
                });
                return;
            }
            root.expect(fakeService.selectedId === "21", "reopen selection");
            root.expect(panel.streamingControllerId === "21", "reopen streaming");
            root.expect(fakeService.beginDiagnostics(panel.controller, panel.controllerProfile), "reopen diagnostic start");
            panel.close();
            root.expect(!panel.opened && fakeService.diagnosticState.phase === "review", "host close ends diagnostic");
            root.expect(fakeService.streamingId === "", "reopen cleanup");
            console.log(root.valid ? "PANEL_LIFECYCLE_SMOKE_OK" : "PANEL_LIFECYCLE_SMOKE_FAILED: " + root.failures);
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("PANEL_LIFECYCLE_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
