pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework

// The right column of the shell: it shows the inspector of the focused pane, or that instrument's
// help page. It claims `panel.inspectorContent` (one Inspector item per panel, moved here, never
// duplicated, so bindings and scroll position stay) and hands it back through `panel.releaseInspector()`.
// While a dock exists, panels never dock their inspector locally.
Rectangle {
    id: dock

    property InstrumentPanel panel: null
    property string page: "inspector"
    property string helpTopic: ""          // "" = the panel's help page (else "app")
    // An instrument pane is on screen (the shell binds it; `panel` can still be null while the
    // pane loads). The "Show an instrument…" hint only appears without one.
    property bool paneShown: panel !== null
    readonly property string effectiveHelpTopic: helpTopic.length > 0 ? helpTopic
                                                 : panel ? panel.helpId : "app"
    readonly property string instrumentTitle: panel ? panel.paneTitle : ""
    // The panel whose inspector is in the dock now (follows `panel`).
    readonly property InstrumentPanel claimedPanel: privateState.claimed

    // The user closed the help page (× in the header).
    signal closeRequested()

    implicitWidth: Theme.inspectorWidth
    color: Theme.window

    QtObject {
        id: privateState
        property InstrumentPanel claimed: null
    }

    function claim() {
        if (privateState.claimed === panel)
            return
        release()
        if (!panel || !panel.inspectorContent)
            return
        privateState.claimed = panel
        panel.inspectorContent.parent = host   // the Inspector fills its parent
    }
    function release() {
        const previous = privateState.claimed
        privateState.claimed = null
        if (previous)
            previous.releaseInspector()
    }
    function showHelp(topic: string) {
        helpTopic = topic
        page = "help"
    }

    onPanelChanged: claim()
    Component.onCompleted: {
        PanelRegistry.dockCount += 1
        claim()
    }
    Component.onDestruction: {
        release()
        PanelRegistry.dockCount -= 1
    }

    Rectangle {
        width: 1
        height: parent.height
        color: Theme.separator
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 1
        spacing: 0

        // Header: the help page's back, title (topic list) and close; the instrument name otherwise.
        Item {
            Layout.fillWidth: true
            implicitHeight: Theme.paneHeaderHeight

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.spacingM
                anchors.rightMargin: Theme.spacingS
                spacing: Theme.spacingS
                ToolButton {
                    objectName: "dockHelpBack"
                    visible: dock.page === "help" && helpLoader.item !== null && helpLoader.item.canBack
                    icon.source: Theme.icon("chevron-left")
                    ToolTip.visible: hovered
                    ToolTip.delay: Theme.toolTipDelay
                    ToolTip.text: qsTr("Back")
                    Accessible.name: qsTr("Back")
                    onClicked: helpLoader.item.back()
                }
                Item {
                    id: topicButton
                    objectName: "dockHelpTopics"
                    visible: dock.page === "help"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Accessible.role: Accessible.Button
                    Accessible.name: qsTr("Help topics")
                    Accessible.onPressAction: helpLoader.item.openTopics(topicButton)
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width)
                        text: Help.title(dock.effectiveHelpTopic) + "  ▾"
                        color: Theme.text
                        font.pixelSize: Theme.fontSizeHeading
                        font.weight: Font.DemiBold
                    }
                    TapHandler {
                        onTapped: helpLoader.item.openTopics(topicButton)
                    }
                    HoverHandler { cursorShape: Qt.PointingHandCursor }
                }
                Text {
                    visible: dock.page !== "help"
                    Layout.fillWidth: visible
                    text: dock.instrumentTitle
                    color: Theme.text
                    font.pixelSize: Theme.fontSizeHeading
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                ToolButton {
                    objectName: "dockClose"
                    visible: dock.page === "help"
                    icon.source: Theme.icon("close")
                    ToolTip.visible: hovered
                    ToolTip.delay: Theme.toolTipDelay
                    ToolTip.text: qsTr("Close Help")
                    Accessible.name: qsTr("Close Help")
                    onClicked: dock.closeRequested()
                }
            }
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.separator
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Item {
                id: host
                objectName: "inspectorDockHost"
                anchors.fill: parent
                visible: dock.page !== "help"
            }

            Text {
                objectName: "dockEmptyHint"
                anchors.centerIn: parent
                width: parent.width - 2 * Theme.spacingL
                visible: dock.page !== "help" && dock.panel === null && !dock.paneShown
                text: qsTr("No instrument")
                color: Theme.textTertiary
                font.pixelSize: Theme.fontSizeBody
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Loader {
                id: helpLoader
                anchors.fill: parent
                active: dock.page === "help"
                sourceComponent: HelpView {
                    topic: dock.effectiveHelpTopic
                }
            }
        }
    }
}
