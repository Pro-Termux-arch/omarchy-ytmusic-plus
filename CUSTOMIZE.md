# YTMusic Plus — Agent Customization Guide

> Read this entire file before touching the codebase. It is written for
> autonomous agents: exact paths, contracts, invariants, and the commands
> that prove your change is safe. Precision over speed. Verify everything.

## 0. Ground truth (do not re-derive)

- Source of truth: `~/Projects/omarchy-ytmusic-plus/` — **NOT a git repo**.
  Edit files directly here. Never `git init` here.
- Publish repo (git, `master`): `~/Documents/Projects/Youtube Music Plus/`
  → `https://github.com/Pro-Termux-arch/omarchy-ytmusic-plus`.
- Live install: `~/.config/omarchy/plugins/local.ytmusic-plus/`.
  Plugin id `local.ytmusic-plus` — NEVER rename (bar layout + IPC depend on it).
- Test binary: `B=~/Projects/omarchy-ytmusic-plus/bin/ytmusic-plus`.
- Lyrics sync engine (lrclib duration match, 100ms phase-locked ticker,
  offsets, tap-to-seek) is SACRED: animation only, never timing.
- NEVER push/tag/commit-to-remote without explicit user approval.
- Screenshots only when the user asks.

## 1. File map (14 source files + this doc)

```
bin/ytmusic-plus   backend (bash): player, queue, DSP, discovery, updater
bin/ytviz          spectrum backend (python3, stdlib only)
BarWidget.qml      bar pill: poster, marquee, VizBars, transport, compact mode,
                   hover art card, popup loader, status/viz procs, IPC
Player.qml         popup player (~5900 lines): dock, transport, wave seekbar,
                   Home (Main/Top/Artist), lyrics, settings, updater UI
Marquee.qml        scrolling title      WaveBars.qml  idle EQ bars
InfoTip.qml        hover tooltip        VizBars.qml   spectrum bars
manifest.json  hypr-bindings.lua  README.md  LICENSE  CHANGELOG.md  Version.txt
```

## 2. Iron rules

1. **QML edits via python3 ONLY** (read, exact-substring replace with
   `count==1` assert, write back). NEVER Edit/Write tools on `*.qml` —
   the pipeline strips nerd-font glyphs. `.json/.md/.sh/.txt` may use edits.
    Glyph counts (PUA `0xE000–0xF8FF` + supp. `0xF0000–0xFFFFF`) MUST hold:
    **Player 14, BarWidget 4, others 0**. (Player was 15 until the v2.2.7
    mix-glyph deletion; BarWidget was 5 until the v2.3.4 canvas-icon swap —
    compact reuse goes through `String.fromCharCode()` to keep the count
    literal.)
   Count: `python3 -c` sum over ranges per file.
2. **Live reinstall is atomic, same filesystem ONLY**:
   `cp -r project plugins/.newplug && chmod +x .newplug/bin/* && rm -rf
   plugins/local.ytmusic-plus && mv .newplug local.ytmusic-plus`.
   Building from project (no `.git` there): also copy live `.git` +
   `preview.png` + `.gitignore` into `.newplug` first. NEVER `rm -rf + cp`.
3. **After ANY change**: `bash -n` backend, `omarchy plugin validate`,
   `qmllint` edited QML (IGNORE: `qs.*` imports, `unqualified-access`,
   `signal-handler-parameters`, single component-line error, BarWidget
   self-type cycle). Real parser = shell log:
   `journalctl --user --since "N minutes ago" | grep ytmusic | grep -v
   reloading` must be EMPTY (ignore `QQuickImage … Connection closed` —
   thumbnail refetch noise). Deeper errors: `/run/user/1000/quickshell/…`
4. **QML scope rule (journal-proven)**: child `id`s are scope-visible BARE
   (`homeModel.clear()`), NEVER as `root.<id>` (`root.homeModel` throws
   `TypeError` and kills the handler). `root.<property|function>` is fine.
   Re-audit with `\broot\.(\w+)` vs id/prop/func sets after every QML edit.
5. **Never disturb live state**: scratch `XDG_RUNTIME_DIR/XDG_DATA_HOME/
   XDG_CACHE_HOME` for tests, never kill mpv, never write live queue.json.
