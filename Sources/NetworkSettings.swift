import Foundation

struct NetworkSettings: Equatable {
    var proxyEnabled: Bool
    var proxyURLString: String
    var proxyBypassList: String = ""

    private static let proxyEnabledKey = "proxyEnabled"
    private static let proxyURLStringKey = "proxyURLString"
    private static let proxyBypassListKey = "proxyBypassList"

    static func load(defaults: UserDefaults = .standard) -> NetworkSettings {
        NetworkSettings(
            proxyEnabled: defaults.object(forKey: proxyEnabledKey) as? Bool ?? false,
            proxyURLString: defaults.string(forKey: proxyURLStringKey) ?? "",
            proxyBypassList: defaults.string(forKey: proxyBypassListKey) ?? ""
        )
    }

    func save(defaults: UserDefaults = .standard) {
        defaults.set(proxyEnabled, forKey: Self.proxyEnabledKey)
        defaults.set(proxyURLString.trimmed, forKey: Self.proxyURLStringKey)
        defaults.set(Self.normalizedBypassList(proxyBypassList), forKey: Self.proxyBypassListKey)
    }

    var normalizedProxyURLString: String? {
        Self.normalizedProxyURLString(proxyURLString)
    }

    var proxyArgument: String? {
        guard proxyEnabled else { return nil }
        return normalizedProxyURLString
    }

    func proxyArgument(for url: URL) -> String? {
        guard !bypassesProxy(for: url) else { return nil }
        return proxyArgument
    }

    var connectionProxyDictionary: [AnyHashable: Any]? {
        connectionProxyDictionary(for: nil)
    }

    func connectionProxyDictionary(for url: URL?) -> [AnyHashable: Any]? {
        guard proxyEnabled,
              url.map({ !bypassesProxy(for: $0) }) ?? true,
              let normalized = normalizedProxyURLString,
              let components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              let host = components.host,
              let port = components.port ?? Self.defaultPort(for: scheme)
        else {
            return nil
        }

        var dictionary: [AnyHashable: Any] = [:]
        switch scheme {
        case "http", "https":
            dictionary["HTTPEnable"] = 1
            dictionary["HTTPProxy"] = host
            dictionary["HTTPPort"] = port
            dictionary["HTTPSEnable"] = 1
            dictionary["HTTPSProxy"] = host
            dictionary["HTTPSPort"] = port
            if let user = components.user, !user.isEmpty {
                dictionary["HTTPUser"] = user
                dictionary["HTTPSUser"] = user
            }
            if let password = components.password, !password.isEmpty {
                dictionary["HTTPPassword"] = password
                dictionary["HTTPSPassword"] = password
            }
        case "socks4", "socks5":
            dictionary["SOCKSEnable"] = 1
            dictionary["SOCKSProxy"] = host
            dictionary["SOCKSPort"] = port
            if let user = components.user, !user.isEmpty {
                dictionary["SOCKSUser"] = user
            }
            if let password = components.password, !password.isEmpty {
                dictionary["SOCKSPassword"] = password
            }
        default:
            return nil
        }

        return dictionary
    }

    func bypassesProxy(for url: URL) -> Bool {
        guard proxyEnabled,
              let host = url.host?.lowercased(),
              !host.isEmpty else {
            return false
        }

        for pattern in Self.bypassPatterns(proxyBypassList) {
            if Self.host(host, matchesBypassPattern: pattern) {
                return true
            }
        }
        return false
    }

    static func normalizedProxyURLString(_ raw: String) -> String? {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return nil }

        let cleaned = cleanedProxyInput(trimmed)
        if isTorProxyAlias(cleaned) {
            return normalizedTorProxyURLString(cleaned)
        }

        let candidate = proxyURLCandidate(from: cleaned)
        guard var components = URLComponents(string: candidate),
              var scheme = components.scheme?.lowercased(),
              let host = components.host,
              !host.isEmpty
        else {
            return nil
        }

        if scheme == "socks" {
            scheme = "socks5"
        }

        guard ["http", "https", "socks4", "socks5"].contains(scheme) else {
            return nil
        }
        if let port = components.port,
           normalizedProxyPort(port) == nil {
            return nil
        }

