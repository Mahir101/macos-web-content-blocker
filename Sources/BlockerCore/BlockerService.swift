import AppKit
import Foundation

/// Top-level orchestrator wired together by the daemon. Owns the
/// browser monitor, detection engine, enforcement engine, VPN watcher,
/// and the shared stores. Reacts to page snapshots by scoring them and
/// enforcing when the threshold is crossed.
@MainActor
public final class BlockerService {
    public let configStore: ConfigStore
    public let stateStore: StateStore
    public let blocklist: BlocklistStore
    public let logger: EventLogger
    private let enforcement: EnforcementEngine
    private var monitor: BrowserMonitor!
    private let vpnWatcher: VPNWatcher

    public init(
        configStore: ConfigStore = ConfigStore(),
        stateStore: StateStore = StateStore(),
        blocklist: BlocklistStore = BlocklistStore(),
        logger: EventLogger = EventLogger()
    ) {
        self.configStore = configStore
        self.stateStore = stateStore
        self.blocklist = blocklist
        self.logger = logger
        self.enforcement = EnforcementEngine(
            blocklist: blocklist,
            logger: logger,
            stateStore: stateStore,
            configStore: configStore
        )
        self.vpnWatcher = VPNWatcher { active in
            stateStore.update { $0.vpnActive = active }
        }
        self.monitor = BrowserMonitor { [weak self] observation in
            self?.handle(observation)
        }
    }

    public func start() {
        stateStore.update { $0.runningSince = Date() }
        blocklist.writeExport()
        vpnWatcher.start()
        monitor.start()
    }

    public func stop() {
        monitor.stop()
        vpnWatcher.stop()
    }

    // MARK: - Snapshot handling

    private func handle(_ observation: BrowserMonitor.Observation) {
        guard configStore.load().enabled else { return }

        let engine = makeEngine()
        let result = engine.evaluate(observation.snapshot)

        guard result.shouldBlock else { return }

        let action = enforcement.enforce(
            detection: result,
            snapshot: observation.snapshot,
            pid: observation.pid
        )

        // Re-scan shortly after a tab close to catch the page underneath
        // (it gets its own tab-close if it is also blocked).
        if action == .closedTab {
            let pid = observation.pid
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.monitor.scanNow(pid: pid)
            }
        }
    }

    private func makeEngine() -> DetectionEngine {
        let config = configStore.load()
        return DetectionEngine(
            threshold: config.blockThreshold,
            blockedDomains: blocklist.blockedDomainSet(),
            whitelist: blocklist.whitelistSet()
        )
    }
}
