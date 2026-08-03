import Foundation

struct SearchMetadataCopy: Identifiable, Equatable {
    var kind: String
    var label: String
    var value: String

    var id: String {
        "\(kind):\(value)"
    }
}

enum SearchResultMetadataService {
    static func copies(for result: SearchResultLink) -> [SearchMetadataCopy] {
        [
            SearchMetadataCopy(
                kind: "artist",
                label: "Artist",
                value: value(for: result, keys: ["artist", "group"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "series",
                label: "Series",
                value: value(for: result, keys: ["series", "parody"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "book",
                label: "Book",
                value: value(for: result, keys: ["book", "book_id"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "character",
                label: "Character",
                value: value(for: result, keys: ["character"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "language",
                label: "Language",
                value: value(for: result, keys: ["language"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "type",
                label: "Type",
                value: value(for: result, keys: ["type"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "tags",
                label: "Tags",
                value: value(for: result, keys: ["tag", "tags"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "date",
                label: "Date",
                value: dateText(for: result) ?? ""
            ),
            SearchMetadataCopy(
                kind: "pages",
                label: "Pages",
                value: value(
                    for: result,
                    keys: [
                        "pages",
                        "page",
                        "page_count",
                        "pagecount",
                        "total_pages",
                        "totalpages"
                    ]
                ) ?? ""
            ),
            SearchMetadataCopy(
                kind: "id",
                label: "ID",
                value: value(
                    for: result,
                    keys: ["post_id", "gallery_id", "media_id", "result_id", "id"]
                ) ?? ""
            ),
            SearchMetadataCopy(
                kind: "uploader",
                label: "Uploader",
                value: value(
                    for: result,
                    keys: ["uploader", "username", "user", "owner"]
                ) ?? ""
            ),
            SearchMetadataCopy(
                kind: "uploader_id",
                label: "Uploader ID",
                value: value(
                    for: result,
                    keys: ["uploader_id", "user_id", "uid"]
                ) ?? ""
            ),
            SearchMetadataCopy(
                kind: "rating",
                label: "Rating",
                value: value(for: result, keys: ["rating"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "score",
                label: "Score",
                value: value(for: result, keys: ["score"]) ?? ""
            ),
            SearchMetadataCopy(
                kind: "format",
                label: "Format",
                value: value(
                    for: result,
                    keys: ["format", "file_format", "media_format"]
                ) ?? ""
            ),
            SearchMetadataCopy(
                kind: "resolution",
                label: "Resolution",
                value: value(for: result, keys: ["resolution"]) ?? ""
            )
        ].filter { !$0.value.trimmed.isEmpty }
    }

    static func value(for result: SearchResultLink, keys: [String]) -> String? {
        let normalizedKeys = keys.map { $0.lowercased() }
        let structured = normalizedKeys.compactMap { key -> String? in
            result.metadata.first { $0.key.lowercased() == key }?.value
        }
        let values = structured.isEmpty
            ? normalizedKeys.compactMap { textValue(in: result.metadataText, key: $0) }
            : structured
        let cleaned = uniqueValues(values.flatMap(splitValues))
        return cleaned.isEmpty ? nil : cleaned.joined(separator: ", ")
    }

    static func dateText(for result: SearchResultLink) -> String? {
        value(for: result, keys: ["date", "published", "posted", "created", "uploaded"])
    }

    static func pageCountText(for result: SearchResultLink) -> String? {
        guard let count = pageCount(for: result) else { return nil }
        return count == 1 ? "1 page" : "\(count) pages"
    }

    static func pageCount(for result: SearchResultLink) -> Int? {
        let pageValue = value(
            for: result,
            keys: ["pages", "page", "page_count", "pagecount", "total_pages", "totalpages"]
        )
        if let pageValue {
            for candidate in splitValues(pageValue) {
                if let count = FilterSyntaxCore.nonnegativeInteger(from: candidate) {
                    return count
                }
            }
        }

        let pattern = #"(?i)\b([1-9][0-9]{0,4})\s*(?:pages?|p\.)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let text = result.metadataText
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return FilterSyntaxCore.nonnegativeInteger(from: String(text[valueRange]))
    }

    static func haystack(for result: SearchResultLink) -> String {
        [
            result.metadataText,
            result.metadata
                .flatMap { [$0.key, $0.value] }
                .joined(separator: " ")
        ].joined(separator: " ").lowercased()
    }

    static func fieldMatches(
        _ result: SearchResultLink,
        field: String,
        value: String
    ) -> Bool? {
        let normalizedField = normalizedKey(field)
        guard !normalizedField.isEmpty else { return nil }

        var values = result.metadata.compactMap { key, metadataValue -> String? in
            let lowercasedKey = key.lowercased()
            guard lowercasedKey == field || normalizedKey(key) == normalizedField else {
                return nil
            }
            return metadataValue
        }
        if values.isEmpty,
           let value = textValue(in: result.metadataText, key: field) {
            values.append(value)
        }
        guard !values.isEmpty else { return nil }

        return values
            .flatMap(splitValues)
            .joined(separator: " ")
            .lowercased()
            .contains(value)
    }

    static func normalizedHost(for result: SearchResultLink) -> String {
        FilterSyntaxCore.normalizedHost(from: result.url)
    }

    private static func normalizedKey(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func uniqueValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let cleaned = value.trimmed
            let key = cleaned.lowercased()
            guard !cleaned.isEmpty, seen.insert(key).inserted else { continue }
            result.append(cleaned)
        }
        return result
    }

    private static func splitValues(_ raw: String) -> [String] {
        raw.components(separatedBy: CharacterSet(charactersIn: ",;|"))
            .map { FilterSyntaxCore.strippingQuotes(from: $0.trimmed) }
            .filter { !$0.isEmpty }
    }

    private static func textValue(in text: String, key: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: key)
        let pattern = #"(?i)(?:^|\s)"# + escaped + #"\s*:\s*(.+?)(?=\s+[a-z_]+:|$)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        let value = String(text[valueRange]).trimmed
        return value.isEmpty ? nil : value
    }
}
