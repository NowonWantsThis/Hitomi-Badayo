import Foundation

enum FediverseService {
    case mastodon
    case misskey
}

struct FediverseMediaAsset {
    var remoteURL: URL
    var filename: String
    var referer: String
    var metadata: [String: String] = [:]
}

final class FediverseResolver {
    func canResolve(_ url: URL) -> Bool {
        guard let service = Self.service(for: url) else { return false }
        switch service {
        case .mastodon:
            return Self.mastodonStatusID(from: url) != nil ||
                Self.mastodonAccountID(from: url) != nil ||
                Self.mastodonUsername(from: url) != nil
        case .misskey:
            return Self.misskeyNoteID(from: url) != nil || Self.misskeyUsername(from: url) != nil
        }
    }

    func resolve(
        _ url: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        assetLimit: Int? = nil
    ) async throws -> ResolvedDownload {
        guard let service = Self.service(for: url) else {
            throw NativeDownloadError.invalidURL(url.absoluteString)
        }

        switch service {
        case .mastodon:
            if let statusID = Self.mastodonStatusID(from: url) {
                let data = try await HTTPClient.shared.data(
                    from: Self.mastodonStatusAPIURL(statusID: statusID, sourceURL: url),
                    referer: headers.referer ?? url.absoluteString,
                    userAgent: headers.userAgent,
                    additionalHeaders: ["Accept": "application/json, text/plain, */*"]
                )
                let status = try Self.jsonObject(from: data)
                return try Self.mastodonDownload(fromStatuses: [status], sourceURL: url, serviceName: Self.mastodonServiceName(from: url))
            }

            if let accountID = Self.mastodonAccountID(from: url) {
                return try await resolveMastodonAccount(
                    accountID: accountID,
                    sourceURL: url,
                    headers: headers,
                    assetLimit: assetLimit
                )
            }

            guard let username = Self.mastodonUsername(from: url) else {
                throw NativeDownloadError.invalidURL(url.absoluteString)
            }
            return try await resolveMastodonProfile(
                username: username,
                sourceURL: url,
                headers: headers,
                assetLimit: assetLimit
            )

        case .misskey:
            if let noteID = Self.misskeyNoteID(from: url) {
                let data = try await HTTPClient.shared.postJSON(
                    to: Self.misskeyAPIURL(endpoint: "notes/show", sourceURL: url),
                    body: Self.jsonBody(["noteId": noteID]),
                    referer: headers.referer ?? url.absoluteString,
                    userAgent: headers.userAgent
                )
                let note = try Self.jsonObject(from: data)
                return try Self.misskeyDownload(fromNotes: [note], sourceURL: url, serviceName: Self.misskeyServiceName(from: url))
            }

            guard let username = Self.misskeyUsername(from: url) else {
                throw NativeDownloadError.invalidURL(url.absoluteString)
            }
            return try await resolveMisskeyUser(
                username: username,
                sourceURL: url,
                headers: headers,
                assetLimit: assetLimit
            )
        }
    }

    private func resolveMastodonProfile(
        username: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        let apiHeaders = await mastodonAPIHeaders(sourceURL: sourceURL, headers: headers)
        let account = try await mastodonAccount(
            username: username,
            sourceURL: sourceURL,
            headers: headers,
            apiHeaders: apiHeaders
        )
        guard let accountID = Self.stringValue(account["id"]) else {
            throw NativeDownloadError.unsupported("Mastodon account lookup did not return an account id.")
        }

        return try await resolveMastodonAccount(
            accountID: accountID,
            sourceURL: sourceURL,
            headers: headers,
            profileUsername: username,
            assetLimit: assetLimit,
            apiHeaders: apiHeaders
        )
    }

    private func resolveMastodonAccount(
        accountID: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        profileUsername: String? = nil,
        assetLimit: Int?,
        apiHeaders suppliedAPIHeaders: [String: String]? = nil
    ) async throws -> ResolvedDownload {
        let apiHeaders: [String: String]
        if let suppliedAPIHeaders {
            apiHeaders = suppliedAPIHeaders
        } else {
            apiHeaders = await mastodonAPIHeaders(sourceURL: sourceURL, headers: headers)
        }
        let limit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        var statuses: [[String: Any]] = []
        var maxID: String?
        var seenCursors = Set<String>()
        var seenStatusIDs = Set<String>()
        var seenMedia = Set<String>()

        while true {
            try Task.checkCancellation()
            let cursorKey = maxID ?? "<first>"
            guard seenCursors.insert(cursorKey).inserted else { break }
            let pageURL = Self.mastodonAccountStatusesAPIURL(accountID: accountID, sourceURL: sourceURL, maxID: maxID)
            let data = try await HTTPClient.shared.data(
                from: pageURL,
                referer: headers.referer ?? sourceURL.absoluteString,
                userAgent: headers.userAgent,
                additionalHeaders: apiHeaders
            )
            let page = try Self.jsonArray(from: data)
            guard !page.isEmpty else { break }

            var addedAssets = 0
            for status in page {
                guard let statusID = Self.stringValue(status["id"]),
                      seenStatusIDs.insert(statusID).inserted else {
                    continue
                }
                let attachments = status["media_attachments"] as? [[String: Any]] ?? []
                var selectedAttachments: [[String: Any]] = []
                for attachment in attachments {
                    guard let remote = Self.mastodonAttachmentURL(attachment, sourceURL: sourceURL) else { continue }
                    let normalized = URLIdentity.normalize(remote.absoluteString)
                    guard seenMedia.insert(normalized).inserted else { continue }
                    selectedAttachments.append(attachment)
                    addedAssets += 1
                    if let limit, seenMedia.count >= limit { break }
                }
                if !selectedAttachments.isEmpty {
                    var selectedStatus = status
                    selectedStatus["media_attachments"] = selectedAttachments
                    statuses.append(selectedStatus)
                }
                if let limit, seenMedia.count >= limit { break }
            }

            if let limit, seenMedia.count >= limit { break }
            guard addedAssets > 0,
                  let minimumID = page.compactMap({ Self.stringValue($0["id"]).flatMap(UInt64.init) }).min(),
                  minimumID > 0 else {
                break
            }
            maxID = String(minimumID - 1)
        }

        return try Self.mastodonDownload(
            fromStatuses: statuses,
            sourceURL: sourceURL,
            serviceName: Self.mastodonServiceName(from: sourceURL),
            profileUsername: profileUsername ?? accountID
        )
    }

