pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Plugin" as Plugin
import "Plugin/profiles/ProfileRegistry.js" as Profiles

// qmllint disable unqualified

ShellRoot {
    id: root

    readonly property string pluginRoot: Quickshell.env("PLUGIN_ROOT")
    property bool exercised: false

    function profileFor(controller) {
        return Profiles.profileFor(controller);
    }

    Plugin.Service {
        id: service
        manifest: ({ __sourceDir: root.pluginRoot })
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (root.exercised || service.health !== "ready" || service.modelState.lastSequence !== 3)
                return;
            root.exercised = true;
            var controller = service.selectedController;
            var profile = root.profileFor(controller);
            var valid = service.beginDiagnostics(controller, profile);
            valid = valid && !service.beginDiagnostics(controller, profile);
            service.beginDiagnosticBaseline();
            service.handleLine('{"type":"input","id":"12","sequence":4,"buttons":{"south":false},"axes":{}}');
            service.finishDiagnosticBaseline();
            service.handleLine('{"type":"input","id":"12","sequence":5,"buttons":{"south":true},"axes":{}}');
            service.handleLine('{"type":"input","id":"12","sequence":6,"buttons":{"south":false},"axes":{}}');
            valid = valid && service.diagnosticState.results.south.pressed && service.diagnosticState.results.south.released;
            service.interruptDiagnostics();
            valid = valid && service.diagnosticState.phase === "review"
                && service.diagnosticState.status === "incomplete"
                && service.diagnosticState.connected === false;
            valid = valid && service.beginDiagnostics(controller, profile);
            service.beginDiagnosticBaseline();
            service.finishDiagnosticBaseline();
            service.finalizeDiagnostics();
            var reviewStatus = service.diagnosticState.status;
            service.handleLine('{"type":"removed","id":"12","sequence":7}');
            valid = valid && service.diagnosticState.controllerId === "12"
                && service.diagnosticState.phase === "review"
                && service.diagnosticState.status === reviewStatus
                && service.diagnosticState.connected === true
                && service.diagnosticState.controllerPresent === false;
            console.log(valid ? "SERVICE_DIAGNOSTICS_SMOKE_OK" : "SERVICE_DIAGNOSTICS_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("SERVICE_DIAGNOSTICS_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