6. **Backend**: atomic writes (tmp + non-empty + `mv`), validate inputs,
   arg arrays only (never shell strings from remote data), yt-dlp URLs get
   `--` + https check, curl `-sS -m $CONNECT_TIMEOUT --proto '=https'
   --max-filesize`, timeouts on network calls.
7. **Versions**: stable releases ALWAYS bump all four: `manifest.json`
   (`"2.x.y"`), `Player.qml` `appVersion` (`"v2.x stable"`), `CHANGELOG.md`
   (count + top entry), `Version.txt`. Betas: `"2.x.y-beta"` /
   `"v2.x beta"`, ride `master` with NO tag. Stable tags `vX.Y.Z-stable`.

## 3. Theme / fonts / animation conventions

- Qt-proof bridge per file: `property var theme` + `tc(name,fb)` /
  `tc2(obj,key,fb)` + `Component.onCompleted` probe
  (`try{theme=ShellColor}catch; if(!theme)try{theme=Color}catch`).
  Zero direct `Color.*` (only stale comments). `Style.*` direct is correct.
  Text = `uiFont` (`customFontName` override), icons = `iconFont`.
- Motion spec: press 90–130ms OutBack/OutCubic, hover 130–180 OutCubic,
  fades ~150 OutCubic, slides 180–220 OutCubic, list add 170 / remove 130 /
  displaced 180. Every opacity/scale/color change gets a Behavior.
  Continuous motion (wave phase) uses `NumberAnimation` loops, never timers.
- Settings pattern: backend `set` whitelist + `SETTINGS_DEFAULTS` + QML
  load-parse (whitelist, safe default) + `saveSetting()` + control.
  BarWidget learns settings via `status` JSON fields (it has no settings
  proc): backend adds field at ALL status emissions, QML whitelists it.
  Current keys: `barmode full|compact`, `seekstyle
  default|lightning|dots|mirror|neon|blocks|gradient|ripple|stellar|comet|heartbeat`,
  `btnstyle classic|glow|soft`, `viz on|off`, `buffer
  saver|balanced|smooth`, `fullscreen on|off` (panel 987x610, normal
  377x610 — consecutive-Fibonacci frames via capped helpers; dock drops to
  bottom in Player).
- Golden-ratio frame (strict): free chrome constants use Fibonacci steps
  3/5/8/13/21/34/55/89/144/233; transport ladder 21:34:55; panel 377x610
  (610/377 = phi), fullscreen 987 wide (987/377 = phi^2). Derived sums
  (column-width formulas, icon reserves) and theme font tokens stay.
  Seek art: existing 9 styles pixel-frozen; new styles are born phi
  (comet tail 55, heartbeat unit 34, previews 76x34 in 89x55 cards).
- Home feed v3 (`foryou`): taste score = (plays + 3*loves)/(1+age_months)
  + recency bonus; strict artist match on taste rows (same predicate as
  follow rows); title normalization (`nt`: feat/live/remaster/video junk
  stripped) on exclusions, dedup keys and have-keys; live queue.json +
  state.json titles folded into exclusions; per-artist round-robin
  (2 each, then remainder), cap 20; cache 30min. Cold users get charts.
- v2.3.5 contracts: `mixtape [refresh]` → JSON array of queue items
  (videoId/title/artist/thumbnail/duration/isLive/url) resolved via the
  shared search cache (needs >=1 hit); QML `buildMixtape/fillMixtape` →
  `playAt(0)` with `listTitle` "Weekly Mixtape". `queue-insert JSON POS`
  (object + 11-char videoId validated, clamps, bumps STATE.index) +
  `queue-move FROM TO` (clamps, remaps STATE.index); TrackRow `>|` (play
  next, always) + `^`/`v` (queue mode only, ASCII-only icons + InfoTips);
  icon reserve derived: 110, 144 in queue mode. Bar mode UI:
  `barModeSetting` mirror + Appearance `SettingCycle` (no backend change —
  `status` already ships `.barMode`). Lyrics cascade v2: get-exact (raw,
  bare) → merged raw+bare search pool (dedup by id, synced-first,
  duration-scored) → NetEase direct → honest plain;   `has_ts` gate before
  any synced claim; cache key (artist/title/duration) + 100ms ticker
  untouched (still sacred).
