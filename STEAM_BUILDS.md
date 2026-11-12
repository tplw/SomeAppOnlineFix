# Steam build support and recovery

OnlineFix hooks a fixed set of functions in `steamclient.dylib`. Profiles are
shipped per Steam build:

| Build | Status |
|---|---|
| 1791918634 | Supported |
| 1792618285 | Supported and currently installed |
| 1794424036 | Not supported: the seven hook targets changed structurally |

The Manager derives a profile for a new build when the function layouts are
close enough to carry forward. It **fails closed** when they are not: the install
is blocked instead of writing hooks that would crash Steam.

## Current live state (2026-11-11)

The test machine runs a fully consistent **1792618285** client, reconstructed
from Valve's old package set:

- exact old `steam_osx` (8,709,904 bytes) and `SteamMacBootstrapper.tar.gz`;
- all 14 framework symlinks and all 6,707 `steam_client_osx.installed` entries
  verified (size, CRC32, symlink target CRC);
- Valve bootstrapper verification passes;
- macsteam **18/18** hooks, NotProton and OnlineFix loaded;
- Terraria (native) and Casualties Unknown (Windows/NotProton) both registered by
  Steam as AppID 480 in live runs.

The old client and update manifests are pinned with `uchg`, and `steam.cfg`
contains `BootStrapperInhibitUpdateOnLaunch=enable`, so the 1794424036 updater
cannot replace them. Steam may log a failed manifest save at launch; it continues
on 1792618285.

## Why not 1794424036

The new build refactored the hook functions. Only 1 of 7 old signatures still
matches; fuzzy matching finds changed functions that cannot be hooked safely.
The installed macsteam release also crashes 1794424036 with `SIGBUS` after
14/18 hooks.

## Updating later

1. Quit Steam.
2. Clear the pins:

```bash
chflags nouchg \
  "$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/steamclient.dylib" \
  "$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/package/steam_client_osx.manifest" \
  "$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/package/steam_client_signed-2_osx.manifest" \
  "$HOME/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/MacOS/package/steam_client_signed-2_osx"
```

3. Remove the inner `steam.cfg` update block if you want Steam to update.
4. Update macsteam and NotProton first; test that Steam stays up with their new
   dylibs.
5. Install an OnlineFix release that lists the new build. Do not force the old
   profile; the Manager will block an unsupported build.
6. Re-add the hooks in this order if Manager does not:

```text
macsteam.dylib:notproton.dylib:cloud_redirect.dylib:onlinefix.dylib
```

Set the same `DYLD_INSERT_LIBRARIES` in both the outer and inner `Info.plist`,
then ad-hoc sign both bundles.

## Restoring 1792618285 again

Use Valve's old packages, not a hand-edited copy:

1. Read `steam_client_osx.manifest` for the 1792618285 file names.
2. Download them from `https://client-update.fastly.steamstatic.com/` and verify
   SHA-256.
3. Extract with symlink support; restore the exact `steam_osx` from
   `steam_osx.zip` and the bootstrapper payload.
4. Generate `steam_client_osx.installed` from the tree (file size/CRC32,
   symlink target CRC32, `OSVER=-71`, `VERSION=3`, `SHA1=` of the body).
5. Verify every entry, then launch Valve's bootstrapper.

A partial merge fails verification and makes Steam exit; do not skip the
manifest check.

## Windows gameplay blocker (test machine, 2026-11-11)

Routing to AppID 480 is proven for a native game (Terraria) and a Windows game
(Casualties Unknown via NotProton). A completed Windows lobby is still blocked by
the runtime, not by OnlineFix:

- Casualties Unknown (Unity/D3D11) crashes with the D3DMetal backend and hangs at
  `Direct3D: detected that using refresh rate causes time drift` with DXMT,
  wined3d and DXVK (5+ minutes at 40-50% CPU, no window, no log progress).
- Windowed launch options (`-screen-fullscreen 0 -screen-width 1280
  -screen-height 720`) do not change it.
- The restored old Steam UI renders only the splash; install dialogs are
  invisible, so a different Windows title cannot be installed through the client.
- SteamCMD anonymous downloads the content depots for Alien Swarm: Reactive Drop
  but not the client executable; app 630 returns `No subscription`.
- A custom Rosetta compatibility tool is removed by NotProton at startup and its
  mapping is reset to the FEX tool.

