pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// Waveform Editor document section (right column): the sample rate as a knob field, the unit
// system and the live update of the channel the waveform was sent to.
ChannelCard {
    id: root

    required property GenController controller
    required property WaveformEditor editor

    objectName: "editorDocumentCard"
    title: editor.windowTitle
    checkable: false

    KnobField {
        id: rateKnob
        objectName: "documentRateField"
        Layout.fillWidth: true
        label: qsTr("Rate")
        // Samples per second in the document's Units (1.0 ... 1 000 000.0).
        unit: root.editor.rateUnit
        digits: 7
        from: 1
        to: 1000000
        logarithmic: true
        toolTip: qsTr("Sample rate (1 to 1 000 000 %1)").arg(root.editor.rateUnit)
        value: root.editor.sampleRate / root.editor.displayScale
        onValueModified: v => root.editor.sampleRate = (rateKnob.knob.dragging ? Number(v.toPrecision(3)) : Math.round(v * 10) / 10)
                                                       * root.editor.displayScale
    }
    FormRow {
        label: qsTr("Units")
        hint: qsTr("Units")
        SegmentedControl {
            objectName: "documentUnits"
            Layout.fillWidth: true
            stretch: true
            compact: true
            // Switching keeps the numbers and changes their meaning (10 s becomes 10 ms), as in
            // ELVISmx; undoable.
            model: [ { text: "Hz", toolTip: qsTr("Hz · s · S/s") }, { text: "kHz", toolTip: qsTr("kHz · ms · kS/s") },
                     { text: "MHz", toolTip: qsTr("MHz · µs · MS/s") } ]
            currentIndex: root.editor.units
            onActivated: index => root.editor.units = index
        }
    }
    FormRow {
        label: qsTr("Live update")
        hint: root.editor.linkedChannel >= 0 ? qsTr("Edits reach the channel while it plays")
                                             : qsTr("Not sent yet")
        ToggleSwitch {
            enabled: root.editor.linkedChannel >= 0
            text: root.editor.linkedChannel >= 0 ? root.controller.channel(root.editor.linkedChannel).name : ""
            checked: root.editor.liveUpdate
            onToggled: root.editor.liveUpdate = checked
        }
    }
}
