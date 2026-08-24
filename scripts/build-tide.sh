#!/usr/bin/env bash
# Fetch Tide Island at the pinned revision, apply the patches in patches/tide,
# build, run the test suite, and install to $TIDE_ISLAND_PREFIX.
#
# Nothing from Tide's own install.sh is used: that script also builds its own
# Quickshell and enables a systemd user service, neither of which this
# integration wants. The upstream CMake install rules are used directly.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require git cmake ninja sudo

mkdir -p "$BUILD_DIR"

if [[ -d $TIDE_SRC/.git ]]; then
    log "fetching Tide Island"
    git -C "$TIDE_SRC" fetch --quiet origin
else
    log "cloning Tide Island"
    git clone --quiet "$TIDE_ISLAND_REPO" "$TIDE_SRC"
fi

log "checking out $TIDE_ISLAND_REV"
git -C "$TIDE_SRC" checkout --quiet --force "$TIDE_ISLAND_REV"
git -C "$TIDE_SRC" clean -qfd
git -C "$TIDE_SRC" reset --quiet --hard

for patch in "$REPO_ROOT"/patches/tide/*.patch; do
    [[ -e $patch ]] || continue
    apply_patch "$TIDE_SRC" "$patch"
done

log "configuring"
cmake -S "$TIDE_SRC" -B "$TIDE_SRC/build" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$TIDE_ISLAND_PREFIX"

log "building"
cmake --build "$TIDE_SRC/build" -j"$(nproc)"

log "testing"
ctest --test-dir "$TIDE_SRC/build" --output-on-failure

log "installing to $TIDE_ISLAND_PREFIX (needs sudo)"
sudo cmake --install "$TIDE_SRC/build"

# The island is hosted inside Caelestia's Quickshell process, so Tide's own
# service must stay disabled or there will be two islands on screen.
if systemctl --user is-enabled tide-island.service >/dev/null 2>&1; then
    warn "tide-island.service is enabled -- disabling it, the island runs inside Caelestia"
    systemctl --user disable --now tide-island.service
fi

log "done -- run scripts/apply-overlay.sh next"
