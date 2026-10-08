import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Compact bar presence for YTMusic Plus. The full player lives in Player.qml;
// this widget shows now-playing state and transport controls, all painted with
// theme tokens (Color.accent / bar foreground) so theme switches repaint it.
BarWidget {
  id: root
  moduleName: "local.ytmusic-plus"

  property string title: ""
  property string artist: ""
  property string thumbnail: ""
  property bool playing: false
  property bool playerRunning: false
  property bool popupOpen: false
  property bool saved: false
  property bool downloaded: false
  property string scriptPath: Qt.resolvedUrl("bin/ytmusic-plus").toString().replace("file://", "")
  readonly property bool hasTrack: title !== ""
  readonly property color foreground: root.bar ? root.bar.barForeground : Color.foreground
  readonly property bool opened: popupOpen
  property var vizLevels: []
  property string vizPath: Qt.resolvedUrl("bin/ytviz").toString().replace("file://", "")
  property int vizFailCount: 0
  property double vizLastFailMs: 0
  // Idle collapse: a track merely being loaded is not "using" the player, so
  // the pill starts as its icon and only expands once you touch it (hover,
  // click, or open). It then lingers for `collapseMs` after your last
  // interaction before shrinking back to the icon. Bump to stay expanded longer.
  property int collapseMs: 5000
  property bool collapsed: true

  implicitWidth: (hasTrack && !root.collapsed) ? Style.space(218) : Style.space(30)
  implicitHeight: barSize

  function applyViz(line) {
    var s = String(line || "")
    if (s.length > 512) return
    var parts = s.trim().split(/\s+/)
    if (parts.length < 10) return
    var lv = []
    for (var i = 0; i < 10; i++) {
      var n = parseInt(parts[i], 10)
      lv.push(isFinite(n) ? Math.max(0, Math.min(100, n)) : 0)
    }
    vizLevels = lv
    vizFailCount = 0
  }

  function openPlayer() { root.toggle("{}") }

  function open(payloadJson) {
    popupOpen = true
    root.collapsed = false
    Qt.callLater(function() {
      if (popupPlayerLoader.item && popupPlayerLoader.item.open) popupPlayerLoader.item.open(payloadJson || "{}")
    })
  }

  function close(reason) {
    if (popupPlayerLoader.item && popupPlayerLoader.item.close) popupPlayerLoader.item.close()
    popupOpen = false
    collapseTimer.restart()
  }

  // Any real interaction reveals the full pill and (re)starts the idle
  // countdown that shrinks it back to an icon.
  function poke() {
    root.collapsed = false
    collapseTimer.restart()
  }

  function toggle(payloadJson) {
    if (root.opened) root.close("toggle")
    else root.open(payloadJson || "{}")
  }

  function runAction(action) {
    if (action !== "toggle" && action !== "next" && action !== "previous") return
    if (actionProc.running) return
    actionProc.command = ["bash", scriptPath, action]
    actionProc.running = true
  }

  function refreshStatus() {
    if (statusProc.running) return
    statusProc.command = ["bash", scriptPath, "status"]
    statusProc.running = true
  }

  function applyStatus(raw) {
    try {
      var status = JSON.parse(String(raw || "{}"))
      root.playerRunning = status.running === true
      root.playing = root.playerRunning && status.paused !== true
      root.title = String(status.title || "").slice(0, 500)
      root.artist = String(status.artist || "").slice(0, 500)
      var thumb = String(status.thumbnail || "")
      if (thumb !== "" && thumb.indexOf("https://") !== 0 && thumb.indexOf("http://") !== 0 && thumb.indexOf("file://") !== 0) thumb = ""
      root.thumbnail = thumb.slice(0, 500)
    } catch (error) {
      console.warn("YTMusic Plus bar: invalid player status", error)
      root.playerRunning = false
      root.playing = false
    }
  }

  Rectangle {
    id: pillBg
    anchors.centerIn: parent
    width: parent.width
    height: Math.max(Style.space(24), parent.height - Style.space(8))
    radius: Style.space(6)
    color: root.hasTrack ? Color.bar.background : "transparent"
    border.width: root.hasTrack ? 1 : 0
    border.color: pillHover.containsMouse ? Color.accent : Color.popups.border
    Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

    // Hover glow: soft accent wash fading in on hover. NoButton so it never
    // steals body/button clicks; declared lowest so click areas stay on top.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: Color.accent
      opacity: (pillHover.containsMouse && root.hasTrack) ? 0.10 : 0
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      id: pillHover
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
      onEntered: root.poke()
      onExited: collapseTimer.restart()
    }

    // Body click: anywhere on the pill that isn't a button opens the player.
    // Declared above the hover detector so clicks still land here.
    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.poke(); root.openPlayer() }
    }

    Item {
      anchors.fill: parent
      visible: !root.hasTrack || root.collapsed

      Text {
        anchors.centerIn: parent
        text: "󰒣"
        color: root.foreground
        font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily
        font.pixelSize: Style.font.iconLarge
      }
    }

    Row {
      anchors.fill: parent
      anchors.margins: Style.space(2)
      spacing: Style.space(3)
      visible: root.hasTrack && !root.collapsed

      Rectangle {
        width: parent.height
        height: parent.height
        radius: Style.space(4)
        color: Color.bar.background
        clip: true
        Image { anchors.fill: parent; source: root.thumbnail; fillMode: Image.PreserveAspectCrop; asynchronous: true }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.poke(); root.openPlayer() }
        }
      }

      Marquee {
        width: Style.space(44)
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        textColor: root.foreground
        textFont: root.bar ? root.bar.fontFamily : Style.font.menuFamily
        pixelSize: Style.font.caption
        bold: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.poke(); root.openPlayer() }
        }
      }

      VizBars {
        width: Style.space(52)
        anchors.verticalCenter: parent.verticalCenter
        levels: root.vizLevels
        barColor: Color.accent
      }

      Item {
        width: Style.space(20)
        height: parent.height
        scale: prevMouse.pressed ? 0.9 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(20)
          height: width
          radius: width / 2
          color: Color.accent
          opacity: prevMouse.containsMouse ? 0.18 : 0
          Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        Text { anchors.centerIn: parent; text: "󰒮"; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.poke(); root.runAction("previous") } }
      }

      Rectangle {
        width: Style.space(22)
        height: width
        radius: width / 2
        color: "transparent"
        scale: playMouse.pressed ? 0.9 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Color.accent
          opacity: playMouse.containsMouse ? 0.22 : 0
          Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        Text { anchors.centerIn: parent; text: "󰏤"; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; opacity: root.playing ? 1 : 0; scale: root.playing ? 1 : 0.6; Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
        Text { anchors.centerIn: parent; text: "󰐊"; color: Color.accent; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; opacity: root.playing ? 0 : 1; scale: root.playing ? 0.6 : 1; Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
        MouseArea {
          id: playMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            root.poke()
            if (root.playerRunning) root.runAction("toggle")
            else root.openPlayer()
          }
        }
      }

      Item {
        width: Style.space(20)
        height: parent.height
        scale: nextMouse.pressed ? 0.9 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(20)
          height: width
          radius: width / 2
          color: Color.accent
          opacity: nextMouse.containsMouse ? 0.18 : 0
          Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        Text { anchors.centerIn: parent; text: "󰒭"; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { root.poke(); root.runAction("next") } }
      }
    }
  }

  KeyboardPanel {
    id: playerPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: playerPopup.fittedContentWidth(Style.space(410))
    contentHeight: playerPopup.cappedContentHeight(Style.space(560))
    padding: 0
    margin: Style.gapsOut
    focusTarget: popupPlayerLoader.item ? popupPlayerLoader.item.searchInput : null

    Loader {
      id: popupPlayerLoader
      anchors.fill: parent
      active: true
      source: Qt.resolvedUrl("Player.qml")
      onLoaded: {
        item.closeCallback = function() { root.close("closeCallback") }
      }
    }
  }

  Process {
    id: actionProc
    onExited: root.refreshStatus()
  }

  // Live spectrum from the output monitor (ytviz). Streams text lines; dies
  // quietly without a monitor, and the bars idle as a flat dim line instead.
  // NOTE: the monitor is the SYSTEM mix by design, so browser/Discord audio
  // also moves the bars. We only run ytviz while our player reports playing.
  Process {
    id: vizProc
    stdout: SplitParser { onRead: function(line) { root.applyViz(line) } }
    onExited: {
      root.vizLevels = []
      if (root.hasTrack && root.playing) {
        root.vizFailCount += 1
        root.vizLastFailMs = Date.now()
      }
    }
  }

  Timer {
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshStatus()
      var want = root.hasTrack && root.playing
      if (!want) {
        if (vizProc.running) vizProc.running = false
        if (root.vizLevels.length) root.vizLevels = []
        if (root.vizFailCount !== 0) root.vizFailCount = 0
        return
      }
      if (!vizProc.running) {
        var backoff = 0
        if (root.vizFailCount > 0) {
          var shift = Math.min(5, root.vizFailCount - 1)
          backoff = Math.min(30000, 1500 * Math.pow(2, shift))
        }
        if (Date.now() - root.vizLastFailMs >= backoff) {
          vizProc.command = [vizPath]
          vizProc.running = true
        }
      }
    }
  }

  // Idle collapse countdown. Seeing the bar expand on track load isn't
  // "using" the player, so it starts collapsed; poke() reveals + restarts this,
  // and it never fires while you're hovering or the player popup is open.
  Timer {
    id: collapseTimer
    interval: root.collapseMs
    repeat: false
    onTriggered: {
      if (!root.popupOpen && !pillHover.containsMouse) root.collapsed = true
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  IpcHandler {
    target: root.moduleName

    function open(): void { root.open("{}") }
    function close(): void { root.close("ipc") }
    function toggle(): void { root.toggle("{}") }
  }
}
