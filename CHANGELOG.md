## Unreleased

- Custom Fix package intelligence: parses the full `OnlineFix.ini` and
  `dlllist.txt`, detects Steam vs Microsoft Store/GDK packages, checks the
  SHA-512 build hash, warns about incomplete BepInEx/loader files, and blocks
  GDK fixes on Steam games.
- Known Windows proxy DLLs (winmm/version/winhttp/etc.) are recommended even
  when Wine has no builtin of the same name.
- Added NotProton Steam bridge repair for games that hang after a Steam restart.

- Valheim is a built-in fix in Available fixes. It installs the native BepInEx
  plugin and launcher, requires BepInEx 5.4.23.6 plus libdoorstop.dylib, and
  restores the stock binary on disable/uninstall.
- Uninstall now recovers when `installation.json` or the backup is missing:
  it restores the backup if present, otherwise strips the OnlineFix injection
  from Steam.app and re-signs it.

# Changelog

## v2.1.0

- Late Steam-pipe routing as an opt-in per-game mode and as the fallback for games launched outside Steam, including NotProton and third-party launchers.
- Automatic routing keeps the proven early `SpawnProcess` rewrite for Steam-launched games.
- Automatic Steam signature-profile derivation when Steam updates to an unshipped build.
- Build detection prefers the installed plain manifest over a newer pending signed manifest.
- Preserve the Valheim PlayFab field and foreign fix entries from newer local builds instead of dropping or rejecting them.
- Manager diagnostics for Steam build, profile status, coexisting hooks and routing history.
- Launch command, routing mode and every AppID transition are written to the log.
- Fixed the manager test suite failing on placeholder Photon catalog entries.

## v2.0.0

- CustomFix workflow for installing and managing game-specific fixes directly in Manager.
- Built-in Fix catalog organizing patch sources and supported games.
- Native Photon multiplayer compatibility patches for Some Game
- Dynamic Steam client build detection with versioned compatibility profile loading.

## v1.0.0

Initial release for Apple Silicon, macOS 15+.

- Native Manager with Steam game search, artwork, and per-game settings.
- Standalone OnlineFix dylib routing selected games to AppID 480.
- Persistent installation with Steam backup and guarded restoration.
- Separate compatibility patches for startup, overlay, Steam Input, and stats.
- Terraria server environment fix with automatic restoration on uninstall.
- Logs reset on each Steam launch.

Terraria now can host & play, (multiplayer not tested yet)
