import QtQuick
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Overview tile (content only): the measured frequency, each channel's scale and a mini trace.
Item {
    id: root

    required property ScopeController controller
    readonly property ScopeChannel ch0: controller.channel0
    readonly property ScopeChannel ch1: controller.channel1
    readonly property ScopeChannel shown: ch0.enabled || !ch1.enabled ? ch0 : ch1
    readonly property bool stale: !controller.running
    readonly property bool measured: shown.hasResults && shown.frequency > 0
    function scale(ch: ScopeChannel): string {
        return ch.enabled ? ch.scaleLabel : qsTr("Off")
    }

    TileBody {
        anchors.fill: parent
        screenShown: root.controller.running || root.controller.hasData

        TileStat {
            big: true
            label: root.measured ? qsTr("CH%1 frequency").arg(root.shown.index) : qsTr("Time/div")
            value: root.measured ? Units.format(root.shown.frequency, "Hz", 4) : root.controller.timeDivLabel
            stale: root.measured && root.stale
        }
        TileStat {
            swatchColor: Theme.signalCh0
            label: qsTr("CH0")
            value: root.scale(root.ch0)
            stale: !root.ch0.enabled
        }
        TileStat {
            swatchColor: Theme.signalCh1
            label: qsTr("CH1")
            value: root.scale(root.ch1)
            stale: !root.ch1.enabled
        }

        screen: BenchPlot {
            id: miniPlot
            anchors.fill: parent
            bare: true
            placeholderText: ""
            // A few periods of the shown channel (the full screen while no frequency is known).
            readonly property real periods: root.shown.frequency > 0 ? 4 / root.shown.frequency : Infinity
            xAxis { min: 0; max: Math.min(root.controller.screenTime, miniPlot.periods); labelsVisible: false; gridVisible: false }
            yAxis { min: -5; max: 5; labelsVisible: false; gridVisible: false }
            PlotTrace {
                buffer: root.controller.ch1
                visible: root.ch1.enabled && root.controller.displayMode === ScopeController.YT
                color: Theme.signalCh1
                width: 1.2
                yScale: 1 / root.ch1.voltsPerDiv
                yOffset: root.ch1.position
            }
            PlotTrace {
                buffer: root.controller.ch0
                visible: root.ch0.enabled && root.controller.displayMode === ScopeController.YT
                color: Theme.signalCh0
                width: 1.2
                yScale: 1 / root.ch0.voltsPerDiv
                yOffset: root.ch0.position
            }
            PlotTrace {
                buffer: root.controller.xyTrace
                visible: root.controller.displayMode === ScopeController.XY && root.ch0.enabled && root.ch1.enabled
                color: Theme.signalCh0
                width: 1.2
                xScale: 1 / root.ch0.voltsPerDiv
                xOffset: root.ch0.position
                yScale: 1 / root.ch1.voltsPerDiv
                yOffset: root.ch1.position
            }
        }
    }
}
