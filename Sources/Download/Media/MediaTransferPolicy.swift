import Foundation

enum MediaTransferPolicy {
    static func maximumConcurrency(
        defaultValue: Int,
        assets: [ResolvedAsset]
    ) -> Int {
        let override = assets.lazy.compactMap { asset in
            Int(asset.metadata["asset_concurrency_override"] ?? "")
        }.first { $0 > 0 }
        let cap = assets.lazy.compactMap { asset in
            Int(asset.metadata["asset_concurrency_cap"] ?? "")
        }.filter { $0 > 0 }.min() ?? 24
        return max(1, min(24, cap, override ?? defaultValue))
    }

    static func existingSkippableURL(
        _ asset: ResolvedAsset,
        in folder: URL,
        skipDuplicates: Bool,
        outputFilename: String? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        guard skipDuplicates,
              canSkipExistingOutput(asset) else {
            return nil
        }
        let filename = outputFilename ?? asset.filename
        if let existing = existingOutputFileURL(
            in: folder,
            filename: filename,
            fileManager: fileManager
        ) {
            return existing
        }

        let originalExtension = (asset.filename as NSString)
            .pathExtension.lowercased()
        let outputExtension = (filename as NSString)
            .pathExtension.lowercased()
        guard !originalExtension.isEmpty,
              outputExtension == originalExtension else {
            return nil
        }
        let base = (filename as NSString).deletingPathExtension
        var seen = Set<String>()
        for alternative in asset.alternativeRemoteURLs {
            let ext = alternative.pathExtension.lowercased()
            guard !ext.isEmpty,
                  ext != outputExtension,
                  ext.range(
                    of: #"^[a-z0-9]{1,8}$"#,
                    options: .regularExpression
                  ) != nil,
                  seen.insert(ext).inserted else {
                continue
            }
            if let existing = existingOutputFileURL(
                in: folder,
                filename: "\(base).\(ext)",
                fileManager: fileManager
            ) {
                return existing
            }
        }
        return nil
    }

    static func canSkipExistingOutput(_ asset: ResolvedAsset) -> Bool {
        guard asset.decryption == nil,
              asset.xorKey == nil,
              asset.pixivGridShuffle == nil,
              asset.lezhinImageShuffle == nil,
              asset.pythonSegmentDecorator == nil,
              !usesM3U8RateLimit(asset) else {
            return false
        }
        return true
    }

    static func usesM3U8RateLimit(_ asset: ResolvedAsset) -> Bool {
        let type = (asset.metadata["type"] ?? "").lowercased()
        let mediaType = (asset.metadata["media_type"] ?? "")
            .lowercased()
        return type == "hls_segment" || type == "hls_map" ||
            mediaType == "hls_segment" || mediaType == "hls_map"
    }

    static func canContinueAfterHLSFailure(
        _ asset: ResolvedAsset
    ) -> Bool {
        let type = (asset.metadata["type"] ?? "").lowercased()
        let mediaType = (asset.metadata["media_type"] ?? "")
            .lowercased()
        return type == "hls_segment" || mediaType == "hls_segment"
    }

    static func canDeferGalleryFailure(_ asset: ResolvedAsset) -> Bool {
        asset.metadata["continue_asset_failures"] == "true"
    }

    static func shouldSpaceOriginalModificationDates(
        sourceURL: URL,
        metadata: [String: String],
        assetMetadata: [[String: String]] = []
    ) -> Bool {
        if isOriginalModificationDateSpacingHost(
            sourceURL.host?.lowercased() ?? ""
        ) {
            return true
        }

        let siteCandidates = [metadata] + assetMetadata
        return siteCandidates.contains { values in
            let site = metadataValue(
                values,
                keys: ["site", "handler", "extractor", "script"]
            ).lowercased()
            return isOriginalModificationDateSpacingSite(site)
        }
    }

    static func originalModificationDate(
        baseDate: Date,
        index: Int
    ) -> Date {
        baseDate.addingTimeInterval(TimeInterval(max(0, index)))
    }

    static func applyOriginalModificationDateSpacing(
        to url: URL,
        baseDate: Date,
        index: Int,
        fileManager: FileManager = .default
    ) throws {
        let date = originalModificationDate(
            baseDate: baseDate,
            index: index
        )
        try fileManager.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    static func originalModificationDate(
        for asset: ResolvedAsset
    ) -> Date? {
        for key in [
            "original_modification_time",
            "original_modification_timestamp"
        ] {
            guard let raw = asset.metadata[key]?.trimmed,
                  let seconds = TimeInterval(raw),
                  seconds > 0 else {
                continue
            }
            return Date(
                timeIntervalSince1970:
                    seconds > 10_000_000_000 ? seconds / 1_000 : seconds
            )
        }
        return nil
    }

    static func applyModificationDate(
        _ date: Date,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try fileManager.setAttributes(
            [.modificationDate: date],
            ofItemAtPath: url.path
        )
    }

    private static func existingOutputFileURL(
        in directory: URL,
        filename: String,
        fileManager: FileManager
    ) -> URL? {
        let candidate = AppPaths.fileURL(
            in: directory,
            filename: filename
        )
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: candidate.path,
            isDirectory: &isDirectory
        ), !isDirectory.boolValue else {
            return nil
        }
        return candidate
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

    private static func isOriginalModificationDateSpacingHost(
        _ host: String
    ) -> Bool {
        host == "hitomi.la" ||
            host.hasSuffix(".hitomi.la") ||
            host == "e-hentai.org" ||
            host == "www.e-hentai.org" ||
            host == "exhentai.org" ||
            host == "www.exhentai.org" ||
            host == "e-hentai.test" ||
            host.hasSuffix(".e-hentai.test") ||
            host == "exhentai.test" ||
            host.hasSuffix(".exhentai.test")
    }

    private static func isOriginalModificationDateSpacingSite(
        _ site: String
    ) -> Bool {
        let normalized = site
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: ".", with: "")
        return normalized == "hitomi" ||
            normalized == "hitomila" ||
            normalized == "ehentai" ||
            normalized == "exhentai"
    }
}
