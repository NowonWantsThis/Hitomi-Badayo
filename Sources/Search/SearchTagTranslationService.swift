import Foundation

enum SearchTagTranslationService {
    nonisolated static func advancedSearchQuery(
        title: String,
        artist: String,
        group: String,
        series: String,
        character: String,
        tag: String,
        language: String,
        types: Set<HitomiAdvancedSearchType>,
        languagePreset: HitomiAdvancedLanguagePreset = .all,
        excludeWebtoon: Bool = false
    ) -> String {
        var tokens: [String] = []

        if let token = advancedSearchFieldToken(prefix: "title", value: title) {
            tokens.append(token)
        }
        if let token = advancedSearchFieldToken(prefix: "artist", value: artist) {
            tokens.append(token)
        }
        if let token = advancedSearchFieldToken(prefix: "group", value: group) {
            tokens.append(token)
        }
        if let token = advancedSearchFieldToken(prefix: "parody", value: series) {
            tokens.append(token)
        }
        if let token = advancedSearchFieldToken(prefix: "character", value: character) {
            tokens.append(token)
        }

        let translatedTags = translatedQueryTags(from: tag)
        if !translatedTags.isEmpty {
            tokens.append(translatedTags)
        }

        if let token = advancedLanguageToken(from: language) {
            tokens.append(token)
        }

        tokens.append(contentsOf: languagePreset.queryTokens)

        if excludeWebtoon {
            tokens.append("-webtoon")
        }

        for type in HitomiAdvancedSearchType.allCases where types.contains(type) {
            tokens.append(type.queryToken)
        }

        return tokens.joined(separator: " ")
    }

    nonisolated static func translatedQueryTags(from text: String) -> String {
        translationPieces(from: text)
            .compactMap(translatedTagToken)
            .joined(separator: " ")
    }

    nonisolated static func suggestions(
        for text: String,
        limit: Int = 8
    ) -> [SearchTagSuggestion] {
        let fragment = activeCompletionFragment(from: text)
        guard !fragment.isEmpty else {
            return Array(suggestionCatalog.prefix(limit))
        }

        let query = translationKey(fragment)
        if let separator = fragment.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            let rawPrefix = String(fragment[..<separator])
            let rawValue = String(fragment[fragment.index(after: separator)...])
            let prefix = prefixTranslations[translationKey(rawPrefix)] ?? queryValue(rawPrefix)
            let valueQuery = translationKey(rawValue)
            let genderValues = ["maid", "school uniform", "swimsuit", "glasses"]

            if prefix == "male" || prefix == "female" {
                return genderValues
                    .map {
                        SearchTagSuggestion(
                            title: "\($0) (\(prefix))",
                            token: "\(prefix):\($0)",
                            detail: prefix
                        )
                    }
                    .filter { valueQuery.isEmpty || suggestionMatches($0, query: valueQuery) }
                    .prefix(limit)
                    .map { $0 }
            }

            if freeTextPrefixes.contains(prefix) {
                let normalizedValue = queryValue(rawValue)
                let directSuggestion = normalizedValue.isEmpty ? [] : [
                    SearchTagSuggestion(
                        title: "\(prefix):\(normalizedValue)",
                        token: "\(prefix):\(normalizedValue)",
                        detail: prefix
                    )
                ]
                let catalogSuggestions = catalog(forPrefix: prefix).map { suggestion in
                    let value = suggestion.token
                        .split(separator: ":", maxSplits: 1)
                        .last
                        .map(String.init) ?? suggestion.token
                    return SearchTagSuggestion(
                        title: suggestion.title,
                        token: "\(prefix):\(value)",
                        detail: prefix
                    )
                }
                let matchingSuggestions = (directSuggestion + catalogSuggestions)
                    .filter { valueQuery.isEmpty || suggestionMatches($0, query: valueQuery) }
                return uniqueSuggestions(matchingSuggestions)
                    .prefix(limit)
                    .map { $0 }
            }

            return catalog(forPrefix: prefix)
                .map { suggestion in
                    let value = suggestion.token
                        .split(separator: ":", maxSplits: 1)
                        .last
                        .map(String.init) ?? suggestion.token
                    return SearchTagSuggestion(
                        title: suggestion.title,
                        token: "\(prefix):\(value)",
                        detail: prefix
                    )
                }
                .filter { valueQuery.isEmpty || suggestionMatches($0, query: valueQuery) }
                .prefix(limit)
                .map { $0 }
        }

