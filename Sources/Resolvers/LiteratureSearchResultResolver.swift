import Foundation

struct LiteratureSearchResultResolver: SearchResultResolving {
    private enum Site {
        case narou
        case kakuyomu
        case hameln
        case comicWalker
    }

    func supports(_ baseURL: URL) -> Bool {
        site(for: baseURL) != nil
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased() else {
            return nil
        }

        if isNarouHost(host),
           let entry = narouDataAttributeEntry(in: attributes),
           narouDataAttributeLooksLikeNovelCard(attributes) {
            if let chapter = entry.chapter {
                return "/\(entry.ncode)/\(chapter)/"
            }
            return "/\(entry.ncode)/"
        }

        if isKakuyomuHost(host),
           let entry = kakuyomuDataAttributeEntry(
               in: attributes,
               baseURL: baseURL
           ),
           kakuyomuDataAttributeLooksLikeWorkCard(attributes) {
            if let episodeID = entry.episodeID {
                return "/works/\(entry.workID)/episodes/\(episodeID)"
            }
            return "/works/\(entry.workID)"
        }

        if isHamelnHost(host),
           let entry = hamelnDataAttributeEntry(
               in: attributes,
               baseURL: baseURL
           ),
           hamelnDataAttributeLooksLikeNovelCard(attributes) {
            if let page = entry.page {
                return "/novel/\(entry.novelID)/\(page)/"
            }
            return "/novel/\(entry.novelID)/"
        }

        if isComicWalkerHost(host) {
            if let episodeID = comicWalkerDataAttributeEpisodeID(
                in: attributes
            ),
               comicWalkerDataAttributeLooksLikeEpisodeCard(attributes) {
                return "/episodes/\(episodeID)"
            }
            if let workID = comicWalkerDataAttributeWorkID(
                in: attributes
            ),
               comicWalkerDataAttributeLooksLikeWorkCard(attributes) {
                return "/contents/detail/\(workID)"
            }
        }

        return nil
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        guard let site = site(for: context.baseURL) else { return [] }

        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let target = canonicalURL(from: absolute, site: site) else {
                continue
            }

            let title = context.title(for: anchor, fallbackURL: target)
            let prefix = sitePrefix(for: site)
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultKey(for: target, site: site),
                sitePrefix: prefix,
                results: &results,
                indexByID: &indexByKey,
                metadata: metadata(
                    for: target,
                    site: site,
                    title: title,
                    contributorMetadata: context.contributorMetadata(for: anchor)
                )
            )
        }

        return results
    }

    private func site(for url: URL) -> Site? {
        guard let host = url.host?.lowercased() else { return nil }
        if Self.isNarouHost(host) {
            return .narou
        }
        if Self.isKakuyomuHost(host) {
            return .kakuyomu
        }
        if Self.isHamelnHost(host) {
            return .hameln
        }
        if Self.isComicWalkerHost(host) {
            return .comicWalker
        }
        return nil
    }

    private func sitePrefix(for site: Site) -> String {
        switch site {
        case .narou:
            return "narou"
        case .kakuyomu:
            return "kakuyomu"
        case .hameln:
            return "hameln"
        case .comicWalker:
            return "comicwalker"
        }
    }

    private func canonicalURL(from url: URL, site: Site) -> URL? {
        switch site {
        case .narou:
            return narouURL(from: url)
        case .kakuyomu:
            return kakuyomuURL(from: url)
        case .hameln:
            return hamelnURL(from: url)
        case .comicWalker:
            return comicWalkerURL(from: url)
        }
    }

    private func resultKey(for url: URL, site: Site) -> String {
        switch site {
        case .narou:
            let ncode = NarouResolver.ncode(from: url) ?? url.path
            if let chapter = NarouResolver.chapterNumber(from: url) {
                return "\(ncode):\(chapter)"
            }
            return ncode
        case .kakuyomu:
            let work = KakuyomuResolver.workID(from: url) ?? url.path
            if let episode = KakuyomuResolver.episodeID(from: url) {
                return "\(work):\(episode)"
            }
            return work
        case .hameln:
            let novel = HamelnResolver.novelID(from: url) ?? url.path
            if let page = HamelnResolver.pageNumber(from: url) {
                return "\(novel):\(page)"
            }
            return novel
        case .comicWalker:
            if let episode = ComicWalkerResolver.episodeID(from: url) {
                return "episode:\(episode)"
            }
            if let work = ComicWalkerResolver.workID(from: url) {
                return "work:\(work)"
            }
            return url.absoluteString.lowercased()
        }
    }

    private func metadata(
        for target: URL,
        site: Site,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        switch site {
        case .narou:
            return narouMetadata(
                target: target,
                title: title,
                contributorMetadata: contributorMetadata
            )
        case .kakuyomu:
            return kakuyomuMetadata(
                target: target,
                title: title,
                contributorMetadata: contributorMetadata
            )
        case .hameln:
            return hamelnMetadata(
                target: target,
                title: title,
                contributorMetadata: contributorMetadata
            )
        case .comicWalker:
            return comicWalkerMetadata(
                target: target,
                title: title,
                contributorMetadata: contributorMetadata
            )
        }
    }

    private func narouURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), Self.isNarouHost(host),
              let ncode = NarouResolver.ncode(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test")
            ? host
            : (host.contains("novel18") ? "novel18.syosetu.com" : "ncode.syosetu.com")
        if let chapter = NarouResolver.chapterNumber(from: url) {
            components.path = "/\(ncode)/\(chapter)/"
        } else {
            components.path = "/\(ncode)/"
        }
        return components.url
    }

    private func kakuyomuURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), Self.isKakuyomuHost(host),
              let workID = KakuyomuResolver.workID(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "kakuyomu.test" : "kakuyomu.jp"
        if let episodeID = KakuyomuResolver.episodeID(from: url) {
            components.path = "/works/\(workID)/episodes/\(episodeID)"
        } else {
            components.path = "/works/\(workID)"
        }
        return components.url
    }

    private func hamelnURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), Self.isHamelnHost(host),
              let novelID = HamelnResolver.novelID(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "syosetu.test" : "syosetu.org"
        if let page = HamelnResolver.pageNumber(from: url) {
            components.path = "/novel/\(novelID)/\(page)/"
        } else {
            components.path = "/novel/\(novelID)/"
        }
        return components.url
    }

    private func comicWalkerURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), Self.isComicWalkerHost(host) else { return nil }
        let canonicalHost = host.hasSuffix(".test") ? "comic-walker.test" : "comic-walker.com"

        if ComicWalkerResolver.episodeID(from: url) != nil {
            return ComicWalkerResolver.canonicalInputURL(for: url)
        }

        guard ComicWalkerResolver.workID(from: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = canonicalHost
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private func narouMetadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        guard let ncode = NarouResolver.ncode(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = contributorMetadata
        metadata.merge([
            "id": ncode,
            "post_id": ncode,
            "work_id": ncode,
            "novel_id": ncode,
            "ncode": ncode,
            "gallery_id": ncode,
            "media_id": ncode,
            "category": "narou",
            "type": "novel",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let chapter = NarouResolver.chapterNumber(from: target) {
            let chapterID = String(chapter)
            metadata["id"] = chapterID
            metadata["post_id"] = chapterID
            metadata["episode_id"] = chapterID
            metadata["chapter_id"] = chapterID
            metadata["media_id"] = chapterID
            metadata["page"] = chapterID
            metadata["position"] = chapterID
            metadata["type"] = "chapter"
        }
        return DownloadMetadata.clean(metadata)
    }

    private func kakuyomuMetadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        guard let workID = KakuyomuResolver.workID(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = contributorMetadata
        metadata.merge([
            "id": workID,
            "work_id": workID,
            "gallery_id": workID,
            "category": "kakuyomu",
            "type": "work",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let episodeID = KakuyomuResolver.episodeID(from: target) {
            metadata["id"] = episodeID
            metadata["post_id"] = episodeID
            metadata["episode_id"] = episodeID
            metadata["chapter_id"] = episodeID
            metadata["media_id"] = episodeID
            metadata["type"] = "episode"
        }
        return DownloadMetadata.clean(metadata)
    }

    private func hamelnMetadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        guard let novelID = HamelnResolver.novelID(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = contributorMetadata
        metadata.merge([
            "id": novelID,
            "post_id": novelID,
            "work_id": novelID,
            "novel_id": novelID,
            "gallery_id": novelID,
            "media_id": novelID,
            "category": "hameln",
            "type": "novel",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let page = HamelnResolver.pageNumber(from: target) {
            let episodeID = String(page)
            metadata["id"] = episodeID
            metadata["post_id"] = episodeID
            metadata["episode_id"] = episodeID
            metadata["chapter_id"] = episodeID
            metadata["media_id"] = episodeID
            metadata["page"] = episodeID
            metadata["position"] = episodeID
            metadata["type"] = "episode"
        }
        return DownloadMetadata.clean(metadata)
    }

    private func comicWalkerMetadata(
        target: URL,
        title: String,
        contributorMetadata: [String: String]
    ) -> [String: String] {
        var metadata = contributorMetadata
        metadata.merge([
            "category": "comicwalker",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let episodeID = ComicWalkerResolver.episodeID(from: target) {
            metadata["id"] = episodeID
            metadata["post_id"] = episodeID
            metadata["episode_id"] = episodeID
            metadata["chapter_id"] = episodeID
            metadata["media_id"] = episodeID
            metadata["gallery_id"] = episodeID
            metadata["slug"] = episodeID
            metadata["type"] = "episode"
        }
        if let workID = ComicWalkerResolver.workID(from: target) {
            metadata["id"] = metadata["id"] ?? workID
            metadata["work_id"] = workID
            metadata["gallery_id"] = metadata["gallery_id"] ?? workID
            metadata["slug"] = metadata["slug"] ?? workID
            metadata["type"] = metadata["type"] ?? "work"
        }
        return DownloadMetadata.clean(metadata)
    }

    static func isNarouHost(_ host: String) -> Bool {
        host == "ncode.syosetu.com" ||
            host == "yomou.syosetu.com" ||
            host == "novel18.syosetu.com" ||
            host == "ncode.syosetu.test" ||
            host == "yomou.syosetu.test" ||
            host == "novel18.syosetu.test"
    }

    static func isKakuyomuHost(_ host: String) -> Bool {
        host == "kakuyomu.jp" ||
            host == "www.kakuyomu.jp" ||
            host == "kakuyomu.test" ||
            host == "www.kakuyomu.test"
    }

    static func isHamelnHost(_ host: String) -> Bool {
        host == "syosetu.org" ||
            host == "www.syosetu.org" ||
            host == "syosetu.test" ||
            host == "www.syosetu.test"
    }

    static func isComicWalkerHost(_ host: String) -> Bool {
        host == "comic-walker.com" ||
            host == "comic-walker.jp" ||
            host == "www.comic-walker.com" ||
            host == "www.comic-walker.jp" ||
            host == "comic-walker.test"
    }

    private static func narouDataAttributeEntry(
        in attributes: [String: String]
    ) -> (ncode: String, chapter: Int?)? {
        let ncodeKeys = [
            "data-ncode", "data-novel-code", "data-novelcode",
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid", "ncode"
        ]
        let ncode = firstAttributeValue(
            in: attributes,
            keys: ncodeKeys,
            matching: isNarouNcode
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: [
                    "narou", "syosetu", "ncode", "novel", "work",
                    "chapter", "episode"
                ]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isNarouNcode
                )
                : nil)
        guard let ncode else { return nil }

        let chapterKeys = [
            "data-chapter", "data-chapter-id", "data-chapterid",
            "data-episode", "data-episode-id", "data-episodeid",
            "data-page", "data-page-id", "chapter-id", "episode-id"
        ]
        let rawChapter = firstAttributeValue(
            in: attributes,
            keys: chapterKeys,
            matching: isPositiveNumber
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["chapter", "episode"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isPositiveNumber
                )
                : nil)
        return (ncode, rawChapter.flatMap(Int.init))
    }

    private static func kakuyomuDataAttributeEntry(
        in attributes: [String: String],
        baseURL: URL
    ) -> (workID: String, episodeID: String?)? {
        let workKeys = [
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid", "data-series-id", "work-id"
        ]
        let workID = firstAttributeValue(
            in: attributes,
            keys: workKeys,
            matching: isKakuyomuID
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["kakuyomu", "work", "novel", "series"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isKakuyomuID
                )
                : nil) ??
            KakuyomuResolver.workID(from: baseURL)
        guard let workID else { return nil }

        let episodeKeys = [
            "data-episode-id", "data-episodeid", "data-episode",
            "data-chapter-id", "data-chapterid", "episode-id"
        ]
        let episodeID = firstAttributeValue(
            in: attributes,
            keys: episodeKeys,
            matching: isKakuyomuID
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["episode", "chapter"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isKakuyomuID
                )
                : nil)
        return (workID, episodeID)
    }

    private static func hamelnDataAttributeEntry(
        in attributes: [String: String],
        baseURL: URL
    ) -> (novelID: String, page: Int?)? {
        let novelKeys = [
            "data-novel-id", "data-novelid", "data-work-id",
            "data-workid", "data-story-id", "novel-id", "work-id"
        ]
        let novelID = firstAttributeValue(
            in: attributes,
            keys: novelKeys,
            matching: isPositiveNumber
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["hameln", "novel", "work", "story"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isPositiveNumber
                )
                : nil) ??
            HamelnResolver.novelID(from: baseURL)
        guard let novelID else { return nil }

        let pageKeys = [
            "data-page", "data-page-id", "data-pageid",
            "data-chapter", "data-chapter-id", "data-chapterid",
            "data-episode", "data-episode-id", "data-episodeid",
            "page-id", "chapter-id", "episode-id"
        ]
        let rawPage = firstAttributeValue(
            in: attributes,
            keys: pageKeys,
            matching: isPositiveNumber
        ) ??
            (typeHint(
                in: attributes,
                containsAnyOf: ["page", "chapter", "episode"]
            )
                ? firstAttributeValue(
                    in: attributes,
                    keys: ["data-id", "id"],
                    matching: isPositiveNumber
                )
                : nil)
        return (novelID, rawPage.flatMap(Int.init))
    }

    private static func comicWalkerDataAttributeEpisodeID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-episode-id", "data-episodeid", "data-episode",
            "data-chapter-id", "data-chapterid", "episode-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isComicWalkerEpisodeID
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: ["episode", "chapter"]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isComicWalkerEpisodeID
        )
    }

    private static func comicWalkerDataAttributeWorkID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-work-id", "data-workid", "data-content-id",
            "data-contentid", "data-series-id", "data-book-id",
            "work-id", "content-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isComicWalkerWorkID
        ) {
            return value
        }
        guard typeHint(
            in: attributes,
            containsAnyOf: [
                "work", "content", "detail", "series", "comic"
            ]
        ) else {
            return nil
        }
        return firstAttributeValue(
            in: attributes,
            keys: ["data-id", "id"],
            matching: isComicWalkerWorkID
        )
    }

    private static func narouDataAttributeLooksLikeNovelCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-ncode", "data-novel-code", "data-novelcode",
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [
                "narou", "syosetu", "ncode", "novel", "work",
                "chapter", "episode"
            ]
        )
    }

    private static func kakuyomuDataAttributeLooksLikeWorkCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid", "data-series-id", "data-episode-id",
            "data-episodeid"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [
                "kakuyomu", "work", "novel", "series", "episode",
                "chapter"
            ]
        )
    }

    private static func hamelnDataAttributeLooksLikeNovelCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-novel-id", "data-novelid", "data-work-id",
            "data-workid", "data-story-id", "data-page-id",
            "data-chapter-id", "data-episode-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [
                "hameln", "novel", "work", "story", "page",
                "chapter", "episode"
            ]
        )
    }

    private static func comicWalkerDataAttributeLooksLikeEpisodeCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-episode-id", "data-episodeid", "data-episode",
            "data-chapter-id", "data-chapterid", "episode-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["episode", "chapter"]
        )
    }

    private static func comicWalkerDataAttributeLooksLikeWorkCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-work-id", "data-workid", "data-content-id",
            "data-contentid", "data-series-id", "data-book-id",
            "work-id", "content-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: [
                "work", "content", "detail", "series", "comic"
            ]
        )
    }

    private static func isNarouNcode(_ value: String) -> Bool {
        value.range(
            of: #"^n[0-9]+[a-z]+$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func isPositiveNumber(_ value: String) -> Bool {
        guard value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil,
              let number = Int(value) else {
            return false
        }
        return number > 0
    }

    private static func isKakuyomuID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]{6,}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isComicWalkerEpisodeID(
        _ value: String
    ) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9_]{2,120}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isComicWalkerWorkID(_ value: String) -> Bool {
        isValidPathSlug(value) && value.count <= 160
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(
                of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#,
                options: .regularExpression
            ) != nil
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               predicate(value) {
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
        let values = keys.compactMap {
            attributes[$0]?.lowercased()
        }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }
}
