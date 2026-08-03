import Foundation

final class ExternalToolOutputMetadataService {
    func ytdlpMetadata(
        for url: URL,
        title: String,
        result: YTDLPResult
    ) -> [String: String] {
        let sourceURL = YTDLPBridge.normalizedSourceURL(for: url)
        let host = sourceURL.host ?? url.host ?? ""
        let primaryItem = ytdlpPrimaryMediaItem(
            in: result.downloadedItems
        )
        let output = result.downloadedItems.count == 1
            ? primaryItem
            : result.outputDirectory
        let filename = output?.lastPathComponent ?? title
        let basename = (filename as NSString).deletingPathExtension
        let ext = primaryItem?.pathExtension.lowercased() ?? ""
        let sourceMetadata = YTDLPBridge.sourceMetadata(for: sourceURL)
        let category =
            sourceMetadata["category"] ??
            externalCategory(forExtension: ext, fallback: "media")

        var metadata = DownloadMetadata.clean([
            "series": title,
            "category": category,
            "type": "yt-dlp",
            "tool": "yt-dlp",
            "handler": SiteRuleHandler.ytdlp.rawValue,
            "format": ext,
            "host": host,
            "site": host,
            "filename": filename,
            "basename": basename,
            "ext": ext,
            "slug": sourceSlug(
                from: sourceURL,
                fallback: basename.isEmpty ? host : basename
            ),
            "path": sourceURL.path,
            "query": sourceURL.query ?? "",
            "url": sourceURL.absoluteString,
            "original_url": url.absoluteString,
            "title": title,
            "playlist_mode":
                YTDLPBridge.allowsPlaylist(for: sourceURL)
                ? "playlist"
                : "single",
            "item_count": String(result.downloadedItems.count),
            "output_count": String(result.downloadedItems.count),
            "output_directory":
                result.outputDirectory.lastPathComponent
        ])

        for (key, value) in sourceMetadata where !value.trimmed.isEmpty {
            metadata[key] = value
        }
        metadata["type"] = "yt-dlp"
        metadata["tool"] = "yt-dlp"
        metadata["handler"] = SiteRuleHandler.ytdlp.rawValue

        for (key, value) in result.infoMetadata
        where !value.trimmed.isEmpty {
            metadata[key] = value
        }
        if let mediaTitle = result.infoMetadata["media_title"],
           !mediaTitle.trimmed.isEmpty {
            metadata["title"] = mediaTitle
            metadata["series"] = mediaTitle
        }
        if let webpageURL = result.infoMetadata["webpage_url"],
           !webpageURL.trimmed.isEmpty {
            metadata["url"] = webpageURL
        }
        return DownloadMetadata.clean(metadata)
    }

    func customCommandMetadata(
        for url: URL,
        rule: SiteRule,
        title: String,
        result: CustomCommandResult
    ) -> [String: String] {
        let host = url.host ?? ""
        let output = result.outputItems.count == 1
            ? result.outputItems.first
            : result.outputDirectory
        let filename = output?.lastPathComponent ?? title
        let basename = (filename as NSString).deletingPathExtension
        let ext =
            result.outputItems.first?.pathExtension.lowercased() ?? ""
        let category = externalCategory(
            forExtension: ext,
            fallback: "external"
        )

        let protectedMetadata = DownloadMetadata.clean([
            "series": title,
            "category": category,
            "type": SiteRuleHandler.customCommand.rawValue,
            "tool": "custom-command",
            "handler": rule.handler.rawValue,
            "rule": rule.name,
            "rule_id": rule.id.uuidString,
            "rule_host": rule.hostSuffix,
            "rule_pattern": rule.urlPattern ?? "",
            "format": ext,
            "host": host,
            "site": host,
            "filename": filename,
            "basename": basename,
            "ext": ext,
            "slug": sourceSlug(
                from: url,
                fallback: basename.isEmpty ? rule.name : basename
            ),
            "path": url.path,
            "query": url.query ?? "",
            "url": url.absoluteString,
            "title": title,
            "item_count": String(result.outputItems.count),
            "output_count": String(result.outputItems.count),
            "output_directory":
                result.outputDirectory.lastPathComponent,
            "remote_package_mode": result.remotePackageMode.label
        ])

        var metadata = protectedMetadata
        for (key, value) in result.manifestMetadata
        where !value.trimmed.isEmpty {
            metadata[key] = value
        }
        for key in [
            "type", "tool", "handler", "rule", "rule_id", "rule_host",
            "rule_pattern"
        ] {
            if let value = protectedMetadata[key] {
                metadata[key] = value
            }
        }
        if let manifestTitle = result.manifestTitle?.trimmed,
           !manifestTitle.isEmpty {
            metadata["title"] = manifestTitle
        } else {
            metadata["title"] = metadata["title"] ?? title
        }
        metadata["series"] =
            metadata["series"] ?? metadata["title"] ?? title
        return DownloadMetadata.clean(metadata)
    }

