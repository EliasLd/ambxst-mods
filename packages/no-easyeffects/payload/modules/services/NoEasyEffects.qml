pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// Cleanup service for the no-easyeffects mod. The shell's Go backend drops
// an easyeffects --gapplication-service instance before Quickshell runs
// (backend/cmd/ambxst/main.go); with the mod active nothing in the
// composed shell touches EasyEffects anymore, so this singleton only exists
// to remove that one instance a moment later. A bounded startup window
// covers the gap between the detached spawn and the shell coming up;
// afterwards the singleton goes quiet with no timers or processes left, and
// nothing respawns the service for the rest of the session.
Singleton {
    id: root

    // Same cmdline the base shell itself matches in main.go; a user-opened
    // EasyEffects GUI (plain "easyeffects" cmdline) never matches.
    readonly property string processPattern: "easyeffects.*gapplication-service"

    // The spawn precedes Quickshell, so the first lookup usually finds it;
    // rechecks with this spacing cover slow boots. 8 more checks at 2 s
    // make the whole window ~16 s; each one ends it either way.
    readonly property int checkIntervalMs: 2000
    readonly property int windowChecks: 8
    property int checksLeft: root.windowChecks
    // Found at least once: a later absence then means "confirmed gone"
    // (the normal case ends here) and the window can close early.
    property bool killedAny: false

    function _closeWindow() {
        checkTimer.running = false;
        root.checksLeft = 0;
    }

    function _log(message) {
        console.log("[no-easyeffects]", message);
    }

    Component.onCompleted: {
        lookupProcess.running = true;
        checkTimer.running = true;
    }

    // Exit code 0 means a service instance exists.
    Process {
        id: lookupProcess
        command: ["pgrep", "-f", root.processPattern]

        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                if (!root.killedAny)
                    root._log("EasyEffects service found; killing it");
                root.killedAny = true;
                killProcess.running = true;
            } else if (root.killedAny) {
                root._log("EasyEffects service is gone; done");
                root._closeWindow();
            }
        }
    }

    Process {
        id: killProcess
        command: ["pkill", "-f", root.processPattern]

        onExited: (exitCode, exitStatus) => {
            if (exitCode !== 0)
                root._log("kill attempt failed with exit code " + exitCode);
        }
    }

    Timer {
        id: checkTimer
        interval: root.checkIntervalMs
        repeat: true
        running: false

        onTriggered: {
            root.checksLeft = root.checksLeft - 1;
            if (root.checksLeft <= 0) {
                running = false;
                // Only worth a line when the window simply ended without
                // ever finding a spawn (easyeffects not installed): the
                // confirmed-gone path already logged its own line.
                if (!root.killedAny)
                    root._log("startup window ended without finding the EasyEffects service");
            } else {
                lookupProcess.running = true;
            }
        }
    }
}
