#!/usr/bin/env bash
# Back out the integration and return to stock Caelestia.
#
# The config fork is moved aside rather than deleted, so its git history (and
# any of your own edits on top of it) survives. Quickshell falls back to
# /etc/xdg/quickshell/caelestia the moment the user copy is gone.
#
#   scripts/uninstall.sh            -- overlay only, leave Tide Island installed
#   scripts/uninstall.sh --all      -- also uninstall Tide Island from the prefix
#   scripts/uninstall.sh --yes ...  -- do not prompt

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

remove_tide=0
assume_yes=0
for arg in "$@"; do
    case $arg in
        --all) remove_tide=1 ;;
        --yes|-y) assume_yes=1 ;;
        *) die "unknown option: $arg" ;;
    esac
done

confirm() {
    [[ $assume_yes -eq 1 ]] && return 0
    read -r -p "$1 [y/N] " reply
    [[ $reply == [yY]* ]]
}

if [[ -d $CAELESTIA_USER_CONFIG ]]; then
    backup="$CAELESTIA_USER_CONFIG.disabled-$(date +%Y%m%d%H%M%S)"
    if confirm "Move $CAELESTIA_USER_CONFIG aside to $backup?"; then
        mv "$CAELESTIA_USER_CONFIG" "$backup"
        log "config fork moved to $backup"
    else
        log "left the config fork in place"
    fi
else
    log "no config fork at $CAELESTIA_USER_CONFIG"
fi

if [[ $remove_tide -eq 1 ]]; then
    manifest="$TIDE_SRC/build/install_manifest.txt"
    if [[ -f $manifest ]]; then
        if confirm "Remove every file listed in $manifest?"; then
            log "removing installed Tide Island files (needs sudo)"
            sudo xargs -r -a "$manifest" rm -f --
            sudo rm -rf "$TIDE_ISLAND_PREFIX/share/tide-island" \
                        "$TIDE_ISLAND_PREFIX/lib64/qt6/qml/IslandBackend"
        fi
    else
        warn "no install manifest at $manifest -- remove Tide Island by hand"
    fi
fi

log "done -- restart with: caelestia shell -d"
