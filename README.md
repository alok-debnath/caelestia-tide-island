# caelestia-tide-island

Run [Tide Island](https://github.com/enhaoswen/Tide-island) — a Dynamic
Island for Hyprland and niri — *inside*
[Caelestia](https://github.com/caelestia-dots/shell), as one Quickshell
process, themed by Caelestia's wallpaper-derived Material You colours.

Not two shells side by side. One shell, with the island mounted in it.

```
qs -c caelestia
├── Background / Drawers / AreaPicker / Lock / …   Caelestia, unmodified
└── TideIsland {}                                  ← the island
    └── Variants → Tide.DynamicIslandWindow        from /usr/share/tide-island
```

Built and used on Fedora 44 + Hyprland + Caelestia 2.3.0 + Quickshell 0.3.1.

## Why this exists

Caelestia and Tide Island are both *complete* Quickshell configurations, not
plugins. Installed the normal way you get two Quickshell processes, two
notification daemons fighting over `org.freedesktop.Notifications`, and an
island hardcoded to an Apple-dark palette (`#1c1c1e`, `#0a84ff`) that ignores
your wallpaper entirely.

This repo fixes both:

- **One process.** The island is mounted inside Caelestia's shell root.
  `caelestia shell -d` starts everything; `SUPER + R` reloads everything.
- **A real notch, not a pill.** The island is drawn by Caelestia's own blob
  renderer, so it grows out of the top border as one continuous surface with
  concave joins — square top corners, rounded bottom — instead of floating
  below it. Notifications and volume/brightness animate in it.
- **One colour system.** A patch to Tide's C++ makes `StyleTokens` read
  `~/.local/state/caelestia/scheme.json` and repaint live when the wallpaper
  changes.
- **Both upstreams stay pullable.** The island's 126 KB `DynamicIslandWindow.qml`
  and its 44-file `qml/` tree are never vendored here. The overlay is a 13-line
  diff plus a 3-line change to Caelestia's `shell.qml`.

## Install

Needs Caelestia and Quickshell already working.

```sh
git clone https://github.com/alok-debnath/caelestia-tide-island
cd caelestia-tide-island
make install
```

`make install` runs four steps, each also available on its own:

| Step | What it does |
| --- | --- |
| `make deps` | Fedora build + runtime packages |
| `make build` | clone Tide at the pinned revision, apply `patches/tide/`, build, `ctest`, install to `/usr` |
| `make overlay` | create the Caelestia config fork at `~/.config/quickshell/caelestia` and layer the island in |
| `make config` | apply the two settings that live in user config files rather than QML |
| `make restart` | restart the shell |

Nothing in your Hyprland config is touched, and Tide's `tide-island.service` is
left disabled on purpose — enabling it would start a *second* island next to
the one inside Caelestia.

### Verify

```sh
qs ipc -c caelestia call island toggle
```

The notch should appear at the top of the screen, in your wallpaper's colours.

One cosmetic warning on startup is expected and explained in
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md):

```
WARN quickshell.qmlscanner: Ignoring unresolvable import ".../file:/usr/share/tide-island"
```

## How the config fork works

Quickshell resolves a config name against `$XDG_CONFIG_HOME/quickshell/<name>`
before `/etc/xdg/quickshell/<name>`. So `make overlay` puts a copy of the
Caelestia tree at `~/.config/quickshell/caelestia`, which shadows the packaged
one with **no launcher change**.

That copy is a git repository:

| Branch | Contents |
| --- | --- |
| `upstream` | the pristine `/etc/xdg/quickshell/caelestia` tree, one commit per `caelestia-shell` version, tagged `upstream/<version>` |
| `main` | `upstream` plus this overlay |

After `dnf update caelestia-shell`, `make overlay` commits the new upstream tree
and merges it into `main`. A package update becomes an ordinary git merge, and
a bad one is a `git revert`.

## Usage

Everything is reachable through the Caelestia instance — note `-c caelestia`,
not Tide's own instance, which is what Tide's own docs assume:

```sh
qs ipc -c caelestia call island toggle
qs ipc -c caelestia call tide toggleControlCenter
qs ipc -c caelestia call tide showLyrics
qs ipc -c caelestia call overview toggle
qs ipc -c caelestia show                    # everything, Caelestia's targets too
```

One gotcha: `call island show` collides with the `qs ipc show` subcommand and
prints the target listing instead of calling anything. Use its alias,
`call island reveal`.

No keybinds are installed. [docs/KEYBINDS.md](docs/KEYBINDS.md) has a
copy-pasteable block for `hypr-user.lua`, plus the list of which features now
exist twice.

Island settings are edited with Tide's own configurator:

```sh
tide-island-config-app
```

## Theming

Caelestia writes a full Material You palette to
`~/.local/state/caelestia/scheme.json` on every wallpaper change.
`patches/tide/0001` rewrites `StyleTokensBackend` to read it, map M3 roles onto
Tide's 47 colour tokens, watch the file, and repaint live — with the upstream
Apple-dark value kept as a per-token fallback.

| Variable | Effect |
| --- | --- |
| `TIDE_ISLAND_CAELESTIA_THEME=0` | disable the bridge, use the stock palette |
| `TIDE_ISLAND_SCHEME_PATH=<path>` | read the scheme from elsewhere |

Full role-by-role mapping: [docs/THEMING.md](docs/THEMING.md).

## Keeping up with upstream

```sh
make sync      # move to the latest Tide revision, regenerate the overlay
git diff       # review
make build && make overlay && make restart
```

```sh
make overlay   # after a caelestia-shell package update
make restart
```

Both are designed to fail loudly and name the file to fix.
[docs/UPSTREAM-SYNC.md](docs/UPSTREAM-SYNC.md) covers conflict resolution for
each patch.

## Uninstall

```sh
scripts/uninstall.sh          # overlay only; Tide Island stays installed
scripts/uninstall.sh --all    # also remove Tide Island from /usr
```

The config fork is moved aside, never deleted, so its history survives.
Quickshell falls back to `/etc/xdg/quickshell/caelestia` immediately.

## Layout

```
patches/tide/       patches against Tide Island (theme bridge + tests, blob surface)
patches/tide-shell/ turns Tide's shell.qml into the overlay module (generator)
patches/caelestia/  patches applied to the Caelestia config fork
                    0001 mounts the island in shell.qml
                    0002 makes the dashboard a left-edge drawer
                    0003 draws the notch in the blob group, routes notifications
overlay/caelestia/  files copied verbatim into the config fork
scripts/            build, overlay, sync, restart, uninstall
docs/               architecture, theming, upstream sync, keybinds
VERSIONS            pinned upstream revisions
```

## Trade-offs, stated plainly

- **One process means one crash.** A fault in the island takes Caelestia down
  with it. `scripts/uninstall.sh` gets you back to stock in one command.
- **This configuration keeps every module both shells ship.** Notifications and
  OSD render in both the notch *and* Caelestia's drawers. That is a choice, not
  a bug — [docs/KEYBINDS.md](docs/KEYBINDS.md) lists what doubles and how to
  turn either side off.
- **The theme bridge is a patch, not an upstream feature.** It needs rebasing
  when Tide edits `StyleTokensBackend`. `make sync` tells you when.
- **Fedora-shaped.** `scripts/install-deps.sh` is `dnf`. Everything else is
  distro-agnostic; only the package names would change.

## Credits

[Tide Island](https://github.com/enhaoswen/Tide-island) by enhaoswen, and
[Caelestia](https://github.com/caelestia-dots/shell) by soramanew. This repo is
glue: it contains no code from either project except two small generated
patches.

## License

The glue in this repo is MIT. Tide Island and Caelestia keep their own licenses.
