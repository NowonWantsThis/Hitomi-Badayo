import CryptoKit
import Foundation

struct NaverTVVideoPair: Hashable {
    var videoID: String
    var key: String
}

struct NaverTVVideoCandidate {
    var url: URL
    var width: Int
    var height: Int
    var size: Int64?
    var videoBitrate: Int?
    var audioBitrate: Int?
    var formatID: String
}

struct NaverTVPlayInfo {
    var clipID: String
    var pair: NaverTVVideoPair
    var title: String?
    var thumbnail: URL?
    var uploader: String?
    var uploaderID: String?
    var uploaderURL: URL?
}

final class NaverTVResolver {
    static let originalSegmentSize: Int64 = 1_048_576
    static let originalDefaultSegmentThreads = 4

    private static let signingKey = "nbxvs5nwNG9QKEWK0ADjYA4JZoujF4gHcIwvoCxFTPAeamq5eemvt5IWAYXxrbYM"
    private let millisecondsProvider: () -> Int64

    init(millisecondsProvider: @escaping () -> Int64 = {
        Int64(Date().timeIntervalSince1970 * 1_000)
    }) {
        self.millisecondsProvider = millisecondsProvider
    }

    func canResolve(_ url: URL) -> Bool {
        Self.clipID(from: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        guard let clipID = Self.clipID(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let pageURL = Self.canonicalURL(for: url) ?? url
        let playInfoURL = Self.playInfoAPIURL(
            clipID: clipID,
            sourceURL: pageURL,
            milliseconds: millisecondsProvider()
        )
        let playInfoData = try await HTTPClient.shared.data(
            from: playInfoURL,
            userAgent: headers.userAgent
        )
        let playInfo = try Self.playInfo(
            fromAPIData: playInfoData,
            clipID: clipID,
            sourceURL: pageURL
        )
        let mediaURL = Self.mediaAPIURL(for: playInfo.pair, sourceURL: pageURL)
        let mediaData = try await HTTPClient.shared.data(
            from: mediaURL,
            userAgent: headers.userAgent
        )
        return try Self.resolvedDownload(
            playInfo: playInfo,
            mediaData: mediaData,
            pageURL: pageURL,
            userAgent: headers.userAgent
        )
    }

    static func clipID(from url: URL) -> String? {
        guard let host = url.host?.lowercased(),
              isNaverTVHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }

        let parts = url.path.split(separator: "/").map(String.init)
        for marker in ["v", "embed"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count else {
                continue
            }
            let id = parts[index + 1]
            if isNumeric(id) {
                return id
            }
        }

        let queryItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        for name in ["clipNo", "clipno", "videoId"] {
            if let value = queryItems.first(where: { $0.name.lowercased() == name.lowercased() })?.value,
               isNumeric(value) {
                return value
            }
        }
        return nil
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let clipID = clipID(from: url),
              let host = url.host?.lowercased() else {
            return nil
        }
        return canonicalURL(clipID: clipID, sourceHost: host, scheme: url.scheme)
    }

    static func canonicalURL(clipID: String, sourceURL: URL? = nil) -> URL? {
        let trimmedID = clipID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isNumeric(trimmedID) else { return nil }
        return canonicalURL(
            clipID: trimmedID,
            sourceHost: sourceURL?.host?.lowercased(),
            scheme: sourceURL?.scheme
        )
    }

    private static func canonicalURL(clipID: String, sourceHost: String?, scheme: String?) -> URL? {
        var components = URLComponents()
        components.scheme = scheme ?? "https"
        components.host = sourceHost?.hasSuffix(".test") == true ? "tv.naver.test" : "tv.naver.com"
        components.path = "/v/\(clipID)"
        return components.url
    }

    static func playInfoAPIURL(clipID: String, sourceURL: URL, milliseconds: Int64) -> URL {
        var endpoint = URLComponents()
        endpoint.scheme = "https"
        endpoint.host = sourceURL.host?.lowercased().hasSuffix(".test") == true
            ? "apis.naver.test"
            : "apis.naver.com"
        endpoint.path = "/now_web2/now_web_api/v1/clips/\(clipID)/play-info"
        let unsignedURL = endpoint.url!
        let message = String(unsignedURL.absoluteString.prefix(255)) + String(milliseconds)
        let authentication = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(message.utf8),
            using: SymmetricKey(data: Data(signingKey.utf8))
        )
        let md = Data(authentication).base64EncodedString()
        endpoint.percentEncodedQuery = "msgpad=\(milliseconds)&md=\(percentEncodedQueryValue(md))"
        return endpoint.url!
    }

