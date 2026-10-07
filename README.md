# YTMusic Plus for Omarchy

Privacy-first, login-free YouTube music player for the Omarchy bar.

- **Search** YouTube (songs, artists, albums) — no Google account, no cookies
- **Mix**: endless station from any track (YouTube Music-style "start radio")
- **Playlists**: import public YouTube playlists (URL or id) + local playlists
  (create, add, open, play) stored as JSON under `~/.local/share`
- **Saved tracks** (♥ library) with one-key save/unsave
- **Downloads**: offline Opus cache in `~/Music/ytmusic-plus/`; downloaded
  tracks play locally with zero network, and the resolver prefers them
- **Lyrics**: version-matched synced lyrics via lrclib (no key, no login) —
  the exact cut is picked by duration, the active line glows in your theme
  accent and follows the song on a phase-locked clock; per-song ± sync
  nudges are remembered, and tapping a line seeks to it
- **Loop & shuffle**: repeat off → all → one, plus shuffle-upcoming that
  keeps history and the playing song intact
- **Settings tab ( dock)**: skip-silence trim, volume normalization,
  startup volume, lyric offset default, autoplay-mix, search count, download
  quality, sleep timer (15/30/45/60 min or end-of-song), cache clearing —
  all persisted locally
- **Fallbacks**: search tries `yt-dlp → Invidious → Piped`; playback tries
  `local file → cached stream URL → yt-dlp (android client → web client)`;
  unplayable tracks auto-skip (capped, so a bad queue stops instead of racing)
- **Efficient**: single `mpv` instance over IPC, `flock`-serialized state,
  10-min search cache + 3-h stream-URL cache, debounced search input
- **Themed**: every surface uses `Color.*` / `Style.*` tokens — theme switches
  repaint the player, nothing is hardcoded

## Dependencies

`yt-dlp`, `mpv`, `socat`, `jq`, `curl` — all present on a standard Omarchy install.

## Install

```sh
omarchy plugin add https://github.com/Pro-Termux-arch/omarchy-ytmusic-plus.git --enable
```

Open it from the bar icon or directly:

```sh
omarchy-shell shell toggle local.ytmusic-plus '{}'
```

Optional shortcuts — add to `~/.config/hypr/bindings.lua`:

```lua
pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/local.ytmusic-plus/hypr-bindings.lua")
```

- `Super + Ctrl + Shift + M` toggles the player.

## Privacy notes

- Never signs in; never stores cookies (`yt-dlp --no-cookies --no-cache-dir`).
- No API keys, no telemetry, no scrobbling.
- Fallback metadata providers (Invidious/Piped) get only the search string
  over plain HTTPS GET, and only when yt-dlp search fails. Override them with:
  `YTMUSIC_INVIDIOUS="https://..."` / `YTMUSIC_PIPED="https://..."`.
- Lyrics come from lrclib (`https://lrclib.net`), which receives only the
  "artist + title (+ duration for exact matching)" query on cache miss
  (cached 30 days). No account, no key.
- The visualizer reads only the speaker-output monitor (never a microphone).
- Playback availability follows YouTube/`yt-dlp`: region-locked,
  age-restricted or account-only videos may not play — the player skips them.

## Security notes

- The UI never builds shell strings: every backend call passes arguments as
  an array. No `eval`, no command substitution on remote data.
- Every input is validated before use: YouTube ids (11 chars), playlist names
  (no slashes, so no path traversal), playlist URLs (https only), radio tags,
  numeric ranges, EQ gains, font extensions + 50 MB cap.
- State files are written atomically (temp + size-checked move), so a crash
  can never truncate your library, playlists, or settings.
- No remote content is ever executed: lyrics, charts, and search results are
  parsed as data (JSON/TSV) and rendered as plain text.

## Credits

♥ The mpv IPC transport, queue/mix engine and player-core concepts in this
plugin are a fork of
[omarchy-youtube-music](https://github.com/itsdotdev/omarchy-youtube-music)
by **itsdotdev** — thank you. YTMusic Plus builds on that core with playlists,
saved tracks, offline downloads, multi-source fallbacks, lyrics and a new UI.

## Data

| What | Where |
|---|---|
| Runtime (socket, queue, state) | `$XDG_RUNTIME_DIR/omarchy-ytmusic-plus/` |
| Saved tracks, playlists, download index | `~/.local/share/omarchy-ytmusic-plus/` |
| Search + stream caches | `~/.cache/omarchy-ytmusic-plus/` |
| Offline music (opus) | `~/Music/ytmusic-plus/` |

`ytmusic-plus cache-clear` wipes the cache only.

## License

MIT