        components.scheme = scheme
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.string
    }

    static func normalizedTorProxyURLString(_ raw: String) -> String? {
        let value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }

        if ["tor", "tor://", "tor socks", "tor-socks"].contains(value) {
            return torProxyURLString(port: 9050)
        }
        if ["torbrowser", "tor-browser", "tor browser", "tor://browser"].contains(value) {
            return torProxyURLString(port: 9150)
        }

        if let port = torPort(from: value) {
            return torProxyURLString(port: port)
        }

        guard value.hasPrefix("tor://"),
              var components = URLComponents(string: value) else {
            return nil
        }

        if components.host == "browser" || components.host == "torbrowser" || components.host == "tor-browser" {
            return torProxyURLString(port: components.port ?? 9150)
        }

        let host = components.host?.trimmed
        let port = components.port ?? 9050
        guard let host, !host.isEmpty, normalizedProxyPort(port) != nil else {
            return nil
        }

        components.scheme = "socks5"
        components.host = host
        components.port = port
        components.path = components.path == "/" ? "" : components.path
        components.query = nil
        components.fragment = nil
        return components.string
    }

    static func isTorProxyAlias(_ raw: String) -> Bool {
        let value = raw.trimmed.lowercased()
        return ["tor", "tor://", "tor socks", "tor-socks", "torbrowser", "tor-browser", "tor browser", "tor://browser"].contains(value) ||
            value.hasPrefix("tor:") ||
            value.hasPrefix("tor://") ||
            value.hasPrefix("tor-browser:") ||
            value.hasPrefix("torbrowser:")
    }

    static func normalizedBypassList(_ raw: String) -> String {
        bypassPatterns(raw).joined(separator: ",")
    }

    private static func cleanedProxyInput(_ raw: String) -> String {
        raw.trimmed
            .replacingOccurrences(of: "：", with: ":")
            .replacingOccurrences(of: "／", with: "/")
            .replacingOccurrences(of: "＼", with: "/")
            .replacingOccurrences(of: "\\", with: "/")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
    }

    private static func proxyURLCandidate(from raw: String) -> String {
        let value = raw.trimmed
        let lower = value.lowercased()
        let schemes = ["socks5", "socks4", "socks", "https", "http"]

        for scheme in schemes {
            if lower.hasPrefix("\(scheme)//") {
                return "\(scheme)://\(value.dropFirst(scheme.count + 2))"
            }
            if lower.hasPrefix("\(scheme):") && !lower.hasPrefix("\(scheme)://") {
                return "\(scheme)://\(String(value.dropFirst(scheme.count + 1)).trimmed)"
            }
        }

        let parts = value.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count == 2,
           Int(parts[1]).flatMap(normalizedProxyPort) != nil {
            return "http://\(parts[0]):\(parts[1])"
        }
        if parts.count == 3,
           schemes.contains(parts[0].lowercased()),
           Int(parts[2]).flatMap(normalizedProxyPort) != nil {
            return "\(parts[0].lowercased())://\(parts[1]):\(parts[2])"
        }

        return value.contains("://") ? value : "http://\(value)"
    }

    private static func bypassPatterns(_ raw: String) -> [String] {
        let separators = CharacterSet(charactersIn: ",;\n\r\t ")
        var output: [String] = []
        var seen = Set<String>()
        for part in raw.components(separatedBy: separators) {
            var value = part.trimmed.lowercased()
            if value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("socks4://") || value.hasPrefix("socks5://") {
                value = URLComponents(string: value)?.host?.lowercased() ?? value
            }
            value = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !value.isEmpty,
                  value.range(of: #"^\*?\.?[a-z0-9-]+(?:\.[a-z0-9-]+)*$"#, options: .regularExpression) != nil else {
                continue
            }
            if value.hasPrefix("*.") {
                value = String(value.dropFirst(2))
            } else if value.hasPrefix(".") {
                value = String(value.dropFirst())
            }
            guard !value.isEmpty,
                  !seen.contains(value),
                  !output.contains(where: { host(value, matchesBypassPattern: $0) }) else {
                continue
            }
            output.removeAll { host($0, matchesBypassPattern: value) }
            seen = Set(output)
            seen.insert(value)
            output.append(value)
        }
        return output
    }

    private static func host(_ host: String, matchesBypassPattern pattern: String) -> Bool {
        host == pattern || host.hasSuffix(".\(pattern)")
    }

    private static func torProxyURLString(port: Int) -> String? {
        guard let normalized = normalizedProxyPort(port) else { return nil }
        return "socks5://127.0.0.1:\(normalized)"
    }

    private static func torPort(from value: String) -> Int? {
        let prefixes = [
            "tor://",
            "tor:",
            "tor-browser:",
            "torbrowser:"
        ]
        for prefix in prefixes where value.hasPrefix(prefix) {
            let digits = String(value.dropFirst(prefix.count))
            if let port = Int(digits),
               let normalized = normalizedProxyPort(port) {
                return normalized
            }
        }
        return nil
    }

    private static func normalizedProxyPort(_ port: Int) -> Int? {
        (1...65_535).contains(port) ? port : nil
    }

    private static func defaultPort(for scheme: String) -> Int? {
        switch scheme {
        case "http": return 80
        case "https": return 443
        case "socks4", "socks5": return 1080
        default: return nil
        }
    }
}