    private func resolveMisskeyUser(
        username: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        assetLimit: Int?
    ) async throws -> ResolvedDownload {
        let lookupData = try await HTTPClient.shared.postJSON(
            to: Self.misskeyAPIURL(endpoint: "users/show", sourceURL: sourceURL),
            body: Self.misskeyUserLookupBody(username),
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent
        )
        let user = try Self.jsonObject(from: lookupData)
        guard let userID = Self.stringValue(user["id"]) else {
            throw NativeDownloadError.unsupported("Misskey user lookup did not return a user id.")
        }

        let limit = assetLimit.flatMap { $0 > 0 ? $0 : nil }
        var notes: [[String: Any]] = []
        var untilID: String?
        var seenCursors = Set<String>()
        var seenNoteIDs = Set<String>()
        var seenMedia = Set<String>()

        while true {
            try Task.checkCancellation()
            let cursorKey = untilID ?? "<first>"
            guard seenCursors.insert(cursorKey).inserted else { break }
            var body: [String: Any] = [
                "userId": userID,
                "limit": 30
            ]
            if let untilID {
                body["untilId"] = untilID
            }

            let data = try await HTTPClient.shared.postJSON(
                to: Self.misskeyAPIURL(endpoint: "users/notes", sourceURL: sourceURL),
                body: Self.jsonBody(body),
                referer: headers.referer ?? sourceURL.absoluteString,
                userAgent: headers.userAgent
            )
            let page = try Self.jsonArray(from: data)
            guard !page.isEmpty else { break }

            var nextUntilID: String?
            for note in page {
                guard let noteID = Self.stringValue(note["id"]) else { continue }
                nextUntilID = noteID
                guard seenNoteIDs.insert(noteID).inserted else { continue }
                let files = note["files"] as? [[String: Any]] ?? []
                var selectedFiles: [[String: Any]] = []
                for file in files {
                    guard let remote = Self.misskeyFileURL(file, sourceURL: sourceURL) else { continue }
                    let normalized = URLIdentity.normalize(remote.absoluteString)
                    guard seenMedia.insert(normalized).inserted else { continue }
                    selectedFiles.append(file)
                    if let limit, seenMedia.count >= limit { break }
                }
                if !selectedFiles.isEmpty {
                    var selectedNote = note
                    selectedNote["files"] = selectedFiles
                    notes.append(selectedNote)
                }
                if let limit, seenMedia.count >= limit { break }
            }

            if let limit, seenMedia.count >= limit { break }
            guard let nextUntilID, nextUntilID != untilID else { break }
            untilID = nextUntilID
        }

        return try Self.misskeyDownload(
            fromNotes: notes,
            sourceURL: sourceURL,
            serviceName: Self.misskeyServiceName(from: sourceURL),
            profileUsername: username
        )
    }

    private func mastodonAPIHeaders(
        sourceURL: URL,
        headers: HTTPRequestOptions
    ) async -> [String: String] {
        var result = ["Accept": "application/json, text/plain, */*"]
        guard let rootURL = Self.mastodonRootURL(sourceURL: sourceURL),
              let html = try? await HTTPClient.shared.string(
                from: rootURL,
                referer: headers.referer,
                userAgent: headers.userAgent
              ),
              let token = Self.mastodonAccessToken(fromHTML: html) else {
            return result
        }
        result["Authorization"] = "Bearer \(token)"
        return result
    }

