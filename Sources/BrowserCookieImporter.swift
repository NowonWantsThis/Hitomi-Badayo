import Foundation
import SQLite3

struct BrowserCookieImportResult {
    let browserName: String
    let imported: Int
    let skipped: Int
    let encryptedSkipped: Int
    let profilesScanned: Int
    let cookies: [StoredCookie]
}

enum BrowserCookieImporter {
    static func importCookies(from sourceURL: URL) throws -> BrowserCookieImportResult {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-cookie-import-\(UUID().uuidString)", isDirectory: true)
        try AppPaths.ensureDirectory(tempDirectory)
        let tempURL = tempDirectory.appendingPathComponent(sourceURL.lastPathComponent.isEmpty ? "cookies.sqlite" : sourceURL.lastPathComponent)

        defer {
            try? FileManager.default.removeItem(at: tempDirectory)
        }

        try FileManager.default.copyItem(at: sourceURL, to: tempURL)

        let database = try SQLiteCookieDatabase(url: tempURL)
        defer {
            database.close()
        }

        if database.tableExists("moz_cookies") {
            return try importFirefoxCookies(from: database, sourceURL: sourceURL)
        }

        if database.tableExists("cookies") {
            return try importChromiumCookies(from: database, sourceURL: sourceURL)
        }

        throw NativeDownloadError.unsupported("The selected file is not a supported Firefox or Chromium cookie database.")
    }

    static func importDetectedProfiles() throws -> BrowserCookieImportResult {
        let candidates = detectedCookieDatabases()
        guard !candidates.isEmpty else {
            throw NativeDownloadError.unsupported("No Firefox or Chromium browser cookie databases were found.")
        }

        var cookies: [StoredCookie] = []
        var skipped = 0
        var encryptedSkipped = 0
        var successfulProfiles = 0
        var browserNames: [String] = []

        for candidate in candidates {
            do {
                let result = try importCookies(from: candidate)
                cookies.append(contentsOf: result.cookies)
                skipped += result.skipped
                encryptedSkipped += result.encryptedSkipped
                if result.imported > 0 {
                    successfulProfiles += 1
                }
                if !browserNames.contains(result.browserName) {
                    browserNames.append(result.browserName)
                }
            } catch {
                skipped += 1
            }
        }

        guard !cookies.isEmpty else {
            throw NativeDownloadError.unsupported("Browser cookie databases were found, but no readable cookies could be imported.")
        }

        return BrowserCookieImportResult(
            browserName: browserNames.isEmpty ? "Browser" : browserNames.joined(separator: "/"),
            imported: cookies.count,
            skipped: skipped,
            encryptedSkipped: encryptedSkipped,
            profilesScanned: successfulProfiles,
            cookies: cookies
        )
    }

    private static func importFirefoxCookies(from database: SQLiteCookieDatabase, sourceURL: URL) throws -> BrowserCookieImportResult {
        let columns = try database.columns(in: "moz_cookies")
        let hostColumn = chromiumColumn(["host", "host_key", "domain", "domain_key"], defaultSQL: "''", in: columns)
        let pathColumn = chromiumColumn(["path", "cookie_path"], defaultSQL: "'/'", in: columns)
        let nameColumn = chromiumColumn(["name", "key"], defaultSQL: "''", in: columns)
        let valueColumn = chromiumColumn(["value", "plain_value", "cookie_value"], defaultSQL: "''", in: columns)
        let secureColumn = chromiumColumn(["isSecure", "secure", "is_secure"], defaultSQL: "0", in: columns)
        let expiresColumn = chromiumColumn(["expiry", "expires", "expires_utc", "expirationDate", "expiration_date", "expiresUnix", "expires_unix"], defaultSQL: "0", in: columns)
        let rows = try database.rows(
            sql: "SELECT \(hostColumn), \(pathColumn), \(nameColumn), \(valueColumn), \(secureColumn), \(expiresColumn) FROM moz_cookies"
        )
        var imported: [StoredCookie] = []
        var skipped = 0

        for row in rows {
            let domain = row.string(0).trimmed
            let path = row.string(1).trimmed
            let name = row.string(2).trimmed
            let value = row.string(3)
            let expiresRaw = row.int64(5)

            guard !domain.isEmpty, !name.isEmpty else {
                skipped += 1
                continue
            }

            let cookie = StoredCookie(
                domain: domain,
                path: path.isEmpty ? "/" : path,
                name: name,
                value: value,
                isSecure: row.int(4) != 0,
                expiresAt: unixCookieDate(from: expiresRaw),
                includeSubdomains: domain.hasPrefix(".")
            )

            if cookie.isExpired {
                skipped += 1
            } else {
                imported.append(cookie)
            }
        }

        return BrowserCookieImportResult(
            browserName: firefoxBrowserName(from: sourceURL),
            imported: imported.count,
            skipped: skipped,
            encryptedSkipped: 0,
            profilesScanned: 1,
            cookies: imported
        )
    }

