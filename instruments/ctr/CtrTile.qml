import QtQuick
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Overview tile content: the function and its last value (or the pulse train / FREQOUT
// frequency), the DIO terminals and, while measuring, a bare mini trend.
Item {
    id: root

    required property CtrController controller

    readonly property bool measuring: controller.counterFunction === CtrController.Measure
    readonly property bool pulsing: controller.counterFunction === CtrController.PulseTrain

    TileBody {
        anchors.fill: parent
        screenShown: root.measuring && (root.controller.running || root.controller.hasData)

        TileStat {
            big: true
            label: root.measuring ? root.controller.functionTitle : root.pulsing ? qsTr("Pulse train") : qsTr("FREQOUT")
            value: root.measuring ? (root.controller.valueText.startsWith("---") ? "—" : (root.controller.valueText + " " + root.controller.unit).trim())
                 : Units.format(root.pulsing ? (root.controller.outputFrequency > 0 ? root.controller.outputFrequency : root.controller.coercedPulseFrequency)
                                             : root.controller.freqOutEnabled ? root.controller.coercedFreqOut : NaN, "Hz", 5)
            stale: !root.controller.running
        }
        TileStat {
            label: qsTr("Terminals")
            value: root.controller.terminals.length > 0 ? root.controller.terminals : "—"
        }

        screen: BenchPlot {
            anchors.fill: parent
            bare: true
            placeholderText: ""
            xAxis { labelFormat: PlotAxis.Time; follow: true; labelsVisible: false; gridVisible: false }
            yAxis { autoScale: true; labelsVisible: false; gridVisible: false }
            Component.onCompleted: xAxis.setRange(Date.now() / 1000 - 30, Date.now() / 1000)
            PlotTrace { buffer: root.controller.trend; color: Theme.signalCh0; width: 1.4 }
        }
    }
}
