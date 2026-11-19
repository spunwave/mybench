pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls
import MyBench.Plot

// Import wizards of the Waveform Editor: delimiters, column, start line and sample count for text;
// channel for multi-channel WAV and .wdt; the assumptions for raw binary; a live preview; Insert or Replace.
Dialog {
    id: root

    required property WaveformEditor editor
    property url file
    property int mode: 0           // 0: insert a new segment, 1: replace the selected sketch's values
    property var info: ({})
    readonly property bool text: (info.kind ?? "") === "text"
    // Manual options (Automatic off); with Automatic on the fields show what was detected.
    property int manualStartLine: 0
    property int manualCount: 0

    function openFor(url: url) {
        file = url
        automatic.checked = true
        column.value = 1
        manualStartLine = 0
        manualCount = 0
        channel.currentIndex = 0
        refresh()
        open()
    }
    function options(): var {
        let delimiters = ""
        if (tab.checked) delimiters += "\t"
        if (semicolon.checked) delimiters += ";"
        if (comma.checked) delimiters += ","
        if (space.checked) delimiters += " "
        if (other.checked && otherChar.text.length > 0) delimiters += otherChar.text[0]
        return { automatic: automatic.checked, delimiters: delimiters, column: column.value,
                 startLine: manualStartLine, count: manualCount, channel: Math.max(0, channel.currentIndex) }
    }
    function refresh() {
        info = editor.inspectImport(file, options())
    }

    title: text ? qsTr("Text File Wizard") : (info.kind ?? "") === "bin" ? qsTr("Binary File Import") : qsTr("Waveform File Wizard")
    anchors.centerIn: Overlay.overlay
    modal: true
    width: Math.min(680, Overlay.overlay ? Overlay.overlay.width - 40 : 680)
    standardButtons: Dialog.Cancel
    onAccepted: editor.acceptImport(file, options(), mode)

    ColumnLayout {
        anchors.fill: parent
        spacing: Theme.spacingS

        Text {
            Layout.fillWidth: true
            text: decodeURIComponent(String(root.file).split("/").pop())
            color: Theme.text
            font.pixelSize: Theme.fontSizeBody
            font.weight: Font.DemiBold
            elide: Text.ElideMiddle
        }

        // Text options
        CheckBox {
            id: automatic
            visible: root.text
            text: qsTr("Automatic")
            ToolTip.visible: hovered
            ToolTip.text: qsTr("Detect header, time and rate")
            checked: true
            onToggled: {
                if (!checked) {
                    // Start from what was detected.
                    root.manualStartLine = root.info.firstNumericLine ?? 0
                    root.manualCount = 0
                }
                root.refresh()
            }
        }
        // Always shown (grayed while Automatic) so the detected layout is visible.
        ColumnLayout {
            visible: root.text
            enabled: !automatic.checked
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            FormRow {
                label: qsTr("Delimiter")
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingS
                    CheckBox { id: tab; text: qsTr("Tab"); checked: true; onToggled: root.refresh() }
                    CheckBox { id: semicolon; text: qsTr("Semicolon"); onToggled: root.refresh() }
                    CheckBox { id: comma; text: qsTr("Comma"); onToggled: root.refresh() }
                    CheckBox { id: space; text: qsTr("Space"); onToggled: root.refresh() }
                    CheckBox { id: other; text: qsTr("Other"); onToggled: root.refresh() }
                    TextField { id: otherChar; Layout.preferredWidth: 32; maximumLength: 1; enabled: other.checked; onTextEdited: root.refresh() }
                    Item { Layout.fillWidth: true }
                }
            }
            FormRow {
                label: qsTr("Column")
                SiField { id: column; Layout.fillWidth: true; engineering: false; decimals: 0; stepSize: 1; from: 1; to: 1000; value: 1
                          onValueModified: v => { value = v; root.refresh() } }
            }
            FormRow {
                label: qsTr("Start line")
                SiField { id: startLine; Layout.fillWidth: true; engineering: false; decimals: 0; stepSize: 1; from: 0; to: 1e9
                          value: automatic.checked ? (root.info.firstNumericLine ?? 0) : root.manualStartLine
                          toolTip: qsTr("First line (0: first numeric)")
                          onValueModified: v => { root.manualStartLine = v; root.refresh() } }
            }
            FormRow {
                label: qsTr("Samples")
                SiField { id: count; Layout.fillWidth: true; engineering: false; decimals: 0; stepSize: 1; from: 0; to: 1e7
                          value: automatic.checked ? (root.info.count ?? 0) : root.manualCount
                          toolTip: qsTr("Count (0: all)")
                          onValueModified: v => { root.manualCount = v; root.refresh() } }
            }
        }
        Rectangle {
            visible: root.text
            Layout.fillWidth: true
            Layout.preferredHeight: 90
            radius: Theme.radiusControl
            color: Theme.display
            border.width: 1
            border.color: Theme.separator
            ScrollView {
                anchors.fill: parent
                anchors.margins: 4
                clip: true
                Text {
                    text: (root.info.lines ?? []).map((l, i) => String(i + 1).padStart(4, " ") + "  " + l).join("\n")
                    color: Theme.textSecondary
                    font.family: Theme.monoFamily
                    font.pixelSize: Theme.fontSizeS
                }
            }
        }

        // Waveform files: channel choice
        FormRow {
            visible: !root.text && (root.info.channels ?? 1) > 1
            label: qsTr("Channel")
            ComboBox {
                id: channel
                Layout.fillWidth: true
                model: Array.from({ length: root.info.channels ?? 1 }, (_, i) => qsTr("Channel %1").arg(i + 1))
                onActivated: root.refresh()
            }
        }
        BenchPlot {
            Layout.fillWidth: true
            Layout.preferredHeight: 170
            placeholderText: root.info.ok ? "" : (root.info.error ?? "")
            xAxis { min: 0; max: Math.max(1, (root.info.count ?? 1) - 1); title: qsTr("Sample") }
            yAxis { autoScale: true; minimumSpan: 0.1; unit: "V" }
            PlotTrace { buffer: root.editor.importPreview; color: Theme.accent; width: 1.2 }
        }
        Text {
            Layout.fillWidth: true
            text: root.info.ok ? qsTr("%1 samples · %2").arg(root.info.count)
                                   .arg(root.info.sampleRate > 0 ? Units.format(root.info.sampleRate, "S/s") : qsTr("Document rate"))
                               : qsTr("%1").arg(root.info.error ?? "")
            color: root.info.ok ? Theme.textSecondary : Theme.negative
            ToolTip.visible: statusHover.hovered && tipText.length > 0
            ToolTip.text: tipText
            readonly property string tipText: (root.info.kind ?? "") === "bin" ? qsTr("Raw 16-bit, ±5 V")
                                            : (root.info.kind ?? "") === "wdt" ? qsTr("LabVIEW file · check the preview")
                                            : root.info.sampleRate > 0 ? "" : qsTr("No rate in file · document rate used")
            HoverHandler { id: statusHover }
            font.pixelSize: Theme.fontSizeS
            wrapMode: Text.WordWrap
        }
    }

    footer: RowLayout {
        spacing: Theme.spacingS
        Item { Layout.fillWidth: true }
        SegmentedControl {
            Layout.bottomMargin: Theme.spacingL
            compact: true
            model: [ { text: qsTr("Insert"), toolTip: qsTr("Insert after current") },
                     { text: qsTr("Replace"), toolTip: qsTr("Replace Sketch values") } ]
            currentIndex: root.mode
            onActivated: index => root.mode = index
        }
        ActionButton {
            Layout.bottomMargin: Theme.spacingL
            text: qsTr("Cancel")
            onClicked: root.reject()
        }
        ActionButton {
            Layout.bottomMargin: Theme.spacingL
            Layout.rightMargin: Theme.spacingL
            text: qsTr("OK")
            tone: "accent"
            enabled: root.info.ok ?? false
            onClicked: root.accept()
        }
    }
}
