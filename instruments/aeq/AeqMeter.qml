import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// Vertical level meter in dBFS (-60 ... 0): RMS bar, peak line, held peak, colored zones
// (green, amber from -12 dBFS, red from -3 dBFS).
// The peak level is the tooltip.
//     AeqMeter { label: "In L"; peak: m.peak; rms: m.rms; hold: m.hold }
Item {
    id: root

    property string label
    property real peak: -120
    property real rms: -120
    property real hold: -120
    property bool active: true
    property real floorDb: -60

    function position(db: real): real {
        return Math.max(0, Math.min(1, (db - root.floorDb) / -root.floorDb))
    }
    function zoneColor(db: real): color {
        return db > -3 ? Theme.negative : db > -12 ? Theme.caution : Theme.positive
    }

    implicitWidth: 14   // the peak level is in the tooltip
    implicitHeight: 180

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingXs

        Rectangle {
            id: bar
            Layout.alignment: Qt.AlignHCenter
            Layout.fillHeight: true
            implicitWidth: 10
            radius: 2
            color: Theme.surfaceSunken
            opacity: root.active ? 1 : 0.4

            // RMS fill with the zone colors.
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                radius: 2
                height: parent.height * root.position(root.rms)
                color: root.zoneColor(root.rms)
            }
            // Peak.
            Rectangle {
                width: parent.width
                height: 2
                y: parent.height * (1 - root.position(root.peak)) - 1
                visible: root.peak > root.floorDb
                color: root.zoneColor(root.peak)
                opacity: 0.8
            }
            // Held peak.
            Rectangle {
                width: parent.width + 4
                x: -2
                height: 2
                y: parent.height * (1 - root.position(root.hold)) - 1
                visible: root.hold > root.floorDb
                color: root.zoneColor(root.hold)
            }
        }
        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeCaption
        }
    }

    ToolTip.visible: hover.hovered
    ToolTip.delay: 600
    ToolTip.text: root.active && root.peak > -120 ? root.label + " · " + Math.round(root.peak) + " dBFS" : root.label
    HoverHandler { id: hover }
}
