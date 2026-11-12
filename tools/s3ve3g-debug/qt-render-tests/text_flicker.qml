// Render test 3: buttons (radius, border) whose labels change, with ever new glyphs (the glyph
// cache texture grows and is re-uploaded, as when zynthian's values change on touch), plus a
// clipped ListView.
import QtQuick
import QtQuick.Window

Window {
    id: win
    visible: true
    visibility: Window.FullScreen
    color: "#101418"
    property int step: 0
    // characters taken in turn from a large set: new glyphs for a long time
    readonly property string chars: "0123456789.-+dBABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyzÄÖÜäöüßéèêàáâçñøåæœ€$%&/()=?!§*#~<>|^°ΑΒΓΔΕΖΗΘΙΚΛΜΝΞΟΠΡΣΤΥΦΧΨΩαβγδεζηθικλμνξοπρστυφχψωАБВГДЕЖЗИЙКЛМНОПРСТУФХЦЧШЩЭЮЯабвгдежзийклмнопрстуфхцчшщэюя"
    function label(i) { var n = chars.length; var s = ""; for (var k = 0; k < 6; k++) s += chars[(step * 3 + i * 7 + k) % n]; return s }

    Grid {
        x: 20; y: 20; columns: 4; spacing: 16
        Repeater {
            model: 16
            Rectangle {
                objectName: "button" + index
                width: 150; height: 110; radius: 10; border.width: 3; border.color: "#a0a8b0"
                color: "#3050c0"
                Text { anchors.centerIn: parent; color: "white"; font.pixelSize: 22 + (index % 4) * 6
                       text: win.label(index) }
            }
        }
    }
    ListView {
        x: 20; y: 560; width: 640; height: 300; clip: true; spacing: 4
        model: 40
        contentY: (win.step * 13) % 900
        delegate: Rectangle { width: 640; height: 40; radius: 6; color: index % 2 ? "#405060" : "#506070"
            Text { anchors.verticalCenter: parent.verticalCenter; x: 10; color: "white"; font.pixelSize: 20
                   text: index + " " + win.label(index + 20) } }
    }
}
