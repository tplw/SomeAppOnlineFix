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
