import QtQuick
import QtQuick.Controls

// Deprecated (use Button): a style Button with the legacy properties.
//     ActionButton { text: qsTr("Autoscale"); iconName: "autoscale"; onClicked: ... }
Button {
    id: control

    property string tone: "neutral"
    property string iconName
    property string toolTip
    property string shortcutText
    property color color: Theme.accent
    property bool compact: false
    property bool large: false

    highlighted: tone === "accent"
    flat: tone === "ghost" || tone === "subtle"
    implicitHeight: large ? Theme.controlHeightL : compact ? Theme.controlHeightS : Theme.controlHeight
    font.pixelSize: compact ? Theme.fontSizeSmall : Theme.fontSizeBody
    horizontalPadding: compact ? Theme.spacingS : Theme.spacingM
    icon.source: Theme.icon(iconName)
    icon.width: compact ? Theme.iconSizeS : Theme.iconSize
    icon.height: compact ? Theme.iconSizeS : Theme.iconSize
    focusPolicy: Qt.TabFocus

    ToolTip.visible: hovered && toolTip.length > 0 && !down
    ToolTip.delay: Theme.toolTipDelay
    ToolTip.text: shortcutText.length > 0 ? toolTip + "  " + shortcutText : toolTip
}
