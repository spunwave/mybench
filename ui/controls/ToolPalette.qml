pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T

// A grid of instrument tools: every tool is an icon with a tooltip, with its label under it when
// the cell is wide enough; the open tool is drawn pressed (accent soft fill). `vertical` (set by an
// InstrumentColumn in band form) makes it one column of icon-only buttons. A click emits activated(id),
// also for the open tool: the owner toggles its ToolPanel (currentId = currentId === id ? "" : id).
//     ToolPalette { model: [{ id: "measure", text: qsTr("Measure"), icon: "ruler" }, ...]
//                   currentId: pane.tool; onActivated: id => pane.tool = pane.tool === id ? "" : id }
Item {
    id: palette

    property var model: []
    property string currentId
    property int columns: 4
    property real cellHeight: Theme.toolCellHeight
    property real spacing: 2
    property bool vertical: false
    // Vertical form: the tallest the strip may be; more tools than fit wrap into further columns
    // (0 = no limit, one column).
    property real verticalLimit: 0
    // The labels show when a cell is at least this wide (and the model gives a text).
    property real labelMinWidth: 56

    signal activated(string id)

    property real verticalCell: Theme.controlHeight + 4
    readonly property int toolCount: model ? (model.length ?? model.count ?? 0) : 0
    readonly property int verticalRows: verticalLimit > 0
        ? Math.max(1, Math.min(toolCount, Math.floor((verticalLimit + spacing) / (verticalCell + spacing)))) : Math.max(1, toolCount)
    readonly property int verticalColumns: Math.max(1, Math.ceil(toolCount / verticalRows))
    implicitWidth: vertical ? verticalColumns * verticalCell + (verticalColumns - 1) * spacing
                            : columns * 60 + (columns - 1) * spacing
    implicitHeight: grid.implicitHeight
    Accessible.role: Accessible.ToolBar

    Grid {
        id: grid
        width: parent.width
        flow: palette.vertical ? Grid.TopToBottom : Grid.LeftToRight
        // Never more columns than tools: three tools share the width in three cells, so a label such
        // as "Connections" has the room of a third of it.
        readonly property int usedColumns: Math.max(1, Math.min(palette.columns, palette.toolCount))
        // One dimension is given, the other follows the item count (-1): a Grid given both warns
        // while the model and the counts update one after the other.
        rows: palette.vertical ? palette.verticalRows : -1
        columns: palette.vertical ? -1 : usedColumns
        spacing: palette.spacing
        readonly property real cellWidth: (width - (usedColumns - 1) * spacing) / usedColumns

        Repeater {
            model: palette.model
            delegate: T.AbstractButton {
                id: tool
                required property var modelData
                required property int index
                readonly property string toolId: String(modelData.id ?? "")
                readonly property bool current: toolId.length > 0 && toolId === palette.currentId
                objectName: "tool_" + toolId
                width: palette.vertical ? palette.verticalCell : grid.cellWidth
                height: palette.vertical ? palette.verticalCell : palette.cellHeight
                readonly property bool showLabel: !palette.vertical && text.length > 0 && width >= palette.labelMinWidth
                hoverEnabled: true
                focusPolicy: Qt.StrongFocus
                enabled: modelData.enabled ?? true
                text: String(modelData.text ?? "")
                checkable: false
                checked: current
                Accessible.role: Accessible.Button
                Accessible.name: text.length > 0 ? text : tipText
                Accessible.checkable: true
                Accessible.checked: current
                onClicked: palette.activated(toolId)

                readonly property color ink: !enabled ? Theme.textDisabled
                                           : current ? Theme.accent
                                           : hovered ? Theme.text : Theme.textSecondary

                background: Rectangle {
                    radius: Theme.radiusControl
                    color: tool.current ? (tool.pressed ? Theme.alpha(Theme.accent, Theme.dark ? 0.28 : 0.18) : Theme.accentSoft)
                         : tool.pressed ? Theme.pressedFill : tool.hovered ? Theme.hoverFill : "transparent"
                    border.width: tool.current ? 1 : 0
                    border.color: Theme.accent
                    FocusRing { shown: tool.visualFocus }
                }
                contentItem: Item {
                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Icon {
                            anchors.horizontalCenter: parent.horizontalCenter
                            name: String(tool.modelData.icon ?? "")
                            size: tool.showLabel ? Theme.iconSizeXL : Theme.iconSizeL
                            color: tool.ink
                        }
                        Text {
                            visible: tool.showLabel
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: Math.min(implicitWidth, tool.width - 2)
                            text: tool.text
                            color: tool.ink
                            font.pixelSize: Theme.fontSizeCaption
                            font.weight: tool.current ? Font.DemiBold : Font.Normal
                            elide: Text.ElideRight
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }
                // Every tool has a tooltip: its description, else its name.
                readonly property string tipText: String(modelData.toolTip ?? "").length > 0 ? String(modelData.toolTip) : String(modelData.text ?? "")
                ToolTip.visible: hovered && tipText.length > 0
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: tipText
            }
        }
    }
}
