import AppKit
import Foundation

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func sanitizedFilename(maxLength: Int = 180) -> String {
        let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let trimSet = CharacterSet(charactersIn: " .-").union(.whitespacesAndNewlines)

        let parts = unicodeScalars.map { scalar -> Character in
            invalid.contains(scalar) ? "-" : Character(scalar)
        }

        var cleaned = String(parts)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: trimSet)

        if cleaned.isEmpty {
            cleaned = "download"
        }

        cleaned = cleaned.truncatedFilenameComponent(
            maxCharacters: max(1, maxLength),
            maxUTF8Bytes: Self.filenameUTF8Limit(for: maxLength),
            trimSet: trimSet
        )

        return cleaned.isEmpty ? "download" : cleaned
    }

    private static func filenameUTF8Limit(for maxLength: Int) -> Int {
        Swift.max(16, Swift.min(240, Swift.max(1, maxLength) * 4))
    }

    private func truncatedFilenameComponent(maxCharacters: Int, maxUTF8Bytes: Int, trimSet: CharacterSet) -> String {
        let ext = (self as NSString).pathExtension
        let stem = (self as NSString).deletingPathExtension
        if !ext.isEmpty, !stem.isEmpty, ext.count <= 24 {
            let suffix = ".\(ext)"
            let stemByteLimit = maxUTF8Bytes - suffix.utf8.count
            let stemCharacterLimit = maxCharacters - suffix.count
            if stemByteLimit >= 8, stemCharacterLimit >= 1 {
                let safeStem = stem
                    .limitedPrefix(maxCharacters: stemCharacterLimit, maxUTF8Bytes: stemByteLimit)
                    .trimmingCharacters(in: trimSet)
                if !safeStem.isEmpty {
                    return "\(safeStem)\(suffix)"
                }
            }
        }

        let value = limitedPrefix(maxCharacters: maxCharacters, maxUTF8Bytes: maxUTF8Bytes)
            .trimmingCharacters(in: trimSet)
        return value.isEmpty ? "download" : value
    }

    private func limitedPrefix(maxCharacters: Int, maxUTF8Bytes: Int) -> String {
        var output = ""
        var usedBytes = 0
        var usedCharacters = 0
        for character in self {
            guard usedCharacters < maxCharacters else { break }
            let byteCount = String(character).utf8.count
            guard usedBytes + byteCount <= maxUTF8Bytes else { break }
            output.append(character)
            usedBytes += byteCount
            usedCharacters += 1
        }
        return output
    }

    func sanitizedRelativePath(maxComponentLength: Int = 120) -> String {
        let normalized = replacingOccurrences(of: "\\", with: "/")
        let parts = normalized
            .split(separator: "/", omittingEmptySubsequences: true)
            .map { String($0).trimmed }
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .map { $0.sanitizedFilename(maxLength: maxComponentLength) }
            .filter { !$0.isEmpty }
        return parts.isEmpty ? "download" : parts.joined(separator: "/")
    }

    var safeRelativePathComponents: [String] {
        sanitizedRelativePath().split(separator: "/").map(String.init)
    }
}

extension URL {
    var displayPath: String {
        path.removingPercentEncoding ?? path
    }
}

enum AppPaths {
#if TESTING
    private static let isolatedTestingSupportDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent(
            "HitomiBadayo-Testing-\(ProcessInfo.processInfo.processIdentifier)",
            isDirectory: true
        )
#endif

    static var defaultDownloadDirectory: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
        return downloads ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
    }

    static var applicationSupportDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["HITOMI_BADAYO_SUPPORT_DIR"] ?? environment["HITOMI_NATIVE_SUPPORT_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

#if TESTING
        return isolatedTestingSupportDirectory
#else
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")

        return base.appendingPathComponent("Hitomi Badayo", isDirectory: true)
#endif
    }

    static func migrateLegacyApplicationSupportIfNeeded() {
#if !TESTING
        let environment = ProcessInfo.processInfo.environment
        guard environment["HITOMI_BADAYO_SUPPORT_DIR"]?.isEmpty != false,
              environment["HITOMI_NATIVE_SUPPORT_DIR"]?.isEmpty != false else {
            return
        }
        let destination = applicationSupportDirectory
        guard !FileManager.default.fileExists(atPath: destination.path) else { return }
        let source = destination.deletingLastPathComponent()
            .appendingPathComponent("HitomiNative", isDirectory: true)
        guard FileManager.default.fileExists(atPath: source.path) else { return }
        try? FileManager.default.copyItem(at: source, to: destination)
#endif
    }

    static var pluginDirectory: URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["HITOMI_BADAYO_PLUGIN_DIR"] ?? environment["HITOMI_NATIVE_PLUGIN_DIR"],
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }

        return applicationSupportDirectory.appendingPathComponent("Plugins", isDirectory: true)
    }

    static var pythonPluginDirectory: URL {
        pluginDirectory.appendingPathComponent("Python", isDirectory: true)
    }

    static var pythonSessionScriptDirectory: URL {
        applicationSupportDirectory
            .appendingPathComponent("Scripts", isDirectory: true)
            .appendingPathComponent("Session", isDirectory: true)
    }

    static var customThumbnailDirectory: URL {
        applicationSupportDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    }

    static var userDataURL: URL {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["HITOMI_BADAYO_USER_DATA"] ?? environment["HITOMI_NATIVE_USER_DATA"],
           !override.isEmpty {
            return URL(fileURLWithPath: override)
        }

        return applicationSupportDirectory.appendingPathComponent("user-data.json")
    }

    static func ensureDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    static func uniqueFileURL(in directory: URL, filename: String) -> URL {
        let components = filename.safeRelativePathComponents
        let parent = components.dropLast().reduce(directory) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
        try? ensureDirectory(parent)
        let safeName = components.last ?? "download"
        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var candidate = parent.appendingPathComponent(safeName)
        var counter = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = parent.appendingPathComponent(name)
            counter += 1
        }

        return candidate
    }

    static func fileURL(in directory: URL, filename: String) -> URL {
        filename.safeRelativePathComponents.reduce(directory) { partial, component in
            partial.appendingPathComponent(component)
        }
    }

    static func uniqueDirectoryURL(in directory: URL, name: String) -> URL {
        let components = name.safeRelativePathComponents
        let parent = components.dropLast().reduce(directory) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
        let safeName = components.last ?? "download"
        var candidate = parent.appendingPathComponent(safeName, isDirectory: true)
        var counter = 2

        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = parent.appendingPathComponent("\(safeName) \(counter)", isDirectory: true)
            counter += 1
        }

        return candidate
    }

    static func directoryURL(in directory: URL, name: String) -> URL {
        name.safeRelativePathComponents.reduce(directory) { partial, component in
            partial.appendingPathComponent(component, isDirectory: true)
        }
    }
}

