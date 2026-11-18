pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework

// docs/help/<topic>.md rendered as Markdown, with back navigation, a topic menu and links between
// pages (other links open in the browser). On the window color; the host draws the edge hairline.
// It has no title row: the host's header shows `Help.title(topic)` and a Back button while `canBack`.
Rectangle {
    id: root

    property string topic: "app"
    property var history: []
    readonly property bool canBack: history.length > 0
    readonly property string pageHtml: Help.html(topic, {
        text: Theme.text.toString(), heading: Theme.text.toString(), muted: Theme.textSecondary.toString(),
        accent: Theme.link.toString(), border: Theme.composite(Theme.separator, Theme.window).toString(),
        codeBackground: Theme.composite(Theme.hoverFill, Theme.window).toString(),
        tableHeader: Theme.composite(Theme.accentMuted, Theme.window).toString(),
        chip: Theme.composite(Theme.hoverFill, Theme.window).toString(), chipText: Theme.text.toString(),
        ch0: Theme.signalCh0.toString(), ch1: Theme.signalCh1.toString(),
        ao0: Theme.signalAo0.toString(), ao1: Theme.signalAo1.toString(),
        math: Theme.signalMath.toString(), ref: Theme.signalRef.toString(),
        run: Theme.runFill.toString(), stop: Theme.stopFill.toString(), bodySize: Theme.fontSizeBody
    })

    function openTopics(anchor: Item) {
        topicMenu.popup(anchor, 0, anchor.height)
    }

    function show(id: string) {
        if (id.length === 0 || id === topic)
            return
        history = history.concat([topic])
        topic = id
        flick.contentY = 0
    }
    function back() {
        if (history.length === 0)
            return
        topic = history[history.length - 1]
        history = history.slice(0, history.length - 1)
        flick.contentY = 0
    }

    implicitWidth: 400
    color: Theme.window

    Menu {
        id: topicMenu
        Instantiator {
            model: Help.topics
            delegate: MenuItem {
                required property var modelData
                text: modelData.title
                checkable: true
                checked: modelData.id === root.topic
                onTriggered: root.show(modelData.id)
            }
            onObjectAdded: (index, object) => topicMenu.insertItem(index, object as MenuItem)
            onObjectRemoved: (index, object) => topicMenu.removeItem(object as MenuItem)
        }
        MenuSeparator {}
        MenuItem {
            text: qsTr("About %1").arg(AppInfo.name)
            onTriggered: Launcher.showAbout()
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        Flickable {
            id: flick
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: width
            contentHeight: page.implicitHeight + 2 * Theme.spacingL
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            ScrollBar.vertical: ScrollBar {}
            WheelScroll { flickable: flick }

            TextEdit {
                id: page
                x: Theme.spacingL
                y: Theme.spacingL
                width: flick.width - 2 * Theme.spacingL
                readOnly: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.Wrap
                text: root.pageHtml
                color: Theme.text
                selectionColor: Theme.selection
                selectedTextColor: Theme.selectionText
                font.pixelSize: Theme.fontSizeBody
                onLinkActivated: link => {
                    const id = Help.topicForLink(link)
                    if (id.length > 0)
                        root.show(id)
                    else
                        Qt.openUrlExternally(link)
                }
                HoverHandler {
                    cursorShape: page.hoveredLink.length > 0 ? Qt.PointingHandCursor : Qt.IBeamCursor
                }
            }
        }
    }
}
