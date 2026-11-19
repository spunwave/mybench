pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// One DIO line in the line strip: the line number, its state (a lamp in the direction's colour and
// High / Low; an output's is a button that flips the line in the Manual pattern) and the direction
// as two icon buttons (clicking the active one frees the line). A lock icon marks a line another
// instrument holds; a warning icon marks an output whose readback differs.
Item {
    id: root

    required property DioController controller
    required property int line
    // Direction colours, shared with the panel (lamps, lanes).
    property color inputColor: Theme.signalCh0
    property color outputColor: Theme.signalAo0
    property bool lastColumn: false
    // A short display: the lamp and the word sit side by side, so the strip leaves the timeline its room.
    property bool compact: false

    readonly property string assets: "qrc:/qt/qml/MyBench/Instruments/Dio/assets/"
    readonly property int direction: (controller.outputMask >> line) & 1 ? DioController.Out
                                   : (controller.inputMask >> line) & 1 ? DioController.In : DioController.Unused
    readonly property bool isOut: direction === DioController.Out
    readonly property bool isIn: direction === DioController.In
    readonly property color stateColor: isOut ? outputColor : isIn ? inputColor : Theme.textTertiary
    // OUT: while running the written level (ELVISmx semantics); stopped in the Manual pattern the
    // value Run will write (so a click shows at once); IN: the level read (none before the first
    // reading); unused: no state.
    readonly property bool showsWritten: controller.hasWritten && (controller.running || controller.pattern !== DioController.Manual)
    readonly property bool known: isOut || (isIn && controller.hasReading)
    readonly property bool level: isOut ? (showsWritten ? (controller.writtenLevels >> line) & 1
                                                        : controller.pattern === DioController.Manual && ((controller.manualValue >> Math.max(0, bitIndex)) & 1))
                                : isIn ? (controller.lineStates >> line) & 1 : false
    readonly property bool togglable: isOut && controller.pattern === DioController.Manual
    readonly property var owner: controller.lineOwners[line] ?? ({})
    readonly property bool owned: (owner.owner ?? "").length > 0
    readonly property bool conflict: owned && owner.active && direction !== DioController.Unused
    readonly property bool readbackError: (controller.readbackErrors >> line) & 1
    readonly property string label: controller.lineLabels[line] ?? ""
    // The state Run will write, lighter than a level on the pin.
    readonly property bool pending: isOut && !controller.running
    readonly property bool on: known && level

    // The cell's click: flips an output line (Manual pattern; the controller ignores others).
    function activate() {
        root.controller.toggleLine(root.line)
    }

    implicitWidth: 54
    implicitHeight: compact ? 72 : 82
    Accessible.role: Accessible.Grouping
    Accessible.name: qsTr("DIO %1").arg(line)

    ColumnLayout {
        anchors { fill: parent; leftMargin: 4; rightMargin: 4; topMargin: 3; bottomMargin: 3 }
        spacing: 3

        // The line number, with the lock / readback warning at the cell's edges.
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: numberText.implicitHeight
            Text {
                id: numberText
                anchors.centerIn: parent
                text: root.line
                color: root.direction === DioController.Unused ? Theme.textSecondary : Theme.text
                font.pixelSize: Theme.fontSizeHeading
                font.weight: Font.DemiBold
                font.features: Theme.tabularFigures
                HoverHandler { id: nameHover }
                ToolTip.visible: nameHover.hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: root.label.length > 0 ? qsTr("DIO %1 · %2").arg(root.line).arg(root.label) : qsTr("DIO %1").arg(root.line)
            }
            Icon {
                objectName: "dioLock" + root.line
                visible: root.owned
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                name: root.assets + "dio-lock.svg"
                size: Theme.iconSizeS
                color: root.conflict ? Theme.caution : Theme.textTertiary
                HoverHandler { id: lockHover }
                ToolTip.visible: lockHover.hovered
                ToolTip.delay: Theme.toolTipDelay
                ToolTip.text: root.conflict ? qsTr("Pauses %1").arg(root.owner.owner)
                                            : (root.owner.text ?? "").length > 0 ? root.owner.text : root.owner.owner
            }
            Icon {
                objectName: "dioReadback" + root.line
                visible: root.readbackError
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                name: "warning"
                size: Theme.iconSizeS
                color: Theme.caution
                HoverHandler { id: warningHover }
                ToolTip.visible: warningHover.hovered
                ToolTip.text: qsTr("DIO %1 reads %2, driven %3").arg(root.line)
                                  .arg(root.level ? qsTr("low") : qsTr("high")).arg(root.level ? qsTr("high") : qsTr("low"))
            }
        }

        // The state: a lamp in the direction's colour (filled when High) and the word.
        Rectangle {
            id: stateBox
            objectName: "dioState" + root.line
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: root.compact ? 20 : 30
            radius: Theme.radiusControl
            color: root.togglable && stateArea.containsMouse ? Theme.hoverFill
                 : root.on ? Theme.tint(root.stateColor) : "transparent"
            border.width: 1
            border.color: root.on ? root.stateColor : root.togglable ? Theme.controlBorder : Theme.separator

            Grid {
                anchors.centerIn: parent
                columns: root.compact ? 2 : 1
                spacing: root.compact ? 4 : 2
                verticalItemAlignment: Grid.AlignVCenter
                horizontalItemAlignment: Grid.AlignHCenter
                Rectangle {
                    width: 12
                    height: 12
                    radius: 6
                    color: root.on ? root.stateColor : "transparent"
                    border.width: root.on ? 0 : 2
                    border.color: root.known ? Theme.alpha(root.stateColor, 0.6) : Theme.textDisabled
                    opacity: root.on && root.pending ? 0.65 : 1
                }
                Text {
                    text: root.direction === DioController.Unused || !root.known ? "—" : root.level ? qsTr("High") : qsTr("Low")
                    color: !root.known ? Theme.textTertiary : root.level ? Theme.text : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: root.level ? Font.DemiBold : Font.Normal
                }
            }
            MouseArea {
                id: stateArea
                anchors.fill: parent
                enabled: root.isOut
                hoverEnabled: true
                cursorShape: root.togglable ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.activate()
                ToolTip.visible: containsMouse
                ToolTip.delay: 600
                ToolTip.text: root.togglable ? qsTr("Set DIO %1 %2 · key %1").arg(root.line).arg(root.level ? qsTr("Low") : qsTr("High"))
                                             : qsTr("Manual pattern only")
            }
            Accessible.role: root.isOut ? Accessible.Button : Accessible.StaticText
            Accessible.name: qsTr("DIO %1 %2").arg(root.line).arg(root.level ? qsTr("high") : qsTr("low"))
        }

        // Direction: input | output. Clicking the active one frees the line (unused).
        Row {
            Layout.fillWidth: true
            Layout.preferredHeight: 22
            spacing: 2
            Repeater {
                model: [{ out: false, icon: "dio-in.svg", name: qsTr("Input") },
                        { out: true, icon: "dio-out.svg", name: qsTr("Output") }]
                delegate: Rectangle {
                    id: dirButton
                    required property var modelData
                    required property int index
                    objectName: "dioDirection" + root.line + (modelData.out ? "Out" : "In")
                    readonly property bool active: modelData.out ? root.isOut : root.isIn
                    readonly property color ink: modelData.out ? root.outputColor : root.inputColor
                    width: (parent.width - parent.spacing) / 2
                    height: parent.height
                    radius: Theme.radiusControl
                    color: active ? Theme.tint(ink) : dirArea.containsMouse ? Theme.hoverFill : "transparent"
                    border.width: 1
                    border.color: active ? ink : Theme.separator
                    Icon {
                        anchors.centerIn: parent
                        name: root.assets + dirButton.modelData.icon
                        size: Theme.iconSize
                        color: dirButton.active ? dirButton.ink : Theme.textSecondary
                    }
                    MouseArea {
                        id: dirArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.controller.setLineDirection(root.line, dirButton.active ? DioController.Unused
                                                                              : dirButton.modelData.out ? DioController.Out : DioController.In)
                        ToolTip.visible: containsMouse
                        ToolTip.delay: Theme.toolTipDelay
                        ToolTip.text: dirButton.active ? qsTr("%1 · click to free").arg(dirButton.modelData.name)
                                                       : dirButton.modelData.name
                    }
                    Accessible.role: Accessible.RadioButton
                    Accessible.checked: active
                    Accessible.name: dirButton.modelData.name
                }
            }
        }
    }

    Rectangle {
        visible: !root.lastColumn
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: 1
        color: Theme.separator
    }

    // Bit of this line in the right-justified output value.
    readonly property int bitIndex: {
        let bit = 0
        for (let l = 0; l < root.line; ++l)
            if ((controller.outputMask >> l) & 1)
                ++bit
        return (controller.outputMask >> root.line) & 1 ? bit : -1
    }
}
