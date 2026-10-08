import QtQuick
import qs.Commons

// Little "now playing" equalizer bars (pure animation): shown on the current
// track row so you can see what's on air while scrolling the queue.
Item {
  id: wb
  property color barColor: Color.accent
  property int bars: 4
  property bool active: true

  implicitWidth: bars * 5
  implicitHeight: 14

  Row {
    anchors.centerIn: parent
    spacing: 2
    Repeater {
      model: Math.max(0, Math.min(12, wb.bars))
      Rectangle {
        width: 3
        height: 12
        radius: 1.5
        color: wb.barColor
        anchors.verticalCenter: parent.verticalCenter
        SequentialAnimation on height {
          running: wb.active && wb.visible
          loops: Animation.Infinite
          NumberAnimation { to: 4; duration: 360 + index * 110; easing.type: Easing.InOutSine }
          NumberAnimation { to: 12; duration: 360 + index * 110; easing.type: Easing.InOutSine }
        }
      }
    }
  }
}
