import QtQuick

Item {
    property var shell: null
    property var manifest: null
    property var service: null
    property bool opened: false

    function open(payloadJson) {
        opened = true
    }

    function close() {
        opened = false
    }
}
