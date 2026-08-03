import Foundation

enum ArtistRecommendationService {
    private enum Bucket {
        case job
        case history
        case bookmark
    }

    private struct Accumulator {
        var name: String
        var score: Double = 0
        var jobCount: Int = 0
        var historyCount: Int = 0
        var bookmarkCount: Int = 0
        var relatedTermCounts: [String: Int] = [:]
        var exampleTitle: String = ""
        var lastSeen: Date?

        mutating func add(
            score: Double,
            title: String,
            metadata: [String: String],
            lastSeen: Date?,
            bucket: Bucket
        ) {
            self.score += score
            switch bucket {
            case .job: jobCount += 1
            case .history: historyCount += 1
            case .bookmark: bookmarkCount += 1
            }
            if exampleTitle.isEmpty {
                exampleTitle = title
            }
            if let lastSeen, lastSeen > (self.lastSeen ?? .distantPast) {
                self.lastSeen = lastSeen
            }
            for term in ArtistRecommendationService.recommendationTerms(
                from: metadata
            ) {
                relatedTermCounts[term, default: 0] += 1
            }
        }

        var recommendation: ArtistRecommendation {
            let terms = relatedTermCounts
                .sorted {
                    if $0.value != $1.value { return $0.value > $1.value }
                    return $0.key.localizedStandardCompare($1.key) ==
                        .orderedAscending
                }
                .prefix(4)
                .map(\.key)
            return ArtistRecommendation(
                name: name,
                score: score,
                jobCount: jobCount,
                historyCount: historyCount,
                bookmarkCount: bookmarkCount,
                relatedTerms: Array(terms),
                exampleTitle: exampleTitle,
                lastSeen: lastSeen
            )
        }
    }

    private static let originalArtistMetadataKeys = [
        "artist", "artists", "artist_name", "artist_names",
        "author", "authors", "author_name", "author_names",
        "creator", "creators", "creator_name", "creator_names",
        "uploader", "uploaders", "uploader_name",
        "channel", "channels", "channel_name",
        "username", "user_name", "user", "member_name", "owner_name"
    ]

    private static let originalGroupMetadataKeys = [
        "group", "groups", "group_name", "group_names",
        "circle", "circles", "circle_name", "circle_names",
        "team", "studio", "publisher"
    ]

    static func recommendations(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        bookmarks: [URLBookmark],
        limit: Int = 20
    ) -> [ArtistRecommendation] {
        var accumulators: [String: Accumulator] = [:]

        func add(
            names: [String],
            score: Double,
            title: String,
            metadata: [String: String],
            lastSeen: Date?,
            bucket: Bucket
        ) {
            for name in names {
                let key = name.folding(
                    options: [.caseInsensitive, .diacriticInsensitive],
                    locale: Locale(identifier: "en_US_POSIX")
                )
                var accumulator = accumulators[key] ?? Accumulator(name: name)
                accumulator.add(
                    score: score,
                    title: title,
                    metadata: metadata,
                    lastSeen: lastSeen,
                    bucket: bucket
                )
                accumulators[key] = accumulator
            }
        }

        for job in jobs {
            let names = artistNames(from: job.metadata)
            guard !names.isEmpty else { continue }
            add(
                names: names,
                score: recommendationScore(for: job.status),
                title: job.title,
                metadata: job.metadata,
                lastSeen: nil,
                bucket: .job
            )
        }

        for entry in history {
            let names = artistNames(from: entry.metadata)
            guard !names.isEmpty else { continue }
            add(
                names: names,
                score: historyScore(completedAt: entry.completedAt),
                title: entry.title,
                metadata: entry.metadata,
                lastSeen: entry.completedAt,
                bucket: .history
            )
        }

        for bookmark in bookmarks {
            let names = artistNames(from: bookmark)
            guard !names.isEmpty else { continue }
            let metadata = [
                "tags": bookmark.tags.joined(separator: ", "),
                "note": bookmark.note
            ]
            add(
                names: names,
                score: 1.25,
                title: bookmark.title,
                metadata: metadata,
                lastSeen: bookmark.createdAt,
                bucket: .bookmark
            )
        }

        return accumulators.values
            .map(\.recommendation)
            .sorted {
                if $0.score != $1.score { return $0.score > $1.score }
                if $0.lastSeen != $1.lastSeen {
                    return ($0.lastSeen ?? .distantPast) >
                        ($1.lastSeen ?? .distantPast)
                }
                return $0.name.localizedStandardCompare($1.name) ==
                    .orderedAscending
            }
            .prefix(max(0, limit))
            .map { $0 }
    }

    static func referenceCount(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        bookmarks: [URLBookmark]
    ) -> Int {
        let jobCount = jobs.filter {
            !artistNames(from: $0.metadata).isEmpty
        }.count
        let historyCount = history.filter {
            !artistNames(from: $0.metadata).isEmpty
        }.count
        let bookmarkCount = bookmarks.filter {
            !artistNames(from: $0).isEmpty
        }.count
        return jobCount + historyCount + bookmarkCount
    }

