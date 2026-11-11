# SomeAppOnlineFix

Experimental OnlineFix implementation for macOS on Apple Silicon.

> [!WARNING]
> **This project is still experimental.** Bugs and compatibility issues are expected.
>
> **Intel-based Macs are not supported.** Apple Silicon (M1 or newer) and macOS 15+ are required.
## Disclaimer

> [!IMPORTANT]
> This project does not bypass game licensing and still requires a valid, original game license.
>
> It is intended for game owners who want to play with people who do not own the game.

## Requirements

- Apple Silicon, macOS 15+
- Xcode Command Line Tools with Swift 6, CMake
- Steam (compatible build)
- Internet access for the first build (Dobby)

## Build

```bash
make -j4
open out/OnlineFixManager.app
```

Supported Steam client builds are `1791918634` and `1792618285`. Steam build
`1794424036` changed the hook targets structurally; OnlineFix blocks installation
until a profile is available. See [STEAM_BUILDS.md](docs/steam-build-recovery.md)
for the current state and recovery steps.

## Online fix routing

Each game can choose how the real AppID is routed to the 480 matchmaking session:

- **Automatic** (default) — early routing for games launched by Steam, the proven BetterSteamTools path. Direct launches without a `SpawnProcess` session use the late pipe fallback.
- **Early** — rewrite the AppID in `CUser::SpawnProcess`, before Steam builds the launch environment.
- **Late** — launch the real game and rewrite only its Steam pipe to 480. Opt in for games that need the compatibility tool, DRM wrapper, Steam Input manifest or overlay to keep the real AppID.

Games launched outside Steam (Finder, a desktop shortcut, or a third-party launcher) are routed when their Steam pipe appears, without needing a `SpawnProcess` session. This is what makes NotProton and CrossOver launches work.

## Windows games with NotProton

1. Install the game with NotProton/CrossOver and launch it once so its prefix exists.
2. Add the game to Manager and keep **Automatic** (early routing through Steam).
3. Install OnlineFix and launch the game from Steam.

The macOS Steam client still owns the pipe; the Windows game's `steam_api` reaches it through NotProton's `lsteamclient`. If a game misbehaves with the early environment rewrite, select **Late** for that game; the compatibility tool and DRM wrapper then keep the real AppID and only the pipe is rewritten.

## Contributing

Issues and pull requests are welcome!

- Keep changes focused and relevant.
- Run `make test` before submitting a PR.
- For compatibility reports, please include:
  - Game name and AppID
  - macOS version
  - Steam build/version
  - Relevant logs
- Place game-specific patches in `src/patch/`.

## Credits

- [BetterSteamTools](https://github.com/madoiscool/BetterSteamTools) / [OpenSteamTool](https://github.com/OpenSteam001/OpenSteamTool) — OnlineFix approach.
- [macSteam](https://github.com/Selectively11/macSteam) — Steam hook reference.

## License

- OnlineFixManager — [AGPL-3.0](LICENSE).
- Third-party components are subject to their respective licenses. See the license notices included in their source code or directories.
