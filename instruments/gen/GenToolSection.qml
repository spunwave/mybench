import QtQuick
import QtQuick.Layouts
import MyBench.Controls

// A flat section of a tool panel (title, optional switch, form rows), spanning the panel edge to
// edge. Declared inside a ToolPanel.
//     GenToolSection { title: qsTr("Time Cursors"); checkable: true; checked: ctl.on
//                        onToggled: on => ctl.on = on
//                        FormRow { label: qsTr("Style"); ComboBox { Layout.fillWidth: true } } }
ChannelCard {
    Layout.fillWidth: true
    Layout.leftMargin: -Theme.spacingM
    Layout.rightMargin: -Theme.spacingM
    Layout.topMargin: -Theme.spacingM / 2
    Layout.bottomMargin: -Theme.spacingM / 2
    color: "transparent"
    checkable: false
    collapseWhenOff: true
}
