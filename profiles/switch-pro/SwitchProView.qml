import QtQuick
import qs.Commons
import qs.Ui as Ui

Ui.CursorSurface {
    id: root

    property var controller: null
    property var profile: null
    property var diagnosticState: ({ phase: "idle", results: ({}) })
    property string interactionMode: "overview"
    property bool renderActive: false
    property color background: Color.background
    property color urgent: Color.urgent
    property string fontFamily: Style.font.family
    readonly property bool sceneReady: sceneLoader.status === Loader.Ready && !!sceneLoader.item
    readonly property bool sceneUnavailable: sceneLoader.status === Loader.Error
    readonly property bool semanticBindingsValid: sceneReady && sceneLoader.item.semanticBindingsValid
    readonly property var implementedPartNames: sceneReady ? sceneLoader.item.implementedPartNames : []
    readonly property real cameraYaw: sceneReady ? sceneLoader.item.cameraYaw : 0
    readonly property real cameraPitch: sceneReady ? sceneLoader.item.cameraPitch : 0
    readonly property real cameraRoll: sceneReady ? sceneLoader.item.cameraRoll : 0
    readonly property real cameraDistance: sceneReady ? sceneLoader.item.cameraDistance : 8

    bordered: true
    foreground: Color.foreground

    function resetView() {
        if (sceneReady && typeof sceneLoader.item.resetView === "function")
            sceneLoader.item.resetView();
    }

    function handleCameraKey(text) {
        return sceneReady && typeof sceneLoader.item.handleCameraKey === "function"
            ? sceneLoader.item.handleCameraKey(text) : false;
    }

    Loader {
        id: sceneLoader
        anchors.fill: parent
        anchors.margins: Style.space(2)
        active: root.renderActive
        asynchronous: true
        source: Qt.resolvedUrl("SwitchProScene.qml")

        onLoaded: {
            if (!item)
                return;
            if ("controller" in item)
                item.controller = Qt.binding(function () { return root.controller; });
            if ("profile" in item)
                item.profile = Qt.binding(function () { return root.profile; });
            if ("diagnosticState" in item)
                item.diagnosticState = Qt.binding(function () { return root.diagnosticState; });
            if ("interactionMode" in item)
                item.interactionMode = Qt.binding(function () { return root.interactionMode; });
            if ("renderActive" in item)
                item.renderActive = Qt.binding(function () { return root.renderActive; });
            if ("foreground" in item)
                item.foreground = Qt.binding(function () { return root.foreground; });
            if ("background" in item)
                item.background = Qt.binding(function () { return root.background; });
            if ("accent" in item)
                item.accent = Qt.binding(function () { return root.accent; });
            if ("urgent" in item)
                item.urgent = Qt.binding(function () { return root.urgent; });
            if ("fontFamily" in item)
                item.fontFamily = Qt.binding(function () { return root.fontFamily; });
        }

        onStatusChanged: {
            if (status === Loader.Error)
                console.warn("Switch Pro 3D scene unavailable: load_failed");
        }
    }

    Column {
        visible: sceneLoader.status === Loader.Loading || sceneLoader.status === Loader.Null
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(48), Style.space(360))
        spacing: Style.space(8)

        Text {
            width: parent.width
            text: "Loading controller view..."
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }
    }

    Column {
        visible: root.sceneUnavailable
        anchors.centerIn: parent
        width: Math.min(parent.width - Style.space(48), Style.space(400))
        spacing: Style.space(8)

        Text {
            width: parent.width
            text: "3D visualization unavailable"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            width: parent.width
            text: "Confirm qt6-quick3d is installed, then restart the shell. If the view remains unavailable, check shell diagnostics. Vitals and diagnostics remain available."
            color: Color.muted
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
        }
    }

    Ui.Button {
        visible: root.sceneReady && root.interactionMode === "overview"
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: Style.space(12)
        text: "Reset view"
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        bordered: true
        onClicked: root.resetView()
    }
}
