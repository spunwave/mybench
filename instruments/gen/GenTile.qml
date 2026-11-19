pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Overview tile (content only): one block per channel (waveform pictogram, frequency or level,
// amplitude) and mini previews of the outputs. A channel that does not output is dimmed.
Item {
    id: root

    required property GenController controller

    function channelColor(channel: GenChannel): color {
        return channel.index === 0 ? Theme.signalAo0 : Theme.signalAo1   // as the channel cards
    }
    function live(channel: GenChannel): bool {
        return channel.state === GenChannel.Running || channel.state === GenChannel.Sweeping
    }
    function icon(channel: GenChannel): string {
        return channel.mode === GenChannel.Dc ? "wave-dc"
             : channel.mode === GenChannel.Arbitrary ? "wave-arbitrary"
             : channel.shape === GenChannel.Triangle ? "wave-triangle"
             : channel.shape === GenChannel.Square ? "wave-square" : "wave-sine"
    }
    function primary(channel: GenChannel): string {
        return channel.mode === GenChannel.Function ? Units.format(channel.frequency, "Hz", 4)
             : channel.mode === GenChannel.Dc ? Units.format(channel.dcLevel, "V", 3)
             : channel.mode === GenChannel.Arbitrary ? (channel.hasWaveform ? Units.format(channel.updateRate, "S/s", 3) : "—")
             : qsTr("Off")
    }
    function secondary(channel: GenChannel): string {
        return channel.mode === GenChannel.Function ? Units.format(channel.amplitude, "Vpp", 3)
             : channel.mode === GenChannel.Arbitrary && channel.hasWaveform ? channel.waveformName : ""
    }
    readonly property bool anyOutput: controller.channel0.mode !== GenChannel.Off || controller.channel1.mode !== GenChannel.Off

    // One channel: swatch and name, the pictogram and the large value, the amplitude.
    component ChannelBlock: Item {
        id: block
        required property GenChannel channel
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: column.implicitHeight
        implicitHeight: column.implicitHeight
        readonly property bool off: channel.mode === GenChannel.Off
        readonly property bool tight: parent && parent.tight === true
        Column {
            id: column
            width: parent.width
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            Item {
                width: parent.width
                height: nameRow.implicitHeight
                Row {
                    id: nameRow
                    spacing: Theme.spacingXs + 2
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8; height: 8; radius: 2
                        color: root.channelColor(block.channel)
                    }
                    Text {
                        text: block.channel.audio ? (block.channel.index === 0 ? qsTr("Left") : qsTr("Right")) : block.channel.name
                        color: Theme.textSecondary
                        font.pixelSize: Theme.fontSizeSmall
                    }
                }
                // Short tile: the amplitude on the name's line.
                Text {
                    visible: block.tight
                    anchors.right: parent.right
                    text: root.secondary(block.channel)
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeSmall
                    font.features: Theme.tabularFigures
                }
            }
            Row {
                width: parent.width
                spacing: Theme.spacingS
                opacity: root.live(block.channel) || !root.controller.running && !block.off ? 1 : 0.5
                Icon {
                    visible: !block.off
                    anchors.verticalCenter: parent.verticalCenter
                    name: root.icon(block.channel)
                    size: Theme.iconSizeXL
                    color: Theme.text
                }
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - (block.off ? 0 : Theme.iconSizeXL + Theme.spacingS)
                    text: root.primary(block.channel)
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeReadoutM
                    font.weight: Font.DemiBold
                    font.features: Theme.tabularFigures
                    fontSizeMode: Text.Fit
                    minimumPixelSize: Theme.fontSizeSmall
                    elide: Text.ElideRight
                }
            }
            // Kept (empty) when there is no second line, so both blocks' values line up.
            Text {
                visible: !block.tight
                width: parent.width
                text: root.secondary(block.channel)
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
                font.features: Theme.tabularFigures
                elide: Text.ElideRight
            }
        }
    }

    TileBody {
        anchors.fill: parent
        screenShown: root.controller.running && root.anyOutput

        ChannelBlock { channel: root.controller.channel0 }
        ChannelBlock { channel: root.controller.channel1 }

        screen: ColumnLayout {
            anchors.fill: parent
            spacing: Theme.spacingXs
            Repeater {
                model: [root.controller.channel0, root.controller.channel1]
                delegate: BenchPlot {
                    id: mini
                    required property GenChannel modelData
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: modelData.mode !== GenChannel.Off
                    bare: true
                    placeholderText: ""
                    xAxis { min: 0; max: mini.modelData.previewSpan; labelsVisible: false; gridVisible: false }
                    yAxis { min: mini.modelData.previewMin; max: mini.modelData.previewMax; labelsVisible: false; gridVisible: false }
                    PlotTrace {
                        buffer: mini.modelData.preview
                        color: root.channelColor(mini.modelData)
                        width: 1.5
                        step: mini.modelData.previewStep
                    }
                }
            }
        }
    }
}
