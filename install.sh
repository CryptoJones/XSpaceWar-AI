#!/usr/bin/env bash
# XSpaceWar-AI one-shot installer: gets Godot 4.6.3 (verified against the
# official SHA-512 sums), puts it on your PATH, builds the project's import
# cache, and tells you how to launch. Safe to re-run; it skips what's done.
#
#   ./install.sh           install + import
#   ./install.sh --test    also run the headless test suites afterwards
#
# Supports Linux (x86_64 / arm64) and macOS. Windows folks: grab the zip from
# https://github.com/CryptoJones/XSpaceWar-AI/releases instead.
set -euo pipefail

GODOT_VERSION="4.6.3"
INSTALL_DIR="${XSW_GODOT_DIR:-$HOME/tools/godot}"
BIN_LINK_DIR="$HOME/.local/bin"
BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable"

# Official SHA-512 sums for ${GODOT_VERSION}-stable (from SHA512-SUMS.txt on
# the Godot release page). Verified at download time.
SUM_LINUX_X86_64="a035258da32b77f966a5376f9fa29c30a6adde826a85ba918e1605bd1fc9823eba7d85f1dd5e748956bd2ba72827c0025ffa11bb82aec91128c407a2e723c99c"
SUM_LINUX_ARM64="447381de9ccc68aa02f37e279322289f7ddf88ce9b839ed88a97c73e01cdcda46e026897e5d88722e08491f71b3d74f72dfeb22ec7e3add6fd3e9bfbbdad6751"
SUM_MACOS_UNIVERSAL="0155bbc8dcf179edab4ef08e3dbbd4480d7434ab1990cb3fb25517d453b1b65787c7fe6dfc8824b15ff25e1fdcec59e8584f765054106894fee00311868c3964"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR:\033[0m %s\n' "$*" >&2; exit 1; }
note() { printf '\033[1;34m::\033[0m %s\n' "$*"; }

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[ -f "$REPO_DIR/project.godot" ] || die "run this from the XSpaceWar-AI repo (project.godot not found next to install.sh)"

# --------------------------------------------------------------------------
# Dependencies
# --------------------------------------------------------------------------
need() {
    command -v "$1" >/dev/null 2>&1 && return 0
    local hint=""
    if command -v apt-get >/dev/null 2>&1; then hint="sudo apt-get install -y $2"
    elif command -v dnf >/dev/null 2>&1; then hint="sudo dnf install -y $2"
    elif command -v pacman >/dev/null 2>&1; then hint="sudo pacman -S $2"
    elif command -v brew >/dev/null 2>&1; then hint="brew install $2"
    fi
    die "'$1' is required but not installed.${hint:+ Try: $hint}"
}
need curl curl
need unzip unzip

sha512_of() {
    if command -v sha512sum >/dev/null 2>&1; then sha512sum "$1" | awk '{print $1}'
    elif command -v shasum >/dev/null 2>&1; then shasum -a 512 "$1" | awk '{print $1}'
    else die "need sha512sum or shasum to verify the download"
    fi
}

# --------------------------------------------------------------------------
# Find or install Godot ${GODOT_VERSION}
# --------------------------------------------------------------------------
GODOT=""
is_right_godot() {
    [ -x "$1" ] && "$1" --version 2>/dev/null | grep -q "^${GODOT_VERSION}\.stable"
}

if is_right_godot "$INSTALL_DIR/godot"; then
    GODOT="$INSTALL_DIR/godot"
    note "Godot ${GODOT_VERSION} already installed at $GODOT"
elif command -v godot >/dev/null 2>&1 && is_right_godot "$(command -v godot)"; then
    GODOT="$(command -v godot)"
    note "Using Godot ${GODOT_VERSION} already on PATH: $GODOT"
else
    OS="$(uname -s)"
    ARCH="$(uname -m)"
    case "$OS-$ARCH" in
        Linux-x86_64)            ASSET="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip"; SUM="$SUM_LINUX_X86_64"; INNER="Godot_v${GODOT_VERSION}-stable_linux.x86_64" ;;
        Linux-aarch64|Linux-arm64) ASSET="Godot_v${GODOT_VERSION}-stable_linux.arm64.zip"; SUM="$SUM_LINUX_ARM64"; INNER="Godot_v${GODOT_VERSION}-stable_linux.arm64" ;;
        Darwin-*)                ASSET="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"; SUM="$SUM_MACOS_UNIVERSAL"; INNER="Godot.app" ;;
        *) die "unsupported platform: $OS $ARCH — install Godot ${GODOT_VERSION} manually and re-run" ;;
    esac

    TMP="$(mktemp -d)"
    trap 'rm -rf "$TMP"' EXIT
    note "Downloading $ASSET …"
    curl -fSL --retry 3 -o "$TMP/$ASSET" "$BASE_URL/$ASSET" \
        || die "download failed — check your network and try again"

    note "Verifying SHA-512 …"
    GOT="$(sha512_of "$TMP/$ASSET")"
    [ "$GOT" = "$SUM" ] || die "checksum mismatch for $ASSET — refusing to install (got $GOT)"

    note "Installing to $INSTALL_DIR …"
    mkdir -p "$INSTALL_DIR"
    unzip -oq "$TMP/$ASSET" -d "$TMP/extract"
    if [ "$OS" = "Darwin" ]; then
        rm -rf "$INSTALL_DIR/Godot.app"
        mv "$TMP/extract/$INNER" "$INSTALL_DIR/Godot.app"
        # Clear the quarantine bit so Gatekeeper doesn't block a CLI-installed app.
        xattr -dr com.apple.quarantine "$INSTALL_DIR/Godot.app" 2>/dev/null || true
        ln -sf "$INSTALL_DIR/Godot.app/Contents/MacOS/Godot" "$INSTALL_DIR/godot"
    else
        mv "$TMP/extract/$INNER" "$INSTALL_DIR/godot"
        chmod +x "$INSTALL_DIR/godot"
    fi
    GODOT="$INSTALL_DIR/godot"
    is_right_godot "$GODOT" || die "installed binary failed its version check"
