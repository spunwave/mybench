pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import MyBench.Framework

// The Device menu (toolbar device button, menu): the devices (radio), Simulated Device, Rescan,
// Reset Device…, Device Info…, Simulator Settings….
//     MenuBar { DeviceMenu { title: qsTr("&Device"); onSelectRequested: id => button.requestSelect(id) ... } }
//     DeviceMenu { id: menu }  menu.popup(button, 0, button.height)
Menu {
    id: menu

    signal selectRequested(string deviceId)
    signal resetRequested()
    signal deviceInfoRequested()
    signal simulatorSettingsRequested()

    title: qsTr("Device")
    popupType: Theme.inlinePopups ? Popup.Item : Popup.Native

    Instantiator {
        id: devices
        model: DeviceHub.devices
        delegate: MenuItem {
            required property string deviceId
            required property string displayName
            required property string serialNumber
            required property bool simulated
            required property bool connected
            text: displayName
            checkable: true
            checked: deviceId === DeviceHub.currentId
            enabled: connected
            onTriggered: {
                checked = Qt.binding(() => deviceId === DeviceHub.currentId)
                menu.selectRequested(deviceId)
            }
        }
        onObjectAdded: (index, object) => menu.insertItem(index, object as Item)
        onObjectRemoved: (index, object) => menu.removeItem(object as Item)
    }
    Instantiator {
        model: DeviceHub.devices.count === 0 && DeviceHub.unavailableCount === 0 ? 1 : 0
        delegate: MenuItem {
            text: qsTr("No Device Found")
            enabled: false
        }
        onObjectAdded: (index, object) => menu.insertItem(0, object as Item)
        onObjectRemoved: (index, object) => menu.removeItem(object as Item)
    }
    Instantiator {
        model: DeviceHub.unavailable
        delegate: MenuItem {
            required property var modelData
            text: qsTr("myDAQ · Not available")
            enabled: false
            ToolTip.visible: hovered
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: modelData.hint
        }
        onObjectAdded: (index, object) => menu.insertItem(menu.indexOfItem(listEnd), object as Item)
        onObjectRemoved: (index, object) => menu.removeItem(object as Item)
    }
    Instantiator {
        model: DeviceHub.unavailable
        delegate: MenuItem {
            required property var modelData
            text: qsTr("How to Fix: %1").arg(modelData.label)
            ToolTip.visible: hovered
            ToolTip.delay: Theme.toolTipDelay
            ToolTip.text: modelData.hint
            onTriggered: Help.show(modelData.helpTopic)
        }
        onObjectAdded: (index, object) => menu.insertItem(menu.indexOfItem(listEnd), object as Item)
        onObjectRemoved: (index, object) => menu.removeItem(object as Item)
    }
    MenuSeparator { id: listEnd }
    Instantiator {
        model: DeviceHub.simulatorAvailable ? 1 : 0
        delegate: MenuItem {
            text: qsTr("Simulated Device")
            checkable: true
            checked: DeviceHub.simulatorPlugged
            onTriggered: DeviceHub.simulatorPlugged = !DeviceHub.simulatorPlugged
        }
        onObjectAdded: (index, object) => menu.insertItem(menu.indexOfItem(rescanItem), object as Item)
        onObjectRemoved: (index, object) => menu.removeItem(object as Item)
    }
    MenuItem {
        id: rescanItem
        text: qsTr("Rescan")
        onTriggered: DeviceHub.rescan()
    }
    MenuSeparator {}
    MenuItem {
        text: qsTr("Reset Device…")
        enabled: DeviceHub.connected && !DeviceHub.resetting && !InstrumentRegistry.anyRunning
        onTriggered: menu.resetRequested()
    }
    MenuItem {
        text: qsTr("Device Info…")
        enabled: DeviceHub.currentId.length > 0
        onTriggered: menu.deviceInfoRequested()
    }
    Instantiator {
        model: DeviceHub.simulatorAvailable ? 1 : 0
        delegate: MenuItem {
            text: qsTr("Simulator Settings…")
            onTriggered: menu.simulatorSettingsRequested()
        }
        onObjectAdded: (index, object) => menu.addItem(object as Item)
        onObjectRemoved: (index, object) => menu.removeItem(object as Item)
    }

    function indexOfItem(item: Item): int {
        for (let i = 0; i < count; ++i) {
            if (itemAt(i) === item)
                return i
        }
        return count
    }
}
