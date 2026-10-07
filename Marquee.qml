import QtQuick

// Scrolling title: pauses at the start, glides to reveal the tail, pauses,
// glides back. Static text stays put. Used for long track names.
Item {
  id: mq
  property string text: ""
  property color textColor: "#f7f7f7"
  property string textFont: "monospace"
  property int pixelSize: 11
  property bool bold: false
  clip: true

  readonly property bool overflowing: mqText.implicitWidth > width

  Text {
    id: mqText
    text: mq.text
    color: mq.textColor
    font.family: mq.textFont
    font.pixelSize: mq.pixelSize
    font.bold: mq.bold
    elide: Text.ElideRight
    width: Math.max(mq.width, implicitWidth)

    SequentialAnimation on x {
      running: mq.overflowing && mq.visible
      loops: Animation.Infinite
      PauseAnimation { duration: 1600 }
      NumberAnimation {
        to: mq.width - mqText.width
        duration: Math.max(1400, (mqText.width - mq.width) * 30)
        easing.type: Easing.InOutSine
      }
      PauseAnimation { duration: 1600 }
      NumberAnimation {
        to: 0
        duration: Math.max(1400, (mqText.width - mq.width) * 30)
        easing.type: Easing.InOutSine
      }
    }
  }
}
