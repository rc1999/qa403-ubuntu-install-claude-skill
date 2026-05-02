#!/usr/bin/env bash
# install-qa40x.sh — one-shot installer for QuantAsylum QA40x on Ubuntu.
#
# Performs the same steps as INSTALL.md, but state-detects each one and skips
# anything already in place. Safe to re-run.
#
# Usage:
#   scripts/install-qa40x.sh [--exe ~/Downloads/setup_QA40x_1.222.exe] [--skip-wine] [--no-mono-official] [--yes]
#
# Flags:
#   --exe PATH             Path to the QA40x Windows installer EXE. If given,
#                          the script runs it under Wine and copies the result
#                          out of the Wine prefix into ~/qa403/. Without this,
#                          the script stops after dependency install and tells
#                          you what to download next.
#   --skip-wine            Don't install Wine (use this if you'll copy
#                          ~/qa403/ from a Windows machine instead).
#   --no-mono-official     Use Ubuntu's stock mono-complete instead of the
#                          official Mono stable repo (slower 6.8.x, but no
#                          third-party apt source).
#   --yes / -y             Don't prompt for confirmation.
#
# Tested on Ubuntu 20.04 Focal and 24.04 Noble. Should work on 22.04 Jammy too.

set -euo pipefail

# -- Args --------------------------------------------------------------------
EXE=""
SKIP_WINE=0
USE_MONO_OFFICIAL=1
ASSUME_YES=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --exe) EXE="$2"; shift 2 ;;
        --skip-wine) SKIP_WINE=1; shift ;;
        --no-mono-official) USE_MONO_OFFICIAL=0; shift ;;
        -y|--yes) ASSUME_YES=1; shift ;;
        -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
        *) echo "unknown arg: $1" >&2; exit 2 ;;
    esac
done

# -- Helpers -----------------------------------------------------------------
log()  { printf "\033[1;36m==>\033[0m %s\n" "$*"; }
ok()   { printf "\033[1;32m  ✓\033[0m %s\n" "$*"; }
skip() { printf "\033[1;33m  ↷\033[0m %s (already present, skipping)\n" "$*"; }
warn() { printf "\033[1;33m  !\033[0m %s\n" "$*" >&2; }
die()  { printf "\033[1;31m  ✗\033[0m %s\n" "$*" >&2; exit 1; }

confirm() {
    [[ $ASSUME_YES -eq 1 ]] && return 0
    read -r -p "$1 [y/N] " ans
    [[ "$ans" =~ ^[Yy]$ ]]
}

need_sudo() {
    if [[ $EUID -eq 0 ]]; then return 0; fi
    if ! sudo -n true 2>/dev/null; then
        log "sudo password needed — you'll be prompted once and the rest is non-interactive"
        sudo -v || die "sudo authentication failed"
    fi
}

write_root_file() {
    # write_root_file <path> <content>
    local path="$1"; local content="$2"
    sudo tee "$path" > /dev/null <<<"$content"
}

# -- Sanity check ------------------------------------------------------------
log "Sanity check"
[[ "$(uname -s)" == "Linux" ]] || die "Not Linux"
[[ -f /etc/lsb-release ]] || die "Not Ubuntu/Debian (no /etc/lsb-release)"
. /etc/lsb-release
CODENAME="${DISTRIB_CODENAME:-unknown}"
ok "Distro: $DISTRIB_ID $DISTRIB_RELEASE ($CODENAME)"
case "$CODENAME" in
    focal|jammy|noble|oracular) ;;
    *) warn "Codename '$CODENAME' is not in the tested list (focal/jammy/noble/oracular). Continuing anyway." ;;
esac
[[ "$(uname -m)" == "x86_64" ]] || warn "Non-x86_64 arch ($(uname -m)) — Mono and Wine assume amd64"

