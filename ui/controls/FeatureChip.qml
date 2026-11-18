import QtQuick
import QtQuick.Controls

// A short fact in a rounded outline: an icon with meaning and one to three words.
//     FeatureChip { iconName: "check"; text: qsTr("No NI software"); tone: Theme.positive }
Rectangle {
    id: root

    property string text
    property string iconName
    property color tone: Theme.textSecondary    // icon colour; the text stays in the secondary text colour
    property string toolTip

    implicitWidth: row.implicitWidth + 2 * Theme.spacingS
    implicitHeight: Math.max(Theme.iconSizeS, label.implicitHeight) + Theme.spacingXs * 2
    radius: height / 2
    color: Theme.alpha(root.tone, 0.10)
    border.width: 1
    border.color: Theme.alpha(root.tone, 0.45)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingXs + 1
        Icon {
            visible: root.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: Theme.iconSizeS
            color: root.tone
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: Theme.text
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    HoverHandler { id: hover }
    ToolTip.visible: root.toolTip.length > 0 && hover.hovered
    ToolTip.delay: Theme.toolTipDelay
    ToolTip.text: root.toolTip
}
