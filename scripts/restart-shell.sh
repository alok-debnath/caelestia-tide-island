#!/usr/bin/env bash
# Restart the Caelestia Quickshell instance so config changes take effect.
#
# Note the pkill pattern: matching on "qs -c caelestia" also matches the shell
# running this script, which kills the script mid-way. Match the process name
# exactly and filter on the argument list instead.

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

require pkill pgrep

if pgrep -u "$(id -u)" -x qs >/dev/null 2>&1; then
    log "stopping running shell"
    pkill -u "$(id -u)" -x qs || true

    for _ in $(seq 20); do
        pgrep -u "$(id -u)" -x qs >/dev/null 2>&1 || break
        sleep 0.25
    done
fi

log "starting caelestia shell"
setsid caelestia shell -d >/dev/null 2>&1 < /dev/null &

sleep 4
if pgrep -u "$(id -u)" -x qs >/dev/null 2>&1; then
    log "shell is up"
else
    die "shell did not start -- run 'caelestia shell' in a terminal to see the error"
fi