# -- udev rules --------------------------------------------------------------
log "udev rules"
need_sudo
declare -A UDEV_RULES=(
    ["51-qa403.rules"]='SUBSYSTEM =="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e39", MODE="0666"'
    ["51-qa402.rules"]='SUBSYSTEM =="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e37", MODE="0666"'
    ["51-qa40xBootloader.rules"]='SUBSYSTEM =="usb", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="0022", MODE="0666"'
)
RULES_CHANGED=0
for f in "${!UDEV_RULES[@]}"; do
    if [[ -f /etc/udev/rules.d/$f ]]; then
        skip "/etc/udev/rules.d/$f"
    else
        write_root_file "/etc/udev/rules.d/$f" "${UDEV_RULES[$f]}"
        ok "wrote /etc/udev/rules.d/$f"
        RULES_CHANGED=1
    fi
done

# ModemManager blacklist
MM_BLACKLIST=/etc/udev/rules.d/77-mm-qa40x-blacklist.rules
if [[ -f $MM_BLACKLIST ]]; then
    skip "$MM_BLACKLIST"
else
    write_root_file "$MM_BLACKLIST" 'SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e39", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="16c0", ATTRS{idProduct}=="4e37", ENV{ID_MM_DEVICE_IGNORE}="1"
SUBSYSTEMS=="usb", ATTRS{idVendor}=="1fc9", ATTRS{idProduct}=="0022", ENV{ID_MM_DEVICE_IGNORE}="1"'
    ok "wrote $MM_BLACKLIST"
    RULES_CHANGED=1
fi

if [[ $RULES_CHANGED -eq 1 ]]; then
    sudo udevadm control --reload-rules
    ok "udev rules reloaded"
    warn "Unplug and re-plug the QA40x device for the new permissions to apply"
fi

# -- Mono --------------------------------------------------------------------
log "Mono"
if dpkg -s mono-complete >/dev/null 2>&1; then
    skip "mono-complete (version $(mono -V 2>&1 | head -1 | awk '{print $5}'))"
else
    if [[ $USE_MONO_OFFICIAL -eq 1 ]]; then
        log "  installing from Mono official stable repo (recommended — newer 6.12.x)"
        sudo apt-get install -y gnupg ca-certificates
        if [[ ! -f /etc/apt/sources.list.d/mono-official-stable.list ]]; then
            sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 \
                --recv-keys 3FA7E0328081BFF6A14DA29AA6A19B38D3D831EF
            echo "deb https://download.mono-project.com/repo/ubuntu stable-focal main" \
                | sudo tee /etc/apt/sources.list.d/mono-official-stable.list
            sudo apt-get update
        fi
    else
        log "  installing from Ubuntu universe (older 6.8.x, no third-party repo)"
        sudo apt-get update
    fi
    sudo apt-get install -y mono-complete
    ok "Mono installed: $(mono -V 2>&1 | head -1)"
fi

# Critical: mono-runtime alone is broken for QA40x. If only mono-runtime is
# installed (without mono-complete), upgrade.
if ! dpkg -s mono-complete >/dev/null 2>&1 && dpkg -s mono-runtime >/dev/null 2>&1; then
    warn "mono-runtime is installed but mono-complete is NOT — QA40x silently fails on this combination"
    confirm "Install mono-complete now?" && sudo apt-get install -y mono-complete
fi

# -- libusb ------------------------------------------------------------------
log "libusb"
if dpkg -s libusb-1.0-0-dev >/dev/null 2>&1; then
    skip "libusb-1.0-0-dev"
else
    sudo apt-get install -y libusb-1.0-0 libusb-1.0-0-dev
    ok "libusb installed"
fi

# -- libcanberra (cosmetic) --------------------------------------------------
log "libcanberra-gtk-module (silences a noisy GTK warning)"
if dpkg -s libcanberra-gtk-module >/dev/null 2>&1; then
    skip "libcanberra-gtk-module"
else
    sudo apt-get install -y libcanberra-gtk-module
    ok "libcanberra-gtk-module installed"
fi

# -- Wine --------------------------------------------------------------------
if [[ $SKIP_WINE -eq 1 ]]; then
    log "Wine — skipped (--skip-wine)"
