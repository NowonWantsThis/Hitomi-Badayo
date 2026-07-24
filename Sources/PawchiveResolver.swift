import Foundation

struct PawchiveRoute: Equatable {
    var service: String
    var creatorID: String
    var postID: String?
}

enum PawchiveFileCategory: String, CaseIterable, Sendable {
    case image
    case video
    case html
    case other
}

struct PawchiveFileTypeSelection: Equatable, Sendable {
    var images: Bool
    var videos: Bool
    var html: Bool
    var other: Bool

    static let all = PawchiveFileTypeSelection(
        images: true,
        videos: true,
        html: true,
        other: true
    )

    func includes(_ category: PawchiveFileCategory) -> Bool {
        switch category {
        case .image: return images
        case .video: return videos
        case .html: return html
        case .other: return other
        }
    }
}

private struct PawchiveFileReference: Decodable {
    var name: String?
    var path: String?
}

private struct PawchivePost: Decodable {
    var id: String
    var user: String
    var service: String
    var title: String?
    var content: String?
    var added: String?
    var published: String?
    var file: PawchiveFileReference?
    var attachments: [PawchiveFileReference]

    enum CodingKeys: String, CodingKey {
        case id
        case user
        case service
        case title
        case content
        case substring
        case added
        case published
        case file
        case attachments
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeLossyString(forKey: .id)
        user = try container.decodeLossyString(forKey: .user)
        service = try container.decodeLossyString(forKey: .service)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        content = try container.decodeIfPresent(String.self, forKey: .content) ??
            container.decodeIfPresent(String.self, forKey: .substring)
        added = try container.decodeIfPresent(String.self, forKey: .added)
        published = try container.decodeIfPresent(String.self, forKey: .published)
        file = try container.decodeIfPresent(PawchiveFileReference.self, forKey: .file)
        attachments = try container.decodeIfPresent([PawchiveFileReference].self, forKey: .attachments) ?? []
    }
}

private struct PawchivePostResponse: Decodable {
    var post: PawchivePost

    private enum CodingKeys: String, CodingKey {
        case post
    }

    init(from decoder: Decoder) throws {
        if let direct = try? PawchivePost(from: decoder) {
            post = direct
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        post = try container.decode(PawchivePost.self, forKey: .post)
    }
}

private struct PawchiveProfile: Decodable {
    var name: String?
}

private extension KeyedDecodingContainer {
    func decodeLossyString(forKey key: Key) throws -> String {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Int64.self, forKey: key) {
            return String(value)
        }
        throw DecodingError.typeMismatch(
            String.self,
            DecodingError.Context(
                codingPath: codingPath + [key],
                debugDescription: "Expected a string or integer identifier."
            )
        )
    }
}

final class PawchiveResolver {
    static let defaultSiteAddresses = [
        "https://pawchive.pw",
        "https://kemono.cr",
        "https://kemono.su",
        "https://coomer.st"
    ]

    private static let legacyHosts: Set<String> = [
        "pawchive.pw",
        "www.pawchive.pw",
        "pawchive.st",
        "www.pawchive.st"
    ]
    private static let userAgent = "Hitomi Badayo Pawchive/0.1"
    private static let pageSize = 50
    private static let maximumPageCount = 10_000

