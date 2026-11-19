pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import MyBench.Controls
import MyBench.Plot

// Overview tile content: eight LEDs (DIO 7 ... DIO 0; inputs green, outputs orange), the input and
// output values and, while running, a bare mini timeline. With the Manual pattern, clicking an OUT
// LED flips it.
Item {
    id: root

    required property DioController controller

    function value(output: bool): string {
        void root.controller.inputValue   // refresh on every new value
        void root.controller.writtenValue
        void root.controller.hasReading
        // The usual prefixes on a tile (0x, 0b, 0o; none for decimal), not LabVIEW's letters.
        const radix = output ? root.controller.outputRadix : root.controller.inputRadix
        const prefix = radix === DioController.Hex ? "0x" : radix === DioController.Binary ? "0b"
                     : radix === DioController.Octal ? "0o" : ""
        return prefix + root.controller.numericValueText(output)
    }

    TileBody {
        anchors.fill: parent
        screenShown: root.controller.running

        Item {
            id: leds
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: ledRow.implicitHeight
            Layout.columnSpan: parent.columns
            implicitHeight: ledRow.implicitHeight

            RowLayout {
                id: ledRow
                width: parent.width
                anchors.verticalCenter: parent.verticalCenter
                spacing: 0
                Repeater {
                    model: 8
                    delegate: Item {
                        id: cell
                        required property int index
                        readonly property int line: 7 - index
                        readonly property bool isOut: (root.controller.outputMask >> line) & 1
                        readonly property bool isIn: (root.controller.inputMask >> line) & 1
                        readonly property bool level: isOut ? (root.controller.hasWritten && ((root.controller.writtenLevels >> line) & 1))
                                                            : isIn && ((root.controller.lineStates >> line) & 1)
                        Layout.fillWidth: true
                        implicitHeight: column.implicitHeight

                        Column {
                            id: column
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 3
                            Led {
                                anchors.horizontalCenter: parent.horizontalCenter
                                size: 16
                                on: cell.level
                                color: cell.isOut ? Theme.signalAo0 : Theme.signalCh0
                                opacity: cell.isIn || cell.isOut ? 1 : 0.35
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: cell.line
                                color: cell.isOut || cell.isIn ? Theme.textSecondary : Theme.textDisabled
                                font.pixelSize: Theme.fontSizeCaption
                                font.weight: Font.DemiBold
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: cell.isOut && root.controller.pattern === DioController.Manual && root.controller.running
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.controller.toggleLine(cell.line)
                        }
                    }
                }
            }
        }
        TileStat {
            big: !parent.tight
            visible: root.controller.inputMask !== 0
            swatchColor: Theme.signalCh0
            label: qsTr("In")
            value: root.value(false)
            stale: !root.controller.running
        }
        TileStat {
            big: root.controller.inputMask === 0 && !parent.tight
            visible: root.controller.outputMask !== 0
            swatchColor: Theme.signalAo0
            label: qsTr("Out")
            value: root.value(true)
        }

        screen: BenchPlot {
            id: mini
            anchors.fill: parent
            bare: true
            placeholderText: ""
            xAxis { follow: root.controller.timelineEnd > 10; labelsVisible: false; gridVisible: false }
            yAxis { min: 0; max: 8; inverted: true; labelsVisible: false; gridVisible: false }
            Component.onCompleted: xAxis.setRange(Math.max(0, root.controller.timelineEnd - 10), Math.max(10, root.controller.timelineEnd))
            PlotLogicTrace {
                buffer: root.controller.timeline
                lanes: [7, 6, 5, 4, 3, 2, 1, 0]
                laneColors: [7, 6, 5, 4, 3, 2, 1, 0].map(l => (root.controller.outputMask >> l) & 1 ? Theme.signalAo0
                                                         : (root.controller.inputMask >> l) & 1 ? Theme.signalCh0 : Theme.textMuted)
                labelsVisible: false
                width: 1
            }
        }
    }
}
