import QtQuick
import QtQuick.Shapes
import QtQuick.Templates as T

// Checkable picture button: a small pictogram above a label, for choices that read better as
// pictures than as a dropdown (measurement types, trigger types, waveform shapes). The pictogram is
// `glyph` (an SVG path on a 32 × 18 box) or `iconName`. Controlled: bind `checked` and change the state
// in onClicked (a click never touches `checked`); `autoToggle: true` makes it a normal checkable button.
//     PictureButton { text: qsTr("RMS"); glyph: "M3 9c3-7 5-7 8 0s5 7 8 0"
//                     checked: ctl.kind === 2; onClicked: ctl.kind = 2 }
T.AbstractButton {
    id: control

    property string glyph
    property string iconName
    property color accentColor: Theme.accent    // legacy, ignored: selection always uses the accent
    property bool autoToggle: false
    // The picture left of the label on one control-height row (a dense dock card), not above it.
    property bool inline: false

    readonly property bool hasPicture: glyph.length > 0 || iconName.length > 0

    checkable: autoToggle
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    implicitWidth: Math.max(Theme.pictureCellWidth, implicitContentWidth + 8)
    implicitHeight: hasPicture && !inline ? Theme.pictureCellHeight : Theme.controlHeight
    padding: 4
    horizontalPadding: 3      // narrow grids (5 per row in a 250 px card) keep their labels
    Accessible.role: Accessible.CheckBox
    Accessible.name: text
    Accessible.checkable: true
    Accessible.checked: checked

    readonly property color ink: !enabled ? Theme.textDisabled
                                : checked ? Theme.accent
                                : hovered ? Theme.text : Theme.textSecondary

    background: Rectangle {
        radius: Theme.radiusControl + 1
        color: control.checked ? (control.pressed ? Theme.accentSoft : Theme.accentMuted)
             : control.pressed ? Theme.pressedFill : control.hovered ? Theme.hoverFill : "transparent"
        border.width: 1
        border.color: control.checked ? Theme.accent : control.hovered ? Theme.controlBorder : Theme.separator
        FocusRing { shown: control.visualFocus }
    }

    contentItem: Item {
        readonly property real pictureSpace: control.hasPicture ? picture.height + 3 : 0
        // The label's natural width from a metrics object, not label.implicitWidth: the label's own
        // width (elided) re-lays it out and would feed back into these bindings.
        TextMetrics {
            id: labelMetrics
            text: control.text
            font: label.font
        }
        readonly property real labelWidth: Math.ceil(labelMetrics.advanceWidth) + 1
        readonly property real inlineWidth: (control.hasPicture ? picture.width + Theme.spacingXs : 0) + labelWidth
        implicitHeight: control.inline ? Math.max(control.hasPicture ? picture.height : 0, label.implicitHeight)
                                       : pictureSpace + label.implicitHeight
        implicitWidth: control.inline ? inlineWidth
                                      : Math.max(control.hasPicture ? picture.width : 0, label.implicitWidth)
        Item {
            id: picture
            visible: control.hasPicture
            width: 36
            height: 20
            x: control.inline ? Math.max(0, Math.round((parent.width - parent.inlineWidth) / 2)) : Math.round((parent.width - width) / 2)
            y: control.inline ? Math.round((parent.height - height) / 2)
                              : Math.round((parent.height - parent.pictureSpace - label.implicitHeight) / 2)
            Shape {
                width: 32
                height: 18
                scale: 36 / 32
                transformOrigin: Item.TopLeft
                visible: control.glyph.length > 0
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: control.ink
                    strokeWidth: 1.4
                    fillColor: "transparent"
                    capStyle: ShapePath.RoundCap
                    joinStyle: ShapePath.RoundJoin
                    PathSvg { path: control.glyph }
                }
            }
            Icon {
                visible: control.glyph.length === 0 && control.iconName.length > 0
                anchors.centerIn: parent
                name: control.iconName
                size: Theme.iconSizeL
                color: control.ink
            }
        }
        Text {
            id: label
            x: control.inline && control.hasPicture ? picture.x + picture.width + Theme.spacingXs : Math.round((parent.width - width) / 2)
            y: control.hasPicture && !control.inline ? picture.y + picture.height + 3 : Math.round((parent.height - implicitHeight) / 2)
            width: Math.min(parent.labelWidth, parent.width - (control.inline && control.hasPicture ? picture.width + Theme.spacingXs : 0))
            text: control.text
            color: control.ink
            font.pixelSize: control.hasPicture && !control.inline ? Theme.fontSizeCaption : Theme.fontSizeSmall
            font.weight: control.checked ? Font.DemiBold : Font.Normal
            elide: Text.ElideRight
            horizontalAlignment: Text.AlignHCenter
        }
    }
}
