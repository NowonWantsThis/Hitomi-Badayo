import Foundation

struct EtcVideoCandidate: Equatable {
    var url: URL
    var quality: Int
    var label: String
    var width: Int = 0
    var height: Int = 0
    var protocolHint: String = ""

    var selectionScore: Int {
        if quality > 0 { return quality }
        if height > 0 { return height }
        return width
    }
}

final class EtcVideoPageResolver {
    private typealias VideoInfo = (id: String, title: String, displayTitle: String, uploader: String, uploaderID: String, thumbnail: URL?, date: String)

    enum Site: String {
        case avgle = "Avgle"
        case bitchute = "BitChute"
        case dailymotion = "Dailymotion"
        case kick = "Kick"
        case kissjav = "KissJAV"
        case odysee = "Odysee"
        case okru = "OK.ru"
        case reddit = "Reddit"
        case rumble = "Rumble"
        case rutube = "Rutube"
        case niconicoLive = "Niconico Live"
        case streamable = "Streamable"
        case thisvid = "ThisVid"
        case tokyomotion = "TokyoMotion"
        case twitcasting = "TwitCasting"
        case ixigua = "Ixigua"
        case tver = "TVer"
        case vk = "VK"
        case xhamster = "xHamster"
        case yourporn = "YourPorn"
        case youporn = "YouPorn"
        case youku = "Youku"

        var folderPrefix: String { rawValue }

        var usesOriginalMP4HLSPostProcessing: Bool {
            switch self {
            case .avgle, .youporn, .youku:
                return true
            default:
                return false
            }
        }

        var titleSuffixes: [String] {
            switch self {
            case .avgle:
                return [" - Avgle", " | Avgle", " - Avgle.com", " | Avgle.com"]
            case .bitchute:
                return [" - BitChute", " | BitChute", " - BitChute.com", " | BitChute.com"]
            case .dailymotion:
                return [" - Dailymotion", " | Dailymotion", " - Dailymotion.com", " | Dailymotion.com"]
            case .kick:
                return [" - Kick", " | Kick", " - Kick.com", " | Kick.com"]
            case .kissjav:
                return [" - KissJAV", " | KissJAV", " - KissJAV.com", " | KissJAV.com"]
            case .odysee:
                return [" - Odysee", " | Odysee", " - Odysee.com", " | Odysee.com"]
            case .okru:
                return [" - OK.ru", " | OK.ru", " - Odnoklassniki", " | Odnoklassniki"]
            case .reddit:
                return [" - Reddit", " | Reddit", " - reddit", " | reddit"]
            case .rumble:
                return [" - Rumble", " | Rumble", " - Rumble.com", " | Rumble.com"]
            case .rutube:
                return [" - Rutube", " | Rutube", " - Rutube.ru", " | Rutube.ru"]
            case .niconicoLive:
                return [
                    " - ニコニコ生放送", " | ニコニコ生放送",
                    " - Niconico Live", " | Niconico Live",
                    " - Nicovideo Live", " | Nicovideo Live"
                ]
            case .streamable:
                return [" - Streamable", " | Streamable", " - Streamable.com", " | Streamable.com"]
            case .thisvid:
                return [" - ThisVid.com", " | ThisVid.com", " - ThisVid", " | ThisVid"]
            case .tokyomotion:
                return [" - TokyoMotion", " | TokyoMotion", " - TokyoMotion.net", " | TokyoMotion.net"]
            case .twitcasting:
                return [" - TwitCasting", " | TwitCasting", " - TwitCasting.tv", " | TwitCasting.tv"]
            case .ixigua:
                return [" - 西瓜视频", " | 西瓜视频", " - Ixigua", " | Ixigua"]
            case .tver:
                return [" - TVer", " | TVer", " - TVer.jp", " | TVer.jp"]
            case .vk:
                return [" - VK", " | VK", " - VK Video", " | VK Video"]
            case .xhamster:
                return [" - xHamster", " | xHamster", " - xHamster.com", " | xHamster.com"]
            case .yourporn:
                return [" - YourPorn", " | YourPorn", " - YourPorn.sexy", " | YourPorn.sexy"]
            case .youporn:
                return [" - YouPorn", " | YouPorn", " - YouPorn.com", " | YouPorn.com"]
            case .youku:
                return [" - 优酷", " | 优酷", " - Youku", " | Youku"]
            }
        }
    }

