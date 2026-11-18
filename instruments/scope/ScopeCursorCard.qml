import QtQuick
import MyBench.Controls

// The readout of a cursor pair in the measurement strip: the cursor colors as tags, the main
// difference as the value and up to four labelled figures beside it.
//     ScopeCursorCard { names: ["C1", "C2"]; title: qsTr("on CH0"); value: "1.25 ms"
//                       items: [{ name: "1/Δt", text: "800 Hz" }, { name: "ΔV", text: "1.2 V" }] }
MeasurementCard {
    id: card

    property var names: ["C1", "C2"]
    property color color1: Theme.cursor1
    property color color2: Theme.cursor2

    swatch: false
    removable: false
    chips: [{ name: names[0], color: color1 }, { name: names[1], color: color2 }]
}
