import QtQuick
import QtQuick.Layouts
import QtTest
import MyBench.Controls

// A managed dock folds its cards to fit (never a cut card): from the bottom of a column, one card
// always open; a click on a folded header opens it and folds a neighbour. Beyond that, little
// arrows instead of a scroll bar.
Item {
    id: root
    width: 700
    height: 500

    component Rows: ColumnLayout {
        property int count: 4
        Layout.fillWidth: true
        Repeater {
            model: parent.count
            Rectangle { Layout.fillWidth: true; implicitHeight: 30; color: "gray" }
        }
    }

    InstrumentColumn {
        id: dock
        width: 300            // one column of cards
        managed: true
        orientation: Qt.Horizontal
        bandHeight: 400
        bandFoldHeight: 400
        ChannelCard { id: a; title: "A"; Rows {} }
        ChannelCard { id: b; title: "B"; Rows {} }
        ChannelCard { id: c; title: "C"; Rows {} }
    }

    InstrumentColumn {
        id: wide
        y: 0
        width: 900
        managed: true
        orientation: Qt.Horizontal
        bandHeight: 400
        bandFoldHeight: 1000
        ChannelCard { id: ch0; title: "CH 0"; checkable: true; checked: true; collapseWhenOff: true; Rows { count: 6 } }
        ChannelCard { id: ch1; title: "CH 1"; checkable: true; checked: true; collapseWhenOff: true; Rows { count: 6 } }
        ChannelCard { id: trig; title: "Trigger"; Rows { id: trigRows; count: 2 } }
        ChannelCard { id: math; title: "Math"; checkable: true; checked: false; collapseWhenOff: true; Rows { count: 3 } }
    }

    TestCase {
        name: "BandPlan"
        when: windowShown

        function init() {
            dock.visible = false
            wide.visible = true
            ch0.checked = true
            trigRows.count = 2
            wide.refit()
            wait(400)                              // the plan settles
        }
        function cleanup() {
            dock.visible = true
        }

        function test_aGrowingCardKeepsItsColumn() {
            ch0.checked = false
            tryVerify(() => ch0.height < 80, 1000)
            wide.refit()
            wait(400)
            tryVerify(() => wide.bandColumns >= 2, 1000)
            const before = [ch0, ch1, trig, math].map(c => [c.x, c.width])
            trigRows.count = 6                     // Edge: the trigger card grows
            tryVerify(() => trig.height > 6 * 30, 1000)
            wait(400)
            const after = [ch0, ch1, trig, math].map(c => [c.x, c.width])
            compare(after, before, "no card moves to another column")
            wide.refit()                           // the pane's size changes: planned again
            verify(wide.bandColumns >= 2)
        }

        function test_switchedOffColumnGivesItsWidth() {
            tryVerify(() => wide.bandColumns === 3, 1000)
            const open = ch1.width
            ch0.checked = false                     // CH 0 alone in its column, header only
            tryVerify(() => ch0.height < 80, 1000)
            if (ch0.x === ch1.x) {
                verify(ch1.width > open, "merged with its neighbour: wider columns")
            } else {
                verify(ch0.width <= wide.headerColumnWidth, "its column is narrow")
                verify(ch1.width > open, "the open cards get the width")
            }
            compare(Math.round(Math.max(...[ch0, ch1, trig, math].map(c => c.x + c.width))), wide.width)
        }
    }

    TestCase {
        name: "Folding"
        when: windowShown

        function init() {
            wide.visible = false
        }

        function test_foldsFromTheBottomAndOpensOnClick() {
            dock.bandFoldHeight = 1000
            dock.openCard = null
            tryVerify(() => !a.folded && !b.folded && !c.folded, 1000, "room for all: nothing folded")
            const full = a.openHeight + b.openHeight + c.openHeight
            dock.bandFoldHeight = full - 20
            tryVerify(() => c.folded && !a.folded && !b.folded, 1000, "the bottom card folds first")
            verify(dock.contentTall <= dock.bandFoldHeight)
            verify(c.height < c.openHeight)
            dock.bandFoldHeight = a.openHeight + 2 * a.foldedHeight + 4
            tryVerify(() => b.folded && c.folded && !a.folded, 1000)

            // A click on C's header opens C; A folds instead.
            const header = findChild(c, "channelHeader")
            verify(findChild(c, "foldChevron").visible)
            mouseClick(header, 20, header.height / 2)
            tryVerify(() => !c.folded && a.folded && b.folded, 1000, "C open, the others folded")
            compare(dock.openCard, c)

            dock.bandFoldHeight = 40
            tryVerify(() => !c.folded && a.folded && b.folded, 1000)
            dock.bandFoldHeight = 1000
            tryVerify(() => !a.folded && !b.folded && !c.folded, 1000)
        }

        function test_arrowsInsteadOfAScrollBar() {
            const arrows = findChild(dock, "columnArrows")
            verify(arrows)
            dock.bandFoldHeight = 1000
            dock.bandHeight = 120     // content taller than the band, nothing left to fold
            dock.openCard = null
            tryVerify(() => arrows.visible && arrows.canDown, 1000)
            const down = findChild(arrows, "scrollDown")
            verify(down.visible)
            mouseClick(down)
            tryVerify(() => arrows.canUp, 1000, "moved down")
            dock.bandHeight = 400
        }
    }
}