    func canResolve(_ url: URL) -> Bool {
        if TokyoMotionResolver().canResolve(url) {
            return false
        }
        return Self.contentID(from: url) != nil
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        guard let id = Self.contentID(from: url),
              let site = Self.site(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let pageURL = Self.canonicalURL(for: url) ?? url
        let html = try await HTTPClient.shared.string(from: pageURL, referer: headers.referer, userAgent: headers.userAgent)
        if site == .tokyomotion,
           Self.isTokyoMotionAlbumURL(pageURL),
           let albumID = Self.tokyoMotionAlbumID(from: pageURL) {
            let slideshowURL = Self.tokyoMotionSlideshowURL(pageURL: pageURL, albumID: albumID)
            let slideshowHTML = (try? await HTTPClient.shared.string(
                from: slideshowURL,
                referer: pageURL.absoluteString,
                userAgent: headers.userAgent
            )) ?? ""
            return try Self.resolvedTokyoMotionAlbum(
                fromHTML: "\(html)\n\(slideshowHTML)",
                pageURL: pageURL,
                albumID: albumID
            )
        }
        return try await Self.resolvedDownload(fromHTML: html, pageURL: pageURL, site: site, contentID: id, userAgent: headers.userAgent)
    }

    static func site(for url: URL) -> Site? {
        guard let host = url.host?.lowercased() else { return nil }
        if isAvgleHost(host) { return .avgle }
        if isBitChuteHost(host) { return .bitchute }
        if isDailymotionHost(host) { return .dailymotion }
        if isKickHost(host) { return .kick }
        if isKissJAVHost(host) { return .kissjav }
        if isOdyseeHost(host) { return .odysee }
        if isOKRUHost(host) { return .okru }
        if isRedditHost(host) { return .reddit }
        if isRumbleHost(host) { return .rumble }
        if isRutubeHost(host) { return .rutube }
        if isNiconicoLiveHost(host) { return .niconicoLive }
        if isStreamableHost(host) { return .streamable }
        if isThisVidHost(host) { return .thisvid }
        if isTokyoMotionHost(host) { return .tokyomotion }
        if isTwitCastingHost(host) { return .twitcasting }
        if isIxiguaHost(host) { return .ixigua }
        if isTVerHost(host) { return .tver }
        if isVKHost(host) { return .vk }
        if isXHamsterHost(host) { return .xhamster }
        if isYourPornHost(host) { return .yourporn }
        if isYouPornHost(host) { return .youporn }
        if isYoukuHost(host) { return .youku }
        return nil
    }

    static func contentID(from url: URL) -> String? {
        guard let site = site(for: url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        switch site {
        case .avgle:
            guard ["watch", "video"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .bitchute:
            guard ["video", "embed"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .dailymotion:
            if isDaiLyHost(url.host?.lowercased() ?? "") {
                guard let first = parts.first, isValidSlug(first) else { return nil }
                return first
            }
            if lower.first == "embed",
               lower.dropFirst().first == "video",
               parts.count >= 3,
               isValidSlug(parts[2]) {
                return parts[2]
            }
            guard lower.first == "video",
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .kick:
            if let queryID = queryItem(named: ["clip", "video", "v"], in: url),
               isValidSlug(queryID) {
                return queryID
            }
            if let id = idAfterMarker(in: parts, lower: lower, markers: ["video", "videos", "clip", "clips", "embed"]) {
                return id
            }
            return nil
        case .kissjav:
            guard ["video", "videos"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .tokyomotion:
            if lower.first == "album" {
                return tokyoMotionAlbumID(from: url)
            }
            guard ["video", "videos"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .odysee:
            guard let last = parts.last,
                  !last.isEmpty,
                  !lower.contains("$") else {
                return nil
            }
            return contentID(fromPathComponent: last)
        case .okru:
            if let id = idAfterMarker(in: parts, lower: lower, markers: ["video", "videoembed"]) {
                return id
            }
            return nil
        case .reddit:
            if isVRedditHost(url.host?.lowercased() ?? "") {
                guard let first = parts.first, isValidSlug(first) else { return nil }
                return first
            }
            if isRedditShortHost(url.host?.lowercased() ?? "") {
                guard let first = parts.first, isValidSlug(first) else { return nil }
                return first
            }
            guard let commentsIndex = lower.firstIndex(of: "comments"),
                  commentsIndex + 1 < parts.count,
                  isValidSlug(parts[commentsIndex + 1]) else {
                return nil
            }
            return parts[commentsIndex + 1]
        case .rumble:
            guard let first = parts.first else { return nil }
            if lower.first == "embed",
               parts.count >= 2,
               isValidSlug(parts[1]) {
                return parts[1]
            }
            guard first.lowercased().hasPrefix("v") else {
                return nil
            }
            let id = first.replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
            return isValidSlug(id) ? id : nil
        case .rutube:
            if lower.count >= 3,
               lower[0] == "play",
               lower[1] == "embed",
               isValidSlug(parts[2]) {
                return parts[2]
            }
            guard lower.first == "video",
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .niconicoLive:
            guard lower.first == "watch",
                  parts.count >= 2,
                  isNiconicoLiveID(parts[1]) else {
                return nil
            }
            return parts[1]
        case .streamable:
            if lower.first == "e",
               parts.count >= 2,
               isValidSlug(parts[1]) {
                return parts[1]
            }
            guard let first = parts.first,
                  parts.count == 1,
                  isValidSlug(first) else {
                return nil
            }
            return first
        case .thisvid:
            guard ["video", "videos"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .twitcasting:
            if let id = queryItem(named: ["movie_id", "movie", "id"], in: url),
               isValidSlug(id) {
                return id
            }
            if let id = idAfterMarker(in: parts, lower: lower, markers: ["movie", "movies", "show", "twplayer"]) {
                return id
            }
            return nil
        case .ixigua:
            if let first = parts.first, parts.count == 1, isIxiguaVideoID(first) {
                return first
            }
            guard lower.first == "video",
                  parts.count >= 2,
                  isIxiguaVideoID(parts[1]) else {
                return nil
            }
            return parts[1]
        case .tver:
            if let id = idAfterMarker(in: parts, lower: lower, markers: ["episodes", "episode"]) {
                return id
            }
            return nil
        case .vk:
            if lower.first == "video_ext.php" {
                let oid = queryItem(named: ["oid"], in: url) ?? ""
                let id = queryItem(named: ["id"], in: url) ?? ""
                if !oid.isEmpty, !id.isEmpty {
                    return "\(oid)_\(id)".sanitizedFilename(maxLength: 120)
                }
            }
            guard let first = parts.first else { return nil }
            if first.lowercased().hasPrefix("video") || first.lowercased().hasPrefix("clip") {
                let value = first
                    .replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
                    .trimmed
                return value.count > 5 ? value.sanitizedFilename(maxLength: 120) : nil
            }
            if let id = idAfterMarker(in: parts, lower: lower, markers: ["video", "clip"]) {
                return id
            }
            return nil
        case .xhamster:
            if let usersIndex = lower.firstIndex(of: "users"),
               let videosIndex = lower.firstIndex(of: "videos"),
               usersIndex < videosIndex {
                return nil
            }
            if let id = idAfterMarker(in: parts, lower: lower, markers: ["videos"]) {
                return id
            }
            return nil
        case .yourporn:
            guard ["post", "watch"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .youporn:
            guard lower.first == "watch",
                  parts.count >= 2,
                  isValidSlug(parts[1]) else {
                return nil
            }
            return parts[1]
        case .youku:
            guard ["video", "v_show"].contains(lower.first ?? "") else {
                return nil
            }
            for part in parts {
                if part.hasPrefix("id_") {
                    let id = String(part.dropFirst(3))
                        .replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
                        .trimmed
                    return id.isEmpty ? nil : id.sanitizedFilename(maxLength: 120)
                }
            }
            return nil
        }
    }

    static func canonicalAvgleURL(for url: URL) -> URL? {
        guard site(for: url) == .avgle,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalKissJAVURL(for url: URL) -> URL? {
        KissJAVResolver.canonicalURL(for: url)
    }

    static func canonicalTokyoMotionURL(for url: URL) -> URL? {
        TokyoMotionResolver.canonicalURL(for: url)
    }

    static func canonicalThisVidURL(for url: URL) -> URL? {
        guard site(for: url) == .thisvid,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalIxiguaURL(for url: URL) -> URL? {
        guard site(for: url) == .ixigua,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalYourPornURL(for url: URL) -> URL? {
        guard site(for: url) == .yourporn,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalYouPornURL(for url: URL) -> URL? {
        guard site(for: url) == .youporn,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalYoukuURL(for url: URL) -> URL? {
        guard site(for: url) == .youku,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalStreamableURL(for url: URL) -> URL? {
        guard site(for: url) == .streamable,
              let id = contentID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalDailymotionURL(for url: URL) -> URL? {
        guard site(for: url) == .dailymotion,
              let id = contentID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let host = url.host?.lowercased() ?? ""
        components.path = isDaiLyHost(host) ? "/\(id)" : "/video/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalRedditURL(for url: URL) -> URL? {
        guard site(for: url) == .reddit,
              let id = contentID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let host = url.host?.lowercased() ?? ""
        if isVRedditHost(host) || isRedditShortHost(host) {
            components.path = "/\(id)"
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalVKURL(for url: URL) -> URL? {
        guard site(for: url) == .vk,
              contentID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if url.path.lowercased().contains("video_ext.php") {
            let items = components.queryItems ?? []
            components.queryItems = items.filter { ["oid", "id"].contains($0.name.lowercased()) }
        } else {
            components.queryItems = nil
        }
        components.fragment = nil
        return components.url
    }

    static func canonicalXHamsterURL(for url: URL) -> URL? {
        guard site(for: url) == .xhamster,
              let id = contentID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/videos/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalXHamsterUserVideosURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isXHamsterHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let usersIndex = lower.firstIndex(of: "users"),
              usersIndex + 2 < parts.count,
              lower[usersIndex + 2] == "videos" else {
            return nil
        }
        let username = parts[usersIndex + 1].trimmed
        guard username.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        components.scheme = "https"
        components.path = "/users/\(username)/videos"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalXHamsterCreatorURL(for url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isXHamsterHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let creatorsIndex = lower.firstIndex(of: "creators"),
              creatorsIndex + 1 < parts.count else {
            return nil
        }
        let username = parts[creatorsIndex + 1].trimmed
        guard username.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        var canonicalParts = Array(parts.prefix(creatorsIndex + 2))
        if creatorsIndex + 2 < parts.count {
            let section = parts[creatorsIndex + 2].trimmed
            if !section.isEmpty,
               section.range(of: #"^[0-9]+$"#, options: .regularExpression) == nil,
               section.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil {
                canonicalParts.append(section)
            }
        }

        components.scheme = "https"
        components.path = "/" + canonicalParts.joined(separator: "/")
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    static func canonicalCommonVideoURL(for url: URL) -> URL? {
        guard let site = site(for: url),
              let id = contentID(from: url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        switch site {
        case .bitchute:
            components.path = "/video/\(id)/"
            components.queryItems = nil
        case .kick:
            if queryItem(named: ["clip", "video", "v"], in: url) != nil {
                let items = components.queryItems ?? []
                components.queryItems = items.filter { ["clip", "video", "v"].contains($0.name.lowercased()) }
            } else {
                components.queryItems = nil
            }
        case .odysee, .okru, .rumble, .rutube, .niconicoLive, .twitcasting, .tver:
            if site == .tver {
                components.path = "/episodes/\(id)"
            }
            if site == .twitcasting,
               queryItem(named: ["movie_id", "movie", "id"], in: url) != nil {
                let items = components.queryItems ?? []
                components.queryItems = items.filter { ["movie_id", "movie", "id"].contains($0.name.lowercased()) }
            } else {
                components.queryItems = nil
            }
        default:
            return nil
        }
        components.fragment = nil
        return components.url
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let site = site(for: url) else { return nil }
        switch site {
        case .avgle:
            return canonicalAvgleURL(for: url)
        case .kissjav:
            return canonicalKissJAVURL(for: url)
        case .tokyomotion:
            return canonicalTokyoMotionURL(for: url)
        case .thisvid:
            return canonicalThisVidURL(for: url)
        case .ixigua:
            return canonicalIxiguaURL(for: url)
        case .yourporn:
            return canonicalYourPornURL(for: url)
        case .youporn:
            return canonicalYouPornURL(for: url)
        case .youku:
            return canonicalYoukuURL(for: url)
        case .streamable:
            return canonicalStreamableURL(for: url)
        case .dailymotion:
            return canonicalDailymotionURL(for: url)
        case .reddit:
            return canonicalRedditURL(for: url)
        case .vk:
            return canonicalVKURL(for: url)
        case .xhamster:
            return canonicalXHamsterURL(for: url)
        case .bitchute, .kick, .odysee, .okru, .rumble, .rutube, .niconicoLive, .twitcasting, .tver:
            return canonicalCommonVideoURL(for: url)
        }
    }

    static func videoCandidates(fromHTML html: String, pageURL: URL) -> [EtcVideoCandidate] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var candidates: [EtcVideoCandidate] = []

        for tag in allCaptures(pattern: #"<(?:video|source)\b[^>]*>"#, in: normalized, group: 0) {
            let width = positiveInt(attributeValue("width", in: tag) ?? attributeValue("data-width", in: tag))
            let height = positiveInt(attributeValue("height", in: tag) ?? attributeValue("data-height", in: tag))
            let label = attributeValue("label", in: tag) ??
                attributeValue("data-quality", in: tag) ??
                attributeValue("quality", in: tag) ??
                attributeValue("res", in: tag) ??
                attributeValue("data-res", in: tag) ??
                attributeValue("height", in: tag) ??
                attributeValue("data-height", in: tag) ??
                attributeValue("title", in: tag) ??
                ""
            for attribute in [
                "src", "data-src", "data-url", "data-video", "data-file",
                "data-source", "data-stream", "data-stream-url", "data-playback-url",
                "data-hls", "data-hls-url", "data-dash", "data-dash-url",
                "data-mpd", "data-mpd-url", "data-manifest", "data-manifest-url",
                "data-m3u8", "data-mp4", "data-file-url", "data-media-url"
            ] {
                if let raw = attributeValue(attribute, in: tag) {
                    appendCandidate(rawURL: raw, label: label, pageURL: pageURL, width: width, height: height, candidates: &candidates)
                }
            }
        }

        for tag in mediaAttributeTags(in: normalized) {
            let width = positiveInt(attributeValue("width", in: tag) ?? attributeValue("data-width", in: tag))
            let height = positiveInt(attributeValue("height", in: tag) ?? attributeValue("data-height", in: tag))
            let label = attributeValue("label", in: tag) ??
                attributeValue("data-quality", in: tag) ??
                attributeValue("quality", in: tag) ??
                attributeValue("res", in: tag) ??
                attributeValue("data-res", in: tag) ??
                attributeValue("height", in: tag) ??
                attributeValue("data-height", in: tag) ??
                attributeValue("title", in: tag) ??
                ""
            for attribute in mediaAttributeNames {
                if let raw = attributeValue(attribute, in: tag) {
                    appendCandidate(rawURL: raw, label: label, pageURL: pageURL, width: width, height: height, candidates: &candidates)
                }
            }
        }

        for meta in allCaptures(pattern: #"<meta\b[^>]*>"#, in: normalized, group: 0) {
            let name = (attributeValue("property", in: meta) ?? attributeValue("name", in: meta) ?? "").lowercased()
            guard ["og:video", "og:video:url", "og:video:secure_url", "twitter:player:stream"].contains(name),
                  let content = attributeValue("content", in: meta) else {
                continue
            }
            appendCandidate(rawURL: content, label: name, pageURL: pageURL, candidates: &candidates)
        }

        for object in scriptJSONObjects(in: normalized) {
            collectCandidates(in: object, pageURL: pageURL, inheritedLabel: "", candidates: &candidates)
        }

        for object in attributeJSONObjects(in: normalized) {
            collectCandidates(in: object, pageURL: pageURL, inheritedLabel: "", candidates: &candidates)
        }

        candidates.append(contentsOf: looseScriptMediaCandidates(in: normalized, pageURL: pageURL))

        for raw in directMediaURLs(in: normalized) {
            appendCandidate(rawURL: raw, label: "", pageURL: pageURL, candidates: &candidates)
        }

        return uniqueCandidates(candidates)
    }

    static func resolvedDownload(fromHTML html: String, pageURL: URL, site: Site, contentID: String, userAgent: String?) async throws -> ResolvedDownload {
        if site == .tokyomotion,
           isTokyoMotionAlbumURL(pageURL),
           let albumID = tokyoMotionAlbumID(from: pageURL) {
            return try resolvedTokyoMotionAlbum(fromHTML: html, pageURL: pageURL, albumID: albumID)
        }

        let candidates = videoCandidates(fromHTML: html, pageURL: pageURL)
        let candidate: EtcVideoCandidate?
        switch site {
        case .youporn:
            candidate = originalYouPornFormatCandidate(fromHTML: html, pageURL: pageURL) ?? bestCandidate(candidates)
        case .youku:
            candidate = originalYoukuFormatCandidate(fromHTML: html, pageURL: pageURL) ?? bestCandidate(candidates)
        default:
            candidate = bestCandidate(candidates)
        }
        guard let candidate else {
            throw NativeDownloadError.noFiles
        }

        let info = videoInfo(fromHTML: html, pageURL: pageURL, site: site, contentID: contentID)
        if isMPD(candidate.url) {
            let dash = try await MPDResolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            let enrichedAssets = dash.assets.enumerated().map { offset, asset in
                enrichedDASHAsset(
                    asset,
                    site: site,
                    info: info,
                    pageURL: pageURL,
                    manifestURL: candidate.url,
                    index: offset + 1
                )
            }
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "\(site.folderPrefix) \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: enrichedAssets,
                packageMode: dashPackageMode(
                    dash.packageMode,
                    site: site,
                    info: info,
                    pageURL: pageURL,
                    manifestURL: candidate.url
                ),
                metadata: metadata(site: site, info: info, pageURL: pageURL, videoURL: candidate.url, candidate: candidate)
                    .merging(dash.metadata) { current, _ in current }
            )
        }

        if isM3U8(candidate, site: site) {
            let hls = try await M3U8Resolver().resolve(
                candidate.url,
                headers: HTTPRequestOptions(referer: pageURL.absoluteString, userAgent: userAgent)
            )
            let outputExtension = site.usesOriginalMP4HLSPostProcessing ? "mp4" : "ts"
            return ResolvedDownload(
                title: info.displayTitle,
                folderName: "\(site.folderPrefix) \(info.displayTitle)".sanitizedFilename(maxLength: 120),
                assets: hls.assets.enumerated().map { offset, asset in
                    var enriched = asset
                    enriched.metadata = asset.metadata.merging(segmentMetadata(
                        site: site,
                        info: info,
                        pageURL: pageURL,
                        asset: asset,
                        index: offset + 1
                    )) { _, siteValue in siteValue }
                    return enriched
                },
                packageMode: .concatenate(
                    outputFilename: videoOutputFilename(site: site, info: info, extension: outputExtension)
                ),
                metadata: metadata(site: site, info: info, pageURL: pageURL, videoURL: candidate.url, candidate: candidate)
                    .merging(hls.metadata) { current, _ in current }
            )
        }

        let ext = site == .youku || candidate.url.pathExtension.trimmed.isEmpty
            ? "mp4"
            : candidate.url.pathExtension
        let filename = videoOutputFilename(site: site, info: info, extension: ext)
        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "\(site.folderPrefix) \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: assetMetadata(site: site, info: info, pageURL: pageURL, candidate: candidate),
                    referer: pageURL.absoluteString
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata(site: site, info: info, pageURL: pageURL, videoURL: candidate.url, candidate: candidate)
        )
    }

    static func resolvedTokyoMotionAlbum(fromHTML html: String, pageURL: URL, albumID: String) throws -> ResolvedDownload {
        let imageURLs = tokyoMotionAlbumImageURLs(fromHTML: html, pageURL: pageURL, albumID: albumID)
        guard !imageURLs.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let info = tokyoMotionAlbumInfo(fromHTML: html, pageURL: pageURL, albumID: albumID)
        let assets = imageURLs.enumerated().map { offset, imageURL in
            let index = offset + 1
            let format = mediaFormat(forImageURL: imageURL)
            return ResolvedAsset(
                remoteURL: imageURL,
                filename: "\(info.displayTitle)-\(String(format: "%03d", index)).\(format)".sanitizedFilename(maxLength: 180),
                metadata: tokyoMotionAlbumAssetMetadata(
                    info: info,
                    pageURL: pageURL,
                    imageURL: imageURL,
                    index: index,
                    total: imageURLs.count
                ),
                referer: pageURL.absoluteString
            )
        }

        return ResolvedDownload(
            title: info.displayTitle,
            folderName: "TokyoMotion \(info.displayTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: tokyoMotionAlbumMetadata(info: info, pageURL: pageURL, imageURLs: imageURLs)
        )
    }

    private static let mediaAttributeNames = [
        "src", "data-src", "data-url", "data-video", "data-video-url",
        "data-file", "data-file-url", "data-source", "data-stream",
        "data-stream-url", "data-playback-url", "data-hls", "data-hls-url",
        "data-dash", "data-dash-url", "data-mpd", "data-mpd-url",
        "data-manifest", "data-manifest-url", "data-m3u8", "data-mp4",
        "data-media-url"
    ]

    private static let looseMediaFieldNames = [
        "url", "src", "file", "video", "video_url", "videoUrl", "downloadUrl",
        "download_url", "contentUrl", "content_url", "playAddr", "play_addr",
        "fallbackUrl", "fallback_url", "dashUrl", "dash_url", "hlsUrl",
        "hls_url", "mainUrl", "main_url", "backupUrl", "backup_url",
        "stream", "streamUrl", "stream_url", "media", "mediaUrl",
        "media_url", "fileUrl", "file_url", "sourceUrl", "source_url",
        "assetUrl", "asset_url", "cdnUrl", "cdn_url", "download", "hls",
        "m3u8", "mp4", "playbackUrl", "playback_url", "playbackURL",
        "manifestUrl", "manifest_url", "manifestURL", "hlsManifestUrl",
        "hlsManifestURL", "hlsManifest", "m3u8Url", "m3u8_url",
        "mp4Url", "mp4_url", "movieUrl", "movie_url", "secureUrl",
        "secure_url", "srcUrl", "src_url", "videoUri", "video_uri",
        "playlistUrl", "playlist_url"
    ]

    private static let embeddedMediaQueryKeys = Set([
        "file", "url", "src", "source", "stream", "video", "video_url",
        "videourl", "media", "media_url", "mediaurl", "hls", "hls_url",
        "hlsurl", "m3u8", "mp4", "manifest", "manifest_url",
        "manifesturl", "playlist", "playlist_url", "playlisturl",
        "playback", "playback_url", "playbackurl"
    ])

    private static func mediaAttributeTags(in html: String) -> [String] {
        let attributes = mediaAttributeNames
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        return allCaptures(
            pattern: #"<[A-Za-z][^>]*\b(?:\#(attributes))\s*=[^>]*>"#,
            in: html,
            group: 0
        )
    }

    private static func looseScriptMediaCandidates(in html: String, pageURL: URL) -> [EtcVideoCandidate] {
        var candidates: [EtcVideoCandidate] = []
        let mediaKeys = looseMediaFieldNames
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let objectPattern = #"\{[^{}]*\b["']?(?:\#(mediaKeys))["']?\s*:\s*(?:"[^"]*"|'[^']*'|atob\([^)]*\)|decodeURIComponent\([^)]*\)|[^,}\]\s;]+)[^{}]*\}"#

        for script in allCaptures(pattern: #"<script\b[^>]*>(.*?)</script>"#, in: html) {
            for fragment in allCaptures(pattern: objectPattern, in: script, group: 0) {
                collectLooseMediaCandidates(in: fragment, pageURL: pageURL, candidates: &candidates)
            }

            let balancedFragments = balancedJSONObjects(in: script) + balancedJSONArrays(in: script)
            for fragment in balancedFragments where hasMediaJSONHints(fragment) {
                collectLooseMediaCandidates(in: fragment, pageURL: pageURL, candidates: &candidates)
            }
        }
        return candidates
    }

    private static func collectLooseMediaCandidates(in text: String, pageURL: URL, candidates: inout [EtcVideoCandidate]) {
        let label = looseFieldValue(
            named: ["label", "quality", "resolution", "definition", "rendition", "name"],
            in: text
        ) ?? ""
        let width = positiveInt(looseFieldValue(named: ["width", "w"], in: text))
        let height = positiveInt(looseFieldValue(named: ["height", "h"], in: text))
        for raw in looseFieldValues(named: looseMediaFieldNames, in: text) {
            appendCandidate(rawURL: raw, label: label, pageURL: pageURL, width: width, height: height, candidates: &candidates)
        }
    }

    private static func looseFieldValue(named names: [String], in text: String) -> String? {
        looseFieldValues(named: names, in: text).first
    }

    private static func looseFieldValues(named names: [String], in text: String) -> [String] {
        let keys = names
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = #"(?:^|[,{;\s])["']?(?:\#(keys))["']?\s*:\s*(?:"([^"]*)"|'([^']*)'|atob\(\s*["']([^"']+)["']\s*\)|decodeURIComponent\(\s*["']([^"']+)["']\s*\)|([^,}\]\s;]+))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        var values: [String] = []
        for match in regex.matches(in: text, range: range) {
            for group in 1..<match.numberOfRanges {
                guard let capture = Range(match.range(at: group), in: text) else { continue }
                let value = String(text[capture]).trimmed
                if !value.isEmpty {
                    values.append(value)
                    break
                }
            }
        }
        return values
    }

    private static func embeddedMediaURLStrings(in text: String) -> [String] {
        let normalized = normalizeEscapes(decodeHTML(text)).trimmed
        guard !normalized.isEmpty else { return [] }

        var results: [String] = []
        var seen = Set<String>()
        func append(_ value: String?) {
            guard let cleaned = value?.trimmed, !cleaned.isEmpty, seen.insert(cleaned).inserted else { return }
            results.append(cleaned)
        }

        if let components = URLComponents(string: normalized),
           let items = components.queryItems {
            for item in items where embeddedMediaQueryKeys.contains(item.name.lowercased()) {
                append(item.value)
            }
        }

        let keys = embeddedMediaQueryKeys
            .map(NSRegularExpression.escapedPattern(for:))
            .joined(separator: "|")
        let pattern = #"(?:^|[?&#;])(?:\#(keys))=([^&"' <>\)\]]+)"#
        for raw in allCaptures(pattern: pattern, in: normalized, group: 1) {
            append(raw.removingPercentEncoding ?? raw)
        }

        for raw in directMediaURLs(in: normalized) {
            append(raw)
        }

        return results
    }

    private static func collectCandidates(in object: Any, pageURL: URL, inheritedLabel: String, candidates: inout [EtcVideoCandidate]) {
        if let dict = object as? [String: Any] {
            let primaryWidth = positiveInt(dict["width"])
            let primaryHeight = positiveInt(dict["height"])
            let width = primaryWidth > 0 ? primaryWidth : positiveInt(dict["w"])
            let height = primaryHeight > 0 ? primaryHeight : positiveInt(dict["h"])
            let protocolHint = stringValue(dict["protocol"]) ?? ""
            let label = stringValue(dict["label"]) ??
                stringValue(dict["quality"]) ??
                stringValue(dict["resolution"]) ??
                stringValue(dict["height"]) ??
                stringValue(dict["format"]) ??
                stringValue(dict["definition"]) ??
                stringValue(dict["rendition"]) ??
                stringValue(dict["name"]) ??
                inheritedLabel

            for key in [
                "url", "src", "file", "video", "video_url", "videoUrl", "downloadUrl",
                "download_url", "contentUrl", "content_url", "playAddr", "play_addr",
                "fallbackUrl", "fallback_url", "dashUrl", "dash_url", "hlsUrl",
                "hls_url", "mainUrl", "main_url", "backupUrl", "backup_url",
                "stream", "streamUrl", "stream_url", "media", "mediaUrl",
                "media_url", "fileUrl", "file_url", "sourceUrl", "source_url",
                "assetUrl", "asset_url", "cdnUrl", "cdn_url", "download", "hls",
                "m3u8", "mp4", "playbackUrl", "playback_url", "playbackURL", "manifestUrl",
                "manifest_url", "manifestURL", "hlsManifestUrl", "hlsManifestURL",
                "hlsManifest", "m3u8Url", "m3u8_url", "mp4Url", "mp4_url",
                "movieUrl", "movie_url", "secureUrl", "secure_url", "srcUrl",
                "src_url", "videoUri", "video_uri", "playlistUrl", "playlist_url"
            ] {
                if let raw = stringValue(dict[key]) {
                    appendCandidate(
                        rawURL: raw,
                        label: label.isEmpty ? key : label,
                        pageURL: pageURL,
                        width: width,
                        height: height,
                        protocolHint: protocolHint,
                        candidates: &candidates
                    )
                }
            }

            for (key, value) in dict {
                let childLabel = label.isEmpty ? key : label
                collectCandidates(in: value, pageURL: pageURL, inheritedLabel: childLabel, candidates: &candidates)
            }
        } else if let array = object as? [Any] {
            for item in array {
                collectCandidates(in: item, pageURL: pageURL, inheritedLabel: inheritedLabel, candidates: &candidates)
            }
        }
    }

    private static func appendCandidate(rawURL: String, label: String, pageURL: URL, candidates: inout [EtcVideoCandidate]) {
        appendCandidate(rawURL: rawURL, label: label, pageURL: pageURL, width: 0, height: 0, candidates: &candidates)
    }

    private static func appendCandidate(
        rawURL: String,
        label: String,
        pageURL: URL,
        width: Int,
        height: Int,
        protocolHint: String = "",
        candidates: inout [EtcVideoCandidate]
    ) {
        for raw in expandedRawURLs(rawURL) {
            guard let url = absoluteURL(raw, baseURL: pageURL),
                  isPlayableVideo(url) else {
                continue
            }
            let quality = qualityFrom(label: label, url: url)
            let inferredHeight = height > 0 ? height : (quality > 0 && quality < 10_000 ? quality : 0)
            candidates.append(EtcVideoCandidate(
                url: url,
                quality: quality,
                label: label,
                width: width,
                height: inferredHeight,
                protocolHint: protocolHint
            ))
            return
        }
    }

    private static func expandedRawURLs(_ raw: String) -> [String] {
        var values: [String] = []
        var seen = Set<String>()

        func append(_ candidate: String) {
            let cleaned = normalizeEscapes(decodeHTML(candidate)).trimmed
            guard !cleaned.isEmpty, seen.insert(cleaned).inserted else { return }

            if let decoded = cleaned.removingPercentEncoding,
               decoded != cleaned {
                append(decoded)
            }
            if let data = Data(base64Encoded: cleaned),
               let decoded = String(data: data, encoding: .utf8),
               decoded.lowercased().contains("http") || hasMediaJSONHints(decoded) {
                append(decoded)
            }
            for embedded in embeddedMediaURLStrings(in: cleaned) {
                append(embedded)
            }
            values.append(cleaned)
        }

        append(raw)
        return values
    }

    private static func bestCandidate(_ candidates: [EtcVideoCandidate]) -> EtcVideoCandidate? {
        candidates.max { lhs, rhs in
            if lhs.selectionScore != rhs.selectionScore {
                return lhs.selectionScore < rhs.selectionScore
            }
            if lhs.isDirectVideo != rhs.isDirectVideo {
                return !lhs.isDirectVideo && rhs.isDirectVideo
            }
            return lhs.url.absoluteString < rhs.url.absoluteString
        }
    }

    private static func originalYouPornFormatCandidate(fromHTML html: String, pageURL: URL) -> EtcVideoCandidate? {
        let objects = scriptJSONObjects(in: normalizeEscapes(decodeHTML(html)))
        for object in objects {
            if let candidate = originalYouPornFormatCandidate(in: object, pageURL: pageURL) {
                return candidate
            }
        }
        return nil
    }

    private static func originalYouPornFormatCandidate(in object: Any, pageURL: URL) -> EtcVideoCandidate? {
        if let dict = object as? [String: Any] {
            for (key, value) in dict where normalizedJSONKey(key) == "formats" {
                guard let formats = value as? [Any] else { continue }
                for format in formats.reversed() {
                    var candidates: [EtcVideoCandidate] = []
                    collectCandidates(in: format, pageURL: pageURL, inheritedLabel: "", candidates: &candidates)
                    if let candidate = bestCandidate(uniqueCandidates(candidates)) {
                        return candidate
                    }
                }
            }
            for value in dict.values {
                if let candidate = originalYouPornFormatCandidate(in: value, pageURL: pageURL) {
                    return candidate
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let candidate = originalYouPornFormatCandidate(in: value, pageURL: pageURL) {
                    return candidate
                }
            }
        }
        return nil
    }

    static func originalYoukuFormatCandidate(fromHTML html: String, pageURL: URL) -> EtcVideoCandidate? {
        let objects = scriptJSONObjects(in: normalizeEscapes(decodeHTML(html)))
        for object in objects {
            if let candidate = originalYoukuFormatCandidate(in: object, pageURL: pageURL) {
                return candidate
            }
        }
        return nil
    }

    private static func originalYoukuFormatCandidate(in object: Any, pageURL: URL) -> EtcVideoCandidate? {
        if let dictionary = object as? [String: Any] {
            for (key, value) in dictionary where normalizedJSONKey(key) == "formats" {
                guard let formats = value as? [Any] else { continue }
                var selected: (width: Int, format: [String: Any])?
                for value in formats {
                    guard let format = value as? [String: Any] else { continue }
                    let width = positiveInt(format["width"])
                    guard width > 0 else { continue }
                    if selected.map({ width > $0.width }) ?? true {
                        selected = (width, format)
                    }
                }
                guard let selected,
                      let rawURL = stringValue(selected.format["url"]),
                      let url = absoluteURL(rawURL, baseURL: pageURL),
                      let scheme = url.scheme?.lowercased(),
                      scheme == "http" || scheme == "https" else {
                    continue
                }
                let height = positiveInt(selected.format["height"])
                let label = stringValue(selected.format["format_note"]) ??
                    stringValue(selected.format["format"]) ??
                    stringValue(selected.format["resolution"]) ??
                    (height > 0 ? "\(height)p" : "")
                return EtcVideoCandidate(
                    url: url,
                    quality: height,
                    label: label,
                    width: selected.width,
                    height: height,
                    protocolHint: stringValue(selected.format["protocol"]) ?? ""
                )
            }
            for value in dictionary.values {
                if let candidate = originalYoukuFormatCandidate(in: value, pageURL: pageURL) {
                    return candidate
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let candidate = originalYoukuFormatCandidate(in: value, pageURL: pageURL) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func uniqueCandidates(_ candidates: [EtcVideoCandidate]) -> [EtcVideoCandidate] {
        let queryBackedBases = Set(candidates.compactMap { candidate -> String? in
            guard hasQuery(candidate.url) else { return nil }
            return mediaBaseIdentity(candidate.url)
        })
        var seen = Set<String>()
        return candidates.filter { candidate in
            if !hasQuery(candidate.url),
               let base = mediaBaseIdentity(candidate.url),
               queryBackedBases.contains(base) {
                return false
            }
            let key = URLIdentity.normalize(candidate.url.absoluteString)
            guard !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private static func hasQuery(_ url: URL) -> Bool {
        guard let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedQuery else {
            return false
        }
        return !query.isEmpty
    }

    private static func mediaBaseIdentity(_ url: URL) -> String? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.query = nil
        components.percentEncodedQuery = nil
        components.fragment = nil
        return components.url.map { URLIdentity.normalize($0.absoluteString) }
    }

    private static func videoInfo(fromHTML html: String, pageURL: URL, site: Site, contentID: String) -> VideoInfo {
        let object = scriptJSONObjects(in: normalizeEscapes(decodeHTML(html)))
        let id = internalVideoID(fromHTML: html, object: object, site: site) ?? contentID
        let structuredTitle = stringValue(named: ["title", "name"], in: object)
        let metaTitle = metaContent(from: html, names: ["og:title", "twitter:title", "title"])
        let usesOriginalStructuredMetadata = site == .youporn || site == .youku
        let rawTitle = (usesOriginalStructuredMetadata ? structuredTitle ?? metaTitle : metaTitle ?? structuredTitle) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            "\(site.rawValue) \(id)"
        let title = cleanTitle(rawTitle, site: site, fallback: "\(site.rawValue) \(id)")
        let uploaderRaw = uploaderName(fromHTML: html, object: object, site: site)
        let uploader = uploaderRaw.map { cleanTitle($0, site: site, fallback: "") } ?? ""
        let uploaderID = uploaderIdentifier(fromHTML: html, object: object) ?? ""
        let displayTitle = usesOriginalStructuredMetadata
            ? title
            : [uploader, title].filter { !$0.isEmpty }.joined(separator: " - ")
        let structuredThumbnail = thumbnailURLString(from: object)
        let metaThumbnail = metaContent(from: html, names: ["og:image", "twitter:image", "thumbnail"])
        let thumbnailRaw = usesOriginalStructuredMetadata
            ? structuredThumbnail ?? metaThumbnail
            : metaThumbnail ?? structuredThumbnail
        let date = publishedDate(fromHTML: html, object: object)
        return (
            id,
            title,
            displayTitle.isEmpty ? title : displayTitle,
            uploader,
            uploaderID,
            thumbnailRaw.flatMap { absoluteURL($0, baseURL: pageURL) },
            date ?? ""
        )
    }

    private static func metadata(site: Site, info: VideoInfo, pageURL: URL, videoURL: URL, candidate: EtcVideoCandidate) -> [String: String] {
        let isHLS = isM3U8(candidate, site: site)
        return DownloadMetadata.clean([
            "site": site.rawValue,
            "title": info.title,
            "series": info.title,
            "category": "video",
            "type": mediaKind(for: candidate, site: site),
            "media_type": mediaKind(for: candidate, site: site),
            "format": mediaFormat(for: candidate, site: site),
            "media_format": mediaFormat(for: candidate, site: site),
            "hls_remux_required": site.usesOriginalMP4HLSPostProcessing && isHLS ? "true" : "",
            "host": pageURL.host ?? "",
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "media_count": (isHLS || isMPD(videoURL)) ? "" : "1",
            "video_count": "1",
            "width": widthString(for: candidate),
            "height": heightString(for: candidate),
            "resolution": resolution(for: candidate) ?? "",
            "quality": candidate.label.isEmpty ? resolution(for: candidate) ?? "" : candidate.label,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "artistid": info.uploaderID,
            "artist_id": info.uploaderID,
            "author_id": info.uploaderID,
            "creator_id": info.uploaderID,
            "uploader_id": info.uploaderID,
            "channel_id": info.uploaderID,
            "user_id": info.uploaderID,
            "uid": info.uploaderID,
            "date": info.date,
            "published_date": info.date,
            "thumbnail": info.thumbnail?.absoluteString ?? "",
            "video_url": videoURL.absoluteString,
            "media_url": videoURL.absoluteString,
            "playlist_url": isHLS ? videoURL.absoluteString : "",
            "manifest_url": isMPD(videoURL) ? videoURL.absoluteString : "",
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func assetMetadata(site: Site, info: VideoInfo, pageURL: URL, candidate: EtcVideoCandidate) -> [String: String] {
        DownloadMetadata.clean([
            "site": site.rawValue,
            "title": info.title,
            "series": info.title,
            "category": "video",
            "type": mediaKind(for: candidate, site: site),
            "media_type": mediaKind(for: candidate, site: site),
            "format": mediaFormat(for: candidate, site: site),
            "media_format": mediaFormat(for: candidate, site: site),
            "id": info.id,
            "video_id": info.id,
            "media_id": info.id,
            "gallery_id": info.id,
            "page": "1",
            "position": "1",
            "width": widthString(for: candidate),
            "height": heightString(for: candidate),
            "resolution": resolution(for: candidate) ?? "",
            "quality": candidate.label.isEmpty ? resolution(for: candidate) ?? "" : candidate.label,
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "artistid": info.uploaderID,
            "artist_id": info.uploaderID,
            "author_id": info.uploaderID,
            "creator_id": info.uploaderID,
            "uploader_id": info.uploaderID,
            "channel_id": info.uploaderID,
            "user_id": info.uploaderID,
            "uid": info.uploaderID,
            "date": info.date,
            "published_date": info.date,
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "playlist_url": isM3U8(candidate, site: site) ? candidate.url.absoluteString : "",
            "manifest_url": isMPD(candidate.url) ? candidate.url.absoluteString : "",
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func dashPackageMode(
        _ packageMode: DownloadPackageMode,
        site: Site,
        info: VideoInfo,
        pageURL: URL,
        manifestURL: URL
    ) -> DownloadPackageMode {
        switch packageMode {
        case .mux(let videoAssets, let audioAssets, _):
            let enrichedVideo = videoAssets.enumerated().map { offset, asset in
                enrichedDASHAsset(asset, site: site, info: info, pageURL: pageURL, manifestURL: manifestURL, index: offset + 1)
            }
            let enrichedAudio = audioAssets.enumerated().map { offset, asset in
                enrichedDASHAsset(asset, site: site, info: info, pageURL: pageURL, manifestURL: manifestURL, index: enrichedVideo.count + offset + 1)
            }
            return .mux(
                videoAssets: enrichedVideo,
                audioAssets: enrichedAudio,
                outputFilename: videoOutputFilename(site: site, info: info, extension: "mp4")
            )
        case .concatenate(let output):
            let ext = (output as NSString).pathExtension.trimmed.isEmpty ? "mp4" : (output as NSString).pathExtension
            return .concatenate(outputFilename: videoOutputFilename(site: site, info: info, extension: ext))
        case .files:
            return .files
        case .grouped:
            return packageMode
        case .groupedMedia:
            return packageMode
        }
    }

    private static func videoOutputFilename(site: Site, info: VideoInfo, extension ext: String) -> String {
        let stem = site == .youku
            ? "\(info.displayTitle) (\(info.id))"
            : "\(info.displayTitle)-\(info.id)"
        return "\(stem).\(ext)".sanitizedFilename(maxLength: 180)
    }

    private static func enrichedDASHAsset(
        _ asset: ResolvedAsset,
        site: Site,
        info: VideoInfo,
        pageURL: URL,
        manifestURL: URL,
        index: Int
    ) -> ResolvedAsset {
        var enriched = asset
        enriched.metadata = asset.metadata.merging(dashAssetMetadata(
            site: site,
            info: info,
            pageURL: pageURL,
            manifestURL: manifestURL,
            asset: asset,
            index: index
        )) { _, siteValue in siteValue }
        return enriched
    }

    private static func dashAssetMetadata(
        site: Site,
        info: VideoInfo,
        pageURL: URL,
        manifestURL: URL,
        asset: ResolvedAsset,
        index: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "site": site.rawValue,
            "title": info.title,
            "series": info.title,
            "category": "video",
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-dash-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "artistid": info.uploaderID,
            "artist_id": info.uploaderID,
            "author_id": info.uploaderID,
            "creator_id": info.uploaderID,
            "uploader_id": info.uploaderID,
            "channel_id": info.uploaderID,
            "user_id": info.uploaderID,
            "uid": info.uploaderID,
            "date": info.date,
            "published_date": info.date,
            "manifest_url": manifestURL.absoluteString,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func segmentMetadata(site: Site, info: VideoInfo, pageURL: URL, asset: ResolvedAsset, index: Int) -> [String: String] {
        let format = mediaFormat(for: asset.remoteURL, fallback: mediaFormat(forFilename: asset.filename, fallback: "ts"))
        return DownloadMetadata.clean([
            "site": site.rawValue,
            "title": info.title,
            "series": info.title,
            "category": "video",
            "type": "hls_segment",
            "media_type": "segment",
            "format": format,
            "media_format": format,
            "id": info.id,
            "video_id": info.id,
            "media_id": "\(info.id)-segment-\(index)",
            "gallery_id": info.id,
            "page": String(index),
            "position": String(index),
            "artist": info.uploader,
            "author": info.uploader,
            "creator": info.uploader,
            "uploader": info.uploader,
            "artistid": info.uploaderID,
            "artist_id": info.uploaderID,
            "author_id": info.uploaderID,
            "creator_id": info.uploaderID,
            "uploader_id": info.uploaderID,
            "channel_id": info.uploaderID,
            "user_id": info.uploaderID,
            "uid": info.uploaderID,
            "date": info.date,
            "published_date": info.date,
            "video_url": asset.remoteURL.absoluteString,
            "media_url": asset.remoteURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func tokyoMotionAlbumInfo(fromHTML html: String, pageURL: URL, albumID: String) -> (id: String, title: String, displayTitle: String) {
        let rawTitle = elementText(pattern: #"<h3\b[^>]*>(.*?)</h3>"#, in: html) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title", "title"]) ??
            elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html) ??
            "TokyoMotion album \(albumID)"
        var title = cleanTitle(rawTitle, site: .tokyomotion, fallback: "TokyoMotion album \(albumID)")
        if title.lowercased().hasPrefix("album - ") {
            title = String(title.dropFirst("Album - ".count)).trimmed.sanitizedFilename(maxLength: 120)
        }
        let displayTitle = title.isEmpty ? "TokyoMotion album \(albumID)" : title
        return (albumID, title, displayTitle)
    }

    private static func tokyoMotionAlbumMetadata(info: (id: String, title: String, displayTitle: String), pageURL: URL, imageURLs: [URL]) -> [String: String] {
        DownloadMetadata.clean([
            "site": Site.tokyomotion.rawValue,
            "title": info.title,
            "series": info.title,
            "category": "album",
            "type": "image",
            "media_type": "image",
            "format": imageURLs.first.map(mediaFormat(forImageURL:)) ?? "",
            "media_format": imageURLs.first.map(mediaFormat(forImageURL:)) ?? "",
            "host": pageURL.host ?? "",
            "id": info.id,
            "album_id": info.id,
            "gallery_id": info.id,
            "media_count": String(imageURLs.count),
            "image_count": String(imageURLs.count),
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func tokyoMotionAlbumAssetMetadata(info: (id: String, title: String, displayTitle: String), pageURL: URL, imageURL: URL, index: Int, total: Int) -> [String: String] {
        let format = mediaFormat(forImageURL: imageURL)
        return DownloadMetadata.clean([
            "site": Site.tokyomotion.rawValue,
            "title": info.title,
            "series": info.title,
            "category": "album",
            "type": "image",
            "media_type": "image",
            "format": format,
            "media_format": format,
            "id": info.id,
            "album_id": info.id,
            "gallery_id": info.id,
            "media_id": "\(info.id)-\(index)",
            "page": String(index),
            "position": String(index),
            "total": String(total),
            "image_url": imageURL.absoluteString,
            "media_url": imageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString
        ])
    }

    private static func tokyoMotionAlbumImageURLs(fromHTML html: String, pageURL: URL, albumID: String) -> [URL] {
        let normalized = normalizeEscapes(decodeHTML(html))
        var urls: [URL] = []
        var seen = Set<String>()
        let hasSlideshowLightbox = normalized.range(of: "data-lightbox", options: [.caseInsensitive]) != nil
        let tagPattern = #"<[A-Za-z][^>]*(?:data-lightbox|href|src|data-src|data-original)[^>]*>"#
        for tag in allCaptures(pattern: tagPattern, in: normalized, group: 0) {
            let lightbox = attributeValue("data-lightbox", in: tag) ?? ""
            let shouldPrefer = hasSlideshowLightbox
                ? lightbox == "slideshow-\(albumID)" || lightbox.contains("slideshow-\(albumID)")
                : lightbox.isEmpty || lightbox == "slideshow-\(albumID)" || lightbox.contains("slideshow-\(albumID)")
            guard shouldPrefer else { continue }

            for attribute in ["href", "data-original", "data-src", "src"] {
                guard let raw = attributeValue(attribute, in: tag),
                      let imageURL = tokyoMotionOriginalImageURL(raw, baseURL: pageURL),
                      isImageURL(imageURL) else {
                    continue
                }
                let key = URLIdentity.normalize(imageURL.absoluteString)
                guard !seen.contains(key) else { continue }
                seen.insert(key)
                urls.append(imageURL)
                break
            }
        }
        return urls
    }

    private static func tokyoMotionOriginalImageURL(_ raw: String, baseURL: URL) -> URL? {
        guard let url = absoluteURL(raw, baseURL: baseURL) else { return nil }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.path = components.path.replacingOccurrences(of: "/tmb/", with: "/")
        return components.url ?? url
    }

    private static func uploaderName(fromHTML html: String, object: Any?, site: Site) -> String? {
        let explicit = stringValue(
            named: [
                "uploader", "uploaderName", "uploader_name",
                "artist", "author", "creator", "owner", "ownerName",
                "username", "userName", "nickname",
                "channel", "channelName", "channel_name", "channelTitle",
                "accountName", "displayName"
            ],
            in: object
        ) ?? nestedProfileName(
            containers: ["uploader", "artist", "author", "creator", "owner", "user", "channel", "account"],
            in: object
        )
        if let explicit = meaningfulUploader(explicit, site: site) {
            return explicit
        }
        let metaAuthor = metaContent(from: html, names: ["author", "article:author"])
        if let metaAuthor = meaningfulUploader(metaAuthor, site: site) {
            return metaAuthor
        }
        return meaningfulUploader(metaContent(from: html, names: ["og:site_name"]), site: site)
    }

    private static func uploaderIdentifier(fromHTML html: String, object: Any?) -> String? {
        if let nested = nestedProfileIdentifier(
            containers: [
                "uploader", "artist", "author", "creator", "owner", "ownerChannel",
                "user", "userInfo", "channel", "channelInfo", "account", "profile"
            ],
            in: object
        ) {
            return nested
        }

        if let explicit = stringValue(
            named: [
                "uploaderId", "uploaderID", "uploader_id",
                "artistId", "artistID", "artist_id",
                "authorId", "authorID", "author_id",
                "creatorId", "creatorID", "creator_id",
                "ownerId", "ownerID", "owner_id",
                "channelId", "channelID", "channel_id",
                "userId", "userID", "user_id",
                "accountId", "accountID", "account_id",
                "profileId", "profileID", "profile_id"
            ],
            in: object
        ).flatMap(sanitizedMediaID) {
            return explicit
        }

        return metaContent(
            from: html,
            names: ["author:id", "article:author:id", "twitter:creator:id", "profile:username"]
        ).flatMap(sanitizedMediaID)
    }

    private static func nestedProfileIdentifier(containers: [String], in object: Any?) -> String? {
        guard let object else { return nil }
        let normalizedContainers = Set(containers.map(normalizedJSONKey))
        if let dict = object as? [String: Any] {
            for (key, value) in dict where normalizedContainers.contains(normalizedJSONKey(key)) {
                if let found = profileIdentifierValue(value) {
                    return found
                }
            }
            for value in dict.values {
                if let found = nestedProfileIdentifier(containers: containers, in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = nestedProfileIdentifier(containers: containers, in: value) {
                    return found
                }
            }
        }
        return nil
    }

    private static func profileIdentifierValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        let idKeys = [
            "id", "uid",
            "userId", "userID", "user_id",
            "uploaderId", "uploaderID", "uploader_id",
            "authorId", "authorID", "author_id",
            "creatorId", "creatorID", "creator_id",
            "ownerId", "ownerID", "owner_id",
            "channelId", "channelID", "channel_id",
            "accountId", "accountID", "account_id",
            "profileId", "profileID", "profile_id",
            "username", "userName", "user_name", "screenName", "screen_name", "handle"
        ]
        if let raw = stringValue(named: idKeys, in: value),
           let sanitized = sanitizedMediaID(raw) {
            return sanitized
        }
        return nil
    }

    private static func normalizedJSONKey(_ key: String) -> String {
        key.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private static func nestedProfileName(containers: [String], in object: Any?) -> String? {
        guard let object else { return nil }
        if let dict = object as? [String: Any] {
            for container in containers {
                guard let value = dict[container] else { continue }
                if let direct = stringValue(value)?.trimmed, !direct.isEmpty {
                    return direct
                }
                if let nested = stringValue(named: ["name", "title", "username", "displayName", "display_name"], in: value) {
                    return nested
                }
            }
            for value in dict.values {
                if let found = nestedProfileName(containers: containers, in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = nestedProfileName(containers: containers, in: value) {
                    return found
                }
            }
        }
        return nil
    }

    private static func internalVideoID(fromHTML html: String, object: Any?, site: Site) -> String? {
        if site == .kissjav,
           let id = firstCapture(pattern: #"\bdata-id\s*=\s*(?:"([^"]+)"|'([^']+)'|([^\s>"']+))"#, in: html, groups: [1, 2, 3]),
           let sanitized = sanitizedMediaID(id) {
            return sanitized
        }

        switch site {
        case .youporn, .youku:
            guard let raw = stringValue(
                named: ["id", "video_id", "videoId", "display_id", "displayId"],
                in: object
            ),
                  let sanitized = sanitizedMediaID(raw) else {
                return nil
            }
            return sanitized
        default:
            return nil
        }
    }

    private static func sanitizedMediaID(_ raw: String) -> String? {
        let value = raw.trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .sanitizedFilename(maxLength: 120)
        return value.isEmpty ? nil : value
    }

    private static func thumbnailURLString(from object: Any?) -> String? {
        if let direct = stringValue(
            named: ["thumbnail", "thumbnailUrl", "thumbnail_url", "poster", "cover", "coverUrl", "cover_url"],
            in: object
        ) {
            return direct
        }
        return thumbnailFromContainers(in: object)
    }

    private static func thumbnailFromContainers(in object: Any?) -> String? {
        guard let object else { return nil }
        if let dict = object as? [String: Any] {
            for key in ["thumbnails", "thumbnail_list", "thumbnailList", "thumbs", "covers"] {
                if let found = thumbnailValue(dict[key]) {
                    return found
                }
            }
            for value in dict.values {
                if let found = thumbnailFromContainers(in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = thumbnailFromContainers(in: value) ?? thumbnailValue(value) {
                    return found
                }
            }
        }
        return nil
    }

    private static func thumbnailValue(_ value: Any?) -> String? {
        if let raw = stringValue(value)?.trimmed, !raw.isEmpty {
            return raw
        }
        if let dict = value as? [String: Any] {
            return stringValue(named: ["url", "src", "thumbnail", "thumbnailUrl", "thumbnail_url"], in: dict)
        }
        if let array = value as? [Any] {
            for item in array {
                if let found = thumbnailValue(item) {
                    return found
                }
            }
        }
        return nil
    }

    private static func meaningfulUploader(_ raw: String?, site: Site) -> String? {
        guard let value = raw?.trimmed, !value.isEmpty else { return nil }
        let cleaned = cleanTitle(value, site: site, fallback: "")
        guard !cleaned.isEmpty else { return nil }
        let lower = cleaned.lowercased()
        let siteNames = Set([
            site.rawValue.lowercased(),
            "\(site.rawValue).com".lowercased(),
            "\(site.rawValue).ru".lowercased(),
            "vk video",
            "odnoklassniki"
        ])
        return siteNames.contains(lower) ? nil : cleaned
    }

    private static func publishedDate(fromHTML html: String, object: Any?) -> String? {
        let raw = metaContent(
            from: html,
            names: [
                "article:published_time", "article:modified_time",
                "datepublished", "datePublished", "uploadDate", "pubdate",
                "publishdate", "published_time", "date"
            ]
        ) ?? stringValue(
            named: [
                "uploadDate", "upload_date", "datePublished", "date_published",
                "publishedAt", "published_at", "publishDate", "publish_date",
                "createdAt", "created_at", "date"
            ],
            in: object
        )
        return normalizedDate(raw)
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

    private static func directMediaURLs(in text: String) -> [String] {
        var urls: [String] = []
        var seen = Set<String>()
        func append(_ value: String) {
            if seen.insert(value).inserted {
                urls.append(value)
            }
        }
        let patterns = [
            #"https?:\\/\\/[^'"\s<>]+?\.(?:mpd|mp4|m4v|webm|mov|m3u8)(?:\?[^'"\s<>]*)?"#,
            #"https?://[^'"\s<>]+?\.(?:mpd|mp4|m4v|webm|mov|m3u8)(?:\?[^'"\s<>]*)?"#,
            #"\\/\\/[^'"\s<>]+?\.(?:mpd|mp4|m4v|webm|mov|m3u8)(?:\?[^'"\s<>]*)?"#,
            #"//[^'"\s<>]+?\.(?:mpd|mp4|m4v|webm|mov|m3u8)(?:\?[^'"\s<>]*)?"#
        ]
        for pattern in patterns {
            for url in allCaptures(pattern: pattern, in: text, group: 0) {
                append(url)
            }
        }

        let relativePattern = #"/(?!/)[^'"\s<>]+?\.(?:mpd|mp4|m4v|webm|mov|m3u8)(?:\?[^'"\s<>]*)?"#
        let allowedPrevious: Set<Character> = ["\"", "'", "`", "=", "(", "[", "{", ",", " ", "\n", "\r", "\t"]
        if let regex = try? NSRegularExpression(pattern: relativePattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in regex.matches(in: text, range: range) {
                guard let capture = Range(match.range(at: 0), in: text) else { continue }
                if capture.lowerBound > text.startIndex {
                    let previous = text[text.index(before: capture.lowerBound)]
                    guard allowedPrevious.contains(previous) else { continue }
                }
                append(String(text[capture]))
            }
        }
        return urls
    }

    private static func scriptJSONObjects(in html: String) -> [Any] {
        let scriptPattern = #"<script\b[^>]*>(.*?)</script>"#
        var objects: [Any] = []
        for script in allCaptures(pattern: scriptPattern, in: html) {
            for objectText in balancedJSONObjects(in: script) + balancedJSONArrays(in: script) {
                guard hasMediaJSONHints(objectText),
                      let data = objectText.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) else {
                    continue
                }
                objects.append(object)
            }
        }
        return objects
    }

    private static func attributeJSONObjects(in html: String) -> [Any] {
        let attributes = [
            "data-setup",
            "data-sources",
            "data-options",
            "data-config",
            "data-player",
            "data-video-sources",
            "data-files"
        ]
        var objects: [Any] = []
        let tagPattern = #"<[A-Za-z][^>]*(?:data-setup|data-sources|data-options|data-config|data-player|data-video-sources|data-files)\s*=[^>]*>"#
        for tag in allCaptures(pattern: tagPattern, in: html, group: 0) {
            for attribute in attributes {
                guard let raw = attributeValue(attribute, in: tag) else { continue }
                objects.append(contentsOf: jsonObjects(inAttributeValue: raw))
            }
        }
        return objects
    }

    private static func jsonObjects(inAttributeValue raw: String) -> [Any] {
        let text = normalizeEscapes(decodeHTML(raw)).trimmed
        guard hasMediaJSONHints(text) else {
            return []
        }

        var objects: [Any] = []
        if let direct = jsonObject(from: text) {
            objects.append(direct)
        }
        for fragment in balancedJSONObjects(in: text) + balancedJSONArrays(in: text) {
            guard fragment != text,
                  let object = jsonObject(from: fragment) else {
                continue
            }
            objects.append(object)
        }
        return objects
    }

    private static func hasMediaJSONHints(_ text: String) -> Bool {
        text.contains(".mp4") ||
            text.contains(".m3u8") ||
            text.contains(".webm") ||
            text.contains("main_url") ||
            text.contains("mainUrl") ||
            text.contains("fallback_url") ||
            text.contains("fallbackUrl") ||
            text.contains("hls_url") ||
            text.contains("hlsUrl") ||
            text.contains("dashUrl") ||
            text.contains("hlsManifest") ||
            text.contains("manifestUrl") ||
            text.contains("playbackUrl") ||
            text.contains("playback_url") ||
            text.contains("renditions") ||
            text.contains("video_url") ||
            text.contains("videoUrl") ||
            text.contains("videoUri") ||
            text.contains("contentUrl") ||
            text.contains("content_url") ||
            text.contains("playAddr") ||
            text.contains("movie_url") ||
            text.contains("movieUrl") ||
            text.contains("streamUrl") ||
            text.contains("mediaUrl") ||
            text.contains("fileUrl") ||
            text.contains("sourceUrl") ||
            text.contains("assetUrl") ||
            text.contains("cdnUrl") ||
            text.contains("secureUrl") ||
            text.contains("secure_url") ||
            text.contains("srcUrl") ||
            text.contains("src_url") ||
            text.contains("sources")
    }

    private static func jsonObject(from text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func balancedJSONObjects(in text: String) -> [String] {
        balancedJSONFragments(in: text, opening: "{", closing: "}")
    }

    private static func balancedJSONArrays(in text: String) -> [String] {
        balancedJSONFragments(in: text, opening: "[", closing: "]")
    }

    private static func balancedJSONFragments(in text: String, opening: Character, closing: Character) -> [String] {
        var objects: [String] = []
        var index = text.startIndex
        while index < text.endIndex {
            guard text[index] == opening else {
                index = text.index(after: index)
                continue
            }

            let start = index
            var cursor = index
            var depth = 0
            var inString: Character?
            var escaped = false
            while cursor < text.endIndex {
                let char = text[cursor]
                if let quote = inString {
                    if escaped {
                        escaped = false
                    } else if char == "\\" {
                        escaped = true
                    } else if char == quote {
                        inString = nil
                    }
                    cursor = text.index(after: cursor)
                    continue
                }

                if char == "\"" || char == "'" {
                    inString = char
                } else if char == opening {
                    depth += 1
                } else if char == closing {
                    depth -= 1
                    if depth == 0 {
                        objects.append(String(text[start...cursor]))
                        index = text.index(after: cursor)
                        break
                    }
                }
                cursor = text.index(after: cursor)
            }
            if cursor >= text.endIndex {
                break
            }
        }
        return objects
    }

    private static func stringValue(named names: [String], in object: Any?) -> String? {
        guard let object else { return nil }
        if let dict = object as? [String: Any] {
            for name in names {
                if let value = stringValue(dict[name])?.trimmed, !value.isEmpty {
                    return value
                }
            }
            for value in dict.values {
                if let found = stringValue(named: names, in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = stringValue(named: names, in: value) {
                    return found
                }
            }
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func positiveInt(_ value: Any?) -> Int {
        guard let text = stringValue(value)?.trimmed,
              let match = firstCapture(pattern: #"([0-9]{2,5})"#, in: text),
              let number = Int(match),
              number > 0 else {
            return 0
        }
        return number
    }

    private static func qualityFrom(label: String, url: URL) -> Int {
        let text = "\(label) \(url.absoluteString)".lowercased()
        if text.contains("source") || text.contains("original") {
            return 10_000
        }
        return firstCapture(pattern: #"^([0-9]{3,4})$"#, in: text).flatMap(Int.init) ??
            firstCapture(pattern: #"([0-9]{3,4})\s*p"#, in: text).flatMap(Int.init) ??
            firstCapture(pattern: #"[^\d]([0-9]{3,4})(?:[^\d]|$)"#, in: text).flatMap(Int.init) ??
            0
    }

    private static func metaContent(from html: String, names: [String]) -> String? {
        for name in names {
            let escaped = NSRegularExpression.escapedPattern(for: name)
            let patterns = [
                #"<meta\b[^>]*(?:property|name|itemprop)\s*=\s*["']\#(escaped)["'][^>]*content\s*=\s*["']([^"']+)["'][^>]*>"#,
                #"<meta\b[^>]*content\s*=\s*["']([^"']+)["'][^>]*(?:property|name|itemprop)\s*=\s*["']\#(escaped)["'][^>]*>"#
            ]
            for pattern in patterns {
                if let value = firstCapture(pattern: pattern, in: html) {
                    return decodeHTML(value).trimmed
                }
            }
        }
        return nil
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let raw = firstCapture(pattern: pattern, in: html) else { return nil }
        let text = stripTags(decodeHTML(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        return text.isEmpty ? nil : text
    }

    private static func attributeValue(_ name: String, in tag: String) -> String? {
        let escaped = NSRegularExpression.escapedPattern(for: name)
        return firstCapture(pattern: #"\b\#(escaped)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#, in: tag, groups: [1, 2, 3])
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        var value = normalizeEscapes(decodeHTML(raw)).trimmed
        guard !value.isEmpty,
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("data:"),
              !value.lowercased().hasPrefix("blob:") else {
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

    private static func isPlayableVideo(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let text = url.absoluteString.lowercased()
        return ["mpd", "m3u8", "mp4", "webm", "mov", "m4v"].contains(ext) ||
            text.contains(".mpd") ||
            text.contains(".m3u8") ||
            text.contains(".mp4") ||
            text.contains(".webm")
    }

    private static func isImageURL(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let text = url.absoluteString.lowercased()
        return ["jpg", "jpeg", "png", "webp", "gif"].contains(ext) ||
            text.contains(".jpg") ||
            text.contains(".jpeg") ||
            text.contains(".png") ||
            text.contains(".webp") ||
            text.contains(".gif")
    }

    private static func isM3U8(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "m3u8" || url.absoluteString.lowercased().contains(".m3u8")
    }

    private static func isM3U8(_ candidate: EtcVideoCandidate, site: Site) -> Bool {
        isM3U8(candidate.url) ||
            (site.usesOriginalMP4HLSPostProcessing && candidate.protocolHint.lowercased().contains("m3u8"))
    }

    private static func isMPD(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "mpd" || url.absoluteString.lowercased().contains(".mpd")
    }

    private static func mediaKind(for url: URL) -> String {
        if isMPD(url) { return "dash" }
        if isM3U8(url) { return "hls" }
        return "video"
    }

    private static func mediaKind(for candidate: EtcVideoCandidate, site: Site) -> String {
        if isMPD(candidate.url) { return "dash" }
        if isM3U8(candidate, site: site) { return "hls" }
        return "video"
    }

    private static func mediaFormat(for url: URL) -> String {
        if isMPD(url) { return "mpd" }
        if isM3U8(url) { return "m3u8" }
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private static func mediaFormat(for candidate: EtcVideoCandidate, site: Site) -> String {
        if isMPD(candidate.url) { return "mpd" }
        if isM3U8(candidate, site: site) { return "m3u8" }
        let ext = candidate.url.pathExtension.lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private static func mediaFormat(for url: URL, fallback: String) -> String {
        let ext = url.pathExtension.trimmed
        return (ext.isEmpty ? fallback : ext).lowercased()
    }

    private static func mediaFormat(forFilename filename: String, fallback: String) -> String {
        let ext = URL(fileURLWithPath: filename).pathExtension.trimmed
        return ext.isEmpty ? fallback : ext.lowercased()
    }

    private static func mediaFormat(forImageURL url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        guard !ext.isEmpty else { return "jpg" }
        return ext == "jpeg" ? "jpg" : ext
    }

    private static func widthString(for candidate: EtcVideoCandidate) -> String {
        candidate.width > 0 ? String(candidate.width) : ""
    }

    private static func heightString(for candidate: EtcVideoCandidate) -> String {
        candidate.height > 0 ? String(candidate.height) : ""
    }

    private static func resolution(for candidate: EtcVideoCandidate) -> String? {
        if candidate.width > 0, candidate.height > 0 {
            return "\(candidate.width)x\(candidate.height)"
        }
        if candidate.height > 0 {
            return "\(candidate.height)p"
        }
        if candidate.quality > 0, candidate.quality < 10_000 {
            return "\(candidate.quality)p"
        }
        return nil
    }

    private static func normalizeEscapes(_ raw: String) -> String {
        raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\\/"#, with: "/")
            .replacingOccurrences(of: #"\u002F"#, with: "/")
            .replacingOccurrences(of: #"\u002f"#, with: "/")
    }

    private static func cleanTitle(_ raw: String, site: Site, fallback: String) -> String {
        var text = stripTags(decodeHTML(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in site.titleSuffixes {
            if text.lowercased().hasSuffix(suffix.lowercased()) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
        }
        return text.isEmpty ? fallback.sanitizedFilename(maxLength: 120) : text.sanitizedFilename(maxLength: 120)
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

    private static func firstCapture(pattern: String, in text: String) -> String? {
        firstCapture(pattern: pattern, in: text, groups: [1])
    }

    private static func firstCapture(pattern: String, in text: String, groups: [Int]) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range) else {
            return nil
        }
        for group in groups {
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else {
                continue
            }
            return String(text[capture])
        }
        return nil
    }

    private static func allCaptures(pattern: String, in text: String, group: Int = 1) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > group,
                  let capture = Range(match.range(at: group), in: text) else {
                return nil
            }
            return String(text[capture])
        }
    }

    private static func isValidSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isIxiguaVideoID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{6,}$"#, options: .regularExpression) != nil
    }

    private static func isNiconicoLiveID(_ value: String) -> Bool {
        value.range(of: #"^lv[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func contentID(fromPathComponent raw: String) -> String? {
        let value = raw
            .replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
            .trimmed
        let pieces = value.split(separator: ":").map(String.init).filter { !$0.isEmpty }
        let candidate = pieces.last ?? value
        guard !candidate.isEmpty else { return nil }
        return candidate.sanitizedFilename(maxLength: 120)
    }

    private static func isTokyoMotionAlbumURL(_ url: URL) -> Bool {
        guard site(for: url) == .tokyomotion else { return false }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        return parts.first?.lowercased() == "album"
    }

    private static func tokyoMotionAlbumID(from url: URL) -> String? {
        guard isTokyoMotionAlbumURL(url) else { return nil }
        let path = (url.path.removingPercentEncoding ?? url.path)
            .replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
        let afterAlbum = path.replacingOccurrences(
            of: #"^/album/"#,
            with: "",
            options: [.regularExpression, .caseInsensitive]
        )
        if afterAlbum.lowercased().hasPrefix("slideshow/") {
            let value = String(afterAlbum.dropFirst("slideshow/".count))
            if let id = firstCapture(pattern: #"([0-9A-Za-z_-]+)"#, in: value) {
                return id.sanitizedFilename(maxLength: 120)
            }
        }
        if let id = firstCapture(pattern: #"([0-9]{1,})"#, in: afterAlbum) {
            return id.sanitizedFilename(maxLength: 120)
        }
        let parts = afterAlbum.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let fallback = parts.first, isValidSlug(fallback) else { return nil }
        return fallback.sanitizedFilename(maxLength: 120)
    }

    private static func tokyoMotionSlideshowURL(pageURL: URL, albumID: String) -> URL {
        var components = URLComponents()
        components.scheme = pageURL.scheme ?? "https"
        components.host = pageURL.host
        components.path = "/album/slideshow/\(albumID)"
        return components.url ?? pageURL
    }

    private static func idAfterMarker(in parts: [String], lower: [String], markers: Set<String>) -> String? {
        for marker in markers {
            guard let index = lower.firstIndex(of: marker),
                  index + 1 < parts.count else {
                continue
            }
            let id = parts[index + 1]
                .replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
                .trimmed
            guard isValidSlug(id) else { continue }
            return id
        }
        return nil
    }

    private static func queryItem(named names: Set<String>, in url: URL) -> String? {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        for item in items {
            guard names.contains(item.name.lowercased()),
                  let value = item.value?.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func isAvgleHost(_ host: String) -> Bool {
        host == "avgle.com" ||
            host == "www.avgle.com" ||
            host == "avgle.test" ||
            host == "www.avgle.test"
    }

    private static func isBitChuteHost(_ host: String) -> Bool {
        host == "bitchute.com" ||
            host == "www.bitchute.com" ||
            host == "bitchute.test" ||
            host == "www.bitchute.test"
    }

    private static func isDailymotionHost(_ host: String) -> Bool {
        host == "dailymotion.com" ||
            host == "www.dailymotion.com" ||
            host == "dailymotion.test" ||
            host == "www.dailymotion.test" ||
            isDaiLyHost(host)
    }

    private static func isDaiLyHost(_ host: String) -> Bool {
        host == "dai.ly" ||
            host == "www.dai.ly" ||
            host == "dai.test" ||
            host == "www.dai.test"
    }

    private static func isKickHost(_ host: String) -> Bool {
        host == "kick.com" ||
            host == "www.kick.com" ||
            host == "kick.test" ||
            host == "www.kick.test"
    }

    private static func isKissJAVHost(_ host: String) -> Bool {
        KissJAVResolver.isSupportedHost(host)
    }

    private static func isOdyseeHost(_ host: String) -> Bool {
        host == "odysee.com" ||
            host == "www.odysee.com" ||
            host == "odysee.test" ||
            host == "www.odysee.test"
    }

    private static func isOKRUHost(_ host: String) -> Bool {
        host == "ok.ru" ||
            host == "www.ok.ru" ||
            host == "ok.test" ||
            host == "www.ok.test"
    }

    private static func isRedditHost(_ host: String) -> Bool {
        host == "reddit.com" ||
            host == "www.reddit.com" ||
            host == "old.reddit.com" ||
            host == "redd.it" ||
            host == "reddit.test" ||
            host == "www.reddit.test" ||
            host == "old.reddit.test" ||
            isRedditShortHost(host) ||
            isVRedditHost(host)
    }

    private static func isRedditShortHost(_ host: String) -> Bool {
        host == "redd.it" ||
            host == "redd.test"
    }

    private static func isVRedditHost(_ host: String) -> Bool {
        host == "v.redd.it" ||
            host == "v.redd.test"
    }

    private static func isRumbleHost(_ host: String) -> Bool {
        host == "rumble.com" ||
            host == "www.rumble.com" ||
            host == "rumble.test" ||
            host == "www.rumble.test"
    }

    private static func isRutubeHost(_ host: String) -> Bool {
        host == "rutube.ru" ||
            host == "www.rutube.ru" ||
            host == "rutube.test" ||
            host == "www.rutube.test"
    }

    private static func isNiconicoLiveHost(_ host: String) -> Bool {
        host == "live.nicovideo.jp" ||
            host == "live2.nicovideo.jp" ||
            host == "live.nicovideo.test" ||
            host == "live2.nicovideo.test"
    }

    private static func isStreamableHost(_ host: String) -> Bool {
        host == "streamable.com" ||
            host == "www.streamable.com" ||
            host == "streamable.test" ||
            host == "www.streamable.test"
    }

    private static func isThisVidHost(_ host: String) -> Bool {
        host == "thisvid.com" ||
            host == "www.thisvid.com" ||
            host.hasSuffix(".thisvid.com") ||
            host == "thisvid.test" ||
            host == "www.thisvid.test"
    }

    private static func isTokyoMotionHost(_ host: String) -> Bool {
        TokyoMotionResolver.isSupportedHost(host)
    }

    private static func isTwitCastingHost(_ host: String) -> Bool {
        host == "twitcasting.tv" ||
            host == "www.twitcasting.tv" ||
            host == "twitcasting.test" ||
            host == "www.twitcasting.test"
    }

    private static func isIxiguaHost(_ host: String) -> Bool {
        host == "ixigua.com" ||
            host == "www.ixigua.com" ||
            host == "m.ixigua.com" ||
            host.hasSuffix(".ixigua.com") ||
            host == "ixigua.test" ||
            host == "www.ixigua.test" ||
            host == "m.ixigua.test"
    }

    private static func isTVerHost(_ host: String) -> Bool {
        host == "tver.jp" ||
            host == "www.tver.jp" ||
            host == "tver.test" ||
            host == "www.tver.test"
    }

    private static func isVKHost(_ host: String) -> Bool {
        host == "vk.com" ||
            host == "www.vk.com" ||
            host == "vkvideo.ru" ||
            host == "www.vkvideo.ru" ||
            host == "vk.test" ||
            host == "www.vk.test" ||
            host == "vkvideo.test" ||
            host == "www.vkvideo.test"
    }

    private static func isXHamsterHost(_ host: String) -> Bool {
        if host == "xhamster.test" || host == "www.xhamster.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain.range(of: #"^[a-z0-9]{2,24}$"#, options: .regularExpression) != nil else {
            return false
        }
        return base.range(
            of: #"^(xhamster|xhwebsite|xhofficial|xhlocal|xhopen|xhtotal|megaxh|xhwide|xhtab|xhtime|xhamsterlive)[0-9]*$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isYourPornHost(_ host: String) -> Bool {
        host == "yourporn.sexy" ||
            host == "www.yourporn.sexy" ||
            host.hasSuffix(".yourporn.sexy") ||
            host == "yourporn.test" ||
            host == "www.yourporn.test"
    }

    private static func isYouPornHost(_ host: String) -> Bool {
        host == "youporn.com" ||
            host == "www.youporn.com" ||
            host.hasSuffix(".youporn.com") ||
            host == "youporn.test" ||
            host == "www.youporn.test" ||
            host.hasSuffix(".youporn.test")
    }

    private static func isYoukuHost(_ host: String) -> Bool {
        host == "youku.com" ||
            host == "www.youku.com" ||
            host == "v.youku.com" ||
            host == "youku.test" ||
            host == "www.youku.test" ||
            host == "v.youku.test"
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .split(separator: ".")
            .map { String($0).lowercased() }
            .filter { !$0.isEmpty }
        return labels.isEmpty ? nil : labels
    }
}

private extension EtcVideoCandidate {
    var isDirectVideo: Bool {
        ["mp4", "m4v", "webm", "mov"].contains(url.pathExtension.lowercased())
    }
}
