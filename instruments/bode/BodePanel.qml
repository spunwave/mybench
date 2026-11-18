pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Bode Analyzer panel: the header holds Sweep, the Start / Stop / Amplitude knobs, Keep as
// Reference and the plot view; the display is the gain and phase plots sharing one frequency axis;
// the Sweep card is the control; tools are Graph, Cursors, References and Wiring; the strip holds
// the cursor readout and the results. State and logic live in BodeController.
Item {
    id: root

    required property BodeController controller

    readonly property bool hasPoints: controller.pointCount > 0
    readonly property bool linearGain: controller.mapping === BodeController.Linear
    readonly property string gainUnit: linearGain ? "" : "dB"
    // Gain follows the stimulus channel's color, phase the response's.
    readonly property color gainColor: Theme.signalCh0        // AI 0 / Audio L in
    readonly property color phaseColor: Theme.signalCh1       // AI 1 / Audio R in
    readonly property color stimulusColor: controller.stimulus === BodeController.StimulusAO1 ? Theme.signalAo1 : Theme.signalAo0
    // The cursor pair: C1 and C2 in the shared cursor colors.
    readonly property color cursor1Color: Theme.cursor1
    readonly property color cursor2Color: Theme.cursor2
    // The plots shown: 0 both, 1 gain, 2 phase. A display under about 320 px (two plots of 150 px) shows one at a time
    // (30 px of hysteresis, so a plot never flips while a divider is dragged).
    property bool singlePlot: false
    property int soloPlot: 1                // the plot shown alone: 1 gain, 2 phase
    readonly property int shownPlot: singlePlot ? soloPlot : 0
    readonly property bool gainShown: shownPlot !== 2
    readonly property bool phaseShown: shownPlot !== 1
    readonly property bool referencesShown: controller.references.some(r => r.visible)
    property string tool                            // the open tool panel ("" = none)
    // Steps per decade on the stepped knob; a restored odd value stays selectable.
    readonly property var stepValues: {
        const base = [1, 2, 5, 10, 20, 25, 50, 100, 200, 500, 1000]
        const v = controller.stepsPerDecade
        return base.indexOf(v) >= 0 ? base : base.concat([v]).sort((a, b) => a - b)
    }
    // The state is one word; the progress, the point count and the duration are the fact after it.
    readonly property string stateWord: controller.running ? (controller.remeasuring ? qsTr("Measuring") : qsTr("Sweeping")) : ""
    readonly property string factText: {
        const c = controller
        if (!c.settingsValid)
            return c.audioPath && c.stopFrequency < 20 && c.startFrequency <= c.stopFrequency ? qsTr("Audio ≥ 20 Hz") : qsTr("Start > Stop")
        if (c.running)
            return c.remeasuring || c.totalPoints <= 0 ? ""
                 : qsTr("%1/%2").arg(Math.min(c.pointCount + 1, c.totalPoints)).arg(c.totalPoints)
                   + (c.remainingSeconds > 0 ? qsTr(" · %1 left").arg(duration(c.remainingSeconds)) : "")
        return hasPoints ? qsTr("%1 points · ≈ %2").arg(c.pointCount).arg(duration(c.plannedSeconds))
                         : qsTr("≈ %1").arg(duration(c.plannedSeconds))
    }
    readonly property bool measurementLocked: controller.running
    readonly property real leftMargin: Math.max(gainPlot.gutterLeft, phasePlot.gutterLeft)
    readonly property real rightMargin: 16

    function duration(seconds: real): string {
        if (!(seconds > 0))
            return ""
        if (seconds < 60)
            return qsTr("%1 s").arg(Math.max(1, Math.round(seconds)))
        const minutes = Math.floor(seconds / 60)
        if (minutes < 60)
            return qsTr("%1 min %2 s").arg(minutes).arg(Math.round(seconds - 60 * minutes))
        return qsTr("%1 h %2 min").arg(Math.floor(minutes / 60)).arg(minutes % 60)
    }
    function referenceInfo(slot: int): var {
        const list = controller.references
        for (let i = 0; i < list.length; ++i)
            if (list[i].slot === slot)
                return list[i]
        return null
    }
    function referenceColor(colorIndex: int): color {
        const order = [3, 4, 5, 6, 7, 2]
        return gainPlot.paletteColor(order[colorIndex % order.length])
    }
    function toggleTool(id: string) { tool = tool === id ? "" : id }

    // A labelled row inside a tool panel: the label above the control.
    component ToolRow: ColumnLayout {
        id: toolRow
        property string label
        default property alias content: rowBody.data
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        Text {
            text: toolRow.label
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
        }
        ColumnLayout {
            id: rowBody
            Layout.fillWidth: true
            spacing: Theme.spacingXs
        }
    }

    function gainText(dbValue: real, ratio: real): string {
        return linearGain ? ratio.toFixed(3) : Units.decibels(dbValue)
    }

    // Autoscale off: both plots jump to the ELVISmx fixed ranges (kept when zooming afterwards).
    function applyFixedRanges() {
        gainPlot.yAxis.min = controller.fixedGainMin
        gainPlot.yAxis.max = controller.fixedGainMax
        phasePlot.yAxis.min = controller.fixedPhaseMin
        phasePlot.yAxis.max = controller.fixedPhaseMax
    }
    Connections {
        target: root.controller
        function onAutoscaleChanged() { if (!root.controller.autoscale) root.applyFixedRanges() }
        function onStarted() { if (!root.controller.autoscale) root.applyFixedRanges() }
    }
    Component.onCompleted: if (!controller.autoscale) applyFixedRanges()

    PlotAxis {
        id: frequencyAxis
        min: root.controller.startFrequency
        max: Math.max(root.controller.stopFrequency, root.controller.startFrequency * 1.0001)
        scale: root.controller.logFrequencyAxis ? PlotAxis.Log : PlotAxis.Linear
        unit: "Hz"
        lowerLimit: root.controller.logFrequencyAxis ? 0.5 : 0
        upperLimit: 40000
    }


    InstrumentPanel {
        id: panel
        objectName: "bodePane"
        anchors.fill: parent
        controller: root.controller
        showRunControls: false
        runBar.showTimeout: false
        inspector: []
        stateText: root.stateWord
        displayInfo: root.factText

        // The gain and phase plots share the frequency axis; the wiring is the Wiring tool's.
        Item {
            id: display
            objectName: "bodeDisplay"
            anchors.fill: parent
            onHeightChanged: {
                if (height <= 0)
                    return
                if (!root.singlePlot && height < 320)
                    root.singlePlot = true
                else if (root.singlePlot && height >= 350)
                    root.singlePlot = false
            }

            ColumnLayout {
                id: plots
                anchors.fill: parent
                spacing: 0

                // One plot at a time: a slim toolbar row picks which (the header never depends on the display).
                Rectangle {
                    objectName: "plotViewBar"
                    visible: root.singlePlot
                    Layout.fillWidth: true
                    Layout.preferredHeight: Theme.controlHeightS + 2 * Theme.spacingXs
                    color: Theme.window
                    SegmentedControl {
                        objectName: "plotView"
                        anchors { right: parent.right; rightMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
                        compact: true
                        model: [{ text: qsTr("Gain"), color: root.gainColor, toolTip: qsTr("Gain plot") },
                                { text: qsTr("Phase"), color: root.phaseColor, toolTip: qsTr("Phase plot") }]
                        currentIndex: root.soloPlot - 1
                        onActivated: index => {
                            root.soloPlot = index + 1
                            currentIndex = Qt.binding(() => root.soloPlot - 1)
                        }
                    }
                }

                BenchPlot {
                    id: gainPlot
                    visible: root.gainShown
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 3
                    xAxis: frequencyAxis
                    xLabelsVisible: !root.phaseShown
                    leftMargin: root.leftMargin
                    rightMargin: root.rightMargin
                    hoverReadout: true
                    yAxis {
                        min: root.linearGain ? 0 : -40
                        max: root.linearGain ? 2 : 10
                        unit: root.gainUnit
                        autoScale: root.controller.autoscale && root.hasPoints
                        autoScaleMargin: 0.05
                        limitToData: root.hasPoints
                        limitMargin: 1
                        minimumSpan: root.linearGain ? 0.01 : 1
                        labelFormat: root.linearGain ? PlotAxis.Engineering : PlotAxis.Fixed
                        tickSpacing: 44
                    }

                    Instantiator {
                        model: root.controller.maxReferences
                        delegate: PlotTrace {
                            required property int index
                            readonly property var info: root.referenceInfo(index)
                            plot: gainPlot
                            z: -1
                            buffer: root.controller.referenceGain(index)
                            visible: info !== null && info.visible
                            name: info ? info.name : ""
                            color: info ? root.referenceColor(info.colorIndex) : Theme.ref
                            style: PlotElement.Dash
                            unit: root.gainUnit
                        }
                    }
                    PlotTrace {
                        id: gainTrace
                        buffer: root.controller.gain
                        name: qsTr("Gain")
                        unit: root.gainUnit
                        color: root.gainColor
                        pointsVisible: true
                        pointSize: 5
                        pointShape: PlotTrace.FilledCircle
                    }
                    PlotTrace {
                        buffer: root.controller.clippedGain
                        name: qsTr("Clipped")
                        color: Theme.danger
                        lineVisible: false
                        pointsVisible: true
                        pointSize: 9
                        legendVisible: false
                    }
                    Instantiator {
                        model: root.controller.showCutoffMarkers ? root.controller.cutoffFrequencies : []
                        delegate: PlotMarker {
                            required property real modelData
                            plot: gainPlot
                            x: modelData
                            trace: gainTrace
                            shape: PlotMarker.Ring
                            size: 11
                            color: root.gainColor
                            guides: true
                            // Left of the point: the cursor's value chip is drawn on the right.
                            labelPosition: PlotMarker.Left
                            label: qsTr("−3 dB")
                        }
                    }
                    PlotMarker {
                        visible: root.controller.showUnityGainMarker && isFinite(root.controller.unityGainFrequency)
                        x: root.controller.unityGainFrequency
                        trace: gainTrace
                        shape: PlotMarker.Diamond
                        size: 10
                        color: root.gainColor
                        guides: true
                        labelPosition: PlotMarker.Left
                        label: qsTr("0 dB")
                    }
                    PlotMarker {
                        visible: root.controller.showMarginMarkers && isFinite(root.controller.phaseCrossoverFrequency)
                        x: root.controller.phaseCrossoverFrequency
                        trace: gainTrace
                        shape: PlotMarker.TriangleDown
                        size: 10
                        color: root.gainColor
                        labelPosition: PlotMarker.Above
                        label: qsTr("GM")
                    }
                    PlotLine {
                        visible: root.controller.showUnityGainMarker && !root.linearGain
                        value: 0
                        color: Theme.textTertiary
                        style: PlotElement.Dash
                        width: 1
                        draggable: false
                        handle: PlotLine.NoHandle
                    }
                    PlotCursor {
                        id: gainCursor
                        objectName: "gainCursor1"
                        visible: root.controller.cursorsOn && root.hasPoints
                        position: root.controller.cursorFrequency
                        trace: gainTrace
                        snap: true
                        label: "C1"
                        color: root.cursor1Color
                        onMoved: position => root.controller.setCursorFrequency(position)
                    }
                    PlotCursor {
                        objectName: "gainCursor2"
                        visible: gainCursor.visible
                        position: root.controller.cursor2Frequency
                        trace: gainTrace
                        snap: true
                        label: "C2"
                        color: root.cursor2Color
                        onMoved: position => root.controller.setCursor2Frequency(position)
                    }
                }

                // --- Phase ------------------------------------------------------------------------
                BenchPlot {
                    id: phasePlot
                    visible: root.phaseShown
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.preferredHeight: 2.6
                    xAxis: frequencyAxis
                    leftMargin: root.leftMargin
                    rightMargin: root.rightMargin
                    hoverReadout: true
                    yAxis {
                        min: -180
                        max: 180
                        divisions: root.controller.autoscale && root.hasPoints ? 0 : 8   // 90° steps on the fixed -360...360 range
                        unit: "°"
                        autoScale: root.controller.autoscale && root.hasPoints
                        autoScaleMargin: 0.05
                        limitToData: root.hasPoints
                        limitMargin: 1
                        minimumSpan: 5
                        labelFormat: PlotAxis.Fixed
                        tickSpacing: 40
                    }

                    Instantiator {
                        model: root.controller.maxReferences
                        delegate: PlotTrace {
                            required property int index
                            readonly property var info: root.referenceInfo(index)
                            plot: phasePlot
                            z: -1
                            buffer: root.controller.referencePhase(index)
                            visible: info !== null && info.visible
                            name: info ? info.name : ""
                            color: info ? root.referenceColor(info.colorIndex) : Theme.ref
                            style: PlotElement.Dash
                            unit: "°"
                        }
                    }
                    PlotTrace {
                        id: phaseTrace
                        buffer: root.controller.phase
                        name: qsTr("Phase")
                        unit: "°"
                        color: root.phaseColor
                        pointsVisible: true
                        pointSize: 5
                        pointShape: PlotTrace.FilledCircle
                    }
                    PlotTrace {
                        buffer: root.controller.clippedPhase
                        name: qsTr("Clipped")
                        color: Theme.danger
                        lineVisible: false
                        pointsVisible: true
                        pointSize: 9
                        legendVisible: false
                    }
                    PlotLine {
                        visible: root.controller.showMarginMarkers
                        value: -180
                        color: Theme.textTertiary
                        style: PlotElement.Dash
                        width: 1
                        draggable: false
                        handle: PlotLine.NoHandle
                    }
                    PlotMarker {
                        visible: root.controller.showMarginMarkers && isFinite(root.controller.unityGainFrequency)
                        x: root.controller.unityGainFrequency
                        trace: phaseTrace
                        shape: PlotMarker.TriangleUp
                        size: 10
                        color: root.phaseColor
                        guides: true
                        labelPosition: PlotMarker.Left
                        label: qsTr("PM")
                    }
                    Instantiator {
                        model: root.controller.showCutoffMarkers ? root.controller.cutoffFrequencies : []
                        delegate: PlotMarker {
                            required property real modelData
                            plot: phasePlot
                            x: modelData
                            trace: phaseTrace
                            shape: PlotMarker.Ring
                            size: 11
                            color: root.phaseColor
                            labelPosition: PlotMarker.Left
                            label: phaseTrace.valueAt(modelData).toFixed(1) + "°"
                        }
                    }
                    PlotCursor {
                        visible: gainCursor.visible
                        position: root.controller.cursorFrequency
                        trace: phaseTrace
                        snap: true
                        label: "C1"
                        color: root.cursor1Color
                        onMoved: position => root.controller.setCursorFrequency(position)
                    }
                    PlotCursor {
                        visible: gainCursor.visible
                        position: root.controller.cursor2Frequency
                        trace: phaseTrace
                        snap: true
                        label: "C2"
                        color: root.cursor2Color
                        onMoved: position => root.controller.setCursor2Frequency(position)
                    }
                }
            }
        }

        // The Sweep card, in the stimulus colour: steps, speed, polarity, averages.
        controls: [
            ChannelCard {
                objectName: "sweepCard"
                Layout.fillWidth: true
                title: qsTr("Sweep")
                color: root.stimulusColor    // the stimulus output
                checkable: false

                FormRow {
                    label: qsTr("Stimulus")
                    SegmentedControl {
                        objectName: "stimulusButtons"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        enabled: !root.measurementLocked
                        model: [{ text: qsTr("AO 0"), color: Theme.signalAo0, toolTip: qsTr("AO 0 · ±10 V") },
                                { text: qsTr("AO 1"), color: Theme.signalAo1, toolTip: qsTr("AO 1 · ±10 V") },
                                { text: qsTr("Audio"), color: Theme.signalAo0, toolTip: qsTr("Audio Out, L and R · ±2 V, AC · from 20 Hz, up to 1.8 V") }]
                        currentIndex: root.controller.stimulus
                        onActivated: index => root.controller.stimulus = index
                    }
                }
                FormRow {
                    label: qsTr("Inputs")
                    SegmentedControl {
                        objectName: "inputButtons"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        enabled: !root.measurementLocked
                        model: [{ text: qsTr("AI 0/1"), toolTip: qsTr("AI 0 stimulus, AI 1 response") },
                                { text: qsTr("Audio L/R"), toolTip: qsTr("Audio In L stimulus, R response · ±2 V, AC · from 20 Hz") }]
                        currentIndex: root.controller.inputPair
                        onActivated: index => root.controller.inputPair = index
                    }
                }
                KnobField {
                    objectName: "stepsKnob"
                    Layout.fillWidth: true
                    enabled: !root.measurementLocked
                    label: qsTr("Steps")
                    values: root.stepValues
                    labels: root.stepValues.map(v => qsTr("%1 /dec").arg(v))
                    currentIndex: Math.max(0, root.stepValues.indexOf(root.controller.stepsPerDecade))
                    toolTip: root.controller.settingsValid ? qsTr("%1 points").arg(root.controller.plannedPoints)
                                                           : qsTr("Steps per decade")
                    onIndexActivated: index => root.controller.stepsPerDecade = root.stepValues[index]
                }
                FormRow {
                    label: qsTr("Speed")
                    SegmentedControl {
                        objectName: "modeButtons"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        enabled: !root.measurementLocked
                        model: [{ text: qsTr("Standard"), toolTip: qsTr("Range pre-measurement per point") },
                                { text: qsTr("Fast"), toolTip: qsTr("No pre-measurement") }]
                        currentIndex: root.controller.sweepMode === BodeController.Fast ? 1 : 0
                        onActivated: index => root.controller.sweepMode = index === 1 ? BodeController.Fast : BodeController.Standard
                    }
                }
                FormRow {
                    label: qsTr("Polarity")
                    SegmentedControl {
                        objectName: "polarityButtons"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [{ text: qsTr("Normal"), toolTip: qsTr("As measured") },
                                { text: qsTr("Invert"), toolTip: qsTr("Inverted · inverting amplifier reads 0°") }]
                        currentIndex: root.controller.polarity === BodeController.Inverted ? 1 : 0
                        onActivated: index => root.controller.polarity = index === 1 ? BodeController.Inverted : BodeController.Normal
                    }
                }
                KnobField {
                    objectName: "averagesKnob"
                    Layout.fillWidth: true
                    enabled: !root.measurementLocked
                    label: qsTr("Averages")
                    from: 1
                    to: 16
                    stepSize: 1
                    value: root.controller.averagesPerPoint
                    formatter: v => String(Math.round(v))
                    toolTip: qsTr("Averages per frequency")
                    onValueModified: v => root.controller.averagesPerPoint = Math.round(v)
                }
            }
        ]

        tools: ToolPalette {
            objectName: "bodeTools"
            currentId: root.tool
            model: [{ id: "graph", text: qsTr("Graph"), toolTip: qsTr("Graph"), icon: "grid" },
                    { id: "cursors", text: qsTr("Cursors"), toolTip: qsTr("Cursors"), icon: "crosshair" },
                    { id: "references", text: qsTr("Refs"), toolTip: qsTr("References"), icon: "layers" },
                    { id: "connections", text: qsTr("Wiring"), toolTip: qsTr("Wiring"), icon: "activity" }]
            onActivated: id => root.toggleTool(id)
        }

        toolPanels: [
            ToolPanel {
                objectName: "graphPanel"
                visible: root.tool === "graph"
                title: qsTr("Graph")
                onCloseRequested: root.tool = ""
                ToolRow {
                    label: qsTr("Gain")
                    SegmentedControl {
                        objectName: "mappingButtons"
                        Layout.fillWidth: true
                        model: [{ text: qsTr("dB"), toolTip: qsTr("Logarithmic") },
                                { text: qsTr("Ratio"), toolTip: qsTr("Linear") }]
                        currentIndex: root.linearGain ? 1 : 0
                        onActivated: index => root.controller.mapping = index === 1 ? BodeController.Linear : BodeController.Logarithmic
                    }
                }
                ToolRow {
                    label: qsTr("Frequency")
                    SegmentedControl {
                        Layout.fillWidth: true
                        model: [qsTr("Log"), qsTr("Linear")]
                        currentIndex: root.controller.logFrequencyAxis ? 0 : 1
                        onActivated: index => root.controller.logFrequencyAxis = index === 0
                    }
                }
                CheckBox {
                    text: qsTr("Autoscale")
                    checked: root.controller.autoscale
                    onToggled: root.controller.autoscale = checked
                }
                CheckBox {
                    text: qsTr("Unwrap phase")
                    ToolTip.visible: hovered
                    ToolTip.text: qsTr("Remove 360° jumps")
                    checked: root.controller.unwrapPhase
                    onToggled: root.controller.unwrapPhase = checked
                }
            },

            // Cursors (C1 / C2) and the automatic markers in one tool.
            ToolPanel {
                objectName: "cursorsPanel"
                visible: root.tool === "cursors"
                title: qsTr("Cursors")
                onCloseRequested: root.tool = ""
                ToggleSwitch {
                    objectName: "cursorsSwitch"
                    Layout.fillWidth: true
                    text: qsTr("Cursors")
                    checked: root.controller.cursorsOn
                    onToggled: root.controller.cursorsOn = checked
                }
                // C1 steps point by point (drag either cursor on the plot); Re-measure replaces C1's point.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs
                    enabled: root.controller.cursorsOn
                    Rectangle { implicitWidth: 10; implicitHeight: 10; radius: 3; color: root.cursor1Color }
                    Text {
                        text: qsTr("C1")
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeS
                        font.weight: Font.DemiBold
                    }
                    Item { Layout.fillWidth: true }
                    IconButton {
                        iconName: "chevron-left"
                        enabled: root.controller.cursorIndex > 0
                        toolTip: qsTr("Previous point")
                        onClicked: root.controller.cursorLeft()
                    }
                    IconButton {
                        iconName: "chevron-right"
                        enabled: root.controller.cursorIndex < root.controller.pointCount - 1
                        toolTip: qsTr("Next point")
                        onClicked: root.controller.cursorRight()
                    }
                    IconButton {
                        iconName: "refresh"
                        enabled: root.controller.cursorIndex >= 0 && root.controller.canRun && !root.controller.paused
                        toolTip: qsTr("Remeasure C1")
                        onClicked: root.controller.remeasureCursorPoint()
                    }
                }
                ToolRow {
                    label: qsTr("Markers")
                    CheckBox {
                        text: qsTr("−3 dB")
                        checked: root.controller.showCutoffMarkers
                        onToggled: root.controller.showCutoffMarkers = checked
                    }
                    CheckBox {
                        text: qsTr("0 dB crossover")
                        checked: root.controller.showUnityGainMarker
                        onToggled: root.controller.showUnityGainMarker = checked
                    }
                    CheckBox {
                        text: qsTr("Gain / phase margin")
                        checked: root.controller.showMarginMarkers
                        onToggled: root.controller.showMarginMarkers = checked
                    }
                }
            },

            ToolPanel {
                objectName: "referencesPanel"
                visible: root.tool === "references"
                title: qsTr("References")
                onCloseRequested: root.tool = ""
                // Kept with the header's Keep as Reference button.
                Text {
                    visible: root.controller.references.length === 0
                    text: qsTr("None")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeS
                }
                Repeater {
                    model: root.controller.references
                    delegate: RowLayout {
                        id: referenceRow
                        required property var modelData
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs
                        Rectangle {
                            implicitWidth: 14
                            implicitHeight: 3
                            radius: 1.5
                            color: root.referenceColor(referenceRow.modelData.colorIndex)
                            opacity: referenceRow.modelData.visible ? 1 : 0.35
                        }
                        TextField {
                            Layout.fillWidth: true
                            text: referenceRow.modelData.name
                            onEditingFinished: root.controller.renameReference(referenceRow.modelData.slot, text)
                            ToolTip.visible: hovered
                            ToolTip.text: qsTr("%1 points%2").arg(referenceRow.modelData.points)
                                              .arg(referenceRow.modelData.inverted ? qsTr(" · inverted") : "")
                        }
                        IconButton {
                            iconName: referenceRow.modelData.visible ? "eye" : "eye-off"
                            size: 24
                            iconSize: Theme.iconSizeS
                            toolTip: referenceRow.modelData.visible ? qsTr("Hide") : qsTr("Show")
                            onClicked: root.controller.setReferenceVisible(referenceRow.modelData.slot, !referenceRow.modelData.visible)
                        }
                        IconButton {
                            iconName: "download"
                            size: 24
                            iconSize: Theme.iconSizeS
                            toolTip: qsTr("Export…")
                            onClicked: {
                                referenceDialog.slot = referenceRow.modelData.slot
                                referenceDialog.selectedFile = DataExport.suggestedFileUrl("bode-reference", "csv")
                                referenceDialog.open()
                            }
                        }
                        IconButton {
                            iconName: "trash"
                            size: 24
                            iconSize: Theme.iconSizeS
                            toolTip: qsTr("Delete")
                            onClicked: root.controller.removeReference(referenceRow.modelData.slot)
                        }
                    }
                }
            },

            ToolPanel {
                objectName: "connectionsPanel"
                visible: root.tool === "connections"
                title: qsTr("Wiring")
                onCloseRequested: root.tool = ""
                BodeWiring {
                    stimulusName: root.controller.stimulusName
                    stimulusInputName: root.controller.stimulusInputName
                    responseInputName: root.controller.responseInputName
                    stimulusColor: root.stimulusColor
                    Layout.alignment: Qt.AlignHCenter
                    scale: Math.min(1, (parent ? parent.width : 300) / implicitWidth)
                    transformOrigin: Item.TopLeft
                    Layout.preferredHeight: implicitHeight * scale
                    Layout.preferredWidth: implicitWidth * scale
                }
            }
        ]

        headerContent: [
            RunButton {
                objectName: "bodeRunButton"
                runText: qsTr("Sweep")
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Stopping
                enabled: root.controller.running || root.controller.canRun
                onToggled: root.controller.toggle()
            }
        ]
        headerSettings: [
            HeaderField {
                objectName: "startKnob"
                enabled: !root.measurementLocked
                label: qsTr("Start")
                toolTip: qsTr("Start frequency")
                unit: "Hz"
                from: 1
                to: 20000
                logarithmic: true
                value: root.controller.startFrequency
                onValueModified: v => root.controller.startFrequency = v
            },
            HeaderField {
                objectName: "stopKnob"
                enabled: !root.measurementLocked
                label: qsTr("Stop")
                toolTip: qsTr("Stop frequency")
                unit: "Hz"
                from: 1
                to: 20000
                logarithmic: true
                value: root.controller.stopFrequency
                onValueModified: v => root.controller.stopFrequency = v
            },
            HeaderField {
                objectName: "amplitudeKnob"
                accentColor: Theme.signalAo0       // the stimulus output
                enabled: !root.measurementLocked
                toolTip: qsTr("Amplitude")
                unit: "Vpk"
                from: 0
                to: 5
                stepSize: 0.01
                value: root.controller.peakAmplitude
                formatter: v => v.toFixed(2) + " Vpk"
                onValueModified: v => root.controller.peakAmplitude = Math.round(v * 100) / 100
            },
            // Only while there is a sweep to keep.
            Button {
                objectName: "keepReferenceButton"
                visible: root.hasPoints && !root.controller.running
                text: qsTr("Keep as Reference")
                icon.source: Theme.icon("layers")
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Keep this sweep")
                onClicked: root.controller.keepAsReference()
            }
        ]


        // The cursor readout cards (or the last point), then the results.
        measurements: [
            MeasurementStrip {
                id: cards
                objectName: "bodeCards"
                readonly property string summaryText: root.controller.cutoffFrequencies.length > 0
                    ? qsTr("f−3dB %1").arg(Units.format(root.controller.cutoffFrequencies[0], "Hz", 3)) : ""
                BodeReadout {
                    objectName: "cardCursor"
                    controller: root.controller
                    linearGain: root.linearGain
                    cursor1Color: root.cursor1Color
                    cursor2Color: root.cursor2Color
                }
                component Card: MeasurementCard {
                    removable: false
                }
                Card {
                    objectName: "cardCutoff"
                    title: qsTr("f−3dB")
                    color: root.gainColor
                    value: root.controller.cutoffFrequencies.length > 0
                           ? root.controller.cutoffFrequencies.map(f => Units.format(f, "Hz", 3)).join(" · ") : "—"
                }
                Card {
                    objectName: "cardUnity"
                    title: qsTr("0 dB at f")
                    color: root.gainColor
                    value: isFinite(root.controller.unityGainFrequency) && root.controller.unityGainFrequency > 0
                           ? Units.format(root.controller.unityGainFrequency, "Hz", 3) : "—"
                }
                Card {
                    objectName: "cardGainMargin"
                    title: qsTr("Gain margin")
                    color: root.gainColor
                    value: isFinite(root.controller.gainMargin) ? Units.decibels(root.controller.gainMargin, 1) : "—"
                }
                Card {
                    objectName: "cardGainMarginFrequency"
                    title: qsTr("GM at f")
                    color: root.gainColor
                    value: isFinite(root.controller.phaseCrossoverFrequency) && root.controller.phaseCrossoverFrequency > 0
                           ? Units.format(root.controller.phaseCrossoverFrequency, "Hz", 3) : "—"
                }
                Card {
                    objectName: "cardPhaseMargin"
                    title: qsTr("Phase margin")
                    color: root.phaseColor
                    value: isFinite(root.controller.phaseMargin) ? root.controller.phaseMargin.toFixed(1) + "°" : "—"
                }
                Card {
                    objectName: "cardMaxGain"
                    title: qsTr("Max gain")
                    color: root.gainColor
                    value: root.hasPoints && isFinite(root.controller.maxGainDb) ? Units.decibels(root.controller.maxGainDb, 2) : "—"
                }
            }
        ]
    }

    ReferenceExportDialog {
        id: referenceDialog
        controller: root.controller
    }
}
