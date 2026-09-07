import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
    id: root

    property string hiddenId: ""
    property int phase: 0
    property bool firstOpenValid: false

    QtObject {
        id: fakeService

        property var controllers: [
            {
                id: "11",
                name: "First Controller",
                family: "switch-pro",
                connection: "wired",
                battery: {
                    available: true,
                    percent: 80,
                    state: "charging"
                }
            },
            {
                id: "12",
                name: "Second Controller",
                family: "switch-pro",
                connection: "wireless",
                battery: {
                    available: true,
                    percent: 60,
                    state: "on_battery"
                }
            }
        ]
        property string selectedId: "11"
        readonly property int connectedCount: controllers.length
        readonly property var selectedController: controllers[selectedId === "12" ? 1 : 0]
        property bool backendWarning: false
        property string health: "running"
        property string lastErrorMessage: ""

        function selectController(id) {
            if (id === "11" || id === "12")
                selectedId = id;
        }

        function cycleSelection(delta) {
            selectedId = selectedId === "11" ? "12" : "11";
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
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (!panel.opened)
                return;
            if (root.phase === 0) {
                root.firstOpenValid = fakeService.selectedId === "12";
                panel.requestClose();
                root.firstOpenValid = root.firstOpenValid && !panel.opened && root.hiddenId === "lightqv.gamepads";
                root.phase = 1;
                Qt.callLater(function () {
                    panel.open('{"view":"gamepads","controllerId":"11"}');
                });
                return;
            }
            var selectedAgain = fakeService.selectedId === "11";
            panel.requestClose();
            var valid = root.firstOpenValid && selectedAgain && !panel.opened && root.hiddenId === "lightqv.gamepads";
            console.log(valid ? "PANEL_LIFECYCLE_SMOKE_OK" : "PANEL_LIFECYCLE_SMOKE_FAILED");
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