- v2.3.6 contracts: hover intent — bar pill LAYOUT follows `hoverIntent`
  (100ms dwell via `hoverIntentTimer` + `onBarHoverChanged`; instant paint
  still follows `barHover`; transport/poster pressed states pin `barHover`
  so press-hold never collapses the pill). Footer: fullscreen popup
  987x700 (content needs it — 610 clips the footer), `bottomMargin` 0
  (dockBottomSlot is in-flow; a margin double-counts under card clip:true).
  `queue-reverse` verb (mirror of shuffle's own reverse path) + transport
  "Reverse" text button (caption, uiFont, zero font risk). `runCmd` takes
  optional `after` hook: playNext/moveTrack/reverseQueue pass
  "reload-queue"; mixtape is single-flight; fillMixtape validates +
  sanitizes before clearing and sets title after setTab. Sleep chips
  highlight remaining-derived minutes (`sleepMinutesLeft`, restart-proof).
  dl-get serializes on private `dl.lock` (global lock freed — status stays
  instant mid-download). All cache writes via `atomic_cache_put`
  (tmp+commit); merge tmps carry PID; queue-insert validates videoId + url
  scheme; jq filters use --argjson (no string interpolation).

## 4. HOWTO: add a seekbar style (key `mystyle`)

1. Backend `bin/ytmusic-plus`: extend `seekstyle)` alternation with
   `|mystyle`. Nothing else (style is presentation-only).
2. Player load whitelist (settings parse) + canvas fallback line: add
   `|| sst === "mystyle"` / `&& st !== "mystyle"` exactly like siblings.
3. Main `waveCanvas` onPaint: `if (st === "mystyle") { …; return }` using
   shared `ratio/splitX/dotR/live/playedCss/restCss/midY/w/h/phase`.
   Per-style live-stream rule: dim only, no dot. No `Math.random`
   per-frame (flicker); deterministic hashes only. Keep `seekRatio`,
   timer, hover logic untouched.
4. Picker: add `"mystyle"` to the Repeater model + one preview cell branch
   (`kind === "mystyle"`, static `splitX = 0.35*w`, `phase = 1.2`).
5. Validate: glyphs, qmllint, plugin validate; screenshot only if asked.

## 5. HOWTO: fonts / animations / bars / viz

- Fonts: presets row (label rendered in its own family) + `font-presets`
  backend cmd (`fc-list` exact-family resolution) + existing FileDialog →
  `font-install` → `customFont` → `uiFont`. Validate 1–128 chars.
- Animations: follow §3 spec; canvas phase via `NumberAnimation`, repaint
  on phase change; previews static (paint once).
- Bar modes (`full|compact`), visualizer (`viz on|off`), buffer profiles
  (`saver|balanced|smooth` → mpv demuxer knobs), `fullscreen` (panel size
  987x610 / 377x610 via BarWidget + dock-bottom layout in Player): all follow §3 settings
  pattern end to end.
- Updater contract: `update-check|update-apply [stable|beta]`;
  `UPDATE_CHECK local_version=.. local_sha=.. remote_sha=..
  available=yes/no/unknown channel=.. target=..`; VERSION GUARD: local
  manifest >= remote manifest (sort -V, fail open to SHA logic) forces
  `available=no` — never offer/apply a downgrade; dirty trees auto-stash;
  failures lead with a short line, detail after; rescan then verify, stale
  manual updates restart the shell, background ones show the copy box.
- Header logo: canvas pixel-art (5x7 bitmap tables, accent gradient
  shading, click particle burst+reform, 16ms timer gated on bursting).
  TransportBtn styles via `previewStyle` override (previews use
  `tapped: null`). Tooltips: fixed `delayMs: 1000` everywhere.

## 6. Pre-commit checklist (run all, paste outputs)

```
bash -n bin/ytmusic-plus && python3 -m py_compile bin/ytviz
qmllint <edited>.qml            # 0 Error lines
omarchy plugin validate .
python3 glyph-count              # Player 14, BarWidget 4, rest 0
grep root\.<id> audit → none
journalctl --user --since "5 minutes ago" | grep ytmusic | grep -v reloading  # empty
```
