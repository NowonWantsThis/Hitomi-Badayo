import Foundation

struct LocalAPIRequestDecoder {
    typealias InputItem = (url: String, metadata: [String: String])

    func parameters(from request: LocalHTTPRequest) -> [String: String] {
        var parameters = request.query
        let bodyText = request.bodyText
        let contentType = request.headers["content-type"]?.lowercased() ?? ""
        let looksLikeJSON = Self.looksLikeJSONBody(bodyText)

        if contentType.contains("application/json") || looksLikeJSON {
            if let data = bodyText.data(using: .utf8),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for (key, value) in object {
                    Self.mergeParameter(
                        key,
                        Self.parameterString(from: value),
                        into: &parameters
                    )
                }
                return parameters
            }
        }

        if contentType.contains("application/json") {
            return parameters
        }

        if contentType.contains("application/x-www-form-urlencoded") || bodyText.contains("=") {
            for pair in bodyText.components(separatedBy: "&") {
                let parts = pair.components(separatedBy: "=")
                guard let key = parts.first, !key.isEmpty else { continue }
                let value = parts.dropFirst().joined(separator: "=")
                Self.mergeParameter(
                    Self.formDecode(key),
                    Self.formDecode(value),
                    into: &parameters
                )
            }
        }

        return parameters
    }

    func inputItems(
        from request: LocalHTTPRequest,
        parseInput: (String) -> [InputItem]
    ) -> [InputItem] {
        let parameters = parameters(from: request)
        if let input = parameters["input"],
           OriginalBrowserExtensionTask.parse(input) != nil {
            return parseInput(input)
        }
        if let url = parameters["url"] ?? parameters["urls"] {
            return parseInput(url)
        }
        if let input = parameters["input"] {
            return parseInput(input)
        }

        let body = request.bodyText.trimmed
        if Self.looksLikeJSONBody(body) {
            let items = inputItems(fromJSONBody: body, parseInput: parseInput)
            if !items.isEmpty {
                return items
            }
        }

        return body.isEmpty ? [] : parseInput(request.bodyText)
    }

    func ticket(from request: LocalHTTPRequest) -> String? {
        if let ticket = request.query["ticket"]?.trimmed, !ticket.isEmpty {
            return ticket
        }
        guard let cookie = request.headers["cookie"] else { return nil }
        for part in cookie.components(separatedBy: ";") {
            let pair = part.split(
                separator: "=",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )
            guard pair.count == 2,
                  String(pair[0]).trimmed.lowercased() == "ticket" else {
                continue
            }
            let value = String(pair[1]).trimmed
            return value.isEmpty ? nil : value
        }
        return nil
    }

    func safeRedirect(_ raw: String) -> String {
        let fallback = "/webui"
        let value = raw.trimmed.isEmpty ? fallback : raw.trimmed
        guard value.hasPrefix("/"),
              !value.hasPrefix("//"),
              !value.lowercased().hasPrefix("/\\") else {
            return fallback
        }
        return value
    }

    func listValues(from text: String) -> [String] {
        text
            .replacingOccurrences(of: ",", with: "\n")
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty }
    }

    nonisolated static func truthy(_ value: String?) -> Bool {
        guard let normalized = value?.trimmed.lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return !["0", "false", "no", "off", "none"].contains(normalized)
    }

    nonisolated static func firstParameterValue(
        in parameters: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = parameters[key]?.trimmed, !value.isEmpty {
                return value
            }
            let normalizedKey = normalizedParameterKey(key)
            if let pair = parameters.first(where: {
                normalizedParameterKey($0.key) == normalizedKey
            }), !pair.value.trimmed.isEmpty {
                return pair.value.trimmed
            }
        }
        return nil
    }

    nonisolated static func parameterValueAllowingEmpty(
        in parameters: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value = parameters[key] {
                return value
            }
            let normalizedKey = normalizedParameterKey(key)
            if let pair = parameters.first(where: {
                normalizedParameterKey($0.key) == normalizedKey
            }) {
                return pair.value
            }
        }
        return nil
    }

    nonisolated static func looksLikeJSONBody(_ bodyText: String) -> Bool {
        let body = bodyText.trimmed
        return body.hasPrefix("{") || body.hasPrefix("[")
    }

    nonisolated static func parameterString(from value: Any) -> String {
        if let string = value as? String {
            return string
        }
        if let array = value as? [Any] {
            return array.map(parameterString(from:)).joined(separator: "\n")
        }
        if value is NSNull {
            return ""
        }
        return String(describing: value)
    }

    private func inputItems(
        fromJSONBody body: String,
        parseInput: (String) -> [InputItem]
    ) -> [InputItem] {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return []
        }
        return inputItems(fromJSONValue: object, parseInput: parseInput)
    }

    private func inputItems(
        fromJSONValue value: Any,
        parseInput: (String) -> [InputItem]
    ) -> [InputItem] {
        if let string = value as? String {
            return parseInput(string)
        }
        if let array = value as? [Any] {
            return array.flatMap {
                inputItems(fromJSONValue: $0, parseInput: parseInput)
            }
        }
        guard let dictionary = value as? [String: Any] else { return [] }
        return ["input", "url", "urls", "text"].flatMap { key in
            dictionary[key].map {
                inputItems(fromJSONValue: $0, parseInput: parseInput)
            } ?? []
        }
    }

    private nonisolated static func normalizedParameterKey(_ key: String) -> String {
        key.unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .map { String($0).lowercased() }
            .joined()
    }

    private static func mergeParameter(
        _ key: String,
        _ value: String,
        into parameters: inout [String: String]
    ) {
        guard !key.isEmpty else { return }
        if let existing = parameters[key], !existing.isEmpty {
            parameters[key] = existing + "\n" + value
        } else {
            parameters[key] = value
        }
    }

    private static func formDecode(_ value: String) -> String {
        value
            .replacingOccurrences(of: "+", with: " ")
            .removingPercentEncoding ?? value
    }
}
