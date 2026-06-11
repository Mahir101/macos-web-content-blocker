import Foundation

/// Delayed-disable protection: turning the blocker off is a two-step
/// operation separated by a waiting period (default 24h), so a moment
/// of weakness cannot defeat the tool instantly.
///
///   requestDisable()  -> starts the clock
///   confirmDisable()  -> only succeeds after the waiting period
///   cancelDisable()   -> abandons a pending request
public struct TamperGuard: Sendable {
    public enum DisableStatus: Sendable, Equatable {
        case notRequested
        case waiting(until: Date)
        case readyToConfirm
    }

    private let configStore: ConfigStore

    public init(configStore: ConfigStore) {
        self.configStore = configStore
    }

    public func status(now: Date = Date()) -> DisableStatus {
        let config = configStore.load()
        guard let requestedAt = config.disableRequestedAt else { return .notRequested }
        let readyAt = requestedAt.addingTimeInterval(config.disableDelayHours * 3600)
        return now >= readyAt ? .readyToConfirm : .waiting(until: readyAt)
    }

    public func requestDisable(now: Date = Date()) {
        _ = configStore.update { config in
            if config.disableRequestedAt == nil {
                config.disableRequestedAt = now
            }
        }
    }

    public func cancelDisable() {
        _ = configStore.update { $0.disableRequestedAt = nil }
    }

    /// Returns true if the blocker was actually disabled.
    @discardableResult
    public func confirmDisable(now: Date = Date()) -> Bool {
        guard status(now: now) == .readyToConfirm else { return false }
        _ = configStore.update { config in
            config.enabled = false
            config.disableRequestedAt = nil
        }
        return true
    }

    public func reEnable() {
        _ = configStore.update { config in
            config.enabled = true
            config.disableRequestedAt = nil
        }
    }
}
