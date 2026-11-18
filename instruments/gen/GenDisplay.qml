pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// The generator display: one plot with both outputs in their channel colors. Time: one shared time
// axis, DC levels as flat lines with a draggable handle (a 60 s strip chart when every used output
// is DC). Frequency: both spectra (dBV). A channel whose output is off is faded; an Off channel is
// not drawn.
ColumnLayout {
    id: root

    required property GenController controller
    readonly property var channels: [controller.channel0, controller.channel1]
    readonly property bool frequencyView: controller.displayMode === GenController.Frequency
    readonly property var shown: channels.filter(c => c.mode !== GenChannel.Off
                                                   && !(c.mode === GenChannel.Arbitrary && !c.hasWaveform))
    // The strip chart only when every output in use is a DC level (other waveforms need the time
    // window of their periods).
    readonly property bool dcChart: !frequencyView && shown.length > 0 && shown.every(c => c.mode === GenChannel.Dc)
    readonly property real historyEnd: {
        let end = 0
        for (const c of channels) {
            c.history.count   // dependency
            if (c.history.count > 0)
                end = Math.max(end, c.history.xMaximum())
        }
        return end
    }
    readonly property alias plot: genPlot

    function channelColor(index: int): color { return index === 0 ? Theme.signalAo0 : Theme.signalAo1 }
    function active(c: GenChannel): bool { return c.state === GenChannel.Running || c.state === GenChannel.Sweeping }

    // --- The plot ---------------------------------------------------------------------------------
    BenchPlot {
        id: genPlot
        objectName: "genPlot"
        Layout.fillWidth: true
        Layout.fillHeight: true
        hoverReadout: true
        placeholderText: root.shown.length === 0 ? qsTr("No output selected") : ""
        xAxis {
            min: root.frequencyView ? 0 : root.dcChart ? Math.max(0, root.historyEnd - root.controller.channel0.historySpan) : 0
            max: root.frequencyView ? Math.max(10, ...root.shown.map(c => c.spectrumSpan))
                 : root.dcChart ? Math.max(root.controller.channel0.historySpan, root.historyEnd)
                 : Math.max(root.controller.channel0.previewSpan, root.controller.channel1.previewSpan)
            unit: root.frequencyView ? "Hz" : "s"
            unitInLabels: true
        }
        yAxis {
            min: root.frequencyView ? -140
                 : root.dcChart ? -Math.max(...root.shown.map(c => c.outputRange))
                 : root.shown.length > 0 ? Math.min(...root.shown.map(c => c.previewMin)) : -1
            max: root.frequencyView ? 20
                 : root.dcChart ? Math.max(...root.shown.map(c => c.outputRange))
                 : root.shown.length > 0 ? Math.max(...root.shown.map(c => c.previewMax)) : 1
            unit: root.frequencyView ? "dBV" : "V"
        }

        // Time: what each output generates (or would), faded while its output is off.
        Instantiator {
            model: root.channels
            delegate: PlotTrace {
                required property GenChannel modelData
                required property int index
                objectName: "genTrace" + index
                plot: genPlot
                visible: !root.frequencyView && !root.dcChart && root.shown.indexOf(modelData) >= 0
                buffer: modelData.preview
                name: modelData.name
                unit: "V"
                color: root.active(modelData) ? root.channelColor(index) : Theme.alpha(root.channelColor(index), 0.45)
                step: modelData.previewStep
            }
        }
        // DC strip chart (every output in use is DC).
        Instantiator {
            model: root.channels
            delegate: PlotTrace {
                required property GenChannel modelData
                required property int index
                plot: genPlot
                visible: root.dcChart && modelData.mode === GenChannel.Dc
                buffer: modelData.history
                name: modelData.name
                unit: "V"
                color: root.channelColor(index)
                step: true
            }
        }
        // Frequency: the spectra.
        Instantiator {
            model: root.channels
            delegate: PlotTrace {
                required property GenChannel modelData
                required property int index
                plot: genPlot
                visible: root.frequencyView && root.shown.indexOf(modelData) >= 0
                buffer: modelData.spectrum
                name: modelData.name
                unit: "dBV"
                color: root.channelColor(index)
                fill: true
                fillOpacity: 0.14
            }
        }
        // DC level handles: drag to set the level.
        Instantiator {
            model: root.channels
            delegate: PlotLine {
                required property GenChannel modelData
                required property int index
                plot: genPlot
                visible: !root.frequencyView && modelData.mode === GenChannel.Dc
                value: modelData.dcLevel
                color: Theme.alpha(root.channelColor(index), 0.6)
                style: PlotElement.Dash
                handle: PlotLine.End
                label: Units.fixed(modelData.dcLevel, "V", 2)
                draggable: true
                onMoved: v => modelData.dcLevel = Math.round(v * 100) / 100
            }
        }
    }
}
