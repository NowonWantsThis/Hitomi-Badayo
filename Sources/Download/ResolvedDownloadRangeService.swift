import Foundation

struct ResolvedDownloadRangeService {
    static let nameTemplateIndexMetadataKey =
        "hitomi_native_template_index"

    func applying(
        _ expression: String,
        to resolved: ResolvedDownload
    ) throws -> ResolvedDownload {
        let range = expression.trimmed
        guard !range.isEmpty else { return resolved }
        guard case .files = resolved.packageMode else {
            throw NativeDownloadError.unsupported(
                "Range is only available for multi-file downloads."
            )
        }

        let indexes = try Self.assetIndexes(
            forRangeExpression: range,
            total: resolved.assets.count
        )
        let assets = indexes.map { index -> ResolvedAsset in
            var asset = resolved.assets[index]
            asset.metadata[
                Self.nameTemplateIndexMetadataKey
            ] = String(index + 1)
            return asset
        }
        guard !assets.isEmpty else {
            throw NativeDownloadError.unsupported(
                "Range did not match any files."
            )
        }

        var metadata = resolved.metadata
        metadata["range"] = range
        metadata["range_total"] = String(resolved.assets.count)
        metadata["range_selected"] = String(assets.count)
        metadata["range_indexes"] = Self.compactRangeDescription(
            fromZeroBasedIndexes: indexes
        )

        return ResolvedDownload(
            title: resolved.title,
            folderName: resolved.folderName,
            assets: assets,
            packageMode: resolved.packageMode,
            metadata: metadata,
            textMergePlan: resolved.textMergePlan,
            temporaryAssetDirectories:
                resolved.temporaryAssetDirectories
        )
    }

    static func isValidAssetRangeExpression(
        _ expression: String
    ) -> Bool {
        do {
            _ = try assetRangeSegments(from: expression)
            return true
        } catch {
            return false
        }
    }

    static func assetIndexes(
        forRangeExpression expression: String,
        total: Int
    ) throws -> [Int] {
        let segments = try assetRangeSegments(from: expression)
        guard !segments.isEmpty else {
            return Array(0..<max(0, total))
        }
        guard total > 0 else { return [] }

        var indexes: [Int] = []
        var seen = Set<Int>()
        for segment in segments {
            let rawStart = segment.start ?? 1
            let rawEnd = segment.end ?? total
            let start = max(1, rawStart)
            let end = min(total, rawEnd)
            guard start <= end else { continue }
            for page in start...end {
                let index = page - 1
                if seen.insert(index).inserted {
                    indexes.append(index)
                }
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported(
                "Range did not match any files."
            )
        }
        return indexes
    }

    static func finiteAssetRangeUpperBound(
        _ expression: String
    ) -> Int? {
        guard let segments = try? assetRangeSegments(
            from: expression
        ), !segments.isEmpty else {
            return nil
        }
        var upperBound = 0
        for segment in segments {
            guard let end = segment.end else { return nil }
            upperBound = max(upperBound, end)
        }
        return upperBound > 0 ? upperBound : nil
    }

    private struct AssetRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func assetRangeSegments(
        from expression: String
    ) throws -> [AssetRangeSegment] {
        let trimmed = expression.trimmed
        guard !trimmed.isEmpty else { return [] }
        let compact = trimmed
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
        let pieces = compact
            .components(
                separatedBy: CharacterSet(charactersIn: ",;")
            )
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }

        return try pieces.map { piece in
            if let split = rangeSplit(piece) {
                let start = try positiveRangeBound(split.0)
                let end = try positiveRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported(
                        "Invalid range."
                    )
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported(
                        "Invalid range."
                    )
                }
                return AssetRangeSegment(start: start, end: end)
            }

            guard let page = Int(piece), page > 0 else {
                throw NativeDownloadError.unsupported(
                    "Invalid range."
                )
            }
            return AssetRangeSegment(start: page, end: page)
        }
    }

    private static func rangeSplit(
        _ value: String
    ) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (
                    String(value[..<range.lowerBound]),
                    String(value[range.upperBound...])
                )
            }
        }
        return nil
    }

    private static func positiveRangeBound(
        _ value: String
    ) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    static func compactRangeDescription(
        fromZeroBasedIndexes indexes: [Int]
    ) -> String {
        guard !indexes.isEmpty else { return "" }
        var pieces: [String] = []
        var start = indexes[0] + 1
        var previous = start

        for index in indexes.dropFirst().map({ $0 + 1 }) {
            if index == previous + 1 {
                previous = index
                continue
            }
            pieces.append(
                start == previous
                    ? "\(start)"
                    : "\(start)-\(previous)"
            )
            start = index
            previous = index
        }
        pieces.append(
            start == previous
                ? "\(start)"
                : "\(start)-\(previous)"
        )
        return pieces.joined(separator: ",")
    }
}
