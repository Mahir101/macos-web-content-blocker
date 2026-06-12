import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Tab-only enforcement: when a page is blocked, close the active tab
/// (Cmd+W posted to the browser pid) — and nothing more. The browser
/// window and process are never touched. If the browser has no focused
/// window, enforcement is skipped entirely.
///
/// Every enforcement also adds the domain to the runtime blocklist and
/// records an event.
@MainActor
public final class EnforcementEngine {
    public enum Action: String, Sendable {
        case closedTab = "closed-tab"
        case skipped = "skipped"
    }

    private let blocklist: BlocklistStore
    private let logger: EventLogger
    private let stateStore: StateStore
    private let configStore: ConfigStore
    private let audio: AudioAlerter

    public init(
        blocklist: BlocklistStore,
        logger: EventLogger,
        stateStore: StateStore,
        configStore: ConfigStore,
        audio: AudioAlerter = AudioAlerter()
    ) {
        self.blocklist = blocklist
        self.logger = logger
        self.stateStore = stateStore
        self.configStore = configStore
        self.audio = audio
    }

    /// Closes the active tab and records the event. Returns the action
    /// taken. Does nothing when the browser has no focused window.
    @discardableResult
    public func enforce(
        detection: DetectionResult,
        snapshot: PageSnapshot,
        pid: pid_t
    ) -> Action {
        let now = Date()
        let config = configStore.load()

        let app = AXUIElementCreateApplication(pid)
        guard AX.focusedWindow(of: app) != nil else { return .skipped }

        closeActiveTab(pid: pid)
        let action: Action = .closedTab

        audio.play()

        if let domain = detection.matchedDomain {
            blocklist.addRuntimeDomain(domain)
        }

        stateStore.update { state in
            state.detectionsTotal += 1
            state.lastDetectionAt = now
            state.lastDetectionDomain = detection.matchedDomain
            state.cooldownUntil = now.addingTimeInterval(config.cooldownSeconds)
        }

        logger.log(BlockEvent(
            browser: snapshot.browserName,
            trigger: detection.triggerReason,
            domain: detection.matchedDomain,
            score: detection.score,
            action: action.rawValue
        ))
        return action
    }

    // MARK: - Actions

    private func closeActiveTab(pid: pid_t) {
        postKeystroke(pid: pid, keyCode: 13 /* W */, flags: .maskCommand)
    }

    private func postKeystroke(pid: pid_t, keyCode: CGKeyCode, flags: CGEventFlags) {
        guard let source = CGEventSource(stateID: .hidSystemState),
              let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true),
              let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        else { return }
        keyDown.flags = flags
        keyUp.flags = flags
        keyDown.postToPid(pid)
        keyUp.postToPid(pid)
    }
}
