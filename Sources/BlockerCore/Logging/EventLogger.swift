import Foundation
import os

/// Append-only JSON-lines event log.
///
/// Stored per event: timestamp, browser, trigger reason, domain,
/// confidence score, action taken. Never stores page content,
/// screenshots, or keystrokes.
public struct BlockEvent: Codable, Sendable {
    public var timestamp: Date
    public var browser: String
    public var trigger: String
    public var domain: String?
    public var score: Int
    public var action: String

    public init(
        timestamp: Date = Date(),
        browser: String,
        trigger: String,
        domain: String?,
        score: Int,
        action: String
    ) {
        self.timestamp = timestamp
        self.browser = browser
        self.trigger = trigger
        self.domain = domain
        self.score = score
        self.action = action
    }
}

public final class EventLogger: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "blocker.eventlog")
    private let oslog = Logger(subsystem: "com.selfcontrol.pornblocker", category: "events")
    /// Rotate when the log exceeds this size (keeps one .old file).
    private let maxBytes: UInt64 = 5 * 1024 * 1024

    public init(url: URL = Paths.eventLogFile) {
        self.url = url
    }

    public func log(_ event: BlockEvent) {
        queue.async { [self] in
            try? Paths.ensureSupportDirectoryExists()
            rotateIfNeeded()
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            guard var data = try? encoder.encode(event) else { return }
            data.append(0x0A)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
            } else {
                try? data.write(to: url)
            }
            oslog.info("\(event.action, privacy: .public) \(event.domain ?? "-", privacy: .private) score=\(event.score)")
        }
    }

    public func recentEvents(limit: Int = 100) -> [BlockEvent] {
        queue.sync {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return text.split(separator: "\n")
                .suffix(limit)
                .compactMap { try? decoder.decode(BlockEvent.self, from: Data($0.utf8)) }
                .reversed()
        }
    }

    private func rotateIfNeeded() {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? UInt64, size > maxBytes else { return }
        let old = url.appendingPathExtension("old")
        try? FileManager.default.removeItem(at: old)
        try? FileManager.default.moveItem(at: url, to: old)
    }
}
