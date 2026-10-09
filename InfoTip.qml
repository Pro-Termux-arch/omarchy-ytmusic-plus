import QtQuick
import qs.Commons

// Hover tooltip with a long dwell (5s): place inside any icon button, point
// `watched` at its MouseArea. Shows what the button does without clicking.
Rectangle {
  id: tip
  property var theme: null
  function tc(name, fallback) { return (theme && theme[name] !== undefined) ? theme[name] : fallback; }
  function tc2(obj, key, fallback) { var o = tc(obj, null); return (o && o[key] !== undefined) ? o[key] : fallback; }
  property color themeTooltipBackground: tc2("tooltip", "background", "#101315")
  property color themeTooltipBorder: tc2("tooltip", "border", "#cacccc")
  property color themeTooltipText: tc2("tooltip", "text", "#cacccc")
  Component.onCompleted: {
    try { theme = ShellColor; } catch (e1) { theme = null; }
    if (!theme) { try { theme = Color; } catch (e2) { theme = null; } }
  }
  property var watched
  property string tipText: ""
  property int delayMs: 5000
  // Crash-safe hover mirror: the null-guarded path below evaluates to the
  // guard branch when watched is null or destroyed, so this binding never
  // dereferences a dead object. That keeps us off the retargeting path
  // where a one-off Quickshell SEGV was observed.
  readonly property bool hovered: (tip.watched ? tip.watched.containsMouse : false) === true
  property bool dwellOk: false
  onHoveredChanged: if (!tip.hovered) tip.dwellOk = false

  width: tipLabel.width + Style.space(14)
  height: Style.space(22)
  radius: Style.space(6)
  color: tip.themeTooltipBackground
  border.width: 1
  border.color: tip.themeTooltipBorder
  visible: tip.tipText !== "" && tip.hovered && tip.dwellOk
  z: 100

  anchors.bottom: parent.top
  anchors.bottomMargin: Style.space(6)
  anchors.horizontalCenter: parent.horizontalCenter

  Text {
    id: tipLabel
    anchors.centerIn: parent
    text: tip.tipText
    textFormat: Text.PlainText
    maximumLineCount: 1
    elide: Text.ElideRight
    width: Math.min(implicitWidth, Style.space(220))
    color: tip.themeTooltipText
    font.family: Style.font.menuFamily
    font.pixelSize: Style.font.caption
  }

  Timer {
    interval: tip.delayMs
    running: tip.tipText !== "" && tip.hovered && !tip.dwellOk
    repeat: false
    onTriggered: tip.dwellOk = true
  }
}