elif [[ -f "$HOME/qa403/QA40x.exe" ]]; then
    log "Wine — skipped (~/qa403/QA40x.exe already extracted)"
elif command -v wine >/dev/null && dpkg -s winehq-stable >/dev/null 2>&1; then
    skip "winehq-stable ($(wine --version 2>/dev/null))"
else
    log "Wine"
    sudo dpkg --add-architecture i386
    sudo mkdir -pm755 /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/winehq-archive.key ]]; then
        sudo wget -qO /etc/apt/keyrings/winehq-archive.key https://dl.winehq.org/wine-builds/winehq.key
    fi
    if ! ls /etc/apt/sources.list.d/winehq-${CODENAME}.sources 2>/dev/null >&2; then
        sudo wget -qNP /etc/apt/sources.list.d/ \
            "https://dl.winehq.org/wine-builds/ubuntu/dists/${CODENAME}/winehq-${CODENAME}.sources"
    fi
    sudo apt-get update
    sudo apt-get install -y --install-recommends winehq-stable
    ok "Wine installed: $(wine --version 2>/dev/null || echo unknown)"
fi

# -- Run installer (optional) ------------------------------------------------
if [[ -n "$EXE" ]]; then
    [[ -f "$EXE" ]] || die "Installer EXE not found at: $EXE"

    log "Running QA40x installer under Wine"
    if [[ -f "$HOME/qa403/QA40x.exe" ]]; then
        skip "~/qa403/QA40x.exe already exists; not re-running installer (delete ~/qa403/ first to re-install)"
    else
        # Run installer. Wine's first-run dialogs (Mono / Gecko) may pop up —
        # the user has to handle those interactively.
        warn "Wine first-run may prompt for Mono/Gecko install — accept or cancel, both work"
        warn "Click through the QA40x installer dialogs and accept defaults"
        wine "$EXE" || warn "wine exit was non-zero, but installer may have completed — checking..."

        WINE_QA40X_DIR="$HOME/.wine/drive_c/Program Files (x86)/QuantAsylum/QA40x"
        if [[ ! -d "$WINE_QA40X_DIR" ]]; then
            die "Installer didn't drop ~/.wine/drive_c/Program Files (x86)/QuantAsylum/QA40x. Did you click Cancel? Try again."
        fi
        mkdir -p "$HOME/qa403"
        cp -rv "$WINE_QA40X_DIR"/* "$HOME/qa403/"
        ok "QA40x extracted to ~/qa403/"
    fi
fi

# -- Final state -------------------------------------------------------------
log "Final state"
if [[ -f "$HOME/qa403/QA40x.exe" ]]; then
    ok "~/qa403/QA40x.exe ready"
    echo
    echo "Run with:"
    echo "    cd ~/qa403 && mono QA40x.exe"
    echo
    echo "First time only: in the QA40x app, File → Devices → QA403 (or QA402)."
    echo "Status corner should turn green when the device is connected."
else
    warn "~/qa403/QA40x.exe is NOT yet present"
    echo
    echo "Next steps:"
    echo "  1. Download setup_QA40x_X.YYY.exe from"
    echo "     https://github.com/QuantAsylum/QA40x/releases"
    echo "  2. Re-run this script with --exe pointing at it:"
    echo "       $0 --exe ~/Downloads/setup_QA40x_1.222.exe"
    echo "     OR run wine ~/Downloads/setup_QA40x_*.exe manually,"
    echo "     then copy ~/.wine/drive_c/Program\\ Files\\ \\(x86\\)/QuantAsylum/QA40x/* ~/qa403/"
fi

echo
echo "If you hit X11 BadAlloc / GDI+ GenericError errors when launching, see"
echo "the troubleshooting section in INSTALL.md (the AccelMethod XAA xorg.conf"
echo "workaround works on most Ubuntu installs with intel/radeon/nouveau"
echo "drivers; not modesetting)."
