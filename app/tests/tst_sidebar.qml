import QtQuick
import QtQuick.Controls
import QtTest
import MyBench.Framework
import MyBench.Controls
import MyBench.App

// The sidebar: Overview, then the instruments by group with their views as child
// rows; a row has the state dot and the key value; click shows, ⌘/Ctrl-click shows beside; the
// context menu; keys ↑/↓, Return, Space (the sidebar's Space is not also the window's Run/Stop).
Item {
    id: host
    width: 400
    height: 700

    AppPreferences { id: prefs }
    WorkspaceState { id: ws }
    ShellDialogs {
        id: dialogs
        preferences: prefs
        workspace: ws
    }
    AppActions {
        id: actions
        workspace: ws
        dialogs: dialogs
        preferences: prefs
    }
    Sidebar {
        id: sidebar
        width: Theme.sidebarWidth
        height: parent.height
        workspace: ws
        dialogs: dialogs
    }

    function menuTexts(menu: Menu): var {
        const texts = []
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i)
            texts.push(item instanceof MenuSeparator ? "-" : (item as MenuItem).text)
        }
        return texts
    }
    function menuItem(menu: Menu, text: string): MenuItem {
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i) as MenuItem
            if (item && item.text === text)
                return item
        }
        return null
    }

    TestCase {
        name: "Sidebar"
        when: windowShown

        function init() {
            ws.fromMap({})
            sidebar.compact = false
            sidebar.peeking = false
            sidebar.width = Theme.sidebarWidth
            for (const id of ["aa", "bb", "cc"]) {
                const c = InstrumentRegistry.controller(id)
                c.stop()
                c.setKey("")
                tryCompare(c, "keyValue", "")              // coalesced to ≤ 4 Hz
            }
            tryVerify(() => !InstrumentRegistry.anyRunning)
        }

        function row(paneId: string): SidebarRow {
            return findChild(sidebar, "sidebarRow-" + paneId) as SidebarRow
        }

        function test_entriesByGroup() {
            const kinds = sidebar.entries.map(e => e.kind + ":" + (e.paneId || e.title))
            compare(kinds, ["overview:Overview", "group:Measure", "instrument:aa", "instrument:bb",
                            "group:Generate", "instrument:cc", "view:cc/editor"])
            verify(row("overview"))
            verify(row("aa"))
            verify(row("cc/editor").child)
            verify(row("overview").selected)               // Overview at start
        }

        function test_clickShowsAndModifierShowsBeside() {
            mouseClick(row("bb"))
            compare(ws.selected, "bb")
            compare(ws.focused, "bb")
            verify(row("bb").selected)
            verify(!row("overview").selected)
            mouseClick(row("cc"), 10, 10, Qt.LeftButton, Qt.ControlModifier)
            compare(ws.selected, "bb")
            compare(ws.beside, "cc")
            verify(row("cc").selected)                     // focused pane
            verify(row("bb").shownBeside)                  // the other pane
            mouseClick(row("overview"))
            verify(ws.overview)
        }

        function test_stateDotAndKeyValue() {
            const aa = InstrumentRegistry.controller("aa")
            const r = row("aa")
            compare(r.status, "")
            const height = r.height
            compare(height, 34)           // one line at rest
            aa.setKey("1.234 V")
            tryCompare(r, "keyValue", "1.234 V")
            compare(r.height, height)                      // a held value of a stopped instrument: no line
            verify(!findChild(r, "sidebarValue").visible)
            aa.run()
            tryCompare(r, "status", "running")
            compare(r.statusColor, Theme.positive)
            const value = findChild(r, "sidebarValue")
            verify(value.visible)
            compare(value.color, Theme.positive)
            compare(r.height, height + value.implicitHeight + r.valueGap)   // the list jumps by that one line
            aa.stop()
            tryCompare(r, "status", "")
            compare(r.height, height)
        }

        // The longest key value (18 characters) fits the text column of the 160 px row at the
        // caption font, tabular figures, with nothing elided.
        function test_valueFits() {
            const aa = InstrumentRegistry.controller("aa")
            aa.run()
            aa.setKey("10.0 kHz · 10 Vpp")
            const r = row("aa")
            const value = findChild(r, "sidebarValue")
            tryCompare(value, "text", "10.0 kHz · 10 Vpp")
            for (const text of ["10.0 kHz · 10 Vpp", "−12 / −12 / −12 dB", "In 0x0F · Out 0x00", "−199.999 mV DC",
                                "100 kHz · 10.0 Vpp", "AO 0 + AO 1", "1.00 kHz · 1.0 Vpp", "000000000000000000"]) {
                verify(text.length <= 18, text)
                aa.setKey(text)
                tryCompare(value, "text", text)
                verify(value.contentWidth <= value.width, text + ": " + value.contentWidth + " > " + value.width)
                verify(value.x + value.contentWidth <= r.width - Theme.spacingS)
            }
            aa.stop()
        }

        function test_groupCaptionsAndIcons() {
            const list = findChild(sidebar, "sidebarList") as ListView
            // The caption of the first group and the icons share the left edge.
            const caption = findChild(list.contentItem, "sidebarCaption-measure")
            verify(caption)
            compare(caption.x, Theme.spacingM)
            compare(caption.color.toString(), Theme.textTertiary.toString())
            compare(caption.font.pixelSize, Theme.fontSizeCaption)
            compare(caption.y, Theme.spacingL)                                       // 16 above
            compare(caption.parent.height - caption.y - caption.height, Theme.spacingXs)   // 4 below
        }

        // The expanded tooltip: after the delay, the full title only, right of the sidebar.
        function test_tooltipRight() {
            const r = row("aa")
            const tip = findChild(r, "sidebarTip")
            verify(tip)
            compare(tip.delay, Theme.toolTipDelay)
            mouseMove(r, 30, r.height / 2)
            tryVerify(() => tip.visible, 3000)
            compare(tip.text, "AA Instrument")
            verify(r.mapToItem(null, tip.x, 0).x >= sidebar.width)
            mouseMove(host, 390, 690)
            tryVerify(() => !tip.visible)
        }

        function test_contextMenu() {
            const menu = row("aa").contextMenu
            verify(menu)
            compare(host.menuTexts(menu), ["Show", "Show Beside", "-", "Run", "Single", "-", "Reset Settings…", "Help"])
            host.menuItem(menu, "Show").triggered()
            compare(ws.selected, "aa")
            host.menuItem(menu, "Run").triggered()
            const aa = InstrumentRegistry.controller("aa")
            tryCompare(aa, "running", true)
            compare(host.menuItem(menu, "Stop").text, "Stop")
            host.menuItem(menu, "Stop").triggered()
            tryCompare(aa, "running", false)
            host.menuItem(row("bb").contextMenu, "Show Beside").triggered()
            compare(ws.beside, "bb")
            host.menuItem(menu, "Help").triggered()
            compare(ws.dockPage, "help")
            compare(ws.helpTopic, "aa")
            // A view row: Show, Show Beside, Help.
            compare(host.menuTexts(row("cc/editor").contextMenu), ["Show", "Show Beside", "-", "Help"])
            verify(row("overview").contextMenu === null)
        }

        function test_keyboard() {
            const list = findChild(sidebar, "sidebarList") as ListView
            list.forceActiveFocus()
            compare(list.currentIndex, 0)
            keyClick(Qt.Key_Down)
            compare(list.currentIndex, 2)                  // the group label is skipped
            keyClick(Qt.Key_Down)
            keyClick(Qt.Key_Return)
            compare(ws.selected, "bb")
            // Space runs/stops the keyboard row once (the window's Space shortcut stays out).
            const bb = InstrumentRegistry.controller("bb")
            keyClick(Qt.Key_Space)
            tryCompare(bb, "running", true)
            wait(50)
            compare(bb.running, true)
            keyClick(Qt.Key_Space)
            tryCompare(bb, "running", false)
            keyClick(Qt.Key_Up)
            keyClick(Qt.Key_Up)
            compare(list.currentIndex, 0)
            keyClick(Qt.Key_Return)
            verify(ws.overview)
        }

        function test_compactRows() {
            sidebar.compact = true
            sidebar.width = Theme.sidebarCompactWidth
            const r = row("aa")
            compare(r.width, Theme.sidebarCompactWidth)
            InstrumentRegistry.controller("aa").setKey("2 V")
            tryVerify(() => r.tipText.indexOf("AA Instrument") === 0)
            tryVerify(() => r.tipText.indexOf("2 V") > 0)
            verify(r.tipText.indexOf("Stopped") > 0)
        }

        // The rail peeking open: every row keeps its place (rail height, icon where the rail has it,
        // no value line), the labels fade in with the width; only the selected row's icon is accented.
        function test_peekKeepsTheRail() {
            sidebar.compact = true
            sidebar.width = Theme.sidebarCompactWidth
            InstrumentRegistry.controller("aa").run()
            tryVerify(() => InstrumentRegistry.controller("aa").running)
            InstrumentRegistry.controller("aa").setKey("2 V")
            const ids = ["overview", "aa", "bb", "cc"]
            waitForRendering(sidebar)
            wait(50)                                  // the list lays out the rail
            const before = ids.map(id => row(id).mapToItem(sidebar, 0, 0).y)
            const heightBefore = row("aa").height
            sidebar.peeking = true
            sidebar.width = (Theme.sidebarCompactWidth + Theme.sidebarWidth) / 2
            const half = sidebar.reveal
            verify(half > 0.3 && half < 0.7, "labels half faded at half width")
            sidebar.width = Theme.sidebarWidth
            compare(sidebar.reveal, 1)
            waitForRendering(sidebar)
            const after = ids.map(id => row(id).mapToItem(sidebar, 0, 0).y)
            compare(after, before, "no row moves while the rail opens")
            compare(row("aa").height, heightBefore)
            verify(!row("aa").compact && row("aa").railLayout)
            verify(!row("aa").showValue, "no value line while peeking")
            compare(row("aa").iconColor.toString(), Theme.textSecondary.toString())
        }
    }
}
