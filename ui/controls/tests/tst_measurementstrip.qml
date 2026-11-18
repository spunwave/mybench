import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtTest
import MyBench.Controls

// MeasurementCard and MeasurementStrip: the card's size, statistics block and features (remove on
// hover, context menu, selection, tooltip), and the strip's grid (no card under its minimum, nothing
// truncated or outside, at most two rows visible, vertical scroll, Add last, order) at widths from
// 440 to 1280 px with 1, 3, 6 and 9 measurements.
Item {
    id: root
    width: 1400
    height: 400

    readonly property var stat: ({ min: 706.4e-3, max: 708.0e-3, mean: 707.2e-3, stdDev: 0.31e-3 })

    Component {
        id: cardComponent
        MeasurementCard {
            width: 360
            title: "CH0 · RMS"
            color: Theme.signalCh0
            numericValue: 0.7071
            unit: "V"
            stats: root.stat
        }
    }
    Component {
        id: stripComponent
        MeasurementStrip {
            id: strip
            property int count: 3
            property var added: []
            property var removed: []
            width: 800
            available: [{ id: "m1", title: "RMS" }, { id: "m2", title: "Frequency" }]
            shownIds: ["m1"]
            onAddRequested: id => added = added.concat([id])
            onRemoveRequested: id => removed = removed.concat([id])
            MeasurementCard { objectName: "cursor"; title: "Cursors"; swatch: false; removable: false; value: "1.25 ms"
                              chips: [{ name: "C1", color: "red" }, { name: "C2", color: "blue" }]
                              items: [{ name: "1/Δt", text: "800 Hz" }, { name: "ΔV", text: "1.2 V" }, { name: "C1", text: "0.5 V" }, { name: "C2", text: "-0.7 V" }] }
            Repeater {
                model: strip.count
                MeasurementCard {
                    required property int index
                    objectName: "card" + index
                    title: "CH" + Math.floor(index / 3) + " · Peak-to-peak " + index
                    value: "1.98" + index + " V"
                    stats: ({ min: "1.979 V", max: "1.983 V", mean: "1.981 V", stdDev: "1.12 mV" })
                }
            }
        }
    }

    function texts(item: Item, list: var): var {
        for (const child of item.children) {
            if (child instanceof Text && child.visible && child.text.length > 0)
                list.push(child)
            texts(child, list)
        }
        return list
    }
    // The cells of a strip in order.
    function cells(strip: Item): var {
        const grid = strip.data.find(o => o.objectName === "stripFlick").contentItem.children[0]
        return grid.children.filter(c => c.minimumWidth !== undefined && c.visible)
    }

    TestCase {
        name: "MeasurementCard"
        when: windowShown

        function test_size_and_statistics_block() {
            const card = createTemporaryObject(cardComponent, root)
            compare(card.height, Theme.measurementCardHeight)
            verify(card.minimumWidth >= Theme.measurementCardMinWidth)
            const m = findChild(card, "cardStats")
            verify(m && m.visible)
            const fig = [0, 1, 2, 3].map(i => findChild(card, "figure_" + i))
            for (const f of fig)
                verify(f && f.text.length > 0 && f.text !== "—")
            const at = f => f.mapToItem(card, 0, 0)
            compare(at(fig[0]).y, at(fig[1]).y)
            compare(at(fig[2]).y, at(fig[3]).y)
            verify(at(fig[2]).y > at(fig[0]).y)
            compare(at(fig[0]).x + fig[0].width, at(fig[2]).x + fig[2].width)
            compare(at(fig[1]).x + fig[1].width, at(fig[3]).x + fig[3].width)
            const value = findChild(card, "cardValue")
            verify(m.x >= value.x + value.implicitWidth)
            verify(m.x + m.width <= card.width)
            const tint = findChild(card, "captionTint")
            compare(tint.color, Theme.tint(Theme.signalCh0))
        }

        function test_no_statistics_card_keeps_height() {
            const card = createTemporaryObject(cardComponent, root, { stats: null })
            compare(card.height, Theme.measurementCardHeight)
            verify(!findChild(card, "cardStats").visible)
        }

        function test_widest_value_sets_the_minimum_width() {
            const card = createTemporaryObject(cardComponent, root, { numericValue: NaN, value: "−1234.5678901234 GHz", stats: null })
            verify(card.minimumWidth > Theme.measurementCardMinWidth)
            card.width = card.minimumWidth
            const value = findChild(card, "cardValue")
            verify(value.x + value.implicitWidth <= card.width)
            verify(!value.truncated)
            const small = createTemporaryObject(cardComponent, root, { stats: null, title: "", value: "1 V", numericValue: NaN })
            compare(small.minimumWidth, Theme.measurementCardCompactMinWidth)
            const before = small.minimumWidth
            small.value = "−1234.5678901234 GHz"
            verify(small.minimumWidth > before)
            small.value = "1 V"
            verify(small.minimumWidth > before)
        }

        function test_hover_shows_remove_and_it_emits() {
            const card = createTemporaryObject(cardComponent, root)
            const remove = findChild(card, "removeButton")
            compare(remove.opacity, 0)
            mouseMove(card, 120, 40)
            tryCompare(remove, "opacity", 1)
            const spy = createTemporaryObject(spyComponent, root, { target: card, signalName: "removeRequested" })
            mouseClick(remove)
            compare(spy.count, 1)
            mouseMove(root, 1300, 380)
            tryCompare(remove, "opacity", 0)
        }

        function test_not_removable_has_no_remove() {
            const card = createTemporaryObject(cardComponent, root, { removable: false })
            verify(!findChild(card, "removeButton").visible)
        }

        function test_context_menu_entries() {
            const card = createTemporaryObject(cardComponent, root)
            const reset = createTemporaryObject(spyComponent, root, { target: card, signalName: "resetStatisticsRequested" })
            const remove = createTemporaryObject(spyComponent, root, { target: card, signalName: "removeRequested" })
            mouseClick(card, 100, 40, Qt.RightButton)
            const menu = card.data.find(o => o instanceof Menu)
            verify(menu)
            tryVerify(() => menu.visible)
            const names = []
            for (let i = 0; i < menu.count; ++i)
                if (menu.itemAt(i) instanceof MenuItem && menu.itemAt(i).visible)
                    names.push(menu.itemAt(i).text)
            compare(names, ["Copy Value", "Copy All", "Reset Statistics", "Remove"])
            menu.itemAt(2).triggered()
            compare(reset.count, 1)
            menu.itemAt(4).triggered()
            compare(remove.count, 1)
            menu.close()
        }

        function test_selection_outline_and_exclusive() {
            const strip = createTemporaryObject(stripComponent, root, { count: 2 })
            const a = findChild(strip, "card0")
            const b = findChild(strip, "card1")
            compare(a.selected, false)
            mouseClick(a, 100, 40)
            compare(a.selected, true)
            verify(findChild(a, "selectionOutline").visible)
            mouseClick(b, 100, 40)
            compare(b.selected, true)
            compare(a.selected, false)
            mouseClick(b, 100, 40)
            compare(b.selected, false)
        }

        function test_tooltip_full_precision() {
            const card = createTemporaryObject(cardComponent, root, { exactValue: 0.70710678 })
            verify(card.tipText.indexOf("707.10678 mV") >= 0)
            verify(card.tipText.indexOf("CH0 · RMS") === 0)
            verify(card.tipText.indexOf("min") > 0 && card.tipText.indexOf("σ") > 0)
        }
    }

    Component { id: spyComponent; SignalSpy {} }

    TestCase {
        name: "MeasurementStrip"
        when: windowShown

        // What an arrangement shows, from the cards' own minimum widths (independent of the strip).
        function shows(strip: Item, form: string): var {
            const tall = form === "tall"
            const list = cells(strip)
            let minimum = Theme.measurementCardCompactMinWidth
            for (const c of list)
                minimum = Math.max(minimum, tall ? c.tallMinimumWidth : form === "compact" ? c.compactMinimumWidth : c.wideMinimumWidth)
            const h = tall ? Theme.measurementCardTallHeight : Theme.measurementCardHeight
            let columns = Math.max(1, Math.floor(strip.width - (strip.railVisible ? Theme.measurementRailWidth : 0)) / minimum | 0)
            const rows = Math.ceil(list.length / columns)
            const fit = Math.max(tall ? 0 : 1, Math.floor(strip.maximumHeight / h))
            if (rows > 1 && rows <= fit)
                columns = Math.ceil(list.length / rows)
            return { shown: Math.min(list.length, columns * Math.min(rows, fit)), height: Math.min(rows, fit) * h, columns: columns }
        }

        function formOf(strip: Item): string {
            return strip.compact ? "compact" : strip.tall ? "tall" : "wide"
        }

        function checkLayout(strip: Item, label: string) {
            const list = cells(strip)
            const flick = findChild(strip, "stripFlick")
            const h = strip.tall ? Theme.measurementCardTallHeight : Theme.measurementCardHeight
            compare(strip.gridColumns, shows(strip, formOf(strip)).columns, label)
            verify(strip.height <= strip.maximumHeight + 0.5, label + " over budget")
            compare(flick.contentWidth <= flick.width + 0.5, true, label + " horizontal overflow")
            const rows = new Set()
            let visibleCards = 0
            for (const c of list) {
                verify(c.width >= c.minimumWidth - 0.5, label + " card narrower than its minimum")
                verify(c.width >= (strip.compact ? Theme.measurementCardCompactMinWidth : Theme.measurementCardMinWidth) - 0.5, label)
                verify(c.x >= -0.5 && c.x + c.width <= flick.width + 0.5, label + " card outside")
                compare(c.height, c.tall ? Theme.measurementCardTallHeight : Theme.measurementCardHeight, label)
                rows.add(Math.round(c.y))
                if (c.y + c.height <= strip.height + 0.5) {
                    visibleCards++
                    for (const t of texts(c, [])) {
                        verify(!t.truncated, label + " truncated: " + t.text)
                        const r = t.mapToItem(c, 0, 0)
                        verify(r.x >= -0.5 && r.x + t.implicitWidth <= c.width + 0.5, label + " clipped: " + t.text)
                    }
                    if (c.hasFigures)
                        verify(findChild(c, "cardStats").visible || strip.compact, label + " statistics hidden")
                }
            }
            const mine = shows(strip, formOf(strip)), wide = shows(strip, "wide"), tallForm = shows(strip, "tall"), compactForm = shows(strip, "compact")
            const best = strip.anyFigures ? Math.max(wide.shown, tallForm.shown) : wide.shown
            verify(strip.anyFigures || (!strip.tall && !strip.compact), label)
            if (strip.anyFigures) {
                compare(strip.compact, compactForm.shown > best, label + " compact only when it shows more")
                verify(mine.shown >= best, label + " " + mine.shown + " < " + best)
                if (!strip.compact && wide.shown === tallForm.shown)
                    verify(mine.height <= Math.max(wide.height, tallForm.height) && mine.height <= (strip.tall ? wide.height : tallForm.height), label + " taller on a tie")
            }
            compare(visibleCards, mine.shown, label + " visible cards")
            compare(strip.gridRows, rows.size, label)
            compare(strip.visibleRows, Math.min(rows.size, Math.max(strip.tall ? 0 : 1, Math.floor(strip.maximumHeight / h))), label)
            compare(strip.height, strip.visibleRows * h, label)
            compare(strip.scrolls, rows.size > strip.visibleRows, label)
            compare(flick.interactive, strip.scrolls, label)
            compare(flick.contentHeight, rows.size * h, label)
            if (strip.scrolls)
                verify(mine.shown < list.length, label)
            else
                compare(visibleCards, list.length, label)
        }

        function test_sweep() {
            for (const count of [1, 3, 6, 9]) {
                for (const budget of [84, 112, 2 * Theme.measurementCardTallHeight]) {
                    const strip = createTemporaryObject(stripComponent, root, { count: count, maximumHeight: budget })
                    for (let w = 440; w <= 1280; w += 40) {
                        strip.width = w
                        wait(20)
                        checkLayout(strip, count + " cards, budget " + budget + ", " + w + " px")
                    }
                    strip.destroy()
                }
            }
        }

        function test_expected_arrangements() {
            const strip = createTemporaryObject(plainStripComponent, root, { maximumHeight: 2 * Theme.measurementCardTallHeight })
            strip.width = 1020; wait(20)
            verify(strip.gridColumns >= 3 && strip.gridColumns <= 4)
            compare(strip.scrolls, false)
            strip.width = 640; wait(20)
            compare(strip.scrolls, false)
            strip.width = 484; wait(20)
            compare(strip.compact, true)
            compare(strip.gridColumns, 3)
            compare(strip.scrolls, false)
            strip.maximumHeight = 84; wait(20)
            compare(strip.tall, false)
            compare(strip.compact, true)
            compare(strip.visibleRows, 1)
            verify(strip.height <= 84)
            strip.maximumHeight = Theme.measurementCardTallHeight; wait(20)
            compare(strip.compact, true)
            compare(strip.gridColumns, 3)
            compare(strip.visibleRows, 1)
        }

        function rowsOf(strip: Item): var {
            const rows = {}
            for (const c of cells(strip)) {
                const y = Math.round(c.y)
                rows[y] = (rows[y] ?? 0) + 1
            }
            return Object.keys(rows).map(Number).sort((a, b) => a - b).map(y => rows[y])
        }

        // Cards without statistics are as narrow as their caption and value: five fit one row from 740 px.
        function test_cards_without_statistics_use_the_compact_minimum() {
            for (const w of [760, 840, 1000]) {
                const strip = createTemporaryObject(bareStripComponent, root, { width: w })
                wait(20)
                compare(rowsOf(strip).length, 1, w + " px: one row")
                compare(rowsOf(strip)[0], 5)
                for (const c of cells(strip))
                    verify(c.minimumWidth < Theme.measurementCardMinWidth, "minimum " + c.minimumWidth)
                strip.destroy()
            }
        }

        // No orphans: balanced rows, the last row's cells keep the grid's cell width.
        function test_rows_are_balanced() {
            let strip = createTemporaryObject(bareStripComponent, root, { width: 500 })
            wait(20)
            compare(rowsOf(strip), [3, 2])
            const widths = cells(strip).map(c => c.width)
            verify(Math.max(...widths) - Math.min(...widths) <= 1, "equal cell widths: " + widths)
            strip.destroy()
            strip = createTemporaryObject(bareStripComponent, root, { width: 700, count: 7 })
            wait(20)
            compare(rowsOf(strip), [4, 3])
            strip.destroy()
        }

        // A second row when it makes every card visible (the dock's allowance), two at most.
        function test_extended_budget_shows_every_card() {
            const one = Theme.measurementCardHeight
            let strip = createTemporaryObject(bareStripComponent, root, { width: 500, maximumHeight: one, extendedHeight: 2 * one })
            wait(20)
            compare(rowsOf(strip), [3, 2])
            compare(strip.scrolls, false)
            compare(strip.height, 2 * one)
            strip.destroy()
            strip = createTemporaryObject(bareStripComponent, root, { width: 500, maximumHeight: one, extendedHeight: 2 * one - 4 })
            wait(20)
            compare(rowsOf(strip).length, 2)   // the grid keeps its rows, one shows
            compare(strip.visibleRows, 1)
            compare(strip.scrolls, true)
            strip.destroy()
            strip = createTemporaryObject(bareStripComponent, root, { width: 500, count: 7, maximumHeight: one, extendedHeight: 5 * one })
            wait(20)
            compare(strip.visibleRows, 1)
            strip.destroy()
        }

        // The arrangement is a function of the width and the cards' intrinsic minimums only: swept up and
        // down it is the same at every width, and it settles (no re-choice after the first polish).
        function test_long_caption_settles_from_both_sides() {
            const strip = createTemporaryObject(longCaptionStripComponent, root)
            const sig = () => formOf(strip) + ":" + strip.gridColumns + ":" + strip.visibleRows
            const up = {}, down = {}
            for (let w = 400; w <= 700; w += 4) {
                strip.width = w; wait(10)
                up[w] = sig()
                const again = sig()
                wait(10)
                compare(sig(), again, w + " px settles")
            }
            for (let w = 700; w >= 400; w -= 4) {
                strip.width = w; wait(10)
                down[w] = sig()
            }
            for (const w in up)
                compare(up[w], down[w], w + " px: same arrangement from either side")
        }

        function test_cards_without_statistics_stay_wide() {
            const strip = createTemporaryObject(actionStripComponent, root, { width: 440 })
            wait(20)
            compare(strip.tall, false)
            for (const c of cells(strip))
                compare(c.height, Theme.measurementCardHeight)
            compare(strip.cellMinimum, Theme.measurementCardCompactMinWidth)
        }

        function test_height_follows_rows_only() {
            const strip = createTemporaryObject(stripComponent, root, { count: 3, width: 1100 })
            wait(20)
            const h = strip.height
            findChild(strip, "card0").value = "123456 V"           // a longer value changes nothing in the rows
            wait(20)
            compare(strip.height, h)
            strip.count = 9
            wait(20)
            verify(strip.gridRows > 1)
            verify(strip.height <= strip.maximumHeight)
        }

        function test_vertical_scroll_only() {
            const strip = createTemporaryObject(stripComponent, root, { count: 9, width: 440, maximumHeight: 84 })
            wait(20)
            const flick = findChild(strip, "stripFlick")
            verify(strip.scrolls)
            compare(flick.flickableDirection, Flickable.VerticalFlick)
            compare(flick.contentWidth, flick.width)
            flick.contentY = 40
            compare(flick.contentY, 40)
        }

        function test_order_cursor_first_then_channels() {
            const strip = createTemporaryObject(stripComponent, root, { count: 6, width: 1000 })
            wait(20)
            compare(cells(strip).map(c => c.objectName), ["cursor", "card0", "card1", "card2", "card3", "card4", "card5"])
            let lastY = -1, lastX = -1
            for (const c of cells(strip)) {
                verify(c.y > lastY || (c.y === lastY && c.x > lastX))
                lastY = c.y; lastX = c.x
            }
        }

        function test_add_rail_and_menu() {
            const strip = createTemporaryObject(stripComponent, root, { count: 2, width: 900 })
            wait(20)
            const add = findChild(strip, "addMeasurement")
            verify(add.visible)
            const rail = findChild(strip, "stripRail")
            compare(rail.width, Theme.measurementRailWidth)
            // The rail never shares space with a card.
            for (const c of cells(strip))
                verify(c.mapToItem(strip, 0, 0).x + c.width <= strip.width - Theme.measurementRailWidth + 0.5)
            mouseClick(add)
            const menu = findChild(strip, "addMenu")
            tryVerify(() => menu.visible)
            compare(menu.itemAt(0).text, "RMS")
            compare(menu.itemAt(0).checked, true)
            compare(menu.itemAt(1).checked, false)
            menu.itemAt(1).triggered()
            compare(strip.added, ["m2"])
            menu.itemAt(0).triggered()
            compare(strip.removed, ["m1"])
            menu.close()
            strip.available = []
            verify(!add.visible)
        }

        function test_action_in_the_rail() {
            const strip = createTemporaryObject(actionStripComponent, root)
            wait(20)
            const act = findChild(strip, "act")
            compare(act.parent, findChild(strip, "stripRail"))
            const spy = createTemporaryObject(spyComponent, root, { target: act, signalName: "clicked" })
            mouseClick(act)
            compare(spy.count, 1)
            verify(!cells(strip).includes(act))
            compare(act.height, 32)
        }
    }

    // A long caption among short ones (the Spectrum's "Fundamental power"): its width must not feed back.
    Component {
        id: longCaptionStripComponent
        MeasurementStrip {
            width: 800
            maximumHeight: 2 * Theme.measurementCardTallHeight
            extendedHeight: 2 * Theme.measurementCardTallHeight
            MeasurementCard { title: "Frequency"; value: "999.999 Hz"; stats: ({ min: "1 kHz", max: "1 kHz", mean: "1 kHz", stdDev: "168 µHz" }) }
            MeasurementCard { title: "Fundamental power"; value: "0.5000 V²"; stats: ({ min: "0.5 V²", max: "0.5 V²", mean: "0.5 V²", stdDev: "1 µV²" }) }
            MeasurementCard { title: "THD"; value: "0.012 %"; stats: ({ min: "0.01 %", max: "0.02 %", mean: "0.012 %", stdDev: "1 m%" }) }
            MeasurementCard { title: "SNR"; value: "72.1 dB"; stats: ({ min: "70 dB", max: "73 dB", mean: "72 dB", stdDev: "0.4 dB" }) }
        }
    }
    // Cards without statistics (Multimeter, Counter): a caption and a value.
    Component {
        id: bareStripComponent
        MeasurementStrip {
            id: bare
            property int count: 5
            width: 800
            maximumHeight: 2 * Theme.measurementCardHeight
            Repeater {
                model: bare.count
                MeasurementCard {
                    required property int index
                    title: ["Min", "Max", "Mean", "σ", "Count"][index % 5]
                    value: "1.237 V"
                }
            }
        }
    }
    Component {
        id: plainStripComponent
        MeasurementStrip {
            width: 800
            available: [{ id: "m1", title: "RMS" }]
            Repeater {
                model: 6
                MeasurementCard {
                    required property int index
                    title: "CH" + Math.floor(index / 3) + " · Peak-to-peak"
                    value: "1.98" + index + " V"
                    stats: ({ min: "1.979 V", max: "1.983 V", mean: "1.981 V", stdDev: "1.12 mV" })
                }
            }
        }
    }
    Component {
        id: actionStripComponent
        MeasurementStrip {
            width: 600
            MeasurementCard { title: "Min"; value: "1 V"; stats: null; removable: false }
            MeasurementAction { objectName: "act"; iconName: "refresh"; toolTip: "Restart Statistics" }
        }
    }
}
