#!/usr/bin/env bash
# Move to a newer Tide Island revision.
#
#   scripts/sync-upstream.sh              -- latest upstream default branch
#   scripts/sync-upstream.sh <rev>        -- a specific commit or tag
#
# What it does:
#   1. checks out the requested revision
#   2. re-applies patches/tide/*.patch, reporting exactly which one broke
#   3. regenerates overlay/caelestia/modules/island/TideIsland.qml from the new
#      upstream shell.qml via patches/tide-shell/0001
#   4. updates the pin in VERSIONS
#
# It deliberately does not build or install. Review the diff, then run
# scripts/build-tide.sh and scripts/apply-overlay.sh.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require git

target=${1:-}

mkdir -p "$BUILD_DIR"
if [[ -d $TIDE_SRC/.git ]]; then
    git -C "$TIDE_SRC" fetch --quiet origin
else
    git clone --quiet "$TIDE_ISLAND_REPO" "$TIDE_SRC"
fi

if [[ -z $target ]]; then
    target=$(git -C "$TIDE_SRC" rev-parse origin/HEAD 2>/dev/null) \
        || die "could not resolve origin/HEAD -- pass a revision explicitly"
fi

rev=$(git -C "$TIDE_SRC" rev-parse "$target^{commit}") \
    || die "unknown revision: $target"

if [[ $rev == "$TIDE_ISLAND_REV" ]]; then
    log "already pinned to $rev"
else
    log "moving pin $TIDE_ISLAND_REV -> $rev"
fi

git -C "$TIDE_SRC" checkout --quiet --force "$rev"
git -C "$TIDE_SRC" clean -qfd
git -C "$TIDE_SRC" reset --quiet --hard

log "re-applying Tide patches"
for patch in "$REPO_ROOT"/patches/tide/*.patch; do
    [[ -e $patch ]] || continue
    if ! git -C "$TIDE_SRC" apply --check "$patch" 2>/dev/null; then
        cat >&2 <<EOF

$(basename "$patch") no longer applies to $rev.

Rebase it by hand:
  cd $TIDE_SRC
  git apply --3way $patch     # resolve conflicts
  git diff > $patch

Then re-run this script. docs/UPSTREAM-SYNC.md has the details.
EOF
        exit 1
    fi
    git -C "$TIDE_SRC" apply "$patch"
    log "applied: $(basename "$patch")"
done

# --- regenerate the overlay module -----------------------------------------

log "regenerating overlay/caelestia/modules/island/TideIsland.qml"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

git -C "$TIDE_SRC" show "$rev:shell.qml" > "$work/shell.qml"
git -C "$work" init --quiet
git -C "$work" apply "$REPO_ROOT/patches/tide-shell/0001-tide-shell-as-caelestia-module.patch" \
    || die "patches/tide-shell/0001 no longer applies to Tide's shell.qml -- rebase it, see docs/UPSTREAM-SYNC.md"

install -Dm644 "$work/shell.qml" \
    "$REPO_ROOT/overlay/caelestia/modules/island/TideIsland.qml"

# --- update the pin ---------------------------------------------------------

sed -i "s|^TIDE_ISLAND_REV=.*|TIDE_ISLAND_REV=$rev|" "$REPO_ROOT/VERSIONS"
sed -i "s|^CAELESTIA_SHELL_VERSION=.*|CAELESTIA_SHELL_VERSION=$(rpm -q --qf '%{VERSION}' caelestia-shell 2>/dev/null || echo unknown)|" \
    "$REPO_ROOT/VERSIONS"

log "pins updated -- review 'git diff', then run scripts/build-tide.sh && scripts/apply-overlay.sh"
