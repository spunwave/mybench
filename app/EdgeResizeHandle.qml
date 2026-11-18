import QtQuick
import MyBench.Controls

// The draggable left edge of a right-hand column (the inspector dock): emits the width the column
// should get. Place it as a child of the column. A double-click restores `defaultWidth`, and a drag
// snaps to it within Theme.snapDistance.
//     EdgeResizeHandle { currentWidth: dock.width; onResized: width => prefs.setInspectorWidth(width) }
MouseArea {
    id: handle

    property real currentWidth: 0
    property real defaultWidth: Theme.inspectorWidth
    property real startX: 0
    property real startWidth: 0

    signal resized(real width)

    x: -Theme.spacingXs
    width: Theme.spacingS
    height: parent ? parent.height : 0
    z: 10
    cursorShape: Qt.SplitHCursor
    onPressed: mouse => {
        startX = mapToItem(null, mouse.x, 0).x
        startWidth = currentWidth
    }
    onPositionChanged: mouse => {
        if (pressed)
            resized(Theme.snapTo(startWidth - (mapToItem(null, mouse.x, 0).x - startX), [defaultWidth]))
    }
    onDoubleClicked: resized(defaultWidth)
    hoverEnabled: true
    // The edge shows while it is hovered or dragged.
    Rectangle {
        x: Math.round(parent.width / 2) - 1
        width: 2
        height: parent.height
        color: Theme.accent
        visible: handle.pressed || handle.containsMouse
    }
}
