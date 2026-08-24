# Architecture

## The problem

[Caelestia](https://github.com/caelestia-dots/shell) and
[Tide Island](https://github.com/enhaoswen/Tide-island) are both *complete*
Quickshell configurations. Neither is a plugin for the other. Run them the
normal way and you get two independent Quickshell processes, two notification
daemons competing for `org.freedesktop.Notifications`, and two colour systems
that never agree.

## The shape of the fix

Tide Island's build is split in a way that makes real integration possible:

| Component | Installed to | Nature |
| --- | --- | --- |
| `IslandBackend` | `/usr/lib64/qt6/qml/IslandBackend` | Qt QML plugin (C++) |
| `libIslandBackend.so` | `/usr/lib64` | backing library |
| `shell.qml`, `DynamicIslandWindow.qml`, `qml/` | `/usr/share/tide-island` | plain QML |
| `lyricsmpris` | `/usr/share/tide-island/bin` | helper binary |

`/usr/lib64/qt6/qml` is already on Qt's default QML import path on Fedora, so
**any** QML application on the machine can `import IslandBackend` with no
environment setup. And `DynamicIslandWindow.qml` uses only *relative* directory
imports (`import "qml/island"`), which resolve against its own location — so it
works wherever it is imported from.

That means the island does not need to be vendored, forked, or rewritten. It
needs to be *instantiated* from inside Caelestia's process.

```
qs -c caelestia                       (one Quickshell process)
│
├── Background {}                     ┐
├── Drawers {}                        │  Caelestia, byte-identical
├── AreaPicker {}                     │  to the packaged tree
├── Lock {}                           │
├── ConfigToasts / Shortcuts / …      ┘
│
└── TideIsland {}                     ← overlay/caelestia/modules/island
    │
    ├── IpcHandler "island"           ← show / hide / toggle / auto-hide
    ├── IpcHandler "tide"             ← clock, lyrics, control centre, …
    ├── IpcHandler "overview"         ← Tide's workspace overview
    │
    └── Variants (per screen)
        └── Tide.DynamicIslandWindow  ← from file:/usr/share/tide-island
            └── qml/island, qml/controlcenter, qml/connectivity, qml/workspace
```

One process, one QML engine, one lifecycle. `caelestia shell -d` starts both.
A crash takes down both, which is the honest trade for the single process.

## Why the config lives in `~/.config`

Quickshell resolves a config *name* against `$XDG_CONFIG_HOME/quickshell/<name>`
first and `/etc/xdg/quickshell/<name>` second. Copying the packaged Caelestia
tree to `~/.config/quickshell/caelestia` shadows it with **no launcher change** —
`caelestia shell -d` and the `SUPER+R` reload keep working untouched.

That copy is a git repository with two branches:

- `upstream` — the pristine `/etc/xdg/quickshell/caelestia` tree, one commit per
  `caelestia-shell` package version, tagged `upstream/<version>`
- `main` — `upstream` plus this integration

A `caelestia-shell` package update is then an ordinary `git merge`, not a
re-fork. `scripts/apply-overlay.sh` performs both sides of that.

## What the overlay actually changes

Two files, and one of them is generated.

**`shell.qml`** — three lines, in `patches/caelestia/0001`:

```qml
//@ pragma DefaultEnv QUICKSHELL_LYRICS_BACKEND=/usr/share/tide-island/bin/lyricsmpris
import "modules/island"
    TideIsland {}
```

The `pragma` replaces the one job Tide's launcher script did that matters here:
telling the island where its lyrics helper lives. `TideIsland {}` is mounted
just before `ConfigToasts {}` so the island's layer surfaces stack above
Caelestia's drawers.

**`modules/island/TideIsland.qml`** — generated from Tide's own `shell.qml` by
`patches/tide-shell/0001`, a 13-line diff:

```qml
import "file:/usr/share/tide-island" as Tide   // added
...
-       DynamicIslandWindow {
+       Tide.DynamicIslandWindow {
```

Everything else — every IPC handler, every multi-monitor helper — is upstream's
code, unmodified. That is deliberate: when Tide changes its `shell.qml`,
`scripts/sync-upstream.sh` regenerates this file by re-applying the same 13-line
diff, and a conflict is a 13-line conflict rather than a 300-line one.

The 126 KB `DynamicIslandWindow.qml` and the 44-file `qml/` tree are **never**
copied into this repo. Upgrading the island is a reinstall, not a merge.

### Why `file:` and not a bare path

QML rejects bare absolute paths in directory imports:

```
"/usr/share/tide-island" is not a valid import URL. You can pass relative paths
or URLs with schema, but not absolute paths or resource paths.
```

So the import is `file:/usr/share/tide-island`. Quickshell's QML scanner logs
one cosmetic warning about it on startup:

```
WARN quickshell.qmlscanner: Ignoring unresolvable import
".../modules/island/file:/usr/share/tide-island" from ".../TideIsland.qml"
```

The scanner joins the path wrongly; the QML engine resolves it correctly and the
island loads. The warning is harmless. It is the price of not vendoring.

### Moving the dashboard out of the island's way

`patches/caelestia/0002`. Caelestia's dashboard was a top drawer, anchored
`horizontalCenter` + `top` and sliding down on `anchors.topMargin` — exactly
where the island now lives, so opening it unrolled the panel from behind the
notch. It is now a **left-edge drawer opened from the top left corner**, which
leaves the whole top edge to the island.

Four files, all in the config fork:

| File | Change |
| --- | --- |
| `modules/dashboard/Wrapper.qml` | slides on `anchors.leftMargin` instead of `topMargin`; content anchors `right` + `top` so it comes in horizontally from off-screen left |
| `modules/drawers/Panels.qml` | anchors the wrapper `left` + `top` |
| `modules/drawers/Regions.qml` | input region becomes a left strip instead of a top strip |
| `modules/drawers/Interactions.qml` | adds `inLeftCorner`, and the dashboard drag axis becomes horizontal |

The hit-testing is the only part with real logic in it. `inLeftCorner` is an
edge test bounded to the corner:

```qml
function inLeftCorner(panel: Item, x: real, y: real): bool {
    const panelWidth = panel.width * (1 - (panel.offsetScale ?? 0));
    const withinEdge = x < bar.implicitWidth + Math.max(Config.border.minThickness, Config.border.thickness + panelWidth);
    if (!withinEdge)
        return false;
    return y < borderThickness + Config.sidebar.minHoverThreshold || (panelWidth > 0 && withinPanelHeight(panel, x, y));
}
```

Two things worth noting:

- The corner bound reuses `Config.sidebar.minHoverThreshold`, which is what
  Caelestia already uses to bound the sidebar's **top right** corner. This is
  its mirror image, so the two corners stay the same size if that setting is
  changed.
- The `panelWidth > 0 && withinPanelHeight(...)` arm is what keeps the panel
  open once it is out. Without it the dashboard would close the moment the
  pointer left the corner box, making the panel unusable.

`panelWidth` folds in `offsetScale`, so a closed dashboard is reachable only
from the corner while an open one is held by its whole body.

### The notch

The island ships as a rounded pill floating a few pixels below the top edge —
correct for a Dynamic Island on its own, foreign inside Caelestia, where every
panel grows out of the screen border as one continuous surface.

Caelestia renders its chrome as signed-distance-field blobs: a `BlobGroup`
holds one `BlobInvertedRect` for the border plus a `BlobRect` per panel, and
the group's `smoothing` melts overlapping shapes together with concave joins.
That is what makes the dashboard and launcher look carved out of the border
rather than stuck onto it.

`patches/caelestia/0003` adds the island to that group:

```qml
BlobRect {
    id: islandBg

    readonly property var islandWindow: ShellState.componentsFor(root.screen)?.island ?? null
    readonly property Item capsule: islandWindow?.caelestiaCapsule ?? null

    group: blobGroup
    visible: !!capsule && capsule.opacity > 0.01
    x: (capsule?.x ?? 0) + bar.implicitWidth
    y: (capsule?.y ?? 0) + root.borderThickness
    implicitWidth: capsule?.width ?? 0
    implicitHeight: capsule?.height ?? 0
    radius: capsule?.radius ?? 0
    topLeftRadius: 0
    topRightRadius: 0
}
```

`BlobRect` exposes per-corner radii, so squaring off `topLeftRadius` and
`topRightRadius` is what turns a pill into a notch: it is flush with the border
above and rounded only where it meets the desktop below.

**This is the payoff of the single-process design.** The island lives in its own
layer-shell window, and the blob is drawn in Caelestia's drawers window — two
separate Wayland surfaces. Mirroring an animated geometry between them would be
impossible across two processes; inside one QML engine it is a property binding.
`radius` is bound to the capsule's own animated radius, so the island's morphs
(clock to player to notification to control centre) carry through to the blob,
and `BlobRect`'s spring physics smooth the rest.

The coordinate mapping is a coincidence worth stating, because it is load-bearing:

- the island's `PanelWindow` is `anchors { top; left; right }` with no margins,
  so Caelestia's own exclusion zones place its origin at exactly
  `(bar.implicitWidth, borderThickness)`;
- `islandContainer` inside it is `anchors.fill: parent`, so `mainCapsule.x/y`
  are already window-relative.

Together those mean the capsule's coordinates land in the same space `PanelBg`
already works in, and the `+ bar.implicitWidth` / `+ borderThickness` offsets
above are the same ones every other panel uses. If either fact changes upstream,
the notch will be offset and this is the first place to look.

On the island side, `patches/tide/0002` adds two properties to
`DynamicIslandWindow.qml`: `caelestiaCapsule`, exposing the capsule to mirror,
and `caelestiaBlobSurface`, which makes the capsule paint nothing so only
Caelestia's blob shows through. The same patch replaces the capsule's hardcoded
`Qt.rgba(0, 0, 0, ...)` fill with `StyleTokens.panel` — upstream painted the
island body black regardless of theme, which the colour bridge alone could not
reach.

Two settings cannot be patches, because they live in user config files rather
than the QML trees. `scripts/apply-config.sh` applies them idempotently:

| File | Key | Why |
| --- | --- | --- |
| `~/.config/caelestia/shell.json` | `osd.enabled = false` | volume and brightness render in the notch |
| `~/.config/tide-island/userconfig.json` | `islandTopMargin = 0` | the notch must sit flush for the blob to fuse with the border |

### Which shell owns notifications and OSD

The notch does. `patches/caelestia/0003` collapses Caelestia's popup stack in
`modules/notifications/Wrapper.qml` — the panel stays mounted, because `Panels`,
`Regions`, `ContentWindow` and the sidebar all anchor against its geometry, but
its `implicitHeight` is pinned to 0. Notification history in the sidebar is
unaffected: it reads the `Notifs` service directly rather than through the panel.

Tide has no per-module configuration — `UserConfigBackend`'s only booleans are
wallpaper and auto-hide related — so this direction is the one that can be done
without vendoring the island's window file. The reverse (Caelestia keeping
notifications, the island suppressed) would need to disable Tide's
`NotificationLayer` and `OsdLayer` in QML instead.

## Theming

Upstream Tide hardcodes an Apple-dark palette in `StyleTokensBackend`, with all
47 colour properties declared `CONSTANT`. `patches/tide/0001` rewrites that
class to read Caelestia's wallpaper-derived Material You scheme and repaint
live. See [THEMING.md](THEMING.md).

## IPC namespaces

Checked for collisions before mounting. Caelestia owns `audio`, `brightness`,
`drawers`, `gameMode`, `hypr`, `idleInhibitor`, `lock`, `mpris`, `nexus`,
`notifs`, `picker`, `toaster`, `wallpaper`. The island adds `island`, `tide`,
and `overview`. No overlap, and every one of them is now reachable through the
same instance:

```sh
qs ipc -c caelestia call island toggle
qs ipc -c caelestia call tide toggleControlCenter
qs ipc -c caelestia call drawers toggle dashboard    # still Caelestia's
```

Note the target is `-c caelestia`, not Tide's own instance. Anything in Tide's
documentation that says `quickshell -p /usr/share/tide-island ipc …` must be
rewritten this way.

## What is deliberately not done

Tide's `install.sh` is not used. It builds its own pinned Quickshell (v0.3.0)
when `/usr/bin/quickshell` is absent, and enables `tide-island.service`. Both
are wrong here: Caelestia already brings Quickshell (0.3.1 from the
`errornointernet/quickshell` COPR on Fedora), and a systemd service would start
a *second* island alongside the one inside Caelestia.
`scripts/build-tide.sh` uses upstream's CMake install rules directly and
actively disables that service if it finds it enabled.
