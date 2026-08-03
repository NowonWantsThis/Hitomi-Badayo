import Foundation

struct OutputNamingService {
    func folderName(
        for resolved: ResolvedDownload,
        sourceURL: URL,
        template rawTemplate: String
    ) -> String {
        if resolved.metadata["preserve_resolved_folder_path"] == "true" {
            return resolved.folderName.sanitizedRelativePath(
                maxComponentLength: 120
            )
        }
        let template = rawTemplate.trimmed
        guard !template.isEmpty else {
            return resolved.folderName.sanitizedRelativePath(
                maxComponentLength: 120
            )
        }
        let context = nameTemplateContext(
            title: resolved.title,
            sourceURL: sourceURL,
            filename: resolved.folderName,
            index: nil,
            total: resolved.assets.count,
            metadata: resolved.metadata
        )
        return NameTemplate.folderName(
            template: template,
            fallback: resolved.folderName,
            context: context
        )
    }

    func assets(
        _ assets: [ResolvedAsset],
        title: String,
        sourceURL: URL,
        metadata: [String: String],
        fileNameTemplate: String
    ) -> [ResolvedAsset] {
        let template = fileNameTemplate.trimmed
        guard !template.isEmpty else { return assets }
        let total = assets.count
        return assets.enumerated().map { offset, asset in
            var copy = asset
            let assetMetadata = Self.mergedNameTemplateMetadata(
                metadata,
                assetMetadata: asset.metadata
            )
            let preservesRelativePath =
                asset.metadata["preserve_relative_path"] == "true"
            let safeRelativePath = asset.filename.sanitizedRelativePath(
                maxComponentLength: 120
            )
            let relativeDirectory = preservesRelativePath
                ? (safeRelativePath as NSString).deletingLastPathComponent
                : ""
            let originalName = preservesRelativePath
                ? (safeRelativePath as NSString).lastPathComponent
                : asset.filename
            let outputName = fileName(
                original: originalName,
                title: title,
                sourceURL: sourceURL,
                index: Self.nameTemplateIndex(
                    for: asset,
                    fallback: offset + 1
                ),
                total: total,
                metadata: assetMetadata,
                template: template
            )
            copy.filename = preservesRelativePath &&
                relativeDirectory != "." &&
                !relativeDirectory.isEmpty
                ? "\(relativeDirectory)/\(outputName)"
                    .sanitizedRelativePath(maxComponentLength: 120)
                : outputName
            return copy
        }
    }

    func concatenatedFileName(
        original: String,
        title: String,
        sourceURL: URL,
        total: Int?,
        metadata: [String: String],
        packageMode: DownloadPackageMode,
        fileNameTemplate: String,
        recordingFileNameTemplate: String
    ) -> String {
        let recordingTemplate = recordingFileNameTemplate.trimmed
        let templateOverride = Self.shouldUseRecordingFileNameTemplate(
            packageMode: packageMode,
            metadata: metadata
        ) && !recordingTemplate.isEmpty
            ? recordingTemplate
            : nil
        return fileName(
            original: original,
            title: title,
            sourceURL: sourceURL,
            index: nil,
            total: total,
            metadata: metadata,
            template: fileNameTemplate,
            templateOverride: templateOverride
        )
    }

    func fileName(
        original: String,
        title: String,
        sourceURL: URL,
        index: Int?,
        total: Int?,
        metadata: [String: String] = [:],
        template rawTemplate: String,
        templateOverride: String? = nil
    ) -> String {
        let override = templateOverride?.trimmed ?? ""
        let template = override.isEmpty ? rawTemplate.trimmed : override
        guard !template.isEmpty else {
            return original.sanitizedFilename(maxLength: 180)
        }
        let context = nameTemplateContext(
            title: title,
            sourceURL: sourceURL,
            filename: original,
            index: index,
            total: total,
            metadata: metadata
        )
        return NameTemplate.fileName(
            template: template,
            fallback: original,
            context: context
        )
    }

    func nameTemplateContext(
        title: String,
        sourceURL: URL,
        filename: String,
        index: Int?,
        total: Int?,
        metadata: [String: String] = [:]
    ) -> NameTemplateContext {
        let safeFilename = filename.sanitizedFilename(maxLength: 180)
        let basename = (safeFilename as NSString).deletingPathExtension
        let ext = (safeFilename as NSString).pathExtension
        let metadataSite = metadata["site"]?.trimmed ?? ""
        let metadataHost = metadata["host"]?.trimmed ?? ""
        return NameTemplateContext(
            title: title,
            site: metadataSite.isEmpty
                ? siteFolderName(for: sourceURL)
                : metadataSite,
            host: metadataHost.isEmpty
                ? sourceHostToken(for: sourceURL)
                : metadataHost,
            date: Self.templateDate(from: metadata) ?? Self.dateFolderName(),
            id: Self.templateIdentifier(from: metadata)
                ?? sourceIdentifier(for: sourceURL),
            url: sourceURL.absoluteString,
            path: sourcePathToken(for: sourceURL),
            slug: sourceSlugToken(for: sourceURL),
            query: sourceQueryToken(for: sourceURL),
            filename: safeFilename,
            basename: basename,
            ext: ext,
            index: index,
            total: total,
            metadata: metadata
        )
    }

