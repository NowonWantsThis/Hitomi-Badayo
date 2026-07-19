import Foundation

enum SearchResultExtractor {
    static func extractLinks(from html: String, baseURL: URL, limit: Int = 50) -> [SearchResultLink] {
        let resolutionBaseURL = documentBaseURL(from: html, fallback: baseURL)
        let anchors = anchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: resolutionBaseURL)
        let host = baseURL.host?.lowercased() ?? ""
        if isHitomiHost(host) {
            let hitomiLinks = extractHitomiGalleryLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !hitomiLinks.isEmpty {
                return hitomiLinks
            }
        }
        if isNHentaiHost(host) {
            let nhentaiLinks = extractNHentaiGalleryLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !nhentaiLinks.isEmpty {
                return nhentaiLinks
            }
        }
        if isNHentaiComHost(host) {
            let nhentaiComLinks = extractNHentaiComLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !nhentaiComLinks.isEmpty {
                return nhentaiComLinks
            }
        }
        if isEHentaiHost(host) {
            let ehentaiLinks = extractEHentaiGalleryLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !ehentaiLinks.isEmpty {
                return ehentaiLinks
            }
        }
        if isNozomiHost(host) {
            let nozomiLinks = extractNozomiPostLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !nozomiLinks.isEmpty {
                return nozomiLinks
            }
        }
        if BooruProvider.provider(for: baseURL) != nil {
            let booruLinks = extractBooruPostLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !booruLinks.isEmpty {
                return booruLinks
            }
        }
        if isPixivHost(host) {
            let pixivLinks = extractPixivArtworkLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !pixivLinks.isEmpty {
                return pixivLinks
            }
        }
        if isArtStationHost(host) {
            let artStationLinks = extractArtStationProjectLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !artStationLinks.isEmpty {
                return artStationLinks
            }
        }
        if isBCYHost(host) {
            let bcyLinks = extractBCYLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !bcyLinks.isEmpty {
                return bcyLinks
            }
        }
        if isFC2Host(host) {
            let fc2Links = extractFC2Links(from: anchors, baseURL: baseURL, limit: limit)
            if !fc2Links.isEmpty {
                return fc2Links
            }
        }
        if isDeviantArtHost(host) {
            let deviantArtLinks = extractDeviantArtLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !deviantArtLinks.isEmpty {
                return deviantArtLinks
            }
        }
        if isPinterestHost(host) {
            let pinterestLinks = extractPinterestPinLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !pinterestLinks.isEmpty {
                return pinterestLinks
            }
        }
        if isNewgroundsHost(host) {
            let newgroundsLinks = extractNewgroundsArtLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !newgroundsLinks.isEmpty {
                return newgroundsLinks
            }
        }
        if isFlickrHost(host) {
            let flickrLinks = extractFlickrPhotoLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !flickrLinks.isEmpty {
                return flickrLinks
            }
        }
        if isCoubHost(host) {
            let coubLinks = extractCoubLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !coubLinks.isEmpty {
                return coubLinks
            }
        }
        if isVimeoHost(host) {
            let vimeoLinks = extractVimeoLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !vimeoLinks.isEmpty {
                return vimeoLinks
            }
        }
        if isSoundCloudHost(host) {
            let soundCloudLinks = extractSoundCloudTrackLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !soundCloudLinks.isEmpty {
                return soundCloudLinks
            }
        }
        if isYouTubeHost(host) {
            let youtubeLinks = extractYouTubeLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !youtubeLinks.isEmpty {
                return youtubeLinks
            }
        }
        if isTwitterHost(host) {
            let twitterLinks = extractTwitterLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !twitterLinks.isEmpty {
                return twitterLinks
            }
        }
        if FediverseResolver.service(for: baseURL) != nil {
            let fediverseLinks = extractFediverseLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !fediverseLinks.isEmpty {
                return fediverseLinks
            }
        }
        if isTikTokHost(host) {
            let tikTokLinks = extractTikTokVideoLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !tikTokLinks.isEmpty {
                return tikTokLinks
            }
        }
        if isBilibiliHost(host) {
            let bilibiliLinks = extractBilibiliVideoLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !bilibiliLinks.isEmpty {
                return bilibiliLinks
            }
        }
        if isChzzkHost(host) {
            let chzzkLinks = extractChzzkClipLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !chzzkLinks.isEmpty {
                return chzzkLinks
            }
        }
        if isSOOPHost(host) {
            let soopLinks = extractSOOPVODLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !soopLinks.isEmpty {
                return soopLinks
            }
        }
        if isEtcVideoSearchHost(host) {
            let etcVideoLinks = extractEtcVideoPageLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !etcVideoLinks.isEmpty {
                return etcVideoLinks
            }
        }
        if isKakaoTVHost(host) {
            let kakaoTVLinks = extractKakaoTVLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !kakaoTVLinks.isEmpty {
                return kakaoTVLinks
            }
        }
        if isNiconicoHost(host) {
            let niconicoLinks = extractNiconicoLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !niconicoLinks.isEmpty {
                return niconicoLinks
            }
        }
        if isTwitchHost(host) {
            let twitchLinks = extractTwitchLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !twitchLinks.isEmpty {
                return twitchLinks
            }
        }
        if isIwaraHost(host) {
            let iwaraLinks = extractIwaraLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !iwaraLinks.isEmpty {
                return iwaraLinks
            }
        }
        if isInstagramHost(host) {
            let instagramLinks = extractInstagramLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !instagramLinks.isEmpty {
                return instagramLinks
            }
        }
        if isFacebookHost(host) {
            let facebookLinks = extractFacebookLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !facebookLinks.isEmpty {
                return facebookLinks
            }
        }
        if isPornhubHost(host) {
            let pornhubLinks = extractPornhubLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !pornhubLinks.isEmpty {
                return pornhubLinks
            }
        }
        if isWeiboHost(host) {
            let weiboLinks = extractWeiboLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !weiboLinks.isEmpty {
                return weiboLinks
            }
        }
        if isSpankBangHost(host) {
            let spankBangLinks = extractSpankBangLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !spankBangLinks.isEmpty {
                return spankBangLinks
            }
        }
        if isXVideosHost(host) || isXNXXHost(host) {
            let xVideoLinks = extractXVideoPageLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !xVideoLinks.isEmpty {
                return xVideoLinks
            }
        }
        if isOriginalYTDLPMediaSearchHost(host) {
            let mediaLinks = extractOriginalYTDLPMediaLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !mediaLinks.isEmpty {
                return mediaLinks
            }
        }
        if isImgurHost(host) {
            let imgurLinks = extractImgurContentLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !imgurLinks.isEmpty {
                return imgurLinks
            }
        }
        if isTumblrHost(host) {
            let tumblrLinks = extractTumblrBlogLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !tumblrLinks.isEmpty {
                return tumblrLinks
            }
        }
        if isFourChanHost(host) {
            let fourChanLinks = extractFourChanThreadLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !fourChanLinks.isEmpty {
                return fourChanLinks
            }
        }
        if isWikiArtHost(host) {
            let wikiArtLinks = extractWikiArtArtistLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !wikiArtLinks.isEmpty {
                return wikiArtLinks
            }
        }
        if isSankakuHost(host) {
            let sankakuLinks = extractSankakuPostLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !sankakuLinks.isEmpty {
                return sankakuLinks
            }
        }
        if isNijieHost(host) {
            let nijieLinks = extractNijieLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !nijieLinks.isEmpty {
                return nijieLinks
            }
        }
        if isV2PHHost(host) {
            let v2phLinks = extractV2PHAlbumLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !v2phLinks.isEmpty {
                return v2phLinks
            }
        }
        if isHentaiCosplayHost(host) {
            let hentaiCosplayLinks = extractHentaiCosplayContentLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !hentaiCosplayLinks.isEmpty {
                return hentaiCosplayLinks
            }
        }
        if isHentaiFoundryHost(host) {
            let hentaiFoundryLinks = extractHentaiFoundryLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !hentaiFoundryLinks.isEmpty {
                return hentaiFoundryLinks
            }
        }
        if isTalkOPGGHost(host) {
            let talkOPGGLinks = extractTalkOPGGArticleLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !talkOPGGLinks.isEmpty {
                return talkOPGGLinks
            }
        }
        if isAsmHentaiHost(host) {
            let asmHentaiLinks = extractAsmHentaiGalleryLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !asmHentaiLinks.isEmpty {
                return asmHentaiLinks
            }
        }
        if isMyReadingMangaHost(host) {
            let myReadingMangaLinks = extractMyReadingMangaPostLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !myReadingMangaLinks.isEmpty {
                return myReadingMangaLinks
            }
        }
        if isLusciousHost(host) {
            let lusciousLinks = extractLusciousContentLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !lusciousLinks.isEmpty {
                return lusciousLinks
            }
        }
        if isBDSMlrHost(host) {
            let bdsmlrLinks = extractBDSMlrLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !bdsmlrLinks.isEmpty {
                return bdsmlrLinks
            }
        }
        if isNarouHost(host) {
            let narouLinks = extractNarouLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !narouLinks.isEmpty {
                return narouLinks
            }
        }
        if isKakuyomuHost(host) {
            let kakuyomuLinks = extractKakuyomuLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !kakuyomuLinks.isEmpty {
                return kakuyomuLinks
            }
        }
        if isHamelnHost(host) {
            let hamelnLinks = extractHamelnLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !hamelnLinks.isEmpty {
                return hamelnLinks
            }
        }
        if isComicWalkerHost(host) {
            let comicWalkerLinks = extractComicWalkerLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !comicWalkerLinks.isEmpty {
                return comicWalkerLinks
            }
        }
        if isNaverBlogHost(host) {
            let naverBlogLinks = extractNaverBlogLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !naverBlogLinks.isEmpty {
                return naverBlogLinks
            }
        }
        if isNaverPostHost(host) {
            let naverPostLinks = extractNaverPostLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !naverPostLinks.isEmpty {
                return naverPostLinks
            }
        }
        if isNaverCafeHost(host) {
            let naverCafeLinks = extractNaverCafeLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !naverCafeLinks.isEmpty {
                return naverCafeLinks
            }
        }
        if isNaverTVHost(host) {
            let naverTVLinks = extractNaverTVLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !naverTVLinks.isEmpty {
                return naverTVLinks
            }
        }
        if isWebtoonHost(host) {
            let webtoonLinks = extractWebtoonLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !webtoonLinks.isEmpty {
                return webtoonLinks
            }
        }
        if isNaverWebtoonHost(host) {
            let naverWebtoonLinks = extractNaverWebtoonLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !naverWebtoonLinks.isEmpty {
                return naverWebtoonLinks
            }
        }
        if isPixivComicHost(host) {
            let pixivComicLinks = extractPixivComicLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !pixivComicLinks.isEmpty {
                return pixivComicLinks
            }
        }
        if isKakaoPageHost(host) {
            let kakaoPageLinks = extractKakaoPageLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !kakaoPageLinks.isEmpty {
                return kakaoPageLinks
            }
        }
        if isKakaoWebtoonHost(host) {
            let kakaoWebtoonLinks = extractKakaoWebtoonLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !kakaoWebtoonLinks.isEmpty {
                return kakaoWebtoonLinks
            }
        }
        if isHiyobiHost(host) {
            let hiyobiLinks = extractHiyobiGalleryLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !hiyobiLinks.isEmpty {
                return hiyobiLinks
            }
        }
        if isManatokiHost(host) {
            let manatokiLinks = extractManatokiLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !manatokiLinks.isEmpty {
                return manatokiLinks
            }
        }
        if isLHScanHost(host) {
            let lhScanLinks = extractLHScanLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !lhScanLinks.isEmpty {
                return lhScanLinks
            }
        }
        if isJManaHost(host) {
            let jManaLinks = extractJManaLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !jManaLinks.isEmpty {
                return jManaLinks
            }
        }
        if isWaybackMachineHost(host) {
            let waybackLinks = extractWaybackMachineLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !waybackLinks.isEmpty {
                return waybackLinks
            }
        }
        if isGoogleHost(host) {
            let googleLinks = extractGoogleRedirectLinks(from: anchors, baseURL: baseURL, limit: limit)
            if !googleLinks.isEmpty {
                return googleLinks
            }
        }

        var results: [SearchResultLink] = []
        var seen = Set<String>()

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            let normalized = URLIdentity.normalize(absolute.absoluteString)
            guard !seen.contains(normalized), isUseful(absolute) else { continue }

            seen.insert(normalized)
            let title = displayTitle(for: anchor, fallbackURL: absolute)
            results.append(SearchResultLink(
                title: title,
                url: absolute.absoluteString,
                metadata: genericFallbackSearchMetadata(searchPageURL: baseURL, target: absolute, title: title, anchor: anchor)
            ))
        }

        return results
    }

    private static func extractGoogleRedirectLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var seen = Set<String>()

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = googleSearchTargetURL(from: absolute) else {
                continue
            }

            let queueURL = googleSearchQueueURL(from: target)
            let normalized = URLIdentity.normalize(queueURL.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            let title = displayTitle(for: anchor, fallbackURL: queueURL)
            results.append(SearchResultLink(
                title: title,
                url: queueURL.absoluteString,
                siteIdentifier: "google",
                metadata: googleSearchMetadata(
                    searchPageURL: baseURL,
                    redirectURL: absolute,
                    targetURL: target,
                    queueURL: queueURL,
                    title: title,
                    anchor: anchor
                )
            ))
        }

        return results
    }

    private static func genericFallbackSearchMetadata(searchPageURL: URL, target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        let sourceHost = searchPageURL.host ?? ""
        let targetHost = target.host ?? ""
        metadata.merge([
            "source_url": target.absoluteString,
            "page_url": target.absoluteString,
            "search_page_url": searchPageURL.absoluteString,
            "search_site": sourceHost,
            "target_url": target.absoluteString,
            "target_host": targetHost,
            "host": targetHost,
            "category": "link",
            "type": "link",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func googleSearchMetadata(
        searchPageURL: URL,
        redirectURL: URL,
        targetURL: URL,
        queueURL: URL,
        title: String,
        anchor: AnchorEntry
    ) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        let targetHost = targetURL.host ?? ""
        metadata.merge([
            "site": "google",
            "search_site": "google",
            "source_url": queueURL.absoluteString,
            "page_url": queueURL.absoluteString,
            "search_page_url": searchPageURL.absoluteString,
            "redirect_url": redirectURL.absoluteString,
            "target_url": targetURL.absoluteString,
            "target_host": targetHost,
            "host": targetHost,
            "queue_url": queueURL.absoluteString,
            "category": "search_redirect",
            "type": "link",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if queueURL.absoluteString != targetURL.absoluteString {
            metadata["canonical_url"] = queueURL.absoluteString
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractCoubLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let id = CoubResolver.coubID(from: absolute),
                  let target = CoubResolver.canonicalViewURL(id: id, sourceURL: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Coub \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "coub",
                results: &results,
                indexByID: &indexByID,
                metadata: coubSearchMetadata(id: id, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractVimeoLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let id = VimeoResolver.videoID(from: absolute),
                  let target = vimeoVideoURL(id: id, sourceURL: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Vimeo \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "vimeo",
                results: &results,
                indexByID: &indexByID,
                metadata: vimeoSearchMetadata(id: id, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractSoundCloudTrackLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByTrack: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = soundCloudTrackURL(from: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            let trackKey = soundCloudTrackKey(for: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: trackKey,
                sitePrefix: "soundcloud",
                results: &results,
                indexByID: &indexByTrack,
                metadata: soundCloudSearchMetadata(trackKey: trackKey, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractYouTubeLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = youtubeQueueURL(from: absolute),
                  let key = youtubeResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "youtube",
                results: &results,
                indexByID: &indexByKey,
                metadata: youtubeSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractTwitterLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            if let id = TwitterResolver.tweetID(from: absolute),
               let target = cleanedURL(absolute) {
                let title = displayTitle(for: anchor, fallback: "Tweet \(id)")
                appendUniqueResult(
                    title: title,
                    url: target,
                    id: "tweet-\(id)",
                    sitePrefix: "tweet",
                    results: &results,
                    indexByID: &indexByKey,
                    metadata: twitterSearchMetadata(id: id, kind: "tweet", title: title, anchor: anchor, target: target)
                )
                continue
            }

            if let id = twitterSpaceID(from: absolute),
               let target = twitterSpaceURL(id: id, sourceURL: absolute) {
                let title = displayTitle(for: anchor, fallback: "Space \(id)")
                appendUniqueResult(
                    title: title,
                    url: target,
                    id: "space-\(id)",
                    sitePrefix: "space",
                    results: &results,
                    indexByID: &indexByKey,
                    metadata: twitterSearchMetadata(id: id, kind: "space", title: title, anchor: anchor, target: target)
                )
                continue
            }

            if let id = twitterBroadcastID(from: absolute),
               let target = twitterBroadcastURL(id: id, sourceURL: absolute) {
                let title = displayTitle(for: anchor, fallback: "Broadcast \(id)")
                appendUniqueResult(
                    title: title,
                    url: target,
                    id: "broadcast-\(id)",
                    sitePrefix: "broadcast",
                    results: &results,
                    indexByID: &indexByKey,
                    metadata: twitterSearchMetadata(id: id, kind: "broadcast", title: title, anchor: anchor, target: target)
                )
                continue
            }

            if let id = twitterUserID(from: absolute),
               let target = twitterUserURL(id: id, sourceURL: absolute) {
                let title = displayTitle(for: anchor, fallback: "User \(id)")
                appendUniqueResult(
                    title: title,
                    url: target,
                    id: "user-\(id)",
                    sitePrefix: "user",
                    results: &results,
                    indexByID: &indexByKey,
                    metadata: twitterSearchMetadata(id: id, kind: "user", title: title, anchor: anchor, target: target)
                )
            }
        }

        return results
    }

    private static func extractFediverseLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = fediverseURL(from: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: fediverseKey(for: target),
                sitePrefix: "fediverse",
                results: &results,
                indexByID: &indexByKey,
                metadata: fediverseSearchMetadata(target: target, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func fediverseSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        guard let service = FediverseResolver.service(for: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "category": service == .mastodon ? "mastodon" : "misskey",
            "site": service == .mastodon ? "mastodon" : "misskey",
            "title": title,
            "search_title": title
        ]) { current, _ in current }

        switch service {
        case .mastodon:
            if let statusID = FediverseResolver.mastodonStatusID(from: target) {
                metadata["id"] = statusID
                metadata["post_id"] = statusID
                metadata["status_id"] = statusID
                metadata["media_id"] = statusID
                metadata["gallery_id"] = statusID
                metadata["type"] = "status"
            } else if let accountID = FediverseResolver.mastodonAccountID(from: target) {
                metadata["id"] = accountID
                metadata["account_id"] = accountID
                metadata["user_id"] = accountID
                metadata["uploader_id"] = accountID
                metadata["gallery_id"] = accountID
                metadata["type"] = "account"
            } else if let username = FediverseResolver.mastodonUsername(from: target) {
                metadata["id"] = username
                metadata["username"] = username
                metadata["user"] = username
                metadata["uploader"] = metadata["uploader"] ?? username
                metadata["uploader_id"] = username
                metadata["channel_id"] = username
                metadata["gallery_id"] = username
                metadata["type"] = "profile"
            }

        case .misskey:
            if let noteID = FediverseResolver.misskeyNoteID(from: target) {
                metadata["id"] = noteID
                metadata["post_id"] = noteID
                metadata["note_id"] = noteID
                metadata["media_id"] = noteID
                metadata["gallery_id"] = noteID
                metadata["type"] = "note"
            } else if let username = FediverseResolver.misskeyUsername(from: target) {
                metadata["id"] = username
                metadata["username"] = username
                metadata["user"] = username
                metadata["uploader"] = metadata["uploader"] ?? username
                metadata["uploader_id"] = username
                metadata["channel_id"] = username
                metadata["gallery_id"] = username
                metadata["type"] = "profile"
            }
        }

        return DownloadMetadata.clean(metadata)
    }

    private static func extractTikTokVideoLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = TikTokResolver.canonicalContentURL(from: absolute) else {
                continue
            }

            let id: String
            let fallback: String
            if let videoID = TikTokResolver.videoID(from: target) {
                id = "video:\(videoID)"
                fallback = "TikTok \(videoID)"
            } else if let username = TikTokResolver.profileUsername(from: target) {
                id = "profile:\(username.lowercased())"
                fallback = "@\(username)"
            } else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: fallback)
            let metadataID = id.hasPrefix("video:")
                ? String(id.dropFirst("video:".count))
                : String(id.dropFirst("profile:".count))
            let kind = id.hasPrefix("video:") ? "video" : "profile"
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "tiktok",
                results: &results,
                indexByID: &indexByID,
                metadata: tikTokSearchMetadata(id: metadataID, kind: kind, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractBilibiliVideoLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let id = BilibiliResolver.videoID(from: absolute),
                  let target = BilibiliResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Bilibili \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "bilibili",
                results: &results,
                indexByID: &indexByID,
                metadata: bilibiliSearchMetadata(id: id, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractChzzkClipLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = ChzzkResolver.canonicalURL(for: absolute) ?? ChzzkResolver.canonicalLiveURL(for: absolute) else {
                continue
            }

            let id: String
            if let clipID = ChzzkResolver.clipID(from: absolute) {
                id = "clip-\(clipID)"
            } else if let vodID = ChzzkResolver.vodID(from: absolute) {
                id = "video-\(vodID)"
            } else if let liveID = ChzzkResolver.liveID(from: absolute) {
                id = "live-\(liveID)"
            } else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Chzzk \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "chzzk",
                results: &results,
                indexByID: &indexByID,
                metadata: chzzkSearchMetadata(id: id, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractSOOPVODLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            let id: String
            let target: URL
            if let videoID = SOOPVODResolver.videoID(from: absolute),
               let videoURL = soopVODURL(from: absolute) {
                id = videoID
                target = videoURL
            } else if let liveID = SOOPVODResolver.liveID(from: absolute) {
                id = "live-\(liveID)"
                target = SOOPVODResolver.canonicalLiveURL(liveID: liveID, sourceURL: absolute)
            } else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "SOOP \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "soop",
                results: &results,
                indexByID: &indexByID,
                metadata: soopSearchMetadata(id: id, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractEtcVideoPageLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let site = EtcVideoPageResolver.site(for: absolute),
                  isEtcVideoSearchSite(site),
                  !isEtcVideoNavigationURL(absolute, site: site),
                  let id = EtcVideoPageResolver.contentID(from: absolute),
                  let target = etcVideoPageURL(from: absolute, site: site, id: id) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "\(site.rawValue) \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: "\(site.rawValue.lowercased())-\(id)",
                sitePrefix: site.rawValue.lowercased(),
                results: &results,
                indexByID: &indexByKey,
                metadata: etcVideoSearchMetadata(id: id, site: site, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func appendUniqueResult(
        title: String,
        url: URL,
        id: String,
        sitePrefix: String,
        results: inout [SearchResultLink],
        indexByID: inout [String: Int],
        metadata extraMetadata: [String: String] = [:]
    ) {
        let metadata = searchResultMetadata(sitePrefix: sitePrefix, id: id, url: url)
            .merging(DownloadMetadata.clean(extraMetadata)) { current, _ in current }
        if let existingIndex = indexByID[id] {
            if isWeakGalleryTitle(results[existingIndex].title, id: id, sitePrefix: sitePrefix),
               !isWeakGalleryTitle(title, id: id, sitePrefix: sitePrefix) {
                results[existingIndex].title = title
                results[existingIndex].metadata["title"] = title
                results[existingIndex].metadata["search_title"] = title
            }
            results[existingIndex].metadata = metadata.merging(results[existingIndex].metadata) { _, existing in existing }
            return
        }

        indexByID[id] = results.count
        results.append(SearchResultLink(
            title: title,
            url: url.absoluteString,
            siteIdentifier: sitePrefix,
            metadata: metadata
        ))
    }

    private static func searchResultMetadata(sitePrefix: String, id: String, url: URL) -> [String: String] {
        DownloadMetadata.clean([
            "site": sitePrefix,
            "result_id": id,
            "source_url": url.absoluteString,
            "page_url": url.absoluteString,
            "search_site": sitePrefix,
            "search_result_id": id,
            "search_url": url.absoluteString
        ])
    }

    private static func searchContributorMetadata(
        anchor: AnchorEntry,
        fallbackName: String? = nil,
        fallbackUsername: String? = nil,
        fallbackUserID: String? = nil
    ) -> [String: String] {
        let attributes = semanticSearchAttributes(for: anchor)
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-channel-name", "channel-name", "channel",
            "data-uploader-name", "data-uploader", "uploader",
            "data-artist-name", "data-artist", "artist",
            "data-author-name", "data-author", "author",
            "data-creator-name", "data-creator", "creator",
            "data-user-name"
        ]) ?? fallbackName
        let username = firstSemanticAttribute(attributes, keys: [
            "data-channel", "data-channel-username",
            "data-username", "username",
            "data-user", "user",
            "data-owner", "owner"
        ]) ?? fallbackUsername
        let userID = firstSemanticAttribute(attributes, keys: [
            "data-channel-id", "channel-id",
            "data-uploader-id", "uploader-id",
            "data-user-id", "user-id",
            "data-uid", "uid"
        ]) ?? fallbackUserID
        var metadata: [String: String] = [:]
        if let displayName, !displayName.isEmpty {
            metadata["artist"] = displayName
            metadata["author"] = displayName
            metadata["creator"] = displayName
            metadata["uploader"] = displayName
            metadata["channel"] = displayName
        }
        if let username, !username.isEmpty {
            metadata["username"] = username
            metadata["user"] = username
        }
        if let userID, !userID.isEmpty {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
            metadata["channel_id"] = userID
        }
        if let date = booruDateValue(firstSemanticAttribute(attributes, keys: [
            "data-created-at", "created-at",
            "data-date", "date",
            "data-published-at", "published-at",
            "data-upload-date", "upload-date"
        ])) {
            metadata["date"] = date
            metadata["created"] = date
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func semanticSearchAttributes(for anchor: AnchorEntry) -> [String: String] {
        var attributes = anchor.attributes
        attributes.merge(imageAttributes(from: anchor.body)) { current, _ in current }
        for values in tagAttributeValues(from: anchor.contextHTML) {
            attributes.merge(values) { current, new in current.isEmpty ? new : current }
        }
        return attributes
    }

    private static func tagAttributeValues(from html: String) -> [[String: String]] {
        let pattern = #"<[a-zA-Z0-9:-]+\b([^>]*)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let attributesRange = Range(match.range(at: 1), in: html) else { return nil }
            let values = attributeValues(from: String(html[attributesRange]))
            return values.isEmpty ? nil : values
        }
    }

    private static func firstSemanticAttribute(_ attributes: [String: String], keys: [String]) -> String? {
        for key in keys {
            guard let value = attributes.first(where: { $0.key.lowercased() == key })?.value.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func coubSearchMetadata(id: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": id,
            "coub_id": id,
            "video_id": id,
            "media_id": id,
            "category": "coub",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func vimeoSearchMetadata(id: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": id,
            "video_id": id,
            "media_id": id,
            "category": "vimeo",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func soundCloudSearchMetadata(trackKey: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        let parts = target.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let username = parts.first
        let slug = parts.dropFirst().first
        var metadata = [
            "id": trackKey,
            "track_id": trackKey,
            "media_id": trackKey,
            "category": "soundcloud",
            "type": "track",
            "media_type": "audio",
            "title": title,
            "search_title": title
        ]
        if let slug {
            metadata["slug"] = slug
        }
        metadata.merge(searchContributorMetadata(anchor: anchor, fallbackName: username, fallbackUsername: username)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func youtubeSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "youtube",
            "title": title,
            "search_title": title
        ]
        let components = URLComponents(url: target, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []
        let parts = target.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.first == "watch",
           let videoID = queryValue("v", in: queryItems) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        } else if lower.first == "shorts", parts.count >= 2 {
            metadata["id"] = parts[1]
            metadata["video_id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["type"] = "short"
            metadata["media_type"] = "video"
        } else if lower.first == "clip", parts.count >= 2 {
            metadata["id"] = parts[1]
            metadata["clip_id"] = parts[1]
            metadata["media_id"] = parts[1]
            metadata["type"] = "clip"
            metadata["media_type"] = "video"
        } else if lower.first == "playlist",
                  let playlistID = queryValue("list", in: queryItems) {
            metadata["id"] = playlistID
            metadata["playlist_id"] = playlistID
            metadata["gallery_id"] = playlistID
            metadata["series"] = playlistID
            metadata["type"] = "playlist"
        } else if let first = parts.first,
                  first.hasPrefix("@") {
            let handle = first.trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            metadata["id"] = handle
            metadata["handle"] = first
            metadata["username"] = first
            metadata["user"] = first
            metadata["channel"] = first
            metadata["type"] = "channel"
        } else if let first = lower.first,
                  ["channel", "user", "c"].contains(first),
                  parts.count >= 2 {
            metadata["id"] = parts[1]
            if first == "channel" {
                metadata["channel_id"] = parts[1]
            } else {
                metadata["username"] = parts[1]
            }
            metadata["user"] = parts[1]
            metadata["channel"] = parts[1]
            metadata["type"] = "channel"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func kakaoTVSearchMetadata(id: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": id,
            "clip_id": id,
            "video_id": id,
            "media_id": id,
            "category": "kakaotv",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func twitterSearchMetadata(id: String, kind: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "twitter",
            "type": kind,
            "title": title,
            "search_title": title
        ]
        if kind == "tweet" {
            metadata["tweet_id"] = id
            metadata["status_id"] = id
            metadata["media_id"] = id
        } else if kind == "space" {
            metadata["space_id"] = id
            metadata["media_id"] = id
            metadata["media_type"] = "audio"
        } else if kind == "broadcast" {
            metadata["broadcast_id"] = id
            metadata["media_id"] = id
            metadata["media_type"] = "video"
            metadata["live_status"] = "broadcast"
        } else {
            metadata["user_id"] = id
        }
        metadata.merge(searchContributorMetadata(anchor: anchor, fallbackUsername: twitterUsername(from: target))) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func twitterUsername(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              ["status", "statuses"].contains(parts[1].lowercased()) else {
            return nil
        }
        return parts[0]
    }

    private static func tikTokSearchMetadata(id: String, kind: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "tiktok",
            "type": kind,
            "title": title,
            "search_title": title
        ]
        if kind == "video" {
            metadata["video_id"] = id
            metadata["media_id"] = id
            metadata["media_type"] = "video"
        } else {
            metadata["user_id"] = id
        }
        let username = TikTokResolver.profileUsername(from: target) ?? tikTokUsername(from: target)
        metadata.merge(searchContributorMetadata(anchor: anchor, fallbackUsername: username)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func tikTokUsername(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        return parts.first(where: { $0.hasPrefix("@") }).map { String($0.dropFirst()) }
    }

    private static func bilibiliSearchMetadata(id: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": id,
            "video_id": id,
            "media_id": id,
            "category": "bilibili",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        if id.uppercased().hasPrefix("BV") {
            metadata["bvid"] = id
        } else if id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
            metadata["aid"] = id
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func chzzkSearchMetadata(id: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "chzzk",
            "title": title,
            "search_title": title
        ]
        if id.hasPrefix("clip-") {
            let value = String(id.dropFirst("clip-".count))
            metadata["clip_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "clip"
            metadata["media_type"] = "video"
        } else if id.hasPrefix("video-") {
            let value = String(id.dropFirst("video-".count))
            metadata["video_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        } else if id.hasPrefix("live-") {
            let value = String(id.dropFirst("live-".count))
            metadata["live_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "live"
            metadata["media_type"] = "live"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func soopSearchMetadata(id: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "soop",
            "title": title,
            "search_title": title
        ]
        if id.hasPrefix("live-") {
            let value = String(id.dropFirst("live-".count))
            metadata["live_id"] = value
            metadata["media_id"] = value
            metadata["type"] = "live"
            metadata["media_type"] = "live"
        } else {
            metadata["video_id"] = id
            metadata["media_id"] = id
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func etcVideoSearchMetadata(
        id: String,
        site: EtcVideoPageResolver.Site,
        title: String,
        anchor: AnchorEntry,
        target: URL
    ) -> [String: String] {
        var metadata = [
            "id": id,
            "content_id": id,
            "media_id": id,
            "category": site.rawValue.lowercased(),
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]

        switch site {
        case .streamable:
            metadata["streamable_id"] = id
            metadata["video_id"] = id
        case .dailymotion:
            metadata["dailymotion_id"] = id
            metadata["video_id"] = id
        case .reddit:
            metadata["reddit_id"] = id
            if isVRedditSearchTarget(target) {
                metadata["video_id"] = id
            } else {
                metadata["post_id"] = id
                metadata["type"] = "post"
            }
        case .rumble:
            metadata["rumble_id"] = id
            metadata["video_id"] = id
        case .odysee:
            metadata["odysee_id"] = id
            metadata["claim_id"] = id
            metadata["video_id"] = id
            if let username = odyseeChannelUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
                metadata["channel"] = username
            }
        case .bitchute:
            metadata["bitchute_id"] = id
            metadata["video_id"] = id
        case .rutube:
            metadata["rutube_id"] = id
            metadata["video_id"] = id
        case .twitcasting:
            metadata["movie_id"] = id
            metadata["video_id"] = id
            if let username = twitCastingUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
                metadata["channel"] = username
            }
        case .kick:
            if kickSearchTargetIsClip(target) {
                metadata["clip_id"] = id
                metadata["type"] = "clip"
            } else {
                metadata["video_id"] = id
            }
        case .vk:
            metadata["vk_id"] = id
            metadata["video_id"] = id
        case .okru:
            metadata["okru_id"] = id
            metadata["video_id"] = id
        case .tver:
            metadata["episode_id"] = id
            metadata["video_id"] = id
            metadata["type"] = "episode"
        default:
            metadata["video_id"] = id
        }

        metadata.merge(searchContributorMetadata(
            anchor: anchor,
            fallbackUsername: odyseeChannelUsername(from: target) ?? twitCastingUsername(from: target)
        )) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func isVRedditSearchTarget(_ url: URL) -> Bool {
        (url.host?.lowercased() ?? "") == "v.redd.it" || (url.host?.lowercased() ?? "") == "v.redd.test"
    }

    private static func odyseeChannelUsername(from url: URL) -> String? {
        url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
            .first { $0.hasPrefix("@") }
            .map { String($0.dropFirst()) }
    }

    private static func twitCastingUsername(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[1].lowercased() == "movie" else {
            return nil
        }
        return parts[0]
    }

    private static func kickSearchTargetIsClip(_ url: URL) -> Bool {
        if URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .contains(where: { $0.name.lowercased() == "clip" }) == true {
            return true
        }
        return url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
            .contains("clip")
    }

    private static func niconicoSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "niconico",
            "title": title,
            "search_title": title
        ]
        if let videoID = NiconicoResolver.videoID(from: target) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        } else if let liveID = NiconicoLiveResolver.liveID(from: target) {
            metadata["id"] = liveID
            metadata["live_id"] = liveID
            metadata["media_id"] = liveID
            metadata["type"] = "live"
            metadata["media_type"] = "live"
        } else if let userID = NiconicoLiveResolver.userID(from: target) {
            metadata["id"] = userID
            metadata["user_id"] = userID
            metadata["type"] = "user"
        } else if let channelID = NiconicoLiveResolver.channelID(from: target) {
            metadata["id"] = channelID
            metadata["channel_id"] = channelID
            metadata["type"] = "channel"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func twitchSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "twitch",
            "title": title,
            "search_title": title
        ]
        if let vodID = TwitchVODResolver.vodID(from: target) {
            metadata["id"] = vodID
            metadata["vod_id"] = vodID
            metadata["video_id"] = vodID
            metadata["media_id"] = vodID
            metadata["type"] = "vod"
            metadata["media_type"] = "video"
        } else if let clipID = twitchClipSlug(from: target) {
            metadata["id"] = clipID
            metadata["clip_id"] = clipID
            metadata["media_id"] = clipID
            metadata["type"] = "clip"
            metadata["media_type"] = "video"
            if let username = twitchClipUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
            }
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func twitchClipUsername(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[1].lowercased() == "clip" else {
            return nil
        }
        return parts[0]
    }

    private static func iwaraSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "iwara",
            "title": title,
            "search_title": title
        ]
        if let imageID = IwaraImageResolver.imageID(from: target) {
            metadata["id"] = imageID
            metadata["image_id"] = imageID
            metadata["media_id"] = imageID
            metadata["gallery_id"] = imageID
            metadata["type"] = "image"
            metadata["media_type"] = "image"
        } else if let videoID = IwaraVideoResolver.videoID(from: target) {
            metadata["id"] = videoID
            metadata["video_id"] = videoID
            metadata["media_id"] = videoID
            metadata["gallery_id"] = videoID
            metadata["type"] = "video"
            metadata["media_type"] = "video"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func instagramSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "instagram",
            "title": title,
            "search_title": title
        ]
        if let shortcode = InstagramResolver.shortcode(from: target) {
            metadata["id"] = shortcode
            metadata["shortcode"] = shortcode
            metadata["media_id"] = shortcode
            metadata["gallery_id"] = shortcode
            metadata["type"] = instagramMediaKind(from: target)
            metadata["media_type"] = "media"
        } else if let storyID = InstagramResolver.storyID(from: target) {
            metadata["id"] = storyID
            metadata["story_id"] = storyID
            metadata["media_id"] = storyID
            metadata["type"] = "story"
            metadata["media_type"] = "story"
            if let username = instagramStoryUsername(from: target) {
                metadata["username"] = username
                metadata["user"] = username
            }
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func instagramMediaKind(from url: URL) -> String {
        url.path.split(separator: "/", omittingEmptySubsequences: true)
            .first
            .map { String($0).lowercased() } ?? "media"
    }

    private static func instagramStoryUsername(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "stories" else {
            return nil
        }
        return parts[1]
    }

    private static func facebookSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
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
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func pornhubSearchMetadata(key: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": key,
            "category": "pornhub",
            "title": title,
            "search_title": title
        ]
        if let request = PornhubMediaResolver.request(from: target) {
            metadata["id"] = request.id
            metadata["media_id"] = request.id
            metadata["gallery_id"] = request.id
            metadata["type"] = request.kind.rawValue
            switch request.kind {
            case .video:
                metadata["video_id"] = request.id
                metadata["media_type"] = "video"
            case .gif:
                metadata["gif_id"] = request.id
                metadata["media_type"] = "video"
            case .photo:
                metadata["photo_id"] = request.id
                metadata["media_type"] = "image"
            case .album:
                metadata["album_id"] = request.id
                metadata["media_type"] = "gallery"
            }
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func weiboSearchMetadata(id: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": id,
            "status_id": id,
            "media_id": id,
            "category": "weibo",
            "type": weiboSearchKind(from: target),
            "media_type": "status",
            "title": title,
            "search_title": title
        ]
        if let profile = weiboStatusProfileID(from: target) {
            metadata["profile_id"] = profile
            metadata["user_id"] = profile
        }
        metadata.merge(searchContributorMetadata(
            anchor: anchor,
            fallbackUsername: weiboStatusProfileID(from: target),
            fallbackUserID: weiboStatusProfileID(from: target)
        )) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func weiboSearchKind(from url: URL) -> String {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.count >= 3, lower[0] == "tv", lower[1] == "show" {
            return "tv"
        }
        if lower.contains("detail") {
            return "detail"
        }
        return "status"
    }

    private static func weiboStatusProfileID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        guard let statusIndex = lower.firstIndex(of: "status"),
              statusIndex > 0 else {
            return nil
        }
        let value = parts[statusIndex - 1].trimmed
        guard value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func spankBangSearchMetadata(videoID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "gallery_id": videoID,
            "category": "spankbang",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func pixivSearchMetadata(artworkID: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": artworkID,
            "artwork_id": artworkID,
            "illust_id": artworkID,
            "media_id": artworkID,
            "gallery_id": artworkID,
            "category": "pixiv",
            "type": "artwork",
            "title": title,
            "search_title": title
        ]
        let attributes = semanticSearchAttributes(for: anchor)
        if let artist = firstSemanticAttribute(attributes, keys: [
            "data-artist", "data-artist-name", "artist",
            "data-author", "data-author-name", "author",
            "data-user-name", "data-username", "username",
            "data-creator", "creator", "data-owner", "owner"
        ]) ?? pixivUserInfo(from: anchor.contextHTML, baseURL: target)?.name {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
            metadata["username"] = artist
        }
        if let userID = firstSemanticAttribute(attributes, keys: [
            "data-user-id", "data-uid", "user-id", "uid"
        ]) ?? pixivUserInfo(from: anchor.contextHTML, baseURL: target)?.id {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
            metadata["artist_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func pixivUserInfo(from html: String, baseURL: URL) -> (id: String, name: String?)? {
        for entry in anchorEntries(from: html) {
            guard let href = entry.attributes["href"]?.trimmed,
                  let url = resolve(href: href, baseURL: baseURL),
                  let id = firstCapture(in: url.path, pattern: #"/(?:en/)?users/([0-9]+)"#) else {
                continue
            }
            let name = displayTitle(for: entry, fallback: "").trimmed
            return (id, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func artStationSearchMetadata(projectID: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": projectID,
            "project_id": projectID,
            "artwork_id": projectID,
            "media_id": projectID,
            "gallery_id": projectID,
            "category": "artstation",
            "type": "project",
            "title": title,
            "search_title": title
        ]
        let attributes = semanticSearchAttributes(for: anchor)
        if let artist = firstSemanticAttribute(attributes, keys: [
            "data-artist", "data-artist-name", "artist",
            "data-author", "data-author-name", "author",
            "data-user-name", "data-username", "username",
            "data-owner", "owner", "data-creator", "creator"
        ]) ?? artStationProfileInfo(from: anchor.contextHTML, baseURL: target)?.name {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
            metadata["username"] = artist
        }
        if let username = firstSemanticAttribute(attributes, keys: [
            "data-profile", "data-profile-name", "data-user", "data-username", "username"
        ]) ?? artStationProfileInfo(from: anchor.contextHTML, baseURL: target)?.username {
            metadata["user"] = username
            metadata["username"] = username
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func artStationProfileInfo(from html: String, baseURL: URL) -> (username: String, name: String?)? {
        let reserved: Set<String> = [
            "about", "artwork", "blogs", "channels", "community", "contests",
            "jobs", "marketplace", "projects", "search", "store"
        ]
        for entry in anchorEntries(from: html) {
            guard let href = entry.attributes["href"]?.trimmed,
                  let url = resolve(href: href, baseURL: baseURL),
                  let host = url.host?.lowercased(),
                  isArtStationHost(host) else {
                continue
            }

            if host.hasSuffix(".artstation.com"),
               let username = host.split(separator: ".").first.map(String.init),
               !["www", "magazine", "cdna"].contains(username.lowercased()) {
                let name = displayTitle(for: entry, fallback: "").trimmed
                return (username, name.isEmpty ? nil : name)
            }

            let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 1,
                  let username = parts.first?.trimmed,
                  !username.isEmpty,
                  !reserved.contains(username.lowercased()) else {
                continue
            }
            let name = displayTitle(for: entry, fallback: "").trimmed
            return (username, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func deviantArtSearchMetadata(title: String, anchor: AnchorEntry, target: URL, fallbackUsername: String?) -> [String: String] {
        let attributes = semanticSearchAttributes(for: anchor)
        let artworkInfo = deviantArtArtworkInfo(from: target)
        let collectionInfo = deviantArtCollectionInfo(from: target)
        let pathUsername = artworkInfo?.username ?? collectionInfo?.username ?? fallbackUsername
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-artist-name", "data-artist", "artist",
            "data-author", "data-author-name", "author",
            "data-creator", "creator"
        ])
        let username = firstSemanticAttribute(attributes, keys: [
            "data-username", "username", "data-user", "data-user-name",
            "data-profile", "data-profile-name"
        ]) ?? pathUsername
        let artist = displayName ?? username
        var metadata = [
            "category": "deviantart",
            "title": title,
            "search_title": title
        ]
        if let artist {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
        }
        if let username {
            metadata["user"] = username
            metadata["username"] = username
        }
        if let artworkInfo {
            metadata["id"] = artworkInfo.id
            metadata["artwork_id"] = artworkInfo.id
            metadata["media_id"] = artworkInfo.id
            metadata["gallery_id"] = artworkInfo.id
            metadata["slug"] = artworkInfo.slug
            metadata["type"] = "artwork"
        } else if let collectionInfo {
            metadata["id"] = collectionInfo.id
            metadata["gallery_id"] = collectionInfo.id
            metadata["slug"] = collectionInfo.slug
            metadata["type"] = collectionInfo.type
        } else if let username {
            metadata["id"] = username
            metadata["user_id"] = username
            metadata["type"] = "profile"
        }
        if let userID = firstSemanticAttribute(attributes, keys: [
            "data-user-id", "data-uid", "user-id", "uid"
        ]) {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func deviantArtArtworkInfo(from url: URL) -> (username: String, slug: String, id: String)? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[1].lowercased() == "art" else {
            return nil
        }
        let username = parts[0]
        let slug = parts[2]
        guard let id = firstCapture(in: slug, pattern: #"(?:^|-)([0-9]{3,})$"#) else {
            return nil
        }
        return (username, slug, id)
    }

    private static func deviantArtCollectionInfo(from url: URL) -> (username: String, id: String, slug: String, type: String)? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 1 else { return nil }
        let username = parts[0]
        guard parts.count >= 2,
              parts[1].lowercased() == "gallery" else {
            return (username, username, username, "profile")
        }
        if parts.count >= 4, parts[2].allSatisfy(\.isNumber) {
            return (username, parts[2], parts[3], "gallery")
        }
        if parts.count >= 3 {
            return (username, "\(username)-\(parts[2])", parts[2], "gallery")
        }
        return (username, username, username, "gallery")
    }

    private static func pinterestSearchMetadata(pinID: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": pinID,
            "pin_id": pinID,
            "media_id": pinID,
            "gallery_id": pinID,
            "category": "pinterest",
            "type": "pin",
            "title": title,
            "search_title": title
        ]
        let attributes = semanticSearchAttributes(for: anchor)
        let profileInfo = pinterestUserInfo(from: anchor.contextHTML, baseURL: target)
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-pinner-name", "data-pinner", "pinner",
            "data-owner-name", "data-owner", "owner",
            "data-creator-name", "data-creator", "creator"
        ]) ?? profileInfo?.name
        let username = firstSemanticAttribute(attributes, keys: [
            "data-username", "username", "data-user", "data-user-name"
        ]) ?? profileInfo?.username
        let artist = displayName ?? username
        if let artist {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
            metadata["pinner"] = artist
        }
        if let username {
            metadata["user"] = username
            metadata["username"] = username
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func pinterestUserInfo(from html: String, baseURL: URL) -> (username: String, name: String?)? {
        let reserved: Set<String> = [
            "about", "business", "categories", "explore", "ideas", "login",
            "pin", "privacy", "search", "settings", "today"
        ]
        for entry in anchorEntries(from: html) {
            guard let href = entry.attributes["href"]?.trimmed,
                  let url = resolve(href: href, baseURL: baseURL),
                  let host = url.host?.lowercased(),
                  isPinterestHost(host) else {
                continue
            }
            let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard parts.count == 1,
                  let username = parts.first?.trimmed,
                  !username.isEmpty,
                  !reserved.contains(username.lowercased()) else {
                continue
            }
            let name = displayTitle(for: entry, fallback: "").trimmed
            return (username, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func newgroundsSearchMetadata(resultID: String, title: String, anchor: AnchorEntry, target: URL, username: String?, slug: String?, type: String) -> [String: String] {
        var metadata = [
            "id": resultID,
            "category": "newgrounds",
            "type": type,
            "title": title,
            "search_title": title
        ]
        let attributes = semanticSearchAttributes(for: anchor)
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-artist-name", "data-artist", "artist",
            "data-author", "data-author-name", "author",
            "data-uploader-name", "data-uploader", "uploader"
        ])
        let usernameValue = firstSemanticAttribute(attributes, keys: [
            "data-username", "username", "data-user", "data-user-name"
        ]) ?? username
        let artist = displayName ?? usernameValue
        if let artist {
            metadata["artist"] = artist
            metadata["author"] = artist
            metadata["creator"] = artist
            metadata["uploader"] = artist
        }
        if let usernameValue {
            metadata["user"] = usernameValue
            metadata["username"] = usernameValue
        }
        if let slug {
            metadata["slug"] = slug
            metadata["artwork"] = slug
            metadata["artwork_id"] = slug
            metadata["media_id"] = slug
            metadata["gallery_id"] = slug
        } else if let username {
            metadata["user_id"] = username
            metadata["gallery_id"] = username
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func newgroundsArtInfo(from url: URL) -> (username: String, slug: String)? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 4,
              parts[0].lowercased() == "art",
              parts[1].lowercased() == "view" else {
            return nil
        }
        return (parts[2], parts[3])
    }

    private static func flickrSearchMetadata(resultID: String, title: String, target: URL, photoID: String?, userID: String?, type: String) -> [String: String] {
        var metadata = [
            "id": photoID ?? userID ?? resultID,
            "category": "flickr",
            "type": type,
            "title": title,
            "search_title": title
        ]
        if let photoID {
            metadata["photo_id"] = photoID
            metadata["media_id"] = photoID
            metadata["gallery_id"] = photoID
        }
        if let userID {
            metadata["artist"] = userID
            metadata["author"] = userID
            metadata["creator"] = userID
            metadata["uploader"] = userID
            metadata["user"] = userID
            metadata["username"] = userID
            metadata["user_id"] = userID
        }
        metadata["source_url"] = target.absoluteString
        metadata["page_url"] = target.absoluteString
        return DownloadMetadata.clean(metadata)
    }

    private static func imgurSearchMetadata(content: (id: String, key: String, path: String), title: String, anchor: AnchorEntry) -> [String: String] {
        let kind = content.key.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init) ?? "media"
        var metadata = [
            "id": content.id,
            "media_id": content.id,
            "category": "imgur",
            "type": kind,
            "media_type": kind == "media" ? "media" : "gallery",
            "title": title,
            "search_title": title
        ]
        switch kind {
        case "a":
            metadata["album_id"] = content.id
            metadata["gallery_id"] = content.id
        case "gallery":
            metadata["gallery_id"] = content.id
        case "t":
            metadata["gallery_id"] = content.id
            if let tag = content.key.split(separator: ":", omittingEmptySubsequences: true).dropFirst().first {
                metadata["tag"] = String(tag)
            }
        default:
            metadata["image_id"] = content.id
            metadata["gallery_id"] = content.id
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func tumblrSearchMetadata(blog: String, title: String, anchor: AnchorEntry, originalURL: URL) -> [String: String] {
        var metadata = [
            "id": blog,
            "blog_id": blog,
            "blog": blog,
            "username": blog,
            "user": blog,
            "uploader": blog,
            "uploader_id": blog,
            "channel_id": blog,
            "category": "tumblr",
            "type": "blog",
            "title": title,
            "search_title": title
        ]
        if let postID = tumblrPostID(from: originalURL) {
            metadata["id"] = postID
            metadata["post_id"] = postID
            metadata["media_id"] = postID
            metadata["type"] = "post"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor, fallbackUsername: blog, fallbackUserID: blog)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func tumblrPostID(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["redirect_to", "url"] {
                guard let nested = items.first(where: { $0.name.lowercased() == name })?.value,
                      let nestedURL = tumblrRedirectURL(from: nested, sourceURL: url),
                      nestedURL.absoluteString != url.absoluteString,
                      let nestedID = tumblrPostID(from: nestedURL) else {
                    continue
                }
                return nestedID
            }
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if let postIndex = parts.firstIndex(where: { $0.lowercased() == "post" }),
           postIndex + 1 < parts.count {
            let value = parts[postIndex + 1].trimmed
            return value.allSatisfy(\.isNumber) ? value : nil
        }
        guard parts.count >= 2,
              parts[1].allSatisfy(\.isNumber) else {
            return nil
        }
        return parts[1]
    }

    private static func fourChanSearchMetadata(thread: (board: String, id: String), title: String) -> [String: String] {
        DownloadMetadata.clean([
            "id": thread.id,
            "thread_id": thread.id,
            "media_id": thread.id,
            "gallery_id": thread.id,
            "board_id": thread.board,
            "channel": thread.board,
            "tag": thread.board,
            "category": "4chan",
            "type": "thread",
            "title": title,
            "search_title": title
        ])
    }

    private static func wikiArtSearchMetadata(artist: String, title: String, anchor: AnchorEntry) -> [String: String] {
        let attributes = anchor.attributes.merging(imageAttributes(from: anchor.body)) { current, _ in current }
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-artist-name", "data-artist", "artist",
            "data-author-name", "data-author", "author"
        ]) ?? wikiArtDisplayName(from: artist)
        var metadata = [
            "id": artist,
            "artist_slug": artist,
            "username": artist,
            "gallery_id": artist,
            "category": "wikiart",
            "type": "artist",
            "title": title,
            "search_title": title
        ]
        if !displayName.isEmpty {
            metadata["artist"] = displayName
            metadata["author"] = displayName
            metadata["creator"] = displayName
            metadata["uploader"] = displayName
            metadata["channel"] = displayName
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func wikiArtDisplayName(from slug: String) -> String {
        slug.split(separator: "-", omittingEmptySubsequences: true)
            .map { part in
                let lower = part.lowercased()
                return lower.prefix(1).uppercased() + lower.dropFirst()
            }
            .joined(separator: " ")
    }

    private static func extractKakaoTVLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = kakaoTVMediaURL(from: absolute),
                  let id = KakaoTVResolver.clipID(from: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "KakaoTV \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "kakaotv",
                results: &results,
                indexByID: &indexByID,
                metadata: kakaoTVSearchMetadata(id: id, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractNiconicoLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = niconicoQueueURL(from: absolute),
                  let key = niconicoResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "niconico",
                results: &results,
                indexByID: &indexByID,
                metadata: niconicoSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractTwitchLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = twitchQueueURL(from: absolute),
                  let key = twitchResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "twitch",
                results: &results,
                indexByID: &indexByID,
                metadata: twitchSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractIwaraLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = iwaraQueueURL(from: absolute),
                  let key = iwaraResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "iwara",
                results: &results,
                indexByID: &indexByID,
                metadata: iwaraSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractInstagramLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = instagramQueueURL(from: absolute),
                  let key = instagramResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Instagram \(key)")
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "instagram",
                results: &results,
                indexByID: &indexByID,
                metadata: instagramSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractFacebookLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = facebookQueueURL(from: absolute),
                  let key = facebookResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "facebook",
                results: &results,
                indexByID: &indexByID,
                metadata: facebookSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractPornhubLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = pornhubMediaURL(from: absolute),
                  let key = pornhubResultKey(for: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: key,
                sitePrefix: "pornhub",
                results: &results,
                indexByID: &indexByID,
                metadata: pornhubSearchMetadata(key: key, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractWeiboLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = weiboMediaURL(from: absolute),
                  let id = WeiboStatusResolver.statusID(from: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Weibo \(id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "weibo",
                results: &results,
                indexByID: &indexByID,
                metadata: weiboSearchMetadata(id: id, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractSpankBangLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let videoID = SpankBangResolver.videoID(from: absolute) else {
                continue
            }
            let target = SpankBangResolver.canonicalURL(for: videoID, sourceURL: absolute)

            let title = displayTitle(for: anchor, fallback: "SpankBang \(videoID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: videoID,
                sitePrefix: "spankbang",
                results: &results,
                indexByID: &indexByID,
                metadata: spankBangSearchMetadata(videoID: videoID, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractXVideoPageLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = XVideoPageResolver.canonicalURL(for: absolute),
                  let videoID = XVideoPageResolver.videoID(from: target) else {
                continue
            }

            let host = absolute.host?.lowercased() ?? ""
            let siteName = isXNXXHost(host) ? "XNXX" : "XVideos"
            let sitePrefix = isXNXXHost(host) ? "xnxx" : "xvideos"

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "\(siteName) \(videoID)"),
                url: target,
                id: "\(sitePrefix)-\(videoID.lowercased())",
                sitePrefix: sitePrefix,
                results: &results,
                indexByID: &indexByID
            )
        }

        return results
    }

    private static func extractOriginalYTDLPMediaLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByURL: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = originalYTDLPMediaURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "media",
                results: &results,
                indexByID: &indexByURL
            )
        }

        return results
    }

    private static func extractImgurContentLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let content = imgurContent(from: absolute),
                  let target = cleanedURL(absolute, path: content.path) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Imgur \(content.id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: content.key,
                sitePrefix: "imgur",
                results: &results,
                indexByID: &indexByKey,
                metadata: imgurSearchMetadata(content: content, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractTumblrBlogLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByBlog: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let blog = tumblrBlogName(from: absolute),
                  let target = tumblrBlogURL(blog: blog, sourceURL: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Tumblr \(blog)")
            appendUniqueResult(
                title: title,
                url: target,
                id: blog,
                sitePrefix: "tumblr",
                results: &results,
                indexByID: &indexByBlog,
                metadata: tumblrSearchMetadata(blog: blog, title: title, anchor: anchor, originalURL: absolute)
            )
        }

        return results
    }

    private static func extractFourChanThreadLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByThread: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let thread = fourChanThread(from: absolute),
                  let target = fourChanThreadURL(thread: thread, sourceURL: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "4chan \(thread.board) \(thread.id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: "\(thread.board)-\(thread.id)",
                sitePrefix: "4chan",
                results: &results,
                indexByID: &indexByThread,
                metadata: fourChanSearchMetadata(thread: thread, title: title)
            )
        }

        return results
    }

    private static func extractWikiArtArtistLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByArtist: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let artist = wikiArtArtistSlug(from: absolute),
                  let target = wikiArtArtistURL(artist: artist, sourceURL: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: artist.replacingOccurrences(of: "-", with: " "))
            appendUniqueResult(
                title: title,
                url: target,
                id: artist,
                sitePrefix: "wikiart",
                results: &results,
                indexByID: &indexByArtist,
                metadata: wikiArtSearchMetadata(artist: artist, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractSankakuPostLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let host = absolute.host?.lowercased(),
                  isSankakuHost(host),
                  let id = SankakuResolver.postID(from: absolute) else {
                continue
            }

            let target = SankakuResolver.postURL(id: id, sourceURL: absolute)
            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "Sankaku \(id)"),
                url: target,
                id: id,
                sitePrefix: "sankaku",
                results: &results,
                indexByID: &indexByID,
                metadata: sankakuSearchMetadata(
                    postID: id,
                    title: displayTitle(for: anchor, fallback: "Sankaku \(id)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractNijieLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let host = absolute.host?.lowercased(),
                  isNijieHost(host) else {
                continue
            }

            if let id = NijieResolver.illustrationID(from: absolute) {
                appendUniqueResult(
                    title: displayTitle(for: anchor, fallback: "Nijie \(id)"),
                    url: NijieResolver.viewURL(illustrationID: id, sourceURL: absolute),
                    id: "illust:\(id)",
                    sitePrefix: "nijie",
                    results: &results,
                    indexByID: &indexByKey,
                    metadata: nijieIllustrationSearchMetadata(
                        illustrationID: id,
                        title: displayTitle(for: anchor, fallback: "Nijie \(id)"),
                        anchor: anchor
                    )
                )
            } else if let memberID = NijieResolver.memberID(from: absolute) {
                appendUniqueResult(
                    title: displayTitle(for: anchor, fallback: "Nijie \(memberID)"),
                    url: NijieResolver.memberIllustURL(memberID: memberID, page: 1, sourceURL: absolute),
                    id: "member:\(memberID)",
                    sitePrefix: "nijie",
                    results: &results,
                    indexByID: &indexByKey,
                    metadata: nijieMemberSearchMetadata(
                        memberID: memberID,
                        title: displayTitle(for: anchor, fallback: "Nijie \(memberID)"),
                        anchor: anchor
                    )
                )
            }
        }

        return results
    }

    private static func extractV2PHAlbumLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByAlbum: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let host = absolute.host?.lowercased(),
                  isV2PHHost(host),
                  let albumID = V2PHResolver.albumID(from: absolute),
                  let target = cleanedURL(absolute, path: "/album/\(albumID)") else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "V2PH \(albumID)"),
                url: target,
                id: albumID,
                sitePrefix: "v2ph",
                results: &results,
                indexByID: &indexByAlbum,
                metadata: v2phSearchMetadata(
                    albumID: albumID,
                    title: displayTitle(for: anchor, fallback: "V2PH \(albumID)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractHentaiCosplayContentLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let targetURL = HentaiCosplayResolver.canonicalURL(for: absolute),
                  let host = targetURL.host?.lowercased(),
                  isHentaiCosplayHost(host),
                  let content = hentaiCosplayContent(from: targetURL),
                  let target = cleanedURL(targetURL, path: "/\(content.kind)/\(content.slug)/") else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: content.slug),
                url: target,
                id: "\(content.kind):\(content.slug)",
                sitePrefix: "hentaicosplay",
                results: &results,
                indexByID: &indexByContent,
                metadata: hentaiCosplaySearchMetadata(
                    content: content,
                    title: displayTitle(for: anchor, fallback: content.slug),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractHentaiFoundryLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = HentaiFoundryResolver.canonicalContentURL(from: absolute) else {
                continue
            }

            let id: String
            let fallback: String
            if let picture = HentaiFoundryResolver.picturePageInfo(from: target) {
                id = "picture:\(picture.username.lowercased()):\(picture.id)"
                fallback = "Hentai Foundry \(picture.id)"
            } else if let username = HentaiFoundryResolver.galleryUsername(from: target) {
                id = "gallery:\(username.lowercased())"
                fallback = username
            } else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: fallback),
                url: target,
                id: id,
                sitePrefix: "hentaifoundry",
                results: &results,
                indexByID: &indexByContent,
                metadata: hentaiFoundrySearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallback: fallback),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractTalkOPGGArticleLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByArticle: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let articleID = TalkOPGGResolver.articleID(from: absolute),
                  let target = TalkOPGGResolver.canonicalArticleURL(for: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "Talk OP.GG \(articleID)"),
                url: target,
                id: articleID,
                sitePrefix: "talkopgg",
                results: &results,
                indexByID: &indexByArticle,
                metadata: talkOPGGSearchMetadata(
                    articleID: articleID,
                    target: target,
                    title: displayTitle(for: anchor, fallback: "Talk OP.GG \(articleID)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractAsmHentaiGalleryLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGallery: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let host = absolute.host?.lowercased(),
                  isAsmHentaiHost(host),
                  let galleryID = AsmHentaiResolver.galleryID(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "AsmHentai \(galleryID)"),
                url: AsmHentaiResolver.canonicalGalleryURL(for: galleryID, sourceURL: absolute),
                id: galleryID,
                sitePrefix: "asmhentai",
                results: &results,
                indexByID: &indexByGallery,
                metadata: asmHentaiSearchMetadata(
                    galleryID: galleryID,
                    title: displayTitle(for: anchor, fallback: "AsmHentai \(galleryID)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractMyReadingMangaPostLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPath: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let targetPath = myReadingMangaPostPath(from: absolute),
                  let target = cleanedURL(absolute, path: targetPath) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: targetPath.lowercased(),
                sitePrefix: "myreadingmanga",
                results: &results,
                indexByID: &indexByPath,
                metadata: myReadingMangaSearchMetadata(
                    path: targetPath,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractLusciousContentLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let canonical = LusciousResolver.canonicalURL(for: absolute),
                  let content = lusciousContent(from: canonical),
                  let target = cleanedURL(canonical, path: content.path) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "Luscious \(content.id)"),
                url: target,
                id: content.key,
                sitePrefix: "luscious",
                results: &results,
                indexByID: &indexByContent,
                metadata: lusciousSearchMetadata(
                    content: content,
                    title: displayTitle(for: anchor, fallback: "Luscious \(content.id)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractBDSMlrLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = bdsmlrURL(from: absolute) else {
                continue
            }

            let key = bdsmlrKey(for: target)
            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: key,
                sitePrefix: "bdsmlr",
                results: &results,
                indexByID: &indexByKey,
                metadata: bdsmlrSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func sankakuSearchMetadata(postID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": postID,
            "post_id": postID,
            "gallery_id": postID,
            "media_id": postID,
            "category": "sankaku",
            "type": "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func nijieIllustrationSearchMetadata(illustrationID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": illustrationID,
            "post_id": illustrationID,
            "illust_id": illustrationID,
            "illustration_id": illustrationID,
            "gallery_id": illustrationID,
            "media_id": illustrationID,
            "category": "nijie",
            "type": "illustration",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func nijieMemberSearchMetadata(memberID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor, fallbackUsername: memberID, fallbackUserID: memberID)
        metadata.merge([
            "id": memberID,
            "member_id": memberID,
            "user_id": memberID,
            "uploader_id": memberID,
            "gallery_id": memberID,
            "category": "nijie",
            "type": "member",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func v2phSearchMetadata(albumID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": albumID,
            "album_id": albumID,
            "gallery_id": albumID,
            "media_id": albumID,
            "category": "v2ph",
            "type": "album",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func hentaiCosplaySearchMetadata(content: (kind: String, slug: String), title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": content.slug,
            "content_id": content.slug,
            "slug": content.slug,
            "gallery_id": content.slug,
            "media_id": content.slug,
            "category": "hentai_cosplay",
            "type": content.kind,
            "media_type": content.kind == "video" ? "video" : "image",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func hentaiFoundrySearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "category": "hentai_foundry",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let picture = HentaiFoundryResolver.picturePageInfo(from: target) {
            metadata["id"] = picture.id
            metadata["post_id"] = picture.id
            metadata["picture_id"] = picture.id
            metadata["gallery_id"] = picture.id
            metadata["media_id"] = picture.id
            metadata["username"] = picture.username
            metadata["uploader"] = metadata["uploader"] ?? picture.username
            metadata["uploader_id"] = picture.username
            metadata["type"] = "picture"
        } else if let username = HentaiFoundryResolver.galleryUsername(from: target) {
            metadata["id"] = username
            metadata["username"] = username
            metadata["user"] = username
            metadata["uploader"] = metadata["uploader"] ?? username
            metadata["uploader_id"] = username
            metadata["gallery_id"] = username
            metadata["type"] = "gallery"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func talkOPGGSearchMetadata(articleID: String, target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let parts = target.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let game = parts.count > 1 ? parts[1] : ""
        let section = parts.count > 2 ? parts[2] : ""
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": articleID,
            "post_id": articleID,
            "article_id": articleID,
            "gallery_id": articleID,
            "media_id": articleID,
            "game": game,
            "section": section,
            "tag": section,
            "category": "talk_opgg",
            "type": "article",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func asmHentaiSearchMetadata(galleryID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": galleryID,
            "gallery_id": galleryID,
            "media_id": galleryID,
            "category": "asmhentai",
            "type": "gallery",
            "slug": galleryID,
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func myReadingMangaSearchMetadata(path: String, title: String, anchor: AnchorEntry) -> [String: String] {
        let slug = path.split(separator: "/", omittingEmptySubsequences: true).first.map(String.init) ?? path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": slug,
            "post_id": slug,
            "gallery_id": slug,
            "media_id": slug,
            "slug": slug,
            "category": "myreadingmanga",
            "type": "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func lusciousSearchMetadata(content: (id: String, key: String, path: String), title: String, anchor: AnchorEntry) -> [String: String] {
        let kind = content.key.split(separator: ":", omittingEmptySubsequences: true).first.map(String.init) ?? "media"
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": content.id,
            "gallery_id": content.id,
            "media_id": content.id,
            "category": "luscious",
            "type": kind,
            "media_type": kind == "video" ? "video" : "image",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if kind == "album" {
            metadata["album_id"] = content.id
        } else if kind == "video" {
            metadata["video_id"] = content.id
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func bdsmlrSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let blog = BDSMlrResolver.blogName(from: target) ?? target.host?.split(separator: ".").first.map(String.init) ?? ""
        var metadata = searchContributorMetadata(anchor: anchor, fallbackUsername: blog, fallbackUserID: blog)
        metadata.merge([
            "blog": blog,
            "blog_id": blog,
            "username": blog,
            "user": blog,
            "uploader": metadata["uploader"] ?? blog,
            "uploader_id": blog,
            "channel_id": blog,
            "category": "bdsmlr",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let postID = BDSMlrResolver.postID(from: target) {
            metadata["id"] = postID
            metadata["post_id"] = postID
            metadata["gallery_id"] = postID
            metadata["media_id"] = postID
            metadata["type"] = "post"
        } else {
            metadata["id"] = blog
            metadata["gallery_id"] = blog
            metadata["type"] = "blog"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractNarouLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = narouURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: narouKey(for: target),
                sitePrefix: "narou",
                results: &results,
                indexByID: &indexByKey,
                metadata: narouSearchMetadata(target: target, title: displayTitle(for: anchor, fallbackURL: target), anchor: anchor)
            )
        }

        return results
    }

    private static func extractKakuyomuLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = kakuyomuURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: kakuyomuKey(for: target),
                sitePrefix: "kakuyomu",
                results: &results,
                indexByID: &indexByKey,
                metadata: kakuyomuSearchMetadata(target: target, title: displayTitle(for: anchor, fallbackURL: target), anchor: anchor)
            )
        }

        return results
    }

    private static func extractHamelnLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = hamelnURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: hamelnKey(for: target),
                sitePrefix: "hameln",
                results: &results,
                indexByID: &indexByKey,
                metadata: hamelnSearchMetadata(target: target, title: displayTitle(for: anchor, fallbackURL: target), anchor: anchor)
            )
        }

        return results
    }

    private static func extractComicWalkerLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = comicWalkerURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: comicWalkerKey(for: target),
                sitePrefix: "comicwalker",
                results: &results,
                indexByID: &indexByKey,
                metadata: comicWalkerSearchMetadata(target: target, title: displayTitle(for: anchor, fallbackURL: target), anchor: anchor)
            )
        }

        return results
    }

    private static func extractNaverBlogLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPost: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let post = NaverBlogResolver.postID(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "Naver Blog \(post.postID)"),
                url: NaverBlogResolver.mobilePostURL(for: post, sourceURL: absolute),
                id: "\(post.username):\(post.postID)",
                sitePrefix: "naverblog",
                results: &results,
                indexByID: &indexByPost,
                metadata: naverBlogSearchMetadata(
                    post: post,
                    title: displayTitle(for: anchor, fallback: "Naver Blog \(post.postID)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractNaverPostLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = naverPostURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: naverPostKey(for: target),
                sitePrefix: "naverpost",
                results: &results,
                indexByID: &indexByKey,
                metadata: naverPostSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractWebtoonLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByEpisode: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = webtoonURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: webtoonKey(for: target),
                sitePrefix: "webtoon",
                results: &results,
                indexByID: &indexByEpisode,
                metadata: webtoonSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractNaverWebtoonLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByEpisode: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = naverWebtoonURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: naverWebtoonKey(for: target),
                sitePrefix: "naverwebtoon",
                results: &results,
                indexByID: &indexByEpisode,
                metadata: naverWebtoonSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractPixivComicLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = pixivComicURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: pixivComicKey(for: target),
                sitePrefix: "pixivcomic",
                results: &results,
                indexByID: &indexByKey,
                metadata: pixivComicSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractKakaoPageLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = kakaoPageURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: kakaoPageKey(for: target),
                sitePrefix: "kakaopage",
                results: &results,
                indexByID: &indexByKey,
                metadata: kakaoPageSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractKakaoWebtoonLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = kakaoWebtoonURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: kakaoWebtoonKey(for: target),
                sitePrefix: "kakaowebtoon",
                results: &results,
                indexByID: &indexByKey,
                metadata: kakaoWebtoonSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractNaverCafeLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = naverCafeURL(from: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: naverCafeKey(for: target),
                sitePrefix: "navercafe",
                results: &results,
                indexByID: &indexByKey,
                metadata: naverCafeSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractNaverTVLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByClip: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let clipID = NaverTVResolver.clipID(from: absolute),
                  let target = NaverTVResolver.canonicalURL(for: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "Naver TV \(clipID)"),
                url: target,
                id: clipID,
                sitePrefix: "navertv",
                results: &results,
                indexByID: &indexByClip,
                metadata: naverTVSearchMetadata(
                    clipID: clipID,
                    title: displayTitle(for: anchor, fallback: "Naver TV \(clipID)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractHiyobiGalleryLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGallery: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let host = absolute.host?.lowercased(),
                  isHiyobiHost(host),
                  let galleryID = HiyobiResolver.galleryID(from: absolute),
                  let target = cleanedURL(absolute, path: "/reader/\(galleryID)") else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "Hiyobi \(galleryID)"),
                url: target,
                id: galleryID,
                sitePrefix: "hiyobi",
                results: &results,
                indexByID: &indexByGallery,
                metadata: hiyobiSearchMetadata(
                    galleryID: galleryID,
                    title: displayTitle(for: anchor, fallback: "Hiyobi \(galleryID)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractManatokiLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let id = ManatokiResolver.contentID(from: absolute),
                  let target = ManatokiResolver.canonicalURL(for: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallback: "\(id.section) \(id.id)"),
                url: target,
                id: "\(id.section):\(id.id)",
                sitePrefix: "manatoki",
                results: &results,
                indexByID: &indexByKey,
                metadata: manatokiSearchMetadata(
                    id: id,
                    title: displayTitle(for: anchor, fallback: "\(id.section) \(id.id)"),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractLHScanLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByURL: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = LHScanResolver.canonicalURL(for: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "lhscan",
                results: &results,
                indexByID: &indexByURL,
                metadata: lhScanSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func extractJManaLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByURL: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = JManaResolver.canonicalURL(for: absolute) else {
                continue
            }

            appendUniqueResult(
                title: displayTitle(for: anchor, fallbackURL: target),
                url: target,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "jmana",
                results: &results,
                indexByID: &indexByURL,
                metadata: jManaSearchMetadata(
                    target: target,
                    title: displayTitle(for: anchor, fallbackURL: target),
                    anchor: anchor
                )
            )
        }

        return results
    }

    private static func naverBlogSearchMetadata(post: NaverBlogID, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor, fallbackUsername: post.username, fallbackUserID: post.username)
        metadata.merge([
            "id": post.postID,
            "post_id": post.postID,
            "gallery_id": post.postID,
            "media_id": post.postID,
            "blog_id": post.username,
            "username": post.username,
            "user": post.username,
            "uploader": post.username,
            "uploader_id": post.username,
            "channel_id": post.username,
            "category": "blog",
            "type": "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func narouSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        guard let ncode = NarouResolver.ncode(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = searchContributorMetadata(anchor: anchor)
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

    private static func kakuyomuSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        guard let workID = KakuyomuResolver.workID(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = searchContributorMetadata(anchor: anchor)
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

    private static func hamelnSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        guard let novelID = HamelnResolver.novelID(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        var metadata = searchContributorMetadata(anchor: anchor)
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

    private static func comicWalkerSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
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

    private static func naverPostSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let items = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let volume = queryValue("volumeNo", in: items)
        let member = queryValue("memberNo", in: items)
        let series = queryValue("seriesNo", in: items)
        var metadata = searchContributorMetadata(anchor: anchor, fallbackUserID: member)
        metadata.merge([
            "category": "naver_post",
            "type": volume == nil ? "collection" : "post",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let volume, !volume.isEmpty {
            metadata["id"] = volume
            metadata["post_id"] = volume
            metadata["volume_no"] = volume
            metadata["media_id"] = volume
            metadata["gallery_id"] = volume
        }
        if let member, !member.isEmpty {
            metadata["member_no"] = member
            metadata["uploader_id"] = member
            metadata["user_id"] = member
            metadata["channel_id"] = member
        }
        if let series, !series.isEmpty {
            metadata["series_id"] = series
            metadata["gallery_id"] = metadata["gallery_id"] ?? series
        }
        if metadata["id"] == nil {
            metadata["id"] = member ?? series ?? ""
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func naverCafeSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        guard let id = NaverCafeResolver.articleID(from: target) else {
            return DownloadMetadata.clean(["title": title, "search_title": title])
        }
        let channel = id.clubID ?? id.cafeName ?? ""
        var metadata = searchContributorMetadata(anchor: anchor, fallbackUsername: id.cafeName, fallbackUserID: channel.isEmpty ? nil : channel)
        metadata.merge([
            "id": id.articleID,
            "post_id": id.articleID,
            "article_id": id.articleID,
            "media_id": id.articleID,
            "gallery_id": id.articleID,
            "club_id": id.clubID ?? "",
            "cafe_name": id.cafeName ?? "",
            "channel_id": channel,
            "category": "cafe",
            "type": "article",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func naverTVSearchMetadata(clipID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": clipID,
            "post_id": clipID,
            "clip_id": clipID,
            "video_id": clipID,
            "media_id": clipID,
            "gallery_id": clipID,
            "category": "video",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func webtoonSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let items = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let titleID = queryValue("title_no", in: items) ?? ""
        let episodeID = queryValue("episode_no", in: items) ?? ""
        return episodeSearchMetadata(
            titleID: titleID,
            episodeID: episodeID,
            category: "webtoon",
            title: title,
            anchor: anchor
        )
    }

    private static func naverWebtoonSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let items = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let titleID = queryValue("titleId", in: items) ?? ""
        let episodeID = queryValue("no", in: items) ?? ""
        return episodeSearchMetadata(
            titleID: titleID,
            episodeID: episodeID,
            category: "naver_webtoon",
            title: title,
            anchor: anchor
        )
    }

    private static func pixivComicSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "category": "pixiv_comic",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let episodeID = PixivComicResolver.episodeID(from: target) {
            metadata["id"] = episodeID
            metadata["post_id"] = episodeID
            metadata["episode_id"] = episodeID
            metadata["media_id"] = episodeID
            metadata["gallery_id"] = episodeID
            metadata["type"] = "episode"
        } else if let workID = PixivComicResolver.workID(from: target) {
            metadata["id"] = workID
            metadata["work_id"] = workID
            metadata["gallery_id"] = workID
            metadata["type"] = "work"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func kakaoPageSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "category": "kakaopage",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let ids = KakaoPageResolver.viewerIDs(from: target) {
            metadata["id"] = ids.productID
            metadata["post_id"] = ids.productID
            metadata["episode_id"] = ids.productID
            metadata["product_id"] = ids.productID
            metadata["media_id"] = ids.productID
            metadata["series_id"] = ids.seriesID
            metadata["gallery_id"] = ids.seriesID
            metadata["type"] = "episode"
        } else if let seriesID = KakaoPageResolver.seriesID(from: target) {
            metadata["id"] = seriesID
            metadata["series_id"] = seriesID
            metadata["gallery_id"] = seriesID
            metadata["type"] = "series"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func kakaoWebtoonSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "category": "kakao_webtoon",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let episode = KakaoWebtoonResolver.viewerEpisode(from: target) {
            metadata["id"] = episode.episodeID
            metadata["post_id"] = episode.episodeID
            metadata["episode_id"] = episode.episodeID
            metadata["media_id"] = episode.episodeID
            metadata["seo_id"] = episode.seoID
            metadata["content_id"] = episode.contentID
            metadata["gallery_id"] = episode.contentID.isEmpty ? episode.seoID : episode.contentID
            metadata["type"] = "episode"
        } else if let contentID = KakaoWebtoonResolver.contentID(fromPath: target.path) {
            metadata["id"] = contentID
            metadata["content_id"] = contentID
            metadata["gallery_id"] = contentID
            metadata["type"] = "series"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func hiyobiSearchMetadata(galleryID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": galleryID,
            "post_id": galleryID,
            "gallery_id": galleryID,
            "media_id": galleryID,
            "category": "hiyobi",
            "type": "gallery",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func manatokiSearchMetadata(id: ManatokiContentID, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": id.id,
            "post_id": id.id,
            "gallery_id": id.id,
            "media_id": id.id,
            "section": id.section,
            "tag": id.section,
            "category": "manatoki",
            "type": id.section,
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func lhScanSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let parts = target.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let series = parts.count >= 2 ? parts[1] : ""
        let chapter = parts.count >= 3 ? parts[2] : ""
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": chapter.isEmpty ? series : chapter,
            "post_id": chapter,
            "chapter_id": chapter,
            "series": series,
            "series_id": series,
            "gallery_id": series,
            "category": "lhscan",
            "type": chapter.isEmpty ? "series" : "chapter",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func jManaSearchMetadata(target: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let items = URLComponents(url: target, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let book = queryValue("book", in: items) ?? ""
        let detailID = queryValue("bookdetailid", in: items) ?? ""
        let titleQuery = queryValue("title", in: items) ?? ""
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "category": "jmana",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if !detailID.isEmpty {
            metadata["id"] = detailID
            metadata["post_id"] = detailID
            metadata["chapter_id"] = detailID
            metadata["media_id"] = detailID
            metadata["book"] = book
            metadata["series_id"] = book
            metadata["gallery_id"] = book.isEmpty ? detailID : book
            metadata["type"] = "chapter"
        } else if !book.isEmpty {
            metadata["id"] = book
            metadata["book"] = book
            metadata["series_id"] = book
            metadata["gallery_id"] = book
            metadata["type"] = "series"
        } else if !titleQuery.isEmpty {
            metadata["id"] = titleQuery
            metadata["tag"] = titleQuery
            metadata["type"] = "search"
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func episodeSearchMetadata(titleID: String, episodeID: String, category: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": episodeID.isEmpty ? titleID : episodeID,
            "post_id": episodeID,
            "episode_id": episodeID,
            "media_id": episodeID,
            "title_id": titleID,
            "series_id": titleID,
            "gallery_id": titleID,
            "category": category,
            "type": "episode",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractWaybackMachineLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByTarget: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let target = WaybackMachineResolver.targetURL(from: absolute),
                  let queueURL = waybackMachineQueueURL(from: absolute, targetURL: target) else {
                continue
            }

            let title = displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: queueURL,
                id: URLIdentity.normalize(target.absoluteString),
                sitePrefix: "wayback",
                results: &results,
                indexByID: &indexByTarget,
                metadata: waybackSearchMetadata(originalURL: target, sourceURL: absolute, queueURL: queueURL, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func waybackSearchMetadata(originalURL: URL, sourceURL: URL, queueURL: URL, title: String, anchor: AnchorEntry) -> [String: String] {
        let timestamp = waybackTimestamp(from: sourceURL) ?? waybackTimestamp(from: queueURL)
        let normalizedTarget = URLIdentity.normalize(originalURL.absoluteString)
        var metadata = searchContributorMetadata(anchor: anchor)
        metadata.merge([
            "id": timestamp ?? normalizedTarget,
            "original_url": originalURL.absoluteString,
            "target_url": originalURL.absoluteString,
            "target_host": originalURL.host ?? "",
            "host": originalURL.host ?? "",
            "archive_url": queueURL.absoluteString,
            "category": "wayback",
            "type": timestamp == nil ? "cdx" : "snapshot",
            "title": title,
            "search_title": title
        ]) { current, _ in current }
        if let timestamp {
            metadata["post_id"] = timestamp
            metadata["snapshot_id"] = timestamp
            metadata["timestamp"] = timestamp
            metadata["archive_timestamp"] = timestamp
            metadata["media_id"] = timestamp
            metadata["date"] = waybackDate(from: timestamp)
        } else {
            metadata["gallery_id"] = normalizedTarget
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractArtStationProjectLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByProjectID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let projectID = artStationProjectID(from: absolute),
                  let target = cleanedURL(absolute, path: "/artwork/\(projectID)") else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "ArtStation \(projectID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: projectID,
                sitePrefix: "artstation",
                results: &results,
                indexByID: &indexByProjectID,
                metadata: artStationSearchMetadata(projectID: projectID, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func bcySearchMetadata(id: String, kind: String, title: String, anchor: AnchorEntry, target: URL) -> [String: String] {
        var metadata = [
            "id": id,
            "category": "bcy",
            "type": kind,
            "title": title,
            "search_title": title
        ]
        if kind == "item" {
            metadata["item_id"] = id
            metadata["media_id"] = id
            metadata["gallery_id"] = id
        } else {
            metadata["user_id"] = id
            metadata["gallery_id"] = id
        }

        let attributes = semanticSearchAttributes(for: anchor)
        let profileInfo = bcyUserInfo(from: anchor.contextHTML, baseURL: target)
        let displayName = firstSemanticAttribute(attributes, keys: [
            "data-artist-name", "data-artist", "artist",
            "data-author-name", "data-author", "author",
            "data-uploader-name", "data-uploader", "uploader",
            "data-user-name"
        ]) ?? (kind == "user" ? title : profileInfo?.name)
        let userID = firstSemanticAttribute(attributes, keys: [
            "data-user-id", "data-uid", "uid", "user-id"
        ]) ?? (kind == "user" ? id : profileInfo?.id)
        if let displayName {
            metadata["artist"] = displayName
            metadata["author"] = displayName
            metadata["creator"] = displayName
            metadata["uploader"] = displayName
            metadata["username"] = displayName
        }
        if let userID {
            metadata["user"] = userID
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func bcyUserInfo(from html: String, baseURL: URL) -> (id: String, name: String?)? {
        for entry in anchorEntries(from: html) {
            guard let href = entry.attributes["href"]?.trimmed,
                  let url = resolve(href: href, baseURL: baseURL),
                  let id = BCYResolver.userID(from: url) else {
                continue
            }
            let name = displayTitle(for: entry, fallback: "").trimmed
            return (id, name.isEmpty ? nil : name)
        }
        return nil
    }

    private static func fc2SearchMetadata(videoID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": videoID,
            "content_id": videoID,
            "video_id": videoID,
            "media_id": videoID,
            "category": "fc2",
            "type": "video",
            "media_type": "video",
            "title": title,
            "search_title": title
        ]
        let attributes = semanticSearchAttributes(for: anchor)
        if let uploader = firstSemanticAttribute(attributes, keys: [
            "data-uploader", "data-uploader-name", "uploader",
            "data-author", "data-author-name", "author",
            "data-artist", "data-artist-name", "artist",
            "data-channel", "data-channel-name", "channel",
            "data-user", "data-user-name", "username"
        ]) {
            metadata["artist"] = uploader
            metadata["author"] = uploader
            metadata["creator"] = uploader
            metadata["uploader"] = uploader
            metadata["username"] = uploader
            metadata["channel"] = uploader
        }
        if let userID = firstSemanticAttribute(attributes, keys: [
            "data-user-id", "data-uploader-id", "data-channel-id", "uid", "user-id"
        ]) {
            metadata["user_id"] = userID
            metadata["uploader_id"] = userID
            metadata["channel_id"] = userID
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractBCYLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            if let itemURL = BCYResolver.canonicalItemURL(from: absolute),
               let itemID = BCYResolver.itemID(from: itemURL) {
                let title = displayTitle(for: anchor, fallback: "BCY \(itemID)")
                appendUniqueResult(
                    title: title,
                    url: itemURL,
                    id: "item:\(itemID)",
                    sitePrefix: "bcy",
                    results: &results,
                    indexByID: &indexByContent,
                    metadata: bcySearchMetadata(id: itemID, kind: "item", title: title, anchor: anchor, target: itemURL)
                )
                continue
            }

            if let userID = BCYResolver.userID(from: absolute),
               let target = cleanedURL(absolute, path: "/u/\(userID)") {
                let title = displayTitle(for: anchor, fallback: userID)
                appendUniqueResult(
                    title: title,
                    url: target,
                    id: "user:\(userID)",
                    sitePrefix: "bcy",
                    results: &results,
                    indexByID: &indexByContent,
                    metadata: bcySearchMetadata(id: userID, kind: "user", title: title, anchor: anchor, target: target)
                )
            }
        }

        return results
    }

    private static func extractFC2Links(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByVideo: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let videoID = FC2Resolver.contentID(from: absolute),
                  let target = FC2Resolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "FC2 \(videoID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: videoID,
                sitePrefix: "fc2",
                results: &results,
                indexByID: &indexByVideo,
                metadata: fc2SearchMetadata(videoID: videoID, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func extractDeviantArtLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            let target: URL
            let fallback: String?
            if DeviantArtResolver.isArtworkURL(absolute),
               let artworkURL = cleanedURL(absolute) {
                target = artworkURL
                fallback = nil
            } else if let profileURL = deviantArtProfileURL(from: absolute),
                      let username = DeviantArtResolver.username(from: profileURL) {
                target = profileURL
                fallback = username
            } else {
                continue
            }

            let title = fallback.map { displayTitle(for: anchor, fallback: $0) } ?? displayTitle(for: anchor, fallbackURL: target)
            let resultID = deviantArtArtworkInfo(from: target).map { "art:\($0.id)" }
                ?? deviantArtCollectionInfo(from: target).map { "\($0.type):\($0.id)" }
                ?? URLIdentity.normalize(target.absoluteString)
            appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "deviantart",
                results: &results,
                indexByID: &indexByID,
                metadata: deviantArtSearchMetadata(title: title, anchor: anchor, target: target, fallbackUsername: fallback)
            )
        }

        return results
    }

    private static func extractPinterestPinLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPinID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  case .pin(let pinID) = PinterestResolver.kind(from: absolute),
                  let target = cleanedURL(absolute, path: "/pin/\(pinID)/") else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Pinterest \(pinID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: pinID,
                sitePrefix: "pinterest",
                results: &results,
                indexByID: &indexByPinID,
                metadata: pinterestSearchMetadata(pinID: pinID, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func extractNewgroundsArtLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            let target: URL
            let fallback: String?
            let resultID: String
            let username: String?
            let slug: String?
            let type: String
            if let artist = NewgroundsResolver.artistUsername(from: absolute) {
                target = NewgroundsResolver.artistArtURL(username: artist, sourceURL: absolute)
                fallback = "\(artist) Art"
                resultID = "artist:\(artist)"
                username = artist
                slug = nil
                type = "artist"
            } else if absolute.path.lowercased().contains("/art/view/"),
                      let clean = cleanedURL(absolute) {
                target = clean
                fallback = nil
                let info = newgroundsArtInfo(from: clean)
                resultID = info.map { "art:\($0.username):\($0.slug)" } ?? URLIdentity.normalize(clean.absoluteString)
                username = info?.username
                slug = info?.slug
                type = "artwork"
            } else {
                continue
            }

            let title = fallback.map { displayTitle(for: anchor, fallback: $0) } ?? displayTitle(for: anchor, fallbackURL: target)
            appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "newgrounds",
                results: &results,
                indexByID: &indexByID,
                metadata: newgroundsSearchMetadata(resultID: resultID, title: title, anchor: anchor, target: target, username: username, slug: slug, type: type)
            )
        }

        return results
    }

    private static func extractFlickrPhotoLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByContent: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL) else {
                continue
            }

            let target: URL
            let id: String
            let fallback: String
            if let photoID = FlickrResolver.photoID(from: absolute),
               let photoURL = FlickrResolver.canonicalPhotoURL(for: absolute) {
                target = photoURL
                id = "photo:\(photoID)"
                fallback = "Flickr \(photoID)"
            } else if let userID = FlickrResolver.userID(from: absolute),
                      let userURL = FlickrResolver.canonicalUserPhotosURL(for: absolute) {
                target = userURL
                id = "user:\(userID.lowercased())"
                fallback = userID
            } else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: fallback)
            appendUniqueResult(
                title: title,
                url: target,
                id: id,
                sitePrefix: "flickr",
                results: &results,
                indexByID: &indexByContent,
                metadata: flickrSearchMetadata(
                    resultID: id,
                    title: title,
                    target: target,
                    photoID: id.hasPrefix("photo:") ? String(id.dropFirst("photo:".count)) : nil,
                    userID: id.hasPrefix("user:") ? String(id.dropFirst("user:".count)) : FlickrResolver.userID(from: target),
                    type: id.hasPrefix("photo:") ? "photo" : "photostream"
                )
            )
        }

        return results
    }

    private static func extractBooruPostLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPostKey: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let post = booruPost(from: absolute),
                  let target = booruPostURL(post: post, sourceURL: absolute) else {
                continue
            }

            let key = "\(post.provider.rawValue.lowercased())-\(post.id)"
            let title = displayTitle(for: anchor, fallback: "\(post.provider.rawValue) \(post.id)")
            if let existingIndex = indexByPostKey[key] {
                if isWeakGalleryTitle(results[existingIndex].title, id: post.id, sitePrefix: post.provider.rawValue.lowercased()),
                   !isWeakGalleryTitle(title, id: post.id, sitePrefix: post.provider.rawValue.lowercased()) {
                    results[existingIndex].title = title
                }
                continue
            }

            indexByPostKey[key] = results.count
            results.append(SearchResultLink(
                title: title,
                url: target.absoluteString,
                siteIdentifier: post.provider.rawValue.lowercased(),
                metadata: booruSearchResultMetadata(post: post, target: target, anchor: anchor)
            ))
        }

        return results
    }

    private static func booruSearchResultMetadata(
        post: (provider: BooruProvider, id: String),
        target: URL,
        anchor: AnchorEntry
    ) -> [String: String] {
        var metadata = searchResultMetadata(
            sitePrefix: post.provider.rawValue.lowercased(),
            id: post.id,
            url: target
        )
        metadata["provider"] = post.provider.rawValue
        metadata["id"] = post.id
        metadata["post_id"] = post.id
        metadata["media_id"] = post.id
        metadata["gallery_id"] = post.id
        metadata["category"] = "booru"
        metadata["type"] = "post"

        let attributes = booruResultAttributes(postID: post.id, anchor: anchor)
        if let tags = booruMetadataValue(in: attributes, keys: ["data-tags", "data-tag-string", "data-tag-string-general", "tags", "tag-string"]) {
            let cleaned = booruTagList(tags)
            metadata["tag"] = cleaned
            metadata["tags"] = cleaned
        }
        if let rating = booruMetadataValue(in: attributes, keys: ["data-rating", "rating"]) {
            metadata["rating"] = booruRatingValue(rating)
        }
        if let score = booruMetadataValue(in: attributes, keys: ["data-score", "score"]) {
            metadata["score"] = score
        }
        if let uploader = booruMetadataValue(
            in: attributes,
            keys: ["data-uploader-name", "data-uploader", "data-owner", "data-author", "data-creator", "uploader", "owner", "author", "creator"]
        ) {
            metadata["artist"] = uploader
            metadata["author"] = uploader
            metadata["creator"] = uploader
            metadata["uploader"] = uploader
        }
        if let userID = booruMetadataValue(in: attributes, keys: ["data-uploader-id", "data-user-id", "uploader-id", "user-id"]) {
            metadata["uploader_id"] = userID
            metadata["user_id"] = userID
        }
        if let date = booruDateValue(booruMetadataValue(
            in: attributes,
            keys: ["data-created-at", "data-created", "data-date", "created-at", "created", "date"]
        )) {
            metadata["date"] = date
            metadata["created"] = date
        }
        if let format = booruMetadataValue(in: attributes, keys: ["data-file-ext", "data-ext", "file-ext", "ext", "format"]) {
            metadata["format"] = format.lowercased()
            metadata["file_format"] = format.lowercased()
        }
        let width = booruMetadataValue(in: attributes, keys: ["data-width", "width", "image-width"])
        let height = booruMetadataValue(in: attributes, keys: ["data-height", "height", "image-height"])
        if let width {
            metadata["width"] = width
        }
        if let height {
            metadata["height"] = height
        }
        if let width, let height {
            metadata["resolution"] = "\(width)x\(height)"
        }

        return DownloadMetadata.clean(metadata)
    }

    private static func booruResultAttributes(postID: String, anchor: AnchorEntry) -> [String: String] {
        var attributes = anchor.attributes
        attributes.merge(imageAttributes(from: anchor.body)) { current, _ in current }

        for candidate in booruContextTags(forPostID: postID, html: anchor.contextHTML) {
            let values = attributeValues(from: candidate)
            guard !values.isEmpty else { continue }
            attributes.merge(values) { current, new in current.isEmpty ? new : current }
        }

        return attributes
    }

    private static func booruContextTags(forPostID postID: String, html: String) -> [String] {
        let escapedID = NSRegularExpression.escapedPattern(for: postID)
        let patterns = [
            #"(<[^>]*(?:data-id|data-post-id|data-post-id-value|post-id)\s*=\s*["']"# + escapedID + #"["'][^>]*>)"#,
            #"(<[^>]*\bid\s*=\s*["']p"# + escapedID + #"["'][^>]*>)"#
        ]
        return patterns.flatMap { pattern in
            matches(in: html, pattern: pattern)
        }
    }

    private static func imageAttributes(from html: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<img\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return [:]
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let attributesRange = Range(match.range(at: 1), in: html) else {
            return [:]
        }
        return attributeValues(from: String(html[attributesRange]))
    }

    private static func booruMetadataValue(in attributes: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = attributes.first(where: { $0.key.lowercased() == key })?.value.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func booruTagList(_ raw: String) -> String {
        let decoded = decodeHTML(raw)
        return decoded
            .components(separatedBy: CharacterSet(charactersIn: ",;|+ \n\t\r"))
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .joined(separator: ", ")
    }

    private static func booruRatingValue(_ raw: String) -> String {
        switch raw.trimmed.lowercased() {
        case "s":
            return "safe"
        case "q":
            return "questionable"
        case "e":
            return "explicit"
        case "g":
            return "general"
        default:
            return raw.trimmed
        }
    }

    private static func booruDateValue(_ raw: String?) -> String? {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        if let match = firstCapture(in: raw, pattern: #"([0-9]{4}-[0-9]{2}-[0-9]{2})"#) {
            return match
        }
        return raw
    }

    private static func extractPixivArtworkLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByArtworkID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let artworkID = PixivArtworkResolver.artworkID(from: absolute) else {
                continue
            }

            let target = PixivArtworkResolver.artworkURL(for: artworkID, sourceURL: absolute)
            let title = displayTitle(for: anchor, fallback: "Pixiv \(artworkID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: artworkID,
                sitePrefix: "pixiv",
                results: &results,
                indexByID: &indexByArtworkID,
                metadata: pixivSearchMetadata(artworkID: artworkID, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func booruPost(from url: URL) -> (provider: BooruProvider, id: String)? {
        guard let provider = BooruProvider.provider(for: url) else { return nil }
        let path = url.path
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let queryItems = components?.queryItems ?? []

        switch provider {
        case .danbooru:
            let id = firstCapture(in: path, pattern: #"/posts/([0-9]+)"#) ??
                queryValue("id", in: queryItems)
            return id.map { (provider, $0) }
        case .yandere:
            let id = firstCapture(in: path, pattern: #"/post/show/([0-9]+)"#) ??
                queryValue("id", in: queryItems)
            return id.map { (provider, $0) }
        case .gelbooru, .rule34:
            guard queryValue("page", in: queryItems)?.lowercased() == "post",
                  queryValue("s", in: queryItems)?.lowercased() == "view",
                  let id = queryValue("id", in: queryItems),
                  !id.isEmpty else {
                return nil
            }
            return (provider, id)
        }
    }

    private static func booruPostURL(post: (provider: BooruProvider, id: String), sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host

        switch post.provider {
        case .danbooru:
            components.path = "/posts/\(post.id)"
        case .yandere:
            components.path = "/post/show/\(post.id)"
        case .gelbooru, .rule34:
            components.path = "/index.php"
            components.queryItems = [
                URLQueryItem(name: "page", value: "post"),
                URLQueryItem(name: "s", value: "view"),
                URLQueryItem(name: "id", value: post.id)
            ]
        }

        return components.url
    }

    private static func extractNHentaiGalleryLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let galleryID = nhentaiGalleryID(from: absolute),
                  let target = nhentaiGalleryURL(galleryID: galleryID, baseURL: baseURL) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "nHentai \(galleryID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: galleryID,
                sitePrefix: "nhentai",
                results: &results,
                indexByID: &indexByGalleryID,
                metadata: nhentaiSearchMetadata(galleryID: galleryID, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func nhentaiSearchMetadata(galleryID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": galleryID,
            "post_id": galleryID,
            "gallery_id": galleryID,
            "media_id": galleryID,
            "category": "nhentai",
            "type": "gallery",
            "media_type": "image",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractNHentaiComLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexBySlug: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let slug = NHentaiComResolver.slug(from: absolute),
                  let target = NHentaiComResolver.canonicalURL(for: absolute) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "nhentai.com \(slug)")
            appendUniqueResult(
                title: title,
                url: target,
                id: slug,
                sitePrefix: "nhentaicom",
                results: &results,
                indexByID: &indexBySlug,
                metadata: nhentaiComSearchMetadata(slug: slug, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func nhentaiComSearchMetadata(slug: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": slug,
            "post_id": slug,
            "gallery_id": slug,
            "comic_id": slug,
            "media_id": slug,
            "slug": slug,
            "category": "nhentai.com",
            "type": "comic",
            "media_type": "image",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractEHentaiGalleryLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let gallery = ehentaiGalleryID(from: absolute),
                  let target = ehentaiGalleryURL(gallery: gallery, sourceURL: absolute, baseURL: baseURL) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "E-Hentai \(gallery.id)")
            appendUniqueResult(
                title: title,
                url: target,
                id: gallery.id,
                sitePrefix: "e-hentai",
                results: &results,
                indexByID: &indexByGalleryID,
                metadata: ehentaiSearchMetadata(gallery: gallery, title: title, anchor: anchor, target: target)
            )
        }

        return results
    }

    private static func ehentaiSearchMetadata(
        gallery: (id: String, token: String, isLoFi: Bool),
        title: String,
        anchor: AnchorEntry,
        target: URL
    ) -> [String: String] {
        let host = target.host?.lowercased() ?? ""
        var metadata = [
            "id": gallery.id,
            "post_id": gallery.id,
            "gallery_id": gallery.id,
            "media_id": gallery.id,
            "gallery_token": gallery.token,
            "token": gallery.token,
            "category": host.contains("exhentai") ? "exhentai" : "e-hentai",
            "type": "gallery",
            "media_type": "image",
            "title": title,
            "search_title": title
        ]
        if gallery.isLoFi {
            metadata["mode"] = "lofi"
        }
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractNozomiPostLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByPostID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let postID = nozomiPostID(from: absolute),
                  let target = nozomiPostURL(postID: postID, baseURL: baseURL) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Nozomi \(postID)")
            appendUniqueResult(
                title: title,
                url: target,
                id: postID,
                sitePrefix: "nozomi",
                results: &results,
                indexByID: &indexByPostID,
                metadata: nozomiSearchMetadata(postID: postID, title: title, anchor: anchor)
            )
        }

        return results
    }

    private static func nozomiSearchMetadata(postID: String, title: String, anchor: AnchorEntry) -> [String: String] {
        var metadata = [
            "id": postID,
            "post_id": postID,
            "gallery_id": postID,
            "media_id": postID,
            "category": "nozomi",
            "type": "post",
            "media_type": "image",
            "title": title,
            "search_title": title
        ]
        metadata.merge(searchContributorMetadata(anchor: anchor)) { current, _ in current }
        return DownloadMetadata.clean(metadata)
    }

    private static func extractHitomiGalleryLinks(from anchors: [AnchorEntry], baseURL: URL, limit: Int) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByGalleryID: [String: Int] = [:]

        for anchor in anchors {
            guard results.count < limit,
                  let href = anchor.attributes["href"]?.trimmed,
                  let absolute = resolve(href: href, baseURL: baseURL),
                  let galleryID = hitomiGalleryID(from: absolute),
                  let target = hitomiReaderURL(galleryID: galleryID, baseURL: baseURL) else {
                continue
            }

            let title = displayTitle(for: anchor, fallback: "Hitomi \(galleryID)")
            let metadataText = hitomiResultMetadata(title: title, anchor: anchor)
            let metadata = hitomiResultMetadataFields(anchor: anchor)
            if let existingIndex = indexByGalleryID[galleryID] {
                if isWeakHitomiTitle(results[existingIndex].title, galleryID: galleryID),
                   !isWeakHitomiTitle(title, galleryID: galleryID) {
                    results[existingIndex].title = title
                    results[existingIndex].metadataText = metadataText
                    results[existingIndex].metadata = metadata
                }
                continue
            }

            indexByGalleryID[galleryID] = results.count
            results.append(SearchResultLink(
                title: title,
                url: target.absoluteString,
                siteIdentifier: "hitomi",
                metadataText: metadataText,
                metadata: metadata
            ))
        }

        return results
    }

    private static func anchorEntries(from html: String, baseURL: URL? = nil, resolutionBaseURL: URL? = nil) -> [AnchorEntry] {
        let linkResolutionBaseURL = resolutionBaseURL ?? baseURL
        let pattern = #"<a\b([^>]*)>(.*?)</a>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return jsonLDAnchorEntries(from: html, baseURL: linkResolutionBaseURL)
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries = regex.matches(in: html, range: range).compactMap { match -> AnchorEntry? in
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                return nil
            }
            let contextHTML = contextSlice(around: matchRange, in: html)
            var attributes = attributeValues(from: String(html[attributesRange]))
            if let href = normalizedHref(attributes["href"], baseURL: linkResolutionBaseURL) {
                attributes["href"] = href
            }
            return AnchorEntry(
                attributes: attributes,
                body: String(html[bodyRange]),
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            )
        }
        entries.append(contentsOf: dataAttributeAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        entries.append(contentsOf: microdataAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        entries.append(contentsOf: rdfaAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        entries.append(contentsOf: jsonLDAnchorEntries(from: html, baseURL: linkResolutionBaseURL))
        entries.append(contentsOf: jsonStateAnchorEntries(from: html, baseURL: baseURL, resolutionBaseURL: linkResolutionBaseURL))
        return entries
    }

    private static func dataAttributeAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let skippedTags: Set<String> = [
            "a", "audio", "body", "br", "head", "html", "iframe", "img",
            "input", "link", "meta", "picture", "script", "source", "style",
            "svg", "video"
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                continue
            }
            let tagName = String(html[tagRange]).lowercased()
            guard !skippedTags.contains(tagName) else { continue }

            let attributes = attributeValues(from: String(html[attributesRange]))
            guard let href = dataAttributeLinkValue(in: attributes, baseURL: baseURL),
                  !seen.contains(href) else {
                continue
            }

            let resolvedHref = normalizedHref(href, baseURL: resolutionBaseURL) ?? href
            guard !seen.contains(resolvedHref) else { continue }
            seen.insert(resolvedHref)
            let contextHTML = currentElementContext(tagName: tagName, around: matchRange, in: html) ??
                microdataCardContext(around: matchRange, in: html) ??
                contextSlice(around: matchRange, in: html)
            let title = dataAttributeTitleValue(in: attributes) ?? contextualCardTitleValue(fromHTML: contextHTML)
            var linkAttributes = attributes
            linkAttributes["href"] = resolvedHref
            if linkAttributes["title"] == nil,
               let title {
                linkAttributes["title"] = title
            }
            entries.append(AnchorEntry(
                attributes: linkAttributes,
                body: title ?? stripTags(contextHTML),
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            ))
        }

        return entries
    }

    private static func microdataAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let skippedTags: Set<String> = [
            "a", "audio", "body", "br", "head", "html", "iframe", "img",
            "input", "picture", "script", "source", "style", "svg", "video"
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                continue
            }
            let tagName = String(html[tagRange]).lowercased()
            guard !skippedTags.contains(tagName),
                  !isInsideHead(around: matchRange, in: html) else {
                continue
            }

            let attributes = attributeValues(from: String(html[attributesRange]))
            guard microdataItemprop(in: attributes, containsAnyOf: ["url", "mainentityofpage", "contenturl"]),
                  let href = microdataLinkValue(in: attributes, baseURL: baseURL),
                  !seen.contains(href) else {
                continue
            }
            let resolvedHref = normalizedHref(href, baseURL: resolutionBaseURL) ?? href
            guard !seen.contains(resolvedHref) else { continue }

            let contextHTML = microdataCardContext(around: matchRange, in: html) ?? contextSlice(around: matchRange, in: html)
            guard let title = microdataTitleValue(in: attributes, contextHTML: contextHTML) else {
                continue
            }

            seen.insert(resolvedHref)
            var linkAttributes = attributes
            linkAttributes["href"] = resolvedHref
            if linkAttributes["title"] == nil {
                linkAttributes["title"] = title
            }
            entries.append(AnchorEntry(
                attributes: linkAttributes,
                body: title,
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            ))
        }

        return entries
    }

    private static func microdataItemprop(in attributes: [String: String], containsAnyOf needles: [String]) -> Bool {
        guard let raw = attributes["itemprop"]?.lowercased() else { return false }
        let tokens = raw.split { character in
            character == " " || character == "\t" || character == "\n" || character == "\r" || character == ","
        }.map(String.init)
        return needles.contains { needle in tokens.contains(needle.lowercased()) }
    }

    private static func microdataLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        let keys = ["href", "content", "itemid", "data-url", "data-href", "data-permalink"]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  looksLikeDataAttributeLink(raw) else {
                continue
            }
            if let baseURL,
               let absolute = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
               URLIdentity.normalize(absolute.absoluteString) == URLIdentity.normalize(baseURL.absoluteString) {
                continue
            }
            return raw
        }
        return nil
    }

    private static func microdataTitleValue(in attributes: [String: String], contextHTML: String) -> String? {
        let bodyContextHTML = contextHTML.replacingOccurrences(
            of: #"<head\b[^>]*>.*?</head>"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        return dataAttributeTitleValue(in: attributes) ??
            microdataValue(fromHTML: bodyContextHTML, itemprops: ["name", "headline", "title"])
    }

    private static func microdataValue(fromHTML html: String, itemprops: [String]) -> String? {
        let alternation = itemprops.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
        let textPattern = "<[a-zA-Z][A-Za-z0-9:-]*\\b(?=[^>]*\\bitemprop\\s*=\\s*[\"'][^\"']*(?:" +
            alternation +
            ")[^\"']*[\"'])[^>]*>(.*?)</[a-zA-Z][A-Za-z0-9:-]*>"
        if let textRegex = try? NSRegularExpression(
            pattern: textPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in textRegex.matches(in: html, range: range) {
                guard let matchRange = Range(match.range, in: html),
                      let bodyRange = Range(match.range(at: 1), in: html),
                      !isInsideHead(around: matchRange, in: html) else { continue }
                let value = stripTags(String(html[bodyRange]))
                if !value.isEmpty {
                    return value
                }
            }
        }

        if let regex = try? NSRegularExpression(
            pattern: #"<[a-zA-Z][A-Za-z0-9:-]*\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let matchRange = Range(match.range, in: html),
                      let attributesRange = Range(match.range(at: 1), in: html),
                      !isInsideHead(around: matchRange, in: html) else { continue }
                let attributes = attributeValues(from: String(html[attributesRange]))
                guard microdataItemprop(in: attributes, containsAnyOf: itemprops) else { continue }
                if let value = dataAttributeTitleValue(in: attributes) ?? attributes["content"]?.trimmed,
                   !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func microdataCardContext(around range: Range<String.Index>, in html: String) -> String? {
        let blockTags = ["article", "li", "section", "div"]
        var bestRange: Range<String.Index>?
        var bestStartDistance = -1
        for tag in blockTags {
            guard let start = lastOpeningTagRange(tag, before: range, in: html),
                  let end = html.range(
                      of: "</\(tag)>",
                      options: [.caseInsensitive],
                      range: range.upperBound..<html.endIndex
                  ) else {
                continue
            }
            let candidate = start.lowerBound..<end.upperBound
            let startDistance = html.distance(from: html.startIndex, to: candidate.lowerBound)
            if startDistance > bestStartDistance {
                bestStartDistance = startDistance
                bestRange = candidate
            }
        }
        return bestRange.map { String(html[$0]) }
    }

    private static func rdfaAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let skippedTags: Set<String> = [
            "a", "audio", "body", "br", "head", "html", "iframe", "img",
            "input", "link", "meta", "picture", "script", "source", "style",
            "svg", "video"
        ]
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let tagRange = Range(match.range(at: 1), in: html),
                  let attributesRange = Range(match.range(at: 2), in: html),
                  let matchRange = Range(match.range, in: html) else {
                continue
            }
            let tagName = String(html[tagRange]).lowercased()
            guard !skippedTags.contains(tagName),
                  !isInsideHead(around: matchRange, in: html) else {
                continue
            }

            let attributes = attributeValues(from: String(html[attributesRange]))
            let contextHTML = currentElementContext(tagName: tagName, around: matchRange, in: html) ??
                microdataCardContext(around: matchRange, in: html) ??
                contextSlice(around: matchRange, in: html)
            guard rdfaLooksLikeResultCard(attributes: attributes, contextHTML: contextHTML),
                  let href = rdfaLinkValue(in: attributes, contextHTML: contextHTML, baseURL: baseURL),
                  !seen.contains(href) else {
                continue
            }
            let resolvedHref = normalizedHref(href, baseURL: resolutionBaseURL) ?? href
            guard !seen.contains(resolvedHref),
                  let title = rdfaTitleValue(in: attributes, contextHTML: contextHTML) else {
                continue
            }

            seen.insert(resolvedHref)
            var linkAttributes = attributes
            linkAttributes["href"] = resolvedHref
            linkAttributes["title"] = title
            linkAttributes.merge(rdfaSemanticAttributes(fromHTML: contextHTML)) { current, _ in current }
            entries.append(AnchorEntry(
                attributes: linkAttributes,
                body: title,
                context: decodeHTML(stripTags(contextHTML)),
                contextHTML: contextHTML
            ))
        }

        return entries
    }

    private static func rdfaLooksLikeResultCard(attributes: [String: String], contextHTML: String) -> Bool {
        let ownText = [
            attributes["typeof"],
            attributes["vocab"],
            attributes["prefix"],
            attributes["property"],
            attributes["rel"]
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        let text = [
            ownText,
            contextHTML
        ].map { $0.lowercased() }.joined(separator: " ")

        let excludedNeedles = [
            "breadcrumblist", "website", "webpage", "organization", "person",
            "searchresults", "searchaction", "sitenavigationelement", "wpheader", "wpfooter"
        ]
        if excludedNeedles.contains(where: { ownText.contains($0) }) {
            return false
        }

        let contentNeedles = [
            "creativework", "article", "blogposting", "socialmediaposting",
            "imageobject", "videoobject", "audioobject", "mediaobject",
            "product", "comic", "book", "episode", "clip", "gallery", "posting"
        ]
        if contentNeedles.contains(where: { text.contains($0) }) {
            return true
        }

        return rdfaContainsProperty(contextHTML, anyOf: ["url", "mainentityofpage", "contenturl"]) &&
            rdfaContainsProperty(contextHTML, anyOf: ["name", "headline", "title"])
    }

    private static func rdfaLinkValue(in attributes: [String: String], contextHTML: String, baseURL: URL?) -> String? {
        let directKeys = ["resource", "about", "href", "src", "content", "data-url", "data-href", "data-permalink"]
        for key in directKeys {
            guard let raw = attributes[key]?.trimmed,
                  looksLikeDataAttributeLink(raw) else {
                continue
            }
            if let baseURL,
               let absolute = URL(string: raw, relativeTo: baseURL)?.absoluteURL,
               URLIdentity.normalize(absolute.absoluteString) == URLIdentity.normalize(baseURL.absoluteString) {
                continue
            }
            return raw
        }

        return rdfaPropertyValue(
            fromHTML: contextHTML,
            properties: ["url", "mainentityofpage", "contenturl"],
            valueKeys: ["href", "resource", "about", "content", "src", "data-url", "data-href", "data-permalink"],
            allowText: false
        ).flatMap { looksLikeDataAttributeLink($0) ? $0 : nil }
    }

    private static func rdfaTitleValue(in attributes: [String: String], contextHTML: String) -> String? {
        dataAttributeTitleValue(in: attributes).flatMap(cleanContextualTitle) ??
            rdfaPropertyValue(
                fromHTML: contextHTML,
                properties: ["name", "headline", "title"],
                valueKeys: ["content", "title", "aria-label", "data-title", "data-name"],
                allowText: true
            ).flatMap(cleanContextualTitle) ??
            contextualCardTitleValue(fromHTML: contextHTML)
    }

    private static func rdfaSemanticAttributes(fromHTML html: String) -> [String: String] {
        var attributes: [String: String] = [:]
        if let author = rdfaPropertyValue(
            fromHTML: html,
            properties: ["author", "creator", "dc:creator"],
            valueKeys: ["content", "title", "aria-label", "data-author", "data-artist", "data-name"],
            allowText: true
        ).flatMap(cleanContextualTitle) {
            attributes["data-author-name"] = author
            attributes["data-artist"] = author
            attributes["data-creator"] = author
        }
        if let date = rdfaPropertyValue(
            fromHTML: html,
            properties: ["datepublished", "datecreated", "uploaddate", "dc:date", "published"],
            valueKeys: ["datetime", "content", "data-date", "title"],
            allowText: true
        ).flatMap(booruDateValue) {
            attributes["data-date"] = date
        }
        return attributes
    }

    private static func rdfaContainsProperty(_ html: String, anyOf properties: [String]) -> Bool {
        rdfaPropertyValue(fromHTML: html, properties: properties, valueKeys: ["content", "href", "resource", "about"], allowText: true) != nil
    }

    private static func rdfaPropertyValue(fromHTML html: String, properties: [String], valueKeys: [String], allowText: Bool) -> String? {
        let wanted = Set(properties.map { $0.lowercased() })

        if let regex = try? NSRegularExpression(
            pattern: #"<[a-zA-Z][A-Za-z0-9:-]*\b(?=[^>]*\b(?:property|rel)\s*=)([^>]*)/?>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) {
            let range = NSRange(html.startIndex..<html.endIndex, in: html)
            for match in regex.matches(in: html, range: range) {
                guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
                let attributes = attributeValues(from: String(html[attributesRange]))
                guard rdfaPropertyTokens(in: attributes).contains(where: { wanted.contains($0) }) else {
                    continue
                }

                for key in valueKeys {
                    guard let value = attributes[key]?.trimmed,
                          !value.isEmpty else {
                        continue
                    }
                    return value
                }
            }
        }

        guard allowText,
              let textRegex = try? NSRegularExpression(
                  pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b(?=[^>]*\b(?:property|rel)\s*=)([^>]*)>(.*?)</\1>"#,
                  options: [.caseInsensitive, .dotMatchesLineSeparators]
              ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in textRegex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 2), in: html),
                  let bodyRange = Range(match.range(at: 3), in: html) else {
                continue
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard rdfaPropertyTokens(in: attributes).contains(where: { wanted.contains($0) }) else {
                continue
            }
            guard let title = cleanContextualTitle(String(html[bodyRange])) else {
                continue
            }
            return title
        }
        return nil
    }

    private static func rdfaPropertyTokens(in attributes: [String: String]) -> [String] {
        let raw = [attributes["property"], attributes["rel"]].compactMap { $0 }.joined(separator: " ").lowercased()
        return raw.split { character in
            character == " " || character == "\t" || character == "\n" || character == "\r" || character == ","
        }.map(String.init)
    }

    private static func currentElementContext(tagName: String, around range: Range<String.Index>, in html: String) -> String? {
        let lowerTagName = tagName.lowercased()
        let voidTags: Set<String> = [
            "area", "base", "br", "col", "embed", "hr", "img", "input",
            "link", "meta", "param", "source", "track", "wbr"
        ]
        guard !voidTags.contains(lowerTagName),
              let end = html.range(
                  of: "</\(lowerTagName)>",
                  options: [.caseInsensitive],
                  range: range.upperBound..<html.endIndex
              ) else {
            return nil
        }
        let candidate = range.lowerBound..<end.upperBound
        guard html.distance(from: candidate.lowerBound, to: candidate.upperBound) <= 6_000 else {
            return nil
        }
        return String(html[candidate])
    }

    private static func lastOpeningTagRange(_ tag: String, before range: Range<String.Index>, in html: String) -> Range<String.Index>? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(tag)\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let searchRange = NSRange(html.startIndex..<range.lowerBound, in: html)
        return regex.matches(in: html, range: searchRange)
            .compactMap { Range($0.range, in: html) }
            .last
    }

    private static func isInsideHead(around range: Range<String.Index>, in html: String) -> Bool {
        let prefix = String(html[..<range.lowerBound]).lowercased()
        guard let headStart = prefix.range(of: "<head", options: .backwards) else {
            guard prefix.range(of: "</head>", options: .backwards) == nil else {
                return false
            }
            let suffix = String(html[range.lowerBound...]).lowercased()
            guard let headEnd = suffix.range(of: "</head>") else {
                return false
            }
            if let bodyStart = suffix.range(of: "<body"),
               bodyStart.lowerBound < headEnd.lowerBound {
                return false
            }
            return true
        }
        if let headEnd = prefix.range(of: "</head>", options: .backwards),
           headEnd.lowerBound > headStart.lowerBound {
            return false
        }
        return true
    }

    private static func dataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        if let waybackLink = waybackDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return waybackLink
        }
        if let host = baseURL?.host?.lowercased(),
           isGoogleHost(host) {
            return googleDataAttributeLinkValue(in: attributes, baseURL: baseURL)
        }

        let keys = [
            "data-href", "data-url", "data-permalink", "data-link",
            "data-target-url", "data-target", "data-canonical-url",
            "data-result-url", "data-destination-url",
            "data-post-url", "data-video-url", "data-watch-url",
            "data-page-url", "data-entry-url", "data-uri", "data-path",
            "data-click-url", "data-click-href", "data-open-url",
            "data-action-url", "data-redirect-url", "data-navigate-url"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  let href = dataAttributeNavigationCandidate(from: raw, baseURL: baseURL) else {
                continue
            }
            return href
        }
        if let eventLink = eventAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return eventLink
        }
        if let hitomiLink = hitomiDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return hitomiLink
        }
        if let nhentaiLink = nhentaiDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return nhentaiLink
        }
        if let nhentaiComLink = nhentaiComDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return nhentaiComLink
        }
        if let ehentaiLink = ehentaiDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return ehentaiLink
        }
        if let nozomiLink = nozomiDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return nozomiLink
        }
        if let booruPostLink = booruDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return booruPostLink
        }
        if let artStationProjectLink = artStationDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return artStationProjectLink
        }
        if let bcyLink = bcyDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return bcyLink
        }
        if let fc2Link = fc2DataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return fc2Link
        }
        if let pinterestPinLink = pinterestDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return pinterestPinLink
        }
        if let deviantArtLink = deviantArtDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return deviantArtLink
        }
        if let newgroundsLink = newgroundsDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return newgroundsLink
        }
        if let flickrLink = flickrDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return flickrLink
        }
        if let coubLink = coubDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return coubLink
        }
        if let vimeoLink = vimeoDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return vimeoLink
        }
        if let soundCloudLink = soundCloudDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return soundCloudLink
        }
        if let kakaoTVLink = kakaoTVDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return kakaoTVLink
        }
        if let twitterLink = twitterDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return twitterLink
        }
        if let tikTokLink = tikTokDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return tikTokLink
        }
        if let bilibiliLink = bilibiliDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return bilibiliLink
        }
        if let chzzkLink = chzzkDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return chzzkLink
        }
        if let soopLink = soopDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return soopLink
        }
        if let niconicoLink = niconicoDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return niconicoLink
        }
        if let twitchLink = twitchDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return twitchLink
        }
        if let iwaraLink = iwaraDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return iwaraLink
        }
        if let instagramLink = instagramDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return instagramLink
        }
        if let facebookLink = facebookDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return facebookLink
        }
        if let pornhubLink = pornhubDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return pornhubLink
        }
        if let weiboLink = weiboDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return weiboLink
        }
        if let spankBangLink = spankBangDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return spankBangLink
        }
        if let xVideoLink = xVideoDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return xVideoLink
        }
        if let etcVideoLink = etcVideoDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return etcVideoLink
        }
        if let originalMediaLink = originalYTDLPMediaDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return originalMediaLink
        }
        if let imagePostLink = imagePostDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return imagePostLink
        }
        if let fediverseLink = fediverseDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return fediverseLink
        }
        if let communityImageLink = communityImageDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return communityImageLink
        }
        if let galleryBlogLink = galleryBlogDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return galleryBlogLink
        }
        if let textFictionLink = textFictionDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return textFictionLink
        }
        if let koreanPortalLink = koreanPortalDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return koreanPortalLink
        }
        if let webComicLink = webComicDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return webComicLink
        }
        if let mangaPortalLink = mangaPortalDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return mangaPortalLink
        }
        if let pixivArtworkLink = pixivDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return pixivArtworkLink
        }
        if let youtubeIDLink = youtubeDataAttributeLinkValue(in: attributes, baseURL: baseURL) {
            return youtubeIDLink
        }
        return nil
    }

    private static func eventAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        let keys = ["onclick", "onmousedown", "onmouseup", "onauxclick", "data-onclick"]
        for key in keys {
            guard let script = attributes[key]?.trimmed,
                  let href = eventNavigationURL(in: script, baseURL: baseURL) else {
                continue
            }
            return href
        }
        return nil
    }

    private static func eventNavigationURL(in script: String, baseURL: URL?) -> String? {
        let lowercasedScript = script.lowercased()
        guard lowercasedScript.contains("location") || lowercasedScript.contains("window.open") else {
            return nil
        }

        let patterns = [
            #"(?:window\.)?location(?:\.href)?\s*=\s*(['"])(.*?)\1"#,
            #"document\.location(?:\.href)?\s*=\s*(['"])(.*?)\1"#,
            #"(?:window\.)?location\.(?:assign|replace)\s*\(\s*(['"])(.*?)\1"#,
            #"window\.open\s*\(\s*(['"])(.*?)\1"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive, .dotMatchesLineSeparators]
            ) else {
                continue
            }
            let range = NSRange(script.startIndex..<script.endIndex, in: script)
            for match in regex.matches(in: script, range: range) {
                guard let rawRange = Range(match.range(at: 2), in: script) else { continue }
                let raw = decodedJavaScriptStringLiteral(String(script[rawRange]))
                if let candidate = eventNavigationCandidate(from: raw, baseURL: baseURL) {
                    return candidate
                }
            }
        }
        return nil
    }

    private static func eventNavigationCandidate(from raw: String, baseURL: URL?) -> String? {
        dataAttributeNavigationCandidate(from: raw, baseURL: baseURL)
    }

    private static func dataAttributeNavigationCandidate(from raw: String, baseURL: URL?) -> String? {
        let candidate = raw.trimmed
        guard looksLikeDataAttributeLink(candidate) else { return nil }
        if let baseURL,
           let absolute = URL(string: candidate, relativeTo: baseURL)?.absoluteURL,
           URLIdentity.normalize(absolute.absoluteString) == URLIdentity.normalize(baseURL.absoluteString) {
            return nil
        }
        return candidate
    }

    private static func decodedJavaScriptStringLiteral(_ raw: String) -> String {
        var value = raw
            .replacingOccurrences(of: #"\/"#, with: "/")
            .replacingOccurrences(of: #"\""#, with: "\"")
            .replacingOccurrences(of: #"\'"#, with: "'")
            .replacingOccurrences(of: #"\\\\"#, with: #"\"#)

        guard let regex = try? NSRegularExpression(pattern: #"\\u([0-9A-Fa-f]{4})"#) else {
            return value
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        for match in regex.matches(in: value, range: range).reversed() {
            guard let fullRange = Range(match.range, in: value),
                  let hexRange = Range(match.range(at: 1), in: value),
                  let scalarValue = UInt32(value[hexRange], radix: 16),
                  let scalar = UnicodeScalar(scalarValue) else {
                continue
            }
            value.replaceSubrange(fullRange, with: String(scalar))
        }
        return value
    }

    private static func coubDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isCoubHost(host),
              let id = coubDataAttributeID(in: attributes),
              coubDataAttributeLooksLikeClipCard(attributes) else {
            return nil
        }
        return "/view/\(id)"
    }

    private static func coubDataAttributeID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-coub-id", "data-coubid", "data-clip-id",
            "data-clipid", "data-video-id", "data-videoid",
            "data-media-id", "coub-id", "clip-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               value.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           id.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil,
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["coub", "clip", "video"]) {
            return id
        }
        return nil
    }

    private static func coubDataAttributeLooksLikeClipCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-coub-id", "data-coubid", "data-clip-id",
            "data-clipid", "data-video-id", "data-videoid",
            "data-media-id", "coub-id", "clip-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["coub", "clip", "video"])
    }

    private static func vimeoDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isVimeoHost(host),
              let id = vimeoDataAttributeVideoID(in: attributes),
              vimeoDataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        return "/\(id)"
    }

    private static func vimeoDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-vimeo-id", "data-vimeoid", "data-video-id",
            "data-videoid", "data-clip-id", "data-clipid",
            "video-id", "clip-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           id.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil,
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["vimeo", "video", "clip"]) {
            return id
        }
        return nil
    }

    private static func vimeoDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-vimeo-id", "data-vimeoid", "data-video-id",
            "data-videoid", "data-clip-id", "data-clipid",
            "video-id", "clip-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["vimeo", "video", "clip"])
    }

    private static func soundCloudDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSoundCloudHost(host),
              let path = soundCloudDataAttributeTrackPath(in: attributes),
              soundCloudDataAttributeLooksLikeTrackCard(attributes) else {
            return nil
        }
        return path
    }

    private static func soundCloudDataAttributeTrackPath(in attributes: [String: String]) -> String? {
        let pathKeys = [
            "data-permalink-path", "data-permalinkpath",
            "data-track-path", "data-trackpath", "permalink-path"
        ]
        for key in pathKeys {
            if let path = soundCloudTrackPath(from: attributes[key]) {
                return path
            }
        }
        if let path = soundCloudTrackPath(from: attributes["data-id"]),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["soundcloud", "track", "audio"]) {
            return path
        }

        let usernameKeys = [
            "data-username", "data-user-username", "data-user-permalink",
            "data-user-permalink-name", "data-artist-username"
        ]
        let slugKeys = [
            "data-track-slug", "data-track-permalink", "data-permalink",
            "data-slug", "data-title-slug"
        ]
        guard let username = firstValidPathSlug(in: attributes, keys: usernameKeys),
              let slug = firstValidPathSlug(in: attributes, keys: slugKeys) else {
            return nil
        }
        return "/\(username)/\(slug)"
    }

    private static func soundCloudTrackPath(from value: String?) -> String? {
        guard let value = value?.trimmed,
              !value.isEmpty else {
            return nil
        }
        let trimmed = value.hasPrefix("/") ? String(value.dropFirst()) : value
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2,
              isValidPathSlug(parts[0]),
              isValidPathSlug(parts[1]) else {
            return nil
        }
        let second = parts[1].lowercased()
        guard !["sets", "albums", "tracks", "likes", "reposts", "popular-tracks"].contains(second) else {
            return nil
        }
        return "/\(parts[0])/\(parts[1])"
    }

    private static func soundCloudDataAttributeLooksLikeTrackCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-permalink-path", "data-permalinkpath",
            "data-track-path", "data-trackpath", "permalink-path",
            "data-track-slug", "data-track-permalink"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["soundcloud", "track", "audio"])
    }

    private static func kakaoTVDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isKakaoTVHost(host),
              let id = kakaoTVDataAttributeClipID(in: attributes),
              kakaoTVDataAttributeLooksLikeClipCard(attributes) else {
            return nil
        }
        if let channelID = firstValidPathSlug(
            in: attributes,
            keys: ["data-channel-id", "data-channelid", "channel-id"]
        ) {
            return "/channel/\(channelID)/cliplink/\(id)"
        }
        return "/v/\(id)"
    }

    private static func kakaoTVDataAttributeClipID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-clip-id", "data-clipid", "data-cliplink-id",
            "data-cliplinkid", "data-video-id", "data-videoid",
            "clip-id", "video-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               value.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           id.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil,
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["kakao", "clip", "video"]) {
            return id
        }
        return nil
    }

    private static func kakaoTVDataAttributeLooksLikeClipCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-clip-id", "data-clipid", "data-cliplink-id",
            "data-cliplinkid", "data-video-id", "data-videoid",
            "clip-id", "video-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["kakao", "clip", "video"])
    }

    private static func twitterDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isTwitterHost(host) else {
            return nil
        }
        if let id = twitterDataAttributeTweetID(in: attributes),
           twitterDataAttributeLooksLikeTweetCard(attributes) {
            if let username = twitterDataAttributeUsername(in: attributes) {
                return "/\(username)/status/\(id)"
            }
            return "/i/web/status/\(id)"
        }
        if let id = twitterDataAttributeSpaceID(in: attributes),
           twitterDataAttributeLooksLikeSpaceCard(attributes) {
            return "/i/spaces/\(id)"
        }
        if let id = twitterDataAttributeBroadcastID(in: attributes),
           twitterDataAttributeLooksLikeBroadcastCard(attributes) {
            return "/i/broadcasts/\(id)"
        }
        if let id = twitterDataAttributeUserID(in: attributes),
           twitterDataAttributeLooksLikeUserCard(attributes) {
            return "/i/user/\(id)"
        }
        return nil
    }

    private static func twitterDataAttributeTweetID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-tweet-id", "data-tweetid", "data-status-id",
            "data-statusid", "data-conversation-id", "data-conversationid",
            "tweet-id", "status-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isTwitterNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isTwitterNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["tweet", "status", "post"]) {
            return id
        }
        return nil
    }

    private static func twitterDataAttributeSpaceID(in attributes: [String: String]) -> String? {
        let keys = ["data-space-id", "data-spaceid", "space-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["space"]) {
            return id
        }
        return nil
    }

    private static func twitterDataAttributeBroadcastID(in attributes: [String: String]) -> String? {
        let keys = ["data-broadcast-id", "data-broadcastid", "broadcast-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["broadcast"]) {
            return id
        }
        return nil
    }

    private static func twitterDataAttributeUserID(in attributes: [String: String]) -> String? {
        let keys = ["data-user-id", "data-userid", "user-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isTwitterNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isTwitterNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "profile", "account"]) {
            return id
        }
        return nil
    }

    private static func twitterDataAttributeUsername(in attributes: [String: String]) -> String? {
        let keys = [
            "data-screen-name", "data-screenname", "data-username",
            "data-author-username", "username", "screen-name"
        ]
        return firstAttributeValue(in: attributes, keys: keys, matching: isValidTwitterUsername)
    }

    private static func twitterDataAttributeLooksLikeTweetCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-tweet-id", "data-tweetid", "data-status-id",
            "data-statusid", "data-conversation-id", "data-conversationid",
            "tweet-id", "status-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["tweet", "status", "post"])
    }

    private static func twitterDataAttributeLooksLikeSpaceCard(_ attributes: [String: String]) -> Bool {
        if ["data-space-id", "data-spaceid", "space-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["space"])
    }

    private static func twitterDataAttributeLooksLikeBroadcastCard(_ attributes: [String: String]) -> Bool {
        if ["data-broadcast-id", "data-broadcastid", "broadcast-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["broadcast"])
    }

    private static func twitterDataAttributeLooksLikeUserCard(_ attributes: [String: String]) -> Bool {
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "profile", "account"])
    }

    private static func tikTokDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isTikTokHost(host) else {
            return nil
        }
        if let id = tikTokDataAttributeVideoID(in: attributes),
           tikTokDataAttributeLooksLikeVideoCard(attributes) {
            if !host.contains("douyin"),
               let username = tikTokDataAttributeUsername(in: attributes) {
                return "/@\(username)/video/\(id)"
            }
            return "/video/\(id)"
        }
        if let username = tikTokDataAttributeUsername(in: attributes),
           tikTokDataAttributeLooksLikeProfileCard(attributes) {
            return host.contains("douyin") ? "/user/\(username)" : "/@\(username)"
        }
        return nil
    }

    private static func tikTokDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-item-id",
            "data-itemid", "data-aweme-id", "data-awemeid",
            "video-id", "item-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isTikTokNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isTikTokNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["tiktok", "douyin", "video", "photo"]) {
            return id
        }
        return nil
    }

    private static func tikTokDataAttributeUsername(in attributes: [String: String]) -> String? {
        let keys = [
            "data-unique-id", "data-uniqueid", "data-username",
            "data-author-username", "data-user-username", "username"
        ]
        return firstAttributeValue(in: attributes, keys: keys, matching: isValidTikTokUsername)
    }

    private static func tikTokDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-video-id", "data-videoid", "data-item-id",
            "data-itemid", "data-aweme-id", "data-awemeid",
            "video-id", "item-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["tiktok", "douyin", "video", "photo"])
    }

    private static func tikTokDataAttributeLooksLikeProfileCard(_ attributes: [String: String]) -> Bool {
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "profile", "author", "creator"])
    }

    private static func bilibiliDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isBilibiliHost(host),
              let id = bilibiliDataAttributeVideoID(in: attributes),
              bilibiliDataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        return "/video/\(id)"
    }

    private static func bilibiliDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let bvidKeys = ["data-bvid", "data-bv-id", "data-bvid-id", "bvid"]
        for key in bvidKeys {
            if let value = attributes[key]?.trimmed,
               let id = normalizedBilibiliDataVideoID(value) {
                return id
            }
        }
        let aidKeys = ["data-aid", "data-av-id", "data-avid", "aid", "av-id"]
        for key in aidKeys {
            if let value = attributes[key]?.trimmed,
               let id = normalizedBilibiliDataVideoID(value) {
                return id
            }
        }
        let videoKeys = ["data-video-id", "data-videoid", "video-id"]
        for key in videoKeys {
            if let value = attributes[key]?.trimmed,
               let id = normalizedBilibiliDataVideoID(value) {
                return id
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           let normalized = normalizedBilibiliDataVideoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["bilibili", "bili", "video"]) {
            return normalized
        }
        return nil
    }

    private static func normalizedBilibiliDataVideoID(_ value: String) -> String? {
        let clean = value.trimmed
        if clean.range(of: #"^BV[0-9A-Za-z]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
            return clean
        }
        if clean.range(of: #"^av[0-9]+$"#, options: [.caseInsensitive, .regularExpression]) != nil {
            return clean
        }
        if clean.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil {
            return "av\(clean)"
        }
        if clean.range(of: #"^[0-9A-Za-z_-]{6,}$"#, options: .regularExpression) != nil {
            return clean
        }
        return nil
    }

    private static func bilibiliDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-bvid", "data-bv-id", "data-bvid-id", "bvid",
            "data-aid", "data-av-id", "data-avid", "aid", "av-id",
            "data-video-id", "data-videoid", "video-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["bilibili", "bili", "video"])
    }

    private static func chzzkDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isChzzkHost(host) else {
            return nil
        }
        if let id = chzzkDataAttributeClipID(in: attributes),
           chzzkDataAttributeLooksLikeClipCard(attributes) {
            return "/clips/\(id)"
        }
        if let id = chzzkDataAttributeVODID(in: attributes),
           chzzkDataAttributeLooksLikeVODCard(attributes) {
            return "/video/\(id)"
        }
        if let id = chzzkDataAttributeLiveID(in: attributes),
           chzzkDataAttributeLooksLikeLiveCard(attributes) {
            return "/live/\(id)"
        }
        return nil
    }

    private static func chzzkDataAttributeClipID(in attributes: [String: String]) -> String? {
        let keys = ["data-clip-id", "data-clipid", "data-clip-uid", "data-clipuid", "clip-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidChzzkClipID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidChzzkClipID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip"]) {
            return id
        }
        return nil
    }

    private static func chzzkDataAttributeVODID(in attributes: [String: String]) -> String? {
        let keys = ["data-vod-id", "data-vodid", "data-video-id", "data-videoid", "vod-id", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidChzzkVideoID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidChzzkVideoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "vod"]) {
            return id
        }
        return nil
    }

    private static func chzzkDataAttributeLiveID(in attributes: [String: String]) -> String? {
        let keys = ["data-live-id", "data-liveid", "live-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidChzzkLiveID) {
            return value
        }
        if let channelID = firstAttributeValue(in: attributes, keys: ["data-channel-id", "data-channelid", "channel-id"], matching: isValidChzzkLiveID),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["live"]) {
            return channelID
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidChzzkLiveID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["live"]) {
            return id
        }
        return nil
    }

    private static func chzzkDataAttributeLooksLikeClipCard(_ attributes: [String: String]) -> Bool {
        if ["data-clip-id", "data-clipid", "data-clip-uid", "data-clipuid", "clip-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip"])
    }

    private static func chzzkDataAttributeLooksLikeVODCard(_ attributes: [String: String]) -> Bool {
        if ["data-vod-id", "data-vodid", "data-video-id", "data-videoid", "vod-id", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "vod"])
    }

    private static func chzzkDataAttributeLooksLikeLiveCard(_ attributes: [String: String]) -> Bool {
        if ["data-live-id", "data-liveid", "live-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["live"])
    }

    private static func soopDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSOOPHost(host) else {
            return nil
        }
        if let id = soopDataAttributeLiveID(in: attributes),
           soopDataAttributeLooksLikeLiveCard(attributes) {
            return soopLiveDataAttributeURL(id: id, baseHost: host)
        }
        if let id = soopDataAttributeCatchID(in: attributes),
           soopDataAttributeLooksLikeCatchCard(attributes) {
            return "/catch/\(id)"
        }
        if let id = soopDataAttributeVideoID(in: attributes),
           soopDataAttributeLooksLikeVideoCard(attributes) {
            return "/player/\(id)"
        }
        return nil
    }

    private static func soopDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-vod-id", "data-vodid", "data-video-id", "data-videoid",
            "data-title-no", "data-titleno", "data-broad-no", "data-broadno",
            "vod-id", "video-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSOOPNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSOOPNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "vod", "player"]) {
            return id
        }
        return nil
    }

    private static func soopDataAttributeCatchID(in attributes: [String: String]) -> String? {
        let keys = ["data-catch-id", "data-catchid", "catch-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSOOPNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSOOPNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["catch"]) {
            return id
        }
        return nil
    }

    private static func soopDataAttributeLiveID(in attributes: [String: String]) -> String? {
        let keys = ["data-live-id", "data-liveid", "data-bj-id", "data-bjid", "live-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSOOPLiveID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSOOPLiveID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["live"]) {
            return id
        }
        return nil
    }

    private static func soopDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-vod-id", "data-vodid", "data-video-id", "data-videoid",
            "data-title-no", "data-titleno", "data-broad-no", "data-broadno",
            "vod-id", "video-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "vod", "player"])
    }

    private static func soopDataAttributeLooksLikeCatchCard(_ attributes: [String: String]) -> Bool {
        if ["data-catch-id", "data-catchid", "catch-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["catch"])
    }

    private static func soopDataAttributeLooksLikeLiveCard(_ attributes: [String: String]) -> Bool {
        if ["data-live-id", "data-liveid", "data-bj-id", "data-bjid", "live-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["live"])
    }

    private static func soopLiveDataAttributeURL(id: String, baseHost: String) -> String {
        let host = baseHost.hasSuffix(".test") ? "play.sooplive.test" : "play.sooplive.com"
        return "https://\(host)/\(id)"
    }

    private static func niconicoDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isNiconicoHost(host) else {
            return nil
        }
        if let id = niconicoDataAttributeVideoID(in: attributes),
           niconicoDataAttributeLooksLikeVideoCard(attributes) {
            return "https://\(niconicoWebHost(for: host))/watch/\(id)"
        }
        if let id = niconicoDataAttributeLiveID(in: attributes),
           niconicoDataAttributeLooksLikeLiveCard(attributes) {
            return "https://\(niconicoLiveHost(for: host))/watch/\(id)"
        }
        if let id = niconicoDataAttributeUserID(in: attributes),
           niconicoDataAttributeLooksLikeUserCard(attributes) {
            return "https://\(niconicoWebHost(for: host))/user/\(id)"
        }
        if let id = niconicoDataAttributeChannelID(in: attributes),
           niconicoDataAttributeLooksLikeChannelCard(attributes) {
            return "https://\(niconicoChannelHost(for: host))/\(id)"
        }
        return nil
    }

    private static func niconicoDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = ["data-video-id", "data-videoid", "data-watch-id", "data-watchid", "video-id", "watch-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidNiconicoVideoID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidNiconicoVideoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "movie"]) {
            return id
        }
        return nil
    }

    private static func niconicoDataAttributeLiveID(in attributes: [String: String]) -> String? {
        let keys = ["data-live-id", "data-liveid", "data-program-id", "data-programid", "live-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidNiconicoLiveID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidNiconicoLiveID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["live", "program"]) {
            return id
        }
        return nil
    }

    private static func niconicoDataAttributeUserID(in attributes: [String: String]) -> String? {
        let keys = ["data-user-id", "data-userid", "data-owner-id", "data-ownerid", "user-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isNiconicoNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isNiconicoNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "profile", "owner"]) {
            return id
        }
        return nil
    }

    private static func niconicoDataAttributeChannelID(in attributes: [String: String]) -> String? {
        let keys = ["data-channel-id", "data-channelid", "data-channel-slug", "channel-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["channel"]) {
            return id
        }
        return nil
    }

    private static func niconicoDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-video-id", "data-videoid", "data-watch-id", "data-watchid", "video-id", "watch-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "movie"])
    }

    private static func niconicoDataAttributeLooksLikeLiveCard(_ attributes: [String: String]) -> Bool {
        if ["data-live-id", "data-liveid", "data-program-id", "data-programid", "live-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["live", "program"])
    }

    private static func niconicoDataAttributeLooksLikeUserCard(_ attributes: [String: String]) -> Bool {
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "profile", "owner"])
    }

    private static func niconicoDataAttributeLooksLikeChannelCard(_ attributes: [String: String]) -> Bool {
        if ["data-channel-id", "data-channelid", "data-channel-slug", "channel-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["channel"])
    }

    private static func niconicoWebHost(for host: String) -> String {
        host.hasSuffix(".test") ? "www.nicovideo.test" : "www.nicovideo.jp"
    }

    private static func niconicoLiveHost(for host: String) -> String {
        host.hasSuffix(".test") ? "live.nicovideo.test" : "live.nicovideo.jp"
    }

    private static func niconicoChannelHost(for host: String) -> String {
        host.hasSuffix(".test") ? "ch.nicovideo.test" : "ch.nicovideo.jp"
    }

    private static func twitchDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isTwitchHost(host) else {
            return nil
        }
        if let id = twitchDataAttributeVODID(in: attributes),
           twitchDataAttributeLooksLikeVODCard(attributes) {
            return "/videos/\(id)"
        }
        if let slug = twitchDataAttributeClipSlug(in: attributes),
           twitchDataAttributeLooksLikeClipCard(attributes) {
            if let username = twitchDataAttributeUsername(in: attributes) {
                return "/\(username)/clip/\(slug)"
            }
            return "https://\(twitchClipsHost(for: host))/\(slug)"
        }
        return nil
    }

    private static func twitchDataAttributeVODID(in attributes: [String: String]) -> String? {
        let keys = ["data-vod-id", "data-vodid", "data-video-id", "data-videoid", "vod-id", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isTwitchNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isTwitchNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["vod", "video"]) {
            return id
        }
        return nil
    }

    private static func twitchDataAttributeClipSlug(in attributes: [String: String]) -> String? {
        let keys = ["data-clip-id", "data-clipid", "data-clip-slug", "data-clipslug", "clip-id", "clip-slug"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidTwitchSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidTwitchSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip"]) {
            return id
        }
        return nil
    }

    private static func twitchDataAttributeUsername(in attributes: [String: String]) -> String? {
        let keys = ["data-channel-login", "data-channel", "data-username", "data-user-login", "username"]
        return firstAttributeValue(in: attributes, keys: keys, matching: isValidTwitchSlug)
    }

    private static func twitchDataAttributeLooksLikeVODCard(_ attributes: [String: String]) -> Bool {
        if ["data-vod-id", "data-vodid", "data-video-id", "data-videoid", "vod-id", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["vod", "video"])
    }

    private static func twitchDataAttributeLooksLikeClipCard(_ attributes: [String: String]) -> Bool {
        if ["data-clip-id", "data-clipid", "data-clip-slug", "data-clipslug", "clip-id", "clip-slug"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip"])
    }

    private static func twitchClipsHost(for host: String) -> String {
        host.hasSuffix(".test") ? "clips.twitch.test" : "clips.twitch.tv"
    }

    private static func iwaraDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isIwaraHost(host) else {
            return nil
        }
        if let id = iwaraDataAttributeImageID(in: attributes),
           iwaraDataAttributeLooksLikeImageCard(attributes) {
            return "/image/\(id)"
        }
        if let id = iwaraDataAttributeVideoID(in: attributes),
           iwaraDataAttributeLooksLikeVideoCard(attributes) {
            return "/video/\(id)"
        }
        return nil
    }

    private static func iwaraDataAttributeImageID(in attributes: [String: String]) -> String? {
        let keys = ["data-image-id", "data-imageid", "image-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["image", "photo"]) {
            return id
        }
        return nil
    }

    private static func iwaraDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = ["data-video-id", "data-videoid", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video"]) {
            return id
        }
        return nil
    }

    private static func iwaraDataAttributeLooksLikeImageCard(_ attributes: [String: String]) -> Bool {
        if ["data-image-id", "data-imageid", "image-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["image", "photo"])
    }

    private static func iwaraDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-video-id", "data-videoid", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video"])
    }

    private static func instagramDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isInstagramHost(host) else {
            return nil
        }
        if let id = instagramDataAttributeShortcode(in: attributes),
           instagramDataAttributeLooksLikeMediaCard(attributes) {
            return "/\(instagramDataAttributeMediaKind(in: attributes))/\(id)/"
        }
        if let storyID = instagramDataAttributeStoryID(in: attributes),
           let username = instagramDataAttributeUsername(in: attributes),
           instagramDataAttributeLooksLikeStoryCard(attributes) {
            return "/stories/\(username)/\(storyID)/"
        }
        return nil
    }

    private static func instagramDataAttributeShortcode(in attributes: [String: String]) -> String? {
        let keys = [
            "data-shortcode", "data-media-shortcode", "data-post-shortcode",
            "data-reel-shortcode", "data-tv-shortcode", "shortcode"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidInstagramShortcode) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidInstagramShortcode(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "media", "reel", "tv"]) {
            return id
        }
        return nil
    }

    private static func instagramDataAttributeStoryID(in attributes: [String: String]) -> String? {
        let keys = ["data-story-id", "data-storyid", "story-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isInstagramNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isInstagramNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["story"]) {
            return id
        }
        return nil
    }

    private static func instagramDataAttributeUsername(in attributes: [String: String]) -> String? {
        let keys = ["data-username", "data-user-username", "data-owner-username", "username"]
        return firstAttributeValue(in: attributes, keys: keys, matching: isValidInstagramUsername)
    }

    private static func instagramDataAttributeMediaKind(in attributes: [String: String]) -> String {
        let hint = ["data-type", "data-kind", "data-content-type", "class", "role"]
            .compactMap { attributes[$0]?.lowercased() }
            .joined(separator: " ")
        if hint.contains("reel") {
            return "reel"
        }
        if hint.contains("tv") {
            return "tv"
        }
        return "p"
    }

    private static func instagramDataAttributeLooksLikeMediaCard(_ attributes: [String: String]) -> Bool {
        if [
            "data-shortcode", "data-media-shortcode", "data-post-shortcode",
            "data-reel-shortcode", "data-tv-shortcode", "shortcode"
        ].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "media", "reel", "tv"])
    }

    private static func instagramDataAttributeLooksLikeStoryCard(_ attributes: [String: String]) -> Bool {
        if ["data-story-id", "data-storyid", "story-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["story"])
    }

    private static func facebookDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isFacebookHost(host) else {
            return nil
        }
        if let id = facebookDataAttributePhotoID(in: attributes),
           facebookDataAttributeLooksLikePhotoCard(attributes) {
            return "/photo.php?fbid=\(id)"
        }
        if let id = facebookDataAttributeVideoID(in: attributes),
           facebookDataAttributeLooksLikeVideoCard(attributes) {
            if dataAttributeTypeHint(in: attributes, containsAnyOf: ["reel"]) {
                return "/reel/\(id)"
            }
            return "/watch/?v=\(id)"
        }
        return nil
    }

    private static func facebookDataAttributePhotoID(in attributes: [String: String]) -> String? {
        let keys = ["data-photo-id", "data-photoid", "data-fbid", "photo-id", "fbid"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isFacebookPhotoID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isFacebookPhotoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["photo", "image"]) {
            return id
        }
        return nil
    }

    private static func facebookDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = ["data-video-id", "data-videoid", "data-reel-id", "data-reelid", "video-id", "reel-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isFacebookVideoID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isFacebookVideoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "reel"]) {
            return id
        }
        return nil
    }

    private static func facebookDataAttributeLooksLikePhotoCard(_ attributes: [String: String]) -> Bool {
        if ["data-photo-id", "data-photoid", "data-fbid", "photo-id", "fbid"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["photo", "image"])
    }

    private static func facebookDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-video-id", "data-videoid", "data-reel-id", "data-reelid", "video-id", "reel-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "reel"])
    }

    private static func pornhubDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isPornhubHost(host) else {
            return nil
        }
        if let id = pornhubDataAttributeVideoID(in: attributes),
           pornhubDataAttributeLooksLikeVideoCard(attributes) {
            return "/view_video.php?viewkey=\(id)"
        }
        if let id = pornhubDataAttributeGifID(in: attributes),
           pornhubDataAttributeLooksLikeGifCard(attributes) {
            return "/gif/\(id)"
        }
        if let id = pornhubDataAttributePhotoID(in: attributes),
           pornhubDataAttributeLooksLikePhotoCard(attributes) {
            return "/photo/\(id)"
        }
        if let id = pornhubDataAttributeAlbumID(in: attributes),
           pornhubDataAttributeLooksLikeAlbumCard(attributes) {
            return "/album/\(id)"
        }
        return nil
    }

    private static func pornhubDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-viewkey", "data-view-key", "data-video-id",
            "data-videoid", "data-media-id", "data-mediaid",
            "viewkey", "video-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isPornhubMediaID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPornhubMediaID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "viewkey"]) {
            return id
        }
        return nil
    }

    private static func pornhubDataAttributeGifID(in attributes: [String: String]) -> String? {
        let keys = ["data-gif-id", "data-gifid", "gif-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isPornhubMediaID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPornhubMediaID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["gif"]) {
            return id
        }
        return nil
    }

    private static func pornhubDataAttributePhotoID(in attributes: [String: String]) -> String? {
        let keys = ["data-photo-id", "data-photoid", "data-image-id", "photo-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isPornhubMediaID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPornhubMediaID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["photo", "image"]) {
            return id
        }
        return nil
    }

    private static func pornhubDataAttributeAlbumID(in attributes: [String: String]) -> String? {
        let keys = ["data-album-id", "data-albumid", "album-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isPornhubMediaID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPornhubMediaID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"]) {
            return id
        }
        return nil
    }

    private static func pornhubDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-viewkey", "data-view-key", "data-video-id", "data-videoid", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "viewkey"])
    }

    private static func pornhubDataAttributeLooksLikeGifCard(_ attributes: [String: String]) -> Bool {
        if ["data-gif-id", "data-gifid", "gif-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gif"])
    }

    private static func pornhubDataAttributeLooksLikePhotoCard(_ attributes: [String: String]) -> Bool {
        if ["data-photo-id", "data-photoid", "data-image-id", "photo-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["photo", "image"])
    }

    private static func pornhubDataAttributeLooksLikeAlbumCard(_ attributes: [String: String]) -> Bool {
        if ["data-album-id", "data-albumid", "album-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"])
    }

    private static func weiboDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isWeiboHost(host) else {
            return nil
        }
        if let id = weiboDataAttributeTVID(in: attributes),
           weiboDataAttributeLooksLikeTVCard(attributes) {
            return "/tv/show/\(id)"
        }
        if let id = weiboDataAttributeDetailID(in: attributes),
           weiboDataAttributeLooksLikeDetailCard(attributes) {
            return "/detail/\(id)"
        }
        if let id = weiboDataAttributeStatusID(in: attributes),
           weiboDataAttributeLooksLikeStatusCard(attributes) {
            if let profileID = weiboDataAttributeProfileID(in: attributes) {
                return "/\(profileID)/status/\(id)"
            }
            return "/status/\(id)"
        }
        return nil
    }

    private static func weiboDataAttributeStatusID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-status-id", "data-statusid", "data-mid", "data-mblog-id",
            "data-mblogid", "data-weibo-id", "data-post-id", "status-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isWeiboStatusID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isWeiboStatusID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["status", "post", "weibo"]) {
            return id
        }
        return nil
    }

    private static func weiboDataAttributeDetailID(in attributes: [String: String]) -> String? {
        let keys = ["data-detail-id", "data-detailid", "detail-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isWeiboStatusID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isWeiboStatusID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["detail"]) {
            return id
        }
        return nil
    }

    private static func weiboDataAttributeTVID(in attributes: [String: String]) -> String? {
        let keys = ["data-tv-id", "data-tvid", "data-sina-id", "data-sinaid", "tv-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isWeiboStatusID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isWeiboStatusID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["tv", "sina"]) {
            return id
        }
        return nil
    }

    private static func weiboDataAttributeProfileID(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-profile-id", "data-profileid", "data-user-id", "data-userid", "data-uid", "profile-id", "user-id", "uid"],
            matching: isValidPathSlug
        )
    }

    private static func weiboDataAttributeLooksLikeStatusCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-status-id", "data-statusid", "data-mid", "data-mblog-id",
            "data-mblogid", "data-weibo-id", "data-post-id", "status-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["status", "post", "weibo"])
    }

    private static func weiboDataAttributeLooksLikeDetailCard(_ attributes: [String: String]) -> Bool {
        if ["data-detail-id", "data-detailid", "detail-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["detail"])
    }

    private static func weiboDataAttributeLooksLikeTVCard(_ attributes: [String: String]) -> Bool {
        if ["data-tv-id", "data-tvid", "data-sina-id", "data-sinaid", "tv-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["tv", "sina"])
    }

    private static func spankBangDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isSpankBangHost(host),
              let id = spankBangDataAttributeVideoID(in: attributes),
              spankBangDataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        return "/\(id)/video"
    }

    private static func spankBangDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = ["data-video-id", "data-videoid", "data-media-id", "data-mediaid", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSpankBangID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSpankBangID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch"]) {
            return id
        }
        return nil
    }

    private static func spankBangDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-video-id", "data-videoid", "data-media-id", "data-mediaid", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch"])
    }

    private static func xVideoDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isXVideosHost(host) || isXNXXHost(host),
              let id = xVideoDataAttributeVideoID(in: attributes, host: host),
              xVideoDataAttributeLooksLikeVideoCard(attributes) else {
            return nil
        }
        let suffix = xVideoDataAttributeSlug(in: attributes).map { "/\($0)" } ?? ""
        if isXNXXHost(host) {
            return "/video-\(id)\(suffix)"
        }
        return "/video\(id)\(suffix)"
    }

    private static func xVideoDataAttributeVideoID(in attributes: [String: String], host: String) -> String? {
        let predicate: (String) -> Bool = { value in
            if isXNXXHost(host) {
                return isXVideoID(value)
            }
            return value.range(of: #"^[0-9][0-9A-Za-z]*$"#, options: .regularExpression) != nil
        }
        let keys = ["data-video-id", "data-videoid", "data-media-id", "data-mediaid", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: predicate) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           predicate(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch"]) {
            return id
        }
        return nil
    }

    private static func xVideoDataAttributeSlug(in attributes: [String: String]) -> String? {
        firstValidPathSlug(in: attributes, keys: ["data-video-slug", "data-videoslug", "data-title-slug", "data-slug", "video-slug"])
    }

    private static func xVideoDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-video-id", "data-videoid", "data-media-id", "data-mediaid", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch"])
    }

    private static func etcVideoDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              let site = EtcVideoPageResolver.site(for: baseURL),
              isEtcVideoSearchSite(site) else {
            return nil
        }

        switch site {
        case .streamable:
            if let id = etcVideoDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/\(id)"
            }
        case .dailymotion:
            if let id = etcVideoDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return isDaiLySearchHost(host) ? "/\(id)" : "/video/\(id)"
            }
        case .reddit:
            if let id = redditDataAttributeVideoID(in: attributes),
               redditDataAttributeLooksLikeVideoCard(attributes) {
                return "https://v.redd.it/\(id)"
            }
            if let id = redditDataAttributePostID(in: attributes),
               redditDataAttributeLooksLikePostCard(attributes) {
                if let subreddit = redditDataAttributeSubreddit(in: attributes),
                   let slug = redditDataAttributePostSlug(in: attributes) {
                    return "/r/\(subreddit)/comments/\(id)/\(slug)/"
                }
                return "https://redd.it/\(id)"
            }
        case .rumble:
            if let id = rumbleDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/\(id).html"
            }
        case .odysee:
            if let id = odyseeDataAttributeClaimID(in: attributes),
               let channel = odyseeDataAttributeChannel(in: attributes),
               let slug = odyseeDataAttributeSlug(in: attributes),
               odyseeDataAttributeLooksLikeClaimCard(attributes) {
                return "/@\(channel)/\(slug):\(id)"
            }
        case .bitchute:
            if let id = etcVideoDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)/"
            }
        case .rutube:
            if let id = etcVideoDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)"
            }
        case .twitcasting:
            if let id = twitCastingDataAttributeMovieID(in: attributes),
               let username = twitCastingDataAttributeUsername(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/\(username)/movie/\(id)"
            }
        case .kick:
            if let id = kickDataAttributeClipID(in: attributes),
               kickDataAttributeLooksLikeClipCard(attributes) {
                return "/?clip=\(id)"
            }
            if let id = etcVideoDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/?video=\(id)"
            }
        case .vk:
            if let external = vkDataAttributeExternalLinkValue(in: attributes) {
                return external
            }
            if let id = vkDataAttributeVideoPathID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/video\(id)"
            }
        case .okru:
            if let id = etcVideoDataAttributeID(in: attributes),
               etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)"
            }
        case .tver:
            if let id = tverDataAttributeEpisodeID(in: attributes),
               dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "video", "watch"]) || etcVideoDataAttributeLooksLikeVideoCard(attributes) {
                return "/episodes/\(id)"
            }
        default:
            return nil
        }

        return nil
    }

    private static func etcVideoDataAttributeID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "data-content-id", "data-contentid",
            "data-clip-id", "data-clipid", "video-id", "clip-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "clip", "episode"]) {
            return id
        }
        return nil
    }

    private static func redditDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = ["data-vreddit-id", "data-vredditid", "data-video-id", "data-videoid", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "media", "vreddit"]) {
            return id
        }
        return nil
    }

    private static func redditDataAttributePostID(in attributes: [String: String]) -> String? {
        let keys = ["data-post-id", "data-postid", "data-thing-id", "data-fullname", "post-id"]
        for key in keys {
            guard let raw = attributes[key]?.trimmed else { continue }
            let value = raw.hasPrefix("t3_") ? String(raw.dropFirst(3)) : raw
            if isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "comments", "reddit"]) {
            return id
        }
        return nil
    }

    private static func redditDataAttributeSubreddit(in attributes: [String: String]) -> String? {
        firstAttributeValue(in: attributes, keys: ["data-subreddit", "data-subreddit-name", "subreddit"], matching: isValidPathSlug)
    }

    private static func redditDataAttributePostSlug(in attributes: [String: String]) -> String? {
        firstAttributeValue(in: attributes, keys: ["data-post-slug", "data-postslug", "data-title-slug", "data-slug"], matching: isValidPathSlug)
    }

    private static func redditDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        if ["data-post-id", "data-postid", "data-thing-id", "data-fullname", "post-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "comments", "reddit"])
    }

    private static func redditDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        if ["data-vreddit-id", "data-vredditid", "data-video-id", "data-videoid", "video-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "media", "vreddit"])
    }

    private static func rumbleDataAttributeID(in attributes: [String: String]) -> String? {
        let keys = ["data-rumble-id", "data-rumbleid", "data-video-id", "data-videoid", "video-id"]
        let predicate: (String) -> Bool = { value in
            value.range(of: #"^v[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil
        }
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: predicate) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           predicate(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "rumble"]) {
            return id
        }
        return nil
    }

    private static func odyseeDataAttributeClaimID(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-claim-id", "data-claimid", "data-video-id", "data-videoid", "claim-id"],
            matching: isValidPathSlug
        )
    }

    private static func odyseeDataAttributeChannel(in attributes: [String: String]) -> String? {
        let keys = ["data-channel", "data-channel-name", "data-channel-slug", "data-creator", "data-uploader", "channel"]
        for key in keys {
            guard let raw = attributes[key]?.trimmed else { continue }
            let value = raw.hasPrefix("@") ? String(raw.dropFirst()) : raw
            if isValidPathSlug(value) {
                return value
            }
        }
        return nil
    }

    private static func odyseeDataAttributeSlug(in attributes: [String: String]) -> String? {
        firstAttributeValue(in: attributes, keys: ["data-claim-slug", "data-claimslug", "data-video-slug", "data-title-slug", "data-slug"], matching: isValidPathSlug)
    }

    private static func odyseeDataAttributeLooksLikeClaimCard(_ attributes: [String: String]) -> Bool {
        if ["data-claim-id", "data-claimid", "claim-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["claim", "video", "watch"])
    }

    private static func twitCastingDataAttributeMovieID(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-movie-id", "data-movieid", "data-video-id", "data-videoid", "movie-id"],
            matching: isValidPathSlug
        )
    }

    private static func twitCastingDataAttributeUsername(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-user", "data-user-name", "data-username", "data-caster", "data-screen-id", "username"],
            matching: isValidPathSlug
        )
    }

    private static func kickDataAttributeClipID(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-clip-id", "data-clipid", "data-clip-slug", "data-clipslug", "clip-id"],
            matching: isValidPathSlug
        )
    }

    private static func kickDataAttributeLooksLikeClipCard(_ attributes: [String: String]) -> Bool {
        if ["data-clip-id", "data-clipid", "data-clip-slug", "data-clipslug", "clip-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip"])
    }

    private static func vkDataAttributeExternalLinkValue(in attributes: [String: String]) -> String? {
        guard let oid = firstAttributeValue(in: attributes, keys: ["data-oid", "data-owner-id", "data-ownerid", "oid"], matching: isVKOwnerID),
              let id = firstAttributeValue(in: attributes, keys: ["data-vk-id", "data-video-id", "data-videoid", "data-id", "vk-id"], matching: isVKNumericID),
              dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "vk", "embed", "external"]) else {
            return nil
        }
        return "/video_ext.php?oid=\(oid)&id=\(id)"
    }

    private static func vkDataAttributeVideoPathID(in attributes: [String: String]) -> String? {
        let keys = ["data-vk-video-id", "data-vkvideoid", "data-video-id", "data-videoid", "video-id"]
        let predicate: (String) -> Bool = { value in
            value.range(of: #"^-?[0-9]+_[0-9]+$"#, options: .regularExpression) != nil
        }
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: predicate) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           predicate(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "vk"]) {
            return id
        }
        return nil
    }

    private static func tverDataAttributeEpisodeID(in attributes: [String: String]) -> String? {
        if let value = firstAttributeValue(
            in: attributes,
            keys: ["data-episode-id", "data-episodeid", "data-video-id", "data-videoid", "episode-id"],
            matching: isValidPathSlug
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "video", "tver"]) {
            return id
        }
        return nil
    }

    private static func etcVideoDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-video-id", "data-videoid", "data-media-id", "data-mediaid",
            "data-content-id", "data-contentid", "data-clip-id", "data-clipid",
            "data-episode-id", "data-episodeid", "data-movie-id", "data-movieid",
            "video-id", "clip-id", "episode-id", "movie-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "clip", "episode", "movie"])
    }

    private static func isDaiLySearchHost(_ host: String) -> Bool {
        host == "dai.ly" || host == "www.dai.ly" || host == "dai.test" || host == "www.dai.test"
    }

    private static func isVKOwnerID(_ value: String) -> Bool {
        value.range(of: #"^-?[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isVKNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func originalYTDLPMediaDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isOriginalYTDLPMediaSearchHost(host) else {
            return nil
        }

        if isAvgleHost(host),
           let id = originalMediaDataAttributeVideoID(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/video/\(id)"
        }

        if isHanimeHost(host),
           let slug = originalMediaDataAttributeSlug(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/videos/hentai/\(slug)"
        }

        if isKissJAVHost(host),
           let slug = originalMediaDataAttributeSlug(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/videos/\(slug)"
        }

        if isTokyoMotionHost(host) {
            if let albumID = originalMediaDataAttributeAlbumID(in: attributes),
               originalMediaDataAttributeLooksLikeAlbumCard(attributes) {
                return "/album/\(albumID)"
            }
            if let id = originalMediaDataAttributeVideoID(in: attributes),
               originalMediaDataAttributeLooksLikeVideoCard(attributes) {
                return "/video/\(id)"
            }
        }

        if isThisVidHost(host),
           let slug = originalMediaDataAttributeSlug(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/videos/\(slug)"
        }

        if isIxiguaHost(host),
           let id = originalMediaDataAttributeIxiguaID(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/\(id)"
        }

        if isYourPornHost(host),
           let slug = originalMediaDataAttributeSlug(in: attributes),
           originalMediaDataAttributeLooksLikePostCard(attributes) {
            return "/post/\(slug)"
        }

        if isXHamsterHost(host) {
            if let galleryID = originalMediaDataAttributeGalleryID(in: attributes),
               originalMediaDataAttributeLooksLikeGalleryCard(attributes) {
                return "/photos/gallery/\(galleryID)"
            }
            if let slug = originalMediaDataAttributeSlug(in: attributes),
               originalMediaDataAttributeLooksLikeVideoCard(attributes) {
                return "/videos/\(slug)"
            }
        }

        if isYouPornHost(host),
           let id = originalMediaDataAttributeVideoID(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/watch/\(id)"
        }

        if isYoukuHost(host),
           let id = originalMediaDataAttributeYoukuID(in: attributes),
           originalMediaDataAttributeLooksLikeVideoCard(attributes) {
            return "/v_show/id_\(id).html"
        }

        return nil
    }

    private static func originalMediaDataAttributeVideoID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-video-id", "data-videoid", "data-media-id",
            "data-mediaid", "data-content-id", "data-contentid", "video-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "movie"]) {
            return id
        }
        return nil
    }

    private static func originalMediaDataAttributeSlug(in attributes: [String: String]) -> String? {
        let keys = [
            "data-video-slug", "data-videoslug", "data-content-slug",
            "data-contentslug", "data-post-slug", "data-postslug",
            "data-title-slug", "data-slug", "slug"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "hentai", "movie", "post"]) {
            return id
        }
        return nil
    }

    private static func originalMediaDataAttributeAlbumID(in attributes: [String: String]) -> String? {
        let keys = ["data-album-id", "data-albumid", "data-gallery-id", "data-galleryid", "album-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"]) {
            return id
        }
        return nil
    }

    private static func originalMediaDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        originalMediaDataAttributeAlbumID(in: attributes)
    }

    private static func originalMediaDataAttributeIxiguaID(in attributes: [String: String]) -> String? {
        let keys = ["data-video-id", "data-videoid", "data-group-id", "data-groupid", "data-item-id", "data-itemid", "video-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isIxiguaVideoID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isIxiguaVideoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch"]) {
            return id
        }
        return nil
    }

    private static func originalMediaDataAttributeYoukuID(in attributes: [String: String]) -> String? {
        let keys = ["data-video-id", "data-videoid", "data-show-id", "data-showid", "video-id"]
        let predicate: (String) -> Bool = { value in
            originalMediaNormalizedYoukuID(value) != nil
        }
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: predicate),
           let id = originalMediaNormalizedYoukuID(value) {
            return id
        }
        if let raw = attributes["data-id"]?.trimmed,
           let id = originalMediaNormalizedYoukuID(raw),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "youku"]) {
            return id
        }
        return nil
    }

    private static func originalMediaNormalizedYoukuID(_ value: String) -> String? {
        var id = value.trimmed
        if id.lowercased().hasPrefix("id_") {
            id = String(id.dropFirst(3))
        }
        id = id.replacingOccurrences(of: ".html", with: "", options: [.caseInsensitive])
        guard id.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    private static func originalMediaDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-video-id", "data-videoid", "data-video-slug", "data-videoslug",
            "data-content-id", "data-contentid", "data-content-slug", "data-contentslug",
            "data-media-id", "data-mediaid", "data-group-id", "data-groupid",
            "data-item-id", "data-itemid", "data-show-id", "data-showid", "video-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "watch", "hentai", "movie"])
    }

    private static func originalMediaDataAttributeLooksLikeAlbumCard(_ attributes: [String: String]) -> Bool {
        if ["data-album-id", "data-albumid", "album-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["album"])
    }

    private static func originalMediaDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        if ["data-gallery-id", "data-galleryid", "data-album-id", "data-albumid", "gallery-id", "album-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "album"])
    }

    private static func originalMediaDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        if ["data-post-id", "data-postid", "data-post-slug", "data-postslug"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "video", "watch"])
    }

    private static func imagePostDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased() else {
            return nil
        }

        if isImgurHost(host) {
            if let tag = imgurDataAttributeTag(in: attributes),
               let id = imgurDataAttributeImageID(in: attributes),
               imgurDataAttributeLooksLikeTagCard(attributes) {
                return "/t/\(tag)/\(id)"
            }
            if let id = imgurDataAttributeAlbumID(in: attributes),
               imgurDataAttributeLooksLikeAlbumCard(attributes) {
                return "/a/\(id)"
            }
            if let id = imgurDataAttributeGalleryID(in: attributes),
               imgurDataAttributeLooksLikeGalleryCard(attributes) {
                return "/gallery/\(id)"
            }
            if let id = imgurDataAttributeImageID(in: attributes),
               imgurDataAttributeLooksLikeImageCard(attributes) {
                return "/\(id)"
            }
        }

        if isTumblrHost(host),
           let blog = tumblrDataAttributeBlogName(in: attributes),
           tumblrDataAttributeLooksLikeBlogOrPostCard(attributes) {
            if let postID = tumblrDataAttributePostID(in: attributes) {
                return "/\(blog)/\(postID)/post"
            }
            return "/\(blog)"
        }

        if isFourChanHost(host),
           let board = fourChanDataAttributeBoard(in: attributes) ?? fourChanBoardFromBaseURL(baseURL),
           let threadID = fourChanDataAttributeThreadID(in: attributes),
           fourChanDataAttributeLooksLikeThreadCard(attributes) {
            return "/\(board)/thread/\(threadID)"
        }

        if isWikiArtHost(host),
           let artist = wikiArtDataAttributeArtistSlug(in: attributes),
           wikiArtDataAttributeLooksLikeArtistCard(attributes) {
            return "/en/\(artist)"
        }

        return nil
    }

    private static func imgurDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        let keys = ["data-gallery-id", "data-galleryid", "data-gallery-hash", "gallery-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidImgurID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidImgurID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery"]) {
            return id
        }
        return nil
    }

    private static func imgurDataAttributeAlbumID(in attributes: [String: String]) -> String? {
        let keys = ["data-album-id", "data-albumid", "data-album-hash", "album-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidImgurID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidImgurID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["album"]) {
            return id
        }
        return nil
    }

    private static func imgurDataAttributeImageID(in attributes: [String: String]) -> String? {
        let keys = ["data-image-id", "data-imageid", "data-media-id", "data-mediaid", "data-hash", "image-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidImgurID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidImgurID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["image", "media", "photo", "post"]) {
            return id
        }
        return nil
    }

    private static func imgurDataAttributeTag(in attributes: [String: String]) -> String? {
        firstAttributeValue(in: attributes, keys: ["data-tag", "data-tag-name", "tag"], matching: isValidImgurID)
    }

    private static func imgurDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        if ["data-gallery-id", "data-galleryid", "data-gallery-hash", "gallery-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery"])
    }

    private static func imgurDataAttributeLooksLikeAlbumCard(_ attributes: [String: String]) -> Bool {
        if ["data-album-id", "data-albumid", "data-album-hash", "album-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["album"])
    }

    private static func imgurDataAttributeLooksLikeImageCard(_ attributes: [String: String]) -> Bool {
        if ["data-image-id", "data-imageid", "data-media-id", "data-mediaid", "data-hash", "image-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["image", "media", "photo", "post"])
    }

    private static func imgurDataAttributeLooksLikeTagCard(_ attributes: [String: String]) -> Bool {
        if ["data-tag", "data-tag-name", "tag"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["tag"])
    }

    private static func tumblrDataAttributeBlogName(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-blog-name", "data-blog", "data-tumblelog", "data-username", "data-user", "blog"],
            matching: isValidTumblrBlogName
        )
    }

    private static func tumblrDataAttributePostID(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-post-id", "data-postid", "data-id", "post-id"],
            matching: isTumblrPostID
        )
    }

    private static func tumblrDataAttributeLooksLikeBlogOrPostCard(_ attributes: [String: String]) -> Bool {
        if ["data-blog-name", "data-blog", "data-tumblelog", "data-post-id", "data-postid", "post-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["tumblr", "blog", "post"])
    }

    private static func fourChanDataAttributeBoard(in attributes: [String: String]) -> String? {
        firstAttributeValue(in: attributes, keys: ["data-board", "data-board-id", "data-boardid", "board"], matching: isFourChanBoardID)
    }

    private static func fourChanBoardFromBaseURL(_ baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isFourChanHost(host) else {
            return nil
        }
        let parts = baseURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first, isFourChanBoardID(first) else {
            return nil
        }
        return first
    }

    private static func fourChanDataAttributeThreadID(in attributes: [String: String]) -> String? {
        let keys = ["data-thread-id", "data-threadid", "data-no", "data-post-id", "thread-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isFourChanThreadID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isFourChanThreadID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["thread", "op"]) {
            return id
        }
        return nil
    }

    private static func fourChanDataAttributeLooksLikeThreadCard(_ attributes: [String: String]) -> Bool {
        if ["data-thread-id", "data-threadid", "data-no", "thread-id"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["thread", "op"])
    }

    private static func wikiArtDataAttributeArtistSlug(in attributes: [String: String]) -> String? {
        let keys = ["data-artist-slug", "data-artistslug", "data-artist-id", "data-artistid", "data-slug", "artist-slug"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["artist"]) {
            return id
        }
        return nil
    }

    private static func wikiArtDataAttributeLooksLikeArtistCard(_ attributes: [String: String]) -> Bool {
        if ["data-artist-slug", "data-artistslug", "data-artist-id", "data-artistid", "artist-slug"].contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["artist"])
    }

    private static func fediverseDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let service = FediverseResolver.service(for: baseURL) else {
            return nil
        }

        switch service {
        case .mastodon:
            if let id = mastodonDataAttributeStatusID(in: attributes),
               mastodonDataAttributeLooksLikeStatusCard(attributes) {
                return "/web/statuses/\(id)"
            }
            if let id = mastodonDataAttributeAccountID(in: attributes),
               mastodonDataAttributeLooksLikeAccountCard(attributes) {
                return "/web/accounts/\(id)"
            }
            if let username = fediverseDataAttributeUsername(in: attributes),
               fediverseDataAttributeLooksLikeProfileCard(attributes) {
                return "/@\(username)"
            }

        case .misskey:
            if let id = misskeyDataAttributeNoteID(in: attributes),
               misskeyDataAttributeLooksLikeNoteCard(attributes) {
                return "/notes/\(id)"
            }
            if let username = fediverseDataAttributeUsername(in: attributes),
               fediverseDataAttributeLooksLikeProfileCard(attributes) {
                return "/@\(username)"
            }
        }

        return nil
    }

    private static func mastodonDataAttributeStatusID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-status-id", "data-statusid", "data-toot-id", "data-tootid",
            "status-id", "toot-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isFediverseNumericID) {
            return value
        }

        let typedKeys = ["data-post-id", "data-postid", "post-id", "data-id"]
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["status", "post", "toot"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: typedKeys, matching: isFediverseNumericID)
    }

    private static func mastodonDataAttributeAccountID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-account-id", "data-accountid", "data-profile-id",
            "data-profileid", "account-id", "profile-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isFediverseNumericID) {
            return value
        }

        let typedKeys = ["data-user-id", "data-userid", "user-id", "data-id"]
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["account", "profile", "user"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: typedKeys, matching: isFediverseNumericID)
    }

    private static func misskeyDataAttributeNoteID(in attributes: [String: String]) -> String? {
        let explicitKeys = ["data-note-id", "data-noteid", "note-id"]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isMisskeyNoteID) {
            return value
        }

        let typedKeys = ["data-post-id", "data-postid", "post-id", "data-id"]
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["note", "post"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: typedKeys, matching: isMisskeyNoteID)
    }

    private static func fediverseDataAttributeUsername(in attributes: [String: String]) -> String? {
        let keys = [
            "data-acct", "data-account", "data-profile", "data-username",
            "data-user-name", "data-user", "username", "user", "acct"
        ]
        for key in keys {
            guard let value = attributes[key]?.trimmed,
                  let username = fediverseUsername(value),
                  isFediverseProfileUsername(username) else {
                continue
            }
            return username
        }
        return nil
    }

    private static func mastodonDataAttributeLooksLikeStatusCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-status-id", "data-statusid", "data-toot-id", "data-tootid",
            "status-id", "toot-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["status", "post", "toot"])
    }

    private static func mastodonDataAttributeLooksLikeAccountCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-account-id", "data-accountid", "data-profile-id",
            "data-profileid", "account-id", "profile-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["account", "profile", "user"])
    }

    private static func misskeyDataAttributeLooksLikeNoteCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-note-id", "data-noteid", "note-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["note", "post"])
    }

    private static func fediverseDataAttributeLooksLikeProfileCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-acct", "data-account", "data-profile", "data-username",
            "data-user-name", "data-user", "username", "user", "acct"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["account", "profile", "user"])
    }

    private static func isFediverseNumericID(_ value: String) -> Bool {
        !value.isEmpty && value.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func isMisskeyNoteID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z_-]{3,128}$"#, options: .regularExpression) != nil
    }

    private static func isFediverseProfileUsername(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z_.@-]{1,120}$"#, options: .regularExpression) != nil
    }

    private static func communityImageDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased() else {
            return nil
        }

        if isSankakuHost(host),
           let id = sankakuDataAttributePostID(in: attributes),
           sankakuDataAttributeLooksLikePostCard(attributes) {
            return SankakuResolver.postURL(id: id, sourceURL: baseURL).absoluteString
        }

        if isNijieHost(host) {
            if let id = nijieDataAttributeIllustrationID(in: attributes),
               nijieDataAttributeLooksLikeIllustrationCard(attributes) {
                return NijieResolver.viewURL(illustrationID: id, sourceURL: baseURL).absoluteString
            }
            if let id = nijieDataAttributeMemberID(in: attributes),
               nijieDataAttributeLooksLikeMemberCard(attributes) {
                return NijieResolver.memberIllustURL(memberID: id, page: 1, sourceURL: baseURL).absoluteString
            }
        }

        if isV2PHHost(host),
           let id = v2phDataAttributeAlbumID(in: attributes),
           v2phDataAttributeLooksLikeAlbumCard(attributes) {
            return "/album/\(id)"
        }

        if isHentaiCosplayHost(host),
           let content = hentaiCosplayDataAttributeContent(in: attributes),
           hentaiCosplayDataAttributeLooksLikeContentCard(attributes, kind: content.kind) {
            return "/\(content.kind)/\(content.slug)/"
        }

        if isHentaiFoundryHost(host) {
            if let picture = hentaiFoundryDataAttributePicture(in: attributes),
               hentaiFoundryDataAttributeLooksLikePictureCard(attributes) {
                return "/pictures/user/\(picture.username)/\(picture.id)"
            }
            if let username = hentaiFoundryDataAttributeGalleryUsername(in: attributes),
               hentaiFoundryDataAttributeLooksLikeGalleryCard(attributes) {
                return "/pictures/user/\(username)"
            }
        }

        if isTalkOPGGHost(host),
           let article = talkOPGGDataAttributeArticle(in: attributes, baseURL: baseURL),
           talkOPGGDataAttributeLooksLikeArticleCard(attributes) {
            let slugSuffix = article.slug.map { "/\($0)" } ?? ""
            return "/s/\(article.game)/\(article.section)/\(article.id)\(slugSuffix)"
        }

        return nil
    }

    private static func sankakuDataAttributePostID(in attributes: [String: String]) -> String? {
        let explicitKeys = ["data-post-id", "data-postid", "data-sankaku-id", "data-sankakuid", "post-id"]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "image", "media"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isPositiveNumericID)
    }

    private static func nijieDataAttributeIllustrationID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-illust-id", "data-illustid", "data-illustration-id",
            "data-illustrationid", "data-post-id", "data-postid", "illust-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["illust", "illustration", "post", "work"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isPositiveNumericID)
    }

    private static func nijieDataAttributeMemberID(in attributes: [String: String]) -> String? {
        let explicitKeys = ["data-member-id", "data-memberid", "data-user-id", "data-userid", "member-id"]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["member", "artist", "user", "profile"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isPositiveNumericID)
    }

    private static func v2phDataAttributeAlbumID(in attributes: [String: String]) -> String? {
        let explicitKeys = ["data-album-id", "data-albumid", "data-gallery-id", "data-galleryid", "album-id"]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isValidPathSlug) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isValidPathSlug)
    }

    private static func hentaiCosplayDataAttributeContent(in attributes: [String: String]) -> (kind: String, slug: String)? {
        for kind in ["story", "image", "video"] {
            let keys = [
                "data-\(kind)-slug", "data-\(kind)-id", "\(kind)-slug", "\(kind)-id"
            ]
            if let slug = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) {
                return (kind, slug)
            }
        }

        guard let kind = hentaiCosplayDataAttributeKind(in: attributes) else {
            return nil
        }
        let keys = ["data-content-id", "data-contentid", "data-slug", "data-id", "content-id", "slug"]
        guard let slug = firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug) else {
            return nil
        }
        return (kind, slug)
    }

    private static func hentaiCosplayDataAttributeKind(in attributes: [String: String]) -> String? {
        let values = ["data-type", "data-kind", "data-content-type", "class", "role"]
            .compactMap { attributes[$0]?.lowercased() }
        for kind in ["story", "image", "video"] {
            if values.contains(where: { $0.contains(kind) }) {
                return kind
            }
        }
        return nil
    }

    private static func hentaiFoundryDataAttributePicture(in attributes: [String: String]) -> (username: String, id: String)? {
        let idKeys = [
            "data-picture-id", "data-pictureid", "data-post-id",
            "data-postid", "data-art-id", "data-artid", "picture-id"
        ]
        let typedKeys = ["data-id", "id"]
        let id = firstAttributeValue(in: attributes, keys: idKeys, matching: isPositiveNumericID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["picture", "post", "art"])
                ? firstAttributeValue(in: attributes, keys: typedKeys, matching: isPositiveNumericID)
                : nil)
        guard let id,
              let username = hentaiFoundryDataAttributeUsername(in: attributes) else {
            return nil
        }
        return (username, id)
    }

    private static func hentaiFoundryDataAttributeGalleryUsername(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-gallery-user", "data-gallery-username", "data-artist",
            "data-username", "data-user", "username", "user", "artist"
        ]
        if let username = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isValidPathSlug) {
            return username
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "artist", "user", "profile"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isValidPathSlug)
    }

    private static func hentaiFoundryDataAttributeUsername(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: ["data-artist", "data-username", "data-user", "username", "user", "artist"],
            matching: isValidPathSlug
        )
    }

    private static func talkOPGGDataAttributeArticle(in attributes: [String: String], baseURL: URL) -> (game: String, section: String, id: String, slug: String?)? {
        let idKeys = ["data-article-id", "data-articleid", "data-post-id", "data-postid", "article-id"]
        let id = firstAttributeValue(in: attributes, keys: idKeys, matching: isTalkOPGGArticleID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["article", "post"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isTalkOPGGArticleID)
                : nil)
        guard let id else { return nil }

        let game = firstAttributeValue(
            in: attributes,
            keys: ["data-game", "data-game-id", "game", "game-id"],
            matching: isValidPathSlug
        ) ?? talkOPGGPathPart(baseURL, offset: 1)
        let section = firstAttributeValue(
            in: attributes,
            keys: ["data-section", "data-board", "data-category", "section", "board"],
            matching: isValidPathSlug
        ) ?? talkOPGGPathPart(baseURL, offset: 2)

        guard let game,
              let section,
              !["all", "search"].contains(section.lowercased()) else {
            return nil
        }

        let slug = firstAttributeValue(
            in: attributes,
            keys: ["data-slug", "data-title-slug", "slug"],
            matching: isValidPathSlug
        )
        return (game, section, id, slug)
    }

    private static func talkOPGGPathPart(_ url: URL, offset: Int) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.first?.lowercased() == "s",
              offset < parts.count,
              isValidPathSlug(parts[offset]) else {
            return nil
        }
        return parts[offset]
    }

    private static func sankakuDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-post-id", "data-postid", "data-sankaku-id", "data-sankakuid", "post-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "image", "media"])
    }

    private static func nijieDataAttributeLooksLikeIllustrationCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-illust-id", "data-illustid", "data-illustration-id",
            "data-illustrationid", "data-post-id", "data-postid", "illust-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["illust", "illustration", "post", "work"])
    }

    private static func nijieDataAttributeLooksLikeMemberCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-member-id", "data-memberid", "data-user-id", "data-userid", "member-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["member", "artist", "user", "profile"])
    }

    private static func v2phDataAttributeLooksLikeAlbumCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-album-id", "data-albumid", "data-gallery-id", "data-galleryid", "album-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"])
    }

    private static func hentaiCosplayDataAttributeLooksLikeContentCard(_ attributes: [String: String], kind: String) -> Bool {
        let markerKeys = [
            "data-\(kind)-slug", "data-\(kind)-id",
            "data-content-id", "data-contentid", "data-slug", "content-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: [kind, "content", "post"])
    }

    private static func hentaiFoundryDataAttributeLooksLikePictureCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-picture-id", "data-pictureid", "data-post-id",
            "data-postid", "data-art-id", "data-artid", "picture-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["picture", "post", "art"])
    }

    private static func hentaiFoundryDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-gallery-user", "data-gallery-username"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "artist", "user", "profile"])
    }

    private static func talkOPGGDataAttributeLooksLikeArticleCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-article-id", "data-articleid", "data-post-id", "data-postid", "article-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["article", "post"])
    }

    private static func isPositiveNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isTalkOPGGArticleID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{3,}$"#, options: .regularExpression) != nil
    }

    private static func galleryBlogDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased() else {
            return nil
        }

        if isAsmHentaiHost(host),
           let id = asmHentaiDataAttributeGalleryID(in: attributes),
           asmHentaiDataAttributeLooksLikeGalleryCard(attributes) {
            return "/gallery/\(id)"
        }

        if isMyReadingMangaHost(host),
           let path = myReadingMangaDataAttributePostPath(in: attributes),
           myReadingMangaDataAttributeLooksLikePostCard(attributes) {
            return path
        }

        if isLusciousHost(host) {
            if let album = lusciousDataAttributeAlbumToken(in: attributes),
               lusciousDataAttributeLooksLikeAlbumCard(attributes) {
                return "/albums/\(album)"
            }
            if let video = lusciousDataAttributeVideoSlug(in: attributes),
               lusciousDataAttributeLooksLikeVideoCard(attributes) {
                return "/videos/\(video)"
            }
        }

        if isBDSMlrHost(host) {
            if let post = bdsmlrDataAttributePost(in: attributes, baseURL: baseURL),
               bdsmlrDataAttributeLooksLikePostCard(attributes) {
                return bdsmlrPostURL(blog: post.blog, postID: post.postID, sourceURL: baseURL)?.absoluteString
            }
            if let blog = bdsmlrDataAttributeBlogName(in: attributes),
               bdsmlrDataAttributeLooksLikeBlogCard(attributes) {
                return BDSMlrResolver.canonicalBlogURL(blogName: blog, sourceURL: baseURL).absoluteString
            }
        }

        return nil
    }

    private static func asmHentaiDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-gallery-id", "data-galleryid", "data-gid",
            "data-asmhentai-id", "gallery-id", "gid"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "asmhentai"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isPositiveNumericID)
    }

    private static func myReadingMangaDataAttributePostPath(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-post-slug", "data-postslug", "data-post-id",
            "data-postid", "data-entry-slug", "post-slug"
        ]
        if let slug = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isMyReadingMangaPostSlug) {
            return "/\(slug)/"
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "article", "entry", "work"]) else {
            return nil
        }
        if let slug = firstAttributeValue(in: attributes, keys: ["data-slug", "data-id", "slug", "id"], matching: isMyReadingMangaPostSlug) {
            return "/\(slug)/"
        }
        return nil
    }

    private static func lusciousDataAttributeAlbumToken(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-album-id", "data-albumid", "data-album-slug",
            "data-gallery-id", "data-galleryid", "album-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isLusciousAlbumToken) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isLusciousAlbumToken)
    }

    private static func lusciousDataAttributeVideoSlug(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-video-slug", "data-video-id", "data-videoid",
            "data-movie-id", "data-movieid", "video-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isValidPathSlug) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "movie"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isValidPathSlug)
    }

    private static func bdsmlrDataAttributePost(in attributes: [String: String], baseURL: URL) -> (blog: String, postID: String)? {
        let postIDKeys = ["data-post-id", "data-postid", "post-id", "data-id"]
        let postID = firstAttributeValue(in: attributes, keys: postIDKeys, matching: isPositiveNumericID)
        guard let postID,
              let blog = bdsmlrDataAttributeBlogName(in: attributes) ?? BDSMlrResolver.blogName(from: baseURL) else {
            return nil
        }
        return (blog, postID)
    }

    private static func bdsmlrDataAttributeBlogName(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-blog", "data-blog-id", "data-blog-name",
                "data-username", "data-user", "blog", "username", "user"
            ],
            matching: isValidPathSlug
        )
    }

    private static func bdsmlrPostURL(blog: String, postID: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = "\(blog).\(sourceURL.host?.lowercased().hasSuffix(".test") == true ? "bdsmlr.test" : "bdsmlr.com")"
        components.path = "/post/\(postID)"
        return components.url
    }

    private static func asmHentaiDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-gallery-id", "data-galleryid", "data-gid",
            "data-asmhentai-id", "gallery-id", "gid"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "asmhentai"])
    }

    private static func myReadingMangaDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-post-slug", "data-postslug", "data-post-id",
            "data-postid", "data-entry-slug", "post-slug"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "article", "entry", "work"])
    }

    private static func lusciousDataAttributeLooksLikeAlbumCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-album-id", "data-albumid", "data-album-slug",
            "data-gallery-id", "data-galleryid", "album-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["album", "gallery"])
    }

    private static func lusciousDataAttributeLooksLikeVideoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-video-slug", "data-video-id", "data-videoid",
            "data-movie-id", "data-movieid", "video-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "movie"])
    }

    private static func bdsmlrDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-post-id", "data-postid", "post-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post"])
    }

    private static func bdsmlrDataAttributeLooksLikeBlogCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-blog", "data-blog-id", "data-blog-name"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["blog", "profile", "user"])
    }

    private static func isMyReadingMangaPostSlug(_ value: String) -> Bool {
        let reserved: Set<String> = [
            "author", "category", "comments", "feed", "page", "tag",
            "search", "wp-admin", "wp-content", "wp-includes", "wp-json"
        ]
        return isValidPathSlug(value) && !reserved.contains(value.lowercased())
    }

    private static func isLusciousAlbumToken(_ value: String) -> Bool {
        isValidPathSlug(value) &&
            value.range(of: #"[0-9]{2,}$"#, options: .regularExpression) != nil
    }

    private static func textFictionDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
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
           let entry = kakuyomuDataAttributeEntry(in: attributes, baseURL: baseURL),
           kakuyomuDataAttributeLooksLikeWorkCard(attributes) {
            if let episodeID = entry.episodeID {
                return "/works/\(entry.workID)/episodes/\(episodeID)"
            }
            return "/works/\(entry.workID)"
        }

        if isHamelnHost(host),
           let entry = hamelnDataAttributeEntry(in: attributes, baseURL: baseURL),
           hamelnDataAttributeLooksLikeNovelCard(attributes) {
            if let page = entry.page {
                return "/novel/\(entry.novelID)/\(page)/"
            }
            return "/novel/\(entry.novelID)/"
        }

        if isComicWalkerHost(host) {
            if let episodeID = comicWalkerDataAttributeEpisodeID(in: attributes),
               comicWalkerDataAttributeLooksLikeEpisodeCard(attributes) {
                return "/episodes/\(episodeID)"
            }
            if let workID = comicWalkerDataAttributeWorkID(in: attributes),
               comicWalkerDataAttributeLooksLikeWorkCard(attributes) {
                return "/contents/detail/\(workID)"
            }
        }

        return nil
    }

    private static func narouDataAttributeEntry(in attributes: [String: String]) -> (ncode: String, chapter: Int?)? {
        let ncodeKeys = [
            "data-ncode", "data-novel-code", "data-novelcode",
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid", "ncode"
        ]
        let ncode = firstAttributeValue(in: attributes, keys: ncodeKeys, matching: isNarouNcode) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["narou", "syosetu", "ncode", "novel", "work", "chapter", "episode"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNarouNcode)
                : nil)
        guard let ncode else { return nil }

        let chapterKeys = [
            "data-chapter", "data-chapter-id", "data-chapterid",
            "data-episode", "data-episode-id", "data-episodeid",
            "data-page", "data-page-id", "chapter-id", "episode-id"
        ]
        let rawChapter = firstAttributeValue(in: attributes, keys: chapterKeys, matching: isTextFictionPositiveNumber) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["chapter", "episode"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isTextFictionPositiveNumber)
                : nil)
        return (ncode, rawChapter.flatMap(Int.init))
    }

    private static func kakuyomuDataAttributeEntry(in attributes: [String: String], baseURL: URL) -> (workID: String, episodeID: String?)? {
        let workKeys = [
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid", "data-series-id", "work-id"
        ]
        let workID = firstAttributeValue(in: attributes, keys: workKeys, matching: isKakuyomuID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["kakuyomu", "work", "novel", "series"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isKakuyomuID)
                : nil) ??
            KakuyomuResolver.workID(from: baseURL)
        guard let workID else { return nil }

        let episodeKeys = [
            "data-episode-id", "data-episodeid", "data-episode",
            "data-chapter-id", "data-chapterid", "episode-id"
        ]
        let episodeID = firstAttributeValue(in: attributes, keys: episodeKeys, matching: isKakuyomuID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "chapter"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isKakuyomuID)
                : nil)
        return (workID, episodeID)
    }

    private static func hamelnDataAttributeEntry(in attributes: [String: String], baseURL: URL) -> (novelID: String, page: Int?)? {
        let novelKeys = [
            "data-novel-id", "data-novelid", "data-work-id",
            "data-workid", "data-story-id", "novel-id", "work-id"
        ]
        let novelID = firstAttributeValue(in: attributes, keys: novelKeys, matching: isTextFictionPositiveNumber) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["hameln", "novel", "work", "story"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isTextFictionPositiveNumber)
                : nil) ??
            HamelnResolver.novelID(from: baseURL)
        guard let novelID else { return nil }

        let pageKeys = [
            "data-page", "data-page-id", "data-pageid",
            "data-chapter", "data-chapter-id", "data-chapterid",
            "data-episode", "data-episode-id", "data-episodeid",
            "page-id", "chapter-id", "episode-id"
        ]
        let rawPage = firstAttributeValue(in: attributes, keys: pageKeys, matching: isTextFictionPositiveNumber) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["page", "chapter", "episode"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isTextFictionPositiveNumber)
                : nil)
        return (novelID, rawPage.flatMap(Int.init))
    }

    private static func comicWalkerDataAttributeEpisodeID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-episode-id", "data-episodeid", "data-episode",
            "data-chapter-id", "data-chapterid", "episode-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isComicWalkerEpisodeID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "chapter"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isComicWalkerEpisodeID)
    }

    private static func comicWalkerDataAttributeWorkID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-work-id", "data-workid", "data-content-id",
            "data-contentid", "data-series-id", "data-book-id",
            "work-id", "content-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isComicWalkerWorkID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["work", "content", "detail", "series", "comic"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isComicWalkerWorkID)
    }

    private static func narouDataAttributeLooksLikeNovelCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-ncode", "data-novel-code", "data-novelcode",
            "data-work-id", "data-workid", "data-novel-id", "data-novelid"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["narou", "syosetu", "ncode", "novel", "work", "chapter", "episode"])
    }

    private static func kakuyomuDataAttributeLooksLikeWorkCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-work-id", "data-workid", "data-novel-id",
            "data-novelid", "data-series-id", "data-episode-id", "data-episodeid"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["kakuyomu", "work", "novel", "series", "episode", "chapter"])
    }

    private static func hamelnDataAttributeLooksLikeNovelCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-novel-id", "data-novelid", "data-work-id",
            "data-workid", "data-story-id", "data-page-id",
            "data-chapter-id", "data-episode-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["hameln", "novel", "work", "story", "page", "chapter", "episode"])
    }

    private static func comicWalkerDataAttributeLooksLikeEpisodeCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-episode-id", "data-episodeid", "data-episode",
            "data-chapter-id", "data-chapterid", "episode-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "chapter"])
    }

    private static func comicWalkerDataAttributeLooksLikeWorkCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-work-id", "data-workid", "data-content-id",
            "data-contentid", "data-series-id", "data-book-id",
            "work-id", "content-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["work", "content", "detail", "series", "comic"])
    }

    private static func isNarouNcode(_ value: String) -> Bool {
        value.range(of: #"^n[0-9]+[a-z]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isTextFictionPositiveNumber(_ value: String) -> Bool {
        guard value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
              let number = Int(value) else {
            return false
        }
        return number > 0
    }

    private static func isKakuyomuID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{6,}$"#, options: .regularExpression) != nil
    }

    private static func isComicWalkerEpisodeID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{2,120}$"#, options: .regularExpression) != nil
    }

    private static func isComicWalkerWorkID(_ value: String) -> Bool {
        isValidPathSlug(value) && value.count <= 160
    }

    private static func koreanPortalDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased() else {
            return nil
        }

        if isNaverBlogHost(host),
           let post = naverBlogDataAttributePost(in: attributes, baseURL: baseURL),
           naverBlogDataAttributeLooksLikePostCard(attributes) {
            if host.hasSuffix(".blog.me") || host.hasSuffix(".blog.test") {
                return "/\(post.postID)"
            }
            return naverRelativeURL(
                path: "/PostView.nhn",
                queryItems: [
                    URLQueryItem(name: "blogId", value: post.blogID),
                    URLQueryItem(name: "logNo", value: post.postID)
                ]
            )
        }

        if isNaverPostHost(host) {
            if let post = naverPostDataAttributePost(in: attributes),
               naverPostDataAttributeLooksLikePostCard(attributes) {
                var items = [URLQueryItem(name: "volumeNo", value: post.volumeNo)]
                if let memberNo = post.memberNo {
                    items.append(URLQueryItem(name: "memberNo", value: memberNo))
                }
                return naverRelativeURL(path: "/viewer/postView.naver", queryItems: items)
            }
            if let collection = naverPostDataAttributeCollection(in: attributes),
               naverPostDataAttributeLooksLikeCollectionCard(attributes) {
                var items = [URLQueryItem(name: "memberNo", value: collection.memberNo)]
                if let seriesNo = collection.seriesNo {
                    items.append(URLQueryItem(name: "seriesNo", value: seriesNo))
                    return naverRelativeURL(path: "/my/series/detail.nhn", queryItems: items)
                }
                return naverRelativeURL(path: "/my.nhn", queryItems: items)
            }
        }

        if isNaverCafeHost(host),
           let article = naverCafeDataAttributeArticle(in: attributes, baseURL: baseURL),
           naverCafeDataAttributeLooksLikeArticleCard(attributes) {
            if let clubID = article.clubID {
                return "/ca-fe/web/cafes/\(clubID)/articles/\(article.articleID)"
            }
            if let cafeName = article.cafeName {
                return "/\(cafeName)/\(article.articleID)"
            }
        }

        if isNaverTVHost(host),
           let clipID = naverTVDataAttributeClipID(in: attributes),
           naverTVDataAttributeLooksLikeClipCard(attributes) {
            return "/v/\(clipID)"
        }

        if isWebtoonHost(host),
           let episode = webtoonDataAttributeEpisode(in: attributes),
           webtoonDataAttributeLooksLikeEpisodeCard(attributes) {
            return naverRelativeURL(
                path: "/viewer",
                queryItems: [
                    URLQueryItem(name: "title_no", value: episode.titleNo),
                    URLQueryItem(name: "episode_no", value: episode.episodeNo)
                ]
            )
        }

        if isNaverWebtoonHost(host),
           let episode = naverWebtoonDataAttributeEpisode(in: attributes),
           naverWebtoonDataAttributeLooksLikeEpisodeCard(attributes) {
            return naverRelativeURL(
                path: "/webtoon/detail",
                queryItems: [
                    URLQueryItem(name: "titleId", value: episode.titleID),
                    URLQueryItem(name: "no", value: episode.episodeNo)
                ]
            )
        }

        return nil
    }

    private static func naverBlogDataAttributePost(in attributes: [String: String], baseURL: URL) -> (blogID: String, postID: String)? {
        let postKeys = [
            "data-log-no", "data-logno", "data-post-id", "data-postid",
            "data-article-id", "data-articleid", "logno", "log-no", "post-id"
        ]
        let postID = firstAttributeValue(in: attributes, keys: postKeys, matching: isNaverPositiveNumericID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "article", "blog"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
                : nil)
        guard let postID else { return nil }

        let blogKeys = [
            "data-blog-id", "data-blogid", "data-blog", "data-author-id",
            "data-author", "data-user-id", "data-user", "data-username",
            "blogid", "blog-id", "blog", "username"
        ]
        let blogID = firstAttributeValue(in: attributes, keys: blogKeys, matching: isNaverPathSlug) ??
            naverBlogName(from: baseURL)
        guard let blogID else { return nil }
        return (blogID, postID)
    }

    private static func naverPostDataAttributePost(in attributes: [String: String]) -> (volumeNo: String, memberNo: String?)? {
        let volumeKeys = [
            "data-volume-no", "data-volumeno", "data-post-id", "data-postid",
            "data-article-id", "data-articleid", "volume-no", "volumeno"
        ]
        let volumeNo = firstAttributeValue(in: attributes, keys: volumeKeys, matching: isNaverPositiveNumericID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "viewer", "volume", "article"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
                : nil)
        guard let volumeNo else { return nil }
        return (volumeNo, naverPostDataAttributeMemberNo(in: attributes))
    }

    private static func naverPostDataAttributeCollection(in attributes: [String: String]) -> (memberNo: String, seriesNo: String?)? {
        guard let memberNo = naverPostDataAttributeMemberNo(in: attributes) else {
            return nil
        }
        let seriesNo = firstAttributeValue(
            in: attributes,
            keys: ["data-series-no", "data-seriesno", "data-series-id", "data-seriesid", "series-no", "seriesno"],
            matching: isNaverPositiveNumericID
        )
        return (memberNo, seriesNo)
    }

    private static func naverPostDataAttributeMemberNo(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-member-no", "data-memberno", "data-member-id",
                "data-memberid", "data-user-id", "data-userid",
                "data-channel-id", "data-channelid", "member-no", "memberno"
            ],
            matching: isNaverPositiveNumericID
        )
    }

    private static func naverCafeDataAttributeArticle(in attributes: [String: String], baseURL: URL) -> (clubID: String?, cafeName: String?, articleID: String)? {
        let articleKeys = [
            "data-article-id", "data-articleid", "data-post-id",
            "data-postid", "article-id", "articleid"
        ]
        let articleID = firstAttributeValue(in: attributes, keys: articleKeys, matching: isNaverPositiveNumericID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["article", "post", "cafe"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
                : nil)
        guard let articleID else { return nil }

        let clubID = firstAttributeValue(
            in: attributes,
            keys: ["data-club-id", "data-clubid", "data-cafe-id", "data-cafeid", "clubid", "club-id"],
            matching: isNaverPositiveNumericID
        )
        let cafeName = firstAttributeValue(
            in: attributes,
            keys: ["data-cafe-name", "data-cafename", "data-cafe", "data-board", "cafe-name", "cafe"],
            matching: isNaverCafeName
        ) ?? naverCafeName(from: baseURL)

        guard clubID != nil || cafeName != nil else { return nil }
        return (clubID, cafeName, articleID)
    }

    private static func naverTVDataAttributeClipID(in attributes: [String: String]) -> String? {
        let clipKeys = [
            "data-clip-id", "data-clipid", "data-clip-no", "data-clipno",
            "data-video-id", "data-videoid", "clip-id", "clipno", "video-id"
        ]
        if let clipID = firstAttributeValue(in: attributes, keys: clipKeys, matching: isNaverPositiveNumericID) {
            return clipID
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip", "video", "navertv"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
    }

    private static func webtoonDataAttributeEpisode(in attributes: [String: String]) -> (titleNo: String, episodeNo: String)? {
        let titleNo = firstAttributeValue(
            in: attributes,
            keys: ["data-title-no", "data-titleno", "data-title-id", "data-titleid", "title-no", "titleno"],
            matching: isNaverPositiveNumericID
        )
        let episodeNo = firstAttributeValue(
            in: attributes,
            keys: ["data-episode-no", "data-episodeno", "data-episode-id", "data-episodeid", "episode-no", "episodeno"],
            matching: isNaverPositiveNumericID
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "viewer"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
            : nil)
        guard let titleNo, let episodeNo else { return nil }
        return (titleNo, episodeNo)
    }

    private static func naverWebtoonDataAttributeEpisode(in attributes: [String: String]) -> (titleID: String, episodeNo: String)? {
        let titleID = firstAttributeValue(
            in: attributes,
            keys: ["data-title-id", "data-titleid", "data-title-no", "data-titleno", "titleid", "title-id"],
            matching: isNaverPositiveNumericID
        )
        let episodeNo = firstAttributeValue(
            in: attributes,
            keys: ["data-episode-no", "data-episodeno", "data-no", "data-episode-id", "data-episodeid", "episode-no", "no"],
            matching: isNaverPositiveNumericID
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "detail", "viewer"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
            : nil)
        guard let titleID, let episodeNo else { return nil }
        return (titleID, episodeNo)
    }

    private static func naverBlogDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-log-no", "data-logno", "data-post-id", "data-postid", "data-article-id", "data-articleid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "article", "blog"])
    }

    private static func naverPostDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-volume-no", "data-volumeno", "data-post-id", "data-postid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "viewer", "volume", "article"])
    }

    private static func naverPostDataAttributeLooksLikeCollectionCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-series-no", "data-seriesno", "data-series-id", "data-seriesid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["collection", "series", "profile", "author"])
    }

    private static func naverCafeDataAttributeLooksLikeArticleCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-article-id", "data-articleid", "data-club-id", "data-clubid", "data-cafe-id", "data-cafeid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["article", "post", "cafe"])
    }

    private static func naverTVDataAttributeLooksLikeClipCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-clip-id", "data-clipid", "data-clip-no", "data-clipno", "data-video-id", "data-videoid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["clip", "video", "navertv"])
    }

    private static func webtoonDataAttributeLooksLikeEpisodeCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-title-no", "data-titleno", "data-episode-no", "data-episodeno"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "viewer", "webtoon"])
    }

    private static func naverWebtoonDataAttributeLooksLikeEpisodeCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-title-id", "data-titleid", "data-episode-no", "data-episodeno", "data-no"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "detail", "viewer", "webtoon"])
    }

    private static func naverRelativeURL(path: String, queryItems: [URLQueryItem]) -> String? {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string
    }

    private static func naverBlogName(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              host.hasSuffix(".blog.me") || host.hasSuffix(".blog.test"),
              let username = host.split(separator: ".").first.map(String.init),
              isNaverPathSlug(username) else {
            return nil
        }
        return username
    }

    private static func naverCafeName(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let cafeName = parts.first,
              isNaverCafeName(cafeName) else {
            return nil
        }
        return cafeName
    }

    private static func isNaverPositiveNumericID(_ value: String) -> Bool {
        isTextFictionPositiveNumber(value)
    }

    private static func isNaverPathSlug(_ value: String) -> Bool {
        isValidPathSlug(value) && value.count <= 80
    }

    private static func isNaverCafeName(_ value: String) -> Bool {
        let reserved: Set<String> = [
            "articlelist.nhn", "articlesearchlist.nhn", "articleview.nhn",
            "cafemembernetworkview.nhn", "ca-fe", "cafe", "cafehome",
            "cafes", "members", "search", "searchlist", "search.naver"
        ]
        return isNaverPathSlug(value) && !reserved.contains(value.lowercased())
    }

    private static func webComicDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased() else {
            return nil
        }

        if isPixivComicHost(host) {
            if let episodeID = pixivComicDataAttributeEpisodeID(in: attributes),
               pixivComicDataAttributeLooksLikeEpisodeCard(attributes) {
                return "/viewer/stories/\(episodeID)"
            }
            if let workID = pixivComicDataAttributeWorkID(in: attributes),
               pixivComicDataAttributeLooksLikeWorkCard(attributes) {
                return "/works/\(workID)"
            }
        }

        if isKakaoPageHost(host),
           let item = kakaoPageDataAttributeItem(in: attributes),
           kakaoPageDataAttributeLooksLikeItemCard(attributes, item: item) {
            if let productID = item.productID {
                return "/content/\(item.seriesID)/viewer/\(productID)"
            }
            return "/content/\(item.seriesID)"
        }

        if isKakaoWebtoonHost(host) {
            if let episode = kakaoWebtoonDataAttributeEpisode(in: attributes),
               kakaoWebtoonDataAttributeLooksLikeEpisodeCard(attributes) {
                return "/viewer/\(episode.seoID)/\(episode.episodeID)"
            }
            if let contentID = kakaoWebtoonDataAttributeContentID(in: attributes),
               kakaoWebtoonDataAttributeLooksLikeContentCard(attributes) {
                return "/content/\(contentID)"
            }
        }

        if isHiyobiHost(host),
           let galleryID = hiyobiDataAttributeGalleryID(in: attributes),
           hiyobiDataAttributeLooksLikeGalleryCard(attributes) {
            return "/reader/\(galleryID)"
        }

        return nil
    }

    private static func pixivComicDataAttributeEpisodeID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-episode-id", "data-episodeid", "data-story-id",
            "data-storyid", "data-comic-episode-id", "episode-id", "story-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isNaverPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "story", "viewer"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
    }

    private static func pixivComicDataAttributeWorkID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-work-id", "data-workid", "data-series-id",
            "data-seriesid", "data-comic-id", "work-id", "series-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isNaverPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["work", "series", "comic"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
    }

    private static func kakaoPageDataAttributeItem(in attributes: [String: String]) -> (seriesID: String, productID: String?)? {
        let seriesID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-series-id", "data-seriesid", "data-content-id",
                "data-contentid", "data-work-id", "data-workid", "series-id"
            ],
            matching: isNaverPositiveNumericID
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["series", "content", "work"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
            : nil)
        guard let seriesID else { return nil }

        let productID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-product-id", "data-productid", "data-episode-id",
                "data-episodeid", "data-viewer-id", "data-viewerid",
                "product-id", "episode-id"
            ],
            matching: isNaverPositiveNumericID
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "viewer", "product"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
            : nil)
        return (seriesID, productID)
    }

    private static func kakaoWebtoonDataAttributeEpisode(in attributes: [String: String]) -> (seoID: String, episodeID: String)? {
        let episodeID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-episode-id", "data-episodeid", "data-product-id",
                "data-productid", "data-viewer-id", "data-viewerid",
                "episode-id", "product-id"
            ],
            matching: isNaverPositiveNumericID
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "viewer", "product"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
            : nil)
        guard let episodeID else { return nil }

        let seoID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-seo-id", "data-seoid", "data-seo", "data-slug",
                "data-title-slug", "data-content-slug", "seo-id", "slug"
            ],
            matching: isValidPathSlug
        ) ?? kakaoWebtoonDataAttributeContentID(in: attributes)
        guard let seoID else { return nil }
        return (seoID, episodeID)
    }

    private static func kakaoWebtoonDataAttributeContentID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-content-id", "data-contentid", "data-series-id",
            "data-seriesid", "data-work-id", "data-workid", "content-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isNaverPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["content", "series", "work"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
    }

    private static func hiyobiDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        let explicitKeys = [
            "data-gallery-id", "data-galleryid", "data-reader-id",
            "data-readerid", "data-post-id", "data-postid", "gallery-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: explicitKeys, matching: isNaverPositiveNumericID) {
            return value
        }
        guard dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "reader", "post"]) else {
            return nil
        }
        return firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
    }

    private static func pixivComicDataAttributeLooksLikeEpisodeCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-episode-id", "data-episodeid", "data-story-id", "data-storyid", "data-comic-episode-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "story", "viewer"])
    }

    private static func pixivComicDataAttributeLooksLikeWorkCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-work-id", "data-workid", "data-series-id", "data-seriesid", "data-comic-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["work", "series", "comic"])
    }

    private static func kakaoPageDataAttributeLooksLikeItemCard(_ attributes: [String: String], item: (seriesID: String, productID: String?)) -> Bool {
        if item.productID != nil {
            let markerKeys = ["data-product-id", "data-productid", "data-episode-id", "data-episodeid", "data-viewer-id", "data-viewerid"]
            if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
                return true
            }
            return dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "viewer", "product"])
        }

        let markerKeys = ["data-series-id", "data-seriesid", "data-content-id", "data-contentid", "data-work-id", "data-workid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["series", "content", "work"])
    }

    private static func kakaoWebtoonDataAttributeLooksLikeEpisodeCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-episode-id", "data-episodeid", "data-product-id", "data-productid", "data-viewer-id", "data-viewerid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["episode", "viewer", "product"])
    }

    private static func kakaoWebtoonDataAttributeLooksLikeContentCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-content-id", "data-contentid", "data-series-id", "data-seriesid", "data-work-id", "data-workid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["content", "series", "work"])
    }

    private static func hiyobiDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-gallery-id", "data-galleryid", "data-reader-id", "data-readerid", "data-post-id", "data-postid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "reader", "post"])
    }

    private static func mangaPortalDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased() else {
            return nil
        }

        if isManatokiHost(host),
           let content = manatokiDataAttributeContent(in: attributes),
           manatokiDataAttributeLooksLikeContentCard(attributes, section: content.section) {
            return "/\(content.section)/\(content.id)"
        }

        if isLHScanHost(host),
           let content = lhScanDataAttributeContent(in: attributes),
           lhScanDataAttributeLooksLikeContentCard(attributes, hasChapter: content.chapterSlug != nil) {
            if let chapterSlug = content.chapterSlug {
                return "/manga/\(content.seriesSlug)/\(chapterSlug)"
            }
            return "/manga/\(content.seriesSlug)"
        }

        if isJManaHost(host),
           let content = jManaDataAttributeContent(in: attributes),
           jManaDataAttributeLooksLikeContentCard(attributes, kind: content.kind) {
            switch content.kind {
            case .chapter:
                return jManaRelativeURL(
                    path: "/bookdetail",
                    queryItems: [
                        URLQueryItem(name: "book", value: content.book),
                        URLQueryItem(name: "bookdetailid", value: content.detailID)
                    ]
                )
            case .series:
                return jManaRelativeURL(
                    path: "/book",
                    queryItems: [URLQueryItem(name: "book", value: content.book)]
                )
            case .title:
                return jManaRelativeURL(
                    path: "/book_by_title",
                    queryItems: [URLQueryItem(name: "title", value: content.title)]
                )
            }
        }

        return nil
    }

    private enum JManaDataAttributeKind {
        case chapter
        case series
        case title
    }

    private static func manatokiDataAttributeContent(in attributes: [String: String]) -> (section: String, id: String)? {
        let idKeys = [
            "data-content-id", "data-contentid", "data-post-id",
            "data-postid", "data-wr-id", "data-wrid", "wr-id", "content-id"
        ]
        let id = firstAttributeValue(in: attributes, keys: idKeys, matching: isNaverPositiveNumericID) ??
            (dataAttributeTypeHint(in: attributes, containsAnyOf: ["comic", "webtoon", "board", "article"])
                ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
                : nil)
        guard let id else { return nil }

        let section = firstAttributeValue(
            in: attributes,
            keys: ["data-section", "data-bo-table", "data-botable", "data-board", "section", "bo-table"],
            matching: isManatokiSection
        ) ?? manatokiSectionHint(in: attributes)
        guard let section else { return nil }
        return (section, id)
    }

    private static func lhScanDataAttributeContent(in attributes: [String: String]) -> (seriesSlug: String, chapterSlug: String?)? {
        let seriesSlug = firstAttributeValue(
            in: attributes,
            keys: [
                "data-series-slug", "data-seriesslug", "data-manga-slug",
                "data-mangaslug", "data-series-id", "data-manga-id",
                "series-slug", "manga-slug"
            ],
            matching: isLHScanSlug
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["series", "manga"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isLHScanSlug)
            : nil)
        guard let seriesSlug else { return nil }

        let chapterSlug = firstAttributeValue(
            in: attributes,
            keys: [
                "data-chapter-slug", "data-chapterslug", "data-chapter-id",
                "data-chapterid", "data-episode-slug", "chapter-slug"
            ],
            matching: isLHScanSlug
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["chapter", "episode"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isLHScanSlug)
            : nil)
        return (seriesSlug, chapterSlug)
    }

    private static func jManaDataAttributeContent(in attributes: [String: String]) -> (kind: JManaDataAttributeKind, book: String, detailID: String, title: String)? {
        let book = firstAttributeValue(
            in: attributes,
            keys: [
                "data-book", "data-book-id", "data-bookid",
                "data-series-id", "data-seriesid", "book", "book-id"
            ],
            matching: isJManaToken
        )
        let detailID = firstAttributeValue(
            in: attributes,
            keys: [
                "data-bookdetailid", "data-book-detail-id", "data-detail-id",
                "data-detailid", "data-chapter-id", "data-chapterid",
                "bookdetailid", "book-detail-id"
            ],
            matching: isNaverPositiveNumericID
        ) ?? (dataAttributeTypeHint(in: attributes, containsAnyOf: ["chapter", "detail"])
            ? firstAttributeValue(in: attributes, keys: ["data-id", "id"], matching: isNaverPositiveNumericID)
            : nil)

        if let book, let detailID {
            return (.chapter, book, detailID, "")
        }
        if let book,
           jManaDataAttributeLooksLikeSeriesCard(attributes) {
            return (.series, book, "", "")
        }

        let title = firstAttributeValue(
            in: attributes,
            keys: ["data-title", "data-title-query", "data-keyword", "data-query", "title"],
            matching: isJManaToken
        )
        if let title,
           jManaDataAttributeLooksLikeTitleCard(attributes) {
            return (.title, "", "", title)
        }

        return nil
    }

    private static func manatokiDataAttributeLooksLikeContentCard(_ attributes: [String: String], section: String) -> Bool {
        let markerKeys = ["data-content-id", "data-contentid", "data-post-id", "data-postid", "data-wr-id", "data-wrid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: [section, "board", "article"])
    }

    private static func lhScanDataAttributeLooksLikeContentCard(_ attributes: [String: String], hasChapter: Bool) -> Bool {
        if hasChapter {
            let markerKeys = ["data-chapter-slug", "data-chapterslug", "data-chapter-id", "data-chapterid", "data-episode-slug"]
            if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
                return true
            }
            return dataAttributeTypeHint(in: attributes, containsAnyOf: ["chapter", "episode"])
        }

        let markerKeys = ["data-series-slug", "data-seriesslug", "data-manga-slug", "data-mangaslug", "data-series-id", "data-manga-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["series", "manga"])
    }

    private static func jManaDataAttributeLooksLikeContentCard(_ attributes: [String: String], kind: JManaDataAttributeKind) -> Bool {
        switch kind {
        case .chapter:
            let markerKeys = ["data-bookdetailid", "data-book-detail-id", "data-detail-id", "data-detailid", "data-chapter-id", "data-chapterid"]
            if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
                return true
            }
            return dataAttributeTypeHint(in: attributes, containsAnyOf: ["chapter", "detail"])
        case .series:
            return jManaDataAttributeLooksLikeSeriesCard(attributes)
        case .title:
            return jManaDataAttributeLooksLikeTitleCard(attributes)
        }
    }

    private static func jManaDataAttributeLooksLikeSeriesCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-book", "data-book-id", "data-bookid"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["book", "series"])
    }

    private static func jManaDataAttributeLooksLikeTitleCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-title", "data-title-query", "data-keyword", "data-query"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["title", "search", "keyword"])
    }

    private static func manatokiSectionHint(in attributes: [String: String]) -> String? {
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["webtoon"]) {
            return "webtoon"
        }
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["comic", "board", "article"]) {
            return "comic"
        }
        return nil
    }

    private static func isManatokiSection(_ value: String) -> Bool {
        ["comic", "webtoon"].contains(value.lowercased())
    }

    private static func isLHScanSlug(_ value: String) -> Bool {
        isValidPathSlug(value) && value.count <= 160
    }

    private static func isJManaToken(_ value: String) -> Bool {
        isValidPathSlug(value) && value.count <= 160
    }

    private static func jManaRelativeURL(path: String, queryItems: [URLQueryItem]) -> String? {
        var components = URLComponents()
        components.path = path
        components.queryItems = queryItems
        return components.string
    }

    private static func waybackDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isWaybackMachineHost(host),
              let targetURL = waybackDataAttributeTargetURL(in: attributes),
              waybackDataAttributeLooksLikeArchiveCard(attributes),
              !waybackDataAttributeLooksLikeNavigation(attributes) else {
            return nil
        }

        if let token = waybackDataAttributeTimestamp(in: attributes) {
            return "/web/\(token)/\(targetURL.absoluteString)"
        }

        return waybackCDXRelativeURL(targetURL: targetURL)
    }

    private static func waybackDataAttributeTargetURL(in attributes: [String: String]) -> URL? {
        let keys = [
            "data-original-url", "data-original", "data-target-url",
            "data-target", "data-page-url", "data-source-url",
            "data-url", "original-url", "target-url"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  let url = waybackDataAttributeTargetURL(from: raw) else {
                continue
            }
            return url
        }
        return nil
    }

    private static func waybackDataAttributeTargetURL(from raw: String) -> URL? {
        let decoded = raw.removingPercentEncoding?.trimmed ?? raw.trimmed
        guard decoded.lowercased().hasPrefix("http://") ||
                decoded.lowercased().hasPrefix("https://"),
              let url = URL(string: decoded),
              let host = url.host?.lowercased(),
              url.scheme?.lowercased().hasPrefix("http") == true else {
            return nil
        }
        if isWaybackMachineHost(host),
           let target = WaybackMachineResolver.targetURL(from: url) {
            return target
        }
        return url
    }

    private static func waybackDataAttributeTimestamp(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-timestamp", "data-snapshot-timestamp",
                "data-archive-timestamp", "data-wayback-timestamp",
                "data-snapshot-id", "timestamp", "snapshot-id"
            ],
            matching: isWaybackArchiveToken
        )
    }

    private static func waybackDataAttributeLooksLikeArchiveCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-original-url", "data-original", "data-target-url",
            "data-target", "data-timestamp", "data-snapshot-timestamp",
            "data-archive-timestamp", "data-wayback-timestamp"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["wayback", "archive", "snapshot", "cdx"])
    }

    private static func waybackDataAttributeLooksLikeNavigation(_ attributes: [String: String]) -> Bool {
        dataAttributeTypeHint(in: attributes, containsAnyOf: ["save", "navigation", "nav", "toolbar", "button"])
    }

    private static func isWaybackArchiveToken(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{1,14}[A-Za-z_]*$"#, options: .regularExpression) != nil
    }

    private static func waybackCDXRelativeURL(targetURL: URL) -> String? {
        var components = URLComponents()
        components.path = "/cdx/search/cdx"
        components.queryItems = [URLQueryItem(name: "url", value: targetURL.absoluteString)]
        return components.string
    }

    private static func googleDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isGoogleHost(host),
              !googleDataAttributeLooksLikeNavigation(attributes) else {
            return nil
        }

        let keys = [
            "data-rw", "data-amp-cur", "data-result-url",
            "data-destination-url", "data-target-url", "data-target",
            "data-href", "data-url", "data-link"
        ]
        for key in keys {
            guard let raw = attributes[key]?.trimmed,
                  looksLikeDataAttributeLink(raw),
                  let absolute = resolve(href: raw, baseURL: baseURL),
                  googleSearchTargetURL(from: absolute) != nil else {
                continue
            }
            return raw
        }
        return nil
    }

    private static func googleDataAttributeLooksLikeNavigation(_ attributes: [String: String]) -> Bool {
        dataAttributeTypeHint(in: attributes, containsAnyOf: ["settings", "preference", "navigation", "nav", "menu", "login", "account"])
    }

    private static func isValidTumblrBlogName(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$"#, options: .regularExpression) != nil
    }

    private static func isTumblrPostID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isFourChanBoardID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9]{1,16}$"#, options: .regularExpression) != nil
    }

    private static func isFourChanThreadID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isPornhubMediaID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil
    }

    private static func isWeiboStatusID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z:_-]+$"#, options: .regularExpression) != nil &&
            !["ajax", "detail", "login", "search", "status", "tv"].contains(value.lowercased())
    }

    private static func isSpankBangID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil &&
            !["s", "search", "tag", "tags", "category", "categories", "users", "user", "channels", "channel", "pornstars", "playlist"].contains(value.lowercased())
    }

    private static func isXVideoID(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z]+$"#, options: .regularExpression) != nil
    }

    private static func isTwitterNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isValidTwitterUsername(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{1,20}$"#, options: .regularExpression) != nil
    }

    private static func isTikTokNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{6,}$"#, options: .regularExpression) != nil
    }

    private static func isValidTikTokUsername(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._-]{1,80}$"#, options: .regularExpression) != nil
    }

    private static func isValidChzzkClipID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isValidChzzkVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{2,}$"#, options: .regularExpression) != nil
    }

    private static func isValidChzzkLiveID(_ value: String) -> Bool {
        guard isValidChzzkVideoID(value) else { return false }
        let reserved = [
            "clip", "clips", "video", "videos", "vod", "live", "search",
            "category", "following", "lounge", "settings", "notice"
        ]
        return !reserved.contains(value.lowercased())
    }

    private static func isSOOPNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isSOOPLiveID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_]{2,32}$"#, options: .regularExpression) != nil
    }

    private static func isValidNiconicoVideoID(_ value: String) -> Bool {
        value.range(of: #"^(?:sm|so|nm)?[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isValidNiconicoLiveID(_ value: String) -> Bool {
        value.range(of: #"^lv[0-9]+$"#, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private static func isNiconicoNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isTwitchNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isValidInstagramShortcode(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{2,}$"#, options: .regularExpression) != nil
    }

    private static func isInstagramNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isValidInstagramUsername(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._]{1,80}$"#, options: .regularExpression) != nil
    }

    private static func isFacebookPhotoID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil
    }

    private static func isFacebookVideoID(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9._-]{3,}$"#, options: .regularExpression) != nil &&
            !["watch", "videos", "video.php", "reel", "reels", "photos", "photo.php", "share"].contains(value.lowercased())
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

    private static func firstValidPathSlug(in attributes: [String: String], keys: [String]) -> String? {
        firstAttributeValue(in: attributes, keys: keys, matching: isValidPathSlug)
    }

    private static func hitomiDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isHitomiHost(host),
              let id = hitomiDataAttributeGalleryID(in: attributes),
              hitomiDataAttributeLooksLikeGalleryCard(attributes) else {
            return nil
        }
        return "/reader/\(id).html"
    }

    private static func hitomiDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-reader-id", "data-readerid",
            "data-work-id", "data-workid", "gallery-id", "reader-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSearchNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSearchNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "reader", "doujin", "manga"]) {
            return id
        }
        return nil
    }

    private static func hitomiDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-gallery-id", "data-galleryid", "data-reader-id", "data-readerid",
            "data-work-id", "data-workid", "gallery-id", "reader-id"
        ]
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["tag", "search", "nav", "menu", "filter"]) {
            return false
        }
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "reader", "doujin", "manga"])
    }

    private static func nhentaiDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isNHentaiHost(host),
              let id = nhentaiDataAttributeGalleryID(in: attributes),
              nhentaiDataAttributeLooksLikeGalleryCard(attributes) else {
            return nil
        }
        return "/g/\(id)/"
    }

    private static func nhentaiDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-doujin-id", "data-doujinid",
            "data-media-id", "data-mediaid", "gallery-id", "doujin-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSearchNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSearchNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "doujin", "comic", "manga"]) {
            return id
        }
        return nil
    }

    private static func nhentaiDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-gallery-id", "data-galleryid", "data-doujin-id", "data-doujinid",
            "data-media-id", "data-mediaid", "gallery-id", "doujin-id"
        ]
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["tag", "search", "nav", "menu", "filter", "profile", "user"]) {
            return false
        }
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "doujin", "comic", "manga"])
    }

    private static func nhentaiComDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isNHentaiComHost(host),
              let slug = nhentaiComDataAttributeComicSlug(in: attributes),
              nhentaiComDataAttributeLooksLikeComicCard(attributes) else {
            return nil
        }
        return "/comic/\(slug)"
    }

    private static func nhentaiComDataAttributeComicSlug(in attributes: [String: String]) -> String? {
        let keys = [
            "data-comic-slug", "data-comicslug", "data-title-slug",
            "data-slug", "comic-slug", "slug"
        ]
        if let value = firstValidPathSlug(in: attributes, keys: keys) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["comic", "gallery", "doujin", "manga"]) {
            return id
        }
        return nil
    }

    private static func nhentaiComDataAttributeLooksLikeComicCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-comic-slug", "data-comicslug", "data-title-slug",
            "data-slug", "comic-slug", "slug"
        ]
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["profile", "user", "tag", "search", "nav", "menu", "filter"]) {
            return false
        }
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["comic", "gallery", "doujin", "manga"])
    }

    private static func ehentaiDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isEHentaiHost(host),
              let id = ehentaiDataAttributeGalleryID(in: attributes),
              let token = ehentaiDataAttributeGalleryToken(in: attributes),
              ehentaiDataAttributeLooksLikeGalleryCard(attributes) else {
            return nil
        }
        let isLoFi = dataAttributeTypeHint(in: attributes, containsAnyOf: ["lofi"]) ||
            attributes["data-mode"]?.lowercased().trimmed == "lofi" ||
            attributes["mode"]?.lowercased().trimmed == "lofi"
        return isLoFi ? "/lofi/g/\(id)/\(token)/" : "/g/\(id)/\(token)/"
    }

    private static func ehentaiDataAttributeGalleryID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-gallery-id", "data-galleryid", "data-gid", "gid", "gallery-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSearchNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSearchNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "lofi"]) {
            return id
        }
        return nil
    }

    private static func ehentaiDataAttributeGalleryToken(in attributes: [String: String]) -> String? {
        firstValidPathSlug(in: attributes, keys: [
            "data-gallery-token", "data-gtoken", "data-token", "data-key",
            "gallery-token", "gtoken", "token"
        ])
    }

    private static func ehentaiDataAttributeLooksLikeGalleryCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-gallery-id", "data-galleryid", "data-gid", "gid", "gallery-id",
            "data-gallery-token", "data-gtoken", "data-token", "gallery-token"
        ]
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["image", "tag", "search", "nav", "menu", "filter", "profile", "user"]) {
            return false
        }
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["gallery", "lofi"])
    }

    private static func nozomiDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isNozomiHost(host),
              let id = nozomiDataAttributePostID(in: attributes),
              nozomiDataAttributeLooksLikePostCard(attributes) else {
            return nil
        }
        return "/post/\(id).html"
    }

    private static func nozomiDataAttributePostID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-post-id", "data-postid", "data-nozomi-id",
            "data-nozomiid", "post-id", "nozomi-id"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isSearchNumericID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isSearchNumericID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "image", "picture"]) {
            return id
        }
        return nil
    }

    private static func nozomiDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-post-id", "data-postid", "data-nozomi-id",
            "data-nozomiid", "post-id", "nozomi-id"
        ]
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["tag", "search", "nav", "menu", "filter", "profile", "user"]) {
            return false
        }
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["post", "image", "picture"])
    }

    private static func isSearchNumericID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func pinterestDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isPinterestHost(host),
              let id = pinterestDataAttributePinID(in: attributes),
              pinterestDataAttributeLooksLikePinCard(attributes) else {
            return nil
        }
        return "/pin/\(id)/"
    }

    private static func pinterestDataAttributePinID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-pin-id", "data-pinid", "data-pin", "pin-id", "pinid", "pin"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isPinterestPinID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isPinterestPinID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["pin"]) {
            return id
        }
        return nil
    }

    private static func pinterestDataAttributeLooksLikePinCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-pin-id", "data-pinid", "data-pin", "pin-id", "pinid", "pin"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["board", "profile", "user", "account"]) {
            return false
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["pin"])
    }

    private static func isPinterestPinID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{4,30}$"#, options: .regularExpression) != nil
    }

    private static func deviantArtDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isDeviantArtHost(host),
              let id = deviantArtDataAttributeArtworkID(in: attributes),
              let username = deviantArtDataAttributeUsername(in: attributes),
              let rawSlug = firstValidPathSlug(in: attributes, keys: [
                  "data-deviation-slug", "data-artwork-slug", "data-title-slug", "data-slug", "slug"
              ]),
              deviantArtDataAttributeLooksLikeArtworkCard(attributes) else {
            return nil
        }
        let slug = rawSlug.hasSuffix("-\(id)") ? rawSlug : "\(rawSlug)-\(id)"
        return "/\(username)/art/\(slug)"
    }

    private static func deviantArtDataAttributeArtworkID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-deviation-id", "data-deviationid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid"
        ]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isDeviantArtArtworkID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isDeviantArtArtworkID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["deviation", "artwork"]) {
            return id
        }
        return nil
    }

    private static func deviantArtDataAttributeUsername(in attributes: [String: String]) -> String? {
        firstValidPathSlug(in: attributes, keys: [
            "data-artist-username", "data-author-username", "data-user-name",
            "data-username", "username", "data-user", "user"
        ])
    }

    private static func deviantArtDataAttributeLooksLikeArtworkCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-deviation-id", "data-deviationid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["profile", "gallery", "folder", "user"]) {
            return false
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["deviation", "artwork"])
    }

    private static func isDeviantArtArtworkID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{3,}$"#, options: .regularExpression) != nil
    }

    private static func newgroundsDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isNewgroundsHost(host),
              let username = newgroundsDataAttributeUsername(in: attributes),
              let slug = newgroundsDataAttributeArtworkSlug(in: attributes),
              newgroundsDataAttributeLooksLikeArtworkCard(attributes) else {
            return nil
        }
        return "/art/view/\(username)/\(slug)"
    }

    private static func newgroundsDataAttributeUsername(in attributes: [String: String]) -> String? {
        firstValidPathSlug(in: attributes, keys: [
            "data-artist-username", "data-author-username", "data-user-name",
            "data-username", "username", "data-user", "user"
        ])
    }

    private static func newgroundsDataAttributeArtworkSlug(in attributes: [String: String]) -> String? {
        let keys = [
            "data-art-slug", "data-artwork-slug", "data-submission-slug",
            "data-title-slug", "data-slug", "art-slug", "slug"
        ]
        if let value = firstValidPathSlug(in: attributes, keys: keys) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["artwork", "submission"]) {
            return id
        }
        return nil
    }

    private static func newgroundsDataAttributeLooksLikeArtworkCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-art-slug", "data-artwork-slug", "data-submission-slug",
            "data-title-slug", "data-slug", "art-slug", "slug"
        ]
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["artist", "profile", "portal", "search", "nav"]) {
            return false
        }
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["artwork", "submission"])
    }

    private static func flickrDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isFlickrHost(host),
              let photoID = flickrDataAttributePhotoID(in: attributes),
              let userID = flickrDataAttributeUserID(in: attributes),
              flickrDataAttributeLooksLikePhotoCard(attributes) else {
            return nil
        }
        return "/photos/\(userID)/\(photoID)"
    }

    private static func flickrDataAttributePhotoID(in attributes: [String: String]) -> String? {
        let keys = ["data-photo-id", "data-photoid", "data-image-id", "data-imageid", "photo-id"]
        if let value = firstAttributeValue(in: attributes, keys: keys, matching: isFlickrPhotoID) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isFlickrPhotoID(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["photo", "image", "picture"]) {
            return id
        }
        return nil
    }

    private static func flickrDataAttributeUserID(in attributes: [String: String]) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-owner", "data-owner-id", "data-ownerid", "data-path-alias",
                "data-user-id", "data-userid", "data-user-name", "data-username",
                "data-user", "username", "user"
            ],
            matching: isFlickrUserIDValue
        )
    }

    private static func flickrDataAttributeLooksLikePhotoCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-photo-id", "data-photoid", "data-image-id", "data-imageid", "photo-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        if dataAttributeTypeHint(in: attributes, containsAnyOf: ["profile", "user", "people", "photostream"]) {
            return false
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["photo", "image", "picture"])
    }

    private static func isFlickrPhotoID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{3,}$"#, options: .regularExpression) != nil
    }

    private static func isFlickrUserIDValue(_ value: String) -> Bool {
        let reserved: Set<String> = ["explore", "groups", "photos", "search", "tags"]
        return value.range(of: #"^[A-Za-z0-9][A-Za-z0-9@._-]{1,80}$"#, options: .regularExpression) != nil &&
            !reserved.contains(value.lowercased())
    }

    private static func fc2DataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isFC2Host(host),
              let id = fc2DataAttributeContentID(in: attributes),
              fc2DataAttributeLooksLikeContentCard(attributes) else {
            return nil
        }
        return "/content/\(id)"
    }

    private static func fc2DataAttributeContentID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-content-id", "data-contentid", "data-video-id",
            "data-videoid", "data-movie-id", "data-movieid", "content-id",
            "video-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["content", "video", "movie"]) {
            return id
        }
        return nil
    }

    private static func fc2DataAttributeLooksLikeContentCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-content-id", "data-contentid", "data-video-id",
            "data-videoid", "data-movie-id", "data-movieid", "content-id",
            "video-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["content", "video", "movie"])
    }

    private static func bcyDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isBCYHost(host) else {
            return nil
        }
        if let itemID = bcyDataAttributeItemID(in: attributes),
           bcyDataAttributeLooksLikeItemCard(attributes) {
            return "/item/detail/\(itemID)"
        }
        if let userID = bcyDataAttributeUserID(in: attributes),
           bcyDataAttributeLooksLikeUserCard(attributes) {
            return "/u/\(userID)"
        }
        return nil
    }

    private static func bcyDataAttributeItemID(in attributes: [String: String]) -> String? {
        for key in ["data-item-id", "data-itemid", "data-post-id", "data-work-id", "item-id"] {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["item", "post", "work"]) {
            return id
        }
        return nil
    }

    private static func bcyDataAttributeUserID(in attributes: [String: String]) -> String? {
        for key in ["data-uid", "data-user-id", "data-userid", "uid", "user-id"] {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "author", "artist"]) {
            return id
        }
        return nil
    }

    private static func bcyDataAttributeLooksLikeItemCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-item-id", "data-itemid", "data-post-id", "data-work-id", "item-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["item", "post", "work"])
    }

    private static func bcyDataAttributeLooksLikeUserCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = ["data-uid", "data-user-id", "data-userid", "uid", "user-id"]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["user", "author", "artist"])
    }

    private static func artStationDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isArtStationHost(host),
              let id = artStationDataAttributeProjectID(in: attributes),
              artStationDataAttributeLooksLikeProjectCard(attributes) else {
            return nil
        }
        return "/artwork/\(id)"
    }

    private static func artStationDataAttributeProjectID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-project-id", "data-projectid", "data-artwork-id",
            "data-artworkid", "project-id", "artwork-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               isValidPathSlug(value) {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           isValidPathSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["project", "artwork"]) {
            return id
        }
        return nil
    }

    private static func artStationDataAttributeLooksLikeProjectCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-project-id", "data-projectid", "data-artwork-id",
            "data-artworkid", "project-id", "artwork-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["project", "artwork"])
    }

    private static func pixivDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isPixivHost(host),
              let id = pixivDataAttributeArtworkID(in: attributes),
              pixivDataAttributeLooksLikeArtworkCard(attributes) else {
            return nil
        }
        return "/artworks/\(id)"
    }

    private static func pixivDataAttributeArtworkID(in attributes: [String: String]) -> String? {
        let keys = [
            "data-illust-id", "data-illustid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid", "illust-id",
            "artwork-id"
        ]
        for key in keys {
            if let value = attributes[key]?.trimmed,
               value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return value
            }
        }
        if let id = attributes["data-id"]?.trimmed,
           id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil,
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["illust", "artwork", "work"]) {
            return id
        }
        return nil
    }

    private static func pixivDataAttributeLooksLikeArtworkCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-illust-id", "data-illustid", "data-artwork-id",
            "data-artworkid", "data-work-id", "data-workid", "illust-id",
            "artwork-id"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        return dataAttributeTypeHint(in: attributes, containsAnyOf: ["illust", "artwork", "work"])
    }

    private static func booruDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let baseURL,
              let provider = BooruProvider.provider(for: baseURL),
              booruDataAttributeLooksLikePostCard(attributes),
              let id = booruDataAttributePostID(in: attributes) else {
            return nil
        }

        switch provider {
        case .danbooru:
            return "/posts/\(id)"
        case .yandere:
            return "/post/show/\(id)"
        case .gelbooru, .rule34:
            return "/index.php?page=post&s=view&id=\(id)"
        }
    }

    private static func booruDataAttributePostID(in attributes: [String: String]) -> String? {
        for key in ["data-id", "data-post-id", "data-post-id-value", "post-id"] {
            if let value = attributes[key]?.trimmed,
               value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return value
            }
        }
        if let value = attributes["id"]?.trimmed,
           let id = firstCapture(in: value, pattern: #"^p([0-9]+)$"#) {
            return id
        }
        return nil
    }

    private static func booruDataAttributeLooksLikePostCard(_ attributes: [String: String]) -> Bool {
        let markerKeys = [
            "data-tags", "data-tag-string", "data-tag-string-general",
            "data-rating", "data-score", "data-file-ext", "data-width", "data-height"
        ]
        if markerKeys.contains(where: { attributes[$0]?.trimmed.isEmpty == false }) {
            return true
        }
        let hint = [
            attributes["class"] ?? "",
            attributes["data-type"] ?? "",
            attributes["data-kind"] ?? "",
            attributes["data-renderer"] ?? ""
        ].joined(separator: " ").lowercased()
        return ["post", "thumb", "preview", "image"].contains { hint.contains($0) }
    }

    private static func youtubeDataAttributeLinkValue(in attributes: [String: String], baseURL: URL?) -> String? {
        guard let host = baseURL?.host?.lowercased(),
              isYouTubeHost(host) else {
            return nil
        }

        let shortsKeys = ["data-shorts-video-id", "data-short-video-id", "data-short-id"]
        for key in shortsKeys {
            guard let id = attributes[key]?.trimmed,
                  isValidYouTubeSlug(id) else {
                continue
            }
            return "/shorts/\(id)"
        }

        let videoKeys = ["data-video-id", "data-videoid", "video-id", "videoid", "data-watch-id"]
        for key in videoKeys {
            guard let id = attributes[key]?.trimmed,
                  isValidYouTubeSlug(id) else {
                continue
            }
            return "/watch?v=\(id)"
        }

        if let id = attributes["data-id"]?.trimmed,
           isValidYouTubeSlug(id),
           dataAttributeTypeHint(in: attributes, containsAnyOf: ["video", "short", "watch"]) {
            return "/watch?v=\(id)"
        }

        let playlistKeys = ["data-playlist-id", "data-list-id", "data-playlistid"]
        for key in playlistKeys {
            guard let id = attributes[key]?.trimmed,
                  isValidYouTubeSlug(id) else {
                continue
            }
            return "/playlist?list=\(id)"
        }

        return nil
    }

    private static func dataAttributeTypeHint(in attributes: [String: String], containsAnyOf needles: [String]) -> Bool {
        let keys = ["data-type", "data-kind", "data-content-type", "data-renderer", "class", "role"]
        let values = keys.compactMap { attributes[$0]?.lowercased() }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func looksLikeDataAttributeLink(_ value: String) -> Bool {
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.hasPrefix("{"),
              !value.hasPrefix("[") else {
            return false
        }
        let lower = value.lowercased()
        guard lower.hasPrefix("http://") ||
              lower.hasPrefix("https://") ||
              lower.hasPrefix("//") ||
              lower.hasPrefix("/") else {
            return false
        }
        let path = (URL(string: value.hasPrefix("//") ? "https:\(value)" : value)?.path ?? value).lowercased()
        let skippedExtensions: Set<String> = [
            "apng", "avif", "bmp", "css", "gif", "ico", "jpeg", "jpg",
            "js", "json", "png", "svg", "webp", "woff", "woff2"
        ]
        if let ext = path.split(separator: ".").last.map(String.init),
           skippedExtensions.contains(ext) {
            return false
        }
        return true
    }

    private static func dataAttributeTitleValue(in attributes: [String: String]) -> String? {
        let keys = [
            "title", "aria-label", "data-title", "data-name", "data-caption",
            "data-label", "data-headline"
        ]
        for key in keys {
            guard let value = attributes[key]?.trimmed,
                  !value.isEmpty else {
                continue
            }
            return value
        }
        return nil
    }

    private static func contextualCardTitleValue(fromHTML html: String) -> String? {
        let headingPattern = #"<h[1-6]\b[^>]*>(.*?)</h[1-6]>"#
        if let title = firstContextualTitle(inHTML: html, pattern: headingPattern) {
            return title
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"<([a-zA-Z][A-Za-z0-9:-]*)\b([^>]*)>(.*?)</\1>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 2), in: html),
                  let bodyRange = Range(match.range(at: 3), in: html) else {
                continue
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard attributesLookLikeTitleContainer(attributes),
                  let title = cleanContextualTitle(String(html[bodyRange])) else {
                continue
            }
            return title
        }
        return nil
    }

    private static func firstContextualTitle(inHTML html: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let bodyRange = Range(match.range(at: 1), in: html),
                  let title = cleanContextualTitle(String(html[bodyRange])) else {
                continue
            }
            return title
        }
        return nil
    }

    private static func attributesLookLikeTitleContainer(_ attributes: [String: String]) -> Bool {
        if let itemprop = attributes["itemprop"]?.lowercased() {
            let tokens = itemprop.split { $0 == " " || $0 == "\t" || $0 == "\n" || $0 == "\r" || $0 == "," }
            if tokens.contains(where: { ["name", "headline", "title"].contains(String($0)) }) {
                return true
            }
        }
        let keys = ["class", "id", "data-testid", "data-test-id", "data-role", "role"]
        let needles = ["title", "headline", "caption", "subject", "entry-title", "post-title", "result-title", "card-title"]
        return keys.compactMap { attributes[$0]?.lowercased() }.contains { value in
            needles.contains { value.contains($0) }
        }
    }

    private static func cleanContextualTitle(_ raw: String) -> String? {
        let title = decodeHTML(stripTags(raw)).sanitizedFilename(maxLength: 100).trimmed
        guard !title.isEmpty else { return nil }
        let lower = title.lowercased()
        let weakTitles: Set<String> = ["download", "open", "view", "more", "read more", "image", "thumbnail"]
        guard !weakTitles.contains(lower),
              !lower.hasPrefix("http://"),
              !lower.hasPrefix("https://"),
              !lower.contains("://") else {
            return nil
        }
        return title
    }

    private static func jsonLDAnchorEntries(from html: String, baseURL: URL? = nil) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let attributes = attributeValues(from: String(html[attributesRange]))
            let type = attributes["type"]?.lowercased() ?? ""
            guard type.contains("ld+json") else { continue }

            let payload = cleanJSONLDPayload(String(html[bodyRange]))
            guard let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            for candidate in jsonLDLinkCandidates(from: object) {
                let url = normalizedHref(candidate.url, baseURL: baseURL) ?? candidate.url
                guard !seen.contains(url) else { continue }
                seen.insert(url)
                var linkAttributes = candidate.attributes
                linkAttributes["href"] = url
                linkAttributes["title"] = candidate.title
                let context = [
                    candidate.title,
                    candidate.attributes["data-author-name"] ?? "",
                    candidate.attributes["data-date"] ?? ""
                ]
                    .map { $0.trimmed }
                    .filter { !$0.isEmpty }
                    .joined(separator: " ")
                entries.append(AnchorEntry(
                    attributes: linkAttributes,
                    body: candidate.title,
                    context: context,
                    contextHTML: jsonLDContextHTML(title: candidate.title, url: url, attributes: candidate.attributes)
                ))
            }
        }

        return entries
    }

    private static func jsonStateAnchorEntries(from html: String, baseURL: URL?, resolutionBaseURL: URL?) -> [AnchorEntry] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b([^>]*)>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var entries: [AnchorEntry] = []
        var seen = Set<String>()

        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }

            let attributes = attributeValues(from: String(html[attributesRange]))
            guard jsonStateScriptLooksRelevant(attributes) else { continue }

            let payload = cleanJSONStatePayload(String(html[bodyRange]))
            guard !payload.isEmpty,
                  let data = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) else {
                continue
            }

            for candidate in jsonStateLinkCandidates(from: object, baseURL: baseURL) {
                let href = normalizedHref(candidate.href, baseURL: resolutionBaseURL) ?? candidate.href
                guard !seen.contains(href) else { continue }
                seen.insert(href)

                var linkAttributes = candidate.attributes
                linkAttributes["href"] = href
                if linkAttributes["title"] == nil {
                    linkAttributes["title"] = candidate.title
                }
                entries.append(AnchorEntry(
                    attributes: linkAttributes,
                    body: candidate.title,
                    context: candidate.context,
                    contextHTML: candidate.contextHTML
                ))
            }
        }

        return entries
    }

    private static func jsonStateScriptLooksRelevant(_ attributes: [String: String]) -> Bool {
        let type = attributes["type"]?.lowercased() ?? ""
        if type.contains("ld+json") {
            return false
        }
        if type.contains("json") {
            return true
        }
        let id = attributes["id"]?.lowercased() ?? ""
        return id.contains("__next_data__") ||
            id.contains("__nuxt") ||
            id.contains("initial-state") ||
            id.contains("initial_state") ||
            id.contains("app-state") ||
            id.contains("app_state")
    }

    private static func cleanJSONStatePayload(_ raw: String) -> String {
        cleanJSONLDPayload(raw)
    }

    private static func jsonStateLinkCandidates(from value: Any, baseURL: URL?) -> [JSONStateLinkCandidate] {
        var candidates: [JSONStateLinkCandidate] = []
        jsonStateCollectCandidates(from: value, baseURL: baseURL, candidates: &candidates)
        return candidates
    }

    private static func jsonStateCollectCandidates(from value: Any, baseURL: URL?, candidates: inout [JSONStateLinkCandidate]) {
        if let array = value as? [Any] {
            for item in array {
                jsonStateCollectCandidates(from: item, baseURL: baseURL, candidates: &candidates)
            }
            return
        }

        guard let object = value as? [String: Any] else {
            return
        }

        if let candidate = jsonStateCandidate(from: object, baseURL: baseURL) {
            candidates.append(candidate)
        }

        for child in object.values {
            jsonStateCollectCandidates(from: child, baseURL: baseURL, candidates: &candidates)
        }
    }

    private static func jsonStateCandidate(from object: [String: Any], baseURL: URL?) -> JSONStateLinkCandidate? {
        let attributes = jsonStateAttributes(from: object)
        let title = jsonStateTitleValue(in: object, attributes: attributes)
        let href = jsonStateHrefValue(in: object, attributes: attributes, baseURL: baseURL)

        guard let href,
              let title,
              !title.isEmpty else {
            return nil
        }

        var linkAttributes = attributes
        linkAttributes["title"] = title
        let contextHTML = jsonStateContextHTML(title: title, href: href, attributes: linkAttributes)
        let context = [
            title,
            linkAttributes["data-author-name"] ?? "",
            linkAttributes["data-uploader-name"] ?? "",
            linkAttributes["data-date"] ?? "",
            linkAttributes["data-created-at"] ?? ""
        ]
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return JSONStateLinkCandidate(
            href: href,
            title: title,
            attributes: linkAttributes,
            context: context,
            contextHTML: contextHTML
        )
    }

    private static func jsonStateHrefValue(in object: [String: Any], attributes: [String: String], baseURL: URL?) -> String? {
        let keys = [
            "url", "href", "link", "permalink", "canonicalURL", "canonicalUrl",
            "canonical_url", "webUrl", "webURL", "web_url", "pageUrl", "pageURL",
            "page_url", "resultUrl", "resultURL", "result_url", "destinationUrl",
            "destinationURL", "destination_url", "path", "pathname", "slug"
        ]
        for key in keys {
            guard let raw = jsonStateStringValue(object[key])?.trimmed,
                  let href = dataAttributeNavigationCandidate(from: raw, baseURL: baseURL) else {
                continue
            }
            return href
        }

        return dataAttributeLinkValue(in: attributes, baseURL: baseURL)
    }

    private static func jsonStateTitleValue(in object: [String: Any], attributes: [String: String]) -> String? {
        let keys = [
            "title", "name", "headline", "caption", "label", "displayTitle",
            "display_title", "alt", "text"
        ]
        for key in keys {
            guard let raw = jsonStateStringValue(object[key])?.trimmed,
                  let title = cleanContextualTitle(raw) else {
                continue
            }
            return title
        }
        return dataAttributeTitleValue(in: attributes).flatMap(cleanContextualTitle)
    }

    private static func jsonStateAttributes(from object: [String: Any]) -> [String: String] {
        var attributes: [String: String] = [:]
        for (key, value) in object {
            guard let string = jsonStateStringValue(value)?.trimmed,
                  !string.isEmpty,
                  string.count <= 500 else {
                continue
            }

            let normalized = jsonStateAttributeName(from: key)
            guard !normalized.isEmpty else { continue }
            attributes[normalized] = string
            if normalized.hasPrefix("data-") {
                attributes[String(normalized.dropFirst("data-".count))] = string
            } else {
                attributes["data-\(normalized)"] = string
            }
        }

        jsonStateAliasPairs.forEach { alias, keys in
            guard attributes[alias] == nil else { return }
            for key in keys {
                if let value = attributes[key]?.trimmed, !value.isEmpty {
                    attributes[alias] = value
                    break
                }
            }
        }

        return DownloadMetadata.clean(attributes)
    }

    private static let jsonStateAliasPairs: [(String, [String])] = [
        ("data-id", ["id", "data-id", "post-id", "data-post-id", "gallery-id", "data-gallery-id", "video-id", "data-video-id", "artwork-id", "data-artwork-id", "illust-id", "data-illust-id", "project-id", "data-project-id"]),
        ("data-title", ["title", "data-title", "name", "data-name", "headline", "data-headline", "caption", "data-caption", "display-title", "data-display-title"]),
        ("data-name", ["name", "data-name", "title", "data-title"]),
        ("data-type", ["type", "data-type", "kind", "data-kind", "content-type", "data-content-type"]),
        ("data-url", ["url", "data-url", "href", "data-href", "permalink", "data-permalink", "canonical-url", "data-canonical-url", "page-url", "data-page-url", "result-url", "data-result-url"]),
        ("data-href", ["href", "data-href", "url", "data-url"]),
        ("data-artist-name", ["artist-name", "data-artist-name", "artist", "data-artist", "author", "data-author", "author-name", "data-author-name", "user-name", "data-user-name", "username", "data-username"]),
        ("data-uploader-name", ["uploader-name", "data-uploader-name", "uploader", "data-uploader", "author-name", "data-author-name", "channel-name", "data-channel-name"]),
        ("data-channel-name", ["channel-name", "data-channel-name", "channel", "data-channel", "uploader-name", "data-uploader-name"]),
        ("data-user-id", ["user-id", "data-user-id", "uid", "data-uid", "uploader-id", "data-uploader-id", "author-id", "data-author-id"]),
        ("data-created-at", ["created-at", "data-created-at", "date", "data-date", "published-at", "data-published-at", "upload-date", "data-upload-date"]),
        ("data-date", ["date", "data-date", "created-at", "data-created-at", "published-at", "data-published-at", "upload-date", "data-upload-date"]),
        ("data-thumbnail", ["thumbnail", "data-thumbnail", "thumbnail-url", "data-thumbnail-url", "image", "data-image"])
    ]

    private static func jsonStateAttributeName(from key: String) -> String {
        let kebab = key
            .replacingOccurrences(of: #"([a-z0-9])([A-Z])"#, with: "$1-$2", options: .regularExpression)
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
            .lowercased()
            .filter { character in
                character.isLetter || character.isNumber || character == "-"
            }
        return String(kebab)
            .replacingOccurrences(of: #"-+"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    }

    private static func jsonStateStringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return decodeHTML(string)
        }
        if let number = value as? NSNumber {
            return number.stringValue
        }
        if let urlObject = value as? [String: Any] {
            for key in ["url", "href", "path", "slug", "name", "title", "text"] {
                if let string = jsonStateStringValue(urlObject[key])?.trimmed,
                   !string.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private static func jsonStateContextHTML(title: String, href: String, attributes: [String: String]) -> String {
        var parts = [#"data-json-state="1""#, #"href="\#(href)""#, #"title="\#(title)""#]
        for key in attributes.keys.sorted() {
            guard let value = attributes[key], !value.isEmpty else { continue }
            parts.append(#"\#(key)="\#(value)""#)
        }
        return "<a \(parts.joined(separator: " "))>\(title)</a>"
    }

    private static func cleanJSONLDPayload(_ raw: String) -> String {
        decodeHTML(raw)
            .replacingOccurrences(of: "<!--", with: "")
            .replacingOccurrences(of: "-->", with: "")
            .replacingOccurrences(of: "//<![CDATA[", with: "")
            .replacingOccurrences(of: "//]]>", with: "")
            .trimmed
    }

    private static func jsonLDLinkCandidates(
        from value: Any,
        blocked: Bool = false,
        inListContext: Bool = false
    ) -> [JSONLDLinkCandidate] {
        if let array = value as? [Any] {
            return array.flatMap { jsonLDLinkCandidates(from: $0, blocked: blocked, inListContext: inListContext) }
        }

        guard let object = value as? [String: Any] else {
            return []
        }

        let typeNames = jsonLDTypeNames(object["@type"]).map { $0.lowercased() }
        let currentBlocked = blocked || typeNames.contains("breadcrumblist") || typeNames.contains("searchaction")
        let childListContext = inListContext || typeNames.contains("itemlist") || object.keys.contains { $0.caseInsensitiveCompare("itemListElement") == .orderedSame }
        var candidates: [JSONLDLinkCandidate] = []

        if !currentBlocked,
           jsonLDShouldEmitCandidate(types: typeNames, inListContext: inListContext),
           let url = jsonLDURLValue(in: object),
           let title = jsonLDTitleValue(in: object) {
            candidates.append(JSONLDLinkCandidate(
                url: url,
                title: title,
                attributes: jsonLDSemanticAttributes(from: object),
                contextHTML: jsonLDContextHTML(title: title, url: url, attributes: jsonLDSemanticAttributes(from: object))
            ))
        }

        for child in object.values {
            candidates.append(contentsOf: jsonLDLinkCandidates(from: child, blocked: currentBlocked, inListContext: childListContext))
        }

        return candidates
    }

    private static func jsonLDShouldEmitCandidate(types: [String], inListContext: Bool) -> Bool {
        let blockedTypes = [
            "website", "searchaction", "breadcrumblist", "organization",
            "person", "place", "brand", "aggregateoffer", "offer"
        ]
        if types.contains(where: { blockedTypes.contains($0) }) {
            return false
        }
        let contentTypes = [
            "article", "blogposting", "creativework", "comicissue", "comicstory",
            "episode", "imagegallery", "imageobject", "mediaobject", "movie",
            "musicrecording", "newsarticle", "photograph", "product",
            "socialmediaposting", "videoobject", "webpage"
        ]
        return types.contains(where: { contentTypes.contains($0) }) ||
            (inListContext && !types.contains("itemlist"))
    }

    private static func jsonLDTypeNames(_ value: Any?) -> [String] {
        if let string = value as? String {
            return [string]
        }
        if let array = value as? [Any] {
            return array.compactMap { $0 as? String }
        }
        return []
    }

    private static func jsonLDURLValue(in object: [String: Any]) -> String? {
        for key in ["url", "mainEntityOfPage", "@id"] {
            guard let value = jsonLDStringValue(object[key])?.trimmed,
                  !value.isEmpty,
                  !value.hasPrefix("#"),
                  !value.lowercased().contains("schema.org") else {
                continue
            }
            return value
        }
        return nil
    }

    private static func jsonLDTitleValue(in object: [String: Any]) -> String? {
        for key in ["name", "headline", "title", "caption"] {
            guard let value = jsonLDStringValue(object[key])?.trimmed,
                  !value.isEmpty else {
                continue
            }
            return decodeHTML(value).sanitizedFilename(maxLength: 100)
        }
        return nil
    }

    private static func jsonLDStringValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string
        }
        if let object = value as? [String: Any] {
            for key in ["url", "@id", "name"] {
                if let string = object[key] as? String,
                   !string.trimmed.isEmpty {
                    return string
                }
            }
        }
        if let array = value as? [Any] {
            for item in array {
                if let string = jsonLDStringValue(item),
                   !string.trimmed.isEmpty {
                    return string
                }
            }
        }
        return nil
    }

    private static func jsonLDNameValue(_ value: Any?) -> String? {
        if let string = value as? String {
            return string.trimmed.isEmpty ? nil : string
        }
        if let object = value as? [String: Any] {
            return jsonLDStringValue(object["name"])
        }
        if let array = value as? [Any] {
            return array.compactMap { jsonLDNameValue($0) }.first
        }
        return nil
    }

    private static func jsonLDSemanticAttributes(from object: [String: Any]) -> [String: String] {
        var attributes: [String: String] = [:]
        if let author = jsonLDNameValue(object["author"]) {
            attributes["data-author-name"] = author
            attributes["data-uploader-name"] = author
            attributes["data-channel-name"] = author
        }
        if let creator = jsonLDNameValue(object["creator"]) {
            attributes["data-creator-name"] = creator
        }
        if let publisher = jsonLDNameValue(object["publisher"]) {
            attributes["data-publisher-name"] = publisher
        }
        if let date = jsonLDStringValue(object["datePublished"] ?? object["uploadDate"] ?? object["dateCreated"] ?? object["dateModified"]) {
            attributes["data-date"] = date
            attributes["data-created-at"] = date
        }
        if let image = jsonLDStringValue(object["thumbnailUrl"] ?? object["image"]) {
            attributes["data-thumbnail"] = image
        }
        return DownloadMetadata.clean(attributes)
    }

    private static func jsonLDContextHTML(title: String, url: String, attributes: [String: String]) -> String {
        var parts = [#"data-jsonld="1""#, #"href="\#(url)""#, #"title="\#(title)""#]
        for key in attributes.keys.sorted() {
            guard let value = attributes[key], !value.isEmpty else { continue }
            parts.append(#"\#(key)="\#(value)""#)
        }
        return "<a \(parts.joined(separator: " "))>\(title)</a>"
    }

    private static func contextSlice(around range: Range<String.Index>, in html: String) -> String {
        let prefixDistance = html.distance(from: html.startIndex, to: range.lowerBound)
        let suffixDistance = html.distance(from: range.upperBound, to: html.endIndex)
        let before = min(600, prefixDistance)
        let after = min(600, suffixDistance)
        let start = html.index(range.lowerBound, offsetBy: -before)
        let end = html.index(range.upperBound, offsetBy: after)
        return String(html[start..<end])
    }

    private static func documentBaseURL(from html: String, fallback: URL) -> URL {
        guard let regex = try? NSRegularExpression(
            pattern: #"<base\b([^>]*)>"#,
            options: [.caseInsensitive]
        ) else {
            return fallback
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attributesRange]))
            guard let href = attributes["href"]?.trimmed,
                  let url = URL(string: href, relativeTo: fallback)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            return url
        }
        return fallback
    }

    private static func normalizedHref(_ href: String?, baseURL: URL?) -> String? {
        guard let href = href?.trimmed,
              let baseURL,
              let absolute = resolve(href: href, baseURL: baseURL) else {
            return nil
        }
        return absolute.absoluteString
    }

    private static func resolve(href: String, baseURL: URL) -> URL? {
        guard !href.isEmpty,
              !href.hasPrefix("#"),
              !href.lowercased().hasPrefix("javascript:"),
              !href.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        return URL(string: href, relativeTo: baseURL)?.absoluteURL
    }

    private static func isUseful(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        return true
    }

    private static func googleSearchTargetURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        guard isGoogleHost(host) else {
            return isUseful(url) ? url : nil
        }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let targetNames = ["q", "url", "u", "imgurl"]
        for name in targetNames {
            guard let raw = queryValue(name, in: components.queryItems ?? [])?.trimmed,
                  !raw.isEmpty else {
                continue
            }
            let decoded = raw.removingPercentEncoding ?? raw
            let candidates = [decoded, raw]
            for candidate in candidates {
                let target: URL?
                if candidate.hasPrefix("//") {
                    target = URL(string: "\(url.scheme ?? "https"):\(candidate)")
                } else if candidate.contains("://") {
                    target = URL(string: candidate)
                } else {
                    target = nil
                }
                guard let target,
                      isUseful(target),
                      let targetHost = target.host?.lowercased(),
                      !isGoogleHost(targetHost) else {
                    continue
                }
                return target
            }
        }
        return nil
    }

    private static func googleSearchQueueURL(from url: URL) -> URL {
        youtubeQueueURL(from: url) ?? url
    }

    private static func displayTitle(for anchor: AnchorEntry, fallbackURL: URL) -> String {
        displayTitle(for: anchor, fallback: fallbackURL.lastPathComponentOrHost)
    }

    private static func displayTitle(for anchor: AnchorEntry, fallback: String) -> String {
        let raw = [
            anchor.attributes["title"],
            anchor.attributes["aria-label"],
            embeddedImageTitle(from: anchor.body),
            stripTags(anchor.body),
            contextualCardTitleValue(fromHTML: anchor.contextHTML)
        ]
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty } ?? fallback

        let title = decodeHTML(raw).sanitizedFilename(maxLength: 100)
        return title == "download" ? fallback.sanitizedFilename(maxLength: 100) : title
    }

    private static func hitomiResultMetadata(title: String, anchor: AnchorEntry) -> String {
        let textParts = [
            title,
            anchor.attributes["title"],
            anchor.attributes["aria-label"],
            embeddedImageTitle(from: anchor.body),
            stripTags(anchor.body),
            anchor.context
        ]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
        let dateTokens = hitomiMetadataDateValues(fromHTML: anchor.contextHTML).map { "date:\($0)" }
        let pageTokens = hitomiMetadataPageCounts(fromHTML: anchor.contextHTML).map { "pages:\($0)" }
        let semanticTokens = searchContributorMetadata(anchor: anchor)
            .filter { !$0.value.isEmpty }
            .map { "\($0.key):\($0.value)" }
        let metadataTokens = hitomiMetadataTokens(fromHTML: anchor.contextHTML) + dateTokens + pageTokens + semanticTokens
        return uniqueStrings(textParts + metadataTokens).joined(separator: " ")
    }

    private static func hitomiResultMetadataFields(anchor: AnchorEntry) -> [String: String] {
        var fields: [String: [String]] = [:]
        for (key, value) in hitomiMetadataFieldPairs(fromHTML: anchor.contextHTML) {
            fields[key, default: []].append(value)
        }
        for value in hitomiMetadataDateValues(fromHTML: anchor.contextHTML) {
            fields["date", default: []].append(value)
        }
        for value in hitomiMetadataPageCounts(fromHTML: anchor.contextHTML) {
            fields["pages", default: []].append(value)
        }
        for (key, value) in searchContributorMetadata(anchor: anchor) where !value.isEmpty {
            fields[key, default: []].append(value)
        }
        return fields.reduce(into: [:]) { result, entry in
            let values = uniqueStrings(entry.value)
            guard !values.isEmpty else { return }
            result[entry.key] = values.joined(separator: ", ")
        }
    }

    private static func hitomiMetadataTokens(fromHTML html: String) -> [String] {
        var tokens: [String] = []

        let pathPattern = #"/(tag|artist|group|series|parody|character|type|language)/([^\"'<>\s?#]+)"#
        tokens.append(contentsOf: captures(in: html, pattern: pathPattern).compactMap { groups in
            guard groups.count == 2 else { return nil }
            return hitomiMetadataToken(kind: groups[0], rawValue: groups[1])
        })

        tokens.append(contentsOf: matches(in: html, pattern: #"index-([A-Za-z][A-Za-z_-]*)\.html"#).map {
            "language:\(hitomiMetadataValue($0))"
        })

        return uniqueStrings(tokens)
    }

    private static func hitomiMetadataFieldPairs(fromHTML html: String) -> [(String, String)] {
        let pathPattern = #"/(tag|artist|group|series|parody|character|type|language)/([^\"'<>\s?#]+)"#
        var pairs = captures(in: html, pattern: pathPattern).compactMap { groups -> (String, String)? in
            guard groups.count == 2 else { return nil }
            let kind = groups[0].lowercased()
            let value = hitomiMetadataValue(groups[1])
            guard !value.isEmpty else { return nil }
            switch kind {
            case "series":
                return ("parody", value)
            default:
                return (kind, value)
            }
        }

        pairs.append(contentsOf: matches(in: html, pattern: #"index-([A-Za-z][A-Za-z_-]*)\.html"#).map {
            ("language", hitomiMetadataValue($0))
        })

        return pairs
    }

    private static func hitomiMetadataDateValues(fromHTML html: String) -> [String] {
        let decoded = decodeHTML(html)
        let patterns = [
            #"\b(20[0-9]{2})[-./](0?[1-9]|1[0-2])[-./](0?[1-9]|[12][0-9]|3[01])\b"#,
            #"\b(0?[1-9]|[12][0-9]|3[01])[-./](0?[1-9]|1[0-2])[-./](20[0-9]{2})\b"#
        ]
        var dates: [String] = []
        for pattern in patterns {
            for groups in captures(in: decoded, pattern: pattern) {
                guard groups.count == 3 else { continue }
                let year: Int?
                let month: Int?
                let day: Int?
                if groups[0].count == 4 {
                    year = Int(groups[0])
                    month = Int(groups[1])
                    day = Int(groups[2])
                } else {
                    day = Int(groups[0])
                    month = Int(groups[1])
                    year = Int(groups[2])
                }
                guard let year, let month, let day,
                      (2000...2099).contains(year),
                      (1...12).contains(month),
                      (1...31).contains(day) else {
                    continue
                }
                dates.append(String(format: "%04d-%02d-%02d", year, month, day))
            }
        }
        return uniqueStrings(dates)
    }

    private static func hitomiMetadataPageCounts(fromHTML html: String) -> [String] {
        let decoded = decodeHTML(html)
        let patterns = [
            #"\b([1-9][0-9]{0,4})\s*(?:pages?|p\.)\b"#,
            #"\b(?:pages?|page_count|pagecount|total_pages)\s*[:=]\s*([1-9][0-9]{0,4})\b"#,
            #"\b([1-9][0-9]{0,4})\s*(?:페이지|쪽)\b"#
        ]
        var counts: [String] = []
        for pattern in patterns {
            counts.append(contentsOf: matches(in: decoded, pattern: pattern).compactMap { raw in
                guard let value = Int(raw.replacingOccurrences(of: ",", with: "")),
                      value > 0 else {
                    return nil
                }
                return String(value)
            })
        }
        return uniqueStrings(counts)
    }

    private static func hitomiMetadataToken(kind rawKind: String, rawValue: String) -> String? {
        let kind = rawKind.lowercased()
        let value = hitomiMetadataValue(rawValue)
        guard !value.isEmpty else { return nil }
        switch kind {
        case "tag":
            return value
        case "artist", "group", "character", "type", "language":
            return "\(kind):\(value)"
        case "series", "parody":
            return "parody:\(value)"
        default:
            return nil
        }
    }

    private static func hitomiMetadataValue(_ raw: String) -> String {
        let withoutExtension = raw
            .replacingOccurrences(of: #"\.html.*$"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"-all$"#, with: "", options: .regularExpression)
        let decoded = withoutExtension.removingPercentEncoding ?? withoutExtension
        return decodeHTML(decoded)
            .replacingOccurrences(of: "_", with: " ")
            .trimmed
    }

    private static func hitomiGalleryID(from url: URL) -> String? {
        let absolute = url.absoluteString
        let patterns = [
            #"hitomi\.la/(?:reader|galleries)/([0-9]+)"#,
            #"-([0-9]+)\.html(?:[#?].*)?$"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }
            let range = NSRange(absolute.startIndex..<absolute.endIndex, in: absolute)
            if let match = regex.firstMatch(in: absolute, range: range),
               let capture = Range(match.range(at: 1), in: absolute) {
                return String(absolute[capture])
            }
        }
        return nil
    }

    private static func nhentaiGalleryID(from url: URL) -> String? {
        firstCapture(in: url.path, pattern: #"/(?:g|gallery|api/gallery)/([0-9]+)"#)
    }

    private static func nhentaiGalleryURL(galleryID: String, baseURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isNHentaiHost(baseURL.host?.lowercased() ?? "") ? baseURL.host : "nhentai.net"
        components.path = "/g/\(galleryID)/"
        return components.url
    }

    private static func ehentaiGalleryID(from url: URL) -> (id: String, token: String, isLoFi: Bool)? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let normalizedParts: [String]
        let isLoFi = parts.first?.lowercased() == "lofi"
        if isLoFi {
            normalizedParts = Array(parts.dropFirst())
        } else {
            normalizedParts = parts
        }
        guard normalizedParts.count >= 3,
              normalizedParts[0].lowercased() == "g",
              normalizedParts[1].range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let token = normalizedParts[2].trimmed
        guard !token.isEmpty else { return nil }
        return (normalizedParts[1], token, isLoFi)
    }

    private static func ehentaiGalleryURL(gallery: (id: String, token: String, isLoFi: Bool), sourceURL: URL, baseURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = isEHentaiHost(sourceURL.host?.lowercased() ?? "") ? sourceURL.host : baseURL.host
        components.path = gallery.isLoFi ? "/lofi/g/\(gallery.id)/\(gallery.token)/" : "/g/\(gallery.id)/\(gallery.token)/"
        return components.url
    }

    private static func nozomiPostID(from url: URL) -> String? {
        firstCapture(in: url.path, pattern: #"/post/([0-9]+)(?:\.html)?/?$"#)
    }

    private static func nozomiPostURL(postID: String, baseURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = isNozomiHost(baseURL.host?.lowercased() ?? "") ? baseURL.host : "nozomi.la"
        components.path = "/post/\(postID).html"
        return components.url
    }

    private static func artStationProjectID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2,
              ["artwork", "projects"].contains(parts[0].lowercased()) else {
            return nil
        }
        let cleaned = (parts[1] as NSString).deletingPathExtension.trimmed
        return cleaned.isEmpty ? nil : cleaned
    }

    private static func imgurContent(from url: URL) -> (id: String, key: String, path: String)? {
        guard let host = url.host?.lowercased(), isImgurHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first?.trimmed, !first.isEmpty else { return nil }

        let lowerFirst = first.lowercased()
        if ["a", "gallery"].contains(lowerFirst), parts.count >= 2 {
            let id = (parts[1] as NSString).deletingPathExtension.trimmed
            guard isValidImgurID(id) else { return nil }
            return (id, "\(lowerFirst):\(id)", "/\(lowerFirst)/\(id)")
        }

        if lowerFirst == "t", parts.count >= 3 {
            let tag = parts[1].trimmed
            let id = (parts[2] as NSString).deletingPathExtension.trimmed
            guard isValidImgurID(tag), isValidImgurID(id) else { return nil }
            return (id, "t:\(tag):\(id)", "/t/\(tag)/\(id)")
        }

        let reserved: Set<String> = [
            "about", "account", "advertise", "apps", "blog", "download",
            "explore", "jobs", "privacy", "register", "search", "signin",
            "signout", "terms", "tos", "upload"
        ]
        let id = (first as NSString).deletingPathExtension.trimmed
        guard parts.count == 1, !reserved.contains(id.lowercased()), isValidImgurID(id) else {
            return nil
        }
        return (id, "media:\(id)", "/\(id)")
    }

    private static func tumblrBlogName(from url: URL) -> String? {
        if let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems {
            for name in ["redirect_to", "url"] {
                guard let nested = items.first(where: { $0.name.lowercased() == name })?.value,
                      let nestedURL = tumblrRedirectURL(from: nested, sourceURL: url),
                      nestedURL.absoluteString != url.absoluteString,
                      let nestedName = tumblrBlogName(from: nestedURL) else {
                    continue
                }
                return nestedName
            }
        }

        guard let host = url.host?.lowercased(), isTumblrHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)

        if let index = parts.firstIndex(where: { $0.lowercased() == "blog" }),
           index + 2 < parts.count,
           parts[index + 1].lowercased() == "view" {
            return cleanTumblrBlogName(parts[index + 2])
        }

        if let index = parts.firstIndex(where: { $0.lowercased() == "dashboard" }),
           index + 2 < parts.count,
           parts[index + 1].lowercased() == "blog" {
            return cleanTumblrBlogName(parts[index + 2])
        }

        if let index = parts.firstIndex(where: { $0.lowercased() == "login_required" }),
           index + 1 < parts.count {
            return cleanTumblrBlogName(parts[index + 1])
        }

        if host == "tumblr.com" || host == "www.tumblr.com" || host == "tumblr.test" || host == "www.tumblr.test" {
            guard let first = parts.first else { return nil }
            let reserved: Set<String> = [
                "about", "blog", "dashboard", "explore", "login", "privacy",
                "register", "search", "settings", "tagged", "terms"
            ]
            return reserved.contains(first.lowercased()) ? nil : cleanTumblrBlogName(first)
        }

        guard (host.hasSuffix(".tumblr.com") || host.hasSuffix(".tumblr.test")),
              let subdomain = host.split(separator: ".").first.map(String.init),
              !["assets", "static", "www"].contains(subdomain.lowercased()) else {
            return nil
        }
        return cleanTumblrBlogName(subdomain)
    }

    private static func tumblrRedirectURL(from raw: String, sourceURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }
        if value.hasPrefix("http://") || value.hasPrefix("https://") {
            return URL(string: value)
        }
        if value.hasPrefix("//") {
            return URL(string: "\(sourceURL.scheme ?? "https"):\(value)")
        }
        let host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "tumblr.test" : "tumblr.com"
        return URL(string: value, relativeTo: URL(string: "https://\(host)")!)?.absoluteURL
    }

    private static func tumblrBlogURL(blog: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "www.tumblr.test" : "www.tumblr.com"
        components.path = "/\(blog)"
        return components.url
    }

    private static func fourChanThread(from url: URL) -> (board: String, id: String)? {
        guard let host = url.host?.lowercased(), isFourChanHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3,
              parts[1].lowercased() == "thread" else {
            return nil
        }

        let board = parts[0].trimmed
        let id = (parts[2] as NSString).deletingPathExtension.trimmed
        guard !board.isEmpty, !id.isEmpty, id.allSatisfy(\.isNumber) else {
            return nil
        }
        return (board, id)
    }

    private static func fourChanThreadURL(thread: (board: String, id: String), sourceURL: URL) -> URL? {
        let sourceHost = sourceURL.host?.lowercased() ?? ""
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        if sourceHost.hasSuffix(".test") {
            components.host = sourceHost.contains("4channel") ? "boards.4channel.test" : "boards.4chan.test"
        } else {
            components.host = sourceHost.contains("4channel") ? "boards.4channel.org" : "boards.4chan.org"
        }
        components.path = "/\(thread.board)/thread/\(thread.id)"
        return components.url
    }

    private static func wikiArtArtistSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), isWikiArtHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2, parts[0].lowercased() == "en" else {
            return nil
        }

        let artist = parts[1].trimmed
        let reserved: Set<String> = [
            "app", "artists-by-art-movement", "paintings-by-genre",
            "paintings-by-style", "search"
        ]
        guard isValidPathSlug(artist), !reserved.contains(artist.lowercased()) else {
            return nil
        }
        return artist
    }

    private static func wikiArtArtistURL(artist: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        let sourceHost = sourceURL.host?.lowercased() ?? ""
        components.host = sourceHost == "wikiart.test" || sourceHost.hasSuffix(".wikiart.test") ? "wikiart.test" : "www.wikiart.org"
        components.path = "/en/\(artist)"
        return components.url
    }

    private static func hentaiCosplayContent(from url: URL) -> (kind: String, slug: String)? {
        guard let host = url.host?.lowercased(), isHentaiCosplayHost(host) else { return nil }
        let loweredPath = url.path.lowercased()
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let isPageOnly = parts.count == 2 &&
            parts[0].lowercased() == "page" &&
            parts[1].allSatisfy(\.isNumber)
        guard !loweredPath.contains("/attachment/"),
              !isPageOnly else {
            return nil
        }

        for kind in ["story", "image", "video"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == kind }),
                  index + 1 < parts.count else {
                continue
            }
            let slug = (parts[index + 1] as NSString).deletingPathExtension.trimmed
            guard isValidPathSlug(slug) else { return nil }
            return (kind, slug)
        }
        return nil
    }

    private static func myReadingMangaPostPath(from url: URL) -> String? {
        guard let host = url.host?.lowercased(), isMyReadingMangaHost(host) else { return nil }
        var parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first?.lowercased() else { return nil }

        let reserved: Set<String> = [
            "author", "category", "comments", "feed", "page", "tag",
            "wp-admin", "wp-content", "wp-includes", "wp-json"
        ]
        guard !reserved.contains(first) else { return nil }
        if first == "search" || isMediaFileExtension(url.pathExtension) {
            return nil
        }

        if parts.count >= 2,
           parts[parts.count - 2].lowercased() == "page",
           parts.last?.allSatisfy(\.isNumber) == true {
            parts.removeLast(2)
        }
        guard !parts.isEmpty else { return nil }
        return "/" + parts.joined(separator: "/") + "/"
    }

    private static func lusciousContent(from url: URL) -> (id: String, key: String, path: String)? {
        guard let host = url.host?.lowercased(), isLusciousHost(host) else { return nil }
        if let albumID = LusciousResolver.albumID(from: url) {
            return (albumID, "album:\(albumID)", "/albums/\(albumID)")
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "videos" }),
              index + 1 < parts.count else {
            return nil
        }
        let slug = (parts[index + 1] as NSString).deletingPathExtension.trimmed
        guard isValidPathSlug(slug) else { return nil }
        return (slug, "video:\(slug)", "/videos/\(slug)")
    }

    private static func bdsmlrURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isBDSMlrHost(host) else { return nil }
        if let postID = BDSMlrResolver.postID(from: url),
           let blog = BDSMlrResolver.blogName(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = "\(blog).\(host.hasSuffix(".test") ? "bdsmlr.test" : "bdsmlr.com")"
            components.path = "/post/\(postID)"
            return components.url
        }

        if let blog = BDSMlrResolver.blogName(from: url) {
            return BDSMlrResolver.canonicalBlogURL(blogName: blog, sourceURL: url)
        }
        return nil
    }

    private static func bdsmlrKey(for url: URL) -> String {
        if let postID = BDSMlrResolver.postID(from: url) {
            return "post:\(postID)"
        }
        return "blog:\(url.host?.lowercased() ?? url.absoluteString.lowercased())"
    }

    private static func narouURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isNarouHost(host),
              let ncode = NarouResolver.ncode(from: url) else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? host : (host.contains("novel18") ? "novel18.syosetu.com" : "ncode.syosetu.com")
        if let chapter = NarouResolver.chapterNumber(from: url) {
            components.path = "/\(ncode)/\(chapter)/"
        } else {
            components.path = "/\(ncode)/"
        }
        return components.url
    }

    private static func narouKey(for url: URL) -> String {
        let ncode = NarouResolver.ncode(from: url) ?? url.path
        if let chapter = NarouResolver.chapterNumber(from: url) {
            return "\(ncode):\(chapter)"
        }
        return ncode
    }

    private static func kakuyomuURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isKakuyomuHost(host),
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

    private static func kakuyomuKey(for url: URL) -> String {
        let work = KakuyomuResolver.workID(from: url) ?? url.path
        if let episode = KakuyomuResolver.episodeID(from: url) {
            return "\(work):\(episode)"
        }
        return work
    }

    private static func hamelnURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isHamelnHost(host),
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

    private static func hamelnKey(for url: URL) -> String {
        let novel = HamelnResolver.novelID(from: url) ?? url.path
        if let page = HamelnResolver.pageNumber(from: url) {
            return "\(novel):\(page)"
        }
        return novel
    }

    private static func comicWalkerURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isComicWalkerHost(host) else { return nil }
        let canonicalHost = host.hasSuffix(".test") ? "comic-walker.test" : "comic-walker.com"

        if ComicWalkerResolver.episodeID(from: url) != nil {
            return ComicWalkerResolver.canonicalInputURL(for: url)
        }

        guard ComicWalkerResolver.workID(from: url) != nil,
              let clean = cleanedURL(url) else {
            return nil
        }
        var components = URLComponents(url: clean, resolvingAgainstBaseURL: false)
        components?.host = canonicalHost
        return components?.url
    }

    private static func comicWalkerKey(for url: URL) -> String {
        if let episode = ComicWalkerResolver.episodeID(from: url) {
            return "episode:\(episode)"
        }
        if let work = ComicWalkerResolver.workID(from: url) {
            return "work:\(work)"
        }
        return url.absoluteString.lowercased()
    }

    private static func naverPostURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isNaverPostHost(host),
              NaverPostResolver.isViewerURL(url) || NaverPostResolver.isCollectionURL(url),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.host = host.hasSuffix(".test") ? "post.naver.test" : "post.naver.com"
        components.fragment = nil
        return components.url
    }

    private static func naverPostKey(for url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let volume = items.first { $0.name == "volumeNo" }?.value
        let member = items.first { $0.name == "memberNo" }?.value
        let series = items.first { $0.name == "seriesNo" }?.value
        if let volume {
            return "volume:\(volume)"
        }
        if let member, let series {
            return "series:\(member):\(series)"
        }
        if let member {
            return "member:\(member)"
        }
        return url.absoluteString.lowercased()
    }

    private static func webtoonURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isWebtoonHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        let episode = queryValue("episode_no", in: items)
        guard episode != nil || url.path.lowercased().contains("/viewer") else {
            return nil
        }
        components.host = host.hasSuffix(".test") ? "webtoons.test" : "www.webtoons.com"
        components.fragment = nil
        components.queryItems = items.filter { ["title_no", "episode_no"].contains($0.name.lowercased()) }
        return components.url
    }

    private static func webtoonKey(for url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let title = queryValue("title_no", in: items) ?? "title"
        let episode = queryValue("episode_no", in: items) ?? url.path
        return "\(title):\(episode)"
    }

    private static func naverWebtoonURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isNaverWebtoonHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let items = components.queryItems ?? []
        guard let titleID = queryValue("titleId", in: items),
              let episodeNo = queryValue("no", in: items) else {
            return nil
        }
        components.host = host.hasSuffix(".test") ? "comic.naver.test" : "comic.naver.com"
        components.path = "/webtoon/detail"
        components.fragment = nil
        components.queryItems = [
            URLQueryItem(name: "titleId", value: titleID),
            URLQueryItem(name: "no", value: episodeNo)
        ]
        return components.url
    }

    private static func naverWebtoonKey(for url: URL) -> String {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return "\(queryValue("titleId", in: items) ?? "title"):\(queryValue("no", in: items) ?? "episode")"
    }

    private static func naverCafeURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isNaverCafeHost(host),
              let id = NaverCafeResolver.articleID(from: url) else {
            return nil
        }

        if id.clubID != nil {
            return NaverCafeResolver.mobileArticleURL(for: id, sourceURL: url)
        }

        guard let cafeName = id.cafeName else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host.hasSuffix(".test") ? "cafe.naver.test" : "cafe.naver.com"
        components.path = "/\(cafeName)/\(id.articleID)"
        return components.url
    }

    private static func naverCafeKey(for url: URL) -> String {
        guard let id = NaverCafeResolver.articleID(from: url) else {
            return url.absoluteString.lowercased()
        }
        return "\(id.clubID ?? id.cafeName ?? "cafe"):\(id.articleID)"
    }

    private static func pixivComicURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isPixivComicHost(host) else { return nil }
        let canonicalHost = host.hasSuffix(".test") ? "comic.pixiv.test" : "comic.pixiv.net"

        if let episodeID = PixivComicResolver.episodeID(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = canonicalHost
            components.path = "/viewer/stories/\(episodeID)"
            return components.url
        }

        guard let workID = PixivComicResolver.workID(from: url) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = canonicalHost
        components.path = "/works/\(workID)"
        return components.url
    }

    private static func pixivComicKey(for url: URL) -> String {
        if let episodeID = PixivComicResolver.episodeID(from: url) {
            return "episode:\(episodeID)"
        }
        if let workID = PixivComicResolver.workID(from: url) {
            return "work:\(workID)"
        }
        return url.absoluteString.lowercased()
    }

    private static func kakaoPageURL(from url: URL) -> URL? {
        KakaoPageResolver.canonicalURL(for: url)
    }

    private static func kakaoPageKey(for url: URL) -> String {
        if let ids = KakaoPageResolver.viewerIDs(from: url) {
            return "viewer:\(ids.seriesID):\(ids.productID)"
        }
        if let seriesID = KakaoPageResolver.seriesID(from: url) {
            return "series:\(seriesID)"
        }
        return url.absoluteString.lowercased()
    }

    private static func kakaoWebtoonURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isKakaoWebtoonHost(host) else { return nil }
        let canonicalHost = host.hasSuffix(".test") ? "webtoon.kakao.test" : "webtoon.kakao.com"

        if let episode = KakaoWebtoonResolver.viewerEpisode(from: url) {
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = canonicalHost
            components.path = "/viewer/\(episode.seoID)/\(episode.episodeID)"
            return components.url
        }

        guard let contentID = KakaoWebtoonResolver.contentID(fromPath: url.path) else {
            return nil
        }
        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = canonicalHost
        components.path = "/content/\(contentID)"
        return components.url
    }

    private static func kakaoWebtoonKey(for url: URL) -> String {
        if let episode = KakaoWebtoonResolver.viewerEpisode(from: url) {
            return "viewer:\(episode.seoID):\(episode.episodeID)"
        }
        if let contentID = KakaoWebtoonResolver.contentID(fromPath: url.path) {
            return "content:\(contentID)"
        }
        return url.absoluteString.lowercased()
    }

    private static func fediverseURL(from url: URL) -> URL? {
        guard let service = FediverseResolver.service(for: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host

        switch service {
        case .mastodon:
            if let statusID = FediverseResolver.mastodonStatusID(from: url) {
                components.path = "/web/statuses/\(statusID)"
                return components.url
            }
            if let accountID = FediverseResolver.mastodonAccountID(from: url) {
                components.path = "/web/accounts/\(accountID)"
                return components.url
            }
            guard let username = fediverseUsername(FediverseResolver.mastodonUsername(from: url)) else {
                return nil
            }
            components.path = "/@\(username)"
            return components.url

        case .misskey:
            if let noteID = FediverseResolver.misskeyNoteID(from: url) {
                components.path = "/notes/\(noteID)"
                return components.url
            }
            guard let username = fediverseUsername(FediverseResolver.misskeyUsername(from: url)) else {
                return nil
            }
            components.path = "/@\(username)"
            return components.url
        }
    }

    private static func fediverseKey(for url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if let statusID = FediverseResolver.mastodonStatusID(from: url) {
            return "\(host):mastodon-status:\(statusID)"
        }
        if let accountID = FediverseResolver.mastodonAccountID(from: url) {
            return "\(host):mastodon-account:\(accountID)"
        }
        if let noteID = FediverseResolver.misskeyNoteID(from: url) {
            return "\(host):misskey-note:\(noteID)"
        }
        if let username = FediverseResolver.mastodonUsername(from: url) ?? FediverseResolver.misskeyUsername(from: url) {
            return "\(host):user:\(username.lowercased())"
        }
        return url.absoluteString.lowercased()
    }

    private static func fediverseUsername(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let username = raw.trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        guard !username.isEmpty,
              !["about", "api", "auth", "deck", "explore", "filters", "home", "notifications", "public", "search", "settings", "share", "tags", "web"].contains(username.lowercased()) else {
            return nil
        }
        return username
    }

    private static func cleanedURL(_ url: URL, path: String? = nil) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        if let path {
            components.path = path
        }
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func waybackMachineQueueURL(from url: URL, targetURL: URL) -> URL? {
        let path = url.path.removingPercentEncoding ?? url.path
        if path.lowercased() == "/cdx/search/cdx" {
            return WaybackMachineResolver.cdxAPIURL(targetURL: targetURL, sourceURL: url)
        }

        guard path.hasPrefix("/web/") else { return nil }
        let rest = String(path.dropFirst("/web/".count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let token = String(rest[..<slash])
        guard token == "*" ||
                token.range(of: #"^[0-9]{1,14}[A-Za-z_]*$"#, options: .regularExpression) != nil else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = url.host?.lowercased().hasSuffix(".test") == true ? "web.archive.org.test" : "web.archive.org"
        components.path = "/web/\(token)/\(targetURL.absoluteString)"
        return components.url
    }

    private static func waybackTimestamp(from url: URL) -> String? {
        let path = url.path.removingPercentEncoding ?? url.path
        guard path.hasPrefix("/web/") else { return nil }
        let rest = String(path.dropFirst("/web/".count))
        guard let slash = rest.firstIndex(of: "/") else { return nil }
        let token = String(rest[..<slash])
        guard let timestamp = firstCapture(in: token, pattern: #"^([0-9]{1,14})"#),
              !timestamp.isEmpty else {
            return nil
        }
        return timestamp
    }

    private static func waybackDate(from timestamp: String) -> String? {
        guard timestamp.count >= 8 else { return nil }
        let year = String(timestamp.prefix(4))
        let monthStart = timestamp.index(timestamp.startIndex, offsetBy: 4)
        let monthEnd = timestamp.index(monthStart, offsetBy: 2)
        let dayEnd = timestamp.index(monthEnd, offsetBy: 2)
        return "\(year)-\(timestamp[monthStart..<monthEnd])-\(timestamp[monthEnd..<dayEnd])"
    }

    private static func vimeoVideoURL(id: String, sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().contains("test") == true ? "vimeo.test" : "vimeo.com"
        components.path = "/\(id)"
        return components.url
    }

    private static func soundCloudTrackURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(), isSoundCloudHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else { return nil }

        let first = parts[0].lowercased()
        let second = parts[1].lowercased()
        guard !["discover", "search", "you", "stream", "charts", "stations", "upload", "pages"].contains(first),
              !["sets", "albums", "tracks", "likes", "reposts", "popular-tracks"].contains(second),
              !parts[0].isEmpty,
              !parts[1].isEmpty else {
            return nil
        }

        return cleanedURL(url, path: "/\(parts[0])/\(parts[1])")
    }

    private static func soundCloudTrackKey(for url: URL) -> String {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 2 else {
            return URLIdentity.normalize(url.absoluteString)
        }
        return "\(parts[0])/\(parts[1])"
    }

    private static func tikTokVideoURL(id: String, sourceURL: URL) -> URL? {
        let parts = sourceURL.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if let markerIndex = parts.firstIndex(where: { ["video", "v"].contains($0.lowercased()) }),
           markerIndex + 1 < parts.count {
            let prefix = markerIndex > 0 ? "/" + parts[..<markerIndex].joined(separator: "/") : ""
            return cleanedURL(sourceURL, path: "\(prefix)/video/\(id)")
        }
        return cleanedURL(sourceURL, path: "/video/\(id)")
    }

    private static func originalYTDLPMediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isOriginalYTDLPMediaSearchHost(host),
              let clean = cleanedURL(url) else {
            return nil
        }

        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !parts.isEmpty else { return nil }
        let lower = parts.map { $0.lowercased() }

        if isAvgleHost(host) {
            return lower.first == "video" && parts.count >= 2 ? clean : nil
        }

        if isHanimeHost(host) {
            if lower.count >= 3, lower[0] == "videos", lower[1] == "hentai" {
                return clean
            }
            if ["watch", "video"].contains(lower.first ?? ""), parts.count >= 2 {
                return clean
            }
            return nil
        }

        if isKissJAVHost(host) {
            return ["video", "videos"].contains(lower.first ?? "") && parts.count >= 2 ? clean : nil
        }

        if isTokyoMotionHost(host) {
            return TokyoMotionResolver.canonicalURL(for: clean)
        }

        if isInstagramHost(host) {
            return InstagramResolver.canonicalInputURL(for: clean)
        }

        if isFacebookHost(host) {
            return facebookMediaURL(from: url)
        }

        if isKakaoTVHost(host) {
            return kakaoTVMediaURL(from: url)
        }

        if isIwaraHost(host) {
            guard ["image", "video", "videos"].contains(lower.first ?? ""),
                  parts.count >= 2,
                  parts[1].range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
                return nil
            }
            if lower.first == "image" {
                return cleanedURL(clean, path: "/image/\(parts[1])")
            }
            return clean
        }

        if isNiconicoHost(host) {
            return niconicoMediaURL(from: clean)
        }

        if isTwitchHost(host) {
            return twitchMediaURL(from: clean)
        }

        if isPornhubHost(host) {
            return pornhubMediaURL(from: url)
        }

        if isWeiboHost(host) {
            return weiboMediaURL(from: clean)
        }

        if isSpankBangHost(host) {
            return spankBangMediaURL(from: clean)
        }

        if isThisVidHost(host) {
            return thisVidMediaURL(from: clean)
        }

        if isIxiguaHost(host) {
            return ixiguaMediaURL(from: clean)
        }

        if isYourPornHost(host) {
            return yourPornMediaURL(from: clean)
        }

        if isXHamsterHost(host) {
            return xHamsterMediaURL(from: clean)
        }

        if isXNXXHost(host) || isXVideosHost(host) {
            return XVideoPageResolver.canonicalURL(for: clean)
        }

        if isYouPornHost(host) {
            return lower.first == "watch" && parts.count >= 2 ? clean : nil
        }

        if isYoukuHost(host) {
            return (lower.first == "video" || lower.first == "v_show") && parts.contains(where: { $0.hasPrefix("id_") }) ? clean : nil
        }

        return nil
    }

    private static func facebookMediaURL(from url: URL) -> URL? {
        facebookVideoURL(from: url) ?? facebookPhotoURL(from: url)
    }

    private static func facebookVideoURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if url.host?.lowercased() == "fb.watch",
           !url.path.split(separator: "/", omittingEmptySubsequences: true).isEmpty {
            return cleanedURL(url)
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }

        if lower.first == "watch",
           let videoID = components.queryItems?.first(where: { $0.name.lowercased() == "v" })?.value?.trimmed,
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

        if let marker = lower.firstIndex(of: "videos"), marker + 1 < parts.count {
            let prefix = marker > 0 ? "/" + parts[..<marker].joined(separator: "/") : ""
            return cleanedURL(url, path: "\(prefix)/videos/\(parts[marker + 1])")
        }

        return nil
    }

    private static func facebookPhotoURL(from url: URL) -> URL? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }

        if let photoID = components.queryItems?.first(where: { ["fbid", "photo_id", "photoId"].contains($0.name) })?.value?.trimmed,
           photoID.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil {
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
        guard after.contains(where: { $0.range(of: #"^[0-9]{4,}$"#, options: .regularExpression) != nil }) else {
            return nil
        }
        return cleanedURL(url)
    }

    private static func kakaoTVMediaURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        if components.path == "/m" {
            components.path = "/"
        } else if components.path.hasPrefix("/m/") {
            components.path = String(components.path.dropFirst(2))
        }
        guard let normalizedURL = components.url,
              let clean = cleanedURL(normalizedURL) else { return nil }
        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        if let marker = lower.firstIndex(of: "cliplink"), marker + 1 < parts.count {
            return clean
        }
        if lower.first == "v", parts.count >= 2 {
            return clean
        }
        return nil
    }

    private static func niconicoMediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }

        if host == "nico.ms" || host == "www.nico.ms" {
            guard let id = parts.first, !id.isEmpty else { return nil }
            var components = URLComponents()
            components.scheme = url.scheme ?? "https"
            components.host = "www.nicovideo.jp"
            components.path = "/watch/\(id)"
            return components.url
        }

        if let liveURL = NiconicoLiveResolver.canonicalInputURL(for: url) {
            return liveURL
        }

        if host == "live.nicovideo.jp" || host == "live.nicovideo.test" {
            return lower.first == "watch" && parts.count >= 2 ? url : nil
        }

        return lower.first == "watch" && parts.count >= 2 ? url : nil
    }

    private static func niconicoQueueURL(from url: URL) -> URL? {
        if NiconicoResolver.videoID(from: url) != nil {
            return NiconicoResolver.canonicalURL(for: url)
        }
        guard let host = url.host?.lowercased(),
              isNiconicoHost(host) else { return nil }
        guard let clean = cleanedURL(url) else { return nil }
        return niconicoMediaURL(from: clean)
    }

    private static func niconicoResultKey(for url: URL) -> String? {
        if let id = NiconicoResolver.videoID(from: url) {
            return "video-\(id)"
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        if let host = url.host?.lowercased(),
           host.hasPrefix("live."),
           parts.first?.lowercased() == "watch",
           parts.count >= 2 {
            return "live-\(parts[1])"
        }
        return URLIdentity.normalize(url.absoluteString)
    }

    private static func twitchMediaURL(from url: URL) -> URL? {
        let host = url.host?.lowercased() ?? ""
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }

        if host == "clips.twitch.tv" || host == "clips.twitch.test" {
            return parts.count >= 1 ? url : nil
        }
        if lower.first == "videos", parts.count >= 2 {
            return url
        }
        if let marker = lower.firstIndex(of: "clip"), marker + 1 < parts.count {
            return url
        }
        return nil
    }

    private static func twitchQueueURL(from url: URL) -> URL? {
        if let vodID = TwitchVODResolver.vodID(from: url) {
            return TwitchVODResolver.canonicalURL(vodID: vodID, sourceURL: url)
        }
        guard let host = url.host?.lowercased(),
              isTwitchHost(host),
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.queryItems = nil
        components.fragment = nil
        if host == "m.twitch.tv" {
            components.scheme = "https"
            components.host = "www.twitch.tv"
        } else if host == "m.twitch.test" {
            components.scheme = "https"
            components.host = "www.twitch.test"
        }
        guard let clean = components.url,
              twitchClipSlug(from: clean) != nil else {
            return nil
        }
        return clean
    }

    private static func twitchResultKey(for url: URL) -> String? {
        if let vodID = TwitchVODResolver.vodID(from: url) {
            return "vod-\(vodID)"
        }
        if let slug = twitchClipSlug(from: url) {
            return "clip-\(slug.lowercased())"
        }
        return nil
    }

    private static func twitchClipSlug(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitchHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if host == "clips.twitch.tv" || host == "clips.twitch.test" {
            guard let slug = parts.first, isValidTwitchSlug(slug) else { return nil }
            return slug
        }

        if let marker = lower.firstIndex(of: "clip"),
           marker + 1 < parts.count,
           isValidTwitchSlug(parts[marker + 1]) {
            return parts[marker + 1]
        }
        return nil
    }

    private static func isValidTwitchSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func iwaraQueueURL(from url: URL) -> URL? {
        if let imageID = IwaraImageResolver.imageID(from: url) {
            return IwaraImageResolver.canonicalURL(for: imageID, sourceURL: url)
        }
        if let videoID = IwaraVideoResolver.videoID(from: url) {
            return IwaraVideoResolver.canonicalURL(for: videoID, sourceURL: url)
        }

        guard let host = url.host?.lowercased(),
              isIwaraHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if lower.first == "videos",
           parts.count >= 2,
           isValidPathSlug(parts[1]) {
            return IwaraVideoResolver.canonicalURL(for: parts[1], sourceURL: url)
        }
        return nil
    }

    private static func iwaraResultKey(for url: URL) -> String? {
        if let imageID = IwaraImageResolver.imageID(from: url) {
            return "image-\(imageID)"
        }
        if let videoID = IwaraVideoResolver.videoID(from: url) {
            return "video-\(videoID)"
        }
        return nil
    }

    private static func instagramQueueURL(from url: URL) -> URL? {
        InstagramResolver.canonicalInputURL(for: url)
    }

    private static func instagramResultKey(for url: URL) -> String? {
        if let shortcode = InstagramResolver.shortcode(from: url) {
            return "media-\(shortcode)"
        }
        if let storyID = InstagramResolver.storyID(from: url) {
            return "story-\(storyID)"
        }
        return nil
    }

    private static func facebookQueueURL(from url: URL) -> URL? {
        if let photoID = FacebookPhotoResolver.photoID(from: url) {
            return FacebookPhotoResolver.canonicalURL(photoID: photoID, sourceURL: url)
        }
        guard FacebookVideoResolver.videoID(from: url) != nil else { return nil }
        return facebookVideoURL(from: url)
    }

    private static func facebookResultKey(for url: URL) -> String? {
        if let photoID = FacebookPhotoResolver.photoID(from: url) {
            return "photo-\(photoID)"
        }
        if let videoID = FacebookVideoResolver.videoID(from: url) {
            return "video-\(videoID)"
        }
        return nil
    }

    private static func pornhubResultKey(for url: URL) -> String? {
        if let request = PornhubMediaResolver.request(from: url) {
            return "\(request.kind.rawValue)-\(request.id)"
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        if lower.first == "view_video.php",
           let viewKey = components.queryItems?.first(where: { $0.name.lowercased() == "viewkey" })?.value?.trimmed,
           !viewKey.isEmpty {
            return "video-\(viewKey)"
        }
        if let first = lower.first,
           ["embed", "video"].contains(first),
           parts.count >= 2 {
            return "video-\(parts[1])"
        }
        return nil
    }

    private static func soopVODURL(from url: URL) -> URL? {
        guard let id = SOOPVODResolver.videoID(from: url) else { return nil }
        let lowerPath = url.path.lowercased()
        let path: String
        if lowerPath.contains("/catch") {
            path = "/catch/\(id)"
        } else if lowerPath.contains("/vod") {
            path = "/vod/\(id)"
        } else {
            path = "/player/\(id)"
        }
        return cleanedURL(url, path: path)
    }

    private static func etcVideoPageURL(from url: URL, site: EtcVideoPageResolver.Site, id: String) -> URL? {
        switch site {
        case .bitchute:
            return cleanedURL(url, path: "/video/\(id)/")
        case .dailymotion:
            let host = url.host?.lowercased() ?? ""
            return cleanedURL(url, path: host == "dai.ly" || host == "www.dai.ly" || host == "dai.test" || host == "www.dai.test" ? "/\(id)" : "/video/\(id)")
        case .kick:
            if let components = cleanedComponentsKeepingQuery(url, names: ["clip", "video", "v"]),
               let target = components.url {
                return target
            }
            return cleanedURL(url)
        case .streamable:
            return cleanedURL(url, path: "/\(id)")
        case .vk:
            if url.path.lowercased().contains("video_ext.php"),
               var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                let items = components.queryItems ?? []
                components.queryItems = items.filter { ["oid", "id"].contains($0.name.lowercased()) }
                components.fragment = nil
                return components.url
            }
            return cleanedURL(url)
        case .reddit:
            let host = url.host?.lowercased() ?? ""
            if host == "v.redd.it" || host == "v.redd.test" || host == "redd.it" || host == "redd.test" {
                return cleanedURL(url, path: "/\(id)")
            }
            return cleanedURL(url)
        case .odysee, .okru, .rumble, .rutube, .tver:
            return cleanedURL(url)
        default:
            return cleanedURL(url)
        }
    }

    private static func isEtcVideoNavigationURL(_ url: URL, site: EtcVideoPageResolver.Site) -> Bool {
        let lower = url.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).lowercased() }
        let first = lower.first ?? ""

        if site == .kick,
           cleanedComponentsKeepingQuery(url, names: ["clip", "video", "v"]) != nil {
            return false
        }
        if site == .vk, first == "video_ext.php" {
            return false
        }
        guard !first.isEmpty else { return true }

        let reserved: Set<String> = [
            "about", "browse", "categories", "category", "channels", "channel",
            "discover", "explore", "feed", "help", "home", "login", "popular",
            "privacy", "search", "settings", "signup", "tag", "tags", "terms",
            "trending", "user", "users"
        ]
        return reserved.contains(first)
    }

    private static func cleanedComponentsKeepingQuery(_ url: URL, names: Set<String>) -> URLComponents? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let allowed = names.map { $0.lowercased() }
        let items = (components.queryItems ?? []).filter { allowed.contains($0.name.lowercased()) }
        guard !items.isEmpty else { return nil }
        components.queryItems = items
        components.fragment = nil
        return components
    }

    private static func pornhubVideoURL(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        if lower.first == "view_video.php",
           let viewKey = components.queryItems?.first(where: { $0.name.lowercased() == "viewkey" })?.value?.trimmed,
           !viewKey.isEmpty {
            components.queryItems = [URLQueryItem(name: "viewkey", value: viewKey)]
            components.fragment = nil
            return components.url
        }
        if ["embed", "video"].contains(lower.first ?? ""),
           parts.count >= 2,
           isValidPathSlug(parts[1]),
           !["search", "categories", "category", "channels", "channel", "model", "models", "pornstar", "pornstars", "playlist", "playlists"].contains(parts[1].lowercased()) {
            return cleanedURL(url)
        }
        return nil
    }

    private static func pornhubMediaURL(from url: URL) -> URL? {
        if let video = pornhubVideoURL(from: url) {
            return video
        }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard let first = lower.first,
              ["gif", "photo", "album"].contains(first),
              parts.count >= 2,
              parts[1].range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleanedURL(url, path: "/\(first)/\(parts[1])")
    }

    private static func xHamsterMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }

        if lower.first == "videos", parts.count >= 2 {
            return clean
        }

        if let photosIndex = lower.firstIndex(of: "photos"),
           photosIndex + 2 < parts.count,
           lower[photosIndex + 1] == "gallery",
           parts[photosIndex + 2].range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil {
            let prefix = photosIndex > 0 ? "/" + parts[..<photosIndex].joined(separator: "/") : ""
            return cleanedURL(clean, path: "\(prefix)/photos/gallery/\(parts[photosIndex + 2])")
        }

        return nil
    }

    private static func weiboMediaURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isWeiboHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        if let marker = lower.firstIndex(of: "status"), marker + 1 < parts.count {
            return cleanedURL(url, path: "/" + parts[0...(marker + 1)].joined(separator: "/"))
        }
        if let marker = lower.firstIndex(of: "detail"), marker + 1 < parts.count {
            return cleanedURL(url, path: "/" + parts[0...(marker + 1)].joined(separator: "/"))
        }
        if lower.count >= 3, lower[0] == "tv", lower[1] == "show" {
            return cleanedURL(url, path: "/tv/show/\(parts[2])")
        }
        return nil
    }

    private static func spankBangMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first,
              first.range(of: #"^[0-9A-Za-z_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        let reserved = Set(["s", "search", "tag", "tags", "category", "categories", "users", "user", "channels", "channel", "pornstars", "playlist"])
        return reserved.contains(first.lowercased()) ? nil : clean
    }

    private static func thisVidMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard let first = lower.first,
              ["video", "videos"].contains(first),
              parts.count >= 2,
              isValidPathSlug(parts[1]) else {
            return nil
        }
        return cleanedURL(clean, path: "/\(first)/\(parts[1])/") ?? clean
    }

    private static func ixiguaMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }

        if let id = parts.first,
           parts.count == 1,
           isIxiguaVideoID(id) {
            return cleanedURL(clean, path: "/\(id)") ?? clean
        }

        if lower.first == "video",
           parts.count >= 2,
           isIxiguaVideoID(parts[1]) {
            return cleanedURL(clean, path: "/video/\(parts[1])") ?? clean
        }

        return nil
    }

    private static func yourPornMediaURL(from url: URL) -> URL? {
        guard let clean = cleanedURL(url) else { return nil }
        let parts = clean.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        let lower = parts.map { $0.lowercased() }
        guard ["post", "watch"].contains(lower.first ?? ""),
              parts.count >= 2,
              isValidPathSlug(parts[1]) else {
            return nil
        }
        return clean
    }

    private static func cleanTumblrBlogName(_ raw: String) -> String? {
        let blog = raw.removingPercentEncoding?.trimmed ?? raw.trimmed
        guard isValidPathSlug(blog) else { return nil }
        return blog.lowercased()
    }

    private static func isValidImgurID(_ value: String) -> Bool {
        isValidPathSlug(value) && value.count <= 80
    }

    private static func isIxiguaVideoID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]{6,}$"#, options: .regularExpression) != nil
    }

    private static func isValidPathSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func isMediaFileExtension(_ value: String) -> Bool {
        ["jpg", "jpeg", "png", "gif", "webp", "avif", "mp4", "webm", "mov", "m3u8", "zip", "cbz", "pdf"].contains(value.lowercased())
    }

    private static func firstCapture(in text: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
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

    private static func matches(in text: String, pattern: String) -> [String] {
        captures(in: text, pattern: pattern).compactMap(\.first)
    }

    private static func captures(in text: String, pattern: String) -> [[String]] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            var groups: [String] = []
            for index in 1..<match.numberOfRanges {
                guard let capture = Range(match.range(at: index), in: text) else { return nil }
                groups.append(String(text[capture]))
            }
            return groups
        }
    }

    private static func uniqueStrings(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for value in values {
            let trimmed = value.trimmed
            guard !trimmed.isEmpty else { continue }
            let key = trimmed.lowercased()
            guard seen.insert(key).inserted else { continue }
            output.append(trimmed)
        }
        return output
    }

    private static func hitomiReaderURL(galleryID: String, baseURL: URL) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        components?.scheme = "https"
        components?.host = "hitomi.la"
        components?.path = "/reader/\(galleryID).html"
        components?.queryItems = nil
        components?.fragment = nil
        return components?.url
    }

    private static func isWeakHitomiTitle(_ title: String, galleryID: String) -> Bool {
        let value = title.trimmed.lowercased()
        return value.isEmpty ||
            value == "download" ||
            value == galleryID ||
            value == "\(galleryID).html" ||
            value == "hitomi \(galleryID)" ||
            value.hasPrefix("reader") ||
            value.contains("/\(galleryID)")
    }

    private static func isWeakGalleryTitle(_ title: String, id: String, sitePrefix: String) -> Bool {
        let value = title.trimmed.lowercased()
        return value.isEmpty ||
            value == "download" ||
            value == id ||
            value == "\(id).html" ||
            value == "\(sitePrefix) \(id)" ||
            value.contains("/\(id)")
    }

    private static func isHitomiHost(_ host: String) -> Bool {
        host == "hitomi.la" || host.hasSuffix(".hitomi.la")
    }

    private static func isGoogleHost(_ host: String) -> Bool {
        host == "google.com" ||
            host.hasSuffix(".google.com") ||
            host.hasPrefix("google.") ||
            host.hasPrefix("www.google.")
    }

    private static func isNHentaiHost(_ host: String) -> Bool {
        host == "nhentai.net" || host == "nhentai.test" || host.hasSuffix(".nhentai.net")
    }

    private static func isNHentaiComHost(_ host: String) -> Bool {
        host == "nhentai.com" ||
            host == "www.nhentai.com" ||
            host == "nhentai.com.test" ||
            host == "www.nhentai.com.test"
    }

    private static func isEHentaiHost(_ host: String) -> Bool {
        host == "e-hentai.org" ||
            host == "exhentai.org" ||
            host == "e-hentai.test" ||
            host == "exhentai.test" ||
            host.hasSuffix(".e-hentai.org") ||
            host.hasSuffix(".exhentai.org")
    }

    private static func isNozomiHost(_ host: String) -> Bool {
        host == "nozomi.la" ||
            host == "www.nozomi.la" ||
            host == "nozomi.test" ||
            host == "www.nozomi.test"
    }

    private static func isPixivHost(_ host: String) -> Bool {
        host == "pixiv.net" ||
            host == "www.pixiv.net" ||
            host == "pixiv.com" ||
            host == "www.pixiv.com" ||
            host == "pixiv.co" ||
            host == "www.pixiv.co" ||
            host == "pixiv.me" ||
            host.hasSuffix(".pixiv.me") ||
            host == "pixiv.test" ||
            host == "www.pixiv.test"
    }

    private static func isArtStationHost(_ host: String) -> Bool {
        host == "artstation.com" ||
            host == "www.artstation.com" ||
            host == "artstation.test"
    }

    private static func isBCYHost(_ host: String) -> Bool {
        host == "bcy.net" ||
            host == "www.bcy.net" ||
            host == "bcy.net.test" ||
            host == "www.bcy.net.test"
    }

    private static func isFC2Host(_ host: String) -> Bool {
        host == "fc2.com" ||
            host == "www.fc2.com" ||
            host == "video.fc2.com" ||
            host == "fc2.com.test" ||
            host == "www.fc2.com.test" ||
            host == "video.fc2.com.test"
    }

    private static func deviantArtProfileURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isDeviantArtHost(host),
              !DeviantArtResolver.isArtworkURL(url),
              isLikelyDeviantArtProfileURL(url, host: host),
              let canonical = DeviantArtResolver.canonicalCollectionURL(for: url) else {
            return nil
        }

        return canonical
    }

    private static func isLikelyDeviantArtProfileURL(_ url: URL, host: String) -> Bool {
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        if isLegacyDeviantArtSubdomain(host) {
            return parts.isEmpty || isLikelyDeviantArtCollectionTail(parts)
        }
        guard parts.count > 1 else { return parts.count == 1 }
        return isLikelyDeviantArtCollectionTail(Array(parts.dropFirst()))
    }

    private static func isLikelyDeviantArtCollectionTail(_ parts: [String]) -> Bool {
        guard let first = parts.first?.lowercased() else { return false }
        switch first {
        case "gallery":
            return parts.count >= 2 && parts.count <= 3
        case "favourites", "favorites":
            return parts.count <= 3
        default:
            return false
        }
    }

    private static func isLegacyDeviantArtSubdomain(_ host: String) -> Bool {
        guard host.hasSuffix(".deviantart.com") || host.hasSuffix(".deviantart.test"),
              let first = host.split(separator: ".").first.map(String.init) else {
            return false
        }
        return !["www", "m", "deviantart"].contains(first)
    }

    private static func isDeviantArtHost(_ host: String) -> Bool {
        host == "deviantart.com" ||
            host == "www.deviantart.com" ||
            host == "deviantart.test" ||
            host.hasSuffix(".deviantart.com") ||
            host.hasSuffix(".deviantart.test")
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

    private static func isNewgroundsHost(_ host: String) -> Bool {
        host == "newgrounds.com" ||
            host == "www.newgrounds.com" ||
            host == "newgrounds.test" ||
            host.hasSuffix(".newgrounds.com")
    }

    private static func isFlickrHost(_ host: String) -> Bool {
        host == "flickr.com" ||
            host == "www.flickr.com" ||
            host == "flickr.test" ||
            host.hasSuffix(".flickr.com") ||
            host.hasSuffix(".flickr.test")
    }

    private static func isCoubHost(_ host: String) -> Bool {
        host == "coub.com" ||
            host == "www.coub.com" ||
            host == "coub.test" ||
            host == "www.coub.test" ||
            host.hasSuffix(".coub.com") ||
            host.hasSuffix(".coub.test") ||
            CoubResolver.isImagizerHost(host)
    }

    private static func isVimeoHost(_ host: String) -> Bool {
        host == "vimeo.com" ||
            host == "www.vimeo.com" ||
            host == "player.vimeo.com" ||
            host == "vimeo.test" ||
            host == "www.vimeo.test" ||
            host == "player.vimeo.test"
    }

    private static func isSoundCloudHost(_ host: String) -> Bool {
        host == "soundcloud.com" ||
            host == "www.soundcloud.com" ||
            host == "soundcloud.test" ||
            host == "www.soundcloud.test" ||
            host.hasSuffix(".soundcloud.com") ||
            host.hasSuffix(".soundcloud.test")
    }

    private static func isYouTubeHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host == "www.youtube.com" ||
            host == "m.youtube.com" ||
            host == "music.youtube.com" ||
            host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "yewtu.be" ||
            host == "youtube.test" ||
            host == "www.youtube.test" ||
            host == "m.youtube.test" ||
            host == "music.youtube.test" ||
            host == "youtu.test" ||
            host == "www.youtu.test" ||
            host == "yewtu.test" ||
            host.hasSuffix(".yewtu.be") ||
            host.hasSuffix(".yewtu.test")
    }

    private static func isYouTubeShortHost(_ host: String) -> Bool {
        host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "youtu.test" ||
            host == "www.youtu.test"
    }

    private static func isYewtuHost(_ host: String) -> Bool {
        host == "yewtu.be" ||
            host == "yewtu.test" ||
            host.hasSuffix(".yewtu.be") ||
            host.hasSuffix(".yewtu.test")
    }

    private static func youtubeQueueURL(from url: URL) -> URL? {
        guard let host = url.host?.lowercased(),
              isYouTubeHost(host) else { return nil }

        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []

        if isYouTubeShortHost(host) {
            guard let id = parts.first, isValidYouTubeSlug(id) else { return nil }
            return youtubeCanonicalURL(path: "/watch", queryItems: [URLQueryItem(name: "v", value: id)])
        }

        if let first = lower.first,
           ["embed", "v"].contains(first),
           parts.count >= 2,
           isValidYouTubeSlug(parts[1]) {
            return youtubeCanonicalURL(path: "/watch", queryItems: [URLQueryItem(name: "v", value: parts[1])])
        }

        if isYewtuHost(host),
           parts.count == 1,
           let id = parts.first,
           isValidYouTubeSlug(id),
           !isYewtuReservedPath(id) {
            return youtubeCanonicalURL(path: "/watch", queryItems: [URLQueryItem(name: "v", value: id)])
        }

        if lower.first == "watch",
           let id = queryValue("v", in: queryItems),
           isValidYouTubeSlug(id) {
            return youtubeCanonicalURL(path: "/watch", queryItems: [URLQueryItem(name: "v", value: id)])
        }

        if lower.first == "shorts",
           parts.count >= 2,
           isValidYouTubeSlug(parts[1]) {
            return youtubeCanonicalURL(path: "/shorts/\(parts[1])")
        }

        if lower.first == "clip",
           parts.count >= 2,
           isValidYouTubeSlug(parts[1]) {
            return youtubeCanonicalURL(path: "/clip/\(parts[1])")
        }

        if lower.first == "live",
           parts.count >= 2,
           isValidYouTubeSlug(parts[1]) {
            return youtubeCanonicalURL(path: "/watch", queryItems: [URLQueryItem(name: "v", value: parts[1])])
        }

        if lower.first == "playlist",
           let id = queryValue("list", in: queryItems),
           isValidYouTubeSlug(id) {
            return youtubeCanonicalURL(path: "/playlist", queryItems: [URLQueryItem(name: "list", value: id)])
        }

        if let first = lower.first,
           ["channel", "user", "c"].contains(first),
           parts.count >= 2,
           isValidYouTubeSlug(parts[1]) {
            return youtubeCanonicalURL(path: youtubeChannelPath(prefix: parts[0], slug: parts[1], tail: parts.dropFirst(2).first))
        }

        if let handle = parts.first,
           isValidYouTubeHandle(handle) {
            return youtubeCanonicalURL(path: youtubeChannelPath(prefix: handle, slug: nil, tail: parts.dropFirst().first))
        }

        return nil
    }

    private static func youtubeChannelPath(prefix: String, slug: String?, tail: String?) -> String {
        var parts = slug == nil ? [prefix] : [prefix, slug!]
        if let tail,
           isYouTubeChannelTab(tail) {
            parts.append(tail)
        }
        return "/" + parts.joined(separator: "/")
    }

    private static func youtubeCanonicalURL(path: String, queryItems: [URLQueryItem]? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.youtube.com"
        components.path = path
        components.queryItems = queryItems
        return components.url
    }

    private static func youtubeResultKey(for url: URL) -> String? {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        let queryItems = components.queryItems ?? []
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }

        if lower.first == "watch",
           let id = queryValue("v", in: queryItems) {
            return "video-\(id)"
        }
        if lower.first == "shorts",
           parts.count >= 2 {
            return "video-\(parts[1])"
        }
        if lower.first == "clip",
           parts.count >= 2 {
            return "clip-\(parts[1])"
        }
        if lower.first == "playlist",
           let id = queryValue("list", in: queryItems) {
            return "playlist-\(id)"
        }
        if let first = parts.first,
           first.hasPrefix("@") {
            return "channel-\(url.path.lowercased())"
        }
        if let first = lower.first,
           ["channel", "user", "c"].contains(first) {
            return "channel-\(url.path.lowercased())"
        }
        return nil
    }

    private static func isValidYouTubeSlug(_ value: String) -> Bool {
        !value.isEmpty &&
            value.range(of: #"^[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    private static func isValidYouTubeHandle(_ value: String) -> Bool {
        value.range(of: #"^@[A-Za-z0-9][A-Za-z0-9._-]*$"#, options: .regularExpression) != nil
    }

    private static func isYouTubeChannelTab(_ value: String) -> Bool {
        ["featured", "videos", "shorts", "streams", "live", "playlists", "community", "releases", "podcasts"].contains(value.lowercased())
    }

    private static func isYewtuReservedPath(_ value: String) -> Bool {
        [
            "channel", "c", "clip", "embed", "feed", "hashtag", "live", "playlist",
            "playlists", "redirect", "results", "shorts", "user", "watch"
        ].contains(value.lowercased()) || value.hasPrefix("@")
    }

    private static func isTwitterHost(_ host: String) -> Bool {
        host == "twitter.com" ||
            host == "www.twitter.com" ||
            host == "mobile.twitter.com" ||
            host == "x.com" ||
            host == "www.x.com" ||
            host == "twitter.test" ||
            host == "www.twitter.test" ||
            host == "x.test" ||
            host == "www.x.test"
    }

    private static func twitterSpaceID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitterHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        let lower = parts.map { $0.lowercased() }
        if let marker = lower.firstIndex(of: "spaces"),
           marker + 1 < parts.count,
           isValidPathSlug(parts[marker + 1]) {
            return parts[marker + 1]
        }
        return nil
    }

    private static func twitterSpaceURL(id: String, sourceURL: URL) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/i/spaces/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func twitterBroadcastID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitterHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "broadcasts",
              isValidPathSlug(parts[2]) else {
            return nil
        }
        return parts[2]
    }

    private static func twitterBroadcastURL(id: String, sourceURL: URL) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/i/broadcasts/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func twitterUserID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isTwitterHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count >= 3,
              parts[0].lowercased() == "i",
              parts[1].lowercased() == "user" else {
            return nil
        }
        let id = parts[2].trimmed
        guard id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return id
    }

    private static func twitterUserURL(id: String, sourceURL: URL) -> URL? {
        guard var components = URLComponents(url: sourceURL, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.path = "/i/user/\(id)"
        components.queryItems = nil
        components.fragment = nil
        return components.url
    }

    private static func isTikTokHost(_ host: String) -> Bool {
        host == "tiktok.com" ||
            host == "www.tiktok.com" ||
            host == "m.tiktok.com" ||
            host == "douyin.com" ||
            host == "www.douyin.com" ||
            host == "tiktok.test" ||
            host == "www.tiktok.test" ||
            host == "douyin.test" ||
            host == "www.douyin.test" ||
            host.hasSuffix(".tiktok.com") ||
            host.hasSuffix(".douyin.com") ||
            host.hasSuffix(".tiktok.test") ||
            host.hasSuffix(".douyin.test")
    }

    private static func isBilibiliHost(_ host: String) -> Bool {
        host == "bilibili.com" ||
            host == "www.bilibili.com" ||
            host == "m.bilibili.com" ||
            host == "bangumi.bilibili.com" ||
            host == "bilibili.test" ||
            host == "www.bilibili.test" ||
            host.hasSuffix(".bilibili.com") ||
            host.hasSuffix(".bilibili.test")
    }

    private static func isChzzkHost(_ host: String) -> Bool {
        host == "chzzk.naver.com" ||
            host == "m.chzzk.naver.com" ||
            host == "chzzk.naver.test" ||
            host == "m.chzzk.naver.test"
    }

    private static func isSOOPHost(_ host: String) -> Bool {
        host == "afreecatv.com" ||
            host.hasSuffix(".afreecatv.com") ||
            host == "sooplive.com" ||
            host.hasSuffix(".sooplive.com") ||
            host == "sooplive.co.kr" ||
            host.hasSuffix(".sooplive.co.kr") ||
            host == "afreecatv.test" ||
            host.hasSuffix(".afreecatv.test") ||
            host == "sooplive.test" ||
            host.hasSuffix(".sooplive.test")
    }

    private static func isEtcVideoSearchHost(_ host: String) -> Bool {
        guard let url = URL(string: "https://\(host)/"),
              let site = EtcVideoPageResolver.site(for: url) else {
            return false
        }
        return isEtcVideoSearchSite(site)
    }

    private static func isEtcVideoSearchSite(_ site: EtcVideoPageResolver.Site) -> Bool {
        switch site {
        case .bitchute, .dailymotion, .kick, .odysee, .okru, .reddit, .rumble, .rutube, .streamable, .twitcasting, .tver, .vk:
            return true
        default:
            return false
        }
    }

    private static func isOriginalYTDLPMediaSearchHost(_ host: String) -> Bool {
        isAvgleHost(host) ||
            isHanimeHost(host) ||
            isKissJAVHost(host) ||
            isTokyoMotionHost(host) ||
            isInstagramHost(host) ||
            isFacebookHost(host) ||
            isKakaoTVHost(host) ||
            isIwaraHost(host) ||
            isNiconicoHost(host) ||
            isTwitchHost(host) ||
            isPornhubHost(host) ||
            isWeiboHost(host) ||
            isSpankBangHost(host) ||
            isThisVidHost(host) ||
            isIxiguaHost(host) ||
            isYourPornHost(host) ||
            isXHamsterHost(host) ||
            isXNXXHost(host) ||
            isXVideosHost(host) ||
            isYouPornHost(host) ||
            isYoukuHost(host)
    }

    private static func isAvgleHost(_ host: String) -> Bool {
        host == "avgle.com" ||
            host == "www.avgle.com" ||
            host == "avgle.test" ||
            host == "www.avgle.test"
    }

    private static func isHanimeHost(_ host: String) -> Bool {
        host == "hanime.tv" ||
            host == "www.hanime.tv" ||
            host == "hanime.test" ||
            host == "www.hanime.test"
    }

    private static func isKissJAVHost(_ host: String) -> Bool {
        KissJAVResolver.isSupportedHost(host)
    }

    private static func isTokyoMotionHost(_ host: String) -> Bool {
        TokyoMotionResolver.isSupportedHost(host)
    }

    private static func isInstagramHost(_ host: String) -> Bool {
        host == "instagram.com" ||
            host == "www.instagram.com" ||
            host == "m.instagram.com" ||
            host.hasSuffix(".instagram.com") ||
            host == "instagram.co" ||
            host == "www.instagram.co" ||
            host.hasSuffix(".instagram.co") ||
            host == "instagram.test" ||
            host == "www.instagram.test" ||
            host.hasSuffix(".instagram.test")
    }

    private static func isFacebookHost(_ host: String) -> Bool {
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
        return topLevelDomain.range(of: #"^[a-z]{2,12}$"#, options: .regularExpression) != nil
    }

    private static func isKakaoTVHost(_ host: String) -> Bool {
        host == "tv.kakao.com" ||
            host.hasSuffix(".tv.kakao.com") ||
            host == "kakao.tv" ||
            host.hasSuffix(".kakao.tv") ||
            host == "kakaotv.daum.net" ||
            host.hasSuffix(".kakaotv.daum.net") ||
            host == "tv.kakao.test" ||
            host.hasSuffix(".tv.kakao.test") ||
            host == "kakao.test" ||
            host.hasSuffix(".kakao.test") ||
            host == "kakaotv.daum.test" ||
            host.hasSuffix(".kakaotv.daum.test")
    }

    private static func isIwaraHost(_ host: String) -> Bool {
        host == "iwara.tv" ||
            host == "www.iwara.tv" ||
            host == "iwara.test" ||
            host == "www.iwara.test"
    }

    private static func isNiconicoHost(_ host: String) -> Bool {
        host == "nico.ms" ||
            host == "www.nico.ms" ||
            host == "nicovideo.jp" ||
            host == "www.nicovideo.jp" ||
            host == "ch.nicovideo.jp" ||
            host == "live.nicovideo.jp" ||
            host == "niconico.com" ||
            host == "www.niconico.com" ||
            host == "nicovideo.test" ||
            host == "www.nicovideo.test" ||
            host == "ch.nicovideo.test" ||
            host == "live.nicovideo.test" ||
            host == "niconico.test" ||
            host == "www.niconico.test"
    }

    private static func isTwitchHost(_ host: String) -> Bool {
        host == "twitch.tv" ||
            host == "www.twitch.tv" ||
            host == "m.twitch.tv" ||
            host == "clips.twitch.tv" ||
            host == "twitch.test" ||
            host == "www.twitch.test" ||
            host == "m.twitch.test" ||
            host == "clips.twitch.test"
    }

    private static func isPornhubHost(_ host: String) -> Bool {
        host == "pornhub.com" ||
            host == "www.pornhub.com" ||
            host == "pornhubthbh7ap3u.onion" ||
            host == "www.pornhubthbh7ap3u.onion" ||
            host == "pornhubpremium.com" ||
            host == "www.pornhubpremium.com" ||
            host == "pornhub.test" ||
            host == "www.pornhub.test"
    }

    private static func isWeiboHost(_ host: String) -> Bool {
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

    private static func isSpankBangHost(_ host: String) -> Bool {
        host == "spankbang.com" ||
            host == "www.spankbang.com" ||
            host == "spankbang.test" ||
            host == "www.spankbang.test"
    }

    private static func isThisVidHost(_ host: String) -> Bool {
        host == "thisvid.com" ||
            host == "www.thisvid.com" ||
            host.hasSuffix(".thisvid.com") ||
            host == "thisvid.test" ||
            host == "www.thisvid.test"
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

    private static func isYourPornHost(_ host: String) -> Bool {
        host == "yourporn.sexy" ||
            host == "www.yourporn.sexy" ||
            host.hasSuffix(".yourporn.sexy") ||
            host == "yourporn.test" ||
            host == "www.yourporn.test"
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

    private static func isXNXXHost(_ host: String) -> Bool {
        if host == "xnxx.test" || host == "www.xnxx.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard topLevelDomain == "com" || topLevelDomain == "es" else { return false }
        return base.range(of: #"^xnxx[0-9]*$"#, options: .regularExpression) != nil
    }

    private static func isXVideosHost(_ host: String) -> Bool {
        if host == "xvideos.test" || host == "www.xvideos.test" {
            return true
        }
        guard let labels = hostLabels(host), labels.count >= 2 else { return false }
        let base = labels[labels.count - 2]
        let topLevelDomain = labels[labels.count - 1]
        guard ["com", "in", "es"].contains(topLevelDomain) else { return false }
        return base.range(of: #"^xvideos[0-9]*$"#, options: .regularExpression) != nil
    }

    private static func hostLabels(_ host: String) -> [String]? {
        let labels = host
            .lowercased()
            .split(separator: ".")
            .map(String.init)
            .filter { !$0.isEmpty }
        return labels.count >= 2 ? labels : nil
    }

    private static func isYouPornHost(_ host: String) -> Bool {
        host == "youporn.com" ||
            host == "www.youporn.com" ||
            host == "youporn.test" ||
            host == "www.youporn.test"
    }

    private static func isYoukuHost(_ host: String) -> Bool {
        host == "youku.com" ||
            host == "www.youku.com" ||
            host == "v.youku.com" ||
            host == "youku.test" ||
            host == "www.youku.test" ||
            host == "v.youku.test"
    }

    private static func isImgurHost(_ host: String) -> Bool {
        host == "imgur.com" ||
            host == "www.imgur.com" ||
            host == "m.imgur.com" ||
            host == "imgur.test" ||
            host == "www.imgur.test" ||
            host == "m.imgur.test"
    }

    private static func isTumblrHost(_ host: String) -> Bool {
        host == "tumblr.com" ||
            host == "www.tumblr.com" ||
            host == "tumblr.test" ||
            host == "www.tumblr.test" ||
            host.hasSuffix(".tumblr.com") ||
            host.hasSuffix(".tumblr.test")
    }

    private static func isFourChanHost(_ host: String) -> Bool {
        host == "boards.4chan.org" ||
            host == "boards.4channel.org" ||
            host == "4chan.org" ||
            host == "www.4chan.org" ||
            host == "4channel.org" ||
            host == "www.4channel.org" ||
            host == "a.4cdn.org" ||
            host == "boards.4chan.test" ||
            host == "boards.4channel.test" ||
            host == "a.4cdn.test"
    }

    private static func isWikiArtHost(_ host: String) -> Bool {
        host == "wikiart.org" ||
            host.hasSuffix(".wikiart.org") ||
            host == "wikiart.test" ||
            host.hasSuffix(".wikiart.test")
    }

    private static func isSankakuHost(_ host: String) -> Bool {
        SankakuResolver.section(for: host) != nil
    }

    private static func isNijieHost(_ host: String) -> Bool {
        host == "nijie.info" ||
            host == "www.nijie.info" ||
            host == "nijie.test" ||
            host == "www.nijie.test"
    }

    private static func isV2PHHost(_ host: String) -> Bool {
        host == "v2ph.com" ||
            host == "www.v2ph.com" ||
            host == "v2ph.test" ||
            host == "www.v2ph.test"
    }

    private static func isHentaiCosplayHost(_ host: String) -> Bool {
        let domains = [
            "hentai-cosplays.com",
            "porn-images-xxx.com",
            "hentai-img.com",
            "porn-video-xxx.com",
            "hentai-cosplays.test",
            "porn-images-xxx.test",
            "hentai-img.test",
            "porn-video-xxx.test"
        ]
        return domains.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isHentaiFoundryHost(_ host: String) -> Bool {
        host == "hentai-foundry.com" ||
            host == "www.hentai-foundry.com" ||
            host == "hentai-foundry.test" ||
            host == "www.hentai-foundry.test"
    }

    private static func isTalkOPGGHost(_ host: String) -> Bool {
        host == "talk.op.gg" ||
            host == "www.talk.op.gg" ||
            host == "talk.op.gg.test" ||
            host == "www.talk.op.gg.test"
    }

    private static func isAsmHentaiHost(_ host: String) -> Bool {
        host == "asmhentai.com" ||
            host == "www.asmhentai.com" ||
            host == "asmhentai.test" ||
            host == "www.asmhentai.test"
    }

    private static func isMyReadingMangaHost(_ host: String) -> Bool {
        host == "myreadingmanga.info" ||
            host == "www.myreadingmanga.info" ||
            host == "myreadingmanga.test" ||
            host == "www.myreadingmanga.test"
    }

    private static func isLusciousHost(_ host: String) -> Bool {
        host == "luscious.net" ||
            host == "www.luscious.net" ||
            host == "members.luscious.net" ||
            host == "luscious.test" ||
            host == "www.luscious.test" ||
            host == "members.luscious.test"
    }

    private static func isBDSMlrHost(_ host: String) -> Bool {
        host == "bdsmlr.com" ||
            host == "www.bdsmlr.com" ||
            host.hasSuffix(".bdsmlr.com") ||
            host == "bdsmlr.test" ||
            host == "www.bdsmlr.test" ||
            host.hasSuffix(".bdsmlr.test")
    }

    private static func isNarouHost(_ host: String) -> Bool {
        host == "ncode.syosetu.com" ||
            host == "yomou.syosetu.com" ||
            host == "novel18.syosetu.com" ||
            host == "ncode.syosetu.test" ||
            host == "yomou.syosetu.test" ||
            host == "novel18.syosetu.test"
    }

    private static func isKakuyomuHost(_ host: String) -> Bool {
        host == "kakuyomu.jp" ||
            host == "www.kakuyomu.jp" ||
            host == "kakuyomu.test" ||
            host == "www.kakuyomu.test"
    }

    private static func isHamelnHost(_ host: String) -> Bool {
        host == "syosetu.org" ||
            host == "www.syosetu.org" ||
            host == "syosetu.test" ||
            host == "www.syosetu.test"
    }

    private static func isComicWalkerHost(_ host: String) -> Bool {
        host == "comic-walker.com" ||
            host == "comic-walker.jp" ||
            host == "www.comic-walker.com" ||
            host == "www.comic-walker.jp" ||
            host == "comic-walker.test"
    }

    private static func isNaverBlogHost(_ host: String) -> Bool {
        host == "blog.naver.com" ||
            host == "m.blog.naver.com" ||
            host == "blog.naver.test" ||
            host == "m.blog.naver.test" ||
            host.hasSuffix(".blog.me") ||
            host.hasSuffix(".blog.test")
    }

    private static func isNaverPostHost(_ host: String) -> Bool {
        host == "post.naver.com" ||
            host == "m.post.naver.com" ||
            host == "post.naver.test" ||
            host == "m.post.naver.test"
    }

    private static func isNaverCafeHost(_ host: String) -> Bool {
        host == "cafe.naver.com" ||
            host == "m.cafe.naver.com" ||
            host == "cafe.naver.test" ||
            host == "m.cafe.naver.test"
    }

    private static func isNaverTVHost(_ host: String) -> Bool {
        host == "tv.naver.com" ||
            host == "m.tv.naver.com" ||
            host == "tv.naver.test" ||
            host == "m.tv.naver.test"
    }

    private static func isWebtoonHost(_ host: String) -> Bool {
        host == "webtoon.com" ||
            host == "www.webtoon.com" ||
            host == "webtoons.com" ||
            host == "www.webtoons.com" ||
            host == "webtoon.test" ||
            host == "webtoons.test"
    }

    private static func isNaverWebtoonHost(_ host: String) -> Bool {
        host == "comic.naver.com" ||
            host == "m.comic.naver.com" ||
            host == "comic.naver.test" ||
            host == "m.comic.naver.test"
    }

    private static func isPixivComicHost(_ host: String) -> Bool {
        host == "comic.pixiv.net" ||
            host == "comic.pixiv.test"
    }

    private static func isKakaoPageHost(_ host: String) -> Bool {
        host == "page.kakao.com" ||
            host == "page.kakao.test"
    }

    private static func isKakaoWebtoonHost(_ host: String) -> Bool {
        host == "webtoon.kakao.com" ||
            host == "webtoon.kakao.test"
    }

    private static func isHiyobiHost(_ host: String) -> Bool {
        host == "hiyobi.me" ||
            host == "www.hiyobi.me" ||
            host == "hiyobi.test" ||
            host == "www.hiyobi.test"
    }

    private static func isManatokiHost(_ host: String) -> Bool {
        host.range(of: #"^(?:.*\.)?(?:mana|new)toki[0-9]*\.(?:com|net|test)$"#, options: .regularExpression) != nil
    }

    private static func isLHScanHost(_ host: String) -> Bool {
        host == "lovehug.net" ||
            host == "welovemanga.one" ||
            host == "welovemanga.net" ||
            host.hasSuffix(".welovemanga.one") ||
            host.hasSuffix(".welovemanga.net") ||
            host == "nicomanga.com" ||
            host.hasSuffix(".nicomanga.com") ||
            host == "lhscan.test" ||
            host == "welovemanga.test" ||
            host == "nicomanga.test"
    }

    private static func isJManaHost(_ host: String) -> Bool {
        host.range(of: #"(^|\.)jmana[0-9]*(\.|$)"#, options: .regularExpression) != nil
    }

    private static func isWaybackMachineHost(_ host: String) -> Bool {
        host == "web.archive.org" ||
            host == "archive.org" ||
            host == "web.archive.org.test" ||
            host == "archive.org.test"
    }

    private static func queryValue(_ name: String, in items: [URLQueryItem]) -> String? {
        items.first { $0.name.lowercased() == name.lowercased() }?.value
    }

    private static func attributeValues(from attributes: String) -> [String: String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"\b([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let range = NSRange(attributes.startIndex..<attributes.endIndex, in: attributes)
        var values: [String: String] = [:]
        for match in regex.matches(in: attributes, range: range) {
            guard let nameRange = Range(match.range(at: 1), in: attributes) else { continue }
            let name = String(attributes[nameRange]).lowercased()
            for group in 2...4 {
                guard let valueRange = Range(match.range(at: group), in: attributes) else { continue }
                values[name] = decodeHTML(String(attributes[valueRange])).trimmed
                break
            }
        }
        return values
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func embeddedImageTitle(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<img\b([^>]*)>"#, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let attributes = attributeValues(from: String(html[attributesRange]))
            if let title = attributes["alt"]?.trimmed, !title.isEmpty {
                return title
            }
            if let title = attributes["title"]?.trimmed, !title.isEmpty {
                return title
            }
        }
        return nil
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private struct AnchorEntry {
    var attributes: [String: String]
    var body: String
    var context: String
    var contextHTML: String
}

private struct JSONLDLinkCandidate {
    var url: String
    var title: String
    var attributes: [String: String]
    var contextHTML: String
}

private struct JSONStateLinkCandidate {
    var href: String
    var title: String
    var attributes: [String: String]
    var context: String
    var contextHTML: String
}

private extension URL {
    var lastPathComponentOrHost: String {
        if !lastPathComponent.isEmpty {
            return lastPathComponent
        }
        return host ?? absoluteString
    }
}
