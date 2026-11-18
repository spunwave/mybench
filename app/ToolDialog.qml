pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework
import MyBench.Controls

// Add or edit a user tool (the Tools menu, edited in Preferences ▸ Tools): a name and a program,
// document, folder or web address, plus optional arguments for programs.
//     ToolDialog { id: toolDialog }   toolDialog.add()   toolDialog.edit(index)
Dialog {
    id: dialog

    property int index: -1               // -1: new tool
    readonly property string kind: Launcher.targetKind(targetField.text)

    function add() {
        index = -1
        nameField.text = ""
        targetField.text = ""
        argsField.text = ""
        open()
        targetField.forceActiveFocus()
    }
    function edit(toolIndex: int) {
        const tool = Launcher.tools[toolIndex]
        if (!tool)
            return
        index = toolIndex
        nameField.text = tool.name
        targetField.text = tool.target
        argsField.text = tool.arguments
        open()
        nameField.forceActiveFocus()
    }

    anchors.centerIn: Overlay.overlay
    width: 480
    modal: true
    title: index < 0 ? qsTr("Add Tool") : qsTr("Edit Tool")
    standardButtons: Dialog.Ok | Dialog.Cancel

    Component.onCompleted: standardButton(Dialog.Ok).text = Qt.binding(() => dialog.index < 0 ? qsTr("Add") : qsTr("Save"))
    onOpened: standardButton(Dialog.Ok).enabled = Qt.binding(() => targetField.text.trim().length > 0)

    onAccepted: {
        if (index < 0)
            Launcher.addTool(nameField.text, targetField.text, argsField.text)
        else
            Launcher.updateTool(index, nameField.text, targetField.text, argsField.text)
    }

    FileDialog {
        id: browse
        title: qsTr("Choose File")
        fileMode: FileDialog.OpenFile
        onAccepted: {
            targetField.text = Launcher.normalizedTarget(selectedFile.toString())
            if (nameField.text.trim().length === 0)
                nameField.placeholderText = qsTr("File name")
        }
    }

    contentItem: ColumnLayout {
        spacing: Theme.spacingL

        Field {
            label: qsTr("Program, file or URL")
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS
                TextField {
                    id: targetField
                    Layout.fillWidth: true
                    placeholderText: qsTr("Path or URL")
                    selectByMouse: true
                    onAccepted: dialog.accept()
                }
                Button {
                    text: qsTr("Browse…")
                    onClicked: browse.open()
                }
            }
            Text {
                Layout.fillWidth: true
                visible: targetField.text.trim().length > 0
                text: dialog.kind === "url" ? qsTr("Web page")
                    : dialog.kind === "program" ? qsTr("Program")
                    : dialog.kind === "folder" ? qsTr("Folder")
                    : dialog.kind === "file" ? qsTr("Document")
                    : qsTr("Not found")
                color: dialog.kind === "missing" ? Theme.caution : Theme.textTertiary
                font.pixelSize: Theme.fontSizeSmall
            }
        }
        Field {
            label: qsTr("Name")
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: qsTr("File or site name")
                selectByMouse: true
                onAccepted: dialog.accept()
            }
        }
        Field {
            visible: dialog.kind === "program"
            label: qsTr("Arguments")
            trailing: qsTr("optional")
            TextField {
                id: argsField
                Layout.fillWidth: true
                placeholderText: qsTr("--verbose \"my file.txt\"")
                selectByMouse: true
                onAccepted: dialog.accept()
            }
        }
    }
}
