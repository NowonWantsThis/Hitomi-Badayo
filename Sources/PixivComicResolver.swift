import AppKit
import CryptoKit
import Foundation

enum PixivComicImageDecoder {
    private static let shuffleSalt = "4wXCKprMMoxnyJ3PocJFs4CYbfnbazNe"

    static func decode(_ data: Data, shuffle: PixivGridShuffle) throws -> Data {
        guard let image = NSImage(data: data) else {
            throw NativeDownloadError.invalidGalleryData
        }

        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            throw NativeDownloadError.invalidGalleryData
        }

        let width = shuffle.width > 0 ? shuffle.width : cgImage.width
        let height = shuffle.height > 0 ? shuffle.height : cgImage.height
        let channels = 4
        var rgba = [UInt8](repeating: 0, count: width * height * channels)
        guard let context = CGContext(
            data: &rgba,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * channels,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        ) else {
            throw NativeDownloadError.invalidGalleryData
        }

        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        let decodedRGBA = unshuffle(
            pixels: rgba,
            width: width,
            height: height,
            channels: channels,
            gridSize: shuffle.gridSize,
            key: shuffle.key,
            invert: true
        )

        var rgb = [UInt8](repeating: 0, count: width * height * 3)
        for pixel in 0..<(width * height) {
            rgb[pixel * 3] = decodedRGBA[pixel * channels]
            rgb[pixel * 3 + 1] = decodedRGBA[pixel * channels + 1]
            rgb[pixel * 3 + 2] = decodedRGBA[pixel * channels + 2]
        }

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 3,
            hasAlpha: false,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: width * 3,
            bitsPerPixel: 24
        ), let bitmap = rep.bitmapData else {
            throw NativeDownloadError.invalidGalleryData
        }

        _ = rgb.withUnsafeBytes { source in
            memcpy(bitmap, source.baseAddress!, rgb.count)
        }

        guard let output = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) else {
            throw NativeDownloadError.invalidGalleryData
        }
        return output
    }

    static func unshuffle(pixels: [UInt8], width: Int, height: Int, channels: Int, gridSize: Int, key: String, invert: Bool) -> [UInt8] {
        guard width > 0, height > 0, channels > 0, gridSize > 0 else {
            return pixels
        }

        let columnCount = width / gridSize
        let rowGroupCount = Int(ceil(Double(height) / Double(gridSize)))
        guard columnCount > 0, rowGroupCount > 0 else {
            return pixels
        }

        var permutations = makePermutations(rowGroupCount: rowGroupCount, columnCount: columnCount, salt: shuffleSalt, key: key)
        if invert {
            permutations = permutations.map { row in
                var inverse = Array(repeating: 0, count: row.count)
                for (index, value) in row.enumerated() where value < inverse.count {
                    inverse[value] = index
                }
                return inverse
            }
        }

        var output = Array(repeating: UInt8(0), count: pixels.count)
        for y in 0..<height {
            let rowGroup = min(y / gridSize, permutations.count - 1)
            let permutation = permutations[rowGroup]

            for column in 0..<columnCount {
                let sourceColumn = permutation[column]
                let destinationStart = (y * width + column * gridSize) * channels
                let sourceStart = (y * width + sourceColumn * gridSize) * channels
                let byteCount = gridSize * channels
                guard sourceStart + byteCount <= pixels.count,
                      destinationStart + byteCount <= output.count else {
                    continue
                }
                output[destinationStart..<(destinationStart + byteCount)] = pixels[sourceStart..<(sourceStart + byteCount)]
            }

            let remainderStartX = columnCount * gridSize
            if remainderStartX < width {
                let start = (y * width + remainderStartX) * channels
                let end = (y * width + width) * channels
                if start < pixels.count, end <= pixels.count, end <= output.count {
                    output[start..<end] = pixels[start..<end]
                }
            }
        }
        return output
    }

    private static func makePermutations(rowGroupCount: Int, columnCount: Int, salt: String, key: String) -> [[Int]] {
        var permutations = Array(repeating: Array(0..<columnCount), count: rowGroupCount)
        var generator = Xoshiro128StarStar(seed: seedWords(from: salt + key))
        for _ in 0..<100 {
            _ = generator.next()
        }

        for row in 0..<rowGroupCount {
            guard columnCount > 1 else { continue }
            for column in stride(from: columnCount - 1, through: 1, by: -1) {
                let swapIndex = Int(generator.next() % UInt32(column + 1))
                permutations[row].swapAt(column, swapIndex)
            }
        }
        return permutations
    }

    private static func seedWords(from text: String) -> [UInt32] {
        let digest = Array(SHA256.hash(data: Data(text.utf8)))
        var words: [UInt32] = []
        for offset in stride(from: 0, to: 16, by: 4) {
            let b0 = UInt32(digest[offset])
            let b1 = UInt32(digest[offset + 1]) << 8
            let b2 = UInt32(digest[offset + 2]) << 16
            let b3 = UInt32(digest[offset + 3]) << 24
            words.append(b0 | b1 | b2 | b3)
        }
        return words
    }

    private struct Xoshiro128StarStar {
        private var state: [UInt32]

        init(seed: [UInt32]) {
            state = seed.count == 4 ? seed : [1, 0, 0, 0]
            if state.allSatisfy({ $0 == 0 }) {
                state[0] = 1
            }
        }

        mutating func next() -> UInt32 {
            let result = 9 &* rotateLeft(5 &* state[1], by: 7)
            let t = state[1] << 9

            state[2] ^= state[0]
            state[3] ^= state[1]
            state[1] ^= state[2]
            state[0] ^= state[3]
            state[2] ^= t
            state[3] = rotateLeft(state[3], by: 11)

            return result
        }

        private func rotateLeft(_ value: UInt32, by amount: Int) -> UInt32 {
            let shift = amount % 32
            if shift == 0 { return value }
            return (value << UInt32(shift)) | (value >> UInt32(32 - shift))
        }
    }
}

