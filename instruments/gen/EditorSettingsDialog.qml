pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Controls

// Edit > Settings… of the Waveform Editor: plot, selection, grid, cursor and plot-area colors
// (transparent = follow the theme), Max Points, Animate Graphs, Show Cursors. Saved as user
// preferences; OK applies, Cancel reverts.
Dialog {
    id: root

    required property WaveformEditor editor

    // Working copy (applied on OK).
    property color plotColor
    property color selectionColor
    property color gridColor
    property color cursorColor
    property color backgroundColor
    property bool animate: false
    property bool cursors: false

    function load() {
        plotColor = editor.plotColor
        selectionColor = editor.selectionColor
        gridColor = editor.gridColor
        cursorColor = editor.cursorColor
        backgroundColor = editor.backgroundColor
        animate = editor.animateGraphs
        cursors = editor.showCursors
        maxPoints.value = editor.maxPoints
    }

    title: qsTr("Waveform Editor Settings")
    anchors.centerIn: Overlay.overlay
    modal: true
    width: 420
    onOpened: load()
    onAccepted: {
        editor.plotColor = plotColor
        editor.selectionColor = selectionColor
        editor.gridColor = gridColor
        editor.cursorColor = cursorColor
        editor.backgroundColor = backgroundColor
        editor.maxPoints = maxPoints.value
        editor.animateGraphs = animate
        editor.showCursors = cursors
    }
    function restoreDefaults() {
        editor.resetPreferences()
        load()
    }

    component ColorRow: FormRow {
        id: colorRow
        required property color value
        required property color themeColor
        signal picked(color c)
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            Rectangle {
                implicitWidth: 44
                implicitHeight: 22
                radius: Theme.radiusControl
                color: colorRow.value.a > 0 ? colorRow.value : colorRow.themeColor
                border.width: 1
                border.color: Theme.controlBorder
                ToolTip.visible: swatchHover.hovered
                ToolTip.text: colorRow.value.a > 0 ? colorRow.value.toString() : qsTr("Theme color")
                HoverHandler { id: swatchHover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: picker.open() }
            }
            Item { Layout.fillWidth: true }
            ActionButton {
                text: qsTr("Theme")
                compact: true
                tone: "ghost"
                enabled: colorRow.value.a > 0
                toolTip: qsTr("Follow theme")
                onClicked: colorRow.picked("transparent")
            }
        }
        ColorDialog {
            id: picker
            title: colorRow.label
            selectedColor: colorRow.value.a > 0 ? colorRow.value : colorRow.themeColor
            onAccepted: colorRow.picked(selectedColor)
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        ColorRow {
            label: qsTr("Plot")
            value: root.plotColor
            themeColor: Theme.accent
            onPicked: c => root.plotColor = c
        }
        ColorRow {
            label: qsTr("Selection")
            value: root.selectionColor
            themeColor: Theme.accent
            onPicked: c => root.selectionColor = c
        }
        ColorRow {
            label: qsTr("Grid")
            value: root.gridColor
            themeColor: Theme.plotGridMajor
            onPicked: c => root.gridColor = c
        }
        ColorRow {
            label: qsTr("Cursor")
            value: root.cursorColor
            themeColor: Theme.cursor1
            onPicked: c => root.cursorColor = c
        }
        ColorRow {
            label: qsTr("Background")
            value: root.backgroundColor
            themeColor: Theme.display
            onPicked: c => root.backgroundColor = c
        }
        FormRow {
            label: qsTr("Max points")
            hint: qsTr("Sample limit")
            SiField {
                id: maxPoints
                Layout.fillWidth: true
                engineering: false
                decimals: 0
                stepSize: 100000
                from: 1000
                to: 10000000
                toolTip: qsTr("1 000 to 10 000 000")
                onValueModified: v => value = v
            }
        }
        FormRow {
            label: qsTr("Animate")
            hint: qsTr("Animate the view")
            ToggleSwitch {
                checked: root.animate
                onToggled: root.animate = checked
            }
        }
        FormRow {
            label: qsTr("Show cursors")
            ToggleSwitch {
                checked: root.cursors
                onToggled: root.cursors = checked
            }
        }
    }

    footer: RowLayout {
        spacing: Theme.spacingS
        ActionButton {
            Layout.leftMargin: Theme.spacingL
            Layout.bottomMargin: Theme.spacingL
            text: qsTr("Defaults")
            onClicked: root.restoreDefaults()
        }
        Item { Layout.fillWidth: true }
        ActionButton {
            Layout.bottomMargin: Theme.spacingL
            text: qsTr("Cancel")
            onClicked: root.reject()
        }
        ActionButton {
            Layout.bottomMargin: Theme.spacingL
            Layout.rightMargin: Theme.spacingL
            text: qsTr("OK")
            tone: "accent"
            onClicked: root.accept()
        }
    }
}
