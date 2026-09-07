import QtQuick
import qs.Commons
import qs.Ui as Ui

Ui.CursorSurface {
    id: root

    property var controller: null
    property string fontFamily: Style.font.family

    implicitHeight: visualContent.implicitHeight + Style.space(24)
    bordered: true

    Row {
        id: visualContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: Style.space(12)
        spacing: Style.space(14)

        Text {
            text: "󰊴"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display * 1.5
            anchors.verticalCenter: parent.verticalCenter
        }

        Column {
            width: parent.width - parent.children[0].width - parent.spacing
            spacing: Style.space(4)

            Text {
                width: parent.width
                text: "Switch Pro visual profile"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.title
                font.bold: true
            }

            Text {
                width: parent.width
                text: root.controller ? root.controller.capabilities.buttons.length + " buttons and " + root.controller.capabilities.axes.length + " axes mapped through the semantic profile." : "Semantic controller mapping ready."
                color: Qt.darker(root.foreground, 1.35)
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                wrapMode: Text.WordWrap
            }
        }
    }
}
