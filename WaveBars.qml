import QtQuick
import qs.Commons

// Little "now playing" equalizer bars (pure animation): shown on the current
// track row so you can see what's on air while scrolling the queue.
Item {
  id: wb
  property var theme: null
  function tc(name, fallback) { return (theme && theme[name] !== undefined) ? theme[name] : fallback; }
  function tc2(obj, key, fallback) { var o = tc(obj, null); return (o && o[key] !== undefined) ? o[key] : fallback; }
  property color themeAccent: tc("accent", "#cacccc")
  property color barColor: themeAccent
  Component.onCompleted: {
    try { theme = ShellColor; } catch (e1) { theme = null; }
    if (!theme) { try { theme = Color; } catch (e2) { theme = null; } }
  }
  property int bars: 4
  property bool active: true
  opacity: wb.active ? 1 : 0.35

  implicitWidth: Math.max(0, Math.min(12, bars)) * 5
  implicitHeight: 14
  Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

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
        opacity: 0.85
        anchors.verticalCenter: parent.verticalCenter
        SequentialAnimation on height {
          running: wb.active && wb.visible
          loops: Animation.Infinite
          NumberAnimation { to: 4; duration: [379, 431, 479, 523, 577, 631, 683, 733, 787, 839, 881, 937][index]; easing.type: Easing.InOutSine }
          NumberAnimation { to: 12; duration: [379, 431, 479, 523, 577, 631, 683, 733, 787, 839, 881, 937][index]; easing.type: Easing.InOutSine }
        }
        SequentialAnimation on opacity {
          running: wb.active && wb.visible
          loops: Animation.Infinite
          NumberAnimation { to: 0.55; duration: [379, 431, 479, 523, 577, 631, 683, 733, 787, 839, 881, 937][index]; easing.type: Easing.InOutSine }
          NumberAnimation { to: 1.0; duration: [379, 431, 479, 523, 577, 631, 683, 733, 787, 839, 881, 937][index]; easing.type: Easing.InOutSine }
        }
      }
    }
  }
}
