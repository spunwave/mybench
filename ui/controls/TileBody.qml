import QtQuick
import QtQuick.Layouts

// The body of an Overview tile: the instrument's values (TileStat children, the default `stats`)
// and, when something is live or measured, its display (`screen` children). Wide tile: values on
// the left (about 40 %), display on the right. A narrow tile (under 300 px) puts the values in two
// columns above the display, which drops out when it would be under 40 px.
//     TileBody { screenShown: controller.running; stats: [ TileStat { ... } ]  BenchPlot { ... } }
Item {
    id: root

    property bool screenShown: false
    default property alias stats: statsGrid.data
    property alias screen: screenItem.data
    readonly property bool wide: width >= 300
    readonly property bool sideBySide: wide && screenShown

    GridLayout {
        anchors.fill: parent
        columns: root.sideBySide ? 2 : 1
        columnSpacing: Theme.spacingM
        rowSpacing: Theme.spacingS

        GridLayout {
            id: statsGrid
            Layout.fillWidth: true
            Layout.fillHeight: !screenItem.visible || root.sideBySide
            Layout.preferredWidth: root.sideBySide ? Math.round(root.width * 0.4) : -1
            Layout.maximumWidth: root.sideBySide ? Math.round(root.width * 0.5) : -1
            columns: root.sideBySide ? 1 : (root.width >= 200 ? 2 : 1)
            columnSpacing: Theme.spacingM
            rowSpacing: 0
            // A short body (under 130 px): secondary values go inline, label beside value.
            readonly property bool tight: root.height < 130
        }
        TileScreen {
            id: screenItem
            visible: root.screenShown && (root.wide || root.height - statsGrid.implicitHeight - Theme.spacingS >= 40)
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.minimumHeight: 0
        }
    }
}
