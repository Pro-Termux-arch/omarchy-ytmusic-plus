-- Load from ~/.config/hypr/bindings.lua with:
-- pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/local.ytmusic-plus/hypr-bindings.lua")

-- NOTE: legacy floating-window rule — the player is a layer-shell
-- KeyboardPanel popup (no standalone window) and mpv runs --no-video,
-- so this block never matches. Kept for reference; o.bind below is live.
o.window(
  { class = "^org.quickshell$", title = "^YTMusic Plus$" },
  {
    tag = "-default-opacity",
    float = true,
    size = { 410, 560 },
    move = { 10, 38 },
    rounding = 8,
    focus_on_activate = true,
    opacity = "0.98 0.98",
  }
)

o.bind(
  "SUPER + CTRL + SHIFT + M",
  "YTMusic Plus",
  "omarchy-shell shell toggle local.ytmusic-plus '{}'"
)
