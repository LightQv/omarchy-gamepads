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
            var valid = service.acceptedMessages === 4 && service.protocolError === "";
            console.log(valid ? "SERVICE_EXIT_SMOKE_OK" : "SERVICE_EXIT_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("SERVICE_EXIT_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
