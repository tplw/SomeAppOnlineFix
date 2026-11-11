# Changelog

## Unreleased

- Late Steam-pipe routing for Wine/CrossOver games, with per-game Automatic, Early and Late modes.
- Pipe-based fallback routes games launched outside Steam, including NotProton and third-party launchers.
- Automatic Steam signature-profile derivation when Steam updates to an unshipped build.
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