    static func originalArtistNames(
        from metadata: [String: String]
    ) -> [String] {
        let artists = firstArtistNames(
            in: metadata,
            keys: originalArtistMetadataKeys
        )
        if !artists.isEmpty {
            return artists
        }
        return firstArtistNames(in: metadata, keys: originalGroupMetadataKeys)
    }

    static func originalArtistDisplayName(
        from metadata: [String: String]
    ) -> String? {
        let names = originalArtistNames(from: metadata)
        return names.isEmpty ? nil : names.joined(separator: " + ")
    }

    private static func recommendationScore(for status: JobStatus) -> Double {
        switch status {
        case .finished: return 4
        case .downloading, .resolving: return 2
        case .queued: return 1.5
        case .failed: return 0.75
        case .cancelled: return 0.25
        }
    }

    private static func historyScore(completedAt: Date) -> Double {
        let age = max(0, -completedAt.timeIntervalSinceNow / 86_400)
        return 2 + max(0, 1.5 - (age / 60))
    }

    private static func artistNames(
        from metadata: [String: String]
    ) -> [String] {
        originalArtistNames(from: metadata)
    }

    private static func artistNames(from bookmark: URLBookmark) -> [String] {
        let taggedNames = bookmark.tags.compactMap(artistNameFromTaggedValue)
        let noteNames = bookmark.note
            .components(separatedBy: CharacterSet(charactersIn: ",;\n\r"))
            .compactMap(artistNameFromTaggedValue)
        return uniqueArtistNames(taggedNames + noteNames)
    }

    private static func artistNameFromTaggedValue(_ raw: String) -> String? {
        let value = raw.trimmed.trimmingCharacters(
            in: CharacterSet(charactersIn: "#")
        )
        guard let separator = value.firstIndex(of: ":") else { return nil }
        let key = String(value[..<separator]).trimmed.lowercased()
        guard [
            "artist", "author", "creator", "uploader", "channel", "작가"
        ].contains(key) else {
            return nil
        }
        return cleanedArtistName(String(value[value.index(after: separator)...]))
    }

    private static func firstArtistNames(
        in metadata: [String: String],
        keys: [String]
    ) -> [String] {
        for key in keys {
            let raw = metadataValue(metadata, keys: [key])
            guard !raw.isEmpty else { continue }
            let names = uniqueArtistNames(splitArtistNames(raw))
            if !names.isEmpty {
                return names
            }
        }
        return []
    }

    private static func splitArtistNames(_ raw: String) -> [String] {
        if let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data),
           let values = object as? [Any] {
            let names = values.compactMap { value -> String? in
                if let value = value as? String {
                    return cleanedArtistName(value)
                }
                if let value = value as? [String: Any] {
                    for key in ["name", "value", "label"] {
                        if let name = value[key] as? String,
                           let cleaned = cleanedArtistName(name) {
                            return cleaned
                        }
                    }
                }
                return nil
            }
            if !names.isEmpty {
                return names
            }
        }

        let separated = raw.replacingOccurrences(
            of: "\\s+\\+\\s+",
            with: "\n",
            options: .regularExpression
        )
        return separated
            .components(separatedBy: CharacterSet(charactersIn: ",;|\n\r"))
            .compactMap(cleanedArtistName)
    }

    private static func cleanedArtistName(_ raw: String) -> String? {
        let cleaned = raw
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'[]()"))
            .replacingOccurrences(
                of: "\\s+",
                with: " ",
                options: .regularExpression
            )
            .trimmed
        guard !cleaned.isEmpty else { return nil }
        guard !["unknown", "n/a", "none", "anonymous"].contains(
            cleaned.lowercased()
        ) else {
            return nil
        }
        return cleaned
    }

    private static func uniqueArtistNames(_ names: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for name in names {
            let key = name.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard seen.insert(key).inserted else { continue }
            result.append(name)
        }
        return result
    }

    private static func recommendationTerms(
        from metadata: [String: String]
    ) -> [String] {
        let keys = [
            "tags", "tag", "language", "category", "type", "series",
            "parody", "site", "note"
        ]
        let rawTerms = keys
            .map { metadataValue(metadata, keys: [$0]) }
            .filter { !$0.isEmpty }
        return uniqueArtistNames(rawTerms.flatMap(splitArtistNames))
            .prefix(8)
            .map { $0 }
    }

    private static func metadataValue(
        _ metadata: [String: String],
        keys: [String]
    ) -> String {
        for key in keys {
            if let value = metadata.first(where: {
                $0.key.lowercased() == key.lowercased()
            })?.value.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return ""
    }
}
