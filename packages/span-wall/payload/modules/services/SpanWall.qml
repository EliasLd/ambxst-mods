pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.modules.services

// State for the span-wall mod: which layout mode the user picked and the
// geometry of the virtual desktop. The spanning layouts (fill/fit/stretch/
// center) paint one image over the whole desktop; per-screen is stock Ambxst.
// Screens are read from Quickshell, whose geometry is the post-transform
// logical size, so per-screen wallpaper windows map 1:1 onto the virtual
// layout and span slices are plain offset crops — no rotation math needed
// anywhere.
Singleton {
    id: root

    // Must match the manifest id.
    readonly property string modId: "eliasld.span-wall"

    // Persisted through ModsService; falls back to the stock behavior for
    // anything unexpected (no saved setting, IPC error, mods disabled).
    property string mode: "per-screen"
    readonly property bool spanActive: mode !== "per-screen" && Quickshell.screens.length > 1

    // How a spanning layout paints the image over the virtual desktop;
    // per-screen falls back to the stock crop at the consumers. Center
    // (Image.Pad) exists since Qt 6.9, hence the guard: on older engines
    // the member is undefined and center falls back to the crop.
    readonly property int spanFillMode: root.mode === "fit"
            ? Image.PreserveAspectFit
            : root.mode === "stretch" ? Image.Stretch
            : root.mode === "center" && Image.Pad !== undefined ? Image.Pad
            : Image.PreserveAspectCrop

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
            // The daemon may have normalized a legacy value; the raw-file
            // peek below runs after this answer to correct it.
            root.bootSettingsApplied = true;
        });
    }

    Connections {
        target: ModsService
        function onSettingChanged(modId, key, value) {
            if (modId === root.modId && key === "mode")
                root._applySetting(value);
        }
    }

    // The daemon validates stored settings against settings.json and drops
    // values that no longer match an option, so a 0.2.x "span" never arrives
    // through ModsService - it reads as the default. Peek the raw settings
    // file once at boot and re-apply what it holds: the whitelist in
    // _applySetting migrates "span" to "fill" (a single settings write) and
    // no-ops for anything the IPC answer already covered. Read-only: the
    // adapter never writes back.
    readonly property string settingsPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/ambxst/mods/" + modId + ".json"
    property bool bootSettingsApplied: false
    onBootSettingsAppliedChanged: root._maybeMigrate()

    FileView {
        id: legacyPeek
        path: root.settingsPath
        preload: true
        watchChanges: false
        printErrors: false
        adapter: JsonAdapter {
            property string mode: ""
        }
        onLoaded: root._maybeMigrate()
        onLoadFailed: root._maybeMigrate()
    }

    function _maybeMigrate() {
        if (!root.bootSettingsApplied || !legacyPeek.loaded)
            return;
        root._applySetting(legacyPeek.adapter.mode);
    }

    function _applySetting(value) {
        var next = "per-screen";
        if (value === "span")
            next = "fill";
        else if (value === "fill" || value === "fit" || value === "stretch" || value === "center")
            next = value;
        mode = next;
        // One-time migration so the store and the Settings pane agree with
        // the new names; the echo lands as a no-op.
        if (next !== value)
            ModsService.setSetting(modId, "mode", next);
    }

    // Optimistic local update for snappy UI; the IPC round trip re-syncs the
    // same value through onSettingChanged.
    function setMode(value) {
        var next = "per-screen";
        if (value === "fill" || value === "fit" || value === "stretch" || value === "center")
            next = value;
        mode = next;
        ModsService.setSetting(modId, "mode", next);
    }
}
