pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Controls

// Vertical mixer fader of the Audio Equalizer, the equalizer's primary control: the typeable value
// (value size) above, a track with a 0 dB detent mark and a cap in the band's colour, the name
// (caption) below. Controlled: bind `value`, handle moved(value). Double-click resets.
// The value field takes a number in the shown unit (`inputScale` converts, e.g. 100 for percent).
//     AeqFader { label: "Bass"; from: -12; to: 12; value: ctl.bass; onMoved: v => ctl.bass = v }
Item {
    id: root

    property string label
    property real from: -12
    property real to: 12
    property real value: 0
    property real stepSize: 1
    property real resetValue: 0
    property color accent: Theme.accent
    property color labelColor: Theme.textSecondary
    property string unitText: "dB"
    // The number in the shown unit; the unit is in the tooltip (the strip is narrow).
    property string valueText: (value > 0 ? "+" : value < 0 ? "−" : "") + Math.abs(value).toFixed(Math.round(Math.abs(value) * 10) % 10 === 0 ? 0 : 1)
    property bool centered: true      // fill from the middle (gains) or from the bottom (volume)
    property real inputScale: 1       // typed number / inputScale = value
    readonly property real travel: track.height

    function commitText(text: string) {
        const v = parseFloat(text.replace("−", "-").replace(",", "."))
        if (isFinite(v))
            root.moved(Math.max(root.from, Math.min(root.to, v / root.inputScale)))
    }

    signal moved(real value)

    implicitWidth: 44
    implicitHeight: 180

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingXs

        TextInput {
            id: valueInput
            objectName: "valueInput"
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.width
            horizontalAlignment: TextInput.AlignHCenter
            text: root.valueText
            color: root.enabled ? Theme.text : Theme.textMuted
            selectionColor: Theme.selection
            selectedTextColor: Theme.selectionText
            selectByMouse: true
            enabled: root.enabled
            font.pixelSize: Theme.fontSizeValue
            font.weight: Font.DemiBold
            font.features: Theme.tabularFigures
            onEditingFinished: {
                root.commitText(text)
                text = Qt.binding(() => root.valueText)
            }
            Rectangle {   // edit underline while typing
                anchors { left: parent.left; right: parent.right; top: parent.bottom }
                height: 1
                visible: valueInput.activeFocus
                color: root.accent
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            // Track.
            Rectangle {
                id: track
                anchors.horizontalCenter: parent.horizontalCenter
                y: handle.height / 2
                width: 6
                height: parent.height - handle.height
                radius: 3
                color: Theme.surfaceSunken
                readonly property real position: (root.value - root.from) / (root.to - root.from)
                readonly property real zero: root.centered ? (0 - root.from) / (root.to - root.from) : 0
                Rectangle {
                    width: parent.width
                    radius: 3
                    y: parent.height * (1 - Math.max(track.position, track.zero))
                    height: parent.height * Math.abs(track.position - track.zero)
                    color: root.enabled ? root.accent : Theme.textDisabled
                }
            }
            // Scale ticks on both sides of the track; the 0 dB detent is a long, bright mark.
            Repeater {
                model: 5
                delegate: Rectangle {
                    required property int index
                    readonly property bool detent: index === 2 && root.centered
                    x: track.x + (track.width - width) / 2
                    y: track.y + track.height * index / 4 - height / 2
                    width: detent ? track.width + 22 : track.width + 10
                    height: detent ? 2 : 1
                    color: detent ? Theme.textSecondary : Theme.textMuted
                    opacity: detent ? 0.9 : 0.5
                }
            }
            // Cap: the band's colour.
            Rectangle {
                id: handle
                anchors.horizontalCenter: parent.horizontalCenter
                y: track.y + track.height * (1 - track.position) - height / 2
                width: 28
                height: 18
                radius: 4
                color: root.enabled ? root.accent : Theme.textDisabled
                border.width: 1
                border.color: dragArea.pressed ? Theme.text : Theme.alpha(Theme.text, 0.35)
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width - 10
                    height: 2
                    radius: 1
                    color: Theme.alpha(Theme.base, 0.75)
                }
            }
            MouseArea {
                id: dragArea
                anchors.fill: parent
                enabled: root.enabled
                preventStealing: true
                function valueAt(y: real): real {
                    const t = 1 - Math.max(0, Math.min(1, (y - track.y) / track.height))
                    const raw = root.from + t * (root.to - root.from)
                    // A detent at the value a double-click restores (3 % of the travel).
                    if (Math.abs(raw - root.resetValue) < 0.03 * Math.abs(root.to - root.from))
                        return root.resetValue
                    return Math.round(raw / root.stepSize) * root.stepSize
                }
                onPressed: mouse => root.moved(valueAt(mouse.y))
                onPositionChanged: mouse => { if (pressed) root.moved(valueAt(mouse.y)) }
                onDoubleClicked: root.moved(root.resetValue)
                onWheel: wheel => root.moved(Math.max(root.from, Math.min(root.to, root.value + (wheel.angleDelta.y > 0 ? 1 : -1) * root.stepSize)))
            }
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: root.label
            color: root.enabled ? Theme.textSecondary : Theme.textDisabled
            font.pixelSize: Theme.fontSizeCaption
        }
    }

    Accessible.role: Accessible.Slider
    Accessible.name: root.label
    activeFocusOnTab: true
    Keys.onUpPressed: root.moved(Math.min(root.to, root.value + root.stepSize))
    Keys.onDownPressed: root.moved(Math.max(root.from, root.value - root.stepSize))
    ToolTip.visible: hover.hovered
    ToolTip.delay: 600
    ToolTip.text: root.label + " · " + root.valueText + (root.unitText.length > 0 ? " " + root.unitText : "")
    HoverHandler { id: hover }
}
