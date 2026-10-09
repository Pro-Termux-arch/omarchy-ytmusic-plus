# YTMusic Plus — Changelog

Updates so far: **17** (v1.0 stable → v1.1 beta → v1.2 beta → v1.4 stable → v1.5 beta → v1.6 stable → v1.7 stable → v1.8 beta → v1.9 beta → v2 stable → v2.1 stable → v2.1.1 stable → v2.1.2 stable → v2.1.3 stable → v2.1.4 stable → v2.1.5 stable → v2.1.6 stable → v2.1.7 stable)

When cutting a release, bump all three together:
`manifest.json` → `Player.qml` (`appVersion`) → this file.
Stable releases also get a tag: `vX.Y.Z-stable` (the stable update channel
tracks these tags; tag the release commit right after pushing).

## v2.1.7 stable (current)

> Updater test target: version bump only, no functional changes — update
> from v2.1.6 to exercise the restart box end to end.

## v2.1.6 stable

> Post-update restart box: when the UI is stale after an update, a slim
> banner shows `omarchy restart shell` in a selectable field with a Copy
> button (wl-copy, manual-select fallback). Hidden in normal work.

- Banner visible only when on-disk version differs from loaded UI,
  zero height otherwise — no layout shift
- Copy success → "Copied - paste in a terminal"; failure → text selected
  for manual Ctrl+C
- Manual updates no longer auto-restart; the box guides instead

## v2.1.5 stable

> Security sweep over the new updater paths (stash flow, restart command,
> version compare): fixed literals only, tracked-only stash, numeric epoch,
> no remote-to-shell flows. No flaws found, no functional changes.

## v2.1.4 stable

> Bar idle icon is a proper music note now (it was silverware — dinner
> is cancelled). Updater self-test release.

- Idle/collapsed bar glyph U+F04A3 (fork + knife) → U+F02CB (music note)
- No functional changes otherwise; exercises the self-finishing updater

## v2.1.3 stable

> Updates actually finish: after applying, the popup verifies the new UI
> really loaded — manual updates reload the shell automatically when stale,
> background updates ask for a restart instead of silently lagging.

- Stale-UI detector compares compiled appVersion against on-disk manifest
  (trailing-zero tolerant, so v2 == 2.0.0)
- Manual Update re-checks after 5s: fresh → "UI reloaded", stale →
  "Reloading shell..." + shell restart (apps stay open)
- Background auto-updates never surprise-restart: persistent notice names
  the version waiting for a restart

## v2.1.2 stable

> Test release: version bump only, no functional changes — exercises the
> smooth-update path (auto-stash, rescan, version flip) end to end.

## v2.1.1 stable

> Updates smooth for everyone: dirty trees auto-stash before updating and
> restore after — never blocked, never lost. Full error text on hover.

- Beta + stable update-apply stash local changes first, pop after success;
  pop conflicts keep the stash with recovery instructions
- Failure output leads with a short actionable line, full detail after
- Popup error shows full text on hover (was truncated); footer reflects
  failures instead of going stale

## v2.1 stable

> Updater --yes fix, cold-start play-button fix, footer clip, visualizer
> fast-start + smooth attack, animation masterpiece, double security pass.

- Beta updater appends --yes (was refusing without confirmation in popup)
- Play button on cold start resumes saved queue position (was dead no-op)
- Footer left cluster capped + clipped, Update button compacted (no credit overlap)
- Visualizer starts instantly: immediate trigger on play, ytviz fast monitor
  resolve + 8-frame ramp + attack smoothing (no 2s gap, no 0→100 pop)
- VizBars smooth attack/release + peak glow; WaveBars buttery prime-staggered
  shimmer; bar pill + transport + track rows polished
- Security revised twice: atomic writes, input validation, arg arrays,
  yt-dlp -- + https, curl --proto=https + caps — no flaws found

## v2 stable

> Promoted from v1.9 beta: cold-start off-by-one fix, footer updater with
> 30-min auto-checks, stable/beta channels — plus Qt-proofing for the
> Qt 6.11/6.12 theme breakage.

- Qt-proof theme bridge in every QML file: tries `ShellColor`, falls back to
  `Color`, falls back to hardcoded dark defaults — themed on old shells,
  working on new ones, usable even if both singletons are missing
- Updater lives in the footer now (version + check button + short status,
  no overlap); Update button appears when an update is available
- Dock tab pill renders on cold start (was 0-width until first hover)
- Cold-start N→N+1 fixed: expired stream cache is busted and recovered
  in place instead of skipping to the next song
- Stable/beta channels: stable follows `vX.Y.Z-stable` tags, beta follows
  the branch (opt-out via `update_last_check=off` or the toggle)

## v1.9 beta

- Cold-start off-by-one fixed: tapping the Nth song no longer plays N+1
- Updater moves to the footer: version + check button + status right there;
  auto-check every 30 min; stable/beta channels in Settings

## v1.8 beta

- Idle auto-collapse: the bar pill collapses to its icon 60s after playback
  stops (display-only — resume re-expands instantly, no new timers)
- Skip-silence fix: end-trim (`stop_periods`) was cutting songs at the first
  mid-track silence (skips + restarts) — now lead-in trim only
- Self-updater: SHA-precise `update-check`/`update-apply` backend commands
  (anti-hijack origin check) + Settings UI with 24h auto-check and opt-out
- Deep bug sweep: corrupt runtime files self-heal (no more wedged empty
  output), empty-queue stop cleans up properly, queue/shuffle/lib-save/sleep
  paths hardened against malformed input, queue view reloads after shuffle,
  dropped proc requests retry latest-wins, track-change lyric race fixed,
  correct per-list "on air" highlight, stale notice/error lines fixed,
  deferred popup-open race fixed, marquee offset reset on title change
- New: `song-link` (share URL) + `queue-clear` commands; elapsed/remaining
  time toggle; live volume stepper; queue position ("3 of 12"); richer empty
  states; import/create pills behave like real buttons
- Motion: list add/remove/displaced transitions, thumbnail fade-ins, tab
  crossfades, collapse/expand glide, staggered bar-button glows, marquee
  pause-on-hover, press ripples everywhere
- Lighter: mpv demuxer cache 50M→24M (still ~12 min of audio buffered);
  InfoTip rewritten binding-only (no Connections — removes the layer where a
  one-off shell SEGV was observed); no lingering helper processes
- Security: `dl-get` shell-string mover removed, mirror/curl flag-injection
  + size caps, cache disk-fill cap (200 MB), stream-cache atomicity, font
  validation tightened, ytviz SIGTERM orphan fixed, full remote-data re-audit

## v1.7 stable

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
