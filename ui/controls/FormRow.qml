import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One row of a form: a label column (40 % of the width, 88–120 px, `textSecondary`, sentence case)
// and the control, which fills the rest. Give the control `Layout.fillWidth: true`. With labelPosition
// "left" the label moves above the control when a segmented control cannot show its segments beside it.
//     FormRow { label: qsTr("Source"); ComboBox { Layout.fillWidth: true; model: ["AI 0", "AI 1"] } }
//     FormRow { label: qsTr("Bands"); labelPosition: "top"; ListView { ... } }   // wide controls
Item {
    id: root

    property string label
    property string hint
    property string trailing             // short unit or range text after the label (textTertiary)
    property bool disabled: false        // dims the label (the control handles its own state)
    property string labelPosition: "left"
    default property alias content: body.data

    // Inside a card (a `formHost` ancestor): the label (caption) is above a full-width control, like a KnobField's, so selectors start where the stepper fields do.
    property bool inColumn: false
    property var formHostItem: null
    Component.onCompleted: {
        for (let p = parent; p; p = p.parent) {
            if (p.formHost === true) {
                inColumn = true
                formHostItem = p
                break
            }
        }
    }
    readonly property int spacing: Theme.spacingS
    // A card's dense form (a dock): the label beside the control in the card's label column.
    readonly property bool dense: formHostItem !== null && formHostItem.dense === true
    readonly property real labelWidth: dense ? Theme.denseLabelWidth : Math.round(Math.max(88, Math.min(120, width * 0.4)))
    readonly property real controlWidth: width - labelWidth - spacing
    readonly property bool hasLabel: label.length > 0 || trailing.length > 0
    // Width the content cannot give up: segmented controls at their full width (combos, fields and text elide).
    readonly property real requiredWidth: {
        let required = 0
        for (let i = 0; i < body.children.length; ++i) {
            const segmented = body.children[i] as SegmentedControl
            if (segmented && segmented.visible)
                required = Math.max(required, segmented.implicitWidth)
        }
        return required
    }
    // In a card (a `formHost` ancestor) the label is always above a full-width control.
    readonly property bool labelOnTop: hasLabel && ((inColumn && !dense) || labelPosition === "top" || (width > 0 && requiredWidth > controlWidth + 0.5))
    readonly property int columns: hasLabel && !labelOnTop ? 2 : 1
    // The first scrubbable control of the row (an SiField with `scrubbable`), dragged by the label.
    readonly property SiField scrubTarget: {
        for (let i = 0; i < body.children.length; ++i) {
            const field = body.children[i] as SiField
            if (field && field.scrubbable && field.visible)
                return field
        }
        return null
    }
    // Left labels sit on the text line of the first control (a standard control, a switch or text).
    readonly property real firstControlHeight: {
        for (let i = 0; i < body.children.length; ++i) {
            const child = body.children[i]
            if (child.visible && child.implicitHeight > 0)
                return child.implicitHeight
        }
        return Theme.controlHeight
    }
    // Dense (a dock card): every row as tall as a knob row (knob beside a field), the control
    // centred in it and the label on the control's centre, so all rows keep one rhythm.
    readonly property bool denseRow: dense && hasLabel && !labelOnTop
    readonly property real denseRowHeight: Math.max(Theme.controlHeight, Theme.knobSizeHeader)
    readonly property real bodyTop: denseRow ? Math.max(0, Math.round((denseRowHeight - body.implicitHeight) / 2)) : 0
    readonly property real labelTopMargin: labelOnTop ? 0
        : denseRow ? bodyTop + Math.max(0, Math.round((Math.min(firstControlHeight, Theme.controlHeight) - captionText.height) / 2))
        : Math.max(0, Math.round((Math.min(firstControlHeight, Theme.controlHeight) - Theme.lineHeight) / 2))

    Layout.fillWidth: true
    // From the requested label position only, never from the width-driven move (that would loop
    // through the parent layout: implicitWidth -> width -> labelOnTop -> implicitWidth).
    implicitWidth: labelPosition === "top" || !hasLabel ? Math.max(hasLabel ? captionText.implicitWidth : 0, body.implicitWidth)
                                                        : 120 + spacing + body.implicitWidth
    implicitHeight: !hasLabel ? body.implicitHeight
                  : labelOnTop ? labelBlock.height + Theme.spacingXs + body.implicitHeight
                  : Math.max(labelTopMargin + labelBlock.height, bodyTop + body.implicitHeight, denseRow ? denseRowHeight : 0)

    Item {
        id: labelBlock
        visible: root.hasLabel
        y: root.labelTopMargin
        width: root.labelOnTop ? root.width : root.labelWidth
        height: root.labelOnTop ? Math.max(captionText.height, trailingText.visible ? trailingText.height : 0)
                                : captionText.height + (trailingText.visible ? trailingText.height : 0)

        // Natural label width, independent of the Text's own width (no loop through implicitWidth
        // while the wrap mode switches).
        TextMetrics {
            id: captionMetrics
            font: captionText.font
            text: root.label
        }
        Text {
            id: captionText
            visible: root.label.length > 0
            width: root.labelOnTop ? Math.min(Math.ceil(captionMetrics.advanceWidth), parent.width - (trailingText.visible ? trailingText.implicitWidth + Theme.spacingS : 0))
                                   : parent.width
            text: root.label
            color: root.disabled ? Theme.textDisabled : Theme.textSecondary
            font.pixelSize: root.inColumn ? Theme.fontSizeCaption : Theme.fontSizeBody
            wrapMode: root.labelOnTop ? Text.NoWrap : Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight

            HoverHandler {
                id: captionHover
                cursorShape: root.scrubTarget && root.scrubTarget.enabled ? Qt.SizeHorCursor : Qt.ArrowCursor
            }
            DragHandler {
                id: scrub
                enabled: root.scrubTarget !== null && root.scrubTarget.enabled
                target: null
                xAxis.enabled: true
                yAxis.enabled: false
                dragThreshold: 2
                property int applied: 0
                onActiveChanged: {
                    applied = 0
                    if (!root.scrubTarget)
                        return
                    if (active)
                        root.scrubTarget.beginScrub()
                    else
                        root.scrubTarget.endScrub()
                }
                onTranslationChanged: {
                    if (!active || !root.scrubTarget)
                        return
                    const fine = (centroid.modifiers & Qt.ShiftModifier) !== 0
                    const steps = Math.trunc(translation.x / (fine ? 16 : 6))
                    if (steps !== applied) {
                        root.scrubTarget.scrubBy(steps - applied, fine)
                        applied = steps
                    }
                }
            }
            ToolTip.visible: captionHover.hovered && !scrub.active && (root.hint.length > 0 || captionText.truncated)
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: root.hint.length > 0 ? root.hint : root.label
        }
        Text {
            id: trailingText
            visible: root.trailing.length > 0
            x: root.labelOnTop ? parent.width - width : 0
            y: root.labelOnTop ? 0 : captionText.height
            width: root.labelOnTop ? implicitWidth : parent.width
            text: root.trailing
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeCaption
            font.features: Theme.tabularFigures
            wrapMode: root.labelOnTop ? Text.NoWrap : Text.WordWrap
            maximumLineCount: 2
            elide: Text.ElideRight
        }
    }

    ColumnLayout {
        id: body
        x: root.hasLabel && !root.labelOnTop ? root.labelWidth + root.spacing : 0
        y: root.hasLabel && root.labelOnTop ? labelBlock.height + Theme.spacingXs : root.bodyTop
        width: root.width - x
        height: implicitHeight
        spacing: Theme.spacingXs
    }
}
