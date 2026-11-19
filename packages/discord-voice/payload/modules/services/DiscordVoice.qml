pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

// State for the discord-voice mod: connection flags, the latest voice state
// snapshot from the companion plugin, and the write side for the tab's
// controls.
//
// One unix socket, newline-delimited UTF-8 JSON: the AmbxstDiscord
// userplugin inside Vesktop connects to the bridge and pushes messages
// ("hello", "state", "speaking", "ack"); the mod answers with commands
// ("cmd volume.set" / "self.toggle" / "camera.toggle" / "voice.leave" /
// "state.get"). Everything executes inside the plugin against Discord's own
// stores and actions: released Vesktop (1.6.x) has no unix control plane a
// shell could write to, so there is no second socket.
Singleton {
    id: root

    // Must match the manifest id.
    readonly property string modId: "eliasld.discord-voice"

    // Per-user runtime dir, resolved the same way BackendService does. The
    // shell expression in GlobalShortcuts is not usable here because the
    // socket objects need plain paths.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    readonly property string bridgePath: root.runtimeDir + "/ambxst_discord.sock"

    // Connection flags, rendered as chips in the tab. pluginActive means a
    // companion said hello for the current Vesktop session.
    property bool pluginActive: false

    // Latest full snapshot from the plugin (`state` message) and views of it.
    // null until the plugin lands its first snapshot.
    property var state: null
    readonly property bool inVoice: root.state !== null && root.state.inVoice === true
    readonly property var users: root.state && root.state.users ? root.state.users : []
    readonly property var self: root.state && root.state.self ? root.state.self : null
    readonly property var channel: root.state && root.state.channel ? root.state.channel : null

    // userId -> bool, last coalesced speaking transitions from the plugin.
    // Rebuilt on every update so bindings on the map fire.
    property var speaking: ({})

    // Settings, persisted through ModsService (SpanWall pattern).
    property bool speakingGlow: true
    property bool debugState: false

    // Raw protocol trace for the "Show protocol state" debug view.
    property string lastBridgeLine: ""
    property real lastBridgeAt: 0

    // --- outbound command machinery ---

    property int nextCmdId: 1
    property var pendingCmds: ({})
    property var bridgeConn: null

    Component.onCompleted: {
        ModsService.getSettings(modId, function (settings, error) {
            if (!error && settings && settings.values) {
                if (typeof settings.values.speakingGlow === "boolean")
                    root.speakingGlow = settings.values.speakingGlow;
                if (typeof settings.values.debugState === "boolean")
                    root.debugState = settings.values.debugState;
            }
        });
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId !== root.modId)
                return;
            if (key === "speakingGlow")
                root.speakingGlow = value === true;
            else if (key === "debugState")
                root.debugState = value === true;
        }
    }

    // A killed shell dies without unlinking its socket, so the file often
    // still exists at restart time. Clear it before binding; the server only
    // owns this path, and Ambxst runs as a single instance.
    Process {
        id: bridgeCleanup
        command: ["rm", "-f", root.bridgePath]
        running: true
        onExited: bridgeServer.active = true
    }

    SocketServer {
        id: bridgeServer
        path: root.bridgePath
        active: false
        // One connection object per client; the server fills in connected
        // and path itself. Only one plugin is expected; a fresh Vesktop
        // session simply replaces the old reference.
        handler: Socket {
            id: conn
            parser: SplitParser {
                onRead: data => root._onBridgeLine(data)
            }
            onConnectionStateChanged: root._onBridgeConnection(conn)
        }
    }

    function _onBridgeConnection(conn) {
        if (conn.connected) {
            root.bridgeConn = conn;
            root._log("bridge client connected");
        } else {
            if (root.bridgeConn === conn) {
                // Companion gone (Vesktop closed, plugin disabled, renderer
                // reload): drop the stale snapshot so the tab falls back to
                // its empty states until the plugin reconnects and pushes a
                // fresh one.
                root.bridgeConn = null;
                root.pluginActive = false;
                root.state = null;
                root.speaking = {};
                root._log("bridge client disconnected");
            }
        }
    }

    function _onBridgeLine(data) {
        if (!data || data === "")
            return;
        var msg;
        try {
            msg = JSON.parse(data);
        } catch (e) {
            console.warn("[discord-voice] bridge: unparseable line:", e);
            return;
        }
        // The debug pane stays planted on the latest full snapshot (the one
        // with the participants in it): speaking/ack lines churn at speaking
        // rate and would flicker the participants out of the pane.
        if (msg.t === "hello" || msg.t === "state") {
            root.lastBridgeLine = data;
            root.lastBridgeAt = Date.now();
        }
        switch (msg.t) {
        case "hello":
            root.pluginActive = true;
            root._log("plugin hello version=" + (msg.plugin || "?") + " vencord=" + (msg.vencordHash || "?"));
            break;
        case "state":
            root.state = msg.data || null;
            root.speaking = {};
            break;
        case "speaking":
            if (msg.userId) {
                var map = Object.assign({}, root.speaking);
                map[msg.userId] = msg.on === true;
                root.speaking = map;
            }
            break;
        case "ack":
            var cb = root.pendingCmds[msg.id];
            if (cb) {
                delete root.pendingCmds[msg.id];
                cb(msg.ok === true, msg.error || "");
            }
            break;
        default:
            root._log("bridge: unknown message type t=" + (msg.t || "?"));
        }
    }

    // --- public commands for the tab ---
    // Every control is executed inside the plugin against Discord's own
    // stores and actions; each command changes something, so a fresh `state`
    // line follows and the tab stays truthful.

    function toggleSelfMute() {
        return root.sendCommand("self.toggle", {
            kind: "mute"
        });
    }

    function toggleSelfDeafen() {
        return root.sendCommand("self.toggle", {
            kind: "deafen"
        });
    }

    function toggleCamera() {
        return root.sendCommand("camera.toggle", {});
    }

    function leaveVoice() {
        return root.sendCommand("voice.leave", {});
    }

    // Per-user local volume, 0-200 percent, executed by the plugin.
    function setUserVolume(userId, value) {
        return root.sendCommand("volume.set", {
            userId: String(userId),
            value: Math.max(0, Math.min(200, Math.round(value)))
        });
    }

    // Ask the plugin for a fresh full snapshot (backs the retry affordance).
    function recheckState() {
        return root.sendCommand("state.get", {});
    }

    function sendCommand(op, params, callback) {
        if (!bridgeConn) {
            console.warn("[discord-voice] plugin not connected; dropping", op);
            return false;
        }
        const id = root.nextCmdId++;
        if (callback)
            root.pendingCmds[id] = callback;
        const msg = Object.assign({
            t: "cmd",
            id: id,
            op: op
        }, params || {});
        bridgeConn.write(JSON.stringify(msg) + "\n");
        bridgeConn.flush();
        return true;
    }

    function _log(message) {
        console.log("[discord-voice]", message);
    }
}
