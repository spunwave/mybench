import QtQuick
import QtQuick.Layouts
import MyBench.Framework

// A primary parameter in the pane header: a Knob (Theme.knobSizeHeader) directly at the left of its
// − value + field, on one header row, no caption and no label above. An optional short inline label
// ("Start") goes at the far left, only where the value does not identify itself. `toolTip` names the
// parameter (also its accessible name). Stepped (`values`, `currentIndex`, indexActivated) or
// continuous (`from`, `to`, `value`, valueModified), like KnobField; the field fits the widest value.
//     HeaderField { values: ctl.timeDivValues; currentIndex: ctl.timeDivIndex
//                   toolTip: qsTr("Timebase"); onIndexActivated: i => ctl.timeDivIndex = i }
Row {
    id: root

    property string label
    property string toolTip
    property alias unit: field.unit
    property alias values: field.values
    property alias labels: field.labels
    property alias currentIndex: field.currentIndex
    property alias defaultIndex: field.defaultIndex
    property alias from: field.from
    property alias to: field.to
    property alias value: field.value
    property alias stepSize: field.stepSize
    property alias logarithmic: field.logarithmic
    property alias defaultValue: field.defaultValue
    property alias digits: field.digits
    property alias formatter: field.formatter
    property alias accentColor: field.accentColor     // the arc: a signal the knob drives, else the accent
    property alias field: field

    signal indexActivated(int index)
    signal valueModified(real value)

    // The widest text this parameter can show (a sample of a continuous range), and the room the
    // field gives it: the stepper buttons are KnobField's own; the text has 4 px of padding each
    // side, and the rest is slack for the tabular figures.
    function textsToMeasure(): var {
        const texts = []
        if (field.discrete) {
            for (let i = 0; i < field.count; ++i)
                texts.push(field.textOf(i, Number(field.values[i])))
        } else {
            const lo = field.from
            const hi = field.to
            const steps = 24
            for (let k = 0; k <= steps; ++k) {
                const t = k / steps
                const v = field.logarithmic && lo > 0 && hi > 0 ? lo * Math.pow(hi / lo, t) : lo + (hi - lo) * t
                texts.push(field.textOf(-1, v))
            }
        }
        return texts
    }
    function widestText(): real {
        let widest = 0
        for (const text of textsToMeasure())
            widest = Math.max(widest, Math.ceil(metrics.advanceWidth(text)))
        return widest
    }
    readonly property string rangeText: {
        const texts = textsToMeasure()
        return texts.length > 1 ? " (" + texts[0] + " … " + texts[texts.length - 1] + ")" : ""
    }

    spacing: Theme.spacingXs
    Accessible.role: Accessible.Grouping
    Accessible.name: toolTip.length > 0 ? toolTip : label

    FontMetrics {
        id: metrics
        font.pixelSize: Theme.fontSizeValue
        font.weight: Font.DemiBold
    }

    Text {
        visible: root.label.length > 0
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: root.enabled ? Theme.textSecondary : Theme.textDisabled
        font.pixelSize: Theme.fontSizeCaption
    }
    KnobField {
        id: field
        anchors.verticalCenter: parent.verticalCenter
        objectName: root.objectName
        knobSize: Theme.knobSizeHeader
        knobSlot: Theme.knobSizeHeader
        valueWidth: root.widestText() + 12
        toolTip: root.toolTip + root.rangeText
        Accessible.name: root.Accessible.name
        onIndexActivated: index => root.indexActivated(index)
        onValueModified: v => root.valueModified(v)
    }
}