struct NameTemplateContext {
    var title: String
    var site: String
    var host: String
    var date: String
    var id: String
    var url: String
    var path: String
    var slug: String
    var query: String
    var filename: String
    var basename: String
    var ext: String
    var index: Int?
    var total: Int?
    var metadata: [String: String] = [:]
}

struct NameTemplateToken: Identifiable, Hashable {
    var value: String
    var title: String

    var id: String { value }
    var menuTitle: String { "\(value) - \(title)" }
}

enum NameTemplate {
    static let originalFolderPresets = [
        "[artist] title (id)",
        "[artist][0:id] title",
        "[artist][lang] title (id)",
        "[artist][group][series] title (id)",
        "title by artist (id)",
        "# artist / title (id)",
        "# type / [artist] title (id)",
        "# lang==\"korean\"?\"Korean\":\"Foreign\"; / [artist] title (id)"
    ]

    static let originalHitomiFilePresets = [
        "{basename}",
        "{index0:04}",
        "{index0:04} - {basename}"
    ]

    static let originalYouTubeFilePresets = [
        "title (id)",
        "title:50; (id)",
        "title",
        "id",
        "[artist] title (id)",
        "artist / title (id)",
        "[date] title (id)",
        "[date:%Y-%m-%d;] title (id)",
        "[height] title (id)"
    ]

    static let originalPixivFilePresets = [
        "id_ppage",
        "id_ppage:+1;",
        "id_ppage title",
        "[artist] id_ppage title",
        "[artist] id_ppage title:50;",
        "[artistid] id_ppage"
    ]

    static let originalInstagramFilePresets = [
        "[date] id_ppage",
        "[date] id_ppage:+1;"
    ]

    static let originalTwitterFilePresets = [
        "[date] id_ppage",
        "[date] id_ppage:+1;",
        "[date:%Y-%m-%d;] id_ppage",
        "[date] id_ppage @username"
    ]

    static let originalFilePresets: [String] = {
        var values: [String] = []
        for preset in originalHitomiFilePresets +
            originalYouTubeFilePresets +
            originalPixivFilePresets +
            originalInstagramFilePresets +
            originalTwitterFilePresets where !values.contains(preset) {
            values.append(preset)
        }
        return values
    }()

    static let originalRecordingPresets = [
        "[artist] date:%Y-%m-%d %H:%M; title"
    ]

    static let originalSourceFileTemplateIDs = [
        "hitomi",
        "youtube",
        "pixiv",
        "twitter",
        "insta"
    ]

    static func originalFilePresets(for sourceID: String) -> [String] {
        switch sourceID.trimmed.lowercased() {
        case "hitomi":
            return originalHitomiFilePresets
        case "youtube":
            return originalYouTubeFilePresets
        case "pixiv":
            return originalPixivFilePresets
        case "twitter":
            return originalTwitterFilePresets
        case "insta":
            return originalInstagramFilePresets
        default:
            return originalFilePresets
        }
    }

    static func originalFileDefault(for sourceID: String) -> String? {
        switch sourceID.trimmed.lowercased() {
        case "hitomi":
            return "{index0:04}"
        case "youtube":
            return "[artist] title (id)"
        case "pixiv":
            return "id_ppage"
        case "twitter", "insta":
            return "[date] id_ppage"
        default:
            return nil
        }
    }

    static func originalHitomiFileTemplate(typeNumber: Int) -> String {
        switch typeNumber {
        case 0: return originalHitomiFilePresets[0]
        case 2: return originalHitomiFilePresets[2]
        default: return originalHitomiFilePresets[1]
        }
    }

    static func originalHitomiFilenameTypeNumber(for template: String) -> Int? {
        switch template.trimmed {
        case originalHitomiFilePresets[0]: return 0
        case originalHitomiFilePresets[1]: return 1
        case originalHitomiFilePresets[2]: return 2
        default: return nil
        }
    }

    static func originalFilePreferenceKey(for sourceID: String) -> String? {
        switch sourceID.trimmed.lowercased() {
        case "youtube":
            return "youtubeFormat"
        case "pixiv":
            return "pixivFormat"
        case "twitter":
            return "twitterFormat"
        case "insta":
            return "instaFormat"
        default:
            return nil
        }
    }

