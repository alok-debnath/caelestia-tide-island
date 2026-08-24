#!/usr/bin/env bash
# Shared helpers. Sourced by the other scripts, not run directly.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# shellcheck disable=SC1091
source "$REPO_ROOT/VERSIONS"

: "${BUILD_DIR:=$REPO_ROOT/.build}"
: "${TIDE_SRC:=$BUILD_DIR/Tide-island}"
: "${CAELESTIA_SYSTEM_CONFIG:=/etc/xdg/quickshell/caelestia}"
: "${CAELESTIA_USER_CONFIG:=${XDG_CONFIG_HOME:-$HOME/.config}/quickshell/caelestia}"

GIT_AUTHOR_IDENTITY_NAME="Alok Debnath"
GIT_AUTHOR_IDENTITY_EMAIL="alokdebnath.in@gmail.com"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m warn\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31merror\033[0m %s\n' "$*" >&2; exit 1; }

require() {
    local missing=()
    local tool
    for tool in "$@"; do
        command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
    done
    [[ ${#missing[@]} -eq 0 ]] || die "missing required tools: ${missing[*]}"
}

# Patches are applied with git apply so the only hard dependency is git itself
# -- GNU patch is not installed on a default Fedora Workstation.
apply_patch() {
    local target_dir=$1 patch=$2
    if git -C "$target_dir" apply --reverse --check "$patch" >/dev/null 2>&1; then
        log "already applied: $(basename "$patch")"
        return 0
    fi
    git -C "$target_dir" apply "$patch" \
        || die "failed to apply $(basename "$patch") -- see docs/UPSTREAM-SYNC.md"
    log "applied: $(basename "$patch")"
}

caelestia_package_version() {
    rpm -q --qf '%{VERSION}-%{RELEASE}' caelestia-shell 2>/dev/null || echo unknown
}
