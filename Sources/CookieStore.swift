import Foundation

struct StoredCookie: Codable, Hashable {
    let domain: String
    let path: String
    let name: String
    let value: String
    let isSecure: Bool
    let expiresAt: Date?
    let includeSubdomains: Bool

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return expiresAt <= Date()
    }
}

struct CookieImportResult {
    let imported: Int
    let skipped: Int
}

struct CookieJarFile: Codable {
    let version: Int
    let savedAt: Date
    let cookies: [StoredCookie]
}

actor CookieStore {
    static let shared = CookieStore()

    static var hasPersistedStore: Bool {
        FileManager.default.fileExists(atPath: defaultStorageURL().path)
    }

    private var cookies: [StoredCookie] = []
    private var hasLoadedCookies = false
    private let storageURL: URL
    private let vault: CookieVault

    init(storageURL: URL? = nil, keyProvider: CookieKeyProvider = .default) {
        self.storageURL = storageURL ?? Self.defaultStorageURL()
        self.vault = CookieVault(storageURL: self.storageURL, keyProvider: keyProvider)
    }

    var count: Int {
        loadCookiesIfNeeded()
        return cookies.filter { !$0.isExpired }.count
    }

    func replace(with imported: [StoredCookie]) {
        hasLoadedCookies = true
        cookies = imported.filter { !$0.isExpired }
        persist()
    }

    func clear() {
        hasLoadedCookies = true
        cookies.removeAll()
        try? FileManager.default.removeItem(at: storageURL)
    }

    func reloadFromDisk() {
        hasLoadedCookies = true
        cookies = vault.load().cookies
    }

    func cookieHeader(for url: URL) -> String? {
        loadCookiesIfNeeded()
        let valid = matchingCookies(for: url)

        guard !valid.isEmpty else { return nil }
        return valid.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func cookieValue(named name: String, for url: URL) -> String? {
        loadCookiesIfNeeded()
        return matchingCookies(for: url)
            .first { $0.name == name && !$0.value.isEmpty }?
            .value
    }

    func netscapeCookieFile(for url: URL) -> String? {
        loadCookiesIfNeeded()
        let valid = matchingCookies(for: url)

        guard !valid.isEmpty else { return nil }
        let host = url.host?.lowercased() ?? "localhost"
        var lines = [
            "# Netscape HTTP Cookie File",
            "# Generated temporarily by Hitomi Native for yt-dlp."
        ]

        for cookie in valid {
            let domain = cookie.domain == "*" ? host : cookie.domain
            let includeSubdomains = cookie.includeSubdomains ? "TRUE" : "FALSE"
            let secure = cookie.isSecure ? "TRUE" : "FALSE"
            let expires = cookie.expiresAt.map { String(Int($0.timeIntervalSince1970)) } ?? "0"
            lines.append([
                domain,
                includeSubdomains,
                cookie.path,
                secure,
                expires,
                cookie.name,
                cookie.value
            ].joined(separator: "\t"))
        }

        return lines.joined(separator: "\n") + "\n"
    }

    func storeCookies(from response: URLResponse, url: URL) {
        guard let http = response as? HTTPURLResponse,
              let fields = http.allHeaderFields as? [String: String] else {
            return
        }

        let found = HTTPCookie.cookies(withResponseHeaderFields: fields, for: url).map(StoredCookie.init)
        merge(found)
    }

    func importText(_ text: String) -> CookieImportResult {
        var imported: [StoredCookie] = []
        var skipped = 0

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmed
            if line.isEmpty { continue }

            if let cookie = Self.parseNetscapeCookie(line) {
                imported.append(cookie)
            } else if let rawCookies = Self.parseRawCookieLine(line) {
                imported.append(contentsOf: rawCookies)
            } else if line.hasPrefix("#") {
                continue
            } else {
                skipped += 1
            }
        }

        if imported.isEmpty, let headerCookie = Self.parseCookieHeader(text) {
            imported.append(contentsOf: headerCookie)
        }

        replace(with: imported)
        return CookieImportResult(imported: imported.count, skipped: skipped)
    }

    func importBrowserDatabase(from url: URL) throws -> BrowserCookieImportResult {
        let result = try BrowserCookieImporter.importCookies(from: url)
        replace(with: result.cookies)
        return result
    }

    func importDetectedBrowserDatabases() throws -> BrowserCookieImportResult {
        let result = try BrowserCookieImporter.importDetectedProfiles()
        replace(with: result.cookies)
        return result
    }

    func importHTTPCookies(_ httpCookies: [HTTPCookie]) -> CookieImportResult {
        let stored = httpCookies.map(StoredCookie.init)
        let valid = stored.filter { !$0.isExpired }
        merge(valid)
        return CookieImportResult(imported: valid.count, skipped: stored.count - valid.count)
    }

    func replaceBrowserExtensionCookies(_ payload: OriginalBrowserExtensionCookiePayload) -> CookieImportResult {
        let valid = payload.cookies.filter { !$0.isExpired }
        replace(with: valid)
        return CookieImportResult(
            imported: valid.count,
            skipped: payload.skipped + payload.cookies.count - valid.count
        )
    }

    private func merge(_ newCookies: [StoredCookie]) {
        guard !newCookies.isEmpty else { return }
        loadCookiesIfNeeded()
        for cookie in newCookies where !cookie.isExpired {
            cookies.removeAll {
                $0.domain == cookie.domain &&
                $0.path == cookie.path &&
                $0.name == cookie.name
            }
            cookies.append(cookie)
        }
        persist()
    }

    private func loadCookiesIfNeeded() {
        guard !hasLoadedCookies else { return }
        hasLoadedCookies = true
        let loaded = vault.load()
        cookies = loaded.cookies
        if loaded.needsEncryptedRewrite {
            try? vault.save(loaded.cookies)
        }
    }

    private func persist() {
        let valid = cookies.filter { !$0.isExpired }

        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try vault.save(valid)
            cookies = valid
        } catch {
            cookies = valid
        }
    }

    private func matchingCookies(for url: URL) -> [StoredCookie] {
        let host = url.host?.lowercased() ?? ""
        return cookies.enumerated()
            .filter { !$0.element.isExpired && $0.element.matches(url: url) }
            .sorted { lhs, rhs in
                Self.cookie(lhs.element, offset: lhs.offset, shouldSortBefore: rhs.element, offset: rhs.offset, host: host)
            }
            .map(\.element)
    }

    private static func cookie(_ lhs: StoredCookie, offset lhsOffset: Int, shouldSortBefore rhs: StoredCookie, offset rhsOffset: Int, host: String) -> Bool {
        let lhsPath = lhs.normalizedPath
        let rhsPath = rhs.normalizedPath
        if lhsPath.count != rhsPath.count {
            return lhsPath.count > rhsPath.count
        }

        let lhsDomain = cookieDomain(lhs)
        let rhsDomain = cookieDomain(rhs)
        if lhsDomain.count != rhsDomain.count {
            return lhsDomain.count > rhsDomain.count
        }

        let lhsHostOnly = lhsDomain == host && !lhs.includeSubdomains
        let rhsHostOnly = rhsDomain == host && !rhs.includeSubdomains
        if lhsHostOnly != rhsHostOnly {
            return lhsHostOnly
        }

        return lhsOffset < rhsOffset
    }

    private static func cookieDomain(_ cookie: StoredCookie) -> String {
        cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func defaultStorageURL() -> URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["HITOMI_BADAYO_COOKIE_STORE"] ?? environment["HITOMI_NATIVE_COOKIE_STORE"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        return AppPaths.applicationSupportDirectory.appendingPathComponent("cookies.json")
    }

    private static func parseNetscapeCookie(_ rawLine: String) -> StoredCookie? {
        var line = rawLine
        if line.hasPrefix("#HttpOnly_") {
            line.removeFirst("#HttpOnly_".count)
        }
        guard !line.hasPrefix("#") else { return nil }

        let fields = line.components(separatedBy: "\t")
        guard fields.count >= 7 else { return nil }

        let domain = fields[0].trimmed
        let includeSubdomains = fields[1].trimmed.uppercased() == "TRUE" || domain.hasPrefix(".")
        let path = fields[2].trimmed.isEmpty ? "/" : fields[2].trimmed
        let isSecure = fields[3].trimmed.uppercased() == "TRUE"
        let expiresRaw = Double(fields[4].trimmed)
        let expiresAt = expiresRaw.flatMap { $0 > 0 ? Date(timeIntervalSince1970: $0) : nil }
        let name = fields[5].trimmed
        let value = fields.dropFirst(6).joined(separator: "\t")

        guard !domain.isEmpty, !name.isEmpty else { return nil }
        return StoredCookie(
            domain: domain,
            path: path,
            name: name,
            value: value,
            isSecure: isSecure,
            expiresAt: expiresAt,
            includeSubdomains: includeSubdomains
        )
    }

    private static func parseRawCookieLine(_ line: String) -> [StoredCookie]? {
        guard line.contains("="), !line.contains("\t") else { return nil }
        let normalized = line.lowercased().hasPrefix("cookie:")
            ? String(line.dropFirst("cookie:".count)).trimmed
            : line

        let pairs = parseCookiePairs(normalized)
        guard !pairs.isEmpty else { return nil }
        return pairs.map {
            StoredCookie(
                domain: "*",
                path: "/",
                name: $0.name,
                value: $0.value,
                isSecure: false,
                expiresAt: nil,
                includeSubdomains: true
            )
        }
    }

    private static func parseCookieHeader(_ text: String) -> [StoredCookie]? {
        let line = text.components(separatedBy: .newlines)
            .map { $0.trimmed }
            .first { !$0.isEmpty && !$0.hasPrefix("#") } ?? text.trimmed

        let normalized = line.lowercased().hasPrefix("cookie:")
            ? String(line.dropFirst("cookie:".count)).trimmed
            : line

        let pairs = parseCookiePairs(normalized)
        guard !pairs.isEmpty else { return nil }

        return pairs.map {
            StoredCookie(
                domain: "*",
                path: "/",
                name: $0.name,
                value: $0.value,
                isSecure: false,
                expiresAt: nil,
                includeSubdomains: true
            )
        }
    }

    private static func parseCookiePairs(_ text: String) -> [(name: String, value: String)] {
        text
            .components(separatedBy: ";")
            .compactMap { part in
                let item = part.trimmed
                guard let eq = item.firstIndex(of: "=") else { return nil }
                let name = String(item[..<eq]).trimmed
                let value = String(item[item.index(after: eq)...]).trimmed
                guard !name.isEmpty else { return nil }
                return (name: name, value: value)
            }
    }
}

