pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Templates as T

// One choice out of 2–4 short options: a bordered group at control height with
// `Theme.radiusControl` corners, its segments sized to their content; the current segment uses
// the accent (accentMuted fill, accent border, primary text); an entry with a `color` picks a signal:
// it shows an 8 px swatch and, selected, is filled with Theme.tint(color). `model`: strings, or
// objects { text, icon, toolTip, enabled, color }. Controlled: bind currentIndex, apply activated(index).
//     SegmentedControl { model: [qsTr("Immediate"), qsTr("Edge")]; currentIndex: ctl.mode
//                        onActivated: index => ctl.mode = index }
T.Control {
    id: control

    property var model: []
    property int currentIndex: 0
    property color accentColor: Theme.text
    property bool compact: false
    property bool stretch: false                // fill the given width (a form row's field column)
    readonly property int count: segmentRepeater.count
    // Sum of the segments' natural widths.
    readonly property real naturalWidth: {
        let total = 0
        for (let i = 0; i < segmentRepeater.count; ++i) {
            const segment = segmentRepeater.itemAt(i) as Segment
            if (segment)
                total += segment.naturalWidth
        }
        return total
    }
    // Narrowest the control gets: every segment keeps room for a short label (or its icon).
    readonly property real minimumWidth: {
        let total = 0
        for (let i = 0; i < segmentRepeater.count; ++i) {
            const segment = segmentRepeater.itemAt(i) as Segment
            if (segment)
                total += segment.minimumWidth
        }
        return total + 2 * inset
    }
    readonly property real trackWidth: stretch ? availableWidth : Math.min(availableWidth, naturalWidth + 2 * inset)
    readonly property int inset: 2
    readonly property int radius: Theme.radiusControl

    signal activated(int index)

    function entry(index: int): var {
        const e = model[index]
        return (typeof e === "string" || typeof e === "number") ? { text: String(e) } : (e ?? {})
    }
    function select(index: int) {
        if (index < 0 || index >= count || index === currentIndex)
            return
        if (entry(index).enabled === false)
            return
        activated(index)
    }

    component Segment: T.AbstractButton {
        property real naturalWidth: 0
        property real minimumWidth: 0
    }

    implicitWidth: naturalWidth + 2 * inset
    implicitHeight: compact ? Theme.controlHeightS : Theme.controlHeight
    focusPolicy: Qt.TabFocus
    hoverEnabled: true
    font.pixelSize: compact ? Theme.fontSizeSmall : Theme.fontSizeBody
    Accessible.role: Accessible.PageTabList

    Keys.onLeftPressed: select(currentIndex - 1)
    Keys.onRightPressed: select(currentIndex + 1)

    background: Item {
        Rectangle {
            width: control.trackWidth
            height: parent.height
            radius: control.radius
            color: Theme.controlTrack
            border.width: Theme.borderWidth
            border.color: Theme.controlBorder
            opacity: control.enabled ? 1 : 0.6
            FocusRing { shown: control.visualFocus }
        }
    }

    contentItem: Item {
        id: track

        Rectangle {
            id: chip
            objectName: "segmentChip"
            readonly property Item target: segmentRepeater.count > 0 && control.currentIndex >= 0
                                           ? segmentRepeater.itemAt(Math.min(control.currentIndex, segmentRepeater.count - 1)) : null
            visible: target !== null
            x: target ? segments.x + target.x : 0
            y: control.inset
            width: target ? target.width : 0
            height: track.height - 2 * control.inset
            radius: control.radius - 1
            readonly property var info: target ? control.entry(control.currentIndex) : ({})
            readonly property bool signalled: info.color !== undefined && info.color !== null
            color: signalled ? Theme.tint(info.color) : Theme.accentMuted
            border.width: Theme.borderWidth
            border.color: signalled ? Theme.alpha(info.color, 0.55) : Theme.accent
            opacity: control.enabled ? 1 : 0.6
            Behavior on x {
                enabled: Theme.animations && chip.width > 0
                NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing }
            }
            Behavior on width {
                enabled: Theme.animations && chip.width > 0
                NumberAnimation { duration: Theme.durationFast; easing.type: Theme.easing }
            }
        }

        Row {
            id: segments
            x: control.inset
            height: track.height
            // Width factor of the segments: they shrink to fit, and grow only when `stretch` is set.
            // The part of a segment above its minimum shrinks (or, with `stretch`, grows).
            readonly property real minTotal: control.minimumWidth - 2 * control.inset
            readonly property real fit: control.naturalWidth > minTotal
                ? (control.trackWidth - 2 * control.inset - minTotal) / (control.naturalWidth - minTotal) : 1
            readonly property real shrink: Math.max(0, fit)
            // Wider than needed: the segments grow only with `stretch`, in proportion to their content.
            readonly property real grow: control.stretch && control.naturalWidth > 0
                ? (control.trackWidth - 2 * control.inset) / control.naturalWidth : 1

            Repeater {
                id: segmentRepeater
                model: control.model
                delegate: Segment {
                    id: segment
                    required property int index
                    readonly property var info: control.entry(index)
                    readonly property bool selected: index === control.currentIndex
                    readonly property bool hasIcon: (info.icon ?? "").length > 0
                    readonly property bool hasText: (info.text ?? "").length > 0
                    readonly property bool hasSwatch: info.color !== undefined && info.color !== null
                    naturalWidth: Math.ceil((hasIcon ? Theme.iconSize : 0) + (hasText ? measure.advanceWidth : 0)
                                            + (hasIcon && hasText ? Theme.spacingXs + 2 : 0)
                                            + (hasSwatch ? 8 + Theme.spacingXs + 2 : 0)
                                            + (control.compact ? 2 * Theme.spacingS : 2 * Theme.spacingM))
                    minimumWidth: Math.min(naturalWidth, Math.ceil((hasIcon ? Theme.iconSize + 2 * Theme.spacingXs : 0)
                                                                   + (hasText ? Math.min(measure.advanceWidth, 3.5 * control.font.pixelSize * 0.55) : 0)
                                                                   + 2 * Theme.spacingXs))
                    width: segments.fit >= 1 ? Math.floor(naturalWidth * segments.grow)
                                             : Math.floor(minimumWidth + (naturalWidth - minimumWidth) * segments.shrink)
                    height: segments.height
                    enabled: control.enabled && info.enabled !== false
                    hoverEnabled: true
                    focusPolicy: Qt.NoFocus
                    onClicked: control.select(index)
                    Accessible.role: Accessible.PageTab
                    Accessible.name: info.text ?? info.toolTip ?? ""
                    Accessible.checked: selected

                    // Width from the DemiBold weight, so selecting never resizes a segment.
                    TextMetrics {
                        id: measure
                        font.pixelSize: control.font.pixelSize
                        font.weight: Font.DemiBold
                        text: segment.info.text ?? ""
                    }
                    background: Rectangle {
                        visible: segment.hovered && !segment.selected && segment.enabled
                        anchors { fill: parent; topMargin: control.inset; bottomMargin: control.inset }
                        radius: control.radius - 1
                        color: segment.down ? Theme.pressedFill : Theme.hoverFill
                    }

                    contentItem: Item {
                        Row {
                            anchors.centerIn: parent
                            spacing: Theme.spacingXs + 2
                            Rectangle {
                                visible: segment.hasSwatch
                                anchors.verticalCenter: parent.verticalCenter
                                width: 8
                                height: 8
                                color: segment.info.color ?? "transparent"
                                opacity: segment.selected || segment.hovered ? 1 : 0.7
                            }
                            Icon {
                                visible: segment.hasIcon
                                anchors.verticalCenter: parent.verticalCenter
                                name: segment.info.icon ?? ""
                                size: control.compact ? Theme.iconSizeS : Theme.iconSize
                                color: !segment.enabled ? Theme.textDisabled
                                     : segment.selected ? Theme.text
                                     : segment.hovered ? Theme.text : Theme.textSecondary
                            }
                            Text {
                                id: label
                                visible: segment.hasText
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, segment.width - (segment.hasIcon ? Theme.iconSize + 6 : 0) - (segment.hasSwatch ? 14 : 0) - 8)
                                text: segment.info.text ?? ""
                                font.pixelSize: control.font.pixelSize
                                font.weight: segment.selected ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                                color: !segment.enabled ? Theme.textDisabled
                                     : segment.selected ? Theme.text
                                     : segment.hovered ? Theme.text : Theme.textSecondary
                            }
                        }
                    }

                    ToolTip.visible: hovered && (info.toolTip ?? "").length > 0
                    ToolTip.delay: Theme.toolTipDelay
                    ToolTip.text: info.toolTip ?? ""
                }
            }
        }
    }
}
