import Foundation
import WebKit

struct KakaoWebtoonEpisode: Hashable {
    var contentID: String
    var episodeID: String
    var seoID: String
    var title: String
    var number: Int
}

struct KakaoWebtoonRenderedPage {
    var episode: KakaoWebtoonEpisode
    var imageFiles: [URL]
    var title: String?
}

final class KakaoWebtoonResolver {
    private let episodePageLimit = 100
    private let episodePageSize = 30

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isKakaoWebtoonHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let path = url.path.lowercased()
        return path.contains("/content/") || path.contains("/viewer/")
    }

    @MainActor
    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        if let episode = Self.viewerEpisode(from: url) {
            let rendered = try await KakaoWebtoonPageRenderer.render(episode: episode, sourceURL: url, headers: headers)
            return try Self.resolvedDownload(title: rendered.title ?? episode.title, sourceURL: url, renderedPages: [rendered])
        }

        guard let contentID = try await contentID(from: url, headers: headers) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let title = try await contentTitle(from: url, headers: headers) ?? "Kakao Webtoon \(contentID)"
        let episodes = try await loadEpisodes(contentID: contentID, sourceURL: url, headers: headers)
        var renderedPages: [KakaoWebtoonRenderedPage] = []

        for episode in episodes {
            try Task.checkCancellation()
            let viewerURL = Self.viewerURL(for: episode, sourceURL: url)
            let rendered = try await KakaoWebtoonPageRenderer.render(episode: episode, sourceURL: viewerURL, headers: headers)
            renderedPages.append(rendered)
        }

        return try Self.resolvedDownload(title: title, sourceURL: url, renderedPages: renderedPages)
    }

    private func contentID(from url: URL, headers: HTTPRequestOptions) async throws -> String? {
        if let id = Self.contentID(fromPath: url.path) {
            return id
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return Self.contentID(fromHTML: html)
    }

    private func contentTitle(from url: URL, headers: HTTPRequestOptions) async throws -> String? {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        return Self.title(fromHTML: html)
    }

    private func loadEpisodes(contentID: String, sourceURL: URL, headers: HTTPRequestOptions) async throws -> [KakaoWebtoonEpisode] {
        var episodes: [KakaoWebtoonEpisode] = []
        var seen = Set<String>()
        var offset = 0

        for _ in 0..<episodePageLimit {
            try Task.checkCancellation()
            let pageURL = Self.episodeListURL(contentID: contentID, offset: offset, limit: episodePageSize, sourceURL: sourceURL)
            let data = try await HTTPClient.shared.data(
                from: pageURL,
                referer: headers.referer ?? sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders(sourceURL: sourceURL)
            )
            let page = try Self.episodes(fromListData: data, contentID: contentID)
            for episode in page.episodes where !seen.contains(episode.episodeID) {
                seen.insert(episode.episodeID)
                episodes.append(episode)
            }
            if page.isLast {
                break
            }
            offset += episodePageSize
        }

        let sorted = episodes.sorted { lhs, rhs in
            if lhs.number == rhs.number {
                return lhs.episodeID < rhs.episodeID
            }
            return lhs.number < rhs.number
        }
        guard !sorted.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return sorted
    }

    static func resolvedDownload(title: String, sourceURL: URL, renderedPages: [KakaoWebtoonRenderedPage]) throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        let cleanTitle = title.sanitizedFilename(maxLength: 120)

        for page in renderedPages.sorted(by: { $0.episode.number < $1.episode.number }) {
            let episodeTitle = episodeOutputTitle(for: page)
            let pageTitle = episodeTitle.sanitizedFilename(maxLength: 100)
            let prefix = String(format: "%04d - %@", page.episode.number, pageTitle).sanitizedFilename(maxLength: 120)
            let contentID = contentID(for: page.episode, sourceURL: sourceURL)
            let viewerURL = Self.viewerURL(for: page.episode, sourceURL: sourceURL)
            for (offset, fileURL) in page.imageFiles.enumerated() {
                let normalized = URLIdentity.normalize(fileURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                let index = offset + 1
                assets.append(ResolvedAsset(
                    remoteURL: fileURL,
                    filename: String(format: "%@ - %04d.jpg", prefix, index).sanitizedFilename(maxLength: 180),
                    metadata: assetMetadata(
                        seriesTitle: cleanTitle,
                        episodeTitle: episodeTitle,
                        contentID: contentID,
                        episode: page.episode,
                        fileURL: fileURL,
                        viewerURL: viewerURL,
                        index: index
                    ),
                    referer: viewerURL.absoluteString
                ))
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: cleanTitle,
            folderName: "KakaoWebtoon \(cleanTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: kakaoWebtoonMetadata(seriesTitle: cleanTitle, sourceURL: sourceURL, renderedPages: renderedPages, imageCount: assets.count)
        )
    }

    static func episodeListURL(contentID: String, offset: Int, limit: Int, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "gateway-kw.kakao.test" : "gateway-kw.kakao.com"
        components.path = "/episode/v1/views/content-home/contents/\(contentID)/episodes"
        components.queryItems = [
            URLQueryItem(name: "sort", value: "-NO"),
            URLQueryItem(name: "offset", value: String(offset)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        return components.url!
    }

    static func episodes(fromListData data: Data, contentID: String) throws -> (episodes: [KakaoWebtoonEpisode], isLast: Bool) {
        let object = try jsonObject(from: data)
        let dataObject = object["data"] as? [String: Any] ?? object
        let episodeObjects = dataObject["episodes"] as? [[String: Any]] ?? []
        var episodes: [KakaoWebtoonEpisode] = []

        for item in episodeObjects {
            let readable = boolValue(item["readable"]) ?? true
            guard readable,
                  let episodeID = stringValue(item["id"]),
                  let seoID = stringValue(item["seoId"]) ?? stringValue(item["seoID"]) ?? stringValue(item["seo_id"]) else {
                continue
            }

            let number = intValue(item["no"]) ?? intValue(item["episodeNo"]) ?? episodes.count + 1
            let title = cleanTitle(stringValue(item["title"]) ?? "Episode \(number)")
            episodes.append(KakaoWebtoonEpisode(
                contentID: contentID,
                episodeID: episodeID,
                seoID: seoID,
                title: title,
                number: number
            ))
        }

        let isLast = boolValue(dictionary(at: ["meta", "pagination"], in: object)?["last"]) ??
            boolValue(dictionary(at: ["pagination"], in: object)?["last"]) ??
            episodeObjects.isEmpty

        return (episodes, isLast)
    }

    static func viewerEpisode(from url: URL) -> KakaoWebtoonEpisode? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let viewerIndex = parts.firstIndex(where: { $0.lowercased() == "viewer" }),
              viewerIndex + 2 < parts.count else {
            return nil
        }

        let seoID = parts[viewerIndex + 1].removingPercentEncoding ?? parts[viewerIndex + 1]
        let episodeID = parts[viewerIndex + 2].removingPercentEncoding ?? parts[viewerIndex + 2]
        guard !seoID.isEmpty, !episodeID.isEmpty else { return nil }

        return KakaoWebtoonEpisode(
            contentID: Self.contentID(fromQuery: url) ?? "",
            episodeID: episodeID,
            seoID: seoID,
            title: "Episode \(episodeID)",
            number: intValue(episodeID) ?? 1
        )
    }

    static func viewerURL(for episode: KakaoWebtoonEpisode, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "webtoon.kakao.test" : "webtoon.kakao.com"
        components.path = "/viewer/\(episode.seoID)/\(episode.episodeID)"
        return components.url!
    }

    static func kakaoWebtoonMetadata(seriesTitle: String, sourceURL: URL, renderedPages: [KakaoWebtoonRenderedPage], imageCount: Int? = nil) -> [String: String] {
        let episodes = renderedPages.map(\.episode)
        let first = episodes.first
        let contentID = first?.contentID.trimmed.isEmpty == false
            ? first?.contentID ?? ""
            : contentID(fromPath: sourceURL.path) ?? contentID(fromQuery: sourceURL) ?? ""
        let episodeIDs = episodes.map(\.episodeID).filter { !$0.isEmpty }
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": "webtoon",
            "type": episodes.count == 1 ? "episode" : "series",
            "media_type": "image",
            "content_id": contentID,
            "work_id": contentID,
            "episode_id": episodeIDs.first ?? "",
            "chapter_id": episodeIDs.first ?? "",
            "gallery_id": contentID.isEmpty ? episodeIDs.first ?? "" : contentID,
            "episode_count": String(episodes.count),
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "slug": first?.seoID ?? contentID,
            "site": "KakaoWebtoon",
            "title": seriesTitle
        ])
    }

    private static func contentID(for episode: KakaoWebtoonEpisode, sourceURL: URL) -> String {
        let direct = episode.contentID.trimmed
        if !direct.isEmpty {
            return direct
        }
        return contentID(fromPath: sourceURL.path) ?? contentID(fromQuery: sourceURL) ?? ""
    }

    private static func episodeOutputTitle(for page: KakaoWebtoonRenderedPage) -> String {
        let episodeTitle = cleanTitle(page.episode.title)
        if !episodeTitle.isEmpty && !episodeTitle.lowercased().hasPrefix("episode ") {
            return episodeTitle
        }

        if let renderedTitle = page.title?.trimmed, !renderedTitle.isEmpty {
            return cleanTitle(renderedTitle)
        }

        return episodeTitle.isEmpty ? "Episode \(page.episode.episodeID)" : episodeTitle
    }

    private static func assetMetadata(seriesTitle: String, episodeTitle: String, contentID: String, episode: KakaoWebtoonEpisode, fileURL: URL, viewerURL: URL, index: Int) -> [String: String] {
        let id = episode.episodeID.isEmpty ? contentID : episode.episodeID
        let format = mediaFormat(for: fileURL)
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "category": "webtoon",
            "episode": episodeTitle,
            "chapter": episodeTitle,
            "type": "image",
            "media_type": "image",
            "content_id": contentID,
            "work_id": contentID,
            "episode_id": episode.episodeID,
            "chapter_id": episode.episodeID,
            "gallery_id": id,
            "id": id,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "image_url": fileURL.absoluteString,
            "media_url": fileURL.absoluteString,
            "source_url": fileURL.absoluteString,
            "page_url": viewerURL.absoluteString,
            "site": "KakaoWebtoon",
            "title": episodeTitle
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    static func contentID(fromPath path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let contentIndex = parts.firstIndex(where: { $0.lowercased() == "content" }) else {
            return nil
        }

        for part in parts[(contentIndex + 1)...].reversed() {
            let decoded = part.removingPercentEncoding ?? part
            if decoded.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
                return decoded
            }
        }
        return nil
    }

    static func contentID(fromHTML html: String) -> String? {
        if let data = nextData(fromHTML: html),
           let object = try? jsonObject(from: data),
           let id = stringValue(dictionary(at: ["props", "initialProps", "pageProps"], in: object)?["id"]) ??
            stringValue(dictionary(at: ["props", "pageProps"], in: object)?["id"]) {
            return id
        }
        return nil
    }

    static func title(fromHTML html: String) -> String? {
        let decoded = decodeHTML(html)
        let title = metaContent(from: decoded, names: ["og:title", "twitter:title"]) ??
            titleTag(from: decoded)
        return title.map(cleanTitle)
    }

    static func blobImageScript() -> String {
        """
        (async function() {
          var stable = 0;
          var previous = -1;
          for (var tries = 0; tries < 80 && stable < 3; tries++) {
            window.scrollTo(0, document.body.scrollHeight);
            await new Promise(function(resolve) { setTimeout(resolve, 250); });
            var count = Array.from(document.getElementsByTagName('img')).filter(function(img) {
              return img.src && img.src.indexOf('blob:') === 0 && img.naturalWidth > 0 && img.naturalHeight > 0;
            }).length;
            if (count === previous) {
              stable += 1;
            } else {
              previous = count;
              stable = 0;
            }
          }
          var srcs = Array.from(document.getElementsByTagName('img')).filter(function(img) {
            return img.src && img.src.indexOf('blob:') === 0 && img.naturalWidth > 0 && img.naturalHeight > 0;
          }).map(function(img) { return img.src; });
          var canvas = document.createElement('canvas');
          var ctx = canvas.getContext('2d');
          var imgsAll = document.getElementsByTagName('img');
          var output = [];
          var step = 64;
          for (var p = 0; p < srcs.length; p += step) {
            var srcChunk = srcs.slice(p, p + step);
            for (var j = 0; j < srcChunk.length; j++) {
              var img = null;
              for (var i = 0; i < imgsAll.length; i++) {
                if (imgsAll[i].src === srcChunk[j]) {
                  img = imgsAll[i];
                  break;
                }
              }
              if (!img || img.naturalWidth <= 0 || img.naturalHeight <= 0) {
                continue;
              }
              canvas.width = img.naturalWidth;
              canvas.height = img.naturalHeight;
              ctx.drawImage(img, 0, 0);
              output.push(canvas.toDataURL('image/jpeg', 0.9).slice(23));
            }
          }
          return {
            title: document.title || '',
            images: output
          };
        })();
        """
    }

    private static func nextData(fromHTML html: String) -> Data? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<script\b[^>]*\bid\s*=\s*["']__NEXT_DATA__["'][^>]*>(.*?)</script>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let text = decodeHTML(String(html[capture]))
        return text.data(using: .utf8)
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func titleTag(from html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let titleRange = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let title = stripTags(String(html[titleRange])).trimmed
        return title.isEmpty ? nil : title
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
        text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = stripTags(raw)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" | 카카오웹툰", " - 카카오웹툰", " | Kakao Webtoon", " - Kakao Webtoon"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? "Kakao Webtoon" : title
    }

    private static func apiHeaders(sourceURL: URL) -> [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "Accept-Language": "ko-KR,ko;q=0.9,en-US;q=0.8,en;q=0.7",
            "Origin": baseURL(for: sourceURL).absoluteString
        ]
    }

    private static func baseURL(for sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "webtoon.kakao.test" : "webtoon.kakao.com"
        return components.url!
    }

    private static func contentID(fromQuery url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { ["contentid", "content_id", "cid"].contains($0.name.lowercased()) }?
            .value
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func dictionary(at path: [String], in object: [String: Any]) -> [String: Any]? {
        var current: Any? = object
        for key in path {
            current = (current as? [String: Any])?[key]
        }
        return current as? [String: Any]
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

    private static func boolValue(_ value: Any?) -> Bool? {
        if let bool = value as? Bool { return bool }
        if let number = value as? NSNumber { return number.boolValue }
        if let string = value as? String {
            let lower = string.trimmed.lowercased()
            if ["true", "1", "yes", "y"].contains(lower) { return true }
            if ["false", "0", "no", "n"].contains(lower) { return false }
        }
        return nil
    }

    private static func decodeHTML(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }

    private static func isKakaoWebtoonHost(_ host: String) -> Bool {
        host == "webtoon.kakao.com" ||
            host == "webtoon.kakao.test"
    }
}

@MainActor
private final class KakaoWebtoonPageRenderer: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?
    private let webView: WKWebView

    override init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let preferences = WKWebpagePreferences()
        preferences.allowsContentJavaScript = true
        configuration.defaultWebpagePreferences = preferences
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1200, height: 1600), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    static func render(episode: KakaoWebtoonEpisode, sourceURL: URL, headers: HTTPRequestOptions) async throws -> KakaoWebtoonRenderedPage {
        let renderer = KakaoWebtoonPageRenderer()
        return try await renderer.render(episode: episode, sourceURL: sourceURL, headers: headers)
    }

    func render(episode: KakaoWebtoonEpisode, sourceURL: URL, headers: HTTPRequestOptions) async throws -> KakaoWebtoonRenderedPage {
        try await load(sourceURL: sourceURL, headers: headers)
        let result = try await evaluateBlobImages()
        let imageFiles = try writeImages(result.images, episode: episode)
        guard !imageFiles.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        return KakaoWebtoonRenderedPage(episode: episode, imageFiles: imageFiles, title: result.title)
    }

    private func load(sourceURL: URL, headers: HTTPRequestOptions) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            self.continuation = continuation
            var request = URLRequest(url: sourceURL)
            if let referer = headers.referer {
                request.setValue(referer, forHTTPHeaderField: "Referer")
            }
            if let userAgent = headers.userAgent {
                webView.customUserAgent = userAgent
            }
            webView.load(request)
        }
    }

    private func evaluateBlobImages() async throws -> (title: String?, images: [String]) {
        let value = try await webView.evaluateJavaScript(KakaoWebtoonResolver.blobImageScript())
        guard let result = value as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        let title = (result["title"] as? String)?.trimmed
        let images = result["images"] as? [String] ?? []
        return (title?.isEmpty == true ? nil : title, images)
    }

    private func writeImages(_ images: [String], episode: KakaoWebtoonEpisode) throws -> [URL] {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-KakaoWebtoon-\(UUID().uuidString)", isDirectory: true)
        try AppPaths.ensureDirectory(folder)

        return try images.enumerated().compactMap { offset, base64 in
            guard let data = Data(base64Encoded: base64) else { return nil }
            let url = folder.appendingPathComponent(String(format: "%04d.jpg", offset + 1))
            try data.write(to: url, options: .atomic)
            return url
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
}
