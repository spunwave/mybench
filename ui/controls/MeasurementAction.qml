import QtQuick
import QtQuick.Controls

// An action of a MeasurementStrip: an icon button with a tooltip in the strip's rail (Add, Restart
// Statistics). Declared inside a MeasurementStrip it moves to the rail by itself.
//     MeasurementAction { iconName: "refresh"; toolTip: qsTr("Restart Statistics"); onClicked: ctl.reset() }
Item {
    id: action

    property string iconName
    property string toolTip
    property color color: Theme.textSecondary
    readonly property bool hovered: hover.hovered
    readonly property bool isAction: true

    signal clicked()

    implicitWidth: Theme.measurementRailWidth
    implicitHeight: Theme.measurementRailWidth
    Accessible.role: Accessible.Button
    Accessible.name: toolTip
    Accessible.onPressAction: action.clicked()

    Rectangle {
        anchors.fill: parent
        anchors.margins: 2
        radius: Theme.radiusControl
        color: hover.hovered ? Theme.hoverFill : "transparent"
    }
    Icon {
        anchors.centerIn: parent
        name: action.iconName
        size: Theme.iconSizeL
        color: hover.hovered ? Theme.text : action.color
    }
    HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: action.clicked()
    }
    ToolTip.visible: hover.hovered && toolTip.length > 0
    ToolTip.delay: Theme.toolTipDelay
    ToolTip.text: toolTip
}
