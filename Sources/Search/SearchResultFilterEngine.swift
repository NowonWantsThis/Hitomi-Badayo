import Foundation

enum SearchResultFilterEngine {
    nonisolated static func filteredSearchResults(
        _ results: [SearchResultLink],
        filter: String,
        knownSources: Set<String>
    ) -> [SearchResultLink] {
        guard let expression = searchResultFilterExpression(from: filter) else { return results }
        return results.filter { result in
            searchResultFilterExpression(expression, matches: result, knownSources: knownSources)
        }
    }

    nonisolated static func filteredSearchResults(
        _ results: [SearchResultLink],
        knownFilter: SearchResultKnownFilter,
        knownSources: Set<String>
    ) -> [SearchResultLink] {
        switch knownFilter {
        case .all:
            return results
        case .notDownloaded:
            return results.filter { !knownSources.contains(URLIdentity.normalize($0.url)) }
        case .downloaded:
            return results.filter { knownSources.contains(URLIdentity.normalize($0.url)) }
        }
    }

    nonisolated static func processedSearchResults(
        _ results: [SearchResultLink],
        deduplicate: Bool,
        hideKnown: Bool,
        knownSources: Set<String>,
        excludedHitomiTags: [String] = []
    ) -> [SearchResultLink] {
        let excludedTags = excludedHitomiTags.map(normalizedHitomiTag).filter { !$0.isEmpty }
        var seen = Set<String>()
        var processed: [SearchResultLink] = []
        for result in results {
            let key = URLIdentity.normalize(result.url)
            guard !hideKnown || !knownSources.contains(key) else { continue }
            guard !matchesHitomiExcludedTags(result, excludedTags: excludedTags) else { continue }
            if deduplicate {
                guard seen.insert(key).inserted else { continue }
            }
            processed.append(result)
        }
        return processed
    }

    nonisolated static func searchResultFilterReferencesKnownSources(_ filter: String) -> Bool {
        guard let expression = searchResultFilterExpression(from: filter) else { return false }
        return searchResultFilterExpressionReferencesKnownSources(expression)
    }

    private struct SearchResultFilterToken {
        var field: String?
        var value: String
        var isNegated: Bool
    }

    private indirect enum SearchResultFilterExpression {
        case token(SearchResultFilterToken)
        case and([SearchResultFilterExpression])
        case or([SearchResultFilterExpression])
        case not(SearchResultFilterExpression)
    }

    private struct SearchResultFilterParser {
        var lexemes: [FilterLexeme]
        var index = 0

        mutating func parse() -> SearchResultFilterExpression? {
            parseOr()
        }

        private mutating func parseOr() -> SearchResultFilterExpression? {
            guard var expression = parseAnd() else { return nil }
            var expressions = [expression]
            while consume(.or) {
                if let next = parseAnd() {
                    expressions.append(next)
                }
            }
            if expressions.count > 1 {
                expression = .or(expressions)
            }
            return expression
        }

        private mutating func parseAnd() -> SearchResultFilterExpression? {
            guard let first = parseNot() else { return nil }
            var expressions = [first]
            while true {
                if consume(.and) {
                    if let next = parseNot() {
                        expressions.append(next)
                    }
                    continue
                }
                guard startsPrimary(peek()) else { break }
                if let next = parseNot() {
                    expressions.append(next)
                } else {
                    break
                }
            }
            return expressions.count == 1 ? first : .and(expressions)
        }

