# Valheim native macOS online fix

The Windows online fix ships a Harmony plugin (`Custom.dll`) whose multiplayer
patch is managed code. It replaces PlayFab's Steam login with a custom-ID login
keyed on the local SteamID:

```csharp
PlayFabClientAPI.LoginWithCustomID(new LoginWithCustomIDRequest {
    CreateAccount = true,
    CustomId = SteamUser.GetSteamID().ToString()
}, resultCallback, errorCallback, null, null);
```

Valheim's Mac build is Mono, so the same patch runs natively through BepInEx.
No Wine and no patched `PlayFab.dll` are needed.

## Build

Install BepInEx 5.4.23.6 **macOS universal** into the game directory, then:

```sh
dotnet build -c Release
cp bin/Release/netstandard2.1/ValheimOnlineFix.dll \
  "$HOME/Library/Application Support/Steam/steamapps/common/Valheim/BepInEx/plugins/"
```

`ValheimDir` can be overridden:

```sh
dotnet build -c Release -p:ValheimDir=/path/to/Valheim
```

## Launch through Steam

Steam starts `valheim.app/Contents/MacOS/Valheim`. Rename the original binary to
`Valheim.bin` and put a wrapper in its place:

```sh
#!/bin/sh
set -e
APP_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
cd "$APP_DIR"
exec ./run_bepinex.sh "$APP_DIR/valheim.app/Contents/MacOS/Valheim.bin" "$@"
```

Re-sign the bundle after editing it:

```sh
codesign --force --sign - /path/to/valheim.app
```

## Verify

`BepInEx/LogOutput.log` shows:

```
Loading [Valheim OnlineFix 1.0.0]
Valheim OnlineFix: LoginWithSteam -> LoginWithCustomID
```

`~/Library/Logs/IronGate/Valheim/Player.log` shows:

```
Sending PlayFab login request (attempt 1)
Logged in PlayFab user via Steam auth session ticket
```

## Limits under fake AppID 480

- PlayFab/crossplay servers work end to end.
- Direct Steam-transport servers time out with
  `5003 Timed out attempting to connect`, because the fake AppID does not match
  the real server's Steam identity.
- The in-game Community tab queries the Steam server list as AppID 480, so it
  also lists other OnlineFix games and passworded Valheim servers.