    private static func importChromiumCookies(from database: SQLiteCookieDatabase, sourceURL: URL) throws -> BrowserCookieImportResult {
        let columns = try database.columns(in: "cookies")
        let hostColumn = chromiumColumn(["host_key", "host", "domain", "domain_key"], defaultSQL: "''", in: columns)
        let pathColumn = chromiumColumn(["path", "cookie_path"], defaultSQL: "'/'", in: columns)
        let nameColumn = chromiumColumn(["name", "key"], defaultSQL: "''", in: columns)
        let valueColumn = chromiumColumn(["value", "plain_value", "cookie_value"], defaultSQL: "''", in: columns)
        let encryptedColumn = chromiumColumn(["encrypted_value", "encryptedValue", "encrypted", "encrypted_cookie"], defaultSQL: "X''", in: columns)
        let secureColumn = chromiumColumn(["is_secure", "secure", "isSecure"], defaultSQL: "0", in: columns)
        let expiresColumn = chromiumColumn(["expires_utc", "expires", "expiry", "expirationDate", "expiration_date", "expiry_utc"], defaultSQL: "0", in: columns)
        let rows = try database.rows(
            sql: "SELECT \(hostColumn), \(pathColumn), \(nameColumn), \(valueColumn), \(encryptedColumn), \(secureColumn), \(expiresColumn) FROM cookies"
        )
        var imported: [StoredCookie] = []
        var skipped = 0
        var encryptedSkipped = 0
        let decryptor = ChromiumCookieDecryptor.context(for: sourceURL)

        for row in rows {
            let domain = row.string(0).trimmed
            let path = row.string(1).trimmed
            let name = row.string(2).trimmed
            var value = row.string(3)
            let encryptedValue = row.data(4)

            guard !domain.isEmpty, !name.isEmpty else {
                skipped += 1
                continue
            }

            if value.isEmpty && !encryptedValue.isEmpty {
                do {
                    guard let decryptor else {
                        encryptedSkipped += 1
                        continue
                    }
                    value = try decryptor.decryptCookieValue(encryptedValue, hostKey: domain)
                } catch {
                    encryptedSkipped += 1
                    continue
                }
            }

            let cookie = StoredCookie(
                domain: domain,
                path: path.isEmpty ? "/" : path,
                name: name,
                value: value,
                isSecure: row.int(5) != 0,
                expiresAt: chromiumDate(from: row.int64(6)),
                includeSubdomains: domain.hasPrefix(".")
            )

            if cookie.isExpired {
                skipped += 1
            } else {
                imported.append(cookie)
            }
        }

        return BrowserCookieImportResult(
            browserName: decryptor?.browserName ?? "Chromium",
            imported: imported.count,
            skipped: skipped,
            encryptedSkipped: encryptedSkipped,
            profilesScanned: 1,
            cookies: imported
        )
    }

    private static func chromiumColumn(_ names: [String], defaultSQL: String, in columns: Set<String>) -> String {
        let columnsByLowercase = Dictionary(uniqueKeysWithValues: columns.map { ($0.lowercased(), $0) })
        guard let name = names.lazy.compactMap({ columnsByLowercase[$0.lowercased()] }).first else {
            return defaultSQL
        }
        return quotedSQLiteIdentifier(name)
    }