    private func mastodonAccount(
        username: String,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        apiHeaders: [String: String]
    ) async throws -> [String: Any] {
        if let data = try? await HTTPClient.shared.data(
            from: Self.mastodonSearchAPIURL(username: username, sourceURL: sourceURL),
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: apiHeaders
        ),
           let result = try? Self.jsonObject(from: data),
           let accounts = result["accounts"] as? [[String: Any]],
           let account = Self.matchingMastodonAccount(accounts, username: username) {
            return account
        }

        let lookupData = try await HTTPClient.shared.data(
            from: Self.mastodonLookupAPIURL(username: username, sourceURL: sourceURL),
            referer: headers.referer ?? sourceURL.absoluteString,
            userAgent: headers.userAgent,
            additionalHeaders: apiHeaders
        )
        return try Self.jsonObject(from: lookupData)
    }

    static func service(for url: URL) -> FediverseService? {
        guard let host = url.host?.lowercased(),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        if isMastodonHost(host) {
            return .mastodon
        }
        if isMisskeyHost(host) {
            return .misskey
        }
        return nil
    }

    static func mastodonStatusID(from url: URL) -> String? {
        let parts = pathParts(from: url)

        for marker in ["statuses", "status"] {
            guard let index = parts.firstIndex(where: { $0.lowercased() == marker }),
                  index + 1 < parts.count,
                  isNumericID(parts[index + 1]) else {
                continue
            }
            return parts[index + 1]
        }

        if parts.count >= 3,
           parts[0].lowercased() == "web",
           parts[1].lowercased() == "statuses",
           isNumericID(parts[2]) {
            return parts[2]
        }

        if parts.count >= 2,
           parts[0].hasPrefix("@"),
           isNumericID(parts[1]) {
            return parts[1]
        }

        return nil
    }

    static func mastodonUsername(from url: URL) -> String? {
        guard mastodonStatusID(from: url) == nil else { return nil }
        let parts = pathParts(from: url)
        guard let first = parts.first else { return nil }
        if first.hasPrefix("@") {
            return cleanUsername(String(first.dropFirst()))
        }
        if first.lowercased() == "users", parts.count >= 2 {
            return cleanUsername(parts[1])
        }
        if parts.count == 1, let username = rootMastodonUsername(first) {
            return username
        }
        if parts.count == 2,
           parts[1].lowercased() == "media",
           let username = rootMastodonUsername(first) {
            return username
        }
        return nil
    }

    static func mastodonAccountID(from url: URL) -> String? {
        guard mastodonStatusID(from: url) == nil else { return nil }
        let parts = pathParts(from: url)
        guard parts.count >= 3,
              parts[0].lowercased() == "web",
              parts[1].lowercased() == "accounts",
              isNumericID(parts[2]) else {
            return nil
        }
        if parts.count == 3 {
            return parts[2]
        }
        guard parts.count == 4,
              parts[3].lowercased() == "media" else {
            return nil
        }
        return parts[2]
    }

    static func canonicalMastodonProfileURL(username rawUsername: String, sourceURL: URL? = nil) -> URL? {
        let username = cleanUsername(rawUsername)
        guard isValidProfileUsername(username) else { return nil }
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        components.host = sourceURL?.host ?? "mastodon.social"
        components.path = "/@\(username)"
        return components.url
    }

    static func canonicalMisskeyProfileURL(username rawUsername: String, sourceURL: URL? = nil) -> URL? {
        let username = cleanUsername(rawUsername)
        guard isValidProfileUsername(username) else { return nil }
        var components = URLComponents()
        components.scheme = sourceURL?.scheme ?? "https"
        components.host = sourceURL?.host ?? "misskey.io"
        components.path = "/@\(username)"
        return components.url
    }

    static func canonicalURL(for url: URL) -> URL? {
        guard let service = service(for: url),
              let host = url.host?.lowercased() else {
            return nil
        }

        var components = URLComponents()
        components.scheme = url.scheme ?? "https"
        components.host = host

        switch service {
        case .mastodon:
            if let statusID = mastodonStatusID(from: url) {
                components.path = "/web/statuses/\(statusID)"
                return components.url
            }
            if let accountID = mastodonAccountID(from: url) {
                components.path = "/web/accounts/\(accountID)"
                return components.url
            }
            guard let username = mastodonUsername(from: url),
                  isValidProfileUsername(username) else {
                return nil
            }
            components.path = "/@\(username)"
            return components.url

        case .misskey:
            if let noteID = misskeyNoteID(from: url) {
                components.path = "/notes/\(noteID)"
                return components.url
            }
            guard let username = misskeyUsername(from: url),
                  isValidProfileUsername(username) else {
                return nil
            }
            components.path = "/@\(username)"
            return components.url
        }
    }

    static func mastodonStatusAPIURL(statusID: String, sourceURL: URL) -> URL {
        apiURL(path: "/api/v1/statuses/\(statusID)", sourceURL: sourceURL)
    }

    static func mastodonLookupAPIURL(username: String, sourceURL: URL) -> URL {
        var components = apiComponents(path: "/api/v1/accounts/lookup", sourceURL: sourceURL)
        components.queryItems = [URLQueryItem(name: "acct", value: cleanUsername(username))]
        return components.url!
    }

    static func mastodonSearchAPIURL(username: String, sourceURL: URL) -> URL {
        var components = apiComponents(path: "/api/v2/search", sourceURL: sourceURL)
        components.queryItems = [
            URLQueryItem(name: "q", value: mastodonSearchQuery(username: username, sourceURL: sourceURL)),
            URLQueryItem(name: "resolve", value: "true"),
            URLQueryItem(name: "limit", value: "5")
        ]
        return components.url!
    }

