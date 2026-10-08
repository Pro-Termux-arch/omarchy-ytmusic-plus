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

  implicitWidth: bars * 5
  implicitHeight: 18

  function levelAt(i) {
    var v = Number(viz.levels[i])
    if (!isFinite(v)) return 0
    return Math.max(0, Math.min(100, v))
  }

  readonly property bool live: viz.levels && viz.levels.length >= viz.bars

  Row {
    anchors.centerIn: parent
    spacing: 2
    Repeater {
      model: viz.bars
      Rectangle {
        width: 3
        height: viz.live
          ? Math.max(2, Math.min(18, Math.round(viz.levelAt(index) / 100 * 18)))
          : 2
        radius: 1.5
        color: viz.live ? viz.barColor : viz.dimColor
        opacity: viz.live ? 0.55 + viz.levelAt(index) / 100 * 0.45 : 1.0
        anchors.verticalCenter: parent.verticalCenter
        Behavior on height { NumberAnimation { duration: 90 + index * 12; easing.type: Easing.OutCubic } }
        Behavior on opacity { NumberAnimation { duration: 90 + index * 12; easing.type: Easing.OutCubic } }
      }
    }
  }
}
