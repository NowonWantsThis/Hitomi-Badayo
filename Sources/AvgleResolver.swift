import Foundation

struct OriginalBrowserExtensionTask: Equatable {
    static let header = "data:hitomi_downloader_task"
    static let markerKey = "original_browser_extension_task"
    static let versionKey = "original_browser_extension_version"
    static let versionKindKey = "original_browser_extension_version_kind"
    static let dataKey = "original_browser_extension_data"

    let url: String
    let version: String
    let versionIsString: Bool
    let data: String

    var metadata: [String: String] {
        DownloadMetadata.clean([
            Self.markerKey: "true",
            Self.versionKey: version,
            Self.versionKindKey: versionIsString ? "string" : "other",
            Self.dataKey: data
        ])
    }

    static func parse(_ input: String) -> OriginalBrowserExtensionTask? {
        guard input.hasPrefix(header) else { return nil }
        let suffix = String(input.dropFirst(header.count))
            .trimmingCharacters(in: CharacterSet(charactersIn: " ;"))
        guard let jsonData = suffix.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let url = object["url"] as? String,
              let data = object["data"] as? String else {
            return nil
        }

        let rawVersion: Any = object["version"] ?? "0.1"
        let versionIsString = rawVersion is String
        let version: String
        if let string = rawVersion as? String {
            version = string
        } else if let number = rawVersion as? NSNumber {
            version = number.stringValue
        } else {
            version = String(describing: rawVersion)
        }

        return OriginalBrowserExtensionTask(
            url: url,
            version: version,
            versionIsString: versionIsString,
            data: data
        )
    }
}

struct AvgleExtensionPayload: Equatable {
    static let fixedFragmentConcurrency = 4

    let version: String
    let segmentURLs: [URL]
    let rawSegmentURLs: [String]
    let requestedAutomaticSegmentReferer: Bool

    static func decode(from metadata: [String: String]) throws -> AvgleExtensionPayload {
        guard metadata[OriginalBrowserExtensionTask.markerKey] == "true",
              let encoded = metadata[OriginalBrowserExtensionTask.dataKey] else {
            throw NativeDownloadError.unsupported(
                "Avgle requires data from the compatible browser extension. See https://github.com/KurtBestor/Hitomi-Downloader/wiki/Chrome-Extension"
            )
        }

        let version = metadata[OriginalBrowserExtensionTask.versionKey] ?? "0.1"
        let versionIsString = metadata[OriginalBrowserExtensionTask.versionKindKey] != "other"
        if versionIsString && version == "0.1" {
            throw NativeDownloadError.unsupported(
                "The compatible browser extension is outdated. Install a newer extension and add the Avgle video again."
            )
        }

        guard let decoded = Data(base64Encoded: encoded, options: .ignoreUnknownCharacters),
              let json = String(data: decoded, encoding: .utf8),
              let jsonData = json.data(using: .utf8),
              let values = try? JSONSerialization.jsonObject(with: jsonData) as? [Any],
              !values.isEmpty else {
            throw NativeDownloadError.unsupported("The Avgle browser extension data is invalid or empty.")
        }

        var rawURLs: [String] = []
        var urls: [URL] = []
        rawURLs.reserveCapacity(values.count)
        urls.reserveCapacity(values.count)
        for value in values {
            guard let raw = value as? String,
                  let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                throw NativeDownloadError.unsupported("The Avgle browser extension returned an invalid segment URL.")
            }
            rawURLs.append(raw)
            urls.append(url)
        }

        return AvgleExtensionPayload(
            version: version,
            segmentURLs: urls,
            rawSegmentURLs: rawURLs,
            requestedAutomaticSegmentReferer: rawURLs[0].contains("referer=force")
        )
    }
}