Resolving this needs a working Rosetta/preview runner from NotProton or a Windows
title known to run under the current FEX renderer. It is not an OnlineFix code
path.

## Rosetta runner attempt (2026-11-11)

NotProton's supported Rosetta tool is `notproton-preview-41069`, which expects
CrossOver **2026 10 06-X86**. The installed `/Applications/CrossOver Preview.app`
is the ARM64 package:

- its `x86_64-windows/ntdll.dll` hashes `1b02dcf6...`, the **FEX clean** hash in
  `SupportedRunner.swift`, not the Rosetta clean `5b388fd4...`;
- the Rosetta detour (`detour2-41069.bin`) cannot be applied because the expected
  cave at `0x815e0` is populated data in that ntdll;
- reusing the FEX-patched ntdll with the Rosetta wine crashes immediately
  (`wine-2026-11-11-213246.ips`);
- a custom tool is deleted by NotProton at startup; the supported tool name
  survives but NotProton's launch hook still hands the game to the FEX tool.

A Windows lobby therefore needs NotProton 1.2.5's runner installer to add the
**CrossOver Preview 11-11-26 X86/Rosetta** package (or the X86 DMG), then the
`notproton-preview-41303` tool. The 1.2.5 app is installed; its config and prefixes
are preserved. OnlineFix routing itself is already proven.

## PEAK (3527290) live result

PEAK is installed and runs under NotProton/FEX. OnlineFix routes it correctly:

```
launch game=3527290 mode=early compat=1
session active game=3527290 pipe=480
networking active: matchmaking uses 480
stats callback: 480 -> 3527290
```

Steam registers the process as AppID 480. PEAK reaches its online stack:

```
Steam Lobby Handler initialized
Steam auth ticket received, adding it to PhotonNetwork
```

It then fails at the game-specific backend, not at Steam routing:

```
LoginAsync result: ConnectExternalTokenValidationFailed
Failed to authenticate: ConnectExternalTokenValidationFailed
OperationResponse 230: ReturnCode: 32755 (Failed(2): error response from Steam)
Opening disconnected modal
```

EOS rejects the Steam token and Photon rejects the session. Copying the generic
`OnlineFix64.dll`/`winmm.dll` and an INI with `PhotonIntegration=true`,
`EmulateTicket=true` did not change it, so PEAK needs its own OnlineFix package
(EOS/Photon app id and ticket patch). Manager's Custom Fix can install that
package when it is available; the Steam-side 480 routing is already proven.

## Valheim (892970): native macOS online port (2026-11-11)

The Windows fix ships a BepInEx/Harmony plugin whose multiplayer patch is
entirely managed:

```csharp
// Custom.dll, class 웈
PlayFabClientAPI.LoginWithCustomID(new LoginWithCustomIDRequest {
    CreateAccount = true,
    CustomId = SteamUser.GetSteamID().ToString()
}, resultCallback, errorCallback, null, null);
```

It prefixes `PlayFabClientAPI.LoginWithSteam`, so no native Steam code changes
are needed. Valheim's Mac build is Mono, so the port is a native BepInEx plugin:

- BepInEx 5.4.23.6 macOS universal in `Valheim/BepInEx`.
- `BepInEx/plugins/ValheimOnlineFix.dll` built against the game's own
  `PlayFab.dll`, `com.rlabrecque.steamworks.net.dll` and `UnityEngine` modules.
- `valheim.app/Contents/MacOS/Valheim` is a wrapper that execs the original
  `Valheim.bin` through `run_bepinex.sh`, so a normal Steam launch loads it.

Live result (native arm64, Steam 1792618285, OnlineFix 892970 -> 480):

```
[Valheim OnlineFix] Valheim OnlineFix: LoginWithSteam -> LoginWithCustomID
Sending PlayFab login request (attempt 1)
Logged in PlayFab user via Steam auth session ticket
```

Joined a public server and spawned in-world:

```
Determined backend of dedicated server to be PlayFab
Connecting to server with PlayFab-backend 59A0BCCCE94F5D9
Joining server 'ECA Public Server (pw:12345)' at PlayFab network ...
PlayFab socket connected to remote player 59A0BCCCE94F5D9
Character ID for player ([asdad, 0:0], [HartzOn4, Steam_76561198687805301, ...], HartzOn4)
Starting music morning
```

