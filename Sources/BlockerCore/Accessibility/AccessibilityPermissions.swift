import ApplicationServices
import Foundation

public enum AccessibilityPermissions {
    /// Whether this process is trusted to use the Accessibility API.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user (once) to grant access, opening System Settings
    /// to the Accessibility pane.
    @discardableResult
    public static func requestIfNeeded() -> Bool {
        // kAXTrustedCheckOptionPrompt is a global var (not concurrency-
        // safe to reference directly under Swift 6); its documented
        // value is the literal "AXTrustedCheckOptionPrompt".
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let options = [key: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
