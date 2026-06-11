import Foundation

/// Central location for every file the blocker reads or writes.
/// Everything lives under ~/Library/Application Support/PornBlocker.
public enum Paths {
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        return base.appendingPathComponent("PornBlocker", isDirectory: true)
    }

    public static var configFile: URL { supportDirectory.appendingPathComponent("config.json") }
    public static var stateFile: URL { supportDirectory.appendingPathComponent("state.json") }
    public static var runtimeBlocklistFile: URL { supportDirectory.appendingPathComponent("blocklist-runtime.json") }
    public static var customBlocklistFile: URL { supportDirectory.appendingPathComponent("blocklist-custom.json") }
    /// Large imported list (e.g. an /etc/hosts-format blocklist).
    public static var importedBlocklistFile: URL { supportDirectory.appendingPathComponent("blocklist-imported.json") }
    public static var whitelistFile: URL { supportDirectory.appendingPathComponent("whitelist.json") }
    public static var eventLogFile: URL { supportDirectory.appendingPathComponent("events.log") }

    /// Optional user-recorded audio played on each block. Any format
    /// afplay supports; drop one in to override the spoken fallback.
    public static var blockAudioFile: URL { supportDirectory.appendingPathComponent("block-audio.m4a") }

    /// Plain-text export (one domain per line) consumed by the root
    /// hosts-sync LaunchDaemon for network-level blocking.
    public static var domainExportFile: URL { supportDirectory.appendingPathComponent("blocked-domains.txt") }

    public static func ensureSupportDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: supportDirectory, withIntermediateDirectories: true
        )
    }
}
