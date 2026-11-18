pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Dialogs
import MyBench.Framework
import MyBench.Controls

// The shell's dialogs and small windows: native file dialogs, confirmations whose
// accept button carries the verb (ConfirmDialog: native only for a standard label such as Save),
// and the Preferences, About, Device Info and Simulator Settings windows (shown inside the main
// window offscreen). Every entry point is a function:
//     dialogs.openSession()   dialogs.resetSettings("scope")   dialogs.showPreferences("tools")
Item {
    id: dialogs

    required property AppPreferences preferences
    required property WorkspaceState workspace
    // Set once the user confirmed quitting (the window then closes without asking again).
    property bool quitConfirmed: false
    readonly property alias sessionGuard: guard
    readonly property string windowTitle: guard.windowTitle

    signal quitAccepted()

    // --- Sessions ------------------------------------------------------------------------------------
    SessionGuard {
        id: guard
        onSaveFirstRequested: saveFirst.open()
    }
    function newSession() {
        if (SessionManager.modified)
            newSessionConfirm.open()
        else
            SessionManager.newSession()
    }
    function openSession() {
        guard.run(() => openDialog.open())
    }
    function openRecent(file: url) {
        guard.run(() => SessionManager.load(file))
    }
    function saveSession() {
        if (!SessionManager.saveCurrent())
            saveSessionAs()
    }
    function saveSessionAs() {
        saveDialog.selectedFile = SessionManager.suggestedFileUrl()
        saveDialog.open()
    }
    function revertToSaved() {
        if (guard.named)
            revertConfirm.open()
    }
    function resetAllInstruments() {
        resetAllConfirm.open()
    }

    FileDialog {
        id: openDialog
        title: qsTr("Open Session")
        fileMode: FileDialog.OpenFile
        nameFilters: SessionManager.nameFilters
        onAccepted: SessionManager.load(selectedFile)
    }
    FileDialog {
        id: saveDialog
        title: qsTr("Save Session")
        fileMode: FileDialog.SaveFile
        defaultSuffix: SessionManager.fileExtension
        nameFilters: SessionManager.nameFilters
        onAccepted: SessionManager.save(selectedFile)
    }
    MessageDialog {
        id: saveFirst
        text: qsTr("Save “%1”?").arg(SessionManager.currentName)
        informativeText: qsTr("Unsaved changes")
        buttons: MessageDialog.Save | MessageDialog.Discard | MessageDialog.Cancel
        onButtonClicked: (button, role) => {
            if (button === MessageDialog.Save)
                guard.save()
            else if (button === MessageDialog.Discard)
                guard.discard()
            else
                guard.cancel()
        }
    }
    ConfirmDialog {
        id: newSessionConfirm
        title: qsTr("New session?")
        text: qsTr("Unsaved changes of “%1”").arg(SessionManager.currentName)
        acceptText: qsTr("New Session")
        destructive: true
        onAccepted: SessionManager.newSession()
    }
    ConfirmDialog {
        id: revertConfirm
        title: qsTr("Revert “%1”?").arg(SessionManager.currentName)
        text: qsTr("Unsaved changes")
        acceptText: qsTr("Revert")
        destructive: true
        onAccepted: SessionManager.load(SessionManager.currentFile)
    }
    ConfirmDialog {
        id: resetAllConfirm
        objectName: "resetAllConfirm"
        title: qsTr("Reset all instruments?")
        text: qsTr("Running instruments stop")
        acceptText: qsTr("Reset All")
        destructive: true
        onAccepted: SessionManager.revertAllToDefaults()
    }

    // --- Instruments ----------------------------------------------------------------------------------
    function resetSettings(paneId: string) {
        const controller = InstrumentRegistry.controller(paneId.split("/")[0])
        if (!controller)
            return
        resetSettingsConfirm.controller = controller
        resetSettingsConfirm.open()
    }
    ConfirmDialog {
        id: resetSettingsConfirm
        property InstrumentController controller: null
        title: qsTr("Reset %1?").arg(controller ? controller.title : "")
        text: qsTr("All settings to default")
        acceptText: qsTr("Reset Settings")
        destructive: true
        onAccepted: {
            if (controller)
                controller.resetSettings()
        }
    }

    // --- Quit ----------------------------------------------------------------------------------------
    // Called from the window's onClosing: true when the window may close now. Otherwise the
    // needed questions are asked (unsaved documents, save the session, instruments running), and
    // quitAccepted() is emitted once everything is answered.
    function mayClose(): bool {
        if (quitConfirmed || AppInfo.screenshot)
            return true
        const mustConfirm = preferences.behaviour.confirmQuit && InstrumentRegistry.anyRunning
        const documents = InstrumentRegistry.unsavedDocuments()
        if (!guard.needsPrompt && !mustConfirm && documents.length === 0)
            return true
        if (documents.length > 0 && !unsavedDocumentsConfirm.answered) {
            unsavedDocumentsConfirm.documents = documents
            unsavedDocumentsConfirm.open()
            return false
        }
        guard.run(() => {
            if (preferences.behaviour.confirmQuit && InstrumentRegistry.anyRunning)
                quitConfirm.open()
            else
                dialogs.acceptQuit()
        })
        return false
    }
    function showQuit() {          // --quit-dialog: the Quit confirmation, for screenshots
        quitConfirm.open()
    }
    function acceptQuit() {
        quitConfirmed = true
        quitAccepted()
    }
    ConfirmDialog {
        id: quitConfirm
        title: qsTr("Quit %1?").arg(AppInfo.name)
        // Spelled out per count: without a loaded translation %n leaves the "(s)" in the text.
        text: InstrumentRegistry.runningCount === 1
              ? qsTr("1 instrument running")
              : qsTr("%1 instruments running").arg(InstrumentRegistry.runningCount)
        acceptText: qsTr("Quit")
        destructive: true
        onAccepted: dialogs.acceptQuit()
    }
    ConfirmDialog {
        id: unsavedDocumentsConfirm
        property var documents: []
        property bool answered: false
        title: qsTr("Discard changes?")
        text: documents.join("\n")
        acceptText: qsTr("Quit")
        destructive: true
        onAccepted: {
            answered = true
            Qt.callLater(() => {
                if (dialogs.mayClose())
                    dialogs.acceptQuit()
            })
        }
    }

    // --- Windows ------------------------------------------------------------------------------------
    function showPreferences(page: string) {
        preferencesWindow.page = page ?? ""
        preferencesWindow.show()
    }
    function showAbout() {
        aboutWindow.show()
    }
    function showDeviceInfo() {
        deviceInfoWindow.show()
    }
    function showSimulatorSettings() {
        simulatorWindow.show()
    }

    PaneWindow {
        id: preferencesWindow
        property string page: ""
        objectName: "preferencesWindow"
        title: qsTr("Preferences")
        pane: Component {
            PreferencesPane {
                preferences: dialogs.preferences
                page: preferencesWindow.page
                onSimulatorSettingsRequested: dialogs.showSimulatorSettings()
            }
        }
    }
    PaneWindow {
        id: aboutWindow
        objectName: "aboutWindow"
        title: qsTr("About %1").arg(AppInfo.name)
        pane: Component { AboutPane {} }
    }
    PaneWindow {
        id: deviceInfoWindow
        objectName: "deviceInfoWindow"
        title: qsTr("Device Info")
        pane: Component { DeviceInfoPane {} }
    }
    PaneWindow {
        id: simulatorWindow
        objectName: "simulatorWindow"
        title: qsTr("Simulator Settings")
        pane: Component { SimulatorPane {} }
    }
}
