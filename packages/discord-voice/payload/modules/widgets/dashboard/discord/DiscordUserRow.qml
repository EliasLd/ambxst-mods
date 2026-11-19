pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// One voice-channel participant: avatar with a speaking glow ring, display
// name, mic/deafen/local-mute indicators and the per-user local volume
// slider. The volume value lives with Discord; the row is just a remote
// control, so nothing is persisted here.
Rectangle {
    id: userRow

    color: "transparent"
    height: 56

    property var user: null

    readonly property string userId: user ? String(user.id) : ""
    readonly property string userName: user ? (user.name || "?") : "?"
    readonly property bool muted: user ? user.muted === true : false
    readonly property bool deafened: user ? user.deafened === true : false
    readonly property bool suppressed: user ? user.suppressed === true : false
    readonly property bool localMute: user ? user.localMute === true : false
    // Self has no local audio context (you do not "hear" yourself through a
    // local volume), so the volume bar is only for other participants.
    readonly property bool isSelf: user ? user.self === true : false
    // The plugin reports volume as null when the internal volume module is
    // unavailable; the slider hides instead of pretending.
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
        volumeSlider.value = volumeValue / 200;
        syncing = false;
    }

    Row {
        anchors.fill: parent
        spacing: 10

        // --- Avatar with speaking glow ring ---
        Item {
            width: 44
            height: 44
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                id: glowRing

                anchors.fill: parent
                radius: width / 2
                color: "transparent"
                border.width: 2
                border.color: Styling.srItem("primary")
                opacity: 0

                SequentialAnimation on opacity {
                    running: DiscordVoice.speakingGlow && userRow.speaking
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
                anchors.margins: 2
                radius: width / 2
                variant: "pane"

                Image {
                    id: avatarImage

                    anchors.fill: parent
                    anchors.margins: 2
                    visible: userRow.user && userRow.user.avatarUrl !== ""
                    source: visible ? userRow.user.avatarUrl : ""
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
        }

        // --- Name ---
        Text {
            text: userRow.userName
            color: userRow.speaking ? Styling.srItem("primary") : Colors.overBackground
            font.family: Config.theme.font
            font.pixelSize: 15
            font.weight: userRow.speaking ? Font.Medium : Font.Normal
            elide: Text.ElideRight
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 44 - 10 - statusIcons.width - 10 - volumeArea.width - 10
            verticalAlignment: Text.AlignVCenter

            Behavior on color {
                enabled: Config.animDuration > 0
                ColorAnimation {
                    duration: Config.animDuration
                }
            }
        }

        // --- Mic / hearing indicators ---
        Row {
            id: statusIcons

            spacing: 6
            anchors.verticalCenter: parent.verticalCenter

            Text {
                visible: userRow.muted || userRow.suppressed
                text: Icons.micSlash
                color: Colors.overError
                font.family: Icons.font
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                visible: userRow.deafened
                text: Icons.speakerX
                color: Colors.overError
                font.family: Icons.font
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                visible: userRow.localMute && !userRow.deafened
                text: Icons.speakerSlash
                color: Colors.overSurfaceVariant
                font.family: Icons.font
                font.pixelSize: 14
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // --- Per-user local volume (never for self: the bar would imply a
        //     local audio path that does not exist) ---
        Item {
            id: volumeArea

            visible: userRow.hasVolume && !userRow.isSelf
            width: visible ? 120 : 0
            height: 34
            anchors.verticalCenter: parent.verticalCenter

            StyledSlider {
                id: volumeSlider

                anchors.fill: parent
                anchors.margins: 4
                resizeParent: false
                tooltipText: Math.round(value * 200) + "%"
                icon: userRow.localMute ? Icons.speakerSlash : Icons.speaker
                iconClickable: false
                smoothDrag: true
                enabled: !userRow.localMute
                opacity: userRow.localMute ? 0.4 : 1

                onValueChanged: {
                    if (userRow.syncing)
                        return;
                    if (userRow.user)
                        DiscordVoice.setUserVolume(userRow.userId, Math.round(value * 200));
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
