pragma ComponentBehavior: Bound
import QtQuick
import MyBench.Framework

// Stack of toasts (the Notifications model), newest at the bottom (global transient events only).
// Anchor it to the bottom-right of the window content; it only takes the space of its toasts.
//     ToastArea { anchors.right: parent.right; anchors.bottom: parent.bottom; anchors.margins: 16 }
ListView {
    id: list

    width: 480
    height: Math.min(contentHeight, 600)
    interactive: false
    spacing: Theme.spacingS
    verticalLayoutDirection: ListView.BottomToTop
    model: Notifications
    z: 1000

    delegate: Toast {
        id: toast
        required toastId
        required level
        required title
        required message
        required actionText
        required repeat
        width: list.width
        onDismissRequested: Notifications.dismiss(toast.toastId)
        onActionRequested: Notifications.trigger(toast.toastId)
    }

    // A message the visible pane already shows (pause, error and input-warning banners, the
    // reconnected banner) is not repeated as a toast.
    function shownInPane(row: int): bool {
        const idx = Notifications.index(row, 0)
        const source = Notifications.data(idx, Notifications.SourceRole) ?? ""
        const message = Notifications.data(idx, Notifications.MessageRole) ?? ""
        const visibleIds = ResourceArbiter.visibleInstruments
        if (source.startsWith("pause:"))
            return visibleIds.indexOf(source.substring(6)) >= 0
        if (source === "device")
            return visibleIds.some(id => InstrumentRegistry.controller(id)?.interruptedByDisconnect === true)
                   && message.length > 0 && Notifications.data(idx, Notifications.LevelRole) === Notifications.Success
        const c = visibleIds.indexOf(source) >= 0 ? InstrumentRegistry.controller(source) : null
        return c !== null && message.length > 0 && (message === c.errorText || message === c.inputWarning)
    }
    Connections {
        target: Notifications
        // Dismissed after the insertion, not inside it: removing the row while the list creates its
        // delegate left a delegate without data on screen (a toast reading "undefined").
        function onRowsInserted(parent, first, last) {
            const ids = []
            for (let row = last; row >= first; --row) {
                if (list.shownInPane(row))
                    ids.push(Notifications.data(Notifications.index(row, 0), Notifications.ToastIdRole))
            }
            if (ids.length > 0)
                Qt.callLater(() => { for (const id of ids) Notifications.dismiss(id) })
        }
    }
    Connections {
        target: ResourceArbiter
        function onVisibleInstrumentsChanged() {
            for (const id of ResourceArbiter.visibleInstruments)
                Notifications.dismissSource("pause:" + id)
        }
    }

    Connections {
        target: Notifications
        function onDetailsRequested() { ShellActions.eventLogRequested() }
    }

    add: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: Theme.durationNormal }
            NumberAnimation { property: "x"; from: 24; to: 0; duration: Theme.durationNormal; easing.type: Theme.easing }
        }
    }
    remove: Transition {
        ParallelAnimation {
            NumberAnimation { property: "opacity"; to: 0; duration: Theme.durationFast }
        }
    }
    displaced: Transition {
        NumberAnimation { properties: "y"; duration: Theme.durationNormal; easing.type: Theme.easing }
    }
}
