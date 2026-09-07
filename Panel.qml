pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model
import "profiles/ProfileRegistry.js" as Profiles
import "components" as Components

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
    property string currentMode: "overview"
    property int focusRegion: 0
    property var registeredStreamingService: null
    property string registeredStreamingId: ""
    property var visibleAxisNames: []

    readonly property bool opened: detailsWindow.visible
    readonly property var controller: service ? service.selectedController : null
    readonly property string selectedControllerId: controller ? String(controller.id) : ""
    readonly property var controllerTabs: service ? service.controllerTabs : []
    readonly property var controllerProfile: Profiles.profileFor(controller)
    readonly property int tabCount: controllerTabs.length
    readonly property string selectedProfileId: controllerProfile ? controllerProfile.id : ""
    readonly property string mode: currentMode
    readonly property string streamingControllerId: registeredStreamingId
    readonly property real scrollPosition: scroll.contentItem ? scroll.contentItem.contentY : 0
    readonly property string pluginId: manifest && manifest.id ? manifest.id : "lightqv.gamepads"
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property string fontFamily: Style.font.family
    readonly property string scriptsDir: localPath(Qt.resolvedUrl("scripts/")).replace(/\/$/, "")

    readonly property string ruleInstanceToken: Math.floor(Date.now()).toString(36) + "-" + Math.floor(Math.random() * 2147483647).toString(36)

    Component.onDestruction: {
        clearStreamingRequest();
        var tokens = pendingCleanupTokens.slice();
        if (ruleCleanupProcess.running && tokens.indexOf(ruleCleanupProcess.ruleToken) === -1)
            tokens.push(ruleCleanupProcess.ruleToken);
        if (activeRuleToken !== "" && tokens.indexOf(activeRuleToken) === -1)
            tokens.push(activeRuleToken);
        if (tokens.length > 0)
            Quickshell.execDetached(scriptCommand("clear-details-window-rule", tokens.slice(0, 64)));
    }

    onOpenedChanged: syncStreamingRequest()
    onServiceChanged: syncStreamingRequest()
    onControllerChanged: {
        syncStreamingRequest();
        refreshAxisNames();
    }
    onSelectedControllerIdChanged: resetScroll()
    onControllerProfileChanged: {
        if (!controllerProfile)
            currentMode = "overview";
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
            focusCurrentRegion();
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

    function handleCloseRequest() {
        if (currentMode === "input-test") {
            setMode("overview");
            return;
        }
        requestClose();
    }

    function cycleController(delta) {
        if (service && service.connectedCount > 1)
            service.cycleSelection(delta);
    }

    function selectController(controllerId) {
        if (service && typeof service.selectController === "function")
            service.selectController(controllerId);
    }

    function setMode(nextMode) {
        if (nextMode !== "overview" && nextMode !== "input-test")
            return false;
        if (nextMode === "input-test" && !controllerProfile)
            return false;
        currentMode = nextMode;
        resetScroll();
        return true;
    }

    function modeOptions() {
        var options = [
            {
                value: "overview",
                label: "Overview",
                icon: "󰋼"
            }
        ];
        if (controllerProfile) {
            options.push({
                value: "input-test",
                label: "Input Test",
                icon: "󰐾"
            });
        }
        return options;
    }

    function focusCurrentRegion() {
        if (focusRegion === 0 && tabCount > 0)
            controllerTabsControl.focusTabs();
        else {
            focusRegion = 1;
            modeSelector.forceActiveFocus();
        }
    }

    function moveFocusRegion(direction) {
        if (tabCount === 0) {
            focusRegion = 1;
        } else {
            var step = direction < 0 ? -1 : 1;
            focusRegion = (focusRegion + step + 2) % 2;
        }
        focusCurrentRegion();
    }

    function scrollContent(direction, page) {
        if (!scroll.contentItem)
            return;
        var amount = page ? Math.max(Style.space(80), scroll.height * 0.8) : Style.space(48);
        var maximum = Math.max(0, scroll.contentItem.contentHeight - scroll.contentItem.height);
        scroll.contentItem.contentY = Math.max(0, Math.min(maximum, scroll.contentItem.contentY + (direction < 0 ? -amount : amount)));
    }

    function resetScroll() {
        Qt.callLater(function () {
            if (scroll.contentItem)
                scroll.contentItem.contentY = 0;
        });
    }

    function clearStreamingRequest() {
        if (registeredStreamingService && typeof registeredStreamingService.setStreamingRequest === "function")
            registeredStreamingService.setStreamingRequest("floating-panel", null);
        registeredStreamingService = null;
        registeredStreamingId = "";
    }

    function syncStreamingRequest() {
        var targetId = opened && controller ? String(controller.id) : "";
        if (registeredStreamingService && (registeredStreamingService !== service || targetId === ""))
            registeredStreamingService.setStreamingRequest("floating-panel", null);
        if (!service || typeof service.setStreamingRequest !== "function" || targetId === "") {
            registeredStreamingService = null;
            registeredStreamingId = "";
            return;
        }
        if (registeredStreamingService !== service || registeredStreamingId !== targetId)
            service.setStreamingRequest("floating-panel", [targetId]);
        registeredStreamingService = service;
        registeredStreamingId = targetId;
    }

    function pressedButtonsLabel() {
        if (!controller)
            return "None";
        var pressed = [];
        var names = Object.keys(controller.buttons || {});
        for (var i = 0; i < names.length; i++) {
            if (controller.buttons[names[i]])
                pressed.push(Profiles.labelFor(controllerProfile, names[i]));
        }
        return pressed.length > 0 ? pressed.join(", ") : "None";
    }

    function refreshAxisNames() {
        var names = controller && controller.capabilities && controller.capabilities.axes ? controller.capabilities.axes : [];
        if (JSON.stringify(names) !== JSON.stringify(visibleAxisNames))
            visibleAxisNames = names.slice();
    }

    function axisValue(name) {
        return controller && controller.axes ? Number(controller.axes[name] || 0).toFixed(2) : "0.00";
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
            Keys.onPressed: function (event) {
                if (event.key === Qt.Key_PageDown) {
                    root.scrollContent(1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.scrollContent(-1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    if (scroll.contentItem)
                        scroll.contentItem.contentY = 0;
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    root.scrollContent(1, true);
                    if (scroll.contentItem)
                        scroll.contentItem.contentY = Math.max(0, scroll.contentItem.contentHeight - scroll.contentItem.height);
                    event.accepted = true;
                }
            }

            Ui.PanelKeyCatcher {
                id: keyCatcher
                anchors.fill: parent
                onMoveRequested: function (dx, dy) {
                    if (dy !== 0)
                        root.scrollContent(dy, false);
                }
                onTabRequested: function (direction) {
                    root.moveFocusRegion(direction);
                }
                onCloseRequested: root.handleCloseRequest()

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

                        Components.ControllerTabs {
                            id: controllerTabsControl
                            visible: root.tabCount > 0
                            width: parent.width
                            controllers: root.controllerTabs
                            selectedId: root.service ? root.service.selectedId : ""
                            foreground: root.foreground
                            background: root.background
                            fontFamily: root.fontFamily
                            onSelected: function (controllerId) {
                                root.selectController(controllerId);
                            }
                        }

                        Ui.ButtonGroup {
                            id: modeSelector
                            visible: !!root.controller
                            options: root.modeOptions()
                            value: root.currentMode
                            foreground: root.foreground
                            background: root.background
                            fontFamily: root.fontFamily
                            onChanged: function (value) {
                                root.setMode(value);
                            }
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

                                Ui.PanelSectionHeader {
                                    text: "SELECTED CONTROLLER"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
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
                                visible: !!root.controller && root.currentMode === "overview"
                                width: parent.width
                                spacing: Style.space(8)

                                Ui.PanelSectionHeader {
                                    text: "OVERVIEW"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                }

                                Loader {
                                    id: profileView
                                    visible: !!root.controllerProfile
                                    width: parent.width
                                    active: root.opened && root.currentMode === "overview" && !!root.controllerProfile
                                    source: root.controllerProfile ? Qt.resolvedUrl("profiles/" + root.controllerProfile.viewComponent) : ""
                                    onLoaded: {
                                        if (!item)
                                            return;
                                        item.controller = Qt.binding(function () {
                                            return root.controller;
                                        });
                                        item.foreground = Qt.binding(function () {
                                            return root.foreground;
                                        });
                                        item.fontFamily = Qt.binding(function () {
                                            return root.fontFamily;
                                        });
                                    }
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

                                DetailRow {
                                    width: parent.width
                                    label: "Detailed profile"
                                    value: root.controllerProfile ? root.controllerProfile.displayName : "Not available"
                                }

                                Ui.Button {
                                    visible: !!root.controllerProfile
                                    text: "Open Input Test"
                                    iconText: "󰐾"
                                    bordered: true
                                    foreground: root.foreground
                                    background: root.background
                                    fontFamily: root.fontFamily
                                    Accessible.role: Accessible.Button
                                    Accessible.name: text
                                    Accessible.onPressAction: root.setMode("input-test")
                                    onClicked: root.setMode("input-test")
                                }
                            }

                            Ui.CursorSurface {
                                visible: !!root.controller && !root.controllerProfile
                                width: parent.width
                                implicitHeight: unsupportedContent.implicitHeight + Style.space(24)
                                bordered: true
                                foreground: root.foreground

                                Column {
                                    id: unsupportedContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.margins: Style.space(12)
                                    spacing: Style.space(6)

                                    Text {
                                        width: parent.width
                                        text: "Detailed profile unavailable"
                                        color: root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.title
                                        font.bold: true
                                    }

                                    Text {
                                        width: parent.width
                                        text: "This SDL-recognized controller keeps its vitals and controller tab, but does not yet have a visual or guided input-test profile."
                                        color: Qt.darker(root.foreground, 1.35)
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                        wrapMode: Text.WordWrap
                                    }
                                }
                            }

                            Column {
                                visible: !!root.controller && root.currentMode === "input-test" && !!root.controllerProfile
                                width: parent.width
                                spacing: Style.space(8)

                                Ui.PanelSectionHeader {
                                    text: "LIVE INPUT"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                }

                                Text {
                                    width: parent.width
                                    text: "Live input is active for this controller. Guided checks and diagnostic results are added in Phase 5."
                                    color: Qt.darker(root.foreground, 1.35)
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.bodySmall
                                    wrapMode: Text.WordWrap
                                }

                                DetailRow {
                                    width: parent.width
                                    label: "Pressed buttons"
                                    value: root.pressedButtonsLabel()
                                }

                                Repeater {
                                    model: root.visibleAxisNames

                                    delegate: DetailRow {
                                        required property string modelData
                                        width: content.width
                                        label: Profiles.labelFor(root.controllerProfile, modelData)
                                        value: root.axisValue(modelData)
                                    }
                                }

                                Ui.Button {
                                    text: "End Input Test"
                                    iconText: "󰅖"
                                    bordered: true
                                    foreground: root.foreground
                                    background: root.background
                                    fontFamily: root.fontFamily
                                    Accessible.role: Accessible.Button
                                    Accessible.name: text
                                    Accessible.onPressAction: root.setMode("overview")
                                    onClicked: root.setMode("overview")
                                }
                            }

                            Text {
                                visible: !root.controller
                                width: parent.width
                                textFormat: Text.PlainText
                                text: root.service ? (root.service.health === "starting" || root.service.health === "restarting" ? "The gamepad backend is starting." : "No SDL-recognized gamepads are connected.") : "The shared gamepad service is unavailable."
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
