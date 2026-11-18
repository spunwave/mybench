import QtQuick

// The display surface of an Overview tile: the plot's colours, a hairline, clipped. Children
// (a bare BenchPlot) fill it with a small margin.
Rectangle {
    id: root

    default property alias content: inner.data

    color: Theme.display
    radius: Theme.radiusControl
    border.width: Theme.borderWidth
    border.color: Theme.separator
    clip: true

    Item {
        id: inner
        anchors.fill: parent
        anchors.margins: Theme.spacingXs
    }
}
