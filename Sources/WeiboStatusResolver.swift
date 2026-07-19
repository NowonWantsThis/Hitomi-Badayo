import Foundation

final class WeiboStatusResolver {
    func canResolve(_ url: URL) -> Bool {
        Self.statusID(from: url) != nil || Self.profileID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        if let statusID = Self.statusID(from: url) {
            let data = try await HTTPClient.shared.data(
                from: Self.statusAPIURL(statusID: statusID, sourceURL: url),
                referer: headers.referer ?? url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
            return try Self.resolvedDownload(fromAPIData: data, pageURL: url, statusID: statusID)
        }

        guard let profileID = Self.profileID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        return try await resolveProfile(
            profileID: profileID,
            sourceURL: url,
            headers: headers,
            assetLimit: assetLimit
        )
    }

    private func resolveProfile(
        profileID initialProfileID: String,
        sourceURL url: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        var profileID = initialProfileID
        var profileName = Self.profileName(from: url) ?? initialProfileID
        if !Self.isNumericID(profileID) {
            let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
            guard let resolvedID = Self.profileID(fromHTML: html) else {
                throw NativeDownloadError.unsupported("Weibo profile id could not be found.")
            }
            profileID = resolvedID
            profileName = Self.profileName(fromHTML: html) ?? profileName
        }

        var statuses: [[String: Any]] = []
        var seenStatusIDs = Set<String>()
        var sinceID = "0"
        var seenSinceIDs = Set<String>()
        var pageCount = 0
        var listedStatusCount = 0
        var resolvedStatusCount = 0
        var resolvedMediaCount = 0
        let albumReferer = Self.profileAlbumReferer(profileID: profileID, sourceURL: url)

        while true {
            try Task.checkCancellation()
            let apiURL = Self.imageWallAPIURL(uid: profileID, sinceID: sinceID, sourceURL: url)
            let data = try await HTTPClient.shared.data(
                from: apiURL,
                referer: headers.referer ?? albumReferer,
                userAgent: headers.userAgent,
                additionalHeaders: ["Accept": "application/json, text/plain, */*"]
            )
            pageCount += 1
            let object = try Self.jsonObject(from: data)
            let pageStatuses = Self.imageWallStatuses(from: object)

            for summary in pageStatuses {
                try Task.checkCancellation()
                guard let statusID = Self.statusID(fromStatusDictionary: summary),
                      seenStatusIDs.insert(statusID).inserted else {
                    continue
                }
                listedStatusCount += 1

                let detailData = try await HTTPClient.shared.data(
                    from: Self.statusAPIURL(statusID: statusID, sourceURL: url),
                    referer: headers.referer ?? albumReferer,
                    userAgent: headers.userAgent,
                    additionalHeaders: ["Accept": "application/json, text/plain, */*"]
                )
                let detailObject = try Self.jsonObject(from: detailData)
                if let ok = Self.integerValue(detailObject["ok"]), ok != 1 {
                    continue
                }
                let status = Self.statusDictionary(from: detailObject)
                let mediaCount = Self.mediaURLs(from: status, pageURL: url).count
                guard mediaCount > 0 else { continue }
                statuses.append(status)
                resolvedStatusCount += 1
                resolvedMediaCount += mediaCount
            }

            if let assetLimit, assetLimit > 0, resolvedMediaCount >= assetLimit {
                break
            }
            guard let nextSinceID = Self.imageWallSinceID(from: object),
                  !nextSinceID.isEmpty,
                  nextSinceID != "0",
                  seenSinceIDs.insert(nextSinceID).inserted else {
                break
            }
            sinceID = nextSinceID
        }

        var resolved = try Self.resolvedProfileDownload(
            statuses: statuses,
            pageURL: url,
            profileID: profileID,
            profileName: profileName
        )
        resolved.metadata["collection_page_count"] = String(pageCount)
        resolved.metadata["listed_status_count"] = String(listedStatusCount)
        resolved.metadata["resolved_status_count"] = String(resolvedStatusCount)
        resolved.metadata["resolved_media_count"] = String(resolved.assets.count)
        return resolved
    }

    static func statusID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if let statusIndex = lower.firstIndex(of: "status"),
           statusIndex + 1 < parts.count,
           isValidID(parts[statusIndex + 1]) {
            return parts[statusIndex + 1]
        }

        if let detailIndex = lower.firstIndex(of: "detail"),
           detailIndex + 1 < parts.count,
           isValidID(parts[detailIndex + 1]) {
            return parts[detailIndex + 1]
        }

        if lower.count >= 3,
           lower[0] == "tv",
           lower[1] == "show",
           isValidID(parts[2]) {
            return parts[2]
        }

        if parts.count >= 2,
           isNumericID(parts[0]),
           isValidID(parts[1]) {
            return parts[1]
        }

        return nil
    }

