import AppKit
import ApplicationServices
import Foundation

/// Event-driven monitor over all supported browsers.
///
/// For each running browser an AXObserver is registered for focus,
/// window, title, and value-change notifications. When any fires, the
/// frontmost page is snapshotted and handed to the callback. There is
/// no polling loop — a low-frequency debounce timer only coalesces
/// bursts of notifications and provides a safety re-scan.
@MainActor
public final class BrowserMonitor {
    public struct Observation: Sendable {
        public let snapshot: PageSnapshot
        public let pid: pid_t
    }

    private let onSnapshot: @MainActor (Observation) -> Void
    private var observers: [pid_t: AXObserver] = [:]
    private var appElements: [pid_t: AXUIElement] = [:]
    private var workspaceTokens: [NSObjectProtocol] = []
    private var debounceWork: DispatchWorkItem?
    private var pendingPID: pid_t?

    /// Coalesce window so rapid notification bursts produce one scan.
    private let debounceInterval: TimeInterval = 0.35

    public init(onSnapshot: @escaping @MainActor (Observation) -> Void) {
        self.onSnapshot = onSnapshot
    }

    // MARK: - Lifecycle

    public func start() {
        for app in NSWorkspace.shared.runningApplications {
            attachIfBrowser(app)
        }
        subscribeToWorkspace()
    }

    public func stop() {
        for (pid, observer) in observers {
            if let appEl = appElements[pid] {
                removeNotifications(observer: observer, element: appEl)
            }
            CFRunLoopRemoveSource(
                CFRunLoopGetCurrent(),
                AXObserverGetRunLoopSource(observer),
                .defaultMode
            )
        }
        observers.removeAll()
        appElements.removeAll()
        for token in workspaceTokens {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        workspaceTokens.removeAll()
        debounceWork?.cancel()
    }

    // MARK: - Workspace tracking

    private func subscribeToWorkspace() {
        let center = NSWorkspace.shared.notificationCenter
        let launch = center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.attachIfBrowser(app) }
        }
        let terminate = center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.detach(pid: app.processIdentifier) }
        }
        let activate = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            else { return }
            MainActor.assumeIsolated { self?.scheduleScan(pid: app.processIdentifier) }
        }
        workspaceTokens = [launch, terminate, activate]
    }

    // MARK: - Per-browser observers

    private func attachIfBrowser(_ app: NSRunningApplication) {
        guard let bundleID = app.bundleIdentifier,
              SupportedBrowsers.bundleIDs.contains(bundleID) else { return }
        let pid = app.processIdentifier
        guard observers[pid] == nil else { return }

        let appElement = AXUIElementCreateApplication(pid)
        var observer: AXObserver?
        let result = AXObserverCreate(pid, axObserverCallback, &observer)
        guard result == .success, let observer else { return }

        let context = Unmanaged.passUnretained(self).toOpaque()
        for notification in Self.notifications {
            AXObserverAddNotification(observer, appElement, notification as CFString, context)
        }
        CFRunLoopAddSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
        observers[pid] = observer
        appElements[pid] = appElement
        scheduleScan(pid: pid)
    }

    private func detach(pid: pid_t) {
        guard let observer = observers.removeValue(forKey: pid) else { return }
        if let appEl = appElements.removeValue(forKey: pid) {
            removeNotifications(observer: observer, element: appEl)
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetCurrent(),
            AXObserverGetRunLoopSource(observer),
            .defaultMode
        )
    }

    private static let notifications = [
        kAXFocusedWindowChangedNotification,
        kAXMainWindowChangedNotification,
        kAXWindowCreatedNotification,
        kAXTitleChangedNotification,
        kAXValueChangedNotification,
        kAXFocusedUIElementChangedNotification,
    ]

    private func removeNotifications(observer: AXObserver, element: AXUIElement) {
        for notification in Self.notifications {
            AXObserverRemoveNotification(observer, element, notification as CFString)
        }
    }

    // MARK: - Scanning

    fileprivate func notificationFired(pid: pid_t) {
        scheduleScan(pid: pid)
    }

    private func scheduleScan(pid: pid_t) {
        guard observers[pid] != nil else { return }
        pendingPID = pid
        debounceWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, let pid = self.pendingPID else { return }
                self.scanNow(pid: pid)
            }
        }
        debounceWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + debounceInterval, execute: work)
    }

    /// Snapshots the frontmost window of the given browser. Public so
    /// the daemon can force an immediate re-scan after enforcement.
    public func scanNow(pid: pid_t) {
        guard let appElement = appElements[pid],
              let bundleID = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier,
              let browser = SupportedBrowsers.browser(for: bundleID)
        else { return }

        guard let window = AX.focusedWindow(of: appElement) else { return }
        let windowTitle = AX.string(window, kAXTitleAttribute) ?? ""
        let content = WebContentReader.read(window: window)

        let snapshot = PageSnapshot(
            browserName: browser.displayName,
            bundleID: bundleID,
            windowTitle: windowTitle,
            urlString: content.url,
            headings: content.headings,
            linkTexts: content.linkTexts,
            buttonTexts: content.buttonTexts,
            staticTexts: content.staticTexts
        )
        onSnapshot(Observation(snapshot: snapshot, pid: pid))
    }
}

/// C callback bridged back to the BrowserMonitor instance.
private func axObserverCallback(
    _ observer: AXObserver,
    _ element: AXUIElement,
    _ notification: CFString,
    _ refcon: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let monitor = Unmanaged<BrowserMonitor>.fromOpaque(refcon).takeUnretainedValue()
    var pid: pid_t = 0
    AXUIElementGetPid(element, &pid)
    MainActor.assumeIsolated {
        monitor.notificationFired(pid: pid)
    }
}