    static let folderTokenSuggestions: [NameTemplateToken] = [
        NameTemplateToken(value: "{title}", title: "Title"),
        NameTemplateToken(value: "{site}", title: "Site"),
        NameTemplateToken(value: "{host}", title: "Host"),
        NameTemplateToken(value: "{date}", title: "Date"),
        NameTemplateToken(value: "{id}", title: "Source ID"),
        NameTemplateToken(value: "{gallery_id}", title: "Gallery ID"),
        NameTemplateToken(value: "{post_id}", title: "Post ID"),
        NameTemplateToken(value: "{video_id}", title: "Video ID"),
        NameTemplateToken(value: "{media_id}", title: "Media ID"),
        NameTemplateToken(value: "{episode_id}", title: "Episode ID"),
        NameTemplateToken(value: "{chapter_id}", title: "Chapter ID"),
        NameTemplateToken(value: "{emoji_id}", title: "Emoji ID"),
        NameTemplateToken(value: "{guild_id}", title: "Guild ID"),
        NameTemplateToken(value: "{snapshot_id}", title: "Snapshot ID"),
        NameTemplateToken(value: "{snapshot_timestamp}", title: "Snapshot timestamp"),
        NameTemplateToken(value: "{target_url}", title: "Target URL"),
        NameTemplateToken(value: "{playlist_url}", title: "Playlist URL"),
        NameTemplateToken(value: "{artist}", title: "Artist"),
        NameTemplateToken(value: "{author}", title: "Author"),
        NameTemplateToken(value: "{creator}", title: "Creator"),
        NameTemplateToken(value: "{series}", title: "Series"),
        NameTemplateToken(value: "{episode}", title: "Episode"),
        NameTemplateToken(value: "{chapter}", title: "Chapter"),
        NameTemplateToken(value: "{book}", title: "Book"),
        NameTemplateToken(value: "{username}", title: "Username"),
        NameTemplateToken(value: "{uid}", title: "User ID"),
        NameTemplateToken(value: "{artistid}", title: "Artist ID"),
        NameTemplateToken(value: "{uploader}", title: "Uploader"),
        NameTemplateToken(value: "{channel}", title: "Channel"),
        NameTemplateToken(value: "{channel_id}", title: "Channel ID"),
        NameTemplateToken(value: "{uploader_id}", title: "Uploader ID"),
        NameTemplateToken(value: "{type}", title: "Content type"),
        NameTemplateToken(value: "{media_type}", title: "Media type"),
        NameTemplateToken(value: "{language}", title: "Language"),
        NameTemplateToken(value: "{parody}", title: "Parody"),
        NameTemplateToken(value: "{category}", title: "Category"),
        NameTemplateToken(value: "{width}", title: "Media width"),
        NameTemplateToken(value: "{height}", title: "Media height"),
        NameTemplateToken(value: "{resolution}", title: "Media resolution"),
        NameTemplateToken(value: "{format}", title: "Media format"),
        NameTemplateToken(value: "{duration}", title: "Duration"),
        NameTemplateToken(value: "{slug}", title: "URL slug"),
        NameTemplateToken(value: "{path}", title: "URL path"),
        NameTemplateToken(value: "{query}", title: "URL query"),
        NameTemplateToken(value: "{url}", title: "Full URL"),
        NameTemplateToken(value: "{total}", title: "File count"),
        NameTemplateToken(value: "{total:03}", title: "Padded file count")
    ]

    static let fileTokenSuggestions: [NameTemplateToken] = [
        NameTemplateToken(value: "{index0:04}", title: "Zero-based padded index"),
        NameTemplateToken(value: "{index0}", title: "Zero-based index"),
        NameTemplateToken(value: "{index:04}", title: "Padded index"),
        NameTemplateToken(value: "{page:03}", title: "Padded page"),
        NameTemplateToken(value: "{index}", title: "Index"),
        NameTemplateToken(value: "{page}", title: "Page"),
        NameTemplateToken(value: "{total}", title: "File count"),
        NameTemplateToken(value: "{total:03}", title: "Padded file count"),
        NameTemplateToken(value: "{basename}", title: "Original basename"),
        NameTemplateToken(value: "{filename}", title: "Original filename"),
        NameTemplateToken(value: "{ext}", title: "Extension"),
        NameTemplateToken(value: "{title}", title: "Title"),
        NameTemplateToken(value: "{site}", title: "Site"),
        NameTemplateToken(value: "{host}", title: "Host"),
        NameTemplateToken(value: "{date}", title: "Date"),
        NameTemplateToken(value: "{id}", title: "Source ID"),
        NameTemplateToken(value: "{gallery_id}", title: "Gallery ID"),
        NameTemplateToken(value: "{post_id}", title: "Post ID"),
        NameTemplateToken(value: "{video_id}", title: "Video ID"),
        NameTemplateToken(value: "{media_id}", title: "Media ID"),
        NameTemplateToken(value: "{episode_id}", title: "Episode ID"),
        NameTemplateToken(value: "{chapter_id}", title: "Chapter ID"),
        NameTemplateToken(value: "{emoji_id}", title: "Emoji ID"),
        NameTemplateToken(value: "{emoji_name}", title: "Emoji name"),
        NameTemplateToken(value: "{guild_id}", title: "Guild ID"),
        NameTemplateToken(value: "{snapshot_id}", title: "Snapshot ID"),
        NameTemplateToken(value: "{snapshot_timestamp}", title: "Snapshot timestamp"),
        NameTemplateToken(value: "{target_url}", title: "Target URL"),
        NameTemplateToken(value: "{original_url}", title: "Original URL"),
        NameTemplateToken(value: "{playlist_url}", title: "Playlist URL"),
        NameTemplateToken(value: "{segment_number}", title: "HLS segment number"),
        NameTemplateToken(value: "{segment_total}", title: "HLS segment count"),
        NameTemplateToken(value: "{media_sequence}", title: "HLS media sequence"),
        NameTemplateToken(value: "{artist}", title: "Artist"),
        NameTemplateToken(value: "{author}", title: "Author"),
        NameTemplateToken(value: "{creator}", title: "Creator"),
        NameTemplateToken(value: "{series}", title: "Series"),
        NameTemplateToken(value: "{episode}", title: "Episode"),
        NameTemplateToken(value: "{chapter}", title: "Chapter"),
        NameTemplateToken(value: "{book}", title: "Book"),
        NameTemplateToken(value: "{username}", title: "Username"),
        NameTemplateToken(value: "{uid}", title: "User ID"),
        NameTemplateToken(value: "{artistid}", title: "Artist ID"),
        NameTemplateToken(value: "{uploader}", title: "Uploader"),
        NameTemplateToken(value: "{channel}", title: "Channel"),
        NameTemplateToken(value: "{channel_id}", title: "Channel ID"),
        NameTemplateToken(value: "{uploader_id}", title: "Uploader ID"),
        NameTemplateToken(value: "{type}", title: "Content type"),
        NameTemplateToken(value: "{media_type}", title: "Media type"),
        NameTemplateToken(value: "{language}", title: "Language"),
        NameTemplateToken(value: "{parody}", title: "Parody"),
        NameTemplateToken(value: "{category}", title: "Category"),
        NameTemplateToken(value: "{width}", title: "Media width"),
        NameTemplateToken(value: "{height}", title: "Media height"),
        NameTemplateToken(value: "{resolution}", title: "Media resolution"),
        NameTemplateToken(value: "{format}", title: "Media format"),
        NameTemplateToken(value: "{duration}", title: "Duration"),
        NameTemplateToken(value: "{duration_seconds}", title: "Duration seconds"),
        NameTemplateToken(value: "{image_url}", title: "Image URL"),
        NameTemplateToken(value: "{video_url}", title: "Video URL"),
        NameTemplateToken(value: "{media_url}", title: "Media URL"),
        NameTemplateToken(value: "{source_url}", title: "Source URL"),
        NameTemplateToken(value: "{page_url}", title: "Page URL"),
        NameTemplateToken(value: "{archive_url}", title: "Archived URL"),
        NameTemplateToken(value: "{slug}", title: "URL slug"),
        NameTemplateToken(value: "{path}", title: "URL path"),
        NameTemplateToken(value: "{query}", title: "URL query"),
        NameTemplateToken(value: "{url}", title: "Full URL")
    ]