    static func mediaAPIURL(for pair: NaverTVVideoPair, sourceURL: URL) -> URL {
        let isFixture = sourceURL.host?.lowercased().hasSuffix(".test") == true
        var components = URLComponents()
        components.scheme = isFixture ? "https" : "http"
        components.host = isFixture ? "play.rmcnmv.naver.test" : "play.rmcnmv.naver.com"
        components.path = "/vod/play/v2.0/\(pair.videoID)"
        components.percentEncodedQuery = "key=\(percentEncodedQueryValue(pair.key))"
        return components.url!
    }

    static func playInfo(
        fromAPIData data: Data,
        clipID: String,
        sourceURL: URL
    ) throws -> NaverTVPlayInfo {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let result = root["result"] as? [String: Any] ?? root
        let clip = result["clip"] as? [String: Any] ?? [:]
        let play = result["play"] as? [String: Any] ?? [:]
        guard let videoID = stringValue(clip["videoId"])?.trimmed,
              !videoID.isEmpty,
              let key = stringValue(play["inKey"])?.trimmed,
              !key.isEmpty else {
            throw NativeDownloadError.unsupported("Naver TV video information was not available.")
        }

        return NaverTVPlayInfo(
            clipID: clipID,
            pair: NaverTVVideoPair(videoID: videoID, key: key),
            title: nonEmptyString(clip["title"]),
            thumbnail: nonEmptyString(clip["thumbnailImageUrl"]).flatMap {
                absoluteHTTPURL($0, baseURL: sourceURL)
            },
            uploader: nonEmptyString(clip["channelName"]),
            uploaderID: nonEmptyString(clip["channelId"]),
            uploaderURL: nonEmptyString(clip["channelUrl"]).flatMap {
                absoluteHTTPURL($0, baseURL: sourceURL)
            }
        )
    }

    static func selectedCandidate(fromAPIData data: Data, sourceURL: URL) throws -> NaverTVVideoCandidate? {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        guard let videos = root["videos"] as? [String: Any],
              let list = videos["list"] as? [[String: Any]] else {
            return nil
        }

        var selected: NaverTVVideoCandidate?
        for item in list {
            guard let rawURL = nonEmptyString(item["source"]),
                  let url = absoluteHTTPURL(rawURL, baseURL: sourceURL),
                  !isPlaylistURL(url) else {
                continue
            }
            let encoding = item["encodingOption"] as? [String: Any] ?? [:]
            let bitrate = item["bitrate"] as? [String: Any] ?? [:]
            let candidate = NaverTVVideoCandidate(
                url: url,
                width: positiveInt(encoding["width"]) ?? positiveInt(item["width"]) ?? 0,
                height: positiveInt(encoding["height"]) ?? positiveInt(item["height"]) ?? 0,
                size: int64Value(item["size"]),
                videoBitrate: positiveInt(bitrate["video"]),
                audioBitrate: positiveInt(bitrate["audio"]),
                formatID: nonEmptyString(encoding["name"] ?? encoding["id"]) ?? nonEmptyString(item["type"]) ?? ""
            )
            if selected == nil || candidate.width > selected!.width {
                selected = candidate
            }
        }
        return selected
    }

    static func resolvedDownload(
        playInfo: NaverTVPlayInfo,
        mediaData: Data,
        pageURL: URL,
        userAgent: String? = nil
    ) throws -> ResolvedDownload {
        guard let root = try JSONSerialization.jsonObject(with: mediaData) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        guard let candidate = try selectedCandidate(fromAPIData: mediaData, sourceURL: pageURL) else {
            throw NativeDownloadError.unsupported("No MP4 videos")
        }

        let meta = root["meta"] as? [String: Any] ?? [:]
        let mediaUser = meta["user"] as? [String: Any] ?? [:]
        let cover = meta["cover"] as? [String: Any] ?? [:]
        let title = cleanTitle(
            playInfo.title ?? nonEmptyString(meta["subject"]) ?? playInfo.clipID,
            fallback: playInfo.clipID
        )
        let thumbnail = playInfo.thumbnail ?? nonEmptyString(cover["source"]).flatMap {
            absoluteHTTPURL($0, baseURL: pageURL)
        }
        let uploader = playInfo.uploader ?? nonEmptyString(mediaUser["name"])
        let uploaderID = playInfo.uploaderID ?? nonEmptyString(mediaUser["id"])
        let uploaderURL = playInfo.uploaderURL ?? nonEmptyString(mediaUser["url"]).flatMap {
            absoluteHTTPURL($0, baseURL: pageURL)
        }
        let format = mediaFormat(for: candidate.url)
        let filename = "\(title) (\(playInfo.clipID)).\(format)".sanitizedFilename(maxLength: 180)
        let metadata = commonMetadata(
            title: title,
            pageURL: pageURL,
            playInfo: playInfo,
            candidate: candidate,
            thumbnail: thumbnail,
            uploader: uploader,
            uploaderID: uploaderID,
            uploaderURL: uploaderURL
        )
        var assetMetadata = metadata
        assetMetadata["page"] = "1"
        assetMetadata["position"] = "1"
        assetMetadata["remote_segment_size"] = String(originalSegmentSize)

        return ResolvedDownload(
            title: title,
            folderName: "Naver TV \(title)".sanitizedFilename(maxLength: 120),
            assets: [
                ResolvedAsset(
                    remoteURL: candidate.url,
                    filename: filename,
                    metadata: assetMetadata,
                    referer: pageURL.absoluteString,
                    userAgent: userAgent
                )
            ],
            packageMode: .concatenate(outputFilename: filename),
            metadata: metadata
        )
    }

