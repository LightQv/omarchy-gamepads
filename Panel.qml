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
    property var registeredStreamingService: null
    property string registeredStreamingId: ""
    property string exportMessage: ""

    readonly property bool opened: detailsWindow.visible
    readonly property var controller: service ? service.selectedController : null
    readonly property string selectedControllerId: controller ? String(controller.id) : ""
    readonly property var controllerTabs: service ? service.controllerTabs : []
    readonly property var controllerProfile: Profiles.profileFor(controller)
    readonly property int tabCount: controllerTabs.length
    readonly property string selectedProfileId: controllerProfile ? controllerProfile.id : ""
    readonly property string streamingControllerId: registeredStreamingId
    readonly property real scrollPosition: scroll.contentItem ? scroll.contentItem.contentY : 0
    readonly property bool visualProfileActive: profileView.active && profileView.status === Loader.Ready && !!profileView.item
    readonly property bool informationFits: !controller || information.implicitHeight <= scroll.height
    readonly property real visualPaneWidth: visualPane.width
    readonly property var diagnosticState: service && service.diagnosticState ? service.diagnosticState : ({ phase: "idle" })
    readonly property string diagnosticPhase: diagnosticState.phase || "idle"
    readonly property bool diagnosticActive: ["baseline_waiting", "baseline_capturing", "digital", "analog_left", "analog_right"].indexOf(diagnosticPhase) !== -1
    readonly property bool diagnosticSessionOpen: diagnosticPhase !== "idle"
    readonly property bool testedControllerPresent: diagnosticControllerIsPresent()
    readonly property string selectedBottomView: diagnosticTray.selectedView
    readonly property int liveButtonCount: diagnosticTray.liveButtonCount
    readonly property int liveDigitalControlCount: diagnosticTray.liveDigitalControlCount
    readonly property var liveDigitalControlNames: diagnosticTray.liveDigitalControlNames
    readonly property bool liveLeftStickActive: diagnosticTray.liveLeftStickActive
    readonly property bool liveRightStickActive: diagnosticTray.liveRightStickActive
    readonly property string guidedDiagnosticTitle: diagnosticTray.titleText()
    readonly property real inputContentHeight: diagnosticTray.modeContentHeight
    readonly property bool liveButtonsScrollable: diagnosticTray.liveButtonsScrollable
    readonly property real liveButtonScrollPosition: diagnosticTray.liveButtonScrollPosition
    readonly property string actionCursorRow: diagnosticTray.cursorRow
    readonly property int actionCursorIndex: diagnosticTray.cursorRow === "mode" ? diagnosticTray.modeIndex
        : (diagnosticTray.cursorRow === "retry" ? diagnosticTray.retryIndex : diagnosticTray.actionIndex)
    readonly property string retryCursorControl: diagnosticTray.selectedRetryControl()
    readonly property real defaultWindowWidth: detailsWindow.implicitWidth
    readonly property real defaultWindowHeight: detailsWindow.implicitHeight
    readonly property bool cancelConfirmationOpen: cancelDialog.opened
    readonly property string pluginId: manifest && manifest.id ? manifest.id : "lightqv.gamepads"
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property string fontFamily: Style.font.family
    readonly property string scriptsDir: localPath(Qt.resolvedUrl("scripts/")).replace(/\/$/, "")

    readonly property string ruleInstanceToken: Math.floor(Date.now()).toString(36) + "-" + Math.floor(Math.random() * 2147483647).toString(36)

    Component.onDestruction: {
        if (diagnosticActive && service && typeof service.interruptDiagnostics === "function")
            service.interruptDiagnostics();
        clearStreamingRequest();
        exportTimer.stop();
        if (exportProcess.running)
            exportProcess.running = false;
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
    }
    onSelectedControllerIdChanged: resetScroll()
    onDiagnosticPhaseChanged: {
        syncStreamingRequest();
        if (diagnosticPhase !== "review")
            exportMessage = "";
        Qt.callLater(diagnosticTray.normalizeCursor);
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
        if (!diagnosticSessionOpen && service && typeof payload.controllerId === "string" && /^[1-9][0-9]{0,19}$/.test(payload.controllerId))
            service.selectController(payload.controllerId);
        if (!diagnosticSessionOpen)
            diagnosticTray.setSelectedView("live");
        else
            diagnosticTray.normalizeCursor();
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
        if (diagnosticActive && service && typeof service.cancelDiagnostics === "function")
            service.cancelDiagnostics();
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
        if (cancelDialog.opened) {
            cancelDialog.opened = false;
            return;
        }
        if (diagnosticActive) {
            showCancelConfirmation();
            return;
        }
        requestClose();
    }

    function confirmDiagnosticCancel() {
        cancelDialog.opened = false;
        if (service && typeof service.cancelDiagnostics === "function")
            service.cancelDiagnostics();
    }

    function showCancelConfirmation() {
        cancelDialog.selectedIndex = 0;
        cancelDialog.opened = true;
        Qt.callLater(cancelDialog.forceActiveFocus);
    }

    function cycleController(delta) {
        if (!diagnosticActive && service && service.connectedCount > 1)
            service.cycleSelection(delta);
    }

    function selectController(controllerId) {
        if (!diagnosticActive && service && typeof service.selectController === "function")
            service.selectController(controllerId);
    }

    function diagnosticControllerIsPresent() {
        if (!service || diagnosticState.controllerPresent === false || diagnosticState.controllerId === undefined)
            return false;
        var id = String(diagnosticState.controllerId || "");
        var controllers = service.controllers || [];
        for (var i = 0; i < controllers.length; i++) {
            if (String(controllers[i].id) === id)
                return true;
        }
        return false;
    }

    function focusCurrentRegion() {
        keyCatcher.forceActiveFocus();
    }

    function handleNavigation(dx, dy) {
        diagnosticTray.moveCursor(dx, dy);
    }

    function activateCurrentRegion() {
        diagnosticTray.activateCursor();
    }

    function scrollContent(direction, page) {
        if (!scroll.contentItem)
            return;
        var amount = page ? Math.max(Style.space(80), scroll.height * 0.8) : Style.space(48);
        var maximum = Math.max(0, scroll.contentItem.contentHeight - scroll.contentItem.height);
        scroll.contentItem.contentY = Math.max(0, Math.min(maximum, scroll.contentItem.contentY + (direction < 0 ? -amount : amount)));
    }

    function scrollVisibleContent(direction, page) {
        if (!diagnosticTray.scrollVisibleContent(direction, page))
            scrollContent(direction, page);
    }

    function scrollVisibleContentToEdge(end) {
        if (diagnosticTray.scrollVisibleContentToEdge(end))
            return;
        if (scroll.contentItem)
            scroll.contentItem.contentY = end ? Math.max(0, scroll.contentItem.contentHeight - scroll.contentItem.height) : 0;
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
        var targetId = opened && diagnosticActive && diagnosticState.connected !== false
            ? String(diagnosticState.controllerId || "")
            : (opened && controller ? String(controller.id) : "");
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

    function axisValue(name) {
        return controller && controller.axes ? Number(controller.axes[name] || 0).toFixed(2) : "0.00";
    }

    function liveButtonIsPressed(name) {
        return diagnosticTray.liveControlPressed(name);
    }

    function liveControlIndicator(name) {
        return diagnosticTray.liveControlIndicator(name);
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

    function exportDiagnosticReport() {
        if (!service || diagnosticPhase !== "review" || exportProcess.running)
            return;
        var metadata = {
            pluginVersion: manifest && manifest.version ? String(manifest.version) : "",
            sdlVersion: service.backendVersion || "",
            backendWarningCodes: service.lastErrorCode ? [service.lastErrorCode] : []
        };
        var payload = JSON.stringify({
            report: service.diagnosticReport(metadata),
            text: service.diagnosticTextReport(metadata)
        });
        if (payload.length > 1048576) {
            exportMessage = "Report export failed: report is too large.";
            return;
        }
        exportProcess.payload = payload;
        exportMessage = "Exporting report...";
        exportProcess.running = true;
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

    Process {
        id: exportProcess
        property string payload: ""
        command: ["/usr/bin/python3", "-E", "-s", root.scriptsDir + "/export-diagnostic-report.py"]
        stdinEnabled: true
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                try {
                    var result = JSON.parse(text || "{}");
                    root.exportMessage = result.ok ? "Report exported: " + result.basename : "Report export failed.";
                } catch (error) {
                    root.exportMessage = "Report export failed.";
                }
            }
        }
        onStarted: {
            exportTimer.restart();
            exportProcess.write(exportProcess.payload + "\n");
        }
        onExited: function (exitCode) {
            exportTimer.stop();
            if (exitCode !== 0)
                root.exportMessage = "Report export failed.";
            exportProcess.payload = "";
        }
    }

    Timer {
        id: exportTimer
        interval: 10000
        onTriggered: {
            if (exportProcess.running)
                exportProcess.running = false;
            root.exportMessage = "Report export timed out.";
        }
    }

    FloatingWindow {
        id: detailsWindow
        visible: false
        title: "Gamepad Details"
        color: root.background
        implicitWidth: 1120
        implicitHeight: 760
        minimumSize: Qt.size(760, 540)

        onVisibleChanged: {
            if (!visible && root.openRequested && !root.closingFromHost) {
                if (root.diagnosticActive && root.service)
                    root.service.cancelDiagnostics();
                root.requestClose();
            }
        }

        FocusScope {
            id: detailsFocusScope
            anchors.fill: parent
            focus: true
            onActiveFocusChanged: {
                if (activeFocus && detailsWindow.visible)
                    Qt.callLater(root.focusCurrentRegion);
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: function (event) {
                if (cancelDialog.opened && cancelDialog.handleKey(event)) {
                    event.accepted = true;
                } else if (cancelDialog.opened && event.key === Qt.Key_Space) {
                    if (cancelDialog.selectedIndex === 0)
                        cancelDialog.canceled();
                    else
                        cancelDialog.confirmed();
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageDown) {
                    root.scrollVisibleContent(1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_PageUp) {
                    root.scrollVisibleContent(-1, true);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Home) {
                    root.scrollVisibleContentToEdge(false);
                    event.accepted = true;
                } else if (event.key === Qt.Key_End) {
                    root.scrollVisibleContentToEdge(true);
                    event.accepted = true;
                }
            }

            Ui.PanelKeyCatcher {
                id: keyCatcher
                anchors.fill: parent
                blocked: cancelDialog.opened
                onMoveRequested: function (dx, dy) {
                    root.handleNavigation(dx, dy);
                }
                onTabRequested: function (direction) {
                    root.cycleController(direction);
                }
                onActivateRequested: root.activateCurrentRegion()
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
                            enabled: !root.diagnosticActive
                            opacity: root.diagnosticActive ? 0.55 : 1
                            onSelected: function (controllerId) {
                                root.selectController(controllerId);
                            }
                        }
                    }

                    Item {
                        id: workspace
                        width: parent.width
                        height: Math.max(0, frame.height - fixedHeader.height - frame.spacing)

                        Row {
                            id: mainPanes
                            visible: !!root.controller
                            anchors.top: parent.top
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: Math.max(0, parent.height - (diagnosticTray.visible ? diagnosticTray.height + Style.space(12) : 0))
                            spacing: Style.space(18)

                            Item {
                                id: informationPane
                                width: {
                                    var available = parent.width - parent.spacing;
                                    return Math.min(Math.max(280, Math.floor(available * 0.38)), available - 360);
                                }
                                height: parent.height

                                ScrollView {
                                    id: scroll
                                    anchors.fill: parent
                                    clip: true
                                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                    ScrollBar.vertical.policy: ScrollBar.AlwaysOff

                                    Column {
                                        id: information
                                        width: scroll.availableWidth
                                        spacing: Style.space(12)

                                    Ui.PanelSectionHeader {
                                        text: "SELECTED CONTROLLER"
                                        foreground: root.foreground
                                        fontFamily: root.fontFamily
                                    }

                                    Ui.CursorSurface {
                                        width: parent.width
                                        implicitHeight: controllerIdentity.implicitHeight + Style.space(20)
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

                                    Ui.PanelSectionHeader {
                                        text: "DETAILS"
                                        foreground: root.foreground
                                        fontFamily: root.fontFamily
                                    }

                                    DetailRow {
                                        width: parent.width
                                        label: "Family"
                                        value: root.controller && root.controller.family ? root.controller.family : "Unknown"
                                    }

                                    DetailRow {
                                        width: parent.width
                                        label: "Profile"
                                        value: root.controllerProfile ? root.controllerProfile.displayName : "Not available"
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

                                Components.ScrollEdgeFades {
                                    anchors.fill: parent
                                    flickable: scroll.contentItem
                                    background: root.background
                                }
                            }

                            Item {
                                id: visualPane
                                width: parent.width - informationPane.width - parent.spacing
                                height: parent.height

                                Ui.PanelSectionHeader {
                                    id: visualHeader
                                    text: "CONTROLLER VIEW"
                                    foreground: root.foreground
                                    fontFamily: root.fontFamily
                                }

                                Loader {
                                    id: profileView
                                    active: root.opened && !!root.controllerProfile
                                    visible: active
                                    anchors.top: visualHeader.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: Style.space(8)
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

                                Ui.CursorSurface {
                                    visible: !root.controllerProfile
                                    anchors.top: visualHeader.bottom
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.topMargin: Style.space(8)
                                    bordered: true
                                    foreground: root.foreground

                                    Column {
                                        anchors.centerIn: parent
                                        width: Math.min(parent.width - Style.space(48), Style.space(440))
                                        spacing: Style.space(8)

                                        Text {
                                            width: parent.width
                                            text: "Detailed profile unavailable"
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.title
                                            font.bold: true
                                            horizontalAlignment: Text.AlignHCenter
                                        }

                                        Text {
                                            width: parent.width
                                            text: "This SDL-recognized controller keeps its vitals and device tab, but does not yet have a visual or guided diagnostic profile."
                                            color: Qt.darker(root.foreground, 1.35)
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.bodySmall
                                            horizontalAlignment: Text.AlignHCenter
                                            wrapMode: Text.WordWrap
                                        }
                                    }
                                }
                            }
                        }

                        Column {
                            visible: !root.controller
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.verticalCenter: mainPanes.verticalCenter
                            width: Math.min(parent.width, Style.space(520))
                            spacing: Style.space(8)

                            Text {
                                width: parent.width
                                textFormat: Text.PlainText
                                text: root.service ? (root.service.health === "starting" || root.service.health === "restarting" ? "The gamepad backend is starting." : "No SDL-recognized gamepads are connected.") : "The shared gamepad service is unavailable."
                                color: Qt.darker(root.foreground, 1.4)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                horizontalAlignment: Text.AlignHCenter
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
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                            }
                        }

                        Components.DiagnosticTray {
                            id: diagnosticTray
                            visible: !!root.controller || root.diagnosticSessionOpen
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            service: root.service
                            controller: root.controller
                            profile: root.controllerProfile
                            exportMessage: root.exportMessage
                            foreground: root.foreground
                            background: root.background
                            fontFamily: root.fontFamily
                            enabled: !cancelDialog.opened
                            testedControllerPresent: root.testedControllerPresent
                            compactLayout: detailsWindow.height < 650
                            onCancelRequested: root.showCancelConfirmation()
                            onExportRequested: root.exportDiagnosticReport()
                        }
                    }
                }
            }

            Ui.ConfirmDialog {
                id: cancelDialog
                anchors.fill: parent
                z: 10
                message: "End this diagnostic session and review the incomplete results?"
                cancelText: "Resume"
                confirmText: "End test"
                background: root.background
                foreground: root.foreground
                fontFamily: root.fontFamily
                focus: opened
                onOpenedChanged: {
                    if (opened)
                        forceActiveFocus();
                    else if (root.diagnosticSessionOpen)
                        root.focusCurrentRegion();
                }
                onCanceled: opened = false
                onConfirmed: {
                    root.confirmDiagnosticCancel();
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
