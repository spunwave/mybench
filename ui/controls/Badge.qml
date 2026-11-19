import QtQuick

Item {
    id: root

    property string text
    property color color: Theme.textSecondary
    property bool solid: false          // legacy, ignored (no filled badges)
    property bool caps: false           // legacy, ignored (no capitals)
    property int fontSize: Theme.fontSizeCaption
    property string iconName

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(16, label.implicitHeight + 2)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Theme.spacingXs
        Icon {
            visible: root.iconName.length > 0
            anchors.verticalCenter: parent.verticalCenter
            name: root.iconName
            size: 10
            color: label.color
        }
        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: root.text
            color: root.color
            font.pixelSize: root.fontSize
        }
    }
}
