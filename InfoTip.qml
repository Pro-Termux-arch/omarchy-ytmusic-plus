import QtQuick
import qs.Commons

// Hover tooltip with a long dwell (5s): place inside any icon button, point
// `watched` at its MouseArea. Shows what the button does without clicking.
Rectangle {
  id: tip
  property var watched
  property string tipText: ""
  property int delayMs: 5000

  width: tipLabel.width + Style.space(14)
  height: Style.space(22)
  radius: Style.space(6)
  color: Color.tooltip.background
  border.width: 1
  border.color: Color.tooltip.border
  visible: false
  z: 100

  anchors.bottom: parent.top
  anchors.bottomMargin: Style.space(6)
  anchors.horizontalCenter: parent.horizontalCenter

  Text {
    id: tipLabel
    anchors.centerIn: parent
    text: tip.tipText
    color: Color.tooltip.text
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }

  Timer {
    interval: tip.delayMs
    running: tip.tipText !== "" && tip.watched && tip.watched.containsMouse
    repeat: false
    onTriggered: tip.visible = true
  }

  Connections {
    target: tip.watched
    function onContainsMouseChanged() {
      if (tip.watched && !tip.watched.containsMouse) tip.visible = false
    }
  }
}
