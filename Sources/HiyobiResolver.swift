import Foundation

struct HiyobiFile {
    var name: String
    var remoteURL: URL
}

final class HiyobiResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.galleryID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let galleryID = Self.galleryID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.readerURL(galleryID: galleryID, sourceURL: url)
        _ = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        let data = try await HTTPClient.shared.data(
            from: Self.apiURL(galleryID: galleryID, sourceURL: pageURL),
            referer: pageURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: ["Accept": "application/json, text/plain, */*"]
        )
        return try Self.resolvedDownload(fromAPIData: data, pageURL: pageURL)
    }

    static func resolvedDownload(fromAPIData data: Data, pageURL: URL) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        guard let galleryID = galleryID(from: pageURL) ?? stringValue(object["id"]) ?? stringValue(object["gallery_id"]) else {
            throw NativeDownloadError.invalidGalleryData
        }
        let sourceURL = readerURL(galleryID: galleryID, sourceURL: pageURL)

        let title = cleanTitle(
            stringValue(object["title"]) ??
                stringValue(object["name"]) ??
                stringValue(object["korean_title"]) ??
                "Hiyobi \(galleryID)",
            fallback: "Hiyobi \(galleryID)"
        )
        let files = try imageFiles(from: object, galleryID: galleryID, sourceURL: sourceURL)
        guard !files.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let metadata = hiyobiMetadata(from: object, galleryID: galleryID, imageCount: files.count, pageURL: sourceURL)
        let assets = files.enumerated().map { offset, file in
            ResolvedAsset(
                remoteURL: file.remoteURL,
                filename: sourceFilename(for: file),
                metadata: assetMetadata(for: file, index: offset + 1, galleryMetadata: metadata, pageURL: sourceURL),
                referer: sourceURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: "\(title) (hiyobi_\(galleryID))".sanitizedFilename(maxLength: 120),
            folderName: "Hiyobi \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func galleryID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        for marker in ["reader", "gallery"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let id = parts[index + 1].trimmed
            if !id.isEmpty, id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return id
            }
        }
        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let galleryID = galleryID(from: url) else { return nil }
        return readerURL(galleryID: galleryID, sourceURL: url)
    }

    static func readerURL(galleryID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "hiyobi.test" : "hiyobi.me"
        components.path = "/reader/\(galleryID)"
        return components.url!
    }

    static func apiURL(galleryID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "api.hiyobi.test" : "api.hiyobi.me"
        components.path = "/gallery/\(galleryID)"
        return components.url!
    }

    static func cdnURL(galleryID: String, filename: String, sourceURL: URL) -> URL {
        let scheme = sourceURL.scheme ?? "https"
        let host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "cdn.hiyobi.test" : "cdn.hiyobi.me"
        return URL(string: "\(scheme)://\(host)/data/\(galleryID)/\(encodedPathComponent(filename))")!
    }

    static func imageFiles(from object: [String: Any], galleryID: String, sourceURL: URL) throws -> [HiyobiFile] {
        let rawFiles = object["files"] as? [Any] ??
            (object["data"] as? [String: Any])?["files"] as? [Any] ??
            object["images"] as? [Any] ??
            []

        var files: [HiyobiFile] = []
        var seen = Set<String>()

        for item in rawFiles {
            guard let file = hiyobiFile(from: item, galleryID: galleryID, sourceURL: sourceURL) else { continue }
            let normalized = URLIdentity.normalize(file.remoteURL.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            files.append(file)
        }
        return files
    }

    private static func hiyobiFile(from item: Any, galleryID: String, sourceURL: URL) -> HiyobiFile? {
        if let name = stringValue(item) {
            let cleanName = name.trimmed
            guard !cleanName.isEmpty else { return nil }
            return HiyobiFile(name: cleanName, remoteURL: cdnURL(galleryID: galleryID, filename: cleanName, sourceURL: sourceURL))
        }

        guard let dictionary = item as? [String: Any] else {
            return nil
        }
        let name = stringValue(dictionary["name"]) ??
            stringValue(dictionary["filename"]) ??
            stringValue(dictionary["file"]) ??
            stringValue(dictionary["path"])
        let directURL = stringValue(dictionary["url"]) ??
            stringValue(dictionary["src"]) ??
            stringValue(dictionary["image"])

        if let directURL,
           let remote = absoluteURL(directURL, baseURL: sourceURL) {
            let fallbackName = remote.lastPathComponent.isEmpty ? "image.jpg" : remote.lastPathComponent
            return HiyobiFile(name: name ?? fallbackName, remoteURL: remote)
        }

        guard let name else { return nil }
        let cleanName = name.trimmed
        guard !cleanName.isEmpty else { return nil }
        return HiyobiFile(name: cleanName, remoteURL: cdnURL(galleryID: galleryID, filename: cleanName, sourceURL: sourceURL))
    }

    static func sourceFilename(for file: HiyobiFile) -> String {
        let safeExt = mediaFormat(for: file.remoteURL, fallbackName: file.name)
        let basename = ((file.name as NSString).deletingPathExtension).trimmed
        let remoteBasename = file.remoteURL.deletingPathExtension().lastPathComponent.trimmed
        let name = basename.isEmpty ? (remoteBasename.isEmpty ? "image" : remoteBasename) : basename
        return "\(name).\(safeExt)".sanitizedFilename(maxLength: 180)
    }

    private static func hiyobiMetadata(from object: [String: Any], galleryID: String, imageCount: Int, pageURL: URL) -> [String: String] {
        let artist = firstMetadataValue(from: object, keys: ["artist", "artists", "author", "authors", "group", "groups", "circle", "circles"])
        let language = firstMetadataValue(from: object, keys: ["language", "languages", "lang"])
        let category = firstMetadataValue(from: object, keys: ["category", "categories", "type"])
        let tags = firstMetadataValue(from: object, keys: ["tags", "tag"])

        return DownloadMetadata.clean([
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "channel": artist,
            "language": language,
            "category": category,
            "tag": tags,
            "tags": tags,
            "gallery_id": galleryID,
            "id": galleryID,
            "site": "Hiyobi",
            "type": "gallery",
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(for file: HiyobiFile, index: Int, galleryMetadata: [String: String], pageURL: URL) -> [String: String] {
        let format = mediaFormat(for: file.remoteURL, fallbackName: file.name)
        let galleryID = galleryMetadata["gallery_id"] ?? ""
        return DownloadMetadata.clean([
            "artist": galleryMetadata["artist"] ?? "",
            "author": galleryMetadata["author"] ?? "",
            "creator": galleryMetadata["creator"] ?? "",
            "uploader": galleryMetadata["uploader"] ?? "",
            "channel": galleryMetadata["channel"] ?? "",
            "language": galleryMetadata["language"] ?? "",
            "category": galleryMetadata["category"] ?? "",
            "tag": galleryMetadata["tag"] ?? "",
            "tags": galleryMetadata["tags"] ?? "",
            "gallery_id": galleryID,
            "id": galleryMetadata["id"] ?? "",
            "media_id": galleryID.isEmpty ? String(index) : "\(galleryID)-\(index)",
            "site": "Hiyobi",
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "filename": file.name,
            "format": format,
            "media_format": format,
            "image_url": file.remoteURL.absoluteString,
            "media_url": file.remoteURL.absoluteString,
            "source_url": file.remoteURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL, fallbackName: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty
            ? (fallbackName as NSString).pathExtension
            : url.pathExtension
        let lowered = ext.lowercased()
        if lowered == "jpeg" {
            return "jpg"
        }
        return lowered.isEmpty ? "jpg" : lowered
    }

    private static func firstMetadataValue(from object: [String: Any], keys: [String]) -> String {
        let nestedData = object["data"] as? [String: Any]
        for key in keys {
            if let value = metadataValue(object[key]) {
                return value
            }
            if let value = metadataValue(nestedData?[key]) {
                return value
            }
        }
        return ""
    }

    private static func metadataValue(_ value: Any?) -> String? {
        if let string = stringValue(value)?.trimmed, !string.isEmpty {
            return string
        }
        if let array = value as? [Any] {
            let values = uniqueStrings(array.compactMap { metadataValue($0) })
            return values.isEmpty ? nil : values.joined(separator: ", ")
        }
        if let dictionary = value as? [String: Any] {
            return metadataValue(dictionary["name"]) ??
                metadataValue(dictionary["title"]) ??
                metadataValue(dictionary["value"]) ??
                metadataValue(dictionary["tag"])
        }
        return nil
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result
    }

    private static func encodedPathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/?#[]@!$&'()*+,;=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(Int(double)) }
        return nil
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "hiyobi.me" ||
            host == "www.hiyobi.me" ||
            host == "hiyobi.test" ||
            host == "www.hiyobi.test"
    }
}
