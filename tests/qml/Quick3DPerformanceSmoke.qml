pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "Plugin/profiles/switch-pro" as SwitchPro
import "Plugin/profiles/switch-pro/Profile.js" as SwitchProfile

ShellRoot {
    id: root

    property var controllerState: makeController(0)
    property int updates: 0
    property var frameTimes: []
    property bool finished: false

    function makeController(step) {
        var phase = step / 12;
        return {
            id: "12",
            buttons: {
                south: step % 20 < 10,
                east: step % 34 < 17,
                left_stick: step % 48 < 8,
                right_stick: step % 64 < 8
            },
            axes: {
                leftx: Math.sin(phase),
                lefty: Math.cos(phase),
                rightx: Math.sin(phase * 0.73),
                righty: Math.cos(phase * 0.61),
                left_trigger: (Math.sin(phase * 0.37) + 1) / 2,
                right_trigger: (Math.cos(phase * 0.41) + 1) / 2
            }
        };
    }

    function percentile(sorted, ratio) {
        return sorted[Math.min(sorted.length - 1, Math.floor(sorted.length * ratio))];
    }

    function finish() {
        if (finished)
            return;
        finished = true;
        performanceWindow.visible = false;
        var samples = frameTimes.slice(30).sort(function (a, b) { return a - b; });
        var median = percentile(samples, 0.5) * 1000;
        var p95 = percentile(samples, 0.95) * 1000;
        var valid = samples.length > 300 && updates > 3000 && p95 <= 33;
        console.log("QUICK3D_PERFORMANCE", "frames=" + samples.length,
            "updates=" + updates, "median_ms=" + median.toFixed(2), "p95_ms=" + p95.toFixed(2));
        console.log(valid && !scene.renderActive
            ? "QUICK3D_PERFORMANCE_OK" : "QUICK3D_PERFORMANCE_FAILED");
        Qt.quit();
    }

    FloatingWindow {
        id: performanceWindow
        visible: true
        width: 640
        height: 480
        title: "Gamepad Quick 3D performance smoke"

        SwitchPro.SwitchProScene {
            id: scene
            anchors.fill: parent
            controller: root.controllerState
            profile: SwitchProfile.profile
            diagnosticState: ({
                phase: frameDriver.elapsedTime < 30 ? "idle" : "digital",
                controllerId: "12",
                profileId: "switch-pro",
                results: ({})
            })
            interactionMode: frameDriver.elapsedTime < 30 ? "overview" : "diagnostic"
            renderActive: performanceWindow.visible
            foreground: "#e8e8e8"
            background: "#202124"
            accent: "#8aadf4"
            urgent: "#ed8796"
        }
    }

    Timer {
        interval: 16
        repeat: true
        running: performanceWindow.visible
        onTriggered: {
            root.updates++;
            root.controllerState = root.makeController(root.updates);
        }
    }

    FrameAnimation {
        id: frameDriver
        running: performanceWindow.visible
        onTriggered: {
            root.frameTimes.push(frameTime);
            if (elapsedTime >= 60)
                root.finish();
        }
    }

    Timer {
        interval: 70000
        running: true
        onTriggered: {
            console.log("QUICK3D_PERFORMANCE_TIMEOUT");
            Qt.quit();
        }
    }
}
