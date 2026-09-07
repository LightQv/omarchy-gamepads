import QtQuick
import qs.Ui

BarWidget {
    id: root

    moduleName: "lightqv.gamepads"
    readonly property var service: bar?.shell?.serviceFor(moduleName)

    visible: false
}