    static func appending(token: String, to template: String) -> String {
        let value = template.trimmed
        guard !value.isEmpty else { return token }
        if value.hasSuffix("-") || value.hasSuffix("_") || value.hasSuffix("/") || value.hasSuffix(" ") {
            return value + token
        }
        return value + "-" + token
    }

    static func autocompleteSuggestions(in template: String, tokens: [NameTemplateToken], limit: Int = 5) -> [NameTemplateToken] {
        guard let partial = activeTokenPartial(in: template), !partial.isEmpty else { return [] }
        let normalized = partial.lowercased()
        let matches = tokens.filter { token in
            tokenName(token.value).lowercased().hasPrefix(normalized) ||
                token.title.lowercased().hasPrefix(normalized)
        }
        return Array(matches.prefix(max(0, limit)))
    }

    static func completingAutocomplete(in template: String, with token: String) -> String {
        guard let range = activeTokenRange(in: template) else {
            return appending(token: token, to: template)
        }
        var value = template
        value.replaceSubrange(range, with: token)
        return value
    }

    static func folderName(template: String, fallback: String, context: NameTemplateContext) -> String {
        let value = expanded(template: template, context: context)
        return value.isEmpty ? fallback.sanitizedFilename(maxLength: 120) : value.sanitizedRelativePath(maxComponentLength: 120)
    }

    static func fileName(template: String, fallback: String, context: NameTemplateContext) -> String {
        let value = expanded(template: template, context: context)
        guard !value.isEmpty else {
            return fallback.sanitizedFilename(maxLength: 180)
        }

        let shouldAppendExtension = !templateProvidesExtension(
            template: template,
            expandedValue: value,
            context: context
        )
        var components = value
            .sanitizedRelativePath(maxComponentLength: 180)
            .split(separator: "/")
            .map(String.init)
        var filename = components.popLast() ?? "download"
        if !context.ext.isEmpty && shouldAppendExtension {
            filename += ".\(context.ext.sanitizedFilename(maxLength: 24))"
        }
        components.append(filename.sanitizedFilename(maxLength: 180))
        return components.joined(separator: "/")
    }

    static func string(template: String, context: NameTemplateContext) -> String {
        expanded(template: template, context: context)
    }

    private static func activeTokenPartial(in template: String) -> String? {
        guard let range = activeTokenRange(in: template) else { return nil }
        let partialStart = template.index(after: range.lowerBound)
        return String(template[partialStart..<range.upperBound])
    }

    private static func activeTokenRange(in template: String) -> Range<String.Index>? {
        guard let open = template.lastIndex(of: "{") else { return nil }
        let afterOpen = template.index(after: open)
        let suffix = template[afterOpen...]
        guard !suffix.contains("}") else { return nil }
        guard suffix.allSatisfy({ character in
            character.isLetter || character.isNumber || character == "_" || character == ":"
        }) else { return nil }
        return open..<template.endIndex
    }

    private static func tokenName(_ token: String) -> String {
        var value = token
        if value.hasPrefix("{") {
            value.removeFirst()
        }
        if value.hasSuffix("}") {
            value.removeLast()
        }
        return value
    }

    private static func expanded(template: String, context: NameTemplateContext) -> String {
        var value = template.trimmed
        guard !value.isEmpty else { return "" }

        value = expandOriginalSyntax(in: value, context: context)
        value = replacePaddedNumberTokens(
            in: value,
            name: "index0",
            value: context.index.map { max(0, $0 - 1) }
        )
        value = replacePaddedNumberTokens(in: value, name: "index", value: context.index)
        value = replacePaddedNumberTokens(in: value, name: "page", value: context.index)
        value = replacePaddedNumberTokens(in: value, name: "total", value: context.total)

        let replacements: [String: String] = [
            "{title}": context.title,
            "{site}": context.site,
            "{host}": context.host,
            "{date}": dateTokenValue(context),
            "{id}": context.id,
            "{url}": context.url,
            "{path}": context.path,
            "{slug}": context.slug,
            "{query}": context.query,
            "{filename}": context.filename,
            "{basename}": context.basename,
            "{ext}": context.ext,
            "{index0}": context.index.map { String(max(0, $0 - 1)) } ?? "",
            "{index}": context.index.map(String.init) ?? "",
            "{page}": context.index.map(String.init) ?? "",
            "{total}": context.total.map(String.init) ?? "",
            "{artist}": metadataValue(context.metadata, keys: ["artist", "author", "creator", "uploader", "channel", "username", "user"]),
            "{author}": metadataValue(context.metadata, keys: ["author", "artist", "creator", "uploader", "channel", "username", "user"]),
            "{creator}": metadataValue(context.metadata, keys: ["creator", "artist", "author", "uploader", "channel", "username", "user"]),
            "{user}": metadataValue(context.metadata, keys: ["user", "username", "artist", "author", "creator", "uploader", "channel"]),
            "{username}": metadataValue(context.metadata, keys: ["username", "user", "artist", "author", "creator", "uploader", "channel"]),
            "{uid}": metadataValue(context.metadata, keys: ["uid", "user_id", "userID", "uploader_id", "uploaderID", "channel_id", "channelID"]),
            "{artistid}": metadataValue(context.metadata, keys: ["artistid", "artist_id", "user_id", "userID", "uid", "uploader_id", "uploaderID"]),
            "{uploader}": metadataValue(context.metadata, keys: ["uploader", "artist", "author", "creator", "channel", "username", "user"]),
            "{channel}": metadataValue(context.metadata, keys: ["channel", "uploader", "artist", "author", "creator", "username", "user"]),
            "{channel_id}": metadataValue(context.metadata, keys: ["channel_id", "channelID"]),
            "{uploader_id}": metadataValue(context.metadata, keys: ["uploader_id", "uploaderID", "user_id", "userID"])
        ]

        for (token, replacement) in replacements {
            value = value.replacingOccurrences(of: token, with: replacement)
        }

        value = replaceFlexibleBracedTokens(in: value, context: context)
        value = replaceMetadataTokens(in: value, metadata: context.metadata)
        value = cleanOriginalOptionalDecorations(in: value)
        return value
    }