    func aria2Metadata(
        for url: URL,
        title: String,
        result: Aria2Result,
        options: Aria2Options = .defaults
    ) -> [String: String] {
        let host = url.host ?? ""
        let scheme = url.scheme?.lowercased() ?? ""
        let infoHash = torrentInfoHash(from: url)
        let output = result.downloadedItems.count == 1
            ? result.downloadedItems.first
            : result.outputDirectory
        let filename = output?.lastPathComponent ?? title
        let basename = (filename as NSString).deletingPathExtension
        let ext =
            result.downloadedItems.first?.pathExtension.lowercased() ?? ""
        let displayName = torrentDisplayName(from: url)

        var metadata = [
            "series": displayName.isEmpty ? title : displayName,
            "category": "torrent",
            "type": scheme == "magnet" ? "magnet" : "torrent",
            "tool": "aria2c",
            "handler": "aria2",
            "scheme": scheme,
            "format": ext,
            "host": host,
            "site": host,
            "filename": filename,
            "basename": basename,
            "ext": ext,
            "slug": sourceSlug(
                from: url,
                fallback: displayName.isEmpty ? basename : displayName
            ),
            "path": url.path,
            "query": url.query ?? "",
            "url": url.absoluteString,
            "title": title,
            "display_name": displayName,
            "info_hash": infoHash,
            "selected_files": options.selectedFiles,
            "seed_time_minutes": options.seedTimeMinutes,
            "seed_ratio": options.seedRatio,
            "max_download_limit": options.maxDownloadLimit,
            "max_upload_limit": options.maxUploadLimit,
            "trackers": options.trackerURLs,
            "anonymous_mode": options.anonymousMode ? "true" : "false",
            "item_count": String(result.downloadedItems.count),
            "output_count": String(result.downloadedItems.count),
            "output_directory":
                result.outputDirectory.lastPathComponent
        ]

        if let pieceInfo = result.torrentPieceInfo {
            metadata["torrent_piece_count"] =
                String(pieceInfo.pieceCount)
            metadata["torrent_piece_size"] =
                ByteCountFormatter.string(
                    fromByteCount: pieceInfo.pieceLength,
                    countStyle: .file
                )
            metadata["torrent_total_size"] =
                ByteCountFormatter.string(
                    fromByteCount: pieceInfo.totalLength,
                    countStyle: .file
                )
            metadata["torrent_piece_length"] =
                String(pieceInfo.pieceLength)
            metadata["torrent_total_length"] =
                String(pieceInfo.totalLength)
        }

        return DownloadMetadata.clean(metadata)
    }

    private func ytdlpPrimaryMediaItem(in items: [URL]) -> URL? {
        items.first { item in
            let category = externalCategory(
                forExtension: item.pathExtension.lowercased(),
                fallback: ""
            )
            return category == "video" || category == "audio"
        } ?? items.first
    }

    private func externalCategory(
        forExtension ext: String,
        fallback: String
    ) -> String {
        let category = DownloadContentClassifier.category(
            forExtension: ext,
            contentType: ""
        )
        return category == "file" ? fallback : category
    }

    private func sourceSlug(from url: URL, fallback: String) -> String {
        let last = url.deletingPathExtension().lastPathComponent
        if !last.trimmed.isEmpty {
            return last.sanitizedFilename(maxLength: 120)
        }
        return fallback.sanitizedFilename(maxLength: 120)
    }

    private func torrentDisplayName(from url: URL) -> String {
        if url.scheme?.lowercased() == "magnet",
           let displayName =
            URLComponents(
                url: url,
                resolvingAgainstBaseURL: false
            )?
            .queryItems?
            .first(where: { $0.name == "dn" })?
            .value?
            .trimmed,
           !displayName.isEmpty {
            return displayName
        }

        let filename =
            url.deletingPathExtension().lastPathComponent.trimmed
        if !filename.isEmpty {
            return filename
        }

        return torrentInfoHash(from: url)
    }

    private func torrentInfoHash(from url: URL) -> String {
        guard url.scheme?.lowercased() == "magnet",
              let xt =
                URLComponents(
                    url: url,
                    resolvingAgainstBaseURL: false
                )?
                .queryItems?
                .first(where: { $0.name.lowercased() == "xt" })?
                .value?
                .trimmed
                .lowercased() else {
            return ""
        }

        let prefix = "urn:btih:"
        if xt.hasPrefix(prefix) {
            return String(xt.dropFirst(prefix.count))
        }
        return xt
    }
}
