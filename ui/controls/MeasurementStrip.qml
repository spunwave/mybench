pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// The measurement strip under an instrument's display: a wrapping grid of equal-width
// MeasurementCards with hairlines between them and a 32 px rail at the right for the actions (Add, and
// any MeasurementAction declared inside). It picks the wide, tall or compact card form that shows the
// most cards inside `maximumHeight`, and scrolls vertically only when no form shows them all.
// Declare cursor cards first, then the cards by channel.
//     MeasurementStrip {
//         available: [{ id: "rms", title: qsTr("RMS") }]; shownIds: ["rms"]
//         maximumHeight: 168
//         onAddRequested: id => ctl.add(id)
//         onRemoveRequested: id => ctl.remove(id)
//         MeasurementCard { title: "CH0 · RMS"; value: "1.0 V" }
//     }
Item {
    id: strip

    default property alias cards: grid.data
    property var available: []                // [{ id, title }]: the Add menu (checked = shown)
    property var shownIds: []
    property bool moreEntry: false            // a last menu entry that emits moreRequested()
    property string summaryText               // one line for short windows (InstrumentPanel)
    property real maximumHeight: 2 * Theme.measurementCardTallHeight   // the host's budget: two tall rows
    // The most the host can spare when a second row (at most `extendedRows` rows) makes every card visible;
    // 0 or under maximumHeight: no such allowance.
    property real extendedHeight: 0
    property int extendedRows: 2

    signal addRequested(string id)
    signal removeRequested(string id)
    signal moreRequested()

    readonly property bool addVisible: available.length > 0 || moreEntry
    readonly property bool railVisible: addVisible || railActions().length > 0

    // A cell is any child that states its `tallMinimumWidth` (cards; not `minimumWidth`, which follows the form the strip sets).
    function cells(): var {
        const list = []
        for (const c of grid.children)
            if (c.tallMinimumWidth !== undefined && c.visible)
                list.push(c)
        return list
    }
    function railActions(): var {
        return rail.children.filter(c => c.isAction === true && c !== addButton && c.visible)
    }

    readonly property real railWidth: railVisible ? Theme.measurementRailWidth : 0
    readonly property real gridWidth: Math.max(0, width - railWidth)
    readonly property var cellList: cells()
    readonly property int cellCount: cellList.length
    readonly property bool anyFigures: cellList.some(c => c.hasFigures === true)

    // One arrangement: the form ("wide", "tall" or "compact"), the columns and how much of it shows inside the budget.
    function arrangement(form: string, budget: real, rowLimit: int): var {
        const tallForm = form === "tall"
        let minimum = Theme.measurementCardCompactMinWidth   // the cards' own minimums carry their form's floor
        for (const c of cellList)
            minimum = Math.max(minimum, tallForm ? (c.tallMinimumWidth ?? c.minimumWidth)
                                      : form === "compact" ? (c.compactMinimumWidth ?? c.minimumWidth)
                                      : (c.wideMinimumWidth ?? c.minimumWidth))
        const cellHeight = tallForm ? Theme.measurementCardTallHeight : Theme.measurementCardHeight
        let columns = Math.max(1, Math.floor(gridWidth / minimum))
        const rows = Math.ceil(cellCount / columns)
        const fitting = Math.max(tallForm ? 0 : 1, Math.min(rowLimit, Math.floor(budget / cellHeight)))
        const shownRows = Math.min(rows, fitting)
        if (rows > 1 && rows <= fitting)
            columns = Math.ceil(cellCount / rows)
        return { form: form, tall: tallForm, compact: form === "compact", minimum: minimum, columns: columns, rows: rows,
                 cellHeight: cellHeight, shownRows: shownRows, budget: budget,
                 shown: Math.min(cellCount, columns * shownRows), height: shownRows * cellHeight }
    }
    // The wide or the tall form (the one showing more, on a tie the lower strip, then the wide);
    // the compact form only when it shows more cards than either (seeing every value beats one value
    // with its statistics).
    readonly property var chosen: {
        const base = chooseWithin(maximumHeight, 1000)
        if (base.shown >= cellCount || extendedHeight <= maximumHeight)
            return base
        // A second row (never more than extendedRows) when it makes every card visible.
        const extended = chooseWithin(extendedHeight, extendedRows)
        return extended.shown >= cellCount ? extended : base
    }
    function chooseWithin(budget: real, rowLimit: int): var {
        const wide = arrangement("wide", budget, rowLimit)
        if (!anyFigures)
            return wide
        const tallArrangement = arrangement("tall", budget, rowLimit)
        let best = wide
        if (tallArrangement.shown !== wide.shown)
            best = tallArrangement.shown > wide.shown ? tallArrangement : wide
        else if (tallArrangement.height < wide.height)
            best = tallArrangement
        const compactArrangement = arrangement("compact", budget, rowLimit)
        return compactArrangement.shown > best.shown ? compactArrangement : best
    }
    readonly property bool compact: chosen.compact
    readonly property bool tall: chosen.tall
    readonly property int gridColumns: chosen.columns
    readonly property int gridRows: chosen.rows
    readonly property int visibleRows: chosen.shownRows
    readonly property bool scrolls: chosen.rows > chosen.shownRows
    readonly property int cellMinimum: chosen.minimum
    readonly property int cellHeight: chosen.cellHeight
    readonly property int wideCellHeight: Theme.measurementCardHeight
    readonly property int tallCellHeight: Theme.measurementCardTallHeight

    implicitHeight: Math.min(chosen.budget, Math.max(cellCount > 0 ? chosen.height : 0, railVisible ? Math.max(rail.implicitHeight, cellCount > 0 ? 0 : Theme.measurementCardHeight) : 0))
    clip: true

    Rectangle {
        anchors.fill: parent
        color: Theme.window
    }

    // The form of every card. Guarded: applied at most once per change of the choice, never re-entered
    // by the property changes it causes.
    property bool applying: false
    function applyForm() {
        if (applying)
            return
        applying = true
        for (const c of grid.children)
            if (c.tall !== undefined && c.tall !== strip.tall)
                c.tall = strip.tall
        for (const c of grid.children)
            if (c.compact !== undefined && c.compact !== strip.compact)
                c.compact = strip.compact
        applying = false
    }
    onTallChanged: applyForm()
    onCompactChanged: applyForm()
    onCellListChanged: applyForm()

    Flickable {
        id: flick
        objectName: "stripFlick"
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: strip.gridWidth
        contentWidth: width
        contentHeight: grid.implicitHeight
        flickableDirection: Flickable.VerticalFlick
        boundsBehavior: Flickable.StopAtBounds
        interactive: strip.scrolls
        clip: true

        GridLayout {
            id: grid
            width: flick.width
            columns: strip.gridColumns
            columnSpacing: 0
            rowSpacing: 0
            uniformCellWidths: true
            onChildrenChanged: Qt.callLater(strip.settle)
        }
    }

    ScrollArrows {
        objectName: "stripArrows"
        flickable: flick
        stacked: true
        visible: strip.scrolls
        anchors { right: parent.right; top: rail.bottom; bottom: parent.bottom }
        width: Theme.measurementRailWidth
        arrowSize: Math.min(Theme.controlHeightS, Math.floor(height / 2))
        step: strip.cellHeight
    }

    Column {
        id: rail
        objectName: "stripRail"
        visible: strip.railVisible
        anchors { right: parent.right; top: parent.top }
        width: Theme.measurementRailWidth
        MeasurementAction {
            id: addButton
            objectName: "addMeasurement"
            visible: strip.addVisible
            width: parent.width
            iconName: "plus"
            toolTip: qsTr("Add")
            color: Theme.textSecondary
            onClicked: addMenu.popup(addButton, 0, addButton.height)
        }
    }

    Component.onCompleted: settle()
    // Actions declared in the strip go to the rail; the form follows the cards.
    function settle() {
        for (const c of Array.from(grid.children))
            if (c.isAction === true) {
                c.parent = rail
                c.x = 0
            }
        applyForm()
    }

    Menu {
        id: addMenu
        objectName: "addMenu"
        Instantiator {
            model: strip.available
            delegate: MenuItem {
                required property var modelData
                text: modelData.title
                checkable: true
                checked: strip.shownIds.includes(modelData.id)
                onTriggered: {
                    if (strip.shownIds.includes(modelData.id))
                        strip.removeRequested(modelData.id)
                    else
                        strip.addRequested(modelData.id)
                    checked = Qt.binding(() => strip.shownIds.includes(modelData.id))
                }
            }
            onObjectAdded: (index, object) => addMenu.insertItem(index, object as MenuItem)
            onObjectRemoved: (index, object) => addMenu.removeItem(object as MenuItem)
        }
        MenuSeparator { visible: strip.moreEntry && strip.available.length > 0 }
        MenuItem {
            visible: strip.moreEntry
            height: visible ? implicitHeight : 0
            text: qsTr("Measure…")
            onTriggered: strip.moreRequested()
        }
    }
}
