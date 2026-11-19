import QtQuick
import MyBench.Controls
import MyBench.Plot

// Overview tile content: the reading under its function name, the range, and a bare trend while
// it measures. The reading turns green while continuity is closed. Updates while the DMM runs even
// when the panel is hidden.
Item {
    id: root

    required property DmmController controller

    Component.onCompleted: root.controller.autoStartIfEnabled()

    TileBody {
        anchors.fill: parent
        screenShown: root.controller.running || root.controller.hasData

        TileStat {
            big: true
            label: root.controller.functionName + (root.controller.nullOffset ? " · " + qsTr("Null") : "")
            value: root.controller.readingText.length === 0 || root.controller.readingText.startsWith("---") ? "—"
                 : (root.controller.readingText + " " + root.controller.readingUnit).trim()
            valueColor: root.controller.continuityClosed && root.controller.running ? Theme.positive : Theme.text
            stale: !root.controller.running
        }
        TileStat {
            label: qsTr("Range")
            value: root.controller.effectiveAutoRange ? qsTr("Auto") : root.controller.selectedRangeLabel
        }

        screen: BenchPlot {
            anchors.fill: parent
            bare: true
            placeholderText: ""
            xAxis { labelFormat: PlotAxis.Time; follow: true; labelsVisible: false; gridVisible: false }
            yAxis { autoScale: true; minimumSpan: root.controller.trendMinimumSpan; labelsVisible: false; gridVisible: false }
            Component.onCompleted: xAxis.setRange(Date.now() / 1000 - 60, Date.now() / 1000)
            PlotTrace { buffer: root.controller.trend; color: Theme.signalRef; width: 1.6 }
        }
    }
}
