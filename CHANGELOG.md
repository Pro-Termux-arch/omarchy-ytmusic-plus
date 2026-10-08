# YTMusic Plus — Changelog

Updates so far: **3** (v1.0 stable → v1.1 beta → v1.2 beta → v1.4 stable)

When cutting a release, bump all three together:
`manifest.json` → `Player.qml` (`appVersion`) → this file.

## v1.4 stable (current)

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
