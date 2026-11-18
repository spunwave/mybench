pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// The waveform editor view of the generator pane: one toolbar (Back, document, Undo / Redo, Zoom to
// Fit, Send to Generator), the waveform plot (selected segment, cursors, sketch drawing) with the
// segment table under it, and a status line. The cards, tool palette and floating tool panel are the
// pane's shared layout slots, declared in GenPanel.
Item {
    id: root

    required property GenController controller
    required property WaveformEditor editor
    readonly property bool frequencyView: editor.xAxis === 1
    // The pane's controls are docked under the display: the segment table is then a card of the dock.
    property bool docked: false
    // The table is in a card of the controls (docked, or a view too short to share its height with it).
    readonly property bool tableInCard: docked || height < 440
    property var dockTable: null
    readonly property alias saveDialog: saveDialog
    readonly property alias exportDialog: exportDialog
    readonly property alias settingsDialog: settingsDialog
    readonly property alias sketchImport: sketchImport
    readonly property bool tableFocused: table.list.activeFocus || (dockTable !== null && dockTable.list.activeFocus)
    property var pendingAction: null
    // Open tool panel ("" = none): functions, scale, display, export, info.
    property string tool: ""

    function guarded(action) {
        if (editor.modified) {
            pendingAction = action
            unsavedDialog.open()
        } else {
            action()
        }
    }
    function saveThen(action) {
        if (editor.save())
            action()
        else {
            pendingAction = action
            saveDialog.open()
        }
    }
    function save() {
        if (!editor.save())
            saveDialog.open()
    }
    function clearSelection() {
        if (editor.selectionKind === 3)
            clearAllDialog.open()
        else
            editor.deleteSelection()
    }
    // Close: back to an empty document and the Generator view (asks to save first).
    function closeDocument() {
        guarded(() => {
            editor.newDocument()
            controller.activeTab = 0
        })
    }
    function openImport() {
        importDialog.mode = 0
        importFileDialog.open()
    }
    // Zoom to fit: both axes follow the rendered waveform again.
    function zoomToFit() {
        plot.xAutoscaleLock = true
        plot.yAutoscaleLock = true
        plot.autoscale()
    }
    // Makes sure a component is selected (a new one after the selection when a segment or the
    // whole waveform is selected).
    function ensureComponent() {
        if (editor.selectionKind === 2)
            return
        if (editor.selectionKind !== 1)
            editor.selectSegment(Math.max(0, editor.segmentIndex))
        editor.newComponent()
    }
    // Draw tool: draws one cycle of a sketch component (the selected one, or a new one).
    function toggleDraw() {
        if (editor.drawMode) {
            editor.drawMode = false
            return
        }
        if (!(editor.selectionKind === 2 && editor.componentType === 2)) {
            ensureComponent()
            editor.componentType = 2
        }
        editor.drawMode = true
    }
    // Functions tool: the selected component becomes this library function (type 0), a formula
    // (type 1) or a sketch (type 2).
    function applyFunction(type: int, index: int) {
        ensureComponent()
        if (type === 0)
            editor.libraryFunction = index
        editor.componentType = type
    }
    function focusTable() {
        (tableInCard && dockTable ? dockTable : table).list.forceActiveFocus()
    }
    function activateTool(id: string) {
        if (id === "draw") {
            tool = ""
            toggleDraw()
        } else {
            tool = tool === id ? "" : id
        }
    }

    // Keyboard shortcuts (File / Edit menus), active while the editor has the focus. The
    // ShortcutOverride is accepted so the shell's shortcuts (Ctrl+N/O/S/W/I) do not fire, and a text
    // field keeps its own editing keys (it accepts the override first).
    function shortcutAction(event: KeyEvent): var {
        if (!root.visible)
            return null
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0
        const alt = (event.modifiers & Qt.AltModifier) !== 0
        if (alt)
            return null
        if (!ctrl) {
            if ((event.key === Qt.Key_Delete || event.key === Qt.Key_Backspace) && root.tableFocused)
                return () => root.clearSelection()
            return null
        }
        switch (event.key) {
        case Qt.Key_N: return () => root.guarded(() => root.editor.newDocument())
        case Qt.Key_O: return () => root.guarded(() => openDialog.open())
        case Qt.Key_W: return () => root.closeDocument()
        case Qt.Key_S: return shift ? () => saveDialog.open() : () => root.save()
        case Qt.Key_I: return () => root.tool = "info"
        case Qt.Key_0: return () => root.zoomToFit()
        case Qt.Key_A: return () => root.editor.selectAll()
        case Qt.Key_H: return () => Help.show("gen")
        case Qt.Key_Z: return shift ? () => root.editor.redo() : () => root.editor.undo()
        case Qt.Key_Y: return () => root.editor.redo()
        case Qt.Key_X: return () => root.editor.cut()
        case Qt.Key_C: return () => root.editor.copy()
        case Qt.Key_V: return () => root.editor.paste()
        default: return null
        }
    }
    function showScene(scene: string) {
        if (scene === "settings") {
            settingsDialog.open()
        } else if (scene === "draw") {
            editor.newDocument()
            editor.segmentDuration = 1
            editor.newComponent()
            editor.componentType = 2
            editor.sketchSamples = 50
            editor.drawMode = true
            editor.drawTool = 1
            editor.addVertex(0.3, 0.8)
            editor.addVertex(0.7, -0.5)
        } else if (scene === "unsaved") {
            editor.newSegment()
            controller.channel1.mode = GenChannel.Arbitrary
            controller.loadLibraryWaveform(1, 2)
            controller.editChannel(1, false)
        } else if (scene === "tracestyle") {
            openTraceStyle()
        } else if (scene === "info") {
            tool = "info"
        } else if (scene === "component") {
            controller.activeTab = 1
            editor.newComponent()
            editor.libraryFunction = 1
            editor.componentType = 0
        } else if (scene.startsWith("editor-tool-")) {
            controller.activeTab = 1
            activateTool(scene.substring(12))
        } else if (scene.startsWith("import:")) {
            importDialog.mode = 0
            importDialog.openFor("file://" + scene.slice(7))
        }
    }
    function openTraceStyle() {
        plot.openTraceStyles()
    }
    function claimsShortcut(event: KeyEvent): bool {
        return shortcutAction(event) !== null
    }
    function handleShortcut(event: KeyEvent) {
        const action = shortcutAction(event)
        if (action) {
            action()
            event.accepted = true
        }
    }

    Keys.onShortcutOverride: event => event.accepted = root.claimsShortcut(event)
    Keys.onPressed: event => root.handleShortcut(event)
    // Showing the editor gives it the keyboard focus (its shortcuts work at once).
    onVisibleChanged: if (visible) root.focusTable()

    Connections {
        target: root.controller
        // Edit on a channel card while this editor holds another, modified document.
        function onEditChannelNeedsConfirmation(channel: int) {
            root.guarded(() => root.controller.editChannel(channel, true))
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // --- Toolbar: icon buttons (22 px icons), wrapping to a second row in a narrow pane ---------------------
        Rectangle {
            id: topBar
            objectName: "editorTopBar"
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(barFlow.implicitHeight, sendBlock.height) + 5
            color: Theme.window

            // The one labelled, filled button of the toolbar, at its right end, set off by a hairline.
            Row {
                id: sendBlock
                objectName: "editorSendBlock"
                anchors { right: parent.right; rightMargin: Theme.spacingS; top: parent.top; topMargin: 2 }
                spacing: Theme.spacingS
                Rectangle { y: (sendButton.height - height) / 2; width: 1; height: 18; color: Theme.separator }
                ActionButton {
                    id: sendButton
                    objectName: "editorSend"
                    tone: "accent"
                    iconName: "export"
                    // The long label when the toolbar has room for it.
                    text: topBar.width >= 560 ? qsTr("Send to Generator") : qsTr("Send")
                    height: 32
                    toolTip: qsTr("Send to Generator")
                    onClicked: sendMenu.popup(sendButton, 0, sendButton.height)
                    Menu {
                        id: sendMenu
                        MenuItem { text: root.controller.channel0.name; onTriggered: root.editor.useInChannel(0) }
                        MenuItem { text: root.controller.channel1.name; onTriggered: root.editor.useInChannel(1) }
                    }
                }
            }

            Flow {
                id: barFlow
                x: Theme.spacingS
                y: 2
                width: parent.width - 3 * Theme.spacingS - sendBlock.width
                spacing: 2

                component Bar: IconButton {
                    size: 32
                    iconSize: Theme.iconSizeL
                }
                component Divider: Item {
                    width: 9
                    height: 32
                    Rectangle { anchors.centerIn: parent; width: 1; height: 18; color: Theme.separator }
                }

                Bar { objectName: "backToGenerator"; iconName: "chevron-left"; toolTip: qsTr("Back to the Generator")
                      onClicked: root.controller.activeTab = 0 }
                Divider {}
                Bar { objectName: "editorNew"; iconName: "file-plus"; toolTip: qsTr("New"); shortcutText: KeyText.of("Ctrl+N"); onClicked: root.guarded(() => root.editor.newDocument()) }
                Bar { objectName: "editorOpen"; iconName: "folder-open"; toolTip: qsTr("Open…"); shortcutText: KeyText.of("Ctrl+O"); onClicked: root.guarded(() => openDialog.open()) }
                Bar { objectName: "editorImport"; iconName: "download"; toolTip: qsTr("Import from File…"); onClicked: root.openImport() }
                Bar { objectName: "editorSave"; iconName: "save"; toolTip: qsTr("Save"); shortcutText: KeyText.of("Ctrl+S"); onClicked: root.save() }
                Divider {}
                Bar {
                    objectName: "editorUndo"
                    iconName: "undo"
                    enabled: root.editor.canUndo
                    toolTip: root.editor.undoText.length > 0 ? qsTr("Undo %1").arg(root.editor.undoText) : qsTr("Undo")
                    shortcutText: KeyText.of("Ctrl+Z")
                    onClicked: root.editor.undo()
                }
                Bar {
                    id: redoButton
                    objectName: "editorRedo"
                    iconName: "undo"
                    // The undo arrow, mirrored.
                    transform: Scale { origin.x: redoButton.width / 2; xScale: -1 }
                    enabled: root.editor.canRedo
                    toolTip: root.editor.redoText.length > 0 ? qsTr("Redo %1").arg(root.editor.redoText) : qsTr("Redo")
                    shortcutText: KeyText.of("Ctrl+Shift+Z")
                    onClicked: root.editor.redo()
                }
                Divider {}
                Bar { objectName: "editorZoomFit"; iconName: "zoom-fit"; toolTip: qsTr("Zoom to Fit"); shortcutText: KeyText.of("Ctrl+0"); onClicked: root.zoomToFit() }
                BusyIndicator {
                    width: 32
                    height: 32
                    padding: 6
                    running: root.editor.rendering
                    visible: busyDelay.show
                    Timer {
                        id: busyDelay
                        property bool show: false
                        interval: 200
                        running: root.editor.rendering
                        onTriggered: show = true
                        onRunningChanged: if (!running) show = false
                    }
                }
            }
            Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Theme.separator }
        }

        // --- Plot -------------------------------------------------------------------------------------------
        Item {
            id: plotBox
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 120

            // Animate Graphs (Settings): the selection highlight glides to the new segment.
            property real highlightStart: root.editor.highlightStart
            property real highlightEnd: root.editor.highlightEnd
            Behavior on highlightStart { enabled: root.editor.animateGraphs; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            Behavior on highlightEnd { enabled: root.editor.animateGraphs; NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }

            // Axes: the plot's autoscale locks (on by default, as ELVISmx) fit the view to the
            // rendered data after every edit; a user zoom or pan turns the lock off and is then kept
            // across edits, until Autoscale or the lock (plot toolbar / right-click menu) is used
            // again. In Draw mode the Y range is frozen at its extent when Draw was pressed.
            property bool yLockBeforeDraw: true
            property bool drawing: false
            Connections {
                target: root.editor
                function onDrawChanged() {
                    if (root.editor.drawMode === plotBox.drawing)
                        return
                    plotBox.drawing = root.editor.drawMode
                    if (root.editor.drawMode) {
                        plotBox.yLockBeforeDraw = plot.yAutoscaleLock
                        plot.yAutoscaleLock = false
                        plot.yAxis.min = root.editor.viewMin
                        plot.yAxis.max = root.editor.viewMax
                    } else {
                        plot.yAutoscaleLock = plotBox.yLockBeforeDraw
                    }
                }
            }

            BenchPlot {
                id: plot
                objectName: "editorPlot"
                anchors.fill: parent
                hoverReadout: !root.editor.drawMode
                dragMode: root.editor.drawMode ? Plot.NoDrag : Plot.Pan
                cursorsAvailable: !root.editor.drawMode
                copyDataAvailable: true
                onCopyDataRequested: root.editor.copyData()
                cursorsEnabled: root.editor.showCursors
                onCursorsToggled: on => root.editor.showCursors = on
                // Trace style: the panel's list (GenPanel). Export data from the plot: the rendered
                // editor waveform (GenController::exportTable exports it while this tab is shown).
                xAutoscaleLock: true
                yAutoscaleLock: true
                xAxis {
                    unit: root.frequencyView ? root.editor.unitName : "s"
                    unitInLabels: true
                }
                yAxis {
                    unit: root.frequencyView ? "dBVrms" : "V"
                    // A flat waveform gets a ±1 V window around its value.
                    minimumSpan: root.editor.flat ? 2 : 0
                }
                onClicked: (x, y) => {
                    root.forceActiveFocus()
                    root.editor.selectAt(x)
                }

                PlotRegion {
                    visible: !root.frequencyView && root.editor.view === 0 && root.editor.segmentCount > 1
                             && root.editor.selectionKind !== 3
                    from: plotBox.highlightStart
                    to: plotBox.highlightEnd
                    color: Theme.alpha(root.editor.selectionColor.a > 0 ? root.editor.selectionColor : Theme.accent,
                                       root.editor.selectionColor.a > 0 ? 0.35 : Theme.dark ? 0.18 : 0.12)
                    edgesVisible: true
                }
                PlotTrace {
                    id: trace
                    visible: root.editor.plotVisible
                    buffer: root.editor.preview
                    name: root.editor.documentName
                    unit: root.frequencyView ? "dBV" : "V"
                    color: Theme.accent
                    userStyle: root.editor.traceStyle
                    pointsVisible: root.editor.drawMode || root.editor.plotStyle !== 0
                }
                PlotCursor {
                    id: cursor1
                    visible: root.editor.showCursors && !root.editor.drawMode
                    label: "C1"
                    color: root.editor.cursorColor.a > 0 ? root.editor.cursorColor : Theme.cursor1
                    trace: trace
                    snap: true
                    position: root.editor.viewStart + 0.25 * (root.editor.viewEnd - root.editor.viewStart)
                }
                PlotCursor {
                    id: cursor2
                    visible: root.editor.showCursors && !root.editor.drawMode
                    label: "C2"
                    color: root.editor.cursorColor.a > 0 ? root.editor.cursorColor : Theme.cursor2
                    trace: trace
                    snap: true
                    position: root.editor.viewStart + 0.75 * (root.editor.viewEnd - root.editor.viewStart)
                }
            }
            // Settings colors that replace the theme's (transparent = keep the theme's).
            Binding { target: plot; property: "gridColor"; value: root.editor.gridColor; when: root.editor.gridColor.a > 0 }
            Binding { target: plot; property: "plotAreaColor"; value: root.editor.backgroundColor; when: root.editor.backgroundColor.a > 0 }

            // Freehand drawing / adding line vertices.
            MouseArea {
                id: drawArea
                x: plot.plotArea.x
                y: plot.plotArea.y
                width: plot.plotArea.width
                height: plot.plotArea.height
                visible: root.editor.drawMode
                cursorShape: Qt.CrossCursor
                acceptedButtons: Qt.LeftButton
                hoverEnabled: true
                property point pointer: Qt.point(NaN, NaN)
                onWheel: wheel => wheel.accepted = false
                onExited: pointer = Qt.point(NaN, NaN)
                function valueAt(mx: real, my: real): point {
                    const p = mapToItem(plot, mx, my)
                    return Qt.point(plot.pixelToX(p.x), plot.pixelToY(p.y))
                }
                onPressed: mouse => {
                    const v = valueAt(mouse.x, mouse.y)
                    if (root.editor.drawTool === 0)
                        root.editor.drawBegin(v.x, v.y)
                }
                onPositionChanged: mouse => {
                    const v = valueAt(mouse.x, mouse.y)
                    pointer = v
                    if (pressed && root.editor.drawTool === 0)
                        root.editor.drawTo(v.x, v.y)
                }
                onReleased: root.editor.drawEnd()
                onClicked: mouse => {
                    if (root.editor.drawTool === 1) {
                        const v = valueAt(mouse.x, mouse.y)
                        root.editor.addVertex(v.x, v.y)
                    }
                }
            }

            // Line-mode vertices: drag to move, right-click to delete.
            Repeater {
                model: root.editor.drawMode && root.editor.drawTool === 1 ? root.editor.vertices : []
                delegate: Rectangle {
                    id: handle
                    required property var modelData
                    required property int index
                    readonly property real px: {
                        plot.xAxis.min; plot.xAxis.max; plot.width   // dependencies
                        return plot.xToPixel(modelData.x)
                    }
                    readonly property real py: {
                        plot.yAxis.min; plot.yAxis.max; plot.height
                        return plot.yToPixel(modelData.y)
                    }
                    x: px - width / 2
                    y: py - height / 2
                    width: 12
                    height: 12
                    radius: 6
                    color: handleArea.pressed ? Theme.accent : Theme.display
                    border.width: 2
                    border.color: Theme.accent
                    MouseArea {
                        id: handleArea
                        anchors.fill: parent
                        anchors.margins: -4
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.SizeAllCursor
                        onPressed: mouse => {
                            if (mouse.button === Qt.LeftButton)
                                root.editor.vertexDragBegin()
                        }
                        onPositionChanged: mouse => {
                            if (!pressed)
                                return
                            const p = mapToItem(plot, mouse.x, mouse.y)
                            root.editor.moveVertex(handle.index, plot.pixelToX(p.x), plot.pixelToY(p.y))
                        }
                        onReleased: mouse => {
                            if (mouse.button === Qt.LeftButton)
                                root.editor.vertexDragEnd()
                        }
                        onClicked: mouse => {
                            if (mouse.button === Qt.RightButton)
                                root.editor.removeVertex(handle.index)
                        }
                    }
                }
            }

            // Draw-mode palette.
            Rectangle {
                visible: root.editor.drawMode
                anchors.top: parent.top
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.topMargin: plot.plotArea.y + 6
                width: drawRow.implicitWidth + 12
                height: drawRow.implicitHeight + 8
                radius: Theme.radiusControl
                color: Theme.base
                border.width: 1
                border.color: Theme.separator
                RowLayout {
                    id: drawRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingS
                    Text {
                        // ELVISmx "Mouse Position" indicator.
                        Layout.preferredWidth: 190
                        text: isNaN(drawArea.pointer.x) ? qsTr("x: —   y: —")
                              : qsTr("x: %1   y: %2").arg(Units.format(drawArea.pointer.x, "s", 4)).arg(Units.format(drawArea.pointer.y, "V", 4))
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeS
                        font.features: Theme.tabularFigures
                        ToolTip.visible: positionHover.hovered
                        ToolTip.text: qsTr("Mouse position")
                        HoverHandler { id: positionHover }
                    }
                    SegmentedControl {
                        compact: true
                        model: [ { text: qsTr("Freehand"), icon: "edit", toolTip: qsTr("Freehand") },
                                 { text: qsTr("Line"), icon: "trend", toolTip: qsTr("Points · right-click deletes") } ]
                        currentIndex: root.editor.drawTool
                        onActivated: index => root.editor.drawTool = index
                    }
                    ActionButton {
                        text: qsTr("Done")
                        compact: true
                        tone: "accent"
                        onClicked: root.editor.drawMode = false
                    }
                }
            }

            Row {
                visible: root.editor.aliasWarning
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 16
                anchors.topMargin: plot.plotArea.y + 6
                spacing: 4
                Icon { name: "warning"; color: Theme.caution; size: Theme.iconSizeS }
                Text { text: qsTr("Aliasing"); color: Theme.caution; font.pixelSize: Theme.fontSizeS }
            }
        }

        // --- Segment table under the plot (a card of the dock when docked) ----------------------------------
        Rectangle { visible: table.visible; Layout.fillWidth: true; implicitHeight: 1; color: Theme.separator }
        EditorSegmentTable {
            id: table
            objectName: "editorSegments"
            visible: !root.tableInCard
            Layout.fillWidth: true
            // As tall as its rows (the actions row and up to five rows, then it scrolls); the plot takes the rest.
            Layout.fillHeight: false
            Layout.preferredHeight: table.fitHeight
            Layout.minimumHeight: table.fitHeight
            Layout.maximumHeight: table.fitHeight
            Layout.leftMargin: Theme.spacingS
            Layout.rightMargin: Theme.spacingS
            editor: root.editor
            onClearRequested: root.clearSelection()
            onSaveAsRequested: saveDialog.open()
            onCloseDocumentRequested: root.closeDocument()
        }

        // --- Status line ----------------------------------------------------------------------------------
        Rectangle { Layout.fillWidth: true; implicitHeight: 1; color: Theme.separator }
        RowLayout {
            objectName: "editorStatus"
            Layout.fillWidth: true
            Layout.preferredHeight: 24
            Layout.leftMargin: Theme.spacingS
            Layout.rightMargin: Theme.spacingS
            spacing: Theme.spacingM
            Text {
                text: qsTr("%1 samples · %2 · %3")
                          .arg(root.editor.totalSamples.toLocaleString(Qt.locale("en_US"), "f", 0))
                          .arg(Units.format(root.editor.totalDuration, "s", 4))
                          .arg(Units.format(root.editor.sampleRate, "S/s", 4))
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.features: Theme.tabularFigures
            }
            Text {
                // Two-cursor readout (Display tool > Cursors).
                visible: cursor1.visible
                readonly property real dx: cursor2.position - cursor1.position
                text: root.frequencyView
                      ? qsTr("ΔX %1 · ΔY %2").arg(Units.format(dx, root.editor.unitName, 4)).arg(Units.format(cursor2.value - cursor1.value, "dB", 4))
                      : qsTr("ΔX %1 · ΔY %2 · 1/ΔX %3").arg(Units.format(dx, "s", 4)).arg(Units.format(cursor2.value - cursor1.value, "V", 4))
                            .arg(Math.abs(dx) > 0 ? Units.format(1 / Math.abs(dx), "Hz", 4) : "—")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.features: Theme.tabularFigures
            }
            Item { Layout.fillWidth: true }
            Text {
                visible: root.editor.warnings.length > 0
                Layout.maximumWidth: parent.width * 0.5
                text: root.editor.warnings.join(" · ")
                color: Theme.caution
                font.pixelSize: Theme.fontSizeCaption
                elide: Text.ElideRight
            }
            Text {
                Layout.maximumWidth: parent.width * 0.4
                text: root.editor.statusText
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeCaption
                font.features: Theme.tabularFigures
                elide: Text.ElideLeft
            }
        }
    }

    SketchImport { id: sketchImport; editor: root.editor }

    // --- Dialogs (native file dialogs, confirmations, import options, settings) ---------------------------------------------------------------------------------------
    FileDialog {
        id: openDialog
        title: qsTr("Open Waveform")
        nameFilters: [qsTr("Waveforms (*.mbw *.wfm *.wav *.csv *.txt *.bin *.wdt)"), qsTr("mybench waveform (*.mbw)"),
                      qsTr("NI Waveform Editor document (*.wfm)"), qsTr("All files (*)")]
        onAccepted: root.editor.openFile(selectedFile)
    }
    FileDialog {
        id: saveDialog
        title: qsTr("Save Waveform")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("mybench waveform (*.mbw)")]
        defaultSuffix: "mbw"
        onAccepted: {
            if (root.editor.saveAs(selectedFile) && root.pendingAction) {
                const action = root.pendingAction
                root.pendingAction = null
                action()
            }
        }
        onRejected: root.pendingAction = null
    }
    FileDialog {
        id: exportDialog
        title: qsTr("Export Waveform")
        fileMode: FileDialog.SaveFile
        nameFilters: [qsTr("CSV (*.csv)"), qsTr("WAV audio, 32-bit float (*.wav)"), qsTr("Binary 16-bit, ±5 V (*.bin)"),
                      qsTr("LabVIEW waveform, mybench layout (*.wdt)")]
        defaultSuffix: "csv"
        onAccepted: root.editor.exportFile(selectedFile)
    }
    FileDialog {
        id: importFileDialog
        title: qsTr("Import")
        nameFilters: [qsTr("Waveforms (*.mbw *.wav *.csv *.txt *.bin *.wdt)"), qsTr("Text data (*.csv *.txt)"),
                      qsTr("WAV audio (*.wav)"), qsTr("Binary 16-bit (*.bin)"), qsTr("All files (*)")]
        onAccepted: importDialog.openFor(selectedFile)
    }

    ImportDialog {
        id: importDialog
        editor: root.editor
    }
    EditorSettingsDialog {
        id: settingsDialog
        editor: root.editor
    }
    ConfirmDialog {
        id: clearAllDialog
        title: qsTr("Clear waveform?")
        text: qsTr("Can be undone")
        acceptText: qsTr("Clear")
        destructive: true
        onAccepted: root.editor.deleteSelection()
    }
    Dialog {
        id: unsavedDialog
        title: qsTr("Save %1?").arg(root.editor.documentName)
        anchors.centerIn: Overlay.overlay
        modal: true
        width: 420
        Text {
            width: parent.width
            text: qsTr("Unsaved changes")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeBody
            wrapMode: Text.WordWrap
        }
        footer: RowLayout {
            spacing: Theme.spacingS
            Item { Layout.fillWidth: true }
            ActionButton {
                Layout.bottomMargin: Theme.spacingL
                text: qsTr("Cancel")
                onClicked: { root.pendingAction = null; unsavedDialog.close() }
            }
            ActionButton {
                Layout.bottomMargin: Theme.spacingL
                text: qsTr("Discard")
                tone: "danger"
                onClicked: {
                    unsavedDialog.close()
                    const action = root.pendingAction
                    root.pendingAction = null
                    if (action) action()
                }
            }
            ActionButton {
                Layout.bottomMargin: Theme.spacingL
                Layout.rightMargin: Theme.spacingL
                text: qsTr("Save")
                tone: "accent"
                onClicked: {
                    unsavedDialog.close()
                    const action = root.pendingAction
                    root.pendingAction = null
                    root.saveThen(action)
                }
            }
        }
    }
}
