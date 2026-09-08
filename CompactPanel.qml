pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model
import "components" as Components

Ui.Panel {
    id: root

    moduleName: "lightqv.gamepads"
    ipcTarget: "lightqv.gamepads.compact"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property var service: null
    property bool cursorActive: false
    property string focusSection: "header"
    property int selectedIndex: 0
    property bool actionFocused: false

    readonly property var barIdentity: hostWidget || root
    readonly property color foreground: bar ? bar.foreground : Color.popups.text
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
    readonly property bool retryVisible: service && (service.dependencyMissing || service.health === "error")
    readonly property bool settingsHasCursor: cursorActive && focusSection === "header"

    onServiceChanged: clampCursor()
    onRetryVisibleChanged: clampCursor()

    Connections {
        target: root.service

        function onConnectedCountChanged() {
            root.clampCursor();
        }

        function onControllersChanged() {
            root.clampCursor();
        }
    }

    function connectedSubtitle() {
        var count = service ? service.connectedCount : 0;
        if (count === 0)
            return "NO CONTROLLERS";
        return count + " CONNECTED";
    }

    function controllerStatus(controller) {
        if (!controller)
            return "";
        var labels = [Model.connectionLabel(controller), Model.batteryLabel(controller)];
        var batteryState = Model.batteryStateLabel(controller);
        if (batteryState !== "")
            labels.push(batteryState);
        return labels.join("  ·  ");
    }

    function selectedControllerIndex() {
        if (!service)
            return 0;
        for (var i = 0; i < service.controllers.length; i++) {
            if (service.controllers[i].id === service.selectedId)
                return i;
        }
        return 0;
    }

    function clampCursor() {
        var count = service ? service.connectedCount : 0;
        if (focusSection === "controllers" && count === 0) {
            focusSection = retryVisible ? "retry" : "header";
            selectedIndex = 0;
            actionFocused = false;
        } else if (focusSection === "controllers") {
            selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex));
        } else if (focusSection === "retry" && !retryVisible) {
            focusSection = count > 0 ? "controllers" : "header";
            selectedIndex = count > 0 ? selectedControllerIndex() : 0;
            actionFocused = false;
        }
        Qt.callLater(ensureCursorVisible);
    }

    function setHeaderCursor() {
        cursorActive = true;
        focusSection = "header";
        selectedIndex = 0;
        actionFocused = false;
    }

    function setControllerCursor(index, detailsAction) {
        cursorActive = true;
        focusSection = "controllers";
        selectedIndex = Math.max(0, Math.min((service ? service.connectedCount : 1) - 1, index));
        actionFocused = detailsAction === true;
        ensureCursorVisible();
    }

    function ensureCursorVisible() {
        var item = null;
        if (focusSection === "header")
            item = heroItem;
        else if (focusSection === "controllers")
            item = controllerRepeater.itemAt(selectedIndex);
        else if (focusSection === "retry")
            item = retryButton;
        if (!item)
            return;
        var point = item.mapToItem(scroll.contentItem, 0, 0);
        if (point.y < scroll.contentItem.contentY)
            scroll.contentItem.contentY = point.y;
        else if (point.y + item.height > scroll.contentItem.contentY + scroll.height)
            scroll.contentItem.contentY = point.y + item.height - scroll.height;
    }

    function moveCursor(dx, dy) {
        if (!cursorActive) {
            cursorActive = true;
            if (service && service.connectedCount > 0) {
                focusSection = "controllers";
                selectedIndex = selectedControllerIndex();
            } else {
                focusSection = "header";
            }
            actionFocused = false;
            ensureCursorVisible();
            return;
        }
        if (dx !== 0 && focusSection === "controllers") {
            actionFocused = dx > 0;
            return;
        }
        if (dy === 0)
            return;

        var count = service ? service.connectedCount : 0;
        if (focusSection === "header") {
            if (dy > 0)
                focusSection = count > 0 ? "controllers" : (retryVisible ? "retry" : "header");
            else
                focusSection = retryVisible ? "retry" : (count > 0 ? "controllers" : "header");
            selectedIndex = focusSection === "controllers" ? (dy > 0 ? 0 : count - 1) : 0;
        } else if (focusSection === "controllers") {
            var next = selectedIndex + dy;
            if (next < 0) {
                focusSection = "header";
                selectedIndex = 0;
            } else if (next >= count) {
                focusSection = retryVisible ? "retry" : "header";
                selectedIndex = 0;
            } else {
                selectedIndex = next;
            }
        } else {
            focusSection = dy > 0 ? "header" : (count > 0 ? "controllers" : "header");
            selectedIndex = focusSection === "controllers" ? count - 1 : 0;
        }
        actionFocused = false;
        ensureCursorVisible();
    }

    function activateCursor() {
        if (!cursorActive)
            return;
        if (focusSection === "header") {
            openDetails("");
        } else if (focusSection === "controllers" && service && selectedIndex < service.controllers.length) {
            var controller = service.controllers[selectedIndex];
            if (actionFocused)
                openDetails(controller.id);
            else
                service.selectController(controller.id);
        } else if (focusSection === "retry" && service) {
            service.retry();
        }
    }

    function open() {
        cursorActive = false;
        focusSection = service && service.connectedCount > 0 ? "controllers" : "header";
        selectedIndex = selectedControllerIndex();
        actionFocused = false;
        root.controller.show();
        Qt.callLater(function () {
            scroll.contentItem.contentY = 0;
        });
    }

    function close() {
        root.controller.hide();
    }

    function toggle() {
        root.opened ? root.close() : root.open();
    }

    function switchPanel(direction) {
        if (root.bar && typeof root.bar.switchPanelFrom === "function")
            return root.bar.switchPanelFrom(root.barIdentity, direction);
        return false;
    }

    function openDetails(controllerId) {
        var payload = {
            view: "gamepads"
        };
        if (controllerId !== "") {
            if (service)
                service.selectController(controllerId);
            payload.controllerId = controllerId;
        }
        close();
        if (bar && bar.shell && typeof bar.shell.summon === "function")
            bar.shell.summon(moduleName, JSON.stringify(payload));
    }

    Ui.KeyboardPanel {
        id: popup
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: popup.fittedContentWidth(Style.space(380))
        contentHeight: popup.fittedContentHeight(panelColumn.implicitHeight, Style.space(560))

        Ui.PanelKeyCatcher {
            id: keyCatcher
            anchors.fill: parent
            onMoveRequested: function (dx, dy) {
                root.moveCursor(dx, dy);
            }
            onActivateRequested: root.activateCursor()
            onCloseRequested: root.close()
            onTabRequested: function (direction) {
                root.switchPanel(direction);
            }

            ScrollView {
                id: scroll
                anchors.fill: parent
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical.policy: panelColumn.implicitHeight > height ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                Binding {
                    target: scroll.contentItem
                    property: "interactive"
                    value: panelColumn.implicitHeight > scroll.height
                }

                Column {
                    id: panelColumn
                    width: scroll.availableWidth
                    spacing: Style.space(14)

                    Item {
                        id: heroItem
                        width: parent.width
                        implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, settingsButton.implicitHeight)

                        Text {
                            id: heroIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰊴"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.display
                        }

                        Column {
                            id: heroLabels
                            anchors.left: heroIcon.right
                            anchors.leftMargin: Style.space(14)
                            anchors.right: settingsButton.left
                            anchors.rightMargin: Style.space(12)
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Style.space(2)

                            Text {
                                width: parent.width
                                text: "Gamepads"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.title
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                text: root.connectedSubtitle()
                                color: Qt.darker(root.foreground, 1.4)
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.bold: true
                                font.letterSpacing: 1.2
                                elide: Text.ElideRight
                            }
                        }

                        Ui.Button {
                            id: settingsButton
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            iconText: "󰒓"
                            tooltipText: "Gamepad details"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                            iconSize: Style.font.subtitle * 1.5
                            horizontalPadding: Style.space(5)
                            verticalPadding: Style.space(2)
                            hasCursor: root.settingsHasCursor
                            Accessible.role: Accessible.Button
                            Accessible.name: tooltipText
                            Accessible.onPressAction: root.openDetails("")
                            onHovered: function (hovered) {
                                if (hovered)
                                    root.setHeaderCursor();
                            }
                            onClicked: root.openDetails("")
                        }
                    }

                    Ui.PanelSeparator {
                        foreground: root.foreground
                    }

                    Column {
                        visible: root.service && root.service.connectedCount > 0
                        width: parent.width
                        spacing: Style.space(8)

                        Ui.PanelSectionHeader {
                            text: "CONNECTED"
                            foreground: root.foreground
                            fontFamily: root.fontFamily
                        }

                        Repeater {
                            id: controllerRepeater
                            model: root.service ? root.service.controllers : []

                            delegate: Ui.CursorSurface {
                                id: controllerRow
                                required property var modelData
                                required property int index

                                width: parent ? parent.width : 0
                                implicitHeight: rowContent.implicitHeight + Style.spacing.xl
                                hasCursor: root.cursorActive && root.focusSection === "controllers" && root.selectedIndex === index && !root.actionFocused
                                current: root.service && root.service.selectedId === modelData.id
                                foreground: root.foreground

                                MouseArea {
                                    id: rowMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onContainsMouseChanged: if (containsMouse)
                                        root.setControllerCursor(controllerRow.index, false)
                                    onClicked: if (root.service)
                                        root.service.selectController(controllerRow.modelData.id)
                                }

                                Item {
                                    id: rowContent
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: Style.space(10)
                                    anchors.rightMargin: Style.space(10)
                                    implicitHeight: Math.max(deviceIcon.implicitHeight, labels.implicitHeight, detailsAction.implicitHeight)

                                    Text {
                                        id: deviceIcon
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "󰊴"
                                        color: Model.batteryIsLow(controllerRow.modelData) ? Color.urgent : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.heading
                                    }

                                    Column {
                                        id: labels
                                        anchors.left: deviceIcon.right
                                        anchors.leftMargin: Style.space(10)
                                        anchors.right: detailsAction.left
                                        anchors.rightMargin: Style.space(8)
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: Style.space(1)

                                        Text {
                                            width: parent.width
                                            textFormat: Text.PlainText
                                            text: controllerRow.modelData.name
                                            color: root.foreground
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.body
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            textFormat: Text.PlainText
                                            text: root.controllerStatus(controllerRow.modelData)
                                            color: Model.batteryIsLow(controllerRow.modelData) ? Color.urgent : Qt.darker(root.foreground, 1.4)
                                            font.family: root.fontFamily
                                            font.pixelSize: Style.font.caption
                                            elide: Text.ElideRight
                                        }
                                    }

                                    Ui.PanelActionButton {
                                        id: detailsAction
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        iconText: "󰋼"
                                        tooltipText: "Open details"
                                        foreground: root.foreground
                                        hoverColor: root.foreground
                                        fontFamily: root.fontFamily
                                        hasCursor: root.cursorActive && root.focusSection === "controllers" && root.selectedIndex === controllerRow.index && root.actionFocused
                                        Accessible.role: Accessible.Button
                                        Accessible.name: "Open details for " + controllerRow.modelData.name
                                        Accessible.onPressAction: root.openDetails(controllerRow.modelData.id)
                                        onHovered: function (hovered) {
                                            if (hovered)
                                                root.setControllerCursor(controllerRow.index, true);
                                            else if (rowMouse.containsMouse)
                                                root.actionFocused = false;
                                        }
                                        onClicked: root.openDetails(controllerRow.modelData.id)
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        visible: !root.service || root.service.connectedCount === 0
                        width: parent.width
                        textFormat: Text.PlainText
                        text: {
                            if (!root.service)
                                return "The shared gamepad service is unavailable.";
                            if (root.service.dependencyMissing)
                                return root.service.lastErrorMessage || "PySDL3 is not installed.";
                            if (root.service.health === "error")
                                return root.service.lastErrorMessage;
                            if (root.service.health === "starting" || root.service.health === "restarting")
                                return "Starting the controller backend...";
                            return "Connect a supported controller to see its vitals.";
                        }
                        color: root.service && (root.service.dependencyMissing || root.service.health === "error") ? Color.urgent : Qt.darker(root.foreground, 1.5)
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.service && root.service.backendWarning
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.service ? root.service.lastErrorMessage : ""
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    Text {
                        visible: root.service && root.service.protocolError !== ""
                        width: parent.width
                        textFormat: Text.PlainText
                        text: root.service ? root.service.protocolError : ""
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.WordWrap
                    }

                    Ui.Button {
                        id: retryButton
                        visible: root.retryVisible
                        width: parent.width
                        text: "Retry backend"
                        iconText: "󰑓"
                        leftAlign: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        hasCursor: root.cursorActive && root.focusSection === "retry"
                        Accessible.role: Accessible.Button
                        Accessible.name: "Retry gamepad backend"
                        Accessible.onPressAction: if (root.service)
                            root.service.retry()
                        onHovered: function (hovered) {
                            if (hovered) {
                                root.cursorActive = true;
                                root.focusSection = "retry";
                                root.actionFocused = false;
                            }
                        }
                        onClicked: if (root.service)
                            root.service.retry()
                    }
                }
            }

            Components.ScrollEdgeFades {
                anchors.fill: parent
                flickable: scroll.contentItem
                background: Color.popups.background
            }
        }
    }
}
