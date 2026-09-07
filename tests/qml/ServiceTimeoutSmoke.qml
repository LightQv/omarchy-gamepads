import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
    id: root

    readonly property string pluginRoot: Quickshell.env("PLUGIN_ROOT")

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
            if (service.health !== "restarting")
                return;
            var valid = service.restartAttempt === 1 && service.supervisorError === "Controller helper did not complete startup.";
            console.log(valid ? "SERVICE_TIMEOUT_SMOKE_OK" : "SERVICE_TIMEOUT_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: {
            console.log("SERVICE_TIMEOUT_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
