pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// An input channel card: on/off switch, Scale, Position, Source and Range rows. Audio sources have
// no range choice (the card states ±2 V AC).
ChannelCard {
    id: card

    required property ScopeController controller
    required property ScopeChannel channel
    required property color channelColor

    // Source entries in ScopeChannel.Source order.
    readonly property var sourceNames: [qsTr("AI 0"), qsTr("AI 1"), qsTr("Audio L"), qsTr("Audio R")]

    objectName: "channelCard" + channel.index
    title: "CH " + channel.index
    // The source shows once: in the Source box while on, here while the card is collapsed.
    subtitle: channel.enabled ? "" : sourceNames[channel.source] ?? ""
    color: channelColor
    checked: channel.enabled
    // Off = header only (the source in the subtitle): the column keeps the trigger in view.
    collapseWhenOff: true
    // The range is shown by the range buttons; audio inputs have none, so it is stated once here.
    facts: channel.audio ? [qsTr("±%1 V · AC").arg(channel.effectiveRange)] : []
    // The controller refuses to switch off the last channel while running.
    onToggled: on => {
        if (!controller.setChannelEnabled(channel.index, on))
            checked = Qt.binding(() => card.channel.enabled)
    }

    KnobField {
        objectName: "scale" + card.channel.index
        Layout.fillWidth: true
        label: qsTr("Scale")
        unit: "V/div"
        compact: card.compact
        values: card.channel.scaleValues
        labels: card.channel.scaleLabels.map(l => l + "/div")
        currentIndex: card.channel.scaleIndex
        onIndexActivated: index => card.channel.scaleIndex = index
    }
    KnobField {
        objectName: "position" + card.channel.index
        Layout.fillWidth: true
        label: qsTr("Position")
        unit: "div"
        compact: card.compact
        from: -5
        to: 5
        stepSize: 0.1
        defaultValue: 0
        digits: 3
        formatter: v => Number(v.toFixed(2)) + " div"
        value: card.channel.position
        toolTip: qsTr("Position (−5 to 5 div)")
        onValueModified: v => card.channel.position = Math.round(v * 100) / 100
    }
    FormRow {
        label: qsTr("Source")
        SegmentedControl {
            objectName: "source" + card.channel.index
            Layout.fillWidth: true
            stretch: true
            compact: true
            model: card.sourceNames.map((name, i) => ({ text: name,
                       toolTip: i >= 2 ? qsTr("Audio · AC, single-ended")
                                       : qsTr("Analog · DC, differential") }))
            currentIndex: card.channel.source
            Accessible.name: qsTr("Channel %1 source").arg(card.channel.index)
            // AI and audio inputs cannot be mixed: the other channel follows (toast).
            onActivated: index => {
                card.controller.setChannelSource(card.channel.index, index)
                currentIndex = Qt.binding(() => card.channel.source)
            }
        }
    }
    FormRow {
        // Audio inputs always use ±2 V: nothing to choose.
        visible: !card.channel.audio
        label: qsTr("Range")
        SegmentedControl {
            objectName: "inputRange" + card.channel.index
            Layout.fillWidth: true
            stretch: true
            compact: true
            // ScopeChannel.InputRange order. Auto: ±10 V from 500 mV/div, ±2 V below (ELVISmx).
            model: [{ text: qsTr("Auto"), toolTip: qsTr("Input range ±%1 V").arg(card.channel.effectiveRange) },
                    { text: "±10", toolTip: qsTr("Input range ±10 V") }, { text: "±2", toolTip: qsTr("Input range ±2 V") }]
            currentIndex: card.channel.inputRange
            onActivated: index => card.channel.inputRange = index
        }
    }
}
