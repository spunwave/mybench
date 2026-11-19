pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// The waveform generator pane: instrument bar in the pane header (Run, Single, output connector),
// one display with both outputs (GenDisplay), and on the right a card per channel and the tool
// palette (Sweep, Presets) whose tools open a floating panel. The editor view (EditorView) follows
// the same pattern.
Item {
    id: root

    required property GenController controller
    readonly property bool editorTab: controller.activeTab === 1
    readonly property WaveformEditor editor: controller.editor
    // Open tool panel ("" = none).
    property string tool: ""
    readonly property var channels: [controller.channel0, controller.channel1]

    function exportChannel(index: int) {
        exportDialog.channelIndex = index
        exportDialog.open()
    }

    InstrumentPanel {
        id: panel
        objectName: "genPane"
        anchors.fill: parent
        controller: root.controller
        // The editor's segment list scrolls in its card: its dock keeps the pane-proportional height.
        dockFitsCards: !root.editorTab
        showRunControls: false
        // A short state word (the framework's own text while paused, in error or without a device).
        stateText: root.controller.hasError || root.controller.paused || (!root.controller.running && !root.controller.canRun)
                   ? "" : root.controller.running ? qsTr("Running") : qsTr("Stopped")
        // Both views keep every control beside their display: no inspector. The editor tab swaps the
        // generator's cards, palette and tool panel for its own (same slots).
        hasInspector: false
        // The editor's trace in the panel menu and the plots' "Trace style…" (editor tab).
        traceStyles: root.editorTab ? [{ name: root.editor.documentName, style: root.editor.traceStyle,
                                         color: root.editor.plotColor.a > 0 ? root.editor.plotColor : Theme.accent }] : []

        displayInfo: root.controller.running && root.controller.taskRate > 0
                     ? Units.format(root.controller.taskRate, "S/s", 3) : ""

        headerContent: [
            RunButton {
                objectName: "genRunButton"
                running: root.controller.running
                busy: root.controller.busy
                enabled: root.controller.running || root.controller.canRun
                onToggled: root.controller.toggle()
            },
            // Single applies only to Arbitrary channels with a waveform: hidden otherwise.
            Button {
                objectName: "genSingleButton"
                visible: !root.editorTab && root.controller.singleEnabled
                text: qsTr("Single")
                icon.source: Theme.icon("step")
                ToolTip.visible: hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: qsTr("Single")
                onClicked: root.controller.runOnce()
            }
        ]
        // Where the two channels come out: the AO screw terminals or the AUDIO OUT jack.
        headerSettings: [
            SegmentedControl {
                objectName: "outputPair"
                visible: !root.editorTab
                model: [ { text: qsTr("AO 0 / AO 1"),
                           toolTip: qsTr("AO 0 / AO 1 · ±10 V · DC") },
                         { text: qsTr("Audio out"),
                           toolTip: qsTr("Audio Out · ±2 V · AC") } ]
                currentIndex: root.controller.outputPair
                onActivated: index => root.controller.outputPair = index
            }
        ]

        // Time | Frequency, the display mode (the generator view only).
        displayTools: [
            SegmentedControl {
                objectName: "previewMode"
                visible: !root.editorTab
                model: [ { text: qsTr("Time"), toolTip: qsTr("Time") },
                         { text: qsTr("Frequency"), toolTip: qsTr("Spectrum (dBV)") } ]
                currentIndex: root.controller.displayMode
                onActivated: index => root.controller.displayMode = index
            }
        ]

        // Options-menu entries (native menus ignore `visible`: fixed entries, enabled when they apply). The
        // controller's commands (Sweep the Function channels) are added by the header.
        menuItems: [
            MenuItem {
                text: qsTr("Export %1 Waveform…").arg(root.controller.channel0.name)
                enabled: root.controller.channel0.mode !== GenChannel.Off
                onTriggered: root.exportChannel(0)
            },
            MenuItem {
                text: qsTr("Export %1 Waveform…").arg(root.controller.channel1.name)
                enabled: root.controller.channel1.mode !== GenChannel.Off
                onTriggered: root.exportChannel(1)
            },
            MenuItem {
                text: qsTr("Waveform Editor")
                enabled: !root.editorTab
                onTriggered: root.controller.activeTab = 1
            },
            MenuItem {
                text: qsTr("Align Phases")
                enabled: root.controller.strategy === GenController.Streaming
                onTriggered: root.controller.alignPhases()
            }
        ]

        StackLayout {
            anchors.fill: parent
            currentIndex: root.controller.activeTab

            // --- Generator view ---------------------------------------------------------------
            // The display: one plot with both outputs; values live in the channel cards.
            Item {
                id: generatorView

                GenDisplay {
                    id: display
                    objectName: "genDisplay"
                    anchors.fill: parent
                    controller: root.controller
                }
            }

            // --- Waveform Editor view ------------------------------------------------------------
            EditorView {
                id: editorView
                objectName: "editorView"
                controller: root.controller
                editor: root.editor
                docked: panel.docked
                dockTable: dockTable
            }
        }

        // One card per output (generator view) or the Document, Segments and Segment cards (editor
        // view); the panel puts them in the column or the dock.
        controls: [
            Repeater {
                model: root.channels
                delegate: GenChannelCard {
                    required property GenChannel modelData
                    visible: !root.editorTab
                    Layout.fillWidth: true
                    controller: root.controller
                    channel: modelData
                }
            },
            EditorDocumentCard {
                visible: root.editorTab
                Layout.fillWidth: true
                controller: root.controller
                editor: root.editor
            },
            // The segment table moves into the dock when the controls are docked (else it is under the plot).
            ChannelCard {
                objectName: "editorSegmentsCard"
                visible: root.editorTab && editorView.tableInCard
                Layout.fillWidth: true
                title: qsTr("Segments")
                checkable: false
                EditorSegmentTable {
                    id: dockTable
                    Layout.fillWidth: true
                    Layout.preferredHeight: 176
                    showTitle: false
                    editor: root.editor
                    onClearRequested: editorView.clearSelection()
                    onSaveAsRequested: editorView.saveDialog.open()
                    onCloseDocumentRequested: editorView.closeDocument()
                }
            },
            EditorSegmentCard {
                visible: root.editorTab
                Layout.fillWidth: true
                editor: root.editor
            }
        ]
        tools: ToolPalette {
            objectName: "genTools"
            currentId: root.editorTab ? (root.editor.drawMode ? "draw" : editorView.tool) : root.tool
            model: root.editorTab ? [
                { id: "draw", text: qsTr("Draw"), icon: "edit", toolTip: qsTr("Draw") },
                { id: "functions", text: qsTr("Functions"), icon: "wave-sine", toolTip: qsTr("Functions") },
                { id: "scale", text: qsTr("Scale"), icon: "ruler", toolTip: qsTr("Scale Selection") },
                { id: "display", text: qsTr("Display"), icon: "eye", toolTip: qsTr("Display") },
                { id: "export", text: qsTr("Export"), icon: "external", toolTip: qsTr("Export") },
                { id: "info", text: qsTr("Info"), icon: "info", toolTip: qsTr("Information") + "  " + KeyText.of("Ctrl+I") }
            ] : [
                { id: "sweep", text: qsTr("Sweep"), icon: "sweep", toolTip: qsTr("Sweep") },
                { id: "presets", text: qsTr("Presets"), icon: "layers", toolTip: qsTr("Presets") }
            ]
            onActivated: id => {
                if (root.editorTab)
                    editorView.activateTool(id)
                else
                    root.tool = root.tool === id ? "" : id
            }
        }
        toolPanels: [
            EditorToolPanel {
                visible: root.editorTab && editorView.tool.length > 0
                view: editorView
            },
            ToolPanel {
                id: toolPanel
                objectName: "genToolPanel"
                visible: !root.editorTab && root.tool.length > 0
                title: root.tool === "sweep" ? qsTr("Frequency Sweep")
                       : root.tool === "presets" ? qsTr("Presets") : ""
                onCloseRequested: root.tool = ""

                GenSweepTool {
                    visible: root.tool === "sweep"
                    Layout.fillWidth: true
                    controller: root.controller
                }
                ColumnLayout {
                    visible: root.tool === "presets"
                    Layout.fillWidth: true
                    spacing: Theme.spacingM
                    GenToolSection {
                        title: qsTr("Built-in")
                        separatorSide: root.controller.presetNames.length > 0 ? "bottom" : "none"
                        Repeater {
                            model: root.controller.builtInPresets
                            delegate: Button {
                                required property string modelData
                                required property int index
                                Layout.fillWidth: true
                                text: modelData
                                onClicked: root.controller.loadBuiltInPreset(index)
                            }
                        }
                    }
                    GenToolSection {
                        title: qsTr("Saved")
                        separatorSide: "none"
                        headerExtras: [
                            IconButton {
                                iconName: "save"
                                size: Theme.controlHeightS
                                toolTip: qsTr("Save Current Settings…")
                                onClicked: presetDialog.open()
                            }
                        ]
                        Repeater {
                            model: root.controller.presetNames
                            delegate: RowLayout {
                                id: presetRow
                                required property string modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingXs
                                Button {
                                    Layout.fillWidth: true
                                    text: presetRow.modelData
                                    icon.source: Theme.icon("file")
                                    onClicked: root.controller.loadPreset(presetRow.modelData)
                                }
                                IconButton {
                                    iconName: "trash"
                                    toolTip: qsTr("Delete")
                                    Accessible.name: qsTr("Delete %1").arg(presetRow.modelData)
                                    onClicked: root.controller.deletePreset(presetRow.modelData)
                                }
                            }
                        }
                    }
                }
            }
        ]
    }

    // Screenshot scenes (dev executable, MYBENCH_GEN_SCENE): open a dialog, tool or state once loaded.
    Timer {
        interval: 300
        running: root.controller.devScene().length > 0
        onTriggered: {
            const scene = root.controller.devScene()
            if (scene.startsWith("tool-")) {
                root.tool = scene.substring(5)
            } else if (scene.startsWith("preset-")) {
                root.controller.loadBuiltInPreset(Number(scene.substring(7)))
                if (!root.controller.running)
                    root.controller.run()
            } else if (scene === "arb") {
                // AO 1 plays a library waveform beside AO 0's sine (Arbitrary card, combined plot).
                root.controller.channel1.mode = GenChannel.Arbitrary
                root.controller.loadLibraryWaveform(1, 17)   // Stairstep
            } else if (scene === "editor") {
                root.controller.activeTab = 1
            } else {
                // Editor scenes (draw, component, info, menu, settings, editor-tool-…).
                root.controller.activeTab = 1
                editorView.showScene(scene)
            }
        }
    }

    FileDialog {
        id: exportDialog
        property int channelIndex: 0
        title: qsTr("Export Waveform")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("CSV (*.csv)"), qsTr("WAV audio (*.wav)")]
        onAccepted: root.controller.exportChannel(channelIndex, selectedFile)
    }

    Dialog {
        id: presetDialog
        title: qsTr("Save Preset")
        anchors.centerIn: parent
        modal: true
        standardButtons: Dialog.Save | Dialog.Cancel
        onOpened: presetName.text = ""
        onAccepted: root.controller.savePreset(presetName.text)
        ColumnLayout {
            spacing: Theme.spacingS
            Text {
                text: qsTr("Preset name")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeM
            }
            TextField {
                id: presetName
                Layout.preferredWidth: 280
                placeholderText: qsTr("My setup")
                onAccepted: presetDialog.accept()
            }
        }
    }
}
