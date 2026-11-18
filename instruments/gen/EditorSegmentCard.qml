pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// Parameters of the selected segment or component: segment Name/Duration/Gain; component Function
// (operator), type (Library / Expression / Sketch) and its parameters; Select All summary.
ChannelCard {
    id: root

    required property WaveformEditor editor
    readonly property int kind: editor.selectionKind   // 1 segment, 2 component, 3 all
    readonly property int type: editor.componentType   // 0 library, 1 expression, 2 sketch

    title: kind === 3 ? qsTr("Whole Waveform")
         : kind === 2 ? qsTr("Segment %1 · Component %2").arg(editor.segmentIndex + 1).arg(editor.componentIndex + 1)
         : qsTr("Segment %1").arg(editor.segmentIndex + 1)
    objectName: "editorSegmentCard"
    checkable: false
    // Library function picked (the picture of the selected component).
    readonly property int libraryIndex: kind === 2 && type === 0 ? editor.libraryFunction : -1

    // --- Segment ---------------------------------------------------------------------------------
    FormRow {
        visible: root.kind === 1
        label: qsTr("Name")
        TextField {
            Layout.fillWidth: true
            text: root.editor.segmentName
            placeholderText: qsTr("Name")
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Segment name")
            onEditingFinished: if (text !== root.editor.segmentName) root.editor.segmentName = text
        }
    }
    KnobField {
        id: durationKnob
        visible: root.kind === 1
        Layout.fillWidth: true
        objectName: "segmentDurationField"
        label: qsTr("Duration")
        // In the document's time unit (s, ms or µs).
        unit: root.editor.timeUnit
        digits: 5
        from: 0.0001
        to: 100000
        logarithmic: true
        toolTip: qsTr("Duration (0.0001 to 100 000 %1)").arg(root.editor.timeUnit)
        value: root.editor.segmentDuration * root.editor.displayScale
        onValueModified: v => root.editor.segmentDuration = (durationKnob.knob.dragging ? Number(v.toPrecision(3)) : v) / root.editor.displayScale
    }
    KnobField {
        visible: root.kind === 1
        Layout.fillWidth: true
        objectName: "segmentGainField"
        label: qsTr("Gain")
        digits: 4
        from: -10
        to: 10
        stepSize: 0.1
        defaultValue: 1
        toolTip: qsTr("Segment gain")
        value: root.editor.segmentGain
        onValueModified: v => root.editor.segmentGain = v
    }

    // --- Component --------------------------------------------------------------------------------
    // Function pictures: the common library functions, a formula or a sketch (Functions tool:
    // the whole library of 21).
    GridLayout {
        objectName: "editorFunctionPictures"
        visible: root.kind === 2
        enabled: !root.editor.drawMode
        Layout.fillWidth: true
        columns: 4
        columnSpacing: 3
        rowSpacing: 3
        Repeater {
            model: [
                { id: "Sine", text: qsTr("Sine"), icon: "wave-sine", type: 0, fn: 1 },
                { id: "Square", text: qsTr("Square"), icon: "wave-square", type: 0, fn: 2 },
                { id: "Triangle", text: qsTr("Tri"), icon: "wave-triangle", type: 0, fn: 3 },
                { id: "Ramp", text: qsTr("Ramp"), icon: "wave-sawtooth", type: 0, fn: 4 },
                { id: "DC", text: qsTr("DC"), icon: "wave-dc", type: 0, fn: 0 },
                { id: "Noise", text: qsTr("Noise"), icon: "wave-noise", type: 0, fn: 5 },
                { id: "Formula", text: qsTr("f(x)"), icon: "edit", type: 1, fn: -1 },
                { id: "Sketch", text: qsTr("Sketch"), icon: "wave-arbitrary", type: 2, fn: -1 }
            ]
            delegate: PictureButton {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitWidth: 40
                leftPadding: 2
                rightPadding: 2
                objectName: "fn" + modelData.id
                text: modelData.text
                iconName: modelData.icon
                checked: root.type === modelData.type && (modelData.fn < 0 || root.libraryIndex === modelData.fn)
                ToolTip.visible: hovered
                ToolTip.text: modelData.type === 1 ? qsTr("Formula of x") : modelData.type === 2 ? qsTr("Sketch")
                              : root.editor.functionNames[modelData.fn] ?? ""
                onClicked: {
                    if (modelData.type === 0)
                        root.editor.libraryFunction = modelData.fn
                    root.editor.componentType = modelData.type
                }
            }
        }
    }
    FormRow {
        visible: root.kind === 2
        label: qsTr("Combine")
        disabled: !root.editor.operatorEnabled
        SegmentedControl {
            objectName: "componentOperator"
            Layout.fillWidth: true
            stretch: true
            compact: true
            enabled: root.editor.operatorEnabled
            model: [ { text: "+", toolTip: qsTr("Add") }, { text: "−", toolTip: qsTr("Subtract") },
                     { text: "×", toolTip: qsTr("Multiply") }, { text: "/", toolTip: qsTr("Divide") },
                     { text: "FM", toolTip: qsTr("Frequency modulation") } ]
            currentIndex: root.editor.componentOperator
            onActivated: index => root.editor.componentOperator = index
        }
    }

    GridLayout {
        visible: root.kind === 2 && root.type === 0
        Layout.fillWidth: true
        columns: 1
        columnSpacing: Theme.spacingS
        rowSpacing: Theme.spacingXs
        Repeater {
            model: root.kind === 2 && root.type === 0 ? root.editor.params : []
            delegate: KnobField {
                id: paramField
                required property var modelData
                Layout.fillWidth: true
                objectName: "param" + modelData.index
                label: modelData.label
                unit: modelData.unit
                caption: modelData.alias ? qsTr("Aliasing") : ""
                accentColor: modelData.alias ? Theme.caution : Theme.accent
                digits: 5
                from: modelData.min
                to: modelData.max
                stepSize: modelData.stepSize
                toolTip: modelData.alias ? qsTr("%1 · aliasing").arg(modelData.label) : modelData.label
                value: modelData.value
                onValueModified: v => root.editor.setParam(paramField.modelData.index, v)
            }
        }
        FormRow {
            visible: root.editor.hasSeed
            label: qsTr("Seed")
            hint: qsTr("Noise seed (0: random each render)")
            SiField {
                Layout.fillWidth: true
                engineering: false
                decimals: 0
                stepSize: 1
                from: 0
                to: 2147483647
                value: root.editor.seed
                onValueModified: v => root.editor.seed = v
            }
        }
    }

    // Expression
    FormRow {
        visible: root.kind === 2 && root.type === 1
        label: qsTr("f(x) =")
        TextField {
            id: expressionField
            Layout.fillWidth: true
            font.family: Theme.monoFamily
            text: root.editor.expression
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Formula of x; the preview and the error follow the typing.\nx, pi, e, + − * / ^, abs acos asin atan ceil cos cosh exp floor ln log max min mod sign sin sinh sqrt tan tanh")
            // Applied while typing (one undo step), so the error text and the preview follow.
            onTextEdited: root.editor.expression = text
        }
    }
    Text {
        visible: root.kind === 2 && root.type === 1 && root.editor.expressionError.length > 0
        Layout.fillWidth: true
        text: root.editor.expressionError
        color: Theme.negative
        font.pixelSize: Theme.fontSizeS
        wrapMode: Text.WordWrap
    }
    FormRow {
        visible: root.kind === 2 && root.type === 1
        label: qsTr("From x")
        SiField { Layout.fillWidth: true; engineering: false; decimals: 4; stepSize: 0.1
                  toolTip: qsTr("x at cycle start")
                  value: root.editor.expressionFrom; onValueModified: v => root.editor.expressionFrom = v }
    }
    FormRow {
        visible: root.kind === 2 && root.type === 1
        label: qsTr("To x")
        SiField { Layout.fillWidth: true; engineering: false; decimals: 4; stepSize: 0.1
                  toolTip: qsTr("x at cycle end")
                  value: root.editor.expressionTo; onValueModified: v => root.editor.expressionTo = v }
    }

    // Sketch
    FormRow {
        visible: root.kind === 2 && root.type === 2
        label: qsTr("Name")
        TextField {
            Layout.fillWidth: true
            text: root.editor.sketchName
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Sketch name")
            onEditingFinished: if (text !== root.editor.sketchName) root.editor.sketchName = text
        }
    }
    KnobField {
        visible: root.kind === 2 && root.type === 2
        Layout.fillWidth: true
        objectName: "sketchSamplesField"
        label: qsTr("Samples")
        digits: 7
        from: 2
        to: 1000000
        stepSize: 1
        logarithmic: true
        toolTip: qsTr("Values per cycle (2 to 1 000 000)")
        value: root.editor.sketchSamples
        onValueModified: v => root.editor.sketchSamples = Math.round(v)
    }
    // Expression and Sketch
    KnobField {
        visible: root.kind === 2 && root.type >= 1
        Layout.fillWidth: true
        objectName: "componentCyclesField"
        label: qsTr("Cycles")
        digits: 5
        from: 0.0001
        to: 1e6
        stepSize: 1
        logarithmic: true
        defaultValue: 1
        toolTip: qsTr("Cycles per segment")
        value: root.editor.componentCycles
        onValueModified: v => root.editor.componentCycles = v
    }
    KnobField {
        visible: root.kind === 2 && root.type >= 1
        Layout.fillWidth: true
        objectName: "componentGainField"
        label: qsTr("Gain")
        digits: 4
        from: -10
        to: 10
        stepSize: 0.1
        defaultValue: 1
        toolTip: qsTr("Component gain")
        value: root.editor.componentGain
        onValueModified: v => root.editor.componentGain = v
    }

    RowLayout {
        visible: root.kind === 2 && root.type === 2
        Layout.fillWidth: true
        ActionButton {
            Layout.fillWidth: true
            text: qsTr("Import…")
            iconName: "upload"
            compact: true
            enabled: !root.editor.drawMode
            toolTip: qsTr("Import…")
            onClicked: importFile.open()
        }
        ActionButton {
            Layout.fillWidth: true
            text: root.editor.drawMode ? qsTr("Drawing") : qsTr("Draw")
            iconName: "edit"
            compact: true
            tone: root.editor.drawMode ? "accent" : "neutral"
            toolTip: qsTr("Draw one cycle")
            onClicked: root.editor.drawMode = !root.editor.drawMode
        }
    }

    SketchImport { id: importFile; editor: root.editor }
}
