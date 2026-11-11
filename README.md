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

## Online fix routing

Each game can choose how the real AppID is routed to the 480 matchmaking session:

- **Automatic** (default) — late routing for Wine/CrossOver launches, early routing for native games.
- **Early** — rewrite the AppID in `CUser::SpawnProcess`, before Steam builds the launch environment. This is the original behaviour.
- **Late** — launch the real game and rewrite only its Steam pipe to 480. This keeps the compatibility tool, DRM wrapper, Steam Input manifest and overlay on the real AppID.

Games launched outside Steam (Finder, a desktop shortcut, or a third-party launcher) are routed when their Steam pipe appears, without needing a `SpawnProcess` session. This is what makes NotProton and CrossOver launches work.

## Windows games with NotProton

1. Install the game with NotProton/CrossOver and launch it once so its prefix exists.
2. Add the game to Manager and pick **Automatic** or **Late** routing.
3. Install OnlineFix and launch the game normally.

The macOS Steam client still owns the pipe; the Windows game's `steam_api` reaches it through NotProton's `lsteamclient`. Late routing is preferred because it leaves NotProton's prefix, CEG and overlay setup untouched.

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
