import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import qs.modules.theme
import qs.modules.components
import qs.modules.services
import qs.config

// Layout-mode dropdown for the Wallpapers tab, modelled after SchemeSelector:
// a pill whose option list expands downward and paints over the content below
// (the tab keeps this row above the grid via z). Lives at the far right of the
// filter row; hidden on single-monitor setups where the mode is meaningless.
// Fill covers and crops, Fit never crops, Stretch distorts, Center draws
// the image unscaled.
Item {
    id: root

    implicitWidth: 128
    implicitHeight: 32

    readonly property var modes: [
        { id: "per-screen", label: "Per Screen" },
        { id: "fill", label: "Fill" },
        { id: "fit", label: "Fit" },
        { id: "stretch", label: "Stretch" },
        { id: "center", label: "Center" }
    ]

    // Index of the actually active mode, derived from the persisted setting.
    readonly property int selectedModeIndex: {
        var index = 0;
        for (var i = 0; i < modes.length; i++)
            if (modes[i].id === SpanWall.mode)
                index = i;
        return index;
    }

    // Keyboard/pointer cursor while the list is open (SchemeSelector's
    // selectedSchemeIndex equivalent); snaps to the active mode on open.
    property int cursorIndex: selectedModeIndex
    property bool modeListExpanded: false
    property bool keyboardNavigationActive: false

    signal modeSelectorClosed
    signal escapePressedOnMode
    signal tabPressed
    signal shiftTabPressed

    visible: Quickshell.screens.length > 1

    onModeListExpandedChanged: {
        if (modeListExpanded)
            cursorIndex = selectedModeIndex;
    }

    function openAndFocus() {
        modeListExpanded = true;
        cursorIndex = selectedModeIndex;
        keyboardNavigationActive = true;
        modeButton.forceActiveFocus();
    }

    function closeAndSignal() {
        keyboardNavigationActive = false;
        modeListExpanded = false;
        modeSelectorClosed();
    }

    StyledRect {
        variant: root.keyboardNavigationActive && modeButton.activeFocus ? "focus" : "pane"
        radius: Styling.radius(4)
        anchors.fill: parent

        // Same nesting as SchemeSelector: the surface is the StyledRect itself,
        // the button is inset by 4px so the ring stays visible.
        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 4
            spacing: 0

            Button {
                id: modeButton
                Layout.fillWidth: true
                Layout.fillHeight: true
                focus: true
                text: root.modes[root.selectedModeIndex].label

                onActiveFocusChanged: {
                    if (!activeFocus) {
                        root.keyboardNavigationActive = false;
                        root.modeListExpanded = false;
                    }
                }

                onClicked: {
                    keyboardNavigationActive = false;
                    root.modeListExpanded = !root.modeListExpanded;
                }

                background: Rectangle {
                    color: Colors.background
                    radius: Styling.radius(0)
                }

                contentItem: Text {
                    text: modeButton.text
                    color: Colors.overSurface
                    font.family: Config.theme.font
                    font.pixelSize: Config.theme.fontSize
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: 8
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Tab) {
                        if (root.keyboardNavigationActive) {
                            root.keyboardNavigationActive = false;
                            root.modeListExpanded = false;
                            if (event.modifiers & Qt.ShiftModifier)
                                root.shiftTabPressed();
                            else
                                root.tabPressed();
                            event.accepted = true;
                        }
                    } else if (event.key === Qt.Key_Space) {
                        root.modeListExpanded = !root.modeListExpanded;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Down) {
                        if (root.modeListExpanded && root.cursorIndex < root.modes.length - 1)
                            root.cursorIndex++;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Up) {
                        if (root.modeListExpanded && root.cursorIndex > 0)
                            root.cursorIndex--;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        if (root.modeListExpanded && root.cursorIndex >= 0 && root.cursorIndex < root.modes.length)
                            SpanWall.setMode(root.modes[root.cursorIndex].id);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        root.keyboardNavigationActive = false;
                        root.modeListExpanded = false;
                        root.escapePressedOnMode();
                        event.accepted = true;
                    }
                }
            }
        }
    }

    // Option list: anchored below the pill instead of growing the pill itself,
    // so the pill never moves when it expands (it is centre-anchored in the
    // filter row). Height 0 + clip hides it when collapsed.
    ClippingRectangle {
        id: modeList
        anchors.top: parent.bottom
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.right: parent.right
        height: root.modeListExpanded ? 24 * root.modes.length + 8 : 0
        color: Colors.background
        radius: Styling.radius(0)
        opacity: root.modeListExpanded ? 1 : 0
        clip: true

        Behavior on height {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration
                easing.type: Easing.OutQuart
            }
        }

        Behavior on opacity {
            enabled: Config.animDuration > 0
            NumberAnimation {
                duration: Config.animDuration / 2
                easing.type: Easing.OutQuart
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 4

            Repeater {
                model: root.modes

                Button {
                    id: modeRow
                    required property var modelData
                    required property int index

                    width: modeList.width - 8
                    height: 24

                    background: Rectangle {
                        color: "transparent"
                    }

                    contentItem: Text {
                        text: modeRow.modelData.label
                        color: root.cursorIndex === modeRow.index ? Styling.srItem("primary") : Colors.overSurface
                        font.family: Config.theme.font
                        font.pixelSize: Config.theme.fontSize
                        font.weight: root.cursorIndex === modeRow.index ? Font.Bold : Font.Normal
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 8

                        Behavior on color {
                            enabled: Config.animDuration > 0
                            ColorAnimation {
                                duration: Config.animDuration / 2
                                easing.type: Easing.OutQuart
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.cursorIndex = modeRow.index
                        onClicked: {
                            SpanWall.setMode(modeRow.modelData.id);
                            root.modeListExpanded = false;
                        }
                    }
                }
            }
        }
    }
}
