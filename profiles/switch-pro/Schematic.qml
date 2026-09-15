pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Shapes
import qs.Commons
import "Schematic.js" as Drawing

Item {
    id: root

    property var controller: null
    property var profile: null
    property var diagnosticState: ({ phase: "idle" })
    property bool active: true
    property color foreground: Color.foreground
    property color background: Color.background
    property color accent: Color.accent
    property color urgent: Color.urgent
    property color muted: Color.muted
    property color pressedColor: Style.pressedStateColor(foreground, accent, urgent)
    property string fontFamily: Style.font.family
    readonly property var projection: Drawing.project(active ? controller : null, profile, active ? diagnosticState : null)
    readonly property real drawingScale: Math.max(0, Math.min((width - 12) / 900, (height - legend.height - 12) / 480))
    readonly property color signalColor: pressedColor.a >= 0.95 && contrast(pressedColor, background) >= 3 ? pressedColor : foreground
    readonly property color signalText: contrast(background, signalColor) >= contrast(foreground, signalColor) ? background : foreground

    implicitWidth: 620
    implicitHeight: 350

    function luminance(color) {
        function channel(value) {
            return value <= 0.04045 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
        }
        return 0.2126 * channel(color.r) + 0.7152 * channel(color.g) + 0.0722 * channel(color.b);
    }

    function contrast(first, second) {
        var a = luminance(first);
        var b = luminance(second);
        return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
    }

    function tint(color, opacity) {
        return Qt.rgba(color.r, color.g, color.b, opacity);
    }

    function controlState(name) {
        return projection.controls[name] || ({ available: false, active: false, status: "" });
    }

    function warning(status) {
        return status === "warning" || status === "not_detected";
    }

    onAccentChanged: shellArt.requestPaint()
    onBackgroundChanged: shellArt.requestPaint()
    onVisibleChanged: if (visible) shellArt.requestPaint()

    component StatusMark: Text {
        property string status: ""
        visible: status === "passed" || root.warning(status)
        text: status === "passed" ? "✓" : "!"
        color: root.warning(status) ? root.urgent : root.accent
        font.family: root.fontFamily
        font.pixelSize: Math.max(18, 10 / Math.max(0.1, root.drawingScale))
        font.bold: true
    }

    component Control: Item {
        id: control
        required property var spec
        readonly property var inputState: root.controlState(spec.control)
        readonly property color outline: root.warning(inputState.status) ? root.urgent : root.accent
        readonly property color fill: inputState.active ? root.signalColor : root.background

        x: spec.x
        y: spec.y
        width: spec.w
        height: spec.h
        opacity: inputState.available ? 1 : 0.3
        objectName: spec.control
        Accessible.role: Accessible.Indicator
        Accessible.name: (root.profile && root.profile.labels ? root.profile.labels[spec.control] : spec.label)
            + (inputState.available ? (inputState.active ? ": pressed" : ": released") : ": unavailable")

        Rectangle {
            visible: !control.spec.path
            anchors.fill: parent
            radius: control.spec.round ? height / 2 : 3
            color: control.fill
            border.color: root.tint(control.outline, control.inputState.active ? 1 : 0.8)
            border.width: 2
        }

        Shape {
            visible: !!control.spec.path
            anchors.fill: parent
            ShapePath {
                fillColor: control.fill
                strokeColor: root.tint(control.outline, control.inputState.active ? 1 : 0.8)
                strokeWidth: 2
                PathSvg { path: control.spec.path || "" }
            }
        }

        Text {
            anchors.centerIn: parent
            text: control.spec.label
            color: control.inputState.active ? root.signalText : root.accent
            font.family: root.fontFamily
            font.pixelSize: Math.max(25, 10 / Math.max(0.1, root.drawingScale))
            font.bold: true
        }

        StatusMark {
            anchors.left: parent.right
            anchors.bottom: parent.top
            anchors.leftMargin: -5
            anchors.bottomMargin: -5
            status: control.inputState.status
        }
    }

    component Stick: Item {
        id: stick
        required property var spec
        readonly property var movement: root.projection.sticks[spec.control]
        readonly property var click: root.controlState(spec.control)

        x: spec.x - width / 2
        y: spec.y - height / 2
        width: 126
        height: 112
        objectName: spec.control
        Accessible.role: Accessible.Indicator
        Accessible.name: spec.label + (click.active ? ": pressed" : "")
            + ", X " + movement.x.toFixed(2) + ", Y " + movement.y.toFixed(2)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: root.background
            border.width: stick.movement.active ? 3 : 2
            border.color: root.warning(stick.movement.status) ? root.urgent
                : root.tint(root.accent, stick.movement.available ? (stick.movement.active ? 1 : 0.6) : 0.25)
        }

        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                x: index === 0 ? 4 : index === 1 ? parent.width - 13 : (parent.width - width) / 2
                y: index === 2 ? 4 : index === 3 ? parent.height - 12 : (parent.height - height) / 2
                width: index < 2 ? 9 : 2
                height: index < 2 ? 2 : 8
                color: root.tint(root.accent, 0.5)
            }
        }

        Rectangle {
            width: 82
            height: 72
            radius: height / 2
            x: (parent.width - width) / 2 + stick.movement.x * 17
            y: (parent.height - height) / 2 + stick.movement.y * 15 + (stick.click.active ? 2 : -2)
            color: stick.click.active ? root.signalColor : root.background
            border.color: root.warning(stick.click.status) ? root.urgent : root.accent
            border.width: 2
            opacity: stick.click.available || stick.movement.available ? 1 : 0.3

            Rectangle {
                anchors.fill: parent
                anchors.margins: 6
                radius: height / 2
                color: "transparent"
                border.color: root.tint(stick.click.active ? root.signalText : root.accent, 0.3)
                border.width: 1
            }

            Text {
                anchors.centerIn: parent
                text: stick.spec.label
                color: stick.click.active ? root.signalText : root.accent
                font.family: root.fontFamily
                font.pixelSize: Math.max(21, 10 / Math.max(0.1, root.drawingScale))
            }

            StatusMark {
                anchors.left: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: -3
                status: stick.click.status
            }
        }

        StatusMark {
            anchors.left: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: 5
            status: stick.movement.status
        }
    }

    Item {
        id: art
        width: 900
        height: 480
        scale: root.drawingScale
        transformOrigin: Item.TopLeft
        x: (root.width - width * scale) / 2
        y: (root.height - legend.height - height * scale) / 2

        // Static shell texture: redraw only for palette/visibility changes.
        // Live controls are separate scene-graph items above this cached canvas.
        Canvas {
            id: shellArt
            anchors.fill: parent
            contextType: "2d"

            function outline(ctx) {
                ctx.beginPath();
                ctx.moveTo(178, 97);
                ctx.bezierCurveTo(221, 86, 276, 86, 320, 92);
                ctx.bezierCurveTo(400, 94, 500, 94, 580, 92);
                ctx.bezierCurveTo(624, 86, 679, 86, 722, 97);
                ctx.bezierCurveTo(748, 104, 763, 124, 772, 153);
                ctx.lineTo(826, 350);
                ctx.bezierCurveTo(840, 395, 825, 438, 795, 449);
                ctx.bezierCurveTo(761, 459, 735, 431, 711, 396);
                ctx.lineTo(664, 339);
                ctx.bezierCurveTo(648, 321, 635, 337, 613, 347);
                ctx.bezierCurveTo(550, 371, 350, 371, 287, 347);
                ctx.bezierCurveTo(265, 337, 252, 321, 236, 339);
                ctx.lineTo(189, 396);
                ctx.bezierCurveTo(165, 431, 139, 459, 105, 449);
                ctx.bezierCurveTo(75, 438, 60, 395, 74, 350);
                ctx.lineTo(128, 153);
                ctx.bezierCurveTo(137, 124, 152, 104, 178, 97);
                ctx.closePath();
            }

            function dots(ctx, x0, y0, x1, y1, step, opacity) {
                ctx.fillStyle = root.tint(root.accent, opacity);
                for (var y = y0, row = 0; y < y1; y += step, row++) {
                    for (var x = x0 + (row % 2) * step / 2; x < x1; x += step)
                        ctx.fillRect(x, y, 2, 2);
                }
            }

            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                ctx.lineJoin = "round";
                ctx.lineWidth = 2;

                ctx.beginPath();
                ctx.moveTo(149, 118);
                ctx.lineTo(209, 44);
                ctx.bezierCurveTo(260, 35, 299, 35, 338, 48);
                ctx.lineTo(562, 48);
                ctx.bezierCurveTo(601, 35, 640, 35, 691, 44);
                ctx.lineTo(751, 118);
                ctx.closePath();
                ctx.fillStyle = root.background;
                ctx.fill();
                ctx.fillStyle = root.tint(root.accent, 0.12);
                ctx.fill();
                ctx.strokeStyle = root.tint(root.accent, 0.6);
                ctx.stroke();
                ctx.save();
                ctx.clip();
                dots(ctx, 140, 40, 760, 130, 8, 0.4);
                ctx.restore();

                outline(ctx);
                ctx.fillStyle = root.background;
                ctx.fill();
                ctx.fillStyle = root.tint(root.accent, 0.065);
                ctx.fill();
                ctx.strokeStyle = root.accent;
                ctx.lineWidth = 2.5;
                ctx.stroke();
                ctx.save();
                ctx.clip();
                dots(ctx, 74, 130, 827, 450, 11, 0.16);

                for (var side = 0; side < 2; side++) {
                    ctx.save();
                    if (side) { ctx.translate(900, 0); ctx.scale(-1, 1); }
                    ctx.beginPath();
                    ctx.moveTo(149, 212);
                    ctx.bezierCurveTo(166, 257, 209, 301, 256, 322);
                    ctx.lineTo(194, 431);
                    ctx.lineTo(84, 466);
                    ctx.lineTo(44, 350);
                    ctx.closePath();
                    ctx.strokeStyle = root.tint(root.accent, 0.45);
                    ctx.lineWidth = 1.5;
                    ctx.stroke();
                    ctx.clip();
                    dots(ctx, 55, 210, 260, 460, 6, 0.5);
                    ctx.restore();
                }
                ctx.restore();

                ctx.beginPath();
                ctx.moveTo(148, 139);
                ctx.bezierCurveTo(250, 119, 333, 120, 450, 124);
                ctx.bezierCurveTo(567, 120, 650, 119, 752, 139);
                ctx.strokeStyle = root.tint(root.accent, 0.55);
                ctx.lineWidth = 1.5;
                ctx.stroke();

                ctx.fillStyle = root.tint(root.accent, 0.5);
                ctx.fillRect(427, 69, 46, 3);
                ctx.fillRect(338, 291, 8, 8);
            }
        }

        Text {
            x: 409
            y: 203
            width: 82
            text: "PRO"
            color: root.tint(root.accent, 0.65)
            font.family: root.fontFamily
            font.pixelSize: 18
            font.letterSpacing: 6
            horizontalAlignment: Text.AlignHCenter
        }

        Repeater {
            model: Drawing.buttons
            delegate: Control { required property var modelData; spec: modelData }
        }

        Repeater {
            model: Drawing.sticks
            delegate: Stick { required property var modelData; spec: modelData }
        }
    }

    Text {
        id: legend
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        height: root.height >= 240 ? implicitHeight + 6 : 0
        visible: height > 0
        text: "● HELD   ✓ TESTED   ! WARNING"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
    }
}
