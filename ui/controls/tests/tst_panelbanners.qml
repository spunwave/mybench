import QtQuick
import QtTest
import MyBench.Controls

// A pane's banners can appear after starting hidden (an unplug's error banner did not: the banner
// column hid itself while empty, and a hidden column reads every child as hidden). The empty column
// takes no room from the display.
Item {
    id: root
    width: 900
    height: 600

    InstrumentPanel {
        id: panel
        anchors.fill: parent
        banners: [
            Banner {
                id: own
                objectName: "ownBanner"
                visible: false
                tone: "danger"
                text: "Device disconnected"
            }
        ]
    }

    TestCase {
        name: "PanelBanners"
        when: windowShown

        function test_bannerAppearsAfterStartingHidden() {
            waitForRendering(panel)
            verify(!own.visible)
            own.visible = true
            tryVerify(() => own.visible && own.height > 0, 1000, "the banner shows")
            const p = own.mapToItem(panel, 0, 0)
            verify(p.y >= 0 && p.y + own.height <= panel.height, "on screen")
            own.visible = false
            tryVerify(() => !own.visible, 1000)
            own.visible = true
            tryVerify(() => own.visible && own.height > 0, 1000, "and again")
        }
    }
}
