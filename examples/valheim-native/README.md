# Valheim native macOS online fix

The Windows online fix's multiplayer logic is managed code: it replaces
PlayFab's Steam login with a custom-ID login keyed on the local SteamID.

```csharp
PlayFabClientAPI.LoginWithCustomID(new LoginWithCustomIDRequest {
    CreateAccount = true,
    CustomId = SteamUser.GetSteamID().ToString()
}, resultCallback, errorCallback, null, null);
```

Valheim's Mac build is Mono, so the port runs natively through BepInEx. It does
not patch `PlayFab.dll`, `assembly_valheim.dll` or any other game assembly; all
changes live in the plugin plus a small launcher.

## How it works

- **BepInEx 5.4.23.6 macOS universal** loads from the game directory.
- **`valheim.app/Contents/MacOS/Valheim`** is a launcher script. Steam starts it,
  and it merges Steam's own `DYLD_INSERT_LIBRARIES` (loader/overlay) with
  `libdoorstop.dylib`, sets the Doorstop variables, and execs
  `Valheim.real` directly. No `arch` invocation is involved.
- **`Valheim.real`** is the stock game binary, re-signed ad-hoc. The ad-hoc
  signature removes the hardened runtime so dyld accepts the injected Doorstop;
  the original binary and code are unchanged.
- The plugin patches, at runtime:
  - `PlayFabAuthWithSteam.Login` and `PlayFabClientAPI.LoginWithSteam` to log in
    with `LoginWithCustomID(SteamUser.GetSteamID())`
  - `SteamManager.LoadAPPID` to return 892970
  - `SteamAPI.RestartAppIfNecessary` to return false (stops Spacewar relaunch)
  - `MultiBackendMatchmaking` to hide the Steam AppID 480 server list

Game assemblies stay stock. A corrupt `PlayFab.dll` from older attempts is
restored from its backup, and the plugin logs a warning if the hash is wrong.

## Install or repair

The Manager installs the same plugin from
`OnlineFixManager/Resources/ValheimOnlineFix.dll` (plugin 1.3.0). For a manual
install, add BepInEx 5.4.23.6 **macOS universal** to the game directory, then:

```sh
./install.sh            # install or repair after a Steam update
./install.sh --check    # verify without changing files
```

The script restores the stock binary layout after a Steam update, installs the
launcher, rebuilds the plugin, and re-signs the binary and bundle.
`VALHEIM_DIR` overrides the game path and `DOTNET` overrides the dotnet binary.

If Steam validation replaced the game binary and there is no `Valheim.real`,
run Steam validation once to restore it, then run `./install.sh`.

## Verify

`BepInEx/LogOutput.log`:

```
patched PlayFab.PlayFabClientAPI.LoginWithSteam
patched SteamManager.LoadAPPID
patched SteamAPI.RestartAppIfNecessary
patched PlayFabAuthWithSteam.Login
patched MultiBackendMatchmaking constructor
Valheim OnlineFix: LoginWithSteam -> LoginWithCustomID
Valheim OnlineFix: crossplay-only browser = True
Server browser: Steam-480 list hidden, showing PlayFab/crossplay only
```

`~/Library/Logs/IronGate/Valheim/Player.log`:

```
Steam initialized, persona:HartzOn4
Logged in PlayFab user via Steam auth session ticket
```

## Server browser

The Community tab lists only PlayFab/crossplay Valheim servers, so other
OnlineFix games and fake-AppID servers no longer appear. Set
`CrossplayOnly = false` in `BepInEx/config/onlinefix.valheim.cfg` to restore the
merged Steam list.

## Plugin 1.3.0

The shipped plugin only logs which patches were applied, the server-browser
mode and a PlayFab hash check. Diagnostic code used during development
(screenshot capture, per-call login logging, a separate ticket-dump plugin) is
not part of the release.

## Limits under fake AppID 480

- PlayFab/crossplay servers work end to end.
- Direct Steam-transport servers time out, because the fake AppID does not match
  the real server's Steam identity. This needs ownership/ticket spoofing on the
  real AppID, not an AppID remap.
