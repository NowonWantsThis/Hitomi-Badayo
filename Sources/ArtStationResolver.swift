import Foundation

struct ArtStationRequest: Equatable {
    enum Kind: Equatable {
        case project(id: String)
        case profile(username: String, section: String?)
    }

    var kind: Kind
    var sourceURL: URL
    var canonicalHost: String
}

final class ArtStationResolver {
    private static let reservedProfilePaths = Set([
        "about", "api", "artwork", "blog", "blogs", "channels", "challenges",
        "contests", "jobs", "learning", "magazine", "marketplace", "prints",
        "projects", "search", "store", "users", "www"
    ])

    func canResolve(_ url: URL) -> Bool {
        Self.request(for: url) != nil
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        guard let request = Self.request(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        let session = ArtStationRequestSession(sourceURL: request.sourceURL, headers: headers)

        switch request.kind {
        case .project(let id):
            let apiURL = try Self.projectAPIURL(id: id, request: request)
            let data = try await session.data(from: apiURL, referer: request.sourceURL.absoluteString)
            return try Self.resolvedDownload(
                from: data,
                baseURL: apiURL,
                sourceURL: request.sourceURL,
                userAgent: headers.userAgent,
                cookieHeader: session.cookieHeader,
                assetLimit: assetLimit
            )
        case .profile(let username, let section):
            return try await resolveProfile(
                request,
                username: username,
                section: section,
                session: session,
                headers: headers,
                assetLimit: assetLimit
            )
        }
    }

    func apiURL(for url: URL) throws -> URL {
        guard let request = Self.request(for: url),
              case .project(let id) = request.kind else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }
        return try Self.projectAPIURL(id: id, request: request)
    }

    static func request(for url: URL) -> ArtStationRequest? {
        guard let host = url.host?.lowercased(),
              let hostInfo = canonicalHostInfo(for: host) else {
            return nil
        }

        if let subdomain = hostInfo.profileSubdomain {
            guard validUsername(subdomain) else { return nil }
            return ArtStationRequest(
                kind: .profile(username: subdomain, section: nil),
                sourceURL: profileURL(username: subdomain, section: nil, canonicalHost: hostInfo.canonicalHost),
                canonicalHost: hostInfo.canonicalHost
            )
        }

        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2, ["artwork", "projects"].contains(parts[0].lowercased()),
           let id = cleanProjectID(parts[1]) {
            return ArtStationRequest(
                kind: .project(id: id),
                sourceURL: projectURL(id: id, canonicalHost: hostInfo.canonicalHost),
                canonicalHost: hostInfo.canonicalHost
            )
        }

        guard let username = parts.first,
              validUsername(username),
              !reservedProfilePaths.contains(username.lowercased()) else {
            return nil
        }
        let section = parts.dropFirst().first?.lowercased() == "likes" ? "likes" : nil
        return ArtStationRequest(
            kind: .profile(username: username, section: section),
            sourceURL: profileURL(username: username, section: section, canonicalHost: hostInfo.canonicalHost),
            canonicalHost: hostInfo.canonicalHost
        )
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let request = request(for: url), case .project = request.kind else { return nil }
        return request.sourceURL
    }

    static func canonicalArtistURL(for url: URL) -> URL? {
        guard let request = request(for: url), case .profile = request.kind else { return nil }
        return request.sourceURL
    }

    static func profileQuickURL(username: String, request: ArtStationRequest) throws -> URL {
        try siteURL(path: "/users/\(username)/quick.json", request: request)
    }