    func canResolve(_ url: URL, siteAddresses: [String]) -> Bool {
        guard Self.route(from: url) != nil,
              let host = url.host?.lowercased() else {
            return false
        }
        return Self.allowedHosts(siteAddresses: siteAddresses).contains(host)
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        siteAddresses: [String],
        downloadLargeOriginalFiles: Bool,
        fileTypeSelection: PawchiveFileTypeSelection = .all,
        rangeExpression: String = ""
    ) async throws -> ResolvedDownload {
        guard let route = Self.route(from: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        let candidates = Self.candidateSiteURLs(inputURL: url, siteAddresses: siteAddresses)
        guard !candidates.isEmpty else {
            throw NativeDownloadError.unsupported("Add a Pawchive site address in Kemono friends settings.")
        }

        if let postID = route.postID {
            let endpoint = [route.service, "user", route.creatorID, "post", postID]
            let (response, effectiveSite) = try await request(
                PawchivePostResponse.self,
                endpoint: endpoint,
                candidates: candidates,
                referer: url.absoluteString,
                headers: headers
            )
            let post = response.post
            let creatorName = await profileName(
                route: route,
                preferredSite: effectiveSite,
                candidates: candidates,
                referer: url.absoluteString,
                headers: headers
            )
            return try Self.makeDownload(
                posts: [post],
                route: route,
                sourceURL: url,
                effectiveSite: effectiveSite,
                candidateSites: candidates,
                creatorName: creatorName,
                downloadLargeOriginalFiles: downloadLargeOriginalFiles,
                fileTypeSelection: fileTypeSelection,
                isCollection: false,
                rangeExpression: "",
                listedPostCount: 1
            )
        }

        let itemRange = rangeExpression.trimmed
        let discoveryLimit = try Self.maximumRequestedItem(in: itemRange)
        var posts: [PawchivePost] = []
        var seenPostIDs = Set<String>()
        var effectiveSite: URL?
        var pageCandidates = candidates

        for page in 0..<Self.maximumPageCount {
            try Task.checkCancellation()
            let offset = page * Self.pageSize
            let endpoint = [route.service, "user", route.creatorID, "posts"]
            let legacyEndpoint = [route.service, "user", route.creatorID]
            let (pagePosts, selectedSite) = try await request(
                [PawchivePost].self,
                endpoint: endpoint,
                alternativeEndpoints: [legacyEndpoint],
                queryItems: [URLQueryItem(name: "o", value: String(offset))],
                candidates: pageCandidates,
                referer: url.absoluteString,
                headers: headers
            )
            if effectiveSite == nil {
                effectiveSite = selectedSite
                pageCandidates = Self.uniqueSiteURLs([selectedSite] + candidates)
            }
            guard !pagePosts.isEmpty else { break }

            for post in pagePosts {
                let identity = "\(post.service)|\(post.user)|\(post.id)"
                guard seenPostIDs.insert(identity).inserted else { continue }
                posts.append(post)
                if let discoveryLimit, posts.count >= discoveryLimit {
                    break
                }
            }
            if let discoveryLimit, posts.count >= discoveryLimit {
                break
            }
        }

        guard !posts.isEmpty, let effectiveSite else {
            throw NativeDownloadError.noFiles
        }
        let listedPostCount = posts.count
        if !itemRange.isEmpty {
            let indexes = try Self.itemIndexes(for: itemRange, total: posts.count)
            posts = indexes.map { posts[$0] }
        }

        let creatorName = await profileName(
            route: route,
            preferredSite: effectiveSite,
            candidates: candidates,
            referer: url.absoluteString,
            headers: headers
        )
        return try Self.makeDownload(
            posts: posts,
            route: route,
            sourceURL: url,
            effectiveSite: effectiveSite,
            candidateSites: candidates,
            creatorName: creatorName,
            downloadLargeOriginalFiles: downloadLargeOriginalFiles,
            fileTypeSelection: fileTypeSelection,
            isCollection: true,
            rangeExpression: itemRange,
            listedPostCount: listedPostCount
        )
    }

    static func normalizedSiteAddress(_ rawValue: String) -> String? {
        var value = rawValue.trimmed
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard var components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { return nil }
        return url.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }

    static func normalizedSiteAddresses(_ values: [String]) -> [String] {
        var output: [String] = []
        var seen = Set<String>()
        for value in values {
            guard let normalized = normalizedSiteAddress(value),
                  seen.insert(normalized.lowercased()).inserted else {
                continue
            }
            output.append(normalized)
        }
        return output
    }

    static func route(from url: URL) -> PawchiveRoute? {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
        guard parts.count == 3 || parts.count == 5,
              parts[1].lowercased() == "user",
              Self.isSafeRouteValue(parts[0]),
              Self.isSafeRouteValue(parts[2]) else {
            return nil
        }
        if parts.count == 5 {
            guard parts[3].lowercased() == "post", Self.isSafeRouteValue(parts[4]) else {
                return nil
            }
            return PawchiveRoute(service: parts[0], creatorID: parts[2], postID: parts[4])
        }
        return PawchiveRoute(service: parts[0], creatorID: parts[2], postID: nil)
    }

    private func profileName(
        route: PawchiveRoute,
        preferredSite: URL,
        candidates: [URL],
        referer: String,
        headers: HTTPRequestOptions
    ) async -> String {
        do {
            let (profile, _) = try await request(
                PawchiveProfile.self,
                endpoint: [route.service, "user", route.creatorID, "profile"],
                candidates: Self.uniqueSiteURLs([preferredSite] + candidates),
                referer: referer,
                headers: headers
            )
            return Self.cleanTitle(profile.name, fallback: route.creatorID)
        } catch {
            return route.creatorID
        }
    }

    private func request<T: Decodable>(
        _ type: T.Type,
        endpoint: [String],
        alternativeEndpoints: [[String]] = [],
        queryItems: [URLQueryItem] = [],
        candidates: [URL],
        referer: String,
        headers: HTTPRequestOptions
    ) async throws -> (T, URL) {
        var lastError: Error?
        for site in candidates {
            for candidateEndpoint in [endpoint] + alternativeEndpoints {
                try Task.checkCancellation()
                do {
                    let apiURL = try Self.apiURL(
                        site: site,
                        endpoint: candidateEndpoint,
                        queryItems: queryItems
                    )
                    let accept = Self.usesModernKemonoAPI(site) ? "text/css" : "application/json"
                    let (data, response) = try await HTTPClient.shared.dataResponse(
                        from: apiURL,
                        referer: headers.referer ?? referer,
                        userAgent: headers.userAgent ?? Self.userAgent,
                        additionalHeaders: ["Accept": accept]
                    )
                    let decoded = try JSONDecoder().decode(type, from: data)
                    let effectiveSite = Self.siteOrigin(from: response.url ?? apiURL) ?? site
                    return (decoded, effectiveSite)
                } catch {
                    if Task.isCancelled { throw CancellationError() }
                    lastError = error
                }
            }
        }
        throw lastError ?? NativeDownloadError.unsupported("No Pawchive site address responded.")
    }

    private static func makeDownload(
        posts: [PawchivePost],
        route: PawchiveRoute,
        sourceURL: URL,
        effectiveSite: URL,
        candidateSites: [URL],
        creatorName: String,
        downloadLargeOriginalFiles: Bool,
        fileTypeSelection: PawchiveFileTypeSelection,
        isCollection: Bool,
        rangeExpression: String,
        listedPostCount: Int
    ) throws -> ResolvedDownload {
        let safeCreator = cleanTitle(creatorName, fallback: route.creatorID)
        let serviceName = cleanTitle(route.service, fallback: "pawchive")
        let creatorFolder = "\(safeCreator) (\(serviceName))".sanitizedFilename(maxLength: 120)
        let temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-Pawchive-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)

        var assets: [ResolvedAsset] = []
        var skippedPSDCount = 0
        var skippedFileTypeCount = 0
        var remoteFileCount = 0
        do {
            for (postOffset, post) in posts.enumerated() {
                try Task.checkCancellation()
                let postTitle = cleanTitle(post.title, fallback: "Post \(post.id)")
                let postDate = compactDate(post.published ?? post.added)
                let postFolder = "\(postDate) \(postTitle)".sanitizedFilename(maxLength: 120)
                let pageURL = postPageURL(
                    site: effectiveSite,
                    service: post.service.isEmpty ? route.service : post.service,
                    creatorID: post.user.isEmpty ? route.creatorID : post.user,
                    postID: post.id
                ) ?? sourceURL
                var seenPaths = Set<String>()
                var references: [PawchiveFileReference] = []
                if let primary = post.file {
                    references.append(primary)
                }
                references.append(contentsOf: post.attachments)

                var filePosition = 0
                for reference in references {
                    guard let rawPath = reference.path?.trimmed, !rawPath.isEmpty else { continue }
                    let identity = rawPath.lowercased()
                    guard seenPaths.insert(identity).inserted else { continue }
                    let originalName = attachmentName(reference, fallbackIndex: filePosition + 1)
                    if !downloadLargeOriginalFiles && isPSD(filename: originalName, path: rawPath) {
                        skippedPSDCount += 1
                        continue
                    }
                    let category = fileCategory(filename: originalName, path: rawPath)
                    guard fileTypeSelection.includes(category) else {
                        skippedFileTypeCount += 1
                        continue
                    }
                    guard let remoteURL = fileURL(site: effectiveSite, path: rawPath, originalName: originalName) else {
                        continue
                    }
                    filePosition += 1
                    remoteFileCount += 1
                    let numberedName = String(format: "%02d_%@", filePosition, originalName)
                        .sanitizedFilename(maxLength: 180)
                    let relativeName = isCollection ? "\(postFolder)/\(numberedName)" : numberedName
                    let modificationTime = timestamp(post.published ?? post.added)
                    var metadata = assetMetadata(
                        post: post,
                        creatorName: safeCreator,
                        title: postTitle,
                        pageURL: pageURL,
                        position: filePosition,
                        postPosition: postOffset + 1,
                        originalName: originalName
                    )
                    if let modificationTime {
                        metadata["original_modification_time"] = String(modificationTime)
                    }
                    // Pawchive can retain post records after an individual archive file disappears.
                    // Match the reference downloader by recording that failure and continuing the creator.
                    metadata["continue_asset_failures"] = "true"
                    if isCollection {
                        metadata["preserve_relative_path"] = "true"
                    }
                    let alternatives = uniqueSiteURLs(candidateSites)
                        .filter { siteOrigin(from: $0)?.host?.lowercased() != effectiveSite.host?.lowercased() }
                        .compactMap { fileURL(site: $0, path: rawPath, originalName: originalName) }
                    assets.append(ResolvedAsset(
                        remoteURL: remoteURL,
                        filename: relativeName,
                        metadata: metadata,
                        referer: pageURL.absoluteString,
                        userAgent: Self.userAgent,
                        alternativeRemoteURLs: alternatives
                    ))
                }

                if fileTypeSelection.html {
                    let htmlName = "\(postFolder).html"
                    let localHTML = temporaryDirectory.appendingPathComponent("\(postOffset + 1)-\(UUID().uuidString).html")
                    try metadataHTML(
                        post: post,
                        title: postTitle,
                        creatorName: safeCreator,
                        pageURL: pageURL
                    ).write(to: localHTML, atomically: true, encoding: .utf8)
                    var htmlMetadata = assetMetadata(
                        post: post,
                        creatorName: safeCreator,
                        title: postTitle,
                        pageURL: pageURL,
                        position: filePosition + 1,
                        postPosition: postOffset + 1,
                        originalName: htmlName
                    )
                    htmlMetadata["type"] = "metadata"
                    if let modificationTime = timestamp(post.published ?? post.added) {
                        htmlMetadata["original_modification_time"] = String(modificationTime)
                    }
                    if isCollection {
                        htmlMetadata["preserve_relative_path"] = "true"
                    }
                    assets.append(ResolvedAsset(
                        remoteURL: localHTML,
                        filename: isCollection ? "\(postFolder)/\(htmlName)" : htmlName,
                        metadata: htmlMetadata,
                        referer: pageURL.absoluteString
                    ))
                }
            }
        } catch {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw error
        }

        guard !assets.isEmpty else {
            try? FileManager.default.removeItem(at: temporaryDirectory)
            throw NativeDownloadError.noFiles
        }

        let singlePostTitle = posts.first.map { cleanTitle($0.title, fallback: "Post \($0.id)") }
        let title = isCollection
            ? creatorFolder
            : (singlePostTitle ?? creatorFolder)
        let singlePostFolder = posts.first.map {
            "\(compactDate($0.published ?? $0.added)) \(cleanTitle($0.title, fallback: "Post \($0.id)"))"
                .sanitizedFilename(maxLength: 120)
        }
        let folderName = isCollection
            ? creatorFolder
            : "\(creatorFolder)/\(singlePostFolder ?? "Post")"

        var metadata: [String: String] = [
            "site": "Pawchive",
            "handler": "pawchive_native",
            "extractor": isCollection ? "pawchive_creator" : "pawchive_post",
            "type": isCollection ? "collection" : "gallery",
            "service": route.service,
            "creator": safeCreator,
            "artist": safeCreator,
            "creator_id": route.creatorID,
            "post_count": String(posts.count),
            "listed_post_count": String(listedPostCount),
            "file_count": String(remoteFileCount),
            "skipped_psd_count": String(skippedPSDCount),
            "skipped_file_type_count": String(skippedFileTypeCount),
            "large_original_files": downloadLargeOriginalFiles ? "true" : "false",
            "download_images": fileTypeSelection.images ? "true" : "false",
            "download_videos": fileTypeSelection.videos ? "true" : "false",
            "download_html": fileTypeSelection.html ? "true" : "false",
            "download_other_files": fileTypeSelection.other ? "true" : "false",
            "source_url": sourceURL.absoluteString,
            "site_address": effectiveSite.absoluteString,
            "preserve_resolved_folder_path": "true"
        ]
        if isCollection {
            metadata["range_scope"] = "collection_items"
            metadata["range_total"] = String(listedPostCount)
            metadata["range_selected"] = String(posts.count)
            if !rangeExpression.isEmpty {
                metadata["range"] = rangeExpression
            }
        } else if let post = posts.first {
            metadata["id"] = post.id
            metadata["post_id"] = post.id
            metadata["title"] = cleanTitle(post.title, fallback: "Post \(post.id)")
            if let published = post.published ?? post.added {
                metadata["published"] = published
                metadata["date"] = compactDate(published)
            }
        }
        metadata = DownloadMetadata.clean(metadata)

        return ResolvedDownload(
            title: title,
            folderName: folderName,
            assets: assets,
            metadata: metadata,
            temporaryAssetDirectories: [temporaryDirectory]
        )
    }

