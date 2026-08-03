import Foundation

struct OutputChapterGroup {
    var title: String
    var path: String
    var indexes: [Int]
}

struct OutputViewSelectionService {
    func chapterGroups(
        in files: [OutputContentFile]
    ) -> [OutputChapterGroup] {
        var groups: [OutputChapterGroup] = []
        var positions: [String: Int] = [:]

        for (index, file) in files.enumerated() {
            let parts = file.relativePath
                .split(
                    separator: "/",
                    omittingEmptySubsequences: true
                )
                .map(String.init)
            let path = parts.count > 1
                ? parts[0]
                : ""
            let key = path.isEmpty
                ? "__root__"
                : path
            let title = path.isEmpty
                ? "Files"
                : path

            if let position = positions[key] {
                groups[position].indexes.append(index)
            } else {
                positions[key] = groups.count
                groups.append(
                    OutputChapterGroup(
                        title: title,
                        path: path,
                        indexes: [index]
                    )
                )
            }
        }

        return groups
    }

    func selectedFiles(
        in files: [OutputContentFile],
        query: [String: String]
    ) -> [OutputContentFile] {
        guard !files.isEmpty else {
            return []
        }
        if query["start"] == nil,
           query["end"] == nil,
           let chapterRange = chapterRange(
               in: files,
               query: query
           ) {
            let groups = chapterGroups(in: files)
            let selectedIndexes = Set(
                groups[chapterRange]
                    .flatMap(\.indexes)
            )
            return files.filter {
                selectedIndexes.contains(
                    $0.originalIndex
                )
            }
        }

        let start = max(
            0,
            Int(query["start"] ?? "") ?? 0
        )
        let end = min(
            files.count - 1,
            max(
                0,
                Int(query["end"] ?? "")
                    ?? (files.count - 1)
            )
        )
        guard start < files.count,
              end >= start else {
            return []
        }
        return Array(files[start...end])
    }

    func sortedFiles(
        _ files: [OutputContentFile],
        sort: String,
        descending: Bool
    ) -> [OutputContentFile] {
        guard files.count > 1 else {
            return files
        }
        guard sort != "path" || descending else {
            return files
        }

        return files.sorted { lhs, rhs in
            let comparison: ComparisonResult
            switch sort {
            case "name":
                comparison =
                    lhs.url.lastPathComponent
                    .localizedStandardCompare(
                        rhs.url.lastPathComponent
                    )
            case "date":
                comparison = Self.compare(
                    modificationDate(for: lhs.url),
                    modificationDate(for: rhs.url)
                )
            case "size":
                comparison = Self.compare(
                    fileSize(for: lhs.url),
                    fileSize(for: rhs.url)
                )
            case "type":
                let leftType =
                    lhs.url.pathExtension.lowercased()
                let rightType =
                    rhs.url.pathExtension.lowercased()
                comparison =
                    leftType == rightType
                    ? lhs.relativePath
                        .localizedStandardCompare(
                            rhs.relativePath
                        )
                    : leftType
                        .localizedStandardCompare(
                            rightType
                        )
            default:
                comparison =
                    lhs.relativePath
                    .localizedStandardCompare(
                        rhs.relativePath
                    )
            }

            if comparison == .orderedSame {
                return lhs.originalIndex
                    < rhs.originalIndex
            }
            return descending
                ? comparison == .orderedDescending
                : comparison == .orderedAscending
        }
    }

    func selectedChapterIndex(
        in files: [OutputContentFile],
        query: [String: String]
    ) -> Int? {
        let groups = chapterGroups(in: files)
        guard groups.count > 1 else {
            return nil
        }

        if query["start"] == nil,
           query["end"] == nil,
           let range = chapterRange(
               in: files,
               query: query
           ),
           range.lowerBound == range.upperBound {
            return range.lowerBound
        }

        guard let startText =
                query["start"]?.trimmed,
              let endText =
                query["end"]?.trimmed,
              let rawStart = Int(startText),
              let rawEnd = Int(endText) else {
            return nil
        }
        let start = max(0, rawStart)
        let end = min(
            files.count - 1,
            max(0, rawEnd)
        )
        return groups.firstIndex { group in
            group.indexes.first == start &&
                group.indexes.last == end
        }
    }

    private func chapterRange(
        in files: [OutputContentFile],
        query: [String: String]
    ) -> ClosedRange<Int>? {
        let groups = chapterGroups(in: files)
        guard !groups.isEmpty else {
            return nil
        }

        if let chapter = Self.parameterValue(
            in: query,
            keys: ["chapter"]
        ),
        let index = chapterIndex(
            from: chapter,
            groups: groups
        ) {
            return index...index
        }

        guard let startToken = Self.parameterValue(
            in: query,
            keys: [
                "start_chapter",
                "chapter_start"
            ]
        ),
        let start = chapterIndex(
            from: startToken,
            groups: groups
        ) else {
            return nil
        }

        let endToken = Self.parameterValue(
            in: query,
            keys: [
                "end_chapter",
                "chapter_end"
            ]
        )
        let end = endToken.flatMap {
            chapterIndex(
                from: $0,
                groups: groups
            )
        } ?? start
        return min(start, end)...max(start, end)
    }

    private func chapterIndex(
        from token: String,
        groups: [OutputChapterGroup]
    ) -> Int? {
        let value = token.trimmed
        guard !value.isEmpty else {
            return nil
        }
        if let index = Int(value),
           groups.indices.contains(index) {
            return index
        }
        return groups.firstIndex {
            $0.title.compare(
                value,
                options: [
                    .caseInsensitive,
                    .diacriticInsensitive
                ]
            ) == .orderedSame ||
                $0.path.compare(
                    value,
                    options: [
                        .caseInsensitive,
                        .diacriticInsensitive
                    ]
                ) == .orderedSame
        }
    }

    private func modificationDate(
        for file: URL
    ) -> Date {
        (
            try? file.resourceValues(
                forKeys: [
                    .contentModificationDateKey
                ]
            ).contentModificationDate
        ) ?? .distantPast
    }

    private func fileSize(
        for file: URL
    ) -> Int64 {
        Int64(
            (
                try? file.resourceValues(
                    forKeys: [.fileSizeKey]
                ).fileSize
            ) ?? 0
        )
    }

    private static func compare(
        _ lhs: Date,
        _ rhs: Date
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func compare(
        _ lhs: Int64,
        _ rhs: Int64
    ) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }
        if lhs > rhs {
            return .orderedDescending
        }
        return .orderedSame
    }

    private static func parameterValue(
        in parameters: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value =
                    parameters[key]?.trimmed,
               !value.isEmpty {
                return value
            }
            let normalizedKey =
                normalizedParameterKey(key)
            if let pair = parameters.first(
                where: {
                    normalizedParameterKey($0.key)
                        == normalizedKey
                }
            ),
            !pair.value.trimmed.isEmpty {
                return pair.value.trimmed
            }
        }
        return nil
    }

    private static func normalizedParameterKey(
        _ key: String
    ) -> String {
        key.unicodeScalars
            .filter {
                CharacterSet.alphanumerics
                    .contains($0)
            }
            .map {
                String($0).lowercased()
            }
            .joined()
    }
}