    static func nameTemplateIndex(
        for asset: ResolvedAsset,
        fallback: Int
    ) -> Int {
        guard let rawValue = asset.metadata[
            ResolvedDownloadRangeService.nameTemplateIndexMetadataKey
        ]?.trimmed,
        let value = Int(rawValue),
        value > 0 else {
            return fallback
        }
        return value
    }

    static func mergedNameTemplateMetadata(
        _ metadata: [String: String],
        assetMetadata: [String: String]
    ) -> [String: String] {
        DownloadMetadata.clean(
            metadata.merging(assetMetadata) { _, assetValue in assetValue }
        )
    }

    static func shouldUseRecordingFileNameTemplate(
        packageMode: DownloadPackageMode,
        metadata: [String: String]
    ) -> Bool {
        switch packageMode {
        case .concatenate, .grouped:
            break
        case .files, .mux, .groupedMedia:
            return false
        }
        let cleaned = DownloadMetadata.clean(metadata)
        let fields = [
            cleaned["type"],
            cleaned["media_type"],
            cleaned["format"],
            cleaned["media_format"],
            cleaned["protocol"],
            cleaned["category"],
            cleaned["live"],
            cleaned["live_status"],
            cleaned["was_live"],
            cleaned["record"],
            cleaned["recording"]
        ].compactMap { $0?.lowercased() }

        if fields.contains(where: { field in
            field == "hls" ||
                field == "m3u8" ||
                field == "live" ||
                field == "record" ||
                field == "recording" ||
                field == "is_live" ||
                field == "was_live" ||
                field.contains("livestream") ||
                field.contains("live stream")
        }) {
            return true
        }

        return ["playlist_url", "media_url", "source_url", "page_url"]
            .compactMap { cleaned[$0]?.lowercased() }
            .contains { $0.contains(".m3u8") }
    }

    static func templateDate(from metadata: [String: String]) -> String? {
        let dateKeys = [
            "date", "upload_date", "uploadDate",
            "published_date", "published", "published_at", "publishedAt",
            "published_time", "publishedTime", "datePublished",
            "date_published", "publishDate", "publish_date", "pubdate",
            "datepublished", "article:published_time",
            "article:modified_time", "posted", "posted_at", "postedAt",
            "created", "created_at", "createdAt", "created_time",
            "createdTime", "createdDate", "uploaded", "uploaded_at",
            "uploadedAt", "registered", "registered_at", "registeredAt",
            "firstRetrieve", "first_retrieve", "release_date", "reg_date",
            "broad_start", "write_tm", "openDate", "taken_at_timestamp",
            "taken_at", "device_timestamp", "imported_taken_at", "timestamp"
        ]
        for key in dateKeys {
            guard let value = templateMetadataValue(metadata, key: key) else {
                continue
            }
            if let date = normalizedTemplateDate(value) {
                return date
            }
        }
        return nil
    }

    static func templateIdentifier(
        from metadata: [String: String]
    ) -> String? {
        let keys = [
            "id", "post_id", "postID", "gallery_id", "galleryID",
            "video_id", "videoID", "clip_id", "clipID", "content_id",
            "contentID", "comic_id", "comicID", "album_id", "albumID",
            "photo_id", "photoID", "artwork_id", "artworkID", "illust_id",
            "illustID", "status_id", "statusID", "tweet_id", "tweetID",
            "note_id", "noteID", "episode_id", "episodeID", "chapter_id",
            "chapterID", "work_id", "workID", "series_id", "seriesID",
            "item_id", "itemID", "pin_id", "pinID", "thread_id",
            "threadID", "article_id", "articleID", "track_id", "trackID",
            "media_id", "mediaID", "attachment_id", "attachmentID",
            "file_id", "fileID", "bvid", "aid", "cid", "vod_id",
            "vodID", "catch_id", "catchID", "live_id", "liveID",
            "movie_id", "movieID", "claim_id", "claimID", "coub_id",
            "coubID", "snapshot_id", "snapshotID", "archive_timestamp"
        ]

        for key in keys {
            if let value = metadata[key]?.trimmed, !value.isEmpty {
                return value.sanitizedFilename(maxLength: 80)
            }
        }
        for key in keys {
            if let match = metadata.first(where: {
                $0.key.caseInsensitiveCompare(key) == .orderedSame
            }), !match.value.trimmed.isEmpty {
                return match.value.trimmed.sanitizedFilename(maxLength: 80)
            }
        }
        return nil
    }

