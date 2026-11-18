pragma ComponentBehavior: Bound
import QtQuick
import MyBench.Controls

// The cursor cards of the Spectrum Analyzer's measurement strip: C1 and C2 (x as the value, the
// level or voltage beside it), then the differences while both cursors sit on the same plot. A
// Repeater: its cards are cells of the strip. The strings are the controller's "x, y" and
// "Δx … · Δy … · 1/Δx …".
//     DsaCursorCard { c1: ctl.cursor1Text; c2: ctl.cursor2Text; delta: ctl.cursorDeltaText }
Repeater {
    id: root

    property string c1
    property string c2
    property string delta
    property bool shown: true       // false: no cards (a Repeater's visibility does not reach its cards)

    // "x, y" -> [x, y]
    function split(text: string): var {
        const i = text.lastIndexOf(", ")
        return i < 0 ? [text, ""] : [text.slice(0, i), text.slice(i + 2)]
    }
    // "Δx 1 kHz · Δy 3 dB" -> [{ name: "Δx", text: "1 kHz" }, { name: "Δy", text: "3 dB" }]
    readonly property var deltaParts: delta.length === 0 ? [] : delta.split(" · ").map(p => {
        const i = p.indexOf(" ")
        return { name: i < 0 ? p : p.slice(0, i), text: i < 0 ? "" : p.slice(i + 1) }
    })

    model: !shown ? 0 : delta.length > 0 ? 3 : 2
    delegate: MeasurementCard {
        id: card
        required property int index
        objectName: index === 0 ? "cursorCardC1" : index === 1 ? "cursorCardC2" : "cursorCardDelta"
        readonly property var parts: index === 2 ? [] : root.split(index === 0 ? root.c1 : root.c2)
        removable: false
        swatch: false
        chips: index === 2 ? [] : [{ name: index === 0 ? "C1" : "C2", color: index === 0 ? Theme.cursor1 : Theme.cursor2 }]
        title: index === 2 ? (root.deltaParts[0]?.name ?? "") : ""
        value: index === 2 ? (root.deltaParts[0]?.text ?? "") : parts[0]
        items: index === 2 ? root.deltaParts.slice(1) : [{ name: "y", text: parts[1] }]
    }
}
