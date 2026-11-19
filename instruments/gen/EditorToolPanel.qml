pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// The Waveform Editor's tools (Functions, Scale Selection, Display, Export, Information) as the
// floating panel of the shared layout. The tool in use is the view's `tool`.
ToolPanel {
    id: root

    required property EditorView view
    readonly property WaveformEditor editor: view.editor

    objectName: "editorToolPanel"
    visible: view.tool.length > 0
    title: view.tool === "functions" ? qsTr("Functions")
           : view.tool === "import" ? qsTr("Import")
           : view.tool === "export" ? qsTr("Export")
           : view.tool === "display" ? qsTr("Display")
           : view.tool === "scale" ? qsTr("Scale Selection")
           : view.tool === "info" ? qsTr("Information") : ""
    onCloseRequested: view.tool = ""

        // Functions: the 21 library functions, a formula or a sketch for the selected component.
        GridLayout {
            objectName: "editorFunctionsTool"
            visible: root.view.tool === "functions"
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Theme.spacingXs
            rowSpacing: Theme.spacingXs
            Repeater {
                model: root.editor.functionNames
                delegate: Button {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    text: modelData
                    checkable: false
                    highlighted: root.editor.selectionKind === 2 && root.editor.componentType === 0 && root.editor.libraryFunction === index
                    onClicked: root.view.applyFunction(0, index)
                }
            }
            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: qsTr("Formula f(x)")
                highlighted: root.editor.selectionKind === 2 && root.editor.componentType === 1
                onClicked: root.view.applyFunction(1, -1)
            }
            Button {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                text: qsTr("Sketch")
                highlighted: root.editor.selectionKind === 2 && root.editor.componentType === 2
                onClicked: root.view.applyFunction(2, -1)
            }
        }
        // Import: a file as new segments (with its column / format options), or into the sketch.
        ColumnLayout {
            visible: root.view.tool === "import"
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            Button {
                objectName: "editorImportFile"
                Layout.fillWidth: true
                text: qsTr("Import from File…")
                icon.source: Theme.icon("upload")
                onClicked: root.view.openImport()
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Into Sketch…")
                enabled: root.editor.selectionKind === 2 && root.editor.componentType === 2 && !root.editor.drawMode
                onClicked: root.view.sketchImport.open()
            }
        }
        // Export: the rendered waveform as a file, or its data to the clipboard.
        ColumnLayout {
            visible: root.view.tool === "export"
            Layout.fillWidth: true
            spacing: Theme.spacingXs
            Button {
                objectName: "editorExportFile"
                Layout.fillWidth: true
                text: qsTr("Export Waveform…")
                icon.source: Theme.icon("export")
                onClicked: root.view.exportDialog.open()
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Save As…")
                icon.source: Theme.icon("save")
                onClicked: root.view.saveDialog.open()
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Copy Data")
                icon.source: Theme.icon("copy")
                onClicked: root.editor.copyData()
            }
        }
        ColumnLayout {
            visible: root.view.tool === "display"
            Layout.fillWidth: true
            spacing: Theme.spacingS
            EditorDisplayTool {
                Layout.fillWidth: true
                editor: root.editor
                onTraceStyleRequested: root.view.openTraceStyle()
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Settings…")
                icon.source: Theme.icon("settings")
                onClicked: root.view.settingsDialog.open()
            }
        }
        EditorScaleTool {
            visible: root.view.tool === "scale"
            Layout.fillWidth: true
            editor: root.editor
        }
        // Information: the file and the description stored with the document.
        ColumnLayout {
            visible: root.view.tool === "info"
            Layout.fillWidth: true
            spacing: Theme.spacingS
            onVisibleChanged: if (visible) infoText.text = root.editor.info
            TextField {
                Layout.fillWidth: true
                readOnly: true
                text: root.editor.filePath
                placeholderText: qsTr("Untitled")
                selectByMouse: true
            }
            TextArea {
                id: infoText
                objectName: "editorInfoText"
                Layout.fillWidth: true
                implicitHeight: 120
                placeholderText: qsTr("Description")
                wrapMode: TextEdit.Wrap
            }
            Button {
                Layout.fillWidth: true
                text: qsTr("Apply")
                highlighted: true
                enabled: infoText.text !== root.editor.info
                onClicked: root.editor.info = infoText.text
            }
        }
}
