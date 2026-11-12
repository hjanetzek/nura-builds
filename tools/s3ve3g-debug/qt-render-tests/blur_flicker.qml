// Render test 2: zynthian's KeypadBlur structure (a live ShaderEffectSource of the screen under
// the keys, blurred by MultiEffect, translucent keys on top) over a screen that changes like on touch.
import QtQuick
import QtQuick.Window
import QtQuick.Effects

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#101418"
    property int step: 0
    readonly property var palette: ["#c03030", "#30a040", "#3050c0", "#c0a030"]

    Item {
        id: screens
        anchors.fill: parent
        Grid {
            x: 20; y: 20; columns: 4; spacing: 16
            Repeater {
                model: 16
                Rectangle { width: 150; height: 110; radius: 10; border.width: 3; border.color: "#a0a8b0"
                            color: win.palette[(index + win.step) % 4] }
            }
        }
        Rectangle { x: 20; y: 560; width: 640; height: 40; color: "#303840"
            Rectangle { width: 40 + (win.step * 37) % 600; height: parent.height; color: "#e0e0e0" } }
    }

    // As KeypadBlur.qml's BlurArea: the bottom area of the screen, blurred
    Item {
        id: area
        objectName: "blurArea"
        x: 0; y: 700; width: parent.width; height: parent.height - 700
        ShaderEffectSource { id: snap; anchors.fill: parent; sourceItem: screens
            sourceRect: Qt.rect(area.x, area.y - 400, area.width, area.height); live: true; visible: false }
        MultiEffect { anchors.fill: parent; source: snap; blurEnabled: true; blur: 1.0; blurMax: 64
            blurMultiplier: 1.0; autoPaddingEnabled: false; brightness: -0.2 }
        // translucent keys
        Grid { x: 20; y: 20; columns: 4; spacing: 16
            Repeater { model: 8
                Rectangle { width: 150; height: 110; radius: 10; color: "#40ffffff"; border.width: 2; border.color: "#80ffffff" } } }
    }
}
