pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui as Ui
import "../profiles/ProfileRegistry.js" as Profiles

Ui.CursorSurface {
    id: root

    property var service: null
    property var controller: null
    property var profile: null
    property string exportMessage: ""
    property color background: Color.background
    property string fontFamily: Style.font.family
    property int actionIndex: 0
    property int retryIndex: 0

    signal cancelRequested()
    signal exportRequested()

    readonly property var diagnostic: service && service.diagnosticState ? service.diagnosticState : ({ phase: "idle", results: {} })
    readonly property string phase: diagnostic.phase || "idle"
    readonly property bool supported: !!controller && !!profile
    readonly property bool active: ["baseline_waiting", "baseline_capturing", "digital", "analog_left", "analog_right"].indexOf(phase) !== -1
    readonly property var retryControls: buildRetryControls()
    readonly property var actionLabels: buildActionLabels()
    readonly property int completedDigital: countCompletedDigital()

    implicitHeight: phase === "idle" ? Style.space(64) : (phase === "digital" ? Style.space(190) : Style.space(154))
    bordered: true

    onPhaseChanged: {
        actionIndex = 0;
        retryIndex = 0;
        if (phase === "baseline_capturing")
            baselineTimer.restart();
        else
            baselineTimer.stop();
        Qt.callLater(focusCurrentAction);
    }

    function result(control) {
        return diagnostic.results && diagnostic.results[control] ? diagnostic.results[control] : null;
    }

    function buildRetryControls() {
        if (phase !== "review" || diagnostic.connected === false)
            return [];
        var controls = (diagnostic.digitalControls || []).concat(diagnostic.analogControls || []);
        return controls.filter(function (control) {
            var item = root.result(control);
            return item && item.available && item.status !== "passed";
        });
    }

    function countCompletedDigital() {
        var controls = diagnostic.digitalControls || [];
        var completed = 0;
        for (var i = 0; i < controls.length; i++) {
            var item = result(controls[i]);
            if (item && (!item.available || item.pressed && item.released))
                completed++;
        }
        return completed;
    }

    function nextDigitalLabel() {
        var controls = diagnostic.digitalControls || [];
        for (var i = 0; i < controls.length; i++) {
            var item = result(controls[i]);
            if (item && item.available && !(item.pressed && item.released))
                return controlLabel(controls[i]);
        }
        return "None";
    }

    function statusCount(status) {
        var controls = (diagnostic.digitalControls || []).concat(diagnostic.analogControls || []);
        var count = 0;
        for (var i = 0; i < controls.length; i++) {
            var item = result(controls[i]);
            if (item && item.status === status)
                count++;
        }
        return count;
    }

    function selectedRetryControl() {
        return retryControls.length > 0 ? retryControls[Math.min(retryIndex, retryControls.length - 1)] : "";
    }

    function controlLabel(control) {
        if (phase !== "idle" && diagnostic.labels && typeof diagnostic.labels[control] === "string")
            return diagnostic.labels[control];
        return Profiles.labelFor(profile, control);
    }

    function buildActionLabels() {
        if (!supported && phase === "idle")
            return [];
        if (phase === "idle")
            return ["Start guided test"];
        if (phase === "baseline_waiting")
            return ["Begin baseline", "Cancel"];
        if (phase === "baseline_capturing")
            return ["Cancel"];
        if (phase === "digital")
            return diagnostic.retryTarget ? ["Review retry", "Review now"] : ["Continue to left stick", "Review now"];
        if (phase === "analog_left")
            return diagnostic.retryTarget ? ["Review retry", "Review now"] : ["Continue to right stick", "Review now"];
        if (phase === "analog_right")
            return [diagnostic.retryTarget ? "Review retry" : "Review results", "Review now"];
        if (phase === "review") {
            var labels = [];
            if (retryControls.length > 0)
                labels.push("Retry " + controlLabel(selectedRetryControl()));
            labels.push("Export report");
            labels.push(supported ? "New test" : "Dismiss results");
            return labels;
        }
        return [];
    }

    function titleText() {
        if (phase === "idle")
            return supported ? "GUIDED INPUT TEST" : "GUIDED TEST UNAVAILABLE";
        if (phase === "baseline_waiting")
            return "NEUTRAL BASELINE";
        if (phase === "baseline_capturing")
            return "CAPTURING NEUTRAL INPUT";
        if (phase === "digital")
            return "DIGITAL CONTROLS  " + completedDigital + "/" + (diagnostic.digitalControls || []).length;
        if (phase === "analog_left")
            return "LEFT STICK RANGE";
        if (phase === "analog_right")
            return "RIGHT STICK RANGE";
        return "REVIEW  " + String(diagnostic.status || "incomplete").replace(/_/g, " ").toUpperCase();
    }

    function instructionText() {
        if (phase === "idle")
            return supported ? "Check every mapped control without changing system calibration." : "This controller has no guided diagnostic profile.";
        if (phase === "baseline_waiting")
            return "Release every button and let both sticks rest, then begin the baseline.";
        if (phase === "baseline_capturing")
            return "Keep all controls released while neutral center and input noise are observed.";
        if (phase === "digital")
            return diagnostic.retryTarget
                ? "Press and release " + controlLabel(diagnostic.retryTarget) + ". Both edges are required."
                : "Press and release each control in any order. Both edges are required. Next: " + nextDigitalLabel() + ".";
        if (phase === "analog_left")
            return diagnostic.retryTarget
                ? "Move " + controlLabel(diagnostic.retryTarget) + " through both directions."
                : "Rotate the left stick around its full edge, reaching every direction.";
        if (phase === "analog_right")
            return diagnostic.retryTarget
                ? "Move " + controlLabel(diagnostic.retryTarget) + " through both directions."
                : "Rotate the right stick around its full edge, reaching every direction.";
        var summary = statusCount("passed") + " passed, " + statusCount("warning") + " warning, "
            + statusCount("not_detected") + " not detected, " + statusCount("incomplete") + " incomplete, "
            + statusCount("unavailable") + " unavailable.";
        if (diagnostic.connected === false)
            summary += " The tested controller disconnected, so the session is incomplete.";
        return summary;
    }

    function moveAction(delta) {
        if (actionLabels.length === 0)
            return;
        var step = delta < 0 ? -1 : 1;
        actionIndex = (actionIndex + step + actionLabels.length) % actionLabels.length;
        focusCurrentAction();
    }

    function moveRetry(delta) {
        if (phase !== "review" || retryControls.length < 2)
            return false;
        var step = delta < 0 ? -1 : 1;
        retryIndex = (retryIndex + step + retryControls.length) % retryControls.length;
        actionIndex = 0;
        return true;
    }

    function activateCurrentAction() {
        activateAction(actionIndex);
    }

    function focusCurrentAction() {
        if (!visible || actionLabels.length === 0)
            return;
        if (phase === "idle") {
            startButton.forceActiveFocus();
            return;
        }
        var item = actionRepeater.itemAt(Math.min(actionIndex, actionLabels.length - 1));
        if (item)
            item.forceActiveFocus();
    }

    function activateAction(index) {
        if (!service || index < 0 || index >= actionLabels.length)
            return;
        if (phase === "idle") {
            service.beginDiagnostics(controller, profile);
        } else if (phase === "baseline_waiting") {
            if (index === 0)
                service.beginDiagnosticBaseline();
            else
                cancelRequested();
        } else if (phase === "baseline_capturing") {
            cancelRequested();
        } else if (phase === "digital" || phase === "analog_left") {
            if (index === 0)
                service.advanceDiagnostics();
            else
                service.finalizeDiagnostics();
        } else if (phase === "analog_right") {
            service.finalizeDiagnostics();
        } else if (phase === "review") {
            var offset = retryControls.length > 0 ? 1 : 0;
            if (offset === 1 && index === 0)
                service.retryDiagnostic(selectedRetryControl());
            else if (index === offset)
                exportRequested();
            else if (supported)
                service.beginDiagnostics(controller, profile);
            else
                service.resetDiagnostics();
        }
    }

    Timer {
        id: baselineTimer
        interval: root.diagnostic.thresholds && root.diagnostic.thresholds.baselineDurationMs
            ? root.diagnostic.thresholds.baselineDurationMs : 1500
        onTriggered: if (root.service)
            root.service.finishDiagnosticBaseline()
    }

    Column {
        visible: root.phase !== "idle"
        anchors.fill: parent
        anchors.margins: Style.space(14)
        spacing: Style.space(8)

        Ui.PanelSectionHeader {
            text: root.titleText()
            foreground: root.foreground
            fontFamily: root.fontFamily
        }

        Text {
            width: parent.width
            textFormat: Text.PlainText
            text: root.instructionText()
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
        }

        Flickable {
            id: digitalChecklist
            visible: root.phase === "digital"
            width: parent.width
            height: Style.space(24)
            contentWidth: digitalChipRow.implicitWidth
            contentHeight: height
            flickableDirection: Flickable.HorizontalFlick
            boundsBehavior: Flickable.StopAtBounds
            clip: true

            Row {
                id: digitalChipRow
                spacing: Style.space(5)

                Repeater {
                    model: root.diagnostic.digitalControls || []

                    delegate: Rectangle {
                        required property string modelData
                        readonly property var diagnosticResult: root.result(modelData)
                        readonly property bool complete: diagnosticResult && (!diagnosticResult.available || diagnosticResult.pressed && diagnosticResult.released)
                        width: chipLabel.implicitWidth + Style.space(14)
                        height: Style.space(24)
                        color: complete ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
                        border.color: complete ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                        border.width: 1
                        radius: Style.cornerRadius

                        Text {
                            id: chipLabel
                            anchors.centerIn: parent
                            text: (parent.complete ? "[x] " : "[ ] ") + root.controlLabel(parent.modelData)
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                        }
                    }
                }
            }
        }

        Item {
            width: parent.width
            height: actions.implicitHeight

            Text {
                visible: root.phase === "review" && root.exportMessage !== ""
                anchors.left: parent.left
                anchors.right: actions.left
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: root.exportMessage
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }

            Row {
                id: actions
                anchors.right: parent.right
                spacing: Style.space(8)

                Repeater {
                    id: actionRepeater
                    model: root.actionLabels

                    delegate: Ui.Button {
                        required property int index
                        required property string modelData
                        text: modelData
                        bordered: true
                        focusable: true
                        hasCursor: root.actionIndex === index
                        foreground: root.foreground
                        background: root.background
                        fontFamily: root.fontFamily
                        onClicked: root.activateAction(index)
                    }
                }
            }
        }
    }

    Row {
        visible: root.phase === "idle"
        anchors.fill: parent
        anchors.margins: Style.space(12)
        spacing: Style.space(12)

        Column {
            width: Math.max(0, parent.width - startButton.width - parent.spacing)
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
                width: parent.width
                text: root.titleText()
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: root.instructionText()
                color: Qt.darker(root.foreground, 1.3)
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
            }
        }

        Ui.Button {
            id: startButton
            visible: root.actionLabels.length > 0
            anchors.verticalCenter: parent.verticalCenter
            text: visible ? root.actionLabels[0] : ""
            bordered: true
            focusable: true
            hasCursor: true
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
            onClicked: root.activateAction(0)
        }
    }
}
