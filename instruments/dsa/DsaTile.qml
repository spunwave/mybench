import QtQuick
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Overview tile content: the span, the lines and the window, the fundamental and THD (or the
// overall level) once measured, and a bare mini spectrum (or the 1/3-octave bars).
Item {
    id: root

    required property DsaController controller
    readonly property color sourceColor: Theme.signalColor(["ai0", "ai1", "audioInL", "audioInR"][controller.sourceChannel] ?? "ai0")
    readonly property bool stale: !controller.running
    readonly property bool measured: controller.octave ? controller.hasOctaveResult : controller.hasResult

    TileBody {
        anchors.fill: parent
        screenShown: root.controller.running || root.measured

        TileStat {
            big: true
            label: !root.measured ? qsTr("Span") : root.controller.octave ? qsTr("Overall") : qsTr("Fundamental")
            value: !root.measured ? Units.format(root.controller.frequencySpan, "Hz", 3)
                 : root.controller.octave ? root.controller.octaveOverall.toFixed(1) + " dBV"
                 : Units.format(root.controller.fundamentalFrequency, "Hz", 4)
            stale: root.measured && root.stale
        }
        TileStat {
            label: root.controller.octave ? qsTr("Bands") : qsTr("Lines")
            value: root.controller.octave ? qsTr("1/3 octave") : String(root.controller.lines)
        }
        TileStat {
            label: root.measured && !root.controller.octave ? qsTr("THD") : qsTr("Window")
            value: root.measured && !root.controller.octave ? root.controller.thd.toFixed(2) + " %"
                 : root.controller.windowLabels[root.controller.windowIndex] ?? "—"
            stale: root.measured && root.stale
        }

        screen: [
            BenchPlot {
                anchors.fill: parent
                visible: !root.controller.octave
                bare: true
                placeholderText: ""
                xAxis { min: 0; max: root.controller.frequencySpan; labelsVisible: false; gridVisible: false; minorGridVisible: false }
                yAxis { min: root.controller.spectrumMinimum; max: root.controller.spectrumMaximum; labelsVisible: false; gridVisible: false; minorGridVisible: false }
                PlotTrace { buffer: root.controller.spectrum; color: root.sourceColor; width: 1.2 }
            },
            BenchPlot {
                anchors.fill: parent
                visible: root.controller.octave
                bare: true
                placeholderText: ""
                xAxis { min: root.controller.octaveFrequencyMinimum; max: root.controller.octaveFrequencyMaximum; scale: PlotAxis.Log; labelsVisible: false; gridVisible: false; minorGridVisible: false }
                yAxis { min: root.controller.octaveMinimum; max: root.controller.octaveMaximum; labelsVisible: false; gridVisible: false; minorGridVisible: false }
                PlotTrace { buffer: root.controller.octaveBars; color: root.sourceColor; width: 1; fill: true; fillOpacity: 0.5 }
            }
        ]
    }
}
