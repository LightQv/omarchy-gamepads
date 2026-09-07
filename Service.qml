import QtQuick
import Quickshell.Io
import "Model.js" as Model

// Tooling cannot resolve Quickshell's QProcess::ExitStatus signal parameter.
// qmllint disable signal-handler-parameters

QtObject {
    id: root

    property var shell: null
    property var manifest: null

    property var modelState: Model.initialState()
    property string health: "starting"
    property string supervisorError: ""
    property string stderrDiagnostic: ""
    property string protocolError: ""
    property int malformedMessages: 0
    property int acceptedMessages: 0
    property int restartAttempt: 0
    property var restartHistory: []
    property bool expectedStop: false
    property bool permanentFailure: false
    property bool startupTimedOut: false
    property bool acceptingOutput: false
    property var streamingRequests: ({})
    property var controllerTabs: []
    property string lastStreamingIdsKey: ""
    property bool lastStreamingEnabled: false
    property bool streamingStateSent: false
    property int messagesThisWindow: 0
    property int chunksThisWindow: 0
    property int bytesThisWindow: 0
    property int stderrBytesThisWindow: 0
    property double lastMessageMs: 0
    property string stdoutBuffer: ""
    property int stdoutBufferBytes: 0
    property bool processExited: false
    property int pendingExitCode: 0

    readonly property var controllers: modelState.controllers
    readonly property int connectedCount: controllers.length
    readonly property string selectedId: modelState.selectedId
    readonly property var selectedController: Model.selectedController(modelState)
    readonly property string backendVersion: modelState.backendVersion
    readonly property string lastErrorCode: supervisorError !== "" ? "supervisor_error" : modelState.lastErrorCode !== "" ? modelState.lastErrorCode : stderrDiagnostic !== "" ? "helper_diagnostic" : ""
    readonly property string lastErrorMessage: supervisorError !== "" ? supervisorError : modelState.lastErrorMessage !== "" ? modelState.lastErrorMessage : stderrDiagnostic
    readonly property bool ready: health === "ready"
    readonly property bool dependencyMissing: health === "dependency-error"
    readonly property bool backendWarning: ready && lastErrorCode !== ""
    readonly property var helperCommand: {
        if (!manifest)
            return [];
        var sourceDir = String(manifest.__sourceDir || "");
        if (sourceDir === "")
            return [];
        return ["/usr/bin/python3", "-E", "-s", sourceDir + "/scripts/gamepad-helper.py"];
    }

    function start() {
        if (helper.running || restartTimer.running || permanentFailure)
            return;
        if (helperCommand.length === 0) {
            health = "error";
            supervisorError = "Plugin source directory is unavailable.";
            return;
        }
        expectedStop = false;
        startupTimedOut = false;
        supervisorError = "";
        stderrDiagnostic = "";
        protocolError = "";
        malformedMessages = 0;
        acceptedMessages = 0;
        messagesThisWindow = 0;
        chunksThisWindow = 0;
        bytesThisWindow = 0;
        stderrBytesThisWindow = 0;
        lastMessageMs = Date.now();
        stdoutBuffer = "";
        stdoutBufferBytes = 0;
        processExited = false;
        modelState = Model.initialState();
        controllerTabs = [];
        streamingStateSent = false;
        lastStreamingIdsKey = "";
        lastStreamingEnabled = false;
        health = "starting";
        helper.command = helperCommand;
        acceptingOutput = true;
        startupTimer.restart();
        helper.running = true;
    }

    function stop() {
        restartTimer.stop();
        startupTimer.stop();
        stableTimer.stop();
        expectedStop = true;
        acceptingOutput = false;
        if (!helper.running) {
            health = "stopped";
            return;
        }
        helper.write(JSON.stringify({
            command: "shutdown"
        }) + "\n");
        shutdownTimer.restart();
    }

    function retry() {
        permanentFailure = false;
        restartAttempt = 0;
        restartHistory = [];
        supervisorError = "";
        if (helper.running) {
            expectedStop = false;
            startupTimedOut = true;
            acceptingOutput = false;
            helper.running = false;
            return;
        }
        restartTimer.stop();
        start();
    }

    function scheduleRestart(reason) {
        modelState = Model.initialState();
        controllerTabs = [];
        if (permanentFailure || expectedStop)
            return;
        var now = Date.now();
        var recent = restartHistory.filter(function (timestamp) {
            return now - timestamp < 3600000;
        });
        if (recent.length >= 10) {
            permanentFailure = true;
            health = "error";
            supervisorError = "Controller helper exceeded its hourly restart limit. Retry from the panel.";
            restartHistory = recent;
            return;
        }
        recent.push(now);
        restartHistory = recent;
        if (restartAttempt >= 6) {
            health = "error";
            supervisorError = "Controller helper stopped repeatedly. Retry from the panel.";
            return;
        }
        var delay = Math.min(30000, 1000 * Math.pow(2, restartAttempt));
        restartAttempt++;
        health = "restarting";
        supervisorError = reason || "Controller helper stopped unexpectedly.";
        restartTimer.interval = delay;
        restartTimer.restart();
    }

    function handleLine(rawLine) {
        if (!acceptingOutput)
            return;
        var line = String(rawLine || "");
        if (line.endsWith("\r"))
            line = line.slice(0, -1);
        if (line.length === 0)
            return;
        messagesThisWindow++;
        var lineBytes = utf8Length(line);
        bytesThisWindow += lineBytes;
        if (messagesThisWindow > 4096 || bytesThisWindow > 2097152) {
            quarantineHelper("Controller helper exceeded its output budget.");
            return;
        }
        if (lineBytes > 65536) {
            rejectProtocolMessage("Backend message exceeds 64 KiB.");
            return;
        }
        var message;
        try {
            message = JSON.parse(line);
        } catch (error) {
            rejectProtocolMessage("Backend emitted invalid JSON.");
            return;
        }
        var result = Model.reduceMessage(modelState, message);
        if (!result.accepted) {
            rejectProtocolMessage("Backend message rejected: " + result.error + ".");
            return;
        }
        modelState = result.state;
        if (message.type === "snapshot" || message.type === "controller" || message.type === "removed")
            refreshControllerTabs();
        acceptedMessages++;
        lastMessageMs = Date.now();
        protocolError = "";
        if (message.type === "hello")
            startupTimer.restart();
        if (message.type === "snapshot") {
            startupTimer.stop();
            health = "ready";
            stableTimer.restart();
            syncStreaming();
        } else if (message.type === "controller" || message.type === "removed") {
            syncStreaming();
        } else if (message.type === "error" && message.code === "dependency_missing") {
            startupTimer.stop();
            stableTimer.stop();
            permanentFailure = true;
            health = "dependency-error";
        }
    }

    function handleChunk(rawChunk) {
        if (!acceptingOutput)
            return;
        var chunk = String(rawChunk || "");
        chunksThisWindow++;
        if (chunksThisWindow > 4096) {
            quarantineHelper("Controller helper exceeded its output callback budget.");
            return;
        }
        stdoutBufferBytes += utf8Length(chunk);
        if (stdoutBufferBytes > 262144) {
            quarantineHelper("Controller helper exceeded its pending output budget.");
            return;
        }
        stdoutBuffer += chunk;
        if (stdoutBuffer.indexOf("\n") === -1 && stdoutBufferBytes > 65536) {
            quarantineHelper("Controller helper emitted an oversized partial message.");
            return;
        }
        if (!drainTimer.running)
            drainTimer.start();
    }

    function drainOutput() {
        if (!acceptingOutput)
            return;
        var handled = 0;
        var handledBytes = 0;
        var newline = stdoutBuffer.indexOf("\n");
        while (newline !== -1 && handled < 32 && handledBytes < 131072) {
            var line = stdoutBuffer.slice(0, newline);
            var lineBytes = utf8Length(line);
            stdoutBuffer = stdoutBuffer.slice(newline + 1);
            stdoutBufferBytes = Math.max(0, stdoutBufferBytes - lineBytes - 1);
            handled++;
            handledBytes += lineBytes + 1;
            handleLine(line);
            if (!acceptingOutput)
                return;
            newline = stdoutBuffer.indexOf("\n");
        }
        if (newline !== -1) {
            drainTimer.restart();
            return;
        }
        if (stdoutBufferBytes > 65536) {
            quarantineHelper("Controller helper emitted an oversized partial message.");
            return;
        }
        if (processExited) {
            if (stdoutBufferBytes > 0)
                protocolError = "Backend ended with an incomplete message.";
            finalizeExit();
        }
    }

    function handleStderrChunk(rawChunk) {
        if (!acceptingOutput)
            return;
        var chunk = String(rawChunk || "");
        stderrBytesThisWindow += utf8Length(chunk);
        if (stderrBytesThisWindow > 262144) {
            quarantineHelper("Controller helper exceeded its diagnostic output budget.");
            return;
        }
        if (chunk.trim() !== "")
            stderrDiagnostic = "Controller helper reported a diagnostic.";
    }

    function utf8Length(value) {
        var text = String(value || "");
        var bytes = 0;
        for (var i = 0; i < text.length; i++) {
            var code = text.charCodeAt(i);
            if (code <= 0x7f)
                bytes++;
            else if (code <= 0x7ff)
                bytes += 2;
            else if (code >= 0xd800 && code <= 0xdbff && i + 1 < text.length && text.charCodeAt(i + 1) >= 0xdc00 && text.charCodeAt(i + 1) <= 0xdfff) {
                bytes += 4;
                i++;
            } else
                bytes += 3;
        }
        return bytes;
    }

    function finalizeExit() {
        acceptingOutput = false;
        stdoutBuffer = "";
        stdoutBufferBytes = 0;
        processExited = false;
        if (expectedStop) {
            modelState = Model.initialState();
            controllerTabs = [];
            health = "stopped";
            return;
        }
        if (permanentFailure)
            return;
        var reason = startupTimedOut ? supervisorError : !modelState.snapshotAccepted && modelState.lastErrorMessage !== "" ? modelState.lastErrorMessage : "Controller helper exited with status " + pendingExitCode + ".";
        startupTimedOut = false;
        scheduleRestart(reason);
    }

    function rejectProtocolMessage(reason) {
        malformedMessages++;
        protocolError = reason;
        if (malformedMessages < 10 || !helper.running)
            return;
        startupTimedOut = true;
        acceptingOutput = false;
        supervisorError = "Controller helper emitted too many invalid messages.";
        helper.running = false;
    }

    function quarantineHelper(reason) {
        if (!helper.running)
            return;
        startupTimedOut = true;
        acceptingOutput = false;
        supervisorError = reason;
        helper.running = false;
    }

    function selectController(id) {
        modelState = Model.selectController(modelState, String(id || ""));
    }

    function refreshControllerTabs() {
        var tabs = [];
        for (var i = 0; i < controllers.length; i++) {
            tabs.push({
                id: controllers[i].id,
                name: controllers[i].name,
                family: controllers[i].family,
                sdlType: controllers[i].sdlType
            });
        }
        if (JSON.stringify(tabs) !== JSON.stringify(controllerTabs))
            controllerTabs = tabs;
    }

    function cycleSelection(delta) {
        modelState = Model.cycleSelection(modelState, Number(delta));
        syncStreaming();
    }

    function setStreamingRequest(consumer, ids) {
        var key = String(consumer || "");
        if (!/^[a-z0-9][a-z0-9_.-]{0,63}$/.test(key))
            return false;
        var requests = Object.create(null);
        var existingKeys = Object.keys(streamingRequests);
        for (var e = 0; e < existingKeys.length; e++)
            requests[existingKeys[e]] = streamingRequests[existingKeys[e]];
        if (ids === null || ids === undefined) {
            delete requests[key];
        } else {
            if (!Array.isArray(ids) || ids.length > 32 || (!Model.hasOwn(requests, key) && existingKeys.length >= 16))
                return false;
            var boundedIds = [];
            var seen = Object.create(null);
            for (var i = 0; i < ids.length; i++) {
                var id = String(ids[i]);
                if (!/^[1-9][0-9]{0,19}$/.test(id))
                    return false;
                var connected = false;
                for (var controllerIndex = 0; controllerIndex < controllers.length; controllerIndex++) {
                    if (controllers[controllerIndex].id === id) {
                        connected = true;
                        break;
                    }
                }
                if (!connected)
                    return false;
                if (!Model.hasOwn(seen, id)) {
                    seen[id] = true;
                    boundedIds.push(id);
                }
            }
            requests[key] = boundedIds;
        }
        streamingRequests = requests;
        syncStreaming();
        return true;
    }

    function syncStreaming() {
        if (!helper.running || !modelState.helloAccepted || !modelState.snapshotAccepted)
            return;
        var ids = [];
        var seen = Object.create(null);
        var consumers = Object.keys(streamingRequests);
        for (var c = 0; c < consumers.length; c++) {
            var consumer = consumers[c];
            var consumerIds = streamingRequests[consumer];
            if (consumerIds.length === 0) {
                for (var i = 0; i < controllers.length; i++) {
                    if (!Model.hasOwn(seen, controllers[i].id)) {
                        seen[controllers[i].id] = true;
                        ids.push(controllers[i].id);
                    }
                }
            } else {
                for (var j = 0; j < consumerIds.length; j++) {
                    var id = String(consumerIds[j]);
                    var connected = false;
                    for (var k = 0; k < controllers.length; k++) {
                        if (controllers[k].id === id) {
                            connected = true;
                            break;
                        }
                    }
                    if (!Model.hasOwn(seen, id) && connected) {
                        seen[id] = true;
                        ids.push(id);
                    }
                }
            }
        }
        var enabled = ids.length > 0;
        var idsKey = ids.join(",");
        if (streamingStateSent && idsKey === lastStreamingIdsKey && enabled === lastStreamingEnabled)
            return;
        helper.write(JSON.stringify({
            command: "subscribe",
            ids: ids
        }) + "\n");
        helper.write(JSON.stringify({
            command: "setStreaming",
            enabled: enabled
        }) + "\n");
        lastStreamingIdsKey = idsKey;
        lastStreamingEnabled = enabled;
        streamingStateSent = true;
    }

    onManifestChanged: launchTimer.restart()
    Component.onCompleted: launchTimer.restart()
    Component.onDestruction: {
        expectedStop = true;
        acceptingOutput = false;
        restartTimer.stop();
        startupTimer.stop();
        stableTimer.stop();
        shutdownTimer.stop();
        livenessTimer.stop();
        trafficTimer.stop();
        drainTimer.stop();
        if (helper.running)
            helper.running = false;
    }

    property Timer launchTimer: Timer {
        interval: 0
        onTriggered: root.start()
    }

    property Timer startupTimer: Timer {
        interval: 5000
        onTriggered: {
            if (root.ready || root.dependencyMissing)
                return;
            root.startupTimedOut = true;
            root.acceptingOutput = false;
            root.supervisorError = "Controller helper did not complete startup.";
            if (root.helper.running) {
                root.helper.running = false;
            } else {
                root.startupTimedOut = false;
                root.scheduleRestart(root.supervisorError);
            }
        }
    }

    property Timer stableTimer: Timer {
        interval: 30000
        onTriggered: root.restartAttempt = 0
    }

    property Timer trafficTimer: Timer {
        interval: 1000
        repeat: true
        running: true
        onTriggered: {
            root.messagesThisWindow = 0;
            root.chunksThisWindow = 0;
            root.bytesThisWindow = 0;
            root.stderrBytesThisWindow = 0;
        }
    }

    property Timer livenessTimer: Timer {
        interval: 15000
        repeat: true
        running: true
        onTriggered: {
            if (!root.ready || !root.helper.running)
                return;
            var silentFor = Date.now() - root.lastMessageMs;
            if (silentFor > 60000) {
                root.quarantineHelper("Controller helper stopped responding.");
            } else if (silentFor > 20000) {
                root.helper.write(JSON.stringify({
                    command: "snapshot"
                }) + "\n");
            }
        }
    }

    property Timer restartTimer: Timer {
        onTriggered: root.start()
    }

    property Timer shutdownTimer: Timer {
        interval: 1500
        onTriggered: if (root.helper.running)
            root.helper.running = false
    }

    property Timer drainTimer: Timer {
        interval: 0
        onTriggered: root.drainOutput()
    }

    property Process helper: Process {
        stdinEnabled: true

        stdout: SplitParser {
            // Empty mode forwards arbitrary read chunks without retaining an
            // unbounded partial line inside Quickshell's delimiter parser.
            splitMarker: ""
            onRead: function (chunk) {
                root.handleChunk(chunk);
            }
        }

        stderr: SplitParser {
            splitMarker: ""
            onRead: function (chunk) {
                root.handleStderrChunk(chunk);
            }
        }

        onStarted: {
            root.acceptingOutput = true;
            root.health = "starting";
        }

        onExited: function (exitCode) {
            root.startupTimer.stop();
            root.shutdownTimer.stop();
            root.stableTimer.stop();
            root.processExited = true;
            root.pendingExitCode = exitCode;
            if (root.acceptingOutput)
                root.drainTimer.restart();
            else
                root.finalizeExit();
        }
    }
}
