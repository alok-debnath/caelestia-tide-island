# Keybinds and overlapping modules

This integration keeps **everything both shells ship**. Caelestia's launcher,
dashboard, sidebar, notification centre, OSD, lock and workspace overview all
stay live, and so do the island's equivalents. That is a deliberate choice —
this file is the map of what now exists twice, and how to reach each one.

Nothing here is applied automatically. The repo does not touch your Hyprland
config.

## What exists twice

| Feature | Caelestia | Island |
| --- | --- | --- |
| Notification popups | drawer, top-right | notch |
| Notification history | sidebar | `tide toggleNotificationCenter` |
| Volume / brightness OSD | drawer | notch |
| App launcher | `SUPER` (tap) | `tide toggleApplicationLauncher` |
| Control centre / quick settings | dashboard (left edge) | `tide toggleControlCenter` |
| Wallpaper picker | `caelestia wallpaper` | `tide toggleWallpaperPicker` |
| Workspace overview | drawer | `overview toggle` |
| Media controls | `mpris` IPC + media keys | notch player, `tide togglePlayer` |
| Clock | bar | notch |

Only the Caelestia side is bound to keys today. The island side is reachable
through IPC and unbound, so there are **no key conflicts** in the default
state — you get duplicate *UI surfaces*, not duplicate *shortcuts*.

Both notification stacks are fed by the same D-Bus service, so a single
notification renders in both places at once. That is the visible cost of this
configuration. If it grates, [Turning one side off](#turning-one-side-off).

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

## Turning one side off

Both are reversible, both are your call — the integration works either way.

**Island side.** Its modules are configured through Tide's own config, which
`tide-island-config-app` edits:

```sh
tide-island-config-app
```

**Caelestia side.** Its notification and OSD surfaces are QML, mounted from
`modules/drawers/`. Edit them in the fork and commit on `main`:

```sh
cd ~/.config/quickshell/caelestia
$EDITOR modules/drawers/Panels.qml     # drop the Notifications / Osd wrappers
git commit -am "overlay: island owns notifications and OSD"
```

Because the fork is a git repo, that edit survives the next
`caelestia-shell` update as a merge, and `git revert` puts it back.

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
