import Foundation

/// Everything the accessibility layer was able to read about the
/// frontmost browser page. Never contains screenshots or keystrokes.
public struct PageSnapshot: Sendable {
    public var browserName: String
    public var bundleID: String
    public var windowTitle: String
    public var urlString: String?
    public var headings: [String]
    public var linkTexts: [String]
    public var buttonTexts: [String]
    public var staticTexts: [String]

    public init(
        browserName: String,
        bundleID: String,
        windowTitle: String,
        urlString: String? = nil,
        headings: [String] = [],
        linkTexts: [String] = [],
        buttonTexts: [String] = [],
        staticTexts: [String] = []
    ) {
        self.browserName = browserName
        self.bundleID = bundleID
        self.windowTitle = windowTitle
        self.urlString = urlString
        self.headings = headings
        self.linkTexts = linkTexts
        self.buttonTexts = buttonTexts
        self.staticTexts = staticTexts
    }

    public var host: String? {
        urlString.flatMap(DomainMatcher.host(from:))
    }

    /// Chrome's extension manager lists extension names that can
    /// legitimately contain blocked keywords (e.g. a porn-blocker
    /// extension), so this one internal page is exempt from scoring.
    public var isChromeExtensionsPage: Bool {
        urlString?.lowercased().hasPrefix("chrome://extensions") == true
    }

    /// Combined text used for keyword scanning. Title and URL are
    /// included so title-only detections work when the AX tree is
    /// unreadable (e.g. Firefox with accessibility partially disabled).
    public var combinedText: String {
        var parts = [windowTitle]
        if let urlString { parts.append(urlString) }
        parts.append(contentsOf: headings)
        parts.append(contentsOf: linkTexts)
        parts.append(contentsOf: buttonTexts)
        parts.append(contentsOf: staticTexts)
        return parts.joined(separator: "\n").lowercased()
    }
}
