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

`patches/caelestia/0002`. Caelestia's dashboard is anchored
`horizontalCenter` + `top`, which is exactly where the island now lives — open
the dashboard and it unrolls from behind the notch. The patch re-anchors it to
`left` + `top`.

Nothing else had to move. Both the pointer hit-testing in `Interactions.qml`
(`withinPanelWidth` -> `bar.implicitWidth + panel.x`) and the input regions in
`Regions.qml` (`x: panel.x + bar.implicitWidth`) are derived from `panel.x`, so
the hover and drag zones follow the anchor on their own.

The one addition is corner tolerance. `inBottomPanel` already took an
`isCorner` flag that widens the trigger by `Config.border.rounding` — that is
how the utilities panel is reachable in the bottom right corner. `inTopPanel`
had no such flag, so it gained the mirror of it, and the dashboard hover test
passes `true`:

```qml
function inTopPanel(panel: Item, x: real, y: real, isCorner = false): bool {
    ...
    return y < Math.max(...) + (isCorner ? Config.border.rounding : 0) && withinPanelWidth(panel, x, y);
}
```

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