Evidence: `evidence/valheim-native-player-join.log`,
`evidence/valheim-native-inworld.png`, `evidence/valheim-native-server-list.png`.

Known limits of the 480 routing:

- PlayFab/crossplay servers work end to end.
- Direct Steam-transport servers time out (`5003 Timed out attempting to
  connect`). The fake AppID 480 does not match a real server's Steam identity,
  so use crossplay servers with this routing.
- The in-game Community tab queries the Steam server list as AppID 480, so it
  also shows other games' servers and passworded OnlineFix Valheim servers.
  A key icon means the server needs a password; ECA publishes `pw:12345`.

### Steam-transport joins: keepRealAppID does not help (2026-11-12)

Tested the two alternatives to the 480 route:

- **No route (real 892970 pipe).** Steam initializes (`Steam initialized,
  persona:HartzOn4`) and the menu loads, but PlayFab login never completes:
  `Sending PlayFab login request` is logged with no success line. The auth
  ticket belongs to an app the account does not own.
- **`keepRealAppID`.** The setting only rewrites `IClientUtils` AppID replies.
  The pipe is still changed to 480 by `CSteamEngine::SetAppIDForCurrentPipe`,
  and `of_networking` reports `matchmaking uses 480`, so Steam P2P still
  identifies as 480.

The requirements conflict: a working PlayFab login needs the 480 pipe, and real
Steam networking needs the 892970 pipe. Fixing this means spoofing ownership and
issuing valid tickets on the real AppID, not remapping the AppID. That is a
separate Steam-client project, so Steam-transport servers remain unsupported;
PlayFab/crossplay servers work end to end.

### Final macOS loader and stock-DLL plugin (2026-11-12)

Follow-up to the `keepRealAppID` test:

- `arch -e` is unusable on this macOS: it fails with "Can't find any plists"
  even for `/bin/echo`, so BepInEx's `run_bepinex.sh` path cannot launch games.
- LaunchServices `LSEnvironment` injects Doorstop on `open valheim.app`, but
  Steam overrides `DYLD_INSERT_LIBRARIES` with its loader/overlay, so the
  injection is lost on a real Steam launch.
- Final loader: a `Valheim` script merges Steam's `DYLD_INSERT_LIBRARIES` with
  `libdoorstop.dylib`, sets `DOORSTOP_*`, and execs `Valheim.real`. The binary
  is ad-hoc signed (hardened runtime removed), which lets dyld accept the
  injection without `arch`.
- Game assemblies are stock again. The plugin patches
  `SteamManager.LoadAPPID` (892970), `SteamAPI.RestartAppIfNecessary` (false),
  `PlayFabAuthWithSteam.Login`/`PlayFabClientAPI.LoginWithSteam`
  (`LoginWithCustomID`), and `MultiBackendMatchmaking` (crossplay-only list).
- Live Steam launch on stock assemblies: all five patches applied and PlayFab
  login succeeded on the first attempt.
- Crossplay-only browser: 178/178 PlayFab servers, no Project Zomboid/Rust
  entries; Connect reached `PlayFab socket connected`.

Evidence: `evidence/valheim-native-final-launch.log`,
`evidence/valheim-native-bepinex-final.log`,
`evidence/valheim-native-crossplay-browser.png`,
`evidence/valheim-native-crossplay-join.log`.

### PEAK (3527290): EOS blocker diagnosis (2026-11-12)

The installed PEAK fix cannot pass Epic Online Services authentication:

- BepInEx ships only `BepInEx.Preloader.dll`; there is no core, plugin, or
  winhttp/version loader.
- `winmm.dll` loads `Custom.dll` into Mono and calls `OnlineFix.Main.Init`.
  Decompiled, that patch only fakes a `CloudAPI` version/login response over
  HTTP. It contains no EOS or Photon code.
- `steam_api64.dll` and `EOSSDK-Win64-Shipping.dll` are stock; the package has
  no EOS emulator or EOS SDK replacement.
- The fix files are dated Oct 2025 while the game is PEAK 3.1.0 (Nov 2026), and
  the INI hash does not match `PEAK.exe` or `Assembly-CSharp.dll`.
- EOS rejects the Steam auth ticket: `ConnectExternalTokenValidationFailed`
  (7000), then Photon `ReturnCode: 32755`. The ticket is issued for the fake
  AppID 480, not PEAK 3527290.
