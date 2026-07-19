import Foundation

enum PinterestKind: Equatable {
    case pin(id: String)
    case board(username: String, slug: String)
    case boardSection(username: String, slug: String, section: String)
    case userCreated(username: String)
}

final class PinterestResolver {
    static let resourceHandlerHeaderValue = "www/[username]/[slug].js"

    func canResolve(_ url: URL) -> Bool {
        Self.kind(from: url) != nil || Self.isPinterestShortURL(url)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        pinLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        if Self.isPinterestShortURL(url) {
            let target = try await Self.expandedShortURL(url, headers: headers)
            return try await resolve(target, headers: headers, pinLimit: pinLimit)
        }

        guard let kind = Self.kind(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        switch kind {
        case .pin(let id):
            let data = try await Self.call(resource: "Pin", options: ["id": id, "field_set_key": "detailed"], sourceURL: url, headers: headers)
            let pin = try Self.resourceData(from: data)
            return try Self.resolvedDownload(fromPins: [pin], title: id, sourceURL: url)
        case .board(let username, let slug):
            return try await resolveBoard(
                username: username,
                slug: slug,
                sectionSlug: nil,
                sourceURL: url,
                headers: headers,
                pinLimit: pinLimit
            )
        case .boardSection(let username, let slug, let section):
            return try await resolveBoard(
                username: username,
                slug: slug,
                sectionSlug: section,
                sourceURL: url,
                headers: headers,
                pinLimit: pinLimit
            )
        case .userCreated(let username):
            return try await resolvePaginatedPins(
                resource: "UserActivityPins",
                options: [
                    "data": [String: Any](),
                    "username": username,
                    "field_set_key": "grid_item"
                ],
                title: "\(username)/_created",
                sourceURL: url,
                headers: headers,
                pinLimit: pinLimit
            )
        }
    }

    private func resolveBoard(
        username: String,
        slug: String,
        sectionSlug: String?,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        pinLimit: Int?
    ) async throws -> ResolvedDownload {
        let boardData = try await Self.call(
            resource: "Board",
            options: ["username": username, "slug": slug, "field_set_key": "detailed"],
            sourceURL: sourceURL,
            headers: headers
        )
        let board = try Self.resourceData(from: boardData)
        guard let boardID = Self.stringValue(board["id"]) else {
            throw NativeDownloadError.invalidGalleryData
        }

        let resource: String
        var options: [String: Any]
        var titleSuffix = ""
        if let sectionSlug, !sectionSlug.isEmpty {
            let sectionsData = try await Self.call(
                resource: "BoardSections",
                options: ["board_id": boardID],
                sourceURL: sourceURL,
                headers: headers
            )
            let sectionsObject = try Self.jsonObject(from: sectionsData)
            let sections = Self.resourceDataArray(from: sectionsObject)
            guard let section = Self.boardSection(in: sections, matching: sectionSlug),
                  let sectionID = Self.stringValue(section["id"]) else {
                throw NativeDownloadError.unsupported("Pinterest board section was not found.")
            }
            resource = "BoardSectionPins"
            options = ["section_id": sectionID]
            titleSuffix = "/\(Self.sectionTitle(from: section, fallback: sectionSlug))"
        } else {
            resource = "BoardFeed"
            options = ["board_id": boardID]
        }

        let boardName = Self.stringValue(board["name"]) ?? Self.stringValue(board["title"]) ?? slug
        let owner = Self.boardOwnerUsername(from: board, fallback: username)
        let title = ("\(owner)/\(boardName)" + titleSuffix)
            .sanitizedRelativePath(maxComponentLength: 120)
        return try await resolvePaginatedPins(
            resource: resource,
            options: options,
            title: title,
            sourceURL: sourceURL,
            headers: headers,
            pinLimit: pinLimit
        )
    }

    private func resolvePaginatedPins(
        resource: String,
        options initialOptions: [String: Any],
        title: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        pinLimit: Int?
    ) async throws -> ResolvedDownload {
        var options = initialOptions
        var pins: [[String: Any]] = []
        var downloadableIdentities = Set<String>()
        var seenBookmarks = Set<String>()
        let effectiveLimit = pinLimit.flatMap { $0 > 0 ? $0 : nil }

        while true {
            try Task.checkCancellation()
            let pageData = try await Self.call(resource: resource, options: options, sourceURL: sourceURL, headers: headers)
            let pageObject = try Self.jsonObject(from: pageData)
            var reachedLimit = false
            for pin in Self.resourceDataArray(from: pageObject) {
                pins.append(pin)
                if let identity = Self.downloadableIdentity(from: pin, sourceURL: sourceURL) {
                    downloadableIdentities.insert(identity)
                }
                if let effectiveLimit, downloadableIdentities.count >= effectiveLimit {
                    reachedLimit = true
                    break
                }
            }
            if reachedLimit { break }

            guard let bookmarks = Self.bookmarks(from: pageObject),
                  let first = bookmarks.first,
                  first != "-end-",
                  !first.hasPrefix("Y2JOb25lO") else {
                break
            }
            let bookmarkIdentity = bookmarks.joined(separator: "\u{1F}")
            guard seenBookmarks.insert(bookmarkIdentity).inserted else { break }
            options["bookmarks"] = bookmarks
        }
        return try Self.resolvedDownload(fromPins: pins, title: title, sourceURL: sourceURL)
    }

    static func call(resource: String, options: [String: Any], sourceURL: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> Data {
        let url = try resourceURL(resource: resource, options: options, sourceURL: sourceURL)
        return try await HTTPClient.shared.data(
            from: url,
            referer: headers.referer ?? Self.baseURL(for: sourceURL).absoluteString + "/",
            userAgent: headers.userAgent,
            additionalHeaders: pinterestHeaders(sourceURL: sourceURL)
        )
    }

    static func resolvedDownload(fromPins pins: [[String: Any]], title: String, sourceURL: URL) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for pin in pins {
            guard let remote = mediaURL(from: pin, sourceURL: sourceURL) else { continue }
            let identity = downloadableIdentity(from: pin, remoteURL: remote)
            guard !seen.contains(identity) else { continue }
            seen.insert(identity)
            let index = assets.count + 1

            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, pin: pin, index: index),
                metadata: assetMetadata(for: remote, pin: pin, sourceURL: sourceURL, index: index),
                referer: pinReferer(pin, sourceURL: sourceURL)
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let resolvedTitle: String
        if case .userCreated = kind(from: sourceURL),
           let creator = nativeCreatorUsername(from: pins.first),
           !creator.isEmpty {
            resolvedTitle = "\(creator)/_created"
        } else {
            resolvedTitle = title
        }
        let clean = resolvedTitle.sanitizedRelativePath(maxComponentLength: 120)
        return ResolvedDownload(
            title: clean,
            folderName: clean,
            assets: assets,
            metadata: pinterestMetadata(pins: pins, title: clean, sourceURL: sourceURL, assets: assets)
        )
    }

    private static func downloadableIdentity(from pin: [String: Any], sourceURL: URL) -> String? {
        guard let remote = mediaURL(from: pin, sourceURL: sourceURL) else { return nil }
        return downloadableIdentity(from: pin, remoteURL: remote)
    }

    private static func downloadableIdentity(from pin: [String: Any], remoteURL: URL) -> String {
        stringValue(pin["id"]).map { "pin:\($0)" } ?? "url:\(URLIdentity.normalize(remoteURL.absoluteString))"
    }

    static func pinterestMetadata(pins: [[String: Any]], title: String, sourceURL: URL, assets: [ResolvedAsset] = []) -> [String: String] {
        let kind = kind(from: sourceURL)
        let firstPin = pins.first
        let user = userName(from: firstPin)
        let pinID = stringValue(firstPin?["id"]) ?? ""
        let date = pinDate(from: firstPin) ?? ""
        let externalSource = pinExternalSource(from: firstPin, sourceURL: sourceURL) ?? ""
        let externalDomain = pinExternalDomain(from: firstPin, externalSource: externalSource) ?? ""
        let pinnerID = pinnerID(from: firstPin)
        let boardName = boardName(from: firstPin)

        let type: String
        let boardUser: String
        let boardSlug: String
        let itemID: String
        switch kind {
        case .pin(let id):
            type = "pin"
            boardUser = ""
            boardSlug = ""
            itemID = id
        case .board(let username, let slug):
            type = "board"
            boardUser = username
            boardSlug = slug
            itemID = "\(username)/\(slug)"
        case .boardSection(let username, let slug, let section):
            type = "section"
            boardUser = username
            boardSlug = slug
            itemID = "\(username)/\(slug)/\(section)"
        case .userCreated(let username):
            type = "created"
            boardUser = username
            boardSlug = ""
            itemID = "\(username)/created"
        case nil:
            type = ""
            boardUser = ""
            boardSlug = ""
            itemID = pinID
        }

        let author = user.isEmpty ? boardUser : user
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        return DownloadMetadata.clean([
            "id": itemID,
            "post_id": type == "pin" ? itemID : pinID,
            "media_id": type == "pin" ? itemID : pinID,
            "artist": author,
            "artist_id": pinnerID,
            "author": author,
            "creator": author,
            "uploader": author,
            "channel": boardUser.isEmpty ? author : boardUser,
            "username": author,
            "series": title,
            "category": type,
            "type": type,
            "media_type": type,
            "pin_id": type == "pin" ? itemID : pinID,
            "board_id": type == "board" || type == "section" ? "\(boardUser)/\(boardSlug)" : "",
            "board_name": boardName,
            "board_slug": boardSlug,
            "section": type == "section" ? itemID.split(separator: "/").last.map(String.init) ?? "" : "",
            "gallery_id": itemID,
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": imageCount > 0 ? String(imageCount) : "",
            "video_count": videoCount > 0 ? String(videoCount) : "",
            "slug": type == "board" ? boardSlug : type == "created" ? "created" : itemID,
            "date": date,
            "published_date": date,
            "source": externalSource,
            "external_url": externalSource,
            "source_domain": externalDomain,
            "url": sourceURL.absoluteString,
            "source_url": sourceURL.absoluteString,
            "page_url": sourceURL.absoluteString,
            "site": "Pinterest",
            "title": title
        ])
    }

    static func resourceURL(resource: String, options: [String: Any], sourceURL: URL) throws -> URL {
        var components = URLComponents(url: baseURL(for: sourceURL), resolvingAgainstBaseURL: false)!
        components.path = "/resource/\(resource)Resource/get/"
        let payload = try JSONSerialization.data(withJSONObject: ["options": options])
        let data = String(data: payload, encoding: .utf8) ?? "{}"
        components.queryItems = [
            URLQueryItem(name: "data", value: data),
            URLQueryItem(name: "source_url", value: "")
        ]
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(sourceURL.absoluteString)
        }
        return url
    }