    static func profileProjectsURL(username: String, userID: String, page: Int, request: ArtStationRequest) throws -> URL {
        guard var components = URLComponents(url: try siteURL(path: "/users/\(username)/projects.json", request: request), resolvingAgainstBaseURL: false) else {
            throw NativeDownloadError.invalidURL(request.sourceURL.absoluteString)
        }
        components.queryItems = [
            URLQueryItem(name: "user_id", value: userID),
            URLQueryItem(name: "page", value: String(max(1, page)))
        ]
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(request.sourceURL.absoluteString)
        }
        return url
    }

    static func resolvedDownload(
        from data: Data,
        baseURL: URL,
        sourceURL: URL,
        userAgent: String? = nil,
        cookieHeader: String? = nil,
        assetLimit: Int? = nil
    ) throws -> ResolvedDownload {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }

        let title = stringValue(object["title"]) ?? "ArtStation Project"
        let user = object["user"] as? [String: Any]
        let userDisplayName = userName(from: user)
        let username = stringValue(user?["username"]) ?? stringValue(user?["name"])
        let createdAt = stringValue(object["created_at"])
        let maximumAssets = max(1, assetLimit ?? Int.max)
        var seen = Set<String>()
        var assets: [ResolvedAsset] = []

        assetLoop: for asset in assetDictionaries(from: object) {
            for rawURL in mediaCandidates(from: asset) {
                guard let originalRemote = absoluteURL(rawURL, baseURL: baseURL) else { continue }
                let remote = preferredImageURL(originalRemote)
                let normalized = URLIdentity.normalize(remote.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)

                let fallback = fallbackFilename(for: remote, index: assets.count + 1, asset: asset)
                let filename = String(format: "%04d-%@", assets.count + 1, fallback).sanitizedFilename(maxLength: 180)
                let alternatives = remote == originalRemote ? [] : [originalRemote]
                var additionalHeaders: [ResolvedRequestHeader] = []
                if let cookieHeader, !cookieHeader.trimmed.isEmpty {
                    additionalHeaders.append(ResolvedRequestHeader(name: "Cookie", value: cookieHeader))
                }
                assets.append(ResolvedAsset(
                    remoteURL: remote,
                    filename: filename,
                    metadata: assetMetadata(
                        for: remote,
                        asset: asset,
                        title: safeProjectTitle(title),
                        projectID: projectIDFromSourceURL(sourceURL) ?? "",
                        userDisplayName: userDisplayName,
                        username: username,
                        sourceURL: sourceURL,
                        createdAt: createdAt,
                        index: assets.count + 1
                    ),
                    referer: sourceURL.absoluteString,
                    userAgent: userAgent,
                    additionalHeaders: additionalHeaders,
                    alternativeRemoteURLs: alternatives
                ))
                if assets.count >= maximumAssets { break assetLoop }
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let safeTitle = title.sanitizedFilename(maxLength: 120)
        let projectID = projectIDFromSourceURL(sourceURL) ?? ""
        let imageCount = assets.filter { $0.metadata["media_type"] == "image" }.count
        let videoCount = assets.filter { $0.metadata["media_type"] == "video" }.count
        let folderTitle = [userDisplayName, safeTitle]
            .compactMap { $0?.trimmed }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
        return ResolvedDownload(
            title: safeTitle,
            folderName: "ArtStation \(folderTitle.isEmpty ? safeTitle : folderTitle)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "ArtStation",
                "title": safeTitle,
                "series": safeTitle,
                "category": assets.contains(where: { $0.metadata["type"] == "video" }) ? "video" : "image",
                "type": "project",
                "media_type": "project",
                "host": sourceURL.host ?? "",
                "id": projectID,
                "project_id": projectID,
                "gallery_id": projectID,
                "media_count": String(assets.count),
                "image_count": imageCount > 0 ? String(imageCount) : "",
                "video_count": videoCount > 0 ? String(videoCount) : "",
                "created_at": createdAt ?? "",
                "date": createdAt ?? "",
                "artist": userDisplayName ?? "",
                "author": userDisplayName ?? "",
                "creator": userDisplayName ?? "",
                "uploader": userDisplayName ?? "",
                "channel": userDisplayName ?? "",
                "user": username ?? userDisplayName ?? "",
                "username": username ?? userDisplayName ?? "",
                "uploader_id": username ?? "",
                "channel_id": username ?? "",
                "url": sourceURL.absoluteString,
                "source_url": sourceURL.absoluteString,
                "page_url": sourceURL.absoluteString,
                "original_contract": "artstation-4.2-project"
            ])
        )
    }

    private func resolveProfile(
        _ request: ArtStationRequest,
        username: String,
        section: String?,
        session: ArtStationRequestSession,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        let quickURL = try Self.profileQuickURL(username: username, request: request)
        let quickData = try await session.data(from: quickURL, referer: request.sourceURL.absoluteString)
        guard let quick = try JSONSerialization.jsonObject(with: quickData) as? [String: Any],
              let userID = Self.stringValue(quick["id"]), !userID.trimmed.isEmpty else {
            throw NativeDownloadError.invalidGalleryData
        }

        let canonicalUsername = Self.stringValue(quick["username"]) ?? username
        let displayName = Self.userName(from: quick) ?? canonicalUsername
        let discovery = try await discoverProjects(
            request,
            username: username,
            userID: userID,
            session: session
        )
        guard !discovery.entries.isEmpty else { throw NativeDownloadError.noFiles }

        let maximumAssets = max(1, assetLimit ?? Int.max)
        var assets: [ResolvedAsset] = []
        var resolvedProjects = 0
        var firstProjectError: Error?
        var usedNames = Set<String>()

        for (projectIndex, entry) in discovery.entries.enumerated() {
            try Task.checkCancellation()
            let remaining = maximumAssets - assets.count
            guard remaining > 0 else { break }
            do {
                let projectURL = Self.projectURL(id: entry.projectID, canonicalHost: request.canonicalHost)
                let apiURL = try Self.projectAPIURL(id: entry.projectID, request: request)
                let data = try await session.data(from: apiURL, referer: projectURL.absoluteString)
                let project = try Self.resolvedDownload(
                    from: data,
                    baseURL: apiURL,
                    sourceURL: projectURL,
                    userAgent: headers.userAgent,
                    cookieHeader: session.cookieHeader,
                    assetLimit: remaining
                )
                var projectName = entry.projectID
                while usedNames.contains(projectName.lowercased()) { projectName += "_" }
                usedNames.insert(projectName.lowercased())

                for (projectAssetIndex, originalAsset) in project.assets.enumerated() {
                    var asset = originalAsset
                    let globalIndex = assets.count + 1
                    asset.filename = String(
                        format: "%04d-%@-%@",
                        globalIndex,
                        projectName,
                        originalAsset.filename
                    ).sanitizedFilename(maxLength: 180)
                    asset.metadata["collection_index"] = String(projectIndex + 1)
                    asset.metadata["collection_asset_index"] = String(projectAssetIndex + 1)
                    asset.metadata["collection_item_id"] = entry.listingID
                    asset.metadata["collection_url"] = request.sourceURL.absoluteString
                    asset.metadata["profile_id"] = canonicalUsername
                    if asset.metadata["created_at"] == nil, let createdAt = entry.createdAt {
                        asset.metadata["created_at"] = createdAt
                        asset.metadata["date"] = createdAt
                    }
                    assets.append(asset)
                }
                resolvedProjects += 1
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                if firstProjectError == nil { firstProjectError = error }
            }
        }

        guard !assets.isEmpty else {
            if let firstProjectError { throw firstProjectError }
            throw NativeDownloadError.noFiles
        }

        let identifier = section == nil ? canonicalUsername : "\(canonicalUsername)/\(section!)"
        let title = "\(displayName) (artstation_\(identifier))".sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: DownloadMetadata.clean([
                "site": "ArtStation",
                "title": title,
                "series": displayName,
                "category": "image",
                "type": "profile",
                "media_type": "collection",
                "collection_kind": section ?? "profile",
                "collection_id": identifier,
                "profile_id": canonicalUsername,
                "user_id": userID,
                "user": canonicalUsername,
                "username": canonicalUsername,
                "artist": displayName,
                "author": displayName,
                "creator": displayName,
                "uploader": displayName,
                "host": request.sourceURL.host ?? "",
                "listed_project_count": String(discovery.entries.count),
                "resolved_project_count": String(resolvedProjects),
                "resolved_api_page_count": String(discovery.populatedPages),
                "media_count": String(assets.count),
                "url": request.sourceURL.absoluteString,
                "source_url": request.sourceURL.absoluteString,
                "page_url": request.sourceURL.absoluteString,
                "original_contract": "artstation-4.2-profile"
            ])
        )
    }

    private func discoverProjects(
        _ request: ArtStationRequest,
        username: String,
        userID: String,
        session: ArtStationRequestSession
    ) async throws -> (entries: [ArtStationProjectEntry], populatedPages: Int) {
        var entries: [ArtStationProjectEntry] = []
        var seen = Set<String>()
        var populatedPages = 0

        for page in 1...999 {
            try Task.checkCancellation()
            let url = try Self.profileProjectsURL(username: username, userID: userID, page: page, request: request)
            let data = try await session.data(from: url, referer: request.sourceURL.absoluteString)
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dictionaries = object["data"] as? [[String: Any]] else {
                throw NativeDownloadError.invalidGalleryData
            }
            guard !dictionaries.isEmpty else { break }
            populatedPages += 1

            var inserted = 0
            for dictionary in dictionaries {
                guard let listingID = Self.stringValue(dictionary["id"]),
                      let projectID = Self.projectID(fromListing: dictionary),
                      seen.insert(listingID).inserted else {
                    continue
                }
                entries.append(ArtStationProjectEntry(
                    listingID: listingID,
                    projectID: projectID,
                    createdAt: Self.stringValue(dictionary["created_at"]),
                    discoveryIndex: entries.count
                ))
                inserted += 1
            }
            if inserted == 0 { break }
        }

        entries.sort { lhs, rhs in
            if let left = Int64(lhs.listingID), let right = Int64(rhs.listingID), left != right {
                return left > right
            }
            if lhs.listingID != rhs.listingID {
                return lhs.listingID.localizedStandardCompare(rhs.listingID) == .orderedDescending
            }
            return lhs.discoveryIndex < rhs.discoveryIndex
        }
        return (entries, populatedPages)
    }

    private static func projectID(fromListing dictionary: [String: Any]) -> String? {
        for key in ["permalink", "url", "project_url"] {
            guard let value = stringValue(dictionary[key]), let url = URL(string: value),
                  let id = projectIDFromSourceURL(url) else { continue }
            return id
        }
        return stringValue(dictionary["hash_id"]).flatMap(cleanProjectID)
            ?? stringValue(dictionary["slug"]).flatMap(cleanProjectID)
    }

    private static func projectAPIURL(id: String, request: ArtStationRequest) throws -> URL {
        try siteURL(path: "/projects/\(id).json", request: request)
    }

    private static func siteURL(path: String, request: ArtStationRequest) throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = request.canonicalHost
        components.path = path
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL(request.sourceURL.absoluteString)
        }
        return url
    }

    private static func projectURL(id: String, canonicalHost: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost
        components.path = "/artwork/\(id)"
        return components.url!
    }

    private static func profileURL(username: String, section: String?, canonicalHost: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = canonicalHost
        components.path = "/\(username)" + (section.map { "/\($0)" } ?? "")
        return components.url!
    }

    private static func canonicalHostInfo(for host: String) -> (canonicalHost: String, profileSubdomain: String?)? {
        if host == "artstation.com" || host == "www.artstation.com" {
            return ("www.artstation.com", nil)
        }
        if host == "artstation.test" || host == "www.artstation.test" {
            return ("www.artstation.test", nil)
        }
        for (suffix, canonicalHost) in [
            (".artstation.com", "www.artstation.com"),
            (".artstation.test", "www.artstation.test")
        ] where host.hasSuffix(suffix) {
            let value = String(host.dropLast(suffix.count)).trimmingCharacters(in: CharacterSet(charactersIn: "."))
            guard !value.isEmpty, !value.contains(".") else { return nil }
            return (canonicalHost, value)
        }
        return nil
    }

    private static func validUsername(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9][A-Za-z0-9_-]*$"#, options: .regularExpression) != nil
    }

    private static func cleanProjectID(_ value: String) -> String? {
        let cleaned = (value as NSString).deletingPathExtension.trimmed
        guard !cleaned.isEmpty,
              cleaned.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return nil
        }
        return cleaned
    }

    private static func assetDictionaries(from object: [String: Any]) -> [[String: Any]] {
        if let assets = object["assets"] as? [[String: Any]] { return assets }
        if let assets = object["images"] as? [[String: Any]] { return assets }
        return []
    }

    private static func mediaCandidates(from asset: [String: Any]) -> [String] {
        let keys = [
            "image_url", "large_image_url", "original_url", "file_url",
            "source_url", "video_url", "stream_url", "cover_url"
        ]
        var candidates = keys.compactMap { stringValue(asset[$0]) }
        if let images = asset["images"] as? [[String: Any]] {
            for image in images { candidates.append(contentsOf: keys.compactMap { stringValue(image[$0]) }) }
        }
        if let image = asset["image"] as? [String: Any] {
            candidates.append(contentsOf: keys.compactMap { stringValue(image[$0]) })
        }
        return candidates.filter { !$0.trimmed.isEmpty }
    }

    private static func preferredImageURL(_ url: URL) -> URL {
        guard url.absoluteString.contains("/large/"),
              let preferred = URL(string: url.absoluteString.replacingOccurrences(of: "/large/", with: "/4k/")) else {
            return url
        }
        return preferred
    }

    private static func fallbackFilename(for url: URL, index: Int, asset: [String: Any]) -> String {
        let last = url.lastPathComponent.removingPercentEncoding ?? url.lastPathComponent
        if !last.trimmed.isEmpty, last.contains(".") { return last }
        let assetType = stringValue(asset["asset_type"])?.lowercased() ?? ""
        let ext = assetType.contains("video") ? "mp4" : "jpg"
        return "asset-\(index).\(ext)"
    }

    private static func assetMetadata(
        for url: URL,
        asset: [String: Any],
        title: String,
        projectID: String,
        userDisplayName: String?,
        username: String?,
        sourceURL: URL,
        createdAt: String?,
        index: Int
    ) -> [String: String] {
        let type = mediaType(for: url, asset: asset)
        let format = mediaFormat(for: url)
        let assetID = stringValue(asset["id"]) ?? stringValue(asset["asset_id"]) ?? "\(projectID)-\(index)"
        return DownloadMetadata.clean([
            "site": "ArtStation",
            "title": title,
            "series": title,
            "type": type,
            "media_type": type,
            "category": type == "video" ? "video" : "image",
            "asset_type": stringValue(asset["asset_type"]) ?? "",
            "id": projectID,
            "project_id": projectID,
            "gallery_id": projectID,
            "asset_id": assetID,
            "media_id": assetID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "created_at": createdAt ?? "",
            "date": createdAt ?? "",
            "artist": userDisplayName ?? "",
            "author": userDisplayName ?? "",
            "creator": userDisplayName ?? "",
            "uploader": userDisplayName ?? "",
            "user": username ?? userDisplayName ?? "",
            "username": username ?? userDisplayName ?? "",
            "image_url": type == "image" ? url.absoluteString : "",
            "video_url": type == "video" ? url.absoluteString : "",
            "media_url": url.absoluteString,
            "source_url": url.absoluteString,
            "page_url": sourceURL.absoluteString
        ])
    }

    private static func mediaType(for url: URL, asset: [String: Any]) -> String {
        let format = mediaFormat(for: url)
        if ["mp4", "webm", "mov", "m4v", "m3u8"].contains(format) { return "video" }
        if ["jpg", "jpeg", "png", "webp", "gif"].contains(format) { return "image" }
        let assetType = stringValue(asset["asset_type"])?.lowercased() ?? ""
        return assetType.contains("video") ? "video" : "image"
    }

    private static func mediaFormat(for url: URL) -> String {
        let pathExtension = url.pathExtension.lowercased()
        if !pathExtension.isEmpty { return pathExtension }
        let lower = url.absoluteString.lowercased()
        for value in ["jpg", "jpeg", "png", "webp", "gif", "mp4", "webm", "mov", "m4v", "m3u8"] where lower.contains(".\(value)") {
            return value
        }
        return ""
    }

    private static func projectIDFromSourceURL(_ url: URL) -> String? {
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, ["artwork", "projects"].contains(parts[0].lowercased()) else { return nil }
        return cleanProjectID(parts[1])
    }

    private static func safeProjectTitle(_ title: String) -> String {
        title.sanitizedFilename(maxLength: 120)
    }

    private static func userName(from user: [String: Any]?) -> String? {
        guard let user else { return nil }
        return stringValue(user["full_name"]) ?? stringValue(user["username"]) ?? stringValue(user["name"])
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let trimmed = raw.trimmed
        if trimmed.hasPrefix("//") { return URL(string: "\(baseURL.scheme ?? "https"):\(trimmed)") }
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteURL
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let int = value as? Int { return String(int) }
        if let number = value as? NSNumber { return number.stringValue }
        return nil
    }
}

