pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework

// Run bar of an instrument panel (legacy; the pane header replaces it): Run/Stop toggle, Single
// (Run Once), status (running, waiting, paused, error), optional timeout LED, and panel actions on
// the right.
Rectangle {
    id: root

    property InstrumentController controller: null
    property string runText: qsTr("Run")
    property string stopText: qsTr("Stop")
    property string resumeText: qsTr("Resume")
    property string singleText: qsTr("Single")
    property string singleIcon: "step"
    property string singleToolTip: qsTr("Acquire once, then stop")
    property bool showSingle: controller ? controller.supportsSingle : true
    // Single allowed right now (InstrumentController.singleEnabled; override to add conditions).
    property bool singleEnabled: controller ? controller.singleEnabled : true
    // Idle instrument still driving outputs (InstrumentController.holdsOutputs): a button returns
    // them to their safe state (the same as Stop / Shift+F5).
    property bool showRelease: controller !== null && controller.holdsOutputs && !running
    property string releaseText: qsTr("Release Outputs")
    property string releaseToolTip: qsTr("Safe state: AO 0 V, digital lines as inputs")
    property bool showTimeout: false
    property string timeoutText: qsTr("Timeout")
    property bool showRate: true
    default property alias actions: actionsRow.data
    property alias extraControls: extraRow.data

    // Narrow panels (split panes): icon-only Single, no rate text, LED-only timeout.
    readonly property bool compact: width < 640
    readonly property bool running: controller !== null && controller.running
    readonly property bool paused: controller !== null && controller.paused
    readonly property string statusText: {
        const c = controller
        if (!c)
            return ""
        switch (c.state) {
        case InstrumentController.Starting:
            return qsTr("Starting")
        case InstrumentController.Stopping:
            return qsTr("Stopping")
        case InstrumentController.Running:
            return c.statusText.length > 0 ? c.statusText
                 : c.runMode === InstrumentController.Once ? qsTr("Single") : qsTr("Running")
        case InstrumentController.Paused:
            return c.pauseReason
        default:
            if (c.hasError)
                return c.errorText
            if (c.inputWarning.length > 0)
                return c.inputWarning
            if (!DeviceHub.connected)
                return qsTr("No device")
            return c.statusText.length > 0 ? c.statusText : c.hasData ? qsTr("Stopped") : qsTr("Ready")
        }
    }
    readonly property color statusColor: {
        const c = controller
        if (!c)
            return Theme.textMuted
        if (c.state === InstrumentController.Running || c.state === InstrumentController.Starting)
            return Theme.success
        if (c.paused)
            return Theme.warning
        if (c.hasError)
            return Theme.danger
        if (c.inputWarning.length > 0)
            return Theme.warning
        return Theme.textMuted
    }
    readonly property bool statusHighlighted: controller !== null
                                              && (controller.hasError || controller.paused
                                                  || (!running && controller.inputWarning.length > 0))

    implicitHeight: Theme.paneHeaderHeight
    color: Theme.surface

    Divider {
        anchors.top: parent.top
        width: parent.width
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Theme.spacingM
        anchors.rightMargin: Theme.spacingM
        spacing: Theme.spacingS + 2

        RunButton {
            id: runButton
            running: root.running
            runText: root.paused ? root.resumeText : root.runText
            stopText: root.stopText
            widthText: root.resumeText
            busy: root.controller !== null && root.controller.state === InstrumentController.Stopping
            enabled: root.controller !== null && (root.running ? root.controller.state !== InstrumentController.Stopping
                                                              : root.controller.canRun)
            shortcutText: Theme.keys("Space")
            onToggled: root.controller.toggle()
        }

        ActionButton {
            visible: root.showSingle
            text: root.compact ? "" : root.singleText
            iconName: root.singleIcon
            toolTip: root.singleToolTip
            enabled: root.controller !== null && root.singleEnabled
                     && (root.controller.canRun
                         || (root.controller.state === InstrumentController.Running
                             && root.controller.runMode === InstrumentController.Continuous))
            onClicked: root.controller.runOnce()
        }

        ActionButton {
            objectName: "releaseButton"
            visible: root.showRelease
            text: root.compact ? "" : root.releaseText
            iconName: "stop-filled"
            tone: "subtle"
            color: Theme.negative
            toolTip: root.releaseToolTip
            onClicked: root.controller.returnToSafeState()
        }

        Row {
            id: extraRow
            spacing: Theme.spacingS
            Layout.alignment: Qt.AlignVCenter
        }

        Divider {
            vertical: true
            length: 24
            Layout.leftMargin: Theme.spacingXs
            Layout.rightMargin: Theme.spacingXs
        }

        StatusDot {
            color: root.statusColor
            pulse: root.controller !== null && root.controller.state === InstrumentController.Running
        }
        Text {
            Layout.fillWidth: true
            Layout.minimumWidth: 60
            text: root.statusText
            color: root.statusHighlighted ? root.statusColor : Theme.textSecondary
            font.pixelSize: Theme.fontSizeBody
            elide: Text.ElideRight
        }
        Text {
            visible: root.showRate && !root.compact && root.running && root.controller.sampleRate > 0
            text: Units.format(root.controller ? root.controller.sampleRate : 0, "S/s", 4)
            color: Theme.textMuted
            font.pixelSize: Theme.fontSizeM
            font.features: Theme.tabularFigures
        }
        Led {
            visible: root.showTimeout
            on: root.controller !== null && root.controller.timedOut
            color: Theme.warning
            text: root.compact ? "" : root.timeoutText
            ToolTip.visible: timeoutHover.hovered
            ToolTip.text: root.timeoutText
            HoverHandler { id: timeoutHover }
        }

        Row {
            id: actionsRow
            spacing: Theme.spacingXs
            Layout.alignment: Qt.AlignVCenter
        }
    }
}
