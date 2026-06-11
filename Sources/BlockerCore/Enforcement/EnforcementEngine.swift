import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

/// Escalating enforcement:
///
///   step 0  close the active tab (Cmd+W posted to the browser pid)
///   step 1  close the focused window (AX close button, then Cmd+Shift+W)
///   step 2  terminate the browser process (graceful, then force)
///
/// The monitor rescans after each step; if the same browser still shows
/// blocked content within the escalation window, the next detection
/// runs the next step. Every enforcement also adds the domain to the
/// runtime blocklist and starts the cooldown timer.
@MainActor
public final class EnforcementEngine {
    public enum Action: String, Sendable {
        case closedTab = "closed-tab"
        case closedWindow = "closed-window"
        case terminatedBrowser = "terminated-browser"
    }

    private struct Escalation {
        var step: Int
        var lastDetection: Date
    }

    /// Detections in the same browser within this window escalate.
    private let escalationWindow: TimeInterval = 12
    private var escalations: [pid_t: Escalation] = [:]

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

    /// Runs one escalation step and records the event. Returns the
    /// action taken.
    @discardableResult
    public func enforce(
        detection: DetectionResult,
        snapshot: PageSnapshot,
        pid: pid_t
    ) -> Action {
        let now = Date()
        let config = configStore.load()

        var step = 0
        if let existing = escalations[pid],
           now.timeIntervalSince(existing.lastDetection) < escalationWindow {
            step = existing.step + 1
        }
        // During cooldown a re-detection of the same domain skips
        // straight to killing the browser.
        let state = stateStore.load()
        if state.inCooldown,
           let domain = detection.matchedDomain,
           domain == state.lastDetectionDomain {
            step = max(step, 2)
        }
        escalations[pid] = Escalation(step: step, lastDetection: now)

        let action: Action
        switch step {
        case 0:
            closeActiveTab(pid: pid)
            action = .closedTab
        case 1:
            closeFocusedWindow(pid: pid)
            action = .closedWindow
        default:
            terminateBrowser(pid: pid)
            action = .terminatedBrowser
            escalations[pid] = nil
        }

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

    public func resetEscalation(pid: pid_t) {
        escalations[pid] = nil
    }

    // MARK: - Actions

    private func closeActiveTab(pid: pid_t) {
        postKeystroke(pid: pid, keyCode: 13 /* W */, flags: .maskCommand)
    }

    private func closeFocusedWindow(pid: pid_t) {
        let app = AXUIElementCreateApplication(pid)
        if let window = AX.focusedWindow(of: app),
           let closeButton = AX.element(window, kAXCloseButtonAttribute),
           AX.press(closeButton) {
            return
        }
        postKeystroke(pid: pid, keyCode: 13 /* W */, flags: [.maskCommand, .maskShift])
    }

    private func terminateBrowser(pid: pid_t) {
        guard let app = NSRunningApplication(processIdentifier: pid) else { return }
        if !app.terminate() {
            app.forceTerminate()
        }
        // Belt and braces: if it is still alive shortly after, force it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            if let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated {
                app.forceTerminate()
            }
        }
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
