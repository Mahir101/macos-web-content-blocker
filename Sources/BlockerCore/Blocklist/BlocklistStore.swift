import Foundation

/// Manages the three domain lists plus the whitelist:
///
///   permanent — KeywordLists.knownAdultDomains, compiled in
///   runtime   — domains auto-added by enforcement
///   custom    — domains the user added by hand (supports wildcards)
///
/// After every mutation a plain-text export of all blocked domains is
/// written for the root hosts-sync daemon to apply at the DNS level.
public final class BlocklistStore: @unchecked Sendable {
    private let runtimeURL: URL
    private let customURL: URL
    private let importedURL: URL
    private let whitelistURL: URL
    private let exportURL: URL
    private let queue = DispatchQueue(label: "blocker.blocklist")

    // Cached lookup structures, rebuilt lazily and invalidated on
    // mutation. The imported list can be huge, so we never rescan it
    // linearly per page.
    private var cachedBlockedSet: DomainSet?
    private var cachedWhitelistSet: DomainSet?

    public init(
        runtimeURL: URL = Paths.runtimeBlocklistFile,
        customURL: URL = Paths.customBlocklistFile,
        importedURL: URL = Paths.importedBlocklistFile,
        whitelistURL: URL = Paths.whitelistFile,
        exportURL: URL = Paths.domainExportFile
    ) {
        self.runtimeURL = runtimeURL
        self.customURL = customURL
        self.importedURL = importedURL
        self.whitelistURL = whitelistURL
        self.exportURL = exportURL
    }

    // MARK: - Reads

    public var permanentDomains: [String] { KeywordLists.knownAdultDomains }
    public var runtimeDomains: [String] { queue.sync { read(runtimeURL) } }
    public var customDomains: [String] { queue.sync { read(customURL) } }
    public var importedDomainCount: Int { queue.sync { read(importedURL).count } }
    public var whitelistedDomains: [String] { queue.sync { read(whitelistURL) } }

    /// Runtime + custom (the lists the detection engine adds on top of
    /// the compiled-in permanent list).
    public var extraBlockedDomains: [String] {
        queue.sync { read(runtimeURL) + read(customURL) + read(importedURL) }
    }

    public var allBlockedDomains: [String] {
        queue.sync { allBlockedDomainsLocked() }
    }

    /// Fast lookup structure over every blocked domain (cached).
    public func blockedDomainSet() -> DomainSet {
        queue.sync {
            if let cached = cachedBlockedSet { return cached }
            let set = DomainSet(domains: allBlockedDomainsLocked())
            cachedBlockedSet = set
            return set
        }
    }

    /// Fast lookup structure over the whitelist (cached).
    public func whitelistSet() -> DomainSet {
        queue.sync {
            if let cached = cachedWhitelistSet { return cached }
            let set = DomainSet(domains: read(whitelistURL))
            cachedWhitelistSet = set
            return set
        }
    }

    /// Caller must already hold `queue`.
    private func allBlockedDomainsLocked() -> [String] {
        permanentDomains + read(runtimeURL) + read(customURL) + read(importedURL)
    }

    public func isBlocked(host: String) -> Bool {
        if whitelistSet().contains(host: host) { return false }
        return blockedDomainSet().contains(host: host)
    }

    // MARK: - Mutations

    /// Adds a domain discovered at runtime. Returns true if it was new.
    @discardableResult
    public func addRuntimeDomain(_ domain: String) -> Bool {
        addDomain(domain, to: runtimeURL)
    }

    @discardableResult
    public func addCustomDomain(_ domain: String) -> Bool {
        addDomain(domain, to: customURL)
    }

    public func removeCustomDomain(_ domain: String) {
        removeDomain(domain, from: customURL)
    }

    public func removeRuntimeDomain(_ domain: String) {
        removeDomain(domain, from: runtimeURL)
    }

    @discardableResult
    public func addWhitelistedDomain(_ domain: String) -> Bool {
        queue.sync {
            let normalized = normalizePattern(domain)
            guard !normalized.isEmpty else { return false }
            var list = read(whitelistURL)
            guard !list.contains(normalized) else { return false }
            list.append(normalized)
            write(list, to: whitelistURL)
            cachedWhitelistSet = nil
            return true
        }
    }

    public func removeWhitelistedDomain(_ domain: String) {
        queue.sync {
            var list = read(whitelistURL)
            list.removeAll { $0 == normalizePattern(domain) }
            write(list, to: whitelistURL)
            cachedWhitelistSet = nil
        }
    }

    // MARK: - Bulk import

    /// Replaces the imported list with the domains parsed from an
    /// /etc/hosts-format file. Returns the number of domains stored.
    @discardableResult
    public func importHostsFile(at url: URL) throws -> Int {
        let domains = try HostsImporter.parse(contentsOf: url)
        return queue.sync {
            let unique = Array(Set(domains)).sorted()
            write(unique, to: importedURL)
            cachedBlockedSet = nil
            writeExportLocked()
            return unique.count
        }
    }

    // MARK: - Hosts export

    /// One domain per line; wildcard prefixes are stripped because the
    /// hosts file cannot express them (the AX layer still covers
    /// arbitrary subdomains).
    public func writeExport() {
        queue.sync { writeExportLocked() }
    }

    public func exportText() -> String {
        queue.sync { exportTextLocked() }
    }

    /// Caller must already hold `queue`.
    private func exportTextLocked() -> String {
        let domains = allBlockedDomainsLocked()
            .map { pattern -> String in
                var p = pattern
                if p.hasPrefix("*.") { p.removeFirst(2) }
                return DomainMatcher.normalize(p)
            }
        return Set(domains).sorted().joined(separator: "\n") + "\n"
    }

    // MARK: - Private

    private func addDomain(_ domain: String, to url: URL) -> Bool {
        queue.sync {
            let normalized = normalizePattern(domain)
            guard !normalized.isEmpty else { return false }
            var list = read(url)
            guard !list.contains(normalized) else { return false }
            list.append(normalized)
            write(list, to: url)
            cachedBlockedSet = nil
            writeExportLocked()
            return true
        }
    }

    private func removeDomain(_ domain: String, from url: URL) {
        queue.sync {
            var list = read(url)
            list.removeAll { $0 == normalizePattern(domain) }
            write(list, to: url)
            cachedBlockedSet = nil
            writeExportLocked()
        }
    }

    private func normalizePattern(_ domain: String) -> String {
        var pattern = domain.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let hasWildcard = pattern.hasPrefix("*.")
        if hasWildcard { pattern.removeFirst(2) }
        pattern = DomainMatcher.normalize(pattern)
        guard pattern.contains("."), !pattern.contains(" ") else { return "" }
        return hasWildcard ? "*." + pattern : pattern
    }

    private func read(_ url: URL) -> [String] {
        guard let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder.blocker.decode([String].self, from: data)
        else { return [] }
        return list
    }

    private func write(_ list: [String], to url: URL) {
        try? Paths.ensureSupportDirectoryExists()
        guard let data = try? JSONEncoder.blocker.encode(list) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func writeExportLocked() {
        try? Paths.ensureSupportDirectoryExists()
        try? exportTextLocked().data(using: .utf8)?.write(to: exportURL, options: .atomic)
    }
}
