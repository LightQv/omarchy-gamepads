import QtQuick
import Quickshell
import "Plugin" as Plugin

ShellRoot {
    id: root

    property bool retried: false
    Plugin.Service {
        id: service
    }

    Timer {
        interval: 25
        repeat: true
        running: true
        onTriggered: {
            if (!root.retried && service.dependencyMissing) {
                if (service.restartAttempt !== 0 || service.restartTimer.running) {
                    console.log("SERVICE_DEPENDENCY_SMOKE_FAILED");
                    Qt.quit();
                    return;
                }
                root.retried = true;
                service.retry();
                return;
            }
            if (!root.retried || service.health !== "ready")
                return;
            var valid = service.connectedCount === 1 && service.selectedId === "12";
            console.log(valid ? "SERVICE_DEPENDENCY_SMOKE_OK" : "SERVICE_DEPENDENCY_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 8000
        running: true
        onTriggered: {
            console.log("SERVICE_DEPENDENCY_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
