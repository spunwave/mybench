import QtQuick
import QtQuick.Templates as T

// On/off switch: a 28×16 track with a round thumb, drawn by MYBENCH under every controls style
// (native styles draw blocky switches). Accent track and light thumb when on, a neutral outlined
// track and a grey thumb when off; never a channel color.
//     ToggleSwitch { text: qsTr("Null offset"); checked: ctl.relative; onToggled: ctl.relative = checked }
T.Switch {
    id: control

    property color accentColor: Theme.accent   // the track when on: the accent, or the signal colour of its card
    property bool labelFirst: false            // legacy, ignored (the label is always on the right)

    implicitWidth: Math.max(implicitBackgroundWidth + leftInset + rightInset,
                            implicitContentWidth + leftPadding + rightPadding)
    implicitHeight: Math.max(implicitBackgroundHeight + topInset + bottomInset,
                             implicitContentHeight + topPadding + bottomPadding,
                             implicitIndicatorHeight + topPadding + bottomPadding)

    padding: 0
    spacing: Theme.spacingS
    hoverEnabled: true
    font.pixelSize: Theme.fontSizeBody

    indicator: Rectangle {
        implicitWidth: 28
        implicitHeight: 16
        x: control.text ? (control.mirrored ? control.width - width - control.rightPadding : control.leftPadding)
                        : control.leftPadding + (control.availableWidth - width) / 2
        y: control.topPadding + (control.availableHeight - height) / 2
        radius: height / 2
        color: control.checked ? (control.down ? Theme.mix(control.accentColor, "#000000", 0.2) : control.hovered ? Theme.mix(control.accentColor, Theme.dark ? "#FFFFFF" : "#000000", 0.12) : control.accentColor)
                               : control.down ? Theme.pressedFill : control.hovered ? Theme.mix(Theme.controlTrack, Theme.text, 0.06) : Theme.controlTrack
        border.width: control.checked ? 0 : Theme.borderWidth
        border.color: Theme.controlBorder
        opacity: control.enabled ? 1 : 0.45
        Behavior on color { ColorAnimation { duration: Theme.durationFast } }

        Rectangle {
            readonly property real inset: control.checked ? 2 : 3
            x: Math.max(inset, Math.min(parent.width - width - inset, control.visualPosition * parent.width - width / 2))
            y: (parent.height - height) / 2
            width: control.checked ? 12 : 10
            height: width
            radius: width / 2
            color: control.checked ? Theme.accentText : Theme.textSecondary
            Behavior on x {
                enabled: !control.down && Theme.animations
                NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing }
            }
        }
        FocusRing { shown: control.visualFocus; radius: height / 2 + 3 }
    }

    contentItem: Text {
        leftPadding: control.indicator && !control.mirrored ? control.indicator.width + control.spacing : 0
        rightPadding: control.indicator && control.mirrored ? control.indicator.width + control.spacing : 0
        text: control.text
        font: control.font
        color: control.enabled ? Theme.text : Theme.textDisabled
        elide: Text.ElideRight
        verticalAlignment: Text.AlignVCenter
    }
}
