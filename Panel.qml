pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

// Tooling cannot resolve Quickshell's QProcess::ExitStatus signal parameter.
// qmllint disable signal-handler-parameters

Item {
    id: root

    property var shell: null
    property var manifest: null
    property var service: null
    property bool closingFromHost: false
    property bool openRequested: false
    property bool windowRuleReady: false
    property string pendingPlacementToken: ""
    property int ruleGeneration: 0
    property string activeRuleToken: ""
    property var pendingCleanupTokens: []

    readonly property bool opened: detailsWindow.visible
    readonly property var controller: service ? service.selectedController : null
    readonly property string pluginId: manifest && manifest.id ? manifest.id : "lightqv.gamepads"
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property string fontFamily: Style.font.family
    readonly property string scriptsDir: localPath(Qt.resolvedUrl("scripts/")).replace(/\/$/, "")

    readonly property string ruleInstanceToken: Math.floor(Date.now()).toString(36) + "-" + Math.floor(Math.random() * 2147483647).toString(36)

    Component.onDestruction: {
        var tokens = pendingCleanupTokens.slice();
        if (ruleCleanupProcess.running && tokens.indexOf(ruleCleanupProcess.ruleToken) === -1)
            tokens.push(ruleCleanupProcess.ruleToken);
        if (activeRuleToken !== "" && tokens.indexOf(activeRuleToken) === -1)
            tokens.push(activeRuleToken);
        if (tokens.length > 0)
            Quickshell.execDetached(scriptCommand("clear-details-window-rule", tokens.slice(0, 64)));
    }

    function localPath(url) {
        return decodeURIComponent(String(url).replace(/^file:\/\//, ""));
    }

    function scriptCommand(name, args) {
        return ["/bin/bash", scriptsDir + "/" + name].concat(args || []);
    }

    function nextRuleToken() {
        ruleGeneration += 1;
        return ruleInstanceToken + "-" + ruleGeneration;
    }

    function scheduleRuleCleanup(ruleToken) {
        if (ruleToken === "")
            return;
        if (ruleCleanupProcess.running && ruleCleanupProcess.ruleToken === ruleToken)
            return;
        var tokens = pendingCleanupTokens.slice();
        if (tokens.indexOf(ruleToken) === -1)
            tokens.push(ruleToken);
        pendingCleanupTokens = tokens;
        drainRuleCleanup();
    }

    function drainRuleCleanup() {
        if (ruleCleanupProcess.running || pendingCleanupTokens.length === 0)
            return;
        var tokens = pendingCleanupTokens.slice();
        ruleCleanupProcess.ruleToken = tokens.shift();
        pendingCleanupTokens = tokens;
        ruleCleanupProcess.running = true;
    }

    function parseOpenRequest(payloadJson) {
        var payload = {};
        var rawPayload = String(payloadJson || "{}");
        if (rawPayload.length > 4096)
            return payload;
        try {
            var parsed = JSON.parse(rawPayload) || {};
            if (parsed && !Array.isArray(parsed) && typeof parsed === "object")
                payload = parsed;
        } catch (error) {}
        return payload;
    }

    function open(payloadJson) {
        var payload = parseOpenRequest(payloadJson);
        if (service && typeof payload.controllerId === "string" && /^[1-9][0-9]{0,19}$/.test(payload.controllerId))
            service.selectController(payload.controllerId);
        openRequested = true;
        closingFromHost = false;
        if (windowRuleReady)
            showOnCurrentWorkspace();
        else if (!windowRuleProcess.running) {
            activeRuleToken = nextRuleToken();
            windowRuleProcess.ruleToken = activeRuleToken;
            windowRuleProcess.running = true;
        }
    }

    function showOnCurrentWorkspace() {
        if (!openRequested)
            return;
        detailsWindow.visible = true;
        schedulePlacement();
        Qt.callLater(function () {
            if (!detailsWindow.visible)
                return;
            keyCatcher.forceActiveFocus();
        });
    }

    function schedulePlacement() {
        if (placementProcess.running) {
            pendingPlacementToken = activeRuleToken;
            return;
        }
        placementProcess.ruleToken = activeRuleToken;
        placementProcess.running = true;
    }

    function close() {
        openRequested = false;
        closingFromHost = true;
        detailsWindow.visible = false;
        closingFromHost = false;
    }

    function requestClose() {
        openRequested = false;
        if (shell && typeof shell.hide === "function")
            shell.hide(pluginId);
        else
            close();
    }

    function cycleController(delta) {
        if (service && service.connectedCount > 1)
            service.cycleSelection(delta);
    }

    function connectionSummary() {
        if (!controller)
            return "No controller selected";
        var labels = [Model.connectionLabel(controller), Model.batteryLabel(controller)];
        var batteryState = Model.batteryStateLabel(controller);
        if (batteryState !== "")
            labels.push(batteryState);
        return labels.join("  ·  ");
    }

    Process {
        id: windowRuleProcess
        property string ruleToken: ""
        command: root.scriptCommand("prepare-details-window", [ruleToken])
        onExited: function (exitCode) {
            if (root.openRequested) {
                root.windowRuleReady = true;
                root.showOnCurrentWorkspace();
            } else {
                root.windowRuleReady = false;
                root.scheduleRuleCleanup(windowRuleProcess.ruleToken);
            }
        }
    }

    Process {
        id: ruleCleanupProcess
        property string ruleToken: ""
        command: root.scriptCommand("clear-details-window-rule", [ruleToken])
        onExited: function (exitCode) {
            Qt.callLater(root.drainRuleCleanup);
        }
    }

    Process {
        id: placementProcess
        property string ruleToken: ""
        command: root.scriptCommand("place-details-window", [ruleToken])
        onExited: function (exitCode) {
            var completedToken = placementProcess.ruleToken;
            if (root.activeRuleToken === completedToken) {
                root.windowRuleReady = false;
                root.activeRuleToken = "";
            }
            var pendingToken = root.pendingPlacementToken;
            root.pendingPlacementToken = "";
            if (pendingToken === "")
                return;
            Qt.callLater(function () {
                if (!root.openRequested)
                    return;
                if (root.activeRuleToken !== "" && root.activeRuleToken !== pendingToken)
                    return;
                placementProcess.ruleToken = pendingToken;
                placementProcess.running = true;
            });
        }
    }

    FloatingWindow {
        id: detailsWindow
        visible: false
        title: "Gamepad Details"
        color: root.background
        implicitWidth: 680
        implicitHeight: 560
        minimumSize: Qt.size(560, 420)

        onVisibleChanged: {
            if (!visible && root.openRequested && !root.closingFromHost)
                root.requestClose();
        }

        FocusScope {
            anchors.fill: parent
            focus: true

            Ui.PanelKeyCatcher {
                id: keyCatcher
                anchors.fill: parent
                onMoveRequested: function (dx, dy) {
                    if (dx !== 0)
                        root.cycleController(dx);
                }
                onTabRequested: function (direction) {
                    root.cycleController(direction);
                }
                onCloseRequested: root.requestClose()

                Column {
                    id: frame
                    anchors.fill: parent
                    anchors.margins: Style.space(22)
                    spacing: Style.space(18)

                    Column {
                        id: fixedHeader
                        width: parent.width
                        spacing: Style.space(18)

                        Row {
                            width: parent.width
                            spacing: Style.space(14)

                            Text {
                                text: "󰊴"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.display
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Column {
                                width: parent.width - parent.children[0].width - parent.spacing
                                spacing: Style.space(3)

                                Text {
                                    text: "Gamepads"
                                    color: root.foreground
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.iconLarge
                                    font.bold: true
                                }

                                Text {
                                    width: parent.width
                                    text: "Inspect connected controllers, input capabilities, and diagnostics."
                                    color: Qt.darker(root.foreground, 1.35)
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                }
                            }
                        }

                        Ui.PanelSeparator {
                            foreground: root.foreground
                        }
                    }

                    ScrollView {
                        id: scroll
                        width: parent.width
                        height: Math.max(0, frame.height - fixedHeader.height - frame.spacing)
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: content.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                        Column {
                            id: content
                            width: scroll.availableWidth
                            spacing: Style.space(18)

                            Column {
                                visible: !!root.controller
                                width: parent.width
                                spacing: Style.space(8)

                                Item {
                                    width: parent.width
                                    implicitHeight: Math.max(controllerHeader.implicitHeight, controllerActions.implicitHeight)

                                    Ui.PanelSectionHeader {
                                        id: controllerHeader
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "CONTROLLER"
                                        foreground: root.foreground
                                        fontFamily: root.fontFamily
                                    }

                                    Row {
                                        id: controllerActions
                                        visible: root.service && root.service.connectedCount > 1
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.space(6)

                                        Ui.PanelActionButton {
                                            iconText: "󰅁"
                                            tooltipText: "Previous controller"
                                            foreground: root.foreground
                                            fontFamily: root.fontFamily
                                            focusable: false
                                            Accessible.role: Accessible.Button
                                            Accessible.name: tooltipText
                                            Accessible.onPressAction: root.cycleController(-1)
                                            onClicked: root.cycleController(-1)
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: {
                                                if (!root.service || !root.controller)
                                                    return "";
                                                var index = 0;
                                                for (var i = 0; i < root.service.controllers.length; i++) {
                                                    if (root.service.controllers[i].id === root.controller.id) {
                                                        index = i;
                                                        break;
                                                    }
                                                }
                                                return (index + 1) + " / " + root.service.connectedCount;
                                            }
                                            color: Qt.darker(root.foreground, 1.4)
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                        }

                                        Ui.PanelActionButton {
                                            iconText: "󰅂"
                                            tooltipText: "Next controller"
                                            foreground: root.foreground
                                            fontFamily: root.fontFamily
                                            focusable: false
                                            Accessible.role: Accessible.Button
                                            Accessible.name: tooltipText
                                            Accessible.onPressAction: root.cycleController(1)
                                            onClicked: root.cycleController(1)
                                        }
                                    }
                                }

                                Ui.CursorSurface {
                                    width: parent.width
                                    implicitHeight: controllerIdentity.implicitHeight + Style.space(24)
                                    current: true
                                    bordered: true
                                    foreground: root.foreground

                                    Row {
                                        id: controllerIdentity
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        anchors.leftMargin: Style.space(12)
                                        anchors.rightMargin: Style.space(12)
                                        spacing: Style.space(12)

                                        Text {
                                            text: "󰊴"
                                            color: Model.batteryIsLow(root.controller) ? Color.urgent : root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.display
                                            anchors.verticalCenter: parent.verticalCenter
                                        }

                                        Column {
                                            width: parent.width - parent.children[0].width - parent.spacing
                                            spacing: Style.space(3)

                                            Text {
                                                width: parent.width
                                                textFormat: Text.PlainText
                                                text: root.controller ? root.controller.name : ""
                                                color: root.foreground
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.title
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                textFormat: Text.PlainText
                                                text: root.connectionSummary()
                                                color: Model.batteryIsLow(root.controller) ? Color.urgent : Qt.darker(root.foreground, 1.35)
                                                font.family: root.fontFamily
                                                font.pixelSize: Style.font.bodySmall
                                                elide: Text.ElideRight
                                            }
                                        }
                                    }
                                }
                            }

                            Ui.PanelSeparator {
                                visible: !!root.controller
                                foreground: root.foreground
                            }

                            Column {
                                visible: !!root.controller
                                width: parent.width
                                spacing: Style.space(8)

                                Ui.PanelSectionHeader {
                                    text: "OVERVIEW"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                }

                                DetailRow {
                                    width: parent.width
                                    label: "Connection"
                                    value: root.controller ? Model.connectionLabel(root.controller) : ""
                                }

                                DetailRow {
                                    width: parent.width
                                    label: "Battery"
                                    value: root.controller ? Model.batteryLabel(root.controller) : ""
                                    urgent: Model.batteryIsLow(root.controller)
                                }

                                DetailRow {
                                    visible: root.controller && Model.batteryStateLabel(root.controller) !== ""
                                    width: parent.width
                                    label: "Power state"
                                    value: root.controller ? Model.batteryStateLabel(root.controller) : ""
                                }

                                DetailRow {
                                    width: parent.width
                                    label: "Controller family"
                                    value: root.controller && root.controller.family ? root.controller.family : "Unknown"
                                }
                            }

                            Text {
                                visible: !root.controller
                                width: parent.width
                                textFormat: Text.PlainText
                                text: root.service ? "Connect a supported controller to view its details." : "The shared gamepad service is unavailable."
                                color: Qt.darker(root.foreground, 1.4)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                wrapMode: Text.WordWrap
                            }

                            Text {
                                visible: root.service && (root.service.backendWarning || root.service.health === "error")
                                width: parent.width
                                textFormat: Text.PlainText
                                text: root.service ? root.service.lastErrorMessage : ""
                                color: Color.urgent
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }
        }
    }

    component DetailRow: Ui.CursorSurface {
        id: detailRow

        property string label: ""
        property string value: ""
        property bool urgent: false

        implicitHeight: detailContent.implicitHeight + Style.space(18)
        bordered: true
        foreground: root.foreground

        Row {
            id: detailContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: Style.space(12)
            anchors.rightMargin: Style.space(12)
            spacing: Style.space(12)

            Text {
                width: Math.min(Style.space(180), parent.width * 0.4)
                textFormat: Text.PlainText
                text: detailRow.label
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
            }

            Text {
                width: parent.width - parent.children[0].width - parent.spacing
                textFormat: Text.PlainText
                text: detailRow.value
                color: detailRow.urgent ? Color.urgent : root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                font.bold: true
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
            }
        }
    }
}