    private static func quotedSQLiteIdentifier(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private static func chromiumDate(from value: Int64) -> Date? {
        guard value > 0 else { return nil }
        if value >= chromiumEpochOffsetMicroseconds {
            let seconds = TimeInterval(value) / 1_000_000 - chromiumEpochOffsetSeconds
            guard seconds > 0 else { return nil }
            return Date(timeIntervalSince1970: seconds)
        }
        return unixCookieDate(from: value)
    }

    private static func unixCookieDate(from value: Int64) -> Date? {
        guard value > 0 else { return nil }
        let seconds: TimeInterval
        if value >= unixMicrosecondThreshold {
            seconds = TimeInterval(value) / 1_000_000
        } else if value >= unixMillisecondThreshold {
            seconds = TimeInterval(value) / 1_000
        } else {
            seconds = TimeInterval(value)
        }
        guard seconds > 0 else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    private static let chromiumEpochOffsetSeconds: TimeInterval = 11_644_473_600
    private static let chromiumEpochOffsetMicroseconds: Int64 = 11_644_473_600_000_000
    private static let unixMillisecondThreshold: Int64 = 100_000_000_000
    private static let unixMicrosecondThreshold: Int64 = 100_000_000_000_000

    private static func detectedCookieDatabases() -> [URL] {
        let homePath = ProcessInfo.processInfo.environment["HITOMI_NATIVE_BROWSER_HOME"]
            .flatMap { $0.isEmpty ? nil : $0 } ?? NSHomeDirectory()
        let home = URL(fileURLWithPath: homePath)
        let support = home.appendingPathComponent("Library/Application Support", isDirectory: true)
        let chromiumRoots = [
            support.appendingPathComponent("Google/Chrome", isDirectory: true),
            support.appendingPathComponent("Google/Chrome Beta", isDirectory: true),
            support.appendingPathComponent("Google/Chrome Canary", isDirectory: true),
            support.appendingPathComponent("Google/Chrome for Testing", isDirectory: true),
            support.appendingPathComponent("Chromium", isDirectory: true),
            support.appendingPathComponent("BraveSoftware/Brave-Browser", isDirectory: true),
            support.appendingPathComponent("BraveSoftware/Brave-Browser-Beta", isDirectory: true),
            support.appendingPathComponent("BraveSoftware/Brave-Browser-Nightly", isDirectory: true),
            support.appendingPathComponent("Microsoft Edge", isDirectory: true),
            support.appendingPathComponent("Microsoft Edge Beta", isDirectory: true),
            support.appendingPathComponent("Microsoft Edge Dev", isDirectory: true),
            support.appendingPathComponent("Microsoft Edge Canary", isDirectory: true),
            support.appendingPathComponent("Vivaldi", isDirectory: true),
            support.appendingPathComponent("com.operasoftware.Opera", isDirectory: true),
            support.appendingPathComponent("com.operasoftware.OperaGX", isDirectory: true),
            support.appendingPathComponent("Arc/User Data", isDirectory: true),
            support.appendingPathComponent("Naver/Whale", isDirectory: true),
            support.appendingPathComponent("Whale", isDirectory: true),
            support.appendingPathComponent("Yandex/YandexBrowser", isDirectory: true),
            support.appendingPathComponent("Thorium", isDirectory: true),
            support.appendingPathComponent("ungoogled-chromium", isDirectory: true)
        ]
        var urls: [URL] = []

        for root in chromiumRoots {
            urls.append(contentsOf: chromiumCookieDatabases(in: root))
        }

        let firefoxProfileRoots = [
            support.appendingPathComponent("Firefox/Profiles", isDirectory: true),
            support.appendingPathComponent("LibreWolf/Profiles", isDirectory: true),
            support.appendingPathComponent("Waterfox/Profiles", isDirectory: true),
            support.appendingPathComponent("Floorp/Profiles", isDirectory: true),
            support.appendingPathComponent("Zen/Profiles", isDirectory: true),
            support.appendingPathComponent("TorBrowser-Data/Browser", isDirectory: true),
            support.appendingPathComponent("Mullvad Browser/Browser", isDirectory: true)
        ]
        for root in firefoxProfileRoots {
            urls.append(contentsOf: firefoxCookieDatabases(in: root))
        }

        var seen = Set<String>()
        return urls.filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    private static func firefoxCookieDatabases(in root: URL) -> [URL] {
        var urls: [URL] = []
        let rootCookieURL = root.appendingPathComponent("cookies.sqlite")
        if FileManager.default.fileExists(atPath: rootCookieURL.path) {
            urls.append(rootCookieURL)
        }

        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return urls
        }

        for profile in profiles {
            let cookieURL = profile.appendingPathComponent("cookies.sqlite")
            if FileManager.default.fileExists(atPath: cookieURL.path) {
                urls.append(cookieURL)
            }
        }
        return urls
    }

    private static func firefoxBrowserName(from sourceURL: URL) -> String {
        let path = sourceURL.path.lowercased()
        if path.contains("/librewolf/") { return "LibreWolf" }
        if path.contains("/waterfox/") { return "Waterfox" }
        if path.contains("/floorp/") { return "Floorp" }
        if path.contains("/zen/") { return "Zen Browser" }
        if path.contains("/torbrowser-data/") { return "Tor Browser" }
        if path.contains("/mullvad browser/") { return "Mullvad Browser" }
        return "Firefox"
    }

    private static func chromiumCookieDatabases(in root: URL) -> [URL] {
        var urls: [URL] = []
        for cookieURL in [
            root.appendingPathComponent("Network/Cookies"),
            root.appendingPathComponent("Cookies")
        ] where FileManager.default.fileExists(atPath: cookieURL.path) {
            urls.append(cookieURL)
        }

        guard let profiles = try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return urls
        }

        for profile in profiles {
            for cookieURL in [
                profile.appendingPathComponent("Network/Cookies"),
                profile.appendingPathComponent("Cookies")
            ] where FileManager.default.fileExists(atPath: cookieURL.path) {
                urls.append(cookieURL)
            }
        }

        return urls
    }
}

private final class SQLiteCookieDatabase {
    private var handle: OpaquePointer?

