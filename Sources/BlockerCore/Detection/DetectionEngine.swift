import Foundation

public struct DetectionSignal: Sendable, Equatable {
    public enum Kind: String, Sendable, Codable {
        case knownDomain
        case siteTitleMatch
        case categoryKeyword
        case isolatedKeyword
    }

    public var kind: Kind
    public var matched: String
    public var points: Int
}

public struct DetectionResult: Sendable {
    public var score: Int
    public var signals: [DetectionSignal]
    public var matchedDomain: String?
    public var shouldBlock: Bool

    public var triggerReason: String {
        signals.map { "\($0.kind.rawValue):\($0.matched)(+\($0.points))" }
            .joined(separator: ", ")
    }
}

/// Confidence-scoring classifier over a PageSnapshot.
///
///   known adult domain        +100  (blocks on its own)
///   brand name in title       +50
///   category keyword          +30 each (capped at 90)
///   isolated keyword          +10 each (capped at 30)
///
/// Whitelisted hosts always score 0.
public struct DetectionEngine: Sendable {
    public var threshold: Int
    /// Fast lookup over the full blocked-domain list (permanent +
    /// runtime + custom + imported).
    public var blockedDomains: DomainSet
    public var whitelist: DomainSet

    private static let scoreKnownDomain = 100
    private static let scoreTitleMatch = 50
    private static let scoreCategoryKeyword = 30
    private static let categoryCap = 90
    private static let scoreIsolatedKeyword = 10
    private static let isolatedCap = 30

    public init(
        threshold: Int = 100,
        blockedDomains: DomainSet = DomainSet(domains: KeywordLists.knownAdultDomains),
        whitelist: DomainSet = DomainSet(domains: [])
    ) {
        self.threshold = threshold
        self.blockedDomains = blockedDomains
        self.whitelist = whitelist
    }

    public func evaluate(_ snapshot: PageSnapshot) -> DetectionResult {
        if let host = snapshot.host, whitelist.contains(host: host) {
            return DetectionResult(score: 0, signals: [], matchedDomain: nil, shouldBlock: false)
        }

        var signals: [DetectionSignal] = []
        var matchedDomain: String?

        // -- High confidence: known / user-blocked domain ------------------
        if let host = snapshot.host, let pattern = blockedDomains.match(host: host) {
            signals.append(.init(kind: .knownDomain, matched: pattern, points: Self.scoreKnownDomain))
            matchedDomain = host
        }

        let text = snapshot.combinedText

        // Cheap pre-filter: skip keyword scoring when nothing relevant
        // appears anywhere in the text.
        let mayContainSignals = KeywordLists.prefilterFragments.contains { text.contains($0) }

        if mayContainSignals {
            // -- High confidence: brand names in the title -----------------
            let title = snapshot.windowTitle.lowercased()
            if let brand = KeywordLists.adultBrandNames.first(where: { title.contains($0) }) {
                signals.append(.init(kind: .siteTitleMatch, matched: brand, points: Self.scoreTitleMatch))
            }

            // -- Medium confidence: category keywords ----------------------
            var categoryPoints = 0
            for keyword in KeywordLists.categoryKeywords where categoryPoints < Self.categoryCap {
                if containsWord(keyword, in: text) {
                    signals.append(.init(kind: .categoryKeyword, matched: keyword, points: Self.scoreCategoryKeyword))
                    categoryPoints += Self.scoreCategoryKeyword
                }
            }

            // -- Low confidence: isolated keywords -------------------------
            var isolatedPoints = 0
            for keyword in KeywordLists.isolatedKeywords where isolatedPoints < Self.isolatedCap {
                if containsWord(keyword, in: text) {
                    signals.append(.init(kind: .isolatedKeyword, matched: keyword, points: Self.scoreIsolatedKeyword))
                    isolatedPoints += Self.scoreIsolatedKeyword
                }
            }
        }

        let score = signals.reduce(0) { $0 + $1.points }
        if matchedDomain == nil, score >= threshold {
            matchedDomain = snapshot.host
        }

        return DetectionResult(
            score: score,
            signals: signals,
            matchedDomain: matchedDomain,
            shouldBlock: score >= threshold
        )
    }

    /// Word-boundary match so "sex" never fires on "Sussex" or
    /// "analysis". Keywords containing non-word characters ("18+")
    /// fall back to substring matching with boundary checks.
    func containsWord(_ keyword: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: keyword)
        let pattern = "(?<![\\p{L}\\p{N}])\(escaped)(?![\\p{L}\\p{N}])"
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
}