    static func mastodonSearchQuery(username: String, sourceURL: URL) -> String {
        let cleaned = cleanUsername(username)
        let pieces = cleaned.split(separator: "@", maxSplits: 1).map(String.init)
        let localName = pieces.first ?? cleaned
        var accountHost = pieces.count == 2 ? pieces[1] : (sourceURL.host?.lowercased() ?? "")
        let sourceHost = sourceURL.host?.lowercased() ?? ""
        if sourceHost == "baraag.net" || sourceHost == "baraag.test",
           accountHost != sourceHost {
            accountHost = accountHost.split(separator: ".").first.map(String.init) ?? accountHost
        }
        return accountHost.isEmpty ? "@\(localName)" : "@\(localName)@\(accountHost)"
    }

    static func mastodonRootURL(sourceURL: URL) -> URL? {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host
        components.path = "/"
        return components.url
    }

    static func mastodonAccessToken(fromHTML html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"['\"]access_token['\"]\s*:\s*['\"]([^'\"]+)['\"]"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let capture = Range(match.range(at: 1), in: html) else {
            return nil
        }
        let token = String(html[capture]).trimmed
        return token.isEmpty ? nil : token
    }

    static func mastodonAccountStatusesAPIURL(accountID: String, sourceURL: URL, maxID: String? = nil) -> URL {
        var components = apiComponents(path: "/api/v1/accounts/\(accountID)/statuses", sourceURL: sourceURL)
        var items = [
            URLQueryItem(name: "only_media", value: "true"),
            URLQueryItem(name: "exclude_replies", value: "true"),
            URLQueryItem(name: "limit", value: "40")
        ]
        if let maxID, !maxID.isEmpty {
            items.append(URLQueryItem(name: "max_id", value: maxID))
        }
        components.queryItems = items
        return components.url!
    }

    static func mastodonDownload(fromStatuses statuses: [[String: Any]], sourceURL: URL, serviceName: String, profileUsername: String? = nil) throws -> ResolvedDownload {
        var assets: [FediverseMediaAsset] = []
        var seen = Set<String>()
        var firstAccount: [String: Any]?
        var firstText: String?

        for status in statuses {
            if firstAccount == nil {
                firstAccount = status["account"] as? [String: Any]
            }
            if firstText == nil {
                firstText = stringValue(status["content"]).map(cleanTitle)
            }

            let statusID = stringValue(status["id"]) ?? "status"
            let referer = profileUsername == nil
                ? (stringValue(status["url"]) ?? sourceURL.absoluteString)
                : sourceURL.absoluteString
            let createdAt = stringValue(status["created_at"])
            let attachments = status["media_attachments"] as? [[String: Any]] ?? []
            for (position, attachment) in attachments.enumerated() {
                guard let asset = mastodonAsset(
                    from: attachment,
                    statusID: statusID,
                    position: position,
                    createdAt: createdAt,
                    referer: referer,
                    sourceURL: sourceURL
                ) else { continue }
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                assets.append(asset)
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let accountLabel = fediverseAccountLabel(from: firstAccount, fallback: profileUsername)
        let title = fediverseTitle(serviceName: serviceName, accountLabel: accountLabel, text: firstText, fallbackID: profileUsername ?? stringValue(statuses.first?["id"]) ?? "feed")
        return ResolvedDownload(
            title: title.sanitizedFilename(maxLength: 120),
            folderName: "\(serviceName) \(title)".sanitizedFilename(maxLength: 120),
            assets: assets.map { ResolvedAsset(remoteURL: $0.remoteURL, filename: $0.filename, metadata: $0.metadata, referer: $0.referer) },
            metadata: mastodonMetadata(
                account: firstAccount,
                fallback: profileUsername,
                serviceName: serviceName,
                sourceURL: sourceURL,
                assets: assets,
                statusID: stringValue(statuses.first?["id"]),
                postCount: statuses.count
            )
        )
    }

    static func misskeyNoteID(from url: URL) -> String? {
        let parts = pathParts(from: url)
        guard let index = parts.firstIndex(where: { $0.lowercased() == "notes" }),
              index + 1 < parts.count else {
            return nil
        }
        let noteID = parts[index + 1]
        return noteID.isEmpty ? nil : noteID
    }

    static func misskeyUsername(from url: URL) -> String? {
        guard misskeyNoteID(from: url) == nil else { return nil }
        let parts = pathParts(from: url)
        guard let first = parts.first else {
            return nil
        }
        if first.hasPrefix("@") {
            return cleanUsername(String(first.dropFirst()))
        }
        if parts.count == 1, let username = rootMisskeyUsername(first) {
            return username
        }
        return nil
    }

    static func misskeyAPIURL(endpoint: String, sourceURL: URL) -> URL {
        apiURL(path: "/api/\(endpoint)", sourceURL: sourceURL)
    }

    static func misskeyUserLookupBody(_ username: String) -> Data {
        let parts = splitMisskeyUsername(username)
        var body: [String: Any] = ["username": parts.username]
        if let host = parts.host {
            body["host"] = host
        }
        return jsonBody(body)
    }

    static func misskeyDownload(fromNotes notes: [[String: Any]], sourceURL: URL, serviceName: String, profileUsername: String? = nil) throws -> ResolvedDownload {
        var assets: [FediverseMediaAsset] = []
        var seen = Set<String>()
        var firstUser: [String: Any]?
        var firstText: String?

        for note in notes {
            if firstUser == nil {
                firstUser = note["user"] as? [String: Any]
            }
            if firstText == nil {
                firstText = (stringValue(note["cw"]) ?? stringValue(note["text"])).map(cleanTitle)
            }

            let noteID = stringValue(note["id"]) ?? "note"
            let referer = misskeyNoteReferer(note: note, sourceURL: sourceURL)
            let files = note["files"] as? [[String: Any]] ?? []
            for file in files {
                guard let asset = misskeyAsset(from: file, noteID: noteID, index: assets.count + 1, referer: referer, sourceURL: sourceURL) else { continue }
                let normalized = URLIdentity.normalize(asset.remoteURL.absoluteString)
                guard !seen.contains(normalized) else { continue }
                seen.insert(normalized)
                assets.append(asset)
            }
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let accountLabel = misskeyAccountLabel(from: firstUser, fallback: profileUsername)
        let title = fediverseTitle(serviceName: serviceName, accountLabel: accountLabel, text: firstText, fallbackID: profileUsername ?? stringValue(notes.first?["id"]) ?? "feed")
        return ResolvedDownload(
            title: title.sanitizedFilename(maxLength: 120),
            folderName: "\(serviceName) \(title)".sanitizedFilename(maxLength: 120),
            assets: assets.map { ResolvedAsset(remoteURL: $0.remoteURL, filename: $0.filename, metadata: $0.metadata, referer: $0.referer) },
            metadata: misskeyMetadata(
                user: firstUser,
                fallback: profileUsername,
                serviceName: serviceName,
                sourceURL: sourceURL,
                assets: assets,
                noteID: stringValue(notes.first?["id"]),
                noteCount: notes.count
            )
        )
    }

    static func jsonBody(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])) ?? Data("{}".utf8)
    }

