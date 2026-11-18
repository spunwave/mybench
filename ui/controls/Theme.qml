pragma Singleton
import QtQuick
import MyBench.Framework

// Design tokens: every color, size and duration of the UI comes from here; never hard-code them.
// Colors derive from the effective palette: the system palette when its lightness matches the chosen
// mode, otherwise a built-in light or dark reference palette. Displays follow the theme;
// `alwaysDarkDisplays` keeps them dark in light mode.
QtObject {
    id: theme

    // --- Mode ----------------------------------------------------------------------------------
    // "system" (follow the platform), "light" or "dark" (the default). ThemeSync feeds it and writes
    // Application.styleHints.colorScheme for a forced mode.
    property string mode: "dark"
    property bool alwaysDarkDisplays: false
    // Animations can be turned off globally (screenshots, reduced motion).
    property bool animations: true
    // macOS unified title bar (the toolbar then sits beside the traffic lights).
    property bool unifiedTitleBar: false
    // Screenshot and test mode, and Wayland (where Qt places native menus and popup windows wrongly
    // or not at all): ComboBox lists, menus and context menus stay in-window popups (Popup.Item);
    // otherwise menus are native and lists are popup windows.
    property bool inlinePopups: AppInfo.offscreen || AppInfo.screenshot || Qt.platform.pluginName === "offscreen"
                                || Qt.platform.pluginName === "wayland"
    // Standard controls are drawn by a platform style (macOS, FluentWinUI3, Fusion, KDE) rather
    // than MyBench.Style (Preferences > Appearance > Controls, --style).
    readonly property bool nativeControls: AppInfo.nativeControls

    // The platform palette (QPalette through SystemPalette). Overridable, so tests and
    // `--system-palette` can play any platform. `platformProvided` is false where Qt reports no color
    // scheme (offscreen, CI): the reference palettes are used there.
    property color systemWindow: sysPalette.window
    property color systemBase: sysPalette.base
    property color systemText: sysPalette.windowText
    property color systemAccent: sysPalette.accent
    property color systemButton: sysPalette.button
    property color systemHighlight: sysPalette.highlight
    property color systemHighlightedText: sysPalette.highlightedText
    property color systemDisabledText: sysDisabledPalette.windowText
    property bool platformProvided: Qt.platform.pluginName !== "offscreen"
                                    && Application.styleHints.colorScheme !== Qt.Unknown
    // The desktop's own look: its color scheme, or the palette's lightness when it reports none.
    readonly property bool systemDark: Application.styleHints.colorScheme === Qt.Dark
                                       || (Application.styleHints.colorScheme === Qt.Unknown && luminance(systemWindow) < 0.5)
    readonly property bool dark: mode === "dark" || (mode !== "light" && systemDark)
    readonly property bool light: !dark
    // The system palette is used only when it matches the chosen light/dark look.
    readonly property bool followSystem: platformProvided && (luminance(systemWindow) < 0.5) === dark
    readonly property bool displayDark: dark || alwaysDarkDisplays

    property SystemPalette sysPalette: SystemPalette { colorGroup: SystemPalette.Active }
    property SystemPalette sysDisabledPalette: SystemPalette { colorGroup: SystemPalette.Disabled }

    // --- Reference palettes (what screenshots show; neutral, close to macOS and Breeze) --------
    readonly property color referenceDarkBase: "#1E1E1E"
    readonly property color referenceDarkText: "#E8E8E8"
    readonly property color referenceWindow: dark ? "#282828" : "#E8E9EC"
    readonly property color referenceBase: dark ? referenceDarkBase : "#FFFFFF"
    readonly property color referenceText: dark ? referenceDarkText : "#1F1F1F"
    readonly property color referenceButton: dark ? "#3A3A3A" : "#FFFFFF"
    readonly property color referenceAccent: dark ? "#2A72D9" : "#0A64D8"

    // --- Effective palette ---------------------------------------------------------------------
    readonly property color paletteWindow: followSystem ? systemWindow : referenceWindow
    readonly property color paletteBase: followSystem ? systemBase : referenceBase
    readonly property color paletteText: followSystem ? systemText : referenceText
    readonly property color paletteButton: followSystem ? systemButton : referenceButton
    // The user's accent color is kept even when the reference palette is shown.
    readonly property color paletteAccent: platformProvided ? systemAccent : referenceAccent
    readonly property color paletteHighlight: followSystem ? systemHighlight : accent
    readonly property color paletteHighlightedText: followSystem ? systemHighlightedText : accentText

    // --- Chrome --------------------------------------------------------------------------------
    readonly property color window: paletteWindow                    // toolbar, pane headers, inspector, status bar
    readonly property color sidebar: dark ? mix(window, "#000000", 0.04) : mix(window, paletteText, 0.04)
    readonly property color base: paletteBase                        // fields, tables, Overview, popups
    readonly property color separator: alpha(text, dark ? 0.16 : 0.15)   // every 1 px hairline
    readonly property color controlFill: paletteButton
    readonly property color controlBorder: alpha(text, dark ? 0.22 : 0.26)
    readonly property color controlBorderHover: alpha(text, dark ? 0.36 : 0.42)
    readonly property color controlTrack: alpha(text, dark ? 0.07 : 0.045)   // recessed group behind a segmented control
    readonly property color raisedFill: dark ? mix(controlFill, "#FFFFFF", 0.08) : "#FFFFFF"   // the selected segment
    readonly property color hoverFill: alpha(text, 0.05)
    readonly property color pressedFill: alpha(text, 0.09)
    // Instrument controls. Surface of the floating tool panels only (never a section of a pane).
    readonly property color cardFill: base
    // The pressed tool and the picked item of a tool strip; the only accent-tinted background.
    readonly property color accentSoft: alpha(accent, dark ? 0.20 : 0.12)
    // Knob only (face and ring at rest, hover, pressed): neutrals, never a channel colour.
    readonly property color knobFace: dark ? mix(base, text, 0.13) : mix(base, text, 0.015)
    readonly property color knobFaceHover: dark ? mix(base, text, 0.17) : mix(base, text, 0.04)
    readonly property color knobFacePressed: dark ? mix(base, text, 0.21) : mix(base, text, 0.07)
    readonly property color knobRing: alpha(text, dark ? 0.30 : 0.38)
    readonly property color knobRingHover: alpha(text, dark ? 0.45 : 0.48)
    readonly property color knobTick: textTertiary
    readonly property color selection: paletteHighlight
    readonly property color selectionText: contrast(paletteHighlightedText, selection) >= 4.5 ? paletteHighlightedText
                                                                                              : onColor(selection)
    readonly property color selectionInactive: alpha(text, 0.10)
    readonly property color overlay: Qt.rgba(0, 0, 0, dark ? 0.45 : 0.22)   // behind modal dialogs
    readonly property color shadowColor: Qt.rgba(0, 0, 0, dark ? 0.22 : 0.12)

    // --- Text ----------------------------------------------------------------------------------
    readonly property color text: paletteText
    readonly property color textSecondary: readable(mix(text, window, 0.30), window, 4.5)
    readonly property color textTertiary: readable(mix(text, window, 0.5), window, 3)
    readonly property color textDisabled: followSystem && contrast(systemDisabledText, window) < 0.7 * contrast(text, window)
                                          ? systemDisabledText : mix(text, window, 0.62)

    // --- Accent --------------------------------------------------------------------------------
    // The platform accent, adjusted to ≥ 3:1 on the window; where possible also darkened so white
    // text on it reaches 4.5:1 (otherwise the text on it is near-black).
    readonly property color accent: accentFor(paletteAccent, window)
    readonly property color accentText: contrast("#FFFFFF", accent) >= 4.5 ? "#FFFFFF"
                                      : contrast("#0B0B0D", accent) >= contrast("#FFFFFF", accent) ? "#0B0B0D" : "#FFFFFF"
    readonly property color accentHover: dark ? mix(accent, "#FFFFFF", 0.12) : mix(accent, "#000000", 0.10)
    readonly property color accentPressed: dark ? mix(accent, "#000000", 0.15) : mix(accent, "#000000", 0.20)
    // The one accent: selection and "on" states (switch track, focus ring, links, a checked picture
    // button); accentMuted and accentSoft are its only tinted backgrounds.
    readonly property color accentMuted: alpha(accent, dark ? 0.22 : 0.14)
    readonly property color focusRing: accent
    readonly property color link: accent

    // --- Status (state dots, banner icons, invalid field borders; never fills) ------------------
    // Status colours: a state dot, the banner icon, error text. Never a surface.
    readonly property color positive: dark ? "#3FB950" : "#1A7F37"
    readonly property color caution: dark ? "#D29922" : "#9A6700"
    readonly property color negative: dark ? "#F85149" : "#CF222E"
    // The Run / Stop button fills only (green to start, red to stop, white text >= 4.5:1).
    readonly property color runFill: "#1F883D"
    readonly property color stopFill: "#CF222E"

    // --- Displays (plots, readout surfaces) -----------------------------------------------------
    readonly property color display: !displayDark ? base
                                   : dark ? mix(base, "#000000", 0.35) : mix(referenceDarkBase, "#000000", 0.35)
    readonly property color displayText: displayDark && !dark ? referenceDarkText : text
    readonly property color displayTextSecondary: readable(mix(displayText, display, 0.30), display, 4.5)
    readonly property color plotGridMajor: alpha(displayText, 0.14)
    readonly property color plotGridMinor: alpha(displayText, 0.06)
    readonly property color plotFrame: alpha(displayText, 0.22)

    // --- Signal palette (channel identity only; on displays) ------------------------------------
    // Signal colours: a trace, an 8 px swatch beside the channel's name, the plot markers of that
    // channel. Never a fill, a stripe, a switch or a value's text.
    readonly property color signalCh0: displayDark ? "#4CC38A" : "#1E8E5A"    // CH0 / AI0 / Audio L in
    readonly property color signalCh1: displayDark ? "#3FB8E0" : "#0B7FAB"    // CH1 / AI1 / Audio R in
    readonly property color signalAo0: displayDark ? "#F2994A" : "#C25E0A"    // AO0 / Audio L out
    readonly property color signalAo1: displayDark ? "#E26FC0" : "#B4318F"    // AO1 / Audio R out
    readonly property color signalMath: displayDark ? "#E8C547" : "#9A7A00"
    readonly property color signalRef: displayDark ? "#A78BFA" : "#6D4FD8"
    readonly property color signalCursor: displayText                          // dashed and labelled
    // Cursor pairs (C1/C2, A/B): two hues no channel uses, so the pair reads apart at a glance.
    readonly property color signalCursor1: displayDark ? "#FF7A7A" : "#C62F3A"
    readonly property color signalCursor2: displayDark ? "#7FA7FF" : "#183F8C"
    // Default trace colors of plots (Plot.seriesColors), in order.
    readonly property var seriesColors: [signalCh0, signalCh1, signalMath, signalRef, signalAo1, signalAo0]

    function signalColor(name: string): color {
        switch (name) {
        case "ai0": case "ch0": case "audioInL": return signalCh0
        case "ai1": case "ch1": case "audioInR": return signalCh1
        case "ao0": case "audioOutL": return signalAo0
        case "ao1": case "audioOutR": return signalAo1
        case "math": return signalMath
        case "ref": case "dmm": return signalRef   // the DMM's trace (panel, tile, logger)
        case "cursor": return signalCursor
        case "cursor1": return signalCursor1
        case "cursor2": return signalCursor2
        }
        return displayText
    }

    // --- Typography ----------------------------------------------------------------------------
    readonly property string fontFamily: Fonts.uiFamily
    readonly property string monoFamily: Fonts.monoFamily
    // The platform UI font size (only offscreen screenshots force 13 px).
    readonly property int fontSizeBase: Fonts.uiPixelSize
    readonly property int fontSizeCaption: Math.max(10, fontSizeBase - 2)
    readonly property int fontSizeSmall: fontSizeBase - 1
    readonly property int fontSizeBody: fontSizeBase
    readonly property int fontSizeValue: fontSizeBase + 1             // DemiBold, tabular: the value in a field
    readonly property int fontSizeHeading: fontSizeBase + 1           // DemiBold: card titles
    readonly property int fontSizeTitle: fontSizeBase + 4             // DemiBold: the pane title
    readonly property int fontSizeReadoutM: fontSizeBase + 9          // DemiBold, tabular: a measurement value
    readonly property int fontSizeReadoutL: 2 * fontSizeBase
    readonly property int fontSizeReadoutXL: Math.round(4.5 * fontSizeBase)
    readonly property var tabularFigures: ({ "tnum": 1 })
    property FontMetrics bodyMetrics: FontMetrics {
        font.family: theme.fontFamily
        font.pixelSize: theme.fontSizeBody
    }
    // Height of a line of body text; control heights derive from it.
    readonly property int lineHeight: Math.ceil(bodyMetrics.height)

    // --- Metrics -------------------------------------------------------------------------------
    readonly property int spacingXs: 4
    readonly property int spacingS: 8
    readonly property int spacingM: 12
    readonly property int spacingL: 16
    readonly property int spacingXl: 24
    readonly property int formRowSpacing: 6        // between the rows of a form (Section content)

    readonly property int controlHeightS: lineHeight + 6     // plot toolbars, dense tables
    // Under MyBench.Style (the default) every platform has lineHeight + 10. Only when the user picks the
    // Native style do our fields match the platform controls beside them (macOS: 24).
    readonly property int nativeControlHeight: nativeControls && AppInfo.controlsStyle === "macOS" ? 24 : 0
    readonly property int controlHeight: nativeControlHeight > 0 ? nativeControlHeight : lineHeight + 12
    readonly property int controlHeightL: lineHeight + 16    // the Run button, dialog default buttons
    // Icons are always larger than the text beside them.
    readonly property int iconSize: 18            // inside a button, beside body text
    readonly property int iconSizeL: 22           // sidebar, pane title, header actions
    readonly property int iconSizeXL: 26          // tool palette, Overview tiles
    readonly property int knobSize: 40            // the knob of a setting row in a card
    readonly property int knobSizeHeader: 32      // the knob of a primary parameter in the pane header
    readonly property int radiusControl: 6
    readonly property int radiusCard: 8           // the cards of the control column, measurement strip corners
    readonly property int radiusPopup: 10         // popups, menus, dialogs, Overview tiles
    readonly property int borderWidth: 1
    readonly property int focusWidth: 2

    readonly property int toolbarHeight: unifiedTitleBar && macShortcuts ? 52 : 44
    readonly property int paneHeaderHeight: 44    // one row of the pane header
    readonly property int statusBarHeight: 24
    readonly property int measurementCardCompactMinWidth: 140   // the compact form's floor (caption and value only)
    readonly property int measurementCardMinWidth: 180   // a floor: a card is as wide as its widest value and statistics
    // Caption row (20), the value line, a margin: the wide form (statistics beside the value).
    readonly property int measurementCardHeight: 20 + Math.round(fontSizeReadoutM * 1.4) + 7
    // The same with two caption-size lines of statistics under the value: the tall form.
    readonly property int measurementCardTallHeight: 20 + Math.round(fontSizeReadoutM * 1.4) + 2 * Math.round(fontSizeCaption * 1.3) + 13
    readonly property int measurementRailWidth: 32
    readonly property int sidebarWidth: 160
    readonly property int sidebarCompactWidth: 56
    readonly property int inspectorWidth: 300
    readonly property int inspectorMinWidth: 260
    readonly property int inspectorMaxWidth: 420
    readonly property int minWindowWidth: 640
    readonly property int minWindowHeight: 480
    readonly property int splitMinWidth: 900
    readonly property int paneMinWidth: 450
    readonly property int shortHeight: 600
    // Instrument panels: the column of cards and knobs right of the display, its width below
    // `instrumentCompactWidth` (pane width), and the floating tool panels.
    readonly property int instrumentColumnWidth: 280
    readonly property int instrumentColumnCompactWidth: 256
    readonly property int instrumentCompactWidth: 1000
    // Pane layout contract: the controls sit at the right when the display keeps this width /
    // height ratio there (40 px hysteresis), else in a dock of fixed height.
    readonly property real paneAspect: 1.2
    readonly property int paneAspectHysteresis: 40
    // The height budget of a docked pane (InstrumentPanel), in this order: the header; the display,
    // at least dockDisplayMinHeight and displayMinShare of what the header leaves; the dock,
    // clamp(dockHeightRatio x what the header leaves, dockMinHeight, dockMaxHeight); the strip, one
    // row (more only while the display keeps its share).
    readonly property real dockHeightRatio: 0.35
    readonly property int dockMinHeight: 212
    readonly property int toolLaneDisplayMin: 240       // the display beside an open tool panel, when the pane allows
    readonly property int toolLaneMinWidth: 240
    readonly property int dockMinContentHeight: 120     // the shortest a dock gets around short cards
    readonly property int dockMaxHeight: 320
    readonly property int dockDisplayMinHeight: 200
    readonly property real displayMinShare: 0.47
    readonly property real stripColumnShare: 0.3
    readonly property int dockCardMinWidth: 248
    readonly property int dockTwoColumnsAt: 520       // pane width from which the dock has 2 columns of cards
    readonly property int dockThreeColumnsAt: 776
    readonly property int dockToolStripWidth: 40
    // A card: 36 px header band, 12 px padding, 8 px between rows and cards.
    readonly property int cardHeaderHeight: 36
    readonly property int cardPadding: 12
    readonly property int cardMargin: 8
    readonly property int cardRowSpacing: 8
    // The dense form of the cards in a dock (side by side, short panes): one label column per card
    // (`denseLabelWidth`), then the knob (knobSizeHeader) and the field on one control-height row.
    readonly property int denseLabelWidth: 68
    // Cards narrower than this keep the label above the field (a field must show "1.111 MHz" whole).
    readonly property int denseCardMinWidth: 280
    readonly property int knobRowHeight: 52
    readonly property int toolCellHeight: 52
    readonly property int pictureCellWidth: 56
    readonly property int pictureCellHeight: 48
    // Height of one row of measurement cards (the aspect rule counts one under the display).
    readonly property int measurementRowHeight: measurementCardHeight
    readonly property int toolPanelWidth: 300

    // Columns of a grid of `count` buttons at least `minWidth` wide: the fewest rows the width
    // allows, shared evenly over them (7 in 4 + 3, not 3 + 3 + 1).
    function balancedColumns(count: int, width: real, minWidth: real, spacing: real): int {
        if (count <= 0)
            return 1
        const fit = Math.max(1, Math.floor((width + spacing) / (minWidth + spacing)))
        const rows = Math.ceil(count / fit)
        return Math.ceil(count / rows)
    }

    // Drags snap: a dragged size or position within snapDistance of a target (the value a
    // double-click restores, the middle) takes the target.
    readonly property int snapDistance: 12
    function snapTo(value: real, targets: var, distance = -1): real {
        const d = distance >= 0 ? distance : snapDistance
        for (const t of targets) {
            if (Math.abs(value - t) < d)
                return t
        }
        return value
    }
    // Adaptive layout class of a window width.
    function layoutClass(width: real): string {
        if (width >= 1280)
            return "wide"
        if (width >= 1024)
            return "medium"
        if (width >= 760)
            return "narrow"
        return "compact"
    }

    // --- Elevation and motion ------------------------------------------------------------------
    // One shadow for popups, menus, dialogs and the overlay inspector (MultiEffect: blurMax =
    // shadowBlur, shadowBlur 1.0, shadowVerticalOffset = shadowOffsetY, shadowColor).
    readonly property int shadowBlur: 16
    readonly property int shadowOffsetY: 4
    readonly property int durationFast: animations ? 120 : 0
    readonly property int durationNormal: animations ? 200 : 0
    readonly property int easing: Easing.OutCubic
    readonly property int toolTipDelay: 600

    // --- Aliases (names older code still uses) --------------------------------------------------
    readonly property color surface: window
    readonly property color surfaceRaised: base
    readonly property color surfaceSunken: base
    readonly property color surfaceHover: hoverFill
    readonly property color border: separator
    readonly property color divider: separator
    readonly property color displayBorder: plotFrame
    readonly property color borderStrong: controlBorder
    readonly property color displayGrid: plotGridMajor
    readonly property color textMuted: textTertiary
    readonly property color success: positive
    readonly property color warning: caution
    readonly property color danger: negative
    readonly property color ch0: signalCh0
    readonly property color ch1: signalCh1
    readonly property color math: signalMath
    readonly property color ref: signalRef
    readonly property color cursor1: signalCursor1
    readonly property color cursor2: signalCursor2
    readonly property int spacingXxs: 2
    readonly property int radiusXs: 3
    readonly property int radiusS: radiusControl
    readonly property int radiusM: radiusControl
    readonly property int radiusL: radiusPopup
    readonly property int iconSizeS: 14
    readonly property int fontSizeXs: fontSizeCaption
    readonly property int fontSizeS: fontSizeCaption
    readonly property int fontSizeM: fontSizeSmall
    readonly property int fontSizeXl: fontSizeHeading

    // --- Helpers -------------------------------------------------------------------------------
    // Shortcut text for tooltips and key hints, from a portable sequence ("Ctrl+Shift+F"): on
    // macOS the native symbols ("⇧⌘F", Ctrl = Command in Qt), elsewhere the sequence itself.
    property bool macShortcuts: Qt.platform.os === "osx" || Qt.platform.os === "macos"
    function keys(sequence: string): string {
        if (!macShortcuts || sequence.length === 0)
            return sequence
        const parts = sequence.split("+")
        let key = parts.pop()
        if (key === "" && parts.length > 0 && parts[parts.length - 1] === "") {
            parts.pop()
            key = "+"
        }
        let mods = ""
        if (parts.indexOf("Meta") >= 0)
            mods += "⌃"
        if (parts.indexOf("Alt") >= 0)
            mods += "⌥"
        if (parts.indexOf("Shift") >= 0)
            mods += "⇧"
        if (parts.indexOf("Ctrl") >= 0)
            mods += "⌘"
        return mods + key
    }
    // Icon URL from a name in assets/icons (or a URL passed through).
    function icon(name: string): url {
        if (name.length === 0)
            return ""
        if (name.indexOf(":") >= 0 || name.indexOf("/") >= 0)
            return name
        return "qrc:/qt/qml/MyBench/Controls/icons/" + name + ".svg"
    }
    // Relative luminance (WCAG) and contrast ratio of two opaque colors.
    function luminance(c: color): real {
        const lin = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
    function contrast(a: color, b: color): real {
        const la = luminance(a), lb = luminance(b)
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
    }
    // A translucent color painted over an opaque one.
    function composite(c: color, background: color): color {
        return mix(Qt.rgba(background.r, background.g, background.b, 1), Qt.rgba(c.r, c.g, c.b, 1), c.a)
    }
    // `c` moved toward white (dark) / black (light) until it has `ratio` contrast on `bg`.
    function readable(c: color, bg: color, ratio: real): color {
        const target = luminance(bg) < 0.4 ? "#FFFFFF" : "#000000"
        let result = c
        for (let i = 0; i < 16 && contrast(result, bg) < ratio; ++i)
            result = mix(result, target, 0.12)
        return result
    }
    function accentFor(c: color, bg: color): color {
        const visible = readable(c, bg, 3)
        if (contrast("#FFFFFF", visible) >= 4.5)
            return visible
        let deeper = visible
        for (let i = 0; i < 24 && contrast("#FFFFFF", deeper) < 4.5; ++i)
            deeper = mix(deeper, "#000000", 0.05)
        return contrast(deeper, bg) >= 3 ? deeper : visible
    }
    function alpha(c: color, a: real): color {
        return Qt.rgba(c.r, c.g, c.b, a)
    }
    function mix(a: color, b: color, t: real): color {
        return Qt.rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t)
    }
    // A signal's colour as a quiet fill: the header of the card, measurement card or selector segment
    // that belongs to that signal (never a whole card).
    function tint(c: color): color {
        return alpha(c, dark ? 0.20 : 0.14)
    }
    // Readable color on top of `c` (white or near-black).
    function onColor(c: color): color {
        return contrast("#FFFFFF", c) >= contrast("#0B0B0D", c) ? "#FFFFFF" : "#0B0B0D"
    }
}
