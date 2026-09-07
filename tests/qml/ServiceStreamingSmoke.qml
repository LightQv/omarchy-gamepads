import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
    id: root

    readonly property string pluginRoot: Quickshell.env("PLUGIN_ROOT")
    property int phase: 0

    Plugin.Service {
        id: service
        manifest: ({
                __sourceDir: root.pluginRoot
            })
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (root.phase === 4 && service.health === "stopped") {
                console.log(service.controllerTabs.length === 0 ? "SERVICE_STREAMING_SMOKE_OK" : "SERVICE_STREAMING_SMOKE_FAILED");
                Qt.quit();
                return;
            }
            if (service.health !== "ready")
                return;
            if (root.phase === 0) {
                if (service.connectedCount !== 2 || service.controllerTabs.length !== 2)
                    return;
                if (service.setStreamingRequest("invalid-panel", ["99"]) !== false) {
                    console.log("SERVICE_STREAMING_SMOKE_FAILED");
                    Qt.quit();
                    return;
                }
                service.setStreamingRequest("floating-panel", ["11"]);
                root.phase = 1;
                return;
            }
            if (root.phase === 1 && service.lastErrorCode === "stream_11_ready") {
                service.setStreamingRequest("floating-panel", ["12"]);
                root.phase = 2;
                return;
            }
            if (root.phase === 2 && service.lastErrorCode === "stream_12_ready") {
                service.setStreamingRequest("floating-panel", null);
                root.phase = 3;
                return;
            }
            if (root.phase === 3 && service.lastErrorCode === "stream_cleared") {
                service.stop();
                root.phase = 4;
                return;
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("SERVICE_STREAMING_SMOKE_TIMEOUT phase=" + root.phase + " health=" + service.health + " error=" + service.lastErrorCode + " tabs=" + service.controllerTabs.length);
            Qt.quit();
        }
    }
}
