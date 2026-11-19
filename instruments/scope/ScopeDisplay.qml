pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// The oscilloscope display: the 10 × 10 division YT graph or the XY graph, the scale legend, and the
// FFT spectrum below it. Markers on the graph edges are draggable (zero, trigger level, horizontal
// position); the wheel steps Time/div, Shift + wheel the Scale of the nearest channel.
Item {
    id: root

    required property ScopeController controller
    readonly property ScopeChannel ch0: controller.channel0
    readonly property ScopeChannel ch1: controller.channel1
    readonly property ScopeMath math: controller.math
    readonly property bool xyMode: controller.displayMode === ScopeController.XY
    readonly property bool edge: controller.triggerType === ScopeController.Edge && !controller.rolling
    readonly property bool fftShown: controller.fftShown
    readonly property int fftChannel: controller.fftSource === ScopeController.FftChannel1 ? 1 : 0
    // The trigger uses the chosen channel while it is enabled, else the other one (controller rule).
    readonly property int triggerChannel: {
        const wanted = controller.triggerSource === ScopeController.Chan1Source ? 1 : 0
        return (wanted === 0 ? ch0 : ch1).enabled ? wanted : 1 - wanted
    }
    readonly property alias ytPlot: ytPlot
    readonly property alias xyPlot: xyPlot
    readonly property alias fftPlot: fftPlot
    readonly property BenchPlot timePlot: xyMode ? xyPlot : ytPlot

    // Bound to this (not to controller.fftMaxFrequency, notified with every record) so the spectrum
    // keeps the user's zoom until the rate really changes.
    readonly property real fftNyquist: Math.max(1, controller.fftMaxFrequency)
    // The kept trace is drawn faded while Normal mode waits for a trigger.
    readonly property bool dimmed: controller.running && controller.waitingForTrigger
                                   && controller.noTriggerMode === ScopeController.KeepLastTrace
    // Persistence: a setting change (the controller's epoch) drops the afterglow of the old setting;
    // the plot drops it by itself when the display is resized or the axes change.
    readonly property int persistenceEpoch: controller.persistenceEpoch
    readonly property int persistence: controller.persistence

    readonly property string idleText: ""

    // Trace colors: the trace style's color when the user picked one, else the signal palette.
    function styleColor(style: TraceStyle, fallback: color): color {
        return style && style.lineColor.valid ? style.lineColor : fallback
    }
    function traceColor(index: int): color {
        return index === 0 ? styleColor(ch0.style, Theme.signalCh0)
             : index === 1 ? styleColor(ch1.style, Theme.signalCh1)
                           : styleColor(math.style, Theme.signalMath)
    }
    function faded(c: color): color {
        return root.dimmed ? Theme.alpha(c, 0.4) : c
    }
    function traceFor(index: int): PlotTrace {
        return index === 0 ? trace0 : index === 1 ? trace1 : mathTrace
    }
    function markerShape(pointStyle: int): int {
        switch (pointStyle) {
        case TraceStyle.FilledCircle: return PlotMarker.Circle
        case TraceStyle.Square:
        case TraceStyle.FilledSquare: return PlotMarker.Square
        case TraceStyle.Diamond:
        case TraceStyle.FilledDiamond: return PlotMarker.Diamond
        default: return PlotMarker.Ring
        }
    }

    // Legend text of a channel: name and scale ("CH0 1 V/div"), "AC" when AC coupled.
    function channelLegend(ch: ScopeChannel, name: string): string {
        return name + " " + ch.scaleLabel + "/div" + (ch.audio ? " AC" : "")
    }
    // The first enabled channel supplies the volt labels of the vertical axis.
    readonly property ScopeChannel labelChannel: ch0.enabled || !ch1.enabled ? ch0 : ch1

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.verticalStretchFactor: 3

            // ---- YT graph -----------------------------------------------------------------------
            BenchPlot {
                id: ytPlot
                objectName: "ytPlot"
                legendAlways: true     // entries carry the scale
                anchors.fill: parent
                visible: !root.xyMode
                hoverReadout: true
                graticule: Plot.Scope
                leftMargin: root.fftShown ? Math.max(ytPlot.gutterLeft, fftPlot.gutterLeft) : ytPlot.gutterLeft
                                placeholderText: root.idleText
                cursorsAvailable: true
                cursorsEnabled: root.controller.cursorsOn
                cursorDeltaVisible: false   // Δt and 1/Δt are in the cursor card under the display
                onCursorsToggled: on => root.controller.cursorsOn = on
                xAxis {
                    min: 0
                    max: root.controller.screenTime
                    divisions: 10
                    unit: "s"
                    lowerLimit: 0
                    upperLimit: root.controller.screenTime
                }
                yAxis {
                    min: -5
                    max: 5
                    divisions: 10
                    unit: "V"
                    labelScale: root.labelChannel.voltsPerDiv
                    labelOffset: -root.labelChannel.position * root.labelChannel.voltsPerDiv
                    interactive: false
                }

                // Wheel = Time/div, Shift + wheel = Scale of the channel nearest the pointer (wheel
                // up = smaller value, as a bench scope's knob turned clockwise).
                WheelHandler {
                    id: wheelTime
                    acceptedModifiers: Qt.NoModifier
                    property real accumulated: 0
                    onWheel: event => {
                        accumulated += event.angleDelta.y
                        const steps = Math.trunc(accumulated / 120)
                        if (steps !== 0) {
                            accumulated -= steps * 120
                            root.controller.stepTimeDiv(-steps)
                        }
                    }
                }
                WheelHandler {
                    id: wheelVolts
                    acceptedModifiers: Qt.ShiftModifier
                    property real accumulated: 0
                    onWheel: event => {
                        // Shift turns the wheel horizontal on some systems.
                        accumulated += event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        const steps = Math.trunc(accumulated / 120)
                        if (steps === 0)
                            return
                        accumulated -= steps * 120
                        const area = ytPlot.plotArea
                        const divisions = 5 - (wheelVolts.point.position.y - area.y) / area.height * 10
                        const channel = root.controller.channelNearestTo(divisions)
                        if (channel >= 0)
                            root.controller.stepChannelScale(channel, -steps)
                    }
                }

                PlotTrace {
                    id: refATrace
                    name: "REF A " + root.controller.refALabel
                    unit: "V"
                    buffer: root.controller.refA
                    visible: root.controller.refAAvailable && root.controller.refAVisible
                    color: Theme.signalRef
                    userStyle: root.controller.refAStyle
                    yScale: 1 / root.controller.refAScale
                    yOffset: root.controller.refAPosition
                }
                PlotTrace {
                    id: refBTrace
                    name: "REF B " + root.controller.refBLabel
                    unit: "V"
                    buffer: root.controller.refB
                    visible: root.controller.refBAvailable && root.controller.refBVisible
                    color: Theme.signalRef
                    userStyle: root.controller.refBStyle
                    yScale: 1 / root.controller.refBScale
                    yOffset: root.controller.refBPosition
                }
                PlotTrace {
                    id: mathTrace
                    name: qsTr("Math") + " " + root.math.functionName + " " + root.math.scaleLabels[root.math.scaleIndex] + "/div"
                    unit: root.math.unit
                    buffer: root.controller.mathTrace
                    visible: root.math.enabled
                    color: root.faded(Theme.signalMath)
                    userStyle: root.math.style
                    yScale: 1 / root.math.voltsPerDiv
                    yOffset: root.math.position
                    persistence: root.persistence
                    persistenceEpoch: root.persistenceEpoch
                }
                PlotTrace {
                    id: trace1
                    name: root.channelLegend(root.ch1, "CH1")
                    unit: "V"
                    buffer: root.controller.ch1
                    visible: root.ch1.enabled
                    color: root.faded(Theme.signalCh1)
                    userStyle: root.ch1.style
                    yScale: 1 / root.ch1.voltsPerDiv
                    yOffset: root.ch1.position
                    persistence: root.persistence
                    persistenceEpoch: root.persistenceEpoch
                }
                PlotTrace {
                    id: trace0
                    name: root.channelLegend(root.ch0, "CH0")
                    unit: "V"
                    buffer: root.controller.ch0
                    visible: root.ch0.enabled
                    color: root.faded(Theme.signalCh0)
                    userStyle: root.ch0.style
                    yScale: 1 / root.ch0.voltsPerDiv
                    yOffset: root.ch0.position
                    persistence: root.persistence
                    persistenceEpoch: root.persistenceEpoch
                }

                // Zero markers at the left edge: drag = the trace's position.
                PlotLine {
                    visible: root.math.enabled
                    value: root.math.position
                    handle: PlotLine.Start
                    label: "M"
                    color: root.traceColor(2)
                    lineMode: PlotLine.WhileDragging
                    onMoved: v => root.math.position = v
                }
                PlotLine {
                    visible: root.ch1.enabled
                    value: root.ch1.position
                    handle: PlotLine.Start
                    label: "1"
                    color: root.traceColor(1)
                    lineMode: PlotLine.WhileDragging
                    onMoved: v => root.ch1.position = Theme.snapTo(v, [0], 0.15)     // the centre line (divisions)
                }
                PlotLine {
                    visible: root.ch0.enabled
                    value: root.ch0.position
                    handle: PlotLine.Start
                    label: "0"
                    color: root.traceColor(0)
                    lineMode: PlotLine.WhileDragging
                    onMoved: v => root.ch0.position = Theme.snapTo(v, [0], 0.15)     // the centre line (divisions)
                }
                // Trigger level (right edge, in volts of the trigger channel) and horizontal
                // position (top edge), in the trigger channel's color.
                PlotLine {
                    objectName: "triggerLevelMarker"
                    visible: root.edge
                    trace: root.traceFor(root.triggerChannel)
                    value: root.controller.triggerLevel
                    handle: PlotLine.End
                    label: "T"
                    color: root.traceColor(root.triggerChannel)
                    style: PlotElement.Dash
                    lineMode: PlotLine.WhileDragging
                    // Snaps to 0 V within 0.15 division.
                    onMoved: v => root.controller.triggerLevel = Theme.snapTo(Math.round(v * 1000) / 1000, [0],
                                                                                0.15 * (root.triggerChannel === 1 ? root.ch1 : root.ch0).voltsPerDiv)
                }
                PlotLine {
                    objectName: "triggerPositionMarker"
                    visible: root.edge
                    orientation: PlotElement.Vertical
                    value: root.controller.horizontalPosition / 100 * root.controller.screenTime
                    handle: PlotLine.Start
                    label: "T"
                    color: root.traceColor(root.triggerChannel)
                    lineMode: PlotLine.WhileDragging
                    // Snaps to the middle (50 %) and the edges.
                    onMoved: v => root.controller.horizontalPosition = Theme.snapTo(Math.round(v / root.controller.screenTime * 100), [0, 50, 100], 2)
                }

                // Cursors C1 / C2 (Theme.cursor1 / cursor2): their readings are a card under the display.
                ScopeCursorItem {
                    id: cursor1
                    objectName: "cursorItem1"
                    cursor: root.controller.cursor1
                    shown: root.controller.cursorsOn
                    trace: root.traceFor(root.controller.cursor1.channel)
                }
                ScopeCursorItem {
                    id: cursor2
                    objectName: "cursorItem2"
                    cursor: root.controller.cursor2
                    shown: root.controller.cursorsOn
                    trace: root.traceFor(root.controller.cursor2.channel)
                }
                PlotLine {
                    visible: cursor1.crosshair
                    trace: cursor1.trace
                    value: cursor1.value
                    handle: PlotLine.NoHandle
                    draggable: false
                    color: cursor1.color
                    style: cursor1.style
                    width: cursor1.lineWidth
                }
                PlotLine {
                    visible: cursor2.crosshair
                    trace: cursor2.trace
                    value: cursor2.value
                    handle: PlotLine.NoHandle
                    draggable: false
                    color: cursor2.color
                    style: cursor2.style
                    width: cursor2.lineWidth
                }
                PlotMarker {
                    visible: cursor1.marked
                    x: cursor1.position
                    trace: cursor1.trace
                    color: cursor1.color
                    shape: root.markerShape(cursor1.cursor.style.pointStyle)
                    size: 8 + 2 * cursor1.lineWidth
                }
                PlotMarker {
                    visible: cursor2.marked
                    x: cursor2.position
                    trace: cursor2.trace
                    color: cursor2.color
                    shape: root.markerShape(cursor2.cursor.style.pointStyle)
                    size: 8 + 2 * cursor2.lineWidth
                }

                // Level cursors H1 / H2 (the cursor pair colors) on one trace; their card is under the display.
                PlotLine {
                    objectName: "levelCursor1"
                    visible: root.controller.levelCursorsOn
                    trace: root.traceFor(root.controller.levelCursorChannel)
                    value: root.controller.levelCursor1
                    handle: PlotLine.End
                    label: "H1"
                    color: Theme.cursor1
                    style: PlotElement.Dash
                    lineMode: PlotLine.Always
                    onMoved: v => root.controller.levelCursor1 = v
                }
                PlotLine {
                    objectName: "levelCursor2"
                    visible: root.controller.levelCursorsOn
                    trace: root.traceFor(root.controller.levelCursorChannel)
                    value: root.controller.levelCursor2
                    handle: PlotLine.End
                    label: "H2"
                    color: Theme.cursor2
                    style: PlotElement.Dash
                    lineMode: PlotLine.Always
                    onMoved: v => root.controller.levelCursor2 = v
                }
            }

            // ---- XY graph: CH0 on X, CH1 on Y ---------------------------------------------------
            BenchPlot {
                id: xyPlot
                objectName: "xyPlot"
                legendAlways: true
                // Square, so circles stay circles (Lissajous figures).
                // (The YT plot fills the same area with the same margins.)
                anchors.centerIn: parent
                width: Math.min(parent.width, parent.height - (ytPlot.height - ytPlot.plotArea.height)
                                              + (ytPlot.width - ytPlot.plotArea.width))
                height: parent.height
                visible: root.xyMode
                hoverReadout: true
                graticule: Plot.Scope
                placeholderText: root.ch0.enabled && root.ch1.enabled ? root.idleText
                                                                     : qsTr("XY: both channels")
                xAxis {
                    min: -5
                    max: 5
                    divisions: 10
                    unit: "V"
                    labelScale: root.ch0.voltsPerDiv
                    labelOffset: -root.ch0.position * root.ch0.voltsPerDiv
                }
                yAxis {
                    min: -5
                    max: 5
                    divisions: 10
                    unit: "V"
                    labelScale: root.ch1.voltsPerDiv
                    labelOffset: -root.ch1.position * root.ch1.voltsPerDiv
                }
                PlotTrace {
                    name: qsTr("CH1 %1/div vs CH0 %2/div").arg(root.ch1.scaleLabel).arg(root.ch0.scaleLabel)
                    buffer: root.controller.xyTrace
                    visible: root.ch0.enabled && root.ch1.enabled
                    color: Theme.signalCh0
                    userStyle: root.ch0.style
                    xScale: 1 / root.ch0.voltsPerDiv
                    xOffset: root.ch0.position
                    yScale: 1 / root.ch1.voltsPerDiv
                    yOffset: root.ch1.position
                    persistence: root.persistence
                    persistenceEpoch: root.persistenceEpoch
                }
            }
        }

        // ---- Spectrum of the FFT section's channel ----------------------------------------------------
        Rectangle {
            visible: root.fftShown
            Layout.fillWidth: true
            Layout.preferredHeight: Theme.borderWidth
            color: Theme.separator
        }
        BenchPlot {
            id: fftPlot
            objectName: "fftPlot"
            leftMargin: ytPlot.leftMargin
            visible: root.fftShown
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.verticalStretchFactor: 2
            hoverReadout: true
            xAxis {
                min: 0
                max: root.fftNyquist
                unit: "Hz"
                unitInLabels: true
                lowerLimit: 0
                upperLimit: root.fftNyquist
                minimumSpan: root.fftNyquist / 200
            }
            yAxis { min: -140; max: 20; unit: "dBV"; limitToData: true; limitMargin: 0.5; minimumSpan: 3 }
            PlotTrace {
                name: qsTr("Spectrum CH%1").arg(root.fftChannel)
                unit: "dBV"
                buffer: root.controller.fftTrace
                color: root.traceColor(root.fftChannel)
                fill: true
                fillOpacity: 0.12
            }
            PlotMarker {
                visible: !isNaN(root.math.peakFrequency)
                x: root.math.peakFrequency
                y: root.math.peakLevel
                shape: PlotMarker.TriangleDown
                color: root.traceColor(root.fftChannel)
                label: Units.format(root.math.peakFrequency, "Hz", 4) + "  " + root.math.peakLevel.toFixed(1) + " dBV"
            }
        }
        // The spectrum's source (the only FFT setting besides View FFT in the bar) and its legend.
        Item {
            objectName: "fftLegend"
            visible: root.fftShown
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(Theme.lineHeight + Theme.spacingS, fftRow.implicitHeight + 4)
            Row {
                id: fftRow
                x: fftPlot.plotArea.x
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Spectrum of")
                    color: Theme.displayText
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.Medium
                }
                SegmentedControl {
                    objectName: "fftSource"
                    anchors.verticalCenter: parent.verticalCenter
                    compact: true
                    // FftChannel0 / FftChannel1 (FftOff is the YT view of the bar).
                    model: [{ text: "CH0", color: root.traceColor(0), enabled: root.ch0.enabled || root.fftChannel === 0 },
                            { text: "CH1", color: root.traceColor(1), enabled: root.ch1.enabled || root.fftChannel === 1 }]
                    currentIndex: root.fftChannel
                    onActivated: index => root.controller.fftSource = index + 1
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    color: root.traceColor(root.fftChannel)
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: qsTr("Hann · dBV RMS")
                    color: Theme.displayTextSecondary
                    font.pixelSize: Theme.fontSizeCaption
                }
            }
        }
    }
}
