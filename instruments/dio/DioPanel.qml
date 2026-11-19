pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Digital I/O panel: the ELVISmx Digital Reader and Writer in one display. Pane header: Run,
// Single, radix. Display: the line strip (DIO 7 ... DIO 0, eight equal cells), the timeline's
// toolbar and the timeline, with the Inputs / Outputs values under it. Controls: Lines (Read /
// Write ranges, interval), Writer (pattern and settings); tool Labels. Inputs are drawn in the
// input green, outputs in the output orange.
Item {
    id: root

    required property DioController controller

    readonly property var presetNames: [qsTr("0–3"), qsTr("4–7"), qsTr("0–7"), qsTr("None")]
    readonly property bool hasInputs: root.controller.inputMask !== 0
    readonly property bool hasOutputs: root.controller.outputMask !== 0
    readonly property color inputColor: Theme.signalCh0
    readonly property color outputColor: Theme.signalAo0
    property string tool: ""
    // One radix for the panel (controller state): Inputs, Outputs, pattern number, cursor values.
    readonly property var radixChoices: [DioController.Hex, DioController.Binary, DioController.Decimal]
    function setRadix(r: int) {
        root.controller.inputRadix = r
        root.controller.outputRadix = r
    }
    // Pattern picture buttons (32 x 18 glyphs), in DioController.WriterPattern order.
    readonly property var patternGlyphs: [
        "M4 2h6v14H4z M6 4h2v4H6z M13 2h6v14h-6z M15 10h2v4h-2z M22 2h6v14h-6z M24 4h2v4h-2z",
        "M2 16h5v-3h5v-3h5v-3h5v-3h5v-3h3",
        "M2 14h5V4h5v10h5V4h5v10h5V4h3",
        "M2 15h5V4h4v11h16 M2 15h28 M14 2l4 2-4 2"
    ]
    readonly property var patternShortNames: [qsTr("Manual"), qsTr("Ramp"), qsTr("Alternate"), qsTr("Walking 1")]
    function toggleTool(id: string) {
        root.tool = root.tool === id ? "" : id
    }

    // The timeline's lanes, MSB first: all eight when each gets at least 14 px, else only the lines
    // in use (read or written).
    readonly property bool allLanes: timelinePlot.plotArea.height >= 8 * 14
    readonly property var lanes: {
        const all = [7, 6, 5, 4, 3, 2, 1, 0]
        if (allLanes)
            return all
        const used = all.filter(l => ((root.controller.inputMask | root.controller.outputMask) >> l) & 1)
        return used.length > 0 ? used : all
    }

    function laneColor(line: int): color {
        return (root.controller.outputMask >> line) & 1 ? root.outputColor
             : (root.controller.inputMask >> line) & 1 ? root.inputColor : Theme.textMuted
    }
    // Keys 0-7 flip the manual bit of an OUT line (panel focused).
    focus: true
    Keys.onPressed: event => {
        if (event.modifiers === Qt.NoModifier && event.key >= Qt.Key_0 && event.key <= Qt.Key_7) {
            root.controller.toggleLine(event.key - Qt.Key_0)
            event.accepted = true
        }
    }

    InstrumentPanel {
        id: panel
        objectName: "dioPane"
        anchors.fill: parent
        controller: root.controller
        // No display title or info line: the line groups are in the Lines card.
        showRunControls: false
        runBar.showTimeout: false
        inspector: []

        headerContent: [
            RunButton {
                objectName: "dioRunButton"
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Stopping
                enabled: root.controller.running || root.controller.canRun
                shortcutText: Theme.keys("Space")
                onToggled: root.controller.toggle()
            },
            // Single: idle = one pass; running = finish after this pass.
            Button {
                objectName: "dioSingleButton"
                text: qsTr("Single")
                icon.source: Theme.icon("step")
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
        // The number base of the values (the view group).
        displayTools: [
            SegmentedControl {
                objectName: "dioRadix"
                model: [{ text: qsTr("Hex"), toolTip: qsTr("Hexadecimal") },
                        { text: qsTr("Bin"), toolTip: qsTr("Binary") },
                        { text: qsTr("Dec"), toolTip: qsTr("Decimal") }]
                currentIndex: root.radixChoices.indexOf(root.controller.outputRadix)
                onActivated: index => root.setRadix(root.radixChoices[index])
            }
        ]

        // --- Display: the line strip and the timeline's toolbar over the timeline --------------
        Item {
            id: display
            objectName: "dioDisplay"
            anchors.fill: parent

            // The strip and the toolbar share the working surface; the timeline is the display.
            Rectangle {
                id: stripBlock
                anchors { left: parent.left; right: parent.right; top: parent.top }
                height: lineStrip.height + timelineBar.height + 2
                color: Theme.window

                // The line strip, MSB left (DIO 7 ... DIO 0) as in ELVISmx: eight equal cells in
                // one row. It takes the timeline's plot edges when the cells keep 64 px each,
                // else the whole width.
                Item {
                    id: lineStrip
                    objectName: "dioLineStrip"
                    readonly property bool aligned: (display.width - timelinePlot.leftMargin - timelinePlot.rightMargin) / 8 >= 64
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    anchors.leftMargin: aligned ? timelinePlot.leftMargin : 0
                    anchors.rightMargin: aligned ? timelinePlot.rightMargin : 0
                    height: stripRow.implicitHeight
                    RowLayout {
                        id: stripRow
                        anchors { left: parent.left; right: parent.right; top: parent.top }
                        spacing: 0
                        Repeater {
                            model: 8
                            delegate: DioLineCell {
                                required property int index
                                objectName: "dioLine" + line
                                inputColor: root.inputColor
                                outputColor: root.outputColor
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                Layout.minimumWidth: 54
                                compact: display.height < 300
                                controller: root.controller
                                line: 7 - index
                                lastColumn: index === 7
                            }
                        }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; top: lineStrip.bottom }
                    height: 1
                    color: Theme.separator
                }

                // The timeline's tools: the time window, cursors, pause, clear.
                Item {
                    id: timelineBar
                    objectName: "dioTimelineBar"
                    anchors { left: parent.left; right: parent.right; top: lineStrip.bottom; topMargin: 1 }
                    height: Theme.controlHeightS + 4
                    SegmentedControl {
                        objectName: "dioTimelineWindow"
                        anchors { left: parent.left; leftMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
                        compact: true
                        model: ["5 s", "10 s", "30 s", "60 s"]
                        currentIndex: root.controller.timelineWindow
                        onActivated: index => root.controller.timelineWindow = index
                    }
                    Row {
                        anchors { right: parent.right; rightMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
                        spacing: Theme.spacingXs
                        // The plot toolbar's actions (the timeline's lanes are fixed: X only).
                        IconButton {
                            objectName: "dioPointerButton"
                            size: Theme.controlHeightS
                            iconName: "pointer"
                            checked: timelinePlot.dragMode === Plot.NoDrag
                            toolTip: qsTr("Pointer")
                            onClicked: timelinePlot.dragMode = Plot.NoDrag
                        }
                        IconButton {
                            objectName: "dioZoomButton"
                            size: Theme.controlHeightS
                            iconName: "zoom-x"
                            checked: timelinePlot.dragMode === Plot.Zoom
                            toolTip: qsTr("Zoom") + "  " + (Theme.macShortcuts ? qsTr("⌘-drag") : qsTr("Ctrl+drag"))
                            onClicked: {
                                timelinePlot.zoomAxes = Plot.ZoomX
                                timelinePlot.dragMode = Plot.Zoom
                            }
                        }
                        IconButton {
                            objectName: "dioPanButton"
                            size: Theme.controlHeightS
                            iconName: "hand"
                            checked: timelinePlot.dragMode === Plot.Pan
                            toolTip: qsTr("Pan")
                            onClicked: timelinePlot.dragMode = Plot.Pan
                        }
                        IconButton {
                            objectName: "dioZoomFitButton"
                            size: Theme.controlHeightS
                            iconName: "zoom-fit"
                            toolTip: qsTr("Reset View")
                            onClicked: {
                                timelinePlot.resetView()
                                root.followArmed = true
                                root.resetTimelineView()
                            }
                        }
                        IconButton {
                            objectName: "dioAutoscaleButton"
                            size: Theme.controlHeightS
                            iconName: "autoscale"
                            toolTip: qsTr("Autoscale X")
                            onClicked: timelinePlot.autoscaleX()
                        }
                        IconButton {
                            id: cursorsButton
                            objectName: "dioCursorsButton"
                            size: Theme.controlHeightS
                            iconName: "crosshair"
                            checkable: true
                            toolTip: qsTr("Cursors")
                            onToggled: if (checked) root.placeCursors()
                        }
                        IconButton {
                            objectName: "dioPauseButton"
                            size: Theme.controlHeightS
                            iconName: root.controller.timelinePaused ? "play" : "pause"
                            checked: root.controller.timelinePaused
                            toolTip: root.controller.timelinePaused ? qsTr("Follow") : qsTr("Hold")
                            onClicked: {
                                root.controller.timelinePaused = !root.controller.timelinePaused
                                if (root.controller.timelinePaused) {
                                    timelinePlot.xAxis.follow = false
                                } else {
                                    root.followArmed = true
                                    root.resetTimelineView()
                                }
                            }
                        }
                        IconButton {
                            objectName: "dioClearButton"
                            size: Theme.controlHeightS
                            iconName: "trash"
                            toolTip: qsTr("Clear")
                            onClicked: {
                                root.controller.clearTimeline()
                                root.followArmed = true
                                root.resetTimelineView()
                            }
                        }
                    }
                }
                Rectangle {
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 1
                    color: Theme.separator
                }
            }

            // Timeline: the display's main area.
            BenchPlot {
                id: timelinePlot
                objectName: "dioTimeline"
                anchors { left: parent.left; right: parent.right; top: stripBlock.bottom; bottom: cursorBar.top }
                tools: false
                hoverReadout: false
                leftMargin: 48
                topMargin: 8
                xAxis {
                    unit: "s"
                    unitInLabels: true
                    follow: false   // see root.updateFollow()
                }
                yAxis { min: 0; max: root.lanes.length; divisions: root.lanes.length; minorTicks: 0; inverted: true; labelsVisible: false; interactive: false; minorGridVisible: false }
                PlotLogicTrace {
                    buffer: root.controller.timeline
                    lanes: root.lanes
                    laneNames: root.lanes.map(l => root.controller.lineName(l))
                    laneColors: root.lanes.map(l => root.laneColor(l))
                    fillOpacity: 0.32      // HIGH reads as a filled band
                    labelsVisible: true
                }
                PlotCursor {
                    id: cursor1
                    visible: cursorsButton.checked
                    label: "C1"
                    color: Theme.cursor1
                    readoutVisible: false
                }
                PlotCursor {
                    id: cursor2
                    visible: cursorsButton.checked
                    label: "C2"
                    color: Theme.cursor2
                    readoutVisible: false
                }
                Component.onCompleted: root.resetTimelineView()
                ToolTip.visible: timelineHover.hovered && timelineHover.point.position.y < 26
                ToolTip.delay: 900
                ToolTip.text: qsTr("Software timed · last 10 min")
                HoverHandler { id: timelineHover }
            }

            // Line values at the cursors: a row under the timeline, never over the traces.
            Rectangle {
                id: cursorBar
                objectName: "dioCursorBar"
                visible: cursorsButton.checked
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: visible ? cursorText.implicitHeight + 2 * Theme.spacingS : 0
                color: Theme.window
                Rectangle { anchors { left: parent.left; right: parent.right; top: parent.top } height: 1; color: Theme.separator }
                // Radix of the line values: the panel radix (controller state, saved), also
                // reachable here for Octal and SI.
                DioRadixButton {
                    id: cursorRadixButton
                    anchors { left: parent.left; leftMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
                    radix: root.controller.outputRadix
                    onRadixSelected: r => root.setRadix(r)
                }
                Text {
                    id: cursorText
                    anchors { left: cursorRadixButton.right; leftMargin: Theme.spacingS; verticalCenter: parent.verticalCenter }
                    textFormat: Text.PlainText
                    property bool elideAllowed: true
                    text: {
                        void root.controller.timelineEnd   // refresh while recording
                        return root.cursorLine("C1", cursor1.position) + "\n" + root.cursorLine("C2", cursor2.position)
                               + "\n" + qsTr("Δt %1").arg(Units.format(cursor2.position - cursor1.position, "s"))
                    }
                    color: Theme.text
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeCaption
                }
            }
        }

        // --- Controls: the column at the right, or the dock under the display ------------------
        controls: [
            // Lines: the ELVISmx "Lines to Read" / "Lines to Write" groups as shortcuts. A single
            // line's direction is set in its cell.
            ChannelCard {
                objectName: "dioLinesCard"
                Layout.fillWidth: true
                title: qsTr("Lines")
                checkable: false
                color: "transparent"
                Repeater {
                    model: [{ text: qsTr("Read"), write: false, tip: qsTr("Inputs") },
                            { text: qsTr("Write"), write: true, tip: qsTr("Outputs") }]
                    delegate: FormRow {
                        id: presetRow
                        required property var modelData
                        label: modelData.text
                        hint: modelData.tip
                        Layout.fillWidth: true
                        SegmentedControl {
                            objectName: presetRow.modelData.write ? "dioWritePreset" : "dioReadPreset"
                            Layout.fillWidth: true
                            stretch: true
                            // "None" belongs to no direction: no swatch.
                            model: root.presetNames.map((n, i) => i === 3 ? ({ text: n })
                                   : ({ text: n, color: presetRow.modelData.write ? root.outputColor : root.inputColor }))
                            currentIndex: presetRow.modelData.write ? root.controller.writePreset : root.controller.readPreset
                            onActivated: index => {
                                if (presetRow.modelData.write)
                                    root.controller.setWritePreset(index)
                                else
                                    root.controller.setReadPreset(index)
                            }
                        }
                    }
                }
                KnobField {
                    objectName: "dioSampleInterval"
                    Layout.fillWidth: true
                    label: qsTr("Interval")
                    unit: "s"
                    digits: 3
                    from: 0.01
                    to: 1
                    logarithmic: true
                    defaultValue: 0.1
                    value: root.controller.sampleInterval / 1000
                    toolTip: qsTr("Sample interval")
                    onValueModified: v => root.controller.sampleInterval = Math.round(v * 1000)
                }
                Text {
                    Layout.fillWidth: true
                    visible: root.controller.conflictMask !== 0
                    text: qsTr("Pauses other instruments")
                    color: Theme.caution
                    font.pixelSize: Theme.fontSizeCaption
                    HoverHandler { id: conflictHover }
                    ToolTip.visible: conflictHover.hovered
                    ToolTip.text: qsTr("Pauses the instrument using the lines · “–” to share")
                }
            },

            // Writer: pattern and its settings.
            ChannelCard {
                objectName: "dioWriterCard"
                visible: root.hasOutputs
                Layout.fillWidth: true
                title: qsTr("Writer")
                checkable: false
                color: root.outputColor
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: Theme.spacingXs
                    rowSpacing: Theme.spacingXs
                    Repeater {
                        model: 4
                        PictureButton {
                            required property int index
                            objectName: "dioPattern" + index
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: root.patternShortNames[index]
                            Accessible.name: root.patternShortNames[index]
                            implicitWidth: 56
                            glyph: root.patternGlyphs[index]
                            checked: root.controller.pattern === index
                            ToolTip.visible: hovered
                            ToolTip.delay: Theme.toolTipDelay
                            ToolTip.text: root.controller.patternNames[index] ?? ""
                            onClicked: root.controller.pattern = index
                        }
                    }
                }
                FormRow {
                    visible: root.controller.pattern === DioController.Manual
                    label: qsTr("Number")
                    hint: qsTr("Pattern number (0 to %1)").arg(root.controller.formatValue(root.controller.outputMax, root.controller.outputRadix, 0))
                    Layout.fillWidth: true
                    DioNumberField {
                        objectName: "dioManualValue"
                        Layout.fillWidth: true
                        value: root.controller.manualValue
                        maximum: root.controller.outputMax
                        radix: root.controller.outputRadix
                        bits: root.controller.outputWidth
                        onValueModified: v => root.controller.manualValue = v
                        // ELVISmx: a typed value that is malformed or too large is not accepted.
                        onEntered: text => {
                            const v = root.controller.parseEntry(text, root.controller.outputRadix)
                            if (v >= 0)
                                root.controller.manualValue = v
                        }
                        onRadixSelected: r => root.setRadix(r)
                    }
                }
                RowLayout {
                    visible: root.controller.pattern === DioController.Manual
                    Layout.fillWidth: true
                    spacing: Theme.spacingXs
                    Repeater {
                        model: [
                            { text: qsTr("Toggle"), action: DioController.Toggle, tip: qsTr("Invert") },
                            { text: qsTr("Rotate"), action: DioController.Rotate, tip: qsTr("Rotate one bit") },
                            { text: qsTr("Shift"), action: DioController.Shift, tip: qsTr("Shift one bit") }
                        ]
                        delegate: Button {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            text: modelData.text
                            leftPadding: 4
                            rightPadding: 4
                            focusPolicy: Qt.TabFocus
                            ToolTip.visible: hovered
                            ToolTip.delay: Theme.toolTipDelay
                            ToolTip.text: modelData.tip
                            onClicked: root.controller.applyAction(modelData.action)
                        }
                    }
                }
                FormRow {
                    visible: root.controller.pattern === DioController.Manual || root.controller.pattern === DioController.WalkingOnes
                    label: qsTr("Direction")
                    Layout.fillWidth: true
                    SegmentedControl {
                        Layout.fillWidth: true
                        stretch: true
                        model: [qsTr("Left"), qsTr("Right")]
                        currentIndex: root.controller.shiftDirection
                        onActivated: index => root.controller.shiftDirection = index
                    }
                }
                KnobField {
                    objectName: "dioStepInterval"
                    visible: root.controller.pattern !== DioController.Manual
                    Layout.fillWidth: true
                    label: qsTr("Step")
                    unit: "s"
                    digits: 3
                    from: 0.01
                    to: 10
                    logarithmic: true
                    defaultValue: 0.5
                    value: root.controller.stepInterval / 1000
                    toolTip: qsTr("Step interval")
                    onValueModified: v => root.controller.stepInterval = Math.round(v * 1000)
                }
            }
        ]

        tools: ToolPalette {
            objectName: "dioTools"
            currentId: root.tool
            model: [{ id: "labels", text: qsTr("Labels"), icon: "edit" }]
            onActivated: id => root.toggleTool(id)
        }

        toolPanels: [
            ToolPanel {
                objectName: "dioLabelsPanel"
                visible: root.tool === "labels"
                title: qsTr("Line Labels")
                onCloseRequested: root.tool = ""
                Repeater {
                    model: 8
                    delegate: RowLayout {
                        id: labelRow
                        required property int index
                        readonly property int line: 7 - index
                        readonly property var owner: root.controller.lineOwners[line] ?? ({})
                        Layout.fillWidth: true
                        Text {
                            Layout.preferredWidth: 44
                            text: "DIO " + labelRow.line
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeBody
                        }
                        TextField {
                            Layout.fillWidth: true
                            placeholderText: (labelRow.owner.owner ?? "").length > 0 ? labelRow.owner.owner : qsTr("Label")
                            text: root.controller.lineLabels[labelRow.line] ?? ""
                            font.pixelSize: Theme.fontSizeBody
                            onEditingFinished: root.controller.setLineLabel(labelRow.line, text)
                        }
                    }
                }
            }
        ]

        // --- Under the display: the Inputs / Outputs values ----------------------------------------
        measurements: [
            MeasurementStrip {
                objectName: "dioValues"
                component ValueCell: MeasurementCard {
                    required property bool output
                    removable: false
                    value: {
                        void root.controller.inputValue   // refresh on every new value
                        void root.controller.writtenValue
                        void root.controller.hasReading
                        void root.controller.inputRadix
                        void root.controller.outputRadix
                        return !output && !root.controller.hasReading ? "" : root.controller.numericValueText(output)
                    }
                }
                ValueCell {
                    objectName: "dioInputsValue"
                    visible: root.hasInputs
                    output: false
                    title: qsTr("Inputs")
                    color: root.inputColor
                }
                ValueCell {
                    objectName: "dioOutputsValue"
                    visible: root.hasOutputs
                    output: true
                    title: qsTr("Outputs")
                    color: root.outputColor
                }
            }
        ]
    }

    function resetTimelineView() {
        // Newest sample near the right edge; a fresh recording starts at the left edge.
        const span = root.controller.timelineSeconds
        const end = Math.max(root.controller.timelineEnd + span * 0.03, span)
        timelinePlot.xAxis.setRange(end - span, end)
        timelinePlot.xAxis.follow = false
        root.updateFollow()
    }
    // Scroll with the newest sample once the recording fills the window (a fresh recording starts
    // at 0 s). Set imperatively: panning or zooming by the user turns following off until Pause/
    // play, a window change or a new run.
    property bool followArmed: true
    function updateFollow() {
        if (root.followArmed && !root.controller.timelinePaused
                && root.controller.timelineEnd > timelinePlot.xAxis.max - root.controller.timelineSeconds * 0.03) {
            timelinePlot.xAxis.follow = true
            root.followArmed = false
        }
    }
    function placeCursors() {
        const lo = timelinePlot.xAxis.min, hi = timelinePlot.xAxis.max
        cursor1.position = lo + (hi - lo) * 0.3
        cursor2.position = lo + (hi - lo) * 0.6
    }
    function cursorLine(name: string, x: real): string {
        let bits = ""
        for (let l = 7; l >= 0; --l) {
            bits += root.controller.timeline.levelAt(l, x) ? "1" : "0"
            if (l === 4)
                bits += " "
        }
        return name + "  " + Units.format(x, "s") + "   7…0 " + bits + "   "
               + root.controller.valuesAtTime(x, root.controller.outputRadix)
    }
    Connections {
        target: root.controller
        function onTimelineWindowChanged() { root.followArmed = true; root.resetTimelineView() }
        function onStarted() { if (!root.controller.timelinePaused) { root.followArmed = true; root.resetTimelineView() } }
        function onTimelineAdvanced() { root.updateFollow() }
    }
}
