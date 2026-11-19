pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// Content of the Sweep tool panel: per Function channel the sweep settings (start, stop, step, step
// interval) and Start Sweep / Stop, with the step progress.
ColumnLayout {
    id: root

    required property GenController controller

    spacing: Theme.spacingM

    Text {
        visible: !root.controller.anyFunction
        Layout.fillWidth: true
        text: qsTr("No function output")
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSizeBody
        ToolTip.visible: noFunctionHover.hovered
        ToolTip.text: qsTr("Needs Sine, Square or Triangle")
        HoverHandler { id: noFunctionHover }
    }

    Repeater {
        model: [root.controller.channel0, root.controller.channel1]
        delegate: GenToolSection {
            id: block
            required property GenChannel modelData
            required property int index
            visible: modelData.mode === GenChannel.Function
            title: modelData.name
            color: modelData.index === 0 ? Theme.signalAo0 : Theme.signalAo1
            separatorSide: index === 0 && root.controller.channel1.mode === GenChannel.Function ? "bottom" : "none"
            collapseWhenOff: false

            FormRow {
                label: qsTr("Start")
                enabled: !block.modelData.sweeping
                SiField {
                    objectName: "sweepStart" + block.modelData.index
                    Layout.fillWidth: true
                    unit: "Hz"; from: 0.2; to: 20000; digits: 5
                    value: block.modelData.sweepStart
                    onValueModified: v => block.modelData.sweepStart = v
                }
            }
            FormRow {
                label: qsTr("Stop")
                enabled: !block.modelData.sweeping
                SiField {
                    objectName: "sweepStop" + block.modelData.index
                    Layout.fillWidth: true
                    unit: "Hz"; from: 0.2; to: 20000; digits: 5
                    value: block.modelData.sweepStop
                    onValueModified: v => block.modelData.sweepStop = v
                }
            }
            FormRow {
                label: qsTr("Step")
                enabled: !block.modelData.sweeping
                SiField {
                    objectName: "sweepStep" + block.modelData.index
                    Layout.fillWidth: true
                    unit: "Hz"; from: 0; to: 20000; digits: 5
                    value: block.modelData.sweepStep
                    onValueModified: v => block.modelData.sweepStep = v
                }
            }
            FormRow {
                label: qsTr("Interval")
                hint: qsTr("Interval")
                enabled: !block.modelData.sweeping
                SiField {
                    objectName: "sweepInterval" + block.modelData.index
                    Layout.fillWidth: true
                    unit: "ms"; engineering: false; decimals: 0; stepSize: 1; from: 1; to: 300000
                    value: block.modelData.sweepInterval
                    onValueModified: v => block.modelData.sweepInterval = v
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS
                Button {
                    objectName: "startSweep" + block.modelData.index
                    text: block.modelData.sweeping ? qsTr("Stop Sweep") : qsTr("Start Sweep")
                    icon.source: Theme.icon(block.modelData.sweeping ? "stop" : "sweep")
                    highlighted: !block.modelData.sweeping
                    // A sweep starts from a stopped channel.
                    enabled: block.modelData.sweeping || !block.modelData.generating
                    ToolTip.visible: hovered && !enabled
                    ToolTip.text: qsTr("%1 is on").arg(block.modelData.name)
                    onClicked: block.modelData.sweeping ? root.controller.setOutput(block.modelData.index, false)
                                                        : root.controller.startSweep(block.modelData.index)
                }
                ProgressBar {
                    visible: block.modelData.sweeping
                    Layout.fillWidth: true
                    from: 0
                    to: 1
                    value: block.modelData.sweepProgress
                }
                Text {
                    visible: block.modelData.sweeping
                    text: qsTr("%1 / %2").arg(block.modelData.sweepStepIndex).arg(block.modelData.sweepStepCount)
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    font.features: Theme.tabularFigures
                }
            }
        }
    }
}