    init(url: URL) throws {
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX
        guard sqlite3_open_v2(url.path, &handle, flags, nil) == SQLITE_OK else {
            let message = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown sqlite error"
            throw NativeDownloadError.unsupported("Could not open cookie database: \(message)")
        }
    }

    func close() {
        if let handle {
            sqlite3_close(handle)
            self.handle = nil
        }
    }

    func tableExists(_ name: String) -> Bool {
        let sql = "SELECT 1 FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1"
        guard let statement = try? prepare(sql) else { return false }
        defer {
            sqlite3_finalize(statement)
        }

        sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    func rows(sql: String) throws -> [SQLiteRow] {
        let statement = try prepare(sql)
        defer {
            sqlite3_finalize(statement)
        }

        var rows: [SQLiteRow] = []
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE {
                return rows
            }
            guard result == SQLITE_ROW else {
                throw NativeDownloadError.unsupported("Could not read cookie database: \(errorMessage)")
            }
            rows.append(SQLiteRow(statement: statement))
        }
    }

    func columns(in table: String) throws -> Set<String> {
        let rows = try rows(sql: "PRAGMA table_info(\(Self.quotedIdentifier(table)))")
        return Set(rows.map { $0.string(1) }.filter { !$0.isEmpty })
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK else {
            throw NativeDownloadError.unsupported("Unsupported cookie database schema: \(errorMessage)")
        }
        return statement
    }

    private static func quotedIdentifier(_ name: String) -> String {
        "\"\(name.replacingOccurrences(of: "\"", with: "\"\""))\""
    }

    private var errorMessage: String {
        guard let handle else { return "database is closed" }
        return String(cString: sqlite3_errmsg(handle))
    }
}

private struct SQLiteRow {
    private let values: [SQLiteValue]

    init(statement: OpaquePointer?) {
        let count = sqlite3_column_count(statement)
        values = (0..<count).map { index in
            switch sqlite3_column_type(statement, index) {
            case SQLITE_INTEGER:
                return .integer(sqlite3_column_int64(statement, index))
            case SQLITE_BLOB:
                let length = Int(sqlite3_column_bytes(statement, index))
                guard length > 0, let bytes = sqlite3_column_blob(statement, index) else {
                    return .blob(Data())
                }
                return .blob(Data(bytes: bytes, count: length))
            case SQLITE_NULL:
                return .null
            default:
                if let text = sqlite3_column_text(statement, index) {
                    return .text(String(cString: text))
                }
                return .text("")
            }
        }
    }

    func string(_ index: Int) -> String {
        guard values.indices.contains(index) else { return "" }
        switch values[index] {
        case .text(let text):
            return text
        case .integer(let value):
            return String(value)
        case .blob, .null:
            return ""
        }
    }

    func int(_ index: Int) -> Int {
        Int(int64(index))
    }

    func int64(_ index: Int) -> Int64 {
        guard values.indices.contains(index) else { return 0 }
        switch values[index] {
        case .integer(let value):
            return value
        case .text(let text):
            return Int64(text) ?? 0
        case .blob, .null:
            return 0
        }
    }

    func blobLength(_ index: Int) -> Int {
        guard values.indices.contains(index) else { return 0 }
        switch values[index] {
        case .blob(let data):
            return data.count
        case .text(let text):
            return text.isEmpty ? 0 : text.utf8.count
        case .integer, .null:
            return 0
        }
    }

    func data(_ index: Int) -> Data {
        guard values.indices.contains(index) else { return Data() }
        switch values[index] {
        case .blob(let data):
            return data
        case .text(let text):
            return Data(text.utf8)
        case .integer, .null:
            return Data()
        }
    }
}

private enum SQLiteValue {
    case text(String)
    case integer(Int64)
    case blob(Data)
    case null
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