    private static func expandedShortURL(_ url: URL, headers: HTTPRequestOptions) async throws -> URL {
        guard let response = try await HTTPClient.shared.head(
            from: url,
            referer: headers.referer,
            userAgent: headers.userAgent
        ),
              let finalURL = response.url,
              finalURL.absoluteString != url.absoluteString,
              kind(from: finalURL) != nil else {
            throw NativeDownloadError.unsupported("Pinterest short link did not resolve to a supported Pinterest URL.")
        }
        return finalURL
    }

    static func kind(from url: URL) -> PinterestKind? {
        guard let host = url.host?.lowercased(),
              isPinterestHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        if let pinIndex = parts.firstIndex(where: { $0.lowercased() == "pin" }),
           pinIndex + 1 < parts.count {
            let component = parts[pinIndex + 1]
            if let id = pinterestPinID(fromPathComponent: component) {
                return .pin(id: id)
            }
        }

        guard parts.count >= 2 else { return nil }
        let username = parts[0]
        let slug = parts[1]
            .removingPercentEncoding?
            .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) ?? parts[1]
        guard !username.isEmpty,
              !slug.isEmpty,
              !["pin", "search", "ideas", "today", "settings"].contains(username.lowercased()) else {
            return nil
        }
        if ["_created", "created"].contains(slug.lowercased()) {
            return .userCreated(username: username)
        }
        if parts.count >= 3 {
            let section = parts[2]
                .removingPercentEncoding?
                .trimmingCharacters(in: CharacterSet(charactersIn: "/").union(.whitespacesAndNewlines)) ?? parts[2]
            if !section.isEmpty,
               !["pins", "created", "followers", "following", "activity"].contains(section.lowercased()) {
                return .boardSection(username: username, slug: slug, section: section)
            }
        }
        return .board(username: username, slug: slug)
    }

    static func pinterestPinID(fromPathComponent rawComponent: String) -> String? {
        let component = rawComponent.removingPercentEncoding ?? rawComponent
        if component.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
            return component
        }
        guard let regex = try? NSRegularExpression(pattern: #"--([0-9]+)$"#),
              let match = regex.firstMatch(
                in: component,
                range: NSRange(component.startIndex..<component.endIndex, in: component)
              ),
              let idRange = Range(match.range(at: 1), in: component) else {
            return nil
        }
        return String(component[idRange])
    }

    static func mediaURL(from pin: [String: Any], sourceURL: URL) -> URL? {
        if let video = videoURL(from: pin, sourceURL: sourceURL) {
            return video
        }
        if let image = imageURL(from: pin, sourceURL: sourceURL) {
            return image
        }
        return nil
    }

    static func imageURL(from pin: [String: Any], sourceURL: URL) -> URL? {
        if let images = pin["images"] as? [String: Any] {
            let candidates = imageCollectionCandidates(images, sourceURL: sourceURL)
            if let best = candidates.max(by: { $0.score < $1.score })?.url {
                return best
            }
        }

        if let image = pin["image"] as? [String: Any] {
            var candidates: [(url: URL, score: Int)] = []
            collectImageCandidates(in: image, sourceURL: sourceURL, depth: 0, candidates: &candidates)
            if let best = candidates.max(by: { $0.score < $1.score })?.url {
                return best
            }
        }

        if let raw = stringValue(pin["image"]) ?? stringValue(pin["url"]) {
            return absoluteURL(raw, baseURL: sourceURL)
        }

        var candidates: [(url: URL, score: Int)] = []
        for container in mediaContainers(from: pin) {
            collectImageCandidates(in: container, sourceURL: sourceURL, depth: 0, candidates: &candidates)
        }
        return candidates.max { $0.score < $1.score }?.url
    }

    private static func collectImageCandidates(in value: Any?, sourceURL: URL, depth: Int, candidates: inout [(url: URL, score: Int)]) {
        guard let value, depth < 8 else { return }

        if let item = value as? [String: Any] {
            if let images = item["images"] as? [String: Any] {
                candidates.append(contentsOf: imageCollectionCandidates(images, sourceURL: sourceURL))
            }

            if let raw = stringValue(in: item, keys: [
                "url", "src", "source",
                "image_url", "imageUrl",
                "content_url", "contentUrl",
                "download_url", "downloadUrl"
            ]),
               let url = absoluteURL(raw, baseURL: sourceURL),
               isImageMediaURL(url) {
                candidates.append((url, scoreImageCandidate(url: url, item: item, key: "")))
            }

            for key in item.keys.sorted() {
                guard let child = item[key] else { continue }
                collectImageCandidates(in: child, sourceURL: sourceURL, depth: depth + 1, candidates: &candidates)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectImageCandidates(in: child, sourceURL: sourceURL, depth: depth + 1, candidates: &candidates)
            }
        }
    }

    private static func imageCollectionCandidates(_ images: [String: Any], sourceURL: URL) -> [(url: URL, score: Int)] {
        var candidates: [(url: URL, score: Int)] = []
        for key in ["orig", "originals", "original", "1200x", "736x", "564x", "474x", "236x"] {
            guard let value = images[key],
                  let candidate = imageCandidate(from: value, key: key, sourceURL: sourceURL) else {
                continue
            }
            candidates.append(candidate)
        }
        for key in images.keys.sorted() {
            guard let value = images[key],
                  let candidate = imageCandidate(from: value, key: key, sourceURL: sourceURL) else {
                continue
            }
            candidates.append(candidate)
        }
        return candidates
    }

    private static func imageCandidate(from value: Any, key: String, sourceURL: URL) -> (url: URL, score: Int)? {
        let image = value as? [String: Any] ?? [:]
        let raw = stringValue(in: image, keys: ["url", "src", "source", "image_url", "imageUrl", "content_url", "contentUrl"]) ??
            stringValue(value)
        guard let raw,
              let url = absoluteURL(raw, baseURL: sourceURL),
              isImageMediaURL(url) else {
            return nil
        }
        return (url, scoreImageCandidate(url: url, item: image, key: key))
    }

    private static func scoreImageCandidate(url: URL, item: [String: Any], key: String) -> Int {
        let label = key.lowercased()
        let preferred = ["orig", "original", "originals"].contains(label) || url.path.lowercased().contains("/originals/") ? 100_000_000 : 0
        let width = intValue(item["width"]) ?? intValue(item["orig_width"]) ?? 0
        let height = intValue(item["height"]) ?? intValue(item["orig_height"]) ?? 0
        return preferred + width * height
    }

    private static func isImageMediaURL(_ url: URL) -> Bool {
        let lowerPath = url.path.lowercased()
        return ["jpg", "jpeg", "png", "gif", "webp", "avif"].contains(url.pathExtension.lowercased()) ||
            [".jpg", ".jpeg", ".png", ".gif", ".webp", ".avif"].contains { lowerPath.contains($0) }
    }

    static func videoURL(from pin: [String: Any], sourceURL: URL) -> URL? {
        var candidates: [(url: URL, score: Int)] = []
        for container in mediaContainers(from: pin) {
            collectVideoCandidates(in: container, sourceURL: sourceURL, depth: 0, candidates: &candidates)
        }

        return candidates.max { $0.score < $1.score }?.url
    }

    private static func collectVideoCandidates(in value: Any?, sourceURL: URL, depth: Int, candidates: inout [(url: URL, score: Int)]) {
        guard let value, depth < 8 else { return }
        if let listObject = videoList(from: value) {
            appendVideoListCandidates(listObject, sourceURL: sourceURL, candidates: &candidates)
        }

        if let item = value as? [String: Any] {
            if let raw = stringValue(in: item, keys: [
                "url", "src", "source",
                "video_url", "videoUrl",
                "content_url", "contentUrl",
                "download_url", "downloadUrl",
                "hls_url", "hlsUrl"
            ]),
               let url = absoluteURL(raw, baseURL: sourceURL),
               isVideoMediaURL(url) {
                candidates.append((url, scoreVideoCandidate(url: url, item: item)))
            }
            for key in item.keys.sorted() {
                guard let child = item[key] else { continue }
                collectVideoCandidates(in: child, sourceURL: sourceURL, depth: depth + 1, candidates: &candidates)
            }
        } else if let array = value as? [Any] {
            for child in array {
                collectVideoCandidates(in: child, sourceURL: sourceURL, depth: depth + 1, candidates: &candidates)
            }
        }
    }

    private static func videoList(from value: Any) -> [String: Any]? {
        guard let videos = value as? [String: Any] else { return nil }
        return videos["video_list"] as? [String: Any] ??
            videos["videoList"] as? [String: Any] ??
            videos["video_list_v2"] as? [String: Any] ??
            videos["videoListV2"] as? [String: Any] ??
            videos["list"] as? [String: Any]
    }

    private static func appendVideoListCandidates(_ listObject: [String: Any], sourceURL: URL, candidates: inout [(url: URL, score: Int)]) {
        for value in listObject.values {
            guard let item = value as? [String: Any],
                  let raw = stringValue(item["url"]) ?? stringValue(item["src"]),
                  let url = absoluteURL(raw, baseURL: sourceURL) else {
                continue
            }
            candidates.append((url, scoreVideoCandidate(url: url, item: item)))
        }
    }

    private static func scoreVideoCandidate(url: URL, item: [String: Any]) -> Int {
        let ext = url.pathExtension.lowercased()
        let isPreferred = ext == "mp4" ? 10_000_000 : ext == "m3u8" ? 1_000_000 : 0
        let width = intValue(item["width"]) ?? 0
        let height = intValue(item["height"]) ?? 0
        let bitrate = intValue(item["bitrate"]) ?? intValue(item["bit_rate"]) ?? 0
        let duration = intValue(item["duration"]) ?? intValue(item["durationMs"]) ?? intValue(item["duration_ms"]) ?? 0
        let quality = stringValue(item["quality"])?.lowercased() ?? ""
        let qualityScore = quality.contains("original") ? 500_000 :
            quality.contains("high") ? 250_000 :
            quality.contains("medium") ? 100_000 : 0
        return isPreferred + width * height + bitrate + min(duration, 300_000) + qualityScore
    }

    private static func isVideoMediaURL(_ url: URL) -> Bool {
        let lowerPath = url.path.lowercased()
        return ["mp4", "m4v", "mov", "webm", "m3u8"].contains(url.pathExtension.lowercased()) ||
            [".mp4", ".m4v", ".mov", ".webm", ".m3u8"].contains { lowerPath.contains($0) }
    }

    static func resourceData(from data: Data) throws -> [String: Any] {
        let object = try jsonObject(from: data)
        return try resourceData(from: object)
    }

    static func resourceData(from object: [String: Any]) throws -> [String: Any] {
        if let response = object["resource_response"] as? [String: Any],
           let data = response["data"] as? [String: Any] {
            return data
        }
        if let data = object["data"] as? [String: Any] {
            return data
        }
        if !object.isEmpty {
            return object
        }
        throw NativeDownloadError.invalidGalleryData
    }

    static func resourceDataArray(from object: [String: Any]) -> [[String: Any]] {
        if let response = object["resource_response"] as? [String: Any],
           let data = resourceArray(from: response["data"]) {
            return data
        }
        if let response = object["resource_response"] as? [String: Any],
           let data = response["data"] as? [String: Any],
           let sections = data["sections"] as? [[String: Any]] {
            return sections
        }
        if let data = resourceArray(from: object["data"]) {
            return data
        }
        if let data = object["data"] as? [String: Any],
           let sections = data["sections"] as? [[String: Any]] {
            return sections
        }
        return []
    }

    private static func resourceArray(from value: Any?) -> [[String: Any]]? {
        if let array = value as? [[String: Any]] {
            return array
        }
        guard let dictionary = value as? [String: Any] else {
            return nil
        }
        for key in ["results", "items", "pins", "edges", "nodes", "sections"] {
            if let array = dictionary[key] as? [[String: Any]] {
                return array
            }
        }
        return nil
    }

    static func boardSection(in sections: [[String: Any]], matching slug: String) -> [String: Any]? {
        let target = normalizedSectionSlug(slug)
        return sections.first { section in
            let candidates = [
                stringValue(section["slug"]),
                stringValue(section["url_name"]),
                stringValue(section["name"]),
                stringValue(section["title"]),
                stringValue(section["id"])
            ]
            return candidates.contains { value in
                value.map(normalizedSectionSlug) == target
            }
        }
    }

    static func bookmarks(from object: [String: Any]) -> [String]? {
        if let resource = object["resource"] as? [String: Any],
           let options = resource["options"] as? [String: Any],
           let bookmarks = options["bookmarks"] as? [String] {
            return bookmarks
        }
        if let response = object["resource_response"] as? [String: Any],
           let bookmarks = response["bookmark"] as? [String] {
            return bookmarks
        }
        if let response = object["resource_response"] as? [String: Any],
           let data = response["data"] as? [String: Any],
           let bookmarks = data["bookmark"] as? [String] ?? data["bookmarks"] as? [String] {
            return bookmarks
        }
        if let data = object["data"] as? [String: Any],
           let bookmarks = data["bookmark"] as? [String] ?? data["bookmarks"] as? [String] {
            return bookmarks
        }
        return nil
    }

    private static func pinTitle(from pin: [String: Any]) -> String? {
        stringValue(pin["title"]) ??
            stringValue(pin["grid_title"]) ??
            stringValue(pin["description"]) ??
            stringValue(pin["id"]).map { "Pinterest Pin \($0)" }
    }

    private static func userName(from pin: [String: Any]?) -> String {
        guard let pin else { return "" }
        if let creator = nativeCreatorUsername(from: pin), !creator.isEmpty {
            return creator
        }
        if let pinner = pin["pinner"] as? [String: Any] {
            return stringValue(pinner["username"]) ??
                stringValue(pinner["full_name"]) ??
                stringValue(pinner["name"]) ??
                ""
        }
        if let board = pin["board"] as? [String: Any] {
            return stringValue(board["owner_username"]) ??
                stringValue(board["username"]) ??
                stringValue(board["name"]) ??
                ""
        }
        return stringValue(pin["pinner_username"]) ??
            stringValue(pin["username"]) ??
            ""
    }

    private static func nativeCreatorUsername(from pin: [String: Any]?) -> String? {
        guard let pin else { return nil }
        let creator = pin["native_creator"] as? [String: Any] ??
            pin["nativeCreator"] as? [String: Any]
        return stringValue(creator?["username"]) ??
            stringValue(creator?["name"]) ??
            stringValue(creator?["full_name"])
    }

    private static func pinnerID(from pin: [String: Any]?) -> String {
        guard let pin else { return "" }
        if let creator = pin["native_creator"] as? [String: Any] ?? pin["nativeCreator"] as? [String: Any] {
            return stringValue(creator["id"]) ?? stringValue(creator["uid"]) ?? ""
        }
        if let pinner = pin["pinner"] as? [String: Any] {
            return stringValue(pinner["id"]) ?? stringValue(pinner["uid"]) ?? ""
        }
        return stringValue(pin["pinner_id"]) ?? stringValue(pin["user_id"]) ?? ""
    }

    private static func boardName(from pin: [String: Any]?) -> String {
        guard let board = pin?["board"] as? [String: Any] else { return "" }
        return stringValue(board["name"]) ??
            stringValue(board["title"]) ??
            stringValue(board["slug"]) ??
            ""
    }

    private static func boardOwnerUsername(from board: [String: Any], fallback: String) -> String {
        if let owner = board["owner"] as? [String: Any] {
            return stringValue(owner["username"]) ??
                stringValue(owner["name"]) ??
                fallback
        }
        return stringValue(board["owner_username"]) ??
            stringValue(board["username"]) ??
            fallback
    }

    private static func pinDate(from pin: [String: Any]?) -> String? {
        let keys = ["created_at", "createdAt", "created_time", "createdTime", "date", "published_at", "publishedAt"]
        let raw = stringValue(in: pin, keys: keys) ??
            stringValue(in: pin?["rich_metadata"] as? [String: Any], keys: keys) ??
            stringValue(in: pin?["metadata"] as? [String: Any], keys: keys)
        return normalizedDate(raw)
    }

    private static func pinExternalSource(from pin: [String: Any]?, sourceURL: URL) -> String? {
        let keys = ["link", "external_link", "click_through_link", "tracked_link", "destination_url", "source_url"]
        let raw = stringValue(in: pin, keys: keys) ??
            stringValue(in: pin?["rich_metadata"] as? [String: Any], keys: ["url", "link", "source_url"]) ??
            stringValue(in: pin?["metadata"] as? [String: Any], keys: keys)
        guard let raw, !raw.trimmed.isEmpty else { return nil }
        return absoluteURL(raw, baseURL: sourceURL)?.absoluteString ?? raw.trimmed
    }

    private static func pinExternalDomain(from pin: [String: Any]?, externalSource: String) -> String? {
        let raw = stringValue(in: pin, keys: ["domain", "link_domain", "source_domain"]) ??
            stringValue(in: pin?["rich_metadata"] as? [String: Any], keys: ["site_name", "domain"]) ??
            stringValue(in: pin?["metadata"] as? [String: Any], keys: ["domain", "site_name"])
        if let raw, !raw.trimmed.isEmpty {
            return raw.trimmed
        }
        guard let url = URL(string: externalSource) else { return nil }
        return url.host
    }

    private static func normalizedDate(_ raw: String?) -> String? {
        guard let value = raw?.trimmed, !value.isEmpty else { return nil }
        if let match = value.range(of: #"[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) {
            return String(value[match])
        }
        if value.range(of: #"^[0-9]{8}$"#, options: .regularExpression) != nil {
            let monthStart = value.index(value.startIndex, offsetBy: 4)
            let dayStart = value.index(value.startIndex, offsetBy: 6)
            return "\(value.prefix(4))-\(value[monthStart..<dayStart])-\(value[dayStart..<value.endIndex])"
        }
        return nil
    }

    private static func stringValue(in dictionary: [String: Any]?, keys: [String]) -> String? {
        guard let dictionary else { return nil }
        for key in keys {
            if let value = stringValue(dictionary[key]), !value.trimmed.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func mediaContainers(from pin: [String: Any]) -> [Any] {
        [
            pin["videos"],
            pin["video"],
            pin["videoData"],
            pin["story_pin_data"],
            pin["storyPinData"],
            pin["media"],
            pin["native_pin_media"],
            pin["nativePinMedia"],
            pin["aggregated_pin_data"],
            pin["aggregatedPinData"]
        ].compactMap { $0 }
    }

    private static func sectionTitle(from section: [String: Any], fallback: String) -> String {
        stringValue(section["name"]) ??
            stringValue(section["title"]) ??
            stringValue(section["slug"]) ??
            fallback
    }

    private static func normalizedSectionSlug(_ raw: String) -> String {
        (raw.removingPercentEncoding ?? raw)
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "\\s+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-/").union(.whitespacesAndNewlines))
    }

    private static func filename(for url: URL, pin: [String: Any], index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        let id = stringValue(pin["id"]) ?? String(format: "%04d", index)
        return "\(id).\(ext)".sanitizedFilename(maxLength: 160)
    }

    private static func assetMetadata(for url: URL, pin: [String: Any], sourceURL: URL, index: Int) -> [String: String] {
        let type = mediaType(for: url)
        let format = mediaFormat(for: url)
        let pinID = stringValue(pin["id"]) ?? ""
        let author = userName(from: pin)
        let externalSource = pinExternalSource(from: pin, sourceURL: sourceURL) ?? ""
        let externalDomain = pinExternalDomain(from: pin, externalSource: externalSource) ?? ""
        return DownloadMetadata.clean([
            "type": type,
            "media_type": type,
            "category": type == "video" ? "video" : "image",
            "format": format,
            "media_format": format,
            "id": pinID,
            "pin_id": pinID,
            "post_id": pinID,
            "media_id": pinID,
            "gallery_id": pinID,
            "page": String(index),
            "position": String(index),
            "artist": author,
            "author": author,
            "creator": author,
            "uploader": author,
            "username": author,
            "date": pinDate(from: pin) ?? "",
            "published_date": pinDate(from: pin) ?? "",
            "source": externalSource,
            "external_url": externalSource,
            "source_domain": externalDomain,
            "image_url": type == "image" ? url.absoluteString : "",
            "video_url": type == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": pinReferer(pin, sourceURL: sourceURL)
        ])
    }

    private static func mediaType(for url: URL) -> String {
        ["mp4", "m4v", "mov", "webm", "m3u8"].contains(mediaFormat(for: url)) ? "video" : "image"
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["jpg", "jpeg", "png", "gif", "webp", "avif", "mp4", "m4v", "mov", "webm", "m3u8"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func pinReferer(_ pin: [String: Any], sourceURL: URL) -> String {
        if let id = stringValue(pin["id"]) {
            return "\(baseURL(for: sourceURL).absoluteString)/pin/\(id)/"
        }
        return sourceURL.absoluteString
    }

    private static func pinterestHeaders(sourceURL: URL) -> [String: String] {
        let base = baseURL(for: sourceURL).absoluteString
        return [
            "Accept": "application/json, text/javascript, */*, q=0.01",
            "Accept-Language": "en-US,en;q=0.5",
            "X-Requested-With": "XMLHttpRequest",
            "X-APP-VERSION": "31461e0",
            "X-Pinterest-PWS-Handler": resourceHandlerHeaderValue,
            "X-Pinterest-AppState": "active",
            "Origin": base
        ]
    }

    private static func baseURL(for sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.pinterest.test" : "www.pinterest.com"
        return components.url!
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func isPinterestHost(_ host: String) -> Bool {
        if host == "pinterest.test" || host.hasSuffix(".pinterest.test") {
            return true
        }

        let labels = host.split(separator: ".").map { String($0) }
        guard let index = labels.lastIndex(of: "pinterest") else { return false }
        let suffix = Array(labels.dropFirst(index + 1))
        if suffix.count == 1 {
            let tld = suffix[0]
            return tld == "com" || (tld.count == 2 && tld.allSatisfy(\.isLetter))
        }
        if suffix.count == 2 {
            let service = suffix[0]
            let country = suffix[1]
            return ["co", "com", "net", "org"].contains(service) &&
                country.count == 2 &&
                country.allSatisfy(\.isLetter)
        }
        return false
    }

    private static func isPinterestShortURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased(),
              ["pin.it", "www.pin.it", "pin.it.test", "www.pin.it.test"].contains(host) else {
            return false
        }
        return !url.path.split(separator: "/").isEmpty
    }
}
