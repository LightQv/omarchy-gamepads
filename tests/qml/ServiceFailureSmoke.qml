import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
    id: root

    Plugin.Service {
        id: service
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (service.health !== "restarting")
                return;
            var valid = service.supervisorError.indexOf("oversized partial message") !== -1;
            console.log(valid ? "SERVICE_FAILURE_SMOKE_OK" : "SERVICE_FAILURE_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("SERVICE_FAILURE_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
