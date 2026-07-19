import Foundation

struct OriginalBrowserExtensionCookiePayload: Equatable {
    static let header = "data:hitomi_downloader_cookies"

    let cookies: [StoredCookie]
    let skipped: Int

    static func parse(_ input: String, now: Date = Date()) -> OriginalBrowserExtensionCookiePayload? {
        guard input.hasPrefix(header) else { return nil }
        let suffix = String(input.dropFirst(header.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
        guard let data = suffix.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        var cookies: [StoredCookie] = []
        var skipped = 0
        cookies.reserveCapacity(values.count)

        for value in values {
            guard let domain = value["domain"] as? String,
                  let name = value["name"] as? String,
                  let cookieValue = value["value"] as? String,
                  isSafeDomain(domain),
                  isSafeName(name),
                  isSafeValue(cookieValue) else {
                skipped += 1
                continue
            }

            let rawPath = (value["path"] as? String)?.trimmed ?? "/"
            let path = rawPath.isEmpty ? "/" : (rawPath.hasPrefix("/") ? rawPath : "/\(rawPath)")
            guard isSafePath(path) else {
                skipped += 1
                continue
            }

            let expiresAt = (value["expirationDate"] as? NSNumber).map {
                Date(timeIntervalSince1970: $0.doubleValue)
            }
            if let expiresAt, expiresAt <= now {
                skipped += 1
                continue
            }

            let hostOnly = (value["hostOnly"] as? Bool) ?? !domain.hasPrefix(".")
            cookies.append(StoredCookie(
                domain: domain,
                path: path,
                name: name,
                value: cookieValue,
                isSecure: (value["secure"] as? Bool) ?? false,
                expiresAt: expiresAt,
                includeSubdomains: !hostOnly || domain.hasPrefix(".")
            ))
        }

        return OriginalBrowserExtensionCookiePayload(cookies: cookies, skipped: skipped)
    }

    private static func isSafeDomain(_ value: String) -> Bool {
        let domain = value.trimmed
        return !domain.isEmpty &&
            !domain.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }) &&
            !domain.contains(";") &&
            !domain.contains("\0")
    }

    private static func isSafeName(_ value: String) -> Bool {
        !value.isEmpty && !value.unicodeScalars.contains { scalar in
            CharacterSet.controlCharacters.contains(scalar) ||
                CharacterSet.whitespaces.contains(scalar) ||
                "()<>@,;:\\\"/[]?={}".unicodeScalars.contains(scalar)
        }
    }

    private static func isSafeValue(_ value: String) -> Bool {
        !value.contains("\r") && !value.contains("\n") && !value.contains("\0")
    }

    private static func isSafePath(_ value: String) -> Bool {
        !value.contains("\r") && !value.contains("\n") && !value.contains("\0")
    }
}