private struct ArtStationProjectEntry {
    var listingID: String
    var projectID: String
    var createdAt: String?
    var discoveryIndex: Int
}

private final class ArtStationRequestSession {
    private let sourceURL: URL
    private let headers: HTTPRequestOptions
    private var attemptedBrowserBootstrap = false
    private(set) var cookieHeader: String?

    init(sourceURL: URL, headers: HTTPRequestOptions) {
        self.sourceURL = sourceURL
        self.headers = headers
    }

    func data(from url: URL, referer: String) async throws -> Data {
        let first = try await request(from: url, referer: referer, acceptsForbidden: true)
        guard first.response.statusCode == 403 else { return first.data }
        guard !attemptedBrowserBootstrap else {
            throw NativeDownloadError.httpStatus(first.response.statusCode, url)
        }
        attemptedBrowserBootstrap = true

        do {
            try await bootstrapBrowserCookies()
        } catch {
            throw NativeDownloadError.httpStatus(first.response.statusCode, url)
        }
        return try await request(from: url, referer: referer, acceptsForbidden: false).data
    }

    private func request(
        from url: URL,
        referer: String,
        acceptsForbidden: Bool
    ) async throws -> (data: Data, response: HTTPURLResponse) {
        var additionalHeaders = ["Accept": "application/json, text/plain, */*"]
        if let cookieHeader, !cookieHeader.trimmed.isEmpty {
            additionalHeaders["Cookie"] = cookieHeader
        }
        return try await HTTPClient.shared.dataResponse(
            from: url,
            referer: referer,
            userAgent: headers.userAgent,
            additionalHeaders: additionalHeaders,
            acceptedStatusCodes: acceptsForbidden ? [403] : []
        )
    }

