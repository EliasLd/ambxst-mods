pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// One voice-channel participant as a grid tile: avatar with the speaking
// ring and a mic / deafen badge, the display name right above the volume
// bar, and the bar itself. The volume value lives with Discord; the tile is
// just a remote control, so nothing is persisted here.
Rectangle {
    id: tile

    color: "transparent"
    // Uniform grid cells: the tab sizes the width from its column count,
    // the tile owns the fixed height.
    implicitHeight: 104

    property var user: null

    readonly property string userId: user ? String(user.id) : ""
    readonly property string userName: user ? (user.name || "?") : "?"
    readonly property bool muted: user ? user.muted === true : false
    readonly property bool deafened: user ? user.deafened === true : false
    readonly property bool suppressed: user ? user.suppressed === true : false
    readonly property bool localMute: user ? user.localMute === true : false
    // Self has no local audio context (you do not "hear" yourself through a
    // local volume), so the bar only exists for other participants.
    readonly property bool isSelf: user ? user.self === true : false
    // The plugin reports volume as null when the internal volume module is
    // unavailable; the bar hides instead of pretending.
    readonly property bool hasVolume: user ? typeof user.volume === "number" : false
    readonly property real volumeValue: hasVolume ? user.volume : 100
    readonly property bool speaking: DiscordVoice.speaking[user ? String(user.id) : ""] === true

    // Guards the slider against echoing state updates back as commands
    // (MicSlider's external-change pattern).
    property bool syncing: false

    onUserChanged: syncVolume()
    Component.onCompleted: syncVolume()

    function syncVolume() {
        syncing = true;
        // Track is 1:1 percent (0-100), like Vesktop's own popout slider;
        // values Discord stored above 100 pin the fill at the end.
        volumeSlider.value = Math.min(volumeValue / 100, 1);
        syncing = false;
    }

    Column {
        anchors.fill: parent
        spacing: 2

        // --- Avatar with the speaking glow ring and the state badge ---
        Item {
            width: 52
            height: 52
            anchors.horizontalCenter: parent.horizontalCenter

            Rectangle {
                id: glowRing

                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                // A 3px ring: anything thinner disappears next to an avatar
                // this size.
                border.width: 3
                border.color: Styling.srItem("primary")
                opacity: 0

                SequentialAnimation on opacity {
                    running: DiscordVoice.speakingGlow && tile.speaking
                    alwaysRunToEnd: true

                    NumberAnimation {
                        from: 0.55
                        to: 1
                        duration: Config.animDuration > 0 ? Config.animDuration : 100
                        easing.type: Easing.InOutSine
                    }

                    NumberAnimation {
                        from: 1
                        to: 0.55
                        duration: Config.animDuration > 0 ? Config.animDuration * 2 : 200
                        easing.type: Easing.InOutSine
                    }
                }
            }

            StyledRect {
                id: avatarBox

                anchors.fill: glowRing
                anchors.margins: 3
                radius: width / 2
                variant: "pane"

                Image {
                    id: avatarImage

                    anchors.fill: parent
                    anchors.margins: 2
                    visible: tile.user && tile.user.avatarUrl !== ""
                    source: visible ? tile.user.avatarUrl : ""
                    mipmap: true
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                }

                Text {
                    visible: !avatarImage.visible
                    anchors.centerIn: parent
                    text: Icons.user
                    color: Colors.overSurfaceVariant
                    font.family: Icons.font
                    font.pixelSize: 18
                }
            }

            // Discord-style corner badge for their own mute / deafen state
            // (deafen wins: a deafened user is muted too). Local mute is not
            // badge material - the volume bar carries it.
            StyledRect {
                visible: tile.deafened || tile.muted || tile.suppressed
                width: 16
                height: 16
                radius: 8
                anchors.right: parent.right
                anchors.rightMargin: -2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: -2
                variant: "pane"

                Text {
                    anchors.centerIn: parent
                    text: tile.deafened ? Icons.speakerX : Icons.micSlash
                    color: Colors.overError
                    font.family: Icons.font
                    font.pixelSize: 10
                }
            }
        }

        // --- Name, directly above the bar ---
        Text {
            width: parent.width
            text: tile.userName
            color: tile.speaking ? Styling.srItem("primary") : Colors.overBackground
            font.family: Config.theme.font
            font.pixelSize: 11
            font.weight: tile.speaking ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration
                }
            }
        }

        // --- Per-user local volume (never for self: the bar would imply a
        //     local audio path that does not exist) ---
        Row {
            visible: tile.hasVolume && !tile.isSelf
            width: parent.width
            height: 26
            spacing: 4

            StyledSlider {
                id: volumeSlider

                width: parent.width
                height: parent.height
                resizeParent: false
                tooltipText: Math.round(value * 100) + "%"
                icon: tile.localMute ? Icons.speakerSlash : Icons.speakerHigh
                iconClickable: false
                // The wheel belongs to the participant grid; volume is
                // drag-first.
                scroll: false
                smoothDrag: true
                enabled: !tile.localMute
                opacity: tile.localMute ? 0.4 : 1

                onValueChanged: {
                    if (tile.syncing)
                        return;
                    if (tile.user)
                        DiscordVoice.setUserVolume(tile.userId, Math.round(value * 100));
                }

                Behavior on opacity {
                    enabled: Config.animDuration > 0
                    NumberAnimation {
                        duration: Config.animDuration / 2
                    }
                }
            }
        }
    }
}
