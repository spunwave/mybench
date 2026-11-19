pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Templates as T
import MyBench.Framework

// One main parameter of an instrument (PicoScope-style): a Knob, and beside it the label, the value
// (click to type "2m", "500u", "1.5k"; Enter applies, Esc reverts) between − / + steppers, and an
// optional caption line ("200 kS/s · 1 001 samples"). Items declared inside go below the caption.
// Stepped: `values`, `currentIndex`, indexActivated(index); a typed value snaps to the nearest entry.
// Continuous: `from`/`to`/`value`, valueModified(value). Controlled: bind the value, apply the signal.
//     KnobField { label: qsTr("Timebase"); values: ctl.timeDivValues; currentIndex: ctl.timeDivIndex
//                 unit: "s/div"; caption: ctl.rateText; onIndexActivated: i => ctl.timeDivIndex = i }
T.Control {
    id: control

    property string label
    property string unit
    property string caption
    // The arc and pointer: the signal colour of the card it sits in, else the accent.
    property color accentColor: formHostItem && formHostItem.knobColor !== undefined ? formHostItem.knobColor : Theme.accent
    property real knobSize: 48
    // Form mode (inside a ChannelCard or any host with `formHost`): one row at the control height,
    // label column, a knob of one size, then the stepper field filling the rest.
    property bool form: false
    property var formHostItem: null
    // Knobs are always there in a form row (the layout gives every row its minimum width); only a
    // non-form field can be asked to drop it with `compact`.
    readonly property bool knobShown: form || !compact
    // A card's dense form (a dock): label column | knob | field on one control-height row.
    readonly property bool dense: form && formHostItem !== null && formHostItem.dense === true
    readonly property real formKnobSize: dense ? Theme.knobSizeHeader : Theme.knobSize
    // Width reserved for the knob, so the values of a column of fields line up when a secondary
    // field has a smaller knob (34 px in a 48 px slot).
    property real knobSlot: Math.max(knobSize, 48)
    property bool compact: false
    property bool clockwiseIncreases: true
    property int digits: 4
    property var values: []
    property var labels: []
    property int currentIndex: 0
    property int defaultIndex: -1
    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: 0          // − / + and knob keys; 0 = 1/100 of the travel
    property bool logarithmic: false
    property var defaultValue: undefined
    // Text of a value (stepped or continuous); null = labels, then Units.format(v, unit, digits).
    property var formatter: null
    property real valueWidth: 96       // width of the value text between the steppers
    property string toolTip
    property alias knob: knobItem
    default property alias content: extras.data

    readonly property bool discrete: values.length > 0
    readonly property int count: values.length
    readonly property real currentValue: discrete ? Number(values[Math.max(0, Math.min(count - 1, currentIndex))] ?? 0) : value
    readonly property string valueText: textOf(currentIndex, currentValue)
    // The widest text this field can show (the longest of a few candidates), in the value font.
    readonly property string widestText: {
        let best = valueText
        const consider = t => { if (t.length > best.length) best = t }
        if (discrete) {
            for (let i = 0; i < count; ++i)
                consider(textOf(i, Number(values[i])))
        } else {
            consider(textOf(0, from))
            consider(textOf(0, to))
        }
        return best
    }
    readonly property real stepperSize: form ? 20 : Math.round(Theme.controlHeight * 0.9)
    // The least a form field can be: its widest value and both steppers.
    readonly property real fieldMinWidth: Math.ceil(widestMetrics.advanceWidth) + 2 * stepperSize + 2 + 2 * 2
    TextMetrics {
        id: widestMetrics
        font.pixelSize: control.form ? Theme.fontSizeValue : Theme.fontSizeHeading
        font.weight: Font.DemiBold
        font.features: Theme.tabularFigures
        text: control.widestText
    }
    readonly property bool editing: input.activeFocus && input.dirty
    readonly property bool invalid: invalidFlash.running

    signal indexActivated(int index)
    signal valueModified(real value)

    function textOf(index: int, v: real): string {
        if (formatter)
            return String(formatter(v))
        if (discrete && labels.length > index && index >= 0)
            return String(labels[index])
        return Units.format(v, unit, digits)
    }
    function parseText(t: string): real {
        let v = Units.parse(t, unit)
        if (isNaN(v) && unit.length > 0)
            v = Units.parse(t, "")
        if (isNaN(v) && discrete) {
            for (let i = 0; i < count; ++i) {
                if (textOf(i, Number(values[i])).replace(/\s/g, "") === t.replace(/\s/g, ""))
                    return Number(values[i])
            }
        }
        return v
    }
    function nearestIndex(v: real): int {
        let best = -1
        let bestDistance = Infinity
        const positive = v > 0 && Number(values[0]) > 0
        for (let i = 0; i < count; ++i) {
            const e = Number(values[i])
            const d = positive && e > 0 ? Math.abs(Math.log(e / v)) : Math.abs(e - v)
            if (d < bestDistance) {
                bestDistance = d
                best = i
            }
        }
        return best
    }
    // Applies a typed text; false when it is not a number.
    function applyText(t: string): bool {
        const v = parseText(t.trim())
        if (isNaN(v)) {
            invalidFlash.restart()
            return false
        }
        if (discrete) {
            const i = nearestIndex(v)
            if (i >= 0 && i !== currentIndex)
                indexActivated(i)
        } else {
            const c = Number(Math.max(Math.min(from, to), Math.min(Math.max(from, to), v)).toPrecision(12))
            if (c !== value)
                valueModified(c)
        }
        return true
    }
    // n steps towards larger values (− / +, arrow keys in the value).
    function stepBy(n: int) {
        if (!enabled || n === 0)
            return
        knobItem.step(n, false)
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    Component.onCompleted: {
        for (let p = parent; p; p = p.parent) {
            if (p.formHost === true) {
                form = true
                formHostItem = p
                break
            }
        }
    }
    hoverEnabled: true
    Accessible.role: Accessible.Grouping
    Accessible.name: label

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: control.form ? Theme.spacingS : Theme.spacingS + 2

        Text {
            id: denseLabel
            visible: control.dense && control.label.length > 0
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: Math.round((Math.max(Theme.controlHeight, control.formKnobSize) - height) / 2)
            Layout.preferredWidth: Math.max(Theme.denseLabelWidth, implicitWidth)
            text: control.label
            color: control.enabled ? Theme.textSecondary : Theme.textDisabled
            font.pixelSize: Theme.fontSizeCaption
        }
        Item {
            visible: control.knobShown
            Layout.alignment: control.dense ? Qt.AlignTop : Qt.AlignVCenter
            Layout.preferredWidth: control.form ? control.formKnobSize : -1
            Layout.preferredHeight: control.dense ? Math.max(Theme.controlHeight, control.formKnobSize)
                                  : control.form ? Theme.knobRowHeight : -1
            implicitWidth: knobItem.implicitWidth
            implicitHeight: knobItem.implicitHeight
            Layout.fillHeight: !control.form
            Layout.leftMargin: control.form ? 0 : Math.floor((control.knobSlot - control.knobSize) / 2)
            Layout.rightMargin: control.form ? 0 : Math.ceil((control.knobSlot - control.knobSize) / 2)
        Knob {
            id: knobItem
            anchors.centerIn: parent
            enabled: control.enabled
            size: control.form ? control.formKnobSize : control.knobSize
            accentColor: control.accentColor
            clockwiseIncreases: control.clockwiseIncreases
            values: control.values
            labels: control.labels
            currentIndex: control.currentIndex
            defaultIndex: control.defaultIndex
            from: control.from
            to: control.to
            value: control.value
            stepSize: control.stepSize
            logarithmic: control.logarithmic
            defaultValue: control.defaultValue
            unit: control.unit
            valueText: control.valueText
            Accessible.name: control.label
            onIndexMoved: index => control.indexActivated(index)
            onMoved: v => control.valueModified(v)
            ToolTip.visible: false
        }
        }

        ColumnLayout {
            Layout.alignment: control.dense ? Qt.AlignTop : Qt.AlignVCenter
            Layout.topMargin: control.dense ? Math.max(0, Math.round((control.formKnobSize - Theme.controlHeight) / 2)) : 0
            Layout.fillWidth: true
            spacing: control.form ? Theme.spacingXs / 2 : 3

            Text {
                id: labelText
                visible: control.label.length > 0 && !control.dense
                Layout.fillWidth: true
                text: control.label
                color: control.enabled ? Theme.textSecondary : Theme.textDisabled
                font.pixelSize: Theme.fontSizeCaption
                elide: Text.ElideRight
            }

            Rectangle {
                id: frame
                Layout.preferredWidth: control.form ? -1 : control.valueWidth + 2 * stepperWidth
                Layout.fillWidth: control.form
                Layout.minimumWidth: control.form ? control.fieldMinWidth : 0
                Layout.preferredHeight: Theme.controlHeight
                readonly property real stepperWidth: control.stepperSize
                radius: Theme.radiusControl
                color: Theme.base
                border.width: 1
                border.color: control.invalid ? Theme.negative
                            : input.activeFocus ? Theme.accent
                            : frameHover.hovered ? Theme.knobRingHover : Theme.controlBorder
                clip: true

                HoverHandler { id: frameHover }

                component Stepper: T.AbstractButton {
                    id: stepper
                    property string glyph
                    width: frame.stepperWidth
                    height: frame.height
                    autoRepeat: true
                    focusPolicy: Qt.NoFocus
                    hoverEnabled: true
                    enabled: control.enabled
                    background: Rectangle {
                        color: stepper.pressed ? Theme.pressedFill : stepper.hovered ? Theme.hoverFill : "transparent"
                    }
                    contentItem: Icon {
                        name: stepper.glyph
                        size: control.form ? 12 : 14
                        color: !stepper.enabled ? Theme.textDisabled : stepper.hovered ? Theme.text : Theme.textSecondary
                    }
                }

                Stepper {
                    id: minus
                    objectName: "minus"
                    x: 0
                    glyph: "minus"
                    Accessible.name: qsTr("Decrease %1").arg(control.label)
                    onClicked: control.stepBy(-1)
                }
                Rectangle {
                    x: minus.width
                    width: 1
                    height: parent.height
                    color: Theme.separator
                }
                Stepper {
                    id: plus
                    objectName: "plus"
                    x: frame.width - width
                    glyph: "plus"
                    Accessible.name: qsTr("Increase %1").arg(control.label)
                    onClicked: control.stepBy(1)
                }
                Rectangle {
                    x: plus.x - 1
                    width: 1
                    height: parent.height
                    color: Theme.separator
                }

                TextInput {
                    id: input
                    objectName: "valueInput"
                    property bool dirty: false
                    x: minus.width + 1
                    width: frame.width - 2 * minus.width - 2
                    height: frame.height
                    leftPadding: 2
                    rightPadding: 2
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    enabled: control.enabled
                    color: control.enabled ? Theme.text : Theme.textDisabled
                    selectionColor: Theme.selection
                    selectedTextColor: Theme.selectionText
                    selectByMouse: true
                    font.pixelSize: control.form ? Theme.fontSizeValue : Theme.fontSizeHeading
                    font.weight: Font.DemiBold
                    font.features: Theme.tabularFigures
                    text: control.valueText
                    Accessible.role: Accessible.EditableText
                    Accessible.name: control.label
                    Accessible.description: control.valueText

                    function revert() {
                        dirty = false
                        text = Qt.binding(() => control.valueText)
                    }
                    function commit() {
                        if (!dirty)
                            return
                        control.applyText(text)
                        revert()
                    }
                    onTextEdited: dirty = true
                    onAccepted: {
                        commit()
                        selectAll()
                    }
                    onActiveFocusChanged: {
                        if (activeFocus)
                            Qt.callLater(selectAll)
                        else
                            commit()
                    }
                    Keys.onEscapePressed: event => {
                        if (dirty) {
                            revert()
                            event.accepted = true
                        } else {
                            event.accepted = false
                        }
                    }
                    Keys.onUpPressed: { revert(); control.stepBy(1) }
                    Keys.onDownPressed: { revert(); control.stepBy(-1) }
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_PageUp) { revert(); control.stepBy(control.discrete ? 3 : 10); event.accepted = true }
                        else if (event.key === Qt.Key_PageDown) { revert(); control.stepBy(control.discrete ? -3 : -10); event.accepted = true }
                    }
                }
                SequentialAnimation {
                    id: invalidFlash
                    PauseAnimation { duration: 900 }
                }
            }

            Text {
                visible: control.caption.length > 0
                Layout.fillWidth: true
                Layout.maximumWidth: frame.width + Theme.spacingL
                text: control.caption
                color: control.enabled ? Theme.textTertiary : Theme.textDisabled
                font.pixelSize: Theme.fontSizeCaption
                font.features: Theme.tabularFigures
                elide: Text.ElideRight
                maximumLineCount: 1
            }

            ColumnLayout {
                id: extras
                visible: children.length > 0
                Layout.fillWidth: true
                spacing: Theme.spacingXs
            }
        }
    }

    ToolTip.visible: toolTip.length > 0 && hovered && !knobItem.dragging
    ToolTip.text: toolTip
}
