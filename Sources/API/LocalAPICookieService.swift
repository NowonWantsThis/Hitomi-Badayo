import Foundation

struct LocalAPICookieImportResult: Equatable {
    let imported: Int
    let skipped: Int
}

struct LocalAPICookieUpdateOutcome {
    let response: LocalHTTPResponse
    let cookieSummary: String?
}

struct LocalAPICookieService {
    typealias CookieImporter =
        (String) async -> LocalAPICookieImportResult
    typealias CookieCounter =
        () async -> Int

    private let requestDecoder: LocalAPIRequestDecoder
    private let sourceAuthenticationPolicy: SourceAuthenticationPolicy
    private let cookieImporter: CookieImporter
    private let cookieCounter: CookieCounter

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder(),
        sourceAuthenticationPolicy:
            SourceAuthenticationPolicy = SourceAuthenticationPolicy.shared,
        cookieImporter: @escaping CookieImporter = { text in
            let result = CookieStore.shared.importText(text)
            return LocalAPICookieImportResult(
                imported: result.imported,
                skipped: result.skipped
            )
        },
        cookieCounter: @escaping CookieCounter = {
            CookieStore.shared.count
        }
    ) {
        self.requestDecoder = requestDecoder
        self.sourceAuthenticationPolicy = sourceAuthenticationPolicy
        self.cookieImporter = cookieImporter
        self.cookieCounter = cookieCounter
    }

    func updateResponse(
        for request: LocalHTTPRequest
    ) async -> LocalAPICookieUpdateOutcome {
        let cookieText = cookieText(from: request).trimmed
        guard !cookieText.isEmpty else {
            return LocalAPICookieUpdateOutcome(
                response: LocalHTTPResponse.jsonObject(
                    ["error": "Missing cookies"],
                    status: 400
                ),
                cookieSummary: nil
            )
        }

        let result = await cookieImporter(cookieText)
        let total = await cookieCounter()
        var summary =
            sourceAuthenticationPolicy
            .storedCookieSummary(count: total)
        if result.skipped > 0 {
            summary += ", \(result.skipped) skipped"
        }

        let message =
            "\(result.imported) cookie\(result.imported == 1 ? "" : "s") imported"
        return LocalAPICookieUpdateOutcome(
            response: LocalHTTPResponse.jsonObject([
                "ok": result.imported > 0,
                "res": usesOriginalActionShape(request) ? "ok" : message,
                "message": message,
                "updated": result.imported > 0,
                "imported": result.imported,
                "skipped": result.skipped,
                "count": total
            ]),
            cookieSummary: summary
        )
    }

    func cookieText(from request: LocalHTTPRequest) -> String {
        let body = request.bodyText.trimmed
        let contentType =
            request.headers["content-type"]?.lowercased() ?? ""

        if (
            contentType.contains("application/json") ||
                LocalAPIRequestDecoder.looksLikeJSONBody(body)
        ),
           let jsonCookieText = Self.cookieText(fromJSONBody: body),
           !jsonCookieText.trimmed.isEmpty {
            return jsonCookieText
        }

        let parameters = requestDecoder.parameters(from: request)
        if let value =
            parameters["cookies"] ??
            parameters["cookie"] ??
            parameters["text"] ??
            parameters["data"],
           !value.trimmed.isEmpty {
            return value
        }

        guard !body.isEmpty else { return "" }
        if contentType.contains("application/json") ||
            contentType.contains("application/x-www-form-urlencoded") {
            return ""
        }
        return body
    }

    private func usesOriginalActionShape(
        _ request: LocalHTTPRequest
    ) -> Bool {
        if request.path.lowercased().hasPrefix("/api/") {
            return false
        }

        let parameters = requestDecoder.parameters(from: request)
        let shape = (
            parameters["format"] ??
            parameters["shape"] ??
            parameters["response"] ??
            ""
        ).trimmed.lowercased()
        if ["object", "native", "full", "detail", "details"].contains(shape) {
            return false
        }
        return !LocalAPIRequestDecoder.truthy(parameters["native"]) &&
            !LocalAPIRequestDecoder.truthy(parameters["details"])
    }

    private static func cookieText(fromJSONBody body: String) -> String? {
        guard !body.isEmpty,
              let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return nil
        }
        return cookieText(fromJSONValue: object)
    }

    private static func cookieText(fromJSONValue value: Any) -> String? {
        if let string = value as? String {
            return string.trimmed.isEmpty ? nil : string
        }
        if let array = value as? [Any] {
            let lines = array.compactMap { cookieText(fromJSONValue: $0) }
            return lines.isEmpty ? nil : lines.joined(separator: "\n")
        }
        guard let dictionary = value as? [String: Any] else {
            return nil
        }

        if let nested = jsonValue(
            in: dictionary,
            keys: ["cookies", "cookie", "text", "data"]
        ) {
            return cookieText(fromJSONValue: nested)
        }
        return cookieLine(fromJSONCookie: dictionary)
    }

    private static func cookieLine(
        fromJSONCookie dictionary: [String: Any]
    ) -> String? {
        guard let name = jsonString(
            in: dictionary,
            keys: ["name", "key"]
        ),
        !name.trimmed.isEmpty,
        let value = jsonString(
            in: dictionary,
            keys: ["value"],
            allowEmpty: true
        ) else {
            return nil
        }

        let domain =
            jsonString(in: dictionary, keys: ["domain", "host"]) ??
            jsonString(in: dictionary, keys: ["url"])
                .flatMap { URL(string: $0)?.host } ??
            "*"
        let path = jsonString(in: dictionary, keys: ["path"]) ?? "/"
        let secure =
            jsonBool(in: dictionary, keys: ["secure", "isSecure"]) ?? false
        let hostOnly =
            jsonBool(in: dictionary, keys: ["hostOnly", "host_only"])
        let includeSubdomains =
            jsonBool(
                in: dictionary,
                keys: ["includeSubdomains", "include_subdomains"]
            ) ??
            (hostOnly.map { !$0 } ?? domain.hasPrefix("."))
        let expires = jsonDouble(
            in: dictionary,
            keys: [
                "expirationDate",
                "expires",
                "expiry",
                "expiresAt",
                "expires_at",
                "expiration"
            ]
        ).map { String(Int($0)) } ?? "0"
        let lineDomain =
            jsonBool(
                in: dictionary,
                keys: ["httpOnly", "http_only"]
            ) == true
            ? "#HttpOnly_\(domain)"
            : domain

        return [
            lineDomain,
            includeSubdomains ? "TRUE" : "FALSE",
            path,
            secure ? "TRUE" : "FALSE",
            expires,
            name,
            value
        ].joined(separator: "\t")
    }

    private static func jsonValue(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Any? {
        let normalized = Set(keys.map { $0.lowercased() })
        return dictionary.first {
            normalized.contains($0.key.lowercased())
        }?.value
    }

    private static func jsonString(
        in dictionary: [String: Any],
        keys: [String],
        allowEmpty: Bool = false
    ) -> String? {
        guard let value = jsonValue(in: dictionary, keys: keys),
              !(value is NSNull) else {
            return nil
        }
        let string = LocalAPIRequestDecoder.parameterString(from: value)
        if !allowEmpty, string.trimmed.isEmpty {
            return nil
        }
        return string
    }

    private static func jsonBool(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Bool? {
        guard let value = jsonValue(in: dictionary, keys: keys),
              !(value is NSNull) else {
            return nil
        }
        if let bool = value as? Bool {
            return bool
        }
        if let number = value as? NSNumber {
            return number.boolValue
        }
        return LocalAPIRequestDecoder.truthy(
            LocalAPIRequestDecoder.parameterString(from: value)
        )
    }

    private static func jsonDouble(
        in dictionary: [String: Any],
        keys: [String]
    ) -> Double? {
        guard let value = jsonValue(in: dictionary, keys: keys),
              !(value is NSNull) else {
            return nil
        }
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        return Double(
            LocalAPIRequestDecoder.parameterString(from: value).trimmed
        )
    }
}