    private static func expandConditionals(in input: String, context: NameTemplateContext) -> String {
        var output = ""
        var index = input.startIndex
        while index < input.endIndex {
            if let parsed = parseConditional(in: input, at: index, context: context) {
                output += parsed.value
                index = parsed.end
            } else {
                output.append(input[index])
                index = input.index(after: index)
            }
        }
        return output
    }

    private static func expandNumericOffsets(in input: String, context: NameTemplateContext) -> String {
        var output = ""
        var index = input.startIndex
        while index < input.endIndex {
            if let parsed = parseNumericOffset(in: input, at: index, context: context) {
                output += parsed.value
                index = parsed.end
            } else {
                output.append(input[index])
                index = input.index(after: index)
            }
        }
        return output
    }

    private static func expandOriginalStyleFragments(in input: String, context: NameTemplateContext) -> String {
        var output = ""
        var index = input.startIndex
        while index < input.endIndex {
            if let parsed = parseOriginalStyleFragment(in: input, at: index, context: context) {
                output += parsed.value
                index = parsed.end
            } else {
                output.append(input[index])
                index = input.index(after: index)
            }
        }
        return output
    }

    private static func parseOriginalStyleFragment(in input: String, at start: String.Index, context: NameTemplateContext) -> (value: String, end: String.Index)? {
        guard isIdentifierStart(input[start]) else { return nil }
        var cursor = input.index(after: start)
        while cursor < input.endIndex, isIdentifierBody(input[cursor]) {
            cursor = input.index(after: cursor)
        }
        let key = String(input[start..<cursor])
        skipWhitespace(in: input, cursor: &cursor)
        guard cursor < input.endIndex, input[cursor] == ":" else { return nil }
        cursor = input.index(after: cursor)
        skipWhitespace(in: input, cursor: &cursor)
        guard cursor < input.endIndex, input[cursor] != "+", input[cursor] != "-" else { return nil }

        let specStart = cursor
        while cursor < input.endIndex, input[cursor] != ";" {
            cursor = input.index(after: cursor)
        }
        guard cursor < input.endIndex else { return nil }
        let spec = String(input[specStart..<cursor]).trimmed
        guard !spec.isEmpty else { return nil }

        let normalized = key.trimmed.lowercased()
        let rawValue = templateValue(named: normalized, context: context)
        guard knownTemplateNames.contains(normalized) || !rawValue.isEmpty else {
            return nil
        }

        let replacement: String
        if normalized == "date", spec.contains("%") {
            replacement = formattedDateToken(context: context, format: spec)
        } else if let width = Int(spec), width > 0 {
            replacement = originalStyleWidthValue(rawValue, width: width, numericValue: numericTemplateValue(named: normalized, context: context))
        } else {
            return nil
        }
        return (replacement, input.index(after: cursor))
    }

    private static func originalStyleWidthValue(_ value: String, width: Int, numericValue: Int?) -> String {
        if let numericValue {
            return String(format: "%0\(width)d", numericValue)
        }
        return String(value.prefix(width))
    }

    private static func formattedDateToken(context: NameTemplateContext, format: String) -> String {
        let value = dateTokenValue(context)
        guard let components = dateComponents(from: value) else {
            return value
        }
        var output = format
        output = output.replacingOccurrences(of: "%Y", with: components.year)
        output = output.replacingOccurrences(of: "%y", with: String(components.year.suffix(2)))
        output = output.replacingOccurrences(of: "%m", with: components.month)
        output = output.replacingOccurrences(of: "%d", with: components.day)
        return output
    }

