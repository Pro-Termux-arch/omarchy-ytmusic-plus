-- Load from ~/.config/hypr/bindings.lua with:
-- pcall(dofile, os.getenv("HOME") .. "/.config/omarchy/plugins/local.ytmusic-plus/hypr-bindings.lua")

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
