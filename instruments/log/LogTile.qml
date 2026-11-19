import QtQuick
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Overview tile content: the sampling rate, the logged channels, the latest value (the recording
// time while a file is written) and the last minute of the chart.
Item {
    id: root

    required property LogController controller

    function entry(key: string): var {
        const list = root.controller.channelStats
        for (let i = 0; i < list.length; ++i) {
            if (list[i].key === key)
                return list[i]
        }
        return null
    }
    function valueOf(key: string, unit: string): string {
        const e = root.entry(key)
        return e && e.count > 0 ? Units.format(e.last, unit, 4) : "—"
    }
    function duration(seconds: real): string {
        const s = Math.floor(seconds)
        const hh = Math.floor(s / 3600)
        return (hh > 0 ? hh + ":" : "") + String(Math.floor(s / 60) % 60).padStart(hh > 0 ? 2 : 1, "0") + ":" + String(s % 60).padStart(2, "0")
    }
    // The logged channels, with their colours.
    readonly property var logged: [
        controller.ai0Enabled ? { key: "ai0", label: "AI 0", unit: "V", color: Theme.signalCh0 } : null,
        controller.ai1Enabled ? { key: "ai1", label: "AI 1", unit: "V", color: Theme.signalCh1 } : null,
        controller.dmmEnabled ? { key: "dmm", label: qsTr("DMM"), unit: controller.dmmUnit, color: Theme.signalRef } : null
    ].filter(c => c !== null)
    readonly property bool measured: controller.running || controller.hasData

    TileBody {
        anchors.fill: parent
        screenShown: root.measured

        TileStat {
            big: true
            label: qsTr("Rate")
            value: Units.format(root.controller.coercedRate, "S/s", 3)
        }
        // Before any data: which channels it logs.
        TileStat {
            visible: !root.measured && !root.controller.recording
            label: qsTr("Channels")
            value: root.logged.length > 0 ? root.logged.map(c => c.label).join(" · ") : qsTr("None")
        }
        TileStat {
            visible: root.controller.recording
            label: root.controller.recordPaused ? qsTr("Paused") : qsTr("Recording")
            value: root.duration(root.controller.recordSeconds)
        }
        // With data: each channel's latest value.
        Repeater {
            model: root.measured ? root.logged : []
            delegate: TileStat {
                required property var modelData
                label: modelData.label
                swatchColor: modelData.color
                value: root.valueOf(modelData.key, modelData.unit)
                stale: !root.controller.running
            }
        }

        screen: BenchPlot {
            anchors.fill: parent
            bare: true
            placeholderText: ""
            xAxis { labelFormat: PlotAxis.Time; follow: true; labelsVisible: false; gridVisible: false }
            yAxis { autoScale: true; labelsVisible: false; gridVisible: false }
            Component.onCompleted: xAxis.setRange(Date.now() / 1000 - 60, Date.now() / 1000)
            PlotTrace { visible: root.controller.ai0Enabled; buffer: root.controller.ai0; color: Theme.signalCh0; width: 1.4 }
            PlotTrace { visible: root.controller.ai1Enabled; buffer: root.controller.ai1; color: Theme.signalCh1; width: 1.4 }
        }
    }
}
