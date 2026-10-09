import QtQuick
import Quickshell
import Quickshell.Io
import Qt5Compat.GraphicalEffects
import QtQuick.Dialogs
import qs.Commons
import qs.Ui

// YTMusic Plus player: search, queue, playlists, saved tracks, offline downloads.
// All painting uses theme tokens (Color.* / Style.*) — no hardcoded brand colors.
Item {
  id: root

  implicitWidth: Style.space(410)
  implicitHeight: Style.space(560)

  // Theme-derived roles. surfaces follow the active Omarchy theme; the accent
  // (and its readable on-accent) repaint automatically on theme switches.
  // Theme bridge: ShellColor on newer shells, Color on this machine, literals
  // when neither singleton exists. tc/tc2 re-evaluate on theme assignment
  // (null->object at completion) and on live theme switches via notify.
  property var theme: null
  function tc(name, fallback) { return (theme && theme[name] !== undefined) ? theme[name] : fallback; }
  function tc2(obj, key, fallback) { var o = tc(obj, null); return (o && o[key] !== undefined) ? o[key] : fallback; }
  readonly property color ink: tc2("popups", "text", "#cacccc")
  readonly property color surface: tc2("popups", "background", "#101315")
  readonly property color border: tc2("popups", "border", "#cacccc")
  readonly property color muted: tc("muted", "#707880")
  readonly property color accent: tc("accent", "#cacccc")
  readonly property color barBackground: tc2("bar", "background", "#101315")
  readonly property color raised: Style.normalFill
  Component.onCompleted: {
    try { theme = ShellColor; } catch (e1) { theme = null; }
    if (!theme) { try { theme = Color; } catch (e2) { theme = null; } }
  }
  readonly property color onAccent: (0.299 * accent.r + 0.587 * accent.g + 0.114 * accent.b) > 0.6 ? "#101010" : "#ffffff"
  // Release stamp, bottom-left. Bump together with manifest.json + CHANGELOG.md.
  readonly property string appVersion: "v2.2.7 beta"

  property bool opened: false
  property bool searching: false
  property int tabIndex: 1 // 0 home · 1 find · 2 queue · 3 playlist · 4 favourite · 5 local · 6 lyrics · 7 settings
  property int hoveredTab: -1 // dock highlight follows the mouse; rests on tabIndex
  // Custom UI font (settings → font picker). Icons always stay on the system
  // font so nerd glyphs never break under a font that lacks them.
  property string customFontName: ""
  readonly property string uiFont: customFontName !== "" ? customFontName : Style.font.menuFamily
  readonly property string iconFont: Style.font.menuFamily
  // Home discovery state
  property string homeMode: "main" // main - top - artist - radio - tunes
  property string homeRadioTag: "pop"
  property string homeTunesQuery: ""
  property bool homeLoading: false
  property bool homeForceRefresh: false
  property bool homeMore: false
  property string currentUrl: "" // non-empty when the track on air is a stream
  property bool settingsDirty: false // a `set` is in flight; reload after drain
  // Playback modes from backend status
  property string loopMode: "off" // off · all · one
  property bool silenceOn: false
  property bool normalizeOn: false
  property int sleepUntil: 0
  property string sleepMode: ""
  // Smooth lyric clock: interpolate between mpv polls with the local clock
  property real smoothPos: 0
  property double lastStatusAt: 0
  property real trackLyricOffset: 0 // effective offset for this song (per-track or global)
  property bool mixAuto: true
  // Settings tab mirrors
  property bool setSilence: false
  property bool setNormalize: false
  property int setVolume: 70
  property real setLyricsOffset: 0
  property bool setMixAuto: true
  property int setSearchLimit: 12
  property string setDlQuality: "best"
  property string updateStatusText: "Never checked - press Check"
  property bool updateAvailable: false
  property string updateLocalSha: ""
  property string updateRemoteSha: ""
  property string updateLocalVersion: ""
  property string updateChannel: "beta"
  property string updateTarget: "-"
  property bool updateAuto: true
  property int updateLastCheck: 0
  property bool updateChecking: false
  property bool updateAutoChecked: false
  property bool updateVerifyPending: false
  property bool updateManualApply: false
  property string eqPresetName: "flat"
  property var eqGainsArr: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  readonly property var eqBands: ["31", "62", "125", "250", "500", "1K", "2K", "4K", "8K", "16K"]
  readonly property var eqPresets: ["flat", "bass", "treble", "vocal", "rock", "pop", "jazz", "classical", "electronic"]
  property string listMode: "search"
  property string listTitle: ""
  property string errorMessage: ""
  property string notice: ""
  // One status line shows notice || error: a fresh notice retires a stale
  // error, and a fresh error preempts the notice + stops its timer.
  onNoticeChanged: if (notice !== "") errorMessage = ""
  onErrorMessageChanged: if (errorMessage !== "") {
    notice = ""
    noticeTimer.stop()
  }
  property int selectedIndex: 0
  property int currentIndex: -1
  // True only when the visible list IS the backend queue at the on-air row:
  // keeps the played-row dim + queue position honest on foreign lists.
  readonly property bool queueAligned: listMode === "queue" && currentIndex >= 0 && currentIndex < tracks.count && tracks.count > 0 && currentVideoId !== "" && tracks.get(currentIndex).videoId === currentVideoId
  property string currentTitle: ""
  property string currentArtist: ""
  property string currentThumbnail: ""
  property string currentDuration: ""
  property string currentVideoId: ""
  property bool currentSaved: false
  property bool currentFollowed: false
  property bool currentDownloaded: false
  property bool mixPrefetching: false
  property bool currentIsLive: false
  property bool playing: false
  property bool playerRunning: false
  property real position: 0
  property real playbackDuration: 0
  property bool showRemaining: false // time labels: elapsed vs remaining
  property string seekStyle: "default"
  property real wavePhase: 0
  property bool vizOn: true
  property bool helpMode: false
  NumberAnimation on wavePhase { from: 0; to: 6.2832; duration: 2400; loops: Animation.Infinite; easing.type: Easing.Linear; running: waveCanvas.visible && root.playing }
  onWavePhaseChanged: waveCanvas.requestPaint()
  property alias searchInput: searchField
  property var closeCallback: null
  property string scriptPath: Qt.resolvedUrl("bin/ytmusic-plus").toString().replace("file://", "")
  property string openPlaylistName: ""
  property string addTargetPlaylist: ""
  // Lyrics state
  property string lyricsLoadedFor: ""
  property bool lyricsSynced: false
  property bool lyricLoading: false
  property int currentLyricIndex: -1

  Keys.onPressed: function(event) {
    if (event.key === Qt.Key_Escape) {
      root.requestClose()
      event.accepted = true
    }
  }

  function open(payloadJson) {
    opened = true
    errorMessage = ""
    notice = ""
    updateAutoChecked = false
    refreshStatus()
    refreshMeta()
    loadSettings()
    if (homeModel.count === 0 && tabIndex === 0) reloadHome()
  }

  function close() {
    searchField.focus = false
    opened = false
  }
  function requestClose() {
    if (closeCallback) closeCallback()
    else close()
  }
  function toggle(payloadJson) { opened ? close() : open(payloadJson) }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var hours = Math.floor(value / 3600)
    var minutes = Math.floor((value % 3600) / 60)
    var remainingSeconds = value % 60
    if (hours > 0)
      return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(remainingSeconds).padStart(2, "0")
    return minutes + ":" + String(remainingSeconds).padStart(2, "0")
  }

  function isVideoId(value) {
    return /^[A-Za-z0-9_-]{11}$/.test(String(value || ""))
  }

  function durationLabel(duration, isLive) {
    var value = String(duration || "").trim()
    if (isLive || value.toUpperCase() === "NA" || value.toUpperCase() === "N/A") return "LIVE"
    return value || "--:--"
  }

  // Remote art may only be remote: reject file://, data:, absolute/relative
  // local paths so a crafted thumbnail can never probe the local filesystem.
  function isSafeImageUrl(u) {
    var s = String(u || "").trim()
    if (!s || s === "NA") return false
    if (s[0] === "/" || s[0] === "." || s[0] === "~") return false
    if (/^(file|data|blob|ftp|jar|filesystem):/i.test(s)) return false
    return /^https?:/i.test(s)
  }

  // Strip C0/C1 controls and bidi overrides (U+202D-U+202E, U+2066-U+2069)
  // from remote titles/artists so a malicious name cannot spoof UI order.
  // Points: [0-8] [11-12] [14-31] [127-159] [8237-8238] [8294-8297].
  function sanitizeText(s) {
    var ranges = [[0, 8], [11, 12], [14, 31], [127, 159], [8237, 8238], [8294, 8297]]
    var out = String(s || "")
    for (var r = 0; r < ranges.length; r++) {
      for (var c = ranges[r][0]; c <= ranges[r][1]; c++) out = out.split(String.fromCharCode(c)).join("")
    }
    return out
  }

  function thumbFor(videoId, raw, streamUrl) {
    var t = String(raw || "").trim()
    if (t && t !== "NA") {
      if (isSafeImageUrl(t)) return t
      if (streamUrl) return ""
      // Unsafe art on a YouTube row: fall back to stock ytimg art.
      if (!isVideoId(videoId)) return ""
      return "https://i.ytimg.com/vi/" + videoId + "/hqdefault.jpg"
    }
    // Streams (radio/previews) have no ytimg art — blank tile, no broken URL.
    if (streamUrl) return ""
    if (!isVideoId(videoId)) return ""
    return "https://i.ytimg.com/vi/" + videoId + "/hqdefault.jpg"
  }

  // ---- home: free, legit, keyless discovery -----------------------------------
  // Charts (Apple RSS), free radio (Radio Browser), tune search (iTunes
  // previews). Radio + previews are direct streams played without any
  // YouTube resolving; chart picks jump to the full track on YouTube.
  function loadHome() {
    listMode = "home"
    if (homeModel.count === 0 && !homeProc.running) reloadHome()
  }

  function reloadHome(force) {
    // Rapid genre/mode hops: remember to refetch with the LATEST tag instead
    // of landing stale results for a previous one.
    if (homeMode === "artist") { root.reloadArtists(); return }
    if (force === true) homeForceRefresh = true
    if (homeProc.running) { homeProc.refetch = true; return }
    var useForce = (force === true) || homeForceRefresh
    homeForceRefresh = false
    homeLoading = true
    errorMessage = ""
    homeProc.collected = ""
    if (homeMode === "main") homeProc.command = useForce ? ["bash", scriptPath, "foryou", "refresh"] : ["bash", scriptPath, "foryou"]
    else if (homeMode === "top") homeProc.command = useForce ? ["bash", scriptPath, "charts", "refresh"] : ["bash", scriptPath, "charts"]
    else if (homeMode === "radio") homeProc.command = ["bash", scriptPath, "radio", homeRadioTag]
    else if (homeMode === "tunes") homeProc.command = ["bash", scriptPath, "tunes", homeTunesQuery]
    else homeProc.command = useForce ? ["bash", scriptPath, "foryou", "refresh"] : ["bash", scriptPath, "foryou"]
    homeProc.running = true
  }

  function setHomeMode(m) {
    homeMode = m
    homeModel.clear()
    try { artistModel.clear() } catch (e) {}
    reloadHome()
  }

  function fillHome(raw) {
    try {
      var arr = JSON.parse(String(raw || "[]"))
      homeModel.clear()
      for (var i = 0; i < arr.length; i++) {
        var r = arr[i] || {}
        var homeUrl = String(r.url || "")
        if (homeUrl && !/^https?:/i.test(homeUrl.trim())) homeUrl = ""
        var homeKind = String(r.kind || "chart")
        if (homeKind !== "radio" && homeKind !== "preview" && homeKind !== "chart") homeKind = "chart"
        var homeReason = sanitizeText(r.reason || "")
        homeModel.append({
          title: sanitizeText(r.title) || "Untitled",
          artist: sanitizeText(r.artist),
          art: isSafeImageUrl(r.art) ? String(r.art) : "",
          url: homeUrl,
          kind: homeKind,
          reason: homeReason
        })
      }
      if (homeModel.count === 0) errorMessage = "Nothing here yet"
    } catch (e) {
      errorMessage = "Discovery failed (offline?)"
    }
  }

  // Stable fake ids (11 chars, backend-accepted) so streams can ride the same
  // queue/state/save machinery as YouTube tracks.
  function fakeId(prefix, seed) {
    var h = 7
    var s = String(seed || "")
    for (var i = 0; i < s.length; i++) h = ((h * 31 + s.charCodeAt(i)) | 0)
    var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
    var out = prefix
    var x = h < 0 ? -h : h
    for (var j = 0; j < 8; j++) {
      out += chars.charAt(x % 62)
      x = Math.floor(x / 62) + j * 13 + 5
    }
    return out
  }

  function playHome(i) {
    if (i < 0 || i >= homeModel.count) return
    var row = homeModel.get(i)
    if (row.kind === "radio" || row.kind === "preview") {
      playDirect(row.url, row.title, row.artist, row.art, row.kind)
    } else {
      ytSearchAndPlay(row.artist + " " + row.title)
    }
  }

  function playDirect(url, title, artist, art, kind) {
    if (!/^https?:/i.test(String(url || "").trim())) return
    tracks.clear()
    tracks.append({
      videoId: fakeId(kind === "radio" ? "RDO" : "PVW", url),
      title: title || "Stream",
      artist: artist || (kind === "radio" ? "Radio" : "Preview"),
      duration: kind === "radio" ? "LIVE" : "0:30",
      isLive: kind === "radio",
      thumbnail: art || "",
      url: url
    })
    listMode = "queue"
    listTitle = kind === "radio" ? "Radio" : "Preview"
    selectedIndex = 0
    playAt(0)
    if (tabIndex !== 2) setTab(2)
  }

  function ytSearchAndPlay(q) {
    if (!q || !q.trim()) return
    notice = "Finding full track…"
    noticeTimer.restart()
    loadTsv(["search", q.trim()], "search-home", "")
  }

  function reloadArtists() {
    if (artistProc.running) { artistProc.refetch = true; return }
    artistLoading = true
    errorMessage = ""
    artistProc.op = "list"
    artistProc.collected = ""
    artistProc.command = ["bash", scriptPath, "artist-list"]
    artistProc.running = true
  }

  // Artist find-as-you-type: argv-only artist-find, results into
  // artistFindModel as [{name, art, genre}]. Short queries clear silently;
  // backend miss/offline clears silently too (Enter with zero results falls
  // back to direct-query-as-profile in the search field handler).
  function findArtists(q) {
    var s = sanitizeText(String(q || "")).trim()
    if (s.length < 2) { artistFindModel.clear(); artistFinding = false; return }
    if (s.length > 100) s = s.slice(0, 100)
    artistFindQuery = s
    if (artistFindProc.running) { artistFindProc.pendingQuery = s; artistFindProc.refetch = true; return }
    artistFinding = true
    artistFindProc.query = s
    artistFindProc.collected = ""
    artistFindProc.command = ["bash", scriptPath, "artist-find", s]
    artistFindProc.running = true
  }

  function loadArtistProfile(name) {
    var n = String(name || "").trim()
    if (n.length < 1 || n.length > 100) { errorMessage = "Artist name 1-100 chars"; return }
    n = sanitizeText(n).trim()
    if (n.length < 1 || n.length > 100) { errorMessage = "Artist name 1-100 chars"; return }
    artistProfile = n
    artistSongsModel.clear()
    artistBio = ""
    artistSubs = ""
    artistGenre = ""
    artistPortrait = ""
    artistBioOpen = false
    if (artistSongsProc.running) {
      artistSongsProc.pendingName = n
      artistSongsProc.refetch = true
      if (artistProfileProc.running) { artistProfileProc.pendingName = n; artistProfileProc.refetch = true }
      return
    }
    artistLoading = true
    errorMessage = ""
    artistSongsProc.collected = ""
    artistSongsProc.command = ["bash", scriptPath, "artist-songs", n]
    artistSongsProc.running = true
    // Portrait/bio sidecar alongside artist-songs: same busy/refetch shape,
    // argv-only call, never touches the songs loading state.
    if (artistProfileProc.running) { artistProfileProc.pendingName = n; artistProfileProc.refetch = true; return }
    artistProfileProc.collected = ""
    artistProfileProc.command = ["bash", scriptPath, "artist-profile", n]
    artistProfileProc.running = true
  }

  function toggleFollow(name, art) {
    var n = String(name || "").trim()
    if (n.length < 1 || n.length > 100) { errorMessage = "Artist name 1-100 chars"; return }
    n = sanitizeText(n).trim()
    if (!n) { errorMessage = "Artist name 1-100 chars"; return }
    var a = String(art || "").trim()
    if (!isSafeImageUrl(a) || !/^https:/i.test(a)) a = ""
    var followed = false
    for (var i = 0; i < artistModel.count; i++) {
      if (artistModel.get(i).name === n) { followed = true; break }
    }
    var cmd = followed ? ["bash", scriptPath, "artist-unfollow", n] : (a ? ["bash", scriptPath, "artist-follow", n, a] : ["bash", scriptPath, "artist-follow", n])
    var op = followed ? "unfollow" : "follow"
    if (artistProc.running) { artistProc.pendingOp = op; artistProc.pendingName = n; artistProc.pendingArt = a; return }
    artistLoading = true
    artistProc.op = op
    artistProc.collected = ""
    artistProc.command = cmd
    artistProc.running = true
  }

  function playArtistSong(i) {
    if (i < 0 || i >= artistSongsModel.count) return
    var row = artistSongsModel.get(i)
    if (row.kind === "radio" || row.kind === "preview") {
      playDirect(row.url, row.title, row.artist, row.art, row.kind)
    } else {
      ytSearchAndPlay(row.artist + " " + row.title)
    }
  }

  function setTab(i) {
    tabIndex = i
    hoveredTab = -1
    errorMessage = ""
    notice = ""
    if (i === 0) { loadHome() }
    else if (i === 1) { listMode = "search" }
    else if (i === 2) { showQueue() }
    else if (i === 3) { listMode = "playlists"; refreshMeta() }
    else if (i === 4) { loadLibrary() }
    else if (i === 5) { loadDownloads() }
    else if (i === 6) { maybeLoadLyrics() }
    else if (i === 7) { loadSettings() }
  }

  function showQueue() {
    listMode = "queue"
    listTitle = "Up next"
  }

  // ---- generic TSV loading --------------------------------------------------
  // `kind` tells onExited what the rows mean; the backend prints identical TSV
  // for search / mix / playlist-import / pl-show / lib-list, so one parser fits.
  function loadTsv(args, kind, title) {
    // A search already in flight: stash the newest request (latest wins) and
    // run it when the current one lands - rapid typing never loses a query.
    if (searchProc.running) {
      searchProc.pendingArgs = args
      searchProc.pendingKind = kind
      searchProc.pendingTitle = title || ""
      searchProc.hasPending = true
      return
    }
    searchProc.kind = kind
    searchProc.listTitle = title || ""
    searchProc.collected = ""
    searching = true
    errorMessage = ""
    if (kind !== "mix-bg") tracks.clear()
    selectedIndex = 0
    searchProc.command = ["bash", scriptPath].concat(args)
    searchProc.running = true
  }

  function flushSearchPending() {
    if (!searchProc.hasPending || searchProc.running) return
    var args = searchProc.pendingArgs
    var kind = searchProc.pendingKind
    var title = searchProc.pendingTitle
    searchProc.hasPending = false
    loadTsv(args, kind, title)
  }

  function search() {
    var query = searchField.text.trim()
    if (!query) return
    listMode = "search"
    loadTsv(["search", query], "search", "")
  }

  function importPlaylist() {
    var url = playlistField.text.trim()
    if (!url) return
    loadTsv(["playlist", url, "50"], "playlist", "Playlist import")
  }

  function openPlaylist(name) {
    if (!name) return
    openPlaylistName = name
    loadTsv(["pl-show", name], "playlist", name)
  }

  function playPlaylist(name) {
    if (!name) return
    runCmd(["pl-play", name])
  }

  function createPlaylist() {
    var name = newPlaylistField.text.trim()
    if (!name) return
    runCmd(["pl-create", name])
    newPlaylistField.text = ""
    Qt.callLater(root.refreshMeta)
  }

  function loadLibrary() {
    listMode = "saved"
    loadTsv(["lib-list"], "saved", "Favourite")
  }

  function loadDownloads() {
    listMode = "downloads"
    loadTsv(["dl-list"], "downloads-raw", "Downloaded")
  }

  function refreshMeta() {
    if (metaProc.running) metaProc.refetch = true
    else {
      metaProc.refetch = false
      metaProc.collected = ""
      metaProc.command = ["bash", scriptPath, "pl-list"]
      metaProc.running = true
    }
    if (currentVideoId) checkCurrentFlags()
  }

  function checkCurrentFlags() {
    // Shell-string below: only a strict videoId may enter (no metachars).
    if (!isVideoId(currentVideoId)) return
    // Track skipped mid-check: re-run for the new id when this one lands.
    if (flagProc.running) { flagProc.retry = true; return }
    flagProc.collected = ""
    flagProc.command = ["bash", "-c",
      scriptPath + " lib-check " + currentVideoId + " >/dev/null 2>&1 && echo SAVED=1 || echo SAVED=0; " +
      scriptPath + " dl-check " + currentVideoId + " >/dev/null 2>&1 && echo DL=1 || echo DL=0"]
    flagProc.running = true
    var followName = String(currentArtist || "").trim()
    if (followName === "") { currentFollowed = false }
    else if (followCheckProc.running) { followCheckProc.pendingArtist = followName }
    else {
      followCheckProc.pendingArtist = ""
      followCheckProc.command = ["bash", scriptPath, "artist-check", followName]
      followCheckProc.running = true
    }
  }

  // ---- lyrics (lrclib, no login) ---------------------------------------------
  // Sync chain, strongest first:
  //   1. backend fetches the EXACT version via /api/get + duration (±2s), so
  //      the LRC matches the audio instead of some remaster;
  //   2. [offset:] tags embedded in the LRC are honored;
  //   3. a phase-locked local clock interpolates between mpv polls (100ms
  //      lyric ticker vs 450ms IPC poll), killing the poll-lag wobble;
  //   4. per-track offsets, live-nudged and remembered forever.
  function effectivePos() {
    var base = (tabIndex === 6 && smoothPos > 0) ? smoothPos : position
    return Math.max(0, base + trackLyricOffset)
  }

  function maybeLoadLyrics() {
    if (!isVideoId(currentVideoId)) return
    if (currentUrl !== "") {
      errorMessage = "Streams carry no synced lyrics"
      return
    }
    loadTrackOffset()
    if (lyricsLoadedFor === currentVideoId || lyricsProc.running) return
    lyricsLoadedFor = currentVideoId
    lyricsProc.reqId = currentVideoId
    lyrics.clear()
    currentLyricIndex = -1
    lyricLoading = true
    errorMessage = ""
    lyricsProc.collected = ""
    lyricsProc.command = ["bash", scriptPath, "lyrics", currentArtist, currentTitle, currentDuration]
    lyricsProc.running = true
  }

  function loadTrackOffset() {
    if (!isVideoId(currentVideoId) || offsetProc.running) return
    offsetProc.mode = "get"
    offsetProc.collected = ""
    offsetProc.command = ["bash", scriptPath, "offset-get", currentVideoId]
    offsetProc.running = true
  }

  function nudgeOffset(delta) {
    if (!isVideoId(currentVideoId)) return
    // Rapid -/+ taps coalesce into one follow-up nudge instead of dropping.
    if (offsetProc.running) { offsetProc.pendingDelta += delta; offsetProc.hasPending = true; return }
    offsetProc.mode = "nudge"
    offsetProc.collected = ""
    offsetProc.command = ["bash", scriptPath, "offset-nudge", currentVideoId, String(delta)]
    offsetProc.running = true
  }

  function resetOffset() {
    if (!isVideoId(currentVideoId)) return
    if (offsetProc.running) { offsetProc.pendingReset = true; return }
    offsetProc.mode = "reset"
    offsetProc.collected = ""
    offsetProc.command = ["bash", scriptPath, "offset-reset", currentVideoId]
    offsetProc.running = true
  }

  function formatOffset(v) {
    var n = Math.round((Number(v) || 0) * 100) / 100
    return (n > 0 ? "+" : "") + String(n) + "s"
  }

  function retryLyrics() {
    lyricsLoadedFor = ""
    maybeLoadLyrics()
  }

  function parseLrc(raw) {
    var timed = []
    var untimed = []
    var synced = false
    var fileOffset = 0 // [offset:±ms] tag honored globally
    var lines = String(raw || "").split("\n")
    var re = /\[(\d+):(\d{1,2})(?:[.:](\d{1,3}))?\](.*)/
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line || !line.trim()) continue
      var off = line.match(/^\[offset:\s*([+-]?\d+)\s*\]/i)
      if (off) { fileOffset = Math.max(-10, Math.min(10, (parseInt(off[1], 10) || 0) / 1000)); continue }
      var tag = line.match(/^\[(ar|ti|al|length|by|offset|au):/i)
      if (tag) continue
      var m = line.match(re)
      if (m) {
        var text = (m[4] || "").trim()
        if (!text) continue
        synced = true
        var t = parseInt(m[1], 10) * 60 + parseInt(m[2], 10)
        if (m[3]) {
          var frac = "0." + m[3]
          t += parseFloat(frac) || 0
        }
        timed.push({ time: t, text: text })
      } else {
        untimed.push(line.trim())
      }
    }
    timed.sort(function(a, b) { return a.time - b.time })
    lyricsSynced = synced && timed.length > 0
    if (lyricsSynced) {
      for (var k = 0; k < timed.length; k++)
        lyrics.append({ time: Math.max(0, timed[k].time + fileOffset), text: timed[k].text })
    } else {
      for (var u = 0; u < untimed.length; u++) lyrics.append({ time: -1, text: untimed[u] })
    }
  }

  function updateLyricIndex() {
    if (!lyricsSynced || lyrics.count === 0) return
    var pos = effectivePos()
    var at = -1
    for (var i = 0; i < lyrics.count; i++) {
      if (lyrics.get(i).time <= pos + 0.05) at = i
      else break
    }
    if (at !== currentLyricIndex) {
      currentLyricIndex = at
      if (at >= 0 && !lyricsView.moving && !lyricsView.flicking)
        lyricsView.positionViewAtIndex(at, ListView.Center)
    }
  }

  function seekToLyric(i) {
    if (!lyricsSynced || i < 0 || i >= lyrics.count) return
    var t = Math.max(0, lyrics.get(i).time - trackLyricOffset)
    if (!isFinite(t)) return
    quickProc.command = ["bash", scriptPath, "seek-to", t.toFixed(2)]
    quickProc.running = true
    smoothPos = t
    updateLyricIndex()
  }

  // Timeline scrub: ratio 0..1 of the known duration.
  function seekRatio(r) {
    if (!(r >= 0) || !isFinite(r) || playbackDuration <= 0) return
    r = Math.max(0, Math.min(1, r))
    var t = r * playbackDuration
    quickProc.command = ["bash", scriptPath, "seek-to", t.toFixed(1)]
    quickProc.running = true
    smoothPos = t
    position = t
    updateLyricIndex()
  }

  function parseTracks(raw, limit) {
    var out = []
    var lines = String(raw || "").trim().split("\n")
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i]) continue
      var fields = lines[i].split("\t")
      if (fields.length < 2) continue
      var videoId = fields[0]
      if (!isVideoId(videoId)) continue
      var duration = fields[3] || ""
      var rowUrl = (fields[6] || "").trim()
      if (rowUrl && !/^https?:/i.test(rowUrl)) rowUrl = ""
      out.push({
        videoId: videoId,
        title: sanitizeText(fields[1]) || "Untitled",
        artist: sanitizeText(fields[2]) || "YouTube",
        duration: duration,
        isLive: fields[5] === "is_live" || duration.toUpperCase() === "NA",
        thumbnail: thumbFor(videoId, fields[4], rowUrl),
        url: rowUrl
      })
      if (out.length >= limit) break
    }
    return out
  }

  function fillTracks(raw, limit) {
    var t = parseTracks(raw, limit)
    for (var i = 0; i < t.length; i++) tracks.append(t[i])
  }

  function queueJson() {
    var queue = []
    for (var i = 0; i < tracks.count; i++) {
      var row = tracks.get(i)
      queue.push({
        videoId: row.videoId,
        title: row.title,
        artist: row.artist,
        thumbnail: row.thumbnail,
        duration: row.duration,
        isLive: row.isLive,
        url: row.url || ""
      })
    }
    return JSON.stringify(queue)
  }

  function playAt(index) {
    if (index < 0 || index >= tracks.count) return
    var track = tracks.get(index)
    currentIndex = index
    currentTitle = track.title
    currentArtist = track.artist
    currentThumbnail = track.thumbnail
    currentDuration = track.duration
    currentVideoId = track.videoId
    currentIsLive = track.isLive === true
    currentUrl = track.url || ""
    position = 0
    playbackDuration = 0
    // Fresh clock: without this the 100ms lyric ticker keeps interpolating
    // from the PREVIOUS song's position until the next status poll lands,
    // flashing the lyrics to some mid/end line on every track start.
    smoothPos = 0
    lastStatusAt = Date.now()
    currentLyricIndex = -1
    playing = true
    playerRunning = true
    checkCurrentFlags()
    if (tabIndex === 6) maybeLoadLyrics()
    var command = ["bash", scriptPath, "queue", queueJson(), String(index)]
    if (actionProc.running) actionProc.pendingCommand = command
    else { actionProc.command = command; actionProc.running = true }
  }

  // Picking a SEARCH result turns into a mix (like YouTube Music's autoplay
  // station); picking inside queue / playlist / saved / offline only jumps,
  // because that list is already the queue the user chose.
  function selectTrack(index) {
    if (index < 0 || index >= tracks.count) return
    var fromSearch = listMode === "search"
    var videoId = tracks.get(index).videoId
    selectedIndex = index
    playAt(index)
    if (fromSearch && mixAuto) prefetchMix(videoId)
    if (tabIndex !== 1) setTab(2)
  }

  function startMix(videoId) {
    if (!isVideoId(videoId)) return
    for (var i = 0; i < tracks.count; i++) {
      if (tracks.get(i).videoId !== videoId) continue
      playAt(i)
      prefetchMix(videoId)
      return
    }
    if (currentVideoId === videoId) prefetchMix(videoId)
  }

  function prefetchMix(videoId) {
    if (!isVideoId(videoId)) return
    if (mixProc.running) { mixProc.pending = videoId; return }
    mixProc.pending = ""
    mixProc.seed = videoId
    mixPrefetching = true
    mixProc.command = ["bash", scriptPath, "mix", videoId]
    mixProc.running = true
  }

  function applyMix(raw, seed) {
    var mix = parseTracks(raw, 40)
    if (mix.length === 0) return
    var seedAt = -1
    for (var i = 0; i < mix.length; i++) {
      if (mix[i].videoId === seed) { seedAt = i; break }
    }
    if (seedAt < 0) {
      mix.unshift({
        videoId: seed,
        title: currentTitle,
        artist: currentArtist,
        duration: currentDuration,
        isLive: currentIsLive,
        thumbnail: currentThumbnail
      })
      seedAt = 0
    }
    tracks.clear()
    for (var j = 0; j < mix.length; j++) tracks.append(mix[j])
    listMode = "queue"
    listTitle = "Mix"
    if (tabIndex !== 2) tabIndex = 1
    currentIndex = seedAt
    selectedIndex = seedAt
    requeueProc.command = ["bash", scriptPath, "requeue", queueJson(), String(seedAt), seed]
    requeueProc.running = true
  }

  // ---- saves / playlists / downloads ----------------------------------------
  function runCmd(args) {
    var command = ["bash", scriptPath].concat(args)
    if (actionProc.running) { actionProc.pendingCommand = command; return }
    actionProc.command = command
    actionProc.running = true
  }

  function trackArgs(i) {
    var t = tracks.get(i)
    return [t.videoId, t.title, t.artist, t.thumbnail, t.duration, t.isLive ? "true" : "false", t.url || ""]
  }

  function saveTrack(i) {
    if (i < 0 || i >= tracks.count) return
    runCmd(["lib-save"].concat(trackArgs(i)))
    notice = "Saved ♥"
    noticeTimer.restart()
  }

  function unsaveTrack(i) {
    if (i < 0 || i >= tracks.count) return
    runCmd(["lib-unsave", tracks.get(i).videoId])
    if (listMode === "saved") Qt.callLater(root.loadLibrary)
    else checkCurrentFlags()
  }

  function saveCurrent() {
    if (!isVideoId(currentVideoId)) return
    runCmd(["lib-save", currentVideoId, currentTitle, currentArtist, currentThumbnail, currentDuration, currentIsLive ? "true" : "false"])
    currentSaved = true
    notice = "Saved ♥"
    noticeTimer.restart()
  }

  function downloadTrack(i) {
    if (i < 0 || i >= tracks.count) return
    if ((tracks.get(i).url || "") !== "") {
      notice = "Streams can't be downloaded"
      noticeTimer.restart()
      return
    }
    runCmd(["dl-get"].concat(trackArgs(i)))
    notice = "Downloading… (opus, ~/Music)"
    noticeTimer.restart()
  }

  function downloadCurrent() {
    if (!isVideoId(currentVideoId)) return
    if (currentUrl !== "") {
      notice = "Streams can't be downloaded"
      noticeTimer.restart()
      return
    }
    runCmd(["dl-get", currentVideoId, currentTitle, currentArtist, currentThumbnail, currentDuration, currentIsLive ? "true" : "false"])
    notice = "Downloading… (opus, ~/Music)"
    noticeTimer.restart()
  }

  function addTrackToPlaylist(i) {
    var target = addTargetPlaylist.trim()
    if (i < 0 || i >= tracks.count || !target) {
      errorMessage = "Pick a playlist name first"
      return
    }
    runCmd(["pl-add", target].concat(trackArgs(i)))
    notice = "Added to " + target
    noticeTimer.restart()
  }

  function removeDownload(i) {
    if (i < 0 || i >= tracks.count) return
    runCmd(["dl-remove", tracks.get(i).videoId])
    if (listMode === "downloads") Qt.callLater(root.loadDownloads)
  }

  // ---- settings ---------------------------------------------------------------
  function loadSettings() {
    if (settingsProc.running) { settingsProc.refetch = true; return }
    settingsProc.collected = ""
    settingsProc.command = ["bash", scriptPath, "settings"]
    settingsProc.running = true
  }

  function applySettings(raw) {
    try {
      var s = JSON.parse(String(raw || "{}"))
      setSilence = s.silence === "on"
      setNormalize = s.normalize === "on"
      setVolume = Math.max(0, Math.min(100, Number(s.volume) || 70))
      setLyricsOffset = Number(s.lyricsOffset) || 0
      setMixAuto = s.mixAuto !== "off"
      mixAuto = setMixAuto
      var lim = Number(s.searchLimit) || 12
      setSearchLimit = (lim === 8 || lim === 20) ? lim : 12
      setDlQuality = s.dlQuality === "compact" ? "compact" : "best"
      var sst = String(s.seekstyle || "default")
      seekStyle = (sst === "default" || sst === "wave" || sst === "lightning" || sst === "spiral" || sst === "dots" || sst === "mirror" || sst === "neon") ? sst : "default"
      vizOn = (s.viz === "off") ? false : true
      customFontName = String(s.customFont || "")
      eqPresetName = String(s.eqPreset || "flat")
      var uch = String(s.update_channel || "beta")
      updateChannel = (uch === "stable") ? "stable" : "beta"
      var ulc = s.update_last_check
      if (typeof ulc === "string" && ulc === "off") { updateAuto = false }
      else { updateAuto = true; var ulcNum = Math.floor(Number(ulc) || 0); updateLastCheck = ulcNum > 0 ? ulcNum : 0 }
      if (s.eqGains && s.eqGains.length === 10) {
        var g = []
        for (var i = 0; i < 10; i++) {
          var n = Number(s.eqGains[i]) || 0
          g.push(Math.max(-12, Math.min(12, n)))
        }
        eqGainsArr = g
      }
    } catch (e) {
      console.warn("YTMusic Plus: invalid settings", e)
    }
  }

  function eqSetPreset(name) {
    eqPresetName = name
    saveSetting("eqPreset", name)
    notice = name === "flat" ? "EQ flat" : ("EQ: " + name)
    noticeTimer.restart()
  }

  function eqSetBand(i, v) {
    v = Math.max(-12, Math.min(12, Math.round(v * 2) / 2))
    var g = eqGainsArr.slice()
    g[i] = v
    eqGainsArr = g
    eqPresetName = "custom"
    saveSetting("eqGains", JSON.stringify(g))
    saveSetting("eqPreset", "custom")
    notice = "EQ custom · applies next track"
    noticeTimer.restart()
  }

  function installFont(url) {
    var rawPath = String(url || "").replace(/^file:\/\//, "")
    var path = rawPath
    try { path = decodeURIComponent(rawPath) } catch (e) { path = rawPath }
    if (!path) return
    if (fontProc.running) return
    fontProc.collected = ""
    fontProc.command = ["bash", scriptPath, "font-install", path]
    fontProc.running = true
  }

  function saveSetting(key, value) {
    settingsDirty = true
    runCmd(["set", key, String(value)])
  }

  function toggleSetting(key, current) {
    var next = current ? "off" : "on"
    if (key === "silence") setSilence = !current
    else if (key === "normalize") setNormalize = !current
    else if (key === "mixAuto") { setMixAuto = !current; mixAuto = setMixAuto }
    saveSetting(key, next)
    if (key === "silence" || key === "normalize") {
      notice = "Applies from next track"
      noticeTimer.restart()
    }
  }

  // ---- self-update: SHA-compared, no version-string guessing ------------------
  // update-check [stable|beta] prints one UPDATE_CHECK line (short SHAs +
  // manifest version + channel/target); update-apply [stable|beta] same.
  // Dedicated processes only (never actionProc: an apply can take minutes and
  // must never block playback/queue commands).
  function checkUpdates(manual) {
    if (updateCheckProc.running || updateApplyProc.running) return
    updateChecking = true
    if (manual) updateStatusText = "Checking..."
    updateCheckProc.collected = ""
    updateCheckProc.manual = !!manual
    updateCheckProc.command = ["bash", scriptPath, "update-check", updateChannel]
    updateCheckProc.running = true
  }

  function updateField(line, key) {
    var parts = String(line || "").split(" ")
    for (var i = 0; i < parts.length; i++) {
      var kv = parts[i].split("=")
      if (kv.length === 2 && kv[0] === key) return kv[1]
    }
    return ""
  }

  function shortUpdateSha(s) {
    var v = String(s || "")
    if (v === "" || v === "unknown") return v === "" ? "unknown" : v
    return v.slice(0, 7)
  }

  function recordUpdateCheck() {
    var now = Math.floor(Date.now() / 1000)
    updateLastCheck = now
    if (!updateAuto) return
    saveSetting("update_last_check", String(now))
  }

  function setUpdateAuto(on) {
    updateAuto = on
    if (on) {
      var now = Math.floor(Date.now() / 1000)
      updateLastCheck = now
      saveSetting("update_last_check", String(now))
    } else {
      saveSetting("update_last_check", "off")
    }
  }

  function setUpdateChannel(c) {
    var v = (c === "stable") ? "stable" : "beta"
    if (updateChannel === v) return
    updateChannel = v
    saveSetting("update_channel", v)
  }

  // Piggybacks the settings load (no new Timer): one background check per
  // popup open when the last check is older than 30min. Waits for settings so a
  // stored opt-out is honored before any auto-apply can fire.
  function maybeAutoUpdateCheck() {
    if (!opened || updateAutoChecked) return
    updateAutoChecked = true
    var now = Math.floor(Date.now() / 1000)
    if ((now - (updateLastCheck || 0)) > 1800) checkUpdates(false)
  }

  // Periodic piggyback for long-open popups (called from the status-refresh
  // path): at most one background check per 30min of open time. Requires
  // updateAutoChecked so the initial settings load (and opt-out) wins first.
  function maybePeriodicUpdateCheck() {
    if (!opened || !updateAutoChecked) return
    if (updateCheckProc.running || updateApplyProc.running) return
    var now = Math.floor(Date.now() / 1000)
    if ((now - (updateLastCheck || 0)) > 1800) checkUpdates(false)
  }

  function parseUpdateCheck(raw, code, errText) {
    updateChecking = false
    var errReason = String(errText || "").trim().split("\n")[0]
    var lines = String(raw || "").split("\n")
    var found = ""
    var noGit = false
    for (var i = 0; i < lines.length; i++) {
      var ln = lines[i].trim()
      if (ln.indexOf("UPDATE_CHECK ") === 0) found = ln
      else if (ln.indexOf("git_checkout:false") === 0) noGit = true
    }
    if (found === "") {
      updateAvailable = false
      if (noGit) updateStatusText = "Not a git checkout - update via omarchy plugin update"
      else updateStatusText = "Check failed"
      root.updateVerifyPending = false
      root.updateManualApply = false
      return
    }
    var avail = updateField(found, "available")
    var lv = updateField(found, "local_version")
    var ls = shortUpdateSha(updateField(found, "local_sha"))
    var rs = shortUpdateSha(updateField(found, "remote_sha"))
    var ch = updateField(found, "channel")
    var tg = updateField(found, "target")
    if (ch === "stable" || ch === "beta") updateChannel = ch
    updateTarget = (tg !== "") ? tg : "-"
    updateLocalVersion = lv
    updateLocalSha = ls
    updateRemoteSha = rs
    if (avail !== "yes" && avail !== "no" && avail !== "unknown") {
      updateAvailable = false
      updateStatusText = "Check failed"
      root.updateVerifyPending = false
      root.updateManualApply = false
      return
    }
    if ((avail === "yes" || avail === "no") && (ls === "" || ls === "unknown" || rs === "" || rs === "unknown" || lv === "")) {
      updateAvailable = false
      updateStatusText = "Check failed"
      root.updateVerifyPending = false
      root.updateManualApply = false
      return
    }
    if (avail === "yes") {
      updateAvailable = true
      updateStatusText = "Update available (" + ls + " -> " + rs + ")"
      recordUpdateCheck()
      if (root.updateVerifyPending || root.updateManualApply) {
        root.updateVerifyPending = false
        root.updateManualApply = false
        root.errorMessage = "Update still available - retry"
      } else if (!updateCheckProc.manual && updateAuto) applyUpdate()
    } else if (avail === "no") {
      updateAvailable = false
      updateStatusText = "Up to date (v" + lv + " - " + ls + ")"
      recordUpdateCheck()
      if (!root.uiMatchesDisk()) {
        if (root.updateManualApply) {
          root.notice = "Updated - copy the restart command below"
          noticeTimer.restart()
        } else {
          root.notice = "Updated - restart shell to reload v" + lv
        }
      } else if (root.updateManualApply) {
        root.notice = "Updated - UI reloaded"
        noticeTimer.restart()
      }
      root.updateVerifyPending = false
      root.updateManualApply = false
    } else {
      updateAvailable = false
      updateStatusText = "Check failed: " + (errReason || "network unreachable")
      root.updateVerifyPending = false
      root.updateManualApply = false
    }
  }

  function footerUpdateStatus() {
    if (updateChecking) return "Checking..."
    if (updateAvailable) return "Update available ->"
    var s = String(updateStatusText || "")
    if (s.indexOf("Up to date") === 0) return "Updated"
    if (s.indexOf("Check failed") === 0) return "Failed"
    if (s.indexOf("Not a git") === 0) return "No git"
    if (s.indexOf("Never checked") === 0) return "Check?"
    if (s === "Checking...") return "Checking..."
    return s.slice(0, 20)
  }

  function uiMatchesDisk() {
    var a = String((String(appVersion).match(/\d+(\.\d+)*/) || [""])[0] || "")
    var b = String((String(updateLocalVersion).match(/\d+(\.\d+)*/) || [""])[0] || "")
    if (a === "" || b === "") return false
    var ap = a.split(".")
    var bp = b.split(".")
    while (ap.length > 1 && Number(ap[ap.length - 1]) === 0) ap.pop()
    while (bp.length > 1 && Number(bp[bp.length - 1]) === 0) bp.pop()
    return ap.join(".") === bp.join(".")
  }

  function applyUpdate(manual) {
    root.updateManualApply = !!manual
    if (updateApplyProc.running) return
    updateApplyProc.collected = ""
    updateApplyProc.command = ["bash", scriptPath, "update-apply", updateChannel]
    updateApplyProc.running = true
    notice = "Updating..."
    noticeTimer.restart()
  }

  // ---- loop / shuffle / sleep ---------------------------------------------------
  function nudgeVolume(delta) {
    var v = Math.max(0, Math.min(100, Math.round((setVolume + delta) / 5) * 5))
    setVolume = v
    runCmd(["volume", String(v)])
    saveSetting("volume", v)
  }

  function cycleLoop() {
    loopMode = loopMode === "off" ? "all" : (loopMode === "all" ? "one" : "off")
    runCmd(["loop", loopMode])
  }

  function shuffleQueue() {
    if (actionProc.running) return
    actionProc.after = "reload-queue"
    actionProc.command = ["bash", scriptPath, "shuffle"]
    actionProc.running = true
    notice = "Shuffled upcoming"
    noticeTimer.restart()
  }

  function loadQueueView() {
    listMode = "queue"
    if (!listTitle) listTitle = "Up next"
    loadTsv(["queue-show"], "queue", listTitle)
  }

  function setSleep(arg) {
    runCmd(["sleep", String(arg)])
    notice = arg === "off" ? "Sleep timer off" : ("Sleep: " + sleepLabel(arg))
    noticeTimer.restart()
  }

  function sleepLabel(arg) {
    if (arg === "song" || sleepMode === "song") return "end of song"
    var until = sleepUntil
    if (arg !== undefined && arg !== "off" && String(Number(arg)) === String(arg)) {
      var mins = Number(arg)
      return mins >= 60 ? (Math.floor(mins / 60) + "h" + (mins % 60 ? " " + (mins % 60) + "m" : "")) : (mins + "m")
    }
    if (sleepMode === "timer" && until > 0) {
      var left = Math.max(0, Math.round(until - Date.now() / 1000))
      var m = Math.floor(left / 60)
      var s = left % 60
      return m + ":" + String(s).padStart(2, "0") + " left"
    }
    return "off"
  }

  // ---- transport --------------------------------------------------------------
  function runAction(action) {
    if (actionProc.running) return
    actionProc.command = ["bash", scriptPath, action]
    actionProc.running = true
  }

  function next() { runAction("next") }
  function previous() { runAction("previous") }

  function togglePlayback() {
    if (!playerRunning && tracks.count > 0) {
      playAt(Math.max(0, selectedIndex))
      return
    }
    runAction("toggle")
    playing = !playing
  }

  function refreshStatus() {
    if (statusProc.running) return
    statusProc.command = ["bash", scriptPath, "status"]
    statusProc.running = true
  }

  function applyStatus(raw) {
    try {
      var status = JSON.parse(String(raw || "{}"))
      playerRunning = status.running === true
      playing = playerRunning && status.paused !== true
      var pos = Number(status.position)
      position = (isFinite(pos) && pos > 0) ? pos : 0
      var dur = Number(status.playbackDuration)
      playbackDuration = (isFinite(dur) && dur > 0) ? dur : 0
      smoothPos = position
      lastStatusAt = Date.now()
      if (status.loop === "all" || status.loop === "one") loopMode = status.loop
      else loopMode = "off"
      silenceOn = status.silence === true
      normalizeOn = status.normalize === true
      sleepUntil = Number(status.sleepUntil) || 0
      sleepMode = String(status.sleepMode || "")
      if (tabIndex === 6) updateLyricIndex()
      if (status.title) currentTitle = sanitizeText(status.title)
      if (status.artist) currentArtist = sanitizeText(status.artist)
      if (status.thumbnail && isSafeImageUrl(status.thumbnail)) currentThumbnail = String(status.thumbnail)
      if (status.duration) currentDuration = sanitizeText(status.duration)
      var incomingId = String(status.videoId || "")
      if (isVideoId(incomingId)) {
        if (currentVideoId !== incomingId) {
          currentVideoId = incomingId
          // Backend-side track change (auto-advance): same fresh-clock reset
          // as playAt, otherwise the ticker runs away on stale time.
          smoothPos = 0
          lastStatusAt = Date.now()
          currentLyricIndex = -1
          checkCurrentFlags()
          if (tabIndex === 6) maybeLoadLyrics()
        }
      }
      if (status.isLive !== undefined) currentIsLive = status.isLive === true
      if (status.index !== undefined) {
        var sIdx = Number(status.index)
        if (isFinite(sIdx)) currentIndex = Math.max(-1, Math.floor(sIdx))
      }
      if (status.queue && status.queue.length > 0 && tracks.count === 0 && !searching && listMode === "queue") {
        for (var i = 0; i < status.queue.length; i++) {
          var row = status.queue[i]
          var videoId = String(row.videoId || "")
          if (!root.isVideoId(videoId)) continue
          var duration = String(row.duration || "")
          var qUrl = String(row.url || "")
          if (qUrl && !/^https?:/i.test(qUrl.trim())) qUrl = ""
          tracks.append({
            videoId: videoId,
            title: sanitizeText(row.title) || "Untitled",
            artist: sanitizeText(row.artist) || "YouTube",
            duration: duration,
            isLive: row.isLive === true || duration.toUpperCase() === "NA",
            thumbnail: thumbFor(videoId, row.thumbnail, qUrl),
            url: qUrl
          })
        }
      }
    } catch (error) {
      console.warn("YTMusic Plus: invalid player status", error)
    }
    maybePeriodicUpdateCheck()
  }

  ListModel { id: tracks }
  ListModel { id: playlists }
  ListModel { id: lyrics }
  ListModel { id: homeModel }
  ListModel { id: artistModel }
  ListModel { id: artistSongsModel }
  ListModel { id: artistFindModel }
  property string artistProfile: ""
  property bool artistLoading: false
  // Artist find-as-you-type state (argv-only artist-find, silent on
  // miss/offline). artistFindQuery holds the latest query so a
  // late reply can never overwrite newer results.
  property bool artistFinding: false
  property string artistFindQuery: ""
  // Artist detail sidecar (best-effort portrait/bio/subs/genre, silent when
  // the backend has no artist-profile yet). artistBioOpen toggles the bio.
  property string artistBio: ""
  property string artistSubs: ""
  property string artistGenre: ""
  property string artistPortrait: ""
  property bool artistBioOpen: false

  Process {
    id: searchProc
    property string collected: ""
    property string kind: "search"
    property string listTitle: ""
    property var pendingArgs: []
    property string pendingKind: ""
    property string pendingTitle: ""
    property bool hasPending: false
    stdout: SplitParser { onRead: function(line) { searchProc.collected += line + "\n" } }
    stderr: StdioCollector { id: searchError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      searching = false
      if (kind === "downloads-raw") {
        // dl-list prints the same track TSV as lib-list (with stored metadata).
        listMode = "downloads"
        listTitle = "Downloaded"
        if (code === 0) root.fillTracks(collected, 200)
        if (tracks.count === 0) {
          var dlErr = searchError.text.trim().split("\n")[0]
          errorMessage = (code !== 0 && dlErr) ? dlErr : "No downloads yet - press the download icon on any track"
        }
        root.flushSearchPending()
        return
      }
      if (code !== 0) {
        errorMessage = searchError.text.trim() || "Request failed (offline? throttled?)"
        root.flushSearchPending()
        return
      }
      if (kind === "queue") {
        // Queue reload (post-shuffle): refill the real backend order instead
        // of leaving the wiped list behind.
        listMode = "queue"
        listTitle = searchProc.listTitle || "Up next"
        root.fillTracks(collected, 200)
        if (tracks.count === 0) errorMessage = "Queue is empty - play something from Find"
        else root.selectedIndex = (root.currentIndex >= 0 && root.currentIndex < tracks.count) ? root.currentIndex : 0
        root.flushSearchPending()
        return
      }
      if (kind === "saved" || kind === "playlist" || kind === "search" || kind === "search-home") {
        if (kind === "search" || kind === "search-home") { listMode = "search"; listTitle = "" }
        else if (kind === "saved") { listMode = "saved"; listTitle = "Favourite" }
        else { listMode = "queue"; root.listTitle = searchProc.listTitle }
        root.fillTracks(collected, 60)
        if (tracks.count === 0) errorMessage = kind === "saved" ? "Nothing loved yet — press ♥ on any track" : "No tracks found"
        else if (kind === "search-home") {
          // Chart pick: play the top YouTube match as its mix station.
          root.selectedIndex = 0
          root.playAt(0)
          if (root.mixAuto) root.prefetchMix(tracks.get(0).videoId)
          if (root.tabIndex !== 2) root.setTab(2)
        }
      }
      root.flushSearchPending()
    }
  }

  Process {
    id: actionProc
    property var pendingCommand: null
    property string after: ""
    stdout: StdioCollector { id: actionOut; waitForEnd: true }
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      if (code !== 0 && actionErr.text.trim()) {
        errorMessage = actionErr.text.trim().split("\n")[0]
      }
      if (pendingCommand) {
        command = pendingCommand
        pendingCommand = null
        running = true
      } else {
        var next = after
        after = ""
        refreshStatus()
        refreshMeta()
        if (next === "reload-queue" && root.tabIndex === 2) root.loadQueueView()
        if (root.settingsDirty) {
          root.settingsDirty = false
          root.loadSettings()
        }
      }
    }
  }

  // Fire-and-forget for lock-free instant commands (lyric tap-to-seek).
  Process {
    id: quickProc
  }

  Process {
    id: offsetProc
    property string collected: ""
    property string mode: "get"
    property real pendingDelta: 0
    property bool hasPending: false
    property bool pendingReset: false
    stdout: SplitParser { onRead: function(line) { offsetProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      if (code === 0) {
        var v = parseFloat(String(collected || "").trim())
        if (isFinite(v)) root.trackLyricOffset = Math.max(-10, Math.min(10, v))
        root.updateLyricIndex()
      }
      // Reset wins over coalesced nudges; the reset's own exit flushes them.
      if (offsetProc.pendingReset) { offsetProc.pendingReset = false; root.resetOffset(); return }
      if (offsetProc.hasPending) {
        var d = offsetProc.pendingDelta
        offsetProc.pendingDelta = 0
        offsetProc.hasPending = false
        root.nudgeOffset(d)
      }
    }
  }

  Process {
    id: settingsProc
    property string collected: ""
    property bool refetch: false
    stdout: SplitParser { onRead: function(line) { settingsProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      if (code === 0) { root.applySettings(collected); root.maybeAutoUpdateCheck() }
      if (settingsProc.refetch) { settingsProc.refetch = false; root.loadSettings() }
    }
  }

  // Self-update check: read-only SHA compare, never touches playback/queue.
  Process {
    id: updateCheckProc
    property string collected: ""
    property bool manual: false
    stdout: SplitParser { onRead: function(line) { updateCheckProc.collected += line + "\n" } }
    stderr: StdioCollector { id: updateCheckError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      root.parseUpdateCheck(collected, code, updateCheckError.text)
    }
  }

  // Self-update apply: plugin manager update + rescan, result via notice.
  Process {
    id: updateApplyProc
    property string collected: ""
    stdout: SplitParser { onRead: function(line) { updateApplyProc.collected += line + "\n" } }
    stderr: StdioCollector { id: updateApplyError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      if (code === 0) {
        var sha = ""
        var outLines = String(collected || "").split("\n")
        for (var i = 0; i < outLines.length; i++) {
          var parts = outLines[i].trim().split(" ")
          if (parts.length >= 2 && parts[0] === "UPDATE_APPLIED") sha = parts[1]
        }
        root.updateAvailable = false
        if (sha) {
          root.updateLocalSha = sha
          root.updateStatusText = "Up to date (v" + root.updateLocalVersion + " - " + sha + ")"
        }
        root.updateVerifyPending = true
        root.notice = root.updateManualApply ? ("Updated to " + (sha || "latest") + " - verifying reload...") : ("Updated to " + (sha || "latest"))
        noticeTimer.restart()
        if (root.updateManualApply) verifyTimer.restart()
      } else {
        var reason = String(updateApplyError.text || "").trim().split("\n")[0] || ("exit " + code)
        root.errorMessage = reason
        root.updateStatusText = reason.length > 60 ? reason.slice(0, 57) + "..." : reason
      }
    }
  }

  Timer {
    id: verifyTimer
    interval: 5000
    repeat: false
    onTriggered: {
      if (!root.updateVerifyPending) return
      root.updateVerifyPending = false
      root.checkUpdates(false)
    }
  }

  Process {
    id: copyProc
    onExited: function(code) {
      if (code === 0) {
        root.notice = "Copied - paste in a terminal"
        noticeTimer.restart()
      } else {
        restartCmdInput.selectAll()
        root.notice = "Copy failed - select the text + Ctrl+C"
      }
    }
  }

  // Font installer: stdout carries the detected family name.
  Process {
    id: fontProc
    property string collected: ""
    stdout: SplitParser { onRead: function(line) { fontProc.collected += line + "\n" } }
    stderr: StdioCollector { id: fontError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      if (code !== 0) {
        errorMessage = fontError.text.trim().split("\n")[0] || "Font install failed"
        return
      }
      var family = String(collected || "").trim().split("\n").filter(function(l) { return l.trim() })[0] || ""
      if (family) {
        root.customFontName = family
        root.notice = "Font: " + family
        noticeTimer.restart()
      }
      root.loadSettings()
    }
  }

  FileDialog {
    id: fontDialog
    title: "Choose a font file"
    fileMode: FileDialog.OpenFile
    nameFilters: ["Font files (*.ttf *.otf *.woff *.woff2 *.ttc)", "All files (*)"]
    onAccepted: root.installFont(selectedFile)
  }

  Process {
    id: mixProc
    property string collected: ""
    property string seed: ""
    property string pending: ""
    stdout: SplitParser { onRead: function(line) { mixProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      root.mixPrefetching = false
      var pendingSeed = pending
      pending = ""
      if (pendingSeed && pendingSeed !== seed) { root.prefetchMix(pendingSeed); return }
      if (code !== 0 || root.currentVideoId !== seed) return
      root.applyMix(collected, seed)
    }
  }

  Process {
    id: requeueProc
    onExited: refreshStatus()
  }

  Process {
    id: homeProc
    property string collected: ""
    property bool refetch: false
    stdout: SplitParser { onRead: function(line) { homeProc.collected += line + "\n" } }
    stderr: StdioCollector { id: homeError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      homeLoading = false
      if (code !== 0) {
        errorMessage = homeError.text.trim().split("\n")[0] || "Discovery failed"
      } else {
        root.fillHome(collected)
      }
      if (homeProc.refetch) { homeProc.refetch = false; root.reloadHome() }
    }
  }

  Process {
    id: artistProc
    property string collected: ""
    property bool refetch: false
    property string op: "list"
    property string pendingName: ""
    property string pendingArt: ""
    property string pendingOp: ""
    stdout: SplitParser { onRead: function(line) { artistProc.collected += line + "\n" } }
    stderr: StdioCollector { id: artistError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      var curOp = op
      if (curOp === "follow" || curOp === "unfollow") {
        op = "list"
        if (code !== 0) {
          artistLoading = false
          errorMessage = artistError.text.trim().split("\n")[0] || "Follow failed"
        } else {
          notice = curOp === "follow" ? "Followed" : "Unfollowed"
          noticeTimer.restart()
        }
        if (pendingOp === "follow" || pendingOp === "unfollow") {
          var pOp = pendingOp
          var pName = pendingName
          var pArt = pendingArt
          pendingOp = ""
          pendingName = ""
          pendingArt = ""
          var pCmd = pOp === "unfollow" ? ["bash", scriptPath, "artist-unfollow", pName] : (pArt ? ["bash", scriptPath, "artist-follow", pName, pArt] : ["bash", scriptPath, "artist-follow", pName])
          op = pOp
          collected = ""
          command = pCmd
          running = true
          return
        }
        if (refetch) { refetch = false }
        root.reloadArtists()
        return
      }
      artistLoading = false
      if (code !== 0) {
        errorMessage = artistError.text.trim().split("\n")[0] || "Artists unavailable"
      } else {
        try {
          var arr = JSON.parse(String(collected || "[]"))
          artistModel.clear()
          for (var i = 0; i < arr.length; i++) {
            var r = arr[i] || {}
            var nm = sanitizeText(r.name) || ""
            nm = String(nm).trim()
            if (!nm) continue
            var at = isSafeImageUrl(r.art) ? String(r.art) : ""
            if (at && !/^https:/i.test(at.trim())) at = ""
            artistModel.append({ name: nm, art: at })
          }
        } catch (e) {
          errorMessage = "Artists unavailable (offline?)"
        }
      }
      if (pendingOp === "follow" || pendingOp === "unfollow") {
        var qOp = pendingOp
        var qName = pendingName
        var qArt = pendingArt
        pendingOp = ""
        pendingName = ""
        pendingArt = ""
        artistLoading = true
        var qCmd = qOp === "unfollow" ? ["bash", scriptPath, "artist-unfollow", qName] : (qArt ? ["bash", scriptPath, "artist-follow", qName, qArt] : ["bash", scriptPath, "artist-follow", qName])
        op = qOp
        collected = ""
        command = qCmd
        running = true
        return
      }
      if (refetch) { refetch = false; root.reloadArtists() }
    }
  }

  Process {
    id: artistSongsProc
    property string collected: ""
    property bool refetch: false
    property string pendingName: ""
    stdout: SplitParser { onRead: function(line) { artistSongsProc.collected += line + "\n" } }
    stderr: StdioCollector { id: artistSongsError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      artistLoading = false
      if (code !== 0) {
        errorMessage = artistSongsError.text.trim().split("\n")[0] || "Artist songs failed"
      } else {
        try {
          var arr = JSON.parse(String(collected || "[]"))
          artistSongsModel.clear()
          for (var i = 0; i < arr.length; i++) {
            var r = arr[i] || {}
            var u = String(r.url || "")
            if (u && !/^https?:/i.test(u.trim())) u = ""
            var k = String(r.kind || "preview")
            if (k !== "radio" && k !== "preview" && k !== "chart") k = "preview"
            artistSongsModel.append({
              title: sanitizeText(r.title) || "Untitled",
              artist: sanitizeText(r.artist),
              art: isSafeImageUrl(r.art) ? String(r.art) : "",
              url: u,
              kind: k
            })
          }
          if (artistSongsModel.count === 0) errorMessage = "No songs for this artist"
        } catch (e) {
          errorMessage = "Artist songs failed (offline?)"
        }
      }
      if (refetch) {
        refetch = false
        var nxt = pendingName ? String(pendingName) : String(root.artistProfile)
        pendingName = ""
        if (nxt) root.loadArtistProfile(nxt)
      }
    }
  }

  // Artist find-as-you-type: argv-only, empty-graceful (miss/offline clears
  // silently, never an error flash while typing). Stale replies (query
  // mismatch with artistFindQuery) are dropped; a queued keystroke refetches
  // with the latest query on exit. Trusts the backend artist-find payload.
  Process {
    id: artistFindProc
    property string collected: ""
    property string query: ""
    property string pendingQuery: ""
    property bool refetch: false
    stdout: SplitParser { onRead: function(line) { artistFindProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      var mine = String(query || "")
      var latest = String(root.artistFindQuery || "")
      if (mine !== latest) {
        if (refetch) {
          refetch = false
          var pq0 = String(pendingQuery || latest)
          pendingQuery = ""
          if (pq0) root.findArtists(pq0)
          else artistFinding = false
        } else {
          artistFinding = false
        }
        return
      }
      artistFinding = false
      if (code === 0) {
        try {
          var arr = JSON.parse(String(collected || "[]"))
          artistFindModel.clear()
          for (var i = 0; i < arr.length; i++) {
            var r = arr[i] || {}
            var nm = String(sanitizeText(r.name) || "").trim()
            if (!nm) continue
            var at = String(r.art || "")
            if (!isSafeImageUrl(at) || !/^https:/i.test(at.trim())) at = ""
            var gn = String(sanitizeText(r.genre || "")).trim()
            artistFindModel.append({ name: nm, art: at, genre: gn })
          }
        } catch (e) {
          artistFindModel.clear()
        }
      } else {
        artistFindModel.clear()
      }
      if (refetch) {
        refetch = false
        var pq = String(pendingQuery || "")
        pendingQuery = ""
        if (pq) root.findArtists(pq)
      }
    }
  }

  // Artist portrait/bio/subs sidecar to artist-songs: best-effort, argv-only,
  // silent on failure (missing backend command, offline, bad payload). Same
  // pendingName/refetch shape as artistSongsProc, but a late reply refetches
  // only itself so it can never restart the songs list. Stale replies (name
  // mismatch with the open profile) are dropped without touching the UI.
  Process {
    id: artistProfileProc
    property string collected: ""
    property bool refetch: false
    property string pendingName: ""
    stdout: SplitParser { onRead: function(line) { artistProfileProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      if (code === 0) {
        try {
          var obj = JSON.parse(String(collected || "{}")) || {}
          var who = root.sanitizeText(obj.name || "")
          if (!who || who === root.artistProfile) {
            var b = root.sanitizeText(obj.bio || "")
            var s = root.sanitizeText(obj.subsText || obj.subs || obj.followers || "")
            var g = root.sanitizeText(obj.genre || "")
            var p = String(obj.portrait || obj.art || "")
            if (!root.isSafeImageUrl(p) || !/^https:/i.test(p.trim())) p = ""
            root.artistBio = b
            root.artistSubs = s
            root.artistGenre = g
            root.artistPortrait = p
          }
        } catch (e) {}
      }
      if (refetch) {
        refetch = false
        var nxtSelf = pendingName ? String(pendingName) : ""
        pendingName = ""
        if (nxtSelf && nxtSelf === root.artistProfile) {
          collected = ""
          command = ["bash", scriptPath, "artist-profile", nxtSelf]
          running = true
        }
      }
    }
  }

  Process {
    id: lyricsProc
    property string collected: ""
    property string reqId: ""
    stdout: SplitParser { onRead: function(line) { lyricsProc.collected += line + "\n" } }
    stderr: StdioCollector { id: lyricsError; waitForEnd: true }
    onStarted: collected = ""
    onExited: function(code) {
      lyricLoading = false
      // Track changed mid-fetch: drop these lines, fetch the new song.
      if (lyricsProc.reqId !== root.currentVideoId) {
        root.lyricsLoadedFor = ""
        if (root.tabIndex === 6) root.maybeLoadLyrics()
        return
      }
      if (code !== 0) {
        errorMessage = lyricsError.text.trim().split("\n")[0] || "Lyrics unavailable"
        return
      }
      root.parseLrc(collected)
      if (lyrics.count === 0) errorMessage = "No lyrics for this track"
      else root.updateLyricIndex()
    }
  }

  Process {
    id: metaProc
    property string collected: ""
    property bool refetch: false
    stdout: SplitParser { onRead: function(line) { metaProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      if (metaProc.refetch) {
        metaProc.refetch = false
        metaProc.collected = ""
        metaProc.command = ["bash", scriptPath, "pl-list"]
        metaProc.running = true
        return
      }
      if (code !== 0) return
      playlists.clear()
      var lines = String(collected || "").trim().split("\n")
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i]) continue
        var parts = lines[i].split("\t")
        var plName = sanitizeText(parts[0])
        if (!plName) continue
        playlists.append({ name: plName, info: sanitizeText(parts[1] || "") })
      }
    }
  }

  Process {
    id: flagProc
    property string collected: ""
    property bool retry: false
    stdout: SplitParser { onRead: function(line) { flagProc.collected += line + "\n" } }
    onStarted: collected = ""
    onExited: function(code) {
      var t = String(collected || "")
      root.currentSaved = t.indexOf("SAVED=1") >= 0
      root.currentDownloaded = t.indexOf("DL=1") >= 0
      if (flagProc.retry) { flagProc.retry = false; root.checkCurrentFlags() }
    }
  }

  Process {
    id: followCheckProc
    property string pendingArtist: ""
    onExited: function(code) {
      if (followCheckProc.pendingArtist !== "") {
        var nxt = String(followCheckProc.pendingArtist)
        followCheckProc.pendingArtist = ""
        followCheckProc.command = ["bash", scriptPath, "artist-check", nxt]
        followCheckProc.running = true
        return
      }
      root.currentFollowed = (code === 0)
    }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyStatus(text)
    }
  }

  Timer {
    interval: root.tabIndex === 6 ? 450 : 1500
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refreshStatus()
  }

  // Phase-locked lyric clock: interpolates mpv's position between IPC polls
  // so lines flip on the beat instead of on the 450ms poll wobble. Clamped to
  // the track duration so a stale poll can never run past the last line.
  Timer {
    id: lyricTicker
    interval: 100
    running: root.opened && root.tabIndex === 6 && root.playing && root.lyricsSynced
    repeat: true
    onTriggered: {
      var guess = root.position + (Date.now() - root.lastStatusAt) / 1000
      if (root.playbackDuration > 0) guess = Math.min(guess, root.playbackDuration)
      root.smoothPos = Math.max(0, guess)
      root.updateLyricIndex()
    }
  }

  // Ticks the sleep countdown label while the settings tab watches it.
  Timer {
    id: sleepTicker
    interval: 1000
    running: root.opened && root.tabIndex === 7 && root.sleepMode === "timer"
    repeat: true
    onTriggered: root.refreshStatus()
  }

  Timer {
    id: searchDebounce
    interval: 550
    repeat: false
    onTriggered: root.search()
  }

  Timer {
    id: noticeTimer
    interval: 2600
    repeat: false
    onTriggered: root.notice = ""
  }

  Rectangle {
    id: card
    anchors.fill: parent
    color: root.surface
    radius: Style.cornerRadius
    border.width: 1
    border.color: root.border
    clip: true
    transformOrigin: Item.Center
    scale: root.opened ? 1 : 0.985
    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

    Image {
      anchors.fill: parent
      source: root.currentThumbnail
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      opacity: root.currentThumbnail ? 0.05 : 0
    }

    Item {
      anchors.fill: parent
      anchors.margins: Style.space(14)

      Column {
        anchors.fill: parent
        spacing: Style.space(7)

        // Title row
        Item {
          width: parent.width
          height: Style.space(22)
          Text {
            text: "YTMusic Plus"
            color: root.ink
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            font.bold: true
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }
          Text {
            text: root.lyricsSynced && root.tabIndex === 6 ? "♪ synced" : ""
            color: root.accent
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
          }
        }

        // Floating dock — variable-width cells, sliding highlight follows the
        // mouse and rests on the active tab. Omarchy tokens only, no glass.
        Item {
          id: dockRow
          width: parent.width
          height: Style.space(36)
          readonly property int litTab: root.hoveredTab >= 0 ? root.hoveredTab : root.tabIndex

          Item {
            height: Style.space(32)
            width: Math.min(dockRow.width, dockCellsRow.width + Style.space(10))
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
              anchors.fill: parent
              radius: height / 2
              color: root.barBackground
              border.width: 1
              border.color: root.border
            }

            Rectangle {
              id: dockHighlight
              visible: true
              x: Style.space(5) + ((dockCellsRepeater.count > dockRow.litTab && dockCellsRepeater.itemAt(dockRow.litTab)) ? dockCellsRepeater.itemAt(dockRow.litTab).x : 0)
              y: Style.space(4)
              width: (dockCellsRepeater.count > dockRow.litTab && dockCellsRepeater.itemAt(dockRow.litTab)) ? dockCellsRepeater.itemAt(dockRow.litTab).width : Style.space(44)
              height: parent.height - Style.space(8)
              radius: height / 2
              color: root.accent
              Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
              Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
            }

            Row {
              id: dockCellsRow
              x: Style.space(5)
              y: Style.space(4)
              height: parent.height - Style.space(8)
              Repeater {
                id: dockCellsRepeater
                model: [
                  { label: "Home", tip: "Discover: charts, radio, tunes" },
                  { label: "Find", tip: "Search YouTube — no login" },
                  { label: "Queue", tip: "Up next" },
                  { label: "Playlist", tip: "Imports + your lists" },
                  { label: "Favourite", tip: "Loved tracks" },
                  { label: "Local", tip: "Offline downloads" },
                  { label: "Lyrics", tip: "Synced lyrics" },
                  { label: "", icon: true, tip: "Settings" }
                ]
                Item {
                  width: cellLabel.width + Style.space(14)
                  height: dockCellsRow.height
                  Text {
                    id: cellLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    color: dockRow.litTab === index ? root.onAccent : root.muted
                    font.family: modelData.icon ? root.iconFont : root.uiFont
                    font.pixelSize: Math.max(8, Style.font.caption - 1)
                    font.bold: root.tabIndex === index
                    Behavior on color { ColorAnimation { duration: 120 } }
                  }
                  MouseArea {
                    id: dockHover
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: root.hoveredTab = index
                    // Guarded: with adjacent cells, a neighbor's exit can
                    // arrive AFTER our enter during fast mouse moves. Clearing
                    // unconditionally snaps the highlight back mid-hover.
                    onExited: if (root.hoveredTab === index) root.hoveredTab = -1
                    onClicked: root.setTab(index)
                  }
                  InfoTip { watched: dockHover; tipText: modelData.tip; delayMs: root.helpMode ? 3000 : 5000 }
                }
              }
            }
          }
          // Help mode toggle: ASCII "?" via uiFont, beside settings gear.
          Item {
            id: helpBtn
            width: Style.space(24)
            height: Style.space(24)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            Text {
              anchors.centerIn: parent
              text: "?"
              color: root.helpMode ? root.accent : root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              font.bold: true
            }
            MouseArea {
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                root.helpMode = !root.helpMode
                if (root.helpMode) {
                  root.notice = "Help on \u2014 hover any button 3s"
                  noticeTimer.restart()
                }
              }
            }
          }
        }

        // Context input row per tab
        Item {
          width: parent.width
          height: Style.space(32)
          visible: root.tabIndex === 1 || root.tabIndex === 3

          Rectangle {
            anchors.fill: parent
            visible: root.tabIndex === 1
            radius: height / 2
            color: root.raised
            border.width: searchField.activeFocus ? 1 : 0
            border.color: root.ink
            TextInput {
              id: searchField
              anchors.left: parent.left
              anchors.leftMargin: Style.space(13)
              anchors.right: parent.right
              anchors.rightMargin: Style.space(13)
              anchors.verticalCenter: parent.verticalCenter
              color: root.ink
              selectionColor: root.accent
              selectedTextColor: root.onAccent
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              clip: true
              onTextChanged: {
                var query = text.trim()
                if (!root.opened) return
                if (!query) {
                  searchDebounce.stop()
                } else if (query.length >= 2) {
                  searchDebounce.restart()
                }
              }
              Text {
                text: "Search music… (no login, no tracking)"
                color: root.muted
                font: searchField.font
                visible: !searchField.text
              }
              Keys.onPressed: function(event) {
                if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { searchDebounce.stop(); root.search(); event.accepted = true }
                else if (event.key === Qt.Key_Down && tracks.count > 0) { root.selectedIndex = 0; resultList.forceActiveFocus(); event.accepted = true }
              }
            }
          }

          Row {
            anchors.fill: parent
            visible: root.tabIndex === 3
            spacing: Style.space(6)
            Rectangle {
              width: parent.width - Style.space(66)
              height: parent.height
              radius: height / 2
              color: root.raised
              TextInput {
                id: playlistField
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(13)
                anchors.verticalCenter: parent.verticalCenter
                color: root.ink
                selectionColor: root.accent
                selectedTextColor: root.onAccent
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                clip: true
                Text {
                  text: "Paste YouTube playlist URL…"
                  color: root.muted
                  font: playlistField.font
                  visible: !playlistField.text
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.importPlaylist(); event.accepted = true }
                }
              }
            }
            Rectangle {
              width: Style.space(60)
              height: parent.height
              radius: height / 2
              color: root.accent
              opacity: importHover.pressed ? 0.8 : 1.0
              transformOrigin: Item.Center
              scale: importHover.pressed ? 0.95 : 1.0
              Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
              Behavior on opacity { NumberAnimation { duration: 120 } }
              Text { anchors.centerIn: parent; text: "Import"; color: root.onAccent; font.family: root.uiFont; font.pixelSize: Style.font.caption; font.bold: true }
              MouseArea { id: importHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.importPlaylist() }
            }
          }
        }

        // Now playing
        Item {
          width: parent.width
          height: root.currentTitle !== "" ? Style.space(56) : 0
          visible: root.currentTitle !== ""
          Row {
            anchors.fill: parent
            spacing: Style.space(8)
            Rectangle {
              width: Style.space(46)
              height: width
              radius: Style.space(7)
              color: root.raised
              clip: true
              anchors.verticalCenter: parent.verticalCenter
              Image { anchors.fill: parent; source: root.currentThumbnail; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
            }
            Column {
              width: parent.width - Style.space(46) - Style.space(132) - parent.spacing * 3
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(1)
              Marquee {
                width: parent.width
                height: Style.space(16)
                text: root.currentTitle
                textColor: root.ink
                textFont: root.uiFont
                pixelSize: Style.font.bodySmall
                bold: true
              }
              Text {
                width: parent.width
                text: (root.currentDownloaded ? "↓ " : "") + root.currentArtist + " · " + root.durationLabel(root.currentDuration, root.currentIsLive)
                textFormat: Text.PlainText
                color: root.currentDownloaded ? root.accent : root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
              }
            }
            // save toggle
            Text {
              text: "󰣐"
              color: root.currentSaved ? root.accent : root.muted
              font.family: root.iconFont
              font.pixelSize: Style.font.iconLarge
              anchors.verticalCenter: parent.verticalCenter
              transformOrigin: Item.Center
              scale: npSaveHover.pressed ? 0.85 : 1.0
              Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
              Behavior on color { ColorAnimation { duration: 120 } }
              MouseArea {
                id: npSaveHover
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (root.currentSaved) { root.runCmd(["lib-unsave", root.currentVideoId]); root.currentSaved = false }
                  else root.saveCurrent()
                }
              }
              InfoTip { watched: npSaveHover; tipText: root.currentSaved ? "Remove from Favourite" : "Save to Favourite"; delayMs: root.helpMode ? 3000 : 5000 }
            }
            // download
            Text {
              text: "󰇚"
              color: root.currentDownloaded ? root.accent : root.muted
              font.family: root.iconFont
              font.pixelSize: Style.font.iconLarge
              anchors.verticalCenter: parent.verticalCenter
              transformOrigin: Item.Center
              scale: npDlHover.pressed ? 0.85 : 1.0
              Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
              Behavior on color { ColorAnimation { duration: 120 } }
              MouseArea {
                id: npDlHover
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.downloadCurrent()
              }
              InfoTip { watched: npDlHover; tipText: "Download offline (opus)"; delayMs: root.helpMode ? 3000 : 5000 }
            }
            // follow toggle
            Rectangle {
              height: 24
              width: npFollowLabel.width + 20
              radius: 12
              color: root.currentFollowed ? root.accent : "transparent"
              border.width: 1
              border.color: root.currentFollowed ? root.accent : root.muted
              anchors.verticalCenter: parent.verticalCenter
              transformOrigin: Item.Center
              scale: npFollowHover.pressed ? 0.9 : 1.0
              Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
              Behavior on color { ColorAnimation { duration: 120 } }
              Text {
                id: npFollowLabel
                anchors.centerIn: parent
                text: root.currentFollowed ? "Following" : "+ Follow"
                textFormat: Text.PlainText
                color: root.currentFollowed ? root.onAccent : root.ink
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              MouseArea {
                id: npFollowHover
                anchors.fill: parent
                anchors.margins: -Style.space(6)
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  var nm = String(root.currentArtist || "").trim()
                  if (!nm) return
                  if (root.currentFollowed) {
                    root.runCmd(["artist-unfollow", nm])
                    root.currentFollowed = false
                    root.notice = "Unfollowed"
                    noticeTimer.restart()
                  } else {
                    var art = String(root.currentThumbnail || "").trim()
                    if (root.isSafeImageUrl(art) && /^https:/i.test(art)) root.runCmd(["artist-follow", nm, art])
                    else root.runCmd(["artist-follow", nm])
                    root.currentFollowed = true
                    root.notice = "Followed"
                    noticeTimer.restart()
                  }
                  if (root.homeMode === "artist") root.reloadArtists()
                }
              }
              InfoTip { watched: npFollowHover; tipText: root.currentFollowed ? "Following - tap to unfollow" : "Follow artist"; delayMs: root.helpMode ? 3000 : 5000 }
            }
            }
          }

        // Progress + transport
        Item {
          width: parent.width
          height: root.currentTitle !== "" ? Style.space(58) : 0
          visible: root.currentTitle !== ""
          Column {
            anchors.fill: parent
            spacing: Style.space(4)
            Row {
              id: timeRow
              width: parent.width
              height: Style.space(14)
              spacing: Style.space(7)
              Text {
                id: elapsedLabel
                width: Style.space(34)
                text: root.showRemaining && root.playbackDuration > 0 ? ("-" + root.formatTime(root.playbackDuration - root.position)) : root.formatTime(root.position)
                textFormat: Text.PlainText
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                anchors.verticalCenter: parent.verticalCenter
                MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showRemaining = !root.showRemaining }
              }
                Rectangle {
                  id: seekBar
                  width: Math.max(Style.space(40), parent.width - Style.space(34) * 2 - timeRow.spacing * 2)
                  height: 14
                  color: "transparent"
                  anchors.verticalCenter: parent.verticalCenter
                  Canvas {
                    id: waveCanvas
                    anchors.fill: parent
                    onWidthChanged: requestPaint()
                    Component.onCompleted: requestPaint()
                    onPaint: {
                      var ctx = getContext("2d")
                      var w = width
                      var h = height
                      ctx.clearRect(0, 0, w, h)
                      if (w <= 0 || h <= 0) return
                      var midY = h / 2
                      var amp = 4
                      var waveLen = 16
                      var phase = root.wavePhase
                      var css = function(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }
                      var playedCss = css(root.accent, 1)
                      var restCss = css(root.muted, 0.4)
                      var st = root.seekStyle
                      if (st !== "default" && st !== "wave" && st !== "lightning" && st !== "spiral" && st !== "dots" && st !== "mirror" && st !== "neon") st = "default"
                      var ratio = Math.min(1, root.position / Math.max(1, root.playbackDuration))
                      var splitX = Math.max(0, Math.min(w, ratio * w))
                      var dotR = (seekHover.containsMouse || seekHover.pressed) ? 5 : 4
                      var live = !(root.playbackDuration > 0)
                      var waveY = function(x) { var a = (x / waveLen) * 2 * Math.PI; return midY + 4 * Math.sin(a + phase) + 1.5 * Math.sin(2.2 * a + 1.3 + phase) }
                      var triY = function(x) {
                        var p = ((x / waveLen) + phase / (2 * Math.PI)) % 1
                        if (p < 0) p += 1
                        var t = p < 0.5 ? (p * 4 - 1) : (3 - p * 4)
                        return midY + amp * t
                      }
                      var strokeWave = function(x0, x1, style) {
                        if (x1 <= x0) return
                        ctx.strokeStyle = style
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        var x = x0
                        ctx.moveTo(x, waveY(x))
                        x += 2
                        while (x < x1) { ctx.lineTo(x, waveY(x)); x += 2 }
                        ctx.lineTo(x1, waveY(x1))
                        ctx.stroke()
                      }
                      var strokeTri = function(x0, x1, style) {
                        if (x1 <= x0) return
                        ctx.strokeStyle = style
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        var x = x0
                        ctx.moveTo(x, triY(x))
                        x += 2
                        while (x < x1) { ctx.lineTo(x, triY(x)); x += 2 }
                        ctx.lineTo(x1, triY(x1))
                        ctx.stroke()
                      }
                      if (st === "default") {
                        ctx.lineCap = "round"
                        ctx.strokeStyle = restCss
                        ctx.lineWidth = 4
                        ctx.beginPath()
                        ctx.moveTo(0, midY)
                        ctx.lineTo(w, midY)
                        ctx.stroke()
                        if (!live) {
                          if (splitX > 0) {
                            ctx.strokeStyle = playedCss
                            ctx.lineWidth = 4
                            ctx.beginPath()
                            ctx.moveTo(0, midY)
                            ctx.lineTo(splitX, midY)
                            ctx.stroke()
                          }
                          ctx.fillStyle = playedCss
                          ctx.beginPath()
                          ctx.arc(splitX, midY, dotR, 0, 2 * Math.PI)
                          ctx.fill()
                        }
                        return
                      }
                      if (st === "wave") {
                        if (live) { strokeWave(0, w, restCss); return }
                        strokeWave(0, splitX, playedCss)
                        strokeWave(splitX, w, restCss)
                        ctx.fillStyle = playedCss
                        ctx.beginPath()
                        ctx.arc(splitX, waveY(splitX), dotR, 0, 2 * Math.PI)
                        ctx.fill()
                        return
                      }
                      if (st === "lightning") {
                        if (live) { strokeTri(0, w, restCss); return }
                        strokeTri(0, splitX, playedCss)
                        strokeTri(splitX, w, restCss)
                        ctx.fillStyle = playedCss
                        ctx.beginPath()
                        ctx.arc(splitX, triY(splitX), dotR, 0, 2 * Math.PI)
                        ctx.fill()
                        return
                      }
                      if (st === "spiral") {
                        ctx.strokeStyle = restCss
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.beginPath()
                        ctx.moveTo(0, midY)
                        ctx.lineTo(w, midY)
                        ctx.stroke()
                        if (live) return
                        var turns = 2.5
                        var maxR = 6
                        var steps = 48
                        ctx.strokeStyle = playedCss
                        ctx.lineWidth = 2
                        ctx.beginPath()
                        for (var i = 0; i <= steps; i++) {
                          var th = (i / steps) * turns * 2 * Math.PI
                          var rr = maxR * (i / steps)
                          var sx = splitX + rr * Math.cos(th)
                          var sy = midY + rr * Math.sin(th) * 0.8
                          if (i === 0) ctx.moveTo(sx, sy)
                          else ctx.lineTo(sx, sy)
                        }
                        ctx.stroke()
                        ctx.fillStyle = playedCss
                        ctx.beginPath()
                        ctx.arc(splitX, midY, dotR, 0, 2 * Math.PI)
                        ctx.fill()
                        return
                      }
                      if (st === "dots") {
                        var N = 24
                        for (var d = 0; d < N; d++) {
                          var dx = (d + 0.5) / N * w
                          var played = (!live) && (dx <= splitX)
                          var dr = 1.5
                          if (played) {
                            var tt = splitX > 0 ? (dx / splitX) : 0
                            dr = 1.5 + 2.5 * tt
                            ctx.fillStyle = playedCss
                          } else {
                            ctx.fillStyle = restCss
                          }
                          ctx.beginPath()
                          ctx.arc(dx, midY, dr, 0, 2 * Math.PI)
                          ctx.fill()
                        }
                        return
                      }
                      if (st === "mirror") {
                        var MN = 56
                        var mHash = function(i) { var x = Math.sin(i * 12.9898) * 43758.5453; return x - Math.floor(x) }
                        var mbw = w < 100 ? 1 : 2
                        for (var mi = 0; mi < MN; mi++) {
                          var h01 = mHash(mi)
                          var bh = 2 + h01 * Math.max(2, (h - 4))
                          var mx = (mi + 0.5) / MN * w
                          var mPlayed = (!live) && (mx <= splitX)
                          ctx.fillStyle = mPlayed ? playedCss : restCss
                          ctx.fillRect(mx - mbw / 2, midY - bh / 2, mbw, bh)
                        }
                        return
                      }
                      if (st === "neon") {
                        if (live) { strokeWave(0, w, restCss); return }
                        var pulse = 8 + 4 * Math.sin(phase)
                        ctx.save()
                        ctx.shadowColor = playedCss
                        ctx.shadowBlur = pulse
                        strokeWave(0, splitX, playedCss)
                        ctx.restore()
                        strokeWave(splitX, w, restCss)
                        ctx.save()
                        ctx.shadowColor = playedCss
                        ctx.shadowBlur = 12
                        ctx.fillStyle = playedCss
                        ctx.beginPath()
                        ctx.arc(splitX, waveY(splitX), 4, 0, 2 * Math.PI)
                        ctx.fill()
                        ctx.restore()
                        return
                      }
                    }
                  }
                  Timer {
                    id: waveTimer
                    interval: 200
                    running: waveCanvas.visible && root.playing
                    repeat: true
                    onTriggered: waveCanvas.requestPaint()
                  }
                  Connections {
                    target: root
                    function onPositionChanged() { waveCanvas.requestPaint() }
                    function onPlayingChanged() { waveCanvas.requestPaint() }
                    function onPlaybackDurationChanged() { waveCanvas.requestPaint() }
                    function onSeekStyleChanged() { waveCanvas.requestPaint() }
                  }
                  Connections {
                    target: seekHover
                    function onContainsMouseChanged() { waveCanvas.requestPaint() }
                    function onPressedChanged() { waveCanvas.requestPaint() }
                  }
                  // Scrub like a video timeline: click or drag anywhere.
                MouseArea {
                  id: seekHover
                  anchors.fill: parent
                  anchors.topMargin: -Style.space(6)
                  anchors.bottomMargin: -Style.space(6)
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onPressed: function(mouse) { root.seekRatio(mouse.x / seekBar.width) }
                  onPositionChanged: function(mouse) {
                    if (pressed) root.seekRatio(mouse.x / seekBar.width)
                  }
                }
              }
              Text {
                width: Style.space(34)
                horizontalAlignment: Text.AlignRight
                text: root.playbackDuration > 0 ? root.formatTime(root.playbackDuration) : root.durationLabel(root.currentDuration, root.currentIsLive)
                textFormat: Text.PlainText
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                anchors.verticalCenter: parent.verticalCenter
                MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.showRemaining = !root.showRemaining }
              }
            }
            Item {
              width: parent.width
              height: Style.space(40)
              Row {
                anchors.centerIn: parent
                spacing: Style.space(12)
                TransportBtn {
                  glyph: "󰒨"
                  btnSize: Style.space(32)
                  small: true
                  tip: "Shuffle upcoming"
                  tapped: function() { root.shuffleQueue() }
                }
                TransportBtn {
                  glyph: "󰒮"
                  btnSize: Style.space(34)
                  tip: "Previous"
                  tapped: function() { root.previous() }
                }
                TransportBtn {
                  glyph: root.playing ? "󰏤" : "󰐊"
                  btnSize: Style.space(44)
                  primary: true
                  large: true
                  tip: root.playing ? "Pause" : "Play"
                  tapped: function() { root.togglePlayback() }
                }
                TransportBtn {
                  glyph: "󰒭"
                  btnSize: Style.space(34)
                  tip: "Next"
                  tapped: function() { root.next() }
                }
                TransportBtn {
                  glyph: root.loopMode === "one" ? "󰑘" : "󰑖"
                  btnSize: Style.space(32)
                  small: true
                  active: root.loopMode !== "off"
                  tip: "Repeat: " + root.loopMode + " (off → all → one)"
                  tapped: function() { root.cycleLoop() }
                }
              }
              Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(5)
                Text {
                  text: "-"
                  color: volDown.containsMouse ? root.accent : root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                  Behavior on color { ColorAnimation { duration: 120 } }
                  MouseArea { id: volDown; anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nudgeVolume(-5) }
                  InfoTip { watched: volDown; tipText: "Quieter"; delayMs: root.helpMode ? 3000 : 5000 }
                }
                Text {
                  width: Style.space(30)
                  horizontalAlignment: Text.AlignHCenter
                  text: String(root.setVolume)
                  textFormat: Text.PlainText
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                  text: "+"
                  color: volUp.containsMouse ? root.accent : root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  anchors.verticalCenter: parent.verticalCenter
                  Behavior on color { ColorAnimation { duration: 120 } }
                  MouseArea { id: volUp; anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nudgeVolume(5) }
                  InfoTip { watched: volUp; tipText: "Louder"; delayMs: root.helpMode ? 3000 : 5000 }
                }
              }
            }
          }
        }

        // Post-update restart helper (stale UI only, zero height when fresh)
        Item {
          width: parent.width
          height: visible ? Style.space(56) : 0
          visible: root.updateLocalVersion !== "" && !root.uiMatchesDisk()
          clip: true
          Column {
            anchors.centerIn: parent
            spacing: 4
            Text {
              anchors.horizontalCenter: parent.horizontalCenter
              horizontalAlignment: Text.AlignHCenter
              text: "Shell restart finishes the update"
              textFormat: Text.PlainText
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
            }
            Row {
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: Style.space(8)
              Rectangle {
                width: Style.space(200)
                height: Style.space(24)
                radius: height / 2
                color: root.raised
                anchors.verticalCenter: parent.verticalCenter
                TextInput {
                  id: restartCmdInput
                  text: "omarchy restart shell"
                  readOnly: true
                  selectByMouse: true
                  activeFocusOnPress: true
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  anchors.right: parent.right
                  anchors.rightMargin: Style.space(10)
                  anchors.verticalCenter: parent.verticalCenter
                  color: root.muted
                  selectionColor: root.accent
                  selectedTextColor: root.onAccent
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  clip: true
                }
              }
              SettingBtn {
                label: "Copy"
                height: Style.space(24)
                anchors.verticalCenter: parent.verticalCenter
                tapped: function() { copyProc.command = ["wl-copy", "omarchy restart shell"]; copyProc.running = true }
              }
            }
          }
        }

        // Section label + status line
        Item {
          width: parent.width
          height: Style.space(18)
          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: {
              if (root.tabIndex === 0) return "Home · free discovery"
              if (root.tabIndex === 1) return root.searching ? "Searching YouTube…" : (tracks.count > 0 ? "Results" : "Search")
              if (root.tabIndex === 2) return (root.mixPrefetching ? "Building mix… · " : "") + (root.listTitle || "Up next") + (root.queueAligned ? (" - " + Math.min(root.currentIndex + 1, tracks.count) + " of " + tracks.count) : "")
              if (root.tabIndex === 3) return root.openPlaylistName ? ("Playlist · " + root.openPlaylistName) : "My playlists"
              if (root.tabIndex === 4) return "Favourite"
              if (root.tabIndex === 5) return "Offline downloads (opus)"
              if (root.tabIndex === 6) return "Lyrics · lrclib"
              return "Settings"
            }
            color: root.ink
            font.family: root.uiFont
            font.pixelSize: Style.font.bodySmall
            font.bold: true
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.notice || root.errorMessage
            textFormat: Text.PlainText
            color: root.notice ? root.accent : "#ff7a7a"
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: Math.min(parent.width * 0.55, implicitWidth)
            horizontalAlignment: Text.AlignRight
            visible: (root.notice !== "" || root.errorMessage !== "")
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            MouseArea { id: statusHover; anchors.fill: parent; hoverEnabled: true }
            InfoTip { watched: statusHover; tipText: root.notice || root.errorMessage; delayMs: root.helpMode ? 3000 : 400 }
          }
        }

        // Playlist management row (tab 2)
        Item {
          width: parent.width
          height: root.tabIndex === 3 ? Style.space(30) : 0
          visible: root.tabIndex === 3
          Row {
            anchors.fill: parent
            spacing: Style.space(6)
            Rectangle {
              width: parent.width - Style.space(150)
              height: parent.height
              radius: height / 2
              color: root.raised
              TextInput {
                id: newPlaylistField
                anchors.left: parent.left
                anchors.leftMargin: Style.space(12)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(12)
                anchors.verticalCenter: parent.verticalCenter
                color: root.ink
                selectionColor: root.accent
                selectedTextColor: root.onAccent
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                clip: true
                Text {
                  text: "New list name…"
                  color: root.muted
                  font: newPlaylistField.font
                  visible: !newPlaylistField.text
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.createPlaylist(); event.accepted = true }
                }
              }
            }
            Rectangle {
              width: Style.space(70)
              height: parent.height
              radius: height / 2
              color: createHover.containsMouse ? root.accent : "transparent"
              border.width: 1
              border.color: root.accent
              transformOrigin: Item.Center
              scale: createHover.pressed ? 0.95 : 1.0
              Behavior on color { ColorAnimation { duration: 120 } }
              Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
              Text { anchors.centerIn: parent; text: "+ Create"; color: createHover.containsMouse ? root.onAccent : root.accent; font.family: root.uiFont; font.pixelSize: Style.font.caption; Behavior on color { ColorAnimation { duration: 120 } } }
              MouseArea { id: createHover; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.createPlaylist() }
            }
            Rectangle {
              width: Style.space(62)
              height: parent.height
              radius: height / 2
              color: root.openPlaylistName ? root.accent : "transparent"
              border.width: 1
              border.color: root.accent
              opacity: root.openPlaylistName ? 1 : 0.4
              enabled: root.openPlaylistName !== ""
              Text { anchors.centerIn: parent; text: "▶ Play"; color: root.openPlaylistName ? root.onAccent : root.accent; font.family: root.uiFont; font.pixelSize: Style.font.caption }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.playPlaylist(root.openPlaylistName) }
            }
          }
        }

        // Playlist chips (tab 2, when no playlist open / to switch)
        Item {
          width: parent.width
          height: (root.tabIndex === 3 && playlists.count > 0) ? Style.space(28) : 0
          visible: root.tabIndex === 3 && playlists.count > 0
          ListView {
            anchors.fill: parent
            orientation: ListView.Horizontal
            model: playlists
            spacing: Style.space(5)
            clip: true
            delegate: Rectangle {
              height: Style.space(26)
              width: chipText.width + Style.space(16)
              radius: height / 2
              color: root.openPlaylistName === name ? root.accent : "transparent"
              border.width: 1
              border.color: root.openPlaylistName === name ? root.accent : root.muted
              Text {
                id: chipText
                anchors.centerIn: parent
                text: name + " (" + info + ")"
                textFormat: Text.PlainText
                color: root.openPlaylistName === name ? root.onAccent : root.ink
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
              }
              MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.openPlaylist(name) }
            }
          }
        }

        // Add-to-playlist row (tabs with tracks)
        Item {
          width: parent.width
          height: (root.tabIndex !== 3 && root.tabIndex !== 0 && playlists.count > 0) ? Style.space(26) : 0
          visible: root.tabIndex !== 3 && root.tabIndex !== 0 && playlists.count > 0
          Row {
            anchors.fill: parent
            spacing: Style.space(6)
            Text {
              text: "+ list:"
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            ListView {
              width: parent.width - Style.space(44)
              height: parent.height
              orientation: ListView.Horizontal
              model: playlists
              spacing: Style.space(5)
              clip: true
              delegate: Rectangle {
                height: parent.height
                width: addChip.width + Style.space(14)
                radius: height / 2
                color: root.addTargetPlaylist === name ? root.accent : "transparent"
                border.width: 1
                border.color: root.muted
                Text {
                  id: addChip
                  anchors.centerIn: parent
                  text: name
                  textFormat: Text.PlainText
                  color: root.addTargetPlaylist === name ? root.onAccent : root.ink
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.addTargetPlaylist = (root.addTargetPlaylist === name) ? "" : name
                }
              }
            }
          }
        }

        // Home: free, legit, keyless discovery (main - top - artist - radio - tunes)
        Item {
          width: parent.width
          height: visible ? parent.height - y - Style.space(18) : 0
          visible: root.tabIndex === 0
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          clip: true

          Column {
            anchors.fill: parent
            spacing: Style.space(5)

            Item {
              width: parent.width
              height: Style.space(26)
              // Dock-style pill: raised container, sliding highlight behind the
              // active segment. Same count-guarded itemAt pattern as the tab
              // dock (44px cold-start fallback, 200ms OutCubic slide).
              Rectangle {
                id: homeDock
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(parent.width - homeRefreshBtn.width - Style.space(8), homeDockRow.width + Style.space(10))
                height: Style.space(24)
                radius: height / 2
                color: root.raised
                readonly property int litIdx: root.homeMode === "main" ? 0 : root.homeMode === "top" ? 1 : root.homeMode === "artist" ? 2 : 3
                Rectangle {
                  id: homeDockHi
                  x: Style.space(5) + ((homeSegRepeater.count > homeDock.litIdx && homeSegRepeater.itemAt(homeDock.litIdx)) ? homeSegRepeater.itemAt(homeDock.litIdx).x : 0)
                  y: Style.space(2)
                  width: (homeSegRepeater.count > homeDock.litIdx && homeSegRepeater.itemAt(homeDock.litIdx)) ? homeSegRepeater.itemAt(homeDock.litIdx).width : Style.space(44)
                  height: parent.height - Style.space(4)
                  radius: height / 2
                  color: root.accent
                  Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                  Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                }
                Row {
                  id: homeDockRow
                  x: Style.space(5)
                  y: Style.space(2)
                  height: parent.height - Style.space(4)
                  Repeater {
                    id: homeSegRepeater
                    model: [
                      { key: "main", label: "Main" },
                      { key: "top", label: "Top charts" },
                      { key: "artist", label: "Artist" },
                      { key: "more", label: "More" }
                    ]
                    Item {
                      readonly property bool segActive: index < 3 ? root.homeMode === modelData.key : (root.homeMore || homeDock.litIdx === 3)
                      width: segLabel.width + Style.space(14)
                      height: homeDockRow.height
                      Text {
                        id: segLabel
                        anchors.centerIn: parent
                        text: modelData.label
                        textFormat: Text.PlainText
                        color: segActive ? root.onAccent : root.muted
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                        font.bold: segActive
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (index < 3) root.setHomeMode(modelData.key)
                          else root.homeMore = !root.homeMore
                        }
                      }
                    }
                  }
                }
              }
              TransportBtn {
                id: homeRefreshBtn
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: btnSize
                height: btnSize
                z: 5
                glyph: "\u21bb"
                btnSize: Style.space(18)
                tip: "Refresh feed"
                tapped: function() {
                  homeModel.clear()
                  root.notice = "Refreshing feed..."
                  noticeTimer.restart()
                  if (root.homeMode === "artist") {
                    try { artistModel.clear() } catch (e2) {}
                    try { root.reloadArtists() } catch (e3) {}
                    return
                  }
                  root.homeForceRefresh = true
                  root.reloadHome(true)
                }
                NumberAnimation on rotation {
                  running: root.homeLoading
                  from: 0
                  to: 360
                  loops: Animation.Infinite
                  duration: 800
                  onStopped: homeRefreshBtn.rotation = 0
                }
              }
            }

            Row {
              width: parent.width
              height: visible ? Style.space(24) : 0
              visible: root.homeMore
              spacing: Style.space(5)
              Rectangle {
                width: tunesMiniLabel.width + Style.space(14)
                height: Style.space(22)
                radius: height / 2
                color: root.homeMode === "tunes" ? root.accent : "transparent"
                border.width: 1
                border.color: root.homeMode === "tunes" ? root.accent : root.muted
                Text {
                  id: tunesMiniLabel
                  anchors.centerIn: parent
                  text: "Find tunes"
                  color: root.homeMode === "tunes" ? root.onAccent : root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  font.bold: root.homeMode === "tunes"
                }
                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.setHomeMode("tunes")
                }
              }
            }


            // Tune search (iTunes, free, previews, under More)
            Rectangle {
              width: parent.width
              height: visible ? Style.space(30) : 0
              visible: root.homeMore && root.homeMode === "tunes"
              radius: height / 2
              color: root.raised
              TextInput {
                id: homeTunesField
                anchors.left: parent.left
                anchors.leftMargin: Style.space(13)
                anchors.right: parent.right
                anchors.rightMargin: Style.space(13)
                anchors.verticalCenter: parent.verticalCenter
                color: root.ink
                selectionColor: root.accent
                selectedTextColor: root.onAccent
                font.family: root.uiFont
                font.pixelSize: Style.font.bodySmall
                clip: true
                onTextChanged: {
                  if (text.trim().length >= 2) homeTunesTimer.restart()
                }
                Text {
                  text: "Artist, genre, mood… (free previews)"
                  color: root.muted
                  font: homeTunesField.font
                  visible: !homeTunesField.text
                }
                Keys.onPressed: function(event) {
                  if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    homeTunesTimer.stop()
                    root.homeTunesQuery = text.trim()
                    homeModel.clear()
                    root.reloadHome()
                    event.accepted = true
                  }
                }
              }
            }

            Text {
              width: parent.width
              visible: root.homeLoading
              text: "Discovering…"
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.bodySmall
              horizontalAlignment: Text.AlignHCenter
            }

            Item {
              width: parent.width
              height: visible ? parent.height - y : 0
              visible: root.homeMode === "artist"
              clip: true
              Column {
                anchors.fill: parent
                spacing: Style.space(5)
                Rectangle {
                  width: parent.width
                  height: Style.space(30)
                  radius: height / 2
                  color: root.raised
                  TextInput {
                    id: artistSearchField
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(13)
                    anchors.right: parent.right
                    anchors.rightMargin: Style.space(13)
                    anchors.verticalCenter: parent.verticalCenter
                    color: root.ink
                    selectionColor: root.accent
                    selectedTextColor: root.onAccent
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    clip: true
                    onTextChanged: {
                      var fq = text.trim()
                      if (fq.length >= 2) artistSearchTimer.restart()
                      else { artistSearchTimer.stop(); artistFindModel.clear(); root.artistFinding = false }
                    }
                    Text {
                      text: "Search artist... (follow to build roster)"
                      color: root.muted
                      font: artistSearchField.font
                      visible: !artistSearchField.text
                    }
                    Keys.onPressed: function(event) {
                      if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        artistSearchTimer.stop()
                        if (artistFindModel.count > 0) root.loadArtistProfile(artistFindModel.get(0).name)
                        else root.loadArtistProfile(text.trim())
                        event.accepted = true
                      }
                    }
                  }
                }
                ListView {
                  id: artistFindList
                  width: parent.width
                  height: visible ? Math.min(artistFindModel.count * Style.space(51), Style.space(51) * 3 + Style.space(6)) : 0
                  visible: root.artistProfile === "" && artistFindModel.count > 0
                  opacity: visible ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                  model: artistFindModel
                  clip: true
                  spacing: Style.space(3)
                  delegate: Rectangle {
                    required property string name
                    required property string art
                    required property string genre
                    width: ListView.view ? ListView.view.width : 0
                    height: Style.space(48)
                    radius: Style.space(7)
                    color: artistFindHover.containsMouse ? root.raised : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                      z: 2
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(7)
                      Rectangle {
                        width: Style.space(38)
                        height: width
                        radius: Style.space(5)
                        color: root.raised
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Image { anchors.fill: parent; source: art; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
                        Text {
                          anchors.centerIn: parent
                          visible: art === ""
                          text: "A"
                          color: root.muted
                          font.family: root.uiFont
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }
                      Column {
                        width: parent.width - Style.space(38) - parent.spacing
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)
                        Text { width: parent.width; text: name; textFormat: Text.PlainText; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; visible: genre !== ""; text: genre; textFormat: Text.PlainText; color: root.muted; font.family: root.uiFont; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                      }
                    }
                    MouseArea {
                      id: artistFindHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.loadArtistProfile(name)
                    }
                  }
                }
                Text {
                  width: parent.width
                  visible: root.artistFinding
                  text: "Finding artists..."
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }
                Text {
                  width: parent.width
                  visible: root.artistLoading
                  text: "Loading artists..."
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.bodySmall
                  horizontalAlignment: Text.AlignHCenter
                }
                Item {
                  width: parent.width
                  height: visible ? artistHeadRow.height + (profileStats.visible ? profileStats.height + Style.space(2) : 0) + (artistBioText.visible ? artistBioText.height + Style.space(2) : 0) : 0
                  visible: root.artistProfile !== ""
                  clip: true
                  Column {
                    id: artistHeadCol
                    width: parent.width
                    spacing: 0
                    Row {
                      id: artistHeadRow
                      width: parent.width
                      height: Style.space(52)
                      spacing: Style.space(8)
                      SettingBtn {
                        label: "Back"
                        anchors.verticalCenter: parent.verticalCenter
                        tapped: function() { root.artistProfile = ""; artistSongsModel.clear(); root.reloadArtists() }
                      }
                      Rectangle {
                        width: Style.space(42)
                        height: width
                        radius: Style.space(7)
                        color: root.raised
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                          anchors.fill: parent
                          fillMode: Image.PreserveAspectCrop
                          asynchronous: true
                          source: {
                            var n = root.artistProfile
                            for (var f = 0; f < artistFindModel.count; f++) {
                              var fm = artistFindModel.get(f)
                              if (fm.name === n && fm.art) return fm.art
                            }
                            if (root.artistPortrait !== "") return root.artistPortrait
                            for (var i = 0; i < artistModel.count; i++) {
                              var m = artistModel.get(i)
                              if (m.name === n && m.art) return m.art
                            }
                            if (artistSongsModel.count > 0 && artistSongsModel.get(0).art) return artistSongsModel.get(0).art
                            return ""
                          }
                          opacity: status === Image.Ready ? 1 : 0
                          Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                        }
                        Text {
                          anchors.centerIn: parent
                          visible: {
                            var n2 = root.artistProfile
                            for (var f2 = 0; f2 < artistFindModel.count; f2++) {
                              if (artistFindModel.get(f2).name === n2 && artistFindModel.get(f2).art) return false
                            }
                            if (root.artistPortrait !== "") return false
                            for (var j = 0; j < artistModel.count; j++) {
                              if (artistModel.get(j).name === n2 && artistModel.get(j).art) return false
                            }
                            if (artistSongsModel.count > 0 && artistSongsModel.get(0).art) return false
                            return true
                          }
                          text: "A"
                          color: root.muted
                          font.family: root.uiFont
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }
                      Text {
                        width: parent.width - Style.space(42) - Style.space(90) - Style.space(60) - (artistBioBtn.visible ? artistBioBtn.width + parent.spacing : 0) - parent.spacing * 3
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.artistProfile
                        textFormat: Text.PlainText
                        color: root.ink
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }
                      SettingBtn {
                        id: artistBioBtn
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.artistBio !== ""
                        label: "BIO"
                        tapped: function() { root.artistBioOpen = !root.artistBioOpen }
                      }
                      SettingBtn {
                        anchors.verticalCenter: parent.verticalCenter
                        label: {
                          var nn = root.artistProfile
                          for (var k = 0; k < artistModel.count; k++) {
                            if (artistModel.get(k).name === nn) return "Following"
                          }
                          return "Follow"
                        }
                        tapped: function() {
                          var nn2 = root.artistProfile
                          var aa = ""
                          for (var k2 = 0; k2 < artistModel.count; k2++) {
                            if (artistModel.get(k2).name === nn2 && artistModel.get(k2).art) { aa = artistModel.get(k2).art; break }
                          }
                          if (!aa && artistSongsModel.count > 0) aa = artistSongsModel.get(0).art
                          root.toggleFollow(nn2, aa)
                        }
                      }
                    }
                    Text {
                      id: profileStats
                      width: parent.width
                      visible: root.artistSubs !== "" || root.artistGenre !== ""
                      text: (root.artistSubs !== "" ? root.artistSubs : "") + ((root.artistSubs !== "" && root.artistGenre !== "") ? " \u2022 " : "") + (root.artistGenre !== "" ? root.artistGenre : "")
                      textFormat: Text.PlainText
                      color: root.muted
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                    }
                    Text {
                      id: artistBioText
                      width: parent.width
                      visible: root.artistBioOpen && root.artistBio !== ""
                      text: root.artistBio
                      textFormat: Text.PlainText
                      wrapMode: Text.WordWrap
                      color: root.muted
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                    }
                  }
                }
                GridView {
                  id: artistGrid
                  width: parent.width
                  height: parent.height - y
                  visible: root.artistProfile === "" && artistModel.count > 0
                  opacity: visible ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                  model: artistModel
                  clip: true
                  cellWidth: Math.floor(width / 2)
                  cellHeight: Style.space(64)
                  delegate: Rectangle {
                    required property string name
                    required property string art
                    width: GridView.view.cellWidth - Style.space(4)
                    height: Style.space(60)
                    radius: Style.space(7)
                    color: artistCellHover.containsMouse ? root.raised : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                      z: 2
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(7)
                      Rectangle {
                        width: Style.space(38)
                        height: width
                        radius: Style.space(5)
                        color: root.raised
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Image { anchors.fill: parent; source: art; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
                        Text {
                          anchors.centerIn: parent
                          visible: art === ""
                          text: "A"
                          color: root.muted
                          font.family: root.uiFont
                          font.pixelSize: Style.font.bodySmall
                          font.bold: true
                        }
                      }
                      Text {
                        width: parent.width - Style.space(38) - Style.space(22) - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        text: name
                        textFormat: Text.PlainText
                        color: root.ink
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        elide: Text.ElideRight
                      }
                      Text {
                        text: "x"
                        color: artistUnfollowHover.containsMouse ? root.accent : root.muted
                        font.family: root.uiFont
                        font.pixelSize: Style.font.bodySmall
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                          id: artistUnfollowHover
                          anchors.fill: parent
                          anchors.margins: -Style.space(6)
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleFollow(name, art)
                        }
                      }
                    }
                    MouseArea {
                      id: artistCellHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.loadArtistProfile(name)
                    }
                  }
                }
                ListView {
                  id: artistSongsList
                  width: parent.width
                  height: parent.height - y
                  visible: root.artistProfile !== "" && artistSongsModel.count > 0
                  opacity: visible ? 1 : 0
                  Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                  model: artistSongsModel
                  clip: true
                  spacing: Style.space(3)
                  delegate: Rectangle {
                    required property int index
                    required property string title
                    required property string artist
                    required property string art
                    required property string url
                    required property string kind
                    width: ListView.view ? ListView.view.width : 0
                    height: Style.space(48)
                    radius: Style.space(7)
                    color: artistSongHover.containsMouse ? root.raised : "transparent"
                    Behavior on color { ColorAnimation { duration: 120 } }
                    Row {
                      z: 2
                      anchors.fill: parent
                      anchors.leftMargin: Style.space(4)
                      anchors.rightMargin: Style.space(6)
                      spacing: Style.space(7)
                      Rectangle {
                        width: Style.space(38)
                        height: width
                        radius: Style.space(5)
                        color: root.raised
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter
                        Image { anchors.fill: parent; source: art; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
                        Text {
                          anchors.centerIn: parent
                          visible: art === ""
                          text: "P"
                          color: root.muted
                          font.family: root.uiFont
                          font.pixelSize: Style.font.bodySmall
                        }
                      }
                      Column {
                        width: parent.width - Style.space(38) - Style.space(34) - Style.space(36) - parent.spacing * 2
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Style.space(2)
                        Text { width: parent.width; text: title; textFormat: Text.PlainText; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight }
                        Text { width: parent.width; text: (artist ? artist + " - " : "") + "preview + full track"; textFormat: Text.PlainText; color: root.muted; font.family: root.uiFont; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
                      }
                      TransportBtn {
                        glyph: ">"
                        btnSize: Style.space(30)
                        small: true
                        anchors.verticalCenter: parent.verticalCenter
                        tip: "Play"
                        tapped: function() { root.playArtistSong(index) }
                      }
                      Rectangle {
                        width: Style.space(34)
                        height: Style.space(30)
                        radius: height / 2
                        color: "transparent"
                        border.width: 1
                        border.color: artistYtHover.containsMouse ? root.accent : root.muted
                        anchors.verticalCenter: parent.verticalCenter
                        transformOrigin: Item.Center
                        scale: artistYtHover.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
                        Behavior on border.color { ColorAnimation { duration: 120 } }
                        Text {
                          anchors.centerIn: parent
                          text: "YT"
                          color: artistYtHover.containsMouse ? root.accent : root.ink
                          font.family: root.uiFont
                          font.pixelSize: Style.font.caption
                          font.bold: true
                          Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        MouseArea {
                          id: artistYtHover
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.ytSearchAndPlay(artist + " " + title)
                        }
                      }
                    }
                    MouseArea {
                      id: artistSongHover
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.playArtistSong(index)
                    }
                  }
                }
                Text {
                  width: parent.width
                  height: parent.height - y
                  visible: root.artistProfile === "" && !root.artistLoading && artistModel.count === 0
                  text: "No follows yet - search above to find an artist"
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
                Text {
                  width: parent.width
                  height: parent.height - y
                  visible: root.artistProfile !== "" && !root.artistLoading && artistSongsModel.count === 0
                  text: "No songs for this artist - try another search"
                  color: root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.body
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                }
              }
              Timer {
                id: artistSearchTimer
                interval: 600
                repeat: false
                onTriggered: root.findArtists(artistSearchField.text.trim())
              }
            }

            ListView {
              id: homeList
              width: parent.width
              height: parent.height - y
              model: homeModel
              clip: true
              spacing: Style.space(3)
              visible: homeModel.count > 0
              opacity: visible ? 1 : 0
              Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
              add: Transition {
                NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
                NumberAnimation { property: "x"; from: 14; to: 0; duration: 170; easing.type: Easing.OutCubic }
              }
              remove: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 130; easing.type: Easing.OutCubic } }
              displaced: Transition { NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic } }
              delegate: HomeRow { }
            }

            Text {
              width: parent.width
              height: parent.height - y
              visible: !root.homeLoading && homeModel.count === 0
              text: root.homeMode === "tunes" ? "Search anything — previews play instantly" : (root.homeMode === "radio" ? "Pick a genre for free live radio" : (root.homeMode === "artist" ? "Artists - pick a name for the mix station" : (root.homeMode === "top" ? "Today's top songs — ▶ plays the full track" : "For you - fresh picks with reasons")))
              color: root.muted
              font.family: root.uiFont
              font.pixelSize: Style.font.body
              horizontalAlignment: Text.AlignHCenter
              wrapMode: Text.WordWrap
            }
          }
        }

        Timer {
          id: homeTunesTimer
          interval: 600
          repeat: false
          onTriggered: {
            root.homeTunesQuery = homeTunesField.text.trim()
            homeModel.clear()
            root.reloadHome()
          }
        }

        // Track list
        ListView {
          id: resultList
          width: parent.width
          height: visible ? parent.height - y - Style.space(18) : 0
          model: tracks
          clip: true
          spacing: Style.space(3)
          currentIndex: root.selectedIndex
          visible: tracks.count > 0 && root.tabIndex !== 0 && root.tabIndex !== 6 && root.tabIndex !== 7
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          add: Transition {
            NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 170; easing.type: Easing.OutCubic }
            NumberAnimation { property: "x"; from: 14; to: 0; duration: 170; easing.type: Easing.OutCubic }
          }
          remove: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 130; easing.type: Easing.OutCubic } }
          displaced: Transition { NumberAnimation { property: "y"; duration: 180; easing.type: Easing.OutCubic } }
          Keys.onPressed: function(event) {
            if (event.key === Qt.Key_Escape) { root.requestClose(); event.accepted = true }
            else if (event.key === Qt.Key_Up) { if (root.selectedIndex <= 0 && root.tabIndex === 1) root.searchInput.forceActiveFocus(); else root.selectedIndex = Math.max(0, root.selectedIndex - 1); event.accepted = true }
            else if (event.key === Qt.Key_Down) { root.selectedIndex = Math.min(tracks.count - 1, root.selectedIndex + 1); event.accepted = true }
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { root.selectTrack(root.selectedIndex); event.accepted = true }
          }
          delegate: TrackRow { }
        }

        // Lyrics view (karaoke-style, synced line glows in theme accent)
        Item {
          width: parent.width
          height: visible ? parent.height - y - Style.space(18) : 0
          visible: root.tabIndex === 6
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          clip: true

          Column {
            anchors.fill: parent
            spacing: Style.space(4)

            Item {
              width: parent.width
              height: Style.space(20)
              Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.lyricLoading ? "Loading lyrics…" : (root.lyricsSynced ? "Synced · follow along" : (lyrics.count > 0 ? "Plain lyrics" : root.currentTitle ? "No lyrics yet" : "Play something first"))
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                width: parent.width - Style.space(104)
              }
              // Live sync nudge (−/+ 0.2s, remembered per song) · tap offset for settings
              Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(7)
                Text {
                  text: "−"
                  color: root.muted
                  font.family: root.iconFont
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nudgeOffset(-0.2) }
                }
                Text {
                  text: root.formatOffset(root.trackLyricOffset)
                  color: root.trackLyricOffset !== 0 ? root.accent : root.muted
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.setTab(7) }
                }
                Text {
                  text: "+"
                  color: root.muted
                  font.family: root.iconFont
                  font.pixelSize: Style.font.bodySmall
                  font.bold: true
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.nudgeOffset(0.2) }
                }
                Text {
                  text: "↻"
                  color: root.muted
                  font.family: root.iconFont
                  font.pixelSize: Style.font.bodySmall
                  MouseArea { anchors.fill: parent; anchors.margins: -Style.space(5); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.retryLyrics() }
                }
              }
            }

            ListView {
              id: lyricsView
              width: parent.width
              height: parent.height - y
              model: lyrics
              clip: true
              spacing: Style.space(6)
              delegate: Item {
                id: lyricRow
                required property int index
                required property string text
                readonly property bool isActive: root.currentLyricIndex === index
                readonly property int dist: Math.abs(root.currentLyricIndex - index)
                width: ListView.view ? ListView.view.width : 0
                height: lyricText.height + Style.space(2)
                opacity: !root.lyricsSynced ? 1.0 : (isActive ? 1.0 : (dist === 1 ? 0.85 : (dist === 2 ? 0.6 : 0.35)))
                Behavior on opacity { NumberAnimation { duration: 280; easing.type: Easing.OutCubic } }
                onIsActiveChanged: if (isActive && root.lyricsSynced) activateAnim.restart()
                Text {
                  id: lyricText
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  wrapMode: Text.WordWrap
                  text: lyricRow.text
                  textFormat: Text.PlainText
                  color: lyricRow.isActive ? root.ink : root.muted
                  font.family: root.uiFont
                  font.pixelSize: lyricRow.isActive ? Style.font.body : Style.font.bodySmall
                  font.bold: lyricRow.isActive
                  font.italic: !root.lyricsSynced
                  transform: Translate { id: lyricSlide; y: 0 }
                }
                MouseArea {
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: root.lyricsSynced ? Qt.PointingHandCursor : Qt.ArrowCursor
                  onClicked: { if (root.lyricsSynced) root.seekToLyric(lyricRow.index) }
                }
                Glow {
                  id: lyricGlow
                  anchors.fill: lyricText
                  source: lyricText
                  color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65)
                  radius: 3
                  samples: 17
                  spread: 0.25
                  visible: lyricRow.isActive && root.lyricsSynced
                }
                ParallelAnimation {
                  id: activateAnim
                  NumberAnimation { target: lyricSlide; property: "y"; from: 8; to: 0; duration: 280; easing.type: Easing.OutCubic }
                  NumberAnimation { target: lyricText; property: "opacity"; from: 0; to: 1; duration: 280; easing.type: Easing.OutCubic }
                }
                SequentialAnimation {
                  id: glowBreath
                  running: lyricRow.isActive && root.lyricsSynced
                  loops: Animation.Infinite
                  NumberAnimation { target: lyricGlow; property: "radius"; from: 3; to: 6; duration: 800; easing.type: Easing.InOutQuad }
                  NumberAnimation { target: lyricGlow; property: "radius"; from: 6; to: 3; duration: 800; easing.type: Easing.InOutQuad }
                  onStopped: lyricGlow.radius = 3
                }
              }
            }
          }
        }

        // Settings — quality-of-life toggles, all persisted, no login anywhere
        Item {
          width: parent.width
          height: visible ? parent.height - y - Style.space(18) : 0
          visible: root.tabIndex === 7
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          clip: true

          Flickable {
            anchors.fill: parent
            contentHeight: settingsCol.height
            clip: true
            Column {
              id: settingsCol
              width: parent.width
              spacing: Style.space(1)

              Text { text: "Playback"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(2) }

              SettingRow {
                title: "Skip silence"
                desc: "Trim dead air at track edges · next track"
                control: SettingToggle {
                  on: root.setSilence
                  flipped: function() { root.toggleSetting("silence", root.setSilence) }
                }
              }
              SettingRow {
                title: "Visualizer"
                desc: "Spectrum bars in the bar"
                control: SettingToggle {
                  on: root.vizOn
                  flipped: function() { root.vizOn = !root.vizOn; root.saveSetting("viz", root.vizOn ? "on" : "off") }
                }
              }
              SettingRow {
                title: "Normalize volume"
                desc: "Even out loud / quiet masters · next track"
                control: SettingToggle {
                  on: root.setNormalize
                  flipped: function() { root.toggleSetting("normalize", root.setNormalize) }
                }
              }
              SettingRow {
                title: "Startup volume"
                desc: "Applied from the next track"
                control: SettingStepper {
                  label: String(root.setVolume)
                  step: 5
                  value: root.setVolume
                  changed: function(v) {
                    v = Math.max(0, Math.min(100, Math.round(v / 5) * 5))
                    root.setVolume = v
                    root.saveSetting("volume", v)
                  }
                }
              }
              SettingRow {
                title: "Repeat mode"
                desc: "Off → all → one (same as transport button)"
                control: SettingCycle {
                  options: ["off", "all", "one"]
                  labels: ["Off", "All", "One"]
                  current: root.loopMode
                  picked: function(v) { root.loopMode = v; root.runCmd(["loop", v]) }
                }
              }
              Item {
                width: parent.width
                height: Style.space(58)
                Column {
                  width: parent.width
                  spacing: Style.space(4)
                  Text {
                    text: "Seekbar style"
                    textFormat: Text.PlainText
                    color: root.ink
                    font.family: root.uiFont
                    font.pixelSize: Style.font.bodySmall
                    font.bold: true
                  }
                  Row {
                    spacing: Style.space(4)
                    Repeater {
                      model: ["default", "wave", "lightning", "spiral", "dots", "mirror", "neon"]
                      delegate: Rectangle {
                        width: 70
                        height: 38
                        radius: 6
                        color: "transparent"
                        border.width: 1
                        border.color: root.seekStyle === modelData ? root.accent : root.muted
                        Column {
                          anchors.centerIn: parent
                          spacing: 1
                          Canvas {
                            width: 64
                            height: 20
                            onWidthChanged: requestPaint()
                            Component.onCompleted: requestPaint()
                            onPaint: {
                              var ctx = getContext("2d")
                              var w = width
                              var h = height
                              ctx.clearRect(0, 0, w, h)
                              if (w <= 0 || h <= 0) return
                              var midY = h / 2
                              var amp = 4
                              var waveLen = 16
                              var phase = 1.2
                              var css = function(c, a) { return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")" }
                              var playedCss = css(root.accent, 1)
                              var restCss = css(root.muted, 0.4)
                              var splitX = 0.35 * w
                              var kind = modelData
                              var waveY = function(x) { var a = (x / waveLen) * 2 * Math.PI; return midY + 4 * Math.sin(a + phase) + 1.5 * Math.sin(2.2 * a + 1.3 + phase) }
                              var triY = function(x) {
                                var p = ((x / waveLen) + phase / (2 * Math.PI)) % 1
                                if (p < 0) p += 1
                                var t = p < 0.5 ? (p * 4 - 1) : (3 - p * 4)
                                return midY + amp * t
                              }
                              if (kind === "default") {
                                ctx.lineCap = "round"
                                ctx.strokeStyle = restCss
                                ctx.lineWidth = 4
                                ctx.beginPath()
                                ctx.moveTo(0, midY)
                                ctx.lineTo(w, midY)
                                ctx.stroke()
                                ctx.strokeStyle = playedCss
                                ctx.lineWidth = 4
                                ctx.beginPath()
                                ctx.moveTo(0, midY)
                                ctx.lineTo(splitX, midY)
                                ctx.stroke()
                                ctx.fillStyle = playedCss
                                ctx.beginPath()
                                ctx.arc(splitX, midY, 3, 0, 2 * Math.PI)
                                ctx.fill()
                                return
                              }
                              if (kind === "wave" || kind === "lightning") {
                                var yf = kind === "wave" ? waveY : triY
                                var seg = function(x0, x1, style) {
                                  if (x1 <= x0) return
                                  ctx.strokeStyle = style
                                  ctx.lineWidth = 2
                                  ctx.lineCap = "round"
                                  ctx.lineJoin = "round"
                                  ctx.beginPath()
                                  var x = x0
                                  ctx.moveTo(x, yf(x))
                                  x += 2
                                  while (x < x1) { ctx.lineTo(x, yf(x)); x += 2 }
                                  ctx.lineTo(x1, yf(x1))
                                  ctx.stroke()
                                }
                                seg(0, splitX, playedCss)
                                seg(splitX, w, restCss)
                                ctx.fillStyle = playedCss
                                ctx.beginPath()
                                ctx.arc(splitX, yf(splitX), 3, 0, 2 * Math.PI)
                                ctx.fill()
                                return
                              }
                              if (kind === "spiral") {
                                ctx.strokeStyle = restCss
                                ctx.lineWidth = 2
                                ctx.lineCap = "round"
                                ctx.beginPath()
                                ctx.moveTo(0, midY)
                                ctx.lineTo(w, midY)
                                ctx.stroke()
                                var turns = 2.5
                                var maxR = 6
                                var steps = 32
                                ctx.strokeStyle = playedCss
                                ctx.lineWidth = 2
                                ctx.beginPath()
                                for (var i = 0; i <= steps; i++) {
                                  var th = (i / steps) * turns * 2 * Math.PI
                                  var rr = maxR * (i / steps)
                                  var sx = splitX + rr * Math.cos(th)
                                  var sy = midY + rr * Math.sin(th) * 0.8
                                  if (i === 0) ctx.moveTo(sx, sy)
                                  else ctx.lineTo(sx, sy)
                                }
                                ctx.stroke()
                                ctx.fillStyle = playedCss
                                ctx.beginPath()
                                ctx.arc(splitX, midY, 3, 0, 2 * Math.PI)
                                ctx.fill()
                                return
                              }
                              if (kind === "mirror") {
                                var MN = 56
                                var mHash = function(i) { var x = Math.sin(i * 12.9898) * 43758.5453; return x - Math.floor(x) }
                                var mbw = 1
                                for (var mi = 0; mi < MN; mi++) {
                                  var h01 = mHash(mi)
                                  var bh = 2 + h01 * Math.max(2, (h - 4))
                                  var mx = (mi + 0.5) / MN * w
                                  ctx.fillStyle = (mx <= splitX) ? playedCss : restCss
                                  ctx.fillRect(mx - mbw / 2, midY - bh / 2, mbw, bh)
                                }
                                return
                              }
                              if (kind === "neon") {
                                var segN = function(x0, x1, style) {
                                  if (x1 <= x0) return
                                  ctx.strokeStyle = style
                                  ctx.lineWidth = 2
                                  ctx.lineCap = "round"
                                  ctx.lineJoin = "round"
                                  ctx.beginPath()
                                  var x = x0
                                  ctx.moveTo(x, waveY(x))
                                  x += 2
                                  while (x < x1) { ctx.lineTo(x, waveY(x)); x += 2 }
                                  ctx.lineTo(x1, waveY(x1))
                                  ctx.stroke()
                                }
                                var pulse = 8 + 4 * Math.sin(phase)
                                ctx.save()
                                ctx.shadowColor = playedCss
                                ctx.shadowBlur = pulse
                                segN(0, splitX, playedCss)
                                ctx.restore()
                                segN(splitX, w, restCss)
                                ctx.save()
                                ctx.shadowColor = playedCss
                                ctx.shadowBlur = 12
                                ctx.fillStyle = playedCss
                                ctx.beginPath()
                                ctx.arc(splitX, waveY(splitX), 4, 0, 2 * Math.PI)
                                ctx.fill()
                                ctx.restore()
                                return
                              }
                              var N = 24
                              for (var d = 0; d < N; d++) {
                                var dx = (d + 0.5) / N * w
                                var isPlayed = dx <= splitX
                                var dr = 1.5
                                if (isPlayed) {
                                  dr = 1.5 + 2.5 * (dx / splitX)
                                  ctx.fillStyle = playedCss
                                } else {
                                  ctx.fillStyle = restCss
                                }
                                ctx.beginPath()
                                ctx.arc(dx, midY, dr, 0, 2 * Math.PI)
                                ctx.fill()
                              }
                            }
                          }
                          Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            textFormat: Text.PlainText
                            color: root.muted
                            font.family: root.uiFont
                            font.pixelSize: Style.font.caption
                          }
                        }
                        MouseArea {
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            root.seekStyle = modelData
                            root.saveSetting("seekstyle", modelData)
                            root.notice = "Seekbar: " + modelData
                            noticeTimer.restart()
                          }
                        }
                      }
                    }
                  }
                }
              }

              Text { text: "Lyrics"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              SettingRow {
                title: "Default sync offset"
                desc: "Per-song −/+ nudges save automatically"
                control: SettingStepper {
                  label: root.formatOffset(root.setLyricsOffset)
                  step: 0.5
                  value: root.setLyricsOffset
                  changed: function(v) {
                    v = Math.max(-5, Math.min(5, Math.round(v * 2) / 2))
                    root.setLyricsOffset = v
                    root.saveSetting("lyricsOffset", v)
                  }
                }
              }
              SettingRow {
                title: "Reset this song's offset"
                desc: root.formatOffset(root.trackLyricOffset) + " on current track"
                control: SettingBtn {
                  label: "Reset"
                  tapped: function() { root.resetOffset() }
                }
              }

              Text { text: "Queue & library"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              SettingRow {
                title: "Autoplay mix"
                desc: "Search picks build a mix station"
                control: SettingToggle {
                  on: root.setMixAuto
                  flipped: function() { root.toggleSetting("mixAuto", root.setMixAuto) }
                }
              }
              SettingRow {
                title: "Search results"
                desc: "How many rows per search"
                control: SettingCycle {
                  options: [8, 12, 20]
                  current: root.setSearchLimit
                  picked: function(v) { root.setSearchLimit = v; root.saveSetting("searchLimit", v) }
                }
              }
              SettingRow {
                title: "Download quality"
                desc: "Opus in ~/Music/ytmusic-plus"
                control: SettingCycle {
                  options: ["best", "compact"]
                  labels: ["Best", "Compact"]
                  current: root.setDlQuality
                  picked: function(v) { root.setDlQuality = v; root.saveSetting("dlQuality", v) }
                }
              }

              Text { text: "Equalizer"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              Text {
                width: parent.width
                text: "10 bands · " + root.eqPresetName + " · changes apply from the next track"
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
              }

              Item {
                width: parent.width
                height: visible ? Style.space(26) : 0
                visible: true
                clip: true
                ListView {
                  anchors.fill: parent
                  orientation: ListView.Horizontal
                  model: root.eqPresets
                  spacing: Style.space(5)
                  clip: true
                  delegate: Rectangle {
                    height: Style.space(24)
                    width: eqpLabel.width + Style.space(14)
                    radius: height / 2
                    color: root.eqPresetName === modelData ? root.accent : "transparent"
                    border.width: 1
                    border.color: root.eqPresetName === modelData ? root.accent : root.muted
                    Text {
                      id: eqpLabel
                      anchors.centerIn: parent
                      text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                      color: root.eqPresetName === modelData ? root.onAccent : root.ink
                      font.family: root.uiFont
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.eqSetPreset(modelData)
                    }
                  }
                }
              }

              // 10 vertical sliders, one per band
              Item {
                width: parent.width
                height: Style.space(118)
                Row {
                  anchors.horizontalCenter: parent.horizontalCenter
                  spacing: Style.space(4)
                  Repeater {
                    model: 10
                    EqSlider {
                      band: root.eqBands[index]
                      gain: (root.eqGainsArr && root.eqGainsArr.length === 10) ? root.eqGainsArr[index] : 0
                      changed: function(v) { root.eqSetBand(index, v) }
                    }
                  }
                }
              }

              SettingRow {
                title: "Reset equalizer"
                desc: "Back to flat, all bands 0 dB"
                control: SettingBtn {
                  label: "Reset"
                  tapped: function() { root.eqSetPreset("flat") }
                }
              }

              Text { text: "Appearance"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              SettingRow {
                title: "Custom font"
                desc: root.customFontName !== "" ? root.customFontName : "System font · ttf otf woff woff2 ttc"
                control: Row {
                  spacing: Style.space(6)
                  SettingBtn {
                    label: "Choose file…"
                    tapped: function() { fontDialog.open() }
                  }
                  SettingBtn {
                    label: "System"
                    visible: root.customFontName !== ""
                    tapped: function() {
                      root.customFontName = ""
                      root.runCmd(["font-reset"])
                    }
                  }
                }
              }

              Item {
                width: parent.width
                height: Style.space(26)
                clip: true
                ListView {
                  anchors.fill: parent
                  orientation: ListView.Horizontal
                  model: ["Noto Sans", "Noto Serif", "Liberation Sans", "Liberation Serif", "JetBrains Mono", "Omarchy system"]
                  spacing: Style.space(5)
                  clip: true
                  delegate: Rectangle {
                    height: Style.space(24)
                    width: fontPresetLabel.width + Style.space(14)
                    radius: height / 2
                    color: (modelData === "Omarchy system" ? root.customFontName === "" : root.customFontName === modelData) ? root.accent : "transparent"
                    border.width: 1
                    border.color: (modelData === "Omarchy system" ? root.customFontName === "" : root.customFontName === modelData) ? root.accent : root.muted
                    Text {
                      id: fontPresetLabel
                      anchors.centerIn: parent
                      text: modelData
                      color: (modelData === "Omarchy system" ? root.customFontName === "" : root.customFontName === modelData) ? root.onAccent : root.ink
                      font.family: modelData === "Omarchy system" ? Style.font.menuFamily : modelData
                      font.pixelSize: Style.font.caption
                    }
                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: {
                        if (modelData === "Omarchy system") {
                          root.customFontName = ""
                          root.runCmd(["font-reset"])
                        } else {
                          root.customFontName = modelData
                          root.saveSetting("customFont", modelData)
                          root.notice = "Font: " + modelData
                          noticeTimer.restart()
                        }
                      }
                    }
                  }
                }
              }

              Text { text: "Sleep timer"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              Item {
                width: parent.width
                height: Style.space(30)
                Row {
                  anchors.left: parent.left
                  anchors.verticalCenter: parent.verticalCenter
                  spacing: Style.space(5)
                  Repeater {
                    model: ["15", "30", "45", "60", "Song", "Off"]
                    Rectangle {
                      width: sleepChip.width + Style.space(14)
                      height: Style.space(24)
                      radius: height / 2
                      color: {
                        if (modelData === "Off") return (root.sleepMode === "") ? root.accent : "transparent"
                        if (modelData === "Song") return (root.sleepMode === "song") ? root.accent : "transparent"
                        return "transparent"
                      }
                      border.width: 1
                      border.color: {
                        if (modelData === "Off") return (root.sleepMode === "") ? root.accent : root.muted
                        if (modelData === "Song") return (root.sleepMode === "song") ? root.accent : root.muted
                        return root.muted
                      }
                      Text {
                        id: sleepChip
                        anchors.centerIn: parent
                        text: modelData === "Off" ? "Off" : (modelData === "Song" ? "Song" : modelData + "m")
                        color: {
                          if (modelData === "Off") return (root.sleepMode === "") ? root.onAccent : root.ink
                          if (modelData === "Song") return (root.sleepMode === "song") ? root.onAccent : root.ink
                          return root.ink
                        }
                        font.family: root.uiFont
                        font.pixelSize: Style.font.caption
                      }
                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                          if (modelData === "Off") root.setSleep("off")
                          else if (modelData === "Song") root.setSleep("song")
                          else root.setSleep(Number(modelData))
                        }
                      }
                    }
                  }
                }
                Text {
                  anchors.right: parent.right
                  anchors.verticalCenter: parent.verticalCenter
                  text: root.sleepMode === "" ? "" : ("⏾ " + root.sleepLabel())
                  color: root.accent
                  font.family: root.uiFont
                  font.pixelSize: Style.font.caption
                }
              }

              Text { text: "Storage"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              SettingRow {
                title: "Clear caches"
                desc: "Search + stream URLs (lyrics kept 30d)"
                control: SettingBtn {
                  label: "Clear"
                  tapped: function() {
                    root.runCmd(["cache-clear"])
                    root.notice = "Caches cleared"
                    noticeTimer.restart()
                  }
                }
              }

              Text { text: "Updates"; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; topPadding: Style.space(8) }

              Text {
                width: parent.width
                text: root.updateChecking ? "Checking..." : root.updateStatusText
                textFormat: Text.PlainText
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
              }

              SettingRow {
                title: "Auto-apply updates"
                desc: "Apply when a background check finds one"
                control: SettingToggle {
                  on: root.updateAuto
                  flipped: function() { root.setUpdateAuto(!root.updateAuto) }
                }
              }

              Text {
                width: parent.width
                text: "DSP toggles apply from the next track (mpv args are launch-time). Everything here is stored locally — nothing ever needs a login."
                color: root.muted
                font.family: root.uiFont
                font.pixelSize: Style.font.caption
                wrapMode: Text.WordWrap
                topPadding: Style.space(6)
              }
            }
          }
        }

        Text {
          width: parent.width
          height: visible ? parent.height - y - Style.space(18) : 0
          visible: tracks.count === 0 && !root.searching && root.tabIndex !== 0 && root.tabIndex !== 6 && root.tabIndex !== 7
          textFormat: Text.PlainText
          lineHeight: 1.35
          opacity: visible ? 1 : 0
          Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
          text: {
            if (root.tabIndex === 1) return "Search for something worth hearing\nResults build a mix station - no login needed"
            if (root.tabIndex === 2) return "Queue is empty - play something from Find\nYour picks line up here"
            if (root.tabIndex === 3) return playlists.count > 0 ? "Pick a list, or import a YouTube playlist above\nPaste a link in the import box to begin" : "Create a list, or import a YouTube playlist above\nUse + Create or paste a link above"
            if (root.tabIndex === 4) return "Nothing loved yet - press the heart icon on any track\nSaved songs live here"
            return "No downloads yet - press the download icon on any track\nOffline opus files are listed here"
          }
          color: root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
        }

        // Bottom bar: version bottom-left, credit bottom-center (kept short so
        // the two can never overlap — the v1.2 footer-collision report).
        // Update cluster lives here (compact): version + check icon + short
        // status; Update replaces status when available so the left cluster
        // never reaches the centered credit. Height stays 18.
        Item {
          width: parent.width
          height: Style.space(18)
          Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(4)
            width: Math.min(implicitWidth, Style.space(150))
            clip: true
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.appVersion
              color: root.muted
              opacity: 0.7
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
            }
            TransportBtn {
              glyph: "\u21bb"
              btnSize: Style.space(18)
              tip: "Check for updates"
              visible: !root.updateChecking && !root.updateAvailable
              tapped: function() { root.checkUpdates(true) }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.footerUpdateStatus()
              visible: !root.updateAvailable
              textFormat: Text.PlainText
              color: root.muted
              opacity: 0.7
              font.family: root.uiFont
              font.pixelSize: Style.font.caption
              width: Math.min(implicitWidth, Style.space(72))
              elide: Text.ElideRight
            }
            SettingBtn {
              label: "Update"
              visible: root.updateAvailable && !root.updateChecking
              height: Style.space(18)
              hPad: 12
              tapped: function() { root.applyUpdate(true) }
            }
          }
          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "♥ itsdotdev · fork"
            color: root.muted
            opacity: 0.7
            font.family: root.uiFont
            font.pixelSize: Style.font.caption
          }
        }
      }
    }
  }

  // ---- settings controls ---------------------------------------------------------
  component SettingRow: Item {
    property string title: ""
    property string desc: ""
    property Component control
    width: parent.width
    height: Style.space(46)
    Column {
      anchors.left: parent.left
      anchors.right: controlLoader.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(1)
      Text {
        width: parent.width
        text: title
        textFormat: Text.PlainText
        color: root.ink
        font.family: root.uiFont
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
      Text {
        width: parent.width
        text: desc
        textFormat: Text.PlainText
        color: root.muted
        font.family: root.uiFont
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
    Loader {
      id: controlLoader
      sourceComponent: control
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
  }

  component SettingToggle: Rectangle {
    id: stog
    property bool on: false
    property var flipped
    width: Style.space(42)
    height: Style.space(23)
    radius: height / 2
    color: stog.on ? root.accent : "transparent"
    border.width: 1
    border.color: stog.on ? root.accent : root.muted
    Behavior on color { ColorAnimation { duration: 140 } }
    Rectangle {
      width: Style.space(15)
      height: width
      radius: width / 2
      x: stog.on ? parent.width - width - Style.space(4) : Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      color: stog.on ? root.onAccent : root.muted
      Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }
    MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: if (stog.flipped) stog.flipped() }
  }

  component SettingStepper: Row {
    id: sstep
    property string label: ""
    property real step: 1
    property real value: 0
    property var changed
    spacing: Style.space(6)
    TransportBtn {
      glyph: "−"
      btnSize: Style.space(24)
      tapped: function() { if (sstep.changed) sstep.changed(sstep.value - sstep.step) }
    }
    Text {
      width: Style.space(52)
      horizontalAlignment: Text.AlignHCenter
      anchors.verticalCenter: parent.verticalCenter
      text: sstep.label
      color: root.ink
      font.family: root.uiFont
      font.pixelSize: Style.font.bodySmall
    }
    TransportBtn {
      glyph: "+"
      btnSize: Style.space(24)
      tapped: function() { if (sstep.changed) sstep.changed(sstep.value + sstep.step) }
    }
  }

  component SettingCycle: Rectangle {
    id: cyc
    property var options: []
    property var labels: []
    property var current
    property var picked
    readonly property int idx: {
      for (var i = 0; i < options.length; i++) {
        if (String(options[i]) === String(current)) return i
      }
      return 0
    }
    readonly property string shown: {
      if (labels && idx < labels.length && labels[idx] !== undefined) return String(labels[idx])
      if (idx < options.length) return String(options[idx])
      return ""
    }
    width: cycLabel.width + Style.space(22)
    height: Style.space(26)
    radius: height / 2
    color: "transparent"
    border.width: 1
    border.color: cycHover.containsMouse ? root.accent : root.muted
    transformOrigin: Item.Center
    scale: cycHover.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Text {
      id: cycLabel
      anchors.centerIn: parent
      text: cyc.shown
      color: cycHover.containsMouse ? root.accent : root.ink
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.bold: true
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    MouseArea {
      id: cycHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: {
        if (!options || options.length === 0 || !cyc.picked) return
        var next = options[(cyc.idx + 1) % options.length]
        cyc.picked(next)
      }
    }
  }

  component SettingBtn: Rectangle {
    id: sbtn
    property string label: "Go"
    property var tapped
    property int hPad: 22
    width: sbtnLabel.width + Style.space(hPad)
    height: Style.space(26)
    radius: height / 2
    color: sbtnHover.containsMouse ? root.accent : "transparent"
    border.width: 1
    border.color: root.accent
    transformOrigin: Item.Center
    scale: sbtnHover.pressed ? 0.96 : 1.0
    Behavior on color { ColorAnimation { duration: 120 } }
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
    Behavior on border.color { ColorAnimation { duration: 120 } }
    Text {
      id: sbtnLabel
      anchors.centerIn: parent
      text: sbtn.label
      color: sbtnHover.containsMouse ? root.onAccent : root.accent
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.bold: true
      Behavior on color { ColorAnimation { duration: 120 } }
    }
    MouseArea {
      id: sbtnHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (sbtn.tapped) sbtn.tapped()
    }
  }

  // Vertical center-zero EQ slider with drag. 0 dB sits mid-groove.
  component EqSlider: Column {
    id: eqs
    property string band: ""
    property real gain: 0 // -12..12
    property var changed
    spacing: Style.space(2)
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: (eqs.gain > 0 ? "+" : "") + (Math.round(eqs.gain * 2) / 2)
      color: eqs.gain !== 0 ? root.accent : root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
      font.bold: eqs.gain !== 0
    }
    Item {
      id: groove
      width: Style.space(30)
      height: Style.space(72)
      anchors.horizontalCenter: parent.horizontalCenter
      Rectangle {
        anchors.centerIn: parent
        width: Style.space(4)
        height: parent.height
        radius: width / 2
        color: root.raised
      }
      // zero line
      Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(10)
        height: 1
        color: root.muted
      }
      // fill from center to value
      Rectangle {
        width: Style.space(4)
        radius: width / 2
        color: root.accent
        anchors.horizontalCenter: parent.horizontalCenter
        y: eqs.gain >= 0 ? (parent.height / 2 - height) : (parent.height / 2)
        height: Math.abs(eqs.gain) / 12 * (parent.height / 2)
      }
      // handle
      Rectangle {
        width: Style.space(12)
        height: Style.space(12)
        radius: width / 2
        color: (eqHandle.containsMouse || eqHandle.pressed) ? root.accent : root.ink
        border.width: 1
        border.color: root.accent
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 - eqs.gain / 12 * (parent.height / 2) - height / 2
        transformOrigin: Item.Center
        scale: (eqHandle.containsMouse || eqHandle.pressed) ? 1.3 : 1.0
        Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 120 } }
      }
      MouseArea {
        id: eqHandle
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onPressed: function(mouse) { eqs.scrub(mouse.y) }
        onPositionChanged: function(mouse) { if (pressed) eqs.scrub(mouse.y) }
        onDoubleClicked: function() { if (eqs.changed) eqs.changed(0) }
      }
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: eqs.band
      color: root.muted
      font.family: root.uiFont
      font.pixelSize: Style.font.caption
    }

    function scrub(y) {
      var h = groove.height
      var v = (0.5 - Math.max(0, Math.min(1, y / h))) * 24
      if (changed) changed(Math.round(v * 2) / 2)
    }
  }

  component TransportBtn: Rectangle {
    id: tbtn
    required property string glyph
    property bool primary: false
    property bool large: false
    property bool small: false
    property bool active: false
    property string tip: ""
    property var tapped
    property int btnSize: Style.space(34)
    width: btnSize
    height: btnSize
    radius: btnSize / 2
    transformOrigin: Item.Center
    scale: btnHover.pressed ? 0.9 : (btnHover.containsMouse ? 1.07 : 1.0)
    color: primary
      ? (btnHover.containsMouse ? root.accent : "transparent")
      : (btnHover.containsMouse ? root.raised : "transparent")
    border.width: (primary || active) ? 2 : 1
    border.color: primary ? root.accent : (active ? root.accent : (btnHover.containsMouse ? root.ink : root.muted))
    Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on border.color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Text {
      anchors.centerIn: parent
      text: tbtn.glyph
      color: (tbtn.primary && btnHover.containsMouse) ? root.onAccent : (tbtn.active ? root.accent : root.ink)
      font.family: root.iconFont
      font.pixelSize: tbtn.large ? Style.font.iconLarge : Style.font.bodySmall
      Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    }
    MouseArea {
      id: btnHover
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: if (tbtn.tapped) tbtn.tapped()
    }
    InfoTip { watched: btnHover; tipText: tbtn.tip; delayMs: root.helpMode ? 3000 : 5000 }
  }

  component HomeRow: Rectangle {
    id: homeRow
    required property int index
    required property string title
    required property string artist
    required property string art
    required property string url
    required property string kind
    required property string reason
    readonly property bool isRadio: kind === "radio"
    width: ListView.view ? ListView.view.width : 0
    height: reason !== "" ? Style.space(62) : Style.space(48)
    radius: Style.space(7)
    color: homeArea.containsMouse ? root.raised : "transparent"
    Behavior on color { ColorAnimation { duration: 120 } }

    Row {
      z: 2
      anchors.fill: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(7)

      Rectangle {
        width: Style.space(38)
        height: width
        radius: Style.space(5)
        color: root.raised
        clip: true
        anchors.verticalCenter: parent.verticalCenter
        Image { anchors.fill: parent; source: homeRow.art; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
        Text {
          anchors.centerIn: parent
          visible: homeRow.art === ""
          text: homeRow.isRadio ? "((•))" : "♪"
          color: root.muted
          font.family: root.iconFont
          font.pixelSize: Style.font.bodySmall
        }
      }

      Column {
        width: parent.width - Style.space(38) - (homeRow.isRadio ? Style.space(40) : Style.space(76)) - parent.spacing * 2
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text { width: parent.width; text: homeRow.title; textFormat: Text.PlainText; color: root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: true; elide: Text.ElideRight }
        Text {
          width: parent.width
          text: (homeRow.artist ? homeRow.artist + " · " : "") + (homeRow.isRadio ? "live radio" : "30s preview + full track")
          textFormat: Text.PlainText
          color: homeRow.isRadio ? root.accent : root.muted
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          visible: homeRow.reason !== ""
          text: homeRow.reason
          textFormat: Text.PlainText
          color: root.muted
          opacity: 0.8
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      TransportBtn {
        glyph: "󰐊"
        btnSize: Style.space(30)
        small: true
        anchors.verticalCenter: parent.verticalCenter
        tip: homeRow.isRadio ? "Play station" : "Play"
        tapped: function() { root.playHome(homeRow.index) }
      }

      Rectangle {
        width: Style.space(34)
        height: Style.space(30)
        radius: height / 2
        color: "transparent"
        border.width: 1
        border.color: ytHover.containsMouse ? root.accent : root.muted
        anchors.verticalCenter: parent.verticalCenter
        visible: !homeRow.isRadio
        transformOrigin: Item.Center
        scale: ytHover.pressed ? 0.94 : 1.0
        Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutBack } }
        Behavior on border.color { ColorAnimation { duration: 120 } }
        Text {
          anchors.centerIn: parent
          text: "YT"
          color: ytHover.containsMouse ? root.accent : root.ink
          font.family: root.uiFont
          font.pixelSize: Style.font.caption
          font.bold: true
          Behavior on color { ColorAnimation { duration: 120 } }
        }
        MouseArea {
          id: ytHover
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            var r = homeRow
            root.ytSearchAndPlay(r.artist + " " + r.title)
          }
        }
        InfoTip { watched: ytHover; tipText: "Full version on YouTube"; delayMs: root.helpMode ? 3000 : 5000 }
      }
    }

    MouseArea {
      id: homeArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.playHome(homeRow.index)
    }
  }

  component TrackRow: Rectangle {
    id: trackRow
    required property int index
    required property string title
    required property string artist
    required property string duration
    required property bool isLive
    required property string thumbnail
    required property string videoId
    required property string url
    width: ListView.view ? ListView.view.width : 0
    height: Style.space(46)
    opacity: (root.queueAligned && index < root.currentIndex) ? 0.45 : 1
    radius: Style.space(7)
    readonly property bool rowHovered: trackArea.containsMouse || mixArea.containsMouse || saveArea.containsMouse || listArea.containsMouse || dlArea.containsMouse
    readonly property bool isCurrent: trackRow.videoId === root.currentVideoId
    color: index === root.selectedIndex ? root.raised : (rowHovered ? root.raised : "transparent")
    scale: trackArea.pressed ? 0.99 : 1.0
    transformOrigin: Item.Center
    Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }

    Row {
      z: 2 // above trackArea (declared later) so the hover buttons get clicks
      anchors.fill: parent
      anchors.leftMargin: Style.space(4)
      anchors.rightMargin: Style.space(6)
      spacing: Style.space(7)

      Rectangle {
        width: Style.space(36)
        height: width
        radius: Style.space(5)
        color: root.raised
        clip: true
        anchors.verticalCenter: parent.verticalCenter
        Image { anchors.fill: parent; source: trackRow.thumbnail; fillMode: Image.PreserveAspectCrop; asynchronous: true; opacity: status === Image.Ready ? 1 : 0; Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } } }
      }

      Column {
        width: parent.width - Style.space(36) - Style.space(88) - Style.space(26) - Style.space(34) - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(2)
        Text { width: parent.width; text: trackRow.title; textFormat: Text.PlainText; color: trackRow.isCurrent ? root.accent : root.ink; font.family: root.uiFont; font.pixelSize: Style.font.bodySmall; font.bold: trackRow.isCurrent; elide: Text.ElideRight }
        Text { width: parent.width; text: trackRow.artist; textFormat: Text.PlainText; color: root.muted; font.family: root.uiFont; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
      }

      // hover actions: mix · save · +list · download
      Item {
        width: Style.space(88)
        height: parent.height
        opacity: rowHovered ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        Row {
          id: hoverRow
          anchors.centerIn: parent
          spacing: Style.space(8)
          Text {
            text: "󰀃"; color: mixArea.containsMouse ? root.ink : root.muted; font.family: root.iconFont; font.pixelSize: Style.font.bodySmall
            scale: mixArea.containsMouse ? 1.12 : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            MouseArea { id: mixArea; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.startMix(trackRow.videoId) }
          }
          Text {
            text: "󰣐"; color: saveArea.containsMouse ? root.ink : root.muted; font.family: root.iconFont; font.pixelSize: Style.font.bodySmall
            scale: saveArea.containsMouse ? 1.12 : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            MouseArea { id: saveArea; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.saveTrack(trackRow.index) }
          }
          Text {
            text: "+"; color: root.addTargetPlaylist ? root.accent : (listArea.containsMouse ? root.ink : root.muted); font.family: root.iconFont; font.pixelSize: Style.font.bodySmall; font.bold: true
            scale: listArea.containsMouse ? 1.12 : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            MouseArea { id: listArea; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.addTrackToPlaylist(trackRow.index) }
          }
          Text {
            text: "󰇚"; color: dlArea.containsMouse ? root.ink : root.muted; font.family: root.iconFont; font.pixelSize: Style.font.bodySmall
            scale: dlArea.containsMouse ? 1.12 : 1.0
            transformOrigin: Item.Center
            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            MouseArea { id: dlArea; anchors.fill: parent; anchors.margins: -Style.space(4); hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.downloadTrack(trackRow.index) }
          }
        }
      }

      Text { width: Style.space(34); text: root.durationLabel(trackRow.duration, trackRow.isLive); textFormat: Text.PlainText; color: trackRow.isLive ? root.accent : root.muted; font.family: root.uiFont; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignRight; anchors.verticalCenter: parent.verticalCenter }

      // Live wave animation on the track that's on air.
      WaveBars {
        width: Style.space(22)
        height: parent.height
        anchors.verticalCenter: parent.verticalCenter
        visible: trackRow.isCurrent && root.playerRunning
        barColor: root.accent
        active: visible && root.playing
      }
    }

    MouseArea {
      id: trackArea
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: { root.selectedIndex = trackRow.index; root.selectTrack(trackRow.index) }
    }
  }
}

