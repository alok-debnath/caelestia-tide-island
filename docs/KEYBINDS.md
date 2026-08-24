# Keybinds and overlapping modules

This integration keeps **everything both shells ship**. Caelestia's launcher,
dashboard, sidebar, notification centre, OSD, lock and workspace overview all
stay live, and so do the island's equivalents. That is a deliberate choice —
this file is the map of what now exists twice, and how to reach each one.

Nothing here is applied automatically. The repo does not touch your Hyprland
config.

## What exists twice

The notch owns notifications and OSD; Caelestia keeps the rest.

| Feature | Rendered by |
| --- | --- |
| Notification popups | **notch** — Caelestia's stack is collapsed |
| Volume / brightness OSD | **notch** — `osd.enabled = false` in `shell.json` |
| Notification history | both: Caelestia's sidebar, and `tide toggleNotificationCenter` |
| App launcher | Caelestia (`SUPER`); the island's is unbound |
| Control centre | Caelestia's dashboard; the island's is unbound |
| Wallpaper picker | Caelestia; the island's is unbound |
| Workspace overview | Caelestia; the island's is unbound |
| Media controls | both: Caelestia's `mpris` IPC and media keys, and the notch player |
| Clock | both: the bar and the notch |

Everything marked *unbound* is dormant — the island ships it, but nothing
invokes it, because no keybind points at it. Tide has no per-module
configuration to disable them with (`UserConfigBackend`'s only booleans are
wallpaper and auto-hide related), so leaving them unbound is how they stay out
of the way.

Only the Caelestia side is bound to keys, so there are **no key conflicts** in
the default state.

## Island IPC reference

Every target lives in the Caelestia instance now — note `-c caelestia`, not
Tide's own instance:

```sh
qs ipc -c caelestia call island reveal   # not `show` -- see the note below
qs ipc -c caelestia call island hide
qs ipc -c caelestia call island toggle
qs ipc -c caelestia call island enableAutoHide
qs ipc -c caelestia call island disableAutoHide

qs ipc -c caelestia call tide showClock
qs ipc -c caelestia call tide showLyrics
qs ipc -c caelestia call tide showCustom
qs ipc -c caelestia call tide swipeLeft
qs ipc -c caelestia call tide swipeRight
qs ipc -c caelestia call tide togglePlayer
qs ipc -c caelestia call tide toggleControlCenter
qs ipc -c caelestia call tide toggleNotificationCenter
qs ipc -c caelestia call tide toggleWallpaperPicker
qs ipc -c caelestia call tide toggleApplicationLauncher
qs ipc -c caelestia call tide toggleFileShelf

qs ipc -c caelestia call overview toggle
qs ipc -c caelestia call overview open
qs ipc -c caelestia call overview close
```

`qs ipc -c caelestia show` lists everything, Caelestia's own targets included.

### `island show` is unreachable from the CLI

`show` is also a `qs ipc` subcommand, so the argument parser takes it before the
function name does:

```
$ qs ipc -c caelestia call island show
target island
  function hide(): void
  ...
```

It prints the target listing and exits 0 without calling anything. The handler
defines `open` and `reveal` as aliases of the same function — use either:

```sh
qs ipc -c caelestia call island reveal
```


## Caelestia binds already taken

From `~/.config/hypr/variables.lua` — avoid these when picking island binds:

| Bind | Action |
| --- | --- |
| `SUPER` (tap) | launcher |
| `SUPER + N` | sidebar |
| `SUPER + K` | show all panels |
| `SUPER + L` | lock |
| `SUPER + R` | reload shell |
| `SUPER + SHIFT + R` | reload shell, clear QML cache |
| `CTRL + ALT + Delete` | session menu |
| `CTRL + ALT + C` | clear notifications |

## Suggested island binds

Add to `~/.config/hypr/hypr-user.lua`, which survives `caelestia update`. These
sit on `SUPER + ALT` to stay clear of everything above:

```lua
local function island(target, method)
    return hl.dsp.exec_cmd(("qs ipc -c caelestia call %s %s"):format(target, method))
end

hl.bind("SUPER + ALT + I",   island("island", "toggle"))
hl.bind("SUPER + ALT + C",   island("tide", "toggleControlCenter"))
hl.bind("SUPER + ALT + N",   island("tide", "toggleNotificationCenter"))
hl.bind("SUPER + ALT + P",   island("tide", "togglePlayer"))
hl.bind("SUPER + ALT + Y",   island("tide", "showLyrics"))
hl.bind("SUPER + ALT + F",   island("tide", "toggleFileShelf"))
hl.bind("SUPER + ALT + Tab", island("overview", "toggle"))
```

`hl` is Caelestia's Hyprland config helper and is already in scope inside
`hypr-user.lua`. Rebinding a key does not replace an existing bind — call
`hl.unbind(key)` first if you are taking one over.

## What the notch does not do

Routing notifications and OSD to the notch is not a free swap. Measured against
what Caelestia's own panels did, these are the gaps:

| Gap | Detail |
| --- | --- |
| **Do Not Disturb is ignored** | The island learns about notifications by snooping the session bus with `dbus-monitor`, rather than by being the notification server. Caelestia is still the server and still honours `notifs toggleDnd` for its own panel and history, but the notch never sees the DND state and pops regardless. |
| **No app icons** | Every notification shows a generic bell. The snooped `Notify` call carries an icon, but the island does not render it. |
| **No actions** | Notifications with buttons show none, and `notifs.actionOnClick` has nothing to act on. The action still exists on Caelestia's side, reachable from the sidebar history. |
| **No urgency styling** | A `critical` notification looks identical to a low-priority one. |
| **Caelestia's expire settings do not apply** | `notifs.expire`, `defaultExpireTimeout` and `fullscreenExpireTimeout` govern Caelestia's panel; the notch uses its own timing. |
| **No microphone OSD** | Caelestia had one behind `osd.enableMicrophone`. Tide has no microphone support at all — no source volume, no mute state — so this is gone outright rather than merely unrouted. |

The first four all follow from the same root cause: the island observes
notifications instead of serving them. Fixing any of them properly means making
Tide a real notification client, which is upstream work, not integration work.

If these matter more than having notifications in the notch, hand them back —
see below.

## Turning the routing around

To give notifications and OSD back to Caelestia:

```sh
cd ~/.config/quickshell/caelestia
$EDITOR modules/notifications/Wrapper.qml   # popupsEnabled: true
git commit -am "overlay: caelestia owns notification popups"
```

and set `osd.enabled` back to `true` in `~/.config/caelestia/shell.json`. You
would then also want to suppress Tide's `NotificationLayer` and `OsdLayer`, or
both sides render again. That direction needs a patch against the island's own
window file, which this repo deliberately avoids vendoring.

## Dashboard is a left-edge drawer

Caelestia's dashboard no longer drops down from the top centre — the island
owns that space, and leaving the top edge alone keeps the island's own gestures
free. It now slides in horizontally from the left and is opened by hovering the
**top left corner**, just right of the bar. The rest of the left edge is inert.

Drag works too, and is horizontal now: press in the top left corner and drag
right past `dashboard.dragThreshold` to open, left to close.

`patches/caelestia/0002` carries the change; the hit-testing is explained in
[ARCHITECTURE.md](ARCHITECTURE.md).

## Exclusive zone

The island reserves screen space at the top (`islandExclusiveZone`, 45 px by
default). Caelestia's bar is vertical on the left, so the two do not fight over
the same edge — but if you move the bar to the top, set the island's exclusive
zone to `0` or the two exclusive zones stack and windows lose height twice.
