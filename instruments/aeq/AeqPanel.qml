pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Audio Equalizer panel: header (Run, Bypass, Flat), the tone response over the before / after
// spectrum with the mixer strip (band and volume faders, In / Out meters), Input and Output cards,
// Streaming and Display tools. The faders are the only editors of the bands and the volume.
Item {
    id: root

    required property AeqController controller

    // The colors of the three band curves (traces only): distinct from each other, the cursors and the accent.
    readonly property color bassColor: Theme.signalAo0
    readonly property color midColor: Theme.signalCh0
    readonly property color trebleColor: Theme.signalRef
    readonly property real topFrequency: Math.min(25000, 0.49 * controller.streamRate)
    property string tool                                       // the open tool panel ("" = none)

    // Short labels of the routing choices (controller order: AI 0, AI 1, audio L, audio R, none).
    readonly property var sourceShort: [qsTr("AI 0"), qsTr("AI 1"), qsTr("In L"), qsTr("In R"), qsTr("Off")]
    readonly property var sinkShort: [qsTr("AO 0"), qsTr("AO 1"), qsTr("Out L"), qsTr("Out R"), qsTr("Off")]
    readonly property var sourceColors: [Theme.signalCh0, Theme.signalCh1, Theme.signalCh0, Theme.signalCh1, undefined]
    readonly property var sinkColors: [Theme.signalAo0, Theme.signalAo1, Theme.signalAo0, Theme.signalAo1, undefined]
    function isAudioSource(s: int): bool { return s === AeqController.SourceAudioInLeft || s === AeqController.SourceAudioInRight }
    function isAudioSink(s: int): bool { return s === AeqController.SinkAudioOutLeft || s === AeqController.SinkAudioOutRight }
    readonly property bool audioIn: isAudioSource(controller.inputLeft) || isAudioSource(controller.inputRight)
    readonly property bool audioOut: isAudioSink(controller.outputLeft) || isAudioSink(controller.outputRight)
    readonly property var sourceChoices: audioIn ? [AeqController.SourceAudioInLeft, AeqController.SourceAudioInRight, AeqController.SourceNone]
                                                 : [AeqController.SourceAI0, AeqController.SourceAI1, AeqController.SourceNone]
    readonly property var sinkChoices: audioOut ? [AeqController.SinkAudioOutLeft, AeqController.SinkAudioOutRight, AeqController.SinkNone]
                                                : [AeqController.SinkAO0, AeqController.SinkAO1, AeqController.SinkNone]
    // Switching the kind never passes through a mixed routing: the right side is off meanwhile.
    function setInputKind(audio: bool) {
        controller.inputRight = AeqController.SourceNone
        controller.inputLeft = audio ? AeqController.SourceAudioInLeft : AeqController.SourceAI0
        controller.inputRight = audio ? AeqController.SourceAudioInRight : AeqController.SourceAI1
    }
    function setOutputKind(audio: bool) {
        controller.outputRight = AeqController.SinkNone
        controller.outputLeft = audio ? AeqController.SinkAudioOutLeft : AeqController.SinkAO0
        controller.outputRight = audio ? AeqController.SinkAudioOutRight : AeqController.SinkAO1
    }

    function meter(i: int): var {
        const m = root.controller.meters
        return i < m.length ? m[i] : { name: "", peak: -120, rms: -120, hold: -120, active: false }
    }
    function toggleTool(id: string) { tool = tool === id ? "" : id }

    // A labelled row inside a tool panel or card: the label above the control.
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
    // One side (L or R) of the routing: a form row with the choices of the selected kind.
    component SideChoices: FormRow {
        id: side
        property string sideName
        property var choices: []
        property var names: []
        property var colors: []                       // the signal colour of each choice (none: Off)
        property int current: 0
        readonly property string choiceText: choices.map(c => names[c]).join("|")   // for tests
        signal chosen(int choice)
        labelPosition: "top"
        label: side.sideName === "L" ? qsTr("Left") : qsTr("Right")
        hint: side.sideName === "L" ? qsTr("Equalizer channel L") : qsTr("Equalizer channel R")
        SegmentedControl {
            Layout.fillWidth: true
            stretch: true
            compact: true
            model: side.choices.map(c => ({ text: side.names[c], color: side.colors[c] }))
            currentIndex: side.choices.indexOf(side.current)
            onActivated: index => side.chosen(side.choices[index])
        }
    }

    InstrumentPanel {
        id: panel
        objectName: "aeqPane"
        anchors.fill: parent
        controller: root.controller
        // The display holds the faders and the response plot: it keeps the pane-proportional dock.
        dockFitsCards: false
        showRunControls: false
        runBar.showTimeout: false
        inspector: []
        // The state is one word, the latency the fact after it.
        stateText: root.controller.running ? qsTr("Streaming") : ""
        displayInfo: root.controller.running
                     ? qsTr("Latency %1").arg(Units.format(root.controller.latencySeconds + root.controller.blockSeconds, "s", 3))
                     : " "

        headerContent: [
            RunButton {
                objectName: "aeqRunButton"
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Stopping
                enabled: root.controller.running || root.controller.canRun
                onToggled: root.controller.toggle()
            }
        ]
        headerSettings: [
            Button {
                objectName: "bypassButton"
                text: qsTr("Bypass")
                checkable: true
                checked: root.controller.bypass
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Bypass the equalizer")
                onClicked: {
                    root.controller.bypass = !root.controller.bypass
                    checked = Qt.binding(() => root.controller.bypass)
                }
            },
            Button {
                objectName: "flatButton"
                text: qsTr("Flat")
                icon.source: Theme.icon("reset")
                enabled: !root.controller.bypass
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Flat: all bands 0 dB")
                onClicked: root.controller.flat()
            }
        ]

        // --- Display: the plots, with the mixer strip beside or under them ----------------------
        Item {
            id: display
            objectName: "aeqDisplay"
            anchors.fill: parent

            readonly property real gap: Theme.spacingS
            readonly property real plotMinimum: 200   // a plot is 200 px each way
            readonly property real slimResponse: 96                  // a slim response curve, under the plot minimum on purpose
            readonly property real faderWidth: width >= 800 ? 52 : 44
            readonly property real mixerWidth: mixer.implicitWidth + 2 * Theme.spacingS
            // Beside the plots while they keep 200 px; else the strip goes under them.
            readonly property bool beside: width >= mixerWidth + gap + plotMinimum
            // Under the plots: 196 px or 40 %, but the response curve keeps 80 px (the strip never under 140).
            readonly property real mixerHeight: beside ? height : Math.max(140, Math.min(Math.max(196, height * 0.4), height - gap - 80))
            readonly property real plotsWidth: beside ? width - mixerWidth - gap : width
            readonly property real plotsHeight: beside ? height : Math.max(0, height - mixerHeight - gap)
            // Both plots from 2 x 200 px; the response slim over a full spectrum from 96 + 200 px;
            // under that the response alone (the faders' effect, also while stopped).
            readonly property bool both: plotsHeight >= 2 * plotMinimum + gap
            readonly property bool stacked: both || plotsHeight >= slimResponse + gap + plotMinimum
            readonly property real responseHeight: both ? Math.max(plotMinimum, Math.min(Math.round(plotsHeight * 0.4), plotsHeight - gap - plotMinimum))
                                                 : stacked ? slimResponse : (plotsHeight >= plotMinimum ? plotsHeight : Math.min(slimResponse, plotsHeight))

            // The plots.
            ColumnLayout {
                id: plots
                x: 0
                y: 0
                width: display.plotsWidth
                height: display.plotsHeight
                spacing: display.gap

                // Tone response of the equalizer and its bands.
                BenchPlot {
                    id: responsePlot
                    objectName: "responsePlot"
                    Layout.fillWidth: true
                    Layout.preferredHeight: display.responseHeight
                    Layout.maximumHeight: display.responseHeight
                    interactive: false
                    legendVisible: false     // the band regions name the curves
                    placeholderText: ""
                    leftMargin: Math.max(gutterLeft, spectrumPlot.gutterLeft)
                    xAxis { scale: PlotAxis.Log; min: 20; max: root.topFrequency; unit: "Hz"; labelsVisible: !display.stacked }
                    yAxis { min: -18; max: 18; divisions: display.stacked && !display.both ? 2 : 6; unit: "dB"; unitInLabels: true }
                    // Band names in the bands' colours; the boundaries are thin dotted lines with their frequency.
                    PlotRegion { from: 20; to: 320; color: Theme.alpha(root.bassColor, 0.07); label: qsTr("Bass"); edgesVisible: false }
                    PlotRegion { from: 320; to: 2560; color: Theme.alpha(root.midColor, 0.07); label: qsTr("Midtone"); edgesVisible: false }
                    PlotRegion { from: 2560; to: Math.min(20840, root.topFrequency); color: Theme.alpha(root.trebleColor, 0.07); label: qsTr("Treble"); edgesVisible: false }
                    PlotLine { orientation: PlotElement.Vertical; value: 320; color: Theme.alpha(Theme.textMuted, 0.5); style: PlotElement.Dot; handle: PlotLine.NoHandle; label: "320 Hz"; draggable: false }
                    PlotLine { orientation: PlotElement.Vertical; value: 2560; color: Theme.alpha(Theme.textMuted, 0.5); style: PlotElement.Dot; handle: PlotLine.NoHandle; label: "2.56 kHz"; draggable: false }
                    PlotTrace { buffer: root.controller.responseBass; color: Theme.alpha(root.bassColor, 0.9); visible: !root.controller.bypass }
                    PlotTrace { buffer: root.controller.responseMid; color: Theme.alpha(root.midColor, 0.9); visible: !root.controller.bypass }
                    PlotTrace { buffer: root.controller.responseTreble; color: Theme.alpha(root.trebleColor, 0.9); visible: !root.controller.bypass }
                    PlotTrace { buffer: root.controller.response; name: qsTr("Tone"); unit: "dB"; color: Theme.text }
                    PlotLine { value: 0; color: Theme.alpha(Theme.textMuted, 0.6); style: PlotElement.Dot; handle: PlotLine.NoHandle; draggable: false }
                }

                // Before / after spectrum (1/24 octave) or the waveforms.
                BenchPlot {
                    id: spectrumPlot
                    objectName: "spectrumPlot"
                    visible: root.controller.view === AeqController.SpectrumView && display.stacked
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    hoverReadout: true
                    placeholderText: ""
                    leftMargin: responsePlot.leftMargin
                    xAxis { scale: PlotAxis.Log; min: 20; max: root.topFrequency; unit: "Hz"; unitInLabels: true; lowerLimit: 10; upperLimit: root.topFrequency * 1.5 }
                    yAxis { autoScale: root.controller.autoScaleSpectrum; min: -110; max: 10; unit: "dBV"; unitInLabels: true; limitToData: true; limitMargin: 0.5; minimumSpan: 3 }
                    // Band boundaries behind the before/after spectrum.
                    PlotLine { orientation: PlotElement.Vertical; value: 320; color: Theme.alpha(Theme.textMuted, root.controller.bypass ? 0.25 : 0.5); style: PlotElement.Dot; handle: PlotLine.NoHandle; draggable: false }
                    PlotLine { orientation: PlotElement.Vertical; value: 2560; color: Theme.alpha(Theme.textMuted, root.controller.bypass ? 0.25 : 0.5); style: PlotElement.Dot; handle: PlotLine.NoHandle; draggable: false }
                    PlotTrace {
                        visible: root.controller.showInput
                        name: qsTr("Before")
                        unit: "dBV"
                        buffer: root.controller.spectrumIn
                        color: Theme.alpha(Theme.textSecondary, 0.8)
                        step: true
                        fill: true
                        fillOpacity: 0.12
                    }
                    PlotTrace {
                        name: qsTr("After")
                        unit: "dBV"
                        buffer: root.controller.spectrumOut
                        color: Theme.accent
                        step: true
                        fill: true
                        fillOpacity: 0.18
                    }
                }
                BenchPlot {
                    id: timePlot
                    objectName: "timePlot"
                    visible: root.controller.view === AeqController.TimeView && display.stacked
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    hoverReadout: true
                    placeholderText: ""
                    leftMargin: responsePlot.leftMargin
                    xAxis { min: 0; max: root.controller.timeSpan; unit: "s"; unitInLabels: true }
                    yAxis { autoScale: root.controller.autoScaleTime; min: -2; max: 2; unit: "V"; unitInLabels: true }
                    PlotTrace { visible: root.controller.showInput; name: qsTr("Input"); unit: "V"; buffer: root.controller.timeIn; color: Theme.signalCh0 }
                    PlotTrace { name: qsTr("Output"); unit: "V"; buffer: root.controller.timeOut; color: Theme.signalAo0 }
                }
            }

            // The mixer strip: band faders, volume, In / Out meters (the only editors of the EQ).
            Rectangle {
                id: mixerFrame
                objectName: "console"
                x: display.beside ? display.width - width : 0
                y: display.beside ? 0 : display.height - height
                width: display.beside ? display.mixerWidth : display.width
                height: display.mixerHeight
                color: "transparent"
                Rectangle {   // hairline between the plots and the strip
                    width: display.beside ? 1 : parent.width
                    height: display.beside ? parent.height : 1
                    color: Theme.separator
                }

                RowLayout {
                    id: mixer
                    anchors {
                        horizontalCenter: display.beside ? undefined : parent.horizontalCenter
                        left: display.beside ? parent.left : undefined
                        top: parent.top
                        bottom: parent.bottom
                        margins: Theme.spacingS
                    }
                    spacing: Theme.spacingXs

                    AeqFader {
                        objectName: "fader_bass"
                        Layout.fillHeight: true
                        Layout.preferredWidth: display.faderWidth
                        accent: root.bassColor
                        label: qsTr("Bass")
                        value: root.controller.bass
                        enabled: !root.controller.bypass
                        onMoved: v => root.controller.bass = v
                    }
                    AeqFader {
                        objectName: "fader_mid"
                        Layout.fillHeight: true
                        Layout.preferredWidth: display.faderWidth
                        accent: root.midColor
                        label: qsTr("Midtone")
                        value: root.controller.midtone
                        enabled: !root.controller.bypass
                        onMoved: v => root.controller.midtone = v
                    }
                    AeqFader {
                        objectName: "fader_treble"
                        Layout.fillHeight: true
                        Layout.preferredWidth: display.faderWidth
                        accent: root.trebleColor
                        label: qsTr("Treble")
                        value: root.controller.treble
                        enabled: !root.controller.bypass
                        onMoved: v => root.controller.treble = v
                    }
                    Rectangle { Layout.fillHeight: true; Layout.topMargin: 24; Layout.bottomMargin: 24; Layout.leftMargin: 3; Layout.rightMargin: 3; implicitWidth: 1; color: Theme.separator }
                    AeqFader {
                        objectName: "fader_volume"
                        Layout.fillHeight: true
                        Layout.preferredWidth: display.faderWidth
                        label: qsTr("Volume")
                        from: 0
                        to: 1
                        stepSize: 0.01
                        resetValue: 0.5
                        centered: false
                        inputScale: 100
                        unitText: ""
                        value: root.controller.volume
                        valueText: Math.round(value * 100) + " %"
                        onMoved: v => root.controller.volume = v
                    }
                    Rectangle { Layout.fillHeight: true; Layout.topMargin: 24; Layout.bottomMargin: 24; Layout.leftMargin: 3; Layout.rightMargin: 3; implicitWidth: 1; color: Theme.separator }
                    Repeater {
                        model: [qsTr("In"), qsTr("Out")]
                        delegate: ColumnLayout {
                            id: meterGroup
                            required property int index
                            required property string modelData
                            Layout.fillHeight: true
                            Layout.leftMargin: index === 1 ? Theme.spacingXs : 0
                            spacing: Theme.spacingXs
                            // The meter bars start at the faders' tracks.
                            Item { implicitHeight: Theme.fontSizeValue + 6 }
                            RowLayout {
                                Layout.fillHeight: true
                                spacing: 2
                                Repeater {
                                    model: 2
                                    delegate: AeqMeter {
                                        required property int index
                                        Layout.fillHeight: true
                                        readonly property var m: root.meter(meterGroup.index * 2 + index)
                                        label: index === 0 ? "L" : "R"
                                        peak: m.peak
                                        rms: m.rms
                                        hold: m.hold
                                        active: m.active
                                    }
                                }
                            }
                            RowLayout {
                                Layout.alignment: Qt.AlignHCenter
                                spacing: 4
                                Led {
                                    visible: meterGroup.index === 1
                                    on: root.controller.clipping
                                    color: Theme.negative
                                    size: 7
                                    glow: root.controller.clipping
                                    ToolTip.visible: clipHover.hovered
                                    ToolTip.text: qsTr("Clipped at ±2 V")
                                    HoverHandler { id: clipHover }
                                }
                                Text {
                                    text: meterGroup.modelData
                                    color: Theme.textSecondary
                                    font.pixelSize: Theme.fontSizeCaption
                                }
                            }
                        }
                    }
                }
            }
        }

        // --- Cards: the column at the right, or the dock under the display ----------------------
        controls: [
            ChannelCard {
                objectName: "inputCard"
                Layout.fillWidth: true
                title: qsTr("Input")
                color: Theme.signalCh0
                checkable: false

                FormRow {
                    label: qsTr("Type")
                    // Simulator: the outputs loop back to these inputs (the routing below changes it).
                    hint: root.controller.feedbackInSimulator ? qsTr("Simulator: loopback") : ""
                    SegmentedControl {
                        objectName: "inputKind"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [{ text: qsTr("Audio in"), toolTip: qsTr("Audio In jack, L/R · ±2 V") },
                                { text: qsTr("AI 0 / AI 1"), toolTip: qsTr("AI 0 / AI 1 · ±2 V") }]
                        currentIndex: root.audioIn ? 0 : 1
                        onActivated: index => root.setInputKind(index === 0)
                    }
                }
                SideChoices {
                    objectName: "inputLeft"
                    sideName: "L"
                    choices: root.sourceChoices
                    names: root.sourceShort
                    colors: root.sourceColors
                    current: root.controller.inputLeft
                    onChosen: choice => root.controller.inputLeft = choice
                }
                SideChoices {
                    objectName: "inputRight"
                    sideName: "R"
                    choices: root.sourceChoices
                    names: root.sourceShort
                    colors: root.sourceColors
                    current: root.controller.inputRight
                    onChosen: choice => root.controller.inputRight = choice
                }
            },

            ChannelCard {
                objectName: "outputCard"
                Layout.fillWidth: true
                title: qsTr("Output")
                color: Theme.signalAo0
                checkable: false

                FormRow {
                    label: qsTr("Type")
                    SegmentedControl {
                        objectName: "outputKind"
                        Layout.fillWidth: true
                        stretch: true
                        compact: true
                        model: [{ text: qsTr("Audio out"), toolTip: qsTr("Audio Out jack, L/R · ±2 V") },
                                { text: qsTr("AO 0 / AO 1"), toolTip: qsTr("AO 0 / AO 1 · ±2 V") }]
                        currentIndex: root.audioOut ? 0 : 1
                        onActivated: index => root.setOutputKind(index === 0)
                    }
                }
                SideChoices {
                    objectName: "outputLeft"
                    sideName: "L"
                    choices: root.sinkChoices
                    names: root.sinkShort
                    colors: root.sinkColors
                    current: root.controller.outputLeft
                    onChosen: choice => root.controller.outputLeft = choice
                }
                SideChoices {
                    objectName: "outputRight"
                    sideName: "R"
                    choices: root.sinkChoices
                    names: root.sinkShort
                    colors: root.sinkColors
                    current: root.controller.outputRight
                    onChosen: choice => root.controller.outputRight = choice
                }
            }
        ]

        tools: ToolPalette {
            objectName: "aeqTools"
            currentId: root.tool
            model: [{ id: "streaming", text: qsTr("Streaming"), icon: "activity" },
                    { id: "display", text: qsTr("Display"), icon: "grid" }]
            onActivated: id => root.toggleTool(id)
        }

        toolPanels: [
            ToolPanel {
                objectName: "streamingPanel"
                visible: root.tool === "streaming"
                title: qsTr("Streaming")
                onCloseRequested: root.tool = ""
                ToolRow {
                    label: qsTr("Sample rate")
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 4
                        columnSpacing: 4
                        Repeater {
                            model: root.controller.rateNames
                            delegate: PictureButton {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                text: modelData
                                checked: root.controller.rateIndex === index
                                onClicked: root.controller.rateIndex = index
                            }
                        }
                    }
                }
                ToolRow {
                    label: qsTr("Output buffer · %1")
                               .arg(Units.format(root.controller.latencySeconds + root.controller.blockSeconds, "s", 3))
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 4
                        columnSpacing: 4
                        Repeater {
                            model: root.controller.latencyNames
                            delegate: PictureButton {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                text: modelData
                                checked: root.controller.latencyIndex === index
                                onClicked: root.controller.latencyIndex = index
                            }
                        }
                    }
                }
                Text {
                    visible: root.controller.dropouts > 0
                    text: qsTr("Dropouts %1").arg(root.controller.dropouts)
                    color: Theme.caution
                    font.pixelSize: Theme.fontSizeCaption
                }
            },

            ToolPanel {
                objectName: "displayPanel"
                visible: root.tool === "display"
                title: qsTr("Display")
                onCloseRequested: root.tool = ""
                ToolRow {
                    label: qsTr("View")
                    SegmentedControl {
                        Layout.fillWidth: true
                        model: [qsTr("Spectrum"), qsTr("Time")]
                        currentIndex: root.controller.view
                        onActivated: index => root.controller.view = index
                    }
                }
                ToolRow {
                    label: qsTr("Channel")
                    SegmentedControl {
                        Layout.fillWidth: true
                        model: [qsTr("L"), qsTr("R")]
                        currentIndex: root.controller.displayChannel
                        onActivated: index => root.controller.displayChannel = index
                    }
                }
                ToolRow {
                    visible: root.controller.view === AeqController.SpectrumView
                    label: qsTr("Averaging")
                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        rowSpacing: 4
                        columnSpacing: 4
                        Repeater {
                            model: root.controller.averagingNames
                            delegate: PictureButton {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                text: modelData
                                checked: root.controller.averagingIndex === index
                                onClicked: root.controller.averagingIndex = index
                            }
                        }
                    }
                }
                ToolRow {
                    visible: root.controller.view === AeqController.TimeView
                    label: qsTr("Time span")
                    SegmentedControl {
                        Layout.fillWidth: true
                        model: root.controller.timeSpanNames
                        currentIndex: root.controller.timeSpanIndex
                        onActivated: index => root.controller.timeSpanIndex = index
                    }
                }
                CheckBox {
                    text: qsTr("Autoscale")
                    checked: root.controller.view === AeqController.SpectrumView ? root.controller.autoScaleSpectrum : root.controller.autoScaleTime
                    onToggled: {
                        if (root.controller.view === AeqController.SpectrumView)
                            root.controller.autoScaleSpectrum = checked
                        else
                            root.controller.autoScaleTime = checked
                    }
                }
                CheckBox {
                    text: qsTr("Show input")
                    checked: root.controller.showInput
                    onToggled: root.controller.showInput = checked
                }
            }
        ]
    }
}
