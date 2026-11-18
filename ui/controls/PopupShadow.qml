import QtQuick
import QtQuick.Effects

// The one shadow of popups, menus, dialogs and the overlay inspector, as a layer effect:
// layer.enabled: true; layer.effect: PopupShadow {}
MultiEffect {
    shadowEnabled: true
    shadowColor: Theme.shadowColor
    shadowBlur: 1.0
    blurMax: Theme.shadowBlur
    shadowVerticalOffset: Theme.shadowOffsetY
    shadowHorizontalOffset: 0
    shadowOpacity: 1
}