private extension StoredCookie {
    var normalizedPath: String {
        if path.isEmpty {
            return "/"
        }
        return path.hasPrefix("/") ? path : "/\(path)"
    }

    init(_ cookie: HTTPCookie) {
        self.domain = cookie.domain
        self.path = cookie.path
        self.name = cookie.name
        self.value = cookie.value
        self.isSecure = cookie.isSecure
        self.expiresAt = cookie.expiresDate
        self.includeSubdomains = cookie.domain.hasPrefix(".")
    }

    func matches(url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return domain == "*" }
        if isSecure, url.scheme?.lowercased() != "https" {
            return false
        }

        let cookieDomain = domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let domainMatches = domain == "*" ||
            host == cookieDomain ||
            (includeSubdomains && host.hasSuffix("." + cookieDomain))

        guard domainMatches else { return false }

        let requestPath = url.path.isEmpty ? "/" : url.path
        let cookiePath = normalizedPath
        if cookiePath == "/" || requestPath == cookiePath {
            return true
        }
        guard requestPath.hasPrefix(cookiePath) else {
            return false
        }
        if cookiePath.hasSuffix("/") {
            return true
        }
        let index = requestPath.index(requestPath.startIndex, offsetBy: cookiePath.count)
        return requestPath[index] == "/"
    }
}