final class PixivComicResolver {
    private static let apiSalt = "mAtW1X8SzGS880fsjEXlM73QpS1i4kUMBhyhdaYySk8nWz533nrEunaSplg63fzTc"

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isPixivComicHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }
        let path = url.path.lowercased()
        return path.contains("/viewer/") || path.contains("/works")
    }

    func resolve(_ url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> ResolvedDownload {
        if let episodeID = Self.episodeID(from: url) {
            let data = try await HTTPClient.shared.data(
                from: Self.apiURL(for: episodeID, sourceURL: url),
                referer: headers.referer ?? url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders(referer: url.absoluteString)
            )
            return try Self.resolvedEpisodeDownload(from: data, episodeID: episodeID, pageURL: url, titleHint: nil, episodeIndex: nil)
        }

        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        let episodes = Self.episodes(fromHTML: html, pageURL: url)
        guard !episodes.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var assets: [ResolvedAsset] = []
        let creator = Self.creator(fromHTML: html)
        for (offset, episode) in episodes.enumerated() {
            try Task.checkCancellation()
            let data = try await HTTPClient.shared.data(
                from: Self.apiURL(for: episode.id, sourceURL: url),
                referer: headers.referer ?? episode.url.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: Self.apiHeaders(referer: episode.url.absoluteString)
            )
            let resolved = try Self.resolvedEpisodeDownload(
                from: data,
                episodeID: episode.id,
                pageURL: episode.url,
                titleHint: episode.title,
                episodeIndex: offset + 1,
                artist: creator?.name,
                artistID: creator?.id
            )
            assets.append(contentsOf: resolved.assets)
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = Self.workTitle(fromHTML: html, pageURL: url)
        var metadata = Self.pixivComicMetadata(
            seriesTitle: title,
            workID: Self.workID(from: url) ?? "",
            episodeID: "",
            episodeCount: episodes.count,
            imageCount: assets.count,
            pageURL: url,
            artist: creator?.name ?? "",
            artistID: creator?.id ?? ""
        )
        metadata["listed_episode_count"] = String(episodes.count)
        metadata["resolved_episode_count"] = String(episodes.count)
        metadata["resolved_media_count"] = String(assets.count)
        return ResolvedDownload(
            title: title,
            folderName: "Pixiv Comic \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: metadata
        )
    }

    static func resolvedEpisodeDownload(
        from data: Data,
        episodeID: String,
        pageURL: URL,
        titleHint: String?,
        episodeIndex: Int?,
        artist: String? = nil,
        artistID: String? = nil
    ) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let reading = dictionary(at: ["data", "reading_episode"], in: object) ??
            dictionary(at: ["reading_episode"], in: object) ??
            object
        let pages = reading["pages"] as? [[String: Any]] ?? []
        guard !pages.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let episodeTitle = cleanTitle(
            titleHint ??
                stringValue(reading["title"]) ??
                stringValue(reading["name"]) ??
                "Episode \(episodeID)"
        )
        let prefix = filePrefix(title: episodeTitle, episodeIndex: episodeIndex)
        let apiCreator = creator(fromObject: reading) ?? creator(fromObject: object)
        let creatorName = cleanCreatorName(artist) ?? apiCreator?.name
        let creatorID = cleanCreatorID(artistID) ?? apiCreator?.id
        var assets: [ResolvedAsset] = []
        var seen = Set<String>()

        for page in pages {
            guard let rawURL = stringValue(page["url"]),
                  let remote = normalizedImageURL(from: rawURL, baseURL: pageURL) else {
                continue
            }

            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let key = stringValue(page["key"])
            let width = intValue(page["width"]) ?? 0
            let height = intValue(page["height"]) ?? 0
            let gridSize = intValue(page["gridsize"]) ?? intValue(page["gridSize"]) ?? 0
            let shuffle = key.map {
                PixivGridShuffle(key: $0, width: width, height: height, gridSize: gridSize)
            }

            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: filename(for: remote, prefix: prefix, index: assets.count + 1),
                metadata: assetMetadata(
                    seriesTitle: titleHint ?? episodeTitle,
                    episodeTitle: episodeTitle,
                    episodeID: episodeID,
                    pageURL: pageURL,
                    remote: remote,
                    index: assets.count + 1,
                    key: key,
                    width: width,
                    height: height,
                    gridSize: gridSize,
                    artist: creatorName ?? "",
                    artistID: creatorID ?? ""
                ),
                referer: pageURL.absoluteString,
                pixivGridShuffle: shuffle
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        return ResolvedDownload(
            title: episodeTitle,
            folderName: "Pixiv Comic \(prefix)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: pixivComicMetadata(
                seriesTitle: titleHint ?? episodeTitle,
                workID: workID(from: pageURL) ?? "",
                episodeID: episodeID,
                episodeCount: nil,
                imageCount: assets.count,
                pageURL: pageURL,
                artist: creatorName ?? "",
                artistID: creatorID ?? ""
            )
        )
    }

    static func episodes(fromHTML html: String, pageURL: URL) -> [(id: String, title: String, url: URL)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }

        var output: [(id: String, title: String, url: URL)] = []
        var seen = Set<String>()
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let values = attributeValues(from: String(html[attrRange]))
            guard let href = values["href"],
                  let url = absoluteURL(href, baseURL: pageURL),
                  let id = episodeID(from: url),
                  !seen.contains(id) else {
                continue
            }

            seen.insert(id)
            let title = cleanTitle(stripTags(String(html[bodyRange])))
            output.append((id, title.isEmpty ? "Episode \(id)" : title, url))
        }
        return output.reversed()
    }

    static func episodeID(from url: URL) -> String? {
        let path = url.path
        let patterns = [
            #"/viewer/stories/([0-9]+)"#,
            #"/viewer/[^/]+/([0-9]+)"#
        ]
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(path.startIndex..<path.endIndex, in: path)
            guard let match = regex.firstMatch(in: path, range: range),
                  let capture = Range(match.range(at: 1), in: path) else {
                continue
            }
            return String(path[capture])
        }
        return nil
    }

    static func workID(from url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard let workIndex = parts.firstIndex(where: { $0.lowercased() == "works" }),
              workIndex + 1 < parts.count else {
            return nil
        }
        let value = parts[workIndex + 1].removingPercentEncoding ?? parts[workIndex + 1]
        return value.isEmpty ? nil : value
    }

    static func apiURL(for episodeID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host?.lowercased().hasSuffix(".test") == true ? "comic.pixiv.test" : "comic.pixiv.net"
        components.path = "/api/app/episodes/\(episodeID)/read_v3"
        return components.url!
    }

    static func apiHeaders(referer: String, date: Date = Date()) -> [String: String] {
        let time = clientTime(from: date)
        let hash = SHA256.hash(data: Data((time + apiSalt).utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return [
            "X-Client-Time": time,
            "X-Client-Hash": hash,
            "X-Requested-With": "pixivcomic",
            "Referer": referer
        ]
    }

    private static func clientTime(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'+00:00'"
        return formatter.string(from: date)
    }

    private static func normalizedImageURL(from raw: String, baseURL: URL) -> URL? {
        let fixed = raw
            .replacingOccurrences(of: "webp%3Ajpeg", with: "jpeg")
            .replacingOccurrences(of: "q=50", with: "q=100")
        return absoluteURL(fixed, baseURL: baseURL)
    }

    private static func filename(for url: URL, prefix: String, index: Int) -> String {
        let ext = url.pathExtension.trimmed.isEmpty ? "jpg" : url.pathExtension
        return String(format: "%@ - %04d.%@", prefix, index, ext).sanitizedFilename(maxLength: 180)
    }

    static func pixivComicMetadata(
        seriesTitle: String,
        workID: String,
        episodeID: String,
        episodeCount: Int?,
        imageCount: Int? = nil,
        pageURL: URL? = nil,
        artist: String = "",
        artistID: String = ""
    ) -> [String: String] {
        let contentID = episodeID.isEmpty ? workID : episodeID
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "channel": artist,
            "user": artist,
            "username": artist,
            "artist_id": artistID,
            "author_id": artistID,
            "creator_id": artistID,
            "user_id": artistID,
            "uploader_id": artistID,
            "channel_id": artistID,
            "category": "comic",
            "type": episodeID.isEmpty ? "work" : "episode",
            "media_type": "image",
            "work_id": workID,
            "episode_id": episodeID,
            "chapter_id": episodeID,
            "gallery_id": contentID,
            "id": contentID,
            "episode_count": episodeCount.map(String.init) ?? "",
            "media_count": imageCount.map(String.init) ?? "",
            "image_count": imageCount.map(String.init) ?? "",
            "slug": contentID,
            "site": "Pixiv Comic",
            "title": seriesTitle,
            "url": pageURL?.absoluteString ?? "",
            "source_url": pageURL?.absoluteString ?? "",
            "page_url": pageURL?.absoluteString ?? ""
        ])
    }

    private static func assetMetadata(
        seriesTitle: String,
        episodeTitle: String,
        episodeID: String,
        pageURL: URL,
        remote: URL,
        index: Int,
        key: String?,
        width: Int,
        height: Int,
        gridSize: Int,
        artist: String = "",
        artistID: String = ""
    ) -> [String: String] {
        let workID = workID(from: pageURL) ?? ""
        let format = mediaFormat(for: remote)
        return DownloadMetadata.clean([
            "series": seriesTitle,
            "artist": artist,
            "author": artist,
            "creator": artist,
            "uploader": artist,
            "channel": artist,
            "user": artist,
            "username": artist,
            "artist_id": artistID,
            "author_id": artistID,
            "creator_id": artistID,
            "user_id": artistID,
            "uploader_id": artistID,
            "channel_id": artistID,
            "category": "comic",
            "episode": episodeTitle,
            "chapter": episodeTitle,
            "type": "image",
            "media_type": "image",
            "work_id": workID,
            "episode_id": episodeID,
            "chapter_id": episodeID,
            "gallery_id": episodeID,
            "id": episodeID,
            "page": String(index),
            "position": String(index),
            "width": width > 0 ? String(width) : "",
            "height": height > 0 ? String(height) : "",
            "resolution": width > 0 && height > 0 ? "\(width)x\(height)" : "",
            "format": format,
            "media_format": format,
            "image_url": remote.absoluteString,
            "media_url": remote.absoluteString,
            "source_url": remote.absoluteString,
            "page_url": pageURL.absoluteString,
            "gridshuffle_key": key ?? "",
            "gridshuffle_width": width > 0 ? String(width) : "",
            "gridshuffle_height": height > 0 ? String(height) : "",
            "gridshuffle_size": gridSize > 0 ? String(gridSize) : "",
            "gridsize": gridSize > 0 ? String(gridSize) : "",
            "site": "Pixiv Comic",
            "title": episodeTitle
        ])
    }

    private static func mediaFormat(for url: URL) -> String {
        let queryFormat = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == "format" }?
            .value?
            .lowercased()
        let raw = queryFormat?.trimmed.isEmpty == false ? queryFormat! : url.pathExtension.lowercased()
        if raw == "jpeg" {
            return "jpg"
        }
        return raw.isEmpty ? "jpg" : raw
    }

    private static func filePrefix(title: String, episodeIndex: Int?) -> String {
        if let episodeIndex {
            if isNumberedEpisodeTitle(title) {
                return title.sanitizedFilename(maxLength: 120)
            }
            return String(format: "%04d - %@", episodeIndex, title).sanitizedFilename(maxLength: 120)
        }
        return title.sanitizedFilename(maxLength: 120)
    }

    private static func isNumberedEpisodeTitle(_ title: String) -> Bool {
        let patterns = [
            #"^\d{1,4}\s*[-_.]"#,
            #"^第\s*\d+\s*話"#,
            #"^\d+\s*화"#
        ]
        return patterns.contains { pattern in
            title.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    private static func workTitle(fromHTML html: String, pageURL: URL) -> String {
        let title = textForTag("h1", in: html) ??
            metaContent(from: html, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: html) ??
            pageURL.lastPathComponent
        return cleanTitle(title)
    }

    private static func creator(fromHTML html: String) -> (name: String, id: String?)? {
        let name = metaContent(from: html, names: [
            "author", "creator", "dc:creator", "dc.creator",
            "article:author", "book:author", "pixiv:author"
        ]).flatMap(cleanCreatorName) ??
            attributeValue(fromHTML: html, attributeNames: ["data-author-name", "data-artist-name", "data-creator-name"]).flatMap(cleanCreatorName) ??
            textForClassNeedle(["author", "creator", "artist", "writer", "manga-author"], in: html).flatMap(cleanCreatorName)
        let id = attributeValue(fromHTML: html, attributeNames: [
            "data-author-id", "data-artist-id", "data-creator-id", "data-user-id", "data-pixiv-user-id"
        ]).flatMap(cleanCreatorID)
        guard let name else { return nil }
        return (name, id)
    }

    private static func creator(fromObject object: [String: Any]) -> (name: String, id: String?)? {
        for key in ["author", "creator", "artist", "user", "writer", "manga_author", "mangaAuthor"] {
            if let dictionary = object[key] as? [String: Any],
               let creator = creator(fromCreatorObject: dictionary) {
                return creator
            }
            if let name = cleanCreatorName(stringValue(object[key])) {
                return (name, nil)
            }
        }

        for key in ["work", "comic", "series", "manga", "content", "book"] {
            if let dictionary = object[key] as? [String: Any],
               let creator = creator(fromObject: dictionary) ?? creator(fromCreatorObject: dictionary) {
                return creator
            }
        }
        return nil
    }

    private static func creator(fromCreatorObject object: [String: Any]) -> (name: String, id: String?)? {
        let name = firstString(forKeys: [
            "name", "display_name", "displayName", "user_name", "userName",
            "username", "nick_name", "nickname", "title", "label"
        ], in: object).flatMap(cleanCreatorName)
        guard let name else { return nil }
        let id = firstString(forKeys: [
            "id", "user_id", "userId", "artist_id", "artistId",
            "author_id", "authorId", "pixiv_user_id", "pixivUserId"
        ], in: object).flatMap(cleanCreatorID)
        return (name, id)
    }

    private static func firstString(forKeys keys: [String], in object: [String: Any]) -> String? {
        for key in keys {
            guard let value = object.first(where: { $0.key.lowercased() == key.lowercased() })?.value,
                  let text = stringValue(value)?.trimmed,
                  !text.isEmpty else {
                continue
            }
            return text
        }
        return nil
    }

    private static func attributeValue(fromHTML html: String, attributeNames: [String]) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<[a-zA-Z][A-Za-z0-9:-]*\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let names = Set(attributeNames.map { $0.lowercased() })
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attrRange]))
            for (key, value) in values where names.contains(key.lowercased()) {
                let trimmed = value.trimmed
                if !trimmed.isEmpty {
                    return trimmed
                }
            }
        }
        return nil
    }

    private static func textForClassNeedle(_ needles: [String], in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<[a-zA-Z][A-Za-z0-9:-]*\b([^>]*)>(.*?)</[a-zA-Z][A-Za-z0-9:-]*>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: html),
                  let bodyRange = Range(match.range(at: 2), in: html) else {
                continue
            }
            let values = attributeValues(from: String(html[attrRange]))
            let marker = [
                values["class"], values["id"], values["property"], values["itemprop"], values["data-testid"]
            ].compactMap { $0?.lowercased() }.joined(separator: " ")
            guard needles.contains(where: { marker.contains($0) }) else { continue }
            if let name = cleanCreatorName(String(html[bodyRange])) {
                return name
            }
        }
        return nil
    }

    private static func cleanCreatorName(_ raw: String?) -> String? {
        guard let raw else { return nil }
        let name = cleanTitle(raw)
        guard !name.isEmpty,
              name.lowercased() != "pixiv comic",
              !name.lowercased().contains("pixivコミック") else {
            return nil
        }
        return name
    }

    private static func cleanCreatorID(_ raw: String?) -> String? {
        guard let raw = raw?.trimmed, !raw.isEmpty else { return nil }
        return raw
    }

    private static func textForTag(_ tag: String, in html: String) -> String? {
        let pattern = #"<\#(tag)\b[^>]*>(.*?)</\#(tag)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let text = cleanTitle(String(html[capture]))
        return text.isEmpty ? nil : text
    }

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attrRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attrRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key,
                  names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func titleTag(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"<title\b[^>]*>(.*?)</title>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return cleanTitle(String(html[capture]))
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

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func dictionary(at path: [String], in object: [String: Any]) -> [String: Any]? {
        var current: Any = object
        for key in path {
            guard let dictionary = current as? [String: Any],
                  let next = dictionary[key] else {
                return nil
            }
            current = next
        }
        return current as? [String: Any]
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func cleanTitle(_ raw: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [" | pixivコミック", " - pixivコミック", " | Pixiv Comic", " - Pixiv Comic"] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title
    }

    private static func stripTags(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
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

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func isPixivComicHost(_ host: String) -> Bool {
        host == "comic.pixiv.net" ||
            host == "comic.pixiv.test"
    }
}
