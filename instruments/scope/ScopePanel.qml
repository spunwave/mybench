pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// The oscilloscope pane, PicoScope-7 style: instrument bar (Run/Stop, Single, timebase, trigger
// position, view, Autoscale), the display, a right column of channel, trigger and math cards with a
// tool palette (Measure, Cursors, References, Display), and the measurement cards under the display.
// Every setting has exactly one control; settings that do not apply are hidden.
Item {
    id: root

    required property ScopeController controller
    readonly property ScopeChannel ch0: controller.channel0
    readonly property ScopeChannel ch1: controller.channel1
    readonly property ScopeMath math: controller.math
    readonly property bool edge: controller.triggerType === ScopeController.Edge
    readonly property int triggerChannel: controller.triggerSource === ScopeController.Chan1Source ? 1 : 0
    readonly property alias panel: panel
    readonly property alias display: display
    readonly property alias measurementModel: measurementModel
    // The open tool panel ("" = none): measure, cursors, references, display.
    // --scope-tool=<id> opens one at start (screenshots of the panels).
    property string tool: AppInfo.value("scope-tool")
    // Pictograms of the measurement types (SVG paths on 32×18).
    readonly property var measurementGlyphs: ({
        [ScopeChannel.Rms]: "M2 9 C6 1 10 1 14 9 S22 17 26 9 30 5 30 5",
        [ScopeChannel.Frequency]: "M2 15 V4 H9 V15 H16 V4 H23 V15 H30",
        [ScopeChannel.PeakToPeak]: "M6 2 H26 M6 16 H26 M16 3 V15",
        [ScopeChannel.Peak]: "M2 16 H30 M16 2 V16 M10 2 H22",
        [ScopeChannel.Mean]: "M2 9 H30",
        [ScopeChannel.Minimum]: "M2 4 C10 4 12 15 16 15 S22 4 30 4 M10 17 H22",
        [ScopeChannel.Maximum]: "M2 14 C10 14 12 3 16 3 S22 14 30 14 M10 1 H22",
        [ScopeChannel.Amplitude]: "M4 3 H28 M4 15 H28 M10 3 V15",
        [ScopeChannel.Period]: "M3 4 V14 M29 4 V14 M3 9 H29",
        [ScopeChannel.DutyCycle]: "M2 15 H6 V3 H16 V15 H30",
        [ScopeChannel.RiseTime]: "M2 15 H10 L22 3 H30",
        [ScopeChannel.FallTime]: "M2 3 H10 L22 15 H30",
        [ScopeChannel.PositiveWidth]: "M2 15 H9 V3 H23 V15 H30",
        [ScopeChannel.NegativeWidth]: "M2 3 H9 V15 H23 V3 H30",
        [ScopeChannel.Overshoot]: "M2 15 H10 V2 L13 5 H30",
        [ScopeChannel.Phase]: "M2 9 C6 1 10 1 14 9 S22 17 26 9 M8 9 C12 1 16 1 20 9",
        [ScopeChannel.CounterFrequency]: "M2 15 V4 H9 V15 H16 V4 H23 V15 H30 M5 2 V6 M19 2 V6",
        [ScopeChannel.AcRms]: "M2 9 C6 1 10 1 14 9 S22 17 26 9 M2 9 H30",
        [ScopeChannel.CrestFactor]: "M2 12 C6 8 10 8 14 12 L16 2 L18 12 C22 8 26 8 30 12",
        [ScopeChannel.Preshoot]: "M2 15 H10 L13 17 V3 H30",
        [ScopeChannel.SlewRate]: "M2 16 L30 2 M18 10 H26 V2"
    })
    // Picture-button captions that fit a third of the panel (the tooltip has the full name).
    readonly property var measurementShortLabels: ({
        [ScopeChannel.PeakToPeak]: qsTr("Pk-pk"),
        [ScopeChannel.CounterFrequency]: qsTr("Edge freq"),
        [ScopeChannel.PositiveWidth]: qsTr("+ Width"),
        [ScopeChannel.NegativeWidth]: qsTr("− Width")
    })
    property int statistics: 1          // measurement cards: 0 off, 1 last 100, 2 all
    property int cardSource: -1         // measurement cards: -1 every trace, else 0 / 1 / 2
    function toggleTool(id: string) {
        tool = tool === id ? "" : id
    }

    // The display's status: only what the bar does not show (timebase and trigger live in their
    // knobs). Empty in the usual case, so the display keeps the whole height.
    readonly property string summary: {
        const parts = []
        if (controller.rolling)
            parts.push(qsTr("Roll"))
        if (controller.averaging > 1)
            parts.push(qsTr("Avg ×%1").arg(controller.averaging))
        if (controller.persistence > 0)
            parts.push(qsTr("Persist %1").arg(Units.format(controller.persistence / 1000, "s", 2)))
        return parts.join("  ·  ")
    }
    // The traces a cursor or the level cursors can follow (index 0, 1, 2 = math).
    readonly property var traceChoices: [{ text: "CH0", color: display.traceColor(0) }, { text: "CH1", color: display.traceColor(1) },
                                         { text: qsTr("Math"), color: display.traceColor(2) }]

    ScopeMeasurements {
        id: measurementModel
        controller: root.controller
        ch0Color: display.traceColor(0)
        ch1Color: display.traceColor(1)
        mathColor: display.traceColor(2)
    }


    InstrumentPanel {
        id: panel
        anchors.fill: parent
        controller: root.controller
        displayTitle: root.summary
        displayInfo: qsTr("%1 · %2 samples").arg(Units.format(root.controller.plannedRate, "S/s", 4))
                                           .arg(root.controller.plannedRecordLength.toLocaleString(Qt.locale(), "f", 0))
        showRunControls: false      // Run/Stop and Single are in headerContent
        runBar.showTimeout: false
        inspector: []

        // Run/Stop and Single; then the settings; then the display mode. The state ("Triggered")
        // and its detail ("50 kS/s · 2,501 samples") are the header's.
        headerContent: [
            RunButton {
                objectName: "scopeRunButton"
                running: root.controller.running
                busy: root.controller.state === InstrumentController.Starting
                      || root.controller.state === InstrumentController.Stopping
                enabled: running ? root.controller.state !== InstrumentController.Stopping : root.controller.canRun
                shortcutText: Theme.keys("Space")
                onToggled: root.controller.toggle()
            },
            Button {
                objectName: "scopeSingleButton"
                text: qsTr("Single")
                icon.source: Theme.icon("step")
                Accessible.name: qsTr("Single")
                enabled: root.controller.canRun
                         || (root.controller.state === InstrumentController.Running
                             && root.controller.runMode === InstrumentController.Continuous)
                focusPolicy: Qt.TabFocus
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Single") + "   " + Theme.keys("Shift+Space")
                onClicked: root.controller.runOnce()
            }
        ]
        headerSettings: [
            HeaderField {
                objectName: "timeDiv"
                toolTip: qsTr("Timebase")
                values: root.controller.timeDivValues
                formatter: v => Units.format(v, "s", 3) + "/div"
                currentIndex: root.controller.timeDivIndex
                onIndexActivated: index => root.controller.timeDivIndex = index
            },
            // The trigger's place on the screen (pre-trigger): Edge only, not while rolling.
            HeaderField {
                objectName: "horizontalPosition"
                visible: root.edge && !root.controller.rolling
                toolTip: qsTr("Trigger position (0 to 100 %)")
                from: 0
                to: 100
                stepSize: 1
                defaultValue: 50
                formatter: v => Math.round(v) + " %"
                value: root.controller.horizontalPosition
                onValueModified: v => root.controller.horizontalPosition = Math.round(v)
            },
            Button {
                objectName: "autoscaleButton"
                text: qsTr("Autoscale")
                icon.source: Theme.icon("autoscale")
                enabled: !root.controller.autoscaling && !root.controller.busy
                         && (root.controller.running || root.controller.canRun)
                focusPolicy: Qt.TabFocus
                Accessible.name: qsTr("Autoscale")
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Autoscale")
                onClicked: root.controller.autoscale()
            }
        ]
        displayTools: [
            // YT, XY (CH1 over CH0) and FFT (YT with the spectrum of a channel under it).
            SegmentedControl {
                objectName: "displayMode"
                readonly property bool fftOn: root.controller.fftSource !== ScopeController.FftOff
                model: [{ text: "YT", toolTip: qsTr("YT") },
                        { text: "XY", toolTip: qsTr("XY") },
                        { text: "FFT", toolTip: qsTr("FFT") }]
                currentIndex: fftOn ? 2 : root.controller.displayMode
                onActivated: index => {
                    if (index === 2) {
                        root.controller.displayMode = ScopeController.YT
                        if (!fftOn)
                            root.controller.fftSource = root.ch0.enabled ? ScopeController.FftChannel0 : ScopeController.FftChannel1
                    } else {
                        root.controller.fftSource = ScopeController.FftOff
                        root.controller.displayMode = index
                    }
                }
            }
        ]
        menuItems: [
            MenuItem {
                text: qsTr("Center Cursors")
                enabled: root.controller.cursorsOn
                onTriggered: root.controller.resetCursors()
            }
        ]
        traceStyles: [
            { name: "CH0", style: root.ch0.style, color: Theme.signalCh0 },
            { name: "CH1", style: root.ch1.style, color: Theme.signalCh1 },
            { name: qsTr("Math"), style: root.math.style, color: Theme.signalMath },
            { name: "REF A", style: root.controller.refAStyle, color: Theme.signalRef },
            { name: "REF B", style: root.controller.refBStyle, color: Theme.signalRef },
            { name: qsTr("Cursor C1"), style: root.controller.cursor1.style, color: Theme.cursor1 },
            { name: qsTr("Cursor C2"), style: root.controller.cursor2.style, color: Theme.cursor2 }
        ]

        // The display; the panel places it, the controls and the tool panels around it.
        ScopeDisplay {
            id: display
            anchors.fill: parent
            controller: root.controller
        }

        // CH 0, CH 1, Trigger and Math cards: the column at the right, or the dock under the display.
        controls: [
            ScopeChannelCard {
                Layout.fillWidth: true
                controller: root.controller
                channel: root.ch0
                channelColor: display.traceColor(0)
            },
            ScopeChannelCard {
                Layout.fillWidth: true
                controller: root.controller
                channel: root.ch1
                channelColor: display.traceColor(1)
            },
            ScopeTriggerCard {
                Layout.fillWidth: true
                controller: root.controller
                ch0Color: display.traceColor(0)
                ch1Color: display.traceColor(1)
            },
            ScopeMathCard {
                Layout.fillWidth: true
                controller: root.controller
                channelColor: display.traceColor(2)
            }
        ]

        tools: ToolPalette {
            objectName: "toolPalette"
            currentId: root.tool
            model: [{ id: "measure", text: qsTr("Measure"), icon: "ruler", toolTip: qsTr("Measurements") },
                    { id: "cursors", text: qsTr("Cursors"), icon: "crosshair", toolTip: qsTr("Cursors") },
                    { id: "references", text: qsTr("Refs"), icon: "layers", toolTip: qsTr("Reference traces") },
                    { id: "display", text: qsTr("Display"), icon: "grid", toolTip: qsTr("Display") }]
            onActivated: id => root.toggleTool(id)
        }

        toolPanels: [
            // Measure: which cards, the measurement types (picture buttons), statistics.
            ToolPanel {
                objectName: "measurePanel"
                visible: root.tool === "measure"
                title: qsTr("Measurements")
                onCloseRequested: root.tool = ""
                ScopeToolSection {
                    title: qsTr("Cards")
                    FormRow {
                        label: qsTr("Trace")
                        SegmentedControl {
                            objectName: "measureSource"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: [{ text: qsTr("All") }, { text: "CH0", color: display.traceColor(0) }, { text: "CH1", color: display.traceColor(1) },
                                    { text: qsTr("Math"), color: display.traceColor(2) }]
                            currentIndex: root.cardSource + 1
                            onActivated: index => root.cardSource = index - 1
                        }
                    }
                    FormRow {
                        label: qsTr("Statistics")
                        SegmentedControl {
                            objectName: "measureStatistics"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: [{ text: qsTr("Off") }, { text: qsTr("Last 100") }, { text: qsTr("All") }]
                            currentIndex: root.statistics
                            onActivated: index => root.statistics = index
                        }
                    }
                    FormRow {
                        label: qsTr("Frequency")
                        SegmentedControl {
                            objectName: "frequencyMethod"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: [{ text: qsTr("Tone"), toolTip: qsTr("Tone") },
                                    { text: qsTr("Edges"), toolTip: qsTr("Edge count") }]
                            currentIndex: root.controller.frequencyMethod
                            onActivated: index => root.controller.frequencyMethod = index
                        }
                    }
                }
                ScopeToolSection {
                    title: qsTr("Measurements")
                    separatorSide: "none"
                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(3, Math.min(6, Math.floor(width / 70)))
                        rowSpacing: Theme.spacingXs
                        columnSpacing: Theme.spacingXs
                        Repeater {
                            model: root.controller.measurementCatalog
                            delegate: PictureButton {
                                id: typeButton
                                required property var modelData
                                readonly property bool shown: (measurementModel.shownMask & modelData.flag) !== 0
                                objectName: "measureType" + modelData.flag
                                Layout.fillWidth: true
                                Layout.preferredWidth: 1
                                checked: shown
                                text: root.measurementShortLabels[modelData.flag] ?? modelData.label
                                glyph: root.measurementGlyphs[modelData.flag] ?? ""
                                focusPolicy: Qt.TabFocus
                                ToolTip.visible: hovered
                                ToolTip.text: modelData.name
                                onClicked: {
                                    if (shown)
                                        measurementModel.remove("m" + modelData.flag)
                                    else
                                        measurementModel.add("m" + modelData.flag)
                                }
                            }
                        }
                    }
                }
            },

            ToolPanel {
                objectName: "cursorsPanel"
                visible: root.tool === "cursors"
                title: qsTr("Cursors")
                onCloseRequested: root.tool = ""
                ScopeToolSection {
                    objectName: "cursorsCard"
                    title: qsTr("Time Cursors")
                    checkable: true
                    checked: root.controller.cursorsOn
                    onToggled: on => root.controller.cursorsOn = on
                    FormRow {
                        label: "C1"
                        hint: qsTr("Trace of C1")
                        SegmentedControl {
                            objectName: "cursor1Trace"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: root.traceChoices
                            currentIndex: root.controller.cursor1.channel
                            onActivated: index => root.controller.cursor1.channel = index
                        }
                    }
                    FormRow {
                        label: "C2"
                        hint: qsTr("Trace of C2")
                        SegmentedControl {
                            objectName: "cursor2Trace"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: root.traceChoices
                            currentIndex: root.controller.cursor2.channel
                            onActivated: index => root.controller.cursor2.channel = index
                        }
                    }
                    FormRow {
                        label: qsTr("Style")
                        ComboBox {
                            objectName: "cursorStyle"
                            Layout.fillWidth: true
                            Layout.preferredHeight: Theme.controlHeight
                            // ScopeCursor.CursorStyle order; one style for both cursors.
                            model: [qsTr("Line"), qsTr("Full crosshair"), qsTr("Small crosshair"), qsTr("Hidden")]
                            currentIndex: root.controller.cursor1.cursorStyle
                            onActivated: index => {
                                root.controller.cursor1.cursorStyle = index
                                root.controller.cursor2.cursorStyle = index
                            }
                        }
                    }
                }
                ScopeToolSection {
                    objectName: "levelCursorsCard"
                    title: qsTr("Level Cursors")
                    separatorSide: "none"
                    checkable: true
                    checked: root.controller.levelCursorsOn
                    onToggled: on => root.controller.levelCursorsOn = on
                    FormRow {
                        label: qsTr("Trace")
                        hint: qsTr("Trace of H1, H2")
                        SegmentedControl {
                            objectName: "levelCursorTrace"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: root.traceChoices
                            currentIndex: root.controller.levelCursorChannel
                            onActivated: index => root.controller.levelCursorChannel = index
                        }
                    }
                }
            },

            ToolPanel {
                objectName: "referencesPanel"
                visible: root.tool === "references"
                title: qsTr("References")
                onCloseRequested: root.tool = ""
                Repeater {
                    model: 2
                    delegate: ScopeToolSection {
                        id: refRow
                        required property int index
                        readonly property bool available: index === 0 ? root.controller.refAAvailable : root.controller.refBAvailable
                        readonly property bool shown: index === 0 ? root.controller.refAVisible : root.controller.refBVisible
                        readonly property string name: index === 0 ? "REF A" : "REF B"
                        title: name
                        subtitle: available ? (index === 0 ? root.controller.refALabel : root.controller.refBLabel) : qsTr("Empty")
                        color: Theme.signalRef
                        separatorSide: index === 1 ? "none" : "bottom"
                        collapseWhenOff: false
                        headerExtras: [
                            IconButton {
                                iconName: refRow.shown ? "eye" : "eye-off"
                                size: Theme.controlHeightS
                                enabled: refRow.available
                                toolTip: refRow.shown ? qsTr("Hide") : qsTr("Show")
                                onClicked: {
                                    if (refRow.index === 0)
                                        root.controller.refAVisible = !refRow.shown
                                    else
                                        root.controller.refBVisible = !refRow.shown
                                }
                            },
                            IconButton {
                                iconName: "folder-open"
                                size: Theme.controlHeightS
                                toolTip: qsTr("Import…")
                                onClicked: refDialog.openFor(refRow.index, false)
                            },
                            IconButton {
                                iconName: "export"
                                size: Theme.controlHeightS
                                enabled: refRow.available
                                toolTip: qsTr("Export…")
                                onClicked: refDialog.openFor(refRow.index, true)
                            },
                            IconButton {
                                iconName: "trash"
                                size: Theme.controlHeightS
                                enabled: refRow.available
                                toolTip: qsTr("Clear")
                                onClicked: root.controller.clearReference(refRow.index)
                            }
                        ]
                        FormRow {
                            label: qsTr("Keep")
                            hint: qsTr("Keep as %1").arg(refRow.name)
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Theme.spacingXs
                                Repeater {
                                    model: [{ text: "CH0", src: 0, on: root.ch0.enabled }, { text: "CH1", src: 1, on: root.ch1.enabled },
                                            { text: qsTr("Math"), src: 2, on: root.math.enabled }]
                                    delegate: Button {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        text: modelData.text
                                        enabled: root.controller.hasRecord && modelData.on
                                        ToolTip.visible: hovered
                                        ToolTip.delay: Theme.toolTipDelay
                                        ToolTip.text: qsTr("Keep %1 as %2").arg(modelData.text).arg(refRow.name)
                                        onClicked: root.controller.saveReference(refRow.index, modelData.src)
                                    }
                                }
                            }
                        }
                    }
                }
            },

            ToolPanel {
                objectName: "displayPanel"
                visible: root.tool === "display"
                title: qsTr("Display")
                onCloseRequested: root.tool = ""
                ScopeToolSection {
                    title: qsTr("Acquisition")
                    FormRow {
                        label: qsTr("Persistence")
                        StepSelector {
                            objectName: "persistence"
                            readonly property var values: [0, 100, 250, 500, 1000, 2000, 5000]
                            Layout.fillWidth: true
                            label: qsTr("Persistence")
                            model: values.map(v => ({ value: v, text: v === 0 ? qsTr("Off") : Units.format(v / 1000, "s", 3) }))
                            currentIndex: Math.max(0, values.indexOf(root.controller.persistence))
                            onActivated: index => root.controller.persistence = values[index]
                        }
                    }
                    FormRow {
                        label: qsTr("Averaging")
                        StepSelector {
                            objectName: "averaging"
                            readonly property var values: [1, 2, 4, 8, 16, 32, 64]
                            Layout.fillWidth: true
                            label: qsTr("Averaging")
                            model: values.map(v => ({ value: v, text: v === 1 ? qsTr("Off") : qsTr("%1 records").arg(v) }))
                            currentIndex: Math.max(0, values.indexOf(root.controller.averaging))
                            onActivated: index => root.controller.averaging = values[index]
                        }
                    }
                    FormRow {
                        label: qsTr("Record")
                        SegmentedControl {
                            objectName: "recordLength"
                            Layout.fillWidth: true
                            stretch: true
                            compact: true
                            model: [{ text: qsTr("Normal"), toolTip: qsTr("2 501 samples") },
                                    { text: qsTr("Long"), toolTip: qsTr("100 000 samples") }]
                            currentIndex: root.controller.samplingMode
                            onActivated: index => root.controller.samplingMode = index
                        }
                    }
                    FormRow {
                        visible: root.controller.rollAvailable
                        label: qsTr("Roll")
                        hint: qsTr("From 50 ms/div")
                        ToggleSwitch {
                            objectName: "rollMode"
                            checked: root.controller.rollMode
                            Accessible.name: qsTr("Roll")
                            onToggled: root.controller.rollMode = checked
                        }
                    }
                    FormRow {
                        label: qsTr("Auto level")
                        hint: qsTr("Level follows Autoscale")
                        ToggleSwitch {
                            objectName: "autoscaleSetsLevel"
                            checked: root.controller.autoscaleSetsLevel
                            Accessible.name: qsTr("Auto level")
                            onToggled: root.controller.autoscaleSetsLevel = checked
                        }
                    }
                }
                ScopeToolSection {
                    title: qsTr("Traces")
                    separatorSide: "none"
                    Button {
                        objectName: "traceStylesButton"
                        Layout.fillWidth: true
                        text: qsTr("Trace Styles…")
                        onClicked: panel.openTraceStyleDialog()
                    }
                }
            }
        ]

        measurements: [
            ScopeMeasurementCards {
                objectName: "measurementCards"
                controller: root.controller
                columns: measurementModel.columns
                traces: measurementModel.traces
                rows: measurementModel.rows
                available: measurementModel.available
                summaryText: measurementModel.summaryText
                catalog: root.controller.measurementCatalog
                statistics: root.statistics
                sourceFilter: root.cardSource
                onAddRequested: id => measurementModel.add(id)
                onRemoveRequested: id => measurementModel.remove(id)
                onOpenMeasurePanel: root.tool = "measure"
            }
        ]
    }

    // --scope-view=xy|fft|cursors|measures opens that display mode, or switches the cursors on, at start (screenshots).
    Component.onCompleted: {
        const view = AppInfo.value("scope-view")
        if (view === "xy") {
            controller.setChannelEnabled(1, true)
            controller.displayMode = ScopeController.XY
        } else if (view === "fft") {
            controller.fftSource = ScopeController.FftChannel0
        } else if (view === "measures") {   // both channels: six cards (RMS, Frequency, Peak-to-peak)
            controller.setChannelEnabled(1, true)
        } else if (view === "cursors") {
            controller.cursorsOn = true
            controller.levelCursorsOn = true
        }
    }

    FileDialog {
        id: refDialog
        property int slot: 0
        property bool saving: true
        function openFor(index: int, save: bool) {
            slot = index
            saving = save
            if (save)
                selectedFile = DataExport.suggestedFileUrl("scope-ref", "csv")
            open()
        }
        title: saving ? qsTr("Export Reference") : qsTr("Import Reference")
        fileMode: saving ? FileDialog.SaveFile : FileDialog.OpenFile
        nameFilters: [qsTr("Data (*.csv *.tsv *.txt)"), qsTr("All files (*)")]
        defaultSuffix: "csv"
        currentFolder: DataExport.lastFolder
        onAccepted: {
            if (saving)
                root.controller.exportReference(slot, selectedFile)
            else
                root.controller.importReference(slot, selectedFile)
        }
    }
}
