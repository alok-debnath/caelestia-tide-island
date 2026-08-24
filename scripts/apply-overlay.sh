#!/usr/bin/env bash
# Materialise the Caelestia config fork at $CAELESTIA_USER_CONFIG.
#
# Quickshell resolves a config name against $XDG_CONFIG_HOME first and
# /etc/xdg second, so a copy of the Caelestia tree under
# ~/.config/quickshell/caelestia shadows the packaged one with no launcher
# change: `caelestia shell -d` keeps working.
#
# That copy is a git repository with two branches:
#
#   upstream  the pristine /etc/xdg/quickshell/caelestia tree, one commit per
#             caelestia-shell package version, tagged upstream/<version>
#   main      upstream plus this integration's overlay
#
# Running this script again after a caelestia-shell update commits the new
# upstream tree and merges it into main, so a package update becomes an
# ordinary git merge instead of a re-fork. See docs/UPSTREAM-SYNC.md.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require git rsync

[[ -d $CAELESTIA_SYSTEM_CONFIG ]] \
    || die "$CAELESTIA_SYSTEM_CONFIG not found -- is caelestia-shell installed?"

[[ -f $TIDE_ISLAND_PREFIX/share/tide-island/DynamicIslandWindow.qml ]] \
    || die "Tide Island is not installed -- run scripts/build-tide.sh first"

first_run=0
if [[ ! -d $CAELESTIA_USER_CONFIG/.git ]]; then
    [[ ! -e $CAELESTIA_USER_CONFIG ]] \
        || die "$CAELESTIA_USER_CONFIG exists but is not a git repo -- move it aside first"
    first_run=1
    log "creating config fork at $CAELESTIA_USER_CONFIG"
    mkdir -p "$CAELESTIA_USER_CONFIG"
    git -C "$CAELESTIA_USER_CONFIG" init --quiet --initial-branch=upstream
    git -C "$CAELESTIA_USER_CONFIG" config user.name "$GIT_AUTHOR_IDENTITY_NAME"
    git -C "$CAELESTIA_USER_CONFIG" config user.email "$GIT_AUTHOR_IDENTITY_EMAIL"
fi

git -C "$CAELESTIA_USER_CONFIG" diff --quiet && git -C "$CAELESTIA_USER_CONFIG" diff --cached --quiet \
    || die "$CAELESTIA_USER_CONFIG has uncommitted changes -- commit or stash them first"

# --- refresh the upstream branch -------------------------------------------

version="$(caelestia_package_version)"
log "syncing upstream branch from $CAELESTIA_SYSTEM_CONFIG (caelestia-shell $version)"
# On a fresh init HEAD already points at the (unborn) upstream branch, and
# checking it out by name fails until it has its first commit.
[[ $first_run -eq 1 ]] || git -C "$CAELESTIA_USER_CONFIG" checkout --quiet upstream

# Everything except our own metadata is replaced wholesale, so files deleted
# upstream disappear here too.
rsync -a --delete \
    --exclude '.git/' \
    --exclude '.gitignore' \
    "$CAELESTIA_SYSTEM_CONFIG"/ "$CAELESTIA_USER_CONFIG"/

printf '*.qmlc\n*.jsc\n' > "$CAELESTIA_USER_CONFIG/.gitignore"

if [[ -n $(git -C "$CAELESTIA_USER_CONFIG" status --porcelain) ]]; then
    git -C "$CAELESTIA_USER_CONFIG" add -A
    git -C "$CAELESTIA_USER_CONFIG" commit --quiet \
        -m "caelestia-shell $version (pristine /etc/xdg tree)"
    git -C "$CAELESTIA_USER_CONFIG" tag -f "upstream/$version" >/dev/null
    log "recorded upstream/$version"
else
    log "upstream branch already current"
fi

# --- rebuild main -----------------------------------------------------------

if [[ $first_run -eq 1 ]]; then
    git -C "$CAELESTIA_USER_CONFIG" checkout --quiet -b main
    for patch in "$REPO_ROOT"/patches/caelestia/0002-*.patch; do
        [[ -e $patch ]] || continue
        apply_patch "$CAELESTIA_USER_CONFIG" "$patch"
    done
else
    git -C "$CAELESTIA_USER_CONFIG" checkout --quiet main
    log "merging upstream into main"
    git -C "$CAELESTIA_USER_CONFIG" merge --quiet --no-edit upstream \
        || die "merge conflict in the config fork -- resolve it in $CAELESTIA_USER_CONFIG, then re-run"
fi

# Files this integration owns outright are copied, not patched.
log "installing overlay files"
rsync -a "$REPO_ROOT/overlay/caelestia"/ "$CAELESTIA_USER_CONFIG"/

if [[ -n $(git -C "$CAELESTIA_USER_CONFIG" status --porcelain) ]]; then
    git -C "$CAELESTIA_USER_CONFIG" add -A
    git -C "$CAELESTIA_USER_CONFIG" commit --quiet \
        -m "overlay: host Tide Island inside the Caelestia shell root"
fi

log "done -- restart the shell with: caelestia shell -d"
