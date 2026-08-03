import Foundation

enum MetadataExplorerService {
    nonisolated static func finderResults(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        field: MetadataFinderField,
        query: String,
        mode: MetadataFinderMode,
        limit: Int = 500
    ) -> [MetadataFinderResult] {
        let normalizedQuery = query.trimmed
        let regex = finderRegex(query: normalizedQuery, mode: mode)
        var values: [String: Accumulator] = [:]

        for job in jobs {
            addFinderValues(
                metadata: job.metadata,
                title: job.title,
                source: job.source,
                isQueueEntry: true,
                field: field,
                query: normalizedQuery,
                mode: mode,
                regex: regex,
                values: &values
            )
        }

        for entry in history {
            addFinderValues(
                metadata: entry.metadata,
                title: entry.title,
                source: entry.source,
                isQueueEntry: false,
                field: field,
                query: normalizedQuery,
                mode: mode,
                regex: regex,
                values: &values
            )
        }

        return values.values
            .map {
                MetadataFinderResult(
                    field: field,
                    value: $0.value,
                    queueCount: $0.queueCount,
                    historyCount: $0.historyCount,
                    sampleTitle: $0.sampleTitle,
                    sampleSource: $0.sampleSource,
                    score: $0.score
                )
            }
            .sorted { left, right in
                if (left.score ?? -1) != (right.score ?? -1) {
                    return (left.score ?? -1) > (right.score ?? -1)
                }
                if left.totalCount != right.totalCount {
                    return left.totalCount > right.totalCount
                }
                return left.value.localizedStandardCompare(right.value) ==
                    .orderedAscending
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    nonisolated static func analysisEntries(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        field: MetadataAnalysisField,
        limit: Int = 500
    ) -> [MetadataAnalysisEntry] {
        var values: [String: Accumulator] = [:]

        for job in jobs {
            addAnalysisValues(
                metadata: job.metadata,
                title: job.title,
                source: job.source,
                isQueueEntry: true,
                field: field,
                values: &values
            )
        }

        for entry in history {
            addAnalysisValues(
                metadata: entry.metadata,
                title: entry.title,
                source: entry.source,
                isQueueEntry: false,
                field: field,
                values: &values
            )
        }

        return values.values
            .map {
                MetadataAnalysisEntry(
                    field: field,
                    value: $0.value,
                    queueCount: $0.queueCount,
                    historyCount: $0.historyCount,
                    sampleTitle: $0.sampleTitle,
                    sampleSource: $0.sampleSource
                )
            }
            .sorted { left, right in
                if left.totalCount != right.totalCount {
                    return left.totalCount > right.totalCount
                }
                if left.queueCount != right.queueCount {
                    return left.queueCount > right.queueCount
                }
                return left.value.localizedStandardCompare(right.value) ==
                    .orderedAscending
            }
            .prefix(max(1, limit))
            .map { $0 }
    }

    nonisolated static func finderKeys(
        for field: MetadataFinderField
    ) -> [String] {
        switch field {
        case .artist:
            return [
                "artist", "artists", "author", "creator",
                "uploader", "channel", "username", "user"
            ]
        case .group:
            return ["group", "groups", "circle", "circles", "team", "studio"]
        case .series:
            return [
                "series", "parody", "album", "collection",
                "playlist", "show", "work", "comic"
            ]
        case .character:
            return ["character", "characters", "char", "chars"]
        case .tag:
            return [
                "tag", "tags", "genre", "genres",
                "category", "language", "site"
            ]
        }
    }

    nonisolated static func finderValues(
        field: MetadataFinderField,
        metadata: [String: String]
    ) -> [String] {
        uniqueValues(metadata: metadata, keys: finderKeys(for: field))
    }

    nonisolated static func analysisKeys(
        for field: MetadataAnalysisField
    ) -> [String] {
        switch field {
        case .artist:
            return finderKeys(for: .artist)
        case .group:
            return finderKeys(for: .group)
        case .type:
            return [
                "type", "types", "kind", "class", "media_type",
                "mediaType", "content_type", "contentType"
            ]
        case .series:
            return finderKeys(for: .series)
        case .character:
            return finderKeys(for: .character)
        case .tag:
            return [
                "tag", "tags", "genre", "genres",
                "category", "categories"
            ]
        case .language:
            return ["language", "languages", "lang", "langs", "locale"]
        }
    }

    nonisolated static func analysisValues(
        field: MetadataAnalysisField,
        metadata: [String: String]
    ) -> [String] {
        uniqueValues(metadata: metadata, keys: analysisKeys(for: field))
    }

    nonisolated static func finderSearchToken(
        _ result: MetadataFinderResult
    ) -> String {
        searchToken(field: result.field.rawValue, value: result.value)
    }

    nonisolated static func analysisSearchToken(
        _ entry: MetadataAnalysisEntry
    ) -> String {
        searchToken(field: entry.field.rawValue, value: entry.value)
    }

    private nonisolated static func addFinderValues(
        metadata: [String: String],
        title: String,
        source: String,
        isQueueEntry: Bool,
        field: MetadataFinderField,
        query: String,
        mode: MetadataFinderMode,
        regex: NSRegularExpression?,
        values: inout [String: Accumulator]
    ) {
        for value in finderValues(field: field, metadata: metadata) {
            guard let score = finderScore(
                value: value,
                query: query,
                mode: mode,
                regex: regex
            ) else {
                continue
            }
            let key = value.lowercased()
            var accumulator = values[key] ?? Accumulator(value: value)
            if isQueueEntry {
                accumulator.queueCount += 1
            } else {
                accumulator.historyCount += 1
            }
            if accumulator.sampleTitle.trimmed.isEmpty {
                accumulator.sampleTitle = title
            }
            if accumulator.sampleSource.trimmed.isEmpty {
                accumulator.sampleSource = source
            }
            accumulator.score = max(accumulator.score ?? score, score)
            values[key] = accumulator
        }
    }

    private nonisolated static func addAnalysisValues(
        metadata: [String: String],
        title: String,
        source: String,
        isQueueEntry: Bool,
        field: MetadataAnalysisField,
        values: inout [String: Accumulator]
    ) {
        for value in analysisValues(field: field, metadata: metadata) {
            let key = value.lowercased()
            var accumulator = values[key] ?? Accumulator(value: value)
            if isQueueEntry {
                accumulator.queueCount += 1
            } else {
                accumulator.historyCount += 1
            }
            if accumulator.sampleTitle.trimmed.isEmpty {
                accumulator.sampleTitle = title
            }
            if accumulator.sampleSource.trimmed.isEmpty {
                accumulator.sampleSource = source
            }
            values[key] = accumulator
        }
    }

    private nonisolated static func uniqueValues(
        metadata: [String: String],
        keys: [String]
    ) -> [String] {
        var seen = Set<String>()
        var values: [String] = []
        for key in keys {
            guard let rawValue = metadata[key],
                  !rawValue.trimmed.isEmpty else {
                continue
            }
            for value in split(rawValue) {
                let normalized = value.lowercased()
                guard seen.insert(normalized).inserted else { continue }
                values.append(value)
            }
        }
        return values
    }

    private nonisolated static func split(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;|\n\t"))
            .map {
                $0.trimmingCharacters(
                    in: CharacterSet(charactersIn: " #[](){}\"'")
                ).trimmed
            }
            .filter { !$0.isEmpty }
    }

    private nonisolated static func finderRegex(
        query: String,
        mode: MetadataFinderMode
    ) -> NSRegularExpression? {
        guard mode == .regex, !query.trimmed.isEmpty else { return nil }
        return try? NSRegularExpression(
            pattern: query,
            options: [.caseInsensitive]
        )
    }

    private nonisolated static func finderScore(
        value: String,
        query: String,
        mode: MetadataFinderMode,
        regex: NSRegularExpression?
    ) -> Int? {
        let query = query.trimmed
        guard !query.isEmpty else { return 0 }
        let valueLower = value.lowercased()
        let queryLower = query.lowercased()

        switch mode {
        case .plain:
            return valueLower.contains(queryLower) ? 100 : nil
        case .regex:
            guard let regex else { return nil }
            let range = NSRange(value.startIndex..<value.endIndex, in: value)
            return regex.firstMatch(in: value, range: range) == nil ? nil : 100
        case .fuzzy:
            if valueLower.contains(queryLower) {
                return 100
            }
            let tokens = valueLower
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
            if tokens.contains(
                where: { $0.hasPrefix(queryLower) || $0.contains(queryLower) }
            ) {
                return 90
            }
            guard isFuzzySubsequence(queryLower, in: valueLower) else {
                return nil
            }
            let compactValueCount = max(
                1,
                valueLower.filter { !$0.isWhitespace }.count
            )
            return max(
                55,
                min(
                    85,
                    Int(
                        (Double(queryLower.count) / Double(compactValueCount)) *
                            100.0
                    )
                )
            )
        }
    }

    private nonisolated static func isFuzzySubsequence(
        _ query: String,
        in value: String
    ) -> Bool {
        var current = value.startIndex
        for character in query where !character.isWhitespace {
            guard let match = value[current...].firstIndex(of: character) else {
                return false
            }
            current = value.index(after: match)
        }
        return true
    }

    private nonisolated static func searchToken(
        field: String,
        value: String
    ) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        if value.contains(where: { $0.isWhitespace }) {
            return "\(field):\"\(escaped)\""
        }
        return "\(field):\(value)"
    }

    private struct Accumulator {
        var value: String
        var queueCount = 0
        var historyCount = 0
        var sampleTitle = ""
        var sampleSource = ""
        var score: Int?
    }
}
