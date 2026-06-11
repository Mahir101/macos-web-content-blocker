import Foundation
import Network

/// Detects active VPN-style interfaces (utun/ipsec/ppp) via
/// NWPathMonitor. The blocker's accessibility monitoring and
/// enforcement are network-independent, so a VPN changes nothing about
/// behavior — this exists for status reporting and logging only.
/// No packet inspection is performed.
public final class VPNWatcher: @unchecked Sendable {
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "blocker.vpnwatch")
    private let onChange: @Sendable (Bool) -> Void
    private var lastActive: Bool?

    public init(onChange: @escaping @Sendable (Bool) -> Void) {
        self.onChange = onChange
    }

    public func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let active = Self.hasVPNInterface(path)
            if active != self.lastActive {
                self.lastActive = active
                self.onChange(active)
            }
        }
        monitor.start(queue: queue)
    }

    public func stop() {
        monitor.cancel()
    }

    static func hasVPNInterface(_ path: NWPath) -> Bool {
        path.availableInterfaces.contains { interface in
            if interface.type == .other {
                let name = interface.name.lowercased()
                return name.hasPrefix("utun") || name.hasPrefix("ipsec")
                    || name.hasPrefix("ppp") || name.hasPrefix("tun")
                    || name.hasPrefix("tap") || name.hasPrefix("wg")
            }
            return false
        }
    }
}
