import QtQuick

// Spectrum strip for the mini player. Feed `levels` (0-100 per bar) from the
// ytviz backend for REAL output-monitor spectrum; with no data it sits as a
// flat dim line — never dancing when nothing plays.
Item {
  id: viz
  property var levels: []
  property int bars: 10
  property color barColor: "#2ecc71"
  property color dimColor: "#3a3f4b"

  implicitWidth: Math.max(0, Math.min(32, bars)) * 5
  implicitHeight: 18

  function levelAt(i) {
    if (!Array.isArray(viz.levels)) return 0
    var v = Number(viz.levels[i])
    if (!isFinite(v)) return 0
    return Math.max(0, Math.min(100, v))
  }

  readonly property bool live: viz.levels && viz.levels.length >= viz.bars

  Row {
    anchors.centerIn: parent
    spacing: 2
    Repeater {
      model: Math.max(0, Math.min(32, viz.bars))
      Rectangle {
        id: barRect
        width: 3
        property real targetLevel: viz.live ? viz.levelAt(index) : 0
        property real displayLevel: 0
        height: Math.max(2, Math.min(18, Math.round(displayLevel / 100 * 18)))
        radius: 1.5
        color: viz.live ? viz.barColor : viz.dimColor
        Behavior on color { ColorAnimation { duration: 180; easing.type: Easing.OutCubic } }
        opacity: viz.live ? (0.55 + 0.45 * Math.pow(displayLevel / 100, 0.65)) : 1.0
        anchors.verticalCenter: parent.verticalCenter
        Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        NumberAnimation {
          id: lvlAnim
          target: barRect
          property: "displayLevel"
          easing.type: Easing.OutCubic
        }
        onTargetLevelChanged: {
          if (displayLevel === targetLevel) return
          lvlAnim.to = targetLevel
          var rising = targetLevel > displayLevel
          lvlAnim.duration = rising ? (110 + index * 3) : (380 + index * 2)
          lvlAnim.restart()
        }
        Rectangle {
          anchors.top: parent.top
          anchors.horizontalCenter: parent.horizontalCenter
          width: 3
          height: 2
          radius: 1.0
          color: viz.barColor
          opacity: viz.live ? Math.max(0, Math.min(0.9, (barRect.displayLevel - 72) / 28 * 0.9)) : 0
          Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
