import Foundation

struct FacebookSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        if host == "fb.watch" || host == "www.fb.watch" {
            return true
        }
        if host == "facebook.test" ||
            host == "www.facebook.test" ||
            host == "m.facebook.test" ||
            host == "mbasic.facebook.test" {
            return true
        }
        let labels = host.split(separator: ".").map(String.init)
        guard labels.count >= 2,
              labels[labels.count - 2] == "facebook" else {
            return false
        }
        let topLevelDomain = labels[labels.count - 1]
        return topLevelDomain.range(
            of: #"^[a-z]{2,12}$"#,
            options: .regularExpression
        ) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }

        if let id = dataAttributePhotoID(in: attributes),
           dataAttributeLooksLikePhotoCard(attributes) {
            return "/photo.php?fbid=\(id)"
        }
        if let id = dataAttributeVideoID(in: attributes),
           dataAttributeLooksLikeVideoCard(attributes) {
            if typeHint(in: attributes, containsAnyOf: ["reel"]) {
                return "/reel/\(id)"
            }
            return "/watch/?v=\(id)"
        }
        return nil
    }

    static func mediaURL(from url: URL) -> URL? {
        videoURL(from: url) ?? photoURL(from: url)
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = Self.queueURL(from: absolute),
                  let key = Self.resultKey(for: target) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "facebook",
                results: &results,
                indexByID: &indexByID,
                metadata: metadata(
                    key: key,
                    title: title,
                    target: target,
                    contributorMetadata: context.contributorMetadata(
                        for: anchor
                    )
                )
            )
        }

        return results
    }

    private func metadata(
        key: String,
        title: String,
        target: URL,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "facebook",
            "title": title,
            "search_title": title
        ]
        if let photoID = FacebookPhotoResolver.photoID(from: target) {
            metadata["id"] = photoID
            metadata["photo_id"] = photoID
            metadata["media_id"] = photoID
            metadata["gallery_id"] = photoID
            metadata["type"] = "photo"
            metadata["media_type"] = "image"
        } else if let videoID = FacebookVideoResolver.videoID(from: target) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["gallery_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        }
        metadata.merge(contributorMetadata) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func queueURL(from url: URL) -> URL? {
        if let photoID = FacebookPhotoResolver.photoID(from: url) {
            return FacebookPhotoResolver.canonicalURL(
                photoID: photoID,
                sourceURL: url
            )
        }
        guard FacebookVideoResolver.videoID(from: url) != nil else {
            return nil
        }
        return videoURL(from: url)
    }

    private static func resultKey(for url: URL) -> String? {
        if let photoID = FacebookPhotoResolver.photoID(from: url) {
            return "photo-\(photoID)"
        }
        if let videoID = FacebookVideoResolver.videoID(from: url) {
            return "video-\(videoID)"
        }
        return nil
    }

    private static func videoURL(from url: URL) -> URL? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if url.host?.lowercased() == "fb.watch",
           !url.path.split(
               separator: "/",
               omittingEmptySubsequences: true
           ).isEmpty {
            return cleanedURL(url)
        }

        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if lower.first == "watch",
           let videoID = components.queryItems?.first(where: {
               $0.name.lowercased() == "v"
           })?.value?.trimmed,
           !videoID.isEmpty {
            var clean = components
            clean.path = "/watch/"
            clean.queryItems = [URLQueryItem(name: "v", value: videoID)]
            clean.fragment = nil
            return clean.url
        }

        if lower.first == "reel", parts.count >= 2 {
            return cleanedURL(url, path: "/reel/\(parts[1])")
        }

        if let marker = lower.firstIndex(of: "videos"),
           marker + 1 < parts.count {
            let prefix = marker > 0
                ? "/" + parts[..<marker].joined(separator: "/")
                : ""
            return cleanedURL(
                url,
                path: "\(prefix)/videos/\(parts[marker + 1])"
            )
        }

        return nil
    }

    private static func photoURL(from url: URL) -> URL? {
        guard let components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        let parts = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        let lower = parts.map { $0.lowercased() }

        if let photoID = components.queryItems?.first(where: {
            ["fbid", "photo_id", "photoId"].contains($0.name)
        })?.value?.trimmed,
           isPhotoID(photoID) {
            var clean = components
            clean.path = "/photo.php"
            clean.queryItems = [URLQueryItem(name: "fbid", value: photoID)]
            clean.fragment = nil
            return clean.url
        }

        guard let marker = lower.firstIndex(of: "photos") else {
            return nil
        }
        let after = parts[(marker + 1)...]
        guard after.contains(where: isPhotoID) else {
            return nil
        }
        return cleanedURL(url)
    }

    private static func dataAttributePhotoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-photo-id", "data-photoid", "data-fbid", "photo-id",
            "fbid"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isPhotoID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPhotoID(id),
           typeHint(in: attributes, containsAnyOf: ["photo", "image"]) {
            return id
        }
        return nil
    }

    private static func dataAttributeVideoID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-reel-id",
            "data-reelid", "video-id", "reel-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isVideoID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isVideoID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["video", "watch", "reel"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikePhotoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-photo-id", "data-photoid", "data-fbid", "photo-id",
            "fbid"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(in: attributes, containsAnyOf: ["photo", "image"])
    }

    private static func dataAttributeLooksLikeVideoCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-video-id", "data-videoid", "data-reel-id",
            "data-reelid", "video-id", "reel-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["video", "watch", "reel"]
        )
    }

    private static func isPhotoID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{4,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isVideoID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9._-]{3,}$"#,
            options: .regularExpression
        ) != nil &&
            ![
                "watch", "videos", "video.php", "reel", "reels",
                "photos", "photo.php", "share"
            ].contains(value.lowercased())
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed, predicate(value) {
                return value
            }
        }
        return nil
    }

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func cleanedURL(
        _ url: URL,
        path: String? = nil
    ) -> URL? {
        guard var components = URLComponents(
            url: url,
            resolvingAgainstBaseURL: false
        ) else {
            return nil
        }
        if let path {
            components.path = path
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }
}
