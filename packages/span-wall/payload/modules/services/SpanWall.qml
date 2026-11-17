pragma Singleton

import QtQuick
import Quickshell
import qs.modules.services

// State for the span-wall mod: which layout mode the user picked and the
// geometry of the virtual desktop. Screens are read from Quickshell, whose
// geometry is the post-transform logical size, so per-screen wallpaper
// windows map 1:1 onto the virtual layout and span slices are plain offset
// crops — no rotation math needed anywhere.
Singleton {
    id: root

    // Must match the manifest id.
    readonly property string modId: "eliasld.span-wall"

    // Persisted through ModsService; falls back to the stock behavior for
    // anything unexpected (no saved setting, IPC error, mods disabled).
    property string mode: "per-screen"
    readonly property bool spanActive: mode === "span" && Quickshell.screens.length > 1

    // Union of every screen's rectangle. Re-evaluates on hotplug and layout
    // changes, and every consumer is binding-driven off this.
    readonly property rect virtualRect: {
        var minX = 0, minY = 0, maxX = 0, maxY = 0;
        var first = true;
        var screens = Quickshell.screens;
        for (var i = 0; i < screens.length; i++) {
            var s = screens[i];
            if (first) {
                minX = s.x;
                minY = s.y;
                maxX = s.x + s.width;
                maxY = s.y + s.height;
                first = false;
            } else {
                if (s.x < minX)
                    minX = s.x;
                if (s.y < minY)
                    minY = s.y;
                if (s.x + s.width > maxX)
                    maxX = s.x + s.width;
                if (s.y + s.height > maxY)
                    maxY = s.y + s.height;
            }
        }
        return Qt.rect(minX, minY, maxX - minX, maxY - minY);
    }

    Component.onCompleted: {
        ModsService.getSettings(modId, function (settings, error) {
            if (!error && settings && typeof settings.values.mode === "string")
                root._applySetting(settings.values.mode);
        });
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId === root.modId && key === "mode")
                root._applySetting(value);
        }
    }

    function _applySetting(value) {
        mode = value === "span" ? "span" : "per-screen";
    }

    // Optimistic local update for snappy UI; the IPC round trip re-syncs the
    // same value through onSettingChanged.
    function setMode(value) {
        var next = value === "span" ? "span" : "per-screen";
        mode = next;
        ModsService.setSetting(modId, "mode", next);
    }
}