    private func bootstrapBrowserCookies() async throws {
        var renderHeaders = [
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Referer": sourceURL.absoluteString
        ]
        if let userAgent = headers.userAgent, !userAgent.trimmed.isEmpty {
            renderHeaders["User-Agent"] = userAgent
        }
        let existing = await CookieStore.shared.cookieHeader(for: sourceURL)
        if let existing, !existing.trimmed.isEmpty {
            renderHeaders["Cookie"] = existing
        }

        let page = try await PythonWebRendererService.shared.renderPage(
            url: sourceURL,
            headers: renderHeaders,
            timeout: 90,
            delay: 10,
            checkBody: true
        )
        let domain = sourceURL.host?.hasSuffix(".test") == true ? ".artstation.test" : ".artstation.com"
        let cookies = page.cookies.compactMap { name, value in
            HTTPCookie(properties: [
                .domain: domain,
                .path: "/",
                .name: name,
                .value: value,
                .secure: "TRUE"
            ])
        }
        if !cookies.isEmpty {
            _ = await CookieStore.shared.importHTTPCookies(cookies)
        }

        let rendered = page.cookies
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
            .map { "\($0.key)=\($0.value)" }
            .joined(separator: "; ")
        cookieHeader = Self.mergedCookieHeader(existing, rendered)
    }

    private static func mergedCookieHeader(_ first: String?, _ second: String?) -> String? {
        var values: [String: String] = [:]
        for header in [first, second] {
            for field in (header ?? "").split(separator: ";") {
                let pair = field.split(separator: "=", maxSplits: 1).map { String($0).trimmed }
                if pair.count == 2, !pair[0].isEmpty { values[pair[0]] = pair[1] }
            }
        }
        guard !values.isEmpty else { return nil }
        return values.keys.sorted().map { "\($0)=\(values[$0]!)" }.joined(separator: "; ")
    }
}
