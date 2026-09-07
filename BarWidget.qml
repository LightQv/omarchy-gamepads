import QtQuick
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

    Ui.WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: {
            var count = root.service ? root.service.connectedCount : 0;
            return count > 1 ? "󰊴 " + count : "󰊴";
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
            return root.service.connectedCount === 1 ? "1 gamepad connected" : root.service.connectedCount + " gamepads connected";
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
