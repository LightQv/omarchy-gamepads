pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui as Ui
import "../profiles/ProfileRegistry.js" as Profiles

Item {
    id: root

    property var service: null
    property var controller: null
    property var profile: null
    property string exportMessage: ""
    property color foreground: Color.foreground
    property color background: Color.background
    property string fontFamily: Style.font.family
    property int actionIndex: 0
    property int retryIndex: 0
    property string selectedView: "live"
    property bool testedControllerPresent: false
    property string observedPhase: "idle"
    property bool compactLayout: false
    property bool modeHasCursor: false
    property bool actionsHaveCursor: false
    property var projectedCapabilities: null
    property var projectedProfile: null
    property var liveDigitalControlNames: []
    property var liveOtherAxisNames: []

    signal cancelRequested()
    signal exportRequested()
    signal modeFocusRequested()
    signal actionFocusRequested()

    readonly property var diagnostic: service && service.diagnosticState ? service.diagnosticState : ({ phase: "idle", results: {} })
    readonly property string phase: diagnostic.phase || "idle"
    readonly property bool supported: !!controller && !!profile
    readonly property bool active: ["baseline_waiting", "baseline_capturing", "digital", "analog_left", "analog_right"].indexOf(phase) !== -1
    readonly property var retryControls: buildRetryControls()
    readonly property var actionLabels: buildActionLabels()
    readonly property int completedDigital: countCompletedDigital()
    readonly property int availableDigital: countAvailableDigital()
    readonly property var liveButtonNames: controller && controller.capabilities && controller.capabilities.buttons ? controller.capabilities.buttons : []
    readonly property var liveAxisNames: controller && controller.capabilities && controller.capabilities.axes ? controller.capabilities.axes : []
    readonly property int liveButtonCount: liveButtonNames.length
    readonly property int liveDigitalControlCount: liveDigitalControlNames.length
    readonly property bool liveLeftStickActive: stickActive(liveAxisValue("leftx"), liveAxisValue("lefty"))
    readonly property bool liveRightStickActive: stickActive(liveAxisValue("rightx"), liveAxisValue("righty"))
    readonly property bool liveButtonsScrollable: liveButtonViewport.contentHeight > liveButtonViewport.height
    readonly property real liveButtonScrollPosition: liveButtonViewport.contentY
    readonly property bool guidedContentScrollable: digitalChecklist.visible && digitalChecklist.contentHeight > digitalChecklist.height
    readonly property real guidedContentScrollPosition: digitalChecklist.contentY
    readonly property bool guidedVisible: selectedView === "guided"
    readonly property bool hasVisibleActions: guidedVisible && actionLabels.length > 0
    readonly property int contentHeight: Style.space(compactLayout ? 196 : 238)
    readonly property real modeContentHeight: contentSurface.height

    implicitHeight: contentHeight

    Component.onCompleted: refreshLiveProjections()
    onControllerChanged: refreshLiveProjections()
    onProfileChanged: refreshLiveProjections()

    onPhaseChanged: {
        var previous = observedPhase;
        observedPhase = phase;
        actionIndex = 0;
        retryIndex = 0;
        digitalChecklist.contentY = 0;
        if (phase === "idle")
            selectedView = "live";
        else if (previous === "idle" || previous === "review")
            selectedView = "guided";
        if (phase === "baseline_capturing")
            baselineTimer.restart();
        else
            baselineTimer.stop();
    }

    function result(control) {
        return diagnostic.results && diagnostic.results[control] ? diagnostic.results[control] : null;
    }

    function buildRetryControls() {
        if (phase !== "review" || diagnostic.connected === false || !testedControllerPresent)
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
            if (item && item.available && item.pressed && item.released)
                completed++;
        }
        return completed;
    }

    function countAvailableDigital() {
        var controls = diagnostic.digitalControls || [];
        var available = 0;
        for (var i = 0; i < controls.length; i++) {
            var item = result(controls[i]);
            if (item && item.available)
                available++;
        }
        return available;
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

    function liveAxisValue(name) {
        return controller && controller.axes ? Number(controller.axes[name] || 0) : 0;
    }

    function liveButtonPressed(name) {
        return !!(controller && controller.buttons && controller.buttons[name]);
    }

    function isProfileDigitalTrigger(name) {
        return !!profile && profile.triggerType === "digital" && /_trigger$/.test(name)
            && Array.isArray(profile.expectedAxes) && profile.expectedAxes.indexOf(name) !== -1;
    }

    function refreshLiveProjections() {
        var capabilities = controller && controller.capabilities ? controller.capabilities : null;
        if (capabilities === projectedCapabilities && profile === projectedProfile)
            return;
        projectedCapabilities = capabilities;
        projectedProfile = profile;

        var buttons = capabilities && Array.isArray(capabilities.buttons) ? capabilities.buttons : [];
        var axes = capabilities && Array.isArray(capabilities.axes) ? capabilities.axes : [];
        var controls = [];
        var seen = Object.create(null);
        var expectedButtons = profile && Array.isArray(profile.expectedButtons) ? profile.expectedButtons : [];
        for (var i = 0; i < expectedButtons.length; i++) {
            if (buttons.indexOf(expectedButtons[i]) !== -1 && !seen[expectedButtons[i]]) {
                seen[expectedButtons[i]] = true;
                controls.push(expectedButtons[i]);
            }
        }
        for (var j = 0; j < axes.length; j++) {
            if (isProfileDigitalTrigger(axes[j]) && !seen[axes[j]]) {
                seen[axes[j]] = true;
                controls.push(axes[j]);
            }
        }
        for (var buttonIndex = 0; buttonIndex < buttons.length; buttonIndex++) {
            if (!seen[buttons[buttonIndex]]) {
                seen[buttons[buttonIndex]] = true;
                controls.push(buttons[buttonIndex]);
            }
        }
        liveDigitalControlNames = controls;
        liveOtherAxisNames = axes.filter(function (name) {
            return ["leftx", "lefty", "rightx", "righty"].indexOf(name) === -1
                && !root.isProfileDigitalTrigger(name);
        });
    }

    function liveControlPressed(name) {
        if (liveButtonNames.indexOf(name) !== -1)
            return liveButtonPressed(name);
        var threshold = profile && profile.thresholds ? Number(profile.thresholds.digitalTriggerPress || 0.75) : 0.75;
        return liveAxisValue(name) >= threshold;
    }

    function liveControlIndicator(name) {
        if (isProfileDigitalTrigger(name))
            return liveAxisValue(name).toFixed(2);
        return liveControlPressed(name) ? "[x]" : "[ ]";
    }

    function stickActive(xValue, yValue) {
        var thresholds = phase !== "idle" && diagnostic.thresholds ? diagnostic.thresholds : (profile && profile.thresholds ? profile.thresholds : null);
        var threshold = thresholds ? Number(thresholds.movementDetection || 0.2) : 0.2;
        return Math.abs(xValue) >= threshold || Math.abs(yValue) >= threshold;
    }

    function conciseControlLabel(control) {
        var label = controlLabel(control);
        var limit = compactLayout ? 20 : 36;
        return label.length > limit ? label.slice(0, limit - 3) + "..." : label;
    }

    function scrollLiveButtons(direction) {
        if (selectedView !== "live" || !liveButtonsScrollable)
            return false;
        var maximum = Math.max(0, liveButtonViewport.contentHeight - liveButtonViewport.height);
        liveButtonViewport.contentY = Math.max(0, Math.min(maximum,
            liveButtonViewport.contentY + (direction < 0 ? -Style.space(48) : Style.space(48))));
        return true;
    }

    function scrollGuidedContent(direction) {
        if (!guidedVisible || !guidedContentScrollable)
            return false;
        var maximum = Math.max(0, digitalChecklist.contentHeight - digitalChecklist.height);
        digitalChecklist.contentY = Math.max(0, Math.min(maximum,
            digitalChecklist.contentY + (direction < 0 ? -Style.space(48) : Style.space(48))));
        return true;
    }

    function diagnosticAxisValue(name) {
        return Number(diagnostic.currentAxes && diagnostic.currentAxes[name] || 0);
    }

    function activeStickPrefix() {
        return phase === "analog_right" ? "right" : "left";
    }

    function directionReached(control, positive) {
        var item = result(control);
        if (!item)
            return false;
        var thresholdName = positive ? "minimumPositiveRange" : "minimumNegativeRange";
        var required = Number(diagnostic.thresholds && diagnostic.thresholds[thresholdName] || 0.75);
        return positive ? item.maximum !== null && item.maximum >= required : item.minimum !== null && item.minimum <= -required;
    }

    function buildActionLabels() {
        if (!supported && phase === "idle")
            return [];
        if (phase === "idle")
            return ["Start guided diagnostic"];
        if (phase === "baseline_waiting")
            return ["Begin baseline", "Cancel"];
        if (phase === "baseline_capturing")
            return ["Cancel"];
        if (phase === "digital")
            return diagnostic.retryTarget ? ["Review now"] : ["Skip to left stick", "Review now"];
        if (phase === "analog_left")
            return diagnostic.retryTarget ? ["Review now"] : ["Skip to right stick", "Review now"];
        if (phase === "analog_right")
            return ["Review now"];
        if (phase === "review") {
            var labels = [];
            if (retryControls.length > 0)
                labels.push("Retry " + conciseControlLabel(selectedRetryControl()));
            labels.push("Export report");
            if (supported)
                labels.push("New diagnostic");
            labels.push("Done");
            return labels;
        }
        return [];
    }

    function titleText() {
        if (phase === "idle")
            return supported ? "GUIDED DIAGNOSTIC" : "GUIDED DIAGNOSTIC UNAVAILABLE";
        if (phase === "baseline_waiting")
            return "NEUTRAL BASELINE";
        if (phase === "baseline_capturing")
            return "CAPTURING NEUTRAL INPUT";
        if (phase === "digital")
            return "DIGITAL CONTROLS  " + completedDigital + "/" + availableDigital;
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
                : "Press and release each control in any order. The stick test starts automatically when all controls are complete. Next: " + nextDigitalLabel() + ".";
        if (phase === "analog_left")
            return diagnostic.retryTarget
                ? "Move " + controlLabel(diagnostic.retryTarget) + " through both directions."
                : "Move the left stick to the full range in all four directions.";
        if (phase === "analog_right")
            return diagnostic.retryTarget
                ? "Move " + controlLabel(diagnostic.retryTarget) + " through both directions."
                : "Move the right stick to the full range in all four directions.";
        var tested = diagnostic.controller && diagnostic.controller.name ? String(diagnostic.controller.name) : String(diagnostic.profileName || "Controller");
        var connection = diagnostic.controller && diagnostic.controller.connection ? String(diagnostic.controller.connection) : "unknown connection";
        var summary = "Tested controller: " + tested + " (" + connection + "). "
            + statusCount("passed") + " passed, " + statusCount("warning") + " warning, "
            + statusCount("not_detected") + " not detected, " + statusCount("incomplete") + " incomplete, "
            + statusCount("unavailable") + " unavailable.";
        if (diagnostic.connected === false)
            summary += " The tested controller disconnected before completion.";
        return summary;
    }

    function setSelectedView(view) {
        selectedView = view === "guided" ? "guided" : "live";
        modeFocusRequested();
    }

    function moveMode(delta) {
        selectedView = delta < 0 ? "live" : "guided";
        focusModeTabs();
    }

    function focusModeTabs() {
        // Keyboard focus remains on the panel-level key catcher.
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
        if (!visible || !guidedVisible || actionLabels.length === 0)
            return;
        // Keyboard focus remains on the panel-level key catcher.
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
            if (diagnostic.retryTarget)
                service.finalizeDiagnostics();
            else if (index === 0)
                service.advanceDiagnostics();
            else
                service.finalizeDiagnostics();
        } else if (phase === "analog_right") {
            service.finalizeDiagnostics();
        } else if (phase === "review") {
            var cursor = 0;
            if (retryControls.length > 0) {
                if (index === cursor) {
                    service.retryDiagnostic(selectedRetryControl());
                    return;
                }
                cursor++;
            }
            if (index === cursor) {
                exportRequested();
                return;
            }
            cursor++;
            if (supported) {
                if (index === cursor) {
                    service.beginDiagnostics(controller, profile);
                    return;
                }
                cursor++;
            }
            if (index === cursor)
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

    Ui.CursorSurface {
        id: contentSurface
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.contentHeight
        bordered: true
        foreground: root.foreground

        Item {
            id: contentFrame
            anchors.fill: parent
            anchors.margins: Style.space(12)

            Ui.ButtonGroup {
                id: modeTabs
                anchors.top: parent.top
                anchors.left: parent.left
                options: [{ value: "live", label: "Live Input" }, { value: "guided", label: "Guided Diagnostic" }]
                value: root.selectedView
                focusable: false
                cursorIndex: root.modeHasCursor ? (root.selectedView === "live" ? 0 : 1) : -1
                foreground: root.foreground
                background: root.background
                fontFamily: root.fontFamily
                onChanged: function (value) {
                    root.setSelectedView(value);
                }
            }

            Text {
                visible: root.active && root.selectedView === "live"
                anchors.right: parent.right
                anchors.verticalCenter: modeTabs.verticalCenter
                text: "GUIDED DIAGNOSTIC RUNNING"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
            }

            Item {
                id: modeBody
                anchors.top: modeTabs.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.topMargin: Style.space(18)

            Row {
                visible: root.selectedView === "live"
                anchors.fill: parent
                spacing: Style.space(14)

                Column {
                    id: liveAnalogPane
                    width: Math.floor((parent.width - parent.spacing) * 0.58)
                    height: parent.height
                    spacing: Style.space(6)

                    Row {
                        id: liveSticks
                        width: parent.width
                        height: Math.max(0, parent.height - (liveOtherAxisFlow.visible ? liveOtherAxisFlow.implicitHeight + parent.spacing : 0))
                        spacing: Style.space(12)

                        StickVisualizer {
                            width: (parent.width - parent.spacing) / 2
                            height: parent.height
                            heading: "LEFT STICK"
                            xValue: root.liveAxisValue("leftx")
                            yValue: root.liveAxisValue("lefty")
                        }

                        StickVisualizer {
                            width: (parent.width - parent.spacing) / 2
                            height: parent.height
                            heading: "RIGHT STICK"
                            xValue: root.liveAxisValue("rightx")
                            yValue: root.liveAxisValue("righty")
                        }
                    }

                    Flow {
                        id: liveOtherAxisFlow
                        visible: root.liveOtherAxisNames.length > 0
                        width: parent.width
                        spacing: Style.space(6)
                        readonly property int columns: Math.min(4, root.liveOtherAxisNames.length)

                        Repeater {
                            model: root.liveOtherAxisNames

                            delegate: Rectangle {
                                required property string modelData
                                width: liveOtherAxisFlow.columns > 0
                                    ? (liveOtherAxisFlow.width - liveOtherAxisFlow.spacing * (liveOtherAxisFlow.columns - 1)) / liveOtherAxisFlow.columns : 0
                                height: Style.space(22)
                                color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.05)
                                border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                                border.width: 1
                                radius: Style.cornerRadius

                                Text {
                                    id: otherAxisLabel
                                    anchors.centerIn: parent
                                    textFormat: Text.PlainText
                                    text: Profiles.labelFor(root.profile, parent.modelData) + "  " + root.liveAxisValue(parent.modelData).toFixed(2)
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }
                    }
                }

                Column {
                    id: liveButtonsPane
                    width: parent.width - liveAnalogPane.width - parent.spacing
                    height: parent.height
                    spacing: Style.space(4)

                    Ui.PanelSectionHeader {
                        text: "BUTTONS"
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                    }

                    Item {
                        width: parent.width
                        height: Math.max(0, parent.height - y)

                        Flickable {
                            id: liveButtonViewport
                            anchors.fill: parent
                            contentWidth: width
                            contentHeight: liveButtonFlow.implicitHeight
                            flickableDirection: Flickable.VerticalFlick
                            boundsBehavior: Flickable.StopAtBounds
                            clip: true

                            Flow {
                                id: liveButtonFlow
                                width: liveButtonViewport.width
                                spacing: Style.space(4)
                                readonly property int columns: width >= Style.space(260) ? 4 : 3

                                Repeater {
                                    model: root.liveDigitalControlNames

                                    delegate: Rectangle {
                                        required property string modelData
                                        readonly property bool pressed: root.liveControlPressed(modelData)
                                        width: (liveButtonFlow.width - liveButtonFlow.spacing * (liveButtonFlow.columns - 1)) / liveButtonFlow.columns
                                        height: Style.space(root.compactLayout ? 22 : 24)
                                        color: pressed ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
                                        border.color: pressed ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                                        border.width: 1
                                        radius: Style.cornerRadius

                                        Text {
                                            id: liveCheckMark
                                            anchors.left: parent.left
                                            anchors.leftMargin: Style.space(5)
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: root.liveControlIndicator(parent.modelData)
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }

                                        Text {
                                            anchors.left: liveCheckMark.right
                                            anchors.right: parent.right
                                            anchors.rightMargin: Style.space(5)
                                            anchors.verticalCenter: parent.verticalCenter
                                            textFormat: Text.PlainText
                                            text: Profiles.labelFor(root.profile, parent.modelData)
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            horizontalAlignment: Text.AlignRight
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }

                        ScrollEdgeFades {
                            anchors.fill: parent
                            flickable: liveButtonViewport
                            background: root.background
                        }
                    }
                }
            }

            Item {
                visible: root.guidedVisible
                anchors.fill: parent

                Ui.PanelSectionHeader {
                    id: guidedHeader
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    text: root.titleText()
                    foreground: root.foreground
                    fontFamily: root.fontFamily
                }

                Text {
                    id: guidedInstruction
                    anchors.top: guidedHeader.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.topMargin: Style.space(6)
                    textFormat: Text.PlainText
                    text: root.instructionText()
                    color: Qt.darker(root.foreground, 1.3)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                    wrapMode: Text.WordWrap
                }

                Item {
                    id: actionFooter
                    visible: root.actionLabels.length > 0
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
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
                                tooltipText: root.phase === "review" && root.retryControls.length > 0 && index === 0
                                    ? "Retry " + root.controlLabel(root.selectedRetryControl()) : ""
                                bordered: true
                                focusable: false
                                hasCursor: root.actionsHaveCursor && root.actionIndex === index
                                foreground: root.foreground
                                background: root.background
                                fontFamily: root.fontFamily
                                onClicked: {
                                    root.actionIndex = index;
                                    root.actionFocusRequested();
                                    root.activateAction(index);
                                }
                            }
                        }
                    }
                }

                Flickable {
                    id: digitalChecklist
                    visible: root.phase === "digital"
                    anchors.top: guidedInstruction.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: actionFooter.top
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    contentWidth: width
                    contentHeight: digitalChipFlow.implicitHeight
                    flickableDirection: Flickable.VerticalFlick
                    boundsBehavior: Flickable.StopAtBounds
                    clip: true

                    Flow {
                        id: digitalChipFlow
                        width: digitalChecklist.width
                        spacing: Style.space(5)

                        Repeater {
                            model: root.diagnostic.digitalControls || []

                            delegate: Rectangle {
                                required property string modelData
                                readonly property var diagnosticResult: root.result(modelData)
                                readonly property bool unavailable: diagnosticResult && !diagnosticResult.available
                                readonly property bool complete: diagnosticResult && diagnosticResult.available && diagnosticResult.pressed && diagnosticResult.released
                                width: Math.min(digitalChipFlow.width,
                                    guidedCheckMark.implicitWidth + chipLabel.implicitWidth + Style.space(26))
                                height: Style.space(24)
                                color: complete ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
                                border.color: complete ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                                border.width: 1
                                radius: Style.cornerRadius

                                Text {
                                    id: guidedCheckMark
                                    anchors.left: parent.left
                                    anchors.leftMargin: Style.space(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: parent.unavailable ? "[-]" : (parent.complete ? "[x]" : "[ ]")
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }

                                Text {
                                    id: chipLabel
                                    anchors.left: guidedCheckMark.right
                                    anchors.leftMargin: Style.space(8)
                                    anchors.right: parent.right
                                    anchors.rightMargin: Style.space(6)
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: root.controlLabel(parent.modelData)
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }
                }

                ScrollEdgeFades {
                    visible: digitalChecklist.visible
                    anchors.fill: digitalChecklist
                    flickable: digitalChecklist
                    background: root.background
                }

                StickVisualizer {
                    visible: root.phase === "analog_left" || root.phase === "analog_right"
                    anchors.top: guidedInstruction.bottom
                    anchors.left: parent.left
                    anchors.bottom: actionFooter.top
                    anchors.topMargin: Style.space(8)
                    anchors.bottomMargin: Style.space(8)
                    width: Math.min(parent.width, Style.space(560))
                    xValue: root.diagnosticAxisValue(root.activeStickPrefix() + "x")
                    yValue: root.diagnosticAxisValue(root.activeStickPrefix() + "y")
                    showDirections: true
                    directionItems: [
                        { label: "-X", reached: root.directionReached(root.activeStickPrefix() + "x", false) },
                        { label: "+X", reached: root.directionReached(root.activeStickPrefix() + "x", true) },
                        { label: "-Y", reached: root.directionReached(root.activeStickPrefix() + "y", false) },
                        { label: "+Y", reached: root.directionReached(root.activeStickPrefix() + "y", true) }
                    ]
                }
            }
            }
        }
    }

    component StickVisualizer: Item {
        id: stickVisual

        property string heading: ""
        property real xValue: 0
        property real yValue: 0
        property bool showDirections: false
        property var directionItems: []
        readonly property bool active: root.stickActive(xValue, yValue)

        Text {
            id: stickHeading
            visible: stickVisual.heading !== ""
            anchors.top: parent.top
            anchors.left: parent.left
            textFormat: Text.PlainText
            text: stickVisual.heading
            color: Qt.darker(root.foreground, 1.4)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: true
        }

        Row {
            anchors.top: stickHeading.visible ? stickHeading.bottom : parent.top
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.topMargin: stickHeading.visible ? Style.space(4) : 0
            spacing: Style.space(10)

            Rectangle {
                id: stickPlot
                width: Math.min(parent.height, Math.max(0, parent.width * 0.46))
                height: width
                anchors.verticalCenter: parent.verticalCenter
                color: stickVisual.active ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                    : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
                border.color: stickVisual.active ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                border.width: 1
                radius: Style.cornerRadius

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 1
                    height: parent.height
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                }

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 1
                    color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)
                }

                Rectangle {
                    width: Style.space(10)
                    height: width
                    radius: width / 2
                    color: root.foreground
                    x: (parent.width - width) / 2 * (1 + Math.max(-1, Math.min(1, stickVisual.xValue)))
                    y: (parent.height - height) / 2 * (1 + Math.max(-1, Math.min(1, stickVisual.yValue)))
                }
            }

            Column {
                width: parent.width - stickPlot.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(7)

                Text {
                    width: parent.width
                    textFormat: Text.PlainText
                    text: "X  " + stickVisual.xValue.toFixed(2) + "\nY  " + stickVisual.yValue.toFixed(2)
                    color: root.foreground
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                }

                Flow {
                    visible: stickVisual.showDirections
                    width: parent.width
                    spacing: Style.space(6)

                    Repeater {
                        model: stickVisual.directionItems

                        delegate: Rectangle {
                            required property var modelData
                            width: directionCheckMark.implicitWidth + directionLabel.implicitWidth + Style.space(26)
                            height: Style.space(26)
                            color: modelData.reached ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12) : "transparent"
                            border.color: modelData.reached ? root.foreground : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.35)
                            border.width: 1
                            radius: Style.cornerRadius

                            Text {
                                id: directionCheckMark
                                anchors.left: parent.left
                                anchors.leftMargin: Style.space(6)
                                anchors.verticalCenter: parent.verticalCenter
                                text: parent.modelData.reached ? "[x]" : "[ ]"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                            }

                            Text {
                                id: directionLabel
                                anchors.left: directionCheckMark.right
                                anchors.leftMargin: Style.space(8)
                                anchors.right: parent.right
                                anchors.rightMargin: Style.space(6)
                                anchors.verticalCenter: parent.verticalCenter
                                textFormat: Text.PlainText
                                text: parent.modelData.label
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                }
            }
        }
    }
}
