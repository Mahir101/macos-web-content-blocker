import Foundation

/// User-tunable configuration, persisted as JSON.
public struct AppConfig: Codable, Sendable, Equatable {
    /// Master switch. The daemon idles (but stays alive) when false.
    public var enabled: Bool
    /// Detection score at or above which enforcement runs.
    public var blockThreshold: Int
    /// Seconds after an enforcement during which re-detections of the
    /// same domain escalate immediately.
    public var cooldownSeconds: TimeInterval
    /// Hours a disable request must wait before it can be confirmed.
    public var disableDelayHours: Double
    /// Pending disable request, if any (set by TamperGuard).
    public var disableRequestedAt: Date?

    public init(
        enabled: Bool = true,
        blockThreshold: Int = 100,
        cooldownSeconds: TimeInterval = 60,
        disableDelayHours: Double = 24,
        disableRequestedAt: Date? = nil
    ) {
        self.enabled = enabled
        self.blockThreshold = blockThreshold
        self.cooldownSeconds = cooldownSeconds
        self.disableDelayHours = disableDelayHours
        self.disableRequestedAt = disableRequestedAt
    }
}

/// Thread-safe load/save for AppConfig.
public final class ConfigStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "blocker.config")
    private var cached: AppConfig?

    public init(url: URL = Paths.configFile) {
        self.url = url
    }

    public func load() -> AppConfig {
        queue.sync {
            if let cached { return cached }
            guard let data = try? Data(contentsOf: url),
                  let config = try? JSONDecoder.blocker.decode(AppConfig.self, from: data)
            else {
                let fresh = AppConfig()
                cached = fresh
                return fresh
            }
            cached = config
            return config
        }
    }

    public func save(_ config: AppConfig) {
        queue.sync {
            cached = config
            guard let data = try? JSONEncoder.blocker.encode(config) else { return }
            try? Paths.ensureSupportDirectoryExists()
            try? data.write(to: url, options: .atomic)
        }
    }

    public func update(_ mutate: (inout AppConfig) -> Void) -> AppConfig {
        var config = load()
        mutate(&config)
        save(config)
        return config
    }

    /// Drops the in-memory cache so the next load re-reads from disk
    /// (used by the UI app to pick up daemon-side changes).
    public func invalidateCache() {
        queue.sync { cached = nil }
    }
}

extension JSONEncoder {
    static var blocker: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var blocker: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
