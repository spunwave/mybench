import QtQuick
import QtQuick.Controls
import QtTest
import MyBench.Framework
import MyBench.Controls

// PaneHeader and the InstrumentPanel frame: Run/Stop, Single, Release Outputs, the action icons,
// the header height rule and a sweep over every pane width (nothing overlaps, is clipped or hidden),
// and the legacy option names panels still use.
Item {
    id: root
    width: 1200
    height: 700

    Component {
        id: headerComponent
        PaneHeader {
            width: 900
            controller: InstrumentRegistry.controller("beta")
        }
    }
    Component {
        id: compatPanel
        InstrumentPanel {
            id: panel
            width: 1100
            height: 650
            controller: InstrumentRegistry.controller("gamma")
            displayTitle: "CH 0 · 5 ms/div"
            displayInfo: "Sample Rate 50 kS/s"
            runBar.showTimeout: true
            runBar.timeoutText: "No input"
            runBar.singleToolTip: "Take one reading"
            runBarControls: [ Button { objectName: "autoscale"; text: "Autoscale" } ]
            runBarActions: [ ToolButton { objectName: "logTool"; text: "Log" } ]
            displayTools: [ ToolButton { objectName: "viewTool"; text: "View" } ]
            traceStyles: [{ name: "CH 0", style: null, color: "red" }]
            measurements: [ Rectangle { objectName: "strip"; implicitHeight: 60; property string summaryText: "RMS 1 V" } ]
            banners: [ Banner { objectName: "ownBanner"; text: "Own banner"; visible: false } ]
            Rectangle { objectName: "displayContent"; anchors.fill: parent; color: "black" }
        }
    }

    Component {
        id: contentPanel
        InstrumentPanel {
            width: 1100
            height: 650
            controller: InstrumentRegistry.controller("gamma")
            showRunControls: false
            headerContent: [ Rectangle { objectName: "bigRun"; property int headerGroup: 1; implicitWidth: 80; implicitHeight: 28 } ]
            headerSettings: [ Rectangle { objectName: "setting1"; property int headerGroup: 2; implicitWidth: 130; implicitHeight: 28 },
                              Rectangle { objectName: "setting2"; property int headerGroup: 2; implicitWidth: 130; implicitHeight: 28 },
                              Rectangle { objectName: "setting3"; property int headerGroup: 2; implicitWidth: 130; implicitHeight: 28 } ]
            displayTools: [ Rectangle { objectName: "modeTool"; property int headerGroup: 3; implicitWidth: 120; implicitHeight: 28 } ]
        }
    }
    Component {
        id: barePanel
        InstrumentPanel {
            width: 1100
            height: 650
            controller: InstrumentRegistry.controller("gamma")
        }
    }

    function menuTexts(menu: Menu): var {
        const texts = []
        for (let i = 0; i < menu.count; ++i) {
            const item = menu.itemAt(i)
            texts.push(item instanceof MenuSeparator ? "-" : (item as MenuItem).text)
        }
        return texts
    }

    FontMetrics {
        id: titleMetrics
        font.pixelSize: Theme.fontSizeTitle
        font.weight: Font.DemiBold
    }

    TestCase {
        name: "PaneHeader"
        when: windowShown

        function cleanup() {
            const beta = InstrumentRegistry.controller("beta")
            beta.stop()
            tryVerify(() => beta.idle)
        }

        function test_runStopToggle() {
            const header = createTemporaryObject(headerComponent, root)
            const run = findChild(header, "runButton")
            verify(run)
            compare(header.height, Theme.paneHeaderHeight)
            compare(run.runText, "Run")
            verify(!run.running)                         // accent "Run" when stopped
            compare(run.height, Theme.controlHeight)     // one line, the control height
            const widthStopped = run.width
            mouseClick(run)
            tryCompare(header.controller, "running", true)
            verify(run.running)                          // neutral "Stop" while running
            compare(run.width, widthStopped)             // one toggle, constant width
            tryCompare(header, "status", "running")
            mouseClick(run)
            tryCompare(header.controller, "running", false)
            verify(!run.running)
        }

        function test_singleAndRelease() {
            const header = createTemporaryObject(headerComponent, root)
            const single = findChild(header, "singleButton")
            const release = findChild(header, "releaseButton")
            verify(single.visible)
            verify(single.enabled)
            verify(!release.visible)                     // no outputs held
            header.showRelease = true
            verify(release.visible)
            compare(release.text, "Release Outputs")
            header.width = 500                           // the bar wraps: Single and Release keep their labels
            header.layoutBar()
            verify(header.twoRows)
            compare(single.text, "Single")
            compare(release.text, "Release Outputs")
        }

        function test_stateText() {
            const header = createTemporaryObject(headerComponent, root)
            const state = findChild(header, "paneState")
            verify(["Ready", "Stopped", "No device"].indexOf(state.text) >= 0, state.text)
            header.stateText = "Waiting for trigger"
            compare(state.text, "Waiting for trigger")
            header.stateText = ""
            header.controller.run()
            tryCompare(state, "text", "Running")
        }

        function test_menusAndActionIcons() {
            const header = createTemporaryObject(headerComponent, root)
            compare(header.menu.popupType, Popup.Item)
            const exportMenu = findChild(header, "exportMenu")
            compare(root.menuTexts(exportMenu), ["Export Data…", "Export Image…", "Print…"])
            // The options menu holds only what has no icon of its own; without entries no button.
            const options = findChild(header, "optionsButton")
            tryVerify(() => root.menuTexts(header.menu).length === 0)
            verify(!options.visible)
            header.hasTraceStyles = true
            tryCompare(options, "visible", true)
            compare(root.menuTexts(header.menu), ["Trace Style…"])
            header.hasTraceStyles = false
            tryCompare(options, "visible", false)
            for (const name of ["exportButton", "resetButton", "helpButton"]) {
                const button = findChild(header, name)
                verify(button.visible, name)
                verify(button.toolTip.length > 0, name)
            }
            compare(findChild(header, "helpButton").shortcutText, "F1")
            const spy = createTemporaryObject(spyComponent, root, { target: header, signalName: "helpRequested" })
            mouseClick(findChild(header, "helpButton"))
            compare(spy.count, 1)
        }

        // The shell's split pane: × = closeRequested() (Close Split; never stops), and a note.
        function test_closableAndNote() {
            const header = createTemporaryObject(headerComponent, root)
            const close = findChild(header, "closeButton")
            const note = findChild(header, "paneNote")
            verify(close)
            verify(note)
            verify(!close.visible)
            verify(!note.visible)
            header.closable = true
            header.note = "Split hidden — window too narrow"
            verify(close.visible)
            verify(note.visible)
            compare(note.text, "Split hidden — window too narrow")
            header.controller.run()
            tryCompare(header.controller, "running", true)
            const spy = createTemporaryObject(spyComponent, root, { target: header, signalName: "closeRequested" })
            waitForRendering(header)
            mouseClick(close)
            compare(spy.count, 1)
            compare(header.controller.running, true)
            const panel = createTemporaryObject(compatPanel, root)
            verify(!panel.paneHeader.closable)
            panel.closable = true
            panel.note = "Note"
            verify(panel.paneHeader.closable)
            compare(panel.paneHeader.note, "Note")
            waitForRendering(panel)
            const panelSpy = createTemporaryObject(spyComponent, root, { target: panel, signalName: "closeRequested" })
            mouseClick(findChild(panel.paneHeader, "closeButton"))
            compare(panelSpy.count, 1)
        }

        function test_contentAndRunControls() {
            const header = createTemporaryObject(headerComponent, root)
            const run = findChild(header, "runButton")
            const single = findChild(header, "singleButton")
            verify(run.visible)
            verify(single.visible)
            compare(header.height, Theme.paneHeaderHeight)

            verify(findChild(header, "paneState").visible)
            header.showRunControls = false
            verify(!run.visible)
            verify(!single.visible)
            verify(findChild(header, "paneState").visible)              // the state stays

            const panel = createTemporaryObject(contentPanel, root)
            const panelHeader = panel.paneHeader
            verify(!findChild(panelHeader, "runButton").visible)
            verify(!findChild(panelHeader, "singleButton").visible)
            const big = findChild(panelHeader, "bigRun")
            const setting = findChild(panelHeader, "setting1")
            const mode = findChild(panelHeader, "modeTool")
            const help = findChild(panelHeader, "helpButton")
            verify(big && setting && mode)
            compare(big.parent.objectName, "paneHeaderBar")
            tryCompare(panelHeader, "height", Theme.paneHeaderHeight)
            const bigPos = big.mapToItem(panelHeader, 0, 0)
            const settingPos = setting.mapToItem(panelHeader, 0, 0)
            const modePos = mode.mapToItem(panelHeader, 0, 0)
            verify(settingPos.x > bigPos.x + big.width)
            verify(modePos.x > settingPos.x + setting.width)
            verify(modePos.x + mode.width <= help.mapToItem(panelHeader, 0, 0).x)
            fuzzyCompare(bigPos.y + big.height / 2, Theme.paneHeaderHeight / 2, 1.5)
            panel.width = 560
            waitForRendering(panel)
            tryVerify(() => panelHeader.twoRows)
            compare(panelHeader.height, Theme.paneHeaderHeight * panelHeader.rows)
            for (const item of [big, setting, mode])
                verify(item.mapToItem(panelHeader, 0, 0).y >= Theme.paneHeaderHeight, item.objectName)
            verify(help.mapToItem(panelHeader, 0, 0).y < Theme.paneHeaderHeight)
            verify(help.mapToItem(panelHeader, 0, 0).x + help.width <= panelHeader.width)
            panel.width = 1100
            waitForRendering(panel)
            tryVerify(() => !panelHeader.twoRows)
            compare(panelHeader.height, Theme.paneHeaderHeight)
            compare(big.parent.objectName, "paneHeaderBar")
        }

        // --- The sweep: nine representative bars (the item counts, kinds and value ranges of the nine
        // instruments' headers) at every pane width from 440 to 1320 px. At each width no two visible
        // items intersect, every item lies inside the header, no Text is truncated unless it may be
        // (elideAllowed), the header is one row height times its rows, and every primary parameter has its knob.
        readonly property string imports: "import QtQuick\nimport QtQuick.Controls\nimport MyBench.Framework\nimport MyBench.Controls\n"
        readonly property string timeDivs: "[1e-6,2e-6,5e-6,1e-5,2e-5,5e-5,1e-4,2e-4,5e-4,1e-3,2e-3,5e-3,0.01,0.02,0.05,0.1,0.2,0.5,1,2,5,10]"
        readonly property string runSource: "RunButton { objectName: \"%1\"; runText: \"%2\" }"
        readonly property string singleButton: "Button { objectName: \"single\"; text: \"Single\"; icon.source: Theme.icon(\"step\") }"
        function button(name, text, icon): string {
            return "Button { objectName: \"" + name + "\"; text: \"" + text + "\"; icon.source: Theme.icon(\"" + icon + "\") }"
        }
        function segmented(name, texts): string {
            return "SegmentedControl { objectName: \"" + name + "\"; model: " + JSON.stringify(texts.map(t => ({ text: t }))) + " }"
        }
        function field(name, props): string {
            return "HeaderField { objectName: \"" + name + "\"; " + props + " }"
        }
        function run(name, verb): string {
            return runSource.arg(name).arg(verb)
        }
        // [id, title, content, settings, extras, displayTools]
        function barSpecs(): var {
            const td = field("timeDiv", "toolTip: \"Timebase\"; values: " + timeDivs
                             + "; formatter: v => Units.format(v, \"s\", 3) + \"/div\"; currentIndex: 12")
            const pos = field("horizontalPosition", "toolTip: \"Trigger position\"; from: 0; to: 100; value: 50; formatter: v => Math.round(v) + \" %\"")
            const start = field("startKnob", "label: \"Start\"; toolTip: \"Start frequency\"; unit: \"Hz\"; from: 1; to: 20000; logarithmic: true; value: 20")
            const stop = field("stopKnob", "label: \"Stop\"; toolTip: \"Stop frequency\"; unit: \"Hz\"; from: 1; to: 20000; logarithmic: true; value: 20000")
            const amp = field("amplitudeKnob", "toolTip: \"Amplitude\"; accentColor: Theme.signalAo0; unit: \"Vpk\"; from: 0; to: 5; value: 2; formatter: v => v.toFixed(2) + \" Vpk\"")
            const span = field("spanKnob", "toolTip: \"Span\"; values: [1,2,5,10,20,50,100,200,500,1000,2000,5000,10000,20000,50000,100000]; formatter: v => Units.format(v, \"Hz\", 3); currentIndex: 8")
            const lines = field("resolutionKnob", "toolTip: \"Resolution\"; values: [100,200,400,800,1600,3200,6400,12800]; formatter: v => v + \" lines\"; currentIndex: 3")
            const rate = field("logRateKnob", "toolTip: \"Sampling rate\"; unit: \"S/s\"; values: [1,2,5,10,20,50,100,200,500,1000]")
            const wideRun = (name, verb) => run(name, verb)
            return [
                ["scope", wideRun("r", "Run"), [singleButton], [td, pos, button("autoscaleButton", "Autoscale", "autoscale")], segmented("displayMode", ["YT", "XY", "FFT"])],
                ["bode", wideRun("r", "Sweep"), [], [start, stop, amp, button("keepReferenceButton", "Keep as Reference", "layers")], null],
                ["dsa", wideRun("r", "Run"), [singleButton], [span, lines], segmented("analysisMode", ["Spectrum", "Octave"])],
                ["dmm", wideRun("r", "Run"), [singleButton], [button("hold", "Hold", "pause"), button("relative", "Relative", "reset")], null],
                ["gen", wideRun("r", "Run"), [singleButton], [segmented("outputPair", ["AO 0 / AO 1", "Audio out"])], segmented("previewMode", ["Time", "Frequency"])],
                ["log", wideRun("r", "Run"), [button("rec", "Stop Rec", "record"), button("pause", "Resume", "record")], [rate], null],
                ["ctr", wideRun("r", "Run"), [singleButton], [], null],
                ["dio", wideRun("r", "Run"), [singleButton], [], segmented("dioRadix", ["Hex", "Bin", "Dec"])],
                ["aeq", wideRun("r", "Run"), [], [button("bypass", "Bypass", "power"), button("flat", "Flat", "reset")], null]
            ]
        }
        function makeHeader(spec): Item {
            const content = [spec[1]].concat(spec[2]).join(", ")
            const source = imports + "PaneHeader {\n width: 900; showRunControls: false; closable: true; title: \"Waveform Generator\"\n"
                         + " controller: InstrumentRegistry.controller(\"gamma\")\n"
                         + " content: [" + content + "]\n"
                         + " settings: [" + spec[3].join(", ") + "]\n"
                         + (spec[4] ? " displayTools: [" + spec[4] + "]\n" : "")
                         + "}"
            return createTemporaryQmlObject(source, root, "sweep-" + spec[0])
        }
        // Every visible Text under `item`.
        function texts(item, out) {
            for (const child of item.children) {
                if (!child.visible)
                    continue
                if (child instanceof Text)
                    out.push(child)
                texts(child, out)
            }
            if (item.contentItem && item.contentItem !== item)
                texts(item.contentItem, out)
            return out
        }
        // The items whose rectangles must not touch: the lead, the detail, the bar and the action group.
        function leafRects(header): var {
            const items = ["paneTitleArea", "paneStateArea", "paneDetail", "paneNote"].map(n => findChild(header, n))
            for (const it of header.barItems)
                items.push(it)
            for (const it of findChild(header, "paneActions").children)
                items.push(it)
            const rects = []
            for (const it of items) {
                if (!it.visible || it.width <= 0 || it.height <= 0)
                    continue
                const p = it.mapToItem(header, 0, 0)
                rects.push({ name: it.objectName.length > 0 ? it.objectName : String(it), x: p.x, y: p.y, w: it.width, h: it.height })
            }
            return rects
        }

        function checkHeader(header, label) {
            header.layoutBar()
            const rects = leafRects(header)
            compare(header.height, Theme.paneHeaderHeight * header.rows, label + " height")
            for (const r of rects) {
                verify(r.x >= -0.5 && r.x + r.w <= header.width + 0.5, label + ": " + r.name + " outside in x: " + r.x + " + " + r.w)
                verify(r.y >= -0.5 && r.y + r.h <= header.height + 0.5, label + ": " + r.name + " outside in y: " + r.y + " + " + r.h)
            }
            for (let i = 0; i < rects.length; ++i) {
                for (let j = i + 1; j < rects.length; ++j) {
                    const a = rects[i]
                    const b = rects[j]
                    const overlap = a.x + 0.5 < b.x + b.w && b.x + 0.5 < a.x + a.w && a.y + 0.5 < b.y + b.h && b.y + 0.5 < a.y + a.h
                    verify(!overlap, label + ": " + a.name + " overlaps " + b.name)
                }
            }
            for (const t of texts(header, [])) {
                const allowed = t.elideAllowed === true
                verify(allowed || !t.truncated, label + ": text \"" + t.text + "\" is truncated")
                verify(allowed || t.contentWidth <= t.width + 0.5 || t.width === 0 || t.implicitWidth <= t.width + 0.5,
                       label + ": text \"" + t.text + "\" is wider than its box")
            }
            for (const it of header.barItems) {
                if (!it.visible || !(it instanceof HeaderField))
                    continue
                verify(it.field.knobShown, label + ": " + it.objectName + " has no knob")
                const k = it.field.knob
                verify(k.visible && k.width >= Theme.knobSizeHeader - 0.5, label + ": " + it.objectName + " knob " + k.width)
                const p = k.mapToItem(header, 0, 0)
                verify(p.x >= -0.5 && p.x + k.width <= header.width + 0.5, label + ": " + it.objectName + " knob outside")
            }
        }

        function test_sweepAllBars() {
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                verify(header, spec[0])
                for (let width = 440; width <= 1320; width += 20) {
                    header.width = width
                    checkHeader(header, spec[0] + " at " + width)
                }
                header.destroy()
            }
        }

        // The bar is either whole in row 1 or whole below it; it wraps on rows of Theme.paneHeaderHeight, and no row is
        // left empty.
        function test_barSharesRowOneOrWrapsWhole() {
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                let sawInline = false
                let sawWrapped = false
                for (let width = 440; width <= 1320; width += 20) {
                    header.width = width
                    header.layoutBar()
                    const shown = header.barItems.filter(it => it.visible)
                    const rows = new Set()
                    for (const it of shown)
                        rows.add(Math.floor((it.mapToItem(header, 0, 0).y + it.height / 2) / Theme.paneHeaderHeight))
                    if (header.barInline) {
                        sawInline = true
                        compare(rows.size, 1, spec[0] + " " + width)
                        compare(Array.from(rows)[0], 0)
                        compare(header.height, Theme.paneHeaderHeight)
                    } else {
                        sawWrapped = true
                        verify(Math.min(...Array.from(rows)) === 1, spec[0] + " " + width + ": the bar starts below row 1")
                        compare(Math.max(...Array.from(rows)), rows.size, spec[0] + " " + width + ": an empty row")
                        compare(header.height, Theme.paneHeaderHeight * (1 + rows.size))
                    }
                }
                verify(sawWrapped, spec[0] + " wraps at 440")
                header.destroy()
            }
            const scope = makeHeader(barSpecs()[0])
            scope.width = 1320
            scope.layoutBar()
            verify(scope.barInline, "the scope's bar fits in row 1 at 1320")
            scope.destroy()
        }

        // Three groups in order (run, parameters, view); a hairline between two groups that share a
        // row, none at the start of a wrapped row; the bar wraps item by item.
        function test_groupsAndHairlines() {
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                for (let width = 440; width <= 1320; width += 20) {
                    header.width = width
                    header.layoutBar()
                    const groups = header.barGroups.map(g => g.filter(it => it.visible)).filter(g => g.length > 0)
                    const rowOf = it => Math.floor((it.mapToItem(header, 0, 0).y + it.height / 2) / Theme.paneHeaderHeight)
                    let seps = 0
                    for (let i = 1; i < groups.length; ++i) {
                        const before = groups[i - 1][groups[i - 1].length - 1]
                        const after = groups[i][0]
                        if (rowOf(before) === rowOf(after))
                            ++seps
                    }
                    let visibleSeps = 0
                    for (let i = 0; i < 2; ++i) {
                        const sep = findChild(header, "paneGroupSeparator" + i)
                        if (!sep.visible)
                            continue
                        ++visibleSeps
                        compare(sep.height, 20)
                        const row = Math.floor((sep.mapToItem(header, 0, 0).y + sep.height / 2) / Theme.paneHeaderHeight)
                        const left = header.barItems.filter(it => it.visible && rowOf(it) === row && it.mapToItem(header, 0, 0).x < sep.mapToItem(header, 0, 0).x)
                        const right = header.barItems.filter(it => it.visible && rowOf(it) === row && it.mapToItem(header, 0, 0).x > sep.mapToItem(header, 0, 0).x)
                        verify(left.length > 0 && right.length > 0, spec[0] + " " + width + ": a hairline at a row edge")
                    }
                    compare(visibleSeps, seps, spec[0] + " " + width)
                }
                header.destroy()
            }
        }

        // The most rows a header may take: 484 px 3, 612 and 640 px 3, 784 px 2, 968 px 2, 1280 px 1
        // (Bode, whose bar is the longest and shows Keep as Reference, one more).
        function test_rowBudget() {
            const budget = { 1280: 1, 968: 2, 784: 2, 640: 3, 612: 3, 484: 3 }
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                const bode = spec[0] === "bode"
                for (const w of Object.keys(budget)) {
                    header.width = Number(w)
                    header.layoutBar()
                    compare(header.rows <= budget[w] + (bode ? 1 : 0), true,
                            spec[0] + " at " + w + " takes " + header.rows + " rows, budget " + budget[w])
                }
                header.destroy()
            }
        }

        // The own buttons show their label or all drop it together, never a mix.
        function test_iconOnlyAllOrNone() {
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                for (let width = 440; width <= 1320; width += 20) {
                    header.width = width
                    header.layoutBar()
                    const modes = new Set(header.compactable.filter(it => it.visible).map(it => it.display))
                    verify(modes.size <= 1, spec[0] + " " + width)
                    for (const it of header.barItems)
                        if (it instanceof RunButton || it.text === "Single")
                            verify(it.display !== AbstractButton.IconOnly, spec[0] + ": " + it.objectName)
                }
                header.destroy()
            }
        }

        function test_wrappedHeaderSettles() {
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                for (let width = 440; width <= 1320; width += 40) {
                    header.width = width
                    wait(30)
                    const passes = header.layoutPasses
                    wait(150)
                    verify(header.layoutPasses - passes <= 1,
                           spec[0] + " at " + width + ": " + (header.layoutPasses - passes) + " passes after settling")
                }
                header.destroy()
            }
        }

        // Run / Stop is the only filled button of the bar; Run is 104 wide.
        function test_runIsTheOnlyFilledButton() {
            for (const spec of barSpecs()) {
                const header = makeHeader(spec)
                for (const it of header.barItems) {
                    if (it instanceof RunButton)
                        verify(it.width >= 104, spec[0] + " run width " + it.width)
                    else if (it.highlighted !== undefined)
                        verify(!it.highlighted, spec[0] + ": " + it.objectName + " is filled")
                }
                header.destroy()
            }
        }

        // Header icons are at least iconSizeL, larger than the title's cap height; the rows are
        // the token's height.
        function test_headerIconsAreLargerThanText() {
            const header = createTemporaryObject(headerComponent, root)
            header.closable = true
            header.layoutBar()
            compare(header.height, Theme.paneHeaderHeight)
            for (const name of ["exportButton", "resetButton", "helpButton", "closeButton"]) {
                const b = findChild(header, name)
                verify(b.iconSize >= Theme.iconSizeL, name)
                verify(b.iconSize > titleMetrics.tightBoundingRect("H").height, name)
                verify(b.width >= 32 && b.height >= 32, name)
            }
            verify(findChild(header, "paneTitle").font.pixelSize === Theme.fontSizeTitle)
        }

        // A primary parameter shows every value in full: stepped lists entry by entry, continuous
        // ranges at both ends.
        function test_fieldsShowTheWidestValue() {
            const header = makeHeader(barSpecs()[0])
            header.width = 1320
            header.layoutBar()
            const timeDiv = findChild(header, "timeDiv")
            const input = findChild(timeDiv, "valueInput")
            verify(timeDiv && input)
            for (let i = 0; i < 22; ++i) {
                timeDiv.currentIndex = i
                verify(input.contentWidth + input.leftPadding + input.rightPadding <= input.width + 0.01,
                       input.text + ": " + input.contentWidth + " in " + input.width)
            }
            timeDiv.currentIndex = 9
            compare(input.text, "1 ms/div")
            timeDiv.currentIndex = 8
            compare(input.text, "500 µs/div")
            for (const [name, texts] of [["startKnob", ["1 Hz", "100 mHz"]], ["amplitudeKnob", ["2.00 Vpk"]]]) {
                const bode = makeHeader(barSpecs()[1])
                const f = findChild(bode, name)
                const field = findChild(f, "valueInput")
                for (const v of [f.from, f.to, (f.from + f.to) / 2, f.from + (f.to - f.from) * 0.4]) {
                    f.value = v
                    verify(field.contentWidth + field.leftPadding + field.rightPadding <= field.width + 0.01,
                           name + " " + field.text + ": " + field.contentWidth + " in " + field.width)
                }
                bode.destroy()
            }
            header.destroy()
        }

        // The knob is Theme.knobSizeHeader, directly at the left of its field, on the header row; the arc is the accent
        // or the colour of the signal the parameter drives.
        function test_primaryParametersHaveKnobs() {
            const header = makeHeader(barSpecs()[1])
            header.width = 1320
            header.layoutBar()
            for (const name of ["startKnob", "stopKnob", "amplitudeKnob"]) {
                const f = findChild(header, name)
                verify(f.visible, name)
                const knob = f.field.knob
                compare(knob.size, Theme.knobSizeHeader)
                const kp = knob.mapToItem(header, 0, 0)
                const fp = findChild(f, "valueInput").mapToItem(header, 0, 0)
                verify(kp.x + Theme.knobSizeHeader <= fp.x, name + ": the knob is left of the value")
                verify(fp.x - (kp.x + Theme.knobSizeHeader) <= 48, name + ": the knob is next to its field")
                verify(kp.y >= 0 && kp.y % Theme.paneHeaderHeight + Theme.knobSizeHeader <= Theme.paneHeaderHeight, name)
            }
            compare(String(findChild(header, "amplitudeKnob").field.knob.accentColor), String(Theme.signalAo0))
            compare(String(findChild(header, "startKnob").field.knob.accentColor), String(Theme.accent))
            verify(findChild(header, "amplitudeKnob").toolTip.length > 0)
            verify(findChild(header, "startKnob").field.toolTip.indexOf("1 Hz") >= 0, "the tooltip gives the range")
            header.destroy()
        }

        // The title of the focused pane is primary text; the other pane of a split is secondary.
        function test_titleColourAndNoAccentLine() {
            const header = createTemporaryObject(headerComponent, root)
            const title = findChild(header, "paneTitle")
            compare(String(title.color), String(Theme.text))
            header.closable = true                      // a pane of a split
            compare(String(title.color), String(Theme.textSecondary))
            header.focused = true
            compare(String(title.color), String(Theme.text))
            for (const child of header.children) {
                if (child instanceof Rectangle && child.anchors.bottom === header.bottom)
                    compare(child.height, 1)
            }
        }

        // A short fact after the state is the first thing dropped, and may be cut.
        function test_detailGoesFirst() {
            const header = createTemporaryObject(headerComponent, root)
            header.detailText = "200 kS/s"
            header.width = 1100
            header.layoutBar()
            const detail = findChild(header, "paneDetail")
            verify(detail.visible)
            verify(detail.elideAllowed)
            header.width = 440
            header.layoutBar()
            verify(!detail.visible || detail.x + detail.width <= findChild(header, "helpButton").mapToItem(header, 0, 0).x)
        }

        function test_confirmVerbs() {
            const dialog = createTemporaryObject(confirmComponent, root, { acceptText: "Reset" })
            verify(dialog.acceptButton >= 0)
            dialog.acceptText = "Reset Settings"
            compare(dialog.acceptButton, -1)
            dialog.acceptText = "Quit"
            compare(dialog.acceptButton, -1)
            verify(dialog.inWindow)
            dialog.destructive = true
            dialog.open()
            let styled = null
            tryVerify(() => (styled = findChild(dialog, "confirmDialog")) !== null && dialog.opened)
            const accept = findChild(styled.footer, "confirmAcceptButton")
            compare(accept.text, "Quit")
            compare(styled.header.objectName, "confirmTitle")
            verify(!accept.highlighted)                     // destructive: not the accent primary
            const spy = createTemporaryObject(spyComponent, root, { target: dialog, signalName: "accepted" })
            tryVerify(() => accept.activeFocus)             // the verb is the default button
            keyClick(Qt.Key_Return)
            compare(spy.count, 1)
            tryCompare(styled, "visible", false)
        }

        // The 9 legacy panels build unchanged through the aliases.
        function test_v1Aliases() {
            const panel = createTemporaryObject(compatPanel, root)
            const header = panel.runBar
            compare(header, panel.paneHeader)
            verify(header.showTimeout)
            compare(header.timeoutText, "No input")
            compare(header.singleToolTip, "Take one reading")
            compare(header.detailText, "Sample Rate 50 kS/s")    // displayInfo → state detail
            compare(panel.displayArea.summary, "CH 0 · 5 ms/div") // displayTitle → display summary
            for (const name of ["autoscale", "logTool", "viewTool"]) {
                const item = findChild(header, name)
                verify(item, name)
                verify(item.visible, name)
            }
            verify(findChild(panel.displayArea, "displayContent"))
            verify(header.hasTraceStyles)
            verify(header.measurementsAvailable)
            verify(panel.measurementsVisible)
            panel.setMeasurementsVisible(false)
            verify(!panel.measurementsVisible)
            panel.setMeasurementsVisible(true)
            verify(findChild(panel, "ownBanner"))
            compare(panel.paneId, "gamma")
            compare(panel.paneTitle, "gamma")
        }

        // The title is never elided in a wide pane, and all action icons stay in a narrow one.
        function test_narrowHeader() {
            const panel = createTemporaryObject(contentPanel, root, { width: 1200 })
            const header = panel.paneHeader
            header.title = "A Rather Long Instrument Title"
            const reset = findChild(header, "resetButton")
            const title = findChild(header, "paneTitle")
            // Wide: room for the whole title whatever the font metrics (text can measure twice as wide offscreen on CI).
            panel.width = Math.max(1200, Math.ceil(title.implicitWidth / 0.3) + 20)
            waitForRendering(panel)
            verify(reset.visible)
            verify(!title.truncated, "title " + title.width + " of " + title.implicitWidth + " px, header "
                   + header.width + " px, font " + title.font.family + " " + title.font.pixelSize
                   + " px (base " + Theme.fontSizeBase + ")")
            panel.width = 480
            waitForRendering(panel)
            verify(header.narrow)
            verify(reset.visible)                                    // the icons do not fold into a menu
            for (const name of ["exportButton", "resetButton", "helpButton"]) {
                const icon = findChild(header, name)
                verify(icon.mapToItem(header, 0, 0).x + icon.width <= header.width, name)
            }
            panel.width = 900
            waitForRendering(panel)
            verify(reset.visible)
        }

        function test_resetButtonConfirms() {
            const panel = createTemporaryObject(compatPanel, root)
            const button = findChild(panel.paneHeader, "resetButton")
            verify(button)
            verify(button.visible)
            compare(button.Accessible.name, "Reset gamma to Defaults…")
            const help = findChild(panel.paneHeader, "helpButton")
            verify(button.mapToItem(panel.paneHeader, 0, 0).x < help.mapToItem(panel.paneHeader, 0, 0).x)
            mouseClick(button)
            let dialog = null
            tryVerify(() => (dialog = findChild(panel, "confirmDialog")) !== null && dialog.opened)
            compare(findChild(dialog.footer, "confirmAcceptButton").text, "Reset")
            mouseClick(findChild(dialog.footer, "confirmCancelButton"))
            tryCompare(dialog, "visible", false)
        }

        // Reset Settings… asks first (ConfirmDialog, in the window offscreen), then resets.
        function test_resetSettingsConfirms() {
            const panel = createTemporaryObject(compatPanel, root)
            panel.requestResetSettings()
            let dialog = null
            tryVerify(() => (dialog = findChild(panel, "confirmDialog")) !== null && dialog.opened)
            compare(dialog.title, "Reset gamma?")
            const accept = findChild(dialog.footer, "confirmAcceptButton")
            verify(accept)
            compare(accept.text, "Reset")
            mouseClick(accept)
            tryCompare(dialog, "visible", false)
            panel.requestResetSettings()
            tryVerify(() => dialog.opened)
            mouseClick(findChild(dialog.footer, "confirmCancelButton"))
            tryCompare(dialog, "visible", false)
        }
    }

    Component {
        id: spyComponent
        SignalSpy {}
    }

    Component {
        id: confirmComponent
        ConfirmDialog { title: "Quit?"; text: "Two instruments run." }
    }

    Component {
        id: deviceButtonComponent
        DeviceButton {}
    }

    TestCase {
        name: "DeviceButton"
        when: windowShown

        function test_menuAndLabel() {
            const button = createTemporaryObject(deviceButtonComponent, root)
            verify(DeviceHub.connected)
            verify(DeviceHub.simulated)
            compare(button.label, "Simulated myDAQ")
            const texts = root.menuTexts(button.menu)
            verify(texts.indexOf("Rescan") > 0, texts)
            verify(texts.indexOf("Reset Device…") > 0, texts)
            verify(texts.indexOf("Device Info…") > 0, texts)
            compare(texts[0], DeviceHub.name)                           // the devices come first
            verify((button.menu.itemAt(0) as MenuItem).checked)         // the current one
            if (DeviceHub.simulatorAvailable) {
                verify(texts.indexOf("Simulated Device") > 0, texts)
                compare(texts[texts.length - 1], "Simulator Settings…")
            }
            const spy = createTemporaryObject(spyComponent, root, { target: button.menu, signalName: "resetRequested" })
            const reset = button.menu.itemAt(texts.indexOf("Reset Device…")) as MenuItem
            verify(reset.enabled)
            reset.triggered()
            compare(spy.count, 1)
            button.requestSelect(DeviceHub.currentId)                   // same device: nothing
            compare(DeviceHub.connected, true)
        }

        // An attached myDAQ that cannot be opened (run with MYBENCH_FAKE_UNAVAILABLE=driver): the
        // menu says so and offers the way out; the labels are one to three words.
        function test_unavailableMyDaq() {
            if (DeviceHub.unavailableCount === 0)
                skip("set MYBENCH_FAKE_UNAVAILABLE=driver to run")
            const button = createTemporaryObject(deviceButtonComponent, root)
            const texts = root.menuTexts(button.menu)
            verify(texts.indexOf("myDAQ · Not available") >= 0, texts)
            verify(texts.indexOf("How to Fix: " + DeviceHub.unavailable[0].label) >= 0, texts)
            verify(DeviceHub.unavailable[0].label.split(" ").length <= 3)
            verify(DeviceHub.unavailable[0].hint.length > 0)
            verify(Help.has(DeviceHub.unavailable[0].helpTopic))
        }
    }
}
