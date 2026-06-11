import Foundation

/// Hostname extraction and wildcard pattern matching.
///
/// Pattern semantics:
///   "example.com"    matches example.com and any subdomain
///   "*.example.com"  same (the wildcard form is accepted for clarity)
public enum DomainMatcher {
    /// Extracts a lowercase hostname from a URL string or a bare host.
    public static func host(from string: String) -> String? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let url = URL(string: trimmed), let host = url.host, !host.isEmpty {
            return normalize(host)
        }
        // Bare host like "example.com" or "example.com/path"
        var candidate = trimmed
        if let schemeRange = candidate.range(of: "://") {
            candidate = String(candidate[schemeRange.upperBound...])
        }
        candidate = candidate
            .split(separator: "/", maxSplits: 1)[0]
            .split(separator: "?", maxSplits: 1)[0]
            .split(separator: ":", maxSplits: 1)[0]
            .lowercased()
        guard candidate.contains("."), !candidate.contains(" ") else { return nil }
        return normalize(candidate)
    }

    public static func normalize(_ host: String) -> String {
        var host = host.lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        if host.hasSuffix(".") { host.removeLast() }
        return host
    }

    public static func matches(host: String, pattern: String) -> Bool {
        let host = normalize(host)
        var pattern = pattern.lowercased().trimmingCharacters(in: .whitespaces)
        if pattern.hasPrefix("*.") { pattern.removeFirst(2) }
        pattern = normalize(pattern)
        guard !pattern.isEmpty else { return false }
        return host == pattern || host.hasSuffix("." + pattern)
    }

    public static func matches(host: String, patterns: some Sequence<String>) -> Bool {
        patterns.contains { matches(host: host, pattern: $0) }
    }
}
