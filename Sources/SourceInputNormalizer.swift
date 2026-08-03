import Foundation

enum SourceInputNormalizer {
    static func cleanedToken(_ raw: String) -> String {
        raw.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'()[]{}.,;"))
    }

    static func normalizedToken(_ raw: String) -> String {
        let trimmed = raw.trimmed
        if let hitomiURL = hitomiCustomURIString(from: cleanedToken(trimmed)) {
            return hitomiURL
        }
        if let sankakuURL = sankakuTagInputURLString(from: trimmed) {
            return sankakuURL
        }
        if let booruURL = booruTagInputURLString(from: trimmed) {
            return booruURL
        }
        let token = cleanedToken(trimmed)
        guard !token.isEmpty else { return "" }
        // YouTube links are common paste inputs. Resolve them before the long
        // site-specific fallback chain so Shorts appear in the queue immediately.
        if let youtubeURL = youtubeInputURLString(from: token) {
            return youtubeURL
        }
        if let youtubeURL = youtubeVideoIDInputURLString(from: token) {
            return youtubeURL
        }
        if let dcInsideURL = DCInsideResolver.canonicalShortcutURL(from: token) {
            return dcInsideURL.absoluteString
        }
        if let instagramURL = instagramInputURLString(from: token) {
            return instagramURL
        }
        if let thunderURL = thunderInputURLString(from: token) {
            return thunderURL
        }
        if let fourChanURL = fourChanInputURLString(from: token) {
            return fourChanURL
        }
        if let asmHentaiURL = asmHentaiInputURLString(from: token) {
            return asmHentaiURL
        }
        if let hitomiURL = hitomiInputURLString(from: token) {
            return hitomiURL
        }
        if let tumblrURL = tumblrInputURLString(from: token) {
            return tumblrURL
        }
        if let coubURL = coubInputURLString(from: token) {
            return coubURL
        }
        if let vimeoURL = vimeoInputURLString(from: token) {
            return vimeoURL
        }
        if let soundCloudURL = soundCloudInputURLString(from: token) {
            return soundCloudURL
        }
        if let comicWalkerURL = comicWalkerInputURLString(from: token) {
            return comicWalkerURL
        }
        if let kakaoPageURL = kakaoPageInputURLString(from: token) {
            return kakaoPageURL
        }
        if let kakaoTVURL = kakaoTVInputURLString(from: token) {
            return kakaoTVURL
        }
        if let soopVODURL = soopVODInputURLString(from: token) {
            return soopVODURL
        }
        if let avgleURL = avgleInputURLString(from: token) {
            return avgleURL
        }
        if let kissJAVURL = kissJAVInputURLString(from: token) {
            return kissJAVURL
        }
        if let tokyoMotionURL = tokyoMotionInputURLString(from: token) {
            return tokyoMotionURL
        }
        if let thisVidURL = thisVidInputURLString(from: token) {
            return thisVidURL
        }
        if let ixiguaURL = ixiguaInputURLString(from: token) {
            return ixiguaURL
        }
        if let yourPornURL = yourPornInputURLString(from: token) {
            return yourPornURL
        }
        if let youPornURL = youPornInputURLString(from: token) {
            return youPornURL
        }
        if let youkuURL = youkuInputURLString(from: token) {
            return youkuURL
        }
        if let streamableURL = streamableInputURLString(from: token) {
            return streamableURL
        }
        if let dailymotionURL = dailymotionInputURLString(from: token) {
            return dailymotionURL
        }
        if let redditURL = redditInputURLString(from: token) {
            return redditURL
        }
        if let vkURL = vkInputURLString(from: token) {
            return vkURL
        }
        if let xHamsterURL = xHamsterInputURLString(from: token) {
            return xHamsterURL
        }
        if let xVideoPageURL = xVideoPageInputURLString(from: token) {
            return xVideoPageURL
        }
        if let commonVideoURL = commonVideoPageInputURLString(from: token) {
            return commonVideoURL
        }
        if let booruURL = booruInputURLString(from: token) {
            return booruURL
        }
        if let fediverseURL = fediverseInputURLString(from: token) {
            return fediverseURL
        }
        if let flickrURL = flickrInputURLString(from: token) {
            return flickrURL
        }
        if let twitterURL = twitterInputURLString(from: token) {
            return twitterURL
        }
        if let weiboURL = weiboInputURLString(from: token) {
            return weiboURL
        }
        if let artStationURL = artStationInputURLString(from: token) {
            return artStationURL
        }
        if let newgroundsURL = newgroundsInputURLString(from: token) {
            return newgroundsURL
        }
        if let bilibiliURL = bilibiliInputURLString(from: token) {
            return bilibiliURL
        }
        if let naverWebtoonURL = naverWebtoonInputURLString(from: token) {
            return naverWebtoonURL
        }
        if let naverBlogURL = naverBlogInputURLString(from: token) {
            return naverBlogURL
        }
        if let naverPostURL = naverPostInputURLString(from: token) {
            return naverPostURL
        }
        if let naverCafeURL = naverCafeInputURLString(from: token) {
            return naverCafeURL
        }
        if let lusciousURL = lusciousInputURLString(from: token) {
            return lusciousURL
        }
        if let v2phURL = v2phInputURLString(from: token) {
            return v2phURL
        }
        if let hentaiCosplayURL = hentaiCosplayInputURLString(from: token) {
            return hentaiCosplayURL
        }
        if let webtoonURL = webtoonInputURLString(from: token) {
            return webtoonURL
        }
        if let manatokiURL = manatokiInputURLString(from: token) {
            return manatokiURL
        }
        if let lhScanURL = lhScanInputURLString(from: token) {
            return lhScanURL
        }
        if let niconicoURL = niconicoInputURLString(from: token) {
            return niconicoURL
        }
        if let hentaiFoundryURL = hentaiFoundryInputURLString(from: token) {
            return hentaiFoundryURL
        }
        if let nijieURL = nijieInputURLString(from: token) {
            return nijieURL
        }
        if let nozomiURL = nozomiInputURLString(from: token) {
            return nozomiURL
        }
        if let jManaURL = jManaInputURLString(from: token) {
            return jManaURL
        }
        if let nHentaiURL = nHentaiInputURLString(from: token) {
            return nHentaiURL
        }
        if let nHentaiComURL = nHentaiComInputURLString(from: token) {
            return nHentaiComURL
        }
        if let pornhubURL = pornhubInputURLString(from: token) {
            return pornhubURL
        }
        if let narouURL = narouInputURLString(from: token) {
            return narouURL
        }
        if let naverTVURL = naverTVInputURLString(from: token) {
            return naverTVURL
        }
        if let chzzkURL = chzzkInputURLString(from: token) {
            return chzzkURL
        }
        if let iwaraURL = iwaraInputURLString(from: token) {
            return iwaraURL
        }
        if let fc2URL = fc2InputURLString(from: token) {
            return fc2URL
        }
        if let deviantArtURL = deviantArtInputURLString(from: token) {
            return deviantArtURL
        }
        if let hanimeURL = hanimeInputURLString(from: token) {
            return hanimeURL
        }
        if let twitchVODURL = twitchVODInputURLString(from: token) {
            return twitchVODURL
        }
        if let spankBangURL = spankBangInputURLString(from: token) {
            return spankBangURL
        }
        if let facebookPhotoCollectionURL = facebookPhotoCollectionInputURLString(from: token) {
            return facebookPhotoCollectionURL
        }
        if let facebookPhotoURL = facebookPhotoInputURLString(from: token) {
            return facebookPhotoURL
        }
        if let facebookVideoURL = facebookVideoInputURLString(from: token) {
            return facebookVideoURL
        }
        if let facebookURL = facebookShortURLString(from: token) {
            return facebookURL
        }
        if let instagramURL = instagramShortURLString(from: token) {
            return instagramURL
        }
        if let pixivURL = pixivInputURLString(from: token) {
            return pixivURL
        }
        if let pixivURL = pixivShortURLString(from: token) {
            return pixivURL
        }
        if let scheme = URL(string: token)?.scheme?.lowercased(),
           token.contains("://") || ["discord", "magnet"].contains(scheme) {
            return token
        }
        if isTorrentInfoHash(token) {
            return "magnet:?xt=urn:btih:\(token.lowercased())"
        }
        if let localFile = localFileURLString(from: token) {
            return localFile
        }
        if let hitomiURL = hitomiRelativeURLString(from: token) {
            return hitomiURL
        }
        if let asmHentaiURL = asmHentaiShortURLString(from: token) {
            return asmHentaiURL
        }
        if let deviantArtURL = deviantArtShortURLString(from: token) {
            return deviantArtURL
        }
        if let fediverseURL = fediverseShortURLString(from: token) {
            return fediverseURL
        }
        if let wikiArtURL = wikiArtShortURLString(from: token) {
            return wikiArtURL
        }
        if let tikTokShortURL = tikTokShortURLString(from: token) {
            return tikTokShortURL
        }
        if let tikTokURL = tikTokBareURLString(from: token) {
            return tikTokURL
        }
        if let pinterestURL = pinterestBareURLString(from: token) {
            return pinterestURL
        }
        if let fc2URL = fc2ShortURLString(from: token) {
            return fc2URL
        }
        if let m3u8URL = m3u8BareURLString(from: token) {
            return m3u8URL
        }
        guard looksLikeBareWebURL(token) else {
            return token
        }
        return "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
    }