    private static func dateComponents(from value: String) -> (year: String, month: String, day: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]{4})[-./년]?([0-9]{1,2})[-./월]?([0-9]{1,2})"#) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let yearRange = Range(match.range(at: 1), in: value),
              let monthRange = Range(match.range(at: 2), in: value),
              let dayRange = Range(match.range(at: 3), in: value) else {
            return nil
        }
        let month = String(format: "%02d", Int(value[monthRange]) ?? 0)
        let day = String(format: "%02d", Int(value[dayRange]) ?? 0)
        guard month != "00", day != "00" else { return nil }
        return (String(value[yearRange]), month, day)
    }

    private static func parseNumericOffset(in input: String, at start: String.Index, context: NameTemplateContext) -> (value: String, end: String.Index)? {
        guard isIdentifierStart(input[start]) else { return nil }
        var cursor = input.index(after: start)
        while cursor < input.endIndex, isIdentifierBody(input[cursor]) {
            cursor = input.index(after: cursor)
        }
        let key = String(input[start..<cursor]).lowercased()
        skipWhitespace(in: input, cursor: &cursor)
        guard ["index", "page", "ppage", "total"].contains(key),
              cursor < input.endIndex,
              input[cursor] == ":" else {
            return nil
        }
        cursor = input.index(after: cursor)
        skipWhitespace(in: input, cursor: &cursor)
        guard cursor < input.endIndex,
              input[cursor] == "+" || input[cursor] == "-" else {
            return nil
        }
        let sign = input[cursor] == "-" ? -1 : 1
        cursor = input.index(after: cursor)
        skipWhitespace(in: input, cursor: &cursor)
        let digitStart = cursor
        while cursor < input.endIndex, input[cursor].isNumber {
            cursor = input.index(after: cursor)
        }
        let digitEnd = cursor
        skipWhitespace(in: input, cursor: &cursor)
        guard digitStart < digitEnd,
              cursor < input.endIndex,
              input[cursor] == ";",
              let offset = Int(input[digitStart..<digitEnd]),
              let base = numericTemplateValue(named: key, context: context) else {
            return nil
        }
        return (String(base + sign * offset), input.index(after: cursor))
    }

    private static func parseConditional(in input: String, at start: String.Index, context: NameTemplateContext) -> (value: String, end: String.Index)? {
        guard isIdentifierStart(input[start]) else { return nil }
        var cursor = input.index(after: start)
        while cursor < input.endIndex, isIdentifierBody(input[cursor]) {
            cursor = input.index(after: cursor)
        }
        let key = String(input[start..<cursor])
        skipWhitespace(in: input, cursor: &cursor)
        guard let comparison = parseConditionalComparison(in: input, cursor: &cursor) else {
            return nil
        }
        skipWhitespace(in: input, cursor: &cursor)

        guard let question = delimiter("?", in: input, from: cursor) else { return nil }
        let expected = unquotedConditionalLiteral(String(input[cursor..<question]))
        cursor = input.index(after: question)
        skipWhitespace(in: input, cursor: &cursor)

        guard let colon = delimiter(":", in: input, from: cursor) else { return nil }
        let trueValue = unquotedConditionalLiteral(String(input[cursor..<colon]))
        cursor = input.index(after: colon)
        skipWhitespace(in: input, cursor: &cursor)

        guard let semicolon = delimiter(";", in: input, from: cursor) else { return nil }
        let falseValue = unquotedConditionalLiteral(String(input[cursor..<semicolon]))
        let actual = templateValue(named: key, context: context).trimmed
        let isMatched: Bool
        switch comparison {
        case "==":
            isMatched = actual.caseInsensitiveCompare(expected) == .orderedSame
        case "!=":
            isMatched = actual.caseInsensitiveCompare(expected) != .orderedSame
        default:
            return nil
        }
        let selected = isMatched ? trueValue : falseValue
        return (selected, input.index(after: semicolon))
    }

    private static func parseConditionalComparison(in input: String, cursor: inout String.Index) -> String? {
        guard cursor < input.endIndex else { return nil }
        if input[cursor...].hasPrefix("==") {
            cursor = input.index(cursor, offsetBy: 2)
            return "=="
        }
        if input[cursor...].hasPrefix("!=") {
            cursor = input.index(cursor, offsetBy: 2)
            return "!="
        }
        return nil
    }

    private static func delimiter(_ delimiter: Character, in input: String, from start: String.Index) -> String.Index? {
        var index = start
        var braceDepth = 0
        while index < input.endIndex {
            if braceDepth == 0,
               let next = numericOffsetFragmentEnd(in: input, at: index) {
                index = next
                continue
            }
            let character = input[index]
            if character == "{" {
                braceDepth += 1
            } else if character == "}" {
                braceDepth = max(0, braceDepth - 1)
            } else if character == delimiter, braceDepth == 0 {
                return index
            }
            index = input.index(after: index)
        }
        return nil
    }

    private static func numericOffsetFragmentEnd(in input: String, at start: String.Index) -> String.Index? {
        guard isIdentifierStart(input[start]) else { return nil }
        var cursor = input.index(after: start)
        while cursor < input.endIndex, isIdentifierBody(input[cursor]) {
            cursor = input.index(after: cursor)
        }
        let key = String(input[start..<cursor]).lowercased()
        skipWhitespace(in: input, cursor: &cursor)
        guard ["index", "page", "ppage", "total"].contains(key),
              cursor < input.endIndex,
              input[cursor] == ":" else {
            return nil
        }
        cursor = input.index(after: cursor)
        skipWhitespace(in: input, cursor: &cursor)
        guard cursor < input.endIndex,
              input[cursor] == "+" || input[cursor] == "-" else {
            return nil
        }
        cursor = input.index(after: cursor)
        skipWhitespace(in: input, cursor: &cursor)
        let digitStart = cursor
        while cursor < input.endIndex, input[cursor].isNumber {
            cursor = input.index(after: cursor)
        }
        skipWhitespace(in: input, cursor: &cursor)
        guard digitStart < cursor,
              cursor < input.endIndex,
              input[cursor] == ";" else {
            return nil
        }
        return input.index(after: cursor)
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_"
    }

    private static func isIdentifierBody(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }

    private static func skipWhitespace(in input: String, cursor: inout String.Index) {
        while cursor < input.endIndex, input[cursor].isWhitespace {
            cursor = input.index(after: cursor)
        }
    }

    private static func unquotedConditionalLiteral(_ rawValue: String) -> String {
        var value = rawValue.trimmed
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }
        value.removeFirst()
        value.removeLast()
        return value
            .replacingOccurrences(of: "\\\"", with: "\"")
            .replacingOccurrences(of: "\\'", with: "'")
    }

    private static let knownTemplateNames: Set<String> = [
        "title", "site", "host", "date", "id", "url", "path", "slug", "query",
        "filename", "basename", "ext", "index0", "index", "page", "total",
        "artist", "author", "creator", "user", "username", "uid", "uploader",
        "artistid", "artist_id", "channel", "channel_id", "uploader_id",
        "lang", "language", "group", "series", "type", "height", "width", "ppage"
    ]

    private static let originalBareTemplateNames: Set<String> = [
        "title", "date", "id", "artist", "artistid", "lang", "language",
        "group", "series", "type", "height", "width", "ppage", "username"
    ]

    private static func expandOriginalSyntax(in input: String, context: NameTemplateContext) -> String {
        var output = ""
        var cursor = input.startIndex

        while cursor < input.endIndex {
            if input[cursor] == "{",
               let close = input[cursor...].firstIndex(of: "}") {
                output += input[cursor...close]
                cursor = input.index(after: close)
                continue
            }

            if input[cursor...].hasPrefix("id_ppage"),
               originalCompositeTokenHasBoundary(in: input, at: cursor, length: 8) {
                output += context.id + "_"
                cursor = input.index(cursor, offsetBy: 3)
                continue
            }

            if let parsed = parseConditional(in: input, at: cursor, context: context) {
                output += parsed.value
                cursor = parsed.end
                continue
            }

            if let parsed = parseNumericOffset(in: input, at: cursor, context: context) {
                output += parsed.value
                cursor = parsed.end
                continue
            }

            if let parsed = parseOriginalStyleFragment(in: input, at: cursor, context: context) {
                output += parsed.value
                cursor = parsed.end
                continue
            }

            if input[cursor...].hasPrefix("0:id"),
               originalTokenHasBoundary(in: input, before: cursor, afterOffset: 4) {
                output += zeroPaddedSourceID(context.id)
                cursor = input.index(cursor, offsetBy: 4)
                continue
            }

            guard isIdentifierStart(input[cursor]) else {
                output.append(input[cursor])
                cursor = input.index(after: cursor)
                continue
            }

            let start = cursor
            cursor = input.index(after: cursor)
            while cursor < input.endIndex, isIdentifierBody(input[cursor]) {
                cursor = input.index(after: cursor)
            }
            let token = String(input[start..<cursor])
            if originalBareTemplateNames.contains(token.lowercased()) {
                output += templateValue(named: token, context: context)
            } else {
                output += token
            }
        }

        return output
    }

    private static func originalCompositeTokenHasBoundary(
        in input: String,
        at start: String.Index,
        length: Int
    ) -> Bool {
        if start > input.startIndex,
           isIdentifierBody(input[input.index(before: start)]) {
            return false
        }
        let end = input.index(start, offsetBy: length)
        return end == input.endIndex || !isIdentifierBody(input[end])
    }

    private static func originalTokenHasBoundary(
        in input: String,
        before start: String.Index,
        afterOffset: Int
    ) -> Bool {
        if start > input.startIndex {
            let previous = input[input.index(before: start)]
            if isIdentifierBody(previous) || previous == ":" {
                return false
            }
        }
        let end = input.index(start, offsetBy: afterOffset)
        if end < input.endIndex {
            let next = input[end]
            if isIdentifierBody(next) || next == ":" {
                return false
            }
        }
        return true
    }

    private static func zeroPaddedSourceID(_ rawValue: String) -> String {
        let value = rawValue.trimmed
        guard let number = Int(value) else { return value }
        return String(format: "%07d", number)
    }

    private static func cleanOriginalOptionalDecorations(in input: String) -> String {
        var output = input
        output = output.replacingOccurrences(
            of: #"\[\s*\]|\(\s*\)"#,
            with: "",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"[ \t]{2,}"#,
            with: " ",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"\s*/\s*"#,
            with: "/",
            options: .regularExpression
        )
        output = output.replacingOccurrences(
            of: #"/{2,}"#,
            with: "/",
            options: .regularExpression
        )
        return output.trimmingCharacters(in: CharacterSet(charactersIn: " /-"))
    }

    private static func replaceFlexibleBracedTokens(in input: String, context: NameTemplateContext) -> String {
        let pattern = #"\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*0?([1-9][0-9]?))?\s*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return input
        }

        var output = ""
        var cursor = input.startIndex
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        for match in regex.matches(in: input, range: range) {
            guard let fullRange = Range(match.range(at: 0), in: input),
                  let nameRange = Range(match.range(at: 1), in: input) else {
                continue
            }

            output += input[cursor..<fullRange.lowerBound]
            let width = Range(match.range(at: 2), in: input).flatMap { Int(input[$0]) }
            let replacement = bracedTemplateReplacement(
                name: String(input[nameRange]),
                width: width,
                context: context
            )
            output += replacement ?? String(input[fullRange])
            cursor = fullRange.upperBound
        }
        output += input[cursor..<input.endIndex]
        return output
    }

    private static func bracedTemplateReplacement(name: String, width: Int?, context: NameTemplateContext) -> String? {
        let normalized = name.trimmed.lowercased()
        if let width {
            guard let value = numericTemplateValue(named: normalized, context: context) else {
                return nil
            }
            return String(format: "%0\(width)d", value)
        }

        if knownTemplateNames.contains(normalized) {
            return templateValue(named: normalized, context: context)
        }

        let metadata = metadataValue(context.metadata, keys: [name, normalized])
        return metadata.isEmpty ? nil : metadata
    }

    private static func templateValue(named name: String, context: NameTemplateContext) -> String {
        switch name.lowercased() {
        case "title": return context.title
        case "site": return context.site
        case "host": return context.host
        case "date": return dateTokenValue(context)
        case "id": return context.id
        case "url": return context.url
        case "path": return context.path
        case "slug": return context.slug
        case "query": return context.query
        case "filename": return context.filename
        case "basename": return context.basename
        case "ext": return context.ext
        case "index0": return context.index.map { String(max(0, $0 - 1)) } ?? ""
        case "index", "page": return context.index.map(String.init) ?? ""
        case "total": return context.total.map(String.init) ?? ""
        case "artist": return metadataValue(context.metadata, keys: ["artist", "author", "creator", "uploader", "channel", "username", "user", "group", "groups"])
        case "author": return metadataValue(context.metadata, keys: ["author", "artist", "creator", "uploader", "channel", "username", "user"])
        case "creator": return metadataValue(context.metadata, keys: ["creator", "artist", "author", "uploader", "channel", "username", "user"])
        case "user": return metadataValue(context.metadata, keys: ["user", "username", "artist", "author", "creator", "uploader", "channel"])
        case "username": return metadataValue(context.metadata, keys: ["username", "user", "artist", "author", "creator", "uploader", "channel"])
        case "uid": return metadataValue(context.metadata, keys: ["uid", "user_id", "userID", "uploader_id", "uploaderID", "channel_id", "channelID"])
        case "artistid", "artist_id": return metadataValue(context.metadata, keys: ["artistid", "artist_id", "user_id", "userID", "uid", "uploader_id", "uploaderID"])
        case "uploader": return metadataValue(context.metadata, keys: ["uploader", "artist", "author", "creator", "channel", "username", "user"])
        case "channel": return metadataValue(context.metadata, keys: ["channel", "uploader", "artist", "author", "creator", "username", "user"])
        case "channel_id": return metadataValue(context.metadata, keys: ["channel_id", "channelID"])
        case "uploader_id": return metadataValue(context.metadata, keys: ["uploader_id", "uploaderID", "user_id", "userID"])
        case "lang", "language": return metadataValue(context.metadata, keys: ["lang", "language"])
        case "group": return metadataValue(context.metadata, keys: ["group", "groups"])
        case "series": return metadataValue(context.metadata, keys: ["series", "parody", "book"])
        case "type": return metadataValue(context.metadata, keys: ["type", "category", "media_type"])
        case "height": return metadataValue(context.metadata, keys: ["height", "resolution_height"])
        case "width": return metadataValue(context.metadata, keys: ["width", "resolution_width"])
        case "ppage":
            return context.index.map { String(max(0, $0 - 1)) } ?? ""
        default:
            return metadataValue(context.metadata, keys: [name, name.lowercased()])
        }
    }

    private static func numericTemplateValue(named name: String, context: NameTemplateContext) -> Int? {
        switch name.lowercased() {
        case "index0":
            return context.index.map { max(0, $0 - 1) }
        case "index", "page":
            return context.index
        case "ppage":
            return context.index.map { max(0, $0 - 1) }
        case "total":
            return context.total
        default:
            return nil
        }
    }

    private static func metadataValue(_ metadata: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = metadata[key]?.trimmed, !value.isEmpty {
                return value
            }
        }
        for key in keys {
            if let match = metadata.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame }),
               !match.value.trimmed.isEmpty {
                return match.value.trimmed
            }
        }
        return ""
    }

    private static func dateTokenValue(_ context: NameTemplateContext) -> String {
        let explicit = context.date.trimmed
        if !explicit.isEmpty {
            return explicit
        }
        let metadataDate = metadataValue(
            context.metadata,
            keys: [
                "date", "upload_date", "uploadDate",
                "published_date", "published", "published_at", "publishedAt",
                "published_time", "publishedTime", "datePublished", "date_published",
                "publishDate", "publish_date", "pubdate", "datepublished",
                "article:published_time", "article:modified_time",
                "posted", "posted_at", "postedAt",
                "created", "created_at", "createdAt", "created_time", "createdTime", "createdDate",
                "uploaded", "uploaded_at", "uploadedAt",
                "registered", "registered_at", "registeredAt",
                "firstRetrieve", "first_retrieve",
                "release_date", "reg_date", "broad_start", "write_tm", "openDate",
                "taken_at_timestamp", "taken_at", "device_timestamp", "imported_taken_at",
                "timestamp"
            ]
        )
        return normalizedDateTokenValue(metadataDate) ?? metadataDate
    }

    private static func normalizedDateTokenValue(_ raw: String) -> String? {
        let value = raw.trimmed
        guard !value.isEmpty else { return nil }

        if let match = value.range(of: #"^[0-9]{8}(?:[0-9]{6})?$"#, options: .regularExpression) {
            let digits = String(value[match])
            let year = digits.prefix(4)
            let monthStart = digits.index(digits.startIndex, offsetBy: 4)
            let dayStart = digits.index(digits.startIndex, offsetBy: 6)
            let month = digits[monthStart..<dayStart]
            let dayEnd = digits.index(digits.startIndex, offsetBy: 8)
            let day = digits[dayStart..<dayEnd]
            return "\(year)-\(month)-\(day)"
        }

        if let date = normalizedUnixDateTokenValue(value) {
            return date
        }

        let pattern = #"([0-9]{4})[-./]([0-9]{1,2})[-./]([0-9]{1,2})"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..<value.endIndex, in: value)),
              let yearRange = Range(match.range(at: 1), in: value),
              let monthRange = Range(match.range(at: 2), in: value),
              let dayRange = Range(match.range(at: 3), in: value) else {
            return nil
        }
        guard let month = Int(value[monthRange]),
              let day = Int(value[dayRange]) else {
            return nil
        }
        return String(format: "%@-%02d-%02d", String(value[yearRange]), month, day)
    }

    private static func normalizedUnixDateTokenValue(_ raw: String) -> String? {
        let value = raw.trimmed
        let seconds: TimeInterval?
        if value.range(of: #"^1[0-9]{9}(?:\.[0-9]+)?$"#, options: .regularExpression) != nil {
            seconds = TimeInterval(value)
        } else if value.range(of: #"^1[0-9]{12}$"#, options: .regularExpression) != nil,
                  let milliseconds = TimeInterval(value) {
            seconds = milliseconds / 1000
        } else {
            seconds = nil
        }
        guard let seconds, seconds > 0 else { return nil }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func replaceMetadataTokens(in input: String, metadata: [String: String]) -> String {
        var output = input
        for (key, value) in metadata {
            guard key.range(of: #"^[A-Za-z][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
                continue
            }
            output = output.replacingOccurrences(of: "{\(key)}", with: value)
        }
        return output
    }

    private static func templateProvidesExtension(template: String, expandedValue: String, context: NameTemplateContext) -> Bool {
        if containsBracedToken(named: ["ext", "filename"], in: template) {
            return true
        }
        if trailingExtension(in: expandConditionals(in: template, context: context)) != nil {
            return true
        }
        if trailingExtension(in: template) != nil {
            return true
        }
        guard !context.ext.isEmpty,
              let expandedExtension = trailingExtension(in: expandedValue) else {
            return false
        }
        return expandedExtension.caseInsensitiveCompare(context.ext) == .orderedSame
    }

    private static func containsBracedToken(named names: Set<String>, in input: String) -> Bool {
        let pattern = #"\{\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*0?[1-9][0-9]?)?\s*\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return false
        }
        let range = NSRange(input.startIndex..<input.endIndex, in: input)
        return regex.matches(in: input, range: range).contains { match in
            guard let nameRange = Range(match.range(at: 1), in: input) else {
                return false
            }
            return names.contains(String(input[nameRange]).lowercased())
        }
    }

    private static func trailingExtension(in input: String) -> String? {
        let value = input.trimmed
        guard let dotIndex = value.lastIndex(of: ".") else { return nil }
        let extStart = value.index(after: dotIndex)
        guard extStart < value.endIndex else { return nil }

        let ext = value[extStart...]
        guard ext.count <= 12,
              ext.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) else {
            return nil
        }
        return String(ext)
    }

    private static func replacePaddedNumberTokens(in input: String, name: String, value: Int?) -> String {
        guard let value else { return input }
        let pattern = "\\{\(NSRegularExpression.escapedPattern(for: name)):0?([1-9][0-9]?)\\}"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return input }

        var output = input
        let matches = regex.matches(in: input, range: NSRange(input.startIndex..<input.endIndex, in: input)).reversed()
        for match in matches {
            guard let range = Range(match.range(at: 0), in: output),
                  let widthRange = Range(match.range(at: 1), in: input),
                  let width = Int(input[widthRange]) else {
                continue
            }
            output.replaceSubrange(range, with: String(format: "%0\(width)d", value))
        }
        return output
    }
}
