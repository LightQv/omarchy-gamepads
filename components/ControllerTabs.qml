pragma ComponentBehavior: Bound

import QtQuick
import qs.Commons
import qs.Ui as Ui

Item {
    id: root

    property var controllers: []
    property string selectedId: ""
    property color foreground: Color.foreground
    property color background: Color.background
    property string fontFamily: Style.font.family
    readonly property bool tabsFocused: tabGroup.activeFocus
    readonly property int tabCount: controllers.length

    signal selected(string controllerId)

    function buildOptions() {
        var totals = Object.create(null);
        var positions = Object.create(null);
        var options = [];
        for (var i = 0; i < controllers.length; i++) {
            var name = String(controllers[i].name || "Gamepad");
            totals[name] = (totals[name] || 0) + 1;
        }
        for (var j = 0; j < controllers.length; j++) {
            var controller = controllers[j];
            var controllerName = String(controller.name || "Gamepad");
            positions[controllerName] = (positions[controllerName] || 0) + 1;
            options.push({
                value: String(controller.id),
                label: totals[controllerName] > 1 ? controllerName + " " + positions[controllerName] : controllerName,
                icon: "󰊴",
                tooltip: controllerName
            });
        }
        return options;
    }

    function focusTabs() {
        tabGroup.forceActiveFocus();
    }

    function revealSelected() {
        Qt.callLater(function () {
            for (var i = 0; i < tabGroup.children.length; i++) {
                var child = tabGroup.children[i];
                if (child.selected !== true)
                    continue;
                if (child.x < viewport.contentX)
                    viewport.contentX = child.x;
                else if (child.x + child.width > viewport.contentX + viewport.width)
                    viewport.contentX = child.x + child.width - viewport.width;
                return;
            }
        });
    }

    onSelectedIdChanged: revealSelected()
    onControllersChanged: revealSelected()

    implicitHeight: tabGroup.implicitHeight

    Flickable {
        id: viewport
        anchors.fill: parent
        contentWidth: tabGroup.implicitWidth
        contentHeight: height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Ui.ButtonGroup {
            id: tabGroup
            options: root.buildOptions()
            value: root.selectedId
            foreground: root.foreground
            background: root.background
            fontFamily: root.fontFamily
            onChanged: function (value) {
                root.selected(value);
            }
        }
    }
}
