pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.modules.widgets.dashboard.widgets
import qs.config

// Discord voice tab: connection chip, self controls, participants and the
// empty states for every missing piece of the stack. All state comes from
// the DiscordVoice singleton, which stays alive regardless of tab visibility.
// The mod reaches Vesktop only through the AmbxstDiscord plugin (released
// Vesktop has no control socket a shell could write to), so there is
// exactly one connection signal: the companion chip.
Rectangle {
    id: discordTabRoot

    color: "transparent"
    implicitWidth: 400
    implicitHeight: 470

    readonly property var channel: DiscordVoice.channel
    readonly property var self: DiscordVoice.self
    readonly property var users: DiscordVoice.users
    readonly property bool inVoice: DiscordVoice.inVoice
    readonly property bool pluginActive: DiscordVoice.pluginActive

    // The rows the tab repeats: self first (same shape as everyone else's
    // entry, plus a self marker the row uses to hide its volume bar), then
    // the other participants.
    readonly property var participants: {
        var list = discordTabRoot.users ?? [];
        if (discordTabRoot.self && discordTabRoot.self.id)
            list = [Object.assign({}, discordTabRoot.self, { self: true })].concat(list);
        return list;
    }

    // Self controls execute inside the plugin, so they only exist while the
    // plugin is connected - and they only make sense while in voice. There
    // is no blind-toggle mode without the transport.
    readonly property bool showControls: inVoice

    // Inline chip: lit or dark connection indicator in the header.
    component DiscordChip: Item {
        id: chip

        property string label: ""
        property bool active: false

        width: chipRow.width
        height: chipRow.height

        Row {
            id: chipRow

            spacing: 6

            Rectangle {
                width: 8
                height: 8
                radius: 4
                anchors.verticalCenter: parent.verticalCenter
                color: chip.active ? Colors.success : Colors.outline

                Behavior on color {
                    enabled: Config.animDuration > 0
                    ColorAnimation {
                        duration: Config.animDuration
                    }
                }
            }

            Text {
                text: chip.label
                color: chip.active ? Colors.overBackground : Colors.overSurfaceVariant
                font.family: Config.theme.font
                font.pixelSize: 12
            }
        }
    }

    ColumnLayout {
        id: content

        anchors.fill: parent
        anchors.margins: 16
        // The debug view anchors itself over the bottom edge; keep the
        // controls dock (now the bottom row) above it while it is open.
        anchors.bottomMargin: debugBox.visible ? 16 + debugBox.height + 8 : 16
        spacing: 12

        // --- Header: channel name plus connection chips ---
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            ColumnLayout {
                spacing: 2

                Text {
                    text: discordTabRoot.inVoice && discordTabRoot.channel ? discordTabRoot.channel.name : "Voice"
                    color: discordTabRoot.inVoice ? Styling.srItem("primary") : Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 20
                    font.weight: Font.Medium
                    elide: Text.ElideRight
                    Layout.maximumWidth: 260
                }

                Text {
                    visible: discordTabRoot.inVoice && discordTabRoot.channel
                    text: discordTabRoot.channel ? discordTabRoot.channel.guildName : ""
                    color: Colors.overSurfaceVariant
                    font.family: Config.theme.font
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.maximumWidth: 260
                }
            }

            Item {
                Layout.fillWidth: true
            }

            DiscordChip {
                label: discordTabRoot.pluginActive ? "Companion" : "No companion"
                active: discordTabRoot.pluginActive
            }
        }

        // --- Empty state: companion missing (covers Vesktop being closed too:
        //     without the plugin the mod cannot tell the two apart). The
        //     hint block centers in the remaining space of the tab. ---
        Item {
            visible: !discordTabRoot.pluginActive
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text: Icons.puzzlePiece
                    color: Colors.overSurfaceVariant
                    font.family: Icons.font
                    font.pixelSize: 40
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Companion plugin missing"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Start Vesktop with the AmbxstDiscord plugin; the tab lights up once it connects."
                    color: Colors.overSurfaceVariant
                    font.family: Config.theme.font
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: discordTabRoot.implicitWidth - 32
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignHCenter
                }

                StyledRect {
                    variant: "pane"
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: installHintText.implicitWidth + 24
                    implicitHeight: installHintText.implicitHeight + 16
                    Text {
                        id: installHintText
                        anchors.centerIn: parent
                        text: "curl -fsSL https://raw.githubusercontent.com/EliasLd/ambxst-mods/main/scripts/discord-install.sh | sh"
                        color: Colors.lightGreen
                        font.family: Config.theme.font
                        font.pixelSize: 12
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            Quickshell.clipboardText = installHintText.text;
                            installHintCopied.restart();
                        }
                    }
                }

                Text {
                    text: installHintCopied.running ? "Copied" : "Click to copy"
                    color: Colors.overSurfaceVariant
                    font.family: Config.theme.font
                    font.pixelSize: 11
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }

        // --- Participants (only while in voice). Self leads the list in the
        //     identical row style - Discord shows you among the participants
        //     too - and the row hides the volume bar for itself. ---
        ColumnLayout {
            visible: discordTabRoot.inVoice
            spacing: 6
            Layout.fillWidth: true

            Repeater {
                model: discordTabRoot.participants

                DiscordUserRow {
                    required property var modelData

                    user: modelData
                    width: parent.width
                }
            }
        }

        // --- Empty state: plugin up, but idle; centered like the other one ---
        Item {
            visible: discordTabRoot.pluginActive && !discordTabRoot.inVoice
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 6
                Text {
                    text: Icons.headphones
                    color: Colors.overSurfaceVariant
                    font.family: Icons.font
                    font.pixelSize: 40
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Not in a voice channel"
                    color: Colors.overBackground
                    font.family: Config.theme.font
                    font.pixelSize: 16
                    font.weight: Font.Medium
                    Layout.alignment: Qt.AlignHCenter
                }

                Text {
                    text: "Join one in Vesktop; the tab follows along."
                    color: Colors.overSurfaceVariant
                    font.family: Config.theme.font
                    font.pixelSize: 13
                    Layout.alignment: Qt.AlignHCenter
                }
                // Retry affordance for a missed or late first snapshot.
                Text {
                    id: recheckText

                    property bool clickedRecently: false

                    text: clickedRecently ? "Recheck sent" : "Recheck"
                    color: recheckArea.containsMouse ? Colors.overBackground : Colors.overSurfaceVariant
                    font.family: Config.theme.font
                    font.pixelSize: 12
                    Layout.alignment: Qt.AlignHCenter

                    MouseArea {
                        id: recheckArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            DiscordVoice.recheckState();
                            recheckText.clickedRecently = true;
                            recheckTimer.restart();
                        }
                    }

                    Timer {
                        id: recheckTimer
                        interval: 800
                        onTriggered: recheckText.clickedRecently = false
                    }
                }
            }
        }

        Item {
            Layout.fillHeight: true
        }

        // --- Self controls pinned to the bottom left: mute, deafen, camera,
        //     leave. ControlButton has no intrinsic size, so each button
        //     carries the dashboard's standard 48x48 preferred size (see
        //     QuickControls). Self controls execute inside the plugin, so
        //     they only exist while the plugin is connected - and they only
        //     make sense while in voice. There is no blind-toggle mode
        //     without the transport. ---
        RowLayout {
            visible: discordTabRoot.showControls
            spacing: 10

            ControlButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                isActive: !!(discordTabRoot.self && discordTabRoot.self.muted)
                iconName: !!(discordTabRoot.self && discordTabRoot.self.muted) ? Icons.micSlash : Icons.mic
                tooltipText: isActive ? "Unmute" : "Mute"
                onClicked: DiscordVoice.toggleSelfMute()
            }

            ControlButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                isActive: !!(discordTabRoot.self && discordTabRoot.self.deafened)
                iconName: !!(discordTabRoot.self && discordTabRoot.self.deafened) ? Icons.speakerX : Icons.headphones
                tooltipText: isActive ? "Undeafen" : "Deafen"
                onClicked: DiscordVoice.toggleSelfDeafen()
            }

            ControlButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                isActive: false
                iconName: Icons.webcam
                tooltipText: "Toggle camera"
                onClicked: DiscordVoice.toggleCamera()
            }

            ControlButton {
                Layout.preferredWidth: 48
                Layout.preferredHeight: 48
                isActive: false
                iconName: Icons.logout
                tooltipText: "Leave voice channel"
                onClicked: DiscordVoice.leaveVoice()
            }

            Item {
                Layout.fillWidth: true
            }
        }
    }

    // Debug view, anchored to the bottom when the setting is on.
    StyledRect {
        id: debugBox

        visible: DiscordVoice.debugState && DiscordVoice.lastBridgeLine !== ""
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        height: debugColumn.childrenRect.height + 18
        variant: "pane"
        radius: Styling.radius(6)

        Timer {
            interval: 1000
            repeat: true
            running: debugBox.visible
            onTriggered: debugMeta.updateAge()
        }

        Column {
            id: debugColumn
            anchors.centerIn: parent
            width: parent.width - 20

            Text {
                id: debugMeta

                property int ageSeconds: -1

                function updateAge() {
                    ageSeconds = DiscordVoice.lastBridgeAt > 0
                            ? Math.max(0, Math.round((Date.now() - DiscordVoice.lastBridgeAt) / 1000))
                            : -1;
                }

                text: ageSeconds >= 0 ? "bridge line (" + ageSeconds + "s ago)" : "no bridge line yet"
                color: Colors.overSurfaceVariant
                font.family: Config.theme.font
                font.pixelSize: 11
            }

            Text {
                width: parent.width
                // Same raw line, made readable: state snapshots get unwrapped
                // and the CDN avatar urls (long, participant-irrelevant) are
                // compacted to one character, so the users tail is on screen.
                text: {
                    const raw = DiscordVoice.lastBridgeLine;
                    if (!raw)
                        return "";
                    try {
                        const msg = JSON.parse(raw);
                        if (msg.t === "state" && msg.data)
                            return JSON.stringify(msg.data, function (key, value) {
                                return key === "avatarUrl" ? "+" : value;
                            });
                    } catch (e) {
                        return raw;
                    }
                    return raw;
                }
                color: Colors.overBackground
                font.family: Config.theme.font
                font.pixelSize: 11
                wrapMode: Text.WrapAnywhere
                maximumLineCount: 14
                elide: Text.ElideRight
            }
        }
    }

    Timer {
        id: installHintCopied
        interval: 1200
    }
}
