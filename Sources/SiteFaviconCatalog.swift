import AppKit
import Foundation

enum SiteFaviconCatalog {
    static let fallbackResourceKey = "unknown"

    static func displayScale(resourceKey: String) -> CGFloat {
        resourceKey == "chzzk" ? 1.08 : 1
    }

    private static let metadataKeys = [
        "site", "type", "handler", "extractor", "extractor_key", "tool", "rule"
    ]

    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 96
        return cache
    }()

    static func resourceKey(source: String, metadata: [String: String]) -> String {
        let sourceURL = URL(string: source.trimmed)
        let host = sourceURL?.host?.lowercased() ?? ""
        let path = sourceURL?.path.lowercased() ?? ""
        let metadataText = metadataKeys.compactMap { key in
            metadata.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value
        }
        .joined(separator: " ")
        .lowercased()
        let context = "\(host) \(path) \(metadataText)"

        func contains(_ values: String...) -> Bool {
            values.contains { context.contains($0) }
        }

        if sourceURL?.isFileURL == true || source.hasPrefix("/") || contains("local file") { return "file" }
        if source.lowercased().hasPrefix("magnet:") || contains("torrent") { return "torrent" }
        if contains("pixiv comic", "pixiv_comic", "comic.pixiv") { return "pixiv_comic" }
        if contains("pixiv") { return "pixiv" }
        if contains("hitomi") { return "hitomi" }
        if contains("hentai foundry", "hentai-foundry") { return "hf" }
        if contains("asmhentai") { return "asmhentai" }
        if contains("nhentai.com") { return "nhentai_com" }
        if contains("nhentai") { return "nhentai" }
        if contains("e-hentai", "exhentai") { return "ehen" }
        if contains("myreadingmanga", "my reading manga", " mrm") { return "mrm" }
        if contains("hiyobi") { return "hiyobi" }
        if contains("luscious") { return "luscious" }
        if contains("v2ph") { return "v2ph" }
        if contains("hanime") { return "hanime" }
        if contains("kissjav") { return "kissjav" }
        if contains("tokyomotion") { return "tokyomotion" }
        if contains("pornhub") { return "pornhub" }
        if contains("youporn") { return "youporn" }
        if contains("xhamster") { return "xhamster" }
        if contains("xvideos", "xvideo") { return "xvideo" }
        if contains("xnxx") { return "xnxx" }
        if contains("avgle") { return "avgle" }
        if contains("youtube", "youtu.be") { return "youtube" }
        if contains("bilibili") { return "bili" }
        if contains("twitch") { return "twitch" }
        if contains("sooplive", "afreecatv", "afreeca") { return "afreeca" }
        if contains("chzzk") { return "chzzk" }
        if contains("niconico", "nicovideo") { return "nico" }
        if contains("vimeo") { return "vimeo" }
        if contains("soundcloud") { return "soundcloud" }
        if contains("coub") { return "coub" }
        if contains("instagram") { return "insta" }
        if contains("tiktok") { return "tiktok" }
        if contains("twitter") || host == "x.com" || host.hasSuffix(".x.com") { return "twitter" }
        if contains("facebook") { return "facebook" }
        if contains("tumblr") { return "tumblr" }
        if contains("bluesky", "bsky.app") { return "bsky" }
        if contains("mastodon") { return "mastodon" }
        if contains("misskey") { return "misskey" }
        if contains("pawoo") { return "pawoo" }
        if contains("baraag") { return "baraag" }
        if contains("discord") { return "discord" }
        if contains("imgur") { return "imgur" }
        if contains("flickr") { return "flickr" }
        if contains("pinterest") { return "pinter" }
        if contains("artstation") { return "artstation" }
        if contains("deviantart", "deviant") { return "deviant" }
        if contains("wikiart") { return "wikiart" }
        if contains("newgrounds") { return "newgrounds" }
        if contains("iwara") { return "iwara" }
        if contains("nijie") { return "nijie" }
        if contains("bcy.net", " bcy") { return "bcy" }
        if contains("bdsmlr") { return "bdsmlr" }
        if contains("weibo") { return "weibo" }
        if contains("youku") { return "youku" }
        if contains("kakaopage") { return "kakaopage" }
        if contains("kakaowebtoon", "kakao webtoon") { return "kakaowebtoon" }
        if contains("kakaotv", "tv.kakao") { return "kakaotv" }
        if contains("comicwalker") { return "comicwalker" }
        if contains("webtoons.com") { return "webtoon" }
        if contains("comic.naver", "naver webtoon", "naver_webtoon") { return "navertoon" }
        if contains("cafe.naver", "naver cafe") { return "navercafe" }
        if contains("post.naver", "naver post") { return "naverpost" }
        if contains("tv.naver", "naver tv") { return "navertv" }
        if contains("naver") { return "naver" }
        if contains("kakuyomu") { return "kakuyomu" }
        if contains("syosetu", "ncode.syosetu", "narou") { return "syosetu" }
        if contains("hameln") { return "hameln" }
        if contains("wayback machine", "web.archive.org") { return "waybackmachine" }
        if contains("talk.op.gg", "talkopgg") { return "talkopgg" }
        if contains("manatoki") { return "manatoki" }
        if contains("nottoki") { return "nottoki" }
        if contains("jmana") { return "jmana" }
        if contains("lhscan") { return "lhscan" }
        if contains("4chan") { return "4chan" }
        if contains("danbooru") { return "danbooru" }
        if contains("gelbooru") { return "gelbooru" }
        if contains("yande.re") { return "yande.re" }
        if contains("rule34.xxx") { return "rule34_xxx" }
        if contains("sankaku") { return "sankaku" }
        if contains("nozomi") { return "nozomi" }
        if contains("fc2") { return "fc2" }
        if contains("m3u8", ".m3u8") { return "m3u8" }
        if contains("custom command", "custom extractor", "custom plugin") { return "custom" }
        return fallbackResourceKey
    }

    static func image(source: String, metadata: [String: String]) -> NSImage? {
        image(resourceKey: resourceKey(source: source, metadata: metadata)) ??
            image(resourceKey: fallbackResourceKey)
    }

    static func image(resourceKey: String) -> NSImage? {
        if let cached = cache.object(forKey: resourceKey as NSString) {
            return cached
        }
        guard let resourceURL = Bundle.main.resourceURL?
            .appendingPathComponent("SiteFavicons", isDirectory: true)
            .appendingPathComponent("\(resourceKey).png"),
              let image = NSImage(contentsOf: resourceURL) else {
            return nil
        }
        image.isTemplate = false
        cache.setObject(image, forKey: resourceKey as NSString)
        return image
    }
}
