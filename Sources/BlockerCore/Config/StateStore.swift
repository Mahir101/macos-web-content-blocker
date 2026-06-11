import Foundation

/// Runtime state shared between the daemon (writer) and the UI (reader).
public struct ServiceState: Codable, Sendable, Equatable {
    public var runningSince: Date?
    public var detectionsTotal: Int
    public var lastDetectionAt: Date?
    public var lastDetectionDomain: String?
    public var cooldownUntil: Date?
    public var vpnActive: Bool

    public init(
        runningSince: Date? = nil,
        detectionsTotal: Int = 0,
        lastDetectionAt: Date? = nil,
        lastDetectionDomain: String? = nil,
        cooldownUntil: Date? = nil,
        vpnActive: Bool = false
    ) {
        self.runningSince = runningSince
        self.detectionsTotal = detectionsTotal
        self.lastDetectionAt = lastDetectionAt
        self.lastDetectionDomain = lastDetectionDomain
        self.cooldownUntil = cooldownUntil
        self.vpnActive = vpnActive
    }

    public var inCooldown: Bool {
        guard let cooldownUntil else { return false }
        return cooldownUntil > Date()
    }
}

public final class StateStore: @unchecked Sendable {
    private let url: URL
    private let queue = DispatchQueue(label: "blocker.state")

    public init(url: URL = Paths.stateFile) {
        self.url = url
    }

    public func load() -> ServiceState {
        queue.sync {
            guard let data = try? Data(contentsOf: url),
                  let state = try? JSONDecoder.blocker.decode(ServiceState.self, from: data)
            else { return ServiceState() }
            return state
        }
    }

    public func update(_ mutate: (inout ServiceState) -> Void) {
        queue.sync {
            var state: ServiceState
            if let data = try? Data(contentsOf: url),
               let loaded = try? JSONDecoder.blocker.decode(ServiceState.self, from: data) {
                state = loaded
            } else {
                state = ServiceState()
            }
            mutate(&state)
            guard let data = try? JSONEncoder.blocker.encode(state) else { return }
            try? Paths.ensureSupportDirectoryExists()
            try? data.write(to: url, options: .atomic)
        }
    }
}
