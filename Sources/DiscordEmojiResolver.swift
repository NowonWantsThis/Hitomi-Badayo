// Developed with reference to SaidBySolo's MIT-licensed extractor.
// See LICENSES/saidbysolo-MIT.txt in the source distribution.
import Foundation

enum DiscordEmojiCredential: Equatable {
    case token(String)
    case account(email: String, password: String)
}

struct DiscordEmojiRequest: Equatable {
    var credential: DiscordEmojiCredential
    var guildID: String
}

final class DiscordEmojiResolver {
    func canResolve(_ raw: String) -> Bool {
        Self.request(from: raw) != nil
    }

    func resolve(_ raw: String) async throws -> ResolvedDownload {
        guard let request = Self.request(from: raw) else {
            throw NativeDownloadError.invalidURL(raw)
        }

        let token: String
        switch request.credential {
        case .token(let value):
            token = value
        case .account(let email, let password):
            token = try await login(email: email, password: password)
        }

        let guildResponse = try await getGuild(guildID: request.guildID, token: token)
        guard guildResponse.statusCode == 200 else {
            throw NativeDownloadError.unsupported("Discord token or guild id was rejected. Check the token and whether the account can access this server.")
        }
        return try Self.resolvedDownload(fromGuildData: guildResponse.data, guildID: request.guildID)
    }