    private static func apiURL(site: URL, endpoint: [String], queryItems: [URLQueryItem]) throws -> URL {
        var url = site
            .appendingPathComponent("api", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        for component in endpoint {
            url.appendPathComponent(component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let result = components.url else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        return result
    }

    private static func fileURL(site: URL, path: String, originalName: String) -> URL? {
        guard let origin = siteOrigin(from: site),
              var components = URLComponents(url: origin, resolvingAgainstBaseURL: false),
              let siteHost = components.host?.lowercased() else {
            return nil
        }
        let baseHost = siteHost.hasPrefix("www.") ? String(siteHost.dropFirst(4)) : siteHost
        components.host = Self.usesModernKemonoAPI(site)
            ? baseHost
            : (baseHost.hasPrefix("file.") ? baseHost : "file.\(baseHost)")
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components.path = "/data\(normalizedPath)"
        components.queryItems = originalName.isEmpty ? nil : [URLQueryItem(name: "f", value: originalName)]
        components.fragment = nil
        return components.url
    }

    private static func postPageURL(
        site: URL,
        service: String,
        creatorID: String,
        postID: String
    ) -> URL? {
        var url = site
        for component in [service, "user", creatorID, "post", postID] {
            url.appendPathComponent(component)
        }
        return url
    }

    private static func candidateSiteURLs(inputURL: URL, siteAddresses: [String]) -> [URL] {
        let input = siteOrigin(from: inputURL)
        let configured = normalizedSiteAddresses(siteAddresses).compactMap(URL.init(string:))
        return uniqueSiteURLs([input].compactMap { $0 } + configured)
    }

    private static func allowedHosts(siteAddresses: [String]) -> Set<String> {
        var hosts = legacyHosts
        for value in normalizedSiteAddresses(siteAddresses) {
            if let host = URL(string: value)?.host?.lowercased() {
                hosts.insert(host)
            }
        }
        return hosts
    }

    private static func uniqueSiteURLs(_ values: [URL]) -> [URL] {
        var output: [URL] = []
        var seen = Set<String>()
        for value in values {
            guard let origin = siteOrigin(from: value) else { continue }
            let identity = origin.absoluteString.lowercased()
            guard seen.insert(identity).inserted else { continue }
            output.append(origin)
        }
        return output
    }

    private static func siteOrigin(from url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty else {
            return nil
        }
        components.scheme = scheme
        components.host = host
        components.path = ""
        components.query = nil
        components.fragment = nil
        return components.url
    }

    private static func usesModernKemonoAPI(_ site: URL) -> Bool {
        guard let host = site.host?.lowercased() else { return false }
        let baseHost = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        let firstLabel = baseHost.split(separator: ".").first.map(String.init) ?? ""
        return firstLabel == "coomer" || firstLabel == "kemono"
    }

    private static func attachmentName(_ reference: PawchiveFileReference, fallbackIndex: Int) -> String {
        let named = reference.name?.trimmed ?? ""
        let pathName = reference.path.flatMap { path -> String? in
            guard let component = URL(string: "https://pawchive.invalid\(path)")?.lastPathComponent else {
                return nil
            }
            return component.removingPercentEncoding ?? component
        }?.trimmed ?? ""
        let fallback = pathName.isEmpty ? String(format: "file-%02d", fallbackIndex) : pathName
        return (named.isEmpty ? fallback : (named as NSString).lastPathComponent)
            .sanitizedFilename(maxLength: 160)
    }

    private static func isPSD(filename: String, path: String) -> Bool {
        (filename as NSString).pathExtension.lowercased() == "psd" ||
            (path as NSString).pathExtension.lowercased() == "psd"
    }

    static func fileCategory(filename: String, path: String = "") -> PawchiveFileCategory {
        let filenameExtension = (filename as NSString).pathExtension.lowercased()
        let pathExtension = (path as NSString).pathExtension.lowercased()
        let ext = filenameExtension.isEmpty ? pathExtension : filenameExtension
        if imageFileExtensions.contains(ext) {
            return .image
        }
        if videoFileExtensions.contains(ext) {
            return .video
        }
        if htmlFileExtensions.contains(ext) {
            return .html
        }
        return .other
    }

    private static let imageFileExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "heif", "jfif", "jpe", "jpeg", "jpg", "jxl",
        "png", "svg", "tif", "tiff", "webp"
    ]

    private static let videoFileExtensions: Set<String> = [
        "3g2", "3gp", "avi", "flv", "m2ts", "m4v", "mkv", "mov", "mp4", "mpeg",
        "mpg", "mts", "ogv", "ts", "webm", "wmv"
    ]

    private static let htmlFileExtensions: Set<String> = ["htm", "html", "xhtml"]

    private static func assetMetadata(
        post: PawchivePost,
        creatorName: String,
        title: String,
        pageURL: URL,
        position: Int,
        postPosition: Int,
        originalName: String
    ) -> [String: String] {
        let ext = (originalName as NSString).pathExtension.lowercased()
        var metadata: [String: String] = [
            "site": "Pawchive",
            "handler": "pawchive_native",
            "service": post.service,
            "creator": creatorName,
            "artist": creatorName,
            "creator_id": post.user,
            "id": post.id,
            "post_id": post.id,
            "title": title,
            "page_url": pageURL.absoluteString,
            "filename": originalName,
            "format": ext,
            "media_format": ext,
            "index": String(position),
            "post_position": String(postPosition)
        ]
        if let published = post.published ?? post.added {
            metadata["published"] = published
            metadata["date"] = compactDate(published)
        }
        return DownloadMetadata.clean(metadata)
    }

    private static func metadataHTML(
        post: PawchivePost,
        title: String,
        creatorName: String,
        pageURL: URL
    ) -> String {
        let published = post.published ?? post.added ?? ""
        let body = (post.content ?? "").trimmed
        return """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscape(title))</title>
          <style>
            body { max-width: 760px; margin: 32px auto; padding: 0 20px; font: 16px -apple-system, sans-serif; line-height: 1.55; }
            h1 { font-size: 24px; } .meta { color: #666; } pre { white-space: pre-wrap; overflow-wrap: anywhere; font: inherit; }
          </style>
        </head>
        <body>
          <h1>\(htmlEscape(title))</h1>
          <p class="meta">\(htmlEscape(creatorName)) · \(htmlEscape(post.service)) · \(htmlEscape(published))</p>
          <p><a href="\(htmlEscape(pageURL.absoluteString))">Open original post</a></p>
          <pre>\(htmlEscape(body))</pre>
        </body>
        </html>
        """
    }

    private static func htmlEscape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    private static func cleanTitle(_ value: String?, fallback: String) -> String {
        let cleaned = value?.trimmed ?? ""
        return (cleaned.isEmpty ? fallback : cleaned).sanitizedFilename(maxLength: 120)
    }

    private static func compactDate(_ rawValue: String?) -> String {
        guard let rawValue, let date = parsedDate(rawValue) else { return "00.00.00" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yy.MM.dd"
        return formatter.string(from: date)
    }

    private static func timestamp(_ rawValue: String?) -> Int64? {
        guard let rawValue, let date = parsedDate(rawValue) else { return nil }
        return Int64(date.timeIntervalSince1970)
    }

    private static func parsedDate(_ rawValue: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: rawValue) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: rawValue) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: rawValue) { return date }
        }
        return nil
    }

    private static func isSafeRouteValue(_ value: String) -> Bool {
        !value.isEmpty && value.range(of: #"^[A-Za-z0-9._:@+-]+$"#, options: .regularExpression) != nil
    }

    private struct ItemRangeSegment {
        var start: Int?
        var end: Int?
    }

    private static func maximumRequestedItem(in expression: String) throws -> Int? {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty, !segments.contains(where: { $0.end == nil }) else { return nil }
        return segments.compactMap(\.end).max()
    }

    private static func itemIndexes(for expression: String, total: Int) throws -> [Int] {
        let segments = try itemRangeSegments(from: expression)
        guard !segments.isEmpty else { return Array(0..<max(0, total)) }
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
            throw NativeDownloadError.unsupported("Range did not match any Pawchive posts.")
        }
        return indexes
    }

    private static func itemRangeSegments(from expression: String) throws -> [ItemRangeSegment] {
        guard !expression.isEmpty else { return [] }
        let pieces = expression.filter { !$0.isWhitespace }
            .components(separatedBy: CharacterSet(charactersIn: ",;"))
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
        guard let result = Int(value), result > 0 else {
            throw NativeDownloadError.unsupported("Invalid range.")
        }
        return result
    }
}
