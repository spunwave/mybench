pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Counter/Timer panel: header (Run, Single), the big reading with its unit and the trend under it
// (pulse diagram / FREQOUT reading in the output modes), cards (Mode, Input, Pulse Train, FREQOUT),
// the statistics strip and tools (Connections, Export). Options the device cannot do are hidden.
Item {
    id: root

    required property CtrController controller

    // Trend time windows (view setting of this panel).
    readonly property var trendWindows: [{ text: qsTr("10 s"), seconds: 10 }, { text: qsTr("1 min"), seconds: 60 },
                                         { text: qsTr("10 min"), seconds: 600 }, { text: qsTr("All"), seconds: 0 }]
    property int trendWindow: 1
    // Expected range presets: the longest expected interval picks the counter timebase (100 MHz,
    // 20 MHz, 100 kHz), so one preset per timebase.
    readonly property var frequencyRanges: [{ min: 1, max: 1e6 }, { min: 0.01, max: 1e6 }, { min: 1e-4, max: 1e3 }]
    readonly property var timeRanges: [{ min: 100e-9, max: 10 }, { min: 1e-6, max: 100 }, { min: 100e-6, max: 1e4 }]
    readonly property bool frequencyRange: measurement === CtrController.Frequency
    readonly property var expectedRanges: frequencyRange ? frequencyRanges : timeRanges
    readonly property int expectedRangeIndex: {
        const lo = frequencyRange ? controller.frequencyMin : controller.timeMin
        const hi = frequencyRange ? controller.frequencyMax : controller.timeMax
        return expectedRanges.findIndex(r => Math.abs(r.min - lo) <= 1e-9 * r.min && Math.abs(r.max - hi) <= 1e-9 * r.max)
    }
    function expectedRangeText(r: var): string {
        const unit = frequencyRange ? "Hz" : "s"
        return Units.format(r.min, unit, 3) + " – " + Units.format(r.max, unit, 3)
    }
    // The button label: the bound that picks the timebase (lowest frequency / longest interval;
    // the row label says which).
    function expectedRangeLabel(r: var): string {
        return frequencyRange ? Units.format(r.min, "Hz", 3) : Units.format(r.max, "s", 3)
    }
    // The pictogram: the covered decades as a bracket over a log axis of all the presets.
    function expectedRangeGlyph(r: var): string {
        const all = expectedRanges
        const lo = Math.log10(Math.min(...all.map(e => e.min))), hi = Math.log10(Math.max(...all.map(e => e.max)))
        const x = v => (2 + 28 * (Math.log10(v) - lo) / (hi - lo)).toFixed(1)
        const a = x(r.min), b = x(r.max)
        return "M2 15h28 M2 13v4 M30 13v4 M" + a + " 9H" + b + " M" + a + " 5v8 M" + b + " 5v8"
    }
    readonly property var timebaseNames: ["100 MHz", "20 MHz", "100 kHz"]
    function selectExpectedRange(index: int) {
        const r = expectedRanges[index]
        if (frequencyRange) {
            controller.frequencyMin = r.min
            controller.frequencyMax = r.max
        } else {
            controller.timeMin = r.min
            controller.timeMax = r.max
        }
    }
    function applyTrendWindow() {
        const span = trendWindows[trendWindow]?.seconds ?? 60
        const now = Date.now() / 1000
        const axis = trendView.plot.xAxis
        if (span > 0) {
            axis.setRange(now - span, now)
        } else {
            const first = controller.trend.count > 0 ? controller.trend.xMinimum() : now - 60
            axis.setRange(first, Math.max(now, first + 10))
        }
        axis.follow = true
    }
    Connections {
        target: root.controller.trend
        enabled: (root.trendWindows[root.trendWindow]?.seconds ?? 60) === 0
        function onChanged() { root.applyTrendWindow() }
    }
    property string tool: ""

    readonly property bool measuring: controller.counterFunction === CtrController.Measure
    readonly property bool pulsing: controller.counterFunction === CtrController.PulseTrain
    readonly property bool counterOff: controller.counterFunction === CtrController.CounterOff
    readonly property int measurement: controller.measurement
    readonly property bool counting: measurement === CtrController.CountEdges
    readonly property bool encoder: controller.encoderMeasurement
    readonly property bool interval: controller.intervalMeasurement

    // DeviceHub capability query; reading the property makes bindings re-evaluate on a device change.
    function unsupported(feature: string): bool {
        return DeviceHub.unsupportedFeatures.includes(feature)
    }
    readonly property var measurementFeatures: [
        "", "", "", "counter.pulseWidth", "counter.semiPeriod", "counter.twoEdgeSeparation",
        "counter.linearEncoder", "counter.angularEncoder"
    ]

    // The modes of the counter: the measurements, then Pulse Train and "FREQOUT only".
    // glyph = 32 × 18 SVG path.
    readonly property var modes: [
        { fn: CtrController.Measure, m: CtrController.Frequency, text: qsTr("Frequency"),
          glyph: "M2 14h4V4h4v10h4V4h4v10h4V4h4v10h2" },
        { fn: CtrController.Measure, m: CtrController.Period, text: qsTr("Period"),
          glyph: "M2 14h5V6h7v8h7V6h7v8 M7 2h14 M7 1v3 M21 1v3" },
        { fn: CtrController.Measure, m: CtrController.PulseWidth, text: qsTr("Pulse Width"), short: qsTr("Width"),
          glyph: "M2 15h9V6h10v9h9 M11 2h10 M11 1v3 M21 1v3" },
        { fn: CtrController.Measure, m: CtrController.SemiPeriod, text: qsTr("Semi-Period"), short: qsTr("Semi"),
          glyph: "M2 15h8V6h8v9h8V6h4 M10 2h8 M18 2h8 M10 1v3 M18 1v3 M26 1v3" },
        { fn: CtrController.Measure, m: CtrController.TwoEdgeSeparation, text: qsTr("Two-Edge"),
          glyph: "M2 8h7V2h21 M2 17h16v-6h12 M9 5h9" },
        { fn: CtrController.Measure, m: CtrController.CountEdges, text: qsTr("Edge Count"), short: qsTr("Count"),
          glyph: "M2 16h6v-4h6v-4h6v-4h6v-3h4" },
        { fn: CtrController.Measure, m: CtrController.LinearEncoder, text: qsTr("Linear Encoder"), short: qsTr("Linear"),
          glyph: "M2 9h28 M6 4v10 M12 4v10 M18 4v10 M24 4v10" },
        { fn: CtrController.Measure, m: CtrController.AngularEncoder, text: qsTr("Angular Encoder"), short: qsTr("Angular"),
          glyph: "M16 2a7 7 0 1 0 0.01 0 M16 9l5-5" },
        { fn: CtrController.PulseTrain, m: -1, text: qsTr("Pulse Train"),
          glyph: "M2 15h4V4h3v11h7V4h3v11h7V4h3v11" },
        { fn: CtrController.CounterOff, m: -1, text: qsTr("FREQOUT Only"), short: qsTr("FREQOUT"),
          glyph: "M2 9h28" }
    ]
    function modeSupported(mode: var): bool {
        return mode.m < 0 || root.measurementFeatures[mode.m] === "" || !root.unsupported(root.measurementFeatures[mode.m])
    }
    function modeActive(mode: var): bool {
        return mode.fn === root.controller.counterFunction && (mode.m < 0 || mode.m === root.measurement)
    }
    function selectMode(mode: var) {
        if (mode.m >= 0)
            root.controller.measurement = mode.m
        root.controller.counterFunction = mode.fn
    }

    // FREQOUT: the achievable frequencies, low to high (the knob turns clockwise to higher).
    readonly property var freqOutValues: controller.freqOutChoices.map(t => Units.parse(t, "Hz"))
    readonly property bool freqOutAscending: freqOutValues.length < 2 || freqOutValues[0] < freqOutValues[1]
    readonly property var freqOutKnobValues: freqOutAscending ? freqOutValues : freqOutValues.slice().reverse()
    readonly property var freqOutKnobLabels: freqOutAscending ? controller.freqOutChoices : controller.freqOutChoices.slice().reverse()
    function knobToTable(index: int): int {
        return freqOutAscending ? index : freqOutValues.length - 1 - index
    }

    // Statistics formatting in the measurement's unit.
    function fmt(v: real, spread: bool): string {
        if (isNaN(v))
            return "—"
        if (root.counting)
            return spread ? v.toFixed(2) : String(Math.round(v))
        if (root.encoder)
            return v.toFixed(3) + (root.controller.unit.length > 0 ? " " + root.controller.unit : "")
        return Units.format(v, root.controller.unit, 5)
    }

    component Caption: Text {
        Layout.fillWidth: true
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSizeCaption
        font.features: Theme.tabularFigures
        wrapMode: Text.WordWrap
    }
    // A count shown without decimals.
    function whole(v: real): string {
        return String(Math.round(v))
    }

    InstrumentPanel {
        id: panel
        objectName: "ctrPane"
        anchors.fill: parent
        controller: root.controller
        // No header detail (a no-break space keeps the controller's setup summary out of the
        // header): the mode is the checked mode button, the terminals are the Input card's subtitle.
        displayInfo: " "
        showRunControls: false
        runBar.showTimeout: false
        inspector: []

        stateText: root.controller.running && root.controller.timedOut ? qsTr("No input") : ""

        headerContent: [
            RunButton {
                objectName: "ctrRunButton"
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Stopping
                enabled: root.controller.running || root.controller.canRun
                shortcutText: Theme.keys("Space")
                onToggled: root.controller.toggle()
            },
            // Single: idle = one reading (or one buffer); running = stop after the next one.
            Button {
                objectName: "ctrSingleButton"
                visible: root.measuring
                text: qsTr("Single")
                icon.source: Theme.icon("step")
                enabled: root.controller.canRun
                         || (root.controller.state === InstrumentController.Running
                             && root.controller.runMode === InstrumentController.Continuous)
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: !root.controller.running && root.controller.sampling === CtrController.Buffered
                              ? qsTr("%1 intervals").arg(root.controller.bufferedSamples)
                              : qsTr("Single")
                onClicked: root.controller.runOnce()
            }
        ]

        // --- Display ------------------------------------------------------------------------
        Item {
            id: display
            objectName: "ctrDisplay"
            anchors.fill: parent

            // The reading scales with the display's height: reading + trend fit a 484 x 200 display.
            readonly property int readoutSize: Math.round(Math.max(28, Math.min(96, display.width / 8, display.height * 0.2)))
            readonly property real trendRoom: height - readoutColumn.implicitHeight - 2 * Theme.spacingS - Theme.spacingS
            readonly property bool hasReading: !root.controller.valueText.startsWith("---")

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacingS

                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: root.counterOff
                    Layout.preferredHeight: readoutColumn.implicitHeight + Theme.spacingS
                    Layout.minimumHeight: readoutColumn.implicitHeight

                    Column {
                        id: readoutColumn
                        anchors.verticalCenter: parent.verticalCenter
                        // The trend's own edges: the reading is centred over the plotted area.
                        x: root.measuring ? trendView.plot.x + trendView.plot.plotArea.x : 0
                        width: root.measuring && trendView.plot.plotArea.width > 0 ? trendView.plot.plotArea.width : parent.width
                        spacing: Theme.spacingS

                        Readout {
                            objectName: "ctrValue"
                            visible: root.measuring
                            width: parent.width
                            valueText: display.hasReading ? root.controller.valueText : "—"
                            fontSize: display.readoutSize
                            stale: !root.controller.running
                            color: display.hasReading ? Theme.text : Theme.textTertiary
                            caption: root.controller.secondaryText.length > 0 ? root.controller.secondaryText : " "
                        }

                        Row {
                            visible: root.pulsing
                            width: parent.width
                            spacing: Theme.spacingXl
                            Readout {
                                width: (parent.width - Theme.spacingXl) / 2
                                label: qsTr("Pulse Frequency")
                                value: root.controller.running && root.controller.outputFrequency > 0 ? root.controller.outputFrequency
                                                                                                      : root.controller.coercedPulseFrequency
                                unit: "Hz"
                                digits: 6
                                fontSize: Math.round(display.readoutSize * 0.75)
                                stale: !root.controller.running
                                caption: qsTr("Period %1").arg(Units.format(1 / root.controller.coercedPulseFrequency, "s", 5))
                            }
                            Readout {
                                width: (parent.width - Theme.spacingXl) / 2
                                label: qsTr("Duty Cycle")
                                valueText: ((root.controller.running && root.controller.outputDutyCycle > 0 ? root.controller.outputDutyCycle
                                                                                                            : root.controller.coercedDutyCycle) * 100).toFixed(2) + " %"
                                fontSize: Math.round(display.readoutSize * 0.75)
                                stale: !root.controller.running
                                caption: qsTr("High %1 · Low %2").arg(Units.format(root.controller.highTime, "s", 4))
                                                                  .arg(Units.format(root.controller.lowTime, "s", 4))
                            }
                        }

                        Readout {
                            visible: root.counterOff
                            width: parent.width
                            label: qsTr("FREQOUT")
                            value: root.controller.freqOutEnabled ? (root.controller.freqOutActual > 0 ? root.controller.freqOutActual
                                                                                                        : root.controller.coercedFreqOut) : NaN
                            unit: "Hz"
                            digits: 6
                            fontSize: display.readoutSize
                            stale: !root.controller.running
                            caption: root.controller.freqOutEnabled ? "" : qsTr("Off")
                        }

                        Caption {
                            visible: root.pulsing && text.length > 0
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            // Only the output state (generation, idle state and delay are in the card).
                            text: root.controller.outputState
                        }
                    }
                }

                // Trend of the readings (Measure), with its time window.
                TrendView {
                    id: trendView
                    objectName: "ctrTrend"
                    visible: root.measuring
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 56
                    // A trend between 100 and 200 px high is too tall to be slim and too short to read:
                    // it stays slim (96 px) and the reading takes the room.
                    Layout.maximumHeight: display.trendRoom < 200 ? Math.min(96, display.trendRoom) : 100000
                    windows: root.trendWindows
                    windowIndex: root.trendWindow
                    onWindowActivated: index => { root.trendWindow = index; root.applyTrendWindow() }
                    onClearRequested: root.controller.resetMeasurement()
                    plot.placeholderText: ""
                    plot.hoverReadout: true
                    plot.xAxis.labelFormat: PlotAxis.Time
                    plot.xAxis.follow: true
                    plot.yAxis.autoScale: true
                    plot.yAxis.unit: root.controller.unit
                    plot.yAxis.unitInLabels: root.controller.unit.length > 0
                    Component.onCompleted: root.applyTrendWindow()
                    PlotTrace {
                        buffer: root.controller.trend
                        name: root.controller.functionTitle
                        unit: root.controller.unit
                        color: Theme.signalCh0
                        step: root.counting
                    }
                    PlotLine {
                        visible: !isNaN(root.controller.statMean) && root.controller.statCount > 1
                        value: isNaN(root.controller.statMean) ? 0 : root.controller.statMean
                        color: Theme.alpha(Theme.signalCh0, 0.6)
                        style: PlotElement.Dash
                        handle: PlotLine.End
                        label: qsTr("mean")
                        draggable: false
                    }
                }

                // Pulse diagram (Pulse Train), in the output's colour.
                BenchPlot {
                    visible: root.pulsing
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 56
                    interactive: false
                    placeholderText: ""
                    readonly property real period: 1 / root.controller.coercedPulseFrequency
                    readonly property int shown: root.controller.pulseGeneration === CtrController.FinitePulses
                                                 ? Math.min(root.controller.pulseCount, 4) : 4
                    readonly property bool tail: root.controller.pulseGeneration === CtrController.FinitePulses && root.controller.pulseCount <= 4
                    xAxis {
                        min: -Math.min(root.controller.initialDelay, period)
                        max: (shown + (tail ? 1 : 0)) * period
                        unit: "s"
                        unitInLabels: true
                    }
                    yAxis { min: -0.3; max: 1.3; labelsVisible: false; gridVisible: false; interactive: false }
                    PlotTrace {
                        buffer: root.controller.pulsePreview
                        color: Theme.signalAo0
                        fill: true
                        fillBaseline: 0
                        fillOpacity: 0.14
                    }
                    PlotLine { value: 1; color: Theme.alpha(Theme.textMuted, 0.5); style: PlotElement.Dot; handle: PlotLine.Start; label: "H"; draggable: false }
                    PlotLine { value: 0; color: Theme.alpha(Theme.textMuted, 0.5); style: PlotElement.Dot; handle: PlotLine.Start; label: "L"; draggable: false }
                    PlotLine {
                        orientation: PlotElement.Vertical
                        visible: root.controller.initialDelay > 0
                        value: 0
                        color: Theme.alpha(Theme.signalAo0, 0.6)
                        style: PlotElement.Dash
                        handle: PlotLine.Start
                        label: qsTr("first pulse")
                        draggable: false
                    }
                }

                Text {
                    visible: root.controller.conflictText.length > 0
                    Layout.fillWidth: true
                    text: root.controller.conflictText
                    color: Theme.warning
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            }
        }

        // --- Cards: the column at the right, or the dock under the display ----------------------
        controls: [
            // Mode: always the picture-button grid (3 columns in the column, more where the card is wider).
            ChannelCard {
                id: modeCard
                objectName: "ctrModeCard"
                Layout.fillWidth: true
                title: qsTr("Mode")
                checkable: false
                GridLayout {
                    objectName: "ctrModeGrid"
                    Layout.fillWidth: true
                    columns: Math.max(3, Math.min(6, Math.floor((modeCard.width - 2 * Theme.cardPadding - 2 * Theme.cardMargin) / 76)))
                    columnSpacing: Theme.spacingXs
                    rowSpacing: Theme.spacingXs
                    Repeater {
                        model: root.modes
                        PictureButton {
                            required property var modelData
                            objectName: "ctrMode_" + modelData.text
                            visible: root.modeSupported(modelData)
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitWidth: 56
                            text: modelData.short ?? modelData.text
                            Accessible.name: modelData.text
                            glyph: modelData.glyph
                            ToolTip.visible: hovered
                            ToolTip.delay: Theme.toolTipDelay
                            ToolTip.text: modelData.toolTip ?? modelData.text
                            checked: root.modeActive(modelData)
                            onClicked: root.selectMode(modelData)
                        }
                    }
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.controller.unsupportedInUse.length > 0
                    text: qsTr("Not supported: %1").arg(root.controller.unsupportedInUse.join(", "))
                    color: Theme.warning
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            },

            // The active measurement's settings.
            ChannelCard {
                objectName: "ctrSettingsCard"
                visible: root.measuring
                Layout.fillWidth: true
                title: qsTr("Input")
                subtitle: root.controller.terminals
                color: Theme.signalCh0
                checkable: false

                FormRow {
                    visible: root.measurement !== CtrController.SemiPeriod && !root.encoder
                    label: root.measurement === CtrController.TwoEdgeSeparation ? qsTr("First edge")
                         : root.measurement === CtrController.PulseWidth ? qsTr("Start edge")
                         : qsTr("Edge")
                    hint: root.measurement === CtrController.TwoEdgeSeparation ? qsTr("First edge (DIO 2)")
                        : root.measurement === CtrController.PulseWidth ? qsTr("Starting edge")
                        : root.counting ? qsTr("Edges to count") : qsTr("Active edge")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: root.unsupported("counter.fallingEdge")
                               ? [{ icon: "slope-rising", toolTip: qsTr("Rising edge") }]
                               : [{ icon: "slope-rising", toolTip: qsTr("Rising edge") }, { icon: "slope-falling", toolTip: qsTr("Falling edge") }]
                        currentIndex: root.controller.activeEdge
                        onActivated: index => root.controller.activeEdge = index
                    }
                }
                FormRow {
                    visible: root.measurement === CtrController.TwoEdgeSeparation
                    label: qsTr("Second edge")
                    hint: qsTr("Second edge (DIO 1)")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [{ icon: "slope-rising", toolTip: qsTr("Rising edge") }, { icon: "slope-falling", toolTip: qsTr("Falling edge") }]
                        currentIndex: root.controller.secondEdge
                        onActivated: index => root.controller.secondEdge = index
                    }
                }
                FormRow {
                    visible: root.counting
                    label: qsTr("Direction")
                    SegmentedControl {
                        id: directionControl
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        // Only the supported directions; `value` = CtrController.CountDirection.
                        model: {
                            const m = [{ text: qsTr("Up"), value: CtrController.CountUp }]
                            if (!root.unsupported("counter.countDown"))
                                m.push({ text: qsTr("Down"), value: CtrController.CountDown })
                            if (!root.unsupported("counter.externalDirection"))
                                m.push({ text: qsTr("External"), value: CtrController.CountExternal,
                                         toolTip: qsTr("DIO 2: high up, low down") })
                            return m
                        }
                        currentIndex: model.findIndex(e => e.value === root.controller.countDirection)
                        onActivated: index => root.controller.countDirection = directionControl.model[index].value
                    }
                }
                KnobField {
                    objectName: "ctrInitialCount"
                    visible: root.counting && !root.unsupported("counter.initialCount")
                    Layout.fillWidth: true
                    label: qsTr("Initial")
                    toolTip: qsTr("Initial count")
                    from: 0
                    to: 4294967295
                    stepSize: 1
                    defaultValue: 0
                    formatter: v => root.whole(v)
                    value: root.controller.initialCount
                    onValueModified: v => root.controller.initialCount = Math.round(v)
                }
                FormRow {
                    visible: root.counting && !root.unsupported("counter.resetOnDio")
                    label: qsTr("Reset")
                    hint: qsTr("Reset on DIO 1 rising edge")
                    ToggleSwitch {
                        accentColor: Theme.signalCh0
                        checked: root.controller.resetOnDio1
                        onToggled: root.controller.resetOnDio1 = checked
                    }
                }

                // Encoders.
                FormRow {
                    visible: root.encoder
                    label: qsTr("Decoding")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [{ text: "X1", toolTip: qsTr("One count per cycle of A") },
                                { text: "X2", toolTip: qsTr("Both edges of A") },
                                { text: "X4", toolTip: qsTr("Every edge of A and B") },
                                { text: qsTr("2-P"), toolTip: qsTr("Two-pulse: DIO 0 up, DIO 2 down") }]
                        currentIndex: root.controller.decoding
                        onActivated: index => root.controller.decoding = index
                    }
                }
                KnobField {
                    objectName: "ctrDistance"
                    visible: root.measurement === CtrController.LinearEncoder
                    Layout.fillWidth: true
                    label: qsTr("Distance")
                    toolTip: qsTr("Distance per pulse")
                    unit: root.controller.distanceUnit
                    from: 1e-9
                    to: 1e6
                    logarithmic: true
                    digits: 5
                    defaultValue: 1
                    value: root.controller.distancePerPulse
                    onValueModified: v => root.controller.distancePerPulse = v
                }
                FormRow {
                    visible: root.measurement === CtrController.LinearEncoder
                    label: qsTr("Unit")
                    TextField {
                        Layout.fillWidth: true
                        text: root.controller.distanceUnit
                        onEditingFinished: root.controller.distanceUnit = text
                    }
                }
                KnobField {
                    objectName: "ctrPulsesPerRev"
                    visible: root.measurement === CtrController.AngularEncoder
                    Layout.fillWidth: true
                    label: qsTr("Pulses/rev")
                    toolTip: qsTr("Pulses per revolution")
                    from: 1
                    to: 16777216
                    logarithmic: true
                    stepSize: 1
                    defaultValue: 360
                    formatter: v => root.whole(v)
                    value: root.controller.pulsesPerRevolution
                    onValueModified: v => root.controller.pulsesPerRevolution = Math.round(v)
                }
                FormRow {
                    visible: root.encoder
                    label: qsTr("Z index")
                    hint: qsTr("Z index on DIO 1")
                    ToggleSwitch {
                        accentColor: Theme.signalCh0
                        checked: root.controller.zIndexEnabled
                        onToggled: root.controller.zIndexEnabled = checked
                    }
                }
                KnobField {
                    objectName: "ctrZValue"
                    visible: root.encoder && root.controller.zIndexEnabled
                    Layout.fillWidth: true
                    label: qsTr("Z value")
                    toolTip: qsTr("Value at the Z index")
                    from: -1e6
                    to: 1e6
                    stepSize: 1
                    defaultValue: 0
                    formatter: v => Number(v.toFixed(3)) + " " + (root.measurement === CtrController.AngularEncoder ? "°" : root.controller.distanceUnit)
                    value: root.controller.zIndexValue
                    onValueModified: v => root.controller.zIndexValue = v
                }

                // Expected range (interval measurements): sets the timebase. One segment per
                // counter timebase: the bound that matters as the text, the full range in the tooltip.
                FormRow {
                    visible: root.interval
                    label: root.frequencyRange ? qsTr("Min freq.") : qsTr("Max time")
                    hint: root.frequencyRange ? qsTr("Min frequency") : qsTr("Max interval")
                    SegmentedControl {
                        objectName: "ctrExpectedRange"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: root.expectedRanges.map((r, i) => ({
                            text: root.expectedRangeLabel(r),
                            toolTip: qsTr("%1 · %2").arg(root.expectedRangeText(r)).arg(root.timebaseNames[i]) }))
                        currentIndex: root.expectedRangeIndex
                        onActivated: index => root.selectExpectedRange(index)
                    }
                }

                // Acquisition.
                FormRow {
                    visible: root.interval && !root.unsupported("counter.buffered")   // On Demand alone is no choice
                    label: qsTr("Acquire")
                    hint: qsTr("Acquisition")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: root.interval && !root.unsupported("counter.buffered")
                               ? [{ text: qsTr("On Demand"), toolTip: qsTr("On Demand · one reading per update") },
                                  { text: qsTr("Buffered"), toolTip: qsTr("Buffered · every interval, exact statistics") }]
                               : [{ text: qsTr("On Demand"), toolTip: qsTr("On Demand · one reading per update") }]
                        currentIndex: root.controller.sampling
                        onActivated: index => root.controller.sampling = index
                    }
                }
                KnobField {
                    objectName: "ctrUpdateInterval"
                    visible: root.controller.sampling === CtrController.OnDemand
                    Layout.fillWidth: true
                    label: qsTr("Update")
                    toolTip: qsTr("Update interval")
                    unit: "s"
                    from: 0.01
                    to: 10
                    logarithmic: true
                    digits: 3
                    defaultValue: 0.1
                    value: root.controller.updateInterval
                    onValueModified: v => root.controller.updateInterval = Number(v.toPrecision(3))
                }
                KnobField {
                    objectName: "ctrIntervals"
                    visible: root.controller.sampling === CtrController.Buffered
                    Layout.fillWidth: true
                    label: qsTr("Intervals")
                    toolTip: qsTr("Intervals per Single")
                    from: 1
                    to: 1000000
                    logarithmic: true
                    stepSize: 100
                    defaultValue: 1000
                    formatter: v => root.whole(v)
                    value: root.controller.bufferedSamples
                    onValueModified: v => root.controller.bufferedSamples = Math.round(v)
                }
            },

            // Pulse train (ctr0 output on DIO 3): in the output's colour.
            ChannelCard {
                objectName: "ctrPulseCard"
                visible: root.pulsing
                Layout.fillWidth: true
                title: qsTr("Pulse Train")
                subtitle: "DIO 3"
                color: Theme.signalAo0
                checkable: false

                FormRow {
                    label: qsTr("Define")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [qsTr("Freq & Duty"), qsTr("High & Low")]
                        currentIndex: root.controller.pulseDefinition
                        onActivated: index => root.controller.pulseDefinition = index
                    }
                }
                KnobField {
                    objectName: "ctrPulseFrequency"
                    visible: root.controller.pulseDefinition === CtrController.FrequencyAndDuty
                    Layout.fillWidth: true
                    label: qsTr("Frequency")
                    toolTip: qsTr("Pulse frequency · 100 MHz / %1").arg(Math.round(100e6 / root.controller.coercedPulseFrequency))
                    unit: "Hz"
                    digits: 5
                    from: root.controller.minimumPulseFrequency
                    to: root.controller.maximumPulseFrequency
                    logarithmic: true
                    defaultValue: 1000
                    value: root.controller.pulseFrequency
                    caption: Math.abs(root.controller.coercedPulseFrequency - root.controller.pulseFrequency) > 1e-9 * root.controller.pulseFrequency
                             ? qsTr("Actual %1").arg(Units.format(root.controller.coercedPulseFrequency, "Hz", 6)) : ""
                    onValueModified: v => root.controller.pulseFrequency = v
                }
                KnobField {
                    objectName: "ctrPulseDuty"
                    visible: root.controller.pulseDefinition === CtrController.FrequencyAndDuty
                    Layout.fillWidth: true
                    label: qsTr("Duty")
                    toolTip: qsTr("Duty cycle")
                    unit: "%"
                    digits: 4
                    from: 0.01
                    to: 99.99
                    stepSize: 1
                    defaultValue: 50
                    value: root.controller.dutyCycle * 100
                    formatter: v => Number(v.toFixed(2)) + " %"
                    caption: Math.abs(root.controller.coercedDutyCycle - root.controller.dutyCycle) > 1e-6
                             ? qsTr("Actual %1 %").arg((root.controller.coercedDutyCycle * 100).toFixed(3)) : ""
                    onValueModified: v => root.controller.dutyCycle = v / 100
                }
                KnobField {
                    visible: root.controller.pulseDefinition === CtrController.HighAndLowTime
                    Layout.fillWidth: true
                    label: qsTr("High")
                    toolTip: qsTr("High time")
                    unit: "s"
                    digits: 5
                    from: 20e-9
                    to: 40
                    logarithmic: true
                    value: root.controller.highTime
                    onValueModified: v => root.controller.setHighLowTimes(v, root.controller.lowTime)
                }
                KnobField {
                    visible: root.controller.pulseDefinition === CtrController.HighAndLowTime
                    Layout.fillWidth: true
                    label: qsTr("Low")
                    toolTip: qsTr("Low time")
                    unit: "s"
                    digits: 5
                    from: 20e-9
                    to: 40
                    logarithmic: true
                    value: root.controller.lowTime
                    onValueModified: v => root.controller.setHighLowTimes(root.controller.highTime, v)
                }
                FormRow {
                    visible: !root.unsupported("pulse.idleHigh")
                    label: qsTr("Idle")
                    hint: qsTr("Idle state")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [qsTr("Low"), qsTr("High")]
                        currentIndex: root.controller.idleHigh ? 1 : 0
                        onActivated: index => root.controller.idleHigh = index === 1
                    }
                }
                KnobField {
                    objectName: "ctrPulseDelay"
                    visible: !root.unsupported("pulse.initialDelay")
                    Layout.fillWidth: true
                    label: qsTr("Delay")
                    toolTip: qsTr("Initial delay")
                    unit: "s"
                    digits: 4
                    from: 0
                    to: 100
                    stepSize: 0.01
                    defaultValue: 0
                    value: root.controller.initialDelay
                    onValueModified: v => root.controller.initialDelay = v
                }
                FormRow {
                    label: qsTr("Pulses")
                    hint: qsTr("Continuous or finite")
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [qsTr("Continuous"), qsTr("Finite")]
                        currentIndex: root.controller.pulseGeneration
                        onActivated: index => root.controller.pulseGeneration = index
                    }
                }
                KnobField {
                    objectName: "ctrPulseCount"
                    visible: root.controller.pulseGeneration === CtrController.FinitePulses
                    Layout.fillWidth: true
                    label: qsTr("Count")
                    toolTip: qsTr("Number of pulses")
                    from: 1
                    to: 1e9
                    logarithmic: true
                    stepSize: 1
                    defaultValue: 10
                    formatter: v => root.whole(v)
                    value: root.controller.pulseCount
                    onValueModified: v => root.controller.pulseCount = Math.round(v)
                }
            },

            // FREQOUT (DIO 4): switch in the header, knob over the achievable frequencies.
            ChannelCard {
                objectName: "ctrFreqOutCard"
                Layout.fillWidth: true
                // Off: the knob stays (dimmed) so a frequency can be chosen before switching on.
                title: qsTr("FREQOUT")
                subtitle: "DIO 4"
                color: Theme.signalAo0
                checked: root.controller.freqOutEnabled
                onToggled: on => root.controller.freqOutEnabled = on
                KnobField {
                    objectName: "ctrFreqOut"
                    Layout.fillWidth: true
                    label: qsTr("Frequency")
                    unit: "Hz"
                    values: root.freqOutKnobValues
                    labels: root.freqOutKnobLabels
                    currentIndex: Math.max(0, Math.min(root.freqOutValues.length - 1, root.knobToTable(Math.max(0, root.controller.freqOutIndex))))
                    toolTip: qsTr("DIO 4 square wave (%1)").arg(root.controller.freqOutDivider)
                    onIndexActivated: index => root.controller.selectFreqOut(root.knobToTable(index))
                }
            }
        ]

        tools: ToolPalette {
            objectName: "ctrTools"
            columns: 2
            currentId: root.tool
            model: [{ id: "connections", text: qsTr("Pins"), icon: "pin", toolTip: qsTr("Connections") },
                    { id: "export", text: qsTr("Export"), icon: "export" }]
            onActivated: id => root.tool = root.tool === id ? "" : id
        }

        toolPanels: [
            ToolPanel {
                objectName: "ctrConnectionsPanel"
                visible: root.tool === "connections"
                title: qsTr("Connections")
                onCloseRequested: root.tool = ""
                PinMap {
                    Layout.fillWidth: true
                    pins: root.controller.pins
                }
                Caption {
                    visible: root.controller.conflictText.length > 0
                    text: root.controller.conflictText
                    color: Theme.warning
                }
            },
            ToolPanel {
                objectName: "ctrExportPanel"
                visible: root.tool === "export"
                title: qsTr("Export")
                onCloseRequested: root.tool = ""
                Button { Layout.fillWidth: true; text: qsTr("Export Data…"); icon.source: Theme.icon("download"); onClicked: { root.tool = ""; panel.exportData() } }
                Button { Layout.fillWidth: true; text: qsTr("Export Image…"); icon.source: Theme.icon("image"); onClicked: { root.tool = ""; panel.exportImage(false) } }
                Button { Layout.fillWidth: true; text: qsTr("Export PDF…"); icon.source: Theme.icon("file"); onClicked: { root.tool = ""; panel.exportImage(true) } }
                Button { Layout.fillWidth: true; text: qsTr("Print…"); icon.source: Theme.icon("printer"); onClicked: { root.tool = ""; panel.printPanel() } }
            }
        ]

        // Statistics of the readings (Measure): the same strip as the Multimeter's.
        measurements: [
            MeasurementStrip {
                objectName: "ctrStatistics"
                visible: root.measuring
                // A fixed model: the cards stay while the values change (a model built from the values
                // would recreate every card at each reading).
                Repeater {
                    model: 5
                    delegate: MeasurementCard {
                        required property int index
                        objectName: index === 0 ? "ctrStatCard" : index === 4 ? "ctrCountCard" : ""
                        title: [qsTr("Min"), qsTr("Max"), qsTr("Mean"), qsTr("σ"),
                                root.controller.sampling === CtrController.Buffered && root.interval ? qsTr("Intervals")
                                                                                                     : qsTr("Readings")][index]
                        color: Theme.signalCh0
                        value: {
                            const c = root.controller
                            if (index === 4)
                                return String(c.statCount)
                            if (c.statCount <= 0)
                                return ""
                            return index === 0 ? root.fmt(c.statMinimum, false) : index === 1 ? root.fmt(c.statMaximum, false)
                                 : index === 2 ? root.fmt(c.statMean, true) : root.fmt(c.statDeviation, true)
                        }
                        stats: null
                        removable: false
                    }
                }
                // Clears the statistics (and the count): distinct from the header's Reset (settings).
                MeasurementAction {
                    objectName: "ctrResetButton"
                    iconName: "refresh"
                    toolTip: root.counting || root.encoder ? qsTr("Reset Count") : qsTr("Reset Statistics")
                    onClicked: root.controller.resetMeasurement()
                }
            }
        ]
    }
}
