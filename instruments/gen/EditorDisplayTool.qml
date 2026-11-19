import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// Display tool of the Waveform Editor (floating ToolPanel): View, X Axis, the Plot Style legend (plot visible, style,
// width, step interpolation, the full Trace style dialog, Copy data) and cursors.
ColumnLayout {
    id: root

    required property WaveformEditor editor
    signal traceStyleRequested()

    spacing: Theme.spacingS

    FormRow {
        SegmentedControl {
            objectName: "editorViewChoice"
            Layout.fillWidth: true
            stretch: true
            compact: true
            enabled: !root.editor.drawMode
            model: [ { text: qsTr("Waveform"), toolTip: qsTr("The whole waveform") },
                     { text: qsTr("Segment"), toolTip: qsTr("The selected segment alone") },
                     { text: qsTr("Component"), toolTip: qsTr("The selected component alone") } ]
            currentIndex: root.editor.view
            onActivated: index => root.editor.view = index
        }
    }
    FormRow {
        label: qsTr("X axis")
        SegmentedControl {
            objectName: "editorAxisChoice"
            Layout.fillWidth: true
            stretch: true
            compact: true
            enabled: !root.editor.drawMode
            model: [ { text: qsTr("Time"), toolTip: qsTr("Amplitude against time") },
                     { text: qsTr("Frequency"), toolTip: qsTr("Spectrum (dBV rms)") } ]
            currentIndex: root.editor.xAxis
            onActivated: index => root.editor.xAxis = index
        }
    }
    FormRow {
        label: qsTr("Style")
        SegmentedControl {
            objectName: "editorPlotStyleChoice"
            Layout.fillWidth: true
            stretch: true
            compact: true
            model: [ { text: qsTr("Line") }, { text: qsTr("Both"), toolTip: qsTr("Line and points") }, { text: qsTr("Points") } ]
            currentIndex: root.editor.plotStyle
            onActivated: index => root.editor.plotStyle = index
        }
    }
    FormRow {
        label: qsTr("Width")
        SiField {
            Layout.fillWidth: true
            engineering: false
            decimals: 1
            stepSize: 0.5
            from: 1
            to: 5
            unit: "px"
            toolTip: qsTr("Line width")
            value: root.editor.lineWidth
            onValueModified: v => root.editor.lineWidth = v
        }
    }
    FormRow {
        label: qsTr("Step")
        hint: qsTr("Hold samples")
        ToggleSwitch {
            checked: root.editor.stepPlot
            onToggled: root.editor.stepPlot = checked
        }
    }
    FormRow {
        label: qsTr("Cursors")
        hint: qsTr("Cursors")
        ToggleSwitch {
            checked: root.editor.showCursors
            onToggled: root.editor.showCursors = checked
        }
    }
    FormRow {
        label: qsTr("Plot")
        hint: qsTr("Show")
        ToggleSwitch {
            checked: root.editor.plotVisible
            onToggled: root.editor.plotVisible = checked
        }
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        ActionButton {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: qsTr("Trace Style…")
            compact: true
            toolTip: qsTr("Trace Style")
            onClicked: root.traceStyleRequested()
        }
        ActionButton {
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            text: qsTr("Copy Data")
            iconName: "copy"
            compact: true
            toolTip: qsTr("Copy Data")
            onClicked: root.editor.copyData()
        }
    }
}
