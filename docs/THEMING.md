# Theming

## What upstream does

Tide Island's colours live in `backend/StyleTokensBackend.cpp` as a fixed
Apple-dark palette — `#1c1c1e` surfaces, `#0a84ff` accent — exposed to QML as
the `StyleTokens` singleton. Every property is declared `CONSTANT`, so QML never
re-reads them and there is no hook to change them at runtime.

Caelestia derives a full Material You palette from the current wallpaper and
writes it to `~/.local/state/caelestia/scheme.json` on every wallpaper change:

```json
{
  "name": "dynamic", "mode": "dark", "variant": "tonalspot",
  "colours": {
    "background": "0b0f11", "surfaceContainer": "151a1e",
    "primary": "a7cbe7", "onSurface": "dfe6ee", "outline": "6f767d", …
  }
}
```

Note the values are bare `RRGGBB` — no leading `#`, no alpha.

## What the patch does

`patches/tide/0001-styletokens-caelestia-scheme.patch` rewrites
`StyleTokensBackend` to:

1. load that file at construction,
2. map M3 roles onto Tide's token names,
3. watch the file (and its directory) with `QFileSystemWatcher` and re-emit a
   single `schemeChanged` signal,
4. fall back to the exact upstream literal for any token whose role is missing.

Every themed property changes from `CONSTANT` to `NOTIFY schemeChanged`, so
QML bindings on `StyleTokens.*` update live — change the wallpaper and the
island repaints with the rest of the desktop.

The fallback is per-token, not all-or-nothing: a scheme missing `success` still
themes everything else and uses upstream's `#34c759` for that one token. With
no scheme file at all, the class behaves exactly like upstream.

Two properties are added for QML to introspect the bridge:

| Property | Meaning |
| --- | --- |
| `StyleTokens.schemeActive` | `true` when a Caelestia scheme is driving the tokens |
| `StyleTokens.schemeMode` | `"dark"` / `"light"` from the scheme, empty if inactive |

### Watching the directory as well as the file

The scheme file is replaced atomically (write + rename). That creates a new
inode, and an inotify watch on the old one goes dead after the first wallpaper
change. The patch therefore watches the containing directory too, and re-arms
both watches after every reload. Reloads are debounced 60 ms so the
write/rename burst produces one repaint, not three.

## Role mapping

`transparent`, `black`, `white` and `clearBlack` are structural and stay
`CONSTANT`. The rest map as follows.

### Surfaces

| Token | M3 role | Rationale |
| --- | --- | --- |
| `panel` | `surfaceContainerLowest` | the island body; darkest container keeps it reading as a notch cut out of the screen rather than a floating card |
| `module` | `surfaceContainer` | |
| `moduleHover` | `surfaceContainerHigh` | one step up is M3's own hover convention |
| `track` | `surfaceContainerHighest` | slider troughs |
| `cardFillActive` | `surfaceContainerHigh` | |
| `cardFillHover` | `surfaceContainer` | |
| `connectivityCard` | `surfaceVariant` | |
| `connectivityCardHover` | `surfaceBright` | |
| `prompt` | `surfaceContainerHigh` | |
| `input` | `surfaceContainerLow` | inputs sit *below* the surface they're on |
| `inputBorder` | `outlineVariant` | |
| `secondaryButton` | `surfaceVariant` | |

### Text

`onSurface` → `onSurfaceVariant` → `outline` is M3's own three-step emphasis
ramp, so this inverts correctly in light mode for free. Tide's nine text tokens
are finer-grained than M3's three and collapse onto them:

| Token | M3 role |
| --- | --- |
| `textPrimary` | `onSurface` |
| `textPrimaryBright` | `onBackground` |
| `textSecondary`, `textMuted`, `textSoft`, `textDim` | `onSurfaceVariant` |
| `textTertiary`, `textDisabled`, `textSubtle` | `outline` |

### Accents and status

| Token | M3 role |
| --- | --- |
| `accent` | `primary` |
| `accentPressed` | `primaryDim` |
| `accentSoft` | `onPrimaryContainer` |
| `success` | `success` (Caelestia extension) |
| `warning` | `yellow` (Caelestia extension) |
| `danger`, `error` | `error` |
| `disabledControl` | `outline` |
| `switchOff` | `surfaceContainerHighest` |

### Buttons

Pill buttons are a high-contrast fill *against* the island body, so they take
an on-surface colour rather than a surface one — which is also what makes them
flip correctly in light mode.

| Token | M3 role |
| --- | --- |
| `buttonFill` | `onSurface` |
| `buttonFillHover` | `inverseSurface` |
| `buttonFillPressed` | `onSurfaceVariant` |

### Overview and workspaces

These carry deliberate alpha in upstream. The patch keeps the alpha byte
exactly as upstream chose it and only swaps the RGB:

| Token | M3 role | Alpha |
| --- | --- | --- |
| `overviewCard` | `surfaceContainerLow` | `0xee` |
| `overviewBorder` | `outline` | `0x33` |
| `overviewInnerBorder` | `outline` | `0x12` |
| `workspaceCell` | `surfaceContainer` | `0xff` |
| `workspaceCellHover` | `surfaceContainerHigh` | `0xff` |
| `workspaceCellBorder` | `outlineVariant` | `0x1e` |
| `workspaceCellBorderHover` | `primary` | `0x66` |
| `workspaceOverlay` | `surfaceContainerLowest` | `0x42` |
| `workspaceOverlayHover` | `surfaceContainerLowest` | `0x28` |
| `workspaceActiveBorder` | `primary` | — |

Radii and animation durations are untouched. They are Tide's visual identity,
not Caelestia's.

## Environment overrides

| Variable | Effect |
| --- | --- |
| `TIDE_ISLAND_CAELESTIA_THEME=0` | disable the bridge entirely, use the stock Apple-dark palette |
| `TIDE_ISLAND_SCHEME_PATH=<path>` | read the scheme from somewhere else |

`XDG_STATE_HOME` is honoured when resolving the default path.

Set them where the shell is launched — for this setup, `~/.config/hypr` — or as
a `//@ pragma DefaultEnv` line in the fork's `shell.qml`.

## Tests

`tests/style_tokens_backend_tests.cpp` is added by the same patch and runs as
part of `ctest`. It covers the fallback path, role mapping, bare-`RRGGBB`
parsing, per-token fallback for missing roles, alpha preservation, live reload
on file change, and the kill switch:

```sh
make test
# or
ctest --test-dir .build/Tide-island/build --output-on-failure -R style_tokens
```

Run it after every `scripts/sync-upstream.sh`. If upstream adds a colour token,
the build still succeeds and the new token simply stays hardcoded — the test
will not catch that, so skim `StyleTokensBackend.h` in the upstream diff when
syncing.