    static func dateFolderName(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func templateMetadataValue(
        _ metadata: [String: String],
        key: String
    ) -> String? {
        if let value = metadata[key]?.trimmed, !value.isEmpty {
            return value
        }
        if let match = metadata.first(where: {
            $0.key.caseInsensitiveCompare(key) == .orderedSame
        }), !match.value.trimmed.isEmpty {
            return match.value.trimmed
        }
        return nil
    }

    private static func normalizedTemplateDate(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }

        if let match = value.range(
            of: #"^[0-9]{8}(?:[0-9]{6})?$"#,
            options: .regularExpression
        ) {
            let digits = String(value[match])
            let year = digits.prefix(4)
            let monthStart = digits.index(digits.startIndex, offsetBy: 4)
            let dayStart = digits.index(digits.startIndex, offsetBy: 6)
            let month = digits[monthStart..<dayStart]
            let dayEnd = digits.index(digits.startIndex, offsetBy: 8)
            let day = digits[dayStart..<dayEnd]
            return "\(year)-\(month)-\(day)"
        }

        if let date = normalizedUnixTemplateDate(value) {
            return date
        }

        let pattern = #"([0-9]{4})[-./]([0-9]{1,2})[-./]([0-9]{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: value,
                range: NSRange(value.startIndex..<value.endIndex, in: value)
              ),
              let yearRange = Range(match.range(at: 1), in: value),
              let monthRange = Range(match.range(at: 2), in: value),
              let dayRange = Range(match.range(at: 3), in: value),
              let month = Int(value[monthRange]),
              let day = Int(value[dayRange]) else {
            return nil
        }
        return String(
            format: "%@-%02d-%02d",
            String(value[yearRange]),
            month,
            day
        )
    }

    private static func normalizedUnixTemplateDate(_ raw: String) -> String? {
        let value = raw.trimmed
        let seconds: TimeInterval?
        if value.range(
            of: #"^1[0-9]{9}(?:\.[0-9]+)?$"#,
            options: .regularExpression
        ) != nil {
            seconds = TimeInterval(value)
        } else if value.range(
            of: #"^1[0-9]{12}$"#,
            options: .regularExpression
        ) != nil,
        let milliseconds = TimeInterval(value) {
            seconds = milliseconds / 1000
        } else {
            seconds = nil
        }
        guard let seconds, seconds > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private func sourceIdentifier(for url: URL) -> String {
        let absolute = url.absoluteString
        let patterns = [
            #"hitomi\.la/(?:reader|galleries|g|lofi|mpv)/([0-9]+)"#,
            #"-([0-9]+)\.html"#,
            #"galleryblock/([0-9]+)"#,
            #"#-\*-[^#]*\(([0-9]+)\)"#
        ]
        for pattern in patterns {
            if let match = firstCapture(in: absolute, pattern: pattern) {
                return match
            }
        }
        let last = url.deletingPathExtension().lastPathComponent
        if !last.trimmed.isEmpty {
            return last.sanitizedFilename(maxLength: 80)
        }
        return siteFolderName(for: url)
    }

    private func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let captureRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[captureRange])
    }

    private func siteFolderName(for url: URL) -> String {
        if url.scheme?.lowercased() == "magnet" { return "magnet" }
        if url.scheme?.lowercased() == "file" { return "local" }
        let host = (url.host ?? "downloads").replacingOccurrences(
            of: "^www\\.",
            with: "",
            options: .regularExpression
        )
        return host.sanitizedFilename(maxLength: 80)
    }

    private func sourceHostToken(for url: URL) -> String {
        if url.scheme?.lowercased() == "magnet" { return "magnet" }
        if url.scheme?.lowercased() == "file" { return "local" }
        return sanitizedTemplateToken(
            url.host?.lowercased() ?? siteFolderName(for: url),
            maxLength: 120
        )
    }

    private func sourcePathToken(for url: URL) -> String {
        let decodedPath = url.path.removingPercentEncoding ?? url.path
        let trimmedPath = decodedPath.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return sanitizedTemplateToken(trimmedPath, maxLength: 180)
    }

    private func sourceSlugToken(for url: URL) -> String {
        let urlWithoutExtension = url.deletingPathExtension()
        let slug = urlWithoutExtension.lastPathComponent.removingPercentEncoding
            ?? urlWithoutExtension.lastPathComponent
        return sanitizedTemplateToken(slug, maxLength: 120)
    }

    private func sourceQueryToken(for url: URL) -> String {
        let query = url.query?.removingPercentEncoding ?? url.query ?? ""
        return sanitizedTemplateToken(query, maxLength: 180)
    }

    private func sanitizedTemplateToken(
        _ value: String,
        maxLength: Int
    ) -> String {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return "" }
        return trimmed.sanitizedFilename(maxLength: maxLength)
    }
}
