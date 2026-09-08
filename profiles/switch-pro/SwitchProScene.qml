pragma ComponentBehavior: Bound

import QtQuick
import QtQuick3D
import "../../VisualState.js" as Visual

Item {
    id: root

    property var controller: null
    property var profile: null
    property var diagnosticState: ({ phase: "idle", results: ({}) })
    property string interactionMode: "overview"
    property bool renderActive: false
    property color foreground: "#ffffff"
    property color background: "#111111"
    property color accent: "#7aa2f7"
    property color urgent: "#f7768e"
    property string fontFamily: "sans-serif"
    property real cameraYaw: 0
    property real cameraPitch: -8
    property real cameraRoll: 0
    property real cameraDistance: 8
    readonly property var projected: Visual.project(controller, profile, diagnosticState)
    readonly property var implementedParts: ({
        shell: shell,
        left_grip: left_grip,
        right_grip: right_grip,
        left_stick: left_stick,
        right_stick: right_stick,
        button_a: button_a,
        button_b: button_b,
        button_x: button_x,
        button_y: button_y,
        dpad_base: dpad_base,
        dpad_up: dpad_up,
        dpad_down: dpad_down,
        dpad_left: dpad_left,
        dpad_right: dpad_right,
        button_l: button_l,
        button_r: button_r,
        button_zl: button_zl,
        button_zr: button_zr,
        button_plus: button_plus,
        button_minus: button_minus,
        button_home: button_home,
        button_capture: button_capture,
        button_left_stick: button_left_stick,
        button_right_stick: button_right_stick
    })
    readonly property var implementedPartNames: Object.keys(implementedParts)
    readonly property bool semanticBindingsValid: validateSemanticBindings()
    readonly property real transitionDuration: profile && profile.animation ? profile.animation.transitionDurationMs : 80
    readonly property real digitalTravel: profile && profile.animation ? profile.animation.digitalTravel : 0.06
    readonly property real stickTilt: profile && profile.animation ? profile.animation.stickTiltDegrees : 14
    readonly property real liveLeftX: presentationAxis("leftx")
    readonly property real liveLeftY: presentationAxis("lefty")
    readonly property real liveRightX: presentationAxis("rightx")
    readonly property real liveRightY: presentationAxis("righty")
    readonly property real overviewYaw: interactionMode === "overview" ? liveLeftX * 22 : 0
    readonly property real overviewPitch: interactionMode === "overview" ? liveLeftY * 16 : 0
    readonly property real overviewRoll: interactionMode === "overview" ? liveRightX * 12 : 0
    readonly property real overviewDistance: interactionMode === "overview" ? liveRightY * 0.8 : 0

    function axisValue(name) {
        var value = Number(controller && controller.axes ? controller.axes[name] : 0);
        return isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0;
    }

    function presentationAxis(name) {
        var value = axisValue(name);
        var configured = Number(profile && profile.thresholds ? profile.thresholds.movementDetection : NaN);
        var deadZone = isFinite(configured) ? configured : 0.2;
        return Math.abs(value) >= deadZone ? value : 0;
    }

    function partState(name) {
        return projected.parts && projected.parts[name] ? projected.parts[name] : ({
            active: false, amount: 0, x: 0, y: 0, completed: false, status: ""
        });
    }

    function validateSemanticBindings() {
        if (!profile || !Array.isArray(profile.modelParts))
            return false;
        if (profile.modelParts.length !== implementedPartNames.length)
            return false;
        for (var i = 0; i < profile.modelParts.length; i++) {
            if (implementedPartNames.indexOf(profile.modelParts[i]) === -1)
                return false;
        }
        return true;
    }

    function resetView() {
        cameraYaw = 0;
        cameraPitch = -8;
        cameraRoll = 0;
        cameraDistance = 8;
    }

    function handleCameraKey(text) {
        var key = String(text || "").toLowerCase();
        if (key === "r") {
            resetView();
            return true;
        }
        if (interactionMode !== "overview")
            return false;
        if (key === "a") cameraYaw = Math.max(-70, cameraYaw - 6);
        else if (key === "d") cameraYaw = Math.min(70, cameraYaw + 6);
        else if (key === "w") cameraPitch = Math.max(-55, cameraPitch - 6);
        else if (key === "s") cameraPitch = Math.min(45, cameraPitch + 6);
        else if (key === "q") cameraRoll = Math.max(-35, cameraRoll - 6);
        else if (key === "e") cameraRoll = Math.min(35, cameraRoll + 6);
        else if (key === "+" || key === "=") cameraDistance = Math.max(6, cameraDistance - 0.35);
        else if (key === "-" || key === "_") cameraDistance = Math.min(11, cameraDistance + 0.35);
        else return false;
        return true;
    }

    component PrimitivePart: Node {
        id: partRoot
        property var partState: ({ active: false, amount: 0, completed: false, status: "" })
        property vector3d basePosition: Qt.vector3d(0, 0, 0)
        property vector3d partScale: Qt.vector3d(0.004, 0.004, 0.002)
        property color partColor: root.foreground
        property string shape: "#Cylinder"
        property bool movable: true

        position: Qt.vector3d(basePosition.x, basePosition.y,
            basePosition.z - (movable ? partState.amount * root.digitalTravel : 0))

        Behavior on position {
            Vector3dAnimation { duration: root.renderActive ? root.transitionDuration : 0 }
        }

        Model {
            source: partRoot.shape
            scale: partRoot.partScale
            materials: PrincipledMaterial {
                baseColor: partRoot.partState.status === "warning" || partRoot.partState.status === "not_detected"
                    ? root.urgent : (partRoot.partState.active || partRoot.partState.completed ? root.accent : partRoot.partColor)
                roughness: 0.42
                metalness: 0.05
                emissiveFactor: partRoot.partState.active || partRoot.partState.completed
                    ? Qt.vector3d(0.12, 0.12, 0.12) : Qt.vector3d(0, 0, 0)
            }
        }
    }

    View3D {
        anchors.fill: parent
        visible: root.renderActive
        renderMode: View3D.Offscreen
        camera: camera

        environment: SceneEnvironment {
            clearColor: root.background
            backgroundMode: SceneEnvironment.Color
            antialiasingMode: SceneEnvironment.MSAA
            antialiasingQuality: SceneEnvironment.Medium
        }

        PerspectiveCamera {
            id: camera
            position: Qt.vector3d(0, 0, root.cameraDistance + root.overviewDistance)
            clipNear: 0.1
            clipFar: 100
        }

        DirectionalLight {
            eulerRotation.x: -35
            eulerRotation.y: -25
            brightness: 1.1
            castsShadow: true
        }

        DirectionalLight {
            eulerRotation.x: 35
            eulerRotation.y: 155
            brightness: 0.55
        }

        Node {
            id: controllerRoot
            scale: Qt.vector3d(1.7, 1.7, 1.7)
            eulerRotation.x: root.interactionMode === "overview" ? root.cameraPitch + root.overviewPitch : -8
            eulerRotation.y: root.interactionMode === "overview" ? root.cameraYaw + root.overviewYaw : 0
            eulerRotation.z: root.interactionMode === "overview" ? root.cameraRoll + root.overviewRoll : 0

            Behavior on eulerRotation {
                Vector3dAnimation { duration: root.renderActive ? 90 : 0 }
            }

            Model {
                id: shell
                source: "#Sphere"
                scale: Qt.vector3d(0.035, 0.018, 0.007)
                materials: PrincipledMaterial { baseColor: "#414751"; roughness: 0.38 }
            }

            Model {
                id: left_grip
                source: "#Sphere"
                position: Qt.vector3d(-2.15, -0.75, -0.15)
                eulerRotation.z: -24
                scale: Qt.vector3d(0.012, 0.023, 0.009)
                materials: PrincipledMaterial { baseColor: "#252930"; roughness: 0.5 }
            }

            Model {
                id: right_grip
                source: "#Sphere"
                position: Qt.vector3d(2.15, -0.75, -0.15)
                eulerRotation.z: 24
                scale: Qt.vector3d(0.012, 0.023, 0.009)
                materials: PrincipledMaterial { baseColor: "#252930"; roughness: 0.5 }
            }

            Node {
                id: left_stick
                position: Qt.vector3d(-1.15, -0.15, 0.78)
                eulerRotation.x: root.interactionMode === "overview" ? 0 : root.partState("left_stick").y * root.stickTilt
                eulerRotation.y: root.interactionMode === "overview" ? 0 : -root.partState("left_stick").x * root.stickTilt

                Node {
                    id: button_left_stick
                    position.z: -root.partState("button_left_stick").amount * root.digitalTravel

                    Model {
                        source: "#Cylinder"
                        eulerRotation.x: 90
                        scale: Qt.vector3d(0.0048, 0.0048, 0.0018)
                        materials: PrincipledMaterial {
                            baseColor: root.partState("left_stick").active || root.partState("button_left_stick").active
                                ? root.accent : "#16191e"
                            roughness: 0.72
                        }
                    }
                }
            }

            Node {
                id: right_stick
                position: Qt.vector3d(0.95, -0.62, 0.78)
                eulerRotation.x: root.interactionMode === "overview" ? 0 : root.partState("right_stick").y * root.stickTilt
                eulerRotation.y: root.interactionMode === "overview" ? 0 : -root.partState("right_stick").x * root.stickTilt

                Node {
                    id: button_right_stick
                    position.z: -root.partState("button_right_stick").amount * root.digitalTravel

                    Model {
                        source: "#Cylinder"
                        eulerRotation.x: 90
                        scale: Qt.vector3d(0.0048, 0.0048, 0.0018)
                        materials: PrincipledMaterial {
                            baseColor: root.partState("right_stick").active || root.partState("button_right_stick").active
                                ? root.accent : "#16191e"
                            roughness: 0.72
                        }
                    }
                }
            }

            Model {
                id: dpad_base
                source: "#Cylinder"
                position: Qt.vector3d(-1.8, 0.48, 0.72)
                eulerRotation.x: 90
                scale: Qt.vector3d(0.0065, 0.0065, 0.0012)
                materials: PrincipledMaterial { baseColor: "#171a20"; roughness: 0.65 }
            }

            PrimitivePart { id: dpad_up; basePosition: Qt.vector3d(-1.8, 0.82, 0.83); partScale: Qt.vector3d(0.0021, 0.003, 0.001); shape: "#Cube"; partState: root.partState("dpad_up"); partColor: "#15181d" }
            PrimitivePart { id: dpad_down; basePosition: Qt.vector3d(-1.8, 0.14, 0.83); partScale: Qt.vector3d(0.0021, 0.003, 0.001); shape: "#Cube"; partState: root.partState("dpad_down"); partColor: "#15181d" }
            PrimitivePart { id: dpad_left; basePosition: Qt.vector3d(-2.14, 0.48, 0.83); partScale: Qt.vector3d(0.003, 0.0021, 0.001); shape: "#Cube"; partState: root.partState("dpad_left"); partColor: "#15181d" }
            PrimitivePart { id: dpad_right; basePosition: Qt.vector3d(-1.46, 0.48, 0.83); partScale: Qt.vector3d(0.003, 0.0021, 0.001); shape: "#Cube"; partState: root.partState("dpad_right"); partColor: "#15181d" }

            PrimitivePart { id: button_a; basePosition: Qt.vector3d(1.85, 0.5, 0.82); partState: root.partState("button_a"); partColor: "#252a31" }
            PrimitivePart { id: button_b; basePosition: Qt.vector3d(1.5, 0.15, 0.82); partState: root.partState("button_b"); partColor: "#252a31" }
            PrimitivePart { id: button_x; basePosition: Qt.vector3d(1.5, 0.85, 0.82); partState: root.partState("button_x"); partColor: "#252a31" }
            PrimitivePart { id: button_y; basePosition: Qt.vector3d(1.15, 0.5, 0.82); partState: root.partState("button_y"); partColor: "#252a31" }

            PrimitivePart { id: button_minus; basePosition: Qt.vector3d(-0.52, 0.72, 0.78); partScale: Qt.vector3d(0.0026, 0.001, 0.0008); shape: "#Cube"; partState: root.partState("button_minus"); partColor: "#181b20" }
            PrimitivePart { id: button_plus; basePosition: Qt.vector3d(0.52, 0.72, 0.78); partScale: Qt.vector3d(0.0026, 0.001, 0.0008); shape: "#Cube"; partState: root.partState("button_plus"); partColor: "#181b20" }
            PrimitivePart { id: button_home; basePosition: Qt.vector3d(0.47, -0.02, 0.8); partScale: Qt.vector3d(0.003, 0.003, 0.001); partState: root.partState("button_home"); partColor: "#20242b" }
            PrimitivePart { id: button_capture; basePosition: Qt.vector3d(-0.48, -0.05, 0.8); partScale: Qt.vector3d(0.0028, 0.0028, 0.001); shape: "#Cube"; partState: root.partState("button_capture"); partColor: "#20242b" }

            PrimitivePart { id: button_l; basePosition: Qt.vector3d(-1.8, 1.08, 0.12); partScale: Qt.vector3d(0.009, 0.0028, 0.004); shape: "#Cube"; partState: root.partState("button_l"); partColor: "#22262d" }
            PrimitivePart { id: button_r; basePosition: Qt.vector3d(1.8, 1.08, 0.12); partScale: Qt.vector3d(0.009, 0.0028, 0.004); shape: "#Cube"; partState: root.partState("button_r"); partColor: "#22262d" }
            PrimitivePart { id: button_zl; basePosition: Qt.vector3d(-1.62, 1.03, -0.35); partScale: Qt.vector3d(0.008, 0.0035, 0.004); shape: "#Cube"; partState: root.partState("button_zl"); partColor: "#1b1e24" }
            PrimitivePart { id: button_zr; basePosition: Qt.vector3d(1.62, 1.03, -0.35); partScale: Qt.vector3d(0.008, 0.0035, 0.004); shape: "#Cube"; partState: root.partState("button_zr"); partColor: "#1b1e24" }
        }
    }

    MouseArea {
        anchors.fill: parent
        enabled: root.renderActive && root.interactionMode === "overview"
        acceptedButtons: Qt.LeftButton
        property real previousX: 0
        property real previousY: 0

        onPressed: function (mouse) {
            previousX = mouse.x;
            previousY = mouse.y;
        }
        onPositionChanged: function (mouse) {
            if (!(mouse.buttons & Qt.LeftButton))
                return;
            root.cameraYaw = Math.max(-70, Math.min(70, root.cameraYaw + (mouse.x - previousX) * 0.35));
            root.cameraPitch = Math.max(-55, Math.min(45, root.cameraPitch + (mouse.y - previousY) * 0.35));
            previousX = mouse.x;
            previousY = mouse.y;
        }
        onWheel: function (wheel) {
            root.cameraDistance = Math.max(6, Math.min(11, root.cameraDistance - wheel.angleDelta.y / 480));
            wheel.accepted = true;
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        height: controls.implicitHeight + 12
        radius: 6
        color: Qt.rgba(root.background.r, root.background.g, root.background.b, 0.82)

        Text {
            id: controls
            anchors.centerIn: parent
            width: parent.width - 20
            text: root.interactionMode === "overview"
                ? "Drag or use WASD to orbit  ·  Q/E roll  ·  +/- zoom  ·  R reset"
                : (root.interactionMode === "review"
                    ? "Diagnostic review  ·  " + String(root.diagnosticState.status || "incomplete").replace(/_/g, " ")
                    : "Controller input animates mapped controls")
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: 12
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }
}