- `keepRealAppID` cannot change the pipe, and a real-3527290 launch is not
  authorized for this account (PEAK is configured as a fix with macsteam depot
  keys); the Wine Steam bridge hangs before Unity starts.

To make PEAK online work we need a current PEAK-specific fix with an EOS
emulator/ticket bypass for build 3.1.0, or a legitimately owned PEAK/Epic
account. This cannot be produced from the installed package.

During the investigation Steam.app's LSEnvironment lost `cloud_redirect.dylib`
(the file is absent) and OnlineFix after a bootstrapper repair. It was
re-registered with macsteam, notproton and the OnlineFix runtime dylib, and
Steam is logged in. Use the Manager's install/repair before the next Steam
restart so the pinned injection is restored correctly.

### Downloaded PEAK package is the GDK fix, not Steam (2026-11-12)

`~/Downloads/PEAK по сети бесплатно.zip` (Nov 2026) is the Microsoft Store/GDK
package, not a Steam fix:

- `OnlineFix.ini` has `IsPackaged=false`, `ProductId=9NMKF7LPVX44` (Microsoft
  Store PEAK), and no `RealAppId`/`FakeAppId`.
- It ships `wdapp.exe` and `xsapi.dll` (Xbox GDK tools) and a `dlllist.txt`
  containing only `OnlineFix64.dll`.
- Its `OnlineFix64.dll` and `winmm.dll` are byte-identical to the versions
  already installed for the Steam fix.

Applying its INI/dlllist to the Steam install does not change EOS; the game
still receives a Steam ticket for fake AppID 480 and EOS rejects it (7000).
The Steam fix (`3527290.zip`) remains the applicable one for this install, and
it has no EOS patch. A Steam-specific 2026 fix with EOS emulation, the GDK game
plus GDK fix, or a legitimately owned account is required.

`AGENTS.md` was added at `~/Downloads/AGENTS.md` and
`~/Desktop/onlinefix-work/AGENTS.md` with the full handoff.

## Final state (2026-11-12)

### Shipped

- **Valheim native fix** (plugin 1.3.0). BepInEx plugin plus launcher, no game
  DLL edits: custom-ID PlayFab login keyed on the local SteamID, AppID 892970
  reported to Steamworks, crossplay-only server browser. Also a built-in
  Manager card with install/disable/repair. Result: PlayFab login on the first
  attempt and working joins to crossplay servers on a family-shared copy.
- **Uninstall recovery.** Removing OnlineFix works when `installation.json` or
  the backup is gone: restore the backup when present, otherwise strip the
  injection from Steam.app and re-sign it.
- **Custom Fix package intelligence (P0/P4).** Parses `OnlineFix.ini` and
  `dlllist.txt`; detects Steam vs Microsoft Store/GDK packages; blocks a GDK
  package on a Steam game; checks the package build hash; warns about
  incomplete BepInEx or a missing loader; recommends known proxy DLLs; repairs
  a stale NotProton Steam bridge. This catches the wrong-package and
  half-installed cases before they turn into a launch failure.

### Removed

- **Real-AppID launch routing.** Tested on the owning account and the
  family-shared account. It does not produce a usable online session for the
  borrower and adds a second launch path to maintain.
- **Ticket transfer.** A Steam auth ticket is bound to the account that
  requested it, so moving it between accounts is invalid.
- **Diagnostic build code.** Screenshot capture, per-call login logging and the
  separate ticket-dump plugin were removed from the shipped plugin.

### Blocked

- **PEAK (3527290).** EOS rejects the Steam ticket (`ConnectExternalTokenValidationFailed`,
  7000) and Photon returns 32755. The installed Steam package has no EOS
  bypass; the 2026 download is the Microsoft Store/GDK fix. Needs a current
  Steam-specific fix with EOS emulation, the GDK game plus GDK fix, or a
  legitimately owned account.
- **Valheim Steam transport.** Direct Steam servers time out under fake AppID
  480; crossplay/PlayFab is the working path.
- **P2 EOS emulator / P3 real-AppID networking.** No usable EOS emulator, and
  real-AppID tickets require ownership. Not implemented.
- **Simultaneous play from one family-shared copy.** This is a Steam
  licensing/family-sharing bypass, not a compatibility feature, and is not
  implemented.
