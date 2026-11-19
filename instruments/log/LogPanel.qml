pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Data Logger panel: pane header (Run/Stop, Record with Pause, sampling-rate knob); display with
// the multi-channel trend, the DMM's own chart when it is logged next to AI channels, and an
// overview of the whole run; the shared InstrumentColumn with the recording card, one ChannelCard
// per input (AI 0, AI 1, DMM) and the tool palette (Log File, Limits, Display); a bottom strip of
// per-channel value + statistics cards. Channel and sampling settings are locked while the logger
// runs; tooltips say why.
Item {
    id: root

    required property LogController controller

    readonly property string pauseIcon: "qrc:/qt/qml/MyBench/Instruments/Log/assets/pause.svg"
    readonly property bool analog: controller.ai0Enabled || controller.ai1Enabled
    // The recorded channels, without the rate (the rate is a field of the header).
    readonly property string channelsText: {
        const parts = []
        if (controller.ai0Enabled) parts.push("AI 0")
        if (controller.ai1Enabled) parts.push("AI 1")
        if (controller.dmmEnabled) parts.push(qsTr("DMM"))
        return parts.length > 0 ? parts.join(" · ") : " "
    }
    readonly property bool elvismx: controller.fileLayout === LogController.ElvismxLayout
    // The DMM channel's color (card, trace, value card).
    readonly property color dmmColor: Theme.signalRef      // same as the multimeter's reading
    // DMM functions of the logger (LogController.dmmFunctionNames order) as pictures.
    readonly property var dmmFunctions: [
        { icon: "dmm-vdc", caption: qsTr("DC V") },
        { icon: "dmm-vac", caption: qsTr("AC V") },
        { icon: "dmm-adc", caption: qsTr("DC A") },
        { icon: "dmm-aac", caption: qsTr("AC A") },
        { icon: "dmm-ohm", caption: qsTr("Ohms") }
    ]
    readonly property string lockedText: qsTr("Stop to change")
    readonly property var rates: [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]
    property int spanIndex: 1
    property string tool: ""
    property bool overviewVisible: true

    function entry(key: string): var {
        const list = root.controller.channelStats
        for (let i = 0; i < list.length; ++i) {
            if (list[i].key === key)
                return list[i]
        }
        return null
    }
    // A time window of the chart: TrendView fits the axis to the data (starts at the first sample,
    // grows with the run up to the window, then slides) while it follows.
    function showSpan(index: int) {
        root.spanIndex = index
        trend.following = true
        trend.fit()
    }
    function duration(seconds: real): string {
        const s = Math.floor(seconds)
        const hh = Math.floor(s / 3600)
        const mm = Math.floor(s / 60) % 60
        const ss = s % 60
        return (hh > 0 ? hh + ":" : "") + String(mm).padStart(hh > 0 ? 2 : 1, "0") + ":" + String(ss).padStart(2, "0")
    }
    function fileName(path: string): string {
        const i = Math.max(path.lastIndexOf("/"), path.lastIndexOf("\\"))
        return i >= 0 ? path.slice(i + 1) : path
    }
    function rateIndex(rate: real): int {
        let best = 0
        for (let i = 1; i < root.rates.length; ++i) {
            if (Math.abs(Math.log(root.rates[i] / rate)) < Math.abs(Math.log(root.rates[best] / rate)))
                best = i
        }
        return best
    }
    function cardStats(key: string, unit: string): var {
        const e = root.entry(key)
        if (!e || e.count <= 0)
            return { min: "—", max: "—", mean: "—", stdDev: "—" }
        // Numbers: the MeasurementCard formats them (4 significant digits, σ 3) in its `unit`.
        const f = v => isFinite(v) ? v : "—"
        return { min: f(e.minimum), max: f(e.maximum), mean: f(e.mean), stdDev: f(e.deviation) }
    }
    function cardValue(key: string, unit: string): string {
        const e = root.entry(key)
        if (!e || e.count <= 0)
            return ""
        return e.overload ? qsTr("Over") : Units.format(e.last, unit, 4)
    }
    function toggleTool(id: string) {
        root.tool = root.tool === id ? "" : id
    }

    FolderDialog {
        id: folderDialog
        title: qsTr("Log Folder")
        currentFolder: root.controller.folderUrl()
        onAccepted: root.controller.setFolderUrl(selectedFolder)
    }

    InstrumentPanel {
        id: panel
        objectName: "logPane"
        anchors.fill: parent
        controller: root.controller
        // No display title or info line: the channels are the card switches, the rate is its knob.
        showRunControls: false
        inspector: []
        displayInfo: root.controller.recording ? root.fileName(root.controller.recordFile) : root.channelsText

        stateText: root.controller.running && !root.controller.hasError && !root.controller.paused
                   ? qsTr("Running · %1").arg(root.duration(root.controller.runSeconds)) : ""

        headerContent: [
            RunButton {
                objectName: "logRunButton"
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Stopping
                enabled: root.controller.running || root.controller.canRun
                onToggled: root.controller.toggle()
            },
            Button {
                id: recordButton
                objectName: "logRecordButton"
                readonly property bool active: root.controller.recording || root.controller.recordPending
                text: active ? qsTr("Stop Rec") : qsTr("Record")
                icon.source: Theme.icon(active ? "stop" : "record")
                icon.color: Theme.negative
                focusPolicy: Qt.TabFocus
                Accessible.name: active ? qsTr("Stop") : qsTr("Record")
                // Fixed width: the label changes without moving the controls beside it.
                implicitWidth: Math.max(recordMetrics.advanceWidth, stopRecMetrics.advanceWidth) + leftPadding + rightPadding + 20 + Theme.spacingS
                TextMetrics { id: recordMetrics; font: recordButton.font; text: qsTr("Record") }
                TextMetrics { id: stopRecMetrics; font: recordButton.font; text: qsTr("Stop Rec") }
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: root.controller.recording ? qsTr("Close %1").arg(root.fileName(root.controller.recordFile))
                                                        : qsTr("New file in %1").arg(root.controller.folder)
                onClicked: {
                    if (active)
                        root.controller.stopRecording()
                    else
                        root.controller.startRecording()
                }
            }
        ]
        headerSettings: [
            // Wrapped so the "locked while running" tooltip shows over the disabled field.
            Item {
                visible: root.analog
                property int headerGroup: 2
                implicitWidth: rateKnob.implicitWidth
                implicitHeight: rateKnob.implicitHeight
                HoverHandler { id: rateHover }
                ToolTip.visible: root.controller.running && rateHover.hovered
                ToolTip.text: root.lockedText
                HeaderField {
                    id: rateKnob
                    objectName: "logRateKnob"
                    anchors.fill: parent
                    unit: "S/s"
                    values: root.rates
                    currentIndex: root.rateIndex(root.controller.samplingRate)
                    enabled: !root.controller.running
                    toolTip: qsTr("Sampling rate")
                    onIndexActivated: index => root.controller.samplingRate = root.rates[index]
                }
            }
        ]


        ColumnLayout {
            id: display
            objectName: "logDisplay"
            anchors.fill: parent
            spacing: 1

            TrendView {
                id: trend
                objectName: "logTrend"
                visible: root.analog
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: Theme.controlHeightL * 3
                windows: [ { text: "10 s", seconds: 10 }, { text: qsTr("1 min"), seconds: 60 }, { text: qsTr("10 min"), seconds: 600 },
                           { text: qsTr("1 h"), seconds: 3600 }, { text: qsTr("All"), seconds: 0 } ]
                windowIndex: root.spanIndex
                onWindowActivated: index => root.showSpan(index)
                onClearRequested: root.controller.clearChart()
                plot.objectName: "logPlot"
                plot.hoverReadout: true
                plot.leftMargin: Math.max(trend.plot.gutterLeft, dmmPlot.visible ? dmmPlot.gutterLeft : 0)
                plot.xAxis.labelFormat: PlotAxis.Time
                plot.xAxis.tickSpacing: 110
                plot.yAxis.autoScale: true
                plot.yAxis.min: root.controller.minimum
                plot.yAxis.max: root.controller.maximum
                plot.yAxis.unit: "V"
                plot.yAxis.unitInLabels: true
                PlotTrace { visible: root.controller.ai0Enabled; name: "AI 0"; unit: "V"; buffer: root.controller.ai0; color: Theme.signalCh0 }
                PlotTrace { visible: root.controller.ai1Enabled; name: "AI 1"; unit: "V"; buffer: root.controller.ai1; color: Theme.signalCh1 }
                buffers: [root.controller.ai0, root.controller.ai1, root.controller.dmm]
            }

            BenchPlot {
                id: dmmPlot
                objectName: "logDmmPlot"
                visible: root.controller.dmmEnabled
                Layout.fillWidth: true
                Layout.fillHeight: !root.analog
                Layout.preferredHeight: root.analog ? Math.max(Theme.controlHeightL * 3, display.height * 0.26) : -1   // not trend.height: polish loop
                interactive: !root.analog
                hoverReadout: true
                leftMargin: trend.visible ? trend.plot.leftMargin : -1
                xAxis { labelFormat: PlotAxis.Time; follow: !root.analog; tickSpacing: 110 }
                yAxis { autoScale: true; unit: root.controller.dmmUnit; unitInLabels: true }
                Component.onCompleted: xAxis.setRange(Date.now() / 1000 - 60, Date.now() / 1000)
                PlotTrace { name: qsTr("DMM"); unit: root.controller.dmmUnit; buffer: root.controller.dmm; color: root.dmmColor }
                Connections {
                    target: trend.plot.xAxis
                    enabled: root.analog
                    function onRangeChanged() { dmmPlot.xAxis.setViewRange(trend.plot.xAxis.min, trend.plot.xAxis.max) }
                }
            }

            // Overview of the whole run with the visible window (drag it to scroll back).
            BenchPlot {
                id: overview
                // Only while the trend above keeps its 200 px.
                visible: root.analog && root.overviewVisible
                         && (root.controller.ai0.count > 0 || root.controller.ai1.count > 0)
                         && display.height >= 200 + 80 + display.spacing
                Layout.fillWidth: true
                Layout.preferredHeight: 80
                interactive: false
                leftMargin: trend.plot.leftMargin
                yLabelsVisible: false
                xAxis { labelFormat: PlotAxis.Time; autoScale: true; interactive: false; tickSpacing: 110 }
                yAxis { autoScale: true; gridVisible: false; interactive: false }
                PlotTrace { visible: root.controller.ai0Enabled; buffer: root.controller.ai0; color: Theme.alpha(Theme.signalCh0, 0.8) }
                PlotTrace { visible: root.controller.ai1Enabled; buffer: root.controller.ai1; color: Theme.alpha(Theme.signalCh1, 0.8) }
                PlotRegion {
                    from: trend.plot.xAxis.min
                    to: trend.plot.xAxis.max
                    draggable: true
                    color: Theme.alpha(Theme.accent, 0.20)
                    onMoved: (from, to) => {
                        trend.following = false
                        trend.plot.xAxis.setViewRange(from, to)
                    }
                }
            }
        }


        // Cards of the column / dock
        controls: [
            // Recording: only while a file is written (the Record button shows the rest).
            ChannelCard {
                objectName: "logRecordState"
                visible: root.controller.recording
                Layout.fillWidth: true
                title: root.controller.recordPaused ? qsTr("Paused") : qsTr("Recording")
                subtitle: root.duration(root.controller.recordSeconds)
                color: "transparent"
                checkable: false
                headerExtras: [
                    Rectangle {
                        id: recDot
                        implicitWidth: 6
                        implicitHeight: 6
                        radius: 3
                        color: root.controller.recordPaused ? Theme.caution : Theme.negative
                        SequentialAnimation on opacity {
                            running: root.controller.recording && !root.controller.recordPaused && Theme.animations
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.25; duration: 700 }
                            NumberAnimation { to: 1; duration: 700 }
                            onStopped: recDot.opacity = 1
                        }
                    }
                ]
                Text {
                    Layout.fillWidth: true
                    text: root.fileName(root.controller.recordFile)
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeBody
                    elide: Text.ElideMiddle
                    property bool elideAllowed: true
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("%1 · %2 rows").arg(Units.format(root.controller.recordBytes, "B", 3)).arg(Math.round(root.controller.recordRows))
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.features: Theme.tabularFigures
                }
                Button {
                    Layout.fillWidth: true
                    text: root.controller.recordPaused ? qsTr("Resume") : qsTr("Pause")
                    icon.source: root.controller.recordPaused ? Theme.icon("record") : root.pauseIcon
                    focusPolicy: Qt.TabFocus
                    ToolTip.visible: hovered
                    ToolTip.delay: Theme.toolTipDelay
                    ToolTip.text: root.controller.recordPaused ? qsTr("Resume") : qsTr("Pause writing")
                    onClicked: root.controller.setRecordPaused(!root.controller.recordPaused)
                }
            },

            // The channel cards are locked while the logger runs; hovering them says why. They are
            // direct items of the column, so a band can flow them into columns.
            ChannelCard {
                objectName: "logCardAi0"
                Layout.fillWidth: true
                title: "AI 0"
                color: Theme.signalCh0
                checked: root.controller.ai0Enabled
                opacity: root.controller.running ? 0.6 : 1
                HoverHandler { id: lockHover0 }
                ToolTip.visible: root.controller.running && lockHover0.hovered
                ToolTip.text: root.lockedText
                subtitle: qsTr("±%1 V").arg(root.controller.hardwareRange)
                onToggled: on => {
                    if (root.controller.running)
                        checked = Qt.binding(() => root.controller.ai0Enabled)
                    else
                        root.controller.ai0Enabled = on
                }
            },
            ChannelCard {
                objectName: "logCardAi1"
                Layout.fillWidth: true
                title: "AI 1"
                color: Theme.signalCh1
                checked: root.controller.ai1Enabled
                opacity: root.controller.running ? 0.6 : 1
                HoverHandler { id: lockHover1 }
                ToolTip.visible: root.controller.running && lockHover1.hovered
                ToolTip.text: root.lockedText
                subtitle: qsTr("±%1 V").arg(root.controller.hardwareRange)
                onToggled: on => {
                    if (root.controller.running)
                        checked = Qt.binding(() => root.controller.ai1Enabled)
                    else
                        root.controller.ai1Enabled = on
                }
            },
            ChannelCard {
                id: dmmCard
                objectName: "logCardDmm"
                Layout.fillWidth: true
                title: qsTr("DMM")
                color: root.dmmColor
                collapseWhenOff: true          // off = header only (no dimmed button grid)
                checked: root.controller.dmmEnabled
                opacity: root.controller.running ? 0.6 : 1
                HoverHandler { id: lockHoverDmm }
                ToolTip.visible: root.controller.running && lockHoverDmm.hovered
                ToolTip.text: root.lockedText
                // While running (settings locked): function and range beside the name.
                readonly property bool editable: root.controller.dmmEnabled && !root.controller.running
                subtitle: !root.controller.dmmEnabled || editable ? ""
                          : (root.dmmFunctions[root.controller.dmmFunction]?.caption ?? "") + " · "
                            + (root.controller.dmmRangeNames[root.controller.dmmRange] ?? "")
                onToggled: on => {
                    if (root.controller.running)
                        checked = Qt.binding(() => root.controller.dmmEnabled)
                    else
                        root.controller.dmmEnabled = on
                }

                GridLayout {
                    objectName: "logDmmFunctions"
                    visible: dmmCard.editable
                    Layout.fillWidth: true
                    columns: 3
                    rowSpacing: Theme.spacingXs
                    columnSpacing: Theme.spacingXs
                    Repeater {
                        model: root.dmmFunctions
                        delegate: PictureButton {
                            required property var modelData
                            required property int index
                            objectName: "logDmmFunction" + index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitWidth: 56
                            text: modelData.caption
                            iconName: modelData.icon
                            checked: index === root.controller.dmmFunction
                            ToolTip.visible: hovered
                            ToolTip.text: root.controller.dmmFunctionNames[index] ?? ""
                            onClicked: root.controller.dmmFunction = index
                        }
                    }
                }
                KnobField {
                    objectName: "logDmmRange"
                    visible: dmmCard.editable
                    Layout.fillWidth: true
                    label: qsTr("Range")
                    values: root.controller.dmmRangeNames.map((n, i) => i)
                    labels: root.controller.dmmRangeNames
                    currentIndex: root.controller.dmmRange
                    toolTip: qsTr("Range")
                    onIndexActivated: index => root.controller.dmmRange = index
                }
            }

        ]

        tools: ToolPalette {
            objectName: "logTools"
            currentId: root.tool
            model: [
                { id: "file", text: qsTr("Log File"), icon: "folder-open" },
                { id: "limits", text: qsTr("Limits"), icon: "sliders" },
                { id: "display", text: qsTr("Display"), icon: "settings" }
            ]
            onActivated: id => root.toggleTool(id)
        }

        toolPanels: [
            ToolPanel {
                objectName: "filePanel"
                visible: root.tool === "file"
                title: qsTr("Log File")
                onCloseRequested: root.tool = ""

                FormRow {
                    label: qsTr("Folder")
                    Layout.fillWidth: true
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.spacingXs
                        TextField {
                            Layout.fillWidth: true
                            Layout.preferredWidth: 60
                            text: root.controller.folder
                            ToolTip.visible: hovered
                            ToolTip.text: text
                            onEditingFinished: root.controller.folder = text
                        }
                        IconButton {
                            iconName: "folder-open"
                            bordered: true
                            toolTip: qsTr("Choose Folder…")
                            onClicked: folderDialog.open()
                        }
                    }
                }
                FormRow {
                    label: qsTr("File name")
                    Layout.fillWidth: true
                    TextField {
                        Layout.fillWidth: true
                        text: root.controller.baseName
                        onEditingFinished: root.controller.baseName = text
                    }
                }
                FormRow {
                    label: qsTr("Format")
                    Layout.fillWidth: true
                    SegmentedControl {
                        objectName: "logFileType"
                        Layout.fillWidth: true
                        stretch: true
                        model: [ { text: qsTr("Tab"), toolTip: qsTr("Tab (.tsv)") },
                                 { text: "CSV", toolTip: qsTr("Comma (.csv)") },
                                 { text: qsTr("ELVISmx"), toolTip: qsTr("ELVISmx layout (.txt) · AI only") } ]
                        currentIndex: root.controller.fileType
                        onActivated: index => root.controller.fileType = index
                    }
                }
                ToggleSwitch {
                    text: qsTr("Date in file name")
                    checked: root.controller.appendTimestamp
                    onToggled: root.controller.appendTimestamp = checked
                }
                ToggleSwitch {
                    visible: root.elvismx
                    text: qsTr("Append to file")
                    checked: root.controller.appendToExisting
                    onToggled: root.controller.appendToExisting = checked
                }
                ToggleSwitch {
                    visible: !root.elvismx
                    text: qsTr("Timestamps")
                    checked: root.controller.timestampColumn
                    onToggled: root.controller.timestampColumn = checked
                }
                ToggleSwitch {
                    text: qsTr("Record on Run")
                    checked: root.controller.recordOnRun
                    onToggled: root.controller.recordOnRun = checked
                }
                RowLayout {
                    Layout.fillWidth: true
                    ToggleSwitch {
                        text: qsTr("Stop after")
                        checked: root.controller.stopAfterEnabled
                        onToggled: root.controller.stopAfterEnabled = checked
                    }
                    SiField {
                        Layout.fillWidth: true
                        Layout.preferredWidth: 60
                        enabled: root.controller.stopAfterEnabled
                        unit: "min"
                        engineering: false
                        decimals: 2
                        stepSize: 1
                        from: 0.01
                        to: 100000
                        value: root.controller.stopAfterMinutes
                        onValueModified: v => root.controller.stopAfterMinutes = v
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: root.controller.recording ? qsTr("%1 · %2 rows").arg(root.controller.recordFile)
                                                                                 .arg(Math.round(root.controller.recordRows))
                                                    : qsTr("Next: %1").arg(root.controller.nextFilePath)
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WrapAnywhere
                }
                Button {
                    text: qsTr("Show Folder")
                    icon.source: Theme.icon("folder-open")
                    onClicked: Qt.openUrlExternally(root.controller.folderUrl())
                }
            },

            ToolPanel {
                objectName: "limitsPanel"
                visible: root.tool === "limits"
                title: qsTr("Input Limits")
                onCloseRequested: root.tool = ""
                KnobField {
                    Layout.fillWidth: true
                    label: qsTr("Maximum")
                    unit: "V"
                    knobSize: 34
                    from: -10
                    to: 10
                    stepSize: 0.1
                    value: root.controller.maximum
                    enabled: !root.controller.running
                    toolTip: root.controller.running ? root.lockedText : qsTr("Maximum input (V)")
                    onValueModified: v => root.controller.maximum = v
                }
                KnobField {
                    Layout.fillWidth: true
                    label: qsTr("Minimum")
                    unit: "V"
                    knobSize: 34
                    from: -10
                    to: 10
                    stepSize: 0.1
                    value: root.controller.minimum
                    enabled: !root.controller.running
                    toolTip: root.controller.running ? root.lockedText : qsTr("Minimum input (V)")
                    onValueModified: v => root.controller.minimum = v
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.controller.minimum >= root.controller.maximum
                    text: qsTr("Minimum above maximum")
                    color: Theme.negative
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            },

            ToolPanel {
                objectName: "displayPanel"
                visible: root.tool === "display"
                title: qsTr("Display")
                onCloseRequested: root.tool = ""
                ToggleSwitch {
                    text: qsTr("Follow")
                    checked: trend.following
                    onToggled: {
                        trend.following = checked
                        checked = Qt.binding(() => trend.following)
                    }
                }
                ToggleSwitch {
                    text: qsTr("Whole run")
                    checked: root.overviewVisible
                    onToggled: root.overviewVisible = checked
                }
            }
        ]

        // --- Bottom: per-channel value + statistics cards ----------------------------------------
        measurements: [
            MeasurementStrip {
                objectName: "logCards"
                component ChannelValue: MeasurementCard {
                    property string key
                    removable: false
                    value: root.cardValue(key, unit)
                    stats: root.cardStats(key, unit)
                }
                ChannelValue {
                    objectName: "logValueAi0"
                    visible: root.controller.ai0Enabled
                    key: "ai0"
                    title: "AI 0"
                    color: Theme.signalCh0
                    unit: "V"
                }
                ChannelValue {
                    objectName: "logValueAi1"
                    visible: root.controller.ai1Enabled
                    key: "ai1"
                    title: "AI 1"
                    color: Theme.signalCh1
                    unit: "V"
                }
                ChannelValue {
                    objectName: "logValueDmm"
                    visible: root.controller.dmmEnabled
                    key: "dmm"
                    title: qsTr("DMM")
                    color: root.dmmColor
                    unit: root.controller.dmmUnit
                }
            }
        ]
    }
}