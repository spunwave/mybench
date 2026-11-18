import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The control surface next to an instrument's display, in two forms: a column at the right
// (Theme.instrumentColumnWidth wide) or a band (dock) under the display. InstrumentPanel builds one
// (`managed: true`) from its `controls` / `tools` slots and places it; instruments do not declare it.
// Vertical: the sections scroll above the pinned tool palette (`tools`). Horizontal: the sections
// flow into equal columns, at most `maximumBandHeight` tall, and the palette is an icon strip.
Rectangle {
    id: column

    property bool compact: false
    // Built by InstrumentPanel: the dock has a fixed height (`bandHeight`), the palette strip is
    // narrower, the palette fills the column with four cells.
    property bool managed: false
    property real bandHeight: 0
    // Cards and other sections declared inside (not counting the helpers that create them).
    property int contentCount: 0
    property bool moving: false
    function recount() {
        if (!moving)
            contentCount = cardsLayout.children.length + bandItem.children.length
    }
    readonly property real toolsSlotWidth: toolsSlot.width
    property real spacing: Theme.spacingS      // between the items of a column without sections
    property int orientation: Qt.Vertical
    // Horizontal form: the tallest the band grows to.
    property real maximumBandHeight: 320
    default property alias cards: cardsLayout.data
    // The pinned tool palette (one item; it is given the column's inner width).
    property Item tools: null
    readonly property alias flickable: flick
    readonly property bool horizontal: orientation === Qt.Horizontal
    readonly property bool scrolls: horizontal ? bandFlick.contentHeight > bandFlick.height + 0.5
                                               : flick.contentHeight > flick.height + 0.5
    // True when the column holds sections (ChannelCard), which carry their own padding and
    // hairlines; otherwise the items get an 8 px inset and 8 px gaps.
    property bool flush: managed
    // Marks the host that sections (ChannelCard) look for.
    readonly property bool isInstrumentColumn: true
    // Height of the tallest section (band), and the height the band's sections are given.
    property real minimumBandColumnWidth: 180
    property int bandColumns: 1
    property real bandColumnWidth: 0
    property real contentTall: 0
    // The widest a lone column of sections gets (the rest of the band stays empty).
    property real maximumBandColumnWidth: 260
    // The tool strip wraps into columns instead of making the band taller: the band holds at
    // least this many tools in a column.
    property int minimumBandToolRows: 3
    readonly property real bandInnerHeight: bandHeight > 0 ? bandHeight - 1
        : Math.min(maximumBandHeight,
        Math.max(contentTall, column.tools
                 ? minimumBandToolRows * (Theme.controlHeight + 4) + (minimumBandToolRows - 1) * 2 + 2 * Theme.spacingS : 0))
    // The padding around the palette: a managed dock has an icon strip of Theme.dockToolStripWidth.
    readonly property real toolsPadding: managed ? 2 : Theme.spacingS
    property bool laying: false
    // The width of a band column that holds only header-only cards (a title, a source and a switch).
    property real headerColumnWidth: 240
    // The band's plan (see layoutBand) and what it was made for.
    property var planGroups: []
    property var planItems: []
    property var planHeaderOnly: []
    property int planWidth: -1
    property int planFit: 0
    property bool replanWanted: false
    // Plans the columns again (the pane changed size or form).
    function refit() {
        replanWanted = true
        layoutBand()
    }
    // For a moment after a new plan the cards' heights settle (layouts update a frame later): the
    // plan follows them, then it is kept.
    Timer {
        id: planSettle
        interval: 300
        onTriggered: column.layoutBand()
    }
    // Folding (managed only): the most a band column of cards may take (`bandFoldHeight`, from the
    // panel's dock budget; 0: no folding). A column taller than its room folds cards to their headers
    // from the bottom; the card the user opened last (`openCard`) stays open.
    property real bandFoldHeight: 0
    property bool anyFolded: false     // the band folded a card (the dock then takes its whole cap)
    property Item openCard: null
    function unfold(card: Item) {
        openCard = card
        layoutBand()
        foldColumn()
    }
    // Folds `cards` (top to bottom) so their heights fit `room`; returns the height they take.
    function foldToFit(cards: var, room: real): real {
        let total = 0
        for (const c of cards)
            total += Math.ceil(c.openHeight ?? c.implicitHeight)
        const fold = new Set()
        let open = cards.filter(c => c.foldable === true).length
        const canFold = c => c !== openCard && c.folded !== undefined && c.foldable === true && !fold.has(c) && open > 1
        if (room > 0) {
            for (let i = cards.length - 1; i >= 0 && total > room; --i) {
                const c = cards[i]
                if (!canFold(c))
                    continue
                const saved = Math.ceil(c.openHeight) - Math.ceil(c.foldedHeight)
                if (saved < 1)
                    continue
                fold.add(c)
                --open
                total -= saved
            }
            for (let i = 0; i < cards.length && total > room; ++i) {
                const c = cards[i]
                if (!canFold(c))
                    continue
                fold.add(c)
                --open
                total -= Math.ceil(c.openHeight) - Math.ceil(c.foldedHeight)
            }
        }
        for (const c of cards)
            if (c.folded !== undefined && c.folded !== fold.has(c))
                c.folded = fold.has(c)
        return total
    }
    // The side column: the cards fold to fit its height.
    function foldColumn() {
        if (horizontal || !managed || laying)
            return
        laying = true
        const items = []
        for (const c of cardsLayout.children)
            if (c.visible)
                items.push(c)
        foldToFit(items, flick.height - (Theme.cardMargin / 2 + Theme.cardMargin))
        laying = false
    }

    // Flows the declared items top to bottom into the band's columns, balanced by height.
    function layoutBand() {
        if (!horizontal || laying)
            return
        laying = true
        const items = []
        for (let i = 0; i < bandItem.children.length; ++i) {
            const c = bandItem.children[i]
            if (c.visible && c.implicitHeight > 0)
                items.push(c)
        }
        const width = bandFlick.width
        const fit = managed ? (width >= 3 * Theme.denseCardMinWidth ? 3 : column.width >= Theme.dockTwoColumnsAt ? 2 : 1)
                            : Math.max(1, Math.floor(width / minimumBandColumnWidth))
        const n = Math.max(1, Math.min(fit, items.length))
        // Balanced on the open heights (folding never moves a card to another column).
        const heights = items.map(c => Math.ceil(c.openHeight ?? c.implicitHeight))
        const columnsFor = h => {
            let count = 1, used = 0
            for (const x of heights) {
                if (used > 0 && used + x > h) {
                    ++count
                    used = 0
                }
                used += x
            }
            return count
        }
        let lo = heights.reduce((m, x) => Math.max(m, x), 0)
        let hi = heights.reduce((t, x) => t + x, 0)
        while (lo < hi) {
            const mid = Math.floor((lo + hi) / 2)
            if (columnsFor(mid) <= n)
                hi = mid
            else
                lo = mid + 1
        }
        let tall = 0
        const headerOnly = items.map(c => c.expanded === false || c.hasBody === false)
        // The plan (which card in which column) is kept while only heights change, so a growing card
        // keeps its column and the control under the pointer stays put.
        const samePlan = !replanWanted && !planSettle.running && planGroups.length > 0 && planWidth === Math.round(width) && planFit === n
            && planItems.length === items.length && planItems.every((c, i) => c === items[i] && planHeaderOnly[i] === headerOnly[i])
        let groups
        if (samePlan) {
            groups = planGroups.map(g => g.slice())
        } else {
            groups = []
            let col = 0, used = 0
            for (let i = 0; i < items.length; ++i) {
                if (used > 0 && used + heights[i] > lo) {
                    ++col
                    used = 0
                }
                if (!groups[col])
                    groups[col] = []
                groups[col].push(items[i])
                used += heights[i]
            }
            // A column of header-only cards (channels switched off) joins its neighbour when the
            // dock already has the room (its present height), so its space goes to the other cards;
            // otherwise it stays, narrow (below).
            const room = managed && bandHeight > 0 ? bandHeight - Theme.cardMargin - 1 : 0
            const sum = g => g.reduce((t, c) => t + heights[items.indexOf(c)], 0)
            for (let k = 0; k < groups.length && groups.length > 1; ) {
                const lonely = groups[k].every(c => headerOnly[items.indexOf(c)])
                const target = k > 0 ? k - 1 : k + 1
                if (lonely && room > 0 && sum(groups[k]) + sum(groups[target]) <= room) {
                    groups[target] = target < k ? groups[target].concat(groups[k]) : groups[k].concat(groups[target])
                    groups.splice(k, 1)
                    continue
                }
                ++k
            }
            planGroups = groups.map(g => g.slice())
            planItems = items.slice()
            planHeaderOnly = headerOnly
            planWidth = Math.round(width)
            planFit = n
            if (replanWanted || !planSettle.running)
                planSettle.restart()
            replanWanted = false
        }
        const usedColumns = groups.length
        const colWidth = usedColumns === 1 ? Math.min(width, maximumBandColumnWidth) : width / usedColumns
        // A column left with header-only cards only is narrow (a header's width); the other columns
        // share the rest, so the cards still open get the room.
        const narrow = Math.min(colWidth, headerColumnWidth)
        const lonelyColumn = groups.map(g => usedColumns > 1 && g.every(c => headerOnly[items.indexOf(c)]))
        const lonelyCount = lonelyColumn.filter(x => x).length
        const wideWidth = lonelyCount > 0 && lonelyCount < usedColumns
            ? (width - lonelyCount * narrow) / (usedColumns - lonelyCount) : colWidth
        const columnWidth = k => lonelyCount > 0 && lonelyCount < usedColumns ? (lonelyColumn[k] ? narrow : wideWidth) : colWidth
        let left = 0
        for (let k = 0; k < groups.length; ++k) {
            foldToFit(groups[k], managed ? bandFoldHeight : 0)
            const x0 = Math.round(left)
            left += columnWidth(k)
            const x1 = Math.round(left)
            let y = 0
            for (const c of groups[k]) {
                const h = Math.ceil(c.folded === true && c.foldable === true ? c.foldedHeight : (c.openHeight ?? c.implicitHeight))
                c.x = x0
                c.y = y
                c.width = x1 - x0
                c.height = h
                y += h
            }
            tall = Math.max(tall, y)
        }
        let folded = false
        for (const c of items)
            if (c.folded === true && c.foldable === true)
                folded = true
        anyFolded = folded
        bandColumns = usedColumns
        bandColumnWidth = colWidth
        contentTall = tall
        laying = false
    }
    // Re-flows the band (called by the sections when their height or visibility changes). Deferred:
    // the layout changes the cards' heights, and doing it inside their implicitHeight notification looped.
    function measure() {
        Qt.callLater(layoutBand)
        if (!horizontal)
            Qt.callLater(foldColumn)
    }
    // Moves the declared items between the column's layout and the band.
    function place() {
        const from = horizontal ? cardsLayout : bandItem
        const to = horizontal ? bandItem : cardsLayout
        const items = Array.from(from.children)
        moving = true
        for (const item of items)
            item.parent = to
        moving = false
        recount()
        layoutBand()
    }
    onHorizontalChanged: {
        place()
        Qt.callLater(foldColumn)
    }
    onBandFoldHeightChanged: Qt.callLater(layoutBand)
    Component.onCompleted: {
        for (let i = 0; i < cardsLayout.children.length; ++i) {
            if (cardsLayout.children[i].separatorSide !== undefined)
                flush = true
        }
        if (horizontal)
            place()
    }

    implicitWidth: compact ? Theme.instrumentColumnCompactWidth : Theme.instrumentColumnWidth
    implicitHeight: horizontal ? bandInnerHeight + 1 : 0
    // Hairline on the display's side (left of the column, above the dock): drawn over the edge, it
    // takes no room, so the cards keep the whole width.
    color: Theme.window

    Binding {
        target: column
        property: "width"
        value: column.implicitWidth
        when: !column.horizontal
    }
    Binding {
        target: column
        property: "height"
        value: column.implicitHeight
        when: column.horizontal
    }

    Binding {
        target: column.tools
        property: "verticalLimit"
        value: column.bandInnerHeight - 2 * column.toolsPadding
        when: column.tools !== null && column.horizontal
    }
    onToolsChanged: {
        if (tools) {
            tools.parent = toolsSlot
            tools.x = Theme.spacingS
            tools.width = Qt.binding(() => column.horizontal ? tools.implicitWidth
                                                              : toolsSlot.width - 2 * Theme.spacingS)
            tools.z = 0
        }
    }
    Binding {
        target: column.tools
        property: "vertical"
        value: column.horizontal
        when: column.tools !== null
    }

    Binding {
        target: column.tools
        property: "columns"
        value: 4
        when: column.tools !== null && column.managed && !column.horizontal
    }
    Binding {
        target: column.tools
        property: "verticalCell"
        value: Theme.dockToolStripWidth - 2 * column.toolsPadding
        when: column.tools !== null && column.managed
    }
    Binding {
        target: column.tools
        property: "cellHeight"
        value: Theme.toolCellHeight
        when: column.tools !== null && column.managed
    }

    Rectangle {
        z: 2
        width: column.horizontal ? parent.width : 1
        height: column.horizontal ? 1 : parent.height
        color: Theme.separator
    }

    // --- Vertical: the sections scroll above the pinned palette. -------------------------------
    Flickable {
        id: flick
        objectName: "instrumentColumnCards"
        visible: !column.horizontal
        onHeightChanged: Qt.callLater(column.foldColumn)
        anchors { left: parent.left; leftMargin: column.managed ? 0 : 1; right: parent.right; top: parent.top; bottom: toolsSlot.top }
        contentWidth: width
        contentHeight: cardsLayout.implicitHeight + (column.managed ? Theme.cardMargin / 2 + Theme.cardMargin : column.flush ? 0 : 2 * Theme.spacingS)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: cardsLayout
            x: column.flush ? 0 : Theme.spacingS
            y: column.managed ? Theme.cardMargin / 2 : column.flush ? 0 : Theme.spacingS
            width: flick.width - (column.flush ? 0 : 2 * Theme.spacingS)
            spacing: column.flush ? 0 : column.spacing
            onChildrenChanged: column.recount()
        }
    }

    component ScrollFade: Rectangle {
        required property Flickable area
        property bool atTop: false
        readonly property bool wanted: area.visible && (atTop ? area.contentY > 1
                                                              : area.contentY + area.height < area.contentHeight - 1)
        visible: opacity > 0
        opacity: wanted ? 1 : 0
        z: 3
        anchors { left: area.left; right: area.right }
        y: atTop ? area.y : area.y + area.height - height
        height: 16
        gradient: Gradient {
            GradientStop { position: 0; color: atTop ? column.color : Theme.alpha(column.color, 0) }
            GradientStop { position: 1; color: atTop ? Theme.alpha(column.color, 0) : column.color }
        }
        Behavior on opacity { NumberAnimation { duration: Theme.durationNormal } }
    }
    ScrollFade { area: column.horizontal ? bandFlick : flick; atTop: true; objectName: "fadeTop" }
    ScrollFade { area: column.horizontal ? bandFlick : flick; objectName: "fadeBottom" }
    // Little arrows instead of a scroll bar (the cards fold first; this is the last resort).
    ScrollArrows {
        objectName: "columnArrows"
        flickable: column.horizontal ? bandFlick : flick
        x: flickable.x
        y: flickable.y
        width: flickable.width
        height: flickable.height
    }

    // --- Horizontal: the sections in equal columns; taller than the cap, the band scrolls up and down. ---
    Flickable {
        id: bandFlick
        objectName: "instrumentBandSections"
        visible: column.horizontal
        anchors { left: parent.left; right: toolsSlot.left; top: parent.top; topMargin: column.managed ? 0 : 1; bottom: parent.bottom }
        contentWidth: width
        contentHeight: column.contentTall + (column.managed ? Theme.cardMargin : 0)
        flickableDirection: Flickable.VerticalFlick
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        onWidthChanged: column.layoutBand()

        Item {
            id: bandItem
            width: bandFlick.width
            height: Math.max(column.contentTall, bandFlick.height)
            onChildrenChanged: column.recount()
        }
        Repeater {
            model: column.horizontal && !column.managed ? column.bandColumns - 1 : 0
            Rectangle {
                required property int index
                x: Math.round((index + 1) * column.bandColumnWidth)
                width: 1
                height: bandItem.height
                color: Theme.separator
            }
        }
    }

    // The palette inherits the slot's visibility: do not bind the slot's `visible` to its own height,
    // that loop kept a palette assigned before the column was shown hidden for good.
    Item {
        id: toolsSlot
        objectName: "instrumentColumnTools"
        anchors {
            left: column.horizontal ? undefined : parent.left
            leftMargin: column.managed ? 0 : 1
            right: parent.right
            top: column.horizontal ? parent.top : undefined
            topMargin: column.horizontal && !column.managed ? 1 : 0
            bottom: parent.bottom
        }
        Binding {
            target: toolsSlot
            property: "width"
            value: column.tools && column.tools.visible ? column.tools.implicitWidth + 2 * column.toolsPadding + (column.managed ? 0 : 1) : 0
            when: column.horizontal
        }
        Binding {
            target: toolsSlot
            property: "height"
            value: column.tools && column.tools.visible ? column.tools.implicitHeight + 2 * Theme.spacingXs + 1 : 0
            when: !column.horizontal
        }
        Rectangle {
            visible: column.tools !== null && (column.horizontal || column.scrolls)
            width: column.horizontal ? 1 : parent.width
            height: column.horizontal ? parent.height : 1
            color: Theme.separator
        }
        Binding {
            target: column.tools
            property: "y"
            value: column.horizontal ? column.toolsPadding : Theme.spacingXs + 1
            when: column.tools !== null
        }
        Binding {
            target: column.tools
            property: "x"
            value: column.horizontal ? (column.managed ? column.toolsPadding : 1 + Theme.spacingS) : Theme.spacingS
            when: column.tools !== null
        }
    }
}