    private static func mastodonAsset(
        from attachment: [String: Any],
        statusID: String,
        position: Int,
        createdAt: String?,
        referer: String,
        sourceURL: URL
    ) -> FediverseMediaAsset? {
        guard let remote = mastodonAttachmentURL(attachment, sourceURL: sourceURL) else { return nil }
        let type = stringValue(attachment["type"])?.lowercased()
        let ext = extensionForURL(remote, fallbackType: type)
        let mediaType = fediverseMediaType(rawType: type, url: remote)
        let attachmentID = stringValue(attachment["id"]) ?? "\(statusID)-\(position)"
        let datePrefix = originalMastodonDate(createdAt).map { "[\($0)] " } ?? ""
        return FediverseMediaAsset(
            remoteURL: remote,
            filename: "\(datePrefix)\(statusID)_p\(position).\(ext)".sanitizedFilename(maxLength: 180),
            referer: referer,
            metadata: mastodonAssetMetadata(
                attachment: attachment,
                mediaType: mediaType,
                statusID: statusID,
                attachmentID: attachmentID,
                remote: remote,
                referer: referer,
                sourceURL: sourceURL,
                index: position + 1
            )
        )
    }

    private static func misskeyAsset(from file: [String: Any], noteID: String, index: Int, referer: String, sourceURL: URL) -> FediverseMediaAsset? {
        guard let remote = misskeyFileURL(file, sourceURL: sourceURL) else { return nil }

        let type = stringValue(file["type"])?.lowercased()
        let ext = extensionForURL(remote, fallbackType: type)
        let originalName = stringValue(file["name"])?.sanitizedFilename(maxLength: 120)
        let suffix: String
        if let originalName, !originalName.isEmpty, (originalName as NSString).pathExtension.isEmpty == false {
            suffix = originalName
        } else {
            suffix = "p\(String(format: "%04d", index)).\(ext)"
        }

        let mediaType = fediverseMediaType(rawType: type, url: remote)
        let fileID = stringValue(file["id"]) ?? "\(noteID)-\(index)"
        return FediverseMediaAsset(
            remoteURL: remote,
            filename: "\(noteID)_\(suffix)".sanitizedFilename(maxLength: 180),
            referer: referer,
            metadata: misskeyAssetMetadata(
                file: file,
                mediaType: mediaType,
                noteID: noteID,
                fileID: fileID,
                remote: remote,
                referer: referer,
                sourceURL: sourceURL,
                index: index
            )
        )
    }

    private static func mastodonAttachmentURL(_ attachment: [String: Any], sourceURL: URL) -> URL? {
        let raw = stringValue(attachment["url"]) ??
            stringValue(attachment["remote_url"]) ??
            stringValue(attachment["preview_url"])
        guard let raw else { return nil }
        return absoluteURL(raw, baseURL: sourceURL)
    }

