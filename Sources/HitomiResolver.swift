import Foundation
import JavaScriptCore

@MainActor
final class HitomiResolver {
    private let scriptEngine = HitomiScriptEngine.shared
    private let defaultResolutionAttempts = 8
    nonisolated static let requestUserAgent =
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) " +
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/135.0.0.0 Safari/537.36"
#if TESTING
    private let resolutionRetryDelayNanoseconds: UInt64 = 0
#else
    private let resolutionRetryDelayNanoseconds: UInt64 = 500_000_000
#endif

    func canResolve(_ url: URL) -> Bool {
        let host = url.host?.lowercased() ?? ""
        return host == "hitomi.la" || host.hasSuffix(".hitomi.la")
    }

    func resolve(
        _ url: URL,
        preferWebP: Bool,
        maximumAttempts: Int? = nil
    ) async throws -> ResolvedDownload {
        let attemptCount = max(1, maximumAttempts ?? defaultResolutionAttempts)
        var lastError: Error?

        for attempt in 0..<attemptCount {
            try Task.checkCancellation()
            do {
                return try await resolveOnce(url, preferWebP: preferWebP)
            } catch {
                try Self.rethrowIfCancelled(error)
                lastError = error
            }

            if attempt + 1 < attemptCount, resolutionRetryDelayNanoseconds > 0 {
                try await Task.sleep(nanoseconds: resolutionRetryDelayNanoseconds)
            }
        }

        throw lastError ?? NativeDownloadError.invalidGalleryData
    }

    private func resolveOnce(_ url: URL, preferWebP: Bool) async throws -> ResolvedDownload {
        let galleryID = try galleryID(from: url)
        let referer = "https://hitomi.la/reader/\(galleryID).html"
        let gallery = try await fetchGallery(id: galleryID, referer: referer)
        let galleryFiles = Self.downloadableFiles(from: gallery)
        let title = Self.displayTitle(gallery: gallery, galleryID: galleryID)
        let folder = "\(title) (\(galleryID))".sanitizedFilename()
        let galleryMetadata = Self.galleryMetadata(gallery: gallery, galleryID: galleryID, title: title, pageURL: referer)

        if gallery.videoFilename?.trimmed.isEmpty == false {
            var thumbnailURL: URL?
            if let thumbnailFile = galleryFiles.first,
               let resolvedThumbnail = try? await scriptEngine.imageURL(
                    galleryID: galleryID,
                    file: thumbnailFile,
                    preferWebP: true
               ) {
                thumbnailURL = resolvedThumbnail
            }
            if let video = Self.videoDownload(
                gallery: gallery,
                galleryID: galleryID,
                sourceURL: url,
                thumbnailURL: thumbnailURL
            ) {
                return video
            }
            throw NativeDownloadError.invalidGalleryData
        }

        guard !galleryFiles.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var assets: [ResolvedAsset] = []
        for (index, file) in galleryFiles.enumerated() {
            let remote = try await scriptEngine.imageURL(
                galleryID: galleryID,
                file: file,
                preferWebP: preferWebP
            )

            let filename = Self.sourceFilename(for: file, remoteURL: remote, preferWebP: preferWebP)
            let pageReferer = Self.imageReferer(galleryID: galleryID, index: index + 1)
            let metadata = Self.assetMetadata(
                for: file,
                remoteURL: remote,
                index: index + 1,
                galleryMetadata: galleryMetadata,
                pageURL: pageReferer
            )
            var downloadMetadata = metadata
            downloadMetadata["asset_concurrency_cap"] = "8"
            downloadMetadata["continue_asset_failures"] = "true"
            downloadMetadata["hitomi_asset"] = "true"
            downloadMetadata["hitomi_lazy_asset"] = "true"
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename,
                metadata: downloadMetadata,
                referer: pageReferer,
                userAgent: Self.requestUserAgent,
                hitomiImageDescriptor: HitomiImageDescriptor(
                    galleryID: galleryID,
                    file: file,
                    preferWebP: preferWebP
                )
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: title,
            folderName: folder,
            assets: assets,
            metadata: galleryMetadata
        )
    }

    nonisolated static func isLazyImageAsset(_ asset: ResolvedAsset) -> Bool {
        asset.hitomiImageDescriptor != nil &&
            asset.metadata["hitomi_lazy_asset"] == "true"
    }

    nonisolated static func resolveLazyImageAsset(_ asset: ResolvedAsset) async throws -> ResolvedAsset {
        guard let descriptor = asset.hitomiImageDescriptor else {
            return asset
        }

        let remote = try await HitomiScriptEngine.shared.imageURL(
            galleryID: descriptor.galleryID,
            file: descriptor.file,
            preferWebP: descriptor.preferWebP
        )
        var resolved = asset
        resolved.remoteURL = remote
        resolved.metadata["image_url"] = remote.absoluteString
        resolved.metadata["media_url"] = remote.absoluteString
        resolved.metadata["source_url"] = remote.absoluteString
        resolved.metadata["format"] = mediaFormat(for: remote, fallbackName: descriptor.file.name)
        resolved.metadata["media_format"] = resolved.metadata["format"]
        return resolved
    }

    nonisolated private static func rethrowIfCancelled(_ error: Error) throws {
        try Task.checkCancellation()
        if error is CancellationError {
            throw CancellationError()
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            throw CancellationError()
        }
        if let nativeError = error as? NativeDownloadError,
           case .cancelled = nativeError {
            throw CancellationError()
        }
    }

    // The improved original sets Downloader_hitomi.NO_LIMIT, so this must not
    // inherit the shared 2,000-item collection cap.
    nonisolated static func downloadableFiles(from gallery: HitomiGallery) -> [HitomiFile] {
        gallery.files
    }

    nonisolated static func imageReferer(galleryID: String, index: Int) -> String {
        "https://hitomi.la/reader/\(galleryID).html#\(max(index, 1))"
    }

    nonisolated static func displayTitle(gallery: HitomiGallery, galleryID: String) -> String {
        let standardTitle = gallery.title?.trimmed
        let japaneseTitle = gallery.japaneseTitle?.trimmed
        let rawTitle: String

        if gallery.language?.trimmed.lowercased() == "japanese",
           let japaneseTitle,
           !japaneseTitle.isEmpty {
            rawTitle = japaneseTitle
        } else if let standardTitle, !standardTitle.isEmpty {
            rawTitle = standardTitle
        } else if let japaneseTitle, !japaneseTitle.isEmpty {
            rawTitle = japaneseTitle
        } else {
            rawTitle = "Hitomi \(galleryID)"
        }

        return rawTitle.sanitizedFilename()
    }

    nonisolated static func videoDownload(
        gallery: HitomiGallery,
        galleryID: String,
        sourceURL: URL,
        thumbnailURL: URL? = nil
    ) -> ResolvedDownload? {
        guard let videoFilename = gallery.videoFilename?.trimmed,
              !videoFilename.isEmpty,
              let encodedFilename = videoFilename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let videoURL = URL(string: "https://streaming.gold-usergeneratedcontent.net/videos/\(encodedFilename)"),
              videoURL.host?.lowercased() == "streaming.gold-usergeneratedcontent.net" else {
            return nil
        }

        let title = displayTitle(gallery: gallery, galleryID: galleryID)
        let folder = "\(title) (\(galleryID))".sanitizedFilename()
        let ext = videoURL.pathExtension.trimmed.isEmpty ? "mp4" : videoURL.pathExtension.lowercased()
        let filename = "\(title) (\(galleryID)).\(ext)".sanitizedFilename(maxLength: 200)
        let pageURL = sourceURL.absoluteString
        var galleryMetadata = galleryMetadata(
            gallery: gallery,
            galleryID: galleryID,
            title: title,
            pageURL: pageURL
        )
        galleryMetadata["media_count"] = "1"
        galleryMetadata["video_count"] = "1"
        galleryMetadata["image_count"] = "0"
        galleryMetadata["gallery_preview_image_count"] = String(gallery.files.count)
        galleryMetadata["type"] = "video"
        galleryMetadata["media_type"] = "video"
        galleryMetadata["video_url"] = videoURL.absoluteString
        if let thumbnailURL {
            galleryMetadata["thumbnail"] = thumbnailURL.absoluteString
            galleryMetadata["thumbnail_url"] = thumbnailURL.absoluteString
            galleryMetadata["thumbnail_referer"] = imageReferer(galleryID: galleryID, index: 1)
        }
        galleryMetadata = DownloadMetadata.clean(galleryMetadata)

        var assetMetadata = galleryMetadata
        assetMetadata["id"] = galleryID
        assetMetadata["media_id"] = galleryID
        assetMetadata["filename"] = videoFilename
        assetMetadata["format"] = ext
        assetMetadata["media_format"] = ext
        assetMetadata["media_url"] = videoURL.absoluteString
        assetMetadata["source_url"] = videoURL.absoluteString
        assetMetadata["page_url"] = pageURL
        assetMetadata = DownloadMetadata.clean(assetMetadata)

        return ResolvedDownload(
            title: title,
            folderName: folder,
            assets: [ResolvedAsset(
                remoteURL: videoURL,
                filename: filename,
                metadata: assetMetadata,
                referer: videoURL.absoluteString,
                userAgent: requestUserAgent
            )],
            metadata: galleryMetadata
        )
    }

    nonisolated static func galleryMetadata(gallery: HitomiGallery, galleryID: String, title: String, pageURL: String? = nil) -> [String: String] {
        let artist = joinedMetadata(gallery.artists) ?? joinedMetadata(gallery.groups) ?? ""
        let parody = joinedMetadata(gallery.parodys) ?? ""
        let character = joinedMetadata(gallery.characters) ?? ""
        let tags = joinedMetadata(gallery.tags) ?? ""
        let language = gallery.languageLocalName?.trimmed.isEmpty == false
            ? gallery.languageLocalName ?? ""
            : gallery.language ?? ""
        let sourcePageURL = pageURL ?? canonicalReaderURL(galleryID: galleryID)
        let imageCount = gallery.files.count

        return DownloadMetadata.clean([
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "channel": artist,
            "language": language,
            "parody": parody,
            "series": parody,
            "category": gallery.type ?? "",
            "type": gallery.type ?? "",
            "character": character,
            "tag": tags,
            "tags": tags,
            "gallery_id": gallery.id?.value ?? galleryID,
            "media_id": gallery.id?.value ?? galleryID,
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "date": gallery.date ?? "",
            "site": "Hitomi",
            "title": title,
            "source_url": sourcePageURL,
            "page_url": sourcePageURL
        ])
    }

    nonisolated static func assetMetadata(for file: HitomiFile, remoteURL: URL, index: Int, galleryMetadata: [String: String], pageURL: String) -> [String: String] {
        let galleryID = galleryMetadata["gallery_id"] ?? galleryMetadata["id"] ?? ""
        let format = mediaFormat(for: remoteURL, fallbackName: file.name)
        let width = file.width.map(String.init) ?? ""
        let height = file.height.map(String.init) ?? ""
        let hasDimensions = !(width.isEmpty || height.isEmpty)
        return DownloadMetadata.clean([
            "artist": galleryMetadata["artist"] ?? "",
            "author": galleryMetadata["author"] ?? "",
            "creator": galleryMetadata["creator"] ?? "",
            "uploader": galleryMetadata["uploader"] ?? "",
            "channel": galleryMetadata["channel"] ?? "",
            "language": galleryMetadata["language"] ?? "",
            "parody": galleryMetadata["parody"] ?? "",
            "series": galleryMetadata["series"] ?? "",
            "category": galleryMetadata["category"] ?? "",
            "character": galleryMetadata["character"] ?? "",
            "tag": galleryMetadata["tag"] ?? "",
            "tags": galleryMetadata["tags"] ?? "",
            "gallery_id": galleryID,
            "id": galleryID,
            "media_id": file.hash?.trimmed.isEmpty == false ? file.hash ?? "" : (galleryID.isEmpty ? String(index) : "\(galleryID)-\(index)"),
            "file_hash": file.hash ?? "",
            "date": galleryMetadata["date"] ?? "",
            "site": "Hitomi",
            "title": galleryMetadata["title"] ?? "",
            "type": "image",
            "media_type": "image",
            "page": String(index),
            "position": String(index),
            "filename": file.name,
            "format": format,
            "media_format": format,
            "width": width,
            "height": height,
            "resolution": hasDimensions ? "\(width)x\(height)" : "",
            "has_webp": file.hasWebP.map { $0.value ? "true" : "false" } ?? "",
            "has_avif": file.hasAvif.map { $0.value ? "true" : "false" } ?? "",
            "image_url": remoteURL.absoluteString,
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": pageURL
        ])
    }

    nonisolated private static func canonicalReaderURL(galleryID: String) -> String {
        "https://hitomi.la/reader/\(galleryID).html"
    }

    nonisolated private static func mediaFormat(for url: URL, fallbackName: String) -> String {
        let ext = url.pathExtension.trimmed.isEmpty
            ? (fallbackName as NSString).pathExtension
            : url.pathExtension
        let lowered = ext.lowercased()
        if lowered == "jpeg" || lowered == "bmp" {
            return "jpg"
        }
        return lowered.isEmpty ? "jpg" : lowered
    }

    nonisolated private static func joinedMetadata(_ values: [HitomiNamedValue]?) -> String? {
        let cleaned = values?
            .map { $0.value.trimmed }
            .filter { !$0.isEmpty }
        guard let cleaned, !cleaned.isEmpty else { return nil }
        var seen = Set<String>()
        var result: [String] = []
        for value in cleaned {
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            result.append(value)
        }
        return result.joined(separator: ", ")
    }

    nonisolated static func galleryID(from url: URL) -> String? {
        let absolute = url.absoluteString
        let patterns = [
            #"hitomi\.la/(?:reader|galleries|g|lofi|mpv)/([0-9]+)"#,
            #"-([0-9]+)\.html"#,
            #"galleryblock/([0-9]+)"#,
            #"#-\*-[^#]*\(([0-9]+)\)"#
        ]

        for pattern in patterns {
            if let match = absolute.firstMatch(pattern: pattern) {
                return match
            }
        }

        return nil
    }

    nonisolated static func galleryScriptURLs(id: String) -> [URL] {
        [
            "https://ltn.gold-usergeneratedcontent.net/galleries/\(id).js"
        ].compactMap(URL.init(string:))
    }

    nonisolated static func canonicalGalleryURL(galleryID: String) -> URL? {
        guard !galleryID.isEmpty, galleryID.allSatisfy(\.isNumber) else {
            return nil
        }
        return URL(string: "https://hitomi.la/galleries/\(galleryID).html")
    }

    private func galleryID(from url: URL) throws -> String {
        if let id = Self.galleryID(from: url) {
            return id
        }
        throw NativeDownloadError.missingGalleryID(url.absoluteString)
    }

    private func fetchGallery(id: String, referer: String) async throws -> HitomiGallery {
        var lastError: Error?
        for url in Self.galleryScriptURLs(id: id) {
            do {
                let script = try await HTTPClient.shared.string(
                    from: url,
                    referer: referer,
                    userAgent: Self.requestUserAgent,
                    retryLimitOverride: 3
                )
                guard let json = script.jsonObjectLiteralFromJavaScriptAssignment(),
                      let data = json.data(using: .utf8) else {
                    throw NativeDownloadError.invalidGalleryData
                }
                return try JSONDecoder().decode(HitomiGallery.self, from: data)
            } catch {
                if case NativeDownloadError.httpStatus(let status, _) = error,
                   status == 404 || status == 410 {
                    throw error
                }
                lastError = error
            }
        }
        throw lastError ?? NativeDownloadError.invalidGalleryData
    }

    nonisolated static func sourceFilename(for file: HitomiFile, remoteURL: URL, preferWebP: Bool) -> String {
        let originalBase = (file.name as NSString).deletingPathExtension
            .sanitizedFilename(maxLength: 150)
        let remoteBase = remoteURL.deletingPathExtension().lastPathComponent
            .sanitizedFilename(maxLength: 150)
        let base = originalBase.trimmed.isEmpty
            ? (remoteBase.trimmed.isEmpty ? "image" : remoteBase)
            : originalBase
        let remoteExt = remoteURL.pathExtension.isEmpty ? (file.name as NSString).pathExtension : remoteURL.pathExtension
        let ext = remoteExt.isEmpty ? (preferWebP ? "webp" : "jpg") : remoteExt
        return "\(base).\(ext)".sanitizedFilename(maxLength: 200)
    }
}

