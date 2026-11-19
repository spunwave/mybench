import QtQuick
import MyBench.Controls

// How to wire a Bode measurement: the stimulus output drives the circuit and the first input also
// taps it, the second input reads the circuit's output (AO 0 / AI 0 / AI 1 unless the controller
// chose others). A thin neutral outline drawing, shown in the Wiring tool and in the middle of the empty plot.
Item {
    id: wiring

    property string stimulusName: qsTr("AO 0")
    property string stimulusInputName: qsTr("AI 0")
    property string responseInputName: qsTr("AI 1")
    property color stimulusColor: Theme.signalAo0
    property color stimulusInputColor: Theme.signalCh0
    property color responseInputColor: Theme.signalCh1
    readonly property color lineColor: Theme.textTertiary

    implicitWidth: 312
    implicitHeight: 92

    component Chip: Rectangle {
        id: chip
        property alias text: chipText.text
        property color swatch: wiring.lineColor
        width: 68
        height: 24
        radius: Theme.radiusControl
        color: "transparent"
        border.width: 1
        border.color: wiring.lineColor
        Text {
            id: chipText
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: 7
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
        }
        Rectangle {   // the channel's signal colour
            anchors { left: parent.left; leftMargin: 5; verticalCenter: parent.verticalCenter }
            width: 8; height: 8; radius: 4
            color: chip.swatch
        }
    }

    Chip { id: ao0Chip; x: 0; y: 12; text: wiring.stimulusName; swatch: wiring.stimulusColor }
    Chip { id: ai0Chip; x: 0; y: 64; text: wiring.stimulusInputName; swatch: wiring.stimulusInputColor }
    Rectangle {   // AO 0 → circuit
        x: ao0Chip.width; y: ao0Chip.y + ao0Chip.height / 2; width: dut.x - x; height: 1
        color: wiring.lineColor
    }
    Rectangle {   // tap down to AI 0
        x: ao0Chip.width + 24; y: ao0Chip.y + ao0Chip.height / 2; width: 1; height: ai0Chip.y + ai0Chip.height / 2 - y
        color: wiring.lineColor
    }
    Rectangle {
        x: ai0Chip.width; y: ai0Chip.y + ai0Chip.height / 2; width: 25; height: 1
        color: wiring.lineColor
    }
    Rectangle {
        x: ao0Chip.width + 22; y: ao0Chip.y + ao0Chip.height / 2 - 2; width: 5; height: 5; radius: 2.5
        color: wiring.lineColor
    }
    Rectangle {
        id: dut
        x: 122; y: 4
        width: 84; height: 40
        radius: Theme.radiusControl
        color: "transparent"
        border.width: 1
        border.color: wiring.lineColor
        Text {
            anchors.centerIn: parent
            text: qsTr("Circuit")
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
        }
    }
    Rectangle {   // circuit → AI 1
        x: dut.x + dut.width; y: ao0Chip.y + ao0Chip.height / 2; width: ai1Chip.x - x; height: 1
        color: wiring.lineColor
    }
    Chip { id: ai1Chip; x: 244; y: 12; text: wiring.responseInputName; swatch: wiring.responseInputColor }
}
