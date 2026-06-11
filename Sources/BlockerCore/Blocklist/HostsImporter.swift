import Foundation

/// Parses a `/etc/hosts`-format blocklist into bare domains.
///
/// Accepted line shapes (comments after `#` and blank lines ignored):
///   0.0.0.0 evil.com
///   127.0.0.1 evil.com
///   evil.com
///
/// Loopback / localhost entries and obviously non-domain tokens are
/// dropped.
public enum HostsImporter {
    private static let skipHosts: Set<String> = [
        "localhost", "localhost.localdomain", "local",
        "broadcasthost", "ip6-localhost", "ip6-loopback",
    ]

    public static func parse(text: String) -> [String] {
        var domains: [String] = []
        domains.reserveCapacity(text.count / 24)

        text.enumerateLines { line, _ in
            // Strip trailing comment.
            var content = line
            if let hash = content.firstIndex(of: "#") {
                content = String(content[..<hash])
            }
            content = content.trimmingCharacters(in: .whitespaces)
            guard !content.isEmpty else { return }

            let tokens = content.split(whereSeparator: { $0 == " " || $0 == "\t" })
            // Either "IP domain" (2 tokens) or a bare "domain" (1 token).
            let domainToken: Substring?
            if tokens.count >= 2 {
                domainToken = tokens[1]
            } else if tokens.count == 1 {
                domainToken = tokens[0]
            } else {
                domainToken = nil
            }

            guard let token = domainToken else { return }
            let candidate = String(token).lowercased()
            guard candidate.contains("."),
                  !skipHosts.contains(candidate),
                  let host = DomainMatcher.host(from: candidate)
            else { return }
            domains.append(host)
        }
        return domains
    }

    public static func parse(contentsOf url: URL) throws -> [String] {
        let text = try String(contentsOf: url, encoding: .utf8)
        return parse(text: text)
    }
}