    private static func misskeyFileURL(_ file: [String: Any], sourceURL: URL) -> URL? {
        let raw = stringValue(file["url"]) ??
            stringValue(file["thumbnailUrl"]) ??
            stringValue(file["thumbnailUrl".lowercased()])
        guard let raw else { return nil }
        return absoluteURL(raw, baseURL: sourceURL)
    }

    private static func originalMastodonDate(_ value: String?) -> String? {
        guard let value, value.count >= 10 else { return nil }
        let start = value.index(value.startIndex, offsetBy: 2)
        let end = value.index(value.startIndex, offsetBy: 10)
        let result = String(value[start..<end])
        return result.isEmpty ? nil : result
    }

    private static func matchingMastodonAccount(
        _ accounts: [[String: Any]],
        username: String
    ) -> [String: Any]? {
        let localName = cleanUsername(username).split(separator: "@", maxSplits: 1).first.map(String.init)?.lowercased()
        guard let localName, !localName.isEmpty else { return accounts.first }
        return accounts.first { account in
            let accountName = (stringValue(account["acct"]) ?? stringValue(account["username"]) ?? "")
                .split(separator: "@", maxSplits: 1)
                .first
                .map(String.init)?
                .lowercased()
            return accountName == localName
        }
    }

    private static func misskeyNoteReferer(note: [String: Any], sourceURL: URL) -> String {
        if let url = stringValue(note["url"]) ?? stringValue(note["uri"]) {
            return url
        }
        if let id = stringValue(note["id"]) {
            var components = URLComponents()
            components.scheme = sourceURL.scheme ?? "https"
            components.host = sourceURL.host
            components.path = "/notes/\(id)"
            return components.url?.absoluteString ?? sourceURL.absoluteString
        }
        return sourceURL.absoluteString
    }

    private static func fediverseTitle(serviceName: String, accountLabel: String?, text: String?, fallbackID: String) -> String {
        let cleanAccount = cleanTitle(accountLabel ?? "")
        let cleanText = cleanTitle(text ?? "")
        if !cleanAccount.isEmpty, !cleanText.isEmpty {
            return "@\(cleanAccount) - \(cleanText)"
        }
        if !cleanAccount.isEmpty {
            return "@\(cleanAccount) - \(fallbackID)"
        }
        if !cleanText.isEmpty {
            return cleanText
        }
        return "\(serviceName) \(fallbackID)"
    }

    private static func fediverseAccountLabel(from account: [String: Any]?, fallback: String?) -> String? {
        guard let account else { return fallback }
        return stringValue(account["acct"]) ??
            stringValue(account["username"]) ??
            stringValue(account["display_name"]) ??
            fallback
    }

    private static func misskeyAccountLabel(from user: [String: Any]?, fallback: String?) -> String? {
        guard let user else { return fallback }
        let username = stringValue(user["username"])
        let host = stringValue(user["host"])
        if let username, let host, !host.isEmpty {
            return "\(username)@\(host)"
        }
        return username ?? stringValue(user["name"]) ?? fallback
    }

    private static func mastodonMetadata(
        account: [String: Any]?,
        fallback: String?,
        serviceName: String = "Mastodon",
        sourceURL: URL? = nil,
        assets: [FediverseMediaAsset] = [],
        statusID: String? = nil,
        postCount: Int = 0
    ) -> [String: String] {
        let username = stringValue(account?["acct"]) ??
            stringValue(account?["username"]) ??
            fallback
        let displayName = stringValue(account?["display_name"]).map(cleanTitle).flatMap { $0.isEmpty ? nil : $0 } ??
            username
        let counts = mediaCounts(for: assets)
        return DownloadMetadata.clean([
            "site": serviceName,
            "type": postCount > 1 ? "profile" : "status",
            "media_type": dominantMediaType(for: counts),
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": counts.image > 0 ? String(counts.image) : "",
            "video_count": counts.video > 0 ? String(counts.video) : "",
            "audio_count": counts.audio > 0 ? String(counts.audio) : "",
            "post_count": postCount > 0 ? String(postCount) : "",
            "id": statusID ?? fallback ?? "",
            "status_id": statusID ?? "",
            "media_id": statusID ?? fallback ?? "",
            "source_url": sourceURL?.absoluteString ?? "",
            "page_url": sourceURL?.absoluteString ?? "",
            "artist": displayName ?? "",
            "author": displayName ?? "",
            "creator": displayName ?? "",
            "user": username ?? displayName ?? "",
            "username": username ?? displayName ?? "",
            "uploader": displayName ?? "",
            "uploader_id": username ?? "",
            "channel": displayName ?? "",
            "channel_id": username ?? ""
        ])
    }

