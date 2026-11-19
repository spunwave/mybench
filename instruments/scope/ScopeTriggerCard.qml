pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// The trigger card: type (Immediate | Edge), and for Edge the mode, source with slope, and level.
// The sliders button unfolds the less used settings (timeout, holdoff, hysteresis).
ChannelCard {
    id: card

    required property ScopeController controller
    // The colors of the trace choices (the display's trace colors).
    property color ch0Color: Theme.signalCh0
    property color ch1Color: Theme.signalCh1
    property bool advanced: false

    readonly property bool edge: controller.triggerType === ScopeController.Edge
    // The edge settings apply (Roll is untriggered: they are hidden while it rolls).
    readonly property bool edgeShown: edge && !controller.rolling
    readonly property int source: controller.triggerSource === ScopeController.Chan1Source ? 1 : 0
    readonly property ScopeChannel sourceChannel: source === 1 ? controller.channel1 : controller.channel0
    readonly property color sourceColor: source === 1 ? ch1Color : ch0Color

    objectName: "triggerCard"
    title: qsTr("Trigger")
    subtitle: controller.rolling ? qsTr("Roll") : ""
    checkable: false
    color: edge ? sourceColor : "transparent"      // the card follows the signal it triggers on

    headerExtras: [
        IconButton {
            objectName: "triggerAdvancedButton"
            visible: card.edgeShown
            iconName: "sliders"
            size: Theme.controlHeightS
            iconSize: 14
            checked: card.advanced
            toolTip: card.advanced ? qsTr("Hide") : qsTr("Timeout, holdoff, hysteresis")
            onClicked: card.advanced = !card.advanced
        }
    ]

    // Type: picture buttons (free running | edge).
    RowLayout {
        Layout.fillWidth: true
        spacing: Theme.spacingXs
        PictureButton {
            objectName: "triggerTypeImmediate"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            inline: card.dense       // one row in the dock
            text: qsTr("Immediate")
            // A free-running wave, no trigger mark.
            glyph: "M2 9 C5 2 8 2 11 9 S17 16 20 9 M22 9 H30 M27 6 L30 9 L27 12"
            checked: !card.edge
            ToolTip.visible: hovered
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: qsTr("Every record shown")
            onClicked: card.controller.triggerType = ScopeController.Immediate
        }
        PictureButton {
            objectName: "triggerTypeEdge"
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            inline: card.dense
            text: qsTr("Edge")
            // A step crossing the level line.
            glyph: "M2 15 H12 L18 3 H30 M6 9 H26"
            checked: card.edge
            ToolTip.visible: hovered
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: qsTr("Starts at the level crossing")
            onClicked: card.controller.triggerType = ScopeController.Edge
        }
    }

    FormRow {
        visible: card.edgeShown
        label: qsTr("Mode")
        SegmentedControl {
            objectName: "triggerMode"
            Layout.fillWidth: true
            stretch: true
            compact: true
            // Auto: shows the untriggered record after the timeout; Normal: waits (the last trace stays).
            model: [{ text: qsTr("Auto"), toolTip: qsTr("Untriggered after the timeout") },
                    { text: qsTr("Normal"), toolTip: qsTr("Waits for an edge") }]
            currentIndex: card.controller.noTriggerMode === ScopeController.ShowUntriggered ? 0 : 1
            onActivated: index => {
                if (index === 0)
                    card.controller.noTriggerMode = ScopeController.ShowUntriggered
                else if (card.controller.noTriggerMode === ScopeController.ShowUntriggered)
                    card.controller.noTriggerMode = ScopeController.KeepLastTrace
            }
        }
    }

    FormRow {
        visible: card.edgeShown
        label: qsTr("Source")
        SegmentedControl {
            objectName: "triggerSource"
            Layout.fillWidth: true
            stretch: true
            compact: true
            // A channel that is off cannot trigger.
            model: [{ text: "CH0", color: card.ch0Color, enabled: card.controller.channel0.enabled,
                      toolTip: card.controller.channel0.enabled ? qsTr("Trigger on channel 0") : qsTr("Channel 0 off") },
                    { text: "CH1", color: card.ch1Color, enabled: card.controller.channel1.enabled,
                      toolTip: card.controller.channel1.enabled ? qsTr("Trigger on channel 1") : qsTr("Channel 1 off") }]
            currentIndex: card.source
            onActivated: index => card.controller.triggerSource = index
        }
    }
    FormRow {
        visible: card.edgeShown
        label: qsTr("Slope")
        SegmentedControl {
            objectName: "triggerSlope"
            Layout.fillWidth: true
            stretch: true
            compact: true
            model: [{ icon: "slope-rising", toolTip: qsTr("Rising edge") },
                    { icon: "slope-falling", toolTip: qsTr("Falling edge") }]
            currentIndex: card.controller.triggerSlope
            onActivated: index => card.controller.triggerSlope = index
        }
    }

    KnobField {
        objectName: "triggerLevel"
        Layout.fillWidth: true
        visible: card.edgeShown
        // The knob covers ±5 div of the source channel; typing takes −100…100 V.
        readonly property real span: 5 * card.sourceChannel.voltsPerDiv
        label: qsTr("Level")
        unit: "V"
        compact: card.compact
        from: -span
        to: span
        stepSize: span / 50
        defaultValue: 0
        value: card.controller.triggerLevel
        toolTip: qsTr("−100 to 100 V")
        onValueModified: v => card.controller.triggerLevel = Math.max(-100, Math.min(100, Number(v.toPrecision(4))))
    }

    // The less used settings (sliders button in the header).
    FormRow {
        visible: card.edgeShown && card.advanced
        label: qsTr("Timeout")
        StepSelector {
            objectName: "triggerTimeout"
            readonly property var values: [0.1, 0.25, 0.5, 1, 2, 5, 10, 0]
            Layout.fillWidth: true
            label: qsTr("Trigger timeout")
            model: values.map(v => ({ value: v, text: v === 0 ? qsTr("Never") : Units.format(v, "s", 3) }))
            currentIndex: Math.max(0, values.indexOf(card.controller.triggerTimeout))
            onActivated: index => card.controller.triggerTimeout = values[index]
        }
    }
    FormRow {
        visible: card.edgeShown && card.advanced
        label: qsTr("Holdoff")
        SiField {
            objectName: "triggerHoldoff"
            Layout.fillWidth: true
            label: qsTr("Holdoff")
            unit: "s"
            from: 0
            to: 10
            stepSize: 0.01
            digits: 3
            value: card.controller.triggerHoldoff
            toolTip: qsTr("Holdoff (0 to 10 s)")
            onValueModified: v => card.controller.triggerHoldoff = v
        }
    }
    FormRow {
        visible: card.edgeShown && card.advanced
        label: qsTr("Hysteresis")
        SiField {
            objectName: "triggerHysteresis"
            Layout.fillWidth: true
            label: qsTr("Hysteresis")
            engineering: false
            decimals: 2
            unit: "div"
            from: 0
            to: 2
            stepSize: 0.05
            value: card.controller.triggerHysteresis
            toolTip: qsTr("Hysteresis (0 to 2 div)")
            onValueModified: v => card.controller.triggerHysteresis = v
        }
    }
    ToggleSwitch {
        objectName: "triggerClear"
        visible: card.edgeShown && card.advanced && card.controller.noTriggerMode !== ScopeController.ShowUntriggered
        text: qsTr("Clear while waiting")
        checked: card.controller.noTriggerMode === ScopeController.ClearGraph
        onToggled: card.controller.noTriggerMode = checked ? ScopeController.ClearGraph : ScopeController.KeepLastTrace
    }
}
