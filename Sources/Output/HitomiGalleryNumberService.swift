import Foundation

struct HitomiGalleryNumberService: Sendable {
    private static let archiveExtensions =
        Set(["zip", "cbz", "rar", "7z"])
    private static let galleryInfoFilenames =
        Set([
            "gallery-info.txt",
            "hitomi_gallery_info.txt",
            "hitomi-gallery-info.txt"
        ])

    func numbers(
        in root: URL,
        fileManager: FileManager = .default
    ) -> [String] {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            return []
        }

        var numbers = Set<String>()
        if isDirectory.boolValue {
            numbers.formUnion(
                self.numbers(
                    fromOutputName:
                        root.lastPathComponent
                )
            )

            let resourceKeys: [URLResourceKey] = [
                .isDirectoryKey,
                .isRegularFileKey
            ]
            guard let enumerator =
                fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys:
                        resourceKeys,
                    options: [
                        .skipsHiddenFiles,
                        .skipsPackageDescendants
                    ],
                    errorHandler: { _, _ in true }
                ) else {
                return sorted(numbers)
            }

            for case let url as URL in enumerator {
                guard let values =
                    try? url.resourceValues(
                        forKeys: Set(resourceKeys)
                    ) else {
                    continue
                }
                if values.isDirectory == true {
                    numbers.formUnion(
                        self.numbers(
                            fromOutputName:
                                url.lastPathComponent
                        )
                    )
                } else if values.isRegularFile == true {
                    numbers.formUnion(
                        self.numbers(
                            fromOutputFile: url
                        )
                    )
                }
            }
        } else {
            numbers.formUnion(
                self.numbers(fromOutputFile: root)
            )
        }

        return sorted(numbers)
    }

    func numbers(
        fromOutputName name: String
    ) -> [String] {
        let decoded =
            name.removingPercentEncoding ?? name
        let normalized =
            decoded.replacingOccurrences(
                of: "\\",
                with: "/"
            )
        var numbers = Set<String>()
        numbers.formUnion(
            self.numbers(
                fromHitomiText: normalized,
                rejectsDates: false
            )
        )

        let outputNamePatterns = [
            #"(?i)(?:hitomi|gallery|gal|gid|id|no|num|number|번호|번)\s*[:#._ \-]*([1-9][0-9]{3,})\b"#,
            #"(?i)(?:^|[\[(])\s*([1-9][0-9]{3,})\s*(?:[\])]|$)"#,
            #"(?i)(?:^|[\s._\-\[\(])([1-9][0-9]{4,})\s*(?:[\]\)]|$)"#
        ]

        for pattern in outputNamePatterns {
            numbers.formUnion(
                capturedNumbers(
                    in: normalized,
                    pattern: pattern,
                    rejectsDates: true
                )
            )
        }
        return sorted(numbers)
    }

    func numbers(
        fromOutputFile url: URL
    ) -> [String] {
        let lowerName =
            url.lastPathComponent.lowercased()
        if Self.galleryInfoFilenames
            .contains(lowerName),
           let text = try? String(
               contentsOf: url,
               encoding: .utf8
           ) {
            return numbers(
                fromHitomiText: text,
                rejectsDates: false
            )
        }

        if Self.archiveExtensions.contains(
            url.pathExtension.lowercased()
        ) {
            let baseName =
                (url.lastPathComponent as NSString)
                .deletingPathExtension
            return numbers(
                fromOutputName: baseName
            )
        }

        return []
    }

    static func isGalleryInfoFilename(
        _ filename: String
    ) -> Bool {
        galleryInfoFilenames.contains(
            filename.lowercased()
        )
    }

    private func numbers(
        fromHitomiText text: String,
        rejectsDates: Bool
    ) -> [String] {
        let normalized =
            text.replacingOccurrences(
                of: "\\",
                with: "/"
            )
        let patterns = [
            #"(?im)^\s*Gallery\s+ID\s*:\s*([0-9]+)\b"#,
            #"(?im)^\s*gallery[_\s-]*id\s*[:=]\s*([0-9]+)\b"#,
            #"hitomi\.la/(?:reader|galleries|g|lofi|mpv)/([0-9]+)(?:\.html)?\b"#,
            #"hitomi\.la/[^ \t\r\n<>"']*-([0-9]+)\.html\b"#,
            #"galleryblock/([0-9]+)"#,
            #"#-\*-[^#\r\n]*\(([0-9]+)\)"#
        ]

        var numbers = Set<String>()
        for pattern in patterns {
            numbers.formUnion(
                capturedNumbers(
                    in: normalized,
                    pattern: pattern,
                    rejectsDates: rejectsDates
                )
            )
        }
        return sorted(numbers)
    }

    private func capturedNumbers(
        in text: String,
        pattern: String,
        rejectsDates: Bool
    ) -> [String] {
        guard let regex =
            try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            ) else {
            return []
        }
        let range = NSRange(
            text.startIndex..<text.endIndex,
            in: text
        )
        return regex.matches(
            in: text,
            range: range
        ).compactMap { match in
            guard match.numberOfRanges > 1,
                  let captureRange =
                      Range(
                          match.range(at: 1),
                          in: text
                      ) else {
                return nil
            }
            return normalizedNumber(
                String(text[captureRange]),
                rejectsDates: rejectsDates
            )
        }
    }

    private func normalizedNumber(
        _ value: String,
        rejectsDates: Bool
    ) -> String? {
        let trimmed = value.trimmed
        guard trimmed.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        if rejectsDates,
           isLikelyCompactDate(trimmed) {
            return nil
        }
        let normalized =
            trimmed.drop { $0 == "0" }
        return normalized.isEmpty
            ? nil
            : String(normalized)
    }

    private func isLikelyCompactDate(
        _ value: String
    ) -> Bool {
        guard value.count == 8,
              let year = Int(value.prefix(4)),
              let month =
                  Int(
                      value.dropFirst(4).prefix(2)
                  ),
              let day = Int(value.suffix(2))
        else {
            return false
        }
        return (1900...2100).contains(year) &&
            (1...12).contains(month) &&
            (1...31).contains(day)
    }

    private func sorted(
        _ numbers: Set<String>
    ) -> [String] {
        numbers.sorted { left, right in
            if let leftValue = Int64(left),
               let rightValue = Int64(right),
               leftValue != rightValue {
                return leftValue < rightValue
            }
            if left.count != right.count {
                return left.count < right.count
            }
            return left < right
        }
    }
}
