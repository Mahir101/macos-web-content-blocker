import Foundation

public struct SupportedBrowser: Sendable, Equatable {
    public let bundleID: String
    public let displayName: String
}

public enum SupportedBrowsers {
    public static let all: [SupportedBrowser] = [
        .init(bundleID: "com.google.Chrome", displayName: "Google Chrome"),
        .init(bundleID: "org.chromium.Chromium", displayName: "Chromium"),
        .init(bundleID: "com.brave.Browser", displayName: "Brave"),
        .init(bundleID: "com.microsoft.edgemac", displayName: "Microsoft Edge"),
        .init(bundleID: "com.apple.Safari", displayName: "Safari"),
        .init(bundleID: "org.mozilla.firefox", displayName: "Firefox"),
    ]

    public static let bundleIDs: Set<String> = Set(all.map(\.bundleID))

    public static func browser(for bundleID: String) -> SupportedBrowser? {
        all.first { $0.bundleID == bundleID }
    }
}
