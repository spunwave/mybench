pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// One entry of the sidebar: a 20 px accent icon, the name and a trailing state dot
// (running = positive, starting or paused = caution, error = negative, stopped = none). Only while
// the instrument runs a second caption line carries its key value (at most 18 characters, in the
// positive colour). On hover or keyboard focus a small Run/Stop button replaces the dot. The tooltip
// opens to the right of the sidebar: the full title (expanded), or title, state and value (compact:
// the 56 px rail with the dot on the icon's corner). `paneId` "" is the Overview entry.
Item {
    id: row

    property string paneId
    property string title                    // short name shown in the row
    property string fullTitle                // tooltip and accessible name
    property string iconName
    property InstrumentController controller: null
    property bool child: false               // a view of an instrument (indented)
    property bool selected: false            // shown in the focused pane
    property bool shownBeside: false         // shown in the other pane of the split
    property bool current: false             // keyboard cursor of the sidebar
    property bool listFocused: false         // the sidebar has the keyboard focus
    property bool compact: false
    // The rail's geometry with the labels shown (the rail peeking open): rail-tall rows, the icon
    // where the rail has it, no value line, so nothing moves while it opens; `reveal` (0..1) fades the
    // labels in with the width.
    property bool railLayout: false
    property real reveal: 1
    // Icons in the text colour; the accent marks the selected row only.
    readonly property color iconColor: activeSelection ? Theme.selectionText : selected ? Theme.accent : Theme.textSecondary
    property Menu contextMenu: null

    readonly property string keyValue: controller && !child ? controller.keyValue : ""
    readonly property bool running: controller !== null && controller.running
    // The value line exists only while the instrument runs (never for a value held after a stop).
    readonly property bool showValue: running && keyValue.length > 0 && !railLayout
    // Left edge of the icon: 6 px of inset highlight plus 6 px.
    readonly property int rowHeight: railLayout ? railCell : 34   // one line; a value line adds its own height
    readonly property int railCell: 44            // compact rail: icon centred in a 44 px cell
    readonly property real leftEdge: railLayout ? Math.round((Theme.sidebarCompactWidth - Theme.iconSizeL) / 2)
                                                : Theme.spacingM + (child ? Theme.iconSizeL + Theme.spacingS : 0)
    readonly property string status: !controller || child ? ""
        : controller.paused ? "paused"
        : controller.state === InstrumentController.Starting ? "starting"
        : controller.running ? "running"
        : controller.hasError ? "error" : ""
    readonly property color statusColor: status === "running" ? Theme.positive
        : status === "paused" || status === "starting" ? Theme.caution
        : status === "error" ? Theme.negative : "transparent"
    readonly property string statusText: status === "running" ? qsTr("Running")
        : status === "paused" ? qsTr("Paused") : status === "starting" ? qsTr("Starting")
        : status === "error" ? qsTr("Error") : controller && !child ? qsTr("Stopped") : ""
    readonly property bool hovered: hover.hovered
    readonly property bool canToggle: controller !== null && !child && (running || controller.canRun)
    readonly property bool activeSelection: selected && listFocused && Window.active
    readonly property color foreground: activeSelection ? Theme.selectionText : Theme.text

    signal clicked(int modifiers)

    implicitWidth: compact ? Theme.sidebarCompactWidth : Theme.sidebarWidth
    implicitHeight: compact || railLayout ? railCell
                            : showValue ? rowHeight + secondLine.implicitHeight + valueGap : rowHeight
    // The value line sits closer to the name than to the next row: the name line gives up 4 px at
    // its foot (valueGap below the value restores them).
    readonly property int valueGap: Theme.spacingXs + 2

    Accessible.role: Accessible.ListItem
    Accessible.name: fullTitle.length > 0 ? fullTitle : title
    Accessible.description: [statusText, keyValue].filter(s => s.length > 0).join(", ")
    Accessible.selected: selected

    HoverHandler { id: hover }
    TapHandler {
        id: tap
        acceptedButtons: Qt.LeftButton
        onTapped: row.clicked(tap.point.modifiers)
    }
    ContextMenu.menu: row.contextMenu

    // Drag the row onto the workspace: left/right half = split, center = replace.
    DragHandler {
        id: dragHandler
        objectName: "rowDragHandler"
        target: null
        enabled: row.paneId.length > 0
        // The list must not take the gesture over once it is a drag.
        grabPermissions: PointerHandler.CanTakeOverFromAnything
    }
    property alias dragChip: chip
    DragChip {
        id: chip
        objectName: "rowDragChip"
        handler: dragHandler
        paneId: row.paneId
        title: row.fullTitle.length > 0 ? row.fullTitle : row.title
        iconName: row.iconName
        origin: "sidebar"
    }

    // To the right of the sidebar, never over the rows above or below.
    readonly property string tipText: compact
        ? [fullTitle.length > 0 ? fullTitle : title, statusText, keyValue].filter(t => t.length > 0).join(" — ")
        : (fullTitle.length > 0 ? fullTitle : title)
    ToolTip {
        id: tip
        objectName: "sidebarTip"
        parent: row
        x: row.width + Theme.spacingXs
        y: Math.round((row.height - height) / 2)
        visible: hover.hovered && row.tipText.length > 0
        delay: Theme.toolTipDelay
        text: runButton.visible && runButton.hovered ? runButton.Accessible.name : row.tipText
    }

    // Selection / hover background, inset like a source list.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        anchors.topMargin: 1
        anchors.bottomMargin: 1
        radius: Theme.radiusControl
        color: row.activeSelection ? Theme.selection
             : row.selected ? Theme.selectionInactive
             : row.shownBeside ? Theme.hoverFill
             : row.hovered ? Theme.hoverFill : "transparent"
        border.width: row.current && row.listFocused && !row.selected ? Theme.focusWidth : 0
        border.color: Theme.focusRing
    }

    // --- Expanded -------------------------------------------------------------------------------
    // One line: icon, name, state dot (Run / Stop in its place on hover). While the instrument runs
    // a second caption line carries its key value, from the name's left edge to the row's right edge.
    Item {
        id: expanded
        visible: !row.compact
        anchors.fill: parent
        readonly property real textLeft: row.leftEdge + Theme.iconSizeL + Theme.spacingS
        readonly property real railWidth: row.controller !== null && !row.child ? Theme.iconSize + Theme.spacingS : 0

        Icon {
            x: row.leftEdge
            y: Math.round((row.rowHeight - height) / 2)
            name: row.iconName
            size: Theme.iconSizeL
            color: row.iconColor
        }
        Text {
            id: nameText
            opacity: row.reveal
            x: expanded.textLeft
            width: row.width - x - expanded.railWidth - Theme.spacingM
            height: row.rowHeight
            text: row.title
            color: row.foreground
            font.pixelSize: Theme.fontSizeBody
            font.weight: row.selected ? Font.DemiBold : Font.Normal
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }
        Text {
            id: secondLine
            objectName: "sidebarValue"
            x: expanded.textLeft
            y: row.rowHeight - 4
            width: row.width - x - Theme.spacingM
            visible: row.showValue
            text: row.keyValue
            color: row.activeSelection ? Theme.selectionText : Theme.positive
            font.pixelSize: Theme.fontSizeCaption
            font.features: Theme.tabularFigures
            wrapMode: Text.NoWrap
        }
        // Trailing: the state dot, or Run/Stop while hovered or focused.
        Item {
            opacity: row.reveal
            x: row.width - Theme.spacingM - width
            y: Math.round((row.rowHeight - height) / 2)
            width: Theme.iconSize + 2
            height: Theme.controlHeightS
            visible: row.controller !== null && !row.child

            Rectangle {
                anchors.centerIn: parent
                visible: !runButton.visible && row.status.length > 0
                width: Theme.spacingS - 1
                height: width
                radius: width / 2
                color: row.statusColor
            }
            ToolButton {
                id: runButton
                objectName: "sidebarRun-" + row.paneId
                anchors.fill: parent
                visible: (row.hovered || (row.current && row.listFocused)) && row.canToggle
                icon.source: Theme.icon(row.running ? "stop-filled" : "play")
                icon.width: Theme.iconSize - 2
                icon.height: Theme.iconSize - 2
                icon.color: row.activeSelection ? Theme.selectionText : row.running ? Theme.stopFill : Theme.runFill
                Accessible.name: row.running ? qsTr("Stop %1").arg(row.title) : qsTr("Run %1").arg(row.title)
                onClicked: row.controller.toggle()
            }
        }
    }

    // --- Compact --------------------------------------------------------------------------------
    Item {
        visible: row.compact
        anchors.centerIn: parent
        width: Theme.iconSizeL
        height: Theme.iconSizeL
        Icon {
            anchors.centerIn: parent
            name: row.iconName
            size: Theme.iconSizeL
            color: row.iconColor
        }
        Rectangle {
            visible: row.status.length > 0
            x: parent.width - width / 2 - 1
            y: -height / 2 + 1
            width: Theme.spacingS
            height: width
            radius: width / 2
            color: row.statusColor
            border.width: Theme.borderWidth + 1
            border.color: Theme.sidebar
        }
    }
}
