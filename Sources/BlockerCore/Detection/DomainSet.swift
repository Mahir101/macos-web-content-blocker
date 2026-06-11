import Foundation

/// Efficient blocked-domain lookup for large lists (tens of thousands
/// of entries). Exact domains go in a hash set; a host matches if it,
/// or any of its parent suffixes, is in the set — so "sub.evil.com"
/// matches the entry "evil.com" in O(number of labels), not O(list).
///
/// Wildcard patterns ("*.evil.com") are kept separately and matched as
/// suffix-only rules.
public struct DomainSet: Sendable {
    private let exact: Set<String>
    private let wildcardBases: [String]

    public init(domains: some Sequence<String>) {
        var exact = Set<String>()
        var wild: [String] = []
        for raw in domains {
            var pattern = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !pattern.isEmpty else { continue }
            if pattern.hasPrefix("*.") {
                pattern.removeFirst(2)
                let base = DomainMatcher.normalize(pattern)
                if !base.isEmpty { wild.append(base) }
            } else {
                let host = DomainMatcher.normalize(pattern)
                if !host.isEmpty { exact.insert(host) }
            }
        }
        self.exact = exact
        self.wildcardBases = wild
    }

    public var isEmpty: Bool { exact.isEmpty && wildcardBases.isEmpty }
    public var count: Int { exact.count + wildcardBases.count }

    /// Returns the matched pattern if the host is blocked, else nil.
    public func match(host: String) -> String? {
        let host = DomainMatcher.normalize(host)
        guard !host.isEmpty else { return nil }

        // Walk the host and every parent suffix against the exact set.
        var candidate = Substring(host)
        while true {
            if exact.contains(String(candidate)) { return String(candidate) }
            guard let dot = candidate.firstIndex(of: ".") else { break }
            candidate = candidate[candidate.index(after: dot)...]
        }

        for base in wildcardBases where host == base || host.hasSuffix("." + base) {
            return "*." + base
        }
        return nil
    }

    public func contains(host: String) -> Bool { match(host: host) != nil }
}
