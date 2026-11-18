pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Templates as T
import MyBench.Framework
import MyBench.Controls

// An instrument tile of the Overview: a card with the instrument icon, name and
// state, a green Run / red Stop button, and the instrument's own body (<Name>Tile.qml: its key
// settings and a live preview). Click shows the instrument; drag onto the workspace splits; the
// context menu has Show, Show Beside, Run/Stop and Pin to Top. A template control: the look is ours.
T.Control {
    id: tile

    property string title
    property string iconName
    property string status                  // "running" | "starting" | "paused" | "error" | ""
    property string keyValue
    property string summary                 // the instrument's setup, one line (tooltip)
    property Component preview: null
    property bool pinned: false
    property bool running: false
    property bool canToggle: false
    // Stopped and nothing measured yet.
    property bool idle: false
    property Menu menu: null
    // Drag the tile onto the workspace to show the instrument.
    property string paneId: ""
    property alias dragChip: chip

    signal clicked()
    signal runToggled()

    readonly property color statusColor: status === "running" ? Theme.positive
        : status === "paused" || status === "starting" ? Theme.caution
        : status === "error" ? Theme.negative : Theme.textTertiary
    readonly property string statusText: status === "running" ? qsTr("Running")
        : status === "paused" ? qsTr("Paused") : status === "starting" ? qsTr("Starting")
        : status === "error" ? qsTr("Error") : qsTr("Stopped")

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding)
    hoverEnabled: true
    padding: Theme.spacingM
    focusPolicy: Qt.TabFocus
    Accessible.role: Accessible.Button
    Accessible.name: title
    Accessible.description: [statusText, keyValue].filter(s => s.length > 0).join(", ")
    Accessible.onPressAction: tile.clicked()
    Keys.onReturnPressed: tile.clicked()
    Keys.onSpacePressed: tile.clicked()

    ContextMenu.menu: tile.menu

    DragHandler {
        id: dragHandler
        target: null
        enabled: tile.paneId.length > 0
        grabPermissions: PointerHandler.CanTakeOverFromAnything
    }
    DragChip {
        id: chip
        objectName: "tileDragChip"
        handler: dragHandler
        paneId: tile.paneId
        title: tile.title
        iconName: tile.iconName
        origin: "tile"
    }

    background: Rectangle {
        radius: Theme.radiusPopup
        color: Theme.base
        border.width: Theme.borderWidth
        border.color: tile.hovered ? Theme.controlBorder : Theme.separator
        FocusRing { shown: tile.visualFocus; radius: Theme.radiusPopup + 3 }
        TapHandler {
            acceptedButtons: Qt.LeftButton
            onTapped: tile.clicked()
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingS

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            Icon {
                name: tile.iconName
                size: Theme.iconSizeXL
                color: Theme.textSecondary
            }
            // The name, and under it the state: a dot and one word.
            ColumnLayout {
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                spacing: 0
                Text {
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    text: tile.title
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeHeading
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Row {
                    spacing: Theme.spacingXs + 2
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Theme.spacingS - 1
                        height: width
                        radius: width / 2
                        color: tile.statusColor
                    }
                    Text {
                        objectName: "tileState"
                        text: tile.statusText
                        color: tile.status.length > 0 ? Theme.textSecondary : Theme.textTertiary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
            }
            Icon {
                visible: tile.pinned
                name: "pin"
                size: Theme.iconSizeS
                color: Theme.textTertiary
            }
            // Run / Stop, filled like the header's button: green, red while running.
            ToolButton {
                id: runButton
                objectName: "tileRun"
                visible: tile.canToggle
                implicitWidth: Theme.controlHeight
                implicitHeight: Theme.controlHeight
                icon.source: Theme.icon(tile.running ? "stop-filled" : "play")
                icon.width: Theme.iconSize
                icon.height: Theme.iconSize
                icon.color: Theme.onColor(fill)
                background: Rectangle {
                    radius: width / 2
                    color: runButton.down ? Qt.darker(runButton.fill, 1.2)
                         : runButton.hovered ? Qt.lighter(runButton.fill, 1.1) : runButton.fill
                    FocusRing { shown: runButton.visualFocus }
                }
                readonly property color fill: tile.running ? Theme.stopFill : Theme.runFill
                Accessible.name: tile.running ? qsTr("Stop %1").arg(tile.title) : qsTr("Run %1").arg(tile.title)
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: Accessible.name
                onClicked: tile.runToggled()
            }
        }

        Loader {
            id: body
            objectName: "tileBody"
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
            sourceComponent: tile.preview
            clip: true
        }
    }
}
