pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// The segment table: segments and their components, one row each, with the structure actions (New
// Segment / Component, Move, Clear, Select All) above it.
ColumnLayout {
    id: root

    required property WaveformEditor editor
    readonly property alias list: segmentList
    // Edit-menu actions the owner implements (they need its dialogs).
    signal clearRequested
    signal saveAsRequested
    signal closeDocumentRequested

    spacing: 0
    // Draw mode grays the structure controls (ELVISmx) until Draw is released.
    enabled: !root.editor.drawMode

    // The height that shows every row up to `maxRows` (then the list scrolls): the actions row, a hairline
    // and the rows.
    property int maxRows: 5
    readonly property real rowHeight: 24
    readonly property real fitHeight: actions.implicitHeight + 2 + 1 + rowHeight * Math.min(maxRows, Math.max(1, segmentList.count))
    // The title (not in a card, which has its own) and the structure actions; wraps when narrow.
    property bool showTitle: true
    Flow {
        id: actions
        Layout.fillWidth: true
        Layout.preferredHeight: implicitHeight + 2
        spacing: 2
        Row {
            visible: root.showTitle
            height: Theme.controlHeightS
            spacing: Theme.spacingXs
            rightPadding: Theme.spacingXs
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: qsTr("Segments")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.weight: Font.DemiBold
            }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.editor.segmentCount
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
                font.features: Theme.tabularFigures
            }
        }
        IconButton { objectName: "editorNewSegment"; iconName: "plus"; size: Theme.controlHeightS; toolTip: qsTr("New Segment"); onClicked: root.editor.newSegment() }
        IconButton { objectName: "editorNewComponent"; iconName: "wave-sine"; size: Theme.controlHeightS; toolTip: qsTr("New Component")
                     enabled: root.editor.selectionKind !== 3; onClicked: root.editor.newComponent() }
        IconButton { iconName: "chevron-up"; size: Theme.controlHeightS; toolTip: qsTr("Move Up"); shortcutText: KeyText.of("Alt+↑"); onClicked: root.editor.moveSelection(-1) }
        IconButton { iconName: "chevron-down"; size: Theme.controlHeightS; toolTip: qsTr("Move Down"); shortcutText: KeyText.of("Alt+↓"); onClicked: root.editor.moveSelection(1) }
        IconButton { iconName: "trash"; size: Theme.controlHeightS; toolTip: qsTr("Clear"); shortcutText: KeyText.of("Del"); onClicked: root.clearRequested() }
        IconButton { iconName: "grid"; size: Theme.controlHeightS; toolTip: qsTr("Select All"); shortcutText: KeyText.of("Ctrl+A"); onClicked: root.editor.selectAll() }
    }
    Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.separator }
    Item {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: root.rowHeight

        ListView {
            id: segmentList
            anchors.fill: parent
            clip: true
            focus: true
            model: root.editor.rows
            currentIndex: root.editor.currentRow
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            Keys.onUpPressed: event => {
                if (event.modifiers & Qt.AltModifier) root.editor.moveSelection(-1)
                else root.editor.currentRow = Math.max(0, root.editor.currentRow - 1)
            }
            Keys.onDownPressed: event => {
                if (event.modifiers & Qt.AltModifier) root.editor.moveSelection(1)
                else root.editor.currentRow = Math.min(count - 1, root.editor.currentRow + 1)
            }
            property int dragFrom: -1
            delegate: Rectangle {
                id: rowItem
                required property int index
                required property string text
                required property string detail
                required property int kind
                required property bool warning
                required property string iconName
                readonly property bool selected: index === root.editor.currentRow || root.editor.selectionKind === 3
                width: ListView.view.width
                height: root.rowHeight
                color: selected ? Theme.accentMuted : rowMouse.containsMouse ? Theme.hoverFill : "transparent"
                border.width: segmentList.dragFrom >= 0 && rowMouse.containsMouse && segmentList.dragFrom !== index ? 1 : 0
                border.color: Theme.accent
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: rowItem.kind === 0 ? 8 : 26
                    anchors.rightMargin: 8
                    spacing: 6
                    Icon {
                        name: rowItem.iconName
                        size: Theme.iconSize
                        color: rowItem.selected ? Theme.text : Theme.textSecondary
                    }
                    Text {
                        Layout.fillWidth: true
                        text: rowItem.text
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeBody
                        font.weight: rowItem.kind === 0 ? Font.DemiBold : Font.Normal
                        elide: Text.ElideRight
                    }
                    Icon {
                        visible: rowItem.warning
                        name: "warning"
                        size: Theme.iconSizeS
                        color: Theme.caution
                    }
                    Text {
                        text: rowItem.detail
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeCaption
                        font.features: Theme.tabularFigures
                    }
                }
                MouseArea {
                    id: rowMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onPressed: mouse => {
                        segmentList.forceActiveFocus()
                        root.editor.currentRow = rowItem.index
                        if (mouse.button === Qt.LeftButton)
                            segmentList.dragFrom = rowItem.index
                    }
                    onReleased: mouse => {
                        const p = mapToItem(segmentList.contentItem, mouse.x, mouse.y)
                        const to = segmentList.indexAt(p.x, p.y)
                        if (segmentList.dragFrom >= 0 && to >= 0 && to !== segmentList.dragFrom)
                            root.editor.moveRow(segmentList.dragFrom, to)
                        segmentList.dragFrom = -1
                    }
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            editMenu.popup()
                    }
                }
            }
        }
    }
    // Edit actions of the selection (the keys work while the editor has the focus).
    Menu {
        id: editMenu
        MenuItem { text: qsTr("Cut"); onTriggered: root.editor.cut() }
        MenuItem { text: qsTr("Copy"); onTriggered: root.editor.copy() }
        MenuItem { text: qsTr("Paste"); enabled: root.editor.canPaste; onTriggered: root.editor.paste() }
        MenuItem { text: qsTr("Clear"); onTriggered: root.clearRequested() }
        MenuSeparator {}
        MenuItem { text: qsTr("Select All"); onTriggered: root.editor.selectAll() }
        MenuItem { text: qsTr("Save As…"); onTriggered: root.saveAsRequested() }
        MenuItem { text: qsTr("Close Document"); onTriggered: root.closeDocumentRequested() }
    }
}