    static func request(from raw: String) -> DiscordEmojiRequest? {
        let trimmed = raw.trimmed
        let lower = trimmed.lowercased()
        let prefixes = ["discord-emoji://", "discordemoji://", "discord://", "discord-emoji:", "discordemoji:", "discord:"]
        guard let prefix = prefixes.first(where: { lower.hasPrefix($0) }) else {
            return nil
        }

        let payloadStart = trimmed.index(trimmed.startIndex, offsetBy: prefix.count)
        let payload = String(trimmed[payloadStart...])
        let parts = payload
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).removingPercentEncoding ?? String($0) }
            .map { $0.trimmed }
            .filter { !$0.isEmpty }

        if parts.count == 2,
           isGuildID(parts[1]) {
            return DiscordEmojiRequest(credential: .token(parts[0]), guildID: parts[1])
        }

        if parts.count == 3,
           isGuildID(parts[2]) {
            return DiscordEmojiRequest(credential: .account(email: parts[0], password: parts[1]), guildID: parts[2])
        }

        return nil
    }

    static func sourceURL(for request: DiscordEmojiRequest) -> URL {
        URL(string: "discord://emoji/\(request.guildID)")!
    }

    static func resolvedDownload(fromGuildData data: Data, guildID: String) throws -> ResolvedDownload {
        let object = try jsonObject(from: data)
        let guildName = cleanTitle(stringValue(object["name"]) ?? "Discord Guild \(guildID)")
        let effectiveGuildID = stringValue(object["id"]) ?? guildID
        let guildSourceURL = URL(string: "discord://emoji/\(effectiveGuildID)")!
        let emojiObjects = object["emojis"] as? [[String: Any]] ?? []
        guard !emojiObjects.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        var assets: [ResolvedAsset] = []
        var seen = Set<String>()
        for emoji in emojiObjects {
            guard let id = stringValue(emoji["id"]) else { continue }
            let animated = boolValue(emoji["animated"]) ?? false
            let ext = animated ? "gif" : "png"
            guard let remote = URL(string: "https://cdn.discordapp.com/emojis/\(id).\(ext)?v=1") else { continue }
            let normalized = URLIdentity.normalize(remote.absoluteString)
            guard !seen.contains(normalized) else { continue }
            seen.insert(normalized)

            let name = cleanTitle(stringValue(emoji["name"]) ?? "emoji")
            let index = assets.count + 1
            assets.append(ResolvedAsset(
                remoteURL: remote,
                filename: "\(id).\(ext)".sanitizedFilename(maxLength: 180),
                metadata: emojiMetadata(
                    emojiID: id,
                    emojiName: name,
                    guildName: guildName,
                    guildID: effectiveGuildID,
                    remoteURL: remote,
                    sourceURL: guildSourceURL,
                    index: index,
                    animated: animated
                ),
                referer: nil
            ))
        }

        guard !assets.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let title = "\(guildName)(\(effectiveGuildID))".sanitizedFilename(maxLength: 120)
        return ResolvedDownload(
            title: title,
            folderName: "Discord Emoji \(title)".sanitizedFilename(maxLength: 120),
            assets: assets,
            metadata: discordMetadata(guildName: guildName, guildID: effectiveGuildID, emojiCount: assets.count, sourceURL: guildSourceURL)
        )
    }

    static func discordMetadata(guildName: String, guildID: String, emojiCount: Int, sourceURL: URL? = nil) -> [String: String] {
        DownloadMetadata.clean([
            "artist": guildName,
            "author": guildName,
            "creator": guildName,
            "uploader": guildName,
            "channel": guildName,
            "channel_id": guildID,
            "guild": guildName,
            "guild_id": guildID,
            "series": guildName,
            "category": "emoji",
            "type": "emoji",
            "tag": "emoji",
            "emoji_count": String(emojiCount),
            "media_count": String(emojiCount),
            "image_count": String(emojiCount),
            "site": "Discord",
            "url": sourceURL?.absoluteString ?? "",
            "source_url": sourceURL?.absoluteString ?? "",
            "page_url": sourceURL?.absoluteString ?? ""
        ])
    }

    private static func emojiMetadata(emojiID: String, emojiName: String, guildName: String, guildID: String, remoteURL: URL, sourceURL: URL, index: Int, animated: Bool) -> [String: String] {
        let format = remoteURL.pathExtension.trimmed.isEmpty ? (animated ? "gif" : "png") : remoteURL.pathExtension.lowercased()
        return DownloadMetadata.clean([
            "site": "Discord",
            "artist": guildName,
            "author": guildName,
            "creator": guildName,
            "uploader": guildName,
            "channel": guildName,
            "channel_id": guildID,
            "guild": guildName,
            "guild_id": guildID,
            "category": "emoji",
            "type": "emoji",
            "media_type": "emoji",
            "emoji_id": emojiID,
            "emoji_name": emojiName,
            "media_id": emojiID,
            "page": String(index),
            "position": String(index),
            "format": format,
            "media_format": format,
            "animated": animated ? "true" : "false",
            "image_url": remoteURL.absoluteString,
            "media_url": remoteURL.absoluteString,
            "source_url": remoteURL.absoluteString,
            "page_url": sourceURL.absoluteString
        ])
    }

    private func getGuild(guildID: String, token: String) async throws -> DiscordHTTPResponse {
        let url = URL(string: "https://discordapp.com/api/v6/guilds/\(guildID)")!
        var response = try await request(url: url, method: "GET", headers: ["Authorization": token])
        if response.statusCode == 401 {
            response = try await request(url: url, method: "GET", headers: ["Authorization": "Bot \(token)"])
        }
        return response
    }

    private func login(email: String, password: String) async throws -> String {
        let url = URL(string: "https://discordapp.com/api/v8/auth/login")!
        let body = try JSONSerialization.data(withJSONObject: [
            "email": email,
            "password": password,
            "undelete": false,
            "captcha_key": NSNull(),
            "login_source": NSNull(),
            "gift_code_sku_id": NSNull()
        ])
        let response = try await request(
            url: url,
            method: "POST",
            headers: [
                "Content-Type": "application/json",
                "Accept": "application/json"
            ],
            body: body
        )
        let object = (try? Self.jsonObject(from: response.data)) ?? [:]
        if response.statusCode == 400 {
            if object["captcha_key"] != nil {
                throw NativeDownloadError.unsupported("Discord requires captcha verification before login. Log in in Discord first, then use a token-based discord: URL.")
            }
            throw NativeDownloadError.unsupported("Discord email or password was rejected.")
        }
        guard let token = Self.stringValue(object["token"]), !token.isEmpty else {
            throw NativeDownloadError.unsupported("Discord login did not return a token. If two-factor authentication is enabled, use a token-based discord: URL.")
        }
        return token
    }

    private func request(url: URL, method: String, headers: [String: String], body: Data? = nil) async throws -> DiscordHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let configuration = URLSessionConfiguration.ephemeral
        NetworkSessionPrivacy.disableSystemCredentialPersistence(in: configuration)
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 120
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        if let proxy = NetworkSettings.load().connectionProxyDictionary(for: url) {
            configuration.connectionProxyDictionary = proxy
        }

        let session = URLSession(configuration: configuration)
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 200
        return DiscordHTTPResponse(statusCode: status, data: data)
    }

    private static func jsonObject(from data: Data) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.invalidGalleryData
        }
        return object
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
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

    private static func cleanTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmed
            .sanitizedFilename(maxLength: 100)
    }

    private static func isGuildID(_ value: String) -> Bool {
        value.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil
    }
}

private struct DiscordHTTPResponse {
    var statusCode: Int
    var data: Data
}
