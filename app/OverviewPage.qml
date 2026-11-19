pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Templates as T
import MyBench.Framework
import MyBench.Controls

// Overview, the first sidebar entry: the device card (name, state, wiring, icon
// buttons), the recent sessions card and every instrument as a tile (pinned ones first) that fills
// the window: the rows share the height left, down to 170 px; below that the page scrolls vertically.
// No sentence at rest: explanations are tooltips.
Rectangle {
    id: page

    required property WorkspaceState workspace
    required property AppActions actions

    // A myDAQ is attached but cannot be opened (NI driver, permission, in use) and nothing else is selected.
    readonly property bool notAvailable: DeviceHub.unavailableCount > 0 && DeviceHub.currentId.length === 0
    readonly property var firstUnavailable: DeviceHub.unavailableCount > 0 ? DeviceHub.unavailable[0] : null
    readonly property bool wideTop: width >= 640
    readonly property int minimumTileHeight: 170
    // Pinned instruments first ("Pin to Top"), then the sidebar order.
    readonly property var tileIds: {
        const ids = InstrumentRegistry.ids
        const pinned = Launcher.favorites.filter(id => ids.indexOf(id) >= 0)
        return pinned.concat(ids.filter(id => pinned.indexOf(id) < 0))
    }

    function shortDate(value: var): string {
        if (!value)
            return ""
        const date = new Date(value)
        if (isNaN(date.getTime()))
            return ""
        const now = new Date()
        if (date.toDateString() === now.toDateString())
            return Qt.formatTime(date, Qt.locale().timeFormat(Locale.ShortFormat))
        return date.toLocaleDateString(Qt.locale(), Locale.ShortFormat)
    }

    color: Theme.base

    component Heading: Text {
        color: Theme.text
        font.pixelSize: Theme.fontSizeHeading
        font.weight: Font.DemiBold
    }
    component Secondary: Text {
        color: Theme.textSecondary
        font.pixelSize: Theme.fontSizeSmall
        elide: Text.ElideRight
    }

    // An icon-only action: a flat tool button with its name as the tooltip.
    component IconAction: ToolButton {
        id: iconAction
        property string iconName
        property string tip
        implicitWidth: Theme.controlHeight
        implicitHeight: Theme.controlHeight
        icon.source: Theme.icon(iconName)
        icon.width: Theme.iconSize
        icon.height: Theme.iconSize
        Accessible.name: tip
        ToolTip.visible: hovered
        ToolTip.delay: Theme.toolTipDelay
        ToolTip.text: tip
    }
    component Card: Rectangle {
        color: Theme.base
        radius: Theme.radiusPopup
        border.width: Theme.borderWidth
        border.color: Theme.separator
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.height + 2 * Theme.spacingL
        boundsBehavior: Flickable.StopAtBounds
        clip: true
        ScrollBar.vertical: ScrollBar {}

        ColumnLayout {
            id: column
            x: Theme.spacingL
            y: Theme.spacingL
            width: flick.width - 2 * Theme.spacingL
            // The window's height when the content fits, the content's own when it does not.
            height: Math.max(flick.height - 2 * Theme.spacingL, implicitHeight)
            spacing: Theme.spacingM

            // --- Device and recent sessions --------------------------------------------------
            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: false
                Layout.maximumHeight: implicitHeight
                columns: page.wideTop ? 2 : 1
                columnSpacing: Theme.spacingM
                rowSpacing: Theme.spacingM

                // Device: name and state with the actions as icons, then the wiring (simulated)
                // or the product and serial number.
                Card {
                    objectName: "overviewDevice"
                    Layout.fillWidth: true
                    Layout.preferredWidth: 3
                    Layout.fillHeight: true
                    implicitHeight: deviceColumn.implicitHeight + 2 * Theme.spacingM

                    ColumnLayout {
                        id: deviceColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingS

                        RowLayout {
                            id: deviceHeader
                            Layout.fillWidth: true
                            spacing: Theme.spacingS
                            Icon {
                                id: deviceIcon
                                name: DeviceHub.simulated ? "cpu" : "usb"
                                size: Theme.iconSizeXL
                                color: Theme.textSecondary
                            }
                            ColumnLayout {
                                id: deviceTitle
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 0
                                Heading {
                                    objectName: "overviewDeviceHeading"
                                    Layout.fillWidth: true
                                    text: DeviceHub.currentId.length > 0 ? DeviceHub.name
                                        : DeviceHub.unavailableCount > 0 ? qsTr("myDAQ") : qsTr("No device")
                                    elide: Text.ElideRight
                                }
                                Row {
                                    spacing: Theme.spacingXs + 2
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: Theme.spacingS - 1
                                        height: width
                                        radius: width / 2
                                        color: DeviceHub.connectionState === DeviceHub.Connected ? Theme.positive
                                             : DeviceHub.connectionState === DeviceHub.Resetting || page.notAvailable ? Theme.caution
                                             : Theme.negative
                                    }
                                    Secondary {
                                        objectName: "overviewDeviceState"
                                        text: DeviceHub.connectionState === DeviceHub.Connected ? qsTr("Connected")
                                            : DeviceHub.connectionState === DeviceHub.Resetting ? qsTr("Resetting")
                                            : DeviceHub.connectionState === DeviceHub.Disconnected ? qsTr("Disconnected")
                                            : page.notAvailable ? qsTr("Not available")
                                            : qsTr("Not connected")
                                    }
                                }
                            }
                            // The selling points beside the name where they fit (the card keeps its
                            // height, so the tiles keep theirs); otherwise on their own row below.
                            Row {
                                id: headerSellingPoints
                                objectName: "overviewSellingPointsHeader"
                                readonly property bool wanted: !DeviceHub.connected || DeviceHub.simulated
                                readonly property bool fits: deviceHeader.width - deviceIcon.width - deviceTitle.implicitWidth
                                                             - deviceButtons.implicitWidth - 3 * deviceHeader.spacing
                                                             - Theme.spacingM >= implicitWidth
                                visible: wanted && fits
                                Layout.alignment: Qt.AlignVCenter
                                spacing: Theme.spacingS
                                FeatureChip {
                                    iconName: "check"
                                    tone: Theme.positive
                                    text: qsTr("No NI software needed")
                                    toolTip: qsTr("mybench has its own USB driver: no NI-DAQmx or ELVISmx install. On Windows it also works next to them")
                                }
                                FeatureChip {
                                    iconName: "device"
                                    text: qsTr("macOS · Windows · Linux")
                                }
                            }
                            RowLayout {
                                id: deviceButtons
                                objectName: "overviewDeviceButtons"
                                spacing: Theme.spacingXs
                                IconAction {
                                    objectName: "overviewInfo"
                                    iconName: "info"
                                    enabled: page.actions.deviceInfo.enabled
                                    tip: page.actions.deviceInfo.text
                                    onClicked: page.actions.deviceInfo.trigger()
                                }
                                IconAction {
                                    objectName: "overviewReset"
                                    iconName: "power"
                                    enabled: page.actions.resetDevice.enabled
                                    tip: page.actions.resetDevice.text
                                    onClicked: page.actions.resetDevice.trigger()
                                }
                                IconAction {
                                    objectName: "overviewResetAll"
                                    iconName: "reset"
                                    tip: qsTr("Reset All Instruments…")
                                    onClicked: page.actions.resetAllInstruments.trigger()
                                }
                                IconAction {
                                    objectName: "overviewSimulator"
                                    iconName: "settings"
                                    visible: DeviceHub.simulated
                                    tip: page.actions.simulatorSettings.text
                                    onClicked: page.actions.simulatorSettings.trigger()
                                }
                            }
                        }
                        // Without a usable myDAQ: the demo device in one click, and what is wrong with a
                        // myDAQ that is attached but not available.
                        Flow {
                            objectName: "overviewDeviceActions"
                            Layout.fillWidth: true
                            spacing: Theme.spacingS
                            visible: !DeviceHub.connected || page.firstUnavailable !== null
                            Button {
                                objectName: "overviewUseDemo"
                                visible: !DeviceHub.connected && DeviceHub.simulatorAvailable
                                highlighted: true
                                icon.source: Theme.icon("cpu")
                                text: qsTr("Use Demo")
                                onClicked: {
                                    DeviceHub.simulatorPlugged = true
                                    DeviceHub.select("sim:0")
                                }
                            }
                            FeatureChip {
                                objectName: "overviewUnavailable"
                                visible: page.firstUnavailable !== null
                                iconName: "warning"
                                tone: Theme.caution
                                text: page.firstUnavailable ? qsTr("myDAQ: %1").arg(page.firstUnavailable.label) : ""
                                toolTip: page.firstUnavailable ? page.firstUnavailable.hint : ""
                            }
                            Button {
                                // Windows: "ni": NI software has the myDAQ, take it now (that program loses it).
                                // "setup": no driver and no mybench-usb service: one click + one UAC prompt.
                                objectName: "overviewSetUpDriver"
                                readonly property bool fromNi: page.firstUnavailable !== null && page.firstUnavailable.kind === "ni"
                                visible: fromNi || (page.firstUnavailable !== null && page.firstUnavailable.kind === "setup"
                                                    && DeviceHub.driverSetupAvailable)
                                enabled: !DeviceHub.driverSetupRunning
                                highlighted: true
                                icon.source: Theme.icon("device")
                                text: fromNi ? qsTr("Use in mybench")
                                             : DeviceHub.driverSetupRunning ? qsTr("Setting Up…") : qsTr("Set Up myDAQ")
                                onClicked: DeviceHub.setUpDriver()
                            }
                            Button {
                                // Windows: mybench borrows the myDAQ from NI's driver while it runs; this gives
                                // it back now (it goes back by itself when mybench closes).
                                objectName: "overviewReleaseToNi"
                                visible: DeviceHub.canReleaseToNi && DeviceHub.connected
                                enabled: !DeviceHub.driverSetupRunning
                                flat: true
                                icon.source: Theme.icon("device")
                                text: qsTr("Give to NI Software")
                                ToolTip.visible: hovered
                                ToolTip.text: qsTr("mybench borrows the myDAQ while it runs, and NI ELVISmx, NI MAX and LabVIEW get it back "
                                                   + "when you close mybench. This gives it to them now.")
                                onClicked: DeviceHub.releaseDriver()
                            }
                            Button {
                                objectName: "overviewHowToFix"
                                visible: page.firstUnavailable !== null
                                flat: true
                                icon.source: Theme.icon("help-circle")
                                text: qsTr("How to Fix")
                                onClicked: Help.show("device")
                            }
                        }
                        Flow {
                            objectName: "overviewSellingPoints"
                            Layout.fillWidth: true
                            spacing: Theme.spacingS
                            visible: headerSellingPoints.wanted && !headerSellingPoints.fits
                            FeatureChip {
                                iconName: "check"
                                tone: Theme.positive
                                text: qsTr("No NI software needed")
                                toolTip: qsTr("mybench has its own USB driver: no NI-DAQmx or ELVISmx install. On Windows it also works next to them")
                            }
                            FeatureChip {
                                iconName: "device"
                                text: qsTr("macOS · Windows · Linux")
                            }
                        }
                        // The simulated device's wiring (why AI 0 / AI 1 show what AO 0 generates),
                        // and the device's own figures.
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            spacing: Theme.spacingL
                            SimWiring {
                                Layout.maximumWidth: 340
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                visible: DeviceHub.simulated
                                background: Theme.base
                            }
                            Item { Layout.fillWidth: true; visible: DeviceHub.simulated }
                            TileStat {
                                Layout.fillWidth: false
                                Layout.preferredWidth: 90
                                visible: !DeviceHub.simulated && DeviceHub.serialNumber.length > 0
                                label: qsTr("Serial")
                                value: DeviceHub.serialNumber
                            }
                            TileStat {
                                Layout.fillWidth: false
                                Layout.preferredWidth: 90
                                visible: DeviceHub.maxAiRate > 0
                                label: qsTr("AI rate")
                                value: Units.format(DeviceHub.maxAiRate, "S/s", 3)
                            }
                            TileStat {
                                Layout.fillWidth: false
                                Layout.preferredWidth: 90
                                visible: DeviceHub.maxAoRate > 0
                                label: qsTr("AO rate")
                                value: Units.format(DeviceHub.maxAoRate, "S/s", 3)
                            }
                        }
                    }
                }

                // Recent sessions (up to three).
                Card {
                    objectName: "overviewSessions"
                    Layout.fillWidth: true
                    // Narrow while there is nothing to list.
                    Layout.preferredWidth: SessionManager.recentSessions.length > 0 ? 2 : 1
                    Layout.fillHeight: true
                    implicitHeight: sessionsColumn.implicitHeight + 2 * Theme.spacingM

                    ColumnLayout {
                        id: sessionsColumn
                        anchors.fill: parent
                        anchors.margins: Theme.spacingM
                        spacing: Theme.spacingXs

                        // Title and count on the device card's two lines (the headings align).
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Theme.spacingS
                            Icon {
                                name: "layers"
                                size: Theme.iconSizeXL
                                color: Theme.textSecondary
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.minimumWidth: 0
                                spacing: 0
                                Heading {
                                    objectName: "overviewSessionsHeading"
                                    Layout.fillWidth: true
                                    text: qsTr("Recent Sessions")
                                    elide: Text.ElideRight
                                }
                                Secondary {
                                    objectName: "overviewNoSessions"
                                    Layout.fillWidth: true
                                    text: SessionManager.recentSessions.length === 0 ? qsTr("None")
                                          : SessionManager.recentSessions.length === 1 ? qsTr("1 file")
                                          : qsTr("%1 files").arg(SessionManager.recentSessions.length)
                                    HoverHandler { id: noSessionsHover }
                                    ToolTip.visible: noSessionsHover.hovered && SessionManager.recentSessions.length === 0
                                    ToolTip.delay: Theme.toolTipDelay
                                    ToolTip.text: qsTr("Saved layouts and settings")
                                }
                            }
                            IconAction {
                                objectName: "overviewOpen"
                                iconName: "folder-open"
                                tip: page.actions.openSession.text
                                onClicked: page.actions.openSession.trigger()
                            }
                        }
                        Repeater {
                            model: SessionManager.recentSessions.slice(0, 3)
                            // A template delegate: the row look is ours (hover fill below).
                            delegate: T.ItemDelegate {
                                id: sessionRow
                                required property var modelData
                                Layout.fillWidth: true
                                Layout.leftMargin: -Theme.spacingS
                                Layout.rightMargin: -Theme.spacingS
                                implicitWidth: implicitContentWidth + leftPadding + rightPadding
                                implicitHeight: Math.max(Theme.controlHeightS, implicitContentHeight + topPadding + bottomPadding)
                                padding: Theme.spacingXs
                                leftPadding: Theme.spacingS
                                rightPadding: Theme.spacingS
                                hoverEnabled: true
                                enabled: modelData.exists
                                opacity: enabled ? 1 : 0.5
                                background: Rectangle {
                                    radius: Theme.radiusControl
                                    color: sessionRow.down ? Theme.pressedFill
                                           : sessionRow.hovered ? Theme.hoverFill : "transparent"
                                }
                                onClicked: page.actions.dialogs.openRecent(modelData.file)
                                ToolTip.visible: hovered
                                ToolTip.delay: Theme.toolTipDelay
                                ToolTip.text: modelData.path
                                contentItem: RowLayout {
                                    spacing: Theme.spacingS
                                    Text {
                                        text: sessionRow.modelData.name
                                        color: Theme.text
                                        font.pixelSize: Theme.fontSizeBody
                                        elide: Text.ElideRight
                                        Layout.maximumWidth: parent.width * 0.5
                                    }
                                    Secondary {
                                        Layout.fillWidth: true
                                        text: sessionRow.modelData.path
                                        elide: Text.ElideMiddle
                                    }
                                    Secondary {
                                        text: page.shortDate(sessionRow.modelData.modified)
                                        font.features: Theme.tabularFigures
                                    }
                                }
                            }
                        }
                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // --- Instruments -------------------------------------------------------------------
            GridLayout {
                id: grid
                objectName: "overviewTiles"
                readonly property int minimumTileWidth: 260
                readonly property int fitColumns: Math.max(1, Math.floor((width + columnSpacing) / (minimumTileWidth + columnSpacing)))
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The column count that leaves the fewest empty cells in the last row (the
                // larger count wins a tie), so the tiles fill the width without an orphan row.
                columns: {
                    const n = page.tileIds.length
                    let best = 1, bestGap = n
                    for (let c = Math.min(fitColumns, Math.max(1, n)); c >= 1; --c) {
                        const gap = (c - n % c) % c
                        if (gap < bestGap) {
                            best = c
                            bestGap = gap
                        }
                    }
                    return best
                }
                columnSpacing: Theme.spacingM
                rowSpacing: Theme.spacingM
                Repeater {
                    model: page.tileIds
                    delegate: OverviewTileFrame {
                        id: tile
                        required property string modelData
                        readonly property var info: InstrumentRegistry.info(modelData)
                        readonly property InstrumentController controller: InstrumentRegistry.controller(modelData)
                        objectName: "overviewTile-" + modelData
                        paneId: modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: grid.minimumTileWidth
                        Layout.preferredHeight: page.minimumTileHeight
                        Layout.minimumHeight: page.minimumTileHeight
                        title: info.title ?? modelData
                        iconName: info.icon ?? ""
                        keyValue: controller ? controller.keyValue : ""
                        summary: controller ? controller.summary : ""
                        status: !controller ? "" : controller.paused ? "paused"
                              : controller.state === InstrumentController.Starting ? "starting"
                              : controller.running ? "running" : controller.hasError ? "error" : ""
                        running: controller !== null && controller.running
                        canToggle: controller !== null && (controller.running || controller.canRun)
                        idle: controller !== null && !controller.running && !controller.hasData
                        pinned: Launcher.favorites.indexOf(modelData) >= 0
                        preview: (info.tileUrl ?? "").toString().length > 0 ? tilePreview : null
                        menu: tileMenu
                        onClicked: page.workspace.show(modelData)
                        onRunToggled: controller.toggle()

                        Component {
                            id: tilePreview
                            Loader {
                                asynchronous: true
                                Component.onCompleted: setSource(tile.info.tileUrl, { controller: tile.controller })
                            }
                        }
                        Menu {
                            id: tileMenu
                            MenuItem { text: qsTr("Show"); onTriggered: page.workspace.show(tile.modelData) }
                            MenuItem { text: qsTr("Show Beside"); onTriggered: page.workspace.showBeside(tile.modelData) }
                            MenuSeparator {}
                            MenuItem {
                                text: tile.running ? qsTr("Stop") : qsTr("Run")
                                enabled: tile.canToggle
                                onTriggered: tile.controller.toggle()
                            }
                            MenuSeparator {}
                            MenuItem {
                                text: tile.pinned ? qsTr("Unpin") : qsTr("Pin to Top")
                                onTriggered: Launcher.toggleFavorite(tile.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
