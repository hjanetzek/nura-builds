// Render test for the black-button flicker: rectangles like zynthian's buttons in a grid
// (rows: plain, radius, border, radius + border), colors and a slider changed by a timer like touch events; the Python side reads every
// frame back and checks the panel centers.
import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#101418"
    property int step: 0
    readonly property var palette: ["#c03030", "#30a040", "#3050c0", "#c0a030"]
    function panelColor(i) { return palette[(i + step) % palette.length] }

    Grid {
        id: grid
        objectName: "grid"
        x: 20; y: 20
        columns: 4; spacing: 16
        Repeater {
            id: rep
            model: 16
            Rectangle {
                objectName: "panel" + index
                width: 150; height: 110
                // rows: plain, radius, border, radius + border (as zynthian's buttons)
                radius: (index >= 4 && index < 8) || index >= 12 ? 10 : 0
                border.width: index >= 8 ? 3 : 0
                border.color: "#a0a8b0"
                color: win.panelColor(index)
            }
        }
    }
    // A slider: a bar whose width follows the step, as when dragging
    Rectangle {
        x: 20; y: grid.y + grid.height + 30; width: 640; height: 40; color: "#303840"
        Rectangle { width: 40 + (win.step * 37) % 600; height: parent.height; color: "#e0e0e0" }
    }
}
