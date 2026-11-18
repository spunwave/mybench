pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import MyBench.Controls

// The measurement strip under the display: one card per cursor pair while cursors are on, then the
// measurements grouped by trace (value plus min / max / mean / σ statistics), and an Add card.
// Same model API as a MeasurementTable (see ScopeMeasurements).
MeasurementStrip {
    id: strip

    required property ScopeController controller
    property var columns: []            // [{ title, color }] = shown traces
    property var traces: []             // [{ index: 0 | 1 | 2, title, color }]
    property var rows: []               // [{ id, title, values: [text per column] }]
    property int statistics: 1          // 0 off, 1 last 100 records, 2 all records
    property int sourceFilter: -1       // -1 all traces, else 0 / 1 / 2
    property var catalog: []            // ScopeChannel.measurementCatalog()

    signal openMeasurePanel()

    shownIds: rows.map(r => r.id)
    moreEntry: true
    onMoreRequested: openMeasurePanel()

    readonly property var measurementRows: rows.filter(r => r.id.startsWith("m"))
    function traceName(index: int): string {
        return index === 2 ? qsTr("Math") : "CH" + index
    }
    // The order the measurements were added in (the controller keeps a mask, not an order).
    property var addOrder: []
    onMeasurementRowsChanged: {
        const ids = measurementRows.map(r => r.id)
        const order = addOrder.filter(id => ids.includes(id))
        for (const id of ids)
            if (!order.includes(id))
                order.push(id)
        if (order.join() !== addOrder.join())
            addOrder = order
    }
    // Card keys "<rowId>/<traceIndex>", by trace, then in the order added; the cards live in a
    // model that is edited in place, so a card keeps its statistics when another one is added.
    readonly property string cardKeys: {
        const ids = measurementRows.map(r => r.id)
        const ordered = addOrder.filter(id => ids.includes(id)).concat(ids.filter(id => !addOrder.includes(id)))
        const keys = []
        for (const t of traces)
            for (const id of ordered)
                if ((sourceFilter < 0 || t.index === sourceFilter)
                        && (t.index !== 2 || id === "m" + ScopeChannel.Rms || id === "m" + ScopeChannel.PeakToPeak))
                    keys.push(id + "/" + t.index)
        return keys.join("|")
    }
    onCardKeysChanged: syncKeys()
    Component.onCompleted: syncKeys()
    function syncKeys() {
        const want = cardKeys.length > 0 ? cardKeys.split("|") : []
        for (let i = 0; i < want.length; ++i) {
            if (i < keyModel.count && keyModel.get(i).key === want[i])
                continue
            let from = -1
            for (let k = i + 1; k < keyModel.count && from < 0; ++k)
                if (keyModel.get(k).key === want[i])
                    from = k
            if (from >= 0)
                keyModel.move(from, i, 1)
            else
                keyModel.insert(i, { key: want[i] })
        }
        while (keyModel.count > want.length)
            keyModel.remove(keyModel.count - 1)
    }
    ListModel { id: keyModel }

    function catalogEntry(flag: int): var {
        return catalog.find(e => e.flag === flag) ?? { label: "", unit: "V" }
    }

    // Time cursors C1–C2: Δt large; 1/Δt, ΔV, and the values at C1 and C2 on their traces.
    ScopeCursorCard {
        objectName: "cursorCard"
        visible: strip.controller.cursorsOn
        readonly property var c1: strip.controller.cursor1
        readonly property var c2: strip.controller.cursor2
        // Re-read with every record (the rows follow the records). First in the strip:
        // what the user is pointing at right now.
        readonly property var readings: {
            void strip.rows
            const v1 = strip.controller.valueAt(c1.channel, c1.position)
            const v2 = strip.controller.valueAt(c2.channel, c2.position)
            return { v1: v1, v2: v2, dt: c2.position - c1.position }
        }
        function unitOf(index: int): string {
            return index === 2 ? strip.controller.math.unit : "V"
        }
        function fmt(v: real, unit: string): string {
            return isFinite(v) ? strip.controller.formatMeasurement(v, unit) : ""
        }
        title: c1.channel === c2.channel ? qsTr("on %1").arg(strip.traceName(c1.channel)) : ""
        value: fmt(readings.dt, "s")
        items: [{ name: "1/Δt", text: Math.abs(readings.dt) > 0 ? fmt(1 / Math.abs(readings.dt), "Hz") : "" },
                { name: "ΔV", text: unitOf(c1.channel) === unitOf(c2.channel) ? fmt(readings.v2 - readings.v1, unitOf(c1.channel)) : "" },
                { name: "C1", color: Theme.cursor1, text: fmt(readings.v1, unitOf(c1.channel)) },
                { name: "C2", color: Theme.cursor2, text: fmt(readings.v2, unitOf(c2.channel)) }]
    }
    // Level cursors H1–H2 on one trace: ΔV large, the two levels beside it.
    ScopeCursorCard {
        objectName: "levelCursorCard"
        visible: strip.controller.levelCursorsOn
        readonly property string unit: strip.controller.levelCursorChannel === 2 ? strip.controller.math.unit : "V"
        names: ["H1", "H2"]
        title: qsTr("on %1").arg(strip.traceName(strip.controller.levelCursorChannel))
        value: strip.controller.formatMeasurement(strip.controller.levelCursor2 - strip.controller.levelCursor1, unit)
        items: [{ name: "H1", color: Theme.cursor1, text: strip.controller.formatMeasurement(strip.controller.levelCursor1, unit) },
                { name: "H2", color: Theme.cursor2, text: strip.controller.formatMeasurement(strip.controller.levelCursor2, unit) }]
    }

    Repeater {
        model: keyModel
        delegate: MeasurementCard {
            id: card
            required property string key
            readonly property var parts: key.split("/")
            readonly property string rowId: parts[0]
            readonly property int flag: Number(rowId.slice(1))
            readonly property int traceIndex: Number(parts[1])
            readonly property int column: strip.traces.findIndex(t => t.index === traceIndex)
            readonly property var row: strip.rows.find(r => r.id === rowId) ?? null
            readonly property var trace: strip.traces[column] ?? { title: "", color: Theme.text }
            readonly property var entry: strip.catalogEntry(flag)
            readonly property string measureUnit: traceIndex === 2 ? strip.controller.math.unit : entry.unit
            property var samples: []
            property real last: NaN
            property real total: 0
            property real total2: 0
            property real minimum: NaN
            property real maximum: NaN
            property int count: 0
            readonly property real mean: count > 0 ? total / count : NaN
            readonly property real sigma: count > 1 ? Math.sqrt(Math.max(0, total2 / count - mean * mean)) : NaN

            function push(v: real) {
                if (!isFinite(v))
                    return
                last = v
                if (strip.statistics === 0)
                    return
                if (strip.statistics === 1) {
                    const s = samples.concat([v]).slice(-100)
                    samples = s
                    count = s.length
                    total = s.reduce((a, b) => a + b, 0)
                    total2 = s.reduce((a, b) => a + b * b, 0)
                    minimum = Math.min(...s)
                    maximum = Math.max(...s)
                } else {
                    count += 1
                    total += v
                    total2 += v * v
                    minimum = isNaN(minimum) ? v : Math.min(minimum, v)
                    maximum = isNaN(maximum) ? v : Math.max(maximum, v)
                }
            }
            function reset() {
                samples = []; total = 0; total2 = 0; minimum = NaN; maximum = NaN; count = 0
            }
            // Statistics as numbers: the card formats them (4 significant digits, σ 3); the
            // value keeps the controller's measurement format. "—" until there is one.
            function num(v: real): var {
                return isFinite(v) ? v : "—"
            }

            Connections {
                target: strip
                function onStatisticsChanged() { card.reset() }
            }
            Connections {
                target: card.traceIndex === 2 ? strip.controller.math
                                              : (card.traceIndex === 0 ? strip.controller.channel0 : strip.controller.channel1)
                function onResultsChanged() {
                    if (card.traceIndex === 2)
                        card.push(card.flag === ScopeChannel.Rms ? strip.controller.math.rms
                                  : card.flag === ScopeChannel.PeakToPeak ? strip.controller.math.peakToPeak : NaN)
                    else
                        card.push((card.traceIndex === 0 ? strip.controller.channel0 : strip.controller.channel1).measurement(card.flag))
                }
            }

            title: card.trace.title + " · " + (card.row ? card.row.title : "")
            color: card.trace.color
            value: card.row ? (card.row.values[card.column] || "—") : "—"
            unit: card.measureUnit
            exactValue: card.last
            stats: strip.statistics === 0 ? ({}) : ({ min: num(minimum), max: num(maximum), mean: num(mean), stdDev: num(sigma) })
            onRemoveRequested: strip.removeRequested(card.rowId)
            onResetStatisticsRequested: card.reset()
        }
    }
}