final class AvgleResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "avgle.com" || host.hasSuffix(".avgle.com")
    }

    func resolve(
        _ url: URL,
        metadata inputMetadata: [String: String],
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        guard canResolve(url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let payload = try AvgleExtensionPayload.decode(from: inputMetadata)
        let html = try await HTTPClient.shared.string(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent
        )
        let page = try Self.openGraphMetadata(fromHTML: html, pageURL: url)
        let mp4Filename = "\(page.title).mp4".sanitizedFilename(maxLength: 180)
        let temporaryFilename = "\((mp4Filename as NSString).deletingPathExtension).ts"

        let hls = try M3U8Resolver().resolveCustomSegments(
            payload.segmentURLs,
            playlistURL: url,
            titleHint: page.title,
            headers: HTTPRequestOptions(userAgent: headers.userAgent)
        )
        let assets = hls.assets.enumerated().map { offset, original -> ResolvedAsset in
            var asset = original
            // In the original 4.2 bytecode, referer_seg="auto" resolves to a nil
            // referer because Avgle does not pass M3u8_stream's referer argument.
            asset.referer = nil
            asset.metadata.merge([
                "site": "Avgle",
                "source_url": url.absoluteString,
                "page_url": url.absoluteString,
                "position": String(offset + 1),
                "asset_concurrency_override": String(AvgleExtensionPayload.fixedFragmentConcurrency)
            ]) { _, avgleValue in avgleValue }
            return asset
        }

        var metadata = hls.metadata
        metadata.merge(inputMetadata) { _, inputValue in inputValue }
        metadata.merge([
            "site": "Avgle",
            "handler": "native-avgle-extension",
            "title": page.title,
            "series": page.title,
            "category": "video",
            "type": "hls",
            "media_type": "hls",
            "format": "m3u8",
            "media_format": "m3u8",
            "filename": mp4Filename,
            "container": "mp4",
            "thumbnail": page.thumbnail.absoluteString,
            "thumbnail_referer": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": url.absoluteString,
            "extension_version": payload.version,
            "segment_count": String(assets.count),
            "fragment_concurrency": String(AvgleExtensionPayload.fixedFragmentConcurrency),
            "referer_force_requested": payload.requestedAutomaticSegmentReferer ? "true" : "false",
            "segment_referer": "none",
            "hls_remux_required": "true"
        ]) { _, avgleValue in avgleValue }

        return ResolvedDownload(
            title: page.title,
            folderName: page.title.sanitizedFilename(maxLength: 120),
            assets: assets,
            packageMode: .concatenate(outputFilename: temporaryFilename.sanitizedFilename(maxLength: 180)),
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    static func openGraphMetadata(fromHTML html: String, pageURL: URL) throws -> (title: String, thumbnail: URL) {
        guard let rawTitle = firstMetaContent(property: "og:title", in: html) else {
            throw NativeDownloadError.unsupported("Avgle page did not contain an og:title value.")
        }
        guard let rawThumbnail = firstMetaContent(property: "og:image", in: html),
              let thumbnail = URL(string: decodeHTML(rawThumbnail).trimmed, relativeTo: pageURL)?.absoluteURL else {
            throw NativeDownloadError.unsupported("Avgle page did not contain a valid og:image value.")
        }
        let title = decodeHTML(rawTitle).trimmed
        guard !title.isEmpty else {
            throw NativeDownloadError.unsupported("Avgle page title is empty.")
        }
        return (title, thumbnail)
    }

    private static func firstMetaContent(property: String, in html: String) -> String? {
        guard let tagRegex = try? NSRegularExpression(pattern: #"<meta\b[^>]*>"#, options: [.caseInsensitive]),
              let attributeRegex = try? NSRegularExpression(
                pattern: #"([A-Za-z_:][A-Za-z0-9_:.-]*)\s*=\s*(?:\"([^\"]*)\"|'([^']*)'|([^\s\"'=<>`]+))"#,
                options: [.caseInsensitive]
              ) else {
            return nil
        }
        let source = html as NSString
        let range = NSRange(location: 0, length: source.length)
        for match in tagRegex.matches(in: html, range: range) {
            let tag = source.substring(with: match.range)
            let tagSource = tag as NSString
            var attributes: [String: String] = [:]
            let tagRange = NSRange(location: 0, length: tagSource.length)
            for attribute in attributeRegex.matches(in: tag, range: tagRange) {
                guard attribute.numberOfRanges >= 5,
                      attribute.range(at: 1).location != NSNotFound else { continue }
                let name = tagSource.substring(with: attribute.range(at: 1)).lowercased()
                let valueRange = (2...4)
                    .map { attribute.range(at: $0) }
                    .first { $0.location != NSNotFound }
                if let valueRange {
                    attributes[name] = tagSource.substring(with: valueRange)
                }
            }
            if attributes["property"]?.caseInsensitiveCompare(property) == .orderedSame,
               let content = attributes["content"] {
                return content
            }
        }
        return nil
    }

    private static func decodeHTML(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
            .replacingOccurrences(of: "&quot;", with: "\"", options: .caseInsensitive)
            .replacingOccurrences(of: "&#39;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&apos;", with: "'", options: .caseInsensitive)
            .replacingOccurrences(of: "&lt;", with: "<", options: .caseInsensitive)
            .replacingOccurrences(of: "&gt;", with: ">", options: .caseInsensitive)
            .replacingOccurrences(of: "&nbsp;", with: " ", options: .caseInsensitive)
        guard let regex = try? NSRegularExpression(pattern: #"&#(x[0-9A-Fa-f]+|[0-9]+);"#) else {
            return value
        }
        let source = value as NSString
        let matches = regex.matches(in: value, range: NSRange(location: 0, length: source.length))
        for match in matches.reversed() {
            guard match.numberOfRanges > 1 else { continue }
            let token = source.substring(with: match.range(at: 1))
            let scalarValue = token.lowercased().hasPrefix("x")
                ? UInt32(token.dropFirst(), radix: 16)
                : UInt32(token, radix: 10)
            guard let scalarValue, let scalar = UnicodeScalar(scalarValue) else { continue }
            value = (value as NSString).replacingCharacters(in: match.range, with: String(Character(scalar)))
        }
        return value
    }
}
