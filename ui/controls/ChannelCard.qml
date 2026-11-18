pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

// A flat section of an instrument's control column: a header row (8 px swatch in the channel
// colour, name, optional secondary subtitle, the on/off switch at the right edge), then the items
// declared inside as form rows on an 8 px padding (KnobFields, selectors, fields). Unchecked, the
// body stays (dimmed, still usable); `collapseWhenOff: true` folds it. Controlled: bind `checked`, apply toggled().
//     ChannelCard { title: "CH 0"; subtitle: "AI 0"; color: Theme.signalCh0
//                   checked: ch.enabled; onToggled: on => ch.enabled = on
//                   KnobField { label: qsTr("Scale"); ... } }
Item {
    id: card

    property string title
    property string subtitle
    property color color: "transparent"           // the signal's colour (transparent: the card belongs to no signal)
    readonly property bool signalled: color.a > 0
    property bool checked: true
    property bool checkable: true                // false: no switch (e.g. References)
    property bool collapseWhenOff: false         // true: unchecked = header only
    property var facts: []                       // short secondary line under the body ("±2 V · AC")
    property bool compact: false
    property alias headerExtras: headerExtrasRow.data   // small items left of the switch
    default property alias content: body.data
    // Where the closing hairline goes ("bottom" | "right" | "none"); a band puts it at the right.
    property string separatorSide: "bottom"
    // The InstrumentColumn this section sits in (a band sets the section's position and width).
    property var host: null
    readonly property bool inBand: host !== null && host.horizontal
    // A real card (Theme.base fill, hairline border, rounded, 8 px from its neighbours) in the column
    // or dock an InstrumentPanel builds; flat sections elsewhere (tool panels, not yet converted columns).
    readonly property bool carded: host !== null && host.managed === true
    Component.onCompleted: {
        for (let p = parent; p; p = p.parent) {
            if (p.isInstrumentColumn === true) {
                host = p
                break
            }
        }
        if (host)
            host.measure()
    }
    onImplicitHeightChanged: if (host) host.measure()
    onVisibleChanged: if (host) host.measure()
    readonly property real padding: carded ? Theme.cardPadding : Theme.spacingS
    // In a dock (a band of the panel's InstrumentColumn): the dense form rows
    // (Theme.denseLabelWidth).
    readonly property bool dense: carded && inBand && width >= Theme.denseCardMinWidth
    readonly property bool active: checked || !checkable      // on (full-strength body)
    readonly property bool expanded: active || !collapseWhenOff
    readonly property bool hasBody: body.children.length > 0 || facts.length > 0
    // Folded by the host when its cards do not fit (the dock's column, the side column): the header
    // only, with a chevron; a click on the header opens it (the host folds a neighbour instead).
    property bool folded: false
    readonly property bool foldable: carded && expanded && hasBody
    readonly property real openHeight: carded ? column.implicitHeight + Theme.cardMargin + 2
                                              : column.implicitHeight + (separatorSide === "bottom" ? 1 : 0)
    readonly property real foldedHeight: carded ? header.implicitHeight + Theme.cardMargin + 2
                                                : header.implicitHeight + (separatorSide === "bottom" ? 1 : 0)

    signal toggled(bool checked)

    implicitWidth: Math.max(Theme.dockCardMinWidth, column.implicitWidth)
    implicitHeight: folded && foldable ? foldedHeight : openHeight
    Accessible.role: Accessible.Grouping
    Accessible.name: subtitle.length > 0 ? title + " " + subtitle : title

    Rectangle {
        id: surface
        visible: card.carded
        anchors.fill: parent
        anchors.leftMargin: Theme.cardMargin
        anchors.rightMargin: Theme.cardMargin
        anchors.topMargin: Theme.cardMargin / 2
        anchors.bottomMargin: Theme.cardMargin / 2
        radius: Theme.radiusCard
        color: Theme.base
    }

    Flickable {
        id: scroller
        anchors.fill: parent
        anchors.leftMargin: card.carded ? Theme.cardMargin + 1 : 0
        anchors.rightMargin: card.carded ? Theme.cardMargin + 1 : (card.separatorSide === "right" ? 1 : 0)
        anchors.topMargin: card.carded ? Theme.cardMargin / 2 + 1 : 0
        anchors.bottomMargin: card.carded ? Theme.cardMargin / 2 + 1 : 0
        contentWidth: width
        contentHeight: column.implicitHeight
        interactive: false
        clip: card.folded

    ColumnLayout {
        id: column
        width: scroller.width
        spacing: 0

        Item {
            id: header
            objectName: "channelHeader"
            Layout.fillWidth: true
            implicitHeight: card.carded ? Theme.cardHeaderHeight - (card.dense ? 4 : 0) : Theme.cardHeaderHeight - 8
            implicitWidth: headerRow.implicitWidth + 2 * card.padding

            Rectangle {
                objectName: "channelHeaderTint"
                anchors.fill: parent
                visible: card.signalled && card.active
                // Opaque (the tint over the card), so the patch below does not lay it twice.
                color: Theme.composite(Theme.tint(card.color), Theme.base)
                radius: card.carded ? Theme.radiusCard - 1 : 0
                Rectangle {
                    visible: card.carded && !card.folded
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: parent.radius
                    color: parent.color
                }
            }

            TapHandler {
                enabled: card.checkable || (card.folded && card.foldable)
                onTapped: {
                    if (card.folded && card.foldable && card.host)
                        card.host.unfold(card)
                    else if (card.checkable)
                        card.toggled(!card.checked)
                }
            }
            HoverHandler {
                enabled: card.folded && card.foldable
                cursorShape: Qt.PointingHandCursor
            }

            RowLayout {
                id: headerRow
                anchors.fill: parent
                anchors.leftMargin: card.padding
                anchors.rightMargin: card.padding
                spacing: Theme.spacingS

                Rectangle {
                    implicitWidth: card.carded ? 10 : 8
                    implicitHeight: card.carded ? 10 : 8
                    visible: card.signalled
                    color: card.color
                    opacity: card.active ? 1 : 0.4
                }
                Text {
                    text: card.title
                    color: card.active ? Theme.text : Theme.textSecondary
                    font.pixelSize: Theme.fontSizeHeading
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Text {
                    Layout.fillWidth: true
                    visible: card.subtitle.length > 0
                    text: card.subtitle
                    color: Theme.textSecondary
                    font.pixelSize: Theme.fontSizeCaption
                    elide: Text.ElideRight
                }
                Item {
                    visible: card.subtitle.length === 0
                    Layout.fillWidth: true
                }
                Icon {
                    objectName: "foldChevron"
                    visible: card.folded && card.foldable
                    name: "chevron-down"
                    size: Theme.iconSizeS
                    color: Theme.textSecondary
                }
                RowLayout {
                    id: headerExtrasRow
                    spacing: Theme.spacingXs
                    visible: children.length > 0
                }
                ToggleSwitch {
                    id: toggle
                    objectName: "channelSwitch"
                    visible: card.checkable
                    checked: card.checked
                    accentColor: card.signalled ? card.color : Theme.accent
                    padding: 0
                    Accessible.name: qsTr("%1 on").arg(card.title)
                    onToggled: {
                        const on = checked
                        checked = Qt.binding(() => card.checked)
                        card.toggled(on)
                    }
                }
            }
        }

        ColumnLayout {
            objectName: "channelBody"
            visible: card.expanded && card.hasBody
            enabled: !card.folded
            Layout.fillWidth: true
            Layout.leftMargin: card.padding
            Layout.rightMargin: card.padding
            Layout.topMargin: card.carded ? Theme.cardPadding - (card.dense ? 2 : 0) : 0
            Layout.bottomMargin: card.padding - (card.dense ? 2 : 0)
            spacing: card.dense ? Theme.cardRowSpacing - 4 : card.carded ? Theme.cardRowSpacing : Theme.spacingXs
            opacity: card.active ? 1 : 0.55
            // KnobFields inside use the form row layout.
            property bool formHost: true
            property bool dense: card.dense
            // The arc and pointer of the knobs inside: the card's signal colour, else the accent.
            property color knobColor: card.signalled ? card.color : Theme.accent

            ColumnLayout {
                id: body
                Layout.fillWidth: true
                visible: children.length > 0
                spacing: card.dense ? Theme.cardRowSpacing - 4 : card.carded ? Theme.cardRowSpacing : Theme.spacingXs
            }

            Text {
                visible: card.facts.length > 0
                Layout.fillWidth: true
                text: card.facts.join("  ·  ")
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeCaption
                font.features: Theme.tabularFigures
                elide: Text.ElideRight
            }
        }
    }
    }

    Rectangle {
        visible: card.carded
        anchors.fill: surface
        radius: Theme.radiusCard
        color: "transparent"
        border.width: 1
        border.color: Theme.separator
    }
    Rectangle {
        visible: card.separatorSide !== "none" && !card.carded
        color: Theme.separator
        x: card.separatorSide === "right" ? parent.width - 1 : 0
        y: card.separatorSide === "right" ? 0 : parent.height - 1
        width: card.separatorSide === "right" ? 1 : parent.width
        height: card.separatorSide === "right" ? parent.height : 1
    }
}
