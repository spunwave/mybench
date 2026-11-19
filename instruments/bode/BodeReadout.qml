pragma ComponentBehavior: Bound
import QtQuick
import MyBench.Framework
import MyBench.Controls

// The cursor readout cards of the measurement strip. Cursors on: one card per cursor (frequency,
// gain and phase) and their difference C2 − C1 with the gain slope in dB/decade. Cursors off: one
// card, the last measured point.
Repeater {
    id: root

    required property BodeController controller
    property bool linearGain: false
    property color cursor1Color: Theme.cursor1
    property color cursor2Color: Theme.cursor2

    readonly property bool cursorsShown: controller.cursorsOn && controller.cursorIndex >= 0
    // Texts as shown (tests read them).
    readonly property string slopeText: isFinite(controller.cursorSlope)
                                        ? qsTr("%1 dB/dec").arg(signed(controller.cursorSlope, 1)) : "—"
    readonly property string deltaFrequencyText: isFinite(controller.cursor2Frequency - controller.cursorFrequency)
                                                  ? sign(controller.cursor2Frequency - controller.cursorFrequency)
                                                    + Units.format(Math.abs(controller.cursor2Frequency - controller.cursorFrequency), "Hz", 4)
                                                  : "—"

    function sign(v: real): string { return v < 0 ? "−" : v > 0 ? "+" : "" }
    function signed(v: real, decimals: int): string { return sign(v) + Math.abs(v).toFixed(decimals) }
    function frequencyText(f: real): string { return isFinite(f) && f > 0 ? Units.format(f, "Hz", 4) : "—" }
    function gainText(db: real): string {
        if (!isFinite(db))
            return "—"
        return linearGain ? Math.pow(10, db / 20).toPrecision(3) : (db < 0 ? "−" : "") + Math.abs(db).toFixed(2) + " dB"
    }
    function phaseText(deg: real): string { return isFinite(deg) ? (deg < 0 ? "−" : "") + Math.abs(deg).toFixed(1) + "°" : "—" }
    function deltaGainText(): string {
        const g1 = controller.cursorGainDb, g2 = controller.cursor2GainDb
        if (!isFinite(g1) || !isFinite(g2))
            return "—"
        return linearGain ? "×" + Math.pow(10, (g2 - g1) / 20).toPrecision(3) : signed(g2 - g1, 2) + " dB"
    }
    function deltaPhaseText(): string {
        const p1 = controller.cursorPhase, p2 = controller.cursor2Phase
        return isFinite(p1) && isFinite(p2) ? signed(p2 - p1, 1) + "°" : "—"
    }
    function lastGainText(): string {
        return linearGain ? controller.readoutGain.toPrecision(3) : gainText(controller.readoutGainDb)
    }

    model: cursorsShown ? 3 : 1
    delegate: MeasurementCard {
        id: card
        required property int index
        objectName: "cardCursor" + index
        readonly property bool delta: root.cursorsShown && index === 2
        readonly property bool last: !root.cursorsShown
        removable: false
        swatch: false
        chips: delta || last ? [] : [{ name: index === 0 ? "C1" : "C2", color: index === 0 ? root.cursor1Color : root.cursor2Color }]
        title: last ? qsTr("Last point") : delta ? qsTr("C2 − C1") : ""
        value: last ? (root.controller.readoutValid ? root.frequencyText(root.controller.readoutFrequency) : "—")
               : delta ? root.deltaFrequencyText
               : root.frequencyText(index === 0 ? root.controller.cursorFrequency : root.controller.cursor2Frequency)
        items: last ? [{ name: qsTr("gain"), text: root.controller.readoutValid ? root.lastGainText() : "—" },
                       { name: qsTr("phase"), text: root.controller.readoutValid ? root.phaseText(root.controller.readoutPhase) : "—" }]
               : delta ? [{ name: qsTr("gain"), text: root.deltaGainText() }, { name: qsTr("phase"), text: root.deltaPhaseText() },
                          { name: qsTr("slope"), text: root.slopeText }]
               : [{ name: qsTr("gain"), text: root.gainText(index === 0 ? root.controller.cursorGainDb : root.controller.cursor2GainDb) },
                  { name: qsTr("phase"), text: root.phaseText(index === 0 ? root.controller.cursorPhase : root.controller.cursor2Phase) }]
    }
}
