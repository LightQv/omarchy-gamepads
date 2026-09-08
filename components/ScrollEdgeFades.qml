import QtQuick
import qs.Commons

Item {
    id: root

    property var flickable: null
    property int orientation: Qt.Vertical
    property color background: Color.background
    property real fadeExtent: Style.space(28)

    readonly property bool horizontal: orientation === Qt.Horizontal
    readonly property real startExtent: horizontal
        ? Math.min(fadeExtent, width / 2) : Math.min(fadeExtent, height / 2)
    readonly property real endExtent: startExtent
    readonly property bool overflows: !!flickable && (horizontal
        ? flickable.contentWidth > flickable.width : flickable.contentHeight > flickable.height)
    readonly property real startRemaining: !flickable ? 0 : (horizontal
        ? flickable.contentX - flickable.originX : flickable.contentY - flickable.originY)
    readonly property real endRemaining: !flickable ? 0 : (horizontal
        ? flickable.originX + flickable.contentWidth - flickable.width - flickable.contentX
        : flickable.originY + flickable.contentHeight - flickable.height - flickable.contentY)
    readonly property real startOpacity: overflows && startExtent > 0
        ? Math.max(0, Math.min(1, startRemaining / startExtent)) : 0
    readonly property real endOpacity: overflows && endExtent > 0
        ? Math.max(0, Math.min(1, endRemaining / endExtent)) : 0

    z: 1

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: root.startExtent
        visible: !root.horizontal && opacity > 0
        opacity: root.startOpacity
        gradient: Gradient {
            GradientStop { position: 0; color: root.background }
            GradientStop { position: 1; color: Util.alpha(root.background, 0) }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: root.endExtent
        visible: !root.horizontal && opacity > 0
        opacity: root.endOpacity
        gradient: Gradient {
            GradientStop { position: 0; color: Util.alpha(root.background, 0) }
            GradientStop { position: 1; color: root.background }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        width: root.startExtent
        visible: root.horizontal && opacity > 0
        opacity: root.startOpacity
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: root.background }
            GradientStop { position: 1; color: Util.alpha(root.background, 0) }
        }
    }

    Rectangle {
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.right: parent.right
        width: root.endExtent
        visible: root.horizontal && opacity > 0
        opacity: root.endOpacity
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop { position: 0; color: Util.alpha(root.background, 0) }
            GradientStop { position: 1; color: root.background }
        }
    }
}
