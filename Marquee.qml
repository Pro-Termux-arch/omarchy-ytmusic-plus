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
  property bool hovered: false
  clip: true
  implicitHeight: mqText.implicitHeight

  readonly property bool overflowing: mqText.implicitWidth > width
  readonly property real contentWidth: mqText.implicitWidth
  onOverflowingChanged: if (!mq.overflowing) mqText.x = 0

  Text {
    id: mqText
    text: mq.text
    textFormat: Text.PlainText
    maximumLineCount: 1
    color: mq.textColor
    font.family: mq.textFont
    font.pixelSize: mq.pixelSize
    font.bold: mq.bold
    elide: Text.ElideRight
    width: Math.min(Math.max(mq.width, implicitWidth), mq.width + 6000)
    opacity: 1.0
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    onTextChanged: {
      mqText.x = 0
      mqText.opacity = 0.3
      Qt.callLater(function() { mqText.opacity = 1.0 })
    }

    SequentialAnimation on x {
      running: mq.overflowing && mq.visible
      paused: mq.overflowing && mq.hovered
      loops: Animation.Infinite
      PauseAnimation { duration: 1600 }
      NumberAnimation {
        to: mq.width - mqText.width
        duration: Math.min(12000, Math.max(1400, (mqText.width - mq.width) * 30))
        easing.type: Easing.InOutSine
      }
      PauseAnimation { duration: 1600 }
      NumberAnimation {
        to: 0
        duration: Math.min(12000, Math.max(1400, (mqText.width - mq.width) * 30))
        easing.type: Easing.InOutSine
      }
    }
  }

  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.NoButton
    hoverEnabled: true
    onContainsMouseChanged: mq.hovered = containsMouse
  }
}
