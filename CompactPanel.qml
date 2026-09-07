import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.Panel {
    id: root

    moduleName: "lightqv.gamepads"
    ipcTarget: "lightqv.gamepads.compact"
    manageIpc: false

    property var anchorItem: null
    property var hostWidget: null
    property var service: null
    property int selectedAction: 0

    readonly property var barIdentity: hostWidget || root
    readonly property var selectedGamepad: service ? service.selectedController : null
    readonly property real selectedBatteryFraction: Model.batteryFraction(selectedGamepad)
    readonly property int actionCount: service && (service.dependencyMissing || service.health === "error") ? 2 : 1
    readonly property color foreground: Color.popups.text
    readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

    onActionCountChanged: selectedAction = Math.min(selectedAction, actionCount - 1)
    onSelectedActionChanged: Qt.callLater(ensureActionVisible)

    function ensureActionVisible() {
        var item = selectedAction === 0 ? detailsButton : retryButton;
        if (!item || !item.visible)
            return;
        var point = item.mapToItem(scroll.contentItem, 0, 0);
        if (point.y < scroll.contentY)
            scroll.contentY = point.y;
        else if (point.y + item.height > scroll.contentY + scroll.height)
            scroll.contentY = point.y + item.height - scroll.height;
    }

    function open() {
        selectedAction = 0;
        root.controller.show();
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

    function moveCursor(dx, dy) {
        if (dx !== 0 && service && service.connectedCount > 1)
            service.cycleSelection(dx);
        if (dy !== 0)
            selectedAction = Math.max(0, Math.min(actionCount - 1, selectedAction + dy));
    }

    function activateCursor() {
        if (selectedAction === 0) {
            openDetails();
        } else if (service) {
            service.retry();
        }
    }

    function openDetails() {
        var id = service ? service.selectedId : "";
        close();
        if (bar && bar.shell && typeof bar.shell.summon === "function")
            bar.shell.summon(moduleName, JSON.stringify({
                controllerId: id
            }));
    }

    Ui.KeyboardPanel {
        id: popup
        anchorItem: root.anchorItem
        owner: root.barIdentity
        bar: root.bar
        open: root.opened
        focusTarget: keyCatcher
        contentWidth: popup.fittedContentWidth(Style.space(340))
        contentHeight: popup.fittedContentHeight(content.implicitHeight)

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

            Flickable {
                id: scroll
                anchors.fill: parent
                contentWidth: width
                contentHeight: content.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                ColumnLayout {
                    id: content
                    width: scroll.width
                    spacing: Style.space(12)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(10)

                        Text {
                            text: "󰊴"
                            color: root.foreground
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.iconLarge
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(2)

                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: root.selectedGamepad ? root.selectedGamepad.name : "GAMEPADS"
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.body
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: root.service && root.service.connectedCount > 0 ? root.service.connectedCount + " CONNECTED" : "NO CONTROLLERS"
                                color: Color.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.letterSpacing: 1
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.spacing.hairline
                        color: root.foreground
                        opacity: 0.12
                    }

                    ColumnLayout {
                        visible: !!root.selectedGamepad
                        Layout.fillWidth: true
                        spacing: Style.space(8)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: Model.connectionLabel(root.selectedGamepad)
                                color: root.foreground
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.bodySmall
                            }

                            Item {
                                Layout.fillWidth: true
                            }

                            ColumnLayout {
                                spacing: Style.space(2)

                                RowLayout {
                                    spacing: Style.space(6)

                                    Rectangle {
                                        visible: root.selectedBatteryFraction >= 0
                                        Layout.preferredWidth: Style.space(28)
                                        Layout.preferredHeight: Style.space(12)
                                        radius: Math.min(Style.cornerRadius, height / 2)
                                        color: "transparent"
                                        border.width: Style.spacing.hairline
                                        border.color: Model.batteryIsLow(root.selectedGamepad) ? Color.urgent : root.foreground

                                        Rectangle {
                                            anchors.left: parent.left
                                            anchors.top: parent.top
                                            anchors.bottom: parent.bottom
                                            anchors.margins: Style.spacing.hairline * 2
                                            width: Math.max(0, (parent.width - anchors.margins * 2) * root.selectedBatteryFraction)
                                            radius: Math.max(0, parent.radius - anchors.margins)
                                            color: Model.batteryIsLow(root.selectedGamepad) ? Color.urgent : root.foreground
                                        }
                                    }

                                    Text {
                                        text: Model.batteryLabel(root.selectedGamepad)
                                        color: Model.batteryIsLow(root.selectedGamepad) ? Color.urgent : root.foreground
                                        font.family: root.fontFamily
                                        font.pixelSize: Style.font.bodySmall
                                    }
                                }

                                Text {
                                    Layout.alignment: Qt.AlignRight
                                    text: Model.batteryStateLabel(root.selectedGamepad)
                                    visible: text !== ""
                                    color: Color.muted
                                    font.family: root.fontFamily
                                    font.pixelSize: Style.font.caption
                                }
                            }
                        }

                        RowLayout {
                            visible: root.service && root.service.connectedCount > 1
                            Layout.fillWidth: true

                            Ui.Button {
                                iconText: "󰅁"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                tooltipText: "Previous controller"
                                Accessible.role: Accessible.Button
                                Accessible.name: tooltipText
                                Accessible.onPressAction: if (root.service)
                                    root.service.cycleSelection(-1)
                                onClicked: if (root.service)
                                    root.service.cycleSelection(-1)
                            }

                            Text {
                                Layout.fillWidth: true
                                horizontalAlignment: Text.AlignHCenter
                                text: {
                                    if (!root.service || !root.selectedGamepad)
                                        return "";
                                    var index = -1;
                                    for (var i = 0; i < root.service.controllers.length; i++)
                                        if (root.service.controllers[i].id === root.selectedGamepad.id)
                                            index = i;
                                    return (index + 1) + " OF " + root.service.connectedCount;
                                }
                                color: Color.muted
                                font.family: root.fontFamily
                                font.pixelSize: Style.font.caption
                                font.letterSpacing: 1
                            }

                            Ui.Button {
                                iconText: "󰅂"
                                foreground: root.foreground
                                fontFamily: root.fontFamily
                                tooltipText: "Next controller"
                                Accessible.role: Accessible.Button
                                Accessible.name: tooltipText
                                Accessible.onPressAction: if (root.service)
                                    root.service.cycleSelection(1)
                                onClicked: if (root.service)
                                    root.service.cycleSelection(1)
                            }
                        }
                    }

                    Text {
                        visible: !root.selectedGamepad
                        Layout.fillWidth: true
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
                        color: root.service && (root.service.dependencyMissing || root.service.health === "error") ? Color.urgent : Color.muted
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: root.service && root.service.backendWarning
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: root.service ? root.service.lastErrorMessage : ""
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }

                    Text {
                        visible: root.service && root.service.protocolError !== ""
                        Layout.fillWidth: true
                        text: root.service ? root.service.protocolError : ""
                        color: Color.urgent
                        font.family: root.fontFamily
                        font.pixelSize: Style.font.caption
                        wrapMode: Text.Wrap
                    }

                    Ui.Button {
                        id: detailsButton
                        Layout.fillWidth: true
                        text: "Details"
                        iconText: "󰋼"
                        leftAlign: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        hasCursor: root.selectedAction === 0
                        Accessible.role: Accessible.Button
                        Accessible.name: "Open gamepad details"
                        Accessible.onPressAction: root.openDetails()
                        onHovered: function (hovered) {
                            if (hovered)
                                root.selectedAction = 0;
                        }
                        onClicked: root.openDetails()
                    }

                    Ui.Button {
                        id: retryButton
                        visible: root.actionCount > 1
                        Layout.fillWidth: true
                        text: "Retry backend"
                        iconText: "󰑓"
                        leftAlign: true
                        foreground: root.foreground
                        fontFamily: root.fontFamily
                        hasCursor: root.selectedAction === 1
                        Accessible.role: Accessible.Button
                        Accessible.name: "Retry gamepad backend"
                        Accessible.onPressAction: if (root.service)
                            root.service.retry()
                        onHovered: function (hovered) {
                            if (hovered)
                                root.selectedAction = 1;
                        }
                        onClicked: if (root.service)
                            root.service.retry()
                    }
                }
            }
        }
    }
}
