import QtQuick
import QtQuick.Shapes
import qs.Commons

// A plain drop-in-a-circle mark — deliberately not Proton's actual logo, just
// a distinct glyph for the bar. Swap for a licensed asset before publishing.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  Shape {
    anchors.fill: parent
    antialiasing: true
    layer.enabled: true
    layer.samples: 4

    ShapePath {
      fillColor: "transparent"
      strokeColor: root.color
      strokeWidth: Math.max(1, root.iconSize * 0.09)
      capStyle: ShapePath.RoundCap
      joinStyle: ShapePath.RoundJoin

      PathAngleArc {
        centerX: root.width / 2
        centerY: root.height / 2
        radiusX: root.width * 0.38
        radiusY: root.height * 0.38
        startAngle: 0
        sweepAngle: 360
      }
    }

    ShapePath {
      fillColor: root.color
      strokeWidth: 0

      startX: root.width * 0.5
      startY: root.height * 0.30
      PathCubic {
        x: root.width * 0.5; y: root.height * 0.68
        control1X: root.width * 0.68; control1Y: root.height * 0.40
        control2X: root.width * 0.68; control2Y: root.height * 0.58
      }
      PathCubic {
        x: root.width * 0.5; y: root.height * 0.30
        control1X: root.width * 0.32; control1Y: root.height * 0.58
        control2X: root.width * 0.32; control2Y: root.height * 0.40
      }
    }
  }
}
