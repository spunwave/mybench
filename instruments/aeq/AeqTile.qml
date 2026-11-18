pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import MyBench.Controls
import MyBench.Plot

// Overview tile content: the band gains as mini bars around 0 dB (Bypass dims them) and the bare
// response curve.
Item {
    id: root

    required property AeqController controller

    function signedDb(v: real): string {
        return (v > 0 ? "+" : v < 0 ? "−" : "") + Math.abs(v).toFixed(0)
    }

    // One band: its value, a bar growing up or down from the middle, its name.
    component Band: Item {
        id: band
        required property string label
        required property real gain
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 56
        opacity: root.controller.bypass ? 0.4 : 1

        Text {
            id: valueLabel
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.signedDb(band.gain)
            color: Theme.text
            font.pixelSize: Theme.fontSizeHeading
            font.weight: Font.DemiBold
            font.features: Theme.tabularFigures
        }
        Text {
            id: nameLabel
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            text: band.label
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeSmall
        }
        Item {
            id: track
            anchors.top: valueLabel.bottom
            anchors.bottom: nameLabel.top
            anchors.margins: Theme.spacingXs
            anchors.horizontalCenter: parent.horizontalCenter
            width: 10
            Rectangle {
                anchors.fill: parent
                radius: 3
                color: Theme.alpha(Theme.text, 0.10)
            }
            Rectangle {
                width: parent.width
                radius: 3
                readonly property real fraction: Math.max(-1, Math.min(1, band.gain / 15))
                height: Math.max(2, Math.abs(fraction) * track.height / 2)
                y: fraction >= 0 ? track.height / 2 - height : track.height / 2
                color: Theme.accent
            }
            Rectangle {
                width: parent.width + 6
                x: -3
                y: track.height / 2
                height: 1
                color: Theme.textTertiary
            }
        }
    }

    TileBody {
        anchors.fill: parent
        screenShown: true

        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.columnSpan: parent.columns
            columns: 3
            columnSpacing: Theme.spacingS
            Band { label: qsTr("Bass"); gain: root.controller.bass }
            Band { label: qsTr("Mid"); gain: root.controller.midtone }
            Band { label: qsTr("Treble"); gain: root.controller.treble }
        }

        screen: BenchPlot {
            anchors.fill: parent
            bare: true
            placeholderText: ""
            xAxis { scale: PlotAxis.Log; min: 20; max: 20000; labelsVisible: false; gridVisible: false }
            yAxis { min: -15; max: 15; labelsVisible: false; gridVisible: false }
            PlotTrace { buffer: root.controller.response; color: Theme.accent; width: 1.6 }
        }
    }
}