    private static func misskeyMetadata(
        user: [String: Any]?,
        fallback: String?,
        serviceName: String = "Misskey",
        sourceURL: URL? = nil,
        assets: [FediverseMediaAsset] = [],
        noteID: String? = nil,
        noteCount: Int = 0
    ) -> [String: String] {
        let username = misskeyAccountLabel(from: user, fallback: fallback)
        let displayName = stringValue(user?["name"]).map(cleanTitle).flatMap { $0.isEmpty ? nil : $0 } ??
            username
        let counts = mediaCounts(for: assets)
        return DownloadMetadata.clean([
            "site": serviceName,
            "type": noteCount > 1 ? "profile" : "note",
            "media_type": dominantMediaType(for: counts),
            "media_count": assets.isEmpty ? "" : String(assets.count),
            "image_count": counts.image > 0 ? String(counts.image) : "",
            "video_count": counts.video > 0 ? String(counts.video) : "",
            "audio_count": counts.audio > 0 ? String(counts.audio) : "",
            "note_count": noteCount > 0 ? String(noteCount) : "",
            "id": noteID ?? fallback ?? "",
            "note_id": noteID ?? "",
            "media_id": noteID ?? fallback ?? "",
            "source_url": sourceURL?.absoluteString ?? "",
            "page_url": sourceURL?.absoluteString ?? "",
            "artist": displayName ?? "",
            "author": displayName ?? "",
            "creator": displayName ?? "",
            "user": username ?? displayName ?? "",
            "username": username ?? displayName ?? "",
            "uploader": displayName ?? "",
            "uploader_id": username ?? "",
            "channel": displayName ?? "",
            "channel_id": username ?? ""
        ])
    }

    private static func mastodonAssetMetadata(attachment: [String: Any], mediaType: String, statusID: String, attachmentID: String, remote: URL, referer: String, sourceURL: URL, index: Int) -> [String: String] {
        let format = extensionForURL(remote, fallbackType: stringValue(attachment["type"])?.lowercased())
        let width = firstDimension(in: attachment, keys: ["width", "w"])
        let height = firstDimension(in: attachment, keys: ["height", "h"])
        return DownloadMetadata.clean(assetURLMetadata(mediaType: mediaType, url: remote).merging([
            "site": mastodonServiceName(from: sourceURL),
            "type": mediaType,
            "media_type": mediaType,
            "id": statusID,
            "status_id": statusID,
            "attachment_id": attachmentID,
            "media_id": attachmentID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "mime": stringValue(attachment["mime_type"]) ?? stringValue(attachment["type"]) ?? "",
            "width": width,
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "source_url": sourceURL.absoluteString,
            "page_url": referer
        ]) { current, _ in current })
    }

    private static func misskeyAssetMetadata(file: [String: Any], mediaType: String, noteID: String, fileID: String, remote: URL, referer: String, sourceURL: URL, index: Int) -> [String: String] {
        let format = extensionForURL(remote, fallbackType: stringValue(file["type"])?.lowercased())
        let width = firstDimension(in: file, keys: ["width", "w"])
        let height = firstDimension(in: file, keys: ["height", "h"])
        return DownloadMetadata.clean(assetURLMetadata(mediaType: mediaType, url: remote).merging([
            "site": misskeyServiceName(from: sourceURL),
            "type": mediaType,
            "media_type": mediaType,
            "id": noteID,
            "note_id": noteID,
            "file_id": fileID,
            "media_id": fileID,
            "page": String(index),
            "position": String(index),
            "filename": stringValue(file["name"]) ?? "",
            "format": format,
            "media_format": format,
            "mime": stringValue(file["type"]) ?? "",
            "width": width,
            "height": height,
            "resolution": height.isEmpty ? "" : "\(height)p",
            "byte_count": stringValue(file["size"]) ?? "",
            "source_url": sourceURL.absoluteString,
            "page_url": referer
        ]) { current, _ in current })
    }

    private static func assetURLMetadata(mediaType: String, url: URL) -> [String: String] {
        var metadata = ["media_url": url.absoluteString]
        switch mediaType {
        case "video":
            metadata["video_url"] = url.absoluteString
        case "audio":
            metadata["audio_url"] = url.absoluteString
        default:
            metadata["image_url"] = url.absoluteString
        }
        return metadata
    }

    private static func fediverseMediaType(rawType: String?, url: URL) -> String {
        let type = rawType?.lowercased() ?? ""
        let ext = url.pathExtension.lowercased()
        if type.contains("video") || type == "gifv" || ["mp4", "webm", "mov", "m4v"].contains(ext) {
            return "video"
        }
        if type.contains("audio") || ["mp3", "m4a", "aac", "ogg", "opus", "wav"].contains(ext) {
            return "audio"
        }
        return "image"
    }

