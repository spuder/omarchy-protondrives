import QtQuick
import qs.Commons

// A plain uppercase "P" — deliberately not Proton's actual logo, just a
// distinct glyph for the bar. See README/PLAN.md for why: Proton's media
// kit terms cover press coverage, not third-party app icons, and a mark
// that's clearly not their real logo is itself part of not looking official.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Text {
    anchors.centerIn: parent
    text: "P"
    color: root.color
    font.family: Style.font.family
    font.pixelSize: root.iconSize
    font.bold: true
    renderType: Text.NativeRendering
  }
}
