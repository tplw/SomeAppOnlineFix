#!/bin/bash
# Install or repair the native macOS Valheim online fix.
# Usage: ./install.sh [--check]
set -euo pipefail

GAME="${VALHEIM_DIR:-$HOME/Library/Application Support/Steam/steamapps/common/Valheim}"
APP="$GAME/valheim.app"
MACOS="$APP/Contents/MacOS"
WRAPPER="$MACOS/Valheim"
REAL="$MACOS/Valheim.bin"
PLUGIN_DIR="$GAME/BepInEx/plugins"
HERE="$(cd "$(dirname "$0")" && pwd)"
STOCK_PLAYFAB="88e39787d1b66b64c0a89514b4a6d635659f9198c41146c5ecab303213f9eae6"
CORRUPT_PLAYFAB="91d36a6f9af667af60d1ee8d67f0144e7e2ceb619b8a7806bf1c8ef009b2b5fa"

fail() { echo "valheim-fix: $*" >&2; exit 1; }
hash() { shasum -a 256 "$1" | awk '{print $1}'; }
is_wrapper() { grep -q 'run_bepinex.sh' "$1" 2>/dev/null; }

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

# A Steam update replaces the wrapper with the original binary.
if [[ -f "$WRAPPER" ]] && ! is_wrapper "$WRAPPER"; then
    if $CHECK; then fail "Valheim is the stock binary; re-run install"; fi
    [[ -f "$REAL" ]] || fail "Valheim.bin is missing and Valheim is the stock binary"
    mv -f "$WRAPPER" "$REAL"
    echo "refreshed Valheim.bin from the stock binary"
fi

if [[ ! -f "$REAL" ]]; then
    if $CHECK; then fail "Valheim.bin missing"; fi
    [[ -f "$WRAPPER" ]] || fail "neither Valheim nor Valheim.bin exists"
    mv "$WRAPPER" "$REAL"
    echo "original binary moved to Valheim.bin"
fi

if $CHECK; then
    [[ -x "$WRAPPER" ]] || fail "wrapper missing"
    [[ -f "$GAME/BepInEx/core/BepInEx.dll" ]] || fail "BepInEx core missing"
    [[ -f "$PLUGIN_DIR/ValheimOnlineFix.dll" ]] || fail "plugin missing"
    echo "valheim-fix: installed"
    exit 0
fi

cat > "$WRAPPER" <<'WRAPPER_EOF'
#!/bin/sh
set -e
APP_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$APP_DIR"
exec ./run_bepinex.sh "$APP_DIR/valheim.app/Contents/MacOS/Valheim.bin" "$@"
WRAPPER_EOF
chmod +x "$WRAPPER"

[[ -f "$GAME/BepInEx/core/BepInEx.dll" ]] ||
    fail "BepInEx 5.4.23.6 is not installed in $GAME/BepInEx"

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

codesign --force --sign - "$APP" >/dev/null 2>&1 || fail "codesign failed"
if ! codesign --verify --strict "$APP" >/dev/null 2>&1; then
    echo "note: ad-hoc bundle does not pass strict verification (script main executable); Steam launches it directly"
fi
echo "valheim-fix: installed"
