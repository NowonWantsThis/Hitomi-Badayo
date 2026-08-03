import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

private struct DuplicateImageCandidate {
    var url: URL
    var sourceKey: String
    var byteCount: Int64
    var width: Int?
    var height: Int?
    var visualHash: UInt64?
}

final class DuplicateImageScanService:
    @unchecked Sendable
{
    func groups(
        in root: URL,
        similarityPercent: Int = 100,
        excludeSameSource: Bool = false
    ) throws -> [DuplicateImageGroup] {
        try groups(
            in: [root],
            similarityPercent: similarityPercent,
            excludeSameSource: excludeSameSource
        )
    }

    func groups(
        in roots: [URL],
        similarityPercent: Int = 100,
        excludeSameSource: Bool = false
    ) throws -> [DuplicateImageGroup] {
        let scanRoots =
            normalizedFolderPaths(
                roots.map(\.path)
            )
            .map {
                URL(
                    fileURLWithPath: $0,
                    isDirectory: true
                )
            }
        guard !scanRoots.isEmpty else {
            throw NativeDownloadError.unsupported(
                "Output folder is unavailable."
            )
        }

        for root in scanRoots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(
                atPath: root.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue else {
                throw NativeDownloadError.unsupported(
                    "Scan folder is unavailable: \(root.path)"
                )
            }
        }

        let normalizedSimilarity =
            normalizedSimilarityPercent(
                similarityPercent
            )
        let candidates = try scanRoots.flatMap {
            try candidates(
                in: $0,
                includeVisualHash:
                    normalizedSimilarity < 100
            )
        }
        var groups =
            try exactGroups(from: candidates)
        if normalizedSimilarity < 100 {
            let existingKeys =
                Set(
                    groups.map {
                        fileKey($0.files)
                    }
                )
            groups.append(
                contentsOf:
                    visualGroups(
                        from: candidates,
                        similarityPercent:
                            normalizedSimilarity,
                        existingFileKeys:
                            existingKeys
                    )
            )
        }
        if excludeSameSource {
            let sourceKeys =
                Dictionary(
                    uniqueKeysWithValues:
                        candidates.map {
                            (
                                $0.url.path,
                                $0.sourceKey
                            )
                        }
                )
            groups =
                groups.compactMap {
                    groupExcludingSameSource(
                        $0,
                        sourceKeysByPath:
                            sourceKeys
                    )
                }
        }

        return groups.sorted {
            if $0.files.count != $1.files.count {
                return $0.files.count >
                    $1.files.count
            }
            if ($0.similarityPercent ?? 100) !=
                ($1.similarityPercent ?? 100) {
                return
                    ($0.similarityPercent ?? 100) >
                    ($1.similarityPercent ?? 100)
            }
            return
                ($0.files.first ?? "")
                .localizedStandardCompare(
                    $1.files.first ?? ""
                ) == .orderedAscending
        }
    }

    func folderURL(
        forPath path: String,
        fileManager: FileManager = .default
    ) -> URL? {
        let value = path.trimmed
        guard !value.isEmpty else {
            return nil
        }

        let url = URL(fileURLWithPath: value)
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(
            atPath: url.path,
            isDirectory: &isDirectory
        ) {
            return isDirectory.boolValue
                ? url
                : url.deletingLastPathComponent()
        }

        let parent =
            url.deletingLastPathComponent()
        guard parent.path != url.path else {
            return nil
        }
        var parentIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: parent.path,
            isDirectory: &parentIsDirectory
        ),
        parentIsDirectory.boolValue else {
            return nil
        }
        return parent
    }

    func selection(
        current: String,
        groups: [DuplicateImageGroup],
        minimumSimilarityPercent: Int
    ) -> (
        selectedPath: String,
        autoSelectedPath: String
    ) {
        let currentSelection =
            validSelection(
                current: current,
                groups: groups
            )
        let autoSelection =
            autoSelectionCandidate(
                in: groups,
                minimumSimilarityPercent:
                    minimumSimilarityPercent
            ) ?? ""
        if !currentSelection.isEmpty {
            return (
                currentSelection,
                autoSelection
            )
        }
        if !autoSelection.isEmpty {
            return (
                autoSelection,
                autoSelection
            )
        }
        return (
            groups.flatMap(\.files).first ?? "",
            ""
        )
    }

    func autoSelectionCandidate(
        in groups: [DuplicateImageGroup],
        minimumSimilarityPercent: Int,
        fileManager: FileManager = .default
    ) -> String? {
        let threshold =
            normalizedSimilarityPercent(
                minimumSimilarityPercent
            )
        for group in groups
            where similarityPercent(for: group) >=
                threshold {
            if let path =
                autoSelectionCandidate(
                    in: group,
                    fileManager: fileManager
                ) {
                return path
            }
        }
        return nil
    }

    func summary(
        for groups: [DuplicateImageGroup],
        autoSelectedPath: String = ""
    ) -> String {
        guard !groups.isEmpty else {
            return "No duplicate images found"
        }
        let duplicateFileCount =
            groups.reduce(0) {
                $0 + max(0, $1.files.count - 1)
            }
        let base =
            "\(groups.count) duplicate groups, \(duplicateFileCount) extra files"
        let autoSelectedName =
            URL(
                fileURLWithPath:
                    autoSelectedPath
            ).lastPathComponent
        if !autoSelectedName.isEmpty {
            return
                "\(base). Auto-selected \(autoSelectedName)"
        }
        return base
    }

    func normalizedSimilarityPercent(
        _ percent: Int
    ) -> Int {
        min(100, max(80, percent))
    }

    func normalizedFolderPaths(
        _ paths: [String]
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for path in paths {
            let value = path.trimmed
            guard !value.isEmpty else {
                continue
            }
            let normalized =
                URL(
                    fileURLWithPath: value,
                    isDirectory: true
                )
                .standardizedFileURL.path
            guard seen.insert(normalized)
                .inserted else {
                continue
            }
            output.append(normalized)
        }
        return output
    }

    private func validSelection(
        current: String,
        groups: [DuplicateImageGroup]
    ) -> String {
        let value = current.trimmed
        guard !value.isEmpty else {
            return ""
        }
        let files = groups.flatMap(\.files)
        return files.contains(value) ? value : ""
    }

    private func autoSelectionCandidate(
        in group: DuplicateImageGroup,
        fileManager: FileManager
    ) -> String? {
        group.files.enumerated().max {
            lhs,
            rhs in
            let lhsDate = modificationDate(
                forPath: lhs.element,
                fileManager: fileManager
            )
            let rhsDate = modificationDate(
                forPath: rhs.element,
                fileManager: fileManager
            )
            if lhsDate != rhsDate {
                return lhsDate < rhsDate
            }
            return lhs.offset < rhs.offset
        }?.element
    }

    private func modificationDate(
        forPath path: String,
        fileManager: FileManager
    ) -> Date {
        let attributes =
            try? fileManager.attributesOfItem(
                atPath: path
            )
        return
            (attributes?[.modificationDate]
                as? Date) ?? .distantPast
    }

    private func similarityPercent(
        for group: DuplicateImageGroup
    ) -> Int {
        min(
            100,
            max(
                0,
                group.similarityPercent ?? 100
            )
        )
    }

    private func exactGroups(
        from candidates: [DuplicateImageCandidate]
    ) throws -> [DuplicateImageGroup] {
        let sameSizeCandidates =
            Dictionary(
                grouping: candidates,
                by: \.byteCount
            )
            .values
            .filter { $0.count > 1 }

        var byHash:
            [String: [DuplicateImageCandidate]] =
                [:]
        for group in sameSizeCandidates {
            for candidate in group {
                let hash =
                    try sha256Hex(
                        for: candidate.url
                    )
                byHash[hash, default: []]
                    .append(candidate)
            }
        }

        return byHash.compactMap {
            hash,
            candidates in
            guard candidates.count > 1 else {
                return nil
            }
            let files =
                candidates
                .map(\.url.path)
                .sorted {
                    $0.localizedStandardCompare(
                        $1
                    ) == .orderedAscending
                }
            let dimensions =
                firstDimensions(in: candidates)
            return DuplicateImageGroup(
                hash: hash,
                byteCount:
                    candidates.first?.byteCount ??
                    0,
                files: files,
                width: dimensions?.width,
                height: dimensions?.height,
                minByteCount:
                    candidates.first?.byteCount,
                maxByteCount:
                    candidates.first?.byteCount,
                similarityPercent: 100
            )
        }
    }

    private func firstDimensions(
        in candidates: [DuplicateImageCandidate]
    ) -> (width: Int, height: Int)? {
        if let dimensions =
            candidates.compactMap({
                candidate
                    -> (
                        width: Int,
                        height: Int
                    )? in
                guard let width = candidate.width,
                      let height =
                        candidate.height else {
                    return nil
                }
                return (width, height)
            }).first {
            return dimensions
        }

        for candidate in candidates {
            if let dimensions =
                imageDimensions(
                    for: candidate.url
                ) {
                return dimensions
            }
        }
        return nil
    }

    private func visualGroups(
        from candidates: [DuplicateImageCandidate],
        similarityPercent: Int,
        existingFileKeys: Set<String>
    ) -> [DuplicateImageGroup] {
        let maxDistance =
            maxHashDistance(
                for: similarityPercent
            )
        guard maxDistance > 0 else {
            return []
        }
        let visualCandidates =
            candidates
            .filter { $0.visualHash != nil }
            .sorted {
                $0.url.path
                    .localizedStandardCompare(
                        $1.url.path
                    ) == .orderedAscending
            }

        var groups: [DuplicateImageGroup] = []
        var usedPaths = Set<String>()
        for seed in visualCandidates {
            let seedPath = seed.url.path
            guard !usedPaths.contains(seedPath),
                  let seedHash =
                    seed.visualHash else {
                continue
            }

            let matches =
                visualCandidates.compactMap {
                    candidate
                        -> (
                            candidate:
                                DuplicateImageCandidate,
                            distance: Int
                        )? in
                    let path = candidate.url.path
                    guard
                        !usedPaths.contains(path),
                        let candidateHash =
                            candidate.visualHash
                    else {
                        return nil
                    }
                    let distance =
                        hammingDistance(
                            seedHash,
                            candidateHash
                        )
                    guard distance <= maxDistance
                    else {
                        return nil
                    }
                    return (
                        candidate,
                        distance
                    )
                }
            guard matches.count > 1 else {
                continue
            }

            let files =
                matches
                .map(\.candidate.url.path)
                .sorted {
                    $0.localizedStandardCompare(
                        $1
                    ) == .orderedAscending
                }
            let candidateFileKey =
                fileKey(files)
            guard !existingFileKeys
                .contains(candidateFileKey) else {
                continue
            }

            files.forEach {
                usedPaths.insert($0)
            }
            let byteCounts =
                matches.map(
                    \.candidate.byteCount
                )
            let minByteCount =
                byteCounts.min() ?? 0
            let maxByteCount =
                byteCounts.max() ??
                minByteCount
            let representative =
                matches.first(where: {
                    $0.candidate.width != nil &&
                        $0.candidate.height != nil
                })?.candidate ?? seed
            let worstDistance =
                matches.map(\.distance).max() ??
                0
            let groupSimilarity =
                visualHashSimilarityPercent(
                    distance: worstDistance
                )
            groups.append(
                DuplicateImageGroup(
                    hash:
                        "visual-\(String(format: "%016llx", seedHash))",
                    byteCount: minByteCount,
                    files: files,
                    width: representative.width,
                    height: representative.height,
                    minByteCount: minByteCount,
                    maxByteCount: maxByteCount,
                    similarityPercent:
                        groupSimilarity
                )
            )
        }
        return groups
    }

    private func candidates(
        in root: URL,
        includeVisualHash: Bool = false
    ) throws -> [DuplicateImageCandidate] {
        guard let enumerator =
            FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [
                    .isRegularFileKey,
                    .fileSizeKey
                ],
                options: [
                    .skipsHiddenFiles,
                    .skipsPackageDescendants
                ]
            ) else {
            return []
        }

        var candidates:
            [DuplicateImageCandidate] = []
        for case let url as URL in enumerator {
            guard imageExtensions.contains(
                url.pathExtension.lowercased()
            ) else {
                continue
            }
            let values =
                try url.resourceValues(
                    forKeys: [
                        .isRegularFileKey,
                        .fileSizeKey
                    ]
                )
            guard values.isRegularFile == true,
                  let byteCount = values.fileSize,
                  byteCount > 0 else {
                continue
            }
            let dimensions =
                includeVisualHash
                ? imageDimensions(for: url)
                : nil
            candidates.append(
                DuplicateImageCandidate(
                    url: url,
                    sourceKey:
                        sourceKey(
                            forPath: url.path,
                            root: root
                        ),
                    byteCount:
                        Int64(byteCount),
                    width: dimensions?.width,
                    height: dimensions?.height,
                    visualHash:
                        includeVisualHash
                        ? visualImageHash(
                            for: url
                        )
                        : nil
                )
            )
        }
        return candidates
    }

    private func maxHashDistance(
        for similarityPercent: Int
    ) -> Int {
        let normalized =
            normalizedSimilarityPercent(
                similarityPercent
            )
        guard normalized < 100 else {
            return 0
        }
        return min(
            64,
            max(
                1,
                Int(
                    ceil(
                        Double(100 - normalized) *
                            64.0 / 100.0
                    )
                )
            )
        )
    }

    private func visualHashSimilarityPercent(
        distance: Int
    ) -> Int {
        let clampedDistance =
            min(64, max(0, distance))
        return min(
            100,
            max(
                0,
                (
                    (64 - clampedDistance) *
                        100 + 32
                ) / 64
            )
        )
    }

    private func hammingDistance(
        _ lhs: UInt64,
        _ rhs: UInt64
    ) -> Int {
        (lhs ^ rhs).nonzeroBitCount
    }

    private func fileKey(
        _ files: [String]
    ) -> String {
        files
            .sorted {
                $0.localizedStandardCompare($1) ==
                    .orderedAscending
            }
            .joined(separator: "\u{0}")
    }

    private func groupExcludingSameSource(
        _ group: DuplicateImageGroup,
        sourceKeysByPath: [String: String]
    ) -> DuplicateImageGroup? {
        var seenSources = Set<String>()
        let files =
            group.files
            .sorted {
                $0.localizedStandardCompare($1) ==
                    .orderedAscending
            }
            .filter { path in
                let key =
                    sourceKeysByPath[path] ??
                    URL(
                        fileURLWithPath: path
                    )
                    .deletingLastPathComponent()
                    .path
                return seenSources.insert(key)
                    .inserted
            }
        guard files.count > 1 else {
            return nil
        }

        var pruned = group
        pruned.files = files
        return pruned
    }

    private func sourceKey(
        forPath path: String,
        root: URL
    ) -> String {
        let fileURL =
            URL(fileURLWithPath: path)
            .standardizedFileURL
        let parent =
            fileURL.deletingLastPathComponent()
            .standardizedFileURL
        let rootURL =
            root.standardizedFileURL
        let rootPath = rootURL.path
        let parentPath = parent.path
        if parentPath.hasPrefix(rootPath) {
            let relative =
                String(
                    parentPath.dropFirst(
                        rootPath.count
                    )
                )
                .trimmingCharacters(
                    in:
                        CharacterSet(
                            charactersIn: "/"
                        )
                )
            return
                "\(rootPath)\u{0}\(relative.isEmpty ? "." : relative)"
        }
        return parentPath
    }

    private func imageDimensions(
        for url: URL
    ) -> (width: Int, height: Int)? {
        guard
            let source =
                CGImageSourceCreateWithURL(
                    url as CFURL,
                    nil
                ),
            let properties =
                CGImageSourceCopyPropertiesAtIndex(
                    source,
                    0,
                    nil
                ) as? [CFString: Any],
            let width =
                properties[
                    kCGImagePropertyPixelWidth
                ] as? NSNumber,
            let height =
                properties[
                    kCGImagePropertyPixelHeight
                ] as? NSNumber,
            width.intValue > 0,
            height.intValue > 0
        else {
            return nil
        }
        return (
            width.intValue,
            height.intValue
        )
    }

    private func visualImageHash(
        for url: URL
    ) -> UInt64? {
        guard
            let source =
                CGImageSourceCreateWithURL(
                    url as CFURL,
                    nil
                ),
            let image =
                CGImageSourceCreateImageAtIndex(
                    source,
                    0,
                    nil
                )
        else {
            return nil
        }

        let sampleWidth = 8
        let sampleHeight = 8
        var pixels =
            [UInt8](
                repeating: 0,
                count:
                    sampleWidth *
                    sampleHeight * 4
            )
        return pixels.withUnsafeMutableBytes {
            buffer -> UInt64? in
            guard
                let baseAddress =
                    buffer.baseAddress,
                let context = CGContext(
                    data: baseAddress,
                    width: sampleWidth,
                    height: sampleHeight,
                    bitsPerComponent: 8,
                    bytesPerRow:
                        sampleWidth * 4,
                    space:
                        CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo:
                        CGImageAlphaInfo
                        .premultipliedLast
                        .rawValue |
                        CGBitmapInfo
                        .byteOrder32Big
                        .rawValue
                )
            else {
                return nil
            }
            context.interpolationQuality = .high
            context.draw(
                image,
                in: CGRect(
                    x: 0,
                    y: 0,
                    width: sampleWidth,
                    height: sampleHeight
                )
            )

            let bytes =
                buffer.bindMemory(to: UInt8.self)
            var luminanceValues: [Int] = []
            luminanceValues.reserveCapacity(
                sampleWidth * sampleHeight
            )
            for index in stride(
                from: 0,
                to: bytes.count,
                by: 4
            ) {
                let red = Int(bytes[index])
                let green =
                    Int(bytes[index + 1])
                let blue =
                    Int(bytes[index + 2])
                luminanceValues.append(
                    (
                        red * 299 +
                        green * 587 +
                        blue * 114
                    ) / 1_000
                )
            }

            guard !luminanceValues.isEmpty
            else {
                return nil
            }
            let average =
                luminanceValues.reduce(0, +) /
                luminanceValues.count
            var hash: UInt64 = 0
            for (
                index,
                value
            ) in luminanceValues.enumerated()
                where value >= average {
                hash |=
                    UInt64(1) <<
                    UInt64(index)
            }
            return hash
        }
    }

    private func sha256Hex(
        for url: URL
    ) throws -> String {
        let handle =
            try FileHandle(
                forReadingFrom: url
            )
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while true {
            let chunk =
                try handle.read(
                    upToCount: 1_048_576
                ) ?? Data()
            if chunk.isEmpty {
                break
            }
            hasher.update(data: chunk)
        }
        return hasher.finalize()
            .map {
                String(format: "%02x", $0)
            }
            .joined()
    }

    private let imageExtensions: Set<String> = [
        "avif",
        "bmp",
        "gif",
        "heic",
        "heif",
        "jpeg",
        "jpg",
        "png",
        "tif",
        "tiff",
        "webp"
    ]
}
