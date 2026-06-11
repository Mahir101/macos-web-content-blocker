import BlockerCore
import Combine
import Foundation
import SwiftUI

/// Observable bridge between the SwiftUI dashboard and the on-disk
/// stores the daemon writes. Polls lightly (1s) since the UI is only
/// open while the user is looking at it.
@MainActor
final class AppModel: ObservableObject {
    @Published var config: AppConfig
    @Published var state: ServiceState
    @Published var customDomains: [String] = []
    @Published var runtimeDomains: [String] = []
    @Published var whitelist: [String] = []
    @Published var recentEvents: [BlockEvent] = []
    @Published var accessibilityTrusted: Bool = AccessibilityPermissions.isTrusted
    @Published var disableStatus: TamperGuard.DisableStatus = .notRequested

    private let configStore = ConfigStore()
    private let stateStore = StateStore()
    private let blocklist = BlocklistStore()
    private let logger = EventLogger()
    private let tamperGuard: TamperGuard
    private var timer: Timer?

    init() {
        let configStore = self.configStore
        self.config = configStore.load()
        self.state = stateStore.load()
        self.tamperGuard = TamperGuard(configStore: configStore)
        refresh()
    }

    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func stopPolling() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        configStore.invalidateCache()
        config = configStore.load()
        state = stateStore.load()
        customDomains = blocklist.customDomains.sorted()
        runtimeDomains = blocklist.runtimeDomains.sorted()
        whitelist = blocklist.whitelistedDomains.sorted()
        recentEvents = logger.recentEvents(limit: 50)
        accessibilityTrusted = AccessibilityPermissions.isTrusted
        disableStatus = tamperGuard.status()
    }

    // MARK: - Mutations

    func updateThreshold(_ value: Int) {
        config = configStore.update { $0.blockThreshold = max(10, value) }
    }

    func updateCooldown(_ seconds: TimeInterval) {
        config = configStore.update { $0.cooldownSeconds = max(0, seconds) }
    }

    func addCustomDomain(_ domain: String) {
        blocklist.addCustomDomain(domain)
        refresh()
    }

    func removeCustomDomain(_ domain: String) {
        blocklist.removeCustomDomain(domain)
        refresh()
    }

    func addWhitelistDomain(_ domain: String) {
        blocklist.addWhitelistedDomain(domain)
        refresh()
    }

    func removeWhitelistDomain(_ domain: String) {
        blocklist.removeWhitelistedDomain(domain)
        refresh()
    }

    // MARK: - Tamper guard

    func requestDisable() {
        tamperGuard.requestDisable()
        refresh()
    }

    func cancelDisable() {
        tamperGuard.cancelDisable()
        refresh()
    }

    func confirmDisable() {
        tamperGuard.confirmDisable()
        refresh()
    }

    func reEnable() {
        tamperGuard.reEnable()
        refresh()
    }

    func requestAccessibility() {
        AccessibilityPermissions.requestIfNeeded()
    }
}
