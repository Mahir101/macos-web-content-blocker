import AppKit
import BlockerCore
import Foundation

// blockerd — the background LaunchAgent service.
//
// Runs an AppKit run loop (required for AXObserver run-loop sources and
// NSWorkspace notifications) with no Dock icon or menu bar presence.
// All real work is event-driven inside BlockerService.

let arguments = ProcessInfo.processInfo.arguments

// Ensure the support directory and a default config exist.
try? Paths.ensureSupportDirectoryExists()
let configStore = ConfigStore()
_ = configStore.load()

// One-shot mode: `blockerd --import-hosts <file>` imports an
// /etc/hosts-format blocklist into the imported list and exits.
if let flagIndex = arguments.firstIndex(of: "--import-hosts") {
    let path = arguments.indices.contains(flagIndex + 1) ? arguments[flagIndex + 1] : nil
    guard let path else {
        FileHandle.standardError.write(Data("usage: blockerd --import-hosts <file>\n".utf8))
        exit(2)
    }
    do {
        let count = try BlocklistStore().importHostsFile(at: URL(fileURLWithPath: path))
        FileHandle.standardError.write(Data("blockerd: imported \(count) domains\n".utf8))
        exit(0)
    } catch {
        FileHandle.standardError.write(Data("blockerd: import failed: \(error)\n".utf8))
        exit(1)
    }
}

// Accessibility is mandatory. If not yet trusted, prompt and keep
// running so that the moment the user grants it, monitoring begins
// (the run loop stays alive; we re-check periodically).
if !AccessibilityPermissions.isTrusted {
    AccessibilityPermissions.requestIfNeeded()
    FileHandle.standardError.write(Data(
        "blockerd: waiting for Accessibility permission…\n".utf8
    ))
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon

final class DaemonController: NSObject, NSApplicationDelegate, @unchecked Sendable {
    private var service: BlockerService?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MainActor.assumeIsolated { startWhenPermitted() }
    }

    @MainActor
    private func startWhenPermitted() {
        if AccessibilityPermissions.isTrusted {
            let service = BlockerService()
            service.start()
            self.service = service
            FileHandle.standardError.write(Data("blockerd: monitoring started\n".utf8))
        } else {
            // Re-check every 5s until granted; cheap and event-light.
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] timer in
                guard AccessibilityPermissions.isTrusted else { return }
                timer.invalidate()
                MainActor.assumeIsolated {
                    let service = BlockerService()
                    service.start()
                    self?.service = service
                    FileHandle.standardError.write(Data("blockerd: monitoring started\n".utf8))
                }
            }
        }
    }
}

let delegate = DaemonController()
app.delegate = delegate
app.run()
