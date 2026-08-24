#!/usr/bin/env bash
# Install the Fedora packages needed to build Tide Island and run the island.
#
# Quickshell itself is NOT installed here. It is expected to already be present
# because Caelestia depends on it (Fedora: the errornointernet/quickshell COPR).

source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

BUILD_PACKAGES=(
    cmake ninja-build gcc-c++ git pkgconf-pkg-config
    qt6-qtbase-devel qt6-qtbase-private-devel qt6-qtdeclarative-devel
    qt6-qtwayland-devel qt6-qt5compat qt6-qtshadertools-devel qt6-qtsvg-devel
    systemd-devel libdrm-devel wayland-devel
)

# Runtime helpers the island shells out to. Most are already pulled in by a
# normal Caelestia install; listed so a fresh machine gets them too.
RUNTIME_PACKAGES=(
    wireplumber pulseaudio-utils brightnessctl upower bluez polkit zenity
    NetworkManager
)

log "installing build and runtime packages"
sudo dnf install -y "${BUILD_PACKAGES[@]}" "${RUNTIME_PACKAGES[@]}"

command -v quickshell >/dev/null 2>&1 \
    || warn "quickshell not found -- install it before running the island"

log "done"