actor HitomiScriptEngine {
    static let shared = HitomiScriptEngine()

    private var context: JSContext?
    private var loadedAt: Date?
    private let maximumInitializationAttempts = 4

    func imageURL(galleryID: String, file: HitomiFile, preferWebP: Bool) async throws -> URL {
        var lastError: Error?

        for attempt in 0..<maximumInitializationAttempts {
            do {
                return try await evaluateImageURL(
                    galleryID: galleryID,
                    file: file,
                    preferWebP: preferWebP
                )
            } catch {
                try Self.rethrowIfCancelled(error)
                lastError = error
                context = nil
                loadedAt = nil
            }

            if attempt + 1 < maximumInitializationAttempts {
                try await Self.waitBeforeInitializationRetry()
            }
        }

        throw lastError ?? NativeDownloadError.invalidGalleryData
    }

    private func evaluateImageURL(
        galleryID: String,
        file: HitomiFile,
        preferWebP: Bool
    ) async throws -> URL {
            let context = try await context()
            let encoder = JSONEncoder()
            let data = try encoder.encode(file)
            guard let json = String(data: data, encoding: .utf8) else {
                throw NativeDownloadError.invalidGalleryData
            }

            let currentDomain = context
                .evaluateScript("typeof domain2 !== 'undefined' ? domain2 : ''")?
                .toString() ?? ""
            let call = Self.imageURLCall(
                galleryID: galleryID,
                fileJSON: json,
                preferWebP: preferWebP,
                currentDomain: currentDomain
            )

            let script = "(function(){ try { return \(call); } catch(e) { return null; } })();"
            guard let value = context.evaluateScript(script)?.toString(),
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https",
                  url.host?.isEmpty == false else {
                throw NativeDownloadError.invalidGalleryData
            }
            return url
    }

    nonisolated static func imageURLCall(
        galleryID: String,
        fileJSON: String,
        preferWebP: Bool,
        currentDomain: String
    ) -> String {
        if currentDomain == "gold-usergeneratedcontent.net" {
            return "url_from_url_from_hash('\(galleryID)', \(fileJSON), 'webp')"
        }
        if preferWebP {
            return "url_from_url_from_hash('\(galleryID)', \(fileJSON), 'webp', 'webp', 'a')"
        }
        return "url_from_url_from_hash('\(galleryID)', \(fileJSON))"
    }

    nonisolated static func supportScriptURLPairs() -> [(common: URL, gg: URL)] {
        [
            (
                URL(string: "https://ltn.gold-usergeneratedcontent.net/common.js")!,
                URL(string: "https://ltn.gold-usergeneratedcontent.net/gg.js")!
            )
        ]
    }

    private func context() async throws -> JSContext {
        if let context, let loadedAt, Date().timeIntervalSince(loadedAt) < 1_800 {
            return context
        }

        var lastError: Error?
        for urls in Self.supportScriptURLPairs() {
            do {
                let common = try await HTTPClient.shared.string(
                    from: urls.common,
                    referer: "https://hitomi.la/",
                    userAgent: HitomiResolver.requestUserAgent,
                    retryLimitOverride: 3
                )
                let gg = try await HTTPClient.shared.string(
                    from: urls.gg,
                    referer: "https://hitomi.la/",
                    userAgent: HitomiResolver.requestUserAgent,
                    retryLimitOverride: 3
                )

                guard let newContext = JSContext() else {
                    throw NativeDownloadError.unsupported("JavaScriptCore could not be initialized.")
                }
                newContext.exceptionHandler = { _, exception in
                    if let exception {
                        print("Hitomi script exception: \(exception)")
                    }
                }

                newContext.evaluateScript(Self.bootstrapScript)
                newContext.evaluateScript(common)
                newContext.evaluateScript(gg)
                if newContext.exception != nil {
                    throw NativeDownloadError.invalidGalleryData
                }

                context = newContext
                loadedAt = Date()
                return newContext
            } catch {
                lastError = error
            }
        }
        throw lastError ?? NativeDownloadError.invalidGalleryData
    }

    private nonisolated static func rethrowIfCancelled(_ error: Error) throws {
        try Task.checkCancellation()
        if error is CancellationError {
            throw CancellationError()
        }
        if let urlError = error as? URLError, urlError.code == .cancelled {
            throw CancellationError()
        }
        if let nativeError = error as? NativeDownloadError,
           case .cancelled = nativeError {
            throw CancellationError()
        }
    }

    private nonisolated static func waitBeforeInitializationRetry() async throws {
#if TESTING
        return
#else
        try await Task.sleep(nanoseconds: 500_000_000)
#endif
    }

    private static let bootstrapScript = """
    var window = this;
    var self = this;
    var navigator = {};
    var localStorage = {};
    var sessionStorage = {};
    var performance = { timeOrigin: Date.now(), timing: {}, now: function(){ return Date.now(); } };
    var location = {
      href: 'https://hitomi.la/',
      origin: 'https://hitomi.la',
      protocol: 'https:',
      host: 'hitomi.la',
      hostname: 'hitomi.la',
      pathname: '/',
      search: '',
      hash: ''
    };
    var document = {
      title: 'Hitomi.la',
      location: location,
      readyState: 'complete',
      cookie: '',
      createElement: function(){ return {}; },
      getElementById: function(){ return null; },
      addEventListener: function(){},
      removeEventListener: function(){}
    };
    var m = {};
    m.ready = function(a){ return null; };
    var $ = function(a){ return m; };
    var jQuery = $;
    """
}

private extension String {
    func firstMatch(pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }
        let range = NSRange(startIndex..<endIndex, in: self)
        guard let match = regex.firstMatch(in: self, options: [], range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: self) else {
            return nil
        }
        return String(self[capture])
    }

    func jsonObjectLiteralFromJavaScriptAssignment() -> String? {
        guard let start = firstIndex(of: "{"), let end = lastIndex(of: "}") else {
            return nil
        }
        return String(self[start...end])
    }
}
