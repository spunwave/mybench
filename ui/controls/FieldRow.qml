import QtQuick
import QtQuick.Layouts

// Deprecated container of side-by-side Fields: it now stacks its Fields vertically like the other
// rows of the form.
//     FieldRow { Field { label: "Probe" ... } Field { label: "Coupling" ... } }
ColumnLayout {
    Layout.fillWidth: true
    spacing: Theme.formRowSpacing
}
