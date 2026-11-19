import QtQuick
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Overview tile content: the sweep range, steps per decade and the −3 dB frequency, with a bare
// mini gain curve once there are points.
Item {
    id: root

    required property BodeController controller

    readonly property bool hasCutoff: controller.cutoffFrequencies.length > 0
    readonly property bool hasPoints: controller.pointCount > 0

    TileBody {
        anchors.fill: parent
        screenShown: root.hasPoints

        TileStat {
            big: true
            label: qsTr("Sweep")
            value: Units.format(root.controller.startFrequency, "Hz", 3) + " – " + Units.format(root.controller.stopFrequency, "Hz", 3)
        }
        TileStat {
            label: qsTr("Steps")
            value: qsTr("%1/dec").arg(root.controller.stepsPerDecade)
        }
        TileStat {
            label: root.hasCutoff ? qsTr("f−3dB") : root.hasPoints ? qsTr("Gain") : qsTr("Points")
            value: root.hasCutoff ? Units.format(root.controller.cutoffFrequencies[0], "Hz", 4)
                 : root.hasPoints ? Units.decibels(root.controller.readoutGainDb) : String(root.controller.plannedPoints)
            stale: !root.controller.running && !root.hasCutoff
        }

        screen: BenchPlot {
            anchors.fill: parent
            bare: true
            placeholderText: ""
            xAxis { min: root.controller.startFrequency; max: Math.max(root.controller.stopFrequency, root.controller.startFrequency * 1.001); scale: PlotAxis.Log; labelsVisible: false; gridVisible: false; minorGridVisible: false }
            yAxis { autoScale: root.controller.pointCount > 0; min: -40; max: 10; labelsVisible: false; gridVisible: false; minorGridVisible: false }
            PlotTrace { id: tileGain; buffer: root.controller.gain; color: Theme.signalColor("ai0"); width: 1.6 }
            PlotMarker {
                visible: root.hasCutoff
                x: root.hasCutoff ? root.controller.cutoffFrequencies[0] : 0
                trace: tileGain
                shape: PlotMarker.Ring
                size: 7
                color: Theme.text
            }
        }
    }
}
