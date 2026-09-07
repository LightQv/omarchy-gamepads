pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui as Ui
import "Model.js" as Model

Ui.BarWidget {
    id: root

    moduleName: "lightqv.gamepads"
    readonly property var service: bar && bar.shell ? bar.shell.serviceFor(moduleName) : null
    readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

    function open() {
        if (panelLoader.item)
            panelLoader.item.open();
    }

    function close() {
        if (panelLoader.item)
            panelLoader.item.close();
    }

    function togglePanel() {
        if (panelLoader.item)
            panelLoader.item.toggle();
    }

    function closeForPopoutSwitch() {
        if (panelLoader.item)
            panelLoader.item.closeForPopoutSwitch();
    }

    function injectPanel() {
        var target = panelLoader.item;
        if (!target)
            return;
        target.bar = root.bar;
        target.settings = root.settings;
        target.anchorItem = button;
        target.hostWidget = root;
        target.service = root.service;
    }

    implicitWidth: button.implicitWidth
    implicitHeight: button.implicitHeight

    onBarChanged: injectPanel()
    onSettingsChanged: injectPanel()
    onServiceChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("CompactPanel.qml")
        visible: false
        onLoaded: {
            root.injectPanel();
            Qt.callLater(root.injectPanel);
        }
    }

    Ui.BarIconButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        iconComponent: Component {
            Item {
                Ui.OpticalGlyph {
                    anchors.fill: parent
                    text: "󰊴"
                    fontFamily: button.fontFamily
                    fontSize: button.fontSize
                    color: button.active && button.useActiveColor ? button.activeColor : button.foreground
                }

                Ui.BorderSurface {
                    id: countBadge
                    visible: root.service && root.service.connectedCount > 1
                    width: Math.max(height, badgeLabel.implicitWidth + Style.space(3))
                    height: Math.max(Style.space(8), Math.round(button.fontSize * 0.58))
                    radius: height / 2
                    color: button.foreground
                    borderSpec: Border.flat(Color.popups.background, 1)
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom

                    Text {
                        id: badgeLabel
                        anchors.centerIn: parent
                        text: root.service && root.service.connectedCount > 9 ? "9+" : String(root.service ? root.service.connectedCount : 0)
                        color: Color.background
                        font.family: button.fontFamily
                        font.pixelSize: Math.max(6, Math.round(parent.height * 0.62))
                        font.bold: true
                        renderType: Text.NativeRendering
                    }
                }
            }
        }
        tooltipText: {
            if (!root.service)
                return "Gamepads service unavailable";
            if (root.service.dependencyMissing)
                return "Gamepad dependency missing";
            if (root.service.health === "error")
                return "Gamepad backend error";
            if (root.service.connectedCount === 0)
                return "No gamepads connected";
            if (root.service.connectedCount === 1)
                return root.service.selectedController ? root.service.selectedController.name + " connected" : "Gamepad connected";
            return root.service.connectedCount + " gamepads connected";
        }
        keepSpace: true
        dimmed: !root.service || root.service.connectedCount === 0
        active: root.service && (root.service.dependencyMissing || root.service.backendWarning || root.service.health === "error" || Model.batteryIsLow(root.service.selectedController))
        Accessible.role: Accessible.Button
        Accessible.name: tooltipText
        Accessible.onPressAction: root.togglePanel()
        onPressed: function (button) {
            if (button === Qt.LeftButton)
                root.togglePanel();
        }
    }
}