    private static func thunderInputURLString(from token: String) -> String? {
        let prefix = "thunder://"
        guard token.lowercased().hasPrefix(prefix) else { return nil }

        var encoded = String(token.dropFirst(prefix.count)).trimmed
        if let percentDecoded = encoded.removingPercentEncoding {
            encoded = percentDecoded
        }
        encoded = encoded
            .components(separatedBy: .whitespacesAndNewlines)
            .joined()
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = encoded.count % 4
        if remainder > 0 {
            encoded += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: encoded, options: [.ignoreUnknownCharacters]),
              var decoded = String(data: data, encoding: .utf8)?.trimmed,
              !decoded.isEmpty else {
            return nil
        }

        if decoded.hasPrefix("AA"), decoded.hasSuffix("ZZ"), decoded.count >= 4 {
            decoded = String(decoded.dropFirst(2).dropLast(2)).trimmed
        }
        guard !decoded.lowercased().hasPrefix(prefix),
              looksLikeURL(decoded) || looksLikeBareWebURL(decoded) || isTorrentInfoHash(decoded) else {
            return nil
        }
        let normalized = normalizedToken(decoded)
        return looksLikeURL(normalized) ? normalized : nil
    }

    private static func localFileURLString(from token: String) -> String? {
        let expandedPath: String
        if token == "~" {
            expandedPath = NSHomeDirectory()
        } else if token.hasPrefix("~/") {
            expandedPath = NSHomeDirectory() + String(token.dropFirst())
        } else {
            expandedPath = token
        }

        guard expandedPath.hasPrefix("/") else { return nil }
        let url = URL(fileURLWithPath: expandedPath).standardizedFileURL
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url.absoluteString
    }

