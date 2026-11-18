pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// FFT display of the Spectrum Analyzer: spectrum (with harmonic markers, max/min hold, cursors),
// optional analysis tables, averaging progress with Restart, optional spectrogram and time record.
// The measurements and cursor readouts are the panel's cards. View only: DsaController holds the state.
Item {
    id: root

    required property DsaController controller
    // The time record shows on request (Display tool).
    property bool showTime: true
    // The source channel's color (spectrum and time record).
    property color traceColor: Theme.signalCh0
    readonly property bool narrow: width < 720
    readonly property real leftMargin: Math.max(spectrumPlot.gutterLeft, timePlot.gutterLeft,
                                                root.controller.waterfallVisible ? waterfallPlot.gutterLeft : 0)
    readonly property bool cursors: controller.cursorsOn
    // Pixels of the time plot's axis units: the ELVISmx record axis 0 … (N-1)/fs.
    readonly property real timeMaximum: Math.max(controller.recordDuration, 1e-6)

    // Pixel position of a frequency along the spectrum plot's x axis.
    function plotX(frequency: real): real {
        const lo = frequencyAxis.min, hi = frequencyAxis.max
        const t = root.controller.logFrequency && lo > 0 ? Math.log(frequency / lo) / Math.log(hi / lo)
                                                         : (frequency - lo) / (hi - lo)
        return t * Math.max(1, spectrumPlot.width - root.leftMargin - 16)
    }
    // The markers that get a label: the fundamental and the significant harmonics, each at least
    // 100 px from the previous label and clear of the plot's right edge, so labels never overlap.
    readonly property var labelledOrders: {
        const shown = []
        let last = -1e9
        const plotWidth = spectrumPlot.width - root.leftMargin - 16
        for (const h of root.controller.harmonics) {
            if (!(h.order === 1 || h.significant))
                continue
            const x = plotX(h.frequency)
            if (x - last >= 100 && x <= plotWidth - 60) {
                shown.push(h.order)
                last = x
            }
        }
        return shown
    }

    PlotAxis {
        id: frequencyAxis
        min: root.controller.frequencyMinimum
        max: Math.max(root.controller.frequencyMaximum, root.controller.frequencyMinimum * 1.001 + 1e-9)
        scale: root.controller.logFrequency ? PlotAxis.Log : PlotAxis.Linear
        unit: "Hz"
        lowerLimit: 0
        upperLimit: root.controller.frequencyMaximum
        // Zooming in stops at a few hundred bins' worth of span (no infinite zoom).
        minimumSpan: Math.max(root.controller.frequencyMaximum - root.controller.frequencyMinimum, 1e-6) / 500
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        // --- Spectrum + tables --------------------------------------------------------------
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 3
            spacing: Theme.spacingS

            BenchPlot {
                id: spectrumPlot
                objectName: "dsaSpectrumPlot"
                Layout.fillWidth: true
                Layout.fillHeight: true
                xAxis: frequencyAxis
                leftMargin: root.leftMargin
                hoverReadout: true
                placeholderText: root.controller.hasResult || root.controller.running ? "" : ""
                yAxis {
                    min: root.controller.spectrumMinimum
                    max: root.controller.spectrumMaximum
                    // Pan/zoom stay inside the scale (auto or manual): never into an empty region, never
                    // out past it, and not endlessly in.
                    lowerLimit: root.controller.spectrumMinimum
                    upperLimit: root.controller.spectrumMaximum
                    minimumSpan: Math.max(root.controller.spectrumMaximum - root.controller.spectrumMinimum, 1e-9) / 200
                    unit: root.controller.magnitudeUnit
                    labelFormat: root.controller.logarithmicUnits ? PlotAxis.Fixed : PlotAxis.Engineering
                    tickSpacing: 36
                }

                PlotTrace {
                    visible: root.controller.minHold
                    buffer: root.controller.minHoldTrace
                    name: qsTr("Min hold")
                    unit: root.controller.magnitudeUnit
                    color: Theme.ref
                    style: PlotElement.Dash
                }
                PlotTrace {
                    visible: root.controller.maxHold
                    buffer: root.controller.maxHoldTrace
                    name: qsTr("Max hold")
                    unit: root.controller.magnitudeUnit
                    color: Theme.math
                }
                PlotTrace {
                    id: spectrumTrace
                    buffer: root.controller.spectrum
                    name: root.controller.spectrumDisplay === DsaController.PowerSpectralDensityDisplay ? qsTr("PSD") : qsTr("Spectrum")
                    unit: root.controller.magnitudeUnit
                    color: root.traceColor
                    fill: true
                    fillOpacity: 0.16
                }
                Instantiator {
                    model: root.controller.harmonicMarkers ? root.controller.harmonics : []
                    delegate: PlotMarker {
                        required property var modelData
                        plot: spectrumPlot
                        x: modelData.frequency
                        trace: spectrumTrace
                        shape: modelData.order === 1 ? PlotMarker.TriangleDown : PlotMarker.Diamond
                        readonly property bool strong: modelData.order === 1 || modelData.significant
                        size: modelData.order === 1 ? 11 : strong ? 8 : 5
                        color: Theme.alpha(root.traceColor, strong ? 1 : 0.5)
                        // Right of the marker near the left edge, so the label never reaches the axis labels.
                        labelPosition: root.plotX(modelData.frequency) < 70 ? PlotMarker.Right : PlotMarker.Above
                        label: !strong || root.labelledOrders.indexOf(modelData.order) < 0 ? "" : modelData.order === 1 ? "F " + modelData.frequencyText
                                                                    : modelData.name + " " + modelData.dbcText
                    }
                }
                PlotCursor {
                    visible: root.cursors && root.controller.cursor1Plot === DsaController.SpectrumPlot
                    position: root.controller.cursor1Position
                    trace: spectrumTrace
                    label: "C1"
                    color: Theme.cursor1
                    selected: root.controller.cursorSelect === 0
                    readoutVisible: false
                    onMoved: position => root.controller.cursor1Position = position
                }
                PlotCursor {
                    visible: root.cursors && root.controller.cursor2Plot === DsaController.SpectrumPlot
                    position: root.controller.cursor2Position
                    trace: spectrumTrace
                    label: "C2"
                    color: Theme.cursor2
                    selected: root.controller.cursorSelect === 1
                    readoutVisible: false
                    onMoved: position => root.controller.cursor2Position = position
                }
            }

            // Harmonics and peaks (MYBENCH).
            Rectangle {
                id: tablesPanel
                visible: root.controller.analysisTables && !root.narrow
                Layout.preferredWidth: 236
                Layout.fillHeight: true
                radius: Theme.radiusM
                color: Theme.alpha(Theme.text, Theme.dark ? 0.03 : 0.025)
                border.width: 1
                border.color: Theme.displayBorder

                Flickable {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    contentHeight: tables.implicitHeight
                    clip: true
                    ColumnLayout {
                        id: tables
                        width: parent.width
                        spacing: 3
                        component Heading: Text {
                            Layout.topMargin: 2
                            color: Theme.textMuted
                            font.pixelSize: Theme.fontSizeXs
                            font.weight: Font.DemiBold
                            font.letterSpacing: 1
                        }
                        component Cell: Text {
                            color: Theme.text
                            font.pixelSize: Theme.fontSizeS
                            font.features: Theme.tabularFigures
                        }
                        Heading { text: qsTr("HARMONICS") }
                        Repeater {
                            model: root.controller.harmonics
                            delegate: RowLayout {
                                required property var modelData
                                Layout.fillWidth: true
                                spacing: Theme.spacingXs
                                Cell { Layout.preferredWidth: 24; text: parent.modelData.name; color: Theme.textSecondary }
                                Cell { Layout.fillWidth: true; text: parent.modelData.frequencyText }
                                Cell { text: parent.modelData.order === 1 ? parent.modelData.levelText : parent.modelData.dbcText; horizontalAlignment: Text.AlignRight }
                            }
                        }
                        Heading { text: qsTr("PEAKS"); Layout.topMargin: Theme.spacingS }
                        Repeater {
                            model: root.controller.peaks
                            delegate: RowLayout {
                                required property var modelData
                                required property int index
                                Layout.fillWidth: true
                                spacing: Theme.spacingXs
                                Cell { Layout.preferredWidth: 24; text: parent.index + 1; color: Theme.textMuted }
                                Cell { Layout.fillWidth: true; text: parent.modelData.frequencyText }
                                Cell { text: parent.modelData.levelText; horizontalAlignment: Text.AlignRight }
                            }
                        }
                    }
                }
            }
        }

        // --- Spectrogram (MYBENCH) ------------------------------------------------------------
        RowLayout {
            visible: root.controller.waterfallVisible
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1.6
            spacing: Theme.spacingS
        BenchPlot {
            id: waterfallPlot
            Layout.fillWidth: true
            Layout.fillHeight: true
            xAxis: frequencyAxis
            xLabelsVisible: false
            leftMargin: root.leftMargin
            yAxis {
                min: -root.controller.waterfallHistory
                max: 0
                unit: ""
                interactive: false
                labelsVisible: false
            }
            PlotWaterfall {
                buffer: root.controller.waterfall
                minimum: root.controller.spectrumMinimum
                maximum: root.controller.spectrumMaximum
                rowHeight: 1
                colormap: PlotWaterfall.Inferno
            }
        }
            // Keeps the spectrogram's frequency axis under the spectrum's when the tables show.
            Item {
                visible: tablesPanel.visible
                Layout.preferredWidth: tablesPanel.Layout.preferredWidth
            }
        }

        // --- Time record ------------------------------------------------------------------------
        BenchPlot {
            id: timePlot
            visible: root.showTime
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredHeight: 1.25
            leftMargin: root.leftMargin
            hoverReadout: true
            xAxis { min: 0; max: root.timeMaximum; unit: "s"; lowerLimit: 0; upperLimit: root.timeMaximum }
            yAxis { autoScale: true; min: -1; max: 1; unit: "V"; tickSpacing: 30; limitToData: true; limitMargin: 1; minimumSpan: 1e-6 }
            PlotTrace {
                id: timeTrace
                buffer: root.controller.timeSignal
                name: qsTr("Amplitude")
                unit: "V"
                color: root.traceColor
            }
            PlotCursor {
                visible: root.cursors && root.controller.cursor1Plot === DsaController.TimePlot
                position: root.controller.cursor1Position
                trace: timeTrace
                label: "C1"
                color: Theme.cursor1
                selected: root.controller.cursorSelect === 0
                readoutVisible: false
                onMoved: position => root.controller.cursor1Position = position
            }
            PlotCursor {
                visible: root.cursors && root.controller.cursor2Plot === DsaController.TimePlot
                position: root.controller.cursor2Position
                trace: timeTrace
                label: "C2"
                color: Theme.cursor2
                selected: root.controller.cursorSelect === 1
                readoutVisible: false
                onMoved: position => root.controller.cursor2Position = position
            }
        }
    }
}