        private mutating func parseNot() -> SearchResultFilterExpression? {
            if consume(.not), let expression = parseNot() {
                return .not(expression)
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> SearchResultFilterExpression? {
            guard let lexeme = peek() else { return nil }
            switch lexeme {
            case .term(let piece):
                index += 1
                return SearchResultFilterEngine.searchResultFilterToken(from: piece).map(SearchResultFilterExpression.token)
            case .openGroup:
                index += 1
                let expression = parseOr()
                _ = consume(.closeGroup)
                return expression
            default:
                return nil
            }
        }

        private func peek() -> FilterLexeme? {
            lexemes.indices.contains(index) ? lexemes[index] : nil
        }

        private mutating func consume(_ lexeme: FilterLexeme) -> Bool {
            guard peek() == lexeme else { return false }
            index += 1
            return true
        }

        private func startsPrimary(_ lexeme: FilterLexeme?) -> Bool {
            switch lexeme {
            case .term, .not, .openGroup:
                return true
            default:
                return false
            }
        }
    }

    private nonisolated static func searchResultFilterTokens(from query: String) -> [SearchResultFilterToken] {
        FilterSyntaxCore.pieces(from: query).compactMap(searchResultFilterToken)
    }

    private nonisolated static func searchResultFilterExpression(from query: String) -> SearchResultFilterExpression? {
        let lexemes = FilterSyntaxCore.lexemes(from: query)
        guard !lexemes.isEmpty else { return nil }
        var parser = SearchResultFilterParser(lexemes: lexemes)
        return parser.parse()
    }

    private nonisolated static func searchResultFilterExpression(
        _ expression: SearchResultFilterExpression,
        matches result: SearchResultLink,
        knownSources: Set<String>
    ) -> Bool {
        switch expression {
        case .token(let token):
            return searchResultFilterToken(token, matches: result, knownSources: knownSources)
        case .and(let expressions):
            return expressions.allSatisfy { searchResultFilterExpression($0, matches: result, knownSources: knownSources) }
        case .or(let expressions):
            return expressions.contains { searchResultFilterExpression($0, matches: result, knownSources: knownSources) }
        case .not(let expression):
            return !searchResultFilterExpression(expression, matches: result, knownSources: knownSources)
        }
    }

    private nonisolated static func searchResultFilterExpressionReferencesKnownSources(_ expression: SearchResultFilterExpression) -> Bool {
        switch expression {
        case .token(let token):
            let field = token.field ?? ""
            return ["done", "complete", "completed", "known", "downloaded"].contains(field)
        case .and(let expressions), .or(let expressions):
            return expressions.contains(where: searchResultFilterExpressionReferencesKnownSources)
        case .not(let expression):
            return searchResultFilterExpressionReferencesKnownSources(expression)
        }
    }

    private nonisolated static func searchResultFilterToken(from piece: String) -> SearchResultFilterToken? {
        var value = piece.trimmed
        guard !value.isEmpty else { return nil }

        var isNegated = false
        while value.hasPrefix("-") {
            isNegated = true
            value.removeFirst()
            value = value.trimmed
        }
        guard !value.isEmpty else { return nil }

        if let comparison = searchResultPageComparisonToken(from: value, isNegated: isNegated) {
            return comparison
        }

        if let separator = value.firstIndex(of: ":") {
            let field = String(value[..<separator]).trimmed.lowercased()
            let fieldValue = FilterSyntaxCore.strippingQuotes(
                from: String(value[value.index(after: separator)...]).trimmed
            )
            guard !field.isEmpty, !fieldValue.isEmpty || searchResultFilterAllowsEmptyValue(for: field) else { return nil }
            return SearchResultFilterToken(field: field, value: fieldValue.lowercased(), isNegated: isNegated)
        }

        return SearchResultFilterToken(
            field: nil,
            value: FilterSyntaxCore.strippingQuotes(from: value).lowercased(),
            isNegated: isNegated
        )
    }

    private nonisolated static func searchResultPageComparisonToken(from value: String, isNegated: Bool) -> SearchResultFilterToken? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(pages?|page_count|pagecount|total_pages|totalpages)\s*(<=|>=|<|>)\s*(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let result = regex.firstMatch(in: value, range: range),
              result.numberOfRanges == 4,
              let opRange = Range(result.range(at: 2), in: value),
              let valueRange = Range(result.range(at: 3), in: value) else {
            return nil
        }
        let op = String(value[opRange])
        let threshold = FilterSyntaxCore.strippingQuotes(from: String(value[valueRange]).trimmed)
        guard !threshold.isEmpty else { return nil }
        return SearchResultFilterToken(field: "pages\(op)", value: threshold.lowercased(), isNegated: isNegated)
    }

    private nonisolated static func searchResultFilterAllowsEmptyValue(for field: String) -> Bool {
        ["done", "complete", "completed", "known", "downloaded"].contains(field)
    }

    private nonisolated static func searchResultFilterToken(
        _ token: SearchResultFilterToken,
        matches result: SearchResultLink,
        knownSources: Set<String>
    ) -> Bool {
        let value = token.value
        let matched: Bool
        if value.isEmpty {
            switch token.field {
            case "done", "complete", "completed", "known", "downloaded":
                matched = searchResultFilterDone(result, knownSources: knownSources, matches: "true")
            default:
                matched = true
            }
        } else {
            switch token.field {
            case nil:
                matched = searchResultFilterHaystack(for: result).contains(value)
            case "done", "complete", "completed", "known", "downloaded":
                matched = searchResultFilterDone(result, knownSources: knownSources, matches: value)
            case "title", "name":
                matched = result.title.lowercased().contains(value)
            case "url", "source", "src":
                matched = result.url.lowercased().contains(value)
            case "site", "host", "domain":
                matched = searchResultFilterHost(for: result).contains(value)
            case "meta", "metadata":
                matched = SearchResultMetadataService.haystack(for: result).contains(value)
            case "tag", "tags":
                matched = (SearchResultMetadataService.value(for: result, keys: ["tag", "tags"]) ?? result.metadataText).lowercased().contains(value)
            case "date", "published", "posted", "created", "uploaded":
                matched = (SearchResultMetadataService.dateText(for: result) ?? result.metadataText).lowercased().contains(value)
            case "page", "pages", "page_count", "pagecount", "total_pages", "totalpages":
                matched = searchResultFilterPageCount(result, matches: value)
            case "pages<":
                matched = searchResultFilterPageCount(result, comparison: .lessThan, threshold: value)
            case "pages<=":
                matched = searchResultFilterPageCount(result, comparison: .lessThanOrEqual, threshold: value)
            case "pages>":
                matched = searchResultFilterPageCount(result, comparison: .greaterThan, threshold: value)
            case "pages>=":
                matched = searchResultFilterPageCount(result, comparison: .greaterThanOrEqual, threshold: value)
            default:
                if let field = token.field,
                   let metadataMatched = SearchResultMetadataService.fieldMatches(result, field: field, value: value) {
                    matched = metadataMatched
                } else if let field = token.field {
                    matched = searchResultFilterHaystack(for: result).contains("\(field):\(value)")
                } else {
                    matched = searchResultFilterHaystack(for: result).contains(value)
                }
            }
        }
        return token.isNegated ? !matched : matched
    }

    private nonisolated static func searchResultFilterDone(
        _ result: SearchResultLink,
        knownSources: Set<String>,
        matches value: String
    ) -> Bool {
        let isKnown = knownSources.contains(URLIdentity.normalize(result.url))
        return FilterSyntaxCore.bool(isKnown, matches: value)
    }

    private nonisolated static func searchResultFilterPageCount(
        _ result: SearchResultLink,
        comparison: FilterComparison,
        threshold: String
    ) -> Bool {
        guard let count = SearchResultMetadataService.pageCount(for: result),
              let threshold = FilterSyntaxCore.nonnegativeInteger(from: threshold) else {
            return false
        }
        switch comparison {
        case .lessThan:
            return count < threshold
        case .lessThanOrEqual:
            return count <= threshold
        case .greaterThan:
            return count > threshold
        case .greaterThanOrEqual:
            return count >= threshold
        }
    }

    private nonisolated static func searchResultFilterPageCount(
        _ result: SearchResultLink,
        matches value: String
    ) -> Bool {
        let trimmed = value.trimmed
        if let comparison = FilterSyntaxCore.inlineComparison(from: trimmed) {
            return searchResultFilterPageCount(result, comparison: comparison.comparison, threshold: comparison.threshold)
        }
        guard let count = SearchResultMetadataService.pageCount(for: result),
              let expected = FilterSyntaxCore.nonnegativeInteger(from: trimmed) else {
            return false
        }
        return count == expected
    }

    private nonisolated static func searchResultFilterHaystack(for result: SearchResultLink) -> String {
        [
            result.title,
            result.url,
            result.siteIdentifier ?? "",
            searchResultFilterHost(for: result),
            result.metadataText,
            result.metadata
                .flatMap { [$0.key, $0.value] }
                .joined(separator: " ")
        ].joined(separator: " ").lowercased()
    }

    private nonisolated static func searchResultFilterHost(for result: SearchResultLink) -> String {
        SearchResultMetadataService.normalizedHost(for: result)
    }

    nonisolated static func hitomiExcludedTags(from text: String) -> [String] {
        var seen = Set<String>()
        var tags: [String] = []
        for raw in text.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")) {
            let tag = normalizedHitomiTag(raw.trimmingCharacters(in: CharacterSet(charactersIn: "# ")))
            guard !tag.isEmpty, seen.insert(tag).inserted else { continue }
            tags.append(tag)
        }
        return tags
    }

    private nonisolated static func matchesHitomiExcludedTags(_ result: SearchResultLink, excludedTags: [String]) -> Bool {
        guard !excludedTags.isEmpty, isHitomiSearchResult(result) else { return false }
        let text = normalizedHitomiTag([result.title, result.url, result.metadataText].joined(separator: " "))
        return excludedTags.contains { text.contains($0) }
    }

    private nonisolated static func isHitomiSearchResult(_ result: SearchResultLink) -> Bool {
        if result.siteIdentifier?.lowercased() == "hitomi" {
            return true
        }
        guard let host = URL(string: result.url)?.host?.lowercased() else { return false }
        return host == "hitomi.la" || host.hasSuffix(".hitomi.la")
    }

    private nonisolated static func normalizedHitomiTag(_ value: String) -> String {
        value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s*:\\s*", with: ":", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }
}
