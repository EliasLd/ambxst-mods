pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pipewire

// Vesktop's mic capture stream as a controllable node. The dashboard's self
// tile drives its mic bar through this, so the bar adjusts exactly what the
// voice chat hears (the gain between Vesktop's selected input device and its
// capture) and never touches other apps or the device volume itself.
//
// The stream only exists while Vesktop is capturing, so `node` (and along
// with it `ready`) comes and goes with the call; the bar hides when absent.
Singleton {
    id: root

    // First audio capture stream owned by Vesktop. `isStream && !isSink`
    // filters to source outputs (devices and playback streams excluded),
    // the same convention the base shell's Audio service uses for its
    // input app node list.
    readonly property var node: {
        const values = Pipewire.nodes.values ?? [];
        for (let i = 0; i < values.length; i++) {
            const candidate = values[i];
            if (!candidate.isStream || candidate.isSink || !candidate.audio)
                continue;
            const app = candidate.properties["application.name"] ?? "";
            if (app.toLowerCase() === "vesktop")
                return candidate;
        }
        return null;
    }

    readonly property bool ready: node?.ready === true
    // Linear 0-1 gain, like every shell-side audio node.
    readonly property real volume: node?.audio?.volume ?? 0
    readonly property bool muted: node?.audio?.muted ?? false

    // Populates `node.audio`; re-tracks on its own when node is replaced.
    PwObjectTracker {
        objects: [root.node]
    }

    function setVolume(value) {
        if (root.ready)
            root.node.audio.volume = Math.max(0, Math.min(1, value));
    }
}
