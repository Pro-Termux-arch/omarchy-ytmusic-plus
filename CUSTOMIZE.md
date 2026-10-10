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
Player.qml         popup player (~4700 lines): dock, transport, wave seekbar,
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
   **Player 14, BarWidget 5, others 0**. (Player was 15 until the v2.2.7
   mix-glyph deletion; BarWidget was 5 throughout — compact reuse goes
   through `String.fromCharCode()` to keep the count literal.)
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
  via BarWidget + dock-bottom layout in Player): all follow §3 settings
  pattern end to end.
- Updater contract: `update-check|update-apply [stable|beta]`;
  `UPDATE_CHECK local_version=.. local_sha=.. remote_sha=..
  available=yes/no/unknown channel=.. target=..`; dirty trees auto-stash;
  failures lead with a short line, detail after; rescan then verify, stale
  manual updates restart the shell, background ones show the copy box.

## 6. Pre-commit checklist (run all, paste outputs)

```
bash -n bin/ytmusic-plus && python3 -m py_compile bin/ytviz
qmllint <edited>.qml            # 0 Error lines
omarchy plugin validate .
python3 glyph-count              # Player 14, BarWidget 5, rest 0
grep root\.<id> audit → none
journalctl --user --since "5 minutes ago" | grep ytmusic | grep -v reloading  # empty
```
