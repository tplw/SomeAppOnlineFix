import Foundation

enum NotProtonBridge {
    static func bridge(appID: UInt32, directory: URL) throws -> URL {
        let prefix = try WineDLLSettings.prefix(appID: appID, directory: directory)
        return prefix.appendingPathComponent("drive_c/Program Files (x86)/Steam", isDirectory: true)
    }

    static func repair(appID: UInt32, directory: URL) throws -> URL {
        try repair(bridge: try bridge(appID: appID, directory: directory))
    }

    static func repair(bridge: URL) throws -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: bridge.path) else {
            throw ManagerError(message: "No NotProton Steam bridge is staged yet. Launch the game once, then retry.")
        }
        let backup = bridge.deletingLastPathComponent()
            .appendingPathComponent("Steam.bridge-backup-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        try fm.moveItem(at: bridge, to: backup)
        return backup
    }
}
