import QtQuick

// Overview tile of the fake instruments (module Test.Fake), so the Overview tests load a real
// tile like the shipped instruments do instead of a missing file (Qt 6.9 crashed on the failed
// asynchronous load during teardown).
Item {
    required property var controller
}