    private static func commonMetadata(
        title: String,
        pageURL: URL,
        playInfo: NaverTVPlayInfo,
        candidate: NaverTVVideoCandidate,
        thumbnail: URL?,
        uploader: String?,
        uploaderID: String?,
        uploaderURL: URL?
    ) -> [String: String] {
        let resolution = candidate.height > 0 ? "\(candidate.height)p" : ""
        return DownloadMetadata.clean([
            "site": "Naver TV",
            "title": title,
            "series": title,
            "category": "video",
            "type": "video",
            "media_type": "video",
            "format": mediaFormat(for: candidate.url),
            "media_format": mediaFormat(for: candidate.url),
            "host": pageURL.host ?? "",
            "id": playInfo.clipID,
            "clip_id": playInfo.clipID,
            "video_id": playInfo.pair.videoID,
            "media_id": playInfo.clipID,
            "gallery_id": playInfo.clipID,
            "media_count": "1",
            "video_count": "1",
            "width": candidate.width > 0 ? String(candidate.width) : "",
            "height": candidate.height > 0 ? String(candidate.height) : "",
            "resolution": resolution,
            "quality": candidate.formatID.isEmpty ? resolution : candidate.formatID,
            "filesize": candidate.size.map(String.init) ?? "",
            "video_bitrate": candidate.videoBitrate.map(String.init) ?? "",
            "audio_bitrate": candidate.audioBitrate.map(String.init) ?? "",
            "uploader": uploader ?? "",
            "uploader_id": uploaderID ?? "",
            "uploader_url": uploaderURL?.absoluteString ?? "",
            "thumbnail": thumbnail?.absoluteString ?? "",
            "thumbnail_referer_disabled": "true",
            "video_url": candidate.url.absoluteString,
            "media_url": candidate.url.absoluteString,
            "url": pageURL.absoluteString,
            "source_url": pageURL.absoluteString,
            "page_url": pageURL.absoluteString,
            "segment_size": String(originalSegmentSize),
            "original_default_segment_threads": String(originalDefaultSegmentThreads),
            "transfer": "http-range",
            "original_contract": "navertv-4.2-improved-runtime"
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        return ext.isEmpty ? "mp4" : ext
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        let title = decodeHTML(raw)
            .replacingOccurrences(of: #"<[^>]+>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmed
        return title.isEmpty ? fallback : title
    }

    private static func isPlaylistURL(_ url: URL) -> Bool {
        let value = url.absoluteString.lowercased()
        return url.pathExtension.lowercased() == "m3u8" || value.contains(".m3u8")
    }

    private static func isNaverTVHost(_ host: String) -> Bool {
        host == "tv.naver.com" ||
            host == "m.tv.naver.com" ||
            host == "tvcast.naver.com" ||
            host == "m.tvcast.naver.com" ||
            host == "tv.naver.test" ||
            host == "m.tv.naver.test" ||
            host == "tvcast.naver.test" ||
            host == "m.tvcast.naver.test"
    }

    private static func absoluteHTTPURL(_ raw: String, baseURL: URL) -> URL? {
        var value = decodeHTML(raw).trimmed
        if value.hasPrefix("//") {
            value = "\(baseURL.scheme ?? "https"):\(value)"
        }
        guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    private static func percentEncodedQueryValue(_ value: String) -> String {
        let unreserved = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let value = stringValue(value)?.trimmed, !value.isEmpty else { return nil }
        return value
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func positiveInt(_ value: Any?) -> Int? {
        guard let value = int64Value(value), value > 0, value <= Int64(Int.max) else { return nil }
        return Int(value)
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let number = value as? NSNumber { return number.int64Value }
        if let string = value as? String { return Int64(string) }
        return nil
    }

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