    private static func mediaCounts(for assets: [FediverseMediaAsset]) -> (image: Int, video: Int, audio: Int) {
        let image = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "image" }.count
        let video = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "video" }.count
        let audio = assets.filter { ($0.metadata["media_type"] ?? $0.metadata["type"]) == "audio" }.count
        return (image, video, audio)
    }

    private static func dominantMediaType(for counts: (image: Int, video: Int, audio: Int)) -> String {
        if counts.video > 0, counts.image == 0, counts.audio == 0 { return "video" }
        if counts.audio > 0, counts.image == 0, counts.video == 0 { return "audio" }
        return "image"
    }

    private static func firstDimension(in object: [String: Any], keys: [String]) -> String {
        let candidates: [[String: Any]?] = [
            object,
            object["meta"] as? [String: Any],
            (object["meta"] as? [String: Any])?["original"] as? [String: Any],
            object["properties"] as? [String: Any]
        ]
        for candidate in candidates.compactMap({ $0 }) {
            for key in keys {
                if let value = stringValue(candidate[key]) {
                    return value
                }
            }
        }
        return ""
    }

    private static func splitMisskeyUsername(_ username: String) -> (username: String, host: String?) {
        let cleaned = cleanUsername(username)
        let parts = cleaned.split(separator: "@", maxSplits: 1).map(String.init)
        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return (parts[0], parts[1])
        }
        return (cleaned, nil)
    }

    private static func mastodonServiceName(from url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host == "pawoo.net" || host.hasSuffix(".pawoo.net") || host == "pawoo.test" || host.hasSuffix(".pawoo.test") {
            return "Pawoo"
        }
        if host == "baraag.net" || host.hasSuffix(".baraag.net") || host == "baraag.test" || host.hasSuffix(".baraag.test") {
            return "Baraag"
        }
        return "Mastodon"
    }

    private static func misskeyServiceName(from url: URL) -> String {
        let host = url.host?.lowercased() ?? ""
        if host.contains("misskey") {
            return "Misskey"
        }
        return "Misskey"
    }

    private static func apiURL(path: String, sourceURL: URL) -> URL {
        apiComponents(path: path, sourceURL: sourceURL).url!
    }

    private static func apiComponents(path: String, sourceURL: URL) -> URLComponents {
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        components.host = sourceURL.host
        components.path = path
        return components
    }

    private static func pathParts(from url: URL) -> [String] {
        url.path.split(separator: "/").map { String($0).removingPercentEncoding ?? String($0) }
    }

    private static func cleanUsername(_ raw: String) -> String {
        raw.trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "@/ "))
            .replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
    }

    private static func rootMastodonUsername(_ raw: String) -> String? {
        let username = cleanUsername(raw)
        guard isValidProfileUsername(username),
              !username.contains("@"),
              !reservedMastodonRootPaths.contains(username.lowercased()) else {
            return nil
        }
        return username
    }

    private static func rootMisskeyUsername(_ raw: String) -> String? {
        let username = cleanUsername(raw)
        guard isValidProfileUsername(username),
              !reservedMisskeyRootPaths.contains(username.lowercased()) else {
            return nil
        }
        return username
    }

    private static func isMastodonHost(_ host: String) -> Bool {
        let known = [
            "mastodon.social",
            "pawoo.net",
            "baraag.net",
            "mastodon.test",
            "pawoo.test",
            "baraag.test"
        ]
        return known.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isMisskeyHost(_ host: String) -> Bool {
        let known = [
            "misskey.io",
            "misskey.test"
        ]
        return known.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    private static func isNumericID(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0 >= "0" && $0 <= "9" }
    }

    private static func isValidProfileUsername(_ text: String) -> Bool {
        !text.isEmpty &&
            text.count <= 120 &&
            text.range(of: #"^[A-Za-z0-9_.@-]+$"#, options: .regularExpression) != nil
    }

    private static let reservedMastodonRootPaths: Set<String> = [
        "about",
        "admin",
        "api",
        "auth",
        "deck",
        "explore",
        "filters",
        "home",
        "interact",
        "media",
        "notifications",
        "oauth",
        "privacy-policy",
        "public",
        "search",
        "settings",
        "share",
        "tags",
        "terms",
        "web"
    ]

    private static let reservedMisskeyRootPaths: Set<String> = [
        "about",
        "admin",
        "announcements",
        "api",
        "auth",
        "channels",
        "clips",
        "explore",
        "gallery",
        "my",
        "notes",
        "oauth",
        "pages",
        "search",
        "settings",
        "share",
        "signin",
        "signup",
        "tags",
        "timeline",
        "users"
    ]

    private static func extensionForURL(_ url: URL, fallbackType: String?) -> String {
        let ext = url.pathExtension.trimmed.lowercased()
        if !ext.isEmpty, ext.count <= 8 {
            return ext
        }
        let type = fallbackType ?? ""
        if type.contains("mp4") || type == "video" || type == "gifv" {
            return "mp4"
        }
        if type.contains("webm") {
            return "webm"
        }
        if type.contains("png") {
            return "png"
        }
        if type.contains("gif") {
            return "gif"
        }
        if type.contains("audio") || type.contains("mpeg") || type.contains("mp3") {
            return "mp3"
        }
        return "jpg"
    }

    private static func absoluteURL(_ raw: String, baseURL: URL) -> URL? {
        let value = raw.trimmed
        if value.hasPrefix("//") {
            return URL(string: "\(baseURL.scheme ?? "https"):\(value)")
        }
        return URL(string: value, relativeTo: baseURL)?.absoluteURL
    }

    private static func cleanTitle(_ raw: String) -> String {
        decodeHTML(stripTags(raw))
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 120)
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

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func jsonArray(from data: Data) throws -> [[String: Any]] {
        guard let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return array
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.isEmpty { return string }
        if let int = value as? Int { return String(int) }
        if let double = value as? Double { return String(Int(double)) }
        return nil
    }
}
