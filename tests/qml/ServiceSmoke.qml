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
            if (!service.helper.running || service.health !== "ready")
                return;
            var oversized = [];
            for (var id = 1; id <= 33; id++)
                oversized.push(String(id));
            var bounded = service.setStreamingRequest("oversized", oversized) === false;
            for (var consumer = 0; consumer < 16; consumer++)
                bounded = service.setStreamingRequest("consumer-" + consumer, []) && bounded;
            bounded = service.setStreamingRequest("consumer-overflow", []) === false && bounded;
            var controller = service.selectedController;
            var valid = bounded && Object.keys(service.streamingRequests).length === 16 && service.backendWarning && service.lastErrorCode === "mapping_failed" && service.connectedCount === 1 && service.selectedId === "12" && controller && controller.buttons.south === true;
            console.log(valid ? "SERVICE_SMOKE_OK" : "SERVICE_SMOKE_FAILED");
            Qt.quit();
        }
    }

    Timer {
        interval: 5000
        running: true
        onTriggered: {
            console.log("SERVICE_SMOKE_TIMEOUT");
            Qt.quit();
        }
    }
}
