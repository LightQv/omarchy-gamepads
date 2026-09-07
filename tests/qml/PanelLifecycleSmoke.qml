import QtQuick
import Quickshell
import "Plugin" as Plugin

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
                buttons: ["south"],
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

        function updateSelectedInput() {
            var next = controllers.slice();
            for (var i = 0; i < next.length; i++) {
                if (next[i].id !== selectedId)
                    continue;
                var updated = Object.assign({}, next[i]);
                updated.axes = Object.assign({}, next[i].axes, {
                    leftx: 0.5
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
    }

    QtObject {
        id: fakeShell

        function hide(id) {
            root.hiddenId = id;
            panel.close();
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
                root.expect(panel.tabCount === 2, "initial tabs");
                root.expect(fakeService.selectedId === "12", "payload selection");
                root.expect(panel.selectedProfileId === "switch-pro", "profile selection");
                root.expect(panel.streamingControllerId === "12", "initial streaming");
                root.expect(panel.visualProfileActive, "persistent profile visual");
                root.expect(panel.informationFits, "default information fit");
                root.expect(panel.visualPaneWidth >= 360, "visual pane minimum");
                root.expect(panel.pressedButtonsLabel() === "None", "live button summary");
                panel.handleNavigation(-1, 0);
                root.expect(fakeService.selectedId === "11", "keyboard device navigation");
                root.phase = 1;
                return;
            }
            if (root.phase === 1) {
                root.expect(panel.streamingControllerId === "11", "selection streaming");
                fakeService.updateSelectedInput();
                root.phase = 11;
                return;
            }
            if (root.phase === 11) {
                root.expect(panel.axisValue("leftx") === "0.50", "unified live input");
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
            panel.handleCloseRequest();
            root.expect(!panel.opened && root.hiddenId === "lightqv.gamepads", "reopen host close");
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
