import QtQuick
import QtQuick.Controls

// Little up / down arrows in place of a scroll bar: shown only where `flickable` has more content
// in that direction, each a small round button that moves it by `step` (default: most of a view).
// The wheel and touchpad still scroll the flickable. Put it over the area the arrows belong to;
// `stacked` puts both arrows at the top (a narrow rail), the one with nowhere to go dimmed.
//     ScrollArrows { anchors.fill: flick; flickable: flick }
//     ScrollArrows { flickable: stripFlick; step: cellHeight; stacked: true; arrowSize: 13 }
Item {
    id: root

    required property Flickable flickable
    property real step: Math.max(24, Math.round(flickable.height * 0.8))
    property real inset: 4
    property bool atRight: false
    property bool stacked: false
    property real arrowSize: 22
    readonly property real maxY: Math.max(0, flickable.contentHeight - flickable.height)
    readonly property bool canUp: flickable.contentY > 0.5
    readonly property bool canDown: flickable.contentY < maxY - 0.5
    readonly property bool active: canUp || canDown

    z: 5
    visible: active

    function move(delta: real) {
        anim.stop()
        anim.to = Math.max(0, Math.min(maxY, Math.round((flickable.contentY + delta) / step) * step))
        if (anim.to === flickable.contentY)
            anim.to = Math.max(0, Math.min(maxY, flickable.contentY + delta))
        anim.start()
    }
    NumberAnimation {
        id: anim
        target: root.flickable
        property: "contentY"
        duration: Theme.durationNormal
        easing.type: Easing.OutCubic
    }

    component Arrow: AbstractButton {
        id: arrow
        property string iconName
        width: root.stacked ? root.width : root.arrowSize
        height: root.arrowSize
        padding: Math.max(0, (Math.min(width, height) - Theme.iconSizeS) / 2)
        hoverEnabled: true
        focusPolicy: Qt.NoFocus
        background: Rectangle {
            radius: root.stacked ? Theme.radiusControl : width / 2
            border.width: root.stacked ? 0 : Theme.borderWidth
            color: root.stacked ? (arrow.down ? Theme.pressedFill : arrow.hovered ? Theme.hoverFill : "transparent")
                 : arrow.down ? Theme.composite(Theme.pressedFill, Theme.base)
                 : arrow.hovered ? Theme.composite(Theme.hoverFill, Theme.base) : Theme.base
            border.color: Theme.separator
        }
        contentItem: Icon {
            opacity: arrow.enabled ? 1 : 0.3
            name: arrow.iconName
            size: Theme.iconSizeS
            color: arrow.hovered ? Theme.accent : Theme.text
        }
        Accessible.name: ToolTip.text
        ToolTip.visible: hovered
        ToolTip.delay: Theme.toolTipDelay
    }

    Arrow {
        objectName: "scrollUp"
        visible: root.stacked || root.canUp
        enabled: root.canUp
        iconName: "chevron-up"
        x: root.stacked ? 0 : root.atRight ? root.width - width - root.inset : Math.round((root.width - width) / 2)
        y: root.stacked ? 0 : root.inset
        ToolTip.text: qsTr("Up")
        onClicked: root.move(-root.step)
    }
    Arrow {
        objectName: "scrollDown"
        visible: root.stacked || root.canDown
        enabled: root.canDown
        iconName: "chevron-down"
        x: root.stacked ? 0 : root.atRight ? root.width - width - root.inset : Math.round((root.width - width) / 2)
        y: root.stacked ? root.arrowSize : root.height - height - root.inset
        ToolTip.text: qsTr("More")
        onClicked: root.move(root.step)
    }
}
