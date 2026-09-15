import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
    id: root

    property bool stopping: false
    Plugin.Service {
        id: service
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (!root.stopping && service.health === "ready") {
                root.stopping = true;
                service.restartAttempt = 6;
                service.helper.running = false;
                return;
            }
            if (!root.stopping || service.health !== "error")
                return;
            var valid = !service.restartTimer.running && service.supervisorError === "Controller helper stopped repeatedly. Retry from the panel.";
            console.log(valid ? "SERVICE_LIMIT_SMOKE_OK" : "SERVICE_LIMIT_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("SERVICE_LIMIT_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
