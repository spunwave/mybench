import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// One value of an Overview tile: a caption label over the value, tabular figures. `big` is the
// tile's primary value (larger, text colour), the others are secondary.
//     TileStat { big: true; label: qsTr("Frequency"); value: "1 kHz"; stale: !running }
Item {
    id: root

    property string label
    property string value
    property bool big: false
    property bool stale: false
    property color swatchColor: "transparent"
    property color valueColor: Theme.text
    property string tip                    // tooltip (the explanation)

    // Secondary value in a short tile body: label and value on one line.
    readonly property bool inline: !big && parent && parent.tight === true
    readonly property bool roomy: height >= 64
    readonly property int valueSize: big ? (roomy ? Theme.fontSizeReadoutL : Theme.fontSizeReadoutM)
                                         : (roomy ? Theme.fontSizeReadoutM - 2 : Theme.fontSizeHeading + 2)

    Layout.fillWidth: true
    Layout.columnSpan: big ? Math.max(1, (parent && parent.columns) ? parent.columns : 1) : 1
    Layout.fillHeight: true
    Layout.minimumHeight: implicitHeight
    Layout.minimumWidth: 0
    implicitHeight: inline ? Math.max(labelRow.implicitHeight, valueText.implicitHeight) : column.implicitHeight
    implicitWidth: inline ? labelRow.implicitWidth + valueText.implicitWidth + Theme.spacingS : Math.max(valueText.implicitWidth, labelRow.implicitWidth)
    Accessible.role: Accessible.StaticText
    Accessible.name: label + ": " + value

    Item {
        id: column
        width: root.width
        height: implicitHeight
        implicitHeight: root.inline ? Math.max(labelRow.implicitHeight, valueText.implicitHeight) : labelRow.implicitHeight + 2 + valueText.implicitHeight
        anchors.verticalCenter: parent.verticalCenter

        Row {
            id: labelRow
            spacing: Theme.spacingXs + 2
            Rectangle {
                visible: root.swatchColor.a > 0
                anchors.verticalCenter: parent.verticalCenter
                width: 8
                height: 8
                radius: 2
                color: root.swatchColor
            }
            Text {
                text: root.label
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
        Text {
            id: valueText
            x: root.inline ? root.width - width : 0
            y: root.inline ? 0 : labelRow.implicitHeight + 2
            width: root.inline ? Math.min(implicitWidth, root.width - labelRow.implicitWidth - Theme.spacingS) : root.width
            horizontalAlignment: root.inline ? Text.AlignRight : Text.AlignLeft
            text: root.value
            color: root.valueColor
            font.pixelSize: root.inline ? Theme.fontSizeHeading : root.valueSize
            font.weight: root.big ? Font.DemiBold : Font.Normal
            font.features: Theme.tabularFigures
            fontSizeMode: Text.Fit
            minimumPixelSize: Theme.fontSizeSmall
            elide: Text.ElideRight
            opacity: root.stale ? 0.5 : 1
        }
    }

    HoverHandler { id: hover }
    ToolTip.visible: hover.hovered && root.tip.length > 0
    ToolTip.delay: Theme.toolTipDelay
    ToolTip.text: root.tip
}
