# Pulling changes from upstream

Two upstreams move independently:

| Upstream | Tracked by | Refreshed with |
| --- | --- | --- |
| Tide Island (git) | `TIDE_ISLAND_REV` in `VERSIONS` | `scripts/sync-upstream.sh` |
| Caelestia shell (Fedora package) | `upstream` branch in the config fork | `scripts/apply-overlay.sh` |

Neither is automatic. Both are designed to fail loudly and tell you which file
to look at.

## Caelestia shell updated

`dnf update caelestia-shell` rewrites `/etc/xdg/quickshell/caelestia`. Your
fork under `~/.config/quickshell/caelestia` shadows it, so nothing changes on
screen until you merge:

```sh
cd ~/src/caelestia-tide-island
make overlay
make restart
```

`apply-overlay.sh` checks out the fork's `upstream` branch, rsyncs the new
`/etc/xdg` tree over it (with `--delete`, so files dropped upstream disappear),
commits it as `caelestia-shell <version>`, tags `upstream/<version>`, then
merges that into `main`.

Three files can conflict, and only if upstream edited the same regions the
overlay touches: `shell.qml`, `modules/drawers/Panels.qml`, and
`modules/drawers/Interactions.qml`. Resolve like any merge:

```sh
cd ~/.config/quickshell/caelestia
git status                 # shows shell.qml unmerged
$EDITOR shell.qml          # keep both: upstream's change and TideIsland {}
git add shell.qml && git commit
```

Keep these three lines alive through any resolution:

```qml
//@ pragma DefaultEnv QUICKSHELL_LYRICS_BACKEND=/usr/share/tide-island/bin/lyricsmpris
import "modules/island"
    TideIsland {}
```

If the resolution changed shape, regenerate the repo's patch so the next fresh
install matches:

```sh
cd ~/.config/quickshell/caelestia
git diff upstream:shell.qml main:shell.qml > \
    ~/src/caelestia-tide-island/patches/caelestia/0001-host-tide-island-in-shell-root.patch
```

For the dashboard patch, what must survive is the `anchors.left` on the
`Dashboard.Wrapper` in `Panels.qml`, and the `isCorner` parameter on
`inTopPanel` in `Interactions.qml` together with the `true` the dashboard hover
test passes to it. If upstream ever adds its own dashboard-position option,
drop `patches/caelestia/0002` and use theirs instead.

### Rolling back a bad Caelestia update

The fork keeps every version:

```sh
cd ~/.config/quickshell/caelestia
git log --oneline upstream        # every packaged version, tagged
git revert <merge-commit>         # or: git reset --hard <good-commit>
```

## Tide Island updated

```sh
cd ~/src/caelestia-tide-island
make sync                    # or: scripts/sync-upstream.sh <rev>
git diff                     # review the regenerated overlay and the new pin
make build                   # builds, runs the tests, installs
make overlay && make restart
```

`sync-upstream.sh` checks out the new revision, re-applies
`patches/tide/*.patch`, regenerates
`overlay/caelestia/modules/island/TideIsland.qml` from the new upstream
`shell.qml`, and updates `VERSIONS`. It does not build or install — review
first.

### When `patches/tide/0001` stops applying

This is the patch that rewires `StyleTokensBackend` for Caelestia's colour
scheme. It rewrites both files nearly whole, so any upstream edit to them
conflicts.

```sh
cd .build/Tide-island
git apply --3way ../../patches/tide/0001-styletokens-caelestia-scheme.patch
# resolve conflict markers in backend/StyleTokensBackend.{h,cpp}
git diff > ../../patches/tide/0001-styletokens-caelestia-scheme.patch
```

What to preserve while resolving:

- every themed property stays `NOTIFY schemeChanged`, never `CONSTANT`
- new upstream tokens get a role in the mapping (see
  [THEMING.md](THEMING.md)) — otherwise they silently stay Apple-dark
- the upstream literal stays as each token's fallback argument
- `tests/style_tokens_backend_tests.cpp` and its `CMakeLists.txt` block survive

Then `make build`, which runs `ctest`.

### When `patches/tide-shell/0001` stops applying

This is the 13-line diff that turns Tide's `shell.qml` into the overlay module.
It only breaks if upstream reworks its own `shell.qml` imports or the
`Variants` block.

```sh
cd .build/Tide-island
git show HEAD:shell.qml > /tmp/shell.qml
cd /tmp && git init -q && git apply --3way \
    ~/src/caelestia-tide-island/patches/tide-shell/0001-tide-shell-as-caelestia-module.patch
# fix it up, then:
diff -u <(git -C ~/src/caelestia-tide-island/.build/Tide-island show HEAD:shell.qml) /tmp/shell.qml \
    > ~/src/caelestia-tide-island/patches/tide-shell/0001-tide-shell-as-caelestia-module.patch
```

The two edits it must always make:

1. add `import "file:/usr/share/tide-island" as Tide`
2. change `DynamicIslandWindow {` to `Tide.DynamicIslandWindow {`

## After any sync

```sh
qs ipc -c caelestia call island toggle          # island responds
qs ipc -c caelestia call tide toggleControlCenter
journalctl --user -e | grep -i quickshell       # or read the log path qs prints
```

Expect exactly one cosmetic warning on startup, explained in
[ARCHITECTURE.md](ARCHITECTURE.md):

```
WARN quickshell.qmlscanner: Ignoring unresolvable import ".../file:/usr/share/tide-island"
```

## Upstream bugs seen, not caused here

`DynamicIslandWindow.qml` binds `detailWidth: root.connectivityDetailWidth`,
but only `connectivityDetailHeight` and `connectivityDetailGap` are declared.
This logs two warnings on every start:

```
WARN scene: DynamicIslandWindow.qml[3017:13]: Unable to assign [undefined] to double
WARN scene: DynamicIslandWindow.qml[3035:13]: Unable to assign [undefined] to double
```

Present in stock Tide Island as well; the connectivity panel falls back to its
own default width. Harmless, and not something this integration should paper
over — it belongs upstream.
