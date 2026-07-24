import Foundation

struct DownloadSourceFolderProfile: Identifiable, Hashable {
    let id: String

    var displayName: String {
        Self.displayNames[id] ?? id
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .capitalized
    }

    var faviconKey: String {
        id == "local" ? "file" : id
    }

    var defaultFolderName: String {
        Self.defaultFolderName(for: id)
    }

    var supportsFolderArchive: Bool {
        !Self.singleFileSourceIDs.contains(id)
    }

    static let originalDefaultFolderTemplate = "[artist] title (id)"

    static let settingsProfiles: [DownloadSourceFolderProfile] = settingsSourceIDs.map {
        DownloadSourceFolderProfile(id: $0)
    }

    static func defaultFolderName(for sourceID: String) -> String {
        let normalized = normalizedSourceID(sourceID)
        guard normalized != "hitomi" else { return "hitomi_downloaded" }
        return "\(defaultFolderStem(for: normalized))_downloaded"
    }

    static func obsoleteDefaultFolderNames(for sourceID: String) -> Set<String> {
        let normalized = normalizedSourceID(sourceID)
        guard normalized != "hitomi" else { return [] }
        return Set([
            "hitomi_downloaded_\(normalized)",
            "\(normalized)_downloaded"
        ]).subtracting([defaultFolderName(for: normalized)])
    }

    private static func defaultFolderStem(for normalizedSourceID: String) -> String {
        intuitiveFolderStems[normalizedSourceID] ?? normalizedSourceID
    }

    static func sourceID(for sourceURL: URL, metadata: [String: String] = [:]) -> String {
        if sourceURL.scheme?.lowercased() == "magnet" {
            return "torrent"
        }
        if sourceURL.isFileURL {
            return "local"
        }

        let resourceKey = SiteFaviconCatalog.resourceKey(
            source: sourceURL.absoluteString,
            metadata: metadata
        )
        switch resourceKey {
        case "hitomi", "ehen", "hiyobi":
            return "hitomi"
        case "pixiv_comic":
            return "pixiv"
        case "file":
            return "local"
        case "unknown":
            return fallbackSourceID(for: sourceURL)
        default:
            return normalizedSourceID(resourceKey)
        }
    }

    static func normalizedSourceID(_ rawValue: String) -> String {
        var value = rawValue.trimmed.lowercased()
        value = value.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        value = value.replacingOccurrences(of: "[^a-z0-9._-]+", with: "_", options: .regularExpression)
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "._-"))
        return value.isEmpty ? "downloads" : value
    }

    static func isSettingsSourceID(_ sourceID: String) -> Bool {
        settingsSourceIDs.contains(normalizedSourceID(sourceID))
    }

    private static func fallbackSourceID(for sourceURL: URL) -> String {
        guard var host = sourceURL.host?.lowercased(), !host.isEmpty else {
            return "downloads"
        }
        host = host.replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        if host.hasSuffix(".test") {
            host.removeLast(".test".count)
        }

        var parts = host.split(separator: ".").map(String.init)
        while let first = parts.first, ["www", "m", "mobile", "cdn", "media"].contains(first) {
            parts.removeFirst()
        }
        guard !parts.isEmpty else { return "downloads" }

        var candidate = parts.count > 1 ? parts[parts.count - 2] : parts[0]
        if ["co", "com", "net", "org", "ac"].contains(candidate), parts.count > 2 {
            candidate = parts[parts.count - 3]
        }
        return normalizedSourceID(candidate)
    }

    private static let settingsSourceIDs = [
        "hitomi",
        "pixiv",
        "pawchive",
        "youtube",
        "insta",
        "twitter",
        "twitch",
        "torrent",
        "afreeca",
        "artstation",
        "asmhentai",
        "avgle",
        "bcy",
        "bdsmlr",
        "bili",
        "bsky",
        "chzzk",
        "comicwalker",
        "coub",
        "danbooru",
        "deviant",
        "discord",
        "facebook",
        "fc2",
        "flickr",
        "hanime",
        "hf",
        "imgur",
        "iwara",
        "jmana",
        "kakaopage",
        "kakaotv",
        "kakaowebtoon",
        "kakuyomu",
        "kissjav",
        "lhscan",
        "local",
        "luscious",
        "m3u8",
        "manatoki",
        "mastodon",
        "misskey",
        "mrm",
        "naver",
        "navercafe",
        "naverpost",
        "navertoon",
        "navertv",
        "newgrounds",
        "nhentai",
        "nhentai_com",
        "nico",
        "nijie",
        "nozomi",
        "pinter",
        "pornhub",
        "sankaku",
        "soundcloud",
        "syosetu",
        "talkopgg",
        "tiktok",
        "tokyomotion",
        "tumblr",
        "v2ph",
        "vimeo",
        "waybackmachine",
        "webtoon",
        "weibo",
        "wikiart",
        "xhamster",
        "xnxx",
        "xvideo",
        "yande.re",
        "youku",
        "youporn"
    ]

    private static let singleFileSourceIDs: Set<String> = [
        "local",
        "m3u8"
    ]

    private static let displayNames: [String: String] = [
        "hitomi": "Hitomi.la / E(x)Hentai",
        "pixiv": "Pixiv",
        "pawchive": "Pawchive",
        "youtube": "YouTube",
        "insta": "Instagram",
        "twitter": "Twitter / X",
        "twitch": "Twitch",
        "torrent": "Torrent / Magnet",
        "afreeca": "SOOP / AfreecaTV",
        "asmhentai": "AsmHentai",
        "bili": "Bilibili",
        "bsky": "Bluesky",
        "comicwalker": "ComicWalker",
        "deviant": "DeviantArt",
        "hf": "Hentai Foundry",
        "jmana": "JMana",
        "kakaopage": "KakaoPage",
        "kakaotv": "KakaoTV",
        "kakaowebtoon": "Kakao Webtoon",
        "kissjav": "KissJAV",
        "local": "Local Files",
        "mrm": "MyReadingManga",
        "navercafe": "Naver Cafe",
        "naverpost": "Naver Post",
        "navertoon": "Naver Webtoon",
        "navertv": "Naver TV",
        "nhentai_com": "nhentai.com",
        "nico": "Niconico",
        "pinter": "Pinterest",
        "syosetu": "Shosetsuka ni Naro",
        "talkopgg": "Talk OP.GG",
        "tokyomotion": "TokyoMotion",
        "v2ph": "V2PH",
        "waybackmachine": "Wayback Machine",
        "xvideo": "XVideos",
        "yande.re": "yande.re",
        "youporn": "YouPorn"
    ]

    private static let intuitiveFolderStems: [String: String] = [
        "afreeca": "soop",
        "bili": "bilibili",
        "bsky": "bluesky",
        "deviant": "deviantart",
        "hf": "hentai_foundry",
        "insta": "instagram",
        "mrm": "myreadingmanga",
        "navertoon": "naver_webtoon",
        "pinter": "pinterest",
        "syosetu": "narou",
        "talkopgg": "talk_opgg",
        "waybackmachine": "wayback_machine",
        "xvideo": "xvideos",
        "yande.re": "yande_re"
    ]
}
