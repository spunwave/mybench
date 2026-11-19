pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Effects
import QtQuick.Layouts
import MyBench.Framework

// The pane of an instrument: PaneHeader, the framework banners (paused, reconnected, input warning,
// error, pre-run conflict) and the panel's own, the display edge to edge, and an optional measurement
// strip. The panel places the controls (a column right of the display, or a dock under it); an
// instrument only declares them. The inspector is one Inspector item (`inspectorContent`) that the
// shell's InspectorDock claims while the pane is focused.
//     InstrumentPanel {
//         controller: root.controller
//         headerControls: [ Button { text: qsTr("Autoscale"); onClicked: root.controller.autoscale() } ]
//         BenchPlot { anchors.fill: parent }                     // the display
//         measurements: [ MeasurementTable { ... } ]
//         controls: [ ChannelCard { ... }, ChannelCard { ... } ]    // cards, in the column / dock
//         tools: ToolPalette { ... }                                // pinned at the foot of the column
//         toolPanels: [ ToolPanel { visible: root.tool === "measure"; ... } ]
//     }
Item {
    id: root

    property InstrumentController controller: null
    // A secondary view of the instrument ("gen/editor"); "" = the instrument's main pane.
    property string viewId: ""
    readonly property string instrumentId: controller ? controller.instrumentId : ""
    readonly property string paneId: viewId.length > 0 ? viewId : instrumentId
    readonly property string paneTitle: viewId.length > 0 ? (InstrumentRegistry.viewInfo(viewId).title ?? viewId)
                                                          : controller ? controller.title : ""
    readonly property string helpId: InstrumentRegistry.info(instrumentId).helpId ?? "app"
    property bool focused: false                   // set by the shell
    // Set by the shell for a split pane: the header's × (closeRequested(): Close Split, never stops
    // the instrument) and a short header note ("Split hidden — window too narrow").
    property bool closable: false
    // The shell's workspace: the header's title area can be dragged (split, swap, close).
    property bool draggable: false
    property string note: ""
    signal closeRequested()
    property string stateText: ""                  // overrides the derived state text
    property alias headerControls: header.extras   // pane-header extras, laid out like the settings
    // The pane header's own run controls of a panel that provides them (a RunButton, Single...):
    // first in the instrument bar.
    property alias headerContent: header.content
    // The instrument's primary parameters in the header (HeaderField: knob, − value +), after
    // Single; the whole bar wraps onto further rows when it does not fit row 1.
    property alias headerSettings: header.settings
    // false hides the header's own Run/Stop and Single (the panel provides its own).
    property alias showRunControls: header.showRunControls
    property list<QtObject> menuItems              // extra entries of the header's options menu
    default property alias display: displayArea.content
    property alias measurements: stripColumn.data
    // View state, saved per pane in the session.
    property bool measurementsVisible: SessionManager.viewState["measurements/" + paneId] !== false
    property alias banners: instrumentBanners.data
    property alias inspector: inspectorItem.sections
    // The cards of the control column / dock (ChannelCard and other sections), the pinned tool
    // palette and the floating tool panels. The panel builds the InstrumentColumn and places it.
    property alias controls: instrumentColumn.cards
    property alias tools: instrumentColumn.tools
    property alias toolPanels: toolArea.data
    // false: the instrument has no controls at the moment (a secondary view): no column, no dock.
    property bool showControls: true
    readonly property alias controlsColumn: instrumentColumn
    // false: nothing in `inspector` (the panel keeps its controls beside the display); the shell
    // then hides the inspector dock column (Help still opens there on request).
    property bool hasInspector: inspectorItem.sections.length > 0
    // [{ name, style: TraceStyle, color }]: "Trace Style…" in ⋯ and in the plots' context menus.
    property var traceStyles: []
    readonly property Item inspectorContent: inspectorItem
    readonly property bool inspectorClaimed: inspectorItem.parent !== localSlot
    signal ready()

    property alias runBar: header
    property alias runBarControls: header.extraControls
    property alias runBarActions: header.actions
    property alias displayTools: header.displayTools
    property string displayTitle      // the display's one-line summary
    property string displayInfo       // state detail when the controller has no summary
    property int narrowWidth: 820
    property int inspectorWidth: Math.round(SessionManager.viewState["inspector/width"] ?? Theme.inspectorWidth)
    property bool showErrorBanner: true
    property bool showExport: true
    property alias inspectorItem: inspectorItem
    property alias displayArea: displayArea
    property alias paneHeader: header

    // Local inspector (no dock): docked when wide enough, else an overlay sheet.
    property bool inspectorVisible: true
    property bool inspectorOverlayOpen: false
    readonly property bool narrow: width < narrowWidth
    readonly property bool focusMode: instrumentId.length > 0 && ShellActions.focusInstrument === instrumentId
    readonly property bool localInspector: hasInspector && !inspectorClaimed && privateState.fallbackArmed
                                           && PanelRegistry.dockCount === 0
    readonly property bool inspectorDocked: localInspector && inspectorVisible && !narrow && !focusMode
    readonly property bool overlayShown: localInspector && narrow && inspectorOverlayOpen && !focusMode

    // --- Control layout (the aspect rule, Theme "pane layout contract") -------------------------
    readonly property bool hasControls: showControls && instrumentColumn.contentCount > 0
    readonly property bool compactColumn: width < Theme.instrumentCompactWidth
    readonly property real columnWidth: compactColumn ? Theme.instrumentColumnCompactWidth : Theme.instrumentColumnWidth
    // The height the display would have beside the column: the pane under the header and one row
    // of measurement cards.
    readonly property real columnDisplayHeight: Math.max(1, height - header.height
                                                         - (strip.visible ? Theme.measurementRowHeight + 1 : 0))
    // How far the display would be from landscape (width minus 1.2 x height) beside the column.
    readonly property real aspectMargin: width - columnWidth - Theme.paneAspect * columnDisplayHeight
    // true: the controls are in the dock under the display. Hysteresis: back to the column only
    // when the margin is Theme.paneAspectHysteresis wide.
    property bool dockedState: false
    readonly property bool docked: hasControls && dockedState
    // The height budget of a docked pane, in this order: the header (its actual rows); the display,
    // at least dockDisplayMinHeight and displayMinShare of what the header leaves; the dock, as
    // tall as its cards need (every control visible, no scrolling) up to what the display and one
    // row of the strip leave; the strip, ONE row of its current form (more only while the display
    // keeps its share).
    readonly property real stage: Math.max(0, height - header.height)
    readonly property real displayFloor: Math.max(Theme.dockDisplayMinHeight, Theme.displayMinShare * stage)
    // The display stays the larger part: the dock takes at most half of what the strip leaves.
    // One row of the strip as it shows docked (the wide form; more rows page with arrows).
    readonly property real stripReserve: strip.visible ? Theme.measurementRowHeight + 1 : 0
    readonly property real dockCap: Math.max(Theme.dockMinHeight,
                                             Math.min(Theme.dockMaxHeight, stage - displayFloor - stripReserve, (stage - stripReserve) / 2))
    // What the cards need now (the tallest of the dock's columns), and the most they needed since
    // the pane got its size.
    readonly property real dockContent: instrumentColumn.contentTall <= 0 ? 0
        : Math.max(instrumentColumn.contentTall + Theme.cardMargin + 1, instrumentColumn.anyFolded ? dockCap : 0)
    property real dockNeed: 0
    // A setting that makes the cards taller grows the dock up to dockCap only (the display never
    // changes with a setting beyond that); the pane's size or form refits it, up to dockRoom.
    onDockContentChanged: if (dockContent > dockNeed) dockNeed = Math.max(dockNeed, Math.min(dockContent, dockCap))
    function refitDock() {
        instrumentColumn.refit()
        dockNeed = dockContent
    }
    onWidthChanged: Qt.callLater(refitDock)
    onHeightChanged: Qt.callLater(refitDock)
    onDockedChanged: Qt.callLater(refitDock)
    onDockCapChanged: Qt.callLater(refitDock)
    // false: the dock keeps the pane-proportional height (clamp(dockHeightRatio x stage, dockMinHeight,
    // dockMaxHeight)), for cards that hold lists, which scroll in themselves (the waveform editor).
    property bool dockFitsCards: true
    readonly property real dockHeight: !dockFitsCards
        ? Math.round(Math.max(Theme.dockMinHeight, Math.min(Theme.dockMaxHeight, Theme.dockHeightRatio * stage)))
        : Math.round(Math.min(dockRoom, dockNeed > 0 ? Math.max(Theme.dockMinContentHeight, dockNeed) : Theme.dockMinHeight))
    // The cards fold to fit dockCap (instrumentColumn.bandFoldHeight), one card per column open; the
    // graph keeps its room ("this cuts too much of the graph"): beyond the cap, little arrows.
    readonly property real dockRoom: dockCap
    // The column's size in the current form: what the controls take away from the display.
    readonly property real controlsWidth: hasControls && !docked ? columnWidth : 0
    readonly property real controlsHeight: hasControls && docked ? dockHeight : 0
    // The tallest the measurement strip may be (its `maximumHeight`).
    readonly property real stripBudget: Math.max(Theme.measurementRowHeight,
        docked ? stage - dockHeight - displayFloor
               : Math.min(2 * Theme.measurementCardTallHeight, Theme.stripColumnShare * stage))
    // Docked only: what the strip may take for a second row (never more than two rows) when that
    // makes every card visible; the display then keeps 200 px and 45 % of what the header leaves,
    // the usual budget above keeps half.
    readonly property real stripExtendedBudget: docked ? Math.max(0, stage - dockHeight - Math.max(Theme.dockDisplayMinHeight, 0.45 * stage)) : 0
    function updateDock() {
        if (dockedState && aspectMargin >= Theme.paneAspectHysteresis)
            dockedState = false
        else if (!dockedState && aspectMargin < 0)
            dockedState = true
    }
    onAspectMarginChanged: updateDock()

    // --- Functions -------------------------------------------------------------------------------
    // InspectorDock hands the inspector back (or the panel takes it back when the dock goes away).
    function releaseInspector() {
        if (inspectorItem.parent !== localSlot)
            inspectorItem.parent = localSlot
    }
    function toggleInspector() {
        if (narrow)
            inspectorOverlayOpen = !inspectorOverlayOpen
        else
            inspectorVisible = !inspectorVisible
    }
    function setMeasurementsVisible(visible: bool) {
        SessionManager.setViewValue("measurements/" + paneId, visible)
    }
    function showHelp() {
        Help.show(helpId)
    }
    function requestResetSettings() {
        resetConfirm.open()
    }
    // Inspector sections keep their collapsed state per pane and section id (view state).
    function keySections() {
        if (paneId.length === 0)
            return
        for (const item of inspectorItem.sections) {
            if (!(item instanceof Section))
                continue
            const section = item as Section
            const id = section.sectionId.length > 0 ? section.sectionId : section.title
            if (id.length > 0 && (section.stateKey.length === 0 || section.stateKey.startsWith("section/")))
                section.stateKey = "section/" + paneId + "/" + id
        }
    }
    function openTraceStyleDialog(index = 0) {
        traceStyleLoader.active = true
        const dialog = traceStyleLoader.item as TraceStyleDialog
        if (dialog)
            dialog.openFor(index)
    }
    function exportData() {
        if (!controller || !controller.hasData) {
            Notifications.notify(Notifications.Info, qsTr("No data"), "")
            return
        }
        dataLoader.active = true
        const dialog = dataLoader.item as FileDialog
        dialog.currentFolder = DataExport.lastFolderFor("csv")
        dialog.selectedFile = DataExport.suggestedFileUrl(instrumentId, "csv")
        dialog.open()
    }
    // Export Image… / Print…: the PrintDialog options first (ink saver, stamps, settings table,
    // orientation, printer), then the file (image, PDF) or the printer.
    function exportImage(pdf: bool) {
        openPrintDialog(pdf ? "pdf" : "image")
    }
    function printPanel() {
        openPrintDialog(DataExport.printingAvailable ? "printer" : "pdf")
    }
    function openPrintDialog(destination: string) {
        printLoader.active = true
        const dialog = printLoader.item as PrintDialog
        dialog.destination = destination
        dialog.open()
    }
    function continuePrint() {
        const options = (printLoader.item as PrintDialog).options()
        if (options.destination === "printer") {
            writeImage("", options)
            return
        }
        const pdf = options.destination === "pdf"
        imageLoader.active = true
        const dialog = imageLoader.item as FileDialog
        dialog.pdf = pdf
        dialog.exportOptions = options
        dialog.currentFolder = DataExport.lastFolderFor(pdf ? "pdf" : "png")
        dialog.selectedFile = DataExport.suggestedFileUrl(instrumentId, pdf ? "pdf" : "png")
        dialog.open()
    }
    // Grabs the display (or the whole pane, options.target) at 2x and writes it. `options`:
    // PrintDialog.options(), or a bool (true = PDF, default options).
    function writeImage(file: url, options: var) {
        const o = typeof options === "boolean" ? { destination: options ? "pdf" : "image" } : options
        const title = controller ? controller.title : ""
        const metadata = controller ? controller.exportMetadata() : {}
        const source = o.target === "panel" ? root : displayArea
        source.grabToImage(result => {
            const temporary = DataExport.temporaryFilePath("png")
            if (!result.saveToFile(temporary)) {
                Notifications.notify(Notifications.Error, qsTr("Image not saved"), temporary)
                return
            }
            const path = DataExport.localPath(file)
            if (o.destination === "printer") {
                if (DataExport.print(temporary, title, metadata, o))
                    Notifications.notify(Notifications.Success, qsTr("Printed"), o.printer ?? "")
                else
                    Notifications.notify(Notifications.Error, qsTr("Not printed"), DataExport.lastError)
            } else if (o.destination === "pdf") {
                if (DataExport.writePdf(file, temporary, title, metadata, o))
                    Notifications.notify(Notifications.Success, qsTr("PDF exported"), path)
                else
                    Notifications.notify(Notifications.Error, qsTr("PDF not saved"), DataExport.lastError)
            } else {
                if (DataExport.writeImage(file, temporary, title, metadata, o))
                    Notifications.notify(Notifications.Success, qsTr("Image exported"), path)
                else
                    Notifications.notify(Notifications.Error, qsTr("Image not saved"), DataExport.lastError)
            }
        }, Qt.size(source.width * 2, source.height * 2))
    }

    // --- Registration --------------------------------------------------------------------------
    QtObject {
        id: privateState
        property bool completed: false
        property bool fallbackArmed: false
        property string registeredId: ""
        property string dismissedConflict: ""
    }
    function registerPane() {
        if (!privateState.completed || privateState.registeredId === paneId)
            return
        if (privateState.registeredId.length > 0)
            PanelRegistry.unregister(privateState.registeredId, root)
        privateState.registeredId = paneId
        if (paneId.length > 0) {
            PanelRegistry.register(paneId, root)
            root.ready()
        }
    }
    onPaneIdChanged: {
        keySections()
        registerPane()
    }
    Component.onCompleted: {
        privateState.completed = true
        updateDock()
        keySections()
        registerPane()
    }
    Component.onDestruction: {
        if (privateState.registeredId.length > 0)
            PanelRegistry.unregister(privateState.registeredId, root)
    }
    // No dock claimed the inspector by the next event-loop turn: dock it locally.
    Timer {
        interval: 0
        running: true
        onTriggered: privateState.fallbackArmed = true
    }
    onNarrowChanged: inspectorOverlayOpen = false

    readonly property var conflict: {
        const c = controller
        if (!c || c.running || c.paused || !DeviceHub.connected)
            return null
        const flags = [ResourceArbiter.AnalogInput, ResourceArbiter.AnalogOutput, ResourceArbiter.Multimeter,
                       ResourceArbiter.DigitalLines, ResourceArbiter.Counter, ResourceArbiter.FrequencyOutput]
        const labels = []
        const titles = []
        for (const h of ResourceArbiter.holders) {
            if (h.instrumentId === c.instrumentId)
                continue
            const flag = flags.find(f => ResourceArbiter.label(f) === h.resource)
            if (flag === undefined || (c.resources & flag) === 0)
                continue
            if (flag === ResourceArbiter.DigitalLines) {
                const other = InstrumentRegistry.controller(h.instrumentId)
                if (!other || (other.dioLines & c.dioLines) === 0)
                    continue
            }
            if (labels.indexOf(h.resource) < 0)
                labels.push(h.resource)
            if (titles.indexOf(h.title) < 0)
                titles.push(h.title)
        }
        if (labels.length === 0)
            return null
        const and = qsTr(" and ")
        return {
            key: labels.join(",") + "|" + titles.join(","),
            text: titles.length > 1 ? qsTr("%1 in use by %2").arg(labels.join(and)).arg(titles.join(and))
                                    : qsTr("%1 in use by %2").arg(labels.join(and)).arg(titles[0])
        }
    }

    // --- Dialogs (created on first use) --------------------------------------------------------
    Loader {
        id: traceStyleLoader
        active: false
        sourceComponent: TraceStyleDialog { entries: root.traceStyles }
    }
    Loader {
        id: dataLoader
        active: false
        sourceComponent: FileDialog {
            title: qsTr("Export %1 Data").arg(root.paneTitle)
            fileMode: FileDialog.SaveFile
            nameFilters: DataExport.nameFiltersFor(root.instrumentId)
            onAccepted: root.controller.exportData(selectedFile)
        }
    }
    Loader {
        id: printLoader
        active: false
        sourceComponent: PrintDialog {
            instrumentTitle: root.paneTitle
            onAccepted: root.continuePrint()
        }
    }
    Loader {
        id: imageLoader
        active: false
        sourceComponent: FileDialog {
            property bool pdf: false
            property var exportOptions: ({})
            title: pdf ? qsTr("Export PDF") : qsTr("Export Image")
            fileMode: FileDialog.SaveFile
            nameFilters: pdf ? [qsTr("PDF (*.pdf)")] : [qsTr("PNG image (*.png)")]
            defaultSuffix: pdf ? "pdf" : "png"
            onAccepted: root.writeImage(selectedFile, exportOptions)
        }
    }
    ConfirmDialog {
        id: resetConfirm
        title: qsTr("Reset %1?").arg(root.paneTitle)
        text: qsTr("All settings to default")
        acceptText: qsTr("Reset")
        destructive: true
        onAccepted: root.controller.resetSettings()
    }

    Keys.onEscapePressed: event => {
        event.accepted = inspectorOverlayOpen
        inspectorOverlayOpen = false
    }

    // --- Layout ----------------------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: Theme.window
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        PaneHeader {
            id: header
            Layout.fillWidth: true
            z: 2                               // the settings popup opens over the display
            controller: root.controller
            title: root.paneTitle
            iconName: root.viewId.length > 0 ? (InstrumentRegistry.viewInfo(root.viewId).icon ?? "")
                                             : (InstrumentRegistry.info(root.instrumentId).icon ?? "")
            stateText: root.stateText
            detailText: root.displayInfo
            focused: root.focused
            closable: root.closable
            paneId: root.paneId
            draggable: root.draggable
            note: root.note
            onCloseRequested: root.closeRequested()
            menuItems: root.menuItems
            showExport: root.showExport
            hasTraceStyles: root.traceStyles.length > 0
            measurementsAvailable: strip.hasContent
            measurementsShown: root.measurementsVisible
            showInspectorToggle: root.localInspector && !root.focusMode
            inspectorShown: root.narrow ? root.inspectorOverlayOpen : root.inspectorVisible
            onExportDataRequested: root.exportData()
            onExportImageRequested: root.exportImage(false)
            onPrintRequested: root.printPanel()
            onResetRequested: root.requestResetSettings()
            onHelpRequested: root.showHelp()
            onTraceStyleRequested: root.openTraceStyleDialog()
            onMeasurementsToggled: root.setMeasurementsVisible(!root.measurementsVisible)
            onInspectorToggleRequested: root.toggleInspector()
        }

        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
            // The area the display and the controls share: the body without the docked inspector.
            readonly property real stageWidth: width - (root.inspectorDocked ? localHost.width : 0)

            ColumnLayout {
                id: displayColumn
                anchors.left: parent.left
                anchors.top: parent.top
                width: body.stageWidth - root.controlsWidth
                height: body.height - root.controlsHeight
                spacing: 0

                ColumnLayout {
                    id: bannerColumn
                    readonly property bool any: pausedBanner.visible || reconnectedBanner.visible || inputBanner.visible
                                                || errorBanner.visible || conflictBanner.visible
                                                || instrumentBanners.visibleChildren.length > 0
                    // Never hidden itself: a hidden column makes every banner's `visible` read
                    // false, so `any` could never turn true again (an unplug showed no reason).
                    // With no banner it is empty and drops its margins.
                    Layout.fillWidth: true
                    Layout.fillHeight: false          // a nested layout fills by default: its content height only
                    Layout.margins: any ? Theme.spacingS : 0
                    spacing: Theme.spacingXs

                    Banner {
                        id: pausedBanner
                        objectName: "pausedBanner"
                        Layout.fillWidth: true
                        visible: root.controller !== null && root.controller.paused
                        tone: "warning"
                        text: root.controller ? root.controller.pauseReason.replace(/^.*? paused — /, "") : ""
                        Button {
                            flat: true
                            text: qsTr("Resume")
                            onClicked: root.controller.resume()
                        }
                    }
                    Banner {
                        id: reconnectedBanner
                        objectName: "reconnectedBanner"
                        Layout.fillWidth: true
                        visible: root.controller !== null && root.controller.interruptedByDisconnect
                                 && !root.controller.running && DeviceHub.connected
                        tone: "success"
                        text: qsTr("Device reconnected")
                        Button {
                            flat: true
                            text: qsTr("Resume")
                            onClicked: root.controller.run()
                        }
                    }
                    // A run refused because of the user's input (InvalidInput): a warning.
                    Banner {
                        id: inputBanner
                        objectName: "inputBanner"
                        Layout.fillWidth: true
                        visible: root.showErrorBanner && root.controller !== null && !root.controller.hasError
                                 && root.controller.inputWarning.length > 0 && !root.controller.running
                        tone: "warning"
                        text: root.controller ? root.controller.inputWarning : ""
                        closable: true
                        onClosed: root.controller.clearInputWarning()
                    }
                    Banner {
                        id: errorBanner
                        objectName: "errorBanner"
                        Layout.fillWidth: true
                        visible: root.showErrorBanner && root.controller !== null && root.controller.hasError
                                 && !root.controller.running
                        tone: "danger"
                        text: root.controller ? root.controller.errorText : ""
                        closable: true
                        onClosed: root.controller.clearError()
                        Button {
                            flat: true
                            text: qsTr("Details")
                            ToolTip.visible: hovered
                            ToolTip.delay: Theme.toolTipDelay
                            ToolTip.text: qsTr("Event Log")
                            onClicked: ShellActions.eventLogRequested()
                        }
                    }
                    Banner {
                        id: conflictBanner
                        objectName: "conflictBanner"
                        Layout.fillWidth: true
                        visible: root.conflict !== null && root.conflict.key !== privateState.dismissedConflict
                        tone: "info"
                        text: root.conflict ? root.conflict.text : ""
                        closable: true
                        onClosed: privateState.dismissedConflict = root.conflict ? root.conflict.key : ""
                    }
                    ColumnLayout {
                        id: instrumentBanners
                        Layout.fillWidth: true
                        Layout.fillHeight: false
                        // Not hidden when empty (same trap as above): with no child shown it has no height.
                        spacing: Theme.spacingXs
                    }
                }

                DisplayArea {
                    id: displayArea
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    summary: root.displayTitle
                }

                Rectangle {
                    id: strip
                    objectName: "stripHost"
                    readonly property bool hasContent: stripColumn.children.length > 0
                    readonly property Item first: hasContent ? stripColumn.children[0] : null
                    readonly property string summaryText: first && typeof first["summaryText"] === "string" ? first["summaryText"] : ""
                    readonly property bool collapsedToSummary: summaryText.length > 0 && root.Window.height > 0
                                                               && root.Window.height < Theme.shortHeight
                    visible: hasContent && root.measurementsVisible
                    color: Theme.window
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1 + (collapsedToSummary ? Theme.controlHeight
                                                                    : Math.max(Theme.measurementRowHeight, stripColumn.implicitHeight))

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: Theme.separator
                    }
                    Column {
                        id: stripColumn
                        y: 1
                        width: parent.width
                        spacing: 0
                        visible: !strip.collapsedToSummary
                        onChildrenChanged: {
                            for (const child of children) {
                                child.width = Qt.binding(() => stripColumn.width)
                                if (child.maximumHeight !== undefined)
                                    child.maximumHeight = Qt.binding(() => root.stripBudget)
                                if (child.extendedHeight !== undefined)
                                    child.extendedHeight = Qt.binding(() => root.stripExtendedBudget)
                            }
                        }
                    }
                    Text {
                        visible: strip.collapsedToSummary
                        y: 1
                        x: Theme.spacingM
                        width: parent.width - 2 * Theme.spacingM
                        height: Theme.controlHeight
                        verticalAlignment: Text.AlignVCenter
                        text: strip.summaryText
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                        font.features: Theme.tabularFigures
                        elide: Text.ElideRight
                    }
                }
            }

            InstrumentColumn {
                id: instrumentColumn
                objectName: "instrumentColumn"
                visible: root.hasControls
                managed: true
                bandFoldHeight: root.dockFitsCards ? Math.max(0, root.dockCap - Theme.cardMargin - 1) : 0
                compact: root.compactColumn
                orientation: root.docked ? Qt.Horizontal : Qt.Vertical
                bandHeight: root.dockHeight
                minimumBandColumnWidth: Theme.dockCardMinWidth
                maximumBandColumnWidth: 100000
                x: root.docked ? 0 : body.stageWidth - width
                y: root.docked ? body.height - height : 0
                width: root.docked ? body.stageWidth : root.columnWidth
                height: root.docked ? root.dockHeight : body.height
            }

            // Where an open tool panel floats: over the display's right side, in both layouts (the
            // display keeps its size; the cards, the strip and the palette are never covered).
            Item {
                id: toolArea
                objectName: "toolArea"
                readonly property bool isToolArea: true
                readonly property real margin: Theme.spacingS
                // The panels' own `visible` (what the instrument binds), read per child so the binding
                // follows each of them.
                readonly property Item openTool: {
                    let open = null
                    for (const child of children) {
                        if (child.maximumHeight !== undefined && child.visible && open === null)
                            open = child
                    }
                    return open
                }
                z: 10
                visible: root.hasControls
                x: displayColumn.x + displayColumn.width - width - margin
                y: displayColumn.y + displayArea.y + margin
                width: Math.max(0, Math.min(Theme.toolPanelWidth, displayArea.width - 2 * margin))
                height: Math.max(0, displayArea.height - 2 * margin)
                // Every tool panel declared inside takes the area's width and sits at its top.
                // The panels arrive while the panel is created, before `wired` exists: wired again once complete.
                property var wired: []
                onChildrenChanged: wire()
                Component.onCompleted: wire()
                function wire() {
                    if (!Array.isArray(wired))
                        return
                    for (const child of children) {
                        if (wired.indexOf(child) >= 0 || child.maximumHeight === undefined)
                            continue
                        wired.push(child)
                        child.x = 0
                        child.y = 0
                        child.width = Qt.binding(() => toolArea.width)
                        child.maximumHeight = Qt.binding(() => toolArea.height)
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                visible: root.overlayShown
                onClicked: root.inspectorOverlayOpen = false
                Rectangle {
                    anchors.fill: parent
                    color: Theme.overlay
                }
            }

            Item {
                id: localHost
                readonly property bool overlay: root.narrow
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: overlay ? Math.min(root.inspectorWidth, body.width - 48)
                               : Math.max(Theme.inspectorMinWidth, Math.min(Theme.inspectorMaxWidth, root.inspectorWidth))
                visible: root.inspectorDocked || root.overlayShown

                Rectangle {
                    id: localBackground
                    anchors.fill: parent
                    color: Theme.window
                    layer.enabled: localHost.overlay
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: Theme.shadowColor
                        shadowBlur: 1.0
                        shadowHorizontalOffset: -2
                        blurMax: Theme.shadowBlur
                    }
                }
                Rectangle {
                    width: 1
                    height: parent.height
                    color: Theme.separator
                }
                Item {
                    id: localSlot
                    objectName: "localInspectorSlot"
                    anchors.fill: parent
                    anchors.leftMargin: 1

                    Inspector {
                        id: inspectorItem
                        anchors.fill: parent   // follows the host it is moved to
                    }
                }

                MouseArea {
                    visible: !localHost.overlay
                    x: -3
                    width: 7
                    height: parent.height
                    cursorShape: Qt.SplitHCursor
                    hoverEnabled: true
                    property real startX: 0
                    property real startWidth: 0
                    onPressed: mouse => {
                        startX = mapToItem(body, mouse.x, 0).x
                        startWidth = localHost.width
                    }
                    onPositionChanged: mouse => {
                        if (!pressed)
                            return
                        const dx = mapToItem(body, mouse.x, 0).x - startX
                        root.inspectorWidth = Math.round(Math.max(Theme.inspectorMinWidth,
                                                                  Math.min(Theme.inspectorMaxWidth, startWidth - dx,
                                                                           body.width - Theme.paneMinWidth / 2)))
                    }
                    onReleased: SessionManager.setViewValue("inspector/width", root.inspectorWidth)
                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: parent.pressed || parent.containsMouse ? 2 : 0
                        height: parent.height
                        color: Theme.accent
                    }
                }
            }
        }
    }
}
