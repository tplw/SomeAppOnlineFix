# Steam build changes and recovery

OnlineFix hooks a fixed set of functions in `steamclient.dylib`. Profiles are
shipped per Steam build:

| Build | Status |
|---|---|
| 1791918634 | Supported |
| 1792618285 | Supported |
| 1794424036 | Not supported: the seven hook targets changed structurally |

The Manager derives a profile for a new build when the function layouts are
close enough to carry forward. It **fails closed** when they are not: the install
is blocked instead of writing hooks that would crash Steam.

## Current live state (2026-11-11)

Steam updated to **1794424036**. The official client is installed and stable.
The third-party hook tools were tested against it:

- **NotProton 1.2.5** loads and works (Steam stays up, WebUI/compat hooks install).
- **macsteam 0.8.2.4** loads 14/18 hooks and then crashes Steam with
  `SIGBUS`/`KERN_PROTECTION_FAILURE`. It is therefore **not** in
  `LSEnvironment` right now. License spoofing is blocked until macsteam ships
  support for this build.
- OnlineFix has no profile for 1794424036, so it is disabled on this build.

The user's Steam currently runs with only NotProton injected:

```
LSEnvironment DYLD_INSERT_LIBRARIES =
  /Applications/Steam.app/Contents/MacOS/notproton.dylib
```

## When macsteam/OnlineFix support the new build

1. Quit Steam.
2. Reinstall/update macsteam and NotProton from their releases.
3. Run OnlineFix Manager; if it reports the build as unsupported, stop. Do not
   install until a profile exists.
4. Add the hooks back in this order:

```text
/Applications/Steam.app/Contents/MacOS/macsteam.dylib:
/Applications/Steam.app/Contents/MacOS/notproton.dylib:
/Applications/Steam.app/Contents/MacOS/cloud_redirect.dylib:
/Users/<you>/Library/Application Support/OnlineFixManager/runtime/onlinefix.dylib
```

Set the same value in both `/Applications/Steam.app/Contents/Info.plist` and
`~/Library/Application Support/Steam/Steam.AppBundle/Steam/Contents/Info.plist`,
then ad-hoc sign both bundles. OnlineFix Manager does this automatically.
5. Launch Steam and verify the logs:

```bash
rg 'hooks: 18/18|macsteam ready' ~/Library/Application\ Support/macSteam/macsteam.log
rg 'routing ready' ~/Library/Application\ Support/OnlineFixManager/onlinefix.log
```

## Why a manual downgrade is not offered

The old client's bootstrapper verifies exact file sizes, symlinks and the signed
`steam_osx` against `steam_client_osx.installed`. Restoring the old packages by
hand leaves broken symlinks and a mismatched executable, so Steam refuses to
start or immediately re-updates. Use Valve's client as-is and wait for the hook
tools to catch up; do not pin old files unless you have a verified full bundle.
