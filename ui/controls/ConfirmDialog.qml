pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import QtQuick.Layouts
import MyBench.Framework

// A confirmation whose accept button carries the verb ("Quit", "Reset Settings"). The platform's
// MessageDialog is used only when `acceptText` is a standard button label, else a styled dialog;
// screenshot and test runs always use the styled one.
//     ConfirmDialog { id: confirm; title: qsTr("Reset device?"); text: ...; acceptText: qsTr("Reset")
//                     destructive: true; onAccepted: DeviceHub.reset() }
//     confirm.open()
Item {
    id: root

    property string title
    property string text
    property string acceptText: qsTr("OK")
    property bool destructive: false
    // The standard button whose label is exactly `acceptText` (native dialog), else -1.
    readonly property int acceptButton: {
        const map = {}
        map[qsTr("Save")] = MessageDialog.Save
        map[qsTr("Discard")] = MessageDialog.Discard
        map[qsTr("Open")] = MessageDialog.Open
        map[qsTr("Close")] = MessageDialog.Close
        map[qsTr("Reset")] = MessageDialog.Reset
        map[qsTr("Apply")] = MessageDialog.Apply
        map[qsTr("Retry")] = MessageDialog.Retry
        map[qsTr("Yes")] = MessageDialog.Yes
        return map[acceptText.trim()] ?? -1
    }
    // In the window (offscreen runs, or a verb no standard button has) or native.
    readonly property bool inWindow: AppInfo.offscreen || acceptButton < 0
    readonly property bool opened: privateState.opened

    signal accepted()
    signal rejected()

    function open() {
        privateState.answered = false
        if (inWindow) {
            styledLoader.active = true
            const styled = styledLoader.item as Dialog
            styled.open()
        } else {
            nativeLoader.active = true
            const box = nativeLoader.item as MessageDialog
            box.open()
        }
        privateState.opened = true
    }
    function close() {
        const styled = styledLoader.item as Dialog
        if (styled)
            styled.close()
        const box = nativeLoader.item as MessageDialog
        if (box)
            box.close()
        privateState.opened = false
    }
    function accept() {
        answer(true)
        close()
    }
    function reject() {
        answer(false)
        close()
    }
    function answer(accept: bool) {
        if (privateState.answered)
            return
        privateState.answered = true
        privateState.opened = false
        if (accept)
            root.accepted()
        else
            root.rejected()
    }

    visible: false

    QtObject {
        id: privateState
        property bool answered: false
        property bool opened: false
    }

    Loader {
        id: nativeLoader
        active: false
        sourceComponent: MessageDialog {
            title: root.title
            text: root.title
            informativeText: root.text
            buttons: Math.max(0, root.acceptButton) | MessageDialog.Cancel
            onButtonClicked: (button, role) => root.answer(button === root.acceptButton)
            onRejected: root.answer(false)
        }
    }

    Loader {
        id: styledLoader
        active: false
        sourceComponent: Dialog {
            id: dialog
            objectName: "confirmDialog"
            title: root.title
            anchors.centerIn: Overlay.overlay
            width: Math.min(420, (Overlay.overlay ? Overlay.overlay.width : 420) - 2 * Theme.spacingXl)
            modal: true
            focus: true
            closePolicy: Popup.CloseOnEscape
            onRejected: root.answer(false)
            onAccepted: root.answer(true)
            onOpened: acceptButton.forceActiveFocus()

            // Our own title row: some platform styles (KDE's) add a red × close button to a Dialog header.
            header: Text {
                objectName: "confirmTitle"
                text: dialog.title
                visible: text.length > 0
                elide: Text.ElideRight
                color: Theme.text
                font.pixelSize: Theme.fontSizeHeading + 1
                font.weight: Font.DemiBold
                leftPadding: dialog.leftPadding
                rightPadding: dialog.rightPadding
                topPadding: Theme.spacingL + 2
                bottomPadding: Theme.spacingXs
            }

            contentItem: Text {
                text: root.text
                color: Theme.textSecondary
                font.pixelSize: Theme.fontSizeBody
                wrapMode: Text.WordWrap
                lineHeight: 1.15
            }
            footer: RowLayout {
                spacing: Theme.spacingS
                Item { Layout.fillWidth: true }
                Button {
                    objectName: "confirmCancelButton"
                    Layout.bottomMargin: Theme.spacingL
                    text: qsTr("Cancel")
                    onClicked: dialog.reject()
                    Keys.onReturnPressed: dialog.accept()
                    Keys.onEnterPressed: dialog.accept()
                }
                Button {
                    id: acceptButton
                    objectName: "confirmAcceptButton"
                    Layout.bottomMargin: Theme.spacingL
                    Layout.rightMargin: Theme.spacingL
                    text: root.acceptText
                    highlighted: !root.destructive
                    onClicked: dialog.accept()
                    Keys.onReturnPressed: dialog.accept()
                    Keys.onEnterPressed: dialog.accept()
                }
            }
        }
    }
}
