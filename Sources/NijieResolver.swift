import Foundation

struct NijieImageCandidate {
    var remoteURL: URL
    var referer: String
}

struct NijieImageAsset {
    var remoteURL: URL
    var illustID: String
    var pageIndex: Int
    var referer: String
}

final class NijieResolver {
    private let maxMemberPages = 100

    func canResolve(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              Self.isSupportedHost(host),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        if Self.memberID(from: url) != nil {
            return true
        }
        if Self.illustrationID(from: url) != nil {
            return true
        }
        return false
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        let canonicalURL = Self.canonicalURL(for: url) ?? url
        if let memberID = Self.memberID(from: canonicalURL) {
            return try await resolveMember(
                memberID: memberID,
                sourceURL: canonicalURL,
                headers: headers,
                rangeExpression: rangeExpression
            )
        }
        return try await resolveIllustration(canonicalURL, headers: headers)
    }

    private func resolveMember(
        memberID: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        rangeExpression: String
    ) async throws -> ResolvedDownload {
        let firstURL = Self.memberIllustURL(memberID: memberID, page: 1, sourceURL: sourceURL)
        let firstHTML = try await HTTPClient.shared.string(from: firstURL, referer: headers.referer ?? sourceURL.absoluteString, userAgent: headers.userAgent)
        if Self.isLoginRequiredHTML(firstHTML) {
            throw NativeDownloadError.unsupported("Nijie login is required for this member page.")
        }

        let memberName = Self.memberName(fromHTML: firstHTML, memberID: memberID)
        let itemRange = rangeExpression.trimmed
        let discoveryLimit = try Self.maximumRequestedItem(in: itemRange)
        var illustrationURLs: [URL] = []
        var seenIllustrations = Set<String>()
        var memberPageCount = 0
        for page in 1...maxMemberPages {
            try Task.checkCancellation()
            let pageURL = Self.memberIllustURL(memberID: memberID, page: page, sourceURL: sourceURL)
            let html = page == 1
                ? firstHTML
                : try await HTTPClient.shared.string(from: pageURL, referer: firstURL.absoluteString, userAgent: headers.userAgent)
            memberPageCount += 1

            if Self.isLoginRequiredHTML(html) {
                continue
            }
            var appended = 0
            for illustrationURL in Self.illustrationURLs(fromHTML: html, baseURL: pageURL) {
                let normalized = URLIdentity.normalize(illustrationURL.absoluteString)
                guard !seenIllustrations.contains(normalized) else { continue }
                seenIllustrations.insert(normalized)
                illustrationURLs.append(illustrationURL)
                appended += 1
            }
            if appended == 0 || (discoveryLimit.map { illustrationURLs.count >= $0 } ?? false) {
                break
            }
        }

        guard !illustrationURLs.isEmpty else { throw NativeDownloadError.noFiles }
        var selectedIllustrations = Array(illustrationURLs.enumerated())
        var selectedPositions: [Int]?
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: illustrationURLs.count)
            selectedIllustrations = indexes.map { (offset: $0, element: illustrationURLs[$0]) }
            selectedPositions = indexes.map { $0 + 1 }
        }

        var images: [NijieImageAsset] = []
        var seenImages = Set<String>()
        var resolvedIllustrationCount = 0
        var skippedIllustrationCount = 0
        for selected in selectedIllustrations {
            try Task.checkCancellation()
            do {
                let resolved = try await resolveOriginalPopupAssets(
                    illustrationURL: selected.element,
                    headers: headers
                )
                guard !resolved.isEmpty else {
                    skippedIllustrationCount += 1
                    continue
                }
                resolvedIllustrationCount += 1
                for image in resolved {
                    let normalized = URLIdentity.normalize(image.remoteURL.absoluteString)
                    guard !seenImages.contains(normalized) else { continue }
                    seenImages.insert(normalized)
                    images.append(image)
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                skippedIllustrationCount += 1
            }
        }

        var resolved = try Self.resolvedMemberDownload(
            memberID: memberID,
            memberName: memberName,
            images: images,
            sourceURL: firstURL
        )
        resolved.metadata["collection_page_count"] = String(memberPageCount)
        resolved.metadata["listed_illustration_count"] = String(illustrationURLs.count)
        resolved.metadata["resolved_illustration_count"] = String(resolvedIllustrationCount)
        resolved.metadata["resolved_media_count"] = String(images.count)
        if skippedIllustrationCount > 0 {
            resolved.metadata["skipped_count"] = String(skippedIllustrationCount)
        }
        if let selectedPositions {
            resolved.metadata["range"] = itemRange
            resolved.metadata["range_scope"] = "collection_items"
            resolved.metadata["range_total"] = String(illustrationURLs.count)
            resolved.metadata["range_selected"] = String(selectedPositions.count)
            resolved.metadata["range_indexes"] = selectedPositions.map(String.init).joined(separator: ",")
        }
        return resolved
    }

    private func resolveIllustration(_ url: URL, headers: HTTPRequestOptions) async throws -> ResolvedDownload {
        let html = try await HTTPClient.shared.string(from: url, referer: headers.referer, userAgent: headers.userAgent)
        if Self.isLoginRequiredHTML(html) {
            throw NativeDownloadError.unsupported("Nijie login is required for this illustration.")
        }

        let images = try await resolveIllustrationAssets(fromHTML: html, pageURL: url, headers: headers)
        let title = Self.illustrationTitle(fromHTML: html, pageURL: url)
        let memberID = Self.memberID(fromHTML: html)
        return try Self.resolvedIllustrationDownload(
            title: title,
            pageURL: url,
            images: images,
            memberName: Self.artistName(fromHTML: html, memberID: memberID),
            memberID: memberID
        )
    }

    private func resolveIllustrationAssets(fromHTML html: String, pageURL: URL, headers: HTTPRequestOptions) async throws -> [NijieImageAsset] {
        let illustID = Self.illustrationID(from: pageURL) ?? Self.illustrationID(fromHTML: html) ?? "illust"
        guard let popupURL = Self.viewPopupURL(illustrationID: illustID, sourceURL: pageURL) else {
            throw NativeDownloadError.invalidURL(pageURL.absoluteString)
        }
        let popupHTML = try await HTTPClient.shared.string(
            from: popupURL,
            referer: pageURL.absoluteString,
            userAgent: headers.userAgent
        )
        if Self.isLoginRequiredHTML(popupHTML) {
            throw NativeDownloadError.unsupported("Nijie login is required for this illustration.")
        }
        return Self.imageAssets(
            from: Self.imageCandidates(fromHTML: popupHTML, pageURL: popupURL),
            illustID: illustID
        )
    }

    private func resolveOriginalPopupAssets(
        illustrationURL: URL,
        headers: HTTPRequestOptions
    ) async throws -> [NijieImageAsset] {
        let illustID = Self.illustrationID(from: illustrationURL) ?? "illust"
        guard let popupURL = Self.viewPopupURL(illustrationID: illustID, sourceURL: illustrationURL) else {
            throw NativeDownloadError.invalidURL(illustrationURL.absoluteString)
        }
        let html = try await HTTPClient.shared.string(
            from: popupURL,
            referer: illustrationURL.absoluteString,
            userAgent: headers.userAgent
        )
        if Self.isLoginRequiredHTML(html) {
            throw NativeDownloadError.unsupported("Nijie login is required for this illustration.")
        }
        return Self.imageAssets(
            from: Self.imageCandidates(fromHTML: html, pageURL: popupURL),
            illustID: illustID
        )
    }

    static func resolvedIllustrationDownload(fromHTML html: String, pageURL: URL) throws -> ResolvedDownload {
        let title = illustrationTitle(fromHTML: html, pageURL: pageURL)
        let illustID = illustrationID(from: pageURL) ?? illustrationID(fromHTML: html) ?? "illust"
        let assets = imageAssets(from: imageCandidates(fromHTML: html, pageURL: pageURL), illustID: illustID)
        let memberID = memberID(fromHTML: html)
        return try resolvedIllustrationDownload(
            title: title,
            pageURL: pageURL,
            images: assets,
            memberName: artistName(fromHTML: html, memberID: memberID),
            memberID: memberID
        )
    }

    static func resolvedIllustrationDownload(title: String, pageURL: URL, images: [NijieImageAsset], memberName: String? = nil, memberID: String? = nil) throws -> ResolvedDownload {
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let displayID = illustrationID(from: pageURL) ?? images.first?.illustID ?? "illust"
        let display = "\(title) (nijie_\(displayID))".sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: display,
            folderName: "Nijie \(display)".sanitizedFilename(maxLength: 120),
            assets: images.map {
                asset(
                    for: $0,
                    metadata: assetMetadata(
                        for: $0,
                        title: title,
                        collectionType: "illustration",
                        memberID: memberID ?? "",
                        memberName: memberName ?? ""
                    )
                )
            },
            metadata: nijieMetadata(
                title: title,
                type: "illustration",
                illustID: displayID,
                memberID: memberID ?? "",
                memberName: memberName ?? "",
                imageCount: images.count,
                sourceURL: pageURL
            )
        )
    }

    static func resolvedMemberDownload(memberID: String, memberName: String, images: [NijieImageAsset], sourceURL: URL? = nil) throws -> ResolvedDownload {
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }
        let display = "\(memberName) (nijie_\(memberID))".sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: display,
            folderName: "Nijie \(display)".sanitizedFilename(maxLength: 120),
            assets: images.enumerated().map { offset, image in
                var metadata = assetMetadata(
                    for: image,
                    title: memberName,
                    collectionType: "member",
                    memberID: memberID,
                    memberName: memberName
                )
                metadata["position"] = String(offset + 1)
                metadata["collection_position"] = String(offset + 1)
                return asset(
                    for: image,
                    metadata: metadata
                )
            },
            metadata: nijieMetadata(
                title: memberName,
                type: "member",
                illustID: "",
                memberID: memberID,
                memberName: memberName,
                imageCount: images.count,
                sourceURL: sourceURL
            )
        )
    }

    static func memberID(from url: URL) -> String? {
        let path = url.path.lowercased()
        guard path.hasSuffix("/members.php") || path.hasSuffix("/members_illust.php") || path == "/members.php" || path == "/members_illust.php" else {
            return nil
        }
        return queryValue("id", in: url).flatMap { numericID($0) }
    }

    static func illustrationID(from url: URL) -> String? {
        let path = url.path.lowercased()
        guard path.hasSuffix("/view.php") || path.hasSuffix("/view_popup.php") || path == "/view.php" || path == "/view_popup.php" else {
            return nil
        }
        return queryValue("id", in: url).flatMap { numericID($0) }
    }

    static func illustrationID(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"(?:view|view_popup)\.php\?[^"']*id=([0-9]+)"#,
            #"\billust(?:_id)?\s*[:=]\s*["']?([0-9]+)"#,
            #"\bid\s*=\s*["']?([0-9]+)["']?"#
        ], in: html)
    }

    static func canonicalURL(for url: URL) -> URL? {
        if let memberID = memberID(from: url) {
            return memberIllustURL(memberID: memberID, page: 1, sourceURL: url)
        }
        guard let illustrationID = illustrationID(from: url) else {
            return nil
        }
        let path = url.path.lowercased()
        if path.hasSuffix("/view_popup.php") || path == "/view_popup.php" {
            let page = queryValue("p", in: url).flatMap(Int.init)
            return viewPopupURL(illustrationID: illustrationID, sourceURL: url, page: page)
        }
        return viewURL(illustrationID: illustrationID, sourceURL: url)
    }

    static func memberID(fromHTML html: String) -> String? {
        firstCapture(patterns: [
            #"members(?:_illust)?\.php\?[^"']*id=([0-9]+)"#,
            #"\b(?:member|user)_id\s*[:=]\s*["']?([0-9]+)"#,
            #"/user_icon/([0-9]+)\."#
        ], in: html)
    }

    static func memberIllustURL(memberID: String, page: Int?, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = canonicalScheme(for: sourceURL)
        components.host = canonicalHost(for: sourceURL)
        components.path = "/members_illust.php"
        var queryItems = [URLQueryItem(name: "id", value: memberID)]
        if let page {
            queryItems.append(URLQueryItem(name: "p", value: String(page)))
        }
        components.queryItems = queryItems
        return components.url!
    }

    static func viewURL(illustrationID: String, sourceURL: URL) -> URL {
        var components = URLComponents()
        components.scheme = canonicalScheme(for: sourceURL)
        components.host = canonicalHost(for: sourceURL)
        components.path = "/view.php"
        components.queryItems = [URLQueryItem(name: "id", value: illustrationID)]
        return components.url!
    }

    static func viewPopupURL(illustrationID: String, sourceURL: URL, page: Int? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = canonicalScheme(for: sourceURL)
        components.host = canonicalHost(for: sourceURL)
        components.path = "/view_popup.php"
        var queryItems = [URLQueryItem(name: "id", value: illustrationID)]
        if let page {
            queryItems.append(URLQueryItem(name: "p", value: String(page)))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func memberPageURLs(fromHTML html: String, baseURL: URL, memberID: String) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        func append(_ url: URL) {
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            urls.append(url)
        }

        append(memberIllustURL(memberID: memberID, page: 1, sourceURL: baseURL))

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  Self.memberID(from: url) == memberID,
                  pageNumber(fromMemberURL: url) >= 1 else {
                continue
            }
            append(url)
        }

        let pageNumbers = urls.compactMap { queryValue("p", in: $0).flatMap(Int.init) }
        if let maxPage = pageNumbers.max(), maxPage > 1 {
            for page in 1...maxPage {
                append(memberIllustURL(memberID: memberID, page: page, sourceURL: baseURL))
            }
        }

        return urls.sorted { lhs, rhs in
            pageNumber(fromMemberURL: lhs) < pageNumber(fromMemberURL: rhs)
        }
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func maximumRequestedItem(in expression: String) throws -> Int? {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return nil }
        if segments.contains(where: { $0.end == nil }) { return nil }
        return segments.compactMap(\.end).max()
    }

    private static func itemIndexes(for expression: String, total: Int) throws -> [Int] {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return Array(0..<max(0, total)) }
        guard total > 0 else { return [] }
        var indexes: [Int] = []
        var seen = Set<Int>()
        for segment in segments {
            let start = max(1, segment.start ?? 1)
            let end = min(total, segment.end ?? total)
            guard start <= end else { continue }
            for position in start...end where seen.insert(position - 1).inserted {
                indexes.append(position - 1)
            }
        }
        guard !indexes.isEmpty else {
            throw NativeDownloadError.unsupported("Range did not match any Nijie illustrations.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let compact = expression.filter { !$0.isWhitespace }
        let pieces = compact.components(separatedBy: CharacterSet(charactersIn: ",;"))
            .filter { !$0.isEmpty }
        guard !pieces.isEmpty else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return try pieces.map { piece in
            if let split = itemRangeSplit(piece) {
                let start = try positiveItemRangeBound(split.0)
                let end = try positiveItemRangeBound(split.1)
                guard start != nil || end != nil else {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                if let start, let end, start > end {
                    throw NativeDownloadError.unsupported("Invalid range.")
                }
                return ItemRangeSegment(start: start, end: end)
            }
            guard let position = Int(piece), position > 0 else {
                throw NativeDownloadError.unsupported("Invalid range.")
            }
            return ItemRangeSegment(start: position, end: position)
        }
    }

    private static func itemRangeSplit(_ value: String) -> (String, String)? {
        for separator in ["...", "..", "~", "-"] {
            if let range = value.range(of: separator) {
                return (String(value[..<range.lowerBound]), String(value[range.upperBound...]))
            }
        }
        return nil
    }

    private static func positiveItemRangeBound(_ value: String) throws -> Int? {
        guard !value.isEmpty else { return nil }
        guard let bound = Int(value), bound > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return bound
    }

    static func illustrationURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()
        let scopes = illustrationLinkScopes(fromHTML: html)
        let searchHTML = scopes.isEmpty ? [html] : scopes

        for scope in searchHTML {
            for href in anchorHREFs(fromHTML: scope) {
                guard let rawURL = absoluteURL(href, baseURL: baseURL),
                      let id = illustrationID(from: rawURL) else {
                    continue
                }
                let url = viewURL(illustrationID: id, sourceURL: baseURL)
                let normalized = URLIdentity.normalize(url.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                urls.append(url)
            }
        }
        return urls
    }

    static func popupURLs(fromHTML html: String, baseURL: URL) -> [URL] {
        var urls: [URL] = []
        var seen = Set<String>()

        for href in anchorHREFs(fromHTML: html) {
            guard let url = absoluteURL(href, baseURL: baseURL),
                  url.path.lowercased().hasSuffix("/view_popup.php"),
                  illustrationID(from: url) != nil else {
                continue
            }
            let normalized = URLIdentity.normalize(url.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            urls.append(url)
        }

        return urls.sorted { lhs, rhs in
            (queryValue("p", in: lhs).flatMap(Int.init) ?? 0) < (queryValue("p", in: rhs).flatMap(Int.init) ?? 0)
        }
    }

    static func imageCandidates(fromHTML html: String, pageURL: URL) -> [NijieImageCandidate] {
        let scopes = imageScopes(fromHTML: html)
        let searchHTML = scopes.isEmpty ? [html] : scopes
        var results: [NijieImageCandidate] = []
        var seen = Set<String>()

        func append(_ raw: String?, referer: String) {
            guard let raw,
                  let url = absoluteURL(decodeURLString(raw), baseURL: pageURL),
                  !url.path.lowercased().contains("/filter/"),
                  let normalizedURL = normalizedImageURL(url),
                  isLikelyImage(normalizedURL) else {
                return
            }
            let normalized = URLIdentity.normalize(normalizedURL.absoluteString)
            guard !seen.contains(normalized) else { return }
            seen.insert(normalized)
            results.append(NijieImageCandidate(remoteURL: normalizedURL, referer: referer))
        }

        for scope in searchHTML {
            for attrs in tagAttributes(tag: "img", html: scope) {
                let values = attributeValues(from: attrs)
                if isExcludedImage(values: values) {
                    continue
                }
                append(values["data-src"] ?? values["data-original"] ?? values["data-lazy-src"] ?? values["src"], referer: pageURL.absoluteString)
            }

            for href in anchorHREFs(fromHTML: scope) {
                append(href, referer: pageURL.absoluteString)
            }
        }

        if results.isEmpty {
            for raw in firstCaptures(patterns: [
                #""(?:url|src|image|original)"\s*:\s*"([^"]+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^"]*)?)""#,
                #"'(?:url|src|image|original)'\s*:\s*'([^']+\.(?:jpg|jpeg|png|gif|webp)(?:\?[^']*)?)'"#
            ], in: html) {
                append(raw, referer: pageURL.absoluteString)
            }
        }

        return results
    }

    static func imageAssets(from candidates: [NijieImageCandidate], illustID: String) -> [NijieImageAsset] {
        var assets: [NijieImageAsset] = []
        var seen = Set<String>()
        for candidate in candidates {
            let normalized = URLIdentity.normalize(candidate.remoteURL.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)
            assets.append(NijieImageAsset(
                remoteURL: candidate.remoteURL,
                illustID: illustID,
                pageIndex: assets.count,
                referer: candidate.referer
            ))
        }
        return assets
    }

    static func memberName(fromHTML html: String, memberID: String) -> String {
        let normalized = decodeHTML(html)
        let name = elementText(pattern: #"<[^>]+\bclass\s*=\s*["'][^"']*\bname\b[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: normalized) ??
            elementText(pattern: #"<h1\b[^>]*>(.*?)</h1>"#, in: normalized) ??
            metaContent(from: normalized, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: normalized) ??
            "Nijie \(memberID)"
        return cleanTitle(name, fallback: "Nijie \(memberID)")
    }

    static func illustrationTitle(fromHTML html: String, pageURL: URL) -> String {
        let normalized = decodeHTML(html)
        let title = elementText(pattern: #"<[^>]+\bclass\s*=\s*["'][^"']*(?:illust_title|illust-title|title)[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: normalized) ??
            metaContent(from: normalized, names: ["og:title", "twitter:title"]) ??
            titleTag(fromHTML: normalized) ??
            illustrationID(from: pageURL) ??
            "Nijie Illustration"
        return cleanTitle(title, fallback: "Nijie \(illustrationID(from: pageURL) ?? "illustration")")
    }

    static func artistName(fromHTML html: String, memberID: String?) -> String? {
        let normalized = decodeHTML(html)
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b([^>]*)>(.*?)</a>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return nil
        }

        let range = NSRange(normalized.startIndex..<normalized.endIndex, in: normalized)
        for match in regex.matches(in: normalized, range: range) {
            guard let attrsRange = Range(match.range(at: 1), in: normalized),
                  let bodyRange = Range(match.range(at: 2), in: normalized) else {
                continue
            }
            let values = attributeValues(from: String(normalized[attrsRange]))
            let href = values["href"] ?? ""
            guard let hrefMemberID = firstCapture(patterns: [#"members(?:_illust)?\.php\?[^"']*id=([0-9]+)"#], in: href),
                  memberID == nil || hrefMemberID == memberID else {
                continue
            }
            let name = cleanTitle(String(normalized[bodyRange]), fallback: "")
            if !name.isEmpty {
                return name
            }
        }

        let candidate = elementText(pattern: #"<[^>]+\bclass\s*=\s*["'][^"']*(?:artist|author|member|user)[^"']*["'][^>]*>(.*?)</[^>]+>"#, in: normalized) ??
            metaContent(from: normalized, names: ["article:author", "author", "artist"])
        return candidate.map { cleanTitle($0, fallback: "") }.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func isLoginRequiredHTML(_ html: String) -> Bool {
        let lowered = html.lowercased()
        return lowered.contains("login.php") && lowered.contains("password") ||
            lowered.contains("islogin") && lowered.contains("false") ||
            lowered.contains("\u{30ED}\u{30B0}\u{30A4}\u{30F3}") && lowered.contains("password")
    }

    static func asset(for image: NijieImageAsset, metadata: [String: String] = [:]) -> ResolvedAsset {
        let ext = mediaFormat(for: image.remoteURL)
        return ResolvedAsset(
            remoteURL: image.remoteURL,
            filename: "\(image.illustID)_p\(image.pageIndex).\(ext)".sanitizedFilename(maxLength: 180),
            metadata: metadata,
            referer: image.referer
        )
    }

    static func assetMetadata(for image: NijieImageAsset, title: String, collectionType: String, memberID: String, memberName: String) -> [String: String] {
        let format = mediaFormat(for: image.remoteURL)
        return DownloadMetadata.clean([
            "artist": memberName,
            "author": memberName,
            "creator": memberName,
            "user": memberName,
            "username": memberName,
            "uploader": memberName,
            "channel": memberName,
            "member_id": memberID,
            "user_id": memberID,
            "illust_id": image.illustID,
            "post_id": image.illustID,
            "gallery_id": image.illustID,
            "id": image.illustID,
            "media_id": "\(image.illustID)-\(image.pageIndex + 1)",
            "slug": image.illustID,
            "site": "Nijie",
            "title": title,
            "category": "illustration",
            "collection_type": collectionType,
            "type": "image",
            "media_type": "image",
            "page": String(image.pageIndex + 1),
            "page_index": String(image.pageIndex),
            "position": String(image.pageIndex + 1),
            "format": format,
            "media_format": format,
            "image_url": image.remoteURL.absoluteString,
            "media_url": image.remoteURL.absoluteString,
            "source_url": image.remoteURL.absoluteString,
            "page_url": image.referer
        ])
    }

    static func nijieMetadata(title: String, type: String, illustID: String, memberID: String, memberName: String, imageCount: Int, sourceURL: URL?) -> [String: String] {
        DownloadMetadata.clean([
            "artist": memberName,
            "author": memberName,
            "creator": memberName,
            "user": memberName,
            "username": memberName,
            "uploader": memberName,
            "channel": memberName,
            "member_id": memberID,
            "user_id": memberID,
            "illust_id": illustID,
            "post_id": illustID,
            "gallery_id": illustID.isEmpty ? memberID : illustID,
            "id": illustID.isEmpty ? memberID : illustID,
            "category": "illustration",
            "type": type,
            "media_type": "image",
            "media_count": String(imageCount),
            "image_count": String(imageCount),
            "slug": illustID.isEmpty ? memberID : illustID,
            "site": "Nijie",
            "title": title,
            "url": sourceURL?.absoluteString ?? "",
            "source_url": sourceURL?.absoluteString ?? "",
            "page_url": sourceURL?.absoluteString ?? ""
        ])
    }

    static func mediaFormat(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if ext == "jpeg" {
            return "jpg"
        }
        return ext.isEmpty ? "jpg" : ext
    }

    private static func pageNumber(fromMemberURL url: URL) -> Int {
        queryValue("p", in: url).flatMap(Int.init) ?? -1
    }

    private static func imageScopes(fromHTML html: String) -> [String] {
        let patterns = [
            #"<(?:div|section|article)\b[^>]*(?:id|class)\s*=\s*["'][^"']*img_window[^"']*["'][^>]*>(.*?)</(?:div|section|article)>"#,
            #"<(?:div|section|article)\b[^>]*(?:id|class)\s*=\s*["'][^"']*illust[^"']*["'][^>]*>(.*?)</(?:div|section|article)>"#
        ]
        return patterns.flatMap { captureMatches(pattern: $0, in: html) }
    }

    private static func illustrationLinkScopes(fromHTML html: String) -> [String] {
        captureMatches(
            pattern: #"<div\b[^>]*\bclass\s*=\s*["'][^"']*\bnijie\b[^"']*["'][^>]*>(.*?)</div>"#,
            in: html
        )
    }

    private static func normalizedImageURL(_ url: URL) -> URL? {
        var raw = url.absoluteString
        raw = raw.replacingOccurrences(of: #"/__rs_l[0-9]+x[0-9]+/"#, with: "/", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"/rs_l[0-9]+x[0-9]+/"#, with: "/", options: .regularExpression)
        raw = raw.replacingOccurrences(of: #"/filter/"#, with: "/", options: .regularExpression)
        return URL(string: raw)
    }

    private static func isLikelyImage(_ url: URL) -> Bool {
        let ext = url.pathExtension.lowercased()
        let lowered = url.absoluteString.lowercased()
        guard ["jpg", "jpeg", "png", "gif", "webp"].contains(ext) else {
            return false
        }
        return !lowered.contains("user_icon") &&
            !lowered.contains("/icon/") &&
            !lowered.contains("/profile/") &&
            !lowered.contains("/banner") &&
            !lowered.contains("/ads/") &&
            !lowered.contains("/logo")
    }

    private static func isExcludedImage(values: [String: String]) -> Bool {
        let haystack = [
            values["id"],
            values["class"],
            values["alt"],
            values["src"]
        ].compactMap { $0?.lowercased() }.joined(separator: " ")
        return haystack.contains("user_icon") ||
            haystack.contains("avatar") ||
            haystack.contains("profile") ||
            haystack.contains("banner") ||
            haystack.contains("logo")
    }

    private static func anchorHREFs(fromHTML html: String) -> [String] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<a\b[^>]*\bhref\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>"']+))"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            for group in 1...3 {
                guard let capture = Range(match.range(at: group), in: html) else { continue }
                return decodeHTML(String(html[capture])).trimmed
            }
            return nil
        }
    }

    private static func tagAttributes(tag: String, html: String) -> [String] {
        let escaped = NSRegularExpression.escapedPattern(for: tag)
        guard let regex = try? NSRegularExpression(
            pattern: #"<\#(escaped)\b([^>]*)>"#,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: html) else { return nil }
            return String(html[capture])
        }
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

    private static func metaContent(from html: String, names: Set<String>) -> String? {
        guard let regex = try? NSRegularExpression(pattern: #"<meta\b([^>]*)>"#, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        for match in regex.matches(in: html, range: range) {
            guard let attributesRange = Range(match.range(at: 1), in: html) else { continue }
            let values = attributeValues(from: String(html[attributesRange]))
            let key = (values["property"] ?? values["name"] ?? values["itemprop"])?.lowercased()
            guard let key, names.contains(key),
                  let content = values["content"]?.trimmed,
                  !content.isEmpty else {
                continue
            }
            return content
        }
        return nil
    }

    private static func elementText(pattern: String, in html: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        return decodeHTML(stripTags(String(html[capture]))).trimmed
    }

    private static func titleTag(fromHTML html: String) -> String? {
        elementText(pattern: #"<title\b[^>]*>(.*?)</title>"#, in: html)
    }

    private static func firstCapture(patterns: [String], in text: String) -> String? {
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
                continue
            }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            guard let match = regex.firstMatch(in: text, range: range),
                  let capture = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[capture])
        }
        return nil
    }

    private static func firstCaptures(patterns: [String], in text: String) -> [String] {
        var values: [String] = []
        var seen = Set<String>()
        for pattern in patterns {
            for value in captureMatches(pattern: pattern, in: text) {
                guard !seen.contains(value) else { continue }
                seen.insert(value)
                values.append(value)
            }
        }
        return values
    }

    private static func captureMatches(pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).compactMap { match in
            guard let capture = Range(match.range(at: 1), in: text) else { return nil }
            return String(text[capture])
        }
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        guard !value.isEmpty,
              !value.hasPrefix("#"),
              !value.lowercased().hasPrefix("javascript:"),
              !value.lowercased().hasPrefix("mailto:") else {
            return nil
        }
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func queryValue(_ name: String, in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name.lowercased() == name.lowercased() }?
            .value
    }

    private static func numericID(_ value: String?) -> String? {
        guard let value = value?.trimmed,
              value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return value
    }

    private static func decodeURLString(_ text: String) -> String {
        decodeHTML(text)
            .replacingOccurrences(of: "\\/", with: "/")
            .replacingOccurrences(of: "\\u002F", with: "/")
            .replacingOccurrences(of: "\\u0026", with: "&")
    }

    private static func cleanTitle(_ raw: String, fallback: String) -> String {
        var title = decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
        for suffix in [
            " - \u{30CB}\u{30B8}\u{30A8}",
            " | \u{30CB}\u{30B8}\u{30A8}",
            " - nijie",
            " | nijie",
            " - nijie.info",
            " | nijie.info"
        ] {
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                title.removeLast(suffix.count)
                title = title.trimmed
            }
        }
        return title.isEmpty ? fallback : title.sanitizedFilename(maxLength: 120)
    }

    private static func stripTags(_ text: String) -> String {
        text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
    }

    private static func decodeHTML(_ text: String) -> String {
        var output = text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")

        guard let regex = try? NSRegularExpression(pattern: #"&#(x?[0-9A-Fa-f]+);"#) else {
            return output
        }
        let matches = regex.matches(in: output, range: NSRange(output.startIndex..<output.endIndex, in: output)).reversed()
        for match in matches {
            guard let whole = Range(match.range(at: 0), in: output),
                  let digitsRange = Range(match.range(at: 1), in: output) else {
                continue
            }
            let digits = String(output[digitsRange])
            let radix = digits.lowercased().hasPrefix("x") ? 16 : 10
            let value = radix == 16 ? String(digits.dropFirst()) : digits
            if let scalarValue = UInt32(value, radix: radix),
               let scalar = UnicodeScalar(scalarValue) {
                output.replaceSubrange(whole, with: String(Character(scalar)))
            }
        }
        return output
    }

    private static func canonicalScheme(for sourceURL: URL) -> String {
        let host = sourceURL.host?.lowercased() ?? ""
        if host == "nijie.test" || host.hasSuffix(".nijie.test") {
            return sourceURL.scheme ?? "https"
        }
        return "https"
    }

    private static func canonicalHost(for sourceURL: URL) -> String {
        let host = sourceURL.host?.lowercased() ?? ""
        return host.hasSuffix(".test") || host == "nijie.test" ? "nijie.test" : "nijie.info"
    }

    private static func isSupportedHost(_ host: String) -> Bool {
        supportedDomains.contains { domain in
            host == domain || host.hasSuffix("." + domain)
        }
    }

    private static let supportedDomains = [
        "nijie.info",
        "nijie.test"
    ]
}
