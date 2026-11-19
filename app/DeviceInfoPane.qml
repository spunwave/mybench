import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// The content of the Device Info window: identity, state and capabilities of the current device,
// and which instrument uses which part of it.
Rectangle {
    id: pane

    implicitWidth: 440
    implicitHeight: grid.implicitHeight + 2 * Theme.spacingXl
    color: Theme.window

    component Label: Text {
        Layout.alignment: Qt.AlignTop
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeBody
    }
    component Value: Text {
        Layout.fillWidth: true
        color: Theme.text
        font.pixelSize: Theme.fontSizeBody
        wrapMode: Text.WordWrap
    }

    ResourceChips {
        id: resourceChips
        visible: false
        textForm: true
    }

    GridLayout {
        id: grid
        x: Theme.spacingXl
        y: Theme.spacingXl
        width: pane.width - 2 * Theme.spacingXl
        columns: 2
        columnSpacing: Theme.spacingL
        rowSpacing: Theme.spacingS

        Label { text: qsTr("Name") }
        Value { text: DeviceHub.name || "—" }
        Label { text: qsTr("State") }
        Value {
            text: DeviceHub.connectionState === DeviceHub.Connected ? qsTr("Connected")
                : DeviceHub.connectionState === DeviceHub.Resetting ? qsTr("Resetting…")
                : DeviceHub.connectionState === DeviceHub.Disconnected ? qsTr("Disconnected") : qsTr("No device")
        }
        Label { text: qsTr("Product") }
        Value { text: DeviceHub.productType || "—" }
        Label { text: qsTr("Serial number") }
        Value { text: DeviceHub.serialNumber || "—"; font.family: Theme.monoFamily }
        Label { text: qsTr("Device id") }
        Value { text: DeviceHub.currentId || "—"; font.family: Theme.monoFamily }
        Label { text: qsTr("Connection") }
        Value { text: DeviceHub.simulated ? qsTr("Simulated") : (DeviceHub.backend || "—") }
        Label { text: qsTr("Analog input") }
        Value {
            text: DeviceHub.maxAiRate > 0 ? qsTr("%1 per channel").arg(Units.format(DeviceHub.maxAiRate, "S/s")) : "—"
            font.features: Theme.tabularFigures
        }
        Label { text: qsTr("Analog output") }
        Value {
            text: DeviceHub.maxAoRate > 0 ? qsTr("%1 per channel").arg(Units.format(DeviceHub.maxAoRate, "S/s")) : "—"
            font.features: Theme.tabularFigures
        }
        Label { text: qsTr("In use") }
        Value { text: resourceChips.summaryText.length > 0 ? resourceChips.summaryText : qsTr("Nothing") }

        // Self-test (read-only, like NI MAX's): stops the instruments, checks that every part answers.
        Label { text: qsTr("Self-test") }
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.spacingS
            Button {
                objectName: "deviceInfoSelfTest"
                text: DeviceHub.selfTesting ? qsTr("Testing…") : qsTr("Run Self-Test")
                enabled: DeviceHub.connected && !DeviceHub.selfTesting && !DeviceHub.resetting
                onClicked: DeviceHub.selfTest()
            }
            Value {
                visible: DeviceHub.selfTestChecks.length > 0 && !DeviceHub.selfTesting
                text: DeviceHub.selfTestChecks.every(c => c.ok) ? qsTr("Passed") : qsTr("Failed")
                color: DeviceHub.selfTestChecks.every(c => c.ok) ? Theme.positive : Theme.negative
            }
        }
        Repeater {
            model: DeviceHub.selfTesting ? [] : DeviceHub.selfTestChecks
            delegate: Value {
                required property var modelData
                Layout.columnSpan: 2
                objectName: "deviceInfoSelfTestCheck"
                text: (modelData.ok ? "✓ " : "✗ ") + modelData.name + ": " + modelData.detail
                color: modelData.ok ? Theme.text : Theme.negative
            }
        }
    }
}
