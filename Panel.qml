import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

Item {
    id: root

    property var shell: null
    property var manifest: null
    property var service: null
    property bool opened: false
    property bool closingFromHost: false

    readonly property var controller: service ? service.selectedController : null
    readonly property string pluginId: manifest && manifest.id ? manifest.id : "lightqv.gamepads"

    function open(payloadJson) {
        var payload = {};
        var rawPayload = String(payloadJson || "{}");
        if (rawPayload.length <= 4096) {
            try {
                payload = JSON.parse(rawPayload) || {};
            } catch (error) {}
        }
        if (service && payload && !Array.isArray(payload) && typeof payload.controllerId === "string" && /^[1-9][0-9]{0,19}$/.test(payload.controllerId))
            service.selectController(payload.controllerId);
        closingFromHost = false;
        opened = true;
        detailsWindow.visible = true;
        Qt.callLater(function () {
            if (root.opened) {
                detailsWindow.requestActivate();
                keyCatcher.forceActiveFocus();
            }
        });
    }

    function close() {
        closingFromHost = true;
        opened = false;
        detailsWindow.visible = false;
        closingFromHost = false;
    }

    function requestClose() {
        if (shell && typeof shell.hide === "function")
            shell.hide(pluginId);
        else
            close();
    }

    FloatingWindow {
        id: detailsWindow
        visible: false
        title: "Omarchy Gamepads"
        color: Color.background
        implicitWidth: 560
        implicitHeight: 400
        minimumSize: Qt.size(420, 300)

        onVisibleChanged: {
            if (!visible && root.opened && !root.closingFromHost)
                root.requestClose();
        }

        FocusScope {
            anchors.fill: parent
            focus: true

            Ui.PanelKeyCatcher {
                id: keyCatcher
                anchors.fill: parent
                onMoveRequested: function (dx, dy) {
                    if (dx !== 0 && root.service)
                        root.service.cycleSelection(dx);
                }
                onActivateRequested: root.requestClose()
                onCloseRequested: root.requestClose()
                onTabRequested: closeButton.forceActiveFocus()

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Style.space(32)
                    spacing: Style.space(18)

                    Text {
                        text: "GAMEPAD DETAILS"
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.caption
                        font.bold: true
                        font.letterSpacing: 2
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Style.space(16)

                        Text {
                            text: "󰊴"
                            color: Color.foreground
                            font.family: Style.font.family
                            font.pixelSize: Style.font.display
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Style.space(4)

                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: root.controller ? root.controller.name : "No controller connected"
                                color: Color.foreground
                                font.family: Style.font.family
                                font.pixelSize: Style.font.title
                                font.bold: true
                                elide: Text.ElideRight
                            }

                            Text {
                                Layout.fillWidth: true
                                textFormat: Text.PlainText
                                text: root.controller ? Model.connectionLabel(root.controller) + "  ·  " + Model.batteryLabel(root.controller) : "Connect a supported controller to continue."
                                color: Color.muted
                                font.family: Style.font.family
                                font.pixelSize: Style.font.body
                            }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Style.spacing.hairline
                        color: Color.foreground
                        opacity: 0.12
                    }

                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: root.service ? root.service.connectedCount + (root.service.connectedCount === 1 ? " controller is connected." : " controllers are connected.") : "The shared gamepad service is unavailable."
                        color: Color.foreground
                        font.family: Style.font.family
                        font.pixelSize: Style.font.body
                        wrapMode: Text.Wrap
                    }

                    Text {
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: "Use Left and Right to change controllers. Input visualization and guided diagnostics will be added to this window next."
                        color: Color.muted
                        font.family: Style.font.family
                        font.pixelSize: Style.font.bodySmall
                        wrapMode: Text.Wrap
                    }

                    Item {
                        Layout.fillHeight: true
                    }

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            visible: root.service && root.service.connectedCount > 1
                            text: "←  " + (root.controller ? root.controller.id : "") + "  →"
                            color: Color.muted
                            font.family: Style.font.family
                            font.pixelSize: Style.font.bodySmall
                        }

                        Item {
                            Layout.fillWidth: true
                        }

                        Ui.Button {
                            id: closeButton
                            text: "Close"
                            iconText: "󰅖"
                            foreground: Color.foreground
                            fontFamily: Style.font.family
                            focusable: true
                            bordered: true
                            Accessible.role: Accessible.Button
                            Accessible.name: "Close gamepad details"
                            Accessible.onPressAction: root.requestClose()
                            onClicked: root.requestClose()
                        }
                    }
                }
            }
        }
    }
}