    static func statusAPIURL(statusID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "weibo.test" : "weibo.com"
        components.path = "/ajax/statuses/show"
        components.queryItems = [URLQueryItem(name: "id", value: statusID)]
        return components.url!
    }

    static func canonicalInputURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = canonicalInputHost(for: host)

        if statusID(from: url) != nil {
            if let marker = lower.firstIndex(of: "status"),
               marker + 1 < parts.count {
                components.path = "/" + parts[0...(marker + 1)].joined(separator: "/")
            } else if let marker = lower.firstIndex(of: "detail"),
                      marker + 1 < parts.count {
                components.path = "/" + parts[0...(marker + 1)].joined(separator: "/")
            } else if lower.count >= 3,
                      lower[0] == "tv",
                      lower[1] == "show" {
                components.path = "/tv/show/\(parts[2])"
            } else if parts.count >= 2,
                      isNumericID(parts[0]),
                      isValidID(parts[1]) {
                components.path = "/\(parts[0])/\(parts[1])"
            } else {
                return nil
            }
            return components.url
        }

        guard let profileID = profileID(from: url) else {
            return nil
        }
        if lower.count >= 2,
           lower[0] == "p" || lower[0] == "u" {
            components.path = "/\(lower[0])/\(profileID)"
        } else if parts.count == 1 {
            components.path = "/\(profileID)"
        } else {
            components.path = "/u/\(profileID)"
        }
        return components.url
    }

    static func profileID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isSupportedHost(host),
              !isSinaHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              statusID(from: url) == nil else {
            return nil
        }

        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["uid", "id", "profile_id", "profileId"] {
            if let value = items.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isValidID(value) {
                return value
            }
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.count >= 2,
           ["u", "p"].contains(lower[0]),
           isValidID(parts[1]) {
            return parts[1]
        }
        if parts.count == 1,
           isValidProfileSlug(parts[0]) {
            return parts[0]
        }
        return nil
    }

    static func imageWallAPIURL(uid: String, sinceID: String = "0", sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "weibo.test" : "weibo.com"
        components.path = "/ajax/profile/getImageWall"
        var queryItems = [
            URLQueryItem(name: "uid", value: uid),
            URLQueryItem(name: "sinceid", value: sinceID)
        ]
        if sinceID == "0" {
            queryItems.append(URLQueryItem(name: "has_album", value: "true"))
        }
        components.queryItems = queryItems
        return components.url!
    }

    static func profileAlbumReferer(profileID: String, sourceURL: URL) -> String {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "weibo.test" : "weibo.com"
        components.path = "/u/\(profileID)"
        components.queryItems = [URLQueryItem(name: "tabtype", value: "album")]
        return components.url!.absoluteString
    }

    static func resolvedDownload(fromAPIData data: Data, pageURL: URL, statusID: String) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let status = statusDictionary(from: object)
        let info = statusInfo(from: status, fallbackID: statusID)
        let media = mediaURLs(from: status, pageURL: pageURL)
        guard !media.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let assets = media.enumerated().map { index, item in
            let position = index + 1
            return ResolvedAsset(
                remoteURL: item.url,
                filename: originalProfileFilename(
                    for: item.url,
                    statusID: statusID,
                    mediaIndex: index,
                    date: info.date
                ),
                metadata: assetMetadata(
                    for: item,
                    statusID: statusID,
                    title: info.title,
                    user: info.user,
                    date: info.date,
                    index: position,
                    position: position,
                    pageURL: pageURL
                ),
                referer: pageURL.absoluteString
            )
        }
        let imageCount = media.filter { $0.kind == .image }.count
        let videoCount = media.filter { $0.kind == .video }.count
        return ResolvedDownload(
            title: info.title,
            folderName: "Weibo \(info.folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Weibo",
                "title": info.title,
                "series": info.title,
                "category": media.contains(where: { $0.kind == .video }) ? "video" : "image",
                "type": "status",
                "media_type": "status",
                "host": pageURL.host ?? "",
                "id": statusID,
                "status_id": statusID,
                "gallery_id": statusID,
                "media_count": String(assets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "video_count": videoCount > 0 ? String(videoCount) : "",
                "artist": info.user,
                "author": info.user,
                "creator": info.user,
                "user": info.user,
                "username": info.user,
                "uploader": info.user,
                "channel": info.user,
                "date": info.date,
                "thumbnail": media.first(where: { $0.kind == .image })?.url.absoluteString ?? "",
                "url": pageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ])
        )
    }

    static func resolvedProfileDownload(statuses: [[String: Any]], pageURL: URL, profileID: String, profileName: String) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var statusCount = 0
        let albumReferer = profileAlbumReferer(profileID: profileID, sourceURL: pageURL)

        for status in statuses {
            let statusID = statusID(fromStatusDictionary: status) ?? String(statusCount + 1)
            let media = mediaURLs(from: status, pageURL: pageURL)
            guard !media.isEmpty else { continue }
            statusCount += 1
            let info = statusInfo(from: status, fallbackID: statusID)
            let statusUser = info.user.isEmpty ? profileName : info.user
            for (index, item) in media.enumerated() {
                let position = assets.count + 1
                assets.append(ResolvedAsset(
                    remoteURL: item.url,
                    filename: originalProfileFilename(
                        for: item.url,
                        statusID: statusID,
                        mediaIndex: index,
                        date: info.date
                    ),
                    metadata: assetMetadata(
                        for: item,
                        statusID: statusID,
                        title: info.title,
                        user: statusUser,
                        date: info.date,
                        index: index + 1,
                        position: position,
                        pageURL: pageURL,
                        profileID: profileID
                    ),
                    referer: albumReferer
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let detailName = statuses.lazy
            .map { statusInfo(from: $0, fallbackID: profileID).user }
            .first { !$0.isEmpty }
        let preferredName = profileName == profileID ? detailName ?? profileName : profileName
        let cleanName = cleanTitle(preferredName, fallback: profileID)
        let title = "\(cleanName) (weibo_\(profileID))"
        let imageCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "image" }.count
        let videoCount = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }.count
        return ResolvedDownload(
            title: title.sanitizedFilename(maxLength: 120),
            folderName: title.sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "Weibo",
                "title": title,
                "series": cleanName,
                "category": assets.contains(where: { ["mp4", "mov", "m4v", "webm"].contains($0.remoteURL.pathExtension.lowercased()) }) ? "video" : "image",
                "type": "profile",
                "media_type": "profile",
                "host": pageURL.host ?? "",
                "id": profileID,
                "profile_id": profileID,
                "user_id": profileID,
                "uid": profileID,
                "gallery_id": profileID,
                "artist": cleanName,
                "author": cleanName,
                "creator": cleanName,
                "uploader": cleanName,
                "username": cleanName,
                "user": cleanName,
                "channel": cleanName,
                "status_count": String(statusCount),
                "media_count": String(assets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "video_count": videoCount > 0 ? String(videoCount) : "",
                "thumbnail": assets.first?.remoteURL.absoluteString ?? "",
                "url": pageURL.absoluteString,
                "source_url": pageURL.absoluteString,
                "page_url": pageURL.absoluteString
            ])
        )
    }

    static func mediaURLs(from status: [String: Any], pageURL: URL) -> [(kind: MediaKind, url: URL)] {
        var media: [(kind: MediaKind, url: URL)] = []
        var seen = Set<String>()

        func append(_ kind: MediaKind, raw: String?) {
            guard let raw,
                  let url = absoluteURL(raw, baseURL: pageURL),
                  kind.isSupported(url) else {
                return
            }
            let key = url.absoluteString
            guard !seen.contains(key) else { return }
            seen.insert(key)
            media.append((kind, url))
        }

        for raw in imageURLs(fromPicInfos: status["pic_infos"]) {
            append(.image, raw: raw)
        }
        for raw in imageURLs(fromPicsArray: status["pics"]) {
            append(.image, raw: raw)
        }
        if let mix = status["mix_media_info"] {
            for raw in imageURLsRecursively(in: mix) {
                append(.image, raw: raw)
            }
        }

        for raw in videoURLsRecursively(in: status) {
            append(.video, raw: raw)
        }

        return media
    }

    enum MediaKind {
        case image
        case video

        func isSupported(_ url: URL) -> Bool {
            switch self {
            case .image:
                return ["jpg", "jpeg", "png", "webp", "gif"].contains(url.pathExtension.lowercased())
            case .video:
                return ["mp4", "mov", "m4v", "webm"].contains(url.pathExtension.lowercased()) ||
                    url.absoluteString.lowercased().contains(".mp4")
            }
        }
    }

    private static func statusDictionary(from object: [String: Any]) -> [String: Any] {
        if let data = object["data"] as? [String: Any] {
            return data
        }
        if let status = object["status"] as? [String: Any] {
            return status
        }
        return object
    }

    static func imageWallStatuses(from object: [String: Any]) -> [[String: Any]] {
        let root = object["data"] as? [String: Any] ?? object
        let list = root["list"] as? [Any] ??
            root["statuses"] as? [Any] ??
            root["cards"] as? [Any] ??
            []
        return list.compactMap { item in
            guard let dictionary = item as? [String: Any] else { return nil }
            for key in ["mblog", "status", "blog", "data"] {
                if let nested = dictionary[key] as? [String: Any],
                   isStatusLikeDictionary(nested) || statusID(fromStatusDictionary: nested) != nil {
                    return nested
                }
            }
            return dictionary
        }
    }

    static func imageWallSinceID(from object: [String: Any]) -> String? {
        let root = object["data"] as? [String: Any] ?? object
        return stringValue(root["since_id"]) ??
            stringValue(root["sinceid"]) ??
            stringValue(root["next_since_id"]) ??
            stringValue(root["nextSinceId"])
    }

    static func profileID(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"CONFIG\[['"]page_id['"]\]\s*=\s*['"]([0-9]+)['"]"#,
            #"/u/page/follow/([0-9]+)"#,
            #"[?&]uid=([0-9]+)"#,
            #""uid"\s*:\s*"?([0-9]+)"?"#
        ], in: html)
    }

    static func profileName(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"CONFIG\[['"]onick['"]\]\s*=\s*['"](.+?)['"]"#,
            #"<[^>]*class\s*=\s*["'][^"']*ProfileHeader_name[^"']*["'][^>]*>(.*?)</[^>]+>"#,
            #"<title[^>]*>(.*?)</title>"#
        ], in: html).map { cleanTitle($0, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 }
    }

    private static func statusInfo(from status: [String: Any], fallbackID: String) -> (title: String, folderTitle: String, user: String, date: String) {
        let rawTitle = stringValue(status["text_raw"]) ??
            stringValue(status["text"]) ??
            stringValue(status["title"]) ??
            "Weibo \(fallbackID)"
        let title = cleanTitle(rawTitle, fallback: "Weibo \(fallbackID)")
        let userObject = status["user"] as? [String: Any] ?? [:]
        let user = cleanTitle(
            stringValue(userObject["screen_name"]) ??
                stringValue(userObject["name"]) ??
                stringValue(status["user_name"]) ??
                "",
            fallback: ""
        )
        let folder = [user, title].filter { !$0.isEmpty }.joined(separator: " - ")
        return (
            title,
            folder.isEmpty ? title : folder,
            user,
            stringValue(status["created_at"]) ?? stringValue(status["date"]) ?? ""
        )
    }

    private static func imageURLs(fromPicInfos value: Any?) -> [String] {
        guard let infos = value as? [String: Any] else { return [] }
        let preferred = ["largest", "original", "mw2000", "large", "bmiddle", "thumbnail"]
        return infos.keys.sorted().compactMap { key in
            guard let info = infos[key] as? [String: Any] else { return nil }
            for sizeKey in preferred {
                if let nested = info[sizeKey] as? [String: Any],
                   let url = stringValue(nested["url"]) {
                    return url
                }
                if let url = stringValue(info[sizeKey]) {
                    return url
                }
            }
            return stringValue(info["url"])
        }
    }

    private static func imageURLs(fromPicsArray value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { item in
            guard let dict = item as? [String: Any] else { return nil }
            return imageURLs(fromPicInfos: ["pic": dict]).first ??
                stringValue(dict["url"])
        }
    }

    private static func imageURLsRecursively(in value: Any) -> [String] {
        var results: [String] = []
        collectImageURLs(in: value, output: &results)
        return results
    }

    private static func collectImageURLs(in value: Any, output: inout [String]) {
        if let array = value as? [Any] {
            for child in array {
                collectImageURLs(in: child, output: &output)
            }
            return
        }
        guard let dict = value as? [String: Any] else {
            if let raw = stringValue(value), isLikelyImageURL(raw) {
                output.append(raw)
            }
            return
        }
        output.append(contentsOf: imageURLs(fromPicInfos: dict["pic_infos"]))
        output.append(contentsOf: imageURLs(fromPicsArray: dict["pics"]))
        for key in ["url", "pic", "pic_url", "original", "large"] {
            if let raw = stringValue(dict[key]), isLikelyImageURL(raw) {
                output.append(raw)
            }
        }
        for key in dict.keys.sorted() {
            if let child = dict[key] {
                collectImageURLs(in: child, output: &output)
            }
        }
    }

    private static func videoURLsRecursively(in value: Any) -> [String] {
        var results: [String] = []
        collectVideoURLs(in: value, output: &results)
        return results
    }

    private static func collectVideoURLs(in value: Any, output: inout [String]) {
        if let array = value as? [Any] {
            for child in array {
                collectVideoURLs(in: child, output: &output)
            }
            return
        }
        guard let dict = value as? [String: Any] else { return }
        for key in ["stream_url_hd", "stream_url", "mp4_hd_url", "mp4_720p_mp4", "mp4_sd_url", "mp4_url", "video_url", "videoUrl"] {
            if let raw = stringValue(dict[key]), isLikelyVideoURL(raw) {
                output.append(raw)
            }
        }
        for key in dict.keys.sorted() {
            if let child = dict[key] {
                collectVideoURLs(in: child, output: &output)
            }
        }
    }

    private static func originalProfileFilename(for url: URL, statusID: String, mediaIndex: Int, date: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "dat" : url.pathExtension
        let datePrefix = originalShortDateToken(date).map { "[\($0)] " } ?? ""
        return "\(datePrefix)\(statusID)_p\(mediaIndex).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func originalShortDateToken(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.range(of: #"^[0-9]{2}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) != nil {
            return String(value.prefix(8))
        }
        if value.range(of: #"^[0-9]{4}-[0-9]{2}-[0-9]{2}"#, options: .regularExpression) != nil {
            return String(value.dropFirst(2).prefix(8))
        }

        let formats = [
            "EEE MMM dd HH:mm:ss Z yyyy",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX"
        ]
        for format in formats {
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = TimeZone(secondsFromGMT: 0)
            parser.dateFormat = format
            guard let date = parser.date(from: value) else { continue }
            let output = DateFormatter()
            output.locale = Locale(identifier: "en_US_POSIX")
            output.timeZone = .current
            output.dateFormat = "yy-MM-dd"
            return output.string(from: date)
        }
        return nil
    }

    private static func assetMetadata(
        for item: (kind: MediaKind, url: URL),
        statusID: String,
        title: String,
        user: String,
        date: String,
        index: Int,
        position: Int,
        pageURL: URL,
        profileID: String? = nil
    ) -> [String: String] {
        let format = mediaFormat(for: item.url)
        let type: String
        switch item.kind {
        case .image:
            type = "image"
        case .video:
            type = "video"
        }
        return DownloadMetadata.clean([
            "site": "Weibo",
            "title": title,
            "type": type,
            "media_type": type,
            "category": type,
            "id": statusID,
            "status_id": statusID,
            "gallery_id": profileID ?? statusID,
            "profile_id": profileID ?? "",
            "media_id": "\(statusID)-\(index)",
            "page": String(index),
            "position": String(position),
            "format": format,
            "media_format": format,
            "artist": user,
            "author": user,
            "creator": user,
            "user": user,
            "username": user,
            "uploader": user,
            "channel": user,
            "date": date,
            "image_url": item.kind == .image ? item.url.absoluteString : "",
            "video_url": item.kind == .video ? item.url.absoluteString : "",
            "media_url": item.url.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty {
            return pathExtension
        }
        let lower = url.absoluteString.lowercased()
        for value in ["jpg", "jpeg", "png", "webp", "gif", "mp4", "mov", "m4v", "webm"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw)
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:") else {
            return nil
        }
        if value.hasPrefix("//") {
            value = (baseURL.scheme ?? "https") + ":" + value
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        host == "weibo.com" ||
            host == "www.weibo.com" ||
            host == "m.weibo.cn" ||
            host == "weibo.cn" ||
            host == "sina.com.cn" ||
            host.hasSuffix(".sina.com.cn") ||
            host == "weibo.test" ||
            host == "www.weibo.test" ||
            host == "m.weibo.test"
    }

    private static func canonicalInputHost(for host: String) -> String {
        if host.hasSuffix(".test") {
            return "weibo.test"
        }
        if host == "sina.com.cn" || host.hasSuffix(".sina.com.cn") {
            return host
        }
        return "weibo.com"
    }

    private static func isSinaHost(_ host: String) -> Bool {
        host == "sina.com.cn" || host.hasSuffix(".sina.com.cn")
    }

    private static func isValidID(_ id: String) -> Bool {
        !id.isEmpty && id.range(of: #"^[0-9A-Za-z:_-]+$"#, options: .regularExpression) != nil
    }

    private static func isNumericID(_ id: String) -> Bool {
        id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isValidProfileSlug(_ value: String) -> Bool {
        guard isValidID(value) else { return false }
        return !["ajax", "detail", "login", "status", "tv", "search", "hot", "u", "p"].contains(value.lowercased())
    }

    private static func profileName(from url: URL) -> String? {
        guard let profileID = profileID(from: url) else { return nil }
        return isNumericID(profileID) ? profileID : profileID
    }

    private static func statusID(fromStatusDictionary status: [String: Any]) -> String? {
        for key in ["id", "mid", "mblogid", "mblog_id", "status_id", "bid"] {
            if let value = stringValue(status[key]), isValidID(value) {
                return value
            }
        }
        return nil
    }

    private static func isStatusLikeDictionary(_ dictionary: [String: Any]) -> Bool {
        dictionary["pic_infos"] != nil ||
            dictionary["pics"] != nil ||
            dictionary["mix_media_info"] != nil ||
            dictionary["page_info"] != nil ||
            dictionary["text"] != nil ||
            dictionary["text_raw"] != nil
    }

    private static func isLikelyImageURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains(".jpg") ||
            lower.contains(".jpeg") ||
            lower.contains(".png") ||
            lower.contains(".webp") ||
            lower.contains(".gif")
    }

    private static func isLikelyVideoURL(_ raw: String) -> Bool {
        let lower = raw.lowercased()
        return lower.contains(".mp4") ||
            lower.contains(".mov") ||
            lower.contains(".m4v") ||
            lower.contains(".webm")
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func integerValue(_ value: Any?) -> Int? {
        if let integer = value as? Int { return integer }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
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

    private static func firstCapture(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let capture = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[capture])
        }
        return nil
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let text = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return (text.isEmpty ? fallback : text).sanitizedFilename(maxLength: 120)
    }
}