    private static func fourChanInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = URL(string: value)
        } else if lowercased.contains("4chan.") || lowercased.contains("4channel.") || lowercased.contains("4cdn.") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = FourChanResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func hitomiRelativeURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard value.range(
            of: #"^(?:g|reader|galleries|lofi|mpv)/[0-9]+(?:\.html)?(?:[#?].*)?$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil else {
            return nil
        }
        return "https://hitomi.la/\(value)"
    }

    private static func hitomiInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        if let customURI = hitomiCustomURIString(from: value) {
            return customURI
        }
        if value.hasPrefix("#-*-"),
           let id = firstCapture(in: value, pattern: #"\(([0-9]+)\)?"#) {
            return "https://hitomi.la/galleries/\(id).html"
        }

        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("hitomi.la") ? URL(string: value) : nil
        } else if lowercased.contains("hitomi.la") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }

        guard let url = candidate,
              let host = url.host?.lowercased(),
              host == "hitomi.la" || host == "www.hitomi.la",
              let id = HitomiResolver.galleryID(from: url) else {
            return nil
        }
        return "https://hitomi.la/galleries/\(id).html"
    }

    static func hitomiCustomURIString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let prefix: String
        if lowercased.hasPrefix("hitomi://") {
            prefix = "hitomi://"
        } else if lowercased.hasPrefix("hitomi:") {
            prefix = "hitomi:"
        } else {
            return nil
        }

        let payload = String(token.dropFirst(prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let id = firstCapture(in: payload, pattern: #"^([0-9]+)(?:\.html)?(?:[#?].*)?$"#) ??
            firstCapture(in: payload, pattern: #"^(?:g|reader|galleries|lofi|mpv)/([0-9]+)(?:\.html)?(?:[#?].*)?$"#)
        guard let id else { return nil }
        return "https://hitomi.la/galleries/\(id).html"
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

    private static func asmHentaiShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let prefixes = ["asmhentai:", "asmhentai/"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let id = String(value.dropFirst(prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return AsmHentaiResolver.canonicalGalleryURL(for: id)?.absoluteString
    }

    private static func asmHentaiInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = URL(string: value)
        } else if lowercased.contains("asmhentai.") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let host = url.host?.lowercased(),
              ["asmhentai.com", "www.asmhentai.com", "asmhentai.test", "www.asmhentai.test"].contains(host),
              let id = AsmHentaiResolver.galleryID(from: url),
              let canonical = AsmHentaiResolver.canonicalGalleryURL(for: id, sourceURL: Optional(url)) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func deviantArtShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let prefixes = ["deviantart:", "deviantart/", "da:"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let usernamePath = String(value.dropFirst(prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return DeviantArtResolver.canonicalProfileOrCollectionURL(path: usernamePath)?.absoluteString
    }

    private static func deviantArtInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let candidate: String
        if value.contains("://") {
            candidate = value
        } else {
            guard looksLikeBareWebURL(value) else { return nil }
            candidate = "https://\(value)"
        }

        guard let url = URL(string: candidate),
              let canonical = DeviantArtResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func isTumblrBlogName(_ value: String) -> Bool {
        value.range(of: #"^[0-9A-Za-z][0-9A-Za-z_-]*$"#, options: .regularExpression) != nil
    }

    private static func fediverseShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let options: [(prefix: String, source: String, misskey: Bool)] = [
            ("mastodon:", "https://mastodon.social", false),
            ("mastodon/", "https://mastodon.social", false),
            ("pawoo:", "https://pawoo.net", false),
            ("pawoo/", "https://pawoo.net", false),
            ("baraag:", "https://baraag.net", false),
            ("baraag/", "https://baraag.net", false),
            ("misskey:", "https://misskey.io", true),
            ("misskey/", "https://misskey.io", true)
        ]
        guard let option = options.first(where: { lowercased.hasPrefix($0.prefix) }),
              let sourceURL = URL(string: option.source) else {
            return nil
        }
        let username = String(value.dropFirst(option.prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if option.misskey {
            return FediverseResolver.canonicalMisskeyProfileURL(username: username, sourceURL: sourceURL)?.absoluteString
        }
        return FediverseResolver.canonicalMastodonProfileURL(username: username, sourceURL: sourceURL)?.absoluteString
    }

    private static func fediverseInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let supportedHosts = [
            "mastodon.social",
            "pawoo.net",
            "baraag.net",
            "misskey.io",
            "mastodon.test",
            "pawoo.test",
            "baraag.test",
            "misskey.test"
        ]
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if supportedHosts.contains(where: { lowercased.contains($0) }) {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = FediverseResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func flickrInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("flickr.") || lowercased.contains("flic.kr") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = FlickrResolver.canonicalContentURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func twitterInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("twitter.") || lowercased.contains("x.com") || lowercased.contains("x.test") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let host = url.host?.lowercased(),
              host.contains("twitter") || host == "x.com" || host.hasSuffix(".x.com") || host == "x.test" || host.hasSuffix(".x.test") else {
            return nil
        }
        if let collection = TwitterCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        return YTDLPBridge.normalizedSourceURL(for: url).absoluteString
    }

    private static func weiboInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("weibo.") || lowercased.contains("weibo.cn") || lowercased.contains("sina.com.cn")) ? URL(string: value) : nil
        } else if lowercased.contains("weibo.") || lowercased.contains("weibo.cn") || lowercased.contains("sina.com.cn") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = WeiboStatusResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func artStationInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = URL(string: value)
        } else if lowercased.contains("artstation.") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate else { return nil }
        if let artistURL = ArtStationResolver.canonicalArtistURL(for: url) {
            return artistURL.absoluteString
        }
        if let projectURL = ArtStationResolver.canonicalURL(for: url) {
            return projectURL.absoluteString
        }
        return nil
    }

    private static func newgroundsInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("newgrounds.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NewgroundsResolver.canonicalArtistArtURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func bilibiliInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("bilibili.") ||
            lowercased.hasPrefix("b23.tv/") ||
            lowercased.hasPrefix("www.b23.tv/") ||
            lowercased == "b23.tv" ||
            lowercased == "www.b23.tv" {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate else {
            return nil
        }
        if let collection = BilibiliCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        if let canonical = BilibiliResolver.canonicalInputURL(for: url) {
            return canonical.absoluteString
        }
        let normalized = YTDLPBridge.normalizedSourceURL(for: url)
        if YTDLPBridge.allowsPlaylist(for: normalized) {
            guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
                return normalized.absoluteString
            }
            components.fragment = nil
            return components.url?.absoluteString ?? normalized.absoluteString
        }
        guard let host = url.host?.lowercased(),
              host == "bilibili.tv" || host.hasSuffix(".bilibili.tv") || host == "b23.tv" || host == "www.b23.tv" else {
            return nil
        }
        guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            return normalized.absoluteString
        }
        components.fragment = nil
        return components.url?.absoluteString ?? normalized.absoluteString
    }

    private static func naverWebtoonInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("comic.naver.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NaverWebtoonResolver.canonicalContentURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func naverBlogInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("blog.naver.") || lowercased.contains(".blog.me") || lowercased.contains(".blog.test")) ? URL(string: value) : nil
        } else if lowercased.contains("blog.naver.") || lowercased.contains(".blog.me") || lowercased.contains(".blog.test") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NaverBlogResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func naverPostInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("post.naver.") ? URL(string: value) : nil
        } else if lowercased.contains("post.naver.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NaverPostResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func naverCafeInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("cafe.naver.") ? URL(string: value) : nil
        } else if lowercased.contains("cafe.naver.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NaverCafeResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func lusciousInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("luscious.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = LusciousResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func v2phInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("v2ph.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = V2PHResolver.canonicalAlbumURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func hentaiCosplayInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let supportedHosts = [
            "hentai-cosplays.",
            "porn-images-xxx.",
            "hentai-img.",
            "porn-video-xxx."
        ]
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if supportedHosts.contains(where: { lowercased.contains($0) }) {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = HentaiCosplayResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func webtoonInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("webtoon.") || lowercased.contains("webtoons.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = WebtoonResolver.canonicalContentURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func manatokiInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("manatoki") || lowercased.contains("newtoki") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = ManatokiResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func lhScanInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let supportedHosts = [
            "lovehug.",
            "welovemanga.",
            "nicomanga."
        ]
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if supportedHosts.contains(where: { lowercased.contains($0) }) {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = LHScanResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func niconicoInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if let canonical = NiconicoResolver.canonicalInputURL(forShortcut: value) {
            return canonical.absoluteString
        }
        if let canonical = NiconicoResolver.canonicalInputURL(forBareVideoID: value) {
            return canonical.absoluteString
        }
        let lowercased = token.lowercased()
        let supportedHosts = [
            "nico.ms",
            "nicovideo.",
            "niconico."
        ]
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if supportedHosts.contains(where: { lowercased.contains($0) }) {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NiconicoLiveResolver.canonicalInputURL(for: url) ??
                NiconicoResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func hentaiFoundryInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let candidate: URL?
        let prefixes = ["hentai-foundry:", "hentai-foundry/", "hentaifoundry:", "hentaifoundry/", "hf:", "hf/"]
        if let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) {
            let username = String(value.dropFirst(prefix.count))
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard username.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil else {
                return nil
            }
            candidate = URL(string: "https://www.hentai-foundry.com/user/\(username)")
        } else if value.contains("://") {
            candidate = URL(string: value)
        } else if lowercased.contains("hentai-foundry.") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = HentaiFoundryResolver.canonicalContentURL(from: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func nijieInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        let prefixes = ["nijie:", "nijie/"]
        if let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) {
            let memberID = String(value.dropFirst(prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            guard let url = URL(string: "https://nijie.info/members.php?id=\(memberID)") else {
                return nil
            }
            candidate = url
        } else if value.contains("://") {
            candidate = URL(string: value)
        } else if lowercased.contains("nijie.info") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NijieResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func nozomiInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = URL(string: value)
        } else if lowercased.contains("nozomi.la") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NozomiResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func jManaInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("jmana") ? URL(string: value) : nil
        } else if lowercased.contains("jmana") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = JManaResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func nHentaiComInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("nhentai.com") ? URL(string: value) : nil
        } else if lowercased.contains("nhentai.com") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NHentaiComResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func nHentaiInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let prefixes = ["nhentai:", "nhentai/"]
        if let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) {
            let id = String(value.dropFirst(prefix.count))
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return NHentaiResolver.canonicalGalleryURL(for: id)?.absoluteString
        }

        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("nhentai.net") || lowercased.contains("nhentai.test")) ? URL(string: value) : nil
        } else if lowercased.contains("nhentai.net") || lowercased.contains("nhentai.test") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NHentaiResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func narouInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let prefixes: [(prefix: String, adult: Bool)] = [
            ("syosetu:", false),
            ("syosetu/", false),
            ("narou:", false),
            ("narou/", false),
            ("ncode:", false),
            ("ncode/", false),
            ("novel18:", true),
            ("novel18/", true),
            ("syosetu18:", true),
            ("syosetu18/", true)
        ]
        if let match = prefixes.first(where: { lowercased.hasPrefix($0.prefix) }) {
            let path = String(value.dropFirst(match.prefix.count))
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            let parts = path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            guard let ncode = parts.first else { return nil }
            let chapter = parts.count >= 2 ? Int(parts[1]) : nil
            return NarouResolver.canonicalURL(ncode: ncode, chapter: chapter, adult: match.adult)?.absoluteString
        }

        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("ncode.syosetu.") || lowercased.contains("novel18.syosetu.")) ? URL(string: value) : nil
        } else if lowercased.contains("ncode.syosetu.") || lowercased.contains("novel18.syosetu.") {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NarouResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func naverTVInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        for prefix in ["navertv:", "navertv/", "naver-tv:", "naver-tv/"] {
            guard lowercased.hasPrefix(prefix) else { continue }
            let id = String(value.dropFirst(prefix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return NaverTVResolver.canonicalURL(clipID: id)?.absoluteString
        }

        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("tv.naver.") ? URL(string: value) : nil
        } else if lowercased.contains("tv.naver.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = NaverTVResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func chzzkInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("chzzk.naver.") ? URL(string: value) : nil
        } else if lowercased.contains("chzzk.naver.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate else { return nil }
        if let collection = ChzzkCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        guard let canonical = ChzzkResolver.canonicalURL(for: url) ?? ChzzkResolver.canonicalLiveURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func iwaraInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("iwara.") ? URL(string: value) : nil
        } else if lowercased.contains("iwara.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate else { return nil }
        if let collection = IwaraCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        if let imageURL = IwaraImageResolver.canonicalURL(for: url) {
            return imageURL.absoluteString
        }
        if let videoURL = IwaraVideoResolver.canonicalURL(for: url) {
            return videoURL.absoluteString
        }
        return nil
    }

    private static func fc2InputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("video.fc2.") ? URL(string: value) : nil
        } else if lowercased.contains("video.fc2.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = FC2Resolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func hanimeInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("hanime.") ? URL(string: value) : nil
        } else if lowercased.contains("hanime.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = HanimeResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func twitchVODInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("twitch.") ? URL(string: value) : nil
        } else if lowercased.contains("twitch.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate else {
            return nil
        }
        if let collection = TwitchClipCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        if let canonical = TwitchVODResolver.canonicalURL(for: url) {
            return canonical.absoluteString
        }
        let normalized = YTDLPBridge.normalizedSourceURL(for: url)
        if YTDLPBridge.allowsPlaylist(for: normalized) {
            guard var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
                return normalized.absoluteString
            }
            components.fragment = nil
            return components.url?.absoluteString ?? normalized.absoluteString
        }
        return nil
    }

    private static func spankBangInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("spankbang.") ? URL(string: value) : nil
        } else if lowercased.contains("spankbang.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = SpankBangResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func pornhubInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let shortcuts: [(prefix: String, kind: PornhubMediaRequest.Kind)] = [
            ("pornhub_gif_", .gif),
            ("pornhub_album_", .album),
            ("pornhub_", .video)
        ]
        for shortcut in shortcuts where lowercased.hasPrefix(shortcut.prefix) {
            let id = String(value.dropFirst(shortcut.prefix.count))
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return PornhubMediaResolver.canonicalURL(kind: shortcut.kind, id: id)?.absoluteString
        }

        let candidate: URL?
        if value.contains("://") {
            candidate = Self.isPornhubInputCandidate(lowercased) ? URL(string: value) : nil
        } else if Self.isPornhubInputCandidate(lowercased) {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate else {
            return nil
        }
        let mediaURL = Self.pornhubRedirectTarget(from: url) ?? url
        if let collection = PornhubCollectionResolver.request(from: mediaURL) {
            return collection.sourceURL.absoluteString
        }
        guard let request = PornhubMediaResolver.request(from: mediaURL),
              let canonical = PornhubMediaResolver.canonicalURL(kind: request.kind, id: request.id, sourceURL: mediaURL) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func isPornhubInputCandidate(_ lowercased: String) -> Bool {
        lowercased.contains("pornhub.") ||
            lowercased.contains("pornhubpremium.") ||
            lowercased.contains("pornhubthbh7ap3u.onion")
    }

    private static func pornhubRedirectTarget(from url: URL) -> URL? {
        guard url.path.lowercased().hasSuffix("/authenticate/gotologgedin"),
              let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
              let raw = items.first(where: { $0.name.lowercased() == "url" })?.value?.trimmed,
              !raw.isEmpty else {
            return nil
        }
        let decoded = raw.removingPercentEncoding ?? raw
        let candidates = [decoded, raw]
        for candidate in candidates {
            let normalized = candidate
                .replacingOccurrences(of: "\\u0026", with: "&", options: .caseInsensitive)
                .replacingOccurrences(of: "\\/", with: "/")
                .replacingOccurrences(of: "&amp;", with: "&")
                .trimmed
            guard !normalized.isEmpty else { continue }
            let target: URL?
            if normalized.hasPrefix("//") {
                target = URL(string: "\(url.scheme ?? "https"):\(normalized)")
            } else if normalized.contains("://") {
                target = URL(string: normalized)
            } else if normalized.hasPrefix("/") {
                target = URL(string: normalized, relativeTo: url)?.absoluteURL
            } else if Self.isPornhubInputCandidate(normalized.lowercased()) {
                target = URL(string: "https://\(normalized.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
            } else {
                target = nil
            }
            if let target,
               let host = target.host?.lowercased(),
               Self.isPornhubInputCandidate(host) {
                return target
            }
        }
        return nil
    }

    private static func facebookPhotoCollectionInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("facebook.") ? URL(string: value) : nil
        } else if lowercased.contains("facebook.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let request = FacebookPhotoCollectionResolver.request(from: url) else {
            return nil
        }
        return request.sourceURL.absoluteString
    }

    private static func facebookPhotoInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("facebook.") ? URL(string: value) : nil
        } else if lowercased.contains("facebook.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = FacebookPhotoResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func facebookVideoInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("facebook.") || lowercased.contains("fb.watch")) ? URL(string: value) : nil
        } else if lowercased.contains("facebook.") || lowercased.contains("fb.watch") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = FacebookVideoResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func facebookShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let prefixes = ["facebook:", "facebook/", "fb:", "fb/"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let path = String(value.dropFirst(prefix.count))
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty,
              let url = URL(string: "https://www.facebook.com/\(path)") else {
            return nil
        }
        if let request = FacebookPhotoCollectionResolver.request(from: url) {
            return request.sourceURL.absoluteString
        }
        if let canonical = FacebookPhotoResolver.canonicalURL(for: url) {
            return canonical.absoluteString
        }
        if let canonical = FacebookVideoResolver.canonicalURL(for: url) {
            return canonical.absoluteString
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        components.host = "www.facebook.com"
        return components.url?.absoluteString
    }

    private static func instagramInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("instagram.") ? URL(string: value) : nil
        } else if lowercased.contains("instagram.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = InstagramResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func instagramShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let prefixes = ["instagram:", "instagram/", "insta:", "insta/"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let path = String(value.dropFirst(prefix.count))
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !path.isEmpty, !path.contains("://") else {
            return nil
        }

        guard let candidate = URL(string: "https://www.instagram.com/\(path)") else {
            return nil
        }
        if let canonical = InstagramResolver.canonicalInputURL(for: candidate) {
            return canonical.absoluteString
        }

        let parts = candidate.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count == 1,
              let username = parts.first,
              username.range(of: #"^[A-Za-z0-9._]{1,30}$"#, options: .regularExpression) != nil,
              !username.hasPrefix("."),
              !username.hasSuffix(".") else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "www.instagram.com"
        components.path = "/\(username)"
        return components.url?.absoluteString
    }

    private static func pixivInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("pixiv.") ? URL(string: value) : nil
        } else if lowercased.contains("pixiv.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = PixivArtworkResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func pixivShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;/"))
        let lowercased = value.lowercased()

        for prefix in ["illust_", "pixiv_illust_"] where lowercased.hasPrefix(prefix) {
            let id = String(value.dropFirst(prefix.count)).trimmed
            guard id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
                return nil
            }
            return "https://www.pixiv.net/en/artworks/\(id)"
        }

        for prefix in ["bmk_", "pixiv_bmk_", "bookmark_", "pixiv_bookmark_"] where lowercased.hasPrefix(prefix) {
            let id = String(value.dropFirst(prefix.count)).trimmed
            guard id.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
                return nil
            }
            return "https://www.pixiv.net/en/users/\(id)/bookmarks/artworks"
        }

        for prefix in ["search_", "pixiv_search_"] where lowercased.hasPrefix(prefix) {
            let tag = String(value.dropFirst(prefix.count))
                .replacingOccurrences(of: "+", with: " ")
                .trimmed
            guard !tag.isEmpty, !tag.contains("/") else { return nil }
            var components = URLComponents()
            components.scheme = "https"
            components.host = "www.pixiv.net"
            components.path = "/en/tags/\(tag)/artworks"
            return components.url?.absoluteString
        }

        if ["following_r18", "pixiv_following_r18"].contains(lowercased) ||
            lowercased.hasPrefix("following_r18_") ||
            lowercased.hasPrefix("pixiv_following_r18_") {
            return "https://www.pixiv.net/bookmark_new_illust_r18.php"
        }
        if ["following", "pixiv_following"].contains(lowercased) ||
            lowercased.hasPrefix("following_") ||
            lowercased.hasPrefix("pixiv_following_") {
            return "https://www.pixiv.net/bookmark_new_illust.php"
        }
        return nil
    }

    private static func wikiArtShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let prefixes = ["wikiart:", "wikiart/"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let slug = String(value.dropFirst(prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return WikiArtResolver.canonicalArtistURL(for: slug)?.absoluteString
    }

    private static func tikTokShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let options: [(prefix: String, host: String?)] = [
            ("tiktok:", nil),
            ("tiktok/", nil),
            ("douyin:", "https://www.douyin.com"),
            ("douyin/", "https://www.douyin.com")
        ]
        guard let option = options.first(where: { lowercased.hasPrefix($0.prefix) }) else {
            return nil
        }
        let username = String(value.dropFirst(option.prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let sourceURL = option.host.flatMap(URL.init(string:))
        return TikTokResolver.canonicalProfileURL(username: username, sourceURL: sourceURL)?.absoluteString
    }

    private static func tikTokBareURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let supportedPrefixes = [
            "tiktok.com/",
            "www.tiktok.com/",
            "m.tiktok.com/",
            "vm.tiktok.com/",
            "vt.tiktok.com/",
            "douyin.com/",
            "www.douyin.com/",
            "v.douyin.com/"
        ]
        guard supportedPrefixes.contains(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        return "https://\(value)"
    }

    private static func pinterestBareURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !value.isEmpty,
              !value.contains("."),
              !value.contains(":"),
              value.range(of: #"^[A-Za-z0-9_@%~+.-]+/[A-Za-z0-9_@%~+./-]+(?:[?#].*)?$"#, options: .regularExpression) != nil else {
            return nil
        }

        let candidate = "https://www.pinterest.com/\(value)"
        guard let url = URL(string: candidate),
              PinterestResolver.kind(from: url) != nil else {
            return nil
        }
        return candidate
    }

    private static func fc2ShortURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let prefixes = ["fc2:", "fc2/"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let id = String(value.dropFirst(prefix.count)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        return FC2Resolver.canonicalURL(contentID: id)?.absoluteString
    }

    private static func youtubeVideoIDInputURLString(from token: String) -> String? {
        guard !token.contains("://"),
              token.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil else {
            return nil
        }
        return "https://www.youtube.com/watch?v=\(token)"
    }

    private static func youtubeInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("youtube.") || lowercased.contains("youtube-nocookie.") || lowercased.contains("youtu.be") || lowercased.contains("yewtu.be") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate else {
            return nil
        }
        if let canonical = YouTubeResolver.canonicalURL(for: url) {
            return canonical.absoluteString
        }
        let normalized = YTDLPBridge.normalizedSourceURL(for: url)
        guard let host = normalized.host?.lowercased(),
              isYouTubeInputHost(host) else {
            return nil
        }
        return normalized.absoluteString
    }

    private static func isYouTubeInputHost(_ host: String) -> Bool {
        host == "youtube.com" ||
            host == "youtube.co" ||
            host == "www.youtube.com" ||
            host == "www.youtube.co" ||
            host == "m.youtube.com" ||
            host == "music.youtube.com" ||
            host == "youtube-nocookie.com" ||
            host == "www.youtube-nocookie.com" ||
            host == "youtu.be" ||
            host == "www.youtu.be" ||
            host == "yewtu.be" ||
            host == "www.yewtu.be" ||
            host.hasSuffix(".yewtu.be")
    }

    private static func tumblrInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        for prefix in ["tumblr:", "tumblr/"] where lowercased.hasPrefix(prefix) {
            let blog = String(token.dropFirst(prefix.count))
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            guard isTumblrBlogName(blog) else { return nil }
            return "https://\(blog).tumblr.com"
        }

        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("tumblr.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = TumblrResolver.canonicalBlogURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func coubInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("coub.") || lowercased.contains(".coub.") || lowercased.contains("coub-com-")) ? URL(string: value) : nil
        } else if lowercased.contains("coub.") || lowercased.contains(".coub.") || lowercased.contains("coub-com-") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = CoubResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func vimeoInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("vimeo.") ? URL(string: value) : nil
        } else if lowercased.contains("vimeo.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = VimeoResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func soundCloudInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("soundcloud.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = SoundCloudResolver.canonicalPageURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func comicWalkerInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("comic-walker.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = ComicWalkerResolver.canonicalDetailURL(for: url) ?? ComicWalkerResolver.canonicalInputURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func kakaoPageInputURLString(from token: String) -> String? {
        let lowercased = token.lowercased()
        let candidate: URL?
        if token.contains("://") {
            candidate = URL(string: token)
        } else if lowercased.contains("page.kakao.") {
            candidate = URL(string: "https://\(token.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = KakaoPageResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func kakaoTVInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("tv.kakao.") || lowercased.contains("kakao.tv") || lowercased.contains("kakaotv.daum.")) ? URL(string: value) : nil
        } else if lowercased.contains("tv.kakao.") || lowercased.contains("kakao.tv") || lowercased.contains("kakaotv.daum.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = KakaoTVResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func soopVODInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("sooplive.") || lowercased.contains("afreecatv.")) ? URL(string: value) : nil
        } else if lowercased.contains("sooplive.") || lowercased.contains("afreecatv.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = SOOPVODResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func avgleInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("avgle.") ? URL(string: value) : nil
        } else if lowercased.contains("avgle.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalAvgleURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func kissJAVInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let namesHost = lowercased.contains("kissjav.") || lowercased.contains("mrjav.")
        let candidate: URL?
        if value.contains("://") {
            candidate = namesHost ? URL(string: value) : nil
        } else if namesHost {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = KissJAVResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func tokyoMotionInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("tokyomotion.") ? URL(string: value) : nil
        } else if lowercased.contains("tokyomotion.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = TokyoMotionResolver.canonicalURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func thisVidInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("thisvid.") ? URL(string: value) : nil
        } else if lowercased.contains("thisvid.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalThisVidURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func ixiguaInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("ixigua.") ? URL(string: value) : nil
        } else if lowercased.contains("ixigua.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalIxiguaURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func yourPornInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("yourporn.") ? URL(string: value) : nil
        } else if lowercased.contains("yourporn.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalYourPornURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func youPornInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("youporn.") ? URL(string: value) : nil
        } else if lowercased.contains("youporn.") {
            candidate = URL(string: "https://\(value)")
        } else if let shortURL = youPornShortInputURLString(from: value) {
            candidate = URL(string: shortURL)
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalYouPornURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func youPornShortInputURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let prefixes = ["youporn:", "youporn/"]
        guard let prefix = prefixes.first(where: { lowercased.hasPrefix($0) }) else {
            return nil
        }
        let rawPath = String(value.dropFirst(prefix.count))
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !rawPath.isEmpty else { return nil }
        let path = rawPath.lowercased().hasPrefix("watch/") ? rawPath : "watch/\(rawPath)"
        guard path.range(
            of: #"^watch/[A-Za-z0-9][A-Za-z0-9_-]*(?:/[A-Za-z0-9][A-Za-z0-9_-]*)*/?$"#,
            options: .regularExpression
        ) != nil else {
            return nil
        }
        return "https://www.youporn.com/\(path)"
    }

    private static func youkuInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("youku.") ? URL(string: value) : nil
        } else if lowercased.contains("youku.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalYoukuURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func streamableInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = lowercased.contains("streamable.") ? URL(string: value) : nil
        } else if lowercased.contains("streamable.") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalStreamableURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func dailymotionInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("dailymotion.") || lowercased.contains("dai.ly") || lowercased.contains("dai.test")) ? URL(string: value) : nil
        } else if lowercased.contains("dailymotion.") || lowercased.contains("dai.ly") || lowercased.contains("dai.test") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalDailymotionURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func redditInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        if value.contains("://") {
            candidate = (lowercased.contains("reddit.") || lowercased.contains("redd.it") || lowercased.contains("redd.test")) ? URL(string: value) : nil
        } else if lowercased.contains("reddit.") || lowercased.contains("redd.it") || lowercased.contains("redd.test") {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalRedditURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func vkInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let candidate: URL?
        let isVKCandidate = lowercased.contains("vk.com") ||
            lowercased.contains("vk.test") ||
            lowercased.contains("vkvideo.ru") ||
            lowercased.contains("vkvideo.test")
        if value.contains("://") {
            candidate = isVKCandidate ? URL(string: value) : nil
        } else if isVKCandidate {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalVKURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func xHamsterInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let markers = [
            "xhamster",
            "xhwebsite",
            "xhofficial",
            "xhlocal",
            "xhopen",
            "xhtotal",
            "megaxh",
            "xhwide",
            "xhtab",
            "xhtime"
        ]
        let isCandidate = markers.contains { lowercased.contains($0) }
        let candidate: URL?
        if value.contains("://") {
            candidate = isCandidate ? URL(string: value) : nil
        } else if isCandidate {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate else { return nil }
        if let collection = XHamsterCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        if let creatorURL = EtcVideoPageResolver.canonicalXHamsterCreatorURL(for: url) {
            return creatorURL.absoluteString
        }
        if let userVideosURL = EtcVideoPageResolver.canonicalXHamsterUserVideosURL(for: url) {
            return userVideosURL.absoluteString
        }
        if let videoURL = EtcVideoPageResolver.canonicalXHamsterURL(for: url) {
            return videoURL.absoluteString
        }
        if let galleryID = XHamsterGalleryResolver.galleryID(from: url) {
            return XHamsterGalleryResolver.canonicalGalleryURL(for: galleryID, sourceURL: url).absoluteString
        }
        return nil
    }

    private static func xVideoPageInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let isCandidate = lowercased.contains("xvideos") || lowercased.contains("xnxx")
        let candidate: URL?
        if value.contains("://") {
            candidate = isCandidate ? URL(string: value) : nil
        } else if isCandidate {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate else { return nil }
        if let collection = XVideoCollectionResolver.request(from: url) {
            return collection.sourceURL.absoluteString
        }
        if let canonical = XVideoPageResolver.canonicalURL(for: url) {
            return canonical.absoluteString
        }
        let normalized = YTDLPBridge.normalizedSourceURL(for: url)
        guard YTDLPBridge.allowsPlaylist(for: normalized),
              var components = URLComponents(url: normalized, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.fragment = nil
        return components.url?.absoluteString ?? normalized.absoluteString
    }

    private static func commonVideoPageInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let lowercased = value.lowercased()
        let isCandidate = lowercased.contains("bitchute.") ||
            lowercased.contains("kick.") ||
            lowercased.contains("odysee.") ||
            lowercased.contains("ok.ru") ||
            lowercased.contains("ok.test") ||
            lowercased.contains("rumble.") ||
            lowercased.contains("rutube.") ||
            lowercased.contains("live.nicovideo.") ||
            lowercased.contains("twitcasting.") ||
            lowercased.contains("tver.")
        let candidate: URL?
        if value.contains("://") {
            candidate = isCandidate ? URL(string: value) : nil
        } else if isCandidate {
            candidate = URL(string: "https://\(value)")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              let canonical = EtcVideoPageResolver.canonicalCommonVideoURL(for: url) else {
            return nil
        }
        return canonical.absoluteString
    }

    private static func booruInputURLString(from token: String) -> String? {
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        let lowercased = value.lowercased()
        let supportedHosts = [
            "danbooru.donmai.us",
            "danbooru.test",
            "gelbooru.com",
            "www.gelbooru.com",
            "gelbooru.test",
            "yande.re",
            "yandere.test",
            "rule34.xxx",
            "www.rule34.xxx",
            "api.rule34.xxx",
            "rule34.test"
        ]
        let candidate: URL?
        if value.contains("://") {
            candidate = supportedHosts.contains(where: { lowercased.contains($0) }) ? URL(string: value) : nil
        } else if supportedHosts.contains(where: { lowercased.contains($0) }) {
            candidate = URL(string: "https://\(value.trimmingCharacters(in: CharacterSet(charactersIn: "/")))")
        } else {
            candidate = nil
        }
        guard let url = candidate,
              BooruProvider.provider(for: url) != nil,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        components.scheme = "https"
        components.fragment = nil
        return components.url?.absoluteString
    }

    private static func m3u8BareURLString(from token: String) -> String? {
        guard !token.contains("://") else { return nil }
        let value = token.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard looksLikeBareWebURL(value),
              value.lowercased().contains(".m3u8") else {
            return nil
        }
        return "http://\(value)"
    }

    static func sankakuTagInputURLString(from raw: String) -> String? {
        let token = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        guard !token.isEmpty else { return nil }
        let pattern = #"^\[(chan|idol|www|app)\]\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(token.startIndex..<token.endIndex, in: token)
        guard let match = regex.firstMatch(in: token, range: range),
              let sectionRange = Range(match.range(at: 1), in: token),
              let tagsRange = Range(match.range(at: 2), in: token) else {
            return nil
        }
        let sectionName = String(token[sectionRange]).lowercased()
        let tags = String(token[tagsRange]).trimmed
        guard let section = SankakuSection(rawValue: sectionName) else { return nil }
        return SankakuResolver.tagSearchURLString(section: section, tags: tags)
    }

    static func booruTagInputURLString(from raw: String) -> String? {
        let token = raw.trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "<>\"'(){},;"))
        guard !token.isEmpty else { return nil }

        let bracketPattern = #"^\[(danbooru|gelbooru|rule34|yande(?:re)?)\]\s+(.+)$"#
        if let regex = try? NSRegularExpression(pattern: bracketPattern, options: [.caseInsensitive]) {
            let range = NSRange(token.startIndex..<token.endIndex, in: token)
            if let match = regex.firstMatch(in: token, range: range),
               let providerRange = Range(match.range(at: 1), in: token),
               let tagsRange = Range(match.range(at: 2), in: token),
               let provider = booruProvider(named: String(token[providerRange])) {
                return booruTagSearchURLString(provider: provider, tags: String(token[tagsRange]))
            }
        }

        let lowercased = token.lowercased()
        let prefixes = [
            ("danbooru:", BooruProvider.danbooru),
            ("danbooru/", BooruProvider.danbooru),
            ("gelbooru:", BooruProvider.gelbooru),
            ("gelbooru/", BooruProvider.gelbooru),
            ("rule34:", BooruProvider.rule34),
            ("rule34/", BooruProvider.rule34),
            ("yande:", BooruProvider.yandere),
            ("yande/", BooruProvider.yandere),
            ("yandere:", BooruProvider.yandere),
            ("yandere/", BooruProvider.yandere)
        ]
        guard let match = prefixes.first(where: { lowercased.hasPrefix($0.0) }) else {
            return nil
        }
        return booruTagSearchURLString(provider: match.1, tags: String(token.dropFirst(match.0.count)))
    }

    private static func booruProvider(named raw: String) -> BooruProvider? {
        switch raw.lowercased() {
        case "danbooru":
            return .danbooru
        case "gelbooru":
            return .gelbooru
        case "rule34":
            return .rule34
        case "yande", "yandere":
            return .yandere
        default:
            return nil
        }
    }

    private static func booruTagSearchURLString(provider: BooruProvider, tags rawTags: String) -> String? {
        let encodedTags = booruEncodedTags(rawTags)
        guard !encodedTags.isEmpty else { return nil }
        switch provider {
        case .danbooru:
            return "https://danbooru.donmai.us/posts?tags=\(encodedTags)"
        case .gelbooru:
            return "https://gelbooru.com/index.php?page=post&s=list&tags=\(encodedTags)"
        case .rule34:
            return "https://rule34.xxx/index.php?page=post&s=list&tags=\(encodedTags)"
        case .yandere:
            return "https://yande.re/post?tags=\(encodedTags)"
        }
    }

    private static func booruEncodedTags(_ rawTags: String) -> String {
        var tags = rawTags.trimmed
        if let decoded = tags.removingPercentEncoding {
            tags = decoded
        }
        tags = tags.replacingOccurrences(of: #"\s+"#, with: "+", options: .regularExpression)
        while tags.contains("++") {
            tags = tags.replacingOccurrences(of: "++", with: "+")
        }
        tags = tags.trimmingCharacters(in: CharacterSet(charactersIn: "+"))
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~+:")
        return tags.addingPercentEncoding(withAllowedCharacters: allowed) ?? tags
    }

    private static func isTorrentInfoHash(_ token: String) -> Bool {
        token.range(of: #"^[A-Fa-f0-9]{40}$"#, options: .regularExpression) != nil
    }

    static func looksLikeURL(_ value: String) -> Bool {
        let lowered = value.lowercased()
        return lowered.hasPrefix("http://") ||
            lowered.hasPrefix("https://") ||
            lowered.hasPrefix("file://") ||
            lowered.hasPrefix("magnet:") ||
            lowered.hasPrefix("discord:")
    }

    private static func looksLikeBareWebURL(_ token: String) -> Bool {
        guard !token.contains("\\"),
              !token.hasPrefix("/"),
              !token.hasPrefix("."),
              !token.contains("@") else {
            return false
        }

        let host = token
            .split(separator: "/", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true)
            .first?
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init) ?? ""
        guard !host.isEmpty else { return false }

        let hostWithoutPort = host.split(separator: ":", maxSplits: 1).first.map(String.init) ?? host
        if hostWithoutPort.lowercased() == "localhost" { return true }
        guard hostWithoutPort.contains("."),
              hostWithoutPort.range(of: #"^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil else {
            return false
        }

        let knownTLDs: Set<String> = [
            "app", "biz", "cc", "cn", "co", "com", "dev", "edu", "fm", "gg",
            "gov", "io", "jp", "kr", "la", "me", "net", "org", "site", "test",
            "tv", "uk", "us", "wiki", "xyz"
        ]
        let tld = hostWithoutPort.split(separator: ".").last.map { String($0).lowercased() } ?? ""
        return knownTLDs.contains(tld)
    }

}