fi

# --------------------------------------------------------------------------
# PATH convenience (best-effort, never fatal)
# --------------------------------------------------------------------------
mkdir -p "$BIN_LINK_DIR"
ln -sf "$GODOT" "$BIN_LINK_DIR/godot" 2>/dev/null || true
case ":$PATH:" in
    *":$BIN_LINK_DIR:"*) ;;
    *) note "$BIN_LINK_DIR is not on your PATH — use \"$GODOT\" directly, or add: export PATH=\"$BIN_LINK_DIR:\$PATH\"" ;;
esac

# --------------------------------------------------------------------------
# Project import cache (the missing step behind first-launch black screens)
# --------------------------------------------------------------------------
note "Building the project import cache (one-time per clone) …"
"$GODOT" --headless --path "$REPO_DIR" --import >/dev/null 2>&1 || true
[ -d "$REPO_DIR/.godot" ] || die "import failed — run \"$GODOT --headless --path . --import\" manually to see why"

# --------------------------------------------------------------------------
# Optional: prove the install with the headless test suites
# --------------------------------------------------------------------------
if [ "${1:-}" = "--test" ]; then
    for suite in run_tests net_tests relay_tests audio_tests scene_smoke; do
        note "Running $suite …"
        "$GODOT" --headless --path "$REPO_DIR" --script "res://tests/$suite.gd" \
            || die "test suite $suite failed"
    done
fi

bold ""
bold "✔ XSpaceWar-AI is ready."
echo "  Play:        $GODOT --path \"$REPO_DIR\""
echo "               (or just: godot --path . — if $BIN_LINK_DIR is on your PATH)"
echo "  Host a relay: $GODOT --headless --path \"$REPO_DIR\" --script res://server/relay_main.gd"
echo "  Run tests:   ./install.sh --test"
