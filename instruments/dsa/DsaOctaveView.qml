pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// 1/3-octave display of the Spectrum Analyzer: Settled indicator and Restart, band bar chart and
// the latest time block (overall level and loudest band are the panel's cards).
Item {
    id: root

    required property DsaController controller
    property color traceColor: Theme.signalCh0
    readonly property string levelUnit: "dBV" + (controller.octaveWeightingSuffix.length > 0 ? " " + controller.octaveWeightingSuffix : "")
    readonly property real leftMargin: Math.max(barPlot.gutterLeft, timePlot.gutterLeft)

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        BenchPlot {
            id: barPlot
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 3
            leftMargin: root.leftMargin
            hoverReadout: true
            placeholderText: root.controller.hasOctaveResult || root.controller.running ? "" : ""
            xAxis {
                min: root.controller.octaveFrequencyMinimum
                max: root.controller.octaveFrequencyMaximum
                scale: PlotAxis.Log
                unit: "Hz"
                lowerLimit: 5
                upperLimit: 25000
            }
            yAxis {
                min: root.controller.octaveMinimum
                max: root.controller.octaveMaximum
                // Pan/zoom stay inside the scale.
                lowerLimit: root.controller.octaveMinimum
                upperLimit: root.controller.octaveMaximum
                minimumSpan: Math.max(root.controller.octaveMaximum - root.controller.octaveMinimum, 1e-9) / 200
                unit: root.levelUnit
                labelFormat: PlotAxis.Fixed
                tickSpacing: 36
            }
            PlotTrace {
                buffer: root.controller.octaveBars
                name: qsTr("Band level")
                unit: root.levelUnit
                color: root.traceColor
                fill: true
                fillOpacity: 0.55
            }
        }

        BenchPlot {
            id: timePlot
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1.2
            leftMargin: root.leftMargin
            hoverReadout: true
            xAxis { min: 0; max: root.controller.recordDuration; unit: "s" }
            yAxis { autoScale: true; min: -1; max: 1; unit: "V"; tickSpacing: 30; limitToData: true; limitMargin: 1; minimumSpan: 1e-6 }
            PlotTrace { buffer: root.controller.timeSignal; name: qsTr("Amplitude"); unit: "V"; color: root.traceColor }
        }
    }
}
