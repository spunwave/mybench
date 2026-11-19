pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Multimeter panel: pane header (Run/Stop, Single, Hold, Relative), the big readout with its
// status caption and the trend, the controls column (Function and Range picture buttons, keys 1–7;
// tools Logging, Connections, Options floating over the display), and a bottom strip of statistics
// cells (Min, Max, Mean, σ, Count) with the Restart Statistics icon.
Item {
    id: root

    required property DmmController controller

    readonly property bool compact: width < 600    // very narrow: 3 statistics cells
    property string tool: ""
    readonly property color readingColor: Theme.signalRef      // the reading: the trend, its statistics and the logger's DMM card

    // Function buttons. `fn` = DmmController.MeterFunction.
    readonly property var functions: [
        { fn: DmmController.DcVoltage, icon: "dmm-vdc", caption: qsTr("DC V"), toolTip: qsTr("DC Voltage") },
        { fn: DmmController.AcVoltage, icon: "dmm-vac", caption: qsTr("AC V"), toolTip: qsTr("AC Voltage") },
        { fn: DmmController.DcCurrent, icon: "dmm-adc", caption: qsTr("DC A"), toolTip: qsTr("DC Current") },
        { fn: DmmController.AcCurrent, icon: "dmm-aac", caption: qsTr("AC A"), toolTip: qsTr("AC Current") },
        { fn: DmmController.Resistance, icon: "dmm-ohm", caption: qsTr("Ω"), toolTip: qsTr("Resistance") },
        { fn: DmmController.Diode, icon: "dmm-diode", caption: qsTr("Diode"), toolTip: qsTr("Diode") },
        { fn: DmmController.Continuity, icon: "dmm-continuity", caption: qsTr("Continuity"), shortCaption: qsTr("Cont."), toolTip: qsTr("Continuity") }
    ]
    readonly property bool currentFunction: root.controller.selectedFunction === DmmController.DcCurrent
                                            || root.controller.selectedFunction === DmmController.AcCurrent
    readonly property bool continuity: root.controller.selectedFunction === DmmController.Continuity
    // A closed continuity or a conducting diode reads green.
    readonly property bool good: root.controller.hasReading && !root.controller.overload
                                 && ((root.continuity && root.controller.continuityClosed)
                                     || root.controller.diodeStatus === "GOOD")

    // Range pictograms (SVG paths on 32 × 18): a gauge whose needle sits further right for a
    // larger range; Auto = the gauge with a sweep arrow.
    function rangeGlyph(index: int, count: int): string {
        const arc = "M4 16 A12 12 0 0 1 28 16 "
        if (index < 0)
            return arc + "M9 12 A8 8 0 0 1 23 12 M20 9 L23 12 L24 8"
        const f = count > 1 ? index / (count - 1) : 0.5
        const a = Math.PI * (0.85 - 0.7 * f)
        const x = 16 + 10 * Math.cos(a)
        const y = 16 - 10 * Math.sin(a)
        return arc + "M16 16 L" + x.toFixed(1) + " " + y.toFixed(1)
    }
    // The caption under the readout, only what no control shows: Hold, the open circuit, the range
    // Auto picked, the null value while Relative is on, the diode state. Empty otherwise.
    readonly property string statusText: {
        const parts = []
        if (root.controller.hold)
            parts.push(qsTr("Hold"))
        if (root.continuity && root.controller.hasReading && !root.controller.continuityClosed)
            parts.push(qsTr("Open"))
        if (root.controller.effectiveAutoRange && root.controller.activeRangeLabel.length > 0)
            parts.push(qsTr("Range %1").arg(root.controller.activeRangeLabel))
        if (root.controller.nullOffset)
            parts.push(root.controller.nullArmed ? qsTr("Δ pending") : qsTr("Δ from %1").arg(root.controller.nullText))
        if (root.controller.diodeStatus.length > 0)
            parts.push(root.controller.diodeStatus === "GOOD" ? qsTr("Conducts") : qsTr("Open"))
        return parts.join("  ·  ")
    }

    function selectButton(index: int) {
        const f = root.functions[index]
        if (f && f.fn >= 0)
            root.controller.selectedFunction = f.fn
    }
    function toggleTool(id: string) {
        root.tool = root.tool === id ? "" : id
    }

    // Keys 1-7 select the function buttons in order (panel focused).
    focus: true
    Keys.onPressed: event => {
        if (event.modifiers === Qt.NoModifier && event.key >= Qt.Key_1 && event.key <= Qt.Key_9) {
            root.selectButton(event.key - Qt.Key_1)
            event.accepted = true
        }
    }
    Component.onCompleted: root.controller.autoStartIfEnabled()

    InstrumentPanel {
        id: panel
        objectName: "dmmPane"
        anchors.fill: parent
        controller: root.controller
        showRunControls: false
        inspector: []
        // The reading rate while measuring; the function and range are in the column, so the
        // controller's setup summary stays out of the header (a no-break space overrides it).
        displayInfo: root.controller.running && root.controller.sampleRate > 0
                     ? Units.format(root.controller.sampleRate, "S/s", 3) : "\u00a0"

        headerContent: [
            RunButton {
                objectName: "dmmRunButton"
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Stopping
                enabled: root.controller.running || root.controller.canRun
                onToggled: root.controller.toggle()
            },
            Button {
                objectName: "dmmSingleButton"
                text: qsTr("Single")
                icon.source: Theme.icon("step")
                Accessible.name: qsTr("Single")
                // Idle: one reading; measuring: stop after the next reading.
                enabled: root.controller.canRun
                         || (root.controller.state === InstrumentController.Running
                             && root.controller.runMode === InstrumentController.Continuous)
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Single")
                onClicked: root.controller.runOnce()
            }
        ]
        headerSettings: [
            Button {
                objectName: "dmmHoldButton"
                text: qsTr("Hold")
                icon.source: Theme.icon("pause")
                checkable: true
                checked: root.controller.hold
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Hold the readout")
                onClicked: {
                    root.controller.hold = checked
                    checked = Qt.binding(() => root.controller.hold)
                }
            },
            Button {
                objectName: "dmmRelativeButton"
                text: qsTr("Relative")
                checkable: true
                checked: root.controller.nullOffset
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Relative to the next reading")
                onClicked: {
                    root.controller.nullOffset = checked
                    checked = Qt.binding(() => root.controller.nullOffset)
                }
            }
        ]

        Item {
            id: display
            objectName: "dmmDisplay"
            anchors.fill: parent

            // The trend keeps 200 px (the layout test's plot minimum); a display under 320 px gives all
            // its height to the reading.
            readonly property real trendMinimum: 200
            readonly property bool trendShown: height >= 320
            // The reading takes the height the trend leaves (at most 60 % of it); its digits scale with it.
            readonly property real readoutHeight: trendShown ? Math.min(Math.round(height * 0.6), height - trendMinimum - Theme.spacingS)
                                                              : height
            readonly property int readoutFont: Math.round(Math.max(24, Math.min(140, width / 7.5, (readoutHeight - 36) / 1.25)))

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.spacingS

                // The reading, centred over the plotted area, in the height the display gives it.
                Item {
                    objectName: "dmmReadoutBlock"
                    Layout.fillWidth: true
                    Layout.fillHeight: !display.trendShown
                    Layout.preferredHeight: display.trendShown ? display.readoutHeight : -1

                    Readout {
                        id: readout
                        objectName: "dmmReadout"
                        anchors.verticalCenter: parent.verticalCenter
                        x: display.trendShown ? trend.plot.x + trend.plot.plotArea.x : 0
                        width: display.trendShown && trend.plot.plotArea.width > 0 ? trend.plot.plotArea.width : parent.width
                        valueText: root.controller.hasReading ? (root.controller.readingUnit.length > 0
                                   ? root.controller.readingText + " " + root.controller.readingUnit : root.controller.readingText) : "—"
                        color: root.controller.overload ? Theme.negative : root.good ? Theme.positive
                               : root.controller.hasReading ? Theme.text : Theme.textTertiary
                        stale: !root.controller.running || root.controller.hold
                        fontSize: display.readoutFont
                        caption: root.statusText.length > 0 ? root.statusText : "\u00a0"
                    }
                }

                TrendView {
                    id: trend
                    objectName: "trendView"
                    visible: display.trendShown
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: display.trendMinimum
                    windows: [ { text: qsTr("1 min"), seconds: 60 }, { text: qsTr("10 min"), seconds: 600 },
                               { text: qsTr("1 h"), seconds: 3600 }, { text: qsTr("All"), seconds: 0 } ]
                    windowIndex: root.controller.trendWindow
                    onWindowActivated: index => root.controller.trendWindow = index
                    onClearRequested: root.controller.clearTrend()
                    // The time axis starts at the first reading and grows up to the window.
                    buffers: [root.controller.trend]
                    plot.objectName: "trendPlot"
                    plot.xAxis.labelFormat: PlotAxis.Time
                    plot.yAxis.autoScale: true
                    plot.yAxis.autoScaleMargin: 0.2     // room above and below the trace
                    plot.yAxis.unit: root.controller.unit
                    plot.yAxis.unitInLabels: true
                    plot.yAxis.minimumSpan: root.controller.trendMinimumSpan
                    PlotTrace {
                        buffer: root.controller.trend
                        unit: root.controller.unit
                        color: root.readingColor
                    }
                }
            }
        }

        // Function and Range sections of picture buttons: the column at the right, or the dock under the display.
        controls: [
            ChannelCard {
                objectName: "dmmFunctionCard"
                Layout.fillWidth: true
                title: qsTr("Function")
                checkable: false
                color: "transparent"
                GridLayout {
                    objectName: "functionGrid"
                    Layout.fillWidth: true
                    // As many per row as fit, the rows balanced (no button alone on a row).
                    columns: Theme.balancedColumns(root.functions.length, width, 56, columnSpacing)
                    rowSpacing: Theme.spacingXs
                    columnSpacing: Theme.spacingXs
                    Repeater {
                        model: root.functions
                        delegate: PictureButton {
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitWidth: 56
                            leftPadding: 2
                            rightPadding: 2
                            // The short caption ("Cont.") where the full one does not fit.
                            text: modelData.shortCaption !== undefined && width < 68 ? modelData.shortCaption : modelData.caption
                            iconName: modelData.icon
                            checked: modelData.fn === root.controller.selectedFunction
                            ToolTip.visible: hovered
                            ToolTip.delay: Theme.toolTipDelay
                            ToolTip.text: qsTr("%1 (key %2)").arg(modelData.toolTip).arg(index + 1)
                            onClicked: root.controller.selectedFunction = modelData.fn
                        }
                    }
                }
            },

            ChannelCard {
                objectName: "dmmRangeCard"
                Layout.fillWidth: true
                title: qsTr("Range")
                checkable: false
                color: "transparent"
                GridLayout {
                    objectName: "rangeGrid"
                    Layout.fillWidth: true
                    columns: Theme.balancedColumns(rangeRepeater.count, width, 56, columnSpacing)
                    rowSpacing: Theme.spacingXs
                    columnSpacing: Theme.spacingXs
                    Repeater {
                        id: rangeRepeater
                        // Auto, then the function's ranges; Continuity always ranges automatically.
                        model: root.continuity ? [qsTr("Auto")] : [qsTr("Auto")].concat(root.controller.rangeLabels)
                        delegate: PictureButton {
                            required property string modelData
                            required property int index
                            objectName: "range" + index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitWidth: 56
                            text: modelData
                            glyph: root.rangeGlyph(index - 1, root.controller.rangeLabels.length)
                            checked: index === 0 ? root.controller.effectiveAutoRange
                                                 : !root.controller.effectiveAutoRange && root.controller.rangeIndex === index - 1
                            focusPolicy: Qt.TabFocus
                            ToolTip.visible: hovered
                            ToolTip.delay: Theme.toolTipDelay
                            ToolTip.text: index === 0 ? qsTr("Auto range")
                                                       : qsTr("Range %1").arg(modelData)
                            onClicked: {
                                if (index === 0) {
                                    root.controller.autoRange = true
                                } else {
                                    root.controller.rangeIndex = index - 1
                                    root.controller.autoRange = false
                                }
                            }
                        }
                    }
                }
            }
        ]

        tools: ToolPalette {
            objectName: "dmmTools"
            currentId: root.tool
            model: [
                { id: "logging", text: qsTr("Logging"), icon: "record", toolTip: qsTr("Logging") },
                { id: "connections", text: qsTr("Wiring"), icon: "instrument-dmm", toolTip: qsTr("Connections") },
                { id: "options", text: qsTr("Options"), icon: "settings", toolTip: qsTr("Options") }
            ]
            onActivated: id => root.toggleTool(id)
        }

        toolPanels: [
            ToolPanel {
                objectName: "loggingPanel"
                visible: root.tool === "logging"
                title: qsTr("Logging")
                onCloseRequested: root.tool = ""
                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: root.controller.recording ? qsTr("Stop") : qsTr("Record")
                        icon.source: Theme.icon(root.controller.recording ? "stop" : "record")
                        onClicked: root.controller.recording = !root.controller.recording
                    }
                    Item { Layout.fillWidth: true }
                    Text {
                        text: qsTr("%n row(s)", "", root.controller.logCount)
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeBody
                        font.features: Theme.tabularFigures
                    }
                }
                Text {
                    Layout.fillWidth: true
                    text: qsTr("Write to file")
                    HoverHandler { id: logHint }
                    ToolTip.visible: logHint.hovered
                    ToolTip.delay: Theme.toolTipDelay
                    ToolTip.text: qsTr("Tab-separated, CSV for .csv")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                }
                RowLayout {
                    Layout.fillWidth: true
                    Text {
                        Layout.fillWidth: true
                        text: root.controller.logFile.toString().length > 0 ? DataExport.localPath(root.controller.logFile) : qsTr("none")
                        elide: Text.ElideMiddle
                        color: root.controller.logFile.toString().length > 0 ? Theme.text : Theme.textTertiary
                        font.pixelSize: Theme.fontSizeBody
                    }
                    IconButton {
                        iconName: "folder-open"
                        toolTip: qsTr("Choose File…")
                        onClicked: {
                            streamDialog.selectedFile = DataExport.suggestedFileUrl("dmm-log", "tsv")
                            streamDialog.open()
                        }
                    }
                    IconButton {
                        visible: root.controller.logFile.toString().length > 0
                        iconName: "close"
                        toolTip: qsTr("No file")
                        onClicked: root.controller.logFile = ""
                    }
                }
                RowLayout {
                    Layout.fillWidth: true
                    Button {
                        text: qsTr("Save Log…")
                        enabled: root.controller.logCount > 0
                        onClicked: {
                            saveDialog.selectedFile = DataExport.suggestedFileUrl("dmm-log", "tsv")
                            saveDialog.open()
                        }
                    }
                    Button {
                        text: qsTr("Clear")
                        flat: true
                        enabled: root.controller.logCount > 0
                        onClicked: root.controller.clearLog()
                    }
                }
            },

            ToolPanel {
                objectName: "connectionsPanel"
                visible: root.tool === "connections"
                title: qsTr("Connections")
                onCloseRequested: root.tool = ""
                DmmJackDiagram {
                    Layout.fillWidth: true
                    Layout.preferredHeight: implicitHeight
                    currentMode: root.currentFunction
                }
                Text {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: root.currentFunction
                          ? qsTr("Red A HI · black COM · in series")
                          : qsTr("Red V Ω HI · black COM")
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    wrapMode: Text.WordWrap
                }
            },

            ToolPanel {
                objectName: "optionsPanel"
                visible: root.tool === "options"
                title: qsTr("Options")
                onCloseRequested: root.tool = ""
                ToggleSwitch {
                    text: qsTr("Continuity tone")
                    checked: root.controller.continuityBeep
                    enabled: root.controller.toneAvailable
                    onToggled: root.controller.continuityBeep = checked
                    ToolTip.visible: hovered
                    ToolTip.text: root.controller.toneAvailable ? qsTr("1 kHz below 15 Ω")
                                                                : qsTr("No sound output")
                }
                ToggleSwitch {
                    text: qsTr("Measure when shown")
                    checked: root.controller.autoStart
                    onToggled: root.controller.autoStart = checked
                }
            }
        ]

        // --- Bottom: statistics strip ------------------------------------------------------------
        measurements: [
            MeasurementStrip {
                objectName: "dmmStatistics"
                // A fixed model: the cards stay while the values change (a model built from the values
                // would recreate every card at each reading).
                Repeater {
                    model: 5
                    delegate: MeasurementCard {
                        required property int index
                        title: [qsTr("Min"), qsTr("Max"), qsTr("Mean"), qsTr("σ"), qsTr("Count")][index]
                        color: root.readingColor
                        value: {
                            const c = root.controller
                            if (index === 4)
                                return String(c.statCount) + (c.statOverloads > 0 ? qsTr(" · %1 over").arg(c.statOverloads) : "")
                            if (c.statCount <= 0)
                                return ""
                            return index === 0 ? c.formatValue(c.statMinimum) : index === 1 ? c.formatValue(c.statMaximum)
                                 : index === 2 ? c.formatValue(c.statMean, true) : c.formatValue(c.statStdDev, true)
                        }
                        stats: null
                        removable: false
                    }
                }
                // Restarts the statistics only (the header ↺ resets the settings).
                MeasurementAction {
                    objectName: "dmmResetStatistics"
                    iconName: "refresh"
                    toolTip: qsTr("Reset Statistics")
                    onClicked: root.controller.resetStatistics()
                }
            }
        ]
    }

    FileDialog {
        id: streamDialog
        title: qsTr("Log File")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("Tab-separated text (*.tsv *.txt)"), qsTr("CSV (*.csv)")]
        defaultSuffix: "tsv"
        currentFolder: DataExport.lastFolder
        onAccepted: root.controller.logFile = selectedFile
    }
    FileDialog {
        id: saveDialog
        title: qsTr("Save Log")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("Tab-separated text (*.tsv *.txt)"), qsTr("CSV (*.csv)")]
        defaultSuffix: "tsv"
        currentFolder: DataExport.lastFolder
        onAccepted: root.controller.saveLog(selectedFile)
    }
}
