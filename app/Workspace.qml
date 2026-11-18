pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import MyBench.Framework
import MyBench.Controls

// The content area: Overview, or one pane, or two panes side by side
// (ratio saved, divider snaps to the middle). Each pane's panel is created the first time it is shown (an
// asynchronous Loader behind a pane-shaped placeholder) and then kept: switching moves it
// between the two slots and a hidden stash, so nothing is lost and nothing stops.
// When the window is too narrow for two panes (`splitSuspended`), only the focused one shows.
Item {
    id: view

    required property WorkspaceState workspace
    required property AppActions actions
    property bool splitSuspended: false

    readonly property bool splitShown: workspace.split && !splitSuspended
    readonly property string leftPane: workspace.overview ? ""
                                     : workspace.split && !splitShown ? workspace.focused : workspace.selected
    readonly property string rightPane: splitShown ? workspace.beside : ""
    // Pane ids on screen.
    readonly property var visiblePanes: [leftPane, rightPane].filter(id => id.length > 0)
    // Every pane that can be shown: { paneId, instrumentId, panelUrl }.
    readonly property var panes: workspace.paneOrder().map(id => ({
        paneId: id,
        instrumentId: workspace.instrumentOf(id),
        panelUrl: id.indexOf("/") >= 0 ? InstrumentRegistry.viewInfo(id).panelUrl : InstrumentRegistry.info(id).panelUrl
    }))

    // Equal panes (a double-click on the divider).
    function centreDivider() {
        workspace.setRatio(0.5)
    }

    function slotOf(paneId: string): Item {
        return paneId === leftSlot.paneId ? leftSlot : paneId === rightSlot.paneId ? rightSlot : null
    }
    // The pane id an item belongs to ("" outside the panes).
    function paneOf(item: Item): string {
        for (let i = item; i !== null; i = i.parent) {
            if (i === leftSlot)
                return leftSlot.paneId
            if (i === rightSlot)
                return rightSlot.paneId
        }
        return ""
    }

    // Overview is created the first time it is shown, then kept (its tiles stay live).
    Loader {
        id: overview
        objectName: "overviewLoader"
        anchors.fill: parent
        readonly property bool wanted: view.workspace.overview
        visible: wanted
        active: false
        onWantedChanged: {
            if (wanted)
                active = true
        }
        // After the shell applied the startup options (--panel shows no Overview at all).
        Component.onCompleted: Qt.callLater(() => active = active || wanted)
        sourceComponent: OverviewPage {
            workspace: view.workspace
            actions: view.actions
        }
    }

    // Two panes and the divider between them. Not a SplitView: the divider snaps to the middle while
    // it is dragged (SplitView keeps the mouse's width until the release) and a double-click on it
    // centres it (SplitView takes the presses of its handles).
    Item {
        id: split
        objectName: "workspaceSplit"
        anchors.fill: parent
        visible: !view.workspace.overview

        // The room the two panes share: the divider's drag area is not a pane's.
        readonly property real handleWidth: 7
        readonly property real paneRoom: Math.max(1, width - handleWidth)
        readonly property real centreWidth: Math.round(paneRoom / 2)
        // The left pane's width while the divider is dragged (-1: none), else from the ratio. Both
        // panes keep Theme.paneMinWidth.
        property real dragWidth: -1
        readonly property real leftWidth: {
            const wanted = dragWidth >= 0 ? dragWidth : Math.round(paneRoom * view.workspace.ratio)
            return Math.max(Theme.paneMinWidth, Math.min(paneRoom - Theme.paneMinWidth, wanted))
        }
        readonly property bool resizing: divider.pressed
        readonly property bool snapped: resizing && leftWidth === centreWidth

        PaneSlot {
            id: leftSlot
            objectName: "leftPaneSlot"
            paneId: view.leftPane
            width: view.splitShown ? split.leftWidth : split.width
            height: split.height
        }
        // A 1 px hairline in a 7 px drag area. Drag: within Theme.snapDistance of the middle it snaps
        // there (with a notch at both ends); double-click: centred.
        MouseArea {
            id: divider
            objectName: "workspaceDivider"
            visible: view.splitShown
            x: leftSlot.width
            width: split.handleWidth
            height: split.height
            hoverEnabled: true
            preventStealing: true
            cursorShape: Qt.SplitHCursor
            readonly property bool active: pressed || containsMouse
            property real pressX: 0
            property real pressWidth: 0
            onPressed: mouse => {
                pressX = mapToItem(split, mouse.x, 0).x
                pressWidth = split.leftWidth
            }
            onPositionChanged: mouse => {
                if (!pressed)
                    return
                const wanted = pressWidth + mapToItem(split, mouse.x, 0).x - pressX
                split.dragWidth = Theme.snapTo(wanted, [split.centreWidth])
            }
            onReleased: {
                if (split.dragWidth >= 0)
                    view.workspace.setRatio(split.leftWidth / split.paneRoom)
                split.dragWidth = -1
            }
            onCanceled: split.dragWidth = -1
            onDoubleClicked: view.centreDivider()

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: divider.active ? 2 : 1
                height: parent.height
                color: divider.active ? Theme.accent : Theme.separator
            }
            Repeater {
                model: split.snapped ? 2 : 0
                Rectangle {
                    required property int index
                    objectName: "dividerSnapMark"
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: index === 0 ? 0 : divider.height - height
                    width: 6
                    height: 18
                    radius: 3
                    color: Theme.accent
                }
            }
        }
        PaneSlot {
            id: rightSlot
            visible: view.splitShown
            paneId: view.rightPane
            x: divider.x + split.handleWidth
            width: split.width - x
            height: split.height
        }
    }

    Item {
        id: stash
        visible: false
    }

    // Drop target of instrument rows, Overview tiles and pane headers: the left or
    // right third splits (or swaps a dragged pane), the middle replaces the focused pane. The
    // accent preview shows the area the instrument will take.
    DropArea {
        id: drop
        objectName: "workspaceDropArea"
        anchors.fill: parent
        z: 10
        keys: ["mybench/instrument"]
        property string zone: ""
        readonly property DragChip chip: drag.source as DragChip
        readonly property bool fromPane: chip !== null && chip.origin === "pane"

        function zoneAt(x: real): string {
            if (view.workspace.overview && !fromPane)
                return "center"
            if (x < width / 3)
                return "left"
            if (x > width * 2 / 3)
                return "right"
            return fromPane ? "" : "center"
        }
        // A pane header only swaps: its own half (and the middle) drop nothing.
        function acceptsZone(z: string): bool {
            if (!fromPane)
                return z.length > 0
            return view.splitShown && ((z === "left" && chip.paneId === view.rightPane)
                                       || (z === "right" && chip.paneId === view.leftPane))
        }
        onEntered: drag => zone = zoneAt(drag.x)
        onPositionChanged: drag => zone = zoneAt(drag.x)
        onExited: zone = ""
        onDropped: dropEvent => {
            const source = dropEvent.source as DragChip
            const where = zoneAt(dropEvent.x)
            zone = ""
            if (!source || !acceptsZone(where))
                return
            dropEvent.accept()
            view.workspace.dropPane(source.paneId, where, source.origin === "pane")
        }

        Rectangle {
            objectName: "dropPreview"
            visible: drop.containsDrag && drop.acceptsZone(drop.zone)
            // The middle replaces the focused pane: its slot in a split, else everything.
            readonly property bool focusRight: view.splitShown && view.workspace.focused === view.rightPane
            x: drop.zone === "right" ? parent.width / 2
             : drop.zone === "center" && focusRight ? leftSlot.width : 0
            width: drop.zone !== "center" ? parent.width / 2
                 : !view.splitShown ? parent.width
                 : focusRight ? parent.width - leftSlot.width : leftSlot.width
            height: parent.height
            color: Qt.alpha(Theme.accent, 0.14)
            border.width: 2
            border.color: Theme.accent
        }
    }

    // Keyboard focus moving into a pane focuses it.
    Connections {
        target: view.Window.window
        function onActiveFocusItemChanged() {
            const item = view.Window.activeFocusItem
            const id = item ? view.paneOf(item) : ""
            if (id.length > 0)
                view.workspace.focus(id)
        }
    }

    // A pane slot: where the panel of `paneId` is shown.
    component PaneSlot: Item {
        property string paneId
        readonly property alias content: slotContent
        Item {
            id: slotContent
            anchors.fill: parent
        }
    }

    // One host per pane: creates the panel on first show, then moves it between the slots.
    Instantiator {
        model: view.panes
        delegate: Item {
            id: host
            required property var modelData
            readonly property string paneId: modelData.paneId
            readonly property InstrumentController controller: InstrumentRegistry.controller(modelData.instrumentId)
            readonly property bool opened: view.workspace.opened[paneId] === true
            readonly property Item slot: view.leftPane === paneId ? leftSlot : view.rightPane === paneId ? rightSlot : null
            // The pane's InstrumentPanel (it registers itself once its tree is complete).
            readonly property InstrumentPanel panel: PanelRegistry.revision >= 0 && loader.status === Loader.Ready
                                                     ? PanelRegistry.panel(paneId) as InstrumentPanel : null

            parent: slot ? (slot as PaneSlot).content : stash
            anchors.fill: parent

            function load() {
                if (opened && loader.status === Loader.Null && host.modelData.panelUrl.toString().length > 0)
                    loader.setSource(host.modelData.panelUrl, { controller: host.controller })
            }
            onOpenedChanged: load()
            Component.onCompleted: load()

            Loader {
                id: loader
                anchors.fill: parent
                // Compiled and created in slices between frames: showing never blocks the UI.
                asynchronous: true
                // Commands waiting for a panel that cannot load are dropped.
                onStatusChanged: {
                    if (status === Loader.Error)
                        PanelRegistry.cancel(host.paneId)
                }
            }
            // The shell's state of the pane: focused (accent line under the header), closable in a
            // split (× = close that pane; the instrument keeps running), the "split hidden" note.
            Binding {
                target: host.panel
                when: host.panel !== null
                property: "focused"
                // Only a split marks the focused pane (one pane is always the focused one).
                value: view.splitShown && host.paneId === view.workspace.focused
            }
            Binding {
                target: host.panel
                when: host.panel !== null
                property: "closable"
                value: view.splitShown && host.slot !== null
            }
            Binding {
                target: host.panel
                when: host.panel !== null
                property: "draggable"
                value: host.slot !== null
            }
            Binding {
                target: host.panel
                when: host.panel !== null
                property: "note"
                value: view.workspace.split && !view.splitShown && host.slot !== null
                       ? qsTr("Split hidden") : ""
            }
            Connections {
                target: host.panel
                function onCloseRequested() {
                    view.workspace.closePane(host.paneId)
                }
            }
            // Drag image of the pane header's title (drop: swap the panes, or close on the sidebar).
            DragChip {
                objectName: "paneDragChip"
                handler: host.panel ? host.panel.paneHeader.titleDrag : null
                source: host
                paneId: host.paneId
                title: host.panel ? host.panel.paneHeader.title : ""
                iconName: host.panel ? host.panel.paneHeader.iconName : ""
                origin: "pane"
            }
            // Pane-shaped placeholder while the panel is created.
            PanePlaceholder {
                anchors.fill: parent
                visible: loader.status === Loader.Loading
            }
            EmptyState {
                anchors.centerIn: parent
                visible: loader.status === Loader.Error
                iconName: "error"
                title: qsTr("Panel failed to load")
                text: host.modelData.panelUrl.toString()
            }
            // A click anywhere in the pane focuses it.
            PointHandler {
                onActiveChanged: {
                    if (active)
                        view.workspace.focus(host.paneId)
                }
            }
        }
    }

    // Header band and display surface, the shape of a pane.
    component PanePlaceholder: Rectangle {
        color: Theme.display
        Rectangle {
            width: parent.width
            height: Theme.paneHeaderHeight
            color: Theme.window
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: Theme.borderWidth
                color: Theme.separator
            }
        }
    }
}
