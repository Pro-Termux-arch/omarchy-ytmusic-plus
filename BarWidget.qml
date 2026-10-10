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
  property var theme: null
  function tc(name, fallback) { return (theme && theme[name] !== undefined) ? theme[name] : fallback; }
  function tc2(obj, key, fallback) { var o = tc(obj, null); return (o && o[key] !== undefined) ? o[key] : fallback; }
  property color themeForeground: tc("foreground", "#cacccc")
  property color themeAccent: tc("accent", "#cacccc")
  property color themeBarBackground: tc2("bar", "background", "#101315")
  property color themePopupsBorder: tc2("popups", "border", "#cacccc")
  Component.onCompleted: {
    try { theme = ShellColor; } catch (e1) { theme = null; }
    if (!theme) { try { theme = Color; } catch (e2) { theme = null; } }
  }

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
  readonly property color foreground: root.bar ? root.bar.barForeground : root.themeForeground
  readonly property bool opened: popupOpen
  property var vizLevels: []
  property string vizPath: Qt.resolvedUrl("bin/ytviz").toString().replace("file://", "")
  property int vizFailCount: 0
  property double vizLastFailMs: 0
  property double lastActiveMs: 0
  property bool idleHidden: false
  property string barMode: "full"
  property bool barExpand: true
  property bool fullScreen: false
  property bool vizOn: true
  readonly property bool barHover: pillHover.containsMouse || bodyMouse.containsMouse || compactMouse.containsMouse || bodyMouse.pressed || compactMouse.pressed
  readonly property bool pillFull: root.hasTrack && !root.idleHidden && root.barMode !== "compact" && (!root.barExpand || root.barHover)

  implicitWidth: root.pillFull ? Math.min(Style.space(320), pillRow.childrenRect.width + Style.space(5)) : (typeof barSize !== "undefined" ? barSize : Style.space(30))
  implicitHeight: barSize
  Behavior on implicitWidth { NumberAnimation { duration: 260; easing.type: Easing.OutExpo } }

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
    Qt.callLater(function() {
      if (!root.popupOpen) return
      if (popupPlayerLoader.item && popupPlayerLoader.item.open) popupPlayerLoader.item.open(payloadJson || "{}")
    })
  }

  function close(reason) {
    if (popupPlayerLoader.item && popupPlayerLoader.item.close) popupPlayerLoader.item.close()
    popupOpen = false
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
      root.barMode = (status.barMode === "compact") ? "compact" : "full"
      root.barExpand = (status.barExpand === "off") ? false : true
      root.fullScreen = (status.fullscreen === "on")
      root.vizOn = (status.viz === "off") ? false : true
      root.playerRunning = status.running === true
      root.playing = root.playerRunning && status.paused !== true
      var newTitle = String(status.title || "").slice(0, 500)
      if (newTitle !== "" && newTitle !== root.title) {
        root.lastActiveMs = Date.now()
        root.idleHidden = false
      }
      if (root.playing) {
        root.lastActiveMs = Date.now()
        root.idleHidden = false
      }
      if (newTitle === "") root.idleHidden = false
      root.title = newTitle
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
    visible: root.barMode !== "compact" && (!root.barExpand || root.pillFull)
    anchors.centerIn: parent
    width: parent.width
    height: Math.max(Style.space(24), parent.height - Style.space(8))
    radius: Style.space(6)
    color: root.hasTrack ? root.themeBarBackground : "transparent"
    border.width: root.hasTrack ? 1 : 0
    Behavior on color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }
    border.color: pillHover.containsMouse ? root.themeAccent : "transparent"
    scale: bodyMouse.pressed ? 0.97 : 1.0
    transformOrigin: Item.Center
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 150; easing.type: Easing.OutCubic } }

    // Hover glow: soft accent wash fading in on hover. NoButton so it never
    // steals body/button clicks; declared lowest so click areas stay on top.
    Rectangle {
      anchors.fill: parent
      radius: parent.radius
      color: root.themeAccent
      opacity: (pillHover.containsMouse && root.hasTrack) ? 0.10 : 0
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }

    MouseArea {
      id: pillHover
      anchors.fill: parent
      acceptedButtons: Qt.NoButton
      hoverEnabled: true
    }

  // Font-proof music-note/pause icon (canvas - renders regardless of fonts).
  component PhonesIcon: Canvas {
    id: phCanvas
    property string mode: "note"
    property color ink: root.themeAccent
    width: Style.space(13)
    height: Style.space(13)
    onWidthChanged: requestPaint()
    onModeChanged: requestPaint()
    onInkChanged: requestPaint()
    Component.onCompleted: requestPaint()
    onPaint: {
      var ctx = getContext("2d")
      var w = width
      var h = height
      if (w <= 0 || h <= 0) return
      ctx.clearRect(0, 0, w, h)
      var inkCss = "rgba(" + Math.round(ink.r * 255) + "," + Math.round(ink.g * 255) + "," + Math.round(ink.b * 255) + ",1)"
      ctx.strokeStyle = inkCss
      ctx.fillStyle = inkCss
      // Double-ring play mark: accent ring + solid play triangle (pause:
      // twin bars). Fully relative so it stays crisp at any size.
      ctx.lineWidth = Math.max(1.2, w * 0.11)
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      var cx = w / 2
      var cy = h / 2
      var rr = Math.min(w, h) / 2 - 1
      ctx.beginPath()
      ctx.arc(cx, cy, rr, 0, 2 * Math.PI)
      ctx.stroke()
      if (mode === "pause") {
        var bw = Math.max(1.4, w * 0.13)
        var gap = w * 0.18
        var bh = h * 0.5
        ctx.fillRect(cx - gap / 2 - bw, cy - bh / 2, bw, bh)
        ctx.fillRect(cx + gap / 2, cy - bh / 2, bw, bh)
        return
      }
      var s = Math.min(w, h) * 0.30
      ctx.beginPath()
      ctx.moveTo(cx - s * 0.55, cy - s)
      ctx.lineTo(cx + s * 0.9, cy)
      ctx.lineTo(cx - s * 0.55, cy + s)
      ctx.closePath()
      ctx.fill()
    }
  }
    // Body click: anywhere on the pill that isn't a button opens the player.
    // Declared above the hover detector so clicks still land here.
    MouseArea {
      id: bodyMouse
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openPlayer()
    }

    Item {
      anchors.fill: parent
      visible: (!root.hasTrack || root.idleHidden) && root.barMode !== "compact" && !root.barExpand
      opacity: ((!root.hasTrack || root.idleHidden) && root.barMode !== "compact" && !root.barExpand) ? 1 : 0
      scale: ((!root.hasTrack || root.idleHidden) && root.barMode !== "compact" && !root.barExpand) ? 1 : 0.85
      transformOrigin: Item.Center
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

      PhonesIcon {
        anchors.centerIn: parent
      }
    }

    Row {
      id: pillRow
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      anchors.leftMargin: Style.space(2)
      anchors.topMargin: Style.space(2)
      anchors.bottomMargin: Style.space(2)
      width: childrenRect.width
      spacing: Style.space(3)
      visible: root.pillFull
      opacity: root.pillFull ? 1 : 0
      scale: root.pillFull ? 1 : 0.96
      transformOrigin: Item.Center
      Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }

      Rectangle {
        id: posterBox
        width: root.thumbnail !== "" ? parent.height : 0
        height: parent.height
        radius: Style.space(6)
        topLeftRadius: Style.space(6)
        bottomLeftRadius: Style.space(6)
        topRightRadius: 0
        bottomRightRadius: 0
        color: root.themeBarBackground
        clip: true
        scale: posterHover.containsMouse ? 1.08 : 1.0
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Image {
          anchors.fill: parent
          source: root.thumbnail
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(192, 192)
        }
        MouseArea {
          id: posterHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openPlayer()
        }
      }

      Marquee {
        id: mqTitle
        width: Math.max(Style.space(34), Math.min(Style.space(120), mqTitle.contentWidth + Style.space(8)))
        anchors.verticalCenter: parent.verticalCenter
        text: root.title
        textColor: root.foreground
        textFont: root.bar ? root.bar.fontFamily : Style.font.menuFamily
        pixelSize: Style.font.caption
        bold: true
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openPlayer()
        }
      }

      VizBars {
        visible: root.vizOn
        width: root.vizOn ? Style.space(48) : 0
        anchors.verticalCenter: parent.verticalCenter
        levels: root.vizLevels
        barColor: root.themeAccent
      }

      Item {
        width: Style.space(20)
        height: parent.height
        scale: prevMouse.pressed ? 0.9 : (prevMouse.containsMouse ? 1.07 : 1.0)
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(20)
          height: width
          radius: width / 2
          color: root.themeAccent
          opacity: prevMouse.containsMouse ? 0.18 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        Text { anchors.centerIn: parent; text: "󰒮"; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        MouseArea { id: prevMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runAction("previous") }
      }

      Rectangle {
        width: Style.space(22)
        height: width
        radius: width / 2
        color: "transparent"
        scale: playMouse.pressed ? 0.9 : (playMouse.containsMouse ? 1.07 : 1.0)
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        anchors.verticalCenter: parent.verticalCenter
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: root.themeAccent
          opacity: playMouse.containsMouse ? 0.22 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        Text { anchors.centerIn: parent; text: "󰏤"; color: root.themeAccent; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; opacity: root.playing ? 1 : 0; scale: root.playing ? 1 : 0.6; Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
        Text { anchors.centerIn: parent; text: "󰐊"; color: root.themeAccent; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall; opacity: root.playing ? 0 : 1; scale: root.playing ? 0.6 : 1; Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } } Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } } }
        MouseArea {
          id: playMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (root.playerRunning) root.runAction("toggle")
            else root.openPlayer()
          }
        }
      }

      Item {
        width: Style.space(20)
        height: parent.height
        scale: nextMouse.pressed ? 0.9 : (nextMouse.containsMouse ? 1.07 : 1.0)
        transformOrigin: Item.Center
        Behavior on scale { NumberAnimation { duration: 160; easing.type: Easing.OutBack } }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(20)
          height: width
          radius: width / 2
          color: root.themeAccent
          opacity: nextMouse.containsMouse ? 0.18 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        }
        Text { anchors.centerIn: parent; text: "󰒭"; color: root.foreground; font.family: root.bar ? root.bar.fontFamily : Style.font.menuFamily; font.pixelSize: Style.font.bodySmall }
        MouseArea { id: nextMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.runAction("next") }
      }
    }

    // Poster hover ART CARD: 96px preview above the pill. Shadow is a plain
    // darker rect (no new imports/effects). If the shell clips overflow the
    // card hides and the in-place poster scale still signals hover.
    Item {
      id: posterCard
      z: 100
      width: Style.space(96)
      height: Style.space(96)
      x: 0
      y: -height - Style.space(6)
      visible: posterHover.containsMouse && root.thumbnail !== "" && root.barMode !== "compact" && root.pillFull
      opacity: posterHover.containsMouse ? 1 : 0
      scale: posterHover.containsMouse ? 1 : 0.9
      transformOrigin: Item.BottomLeft
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutBack } }
      Rectangle {
        x: 2
        y: 3
        width: parent.width
        height: parent.height
        radius: Style.space(8)
        color: "black"
        opacity: 0.45
      }
      Rectangle {
        anchors.fill: parent
        radius: Style.space(8)
        color: root.themeBarBackground
        border.width: 1
        border.color: root.themePopupsBorder
        clip: true
        Image {
          anchors.fill: parent
          source: root.thumbnail
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          sourceSize: Qt.size(192, 192)
        }
      }
    }
  }

  // Compact bar: icon-square footprint (omarchy icon style, no pill).
  // idle/no-track -> canvas note; playing -> mini WaveBars; paused -> canvas pause.
  Item {
    id: compactBox
    anchors.fill: parent
    visible: root.barMode === "compact" || (root.barMode !== "compact" && root.barExpand && !root.pillFull)
    opacity: (root.barMode === "compact" || (root.barMode !== "compact" && root.barExpand && !root.pillFull)) ? 1 : 0
    scale: (root.barMode === "compact" || (root.barMode !== "compact" && root.barExpand && !root.pillFull)) ? 1 : 0.9
    transformOrigin: Item.Center
    Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
    Rectangle {
      anchors.fill: parent
      color: root.themeAccent
      opacity: compactMouse.containsMouse ? 0.12 : 0
      Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    }
    PhonesIcon {
      anchors.centerIn: parent
      visible: !root.hasTrack || root.idleHidden
    }
    WaveBars {
      anchors.centerIn: parent
      visible: root.hasTrack && !root.idleHidden && root.playing
      bars: 3
      width: Style.space(13)
      barColor: root.themeAccent
      active: true
    }
    PhonesIcon {
      anchors.centerIn: parent
      visible: root.hasTrack && !root.idleHidden && !root.playing
      mode: "pause"
    }
    MouseArea {
      id: compactMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.openPlayer()
    }
  }

  KeyboardPanel {
    id: playerPopup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: playerPopup.fittedContentWidth(root.fullScreen ? Style.space(987) : Style.space(377))
    contentHeight: playerPopup.cappedContentHeight(root.fullScreen ? Style.space(700) : Style.space(610)) // fullscreen 700: content needs it (footer clips at 610)
    padding: 0
    margin: Style.gapsOut
    focusTarget: popupPlayerLoader.item ? popupPlayerLoader.item.searchInput : null

    Loader {
      id: popupPlayerLoader
      anchors.fill: parent
      active: true
      source: Qt.resolvedUrl("Player.qml")
      opacity: root.popupOpen ? 1 : 0
      scale: root.popupOpen ? 1 : 0.96
      transformOrigin: Item.Center
      transform: Translate { id: popupRise; y: root.popupOpen ? 0 : Style.space(6); Behavior on y { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } } }
      Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
      Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutBack } }
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

  function tryStartViz() {
    if (!root.hasTrack || !root.playing || !root.vizOn) return
    if (vizProc.running) return
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
  onPlayingChanged: if (root.hasTrack && root.playing) root.tryStartViz()
  onHasTrackChanged: if (root.hasTrack && root.playing) root.tryStartViz()

  Timer {
    interval: 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refreshStatus()
      var want = root.hasTrack && root.playing && root.vizOn
      if (root.hasTrack && !root.playing && (Date.now() - root.lastActiveMs) > 60000) root.idleHidden = true
      if (!want) {
        if (vizProc.running) vizProc.running = false
        if (root.vizLevels.length) root.vizLevels = []
        if (root.vizFailCount !== 0) root.vizFailCount = 0
        return
      }
      root.tryStartViz()
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
