#!/bin/bash
# Install or repair the native macOS Valheim online fix.
# Usage: ./install.sh [--check]
set -euo pipefail

GAME="${VALHEIM_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Valheim}"
APP="$GAME/valheim.app"
MACOS="$APP/Contents/MacOS"
EXE="$MACOS/Valheim"
REAL="$MACOS/Valheim.real"
PLIST="$APP/Contents/Info.plist"
PLUGIN_DIR="$GAME/BepInEx/plugins"
HERE="$(cd "$(dirname "$0")" && pwd)"
STOCK_PLAYFAB="88e39787d1b66b64c0a89514b4a6d635659f9198c41146c5ecab303213f9eae6"
CORRUPT_PLAYFAB="91d36a6f9af667af60d1ee8d67f0144e7e2ceb619b8a7806bf1c8ef009b2b5fa"
PB=/usr/libexec/PlistBuddy

fail() { echo "valheim-fix: $*" >&2; exit 1; }
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
is_script() { head -c 2 "$1" 2>/dev/null | grep -q '#!'; }

CHECK=false
[[ "${1:-}" == "--check" ]] && CHECK=true

[[ -d "$APP" ]] || fail "Valheim not found at $GAME (set VALHEIM_DIR)"

PLAYFAB="$APP/Contents/Resources/Data/Managed/PlayFab.dll"
if [[ -f "$PLAYFAB" ]]; then
    current="$(hash "$PLAYFAB")"
    if [[ "$current" == "$STOCK_PLAYFAB" ]]; then
        echo "PlayFab.dll: stock"
    elif [[ "$current" == "$CORRUPT_PLAYFAB" ]]; then
        if $CHECK; then fail "PlayFab.dll is the known-bad patch; run install to restore"; fi
        backup="$PLAYFAB.onlinefix-valheim-backup"
        [[ -f "$backup" ]] || fail "PlayFab.dll is patched and the backup is missing"
        cp "$backup" "$PLAYFAB"
        echo "PlayFab.dll: restored from backup"
    else
        echo "PlayFab.dll: unknown hash $current (left unchanged)"
    fi
fi

# A Steam update replaces the wrapper with the stock Mach-O binary.
if [[ -f "$EXE" ]] && ! is_script "$EXE"; then
    if $CHECK; then fail "wrapper missing; re-run install"; fi
    [[ -f "$REAL" ]] && mv -f "$REAL" "$GAME/Valheim.real.previous"
    mv -f "$EXE" "$REAL"
    echo "moved the stock binary to Valheim.real"
fi

[[ -f "$EXE" ]] || fail "launcher missing: $EXE"
[[ -f "$REAL" ]] || fail "game binary missing; run Steam validation to restore it, then re-run install"
file "$REAL" | grep -q 'Mach-O' || fail "Valheim.real is not a Mach-O executable"

if $CHECK; then
    is_script "$EXE" || fail "Valheim is not the launcher script"
    grep -q 'Valheim.real' "$EXE" || fail "launcher does not start Valheim.real"
    [[ -f "$GAME/BepInEx/core/BepInEx.dll" ]] || fail "BepInEx core missing"
    [[ -f "$PLUGIN_DIR/ValheimOnlineFix.dll" ]] || fail "plugin missing"
    if codesign -dvv "$REAL" 2>&1 | grep -q 'flags=.*runtime'; then
        fail "hardened runtime still enabled; re-run install"
    fi
    echo "valheim-fix: installed"
    exit 0
fi

[[ -f "$GAME/BepInEx/core/BepInEx.dll" ]] ||
    fail "BepInEx 5.4.23.6 is not installed in $GAME/BepInEx"

cp "$HERE/Valheim.launcher" "$EXE"
chmod +x "$EXE"

$PB -c "Set :CFBundleExecutable Valheim" "$PLIST" 2>/dev/null ||
    $PB -c "Add :CFBundleExecutable string Valheim" "$PLIST"
$PB -c "Delete :LSEnvironment" "$PLIST" 2>/dev/null || true

DOTNET_BIN="${DOTNET:-}"
if [[ -z "$DOTNET_BIN" ]]; then
    if command -v dotnet >/dev/null 2>&1; then
        DOTNET_BIN="$(command -v dotnet)"
    elif [[ -x /tmp/dotnet10/dotnet ]]; then
        DOTNET_BIN=/tmp/dotnet10/dotnet
    fi
fi

mkdir -p "$PLUGIN_DIR"
if [[ -n "$DOTNET_BIN" ]]; then
    ( cd "$HERE" && "$DOTNET_BIN" build -c Release -p:ValheimDir="$GAME" > /tmp/valheim-fix-build.log )
    cp "$HERE/bin/Release/netstandard2.1/ValheimOnlineFix.dll" "$PLUGIN_DIR/"
    echo "plugin built and installed"
elif [[ -f "$PLUGIN_DIR/ValheimOnlineFix.dll" ]]; then
    echo "dotnet not found; keeping the installed plugin"
else
    fail "dotnet not found and no plugin is installed"
fi

# Ad-hoc signing removes the hardened runtime so dyld accepts Doorstop, and the
# launcher merges Doorstop with Steam's own DYLD_INSERT_LIBRARIES.
codesign --force --sign - "$REAL" >/dev/null 2>&1 || fail "codesign failed for Valheim.real"
codesign --force --sign - "$APP" >/dev/null 2>&1 || fail "codesign failed for the bundle"
if codesign -dvv "$REAL" 2>&1 | grep -q 'flags=.*runtime'; then
    fail "hardened runtime is still enabled"
fi
echo "valheim-fix: installed"
