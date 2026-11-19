pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework

// Header of an instrument pane: icon, title and state, then the instrument bar in three groups
// (1 Run/Stop and Single, 2 primary parameters as HeaderFields, 3 display mode and the panel's own
// buttons), then Export, Reset, Help, Options and a close button. An item picks its group with
// `property int headerGroup: 1..3`. The bar shares row 1 when it fits, else it wraps below it.
// InstrumentPanel creates it; panels fill it through InstrumentPanel's headerControls, headerContent,
// headerSettings, displayTools and menuItems.
//     PaneHeader { controller: root.controller; settings: [ HeaderField { toolTip: qsTr("Timebase"); ... } ] }
Rectangle {
    id: header

    // The controller, or the registry's controller of `instrumentId`.
    property string instrumentId: ""
    property InstrumentController controller: instrumentId.length > 0 ? InstrumentRegistry.controller(instrumentId) : null
    property string title: controller ? controller.title : ""
    property string iconName: controller ? (InstrumentRegistry.info(controller.instrumentId).icon ?? "") : ""
    // Overrides the state text derived from the controller.
    property string stateText: ""
    // A short fact after the state ("200 kS/s"): this text, else the controller's summary, else
    // the rate while running. It is the first thing dropped.
    property string detailText: ""
    // The shell marks the focused pane of a split; a single pane is not "focused" (but is not
    // `closable` either: only the panes of a split are).
    property bool focused: false
    // The shell's split: an × at the end that emits closeRequested() (Close Split; it never stops
    // the instrument), and a short note in place of the detail ("Split hidden").
    property bool closable: false
    property string closeToolTip: qsTr("Close Split")
    property string note: ""
    // The shell's workspace: the icon and name can be dragged (`titleDrag`; the shell shows the
    // drag image and handles the drop: swap the panes, or close the pane on the sidebar).
    property string paneId: ""
    property bool draggable: false
    property alias titleDrag: titleDragHandler
    // Number of rows of Theme.paneHeaderHeight (1 when the bar shares row 1).
    readonly property int rows: barInline ? 1 : 1 + barRows
    readonly property bool twoRows: rows > 1
    readonly property bool narrow: twoRows

    // Run options (the names of the legacy RunBar).
    property string runText: qsTr("Run")
    property string stopText: qsTr("Stop")
    property string resumeText: qsTr("Resume")
    property string singleText: qsTr("Single")
    property string singleIcon: "step"
    property string singleToolTip: qsTr("Acquire once, then stop")
    property bool showSingle: controller ? controller.supportsSingle : false
    property bool singleEnabled: controller ? controller.singleEnabled : false
    property bool showRelease: controller !== null && controller.holdsOutputs && !running
    property string releaseText: qsTr("Release Outputs")
    property string releaseToolTip: qsTr("Return the outputs to their safe state (AO to 0 V, digital lines to inputs)")
    property bool showTimeout: false
    property string timeoutText: qsTr("Timeout")
    property bool showRate: true

    // What the panel puts in the instrument bar, in this order after Run / Stop, Single and
    // Release: `content` (the panel's own run controls), `settings` (primary parameters:
    // HeaderField), `extras` and `actions` (buttons), `extraControls` (legacy name), `displayTools`
    // (the display-mode selector, last).
    property list<QtObject> settings
    default property list<QtObject> actions
    property list<QtObject> extras
    property list<QtObject> extraControls
    property list<QtObject> displayTools
    property list<QtObject> content
    // false: no Run/Stop and Single of the header (the panel provides its own in `content`).
    property bool showRunControls: true
    // The state text and its dot.
    property bool showState: true
    // Extra options-menu entries (MenuItem, Menu, Action, MenuSeparator), after the instrument's
    // commands.
    property list<QtObject> menuItems

    property bool showExport: true
    property bool hasTraceStyles: false
    property bool measurementsAvailable: false
    property bool measurementsShown: true
    property bool showInspectorToggle: false
    property bool inspectorShown: true

    signal exportDataRequested()
    signal exportImageRequested()
    signal printRequested()
    signal resetRequested()
    signal helpRequested()
    signal traceStyleRequested()
    signal measurementsToggled()
    signal inspectorToggleRequested()
    // The × of a closable header (the shell closes the split pane).
    signal closeRequested()
    signal popOutRequested()

    readonly property bool running: controller !== null && controller.running
    readonly property bool paused: controller !== null && controller.paused
    readonly property bool timedOut: showTimeout && controller !== null && controller.timedOut
    // "running" | "waiting" | "paused" | "error" | "stopped" (the state dot)
    readonly property string status: {
        const c = controller
        if (!c)
            return "stopped"
        if (c.paused)
            return "paused"
        if (c.running)
            return c.timedOut ? "waiting" : "running"
        if (c.hasError)
            return "error"
        return "stopped"
    }
    // The derived state text (legacy RunBar.statusText).
    readonly property string statusText: {
        const c = controller
        if (!c)
            return ""
        switch (c.state) {
        case InstrumentController.Starting:
            return startingTimer.slow ? qsTr("Starting…") : qsTr("Running")
        case InstrumentController.Stopping:
            return qsTr("Stopping…")
        case InstrumentController.Running:
            return c.statusText.length > 0 ? c.statusText
                 : c.runMode === InstrumentController.Once ? qsTr("Single acquisition") : qsTr("Running")
        case InstrumentController.Paused:
            return qsTr("Paused")
        default:
            if (c.hasError)
                return qsTr("Error")
            if (!DeviceHub.connected)
                return qsTr("No device")
            return c.statusText.length > 0 ? c.statusText : c.hasData ? qsTr("Stopped") : qsTr("Ready")
        }
    }
    readonly property string effectiveStateText: stateText.length > 0 ? stateText : statusText
    readonly property string effectiveDetail: {
        if (controller === null || paused)
            return ""
        // A blank detailText (a space) suppresses the detail.
        if (detailText.length > 0)
            return detailText.trim()
        if (controller.summary.trim().length > 0)
            return controller.summary.trim()
        return running && showRate && controller.sampleRate > 0 ? Units.format(controller.sampleRate, "S/s", 3) : ""
    }
    readonly property color stateColor: status === "running" ? Theme.positive
                                      : status === "error" ? Theme.negative
                                      : status === "paused" ? Theme.caution : Theme.textSecondary


    implicitHeight: Theme.paneHeaderHeight * rows
    implicitWidth: 440
    color: Theme.window

    // "Starting…" only for a start slower than 300 ms.
    Timer {
        id: startingTimer
        property bool slow: false
        interval: 300
        running: header.controller !== null && header.controller.state === InstrumentController.Starting
        onRunningChanged: if (running) slow = false
        onTriggered: slow = true
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Theme.separator
        z: 1
    }

    readonly property real edgeLeft: Theme.spacingM
    readonly property real edgeRight: Theme.spacingXs
    readonly property real gap: Theme.spacingS
    readonly property real rowHeight: Theme.paneHeaderHeight

    // The longest state word, so that the fit of the bar does not change with the state.
    FontMetrics {
        id: stateMetrics
        font.pixelSize: Theme.fontSizeBody
    }
    readonly property real referenceStateWidth: 12 + Math.ceil(stateMetrics.advanceWidth("Generating"))

    // --- Row 1: icon, title, state ----------------------------------------------------------------
    Row {
        id: titleArea
        objectName: "paneTitleArea"
        x: header.edgeLeft
        height: header.rowHeight
        spacing: Theme.spacingS
        Icon {
            id: titleIcon
            visible: header.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
            name: header.iconName
            size: Theme.iconSizeL
            color: Theme.textSecondary      // the accent marks selection only
        }
        Text {
            id: titleLabel
            objectName: "paneTitle"
            anchors.verticalCenter: parent.verticalCenter
            text: header.title
            color: !header.closable || header.focused ? Theme.text : Theme.textSecondary
            font.pixelSize: Theme.fontSizeTitle
            font.weight: Font.DemiBold
        }
        DragHandler {
            id: titleDragHandler
            target: null
            enabled: header.draggable && header.paneId.length > 0
            cursorShape: Qt.ClosedHandCursor
        }
        HoverHandler {
            enabled: titleDragHandler.enabled
            cursorShape: Qt.OpenHandCursor
        }
    }

    Row {
        id: stateArea
        objectName: "paneStateArea"
        visible: header.showState
        x: titleArea.x + titleArea.width + header.gap
        height: header.rowHeight
        spacing: 6
        Rectangle {
            id: stateDot
            visible: header.status !== "stopped" && !header.leadTight
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: header.status === "running" ? Theme.positive
                 : header.status === "error" ? Theme.negative : Theme.caution
        }
        Text {
            id: stateLabel
            objectName: "paneState"
            anchors.verticalCenter: parent.verticalCenter
            text: header.timedOut ? header.timeoutText : header.effectiveStateText
            color: header.timedOut ? Theme.caution
                 : header.status === "running" ? Theme.positive : header.stateColor
            font.pixelSize: Theme.fontSizeBody
        }
    }

    readonly property bool leadTight: width - edgeLeft - edgeRight - titleArea.width - gap - gap
                                      - (stateLabel.implicitWidth + 12) - actionGroup.width < 0
    // What row 1 needs before the bar: the title, and the state at its widest.
    readonly property real leadWidth: titleArea.width + (showState ? gap + Math.max(stateArea.width, referenceStateWidth) : 0)

    // --- The action group: one fixed block at the right edge. Nothing else is placed in it. -------
    Row {
        id: actionGroup
        objectName: "paneActions"
        anchors.right: parent.right
        anchors.rightMargin: header.edgeRight
        height: header.rowHeight
        spacing: 4
        IconButton {
            size: 32
            iconSize: Theme.iconSizeL
            id: inspectorButton
            objectName: "inspectorToggle"
            anchors.verticalCenter: parent.verticalCenter
            visible: header.showInspectorToggle
            iconName: "sidebar-right"
            checkable: true
            checked: header.inspectorShown
            toolTip: header.inspectorShown ? qsTr("Hide Inspector") : qsTr("Show Inspector")
            shortcutText: Theme.keys("Ctrl+I")
            onClicked: header.inspectorToggleRequested()
        }
        IconButton {
            size: 32
            iconSize: Theme.iconSizeL
            id: exportButton
            objectName: "exportButton"
            anchors.verticalCenter: parent.verticalCenter
            visible: header.showExport
            iconName: "export"
            toolTip: qsTr("Export")
            shortcutText: Theme.keys("Ctrl+E")
            down: exportMenu.visible || pressed
            onClicked: exportMenu.popup(exportButton, 0, exportButton.height)
        }
        IconButton {
            size: 32
            iconSize: Theme.iconSizeL
            id: resetButton
            objectName: "resetButton"
            anchors.verticalCenter: parent.verticalCenter
            visible: header.controller !== null
            iconName: "reset"
            toolTip: qsTr("Reset %1 to Defaults…").arg(header.title)
            onClicked: header.resetRequested()
        }
        IconButton {
            size: 32
            iconSize: Theme.iconSizeL
            id: helpButton
            objectName: "helpButton"
            anchors.verticalCenter: parent.verticalCenter
            iconName: "help-circle"
            toolTip: qsTr("Help")
            shortcutText: "F1"
            onClicked: header.helpRequested()
        }
        IconButton {
            size: 32
            iconSize: Theme.iconSizeL
            id: optionsButton
            objectName: "optionsButton"
            anchors.verticalCenter: parent.verticalCenter
            visible: optionsMenu.count > 0
            iconName: "sliders"
            toolTip: qsTr("Instrument Options")
            down: optionsMenu.visible || pressed
            onClicked: optionsMenu.popup(optionsButton, optionsButton.width - optionsMenu.implicitWidth, optionsButton.height)
        }
        IconButton {
            size: 32
            iconSize: Theme.iconSizeL
            id: closeButton
            objectName: "closeButton"
            anchors.verticalCenter: parent.verticalCenter
            visible: header.closable
            iconName: "close"
            toolTip: header.closeToolTip
            onClicked: header.closeRequested()
        }
    }

    // --- The short fact: after the state when the bar is below, after the bar when it shares row 1;
    // only where there is room, and the first thing to go. -----------------------------------------
    readonly property string detailShown: note.length > 0 ? note : effectiveDetail
    Text {
        id: detailLabel
        objectName: "paneDetail"
        property bool elideAllowed: true
        readonly property real startX: header.barInline && header.barCount > 0
                                       ? header.barX + header.barNatural + header.gap
                                       : stateArea.x + (header.showState ? stateArea.width : 0) + header.gap
        readonly property real room: actionGroup.x - header.gap - startX
        x: startX
        y: (header.rowHeight - height) / 2
        width: Math.max(0, Math.min(Math.ceil(implicitWidth), room))
        visible: header.note.length === 0 && text.length > 0 && room >= 56
        text: header.effectiveDetail
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeBody
        font.features: Theme.tabularFigures
        elide: Text.ElideRight
        maximumLineCount: 1
    }
    Text {
        id: noteLabel
        objectName: "paneNote"
        property bool elideAllowed: true
        x: detailLabel.startX
        y: (header.rowHeight - height) / 2
        width: Math.max(0, Math.min(Math.ceil(implicitWidth), detailLabel.room))
        visible: header.note.length > 0 && detailLabel.room >= 56
        text: header.note
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
        maximumLineCount: 1
    }

    // --- The instrument bar --------------------------------------------------------------------------
    // Every item of the bar is a direct child of `bar`, placed by layoutBar(): in row 1 when the whole
    // bar fits there, else from the second row on, wrapping at the header's width, one row height per
    // row, 8 px between items, a group moving to the next row as a whole.
    property real barX: edgeLeft
    property real barY: 0
    property real barNatural: 0
    property int barRows: 1
    property int barCount: 0
    property bool barInline: true
    property var barItems: []
    property var barGroups: [[], [], []]
    property bool laying: false

    Item {
        id: bar
        objectName: "paneHeaderBar"
        x: header.barX
        y: header.barY
        width: header.barInline ? header.barNatural : Math.max(0, header.width - header.edgeLeft - header.edgeRight)
        height: header.rowHeight * header.barRows

        Repeater {
            id: separatorRepeater
            model: 2
            Rectangle {
                required property int index
                objectName: "paneGroupSeparator" + index
                visible: false
                width: 1
                height: 20
                color: Theme.separator
            }
        }
        RunButton {
            id: runButton
            objectName: "runButton"
            property int headerGroup: 1
            visible: header.showRunControls
            running: header.running
            runText: header.paused ? header.resumeText : header.runText
            stopText: header.stopText
            widthText: header.resumeText
            busy: header.controller !== null && header.controller.state === InstrumentController.Stopping
            enabled: header.controller !== null
                     && (running ? header.controller.state !== InstrumentController.Stopping : header.controller.canRun)
            shortcutText: Theme.keys("Space")
            onToggled: header.controller.toggle()
        }
        Button {
            id: singleButton
            objectName: "singleButton"
            visible: header.showSingle && header.showRunControls
            text: header.singleText
            icon.source: Theme.icon(header.singleIcon)
            property int headerGroup: 1
            enabled: header.controller !== null && header.singleEnabled
                     && (header.controller.canRun
                         || (header.controller.state === InstrumentController.Running
                             && header.controller.runMode === InstrumentController.Continuous))
            focusPolicy: Qt.TabFocus
            onClicked: header.controller.runOnce()
            Accessible.name: header.singleText
            ToolTip.visible: hovered
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: header.singleToolTip + "   " + Theme.keys("Shift+Space")
        }
        Button {
            id: releaseButton
            objectName: "releaseButton"
            visible: header.showRelease
            text: header.releaseText
            property int headerGroup: 3
            icon.source: Theme.icon("power")
            focusPolicy: Qt.TabFocus
            onClicked: header.controller.returnToSafeState()
            Accessible.name: header.releaseText
            ToolTip.visible: hovered
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: header.releaseToolTip
        }
    }

    function isItem(o): bool {
        return o !== null && o !== undefined && o.implicitWidth !== undefined && o.visible !== undefined
    }
    function itemWidth(it): real {
        return Math.ceil(it.implicitWidth > 0 ? it.implicitWidth : it.width)
    }
    function itemHeight(it): real {
        return it.implicitHeight > 0 ? it.implicitHeight : it.height
    }
    readonly property real groupGap: Theme.spacingM
    readonly property real separatorSpan: 2 * groupGap + 1
    function groupHint(it, fallback: int): int {
        const hint = it.headerGroup
        return hint >= 1 && hint <= 3 ? hint : fallback
    }
    // Adopts the panel's items (once each) into three groups: run controls, primary parameters, view
    // (the display-mode selector first, then the panel's own buttons).
    function gather() {
        const groups = [[], [], []]
        const add = (it, fallback) => {
            if (isItem(it))
                groups[groupHint(it, fallback) - 1].push(it)
        }
        add(runButton, 1)
        add(singleButton, 1)
        const isRun = it => it instanceof RunButton || it.text === singleText
        for (let i = 0; i < content.length; ++i) {
            if (isItem(content[i]) && isRun(content[i]))
                add(content[i], 1)
        }
        for (let i = 0; i < settings.length; ++i) {
            if (isItem(settings[i]) && settings[i] instanceof HeaderField)
                add(settings[i], 2)
        }
        for (let i = 0; i < displayTools.length; ++i)
            add(displayTools[i], 3)
        for (let i = 0; i < settings.length; ++i) {
            if (isItem(settings[i]) && !(settings[i] instanceof HeaderField))
                add(settings[i], 3)
        }
        for (const list of [extras, actions, extraControls]) {
            for (let i = 0; i < list.length; ++i)
                add(list[i], 3)
        }
        for (let i = 0; i < content.length; ++i) {
            if (isItem(content[i]) && !isRun(content[i]))
                add(content[i], 3)
        }
        add(releaseButton, 3)
        const wanted = groups[0].concat(groups[1], groups[2])
        for (const it of wanted) {
            if (barItems.indexOf(it) >= 0)
                continue
            if (it.parent !== bar)
                it.parent = bar
            it.visibleChanged.connect(scheduleLayout)
            it.implicitWidthChanged.connect(scheduleLayout)
            it.implicitHeightChanged.connect(scheduleLayout)
        }
        barItems = wanted
        barGroups = groups
    }
    // A size change caused by layoutBar() itself (setIconOnly toggling the buttons' labels while it
    // measures) must not queue another pass: that was a busy loop whenever the bar wraps.
    function scheduleLayout() {
        if (!laying)
            Qt.callLater(header.layoutBar)
    }
    // Lays the visible groups out as a plain flow, item by item in order: an item goes on the
    // current row when it fits, else it starts the next one. Two groups side by side on a row get a
    // hairline between them; none at the start of a row.
    function arrange(groups, limit, apply): int {
        const separatorItems = [0, 1].map(i => separatorRepeater.itemAt(i))
        if (apply) {
            for (const sep of separatorItems)
                if (sep) sep.visible = false
        }
        let x = 0
        let row = 0
        let separators = 0
        for (let gi = 0; gi < groups.length; ++gi) {
            const g = groups[gi]
            for (let ii = 0; ii < g.length; ++ii) {
                const it = g[ii]
                const w = itemWidth(it)
                let lead = 0
                let sep = false
                if (x > 0) {
                    sep = ii === 0
                    lead = sep ? separatorSpan : gap
                    if (x + lead + w > limit + 0.01) {
                        ++row
                        x = 0
                        lead = 0
                        sep = false
                    }
                }
                if (sep) {
                    const s = separatorItems[separators++]
                    if (apply && s) {
                        s.x = x + groupGap
                        s.y = row * rowHeight + (rowHeight - s.height) / 2
                        s.visible = true
                    }
                }
                x += lead
                if (apply) {
                    it.x = x
                    it.y = row * rowHeight + (rowHeight - itemHeight(it)) / 2
                }
                x += w
            }
        }
        return row + 1
    }
    // Own buttons with a pictogram may drop their label together (never a mix), when it saves a row.
    property var compactable: []
    property bool iconOnly: false
    function setIconOnly(on: bool) {
        const display = on ? AbstractButton.IconOnly : AbstractButton.TextBesideIcon
        for (const it of compactable) {
            if (it.display !== undefined && it.display !== display)
                it.display = display
        }
        iconOnly = on
    }
    property int layoutPasses: 0   // tests: a settled header stops laying out
    function layoutBar() {
        if (laying || width <= 0)
            return
        laying = true
        ++layoutPasses
        gather()
        compactable = barGroups[2].filter(it => it.visible !== undefined && it.display !== undefined
                                                && it.icon !== undefined && it.icon.source.toString().length > 0
                                                && it.text !== undefined && it.text.length > 0
                                                && !(it instanceof RunButton))
        const visibleGroups = () => barGroups.map(g => g.filter(it => it.visible)).filter(g => g.length > 0)
        const room = width - edgeLeft - leadWidth - gap - gap - actionGroup.width - edgeRight
        const limit = width - edgeLeft - edgeRight
        setIconOnly(false)
        let groups = visibleGroups()
        const measure = () => {
            let n = Math.max(0, groups.length - 1) * separatorSpan
            for (const g of groups)
                n += g.reduce((sum, it) => sum + itemWidth(it), 0) + (g.length - 1) * gap
            return n
        }
        let natural = measure()
        let inRow = groups.length === 0 || natural <= room
        let rows = inRow ? 1 : arrange(groups, limit, false)
        if (!inRow && compactable.some(it => it.visible)) {
            setIconOnly(true)
            groups = visibleGroups()
            const compactRows = arrange(groups, limit, false)
            if (compactRows < rows)
                rows = compactRows
            else
                setIconOnly(false)
            groups = visibleGroups()
            natural = measure()
        }
        arrange(groups, inRow ? Number.POSITIVE_INFINITY : limit, true)
        barCount = groups.reduce((n, g) => n + g.length, 0)
        barNatural = natural
        barRows = barCount === 0 ? 0 : rows
        barInline = inRow
        barX = inRow ? edgeLeft + leadWidth + gap : edgeLeft
        barY = inRow ? 0 : rowHeight
        laying = false
    }
    onWidthChanged: layoutBar()
    onLeadWidthChanged: scheduleLayout()
    onSettingsChanged: scheduleLayout()
    onActionsChanged: scheduleLayout()
    onExtrasChanged: scheduleLayout()
    onExtraControlsChanged: scheduleLayout()
    onDisplayToolsChanged: scheduleLayout()
    onContentChanged: scheduleLayout()
    Connections {
        target: actionGroup
        function onWidthChanged() { header.scheduleLayout() }
    }
    Component.onCompleted: {
        layoutBar()
        scheduleLayout()
        scheduleMenuRebuild()
    }

    // --- Menus --------------------------------------------------------------------------------
    // Export menu: native on desktop runs, in the window offscreen (screenshots, tests).
    Menu {
        id: exportMenu
        objectName: "exportMenu"
        popupType: Theme.inlinePopups ? Popup.Item : Popup.Native

        MenuItem {
            text: qsTr("Export Data…")
            enabled: header.showExport && header.controller !== null && header.controller.hasData
            onTriggered: header.exportDataRequested()
        }
        MenuItem {
            text: qsTr("Export Image…")
            enabled: header.showExport
            onTriggered: header.exportImageRequested()
        }
        MenuItem {
            text: qsTr("Print…")
            enabled: header.showExport
            onTriggered: header.printRequested()
        }
    }

    // Options menu: the controller's commands (that need no argument), Trace Style…, Show
    // Measurements, then the panel's menuItems.
    property alias menu: optionsMenu
    Menu {
        id: optionsMenu
        objectName: "paneMenu"
        popupType: Theme.inlinePopups ? Popup.Item : Popup.Native
    }
    property var commandEntries: []
    property var optionalEntries: []
    function scheduleMenuRebuild() {
        Qt.callLater(header.rebuildMenu)
    }
    function rebuildMenu() {
        while (optionsMenu.count > 0)
            optionsMenu.takeItem(0)
        for (const entry of [...commandEntries, ...optionalEntries, ...menuItems]) {
            if (entry instanceof Action)
                optionsMenu.addAction(entry as Action)
            else if (entry instanceof Menu)
                optionsMenu.addMenu(entry as Menu)
            else if (entry instanceof Item)
                optionsMenu.addItem(entry as Item)
        }
    }
    onMenuItemsChanged: scheduleMenuRebuild()
    Instantiator {
        model: header.controller ? header.controller.commands.filter(c => !c.argumentLabel) : []
        delegate: MenuItem {
            required property var modelData
            text: modelData.title
            enabled: modelData.enabled !== false
            onTriggered: header.controller.invokeCommand(modelData.id)
        }
        onObjectAdded: (index, object) => {
            header.commandEntries = [...header.commandEntries, object]
            header.scheduleMenuRebuild()
        }
        onObjectRemoved: (index, object) => {
            header.commandEntries = header.commandEntries.filter(e => e !== object)
            header.scheduleMenuRebuild()
        }
    }
    Instantiator {
        model: (header.hasTraceStyles ? ["trace"] : []).concat(header.measurementsAvailable ? ["measurements"] : [])
        delegate: MenuItem {
            required property string modelData
            text: modelData === "trace" ? qsTr("Trace Style…") : qsTr("Show Measurements")
            checkable: modelData === "measurements"
            checked: modelData === "measurements" && header.measurementsShown
            onTriggered: modelData === "trace" ? header.traceStyleRequested() : header.measurementsToggled()
        }
        onObjectAdded: (index, object) => {
            header.optionalEntries = [...header.optionalEntries, object]
            header.scheduleMenuRebuild()
        }
        onObjectRemoved: (index, object) => {
            header.optionalEntries = header.optionalEntries.filter(e => e !== object)
            header.scheduleMenuRebuild()
        }
    }
}
