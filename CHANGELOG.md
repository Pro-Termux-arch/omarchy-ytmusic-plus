# YTMusic Plus — Changelog

Updates so far: **6** (v1.0 stable → v1.1 beta → v1.2 beta → v1.4 stable → v1.5 beta → v1.6 stable → v1.7 stable)

When cutting a release, bump all three together:
`manifest.json` → `Player.qml` (`appVersion`) → this file.

## v1.7 stable (current)

- Track-row hover buttons no longer vanish under the cursor: new `rowHovered`
  state covers the row plus all four action buttons (Qt gives hover only to
  the topmost item, which used to kill the fade trigger); buttons also
  brighten + grow subtly on direct hover
- Lyrics readability fix: active line is crisp bright ink under a soft halo
  (was accent-on-accent floodlight) — slide/fade, breathing, dimming and
  sync timing unchanged
- Motion upgrade everywhere, behavior-identical: pill hover wash + accent
  border, transport halos with press-scale, play/pause glyph crossfade,
  VizBars left-to-right ripple, prime-staggered WaveBars shimmer, gliding
  dock indicator, card entrance, hover-growing EQ handles and seek knob

## v1.6 stable

> Promoted from v1.5 beta: per project rule, going stable always bumps the
> version. This is a security-hardening release — full word-by-word audit of
> backend + every QML file, no features, no sync-engine changes.

- Backend: bounded unplayable-track skip (no more unbounded yt-dlp recursion
  on dead queues), fail-closed state writes (corrupt input can no longer print
  false `saved` success), `cache-clear` dir guard, runtime dir `700`,
  validated `pl-remove` ids, duplicate cache-prune removed, lyric title trim
  without `xargs` mangling
- ytviz: monitor-id validation (numeric ids + `*.monitor` shape only), bounded
  5s reads (silent sinks can't hang the bar widget), zombie reaping, hostile
  pactl output rejected with fallback
- Player: IPC command gated on strict videoId (kills the one `bash -c`
  interpolation), thumbnail/stream URL allowlists (https only), plain-text
  rendering of all remote strings (no HTML/beacon injection), `[offset:]`
  clamped ±10s, NaN guards on seek paths, control/bidi character stripping
- Widgets: viz line-length cap, action whitelist, fail-safe status parse
  (stale `playing` impossible), marquee width/duration caps + plain text,
  VizBars NaN-height fix, tooltips width-capped + plain text

## v1.5 beta

- Phantom playing state fixed: stale mpv socket no longer sticks the transport
  on the pause glyph — `status` cleans the dead socket and reports
  `running:false`, and `toggle` re-syncs promptly (bar + popup fix at once)
- Visualizer revived: robust PipeWire monitor resolution (enumerates
  `pactl list short sources` for `*.monitor` first, numeric `--target`, clear
  stderr + non-zero exit when none), new `viz-test` one-command diagnosis,
  bar backoff (1.5s → 30s cap, resets on first bars); system mix by design,
  flat dim line when paused
- Lyrics animation redo (sync untouched): slide-up + fade on activation,
  breathing Glow (radius 8↔14, scale pulse dropped), distance dimming
  (1.0 / 0.85 / 0.6 / 0.35); auto-scroll-center, tap-to-seek, ±0.2s nudge,
  per-track offsets, `[offset:]` tags unchanged
- Progress bar: smooth 120ms fill, glowing accent knob on the head,
  hover 3px→5px thickening, pixel-perfect click/drag scrubbing, labels intact

## v1.4 stable

> Renamed from v1.3: per project rule, going stable always bumps the
> version, so the published stable is v1.4 (same content as the v1.3 beta).

- Settings that actually stick: fixed the status-poll merge race that reverted
  every change within a second; all state writes are now truncation-proof
- Home tab: free, legit, keyless discovery — Apple top charts, community
  radio (direct streams), iTunes tune search with 30s previews, one tap to
  the full YouTube track
- 10-band equalizer with 9 presets + custom sliders + reset (mpv launch DSP)
- Custom UI font picker (file manager → ttf/otf/woff/woff2/ttc → installed +
  applied, icons stay intact); system-font reset
- Real spectrum visualizer in the mini player (PipeWire monitor, stdlib-only
  Goertzel engine; idle pulse when nothing is capturable)
- Marquee titles (bar + now-playing), click/drag timeline scrubbing, dancing
  wave bars on the playing row
- Hover tooltips (5s dwell) on transport, dock, and icon buttons
- Tab renames (Playlist, Favourite, Local), variable-width dock fits all eight
- Footer overlap fixed; loop button says what it does ( Repeat: off/all/one )
- Bugfixes: stray-brace crashes (widget failed to load at all), lyric clock
  reset on track change, dock hover snap-back

## v1.2 beta

- Loop (off → all → one) + shuffle-upcoming transport buttons
- Settings tab (dock gear): skip silence, volume normalize, startup volume,
  repeat mode, lyric offset default + per-song reset, autoplay mix, search
  count, download quality, sleep timer (15/30/45/60 min / end-of-song / off),
  cache clearing — all persisted locally, no login
- Lyrics sync rework: exact-version fetch via duration matching, phase-locked
  interpolation clock, `[offset:]` tag support, per-track remembered offsets,
  live ±0.2s nudge, tap-to-seek
- Fixes: lyric clock reset on track change (no more runaway at song start),
  dock hover race (highlight no longer snaps back mid-hover), faster dock slide

## v1.1 beta

- Floating dock tabs with hover-follow highlight (Omarchy tokens, no glass)
- Lyrics tab: synced karaoke view via lrclib, accent glow + pulse on the
  active line, auto-scroll
- Credit footer (fork of omarchy-youtube-music by itsdotdev)
- Better transport buttons (hover fill, press scale)
- Download metadata stored, so Offline shows real titles

## v1.0 stable

- First release: login-free YouTube search + mix station, single-mpv IPC
  playback, local playlists (import/create/add/play), saved tracks, offline
  Opus downloads, yt-dlp → Invidious → Piped fallbacks, themed UI
