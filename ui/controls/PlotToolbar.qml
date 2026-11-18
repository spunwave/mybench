pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import MyBench.Plot

// The plot toolbar: it fades in at the top right of the plot area while the pointer is over the
// plot. Pointer / Zoom (menu: box, X only, Y only, zoom in/out, undo, reset) / Pan tools, then
// Autoscale X and Y (click = once; the lock keeps following the data).
//     PlotToolbar { plot: thePlot; shown: hover.hovered }
Rectangle {
    id: root

    property Plot plot: null
    // Hover state of the host; the toolbar also stays while its menu is open or it is hovered.
    property bool shown: false
    property list<Item> extras
    // Stays while a list of its own is open (the time-window ComboBox): leaving the plot to pick an
    // entry would otherwise hide the toolbar and close the list under the pointer.
    readonly property bool extrasOpen: {
        for (let i = 0; i < extras.length; ++i) {
            const popup = extras[i].popup
            if (popup && popup.visible)
                return true
        }
        return false
    }
    readonly property bool active: shown || hover.hovered || zoomMenu.visible || extrasOpen

    implicitWidth: row.implicitWidth + 4
    implicitHeight: Theme.controlHeightS + 4
    radius: Theme.radiusControl + 1
    color: Theme.displayDark ? Theme.mix(Theme.display, "#FFFFFF", 0.07) : Theme.base
    border.width: Theme.borderWidth
    border.color: Theme.plotFrame
    opacity: active ? 1 : 0
    visible: opacity > 0 && plot !== null
    Behavior on opacity { NumberAnimation { duration: Theme.durationFast } }

    onExtrasChanged: {
        for (let i = 0; i < extras.length; ++i)
            extras[i].parent = extrasRow
    }
    Component.onCompleted: extrasChanged()

    HoverHandler { id: hover }

    component Tool: ToolButton {
        implicitWidth: Theme.controlHeightS
        implicitHeight: Theme.controlHeightS
        icon.width: Theme.iconSizeS
        icon.height: Theme.iconSizeS
        icon.color: !enabled ? Theme.textDisabled
                  : checked ? Theme.accent
                  : hovered ? Theme.displayText : Theme.displayTextSecondary
        ToolTip.visible: hovered
        ToolTip.delay: Theme.toolTipDelay
    }
    component Separator: Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.borderWidth
        height: Theme.iconSizeS
        color: Theme.plotFrame
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 0

        Row {
            id: extrasRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXs
            rightPadding: children.length > 0 ? Theme.spacingXs : 0
        }
        Separator { visible: extrasRow.children.length > 0 }

        Tool {
            icon.source: Theme.icon("pointer")
            checked: root.plot !== null && root.plot.dragMode === Plot.NoDrag
            ToolTip.text: qsTr("Pointer")
            Accessible.name: qsTr("Pointer")
            onClicked: root.plot.dragMode = Plot.NoDrag
        }
        Tool {
            id: zoomButton
            readonly property bool zoomTool: root.plot !== null && root.plot.dragMode === Plot.Zoom
            icon.source: Theme.icon(!zoomTool || root.plot.zoomAxes === Plot.ZoomXY ? "zoom-box"
                                    : root.plot.zoomAxes === Plot.ZoomX ? "zoom-x" : "zoom-y")
            checked: zoomTool
            ToolTip.text: qsTr("Zoom") + "  " + (Theme.macShortcuts ? qsTr("⌘-drag") : qsTr("Ctrl+drag"))
            Accessible.name: qsTr("Zoom")
            onClicked: zoomMenu.popup(zoomButton, 0, zoomButton.height + 2)

            Menu {
                id: zoomMenu
                function setZoomTool(axes: int) {
                    root.plot.zoomAxes = axes
                    root.plot.dragMode = Plot.Zoom
                }
                MenuItem {
                    text: qsTr("Zoom Box")
                    onTriggered: zoomMenu.setZoomTool(Plot.ZoomXY)
                }
                MenuItem {
                    text: qsTr("Zoom X Only")
                    onTriggered: zoomMenu.setZoomTool(Plot.ZoomX)
                }
                MenuItem {
                    text: qsTr("Zoom Y Only")
                    onTriggered: zoomMenu.setZoomTool(Plot.ZoomY)
                }
                MenuSeparator {}
                MenuItem {
                    text: qsTr("Zoom In")
                    onTriggered: root.plot.zoomAt(Qt.point(root.plot.plotArea.x + root.plot.plotArea.width / 2,
                                                           root.plot.plotArea.y + root.plot.plotArea.height / 2), 1.5, 1.5)
                }
                MenuItem {
                    text: qsTr("Zoom Out")
                    onTriggered: root.plot.zoomAt(Qt.point(root.plot.plotArea.x + root.plot.plotArea.width / 2,
                                                           root.plot.plotArea.y + root.plot.plotArea.height / 2), 1 / 1.5, 1 / 1.5)
                }
                MenuSeparator {}
                MenuItem {
                    text: qsTr("Undo Zoom")
                    enabled: root.plot !== null && root.plot.canUndoZoom
                    onTriggered: root.plot.undoZoom()
                }
                MenuItem {
                    text: qsTr("Reset View")
                    onTriggered: root.plot.resetView()
                }
            }
        }
        Tool {
            icon.source: Theme.icon("hand")
            checked: root.plot !== null && root.plot.dragMode === Plot.Pan
            ToolTip.text: qsTr("Pan")
            Accessible.name: qsTr("Pan")
            onClicked: root.plot.dragMode = Plot.Pan
        }
        Separator {}
        Tool {
            readonly property bool locked: root.plot !== null && root.plot.xAutoscaleLock
            text: "X"
            display: AbstractButton.TextBesideIcon
            icon.source: Theme.icon("autoscale")
            implicitWidth: implicitContentWidth + leftPadding + rightPadding
            horizontalPadding: Theme.spacingXs
            spacing: 2
            font.pixelSize: Theme.fontSizeCaption
            checked: locked
            ToolTip.text: locked ? qsTr("Following X") + "\n" + qsTr("Click to stop") : qsTr("Autoscale X") + "\n" + qsTr("Double-click to follow")
            Accessible.name: qsTr("Autoscale X")
            onClicked: locked ? (root.plot.xAutoscaleLock = false) : root.plot.autoscaleX()
            onDoubleClicked: root.plot.xAutoscaleLock = true
        }
        Tool {
            readonly property bool locked: root.plot !== null && root.plot.yAutoscaleLock
            text: "Y"
            display: AbstractButton.TextBesideIcon
            icon.source: Theme.icon("autoscale")
            implicitWidth: implicitContentWidth + leftPadding + rightPadding
            horizontalPadding: Theme.spacingXs
            spacing: 2
            font.pixelSize: Theme.fontSizeCaption
            checked: locked
            ToolTip.text: locked ? qsTr("Following Y") + "\n" + qsTr("Click to stop") : qsTr("Autoscale Y") + "\n" + qsTr("Double-click to follow")
            Accessible.name: qsTr("Autoscale Y")
            onClicked: locked ? (root.plot.yAutoscaleLock = false) : root.plot.autoscaleY()
            onDoubleClicked: root.plot.yAutoscaleLock = true
        }
    }
}
