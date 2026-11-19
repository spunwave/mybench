import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T

// The instrument's Run / Stop toggle: one line at Theme.controlHeight and a fixed width, so the row
// does not shift between the two states. Stopped: green fill "▶ Run" (or the instrument's verb,
// `runText`). Running: red fill, "■ Stop". The state text belongs to the pane header; `stateText` is
// only the accessible description. `busy` dims it and ignores clicks. Emits toggled(); the owner
// starts or stops the instrument and binds `running`.
//     RunButton { running: ctl.running; onToggled: ctl.running ? ctl.stop() : ctl.start() }
T.AbstractButton {
    id: control

    property bool running: false
    property string stateText               // accessible description only
    property bool busy: false
    property string runText: qsTr("Run")
    property string stopText: qsTr("Stop")
    property string shortcutText            // shown in the tooltip, e.g. "⌘R"
    property string widthText               // another label (Resume) the fixed width must hold

    readonly property real glyphSize: 14
    readonly property real labelWidth: Math.ceil(Math.max(runMetrics.advanceWidth, stopMetrics.advanceWidth,
                                                          hintMetrics.advanceWidth))

    implicitWidth: Math.max(104, 2 * Theme.spacingM + glyphSize + Theme.spacingS + labelWidth)
    implicitHeight: Theme.controlHeight
    focusPolicy: Qt.StrongFocus
    hoverEnabled: true
    checkable: false
    Accessible.role: Accessible.Button
    Accessible.name: running ? stopText : runText
    Accessible.description: stateText
    Accessible.checkable: true
    Accessible.checked: running

    onClicked: {
        if (!busy)
            control.toggled()
    }
    Keys.onReturnPressed: control.click()
    Keys.onEnterPressed: control.click()

    TextMetrics {
        id: runMetrics
        font: label.font
        text: control.runText
    }
    TextMetrics {
        id: stopMetrics
        font: label.font
        text: control.stopText
    }

    TextMetrics {
        id: hintMetrics
        font: label.font
        text: control.widthText
    }

    readonly property color baseFill: running ? Theme.stopFill : Theme.runFill
    readonly property color fill: down ? Theme.mix(baseFill, "#000000", 0.18)
                                : hovered ? Theme.mix(baseFill, "#FFFFFF", 0.10) : baseFill
    readonly property color ink: "#FFFFFF"

    background: Rectangle {
        radius: Theme.radiusControl
        color: control.fill
        opacity: control.busy || !control.enabled ? 0.55 : 1
        FocusRing { shown: control.visualFocus }
    }

    contentItem: Item {
        Row {
            anchors.centerIn: parent
            spacing: Theme.spacingS
            Item {
                width: control.glyphSize
                height: control.glyphSize
                anchors.verticalCenter: parent.verticalCenter
                Rectangle {
                    visible: control.running
                    anchors.fill: parent
                    radius: 1.5
                    color: control.ink
                }
                Canvas {
                    visible: !control.running
                    anchors.fill: parent
                    property color ink: control.ink
                    onInkChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.fillStyle = ink
                        ctx.beginPath()
                        ctx.moveTo(1, 0)
                        ctx.lineTo(width, height / 2)
                        ctx.lineTo(1, height)
                        ctx.closePath()
                        ctx.fill()
                    }
                }
            }
            Text {
                id: label
                anchors.verticalCenter: parent.verticalCenter
                text: control.running ? control.stopText : control.runText
                color: control.ink
                font.pixelSize: Theme.fontSizeValue
                font.weight: Font.DemiBold
            }
        }
    }

    ToolTip.visible: hovered && ToolTip.text.length > 0
    ToolTip.delay: Theme.toolTipDelay
    ToolTip.text: shortcutText.length > 0 ? (running ? stopText : runText) + "  " + shortcutText : ""
}