        return suggestionCatalog
            .filter { suggestionMatches($0, query: query) }
            .prefix(limit)
            .map { $0 }
    }

    nonisolated static func translatedTagToken(_ raw: String) -> String? {
        var token = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !token.isEmpty else { return nil }

        var isExcluded = false
        if token.hasPrefix("-") || token.hasPrefix("!") {
            isExcluded = true
            token.removeFirst()
            token = token.trimmed
        }

        let translated: String?
        if let separator = token.firstIndex(where: { $0 == ":" || $0 == "：" }) {
            let prefix = String(token[..<separator])
            let valueStart = token.index(after: separator)
            let value = String(token[valueStart...])
            translated = translatedTag(prefix: prefix, value: value)
        } else {
            translated = translatedTagValue(token)
        }

        guard let translated, !translated.isEmpty else { return nil }
        return isExcluded ? "-\(translated)" : translated
    }

    nonisolated static func appendingQueryToken(
        _ token: String,
        to query: String
    ) -> String {
        let base = query.trimmed
        return base.isEmpty ? token : "\(base) \(token)"
    }

    private nonisolated static func translatedTag(
        prefix rawPrefix: String,
        value rawValue: String
    ) -> String? {
        let prefix = prefixTranslations[translationKey(rawPrefix)] ?? queryValue(rawPrefix)
        guard !prefix.isEmpty else { return nil }
        let value = translatedTagValue(rawValue, forPrefix: prefix) ?? queryValue(rawValue)
        guard !value.isEmpty else { return nil }
        return "\(prefix):\(value)"
    }

    private nonisolated static func translatedTagValue(
        _ raw: String,
        forPrefix prefix: String
    ) -> String? {
        guard let mapped = translatedTagValue(raw) else { return nil }
        guard let separator = mapped.firstIndex(of: ":") else { return mapped }
        let mappedPrefix = String(mapped[..<separator])
        let valueStart = mapped.index(after: separator)
        if mappedPrefix == prefix {
            return String(mapped[valueStart...])
        }
        return containsHangul(raw) ? nil : queryValue(raw)
    }

    private nonisolated static func translatedTagValue(_ raw: String) -> String? {
        let cleaned = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard !cleaned.isEmpty else { return nil }
        let key = translationKey(cleaned)
        if let mapped = valueTranslations[key] {
            return mapped
        }
        if containsHangul(cleaned) {
            return nil
        }
        return queryValue(cleaned)
    }

    private nonisolated static func translationPieces(from text: String) -> [String] {
        var pieces: [String] = []
        for rawChunk in text.components(separatedBy: CharacterSet(charactersIn: ",;\n\r")) {
            let chunk = rawChunk.trimmed
            guard !chunk.isEmpty else { continue }
            if translatedTagToken(chunk) != nil || chunk.contains(":") || chunk.contains("：") {
                pieces.append(chunk)
                continue
            }
            let words = chunk.components(separatedBy: .whitespacesAndNewlines)
                .map(\.trimmed)
                .filter { !$0.isEmpty }
            if words.count > 1 {
                pieces.append(contentsOf: words)
            } else {
                pieces.append(chunk)
            }
        }
        return pieces
    }

    private nonisolated static func activeCompletionFragment(from text: String) -> String {
        let separators = CharacterSet(charactersIn: ",;\n\r")
        let fragments = text.components(separatedBy: separators)
        return (fragments.last ?? text).trimmed
    }

    private nonisolated static func suggestionMatches(
        _ suggestion: SearchTagSuggestion,
        query: String
    ) -> Bool {
        guard !query.isEmpty else { return true }
        return [suggestion.title, suggestion.token, suggestion.detail]
            .map(translationKey)
            .contains { $0.contains(query) }
    }

    private nonisolated static func catalog(forPrefix prefix: String) -> [SearchTagSuggestion] {
        switch prefix {
        case "language":
            return suggestionCatalog.filter { $0.detail == "language" }
        case "type":
            return suggestionCatalog.filter { $0.detail == "type" }
        case "tag":
            return suggestionCatalog.filter { $0.detail == "tag" }
        default:
            return suggestionCatalog.filter { $0.detail != "prefix" }
        }
    }

    private nonisolated static func uniqueSuggestions(
        _ suggestions: [SearchTagSuggestion]
    ) -> [SearchTagSuggestion] {
        var seen = Set<String>()
        var output: [SearchTagSuggestion] = []
        for suggestion in suggestions {
            let key = translationKey(suggestion.token)
            guard seen.insert(key).inserted else { continue }
            output.append(suggestion)
        }
        return output
    }

    private nonisolated static func advancedSearchFieldToken(
        prefix: String,
        value: String
    ) -> String? {
        let normalized = queryValue(value)
        guard !normalized.isEmpty else { return nil }
        return "\(prefix):\(normalized)"
    }

    private nonisolated static func advancedLanguageToken(from language: String) -> String? {
        let value = language.trimmed
        guard !value.isEmpty else { return nil }

        if value.contains(":") || value.contains("："),
           let token = translatedTagToken(value),
           token.hasPrefix("language:") {
            return token
        }

        if let token = translatedTagToken("language:\(value)"),
           token.hasPrefix("language:") {
            return token
        }

        if let token = translatedTagToken(value),
           token.hasPrefix("language:") {
            return token
        }

        let normalized = queryValue(value)
        return normalized.isEmpty ? nil : "language:\(normalized)"
    }

    private nonisolated static func queryValue(_ raw: String) -> String {
        raw
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "#"))
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private nonisolated static func translationKey(_ raw: String) -> String {
        queryValue(raw).replacingOccurrences(of: " ", with: "")
    }

    private nonisolated static func containsHangul(_ text: String) -> Bool {
        text.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(Int(scalar.value)) ||
                (0x1100...0x11FF).contains(Int(scalar.value)) ||
                (0x3130...0x318F).contains(Int(scalar.value))
        }
    }

    private nonisolated static let prefixTranslations: [String: String] = [
        "artist": "artist",
        "아티스트": "artist",
        "작가": "artist",
        "작가명": "artist",
        "group": "group",
        "그룹": "group",
        "서클": "group",
        "circle": "group",
        "parody": "parody",
        "원작": "parody",
        "패러디": "parody",
        "series": "parody",
        "시리즈": "parody",
        "작품": "parody",
        "작품명": "parody",
        "character": "character",
        "캐릭터": "character",
        "인물": "character",
        "language": "language",
        "언어": "language",
        "lang": "language",
        "type": "type",
        "종류": "type",
        "타입": "type",
        "분류": "type",
        "female": "female",
        "여성": "female",
        "여자": "female",
        "male": "male",
        "남성": "male",
        "남자": "male",
        "tag": "tag",
        "태그": "tag"
    ]

    private nonisolated static let valueTranslations: [String: String] = [
        "한국어": "language:korean",
        "한글": "language:korean",
        "korean": "language:korean",
        "영어": "language:english",
        "english": "language:english",
        "일본어": "language:japanese",
        "japanese": "language:japanese",
        "중국어": "language:chinese",
        "chinese": "language:chinese",
        "스페인어": "language:spanish",
        "spanish": "language:spanish",
        "프랑스어": "language:french",
        "french": "language:french",
        "러시아어": "language:russian",
        "russian": "language:russian",
        "n/a": "language:n/a",
        "na": "language:n/a",
        "언어없음": "language:n/a",
        "동인지": "type:doujinshi",
        "doujinshi": "type:doujinshi",
        "망가": "type:manga",
        "만화": "type:manga",
        "manga": "type:manga",
        "아티스트cg": "type:artistcg",
        "artistcg": "type:artistcg",
        "게임cg": "type:gamecg",
        "gamecg": "type:gamecg",
        "이미지셋": "type:imageset",
        "이미지세트": "type:imageset",
        "imageset": "type:imageset",
        "코스프레": "type:cosplay",
        "cosplay": "type:cosplay",
        "애니": "type:anime",
        "애니메이션": "type:anime",
        "anime": "type:anime",
        "서양": "type:western",
        "western": "type:western",
        "메이드": "maid",
        "maid": "maid",
        "교복": "school uniform",
        "schooluniform": "school uniform",
        "수영복": "swimsuit",
        "swimsuit": "swimsuit",
        "안경": "glasses",
        "glasses": "glasses",
        "풀컬러": "full color",
        "컬러": "full color",
        "fullcolor": "full color",
        "웹툰": "webtoon",
        "webtoon": "webtoon"
    ]

    private nonisolated static let suggestionCatalog: [SearchTagSuggestion] = [
        SearchTagSuggestion(title: "Korean", token: "language:korean", detail: "language"),
        SearchTagSuggestion(title: "English", token: "language:english", detail: "language"),
        SearchTagSuggestion(title: "Japanese", token: "language:japanese", detail: "language"),
        SearchTagSuggestion(title: "Chinese", token: "language:chinese", detail: "language"),
        SearchTagSuggestion(title: "N/A Language", token: "language:n/a", detail: "language"),
        SearchTagSuggestion(title: "Doujinshi", token: "type:doujinshi", detail: "type"),
        SearchTagSuggestion(title: "Manga", token: "type:manga", detail: "type"),
        SearchTagSuggestion(title: "Artist CG", token: "type:artistcg", detail: "type"),
        SearchTagSuggestion(title: "Game CG", token: "type:gamecg", detail: "type"),
        SearchTagSuggestion(title: "Image Set", token: "type:imageset", detail: "type"),
        SearchTagSuggestion(title: "Cosplay", token: "type:cosplay", detail: "type"),
        SearchTagSuggestion(title: "Anime", token: "type:anime", detail: "type"),
        SearchTagSuggestion(title: "Western", token: "type:western", detail: "type"),
        SearchTagSuggestion(title: "Maid", token: "maid", detail: "tag"),
        SearchTagSuggestion(title: "School Uniform", token: "school uniform", detail: "tag"),
        SearchTagSuggestion(title: "Swimsuit", token: "swimsuit", detail: "tag"),
        SearchTagSuggestion(title: "Glasses", token: "glasses", detail: "tag"),
        SearchTagSuggestion(title: "Full Color", token: "full color", detail: "tag"),
        SearchTagSuggestion(title: "Webtoon", token: "webtoon", detail: "tag"),
        SearchTagSuggestion(title: "Artist", token: "artist:", detail: "prefix"),
        SearchTagSuggestion(title: "Group", token: "group:", detail: "prefix"),
        SearchTagSuggestion(title: "Parody", token: "parody:", detail: "prefix"),
        SearchTagSuggestion(title: "Character", token: "character:", detail: "prefix"),
        SearchTagSuggestion(title: "Male", token: "male:", detail: "prefix"),
        SearchTagSuggestion(title: "Female", token: "female:", detail: "prefix")
    ]

    private nonisolated static let freeTextPrefixes: Set<String> = [
        "artist",
        "group",
        "parody",
        "character"
    ]
}
