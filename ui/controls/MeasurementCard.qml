pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework

// One measurement under the display: a flat cell of the MeasurementStrip with a caption row (signal
// swatch and name), the value in tabular figures and its statistics (min, max, mean, σ) as a 2 x 2
// block. Hover shows remove and a context menu; a click selects the card (`selected`, clicked()).
// Set `value` as a string, or `numericValue` and `unit` to have it formatted with Units.format.
//     MeasurementCard { title: "CH0 · RMS"; color: Theme.signalCh0; value: "707.1 mV"
//                       stats: ({ min: "706.4 mV", max: "708.0 mV", mean: "707.2 mV", stdDev: "0.31 mV" })
//                       onRemoveRequested: model.remove(index) }
Item {
    id: card

    // The form, set by the strip: wide (value, then the statistics at its right) or tall (caption,
    // value, the statistics under it in two columns).
    property bool tall: false
    // The third form, set by the strip when neither other form can show every card: the caption and
    // the value only (as tall as the wide form), the statistics in the tooltip, a σ in the caption's corner.
    property bool compact: false
    readonly property int cardHeight: tall && !compact ? Theme.measurementCardTallHeight : Theme.measurementCardHeight
    // A floor; the content decides above it. A card without statistics is a caption and a value: the compact floor.
    readonly property int baseWidth: hasFigures ? Theme.measurementCardMinWidth : Theme.measurementCardCompactMinWidth
    readonly property real valueLineHeight: Math.round(Theme.fontSizeReadoutM * 1.4)
    readonly property real figureLineHeight: Math.round(Theme.fontSizeCaption * 1.3)

    property string title
    property color color: Theme.accent
    property bool swatch: true                   // false: a value that belongs to no signal (neutral caption)
    property string value
    property var stats: ({})
    // Instead of min / max / mean / σ: other labelled figures, two per row ([{ name, text, color? }]).
    property var items: []
    // Tags before the title (the two cursors of a pair: [{ name: "C1", color }]).
    property var chips: []
    property real numericValue: NaN              // NaN: show `value`
    property real exactValue: NaN                // the unrounded number for the tooltip (with `unit`)
    property string unit
    property int significantDigits: 4
    property int stdDevDigits: Math.max(1, significantDigits - 1)
    // What the card shows: the formatted number, else `value`.
    readonly property string valueText: !isNaN(numericValue) ? Units.format(numericValue, unit, significantDigits) : value
    property Menu menu: null                     // replaces the built-in context menu
    property bool removable: true
    property bool selectable: true
    property bool selected: false
    property bool separator: true                // hairline at the right edge

    readonly property bool hasStats: stats !== null && stats !== undefined
                                     && ["min", "max", "mean", "stdDev"].some(k => String(stats[k] ?? "").length > 0)
    readonly property bool hovered: hover.hovered
    readonly property bool actionsShown: hovered || defaultMenu.visible || (menu?.visible ?? false) || menuButton.activeFocus || removeButton.activeFocus
    // What the block at the right of the value shows.
    readonly property var figures: items.length > 0 ? items
                                   : hasStats ? statNames.map(s => ({ name: s.name, text: statText(s.key) })) : []

    signal removeRequested()
    signal resetStatisticsRequested()
    signal clicked()

    // A statistic as shown: numbers formatted like the value, strings as given.
    function statText(key: string): string {
        const v = stats?.[key]
        if (v === undefined || v === null || v === "")
            return "—"
        if (typeof v === "number")
            return Units.format(v, unit, key === "stdDev" ? stdDevDigits : significantDigits)
        return String(v)
    }
    // The same at full precision (tooltip, Copy All).
    function exactText(key: string): string {
        const v = stats?.[key]
        if (v === undefined || v === null || v === "")
            return "—"
        return typeof v === "number" ? Units.format(v, unit, 9) : String(v)
    }
    readonly property var statNames: [ { key: "min", name: qsTr("min") }, { key: "max", name: qsTr("max") },
                                       { key: "mean", name: qsTr("mean") }, { key: "stdDev", name: "σ" } ]
    readonly property string exactValueText: !isNaN(exactValue) ? Units.format(exactValue, unit, 9)
                                             : !isNaN(numericValue) ? Units.format(numericValue, unit, 9)
                                             : valueText
    function statsLines(): string {
        return items.length > 0 ? items.map(i => i.name + " " + i.text).join("   ")
               : hasStats ? statNames.map(s => s.name + " " + exactText(s.key)).join("   ") : ""
    }
    function copyText(text: string) {
        clipboard.text = text
        clipboard.selectAll()
        clipboard.copy()
    }
    TextEdit {
        id: clipboard
        visible: false
    }

    // The widest value and statistics block seen so far set the minimum width: it only grows, so
    // the strip's columns do not jump while the readings change.
    property real valueSeen: 0
    property real statsWideSeen: 0
    property real statsTallSeen: 0
    readonly property real valueNow: valueLabel.implicitWidth
    // The statistics block's width in each form, from the widest cell of each column: wide, every
    // column as wide as its own cells; tall, two equal columns of the wider one.
    readonly property var statsWidths: {
        let c0 = 0, c1 = 0
        for (let i = 0; i < figRep.count; ++i) {
            const w = figRep.itemAt(i)?.implicitWidth ?? 0
            if (i % 2 === 0)
                c0 = Math.max(c0, w)
            else
                c1 = Math.max(c1, w)
        }
        return { wide: c0 + c1 + (c1 > 0 ? Theme.spacingS + 4 : 0),
                 tall: 2 * Math.max(c0, c1) + (c1 > 0 ? Theme.spacingS : 0) }
    }
    onValueNowChanged: valueSeen = Math.max(valueSeen, valueNow)
    onStatsWidthsChanged: {
        statsWideSeen = Math.max(statsWideSeen, statsWidths.wide)
        statsTallSeen = Math.max(statsTallSeen, statsWidths.tall)
    }
    Component.onCompleted: { valueSeen = valueNow; statsWideSeen = statsWidths.wide; statsTallSeen = statsWidths.tall }

    // The caption's intrinsic width, from text metrics of its own strings: independent of the form, the
    // size and the visibility of the card, so the strip's choice never depends on what it applied.
    TextMetrics { id: titleMetrics; text: card.title; font.pixelSize: Theme.fontSizeCaption }
    TextMetrics { id: glyphMetrics; text: "σ"; font.pixelSize: Theme.fontSizeCaption }
    readonly property real chipsWidth: {
        let w = 0
        for (const chip of chips)
            w += 8 + 3 + chipMetrics.advanceOf(chip.name) + 6
        return w
    }
    FontMetrics { id: chipMetrics; font.pixelSize: Theme.fontSizeCaption; font.weight: Font.DemiBold
                  function advanceOf(text: string): real { return advanceWidth(text) } }
    // Swatch, chips and title with the row's 6 px spacing (no σ), and the same with the σ of the compact form.
    readonly property real captionContent: (swatch ? 8 + 6 : 0) + chipsWidth + titleMetrics.advanceWidth
    readonly property real captionWidth: captionContent + 2 * Theme.spacingS + 1
    readonly property real captionWidthCompact: captionContent + (hasFigures ? 6 + glyphMetrics.advanceWidth : 0) + 2 * Theme.spacingS + 1
    readonly property real captionHeight: 4 + captionRow.implicitHeight
    readonly property bool hasFigures: figures.length > 0
    readonly property real wideMinimumWidth: Math.max(baseWidth, captionWidth,
                                                      Math.max(valueSeen, valueNow) + (hasFigures ? Theme.spacingM + Math.max(statsWideSeen, statsWidths.wide) : 0)
                                                      + 2 * Theme.spacingS + 1)
    readonly property real tallMinimumWidth: Math.max(baseWidth, captionWidth,
                                                      Math.max(valueSeen, valueNow) + 2 * Theme.spacingS + 1,
                                                      hasFigures ? Math.max(statsTallSeen, statsWidths.tall) + 2 * Theme.spacingS + 1 : 0)
    // Compact: the caption row and the value; the floor is the token, the content decides above it.
    readonly property real compactMinimumWidth: Math.max(Theme.measurementCardCompactMinWidth, captionWidthCompact,
                                                         Math.max(valueSeen, valueNow) + 2 * Theme.spacingS + 1)
    readonly property real minimumWidth: compact ? compactMinimumWidth : tall ? tallMinimumWidth : wideMinimumWidth
    implicitWidth: minimumWidth
    implicitHeight: cardHeight
    Layout.fillWidth: true
    Layout.minimumWidth: minimumWidth
    Layout.preferredWidth: minimumWidth
    Layout.preferredHeight: cardHeight
    Layout.alignment: Qt.AlignTop
    Accessible.role: Accessible.StaticText
    Accessible.name: title + ": " + valueLabel.text

    onSelectedChanged: {
        if (!selected || !parent)
            return
        for (const sibling of parent.children)
            if (sibling !== card && sibling.selected === true)
                sibling.selected = false
    }

    Rectangle {
        anchors.fill: parent
        color: card.hovered && !card.selected ? Theme.hoverFill : "transparent"
    }
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
        height: Theme.borderWidth
        color: Theme.separator
    }
    Rectangle {
        visible: card.separator
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: Theme.borderWidth
        color: Theme.separator
    }

    Rectangle {
        objectName: "captionTint"
        anchors { left: parent.left; top: parent.top }
        width: parent.width - (card.separator ? Theme.borderWidth : 0)
        height: card.captionHeight
        color: card.swatch ? Theme.tint(card.color) : Theme.alpha(Theme.text, 0.04)
    }
    Rectangle {
        objectName: "selectionOutline"
        visible: card.selected
        anchors.fill: parent
        anchors.rightMargin: card.separator ? Theme.borderWidth : 0
        anchors.bottomMargin: Theme.borderWidth
        color: "transparent"
        border.width: 2
        border.color: Theme.accent
    }

    HoverHandler { id: hover }
    TapHandler {
        acceptedButtons: Qt.LeftButton
        enabled: card.selectable
        onTapped: {
            card.selected = !card.selected
            card.clicked()
        }
    }
    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: (point, button) => card.openMenu(point.position.x, point.position.y)
    }
    function openMenu(x: real, y: real) {
        (card.menu ?? defaultMenu).popup(card, x, y)
    }

    readonly property string tipText: valueText.length > 0
        ? title + "\n" + exactValueText + (figures.length > 0 ? "\n" + statsLines() : "") : ""
    ToolTip.visible: hover.hovered && tipText.length > 0
    ToolTip.delay: Theme.toolTipDelay
    ToolTip.text: tipText

    RowLayout {
        id: captionRow
        anchors { left: parent.left; right: parent.right; top: parent.top; topMargin: 2
                  leftMargin: Theme.spacingS; rightMargin: Theme.spacingS + 1 }
        spacing: 6
        Rectangle {
            visible: card.swatch
            implicitWidth: 8
            implicitHeight: 8
            color: card.color
        }
        Repeater {
            model: card.chips
            delegate: Row {
                id: chip
                required property var modelData
                spacing: 3
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 8
                    height: 8
                    color: chip.modelData.color
                }
                Text {
                    text: chip.modelData.name
                    color: chip.modelData.color
                    font.pixelSize: Theme.fontSizeCaption
                    font.weight: Font.DemiBold
                }
            }
        }
        Text {
            objectName: "cardTitle"
            Layout.fillWidth: true
            text: card.title
            color: Theme.textSecondary
            font.pixelSize: Theme.fontSizeCaption
        }
        Text {
            objectName: "statsGlyph"
            visible: card.compact && card.figures.length > 0
            text: "σ"
            color: Theme.textTertiary
            font.pixelSize: Theme.fontSizeCaption
        }
    }

    // The hover actions float over the caption's right end (they take no room, so the minimum width
    // is the caption's own); an opaque backing keeps the title readable under them.
    Rectangle {
        objectName: "hoverActions"
        opacity: card.actionsShown ? 1 : 0
        anchors { right: parent.right; rightMargin: card.separator ? Theme.borderWidth : 0; top: parent.top }
        width: actionRow.width + 4
        height: card.captionHeight
        color: Theme.window
        Rectangle {
            anchors.fill: parent
            color: card.swatch ? Theme.tint(card.color) : Theme.alpha(Theme.text, 0.04)
        }
        Row {
            id: actionRow
            anchors { right: parent.right; rightMargin: 2; verticalCenter: parent.verticalCenter }
            spacing: 0
            IconButton {
                id: menuButton
                objectName: "menuButton"
                opacity: card.actionsShown ? 1 : 0
                iconName: "more-horizontal"
                size: 16
                iconSize: 12
                toolTip: qsTr("Options")
                onClicked: { const p = menuButton.mapToItem(card, 0, menuButton.height); card.openMenu(p.x, p.y) }
            }
            IconButton {
                id: removeButton
                objectName: "removeButton"
                opacity: card.actionsShown ? 1 : 0
                visible: card.removable
                iconName: "close"
                size: 16
                iconSize: 10
                toolTip: qsTr("Remove Measurement")
                Accessible.name: qsTr("Remove %1").arg(card.title)
                onClicked: card.removeRequested()
            }
        }
    }

    Text {
        id: valueLabel
        objectName: "cardValue"
        x: Theme.spacingS
        y: card.captionHeight
        height: card.tall && !card.compact ? card.valueLineHeight : card.height - card.captionHeight - Theme.borderWidth
        verticalAlignment: Text.AlignVCenter
        text: card.valueText.length > 0 ? card.valueText : "—"
        color: Theme.text
        font.pixelSize: Theme.fontSizeReadoutM
        font.weight: Font.DemiBold
        font.features: Theme.tabularFigures
        wrapMode: Text.NoWrap
    }

    GridLayout {
        id: statsGrid
        objectName: "cardStats"
        visible: card.figures.length > 0 && !card.compact
        x: card.tall ? Theme.spacingS : card.width - Theme.spacingS - 1 - width
        y: card.tall ? card.captionHeight + card.valueLineHeight
                     : valueLabel.y + (valueLabel.height - height) / 2
        width: card.tall ? card.width - 2 * Theme.spacingS - 1 : implicitWidth
        columns: card.tall ? 2 : 4
        columnSpacing: card.tall ? Theme.spacingS : 4
        uniformCellWidths: card.tall
        rowSpacing: 0
        Repeater {
            id: figRep
            model: card.figures
            delegate: Item {
                id: cell
                required property var modelData
                required property int index
                Layout.columnSpan: card.tall ? 1 : 2
                Layout.fillWidth: true
                Layout.leftMargin: card.tall || index % 2 === 0 ? 0 : Theme.spacingS
                implicitWidth: nameLabel.implicitWidth + 4 + figure.implicitWidth
                implicitHeight: Math.max(figure.implicitHeight, card.tall ? card.figureLineHeight : 0)
                Text {
                    id: nameLabel
                    text: cell.modelData.name
                    color: cell.modelData.color ?? Theme.textTertiary
                    font.pixelSize: Theme.fontSizeCaption
                }
                Text {
                    id: figure
                    objectName: "figure_" + cell.index
                    anchors.right: parent.right
                    text: cell.modelData.text.length > 0 ? cell.modelData.text : "—"
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    font.features: Theme.tabularFigures
                }
            }
        }
    }

    Menu {
        id: defaultMenu
        MenuItem {
            text: qsTr("Copy Value")
            onTriggered: card.copyText(card.exactValueText)
        }
        MenuItem {
            text: qsTr("Copy All")
            onTriggered: card.copyText([card.title, card.exactValueText].concat(card.figures.length > 0 ? [card.statsLines()] : []).join("\t"))
        }
        MenuItem {
            text: qsTr("Reset Statistics")
            enabled: card.hasStats
            onTriggered: card.resetStatisticsRequested()
        }
        MenuSeparator { visible: card.removable }
        MenuItem {
            visible: card.removable
            height: visible ? implicitHeight : 0
            text: qsTr("Remove")
            onTriggered: card.removeRequested()
        }
    }
}
