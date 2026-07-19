import Foundation

final class BCYResolver {
    private let maxUserPages = 1_000

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        return Self.itemID(from: url) != nil || Self.userID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        if let pageURL = Self.canonicalItemURL(from: url) {
            let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
            return try Self.resolvedDownload(fromHTML: html, pageURL: pageURL)
        }

        guard let uid = Self.userID(from: url) else {
            throw NativeDownloadError.unsupported("Unsupported BCY URL.")
        }
        return try await resolveUser(uid: uid, sourceURL: url, headers: headers, assetLimit: assetLimit)
    }

    private func resolveUser(
        uid: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: sourceURL, referer: headers.referer, userAgent: headers.userAgent)
        let finiteAssetLimit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        var downloads: [(url: URL, resolved: ResolvedDownload)] = []
        var seenItems = Set<String>()
        var resolvedAssetCount = 0
        var resolvedAPIPageCount = 0

        var since: String?
        for _ in 0..<maxUserPages {
            try Task.checkCancellation()
            let apiURL = Self.selfPostsAPIURL(uid: uid, since: since, sourceURL: sourceURL)
            let data: Data
            do {
                data = try await HTTPClient.shared.data(
                    from: apiURL,
                    referer: sourceURL.absoluteString,
                    userAgent: headers.userAgent
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                break
            }
            guard let object = try? Self.jsonObject(from: data) else { break }

            let details = Self.itemDetails(fromAPIObject: object)
            guard !details.isEmpty else { break }
            resolvedAPIPageCount += 1

            var newItemCount = 0
            for detail in details {
                try Task.checkCancellation()
                let itemID = Self.stringValue(detail["item_id"]) ??
                    Self.stringValue(detail["itemId"]) ??
                    Self.stringValue(detail["id"]) ??
                    Self.firstString(forKeys: ["item_id", "itemId", "id"], in: detail)
                guard let itemID else { continue }
                guard !seenItems.contains(itemID) else { continue }
                seenItems.insert(itemID)
                newItemCount += 1

                let itemURL = Self.itemURL(itemID: itemID, sourceURL: sourceURL)
                do {
                    let itemHTML = try await HTTPClient.shared.string(
                        from: itemURL,
                        referer: sourceURL.absoluteString,
                        userAgent: headers.userAgent
                    )
                    let resolved = try Self.resolvedDownload(fromHTML: itemHTML, pageURL: itemURL)
                    downloads.append((url: itemURL, resolved: resolved))
                    resolvedAssetCount += resolved.assets.count
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    continue
                }
                if let finiteAssetLimit, resolvedAssetCount >= finiteAssetLimit { break }
            }

            guard newItemCount > 0 else { break }
            if let finiteAssetLimit, resolvedAssetCount >= finiteAssetLimit { break }
            since = downloads.last.flatMap { Self.itemID(from: $0.url) }
        }

        if downloads.isEmpty {
            for itemURL in Self.itemPageURLs(fromHTML: html, baseURL: sourceURL) {
                try Task.checkCancellation()
                let itemID = Self.itemID(from: itemURL) ?? URLIdentity.normalize(itemURL.absoluteString)
                guard !seenItems.contains(itemID) else { continue }
                seenItems.insert(itemID)

                let itemHTML = try await HTTPClient.shared.string(from: itemURL, referer: sourceURL.absoluteString, userAgent: headers.userAgent)
                if let resolved = try? Self.resolvedDownload(fromHTML: itemHTML, pageURL: itemURL) {
                    downloads.append((url: itemURL, resolved: resolved))
                    resolvedAssetCount += resolved.assets.count
                }
                if let finiteAssetLimit, resolvedAssetCount >= finiteAssetLimit { break }
            }
        }

        var resolved = try Self.resolvedCollectionDownload(
            uid: uid,
            sourceURL: sourceURL,
            pageHTML: html,
            itemDownloads: downloads,
            maxAssets: finiteAssetLimit
        )
        resolved.metadata["resolved_api_page_count"] = String(resolvedAPIPageCount)
        resolved.metadata["resolved_post_count"] = String(downloads.count)
        resolved.metadata["resolved_media_count"] = String(resolved.assets.count)
        return resolved
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        guard let object = ssrObject(fromHTML: html) else {
            throw NativeDownloadError.noFiles
        }
        return try resolvedDownload(fromItemObject: itemDetailObject(from: object) ?? object, pageURL: pageURL, pageHTML: html)
    }

    static func resolvedDownload(fromItemObject object: [String: Any], pageURL: URL, pageHTML: String?) throws -> ResolvedDownload {
        let itemID = itemID(from: pageURL) ??
            stringValue(object["item_id"]) ??
            stringValue(object["itemId"]) ??
            stringValue(object["id"]) ??
            firstString(forKeys: ["item_id", "itemId", "id"], in: object) ??
            pageURL.lastPathComponent
        let canonicalPageURL = itemURL(itemID: itemID, sourceURL: pageURL)
        let title = cleanTitle(
            firstString(forKeys: ["title", "name"], in: object) ??
                pageHTML.flatMap { title(fromHTML: $0) } ??
                "BCY \(itemID)",
            fallback: "BCY \(itemID)"
        )
        let artist = cleanTitle(
            firstString(forKeys: ["uname", "user_name", "username", "artist", "name"], in: detailUserObject(from: object) ?? [:]) ??
                pageHTML.flatMap { artistName(fromHTML: $0) } ??
                "",
            fallback: ""
        )

        let imageURLs = mediaURLs(fromItemObject: object, pageURL: canonicalPageURL)
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assets = imageURLs.enumerated().map { offset, remote in
            ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, index: offset + 1, total: imageURLs.count),
                metadata: assetMetadata(for: remote, itemID: itemID, userID: nil, artist: artist, title: title, pageURL: canonicalPageURL, index: offset + 1),
                referer: canonicalPageURL.absoluteString
            )
        }

        let displayTitle = artist.isEmpty ? "\(title) (bcy_\(itemID))" : "\(title) (bcy_\(itemID)) - \(artist)"
        return ResolvedDownload(
            title: displayTitle.sanitizedFilename(maxLength: 120),
            folderName: displayTitle.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "artist": artist,
                "author": artist,
                "creator": artist,
                "user": artist,
                "username": artist,
                "uploader": artist,
                "channel": artist,
                "item_id": itemID,
                "gallery_id": itemID,
                "slug": itemID,
                "site": "BCY",
                "title": title,
                "type": "item",
                "media_type": "image",
                "category": "image",
                "media_count": String(imageURLs.count),
                "image_count": String(imageURLs.count),
                "url": canonicalPageURL.absoluteString,
                "source_url": canonicalPageURL.absoluteString,
                "page_url": canonicalPageURL.absoluteString
            ])
        )
    }

    static func resolvedCollectionDownload(
        uid: String,
        sourceURL: URL,
        pageHTML: String,
        itemDownloads: [(url: URL, resolved: ResolvedDownload)],
        maxAssets: Int? = nil
    ) throws -> ResolvedDownload {
        guard !itemDownloads.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var assets: [ResolvedAsset] = []
        var seenFiles = Set<String>()
        itemLoop: for (itemIndex, item) in itemDownloads.enumerated() {
            for asset in item.resolved.assets {
                var filename = String(format: "%04d-%@", itemIndex + 1, asset.filename).sanitizedFilename(maxLength: 180)
                if seenFiles.contains(filename.lowercased()) {
                    let ext = (filename as NSString).pathExtension
                    let base = (filename as NSString).deletingPathExtension
                    filename = ext.isEmpty ? "\(base)-\(assets.count + 1)" : "\(base)-\(assets.count + 1).\(ext)"
                }
                var metadata = asset.metadata
                if metadata["user_id", default: ""].trimmed.isEmpty {
                    metadata["user_id"] = uid
                }
                metadata["post_index"] = String(itemIndex + 1)
                metadata["page"] = String(assets.count + 1)
                metadata["position"] = String(assets.count + 1)
                seenFiles.insert(filename.lowercased())
                assets.append(ResolvedAsset(
                    remoteURL: asset.remoteURL,
                    filename: filename,
                    metadata: metadata,
                    referer: asset.referer ?? item.url.absoluteString
                ))
                if let maxAssets, assets.count >= maxAssets { break itemLoop }
            }
        }

        let name = cleanTitle(artistName(fromHTML: pageHTML) ?? "BCY \(uid)", fallback: "BCY \(uid)")
        return ResolvedDownload(
            title: "\(name) (bcy_\(uid))".sanitizedFilename(maxLength: 120),
            folderName: "BCY \(name)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "artist": name,
                "author": name,
                "creator": name,
                "user": name,
                "username": name,
                "uploader": name,
                "channel": name,
                "user_id": uid,
                "gallery_id": uid,
                "slug": uid,
                "site": "BCY",
                "title": name,
                "type": "user",
                "media_type": "image",
                "category": "image",
                "media_count": String(assets.count),
                "image_count": String(assets.count),
                "post_count": String(itemDownloads.count),
                "url": sourceURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "page_url": sourceURL.absoluteString
            ])
        )
    }

    static func itemDownloads(fromHTML html: String, pageURL: URL) -> [(url: URL, resolved: ResolvedDownload)] {
        guard let object = ssrObject(fromHTML: html) else { return [] }
        var downloads: [(url: URL, resolved: ResolvedDownload)] = []
        var seen = Set<String>()
        for detail in itemDetails(from: object) {
            let itemID = stringValue(detail["item_id"]) ??
                stringValue(detail["itemId"]) ??
                stringValue(detail["id"]) ??
                firstString(forKeys: ["item_id", "itemId", "id"], in: detail) ??
                UUID().uuidString
            guard !seen.contains(itemID) else { continue }
            seen.insert(itemID)

            let url = itemURL(itemID: itemID, sourceURL: pageURL)
            if let resolved = try? resolvedDownload(fromItemObject: detail, pageURL: url, pageHTML: nil) {
                downloads.append((url, resolved))
            }
        }
        return downloads
    }

    static func mediaURLs(fromItemObject object: [String: Any], pageURL: URL) -> [URL] {
        let postData = postDataObject(from: object) ?? object
        var rawPaths: [String] = []

        if let multi = postData["multi"] as? [[String: Any]] {
            for item in multi {
                if let original = firstString(forKeys: ["original_path", "originalPath", "path"], in: item) {
                    rawPaths.append(original)
                }
            }
        }
        if rawPaths.isEmpty {
            rawPaths.append(contentsOf: allStrings(forKey: "original_path", in: postData))
            rawPaths.append(contentsOf: allStrings(forKey: "originalPath", in: postData))
        }

        var urls: [URL] = []
        var seen = Set<String>()
        for raw in rawPaths {
            guard !raw.contains("noop.image"),
                  !raw.hasSuffix(".image"),
                  let remote = absoluteURL(raw, baseURL: pageURL),
                  isDownloadableMedia(remote) else {
                continue
            }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(remote)
        }
        return urls
    }

    static func itemPageURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        var urls: [URL] = []
        var seen = Set<String>()
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attrsRange]))
            guard let href = attributes["href"],
                  let url = absoluteURL(href, baseURL: baseURL),
                  let canonical = canonicalItemURL(from: url) else {
                continue
            }
            let normalized = URLIdentity.normalize(canonical.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(canonical)
        }
        return urls
    }

    static func canonicalItemURL(from url: URL) -> URL? {
        guard let itemID = itemID(from: url) else { return nil }
        return itemURL(itemID: itemID, sourceURL: url)
    }

    static func itemID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let detailIndex = parts.firstIndex(where: { $0.lowercased() == "detail" }),
              detailIndex + 1 < parts.count else {
            return nil
        }
        let id = parts[detailIndex + 1].removingPercentEncoding ?? parts[detailIndex + 1]
        return isValidID(id) ? id : nil
    }

    static func userID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2,
              parts[0].lowercased() == "u" else {
            return nil
        }
        let id = parts[1].removingPercentEncoding ?? parts[1]
        return isValidID(id) ? id : nil
    }

    static func itemURL(itemID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "bcy.net.test" : "bcy.net"
        components.path = "/item/detail/\(itemID)"
        return components.url!
    }

    static func selfPostsAPIURL(uid: String, since: String?, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "bcy.net.test" : "bcy.net"
        components.path = "/apiv3/user/selfPosts"
        var items = [URLQueryItem(name: "uid", value: uid)]
        if let since, !since.isEmpty {
            items.append(URLQueryItem(name: "since", value: since))
        }
        components.queryItems = items
        return components.url!
    }

    static func ssrObject(fromHTML html: String) -> [String: Any]? {
        if let jsonText = jsonParseJSONStringArgument(fromHTML: html),
           let data = jsonText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        if let raw = firstCapture(pattern: #"window\.__ssr_data\s*=\s*(\{.*?\})\s*(?:;|</script>)"#, in: html),
           let data = raw.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }

        return nil
    }

    private static func jsonParseJSONStringArgument(fromHTML html: String) -> String? {
        guard let parseRange = html.range(of: "JSON.parse(") else { return nil }
        var index = parseRange.upperBound
        while index < html.endIndex, html[index].isWhitespace {
            index = html.index(after: index)
        }
        guard index < html.endIndex, html[index] == "\"" else { return nil }

        var output = ""
        var escaped = false
        index = html.index(after: index)
        while index < html.endIndex {
            let character = html[index]
            if escaped {
                switch character {
                case "\"", "\\", "/":
                    output.append(character)
                case "n":
                    output.append("\n")
                case "r":
                    output.append("\r")
                case "t":
                    output.append("\t")
                default:
                    output.append(character)
                }
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else if character == "\"" {
                return output
            } else {
                output.append(character)
            }
            index = html.index(after: index)
        }
        return nil
    }

    static func itemDetails(fromAPIObject object: [String: Any]) -> [[String: Any]] {
        itemDetails(from: object)
    }

    static func nextSince(fromAPIObject object: [String: Any]) -> String? {
        firstString(forKeys: ["since", "next", "nextSince", "last_id", "lastId"], in: object)
    }

    private static func itemDetails(from object: [String: Any]) -> [[String: Any]] {
        var details: [[String: Any]] = []
        collectItemDetails(from: object, into: &details)
        var seen = Set<String>()
        return details.filter { detail in
            guard let id = stringValue(detail["item_id"]) ??
                stringValue(detail["itemId"]) ??
                stringValue(detail["id"]) ??
                firstString(forKeys: ["item_id", "itemId", "id"], in: detail) else {
                return true
            }
            guard !seen.contains(id) else { return false }
            seen.insert(id)
            return true
        }
    }

    private static func collectItemDetails(from value: Any, into details: inout [[String: Any]]) {
        if let dict = value as? [String: Any] {
            if let itemDetail = dict["item_detail"] as? [String: Any] {
                details.append(itemDetail)
            }
            if dict["post_data"] != nil ||
                (dict["multi"] != nil && (dict["item_id"] != nil || dict["itemId"] != nil || dict["id"] != nil)) {
                details.append(dict)
            }
            for child in dict.values {
                collectItemDetails(from: child, into: &details)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectItemDetails(from: child, into: &details)
            }
        }
    }

    private static func itemDetailObject(from object: [String: Any]) -> [String: Any]? {
        if let data = object["data"] as? [String: Any],
           let detail = data["detail"] as? [String: Any] {
            return detail
        }
        if let detail = object["detail"] as? [String: Any] {
            return detail
        }
        return itemDetails(from: object).first
    }

    private static func postDataObject(from object: [String: Any]) -> [String: Any]? {
        if let post = object["post_data"] as? [String: Any] {
            return post
        }
        if let data = object["data"] as? [String: Any],
           let detail = data["detail"] as? [String: Any],
           let post = detail["post_data"] as? [String: Any] {
            return post
        }
        return nil
    }

    private static func detailUserObject(from object: [String: Any]) -> [String: Any]? {
        if let user = object["detail_user"] as? [String: Any] {
            return user
        }
        if let user = object["user"] as? [String: Any] {
            return user
        }
        if let data = object["data"] as? [String: Any],
           let detail = data["detail"] as? [String: Any],
           let user = detail["detail_user"] as? [String: Any] {
            return user
        }
        return nil
    }

    private static func title(fromHTML html: String) -> String? {
        elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html)
    }

    private static func artistName(fromHTML html: String) -> String? {
        for marker in ["user-name", "user-info-name", "uname", "nickname"] {
            if let text = elementText(
                pattern: #"<[^>]*\bclass\s*=\s*["'][^"']*\#(marker)[^"']*["'][^>]*>(.*?)</[^>]+>"#,
                in: html
            ) {
                return text
            }
        }
        return nil
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = firstCapture(pattern: pattern, in: html) else { return nil }
        let text = cleanTitle(stripTags(raw), fallback: "")
        return text.isEmpty ? nil : text
    }

    private static func attributeValues(from raw: String) -> [String: String] {
        var values: [String: String] = [:]
        guard let regex = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s"'=<>`]+))"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return values
        }
        let range = NSRange(raw.startIndex..<raw.endIndex, in: raw)
        for match in regex.matches(in: raw, range: range) {
            guard let keyRange = Range(match.range(at: 1), in: raw) else { continue }
            let key = String(raw[keyRange]).lowercased()
            let value: String
            if let range = Range(match.range(at: 2), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 3), in: raw) {
                value = String(raw[range])
            } else if let range = Range(match.range(at: 4), in: raw) {
                value = String(raw[range])
            } else {
                value = ""
            }
            values[key] = decodeHTML(value)
        }
        return values
    }

    private static func allStrings(forKey key: String, in value: Any) -> [String] {
        var strings: [String] = []
        collectStrings(forKey: key, in: value, into: &strings)
        return strings
    }

    private static func collectStrings(forKey key: String, in value: Any, into strings: inout [String]) {
        if let dict = value as? [String: Any] {
            for (dictKey, child) in dict {
                if dictKey == key, let text = stringValue(child), !text.isEmpty {
                    strings.append(text)
                }
                collectStrings(forKey: key, in: child, into: &strings)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectStrings(forKey: key, in: child, into: &strings)
            }
        }
    }

    private static func firstString(forKeys keys: [String], in value: Any) -> String? {
        if let dict = value as? [String: Any] {
            for key in keys {
                if let value = stringValue(dict[key]), !value.isEmpty {
                    return value
                }
            }
            for child in dict.values {
                if let found = firstString(forKeys: keys, in: child) {
                    return found
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let found = firstString(forKeys: keys, in: child) {
                    return found
                }
            }
        }
        return nil
    }

    private static func firstCapture(pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return String(text[capture])
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.unsupported("Invalid BCY JSON response.")
        }
        return object
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        return nil
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        if let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            return url
        }
        return nil
    }

    private static func isDownloadableMedia(_ url: URL) -> Bool {
        allowedExtensions.contains(url.pathExtension.lowercased())
    }

    private static func filename(for url: URL, index: Int, total: Int) -> String {
        let rawExt = url.pathExtension.lowercased()
        let ext = rawExt.isEmpty ? "jpg" : rawExt
        return String(format: "%04d.%@", index, ext).sanitizedFilename(maxLength: 180)
    }

    private static func assetMetadata(for url: URL, itemID: String, userID: String?, artist: String, title: String, pageURL: URL, index: Int) -> [String: String] {
        let format = mediaFormat(for: url)
        return DownloadMetadata.clean([
            "artist": artist,
            "author": artist,
            "creator": artist,
            "user": artist,
            "username": artist,
            "uploader": artist,
            "channel": artist,
            "item_id": itemID,
            "user_id": userID ?? "",
            "gallery_id": itemID,
            "id": itemID,
            "media_id": "\(itemID)-\(index)",
            "page": String(index),
            "position": String(index),
            "slug": itemID,
            "site": "BCY",
            "title": title,
            "series": title,
            "type": "image",
            "media_type": "image",
            "category": "image",
            "format": format,
            "media_format": format,
            "image_url": url.absoluteString,
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func stripTags(_ raw: String) -> String {
        raw.replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ raw: String) -> String {
        var text = raw
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
        guard let regex = try? NSRegularExpression(pattern: #"&#(?:x([0-9A-Fa-f]+)|([0-9]+));"#) else {
            return text
        }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..<text.endIndex, in: text)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: text) else { continue }
            let scalarValue: UInt32?
            if let hexRange = Range(match.range(at: 1), in: text) {
                scalarValue = UInt32(String(text[hexRange]), radix: 16)
            } else if let decimalRange = Range(match.range(at: 2), in: text) {
                scalarValue = UInt32(String(text[decimalRange]), radix: 10)
            } else {
                scalarValue = nil
            }
            if let scalarValue, let scalar = UnicodeScalar(scalarValue) {
                text.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return text
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var text = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" - BCY", " | BCY", " - bcy.net", " | bcy.net"] {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return text.isEmpty ? fallback : text
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "bcy.net" ||
            host == "www.bcy.net" ||
            host == "bcy.net.test" ||
            host == "www.bcy.net.test"
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static let allowedExtensions: Set<String> = [
        "jpg",
        "jpeg",
        "png",
        "gif",
        "webp",
        "bmp"
    ]
}
