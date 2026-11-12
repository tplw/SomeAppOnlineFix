import Foundation

enum ValheimPatch {
    static let pluginName = "ValheimOnlineFix.dll"

    private static let launcher = """
    #!/bin/sh
    set -e
    APP_DIR="$(cd "$(dirname "$0")/../../.." && pwd)"
    cd "$APP_DIR"
    libs="$APP_DIR/libdoorstop.dylib"
    if [ -n "${DYLD_INSERT_LIBRARIES:-}" ]; then
        libs="$libs:$DYLD_INSERT_LIBRARIES"
    fi
    export DYLD_INSERT_LIBRARIES="$libs"
    export DYLD_LIBRARY_PATH="$APP_DIR${DYLD_LIBRARY_PATH:+:$DYLD_LIBRARY_PATH}"
    export DOORSTOP_ENABLED=1
    export DOORSTOP_TARGET_ASSEMBLY="$APP_DIR/BepInEx/core/BepInEx.Preloader.dll"
    export DOORSTOP_MONO_DLL_SEARCH_PATH_OVERRIDE="$APP_DIR/BepInEx/core"
    exec "$APP_DIR/valheim.app/Contents/MacOS/Valheim.real" "$@"

    """

    static func appURL(directory: URL) -> URL {
        directory.appendingPathComponent("valheim.app", isDirectory: true)
    }

    private static func macos(_ directory: URL) -> URL {
        appURL(directory: directory).appendingPathComponent("Contents/MacOS", isDirectory: true)
    }

    private static func wrapper(_ directory: URL) -> URL {
        macos(directory).appendingPathComponent("Valheim")
    }

    private static func real(_ directory: URL) -> URL {
        macos(directory).appendingPathComponent("Valheim.real")
    }

    private static func legacyBin(_ directory: URL) -> URL {
        macos(directory).appendingPathComponent("Valheim.bin")
    }

    private static func plugin(_ directory: URL) -> URL {
        directory.appendingPathComponent("BepInEx/plugins/\(pluginName)")
    }

    private static func bepInExCore(_ directory: URL) -> URL {
        directory.appendingPathComponent("BepInEx/core/BepInEx.dll")
    }

    static func canInstall(directory: URL?) -> Bool {
        guard let directory else { return false }
        let fm = FileManager.default
        return fm.fileExists(atPath: appURL(directory: directory).path)
            && fm.fileExists(atPath: bepInExCore(directory).path)
            && fm.fileExists(atPath: directory.appendingPathComponent("libdoorstop.dylib").path)
    }

    static func hasWrapper(directory: URL?) -> Bool {
        guard let directory else { return false }
        let fm = FileManager.default
        guard fm.fileExists(atPath: real(directory).path), isMachO(real(directory)),
              let text = try? String(contentsOf: wrapper(directory), encoding: .utf8) else { return false }
        return text.contains("Valheim.real")
    }

    static func isInstalled(directory: URL?) -> Bool {
        guard let directory, canInstall(directory: directory), hasWrapper(directory: directory) else { return false }
        return FileManager.default.fileExists(atPath: plugin(directory).path)
    }

    static func setEnabled(_ enabled: Bool, directory: URL, plugin source: URL? = nil) throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: appURL(directory: directory).path) else {
            throw ManagerError(message: "Valheim is not installed in that folder.")
        }
        if enabled {
            guard fm.fileExists(atPath: bepInExCore(directory).path),
                  fm.fileExists(atPath: directory.appendingPathComponent("libdoorstop.dylib").path) else {
                throw ManagerError(message: "Install BepInEx 5.4.23.6 macOS in the Valheim folder before enabling the native fix.")
            }
            // Migrate a stock binary or the old wrapper layout.
            if isMachO(wrapper(directory)) {
                if fm.fileExists(atPath: real(directory).path) { try fm.removeItem(at: real(directory)) }
                try fm.moveItem(at: wrapper(directory), to: real(directory))
            } else if fm.fileExists(atPath: legacyBin(directory).path), !fm.fileExists(atPath: real(directory).path) {
                try fm.moveItem(at: legacyBin(directory), to: real(directory))
            }
            guard fm.fileExists(atPath: real(directory).path), isMachO(real(directory)) else {
                throw ManagerError(message: "The Valheim game binary is missing. Run Steam validation, then retry.")
            }
            let pluginSource = source ?? Bundle.main.resourceURL?.appendingPathComponent(pluginName)
            guard let pluginSource, fm.fileExists(atPath: pluginSource.path) else {
                throw ManagerError(message: "The bundled Valheim plugin is missing from OnlineFix Manager.")
            }
            let pluginDestination = plugin(directory)
            try fm.createDirectory(at: pluginDestination.deletingLastPathComponent(), withIntermediateDirectories: true)
            if fm.fileExists(atPath: pluginDestination.path) { try fm.removeItem(at: pluginDestination) }
            try fm.copyItem(at: pluginSource, to: pluginDestination)
            try launcher.write(to: wrapper(directory), atomically: true, encoding: .utf8)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper(directory).path)
            try sign(real(directory))
            try sign(appURL(directory: directory))
        } else {
            if fm.fileExists(atPath: plugin(directory).path) { try fm.removeItem(at: plugin(directory)) }
            let script = wrapper(directory)
            if let text = try? String(contentsOf: script, encoding: .utf8), text.contains("Valheim.real") {
                try fm.removeItem(at: script)
                try fm.moveItem(at: real(directory), to: script)
                try sign(script)
                try sign(appURL(directory: directory))
            }
        }
    }

    private static func sign(_ url: URL) throws {
        try SteamInstaller.run("/usr/bin/codesign", ["--force", "--sign", "-", url.path])
    }

    private static func isMachO(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 4), data.count == 4 else { return false }
        let magic = data.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        return [0xfeedface, 0xfeedfacf, 0xcafebabe, 0xbebafeca, 0xcafebabf].contains(magic)
    }
}
