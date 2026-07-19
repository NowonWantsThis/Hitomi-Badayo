import CryptoKit
import Foundation

struct PythonDownloaderDescriptor: Codable, Hashable, Identifiable {
    var className: String
    var type: String
    var urlPatterns: [String]
    var single: Bool

    var id: String { "\(className):\(type)" }

    func matches(_ url: URL) -> Bool {
        urlPatterns.contains { Self.matches(pattern: $0, url: url) }
    }

    private static func matches(pattern rawPattern: String, url: URL) -> Bool {
        let pattern = rawPattern.trimmed
        guard !pattern.isEmpty else { return false }
        let absolute = url.absoluteString
        let lowerAbsolute = absolute.lowercased()
        let lowerPattern = pattern.lowercased()

        if pattern.range(of: #"^[A-Za-z0-9.-]+(?::[0-9]+)?$"#, options: .regularExpression) != nil {
            let hostPattern = lowerPattern.components(separatedBy: ":").first ?? lowerPattern
            guard let host = url.host?.lowercased() else { return false }
            return host == hostPattern || host.hasSuffix("." + hostPattern)
        }

        let looksLikeRegex = pattern.hasPrefix("^") || pattern.hasSuffix("$") ||
            pattern.contains("(?") || pattern.contains("\\") || pattern.contains("[") ||
            pattern.contains(".*") || pattern.contains("|")
        if looksLikeRegex,
           let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
           expression.firstMatch(in: absolute, range: NSRange(absolute.startIndex..., in: absolute)) != nil {
            return true
        }

        if pattern.contains("*") || pattern.contains("?") {
            let escaped = NSRegularExpression.escapedPattern(for: pattern)
                .replacingOccurrences(of: #"\*"#, with: ".*")
                .replacingOccurrences(of: #"\?"#, with: ".")
            return absolute.range(of: "^\(escaped)$", options: [.regularExpression, .caseInsensitive]) != nil ||
                absolute.range(of: escaped, options: [.regularExpression, .caseInsensitive]) != nil
        }

        return lowerAbsolute.contains(lowerPattern)
    }
}

enum PythonHookEvent: String, Codable, CaseIterable, Hashable {
    case taskAboutToStart = "task_about_to_start"
    case taskAboutToDownload = "task_about_to_download"
    case taskFinished = "task_finished"
    case format

    var shortLabel: String {
        switch self {
        case .taskAboutToStart: return "start"
        case .taskAboutToDownload: return "download"
        case .taskFinished: return "finished"
        case .format: return "format"
        }
    }
}

struct PythonHookDescriptor: Codable, Hashable, Identifiable {
    var event: PythonHookEvent
    var name: String

    var id: String { "\(event.rawValue):\(name)" }
}

enum PythonThemeAppearance: String, Codable, Hashable {
    case system
    case light
    case dark
}

struct PythonThemeDescriptor: Codable, Hashable, Identifiable {
    var key: String
    var displayName: String
    var appearance: PythonThemeAppearance
    var accentColor: String?
    var backgroundColor: String?
    var surfaceColor: String?
    var foregroundColor: String?
    var base: String?
    var system: Bool
    var translucent: Bool
    var buttonShadow: Bool
    var styleSheetPresent: Bool
    var palettePresent: Bool

    var id: String { key }

    func normalized() -> PythonThemeDescriptor? {
        let normalizedKey = String(key.trimmed.lowercased().prefix(128))
        guard !normalizedKey.isEmpty else { return nil }
        var copy = self
        copy.key = normalizedKey
        let name = String(displayName.trimmed.prefix(200))
        copy.displayName = name.isEmpty ? normalizedKey : name
        copy.accentColor = Self.normalizedColor(accentColor)
        copy.backgroundColor = Self.normalizedColor(backgroundColor)
        copy.surfaceColor = Self.normalizedColor(surfaceColor)
        copy.foregroundColor = Self.normalizedColor(foregroundColor)
        if let base = base?.trimmed, !base.isEmpty {
            copy.base = String(base.prefix(100))
        } else {
            copy.base = nil
        }
        return copy
    }

    private static func normalizedColor(_ value: String?) -> String? {
        guard var raw = value?.trimmed.uppercased(), !raw.isEmpty else { return nil }
        if raw.hasPrefix("#") { raw.removeFirst() }
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else { return nil }
        return "#" + raw
    }
}

struct PythonHookAssetContext: Codable, Equatable {
    var url: String
    var filename: String
    var referer: String?
    var userAgent: String?
    var headers: [String: String]
    var metadata: [String: String]

    init(
        url: String,
        filename: String,
        referer: String? = nil,
        userAgent: String? = nil,
        headers: [String: String] = [:],
        metadata: [String: String] = [:]
    ) {
        self.url = url
        self.filename = filename
        self.referer = referer
        self.userAgent = userAgent
        self.headers = headers
        self.metadata = metadata
    }

    init(asset: ResolvedAsset) {
        url = asset.remoteURL.absoluteString
        filename = asset.filename
        referer = asset.referer
        userAgent = asset.userAgent
        headers = asset.additionalHeaderFields
        metadata = asset.metadata
    }
}

struct PythonHookContext: Codable, Equatable {
    var sourceURL: String
    var title: String
    var artist: String?
    var type: String?
    var status: String
    var outputPath: String
    var metadata: [String: String]
    var assets: [PythonHookAssetContext]
    var names: [String]
    var total: Int
    var completed: Int
    var errorMessage: String?
    var valid: Bool
    var single: Bool
}

struct PythonHookExecutionResult {
    var context: PythonHookContext
    var logs: String
}

struct PythonScriptStaticMetadata: Equatable {
    var title: String
    var author: String
    var comment: String
    var signature: String
    var encoding: String
    var digest: String
    var byteCount: Int
}

struct PythonScriptPlugin: Codable, Equatable, Identifiable {
    var digest: String
    var scriptPath: String
    var title: String
    var author: String
    var comment: String
    var signature: String
    var encoding: String
    var downloaders: [PythonDownloaderDescriptor]
    var hooks: [PythonHookDescriptor]?
    var themes: [PythonThemeDescriptor]? = nil
    var runsOnLoad: Bool? = nil
    var lastOutput: String? = nil
    var isEnabled: Bool
    var isSession: Bool
    var importedAt: Date
    var lastError: String?

    var id: String { digest }
    var scriptURL: URL { URL(fileURLWithPath: scriptPath) }
    var filename: String { scriptURL.lastPathComponent }
    var hasSignature: Bool { !signature.trimmed.isEmpty }
    var registeredHooks: [PythonHookDescriptor] { hooks ?? [] }
    var registeredThemes: [PythonThemeDescriptor] { themes ?? [] }
    var isToolPlugin: Bool { runsOnLoad == true }
    var hasCompatibleEntryPoints: Bool {
        !downloaders.isEmpty || !registeredHooks.isEmpty || !registeredThemes.isEmpty || isToolPlugin
    }

    var typeSummary: String {
        var parts = downloaders.map(\.type)
        let hookEvents = PythonHookEvent.allCases.filter { event in
            registeredHooks.contains { $0.event == event }
        }
        if !hookEvents.isEmpty {
            parts.append("hooks " + hookEvents.map(\.shortLabel).joined(separator: "/"))
        }
        if !registeredThemes.isEmpty {
            parts.append("themes \(registeredThemes.count)")
        }
        if isToolPlugin {
            parts.append("tool plugin")
        }
        return parts.isEmpty ? "No compatible entry points" : parts.joined(separator: ", ")
    }

    var patternSummary: String {
        let patterns = downloaders.flatMap(\.urlPatterns)
        if !patterns.isEmpty {
            return patterns.joined(separator: ", ")
        }
        let hookNames = registeredHooks.map { "\($0.event.shortLabel):\($0.name)" }
        let themeNames = registeredThemes.map { "theme:\($0.key)" }
        let names = hookNames + themeNames
        return names.isEmpty ? "No URL patterns, hooks, or themes" : names.joined(separator: ", ")
    }

    var statusSummary: String {
        if let lastError, !lastError.trimmed.isEmpty {
            return lastError
        }
        var parts = [typeSummary]
        if isSession {
            parts.append("session")
        }
        if hasSignature {
            parts.append("signature present")
        }
        return parts.joined(separator: " · ")
    }

    func matchingDownloader(for url: URL) -> PythonDownloaderDescriptor? {
        downloaders.last { $0.matches(url) }
    }
}

enum PythonScriptBridgeError: LocalizedError {
    case invalidScript(String)
    case runtimeUnavailable
    case runnerUnavailable
    case invalidResponse(String)
    case nativeDelegation(String)
    case taskReaction(name: String, message: String)
    case retryRequested(status: String, message: String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidScript(let message): return message
        case .runtimeUnavailable:
            return "Python 3 is not available. Choose a Python 3 executable in Settings > Plugins."
        case .runnerUnavailable:
            return "The bundled Python compatibility runner is missing."
        case .invalidResponse(let message): return "Python script returned an invalid response: \(message)"
        case .nativeDelegation(let feature): return "Using native resolver for \(feature)."
        case .taskReaction(_, let message): return message
        case .retryRequested(_, let message): return message
        case .scriptFailed(let message): return "Python script failed: \(message)"
        }
    }
}

final class PythonScriptBridge {
    static let maximumScriptSize = 128 * 1024 * 1024
    private static let maximumRunnerOutputSize = 64 * 1024 * 1024
    private static let resultPrefix = "HITOMI_NATIVE_RESULT:"

    private let configuredPythonPath: String

    init(configuredPythonPath: String = "") {
        self.configuredPythonPath = configuredPythonPath
    }

    func inspect(scriptURL: URL) async throws -> PythonScriptPlugin {
        let metadata = try Self.staticMetadata(at: scriptURL)
        let request = RunnerRequest(
            action: "inspect",
            scriptPath: scriptURL.path,
            sourceURL: nil,
            className: nil,
            requestHeaders: nil,
            maxAssets: nil
        )
        let response = try await run(request, scriptDirectory: scriptURL.deletingLastPathComponent())
        guard response.sha256 == nil || response.sha256 == metadata.digest else {
            throw PythonScriptBridgeError.invalidResponse("script hash changed while it was being inspected")
        }
        let downloaders = response.downloaders ?? []
        let hooks = response.hooks ?? []
        let themes = (response.themes ?? []).compactMap { $0.normalized() }
        let hasEntryPoints = !downloaders.isEmpty || !hooks.isEmpty || !themes.isEmpty
        return PythonScriptPlugin(
            digest: metadata.digest,
            scriptPath: scriptURL.path,
            title: metadata.title,
            author: metadata.author,
            comment: metadata.comment,
            signature: metadata.signature,
            encoding: response.encoding ?? metadata.encoding,
            downloaders: downloaders,
            hooks: hooks,
            themes: themes,
            lastOutput: response.logs,
            isEnabled: hasEntryPoints,
            isSession: false,
            importedAt: Date(),
            lastError: hasEntryPoints ? nil : "No compatible Downloader, Hook, or theme registered"
        )
    }

    func resolve(
        plugin: PythonScriptPlugin,
        downloader: PythonDownloaderDescriptor,
        sourceURL: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions()
    ) async throws -> ResolvedDownload {
        var requestHeaders: [String: String] = [:]
        if let referer = headers.referer?.trimmed, !referer.isEmpty {
            requestHeaders["Referer"] = referer
        }
        if let userAgent = headers.userAgent?.trimmed, !userAgent.isEmpty {
            requestHeaders["User-Agent"] = userAgent
        }
        let request = RunnerRequest(
            action: "resolve",
            scriptPath: plugin.scriptPath,
            sourceURL: sourceURL.absoluteString,
            className: downloader.className,
            requestHeaders: requestHeaders,
            maxAssets: 100_000
        )
        let response = try await run(request, scriptDirectory: plugin.scriptURL.deletingLastPathComponent())
        guard response.sha256 == nil || response.sha256 == plugin.digest else {
            throw PythonScriptBridgeError.invalidScript("The installed script changed. Reload it before downloading.")
        }
        guard let result = response.result else {
            throw PythonScriptBridgeError.invalidResponse("missing download result")
        }
        guard !result.assets.isEmpty else {
            throw PythonScriptBridgeError.scriptFailed("no URLs were added")
        }

        let title = result.title.trimmed.isEmpty ? plugin.title : result.title.trimmed
        var metadata: [String: String] = [
            "type": downloader.type,
            "site": sourceURL.host ?? downloader.type,
            "handler": "python-script",
            "python_plugin": plugin.title,
            "python_script": plugin.filename,
            "python_script_sha256": plugin.digest,
            "python_downloader": downloader.className,
            "python_single": result.single ? "true" : "false"
        ]
        for (key, value) in result.metadata ?? [:]
            where !key.trimmed.isEmpty && !value.trimmed.isEmpty {
            metadata[key] = value
        }
        metadata["type"] = downloader.type
        metadata["handler"] = "python-script"
        metadata["artist"] = result.artist
        metadata["author"] = result.artist ?? (plugin.author.trimmed.isEmpty ? nil : plugin.author)

        let streamAssets = result.assets.filter { $0.stream != nil }
        if !streamAssets.isEmpty {
            if streamAssets.count == 1, result.assets.count == 1 {
                return try await resolveStreamAsset(
                    streamAssets[0],
                    title: title,
                    metadata: metadata,
                    sourceURL: sourceURL,
                    plugin: plugin,
                    downloader: downloader,
                    streamIndex: 0
                )
            }
            return try await resolveGroupedAssets(
                result.assets,
                title: title,
                metadata: metadata,
                sourceURL: sourceURL,
                plugin: plugin,
                downloader: downloader
            )
        }

        var usedNames: [String: Int] = [:]
        var assets: [ResolvedAsset] = []
        for (index, value) in result.assets.enumerated() {
            assets.append(try Self.resolvedFileAsset(value, index: index, usedNames: &usedNames))
        }

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            metadata: DownloadMetadata.clean(metadata)
        )
    }

    private func resolveGroupedAssets(
        _ values: [RunnerAsset],
        title: String,
        metadata: [String: String],
        sourceURL: URL,
        plugin: PythonScriptPlugin,
        downloader: PythonDownloaderDescriptor
    ) async throws -> ResolvedDownload {
        var assets: [ResolvedAsset] = []
        var fileAssetIndexes: [Int] = []
        var concatenations: [ResolvedConcatenationGroup] = []
        var usedOutputNames: [String: Int] = [:]
        var live = false

        for (index, value) in values.enumerated() {
            if value.stream != nil {
                let streamDownload = try await resolveStreamAsset(
                    value,
                    title: title,
                    metadata: metadata,
                    sourceURL: sourceURL,
                    plugin: plugin,
                    downloader: downloader,
                    streamIndex: index
                )
                guard case .concatenate(let requestedOutput) = streamDownload.packageMode else {
                    throw PythonScriptBridgeError.invalidResponse("stream did not produce a concatenation plan")
                }
                let start = assets.count
                assets.append(contentsOf: streamDownload.assets)
                let indexes = Array(start..<assets.count)
                guard !indexes.isEmpty else {
                    throw PythonScriptBridgeError.scriptFailed("stream output contained no downloadable segments")
                }
                let output = Self.uniqueRelativeFilename(requestedOutput, used: &usedOutputNames)
                concatenations.append(
                    ResolvedConcatenationGroup(
                        assetIndexes: indexes,
                        outputFilename: output,
                        metadata: streamDownload.metadata
                    )
                )
                live = live || streamDownload.metadata["live"] == "true" || streamDownload.metadata["is_live"] == "true"
            } else {
                let asset = try Self.resolvedFileAsset(value, index: index, usedNames: &usedOutputNames)
                fileAssetIndexes.append(assets.count)
                assets.append(asset)
            }
        }

        var groupedMetadata = metadata
        groupedMetadata["python_downloader_type"] = metadata["type"]
        groupedMetadata["python_stream"] = "m3u8"
        groupedMetadata["python_stream_count"] = String(concatenations.count)
        groupedMetadata["python_file_count"] = String(fileAssetIndexes.count)
        groupedMetadata["python_output_count"] = String(concatenations.count + fileAssetIndexes.count)
        groupedMetadata["python_grouped_output"] = "true"
        groupedMetadata["package_mode"] = "grouped"
        groupedMetadata["format"] = fileAssetIndexes.isEmpty ? "m3u8" : "mixed"
        groupedMetadata["media_type"] = fileAssetIndexes.isEmpty ? "hls" : "mixed"
        groupedMetadata["source_url"] = sourceURL.absoluteString
        groupedMetadata["page_url"] = sourceURL.absoluteString
        if live {
            groupedMetadata["live"] = "true"
            groupedMetadata["is_live"] = "true"
        }

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            packageMode: .grouped(
                fileAssetIndexes: fileAssetIndexes,
                concatenations: concatenations
            ),
            metadata: DownloadMetadata.clean(groupedMetadata)
        )
    }

    private static func resolvedFileAsset(
        _ value: RunnerAsset,
        index: Int,
        usedNames: inout [String: Int]
    ) throws -> ResolvedAsset {
        guard let remoteURL = URL(string: value.url),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw PythonScriptBridgeError.invalidScript("Unsupported asset URL at item \(index + 1): \(value.url)")
        }
        let proposed = value.filename.trimmed.isEmpty
            ? defaultFilename(for: remoteURL, index: index)
            : value.filename.sanitizedRelativePath()
        let filename = uniqueRelativeFilename(proposed, used: &usedNames)
        let headerFields = validHeaders(value.headers ?? [:])
        let referer = cleanHeaderValue(value.referer)
            ?? headerFields.firstValue(caseInsensitiveKey: "Referer")
        let userAgent = cleanHeaderValue(value.userAgent)
            ?? headerFields.firstValue(caseInsensitiveKey: "User-Agent")
        let additionalHeaders = headerFields
            .filter { !["referer", "user-agent"].contains($0.key.lowercased()) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
        return ResolvedAsset(
            remoteURL: remoteURL,
            filename: filename,
            metadata: DownloadMetadata.clean(value.metadata ?? [:]),
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders
        )
    }

    private func resolveStreamAsset(
        _ value: RunnerAsset,
        title: String,
        metadata: [String: String],
        sourceURL: URL,
        plugin: PythonScriptPlugin,
        downloader: PythonDownloaderDescriptor,
        streamIndex: Int
    ) async throws -> ResolvedDownload {
        guard let stream = value.stream else {
            throw PythonScriptBridgeError.invalidResponse("missing stream descriptor")
        }
        guard stream.type.lowercased() == "m3u8" else {
            throw PythonScriptBridgeError.scriptFailed(
                "unsupported Python stream type: \(stream.type)"
            )
        }
        if stream.hasTransforms,
           stream.hasDecorator != true,
           stream.hasAlter != true {
            throw PythonScriptBridgeError.scriptFailed(
                "M3u8_stream contains an unsupported Python transform callback."
            )
        }
        guard let playlistURL = URL(string: value.url),
              let scheme = playlistURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw PythonScriptBridgeError.invalidScript("Unsupported stream URL: \(value.url)")
        }

        let headerFields = Self.validHeaders(value.headers ?? [:])
        let referer = Self.cleanHeaderValue(value.referer)
            ?? headerFields.firstValue(caseInsensitiveKey: "Referer")
            ?? sourceURL.absoluteString
        let userAgent = Self.cleanHeaderValue(value.userAgent)
            ?? headerFields.firstValue(caseInsensitiveKey: "User-Agent")
        let additionalHeaders = headerFields.filter {
            !["referer", "user-agent"].contains($0.key.lowercased())
        }
        let requestOptions = HTTPRequestOptions(referer: referer, userAgent: userAgent)
        let preferredResolution = stream.preferredResolution?.trimmed ?? ""
        let segmentReferer = Self.cleanHeaderValue(stream.segmentReferer) ?? referer
        let customSegmentURLs = try Self.customSegmentURLs(stream, playlistURL: playlistURL)
        let hls: ResolvedDownload
        if customSegmentURLs.isEmpty {
            hls = try await M3U8Resolver().resolve(
                playlistURL,
                headers: requestOptions,
                preferredResolution: preferredResolution,
                additionalHeaders: additionalHeaders,
                segmentReferer: segmentReferer
            )
        } else {
            hls = try M3U8Resolver().resolveCustomSegments(
                customSegmentURLs,
                playlistURL: playlistURL,
                titleHint: title,
                headers: requestOptions,
                additionalHeaders: additionalHeaders,
                segmentReferer: segmentReferer,
                live: stream.live
            )
        }

        var streamAssets = hls.assets
        var hlsMetadata = hls.metadata
        if stream.hasAlter == true {
            streamAssets = try await alteredStreamAssets(
                streamAssets,
                plugin: plugin,
                downloader: downloader,
                sourceURL: sourceURL,
                streamIndex: streamIndex
            )
            let segmentCount = streamAssets.filter { $0.metadata["type"] == "hls_segment" }.count
            hlsMetadata["media_count"] = String(streamAssets.count)
            hlsMetadata["segment_count"] = String(segmentCount)
            hlsMetadata["total_segments"] = String(segmentCount)
            hlsMetadata["python_altered_segments"] = "true"
        }

        let additionalStreams = stream.additionalStreams ?? []
        if !additionalStreams.isEmpty {
            var groups = [streamAssets]
            for (index, additional) in additionalStreams.enumerated() {
                groups.append(try await resolveAdditionalFFmpegStream(
                    additional,
                    title: "\(title) part \(index + 2)",
                    sourceURL: sourceURL
                ))
            }
            streamAssets = groups.enumerated().flatMap { groupIndex, assets in
                assets.enumerated().map { assetIndex, asset in
                    var copy = asset
                    let originalExtension = URL(fileURLWithPath: asset.filename).pathExtension.trimmed
                    let remoteExtension = asset.remoteURL.pathExtension.trimmed
                    let fileExtension = originalExtension.isEmpty
                        ? (remoteExtension.isEmpty ? "ts" : remoteExtension)
                        : originalExtension
                    copy.filename = String(
                        format: "stream-%03d-%06d.%@",
                        groupIndex,
                        assetIndex,
                        fileExtension
                    ).sanitizedFilename()
                    copy.metadata["python_stream_sequence_index"] = String(groupIndex)
                    copy.metadata["python_stream_sequence_item_index"] = String(assetIndex)
                    return copy
                }
            }
            let segmentCount = streamAssets.filter { $0.metadata["type"] == "hls_segment" }.count
            hlsMetadata["media_count"] = String(streamAssets.count)
            hlsMetadata["segment_count"] = String(segmentCount)
            hlsMetadata["total_segments"] = String(segmentCount)
            hlsMetadata["python_stream_additional_count"] = String(additionalStreams.count)
            hlsMetadata["python_stream_sequence_count"] = String(groups.count)
            hlsMetadata["original_contract"] = "ffmpeg-stream-add-improved"
        }

        let decorator = stream.hasDecorator == true
            ? PythonSegmentDecorator(
                scriptPath: plugin.scriptPath,
                scriptSHA256: plugin.digest,
                sourceURL: sourceURL.absoluteString,
                downloaderClass: downloader.className,
                streamIndex: streamIndex
            )
            : nil
        let streamMetadata = DownloadMetadata.clean(value.metadata ?? [:])
        let assets = streamAssets.map { asset in
            var copy = asset
            copy.metadata = DownloadMetadata.clean(
                asset.metadata.merging(streamMetadata) { _, streamValue in streamValue }
            )
            if copy.metadata["type"] == "hls_segment" {
                copy.pythonSegmentDecorator = decorator
            }
            return copy
        }
        var mergedMetadata = hlsMetadata
        for (key, metadataValue) in streamMetadata {
            mergedMetadata[key] = metadataValue
        }
        for (key, metadataValue) in metadata {
            mergedMetadata[key] = metadataValue
        }
        mergedMetadata["type"] = "hls"
        mergedMetadata["format"] = "m3u8"
        mergedMetadata["handler"] = "python-script"
        mergedMetadata["python_stream"] = "m3u8"
        mergedMetadata["python_downloader_type"] = metadata["type"]
        mergedMetadata["python_requested_filename"] = value.filename
        mergedMetadata["source_url"] = sourceURL.absoluteString
        mergedMetadata["page_url"] = sourceURL.absoluteString
        if !customSegmentURLs.isEmpty {
            mergedMetadata["python_custom_segments"] = "true"
            mergedMetadata["python_custom_segment_count"] = String(customSegmentURLs.count)
        }
        if stream.hasDecorator == true {
            mergedMetadata["python_stream_decorator"] = "true"
        }
        if stream.hasAlter == true {
            mergedMetadata["python_stream_alter"] = "true"
        }
        if let postProcessing = stream.postProcessing {
            mergedMetadata["python_stream_post_processing"] = postProcessing ? "true" : "false"
        }
        if stream.live {
            mergedMetadata["live"] = "true"
            mergedMetadata["is_live"] = "true"
        }

        return ResolvedDownload(
            title: title,
            folderName: title,
            assets: assets,
            packageMode: .concatenate(
                outputFilename: Self.streamOutputFilename(requested: value.filename, title: title)
            ),
            metadata: DownloadMetadata.clean(mergedMetadata)
        )
    }

    private func resolveAdditionalFFmpegStream(
        _ value: RunnerAsset,
        title: String,
        sourceURL: URL
    ) async throws -> [ResolvedAsset] {
        guard let stream = value.stream else {
            throw PythonScriptBridgeError.invalidResponse("missing additional stream descriptor")
        }
        guard stream.type.lowercased() == "m3u8" else {
            throw PythonScriptBridgeError.scriptFailed(
                "unsupported additional Python stream type: \(stream.type)"
            )
        }
        if stream.hasTransforms {
            throw PythonScriptBridgeError.scriptFailed(
                "Additional ffmpeg.Stream callbacks cannot be serialized independently."
            )
        }
        if !(stream.additionalStreams ?? []).isEmpty {
            throw PythonScriptBridgeError.invalidResponse(
                "additional ffmpeg.Stream descriptors must be flattened"
            )
        }
        guard let playlistURL = URL(string: value.url),
              let scheme = playlistURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw PythonScriptBridgeError.invalidScript(
                "Unsupported additional stream URL: \(value.url)"
            )
        }

        let headerFields = Self.validHeaders(value.headers ?? [:])
        let referer = Self.cleanHeaderValue(value.referer)
            ?? headerFields.firstValue(caseInsensitiveKey: "Referer")
            ?? sourceURL.absoluteString
        let userAgent = Self.cleanHeaderValue(value.userAgent)
            ?? headerFields.firstValue(caseInsensitiveKey: "User-Agent")
        let additionalHeaders = headerFields.filter {
            !["referer", "user-agent"].contains($0.key.lowercased())
        }
        let requestOptions = HTTPRequestOptions(referer: referer, userAgent: userAgent)
        let segmentReferer = Self.cleanHeaderValue(stream.segmentReferer) ?? referer
        let customSegmentURLs = try Self.customSegmentURLs(stream, playlistURL: playlistURL)
        let resolved: ResolvedDownload
        if customSegmentURLs.isEmpty {
            resolved = try await M3U8Resolver().resolve(
                playlistURL,
                headers: requestOptions,
                preferredResolution: stream.preferredResolution?.trimmed ?? "",
                additionalHeaders: additionalHeaders,
                segmentReferer: segmentReferer
            )
        } else {
            resolved = try M3U8Resolver().resolveCustomSegments(
                customSegmentURLs,
                playlistURL: playlistURL,
                titleHint: title,
                headers: requestOptions,
                additionalHeaders: additionalHeaders,
                segmentReferer: segmentReferer,
                live: stream.live
            )
        }

        let streamMetadata = DownloadMetadata.clean(value.metadata ?? [:])
        return resolved.assets.map { asset in
            var copy = asset
            copy.metadata = DownloadMetadata.clean(
                asset.metadata.merging(streamMetadata) { _, streamValue in streamValue }
            )
            return copy
        }
    }

    private static func customSegmentURLs(
        _ stream: RunnerStreamDescriptor,
        playlistURL: URL
    ) throws -> [URL] {
        let values = stream.customURLs ?? []
        if stream.customURLCount > 0, values.count != stream.customURLCount {
            throw PythonScriptBridgeError.invalidResponse(
                "custom stream URL count does not match the serialized URL list"
            )
        }
        let baseURL = stream.baseURL
            .flatMap { URL(string: $0.trimmed) }
            ?? playlistURL
        return try values.enumerated().map { index, value in
            guard let url = URL(string: value, relativeTo: baseURL)?.absoluteURL,
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                throw PythonScriptBridgeError.invalidScript(
                    "Unsupported custom stream URL at item \(index + 1): \(value)"
                )
            }
            return url
        }
    }

    private func alteredStreamAssets(
        _ assets: [ResolvedAsset],
        plugin: PythonScriptPlugin,
        downloader: PythonDownloaderDescriptor,
        sourceURL: URL,
        streamIndex: Int
    ) async throws -> [ResolvedAsset] {
        let mediaAssets = assets.filter { $0.metadata["type"] == "hls_segment" }
        guard !mediaAssets.isEmpty else {
            throw PythonScriptBridgeError.scriptFailed("M3u8_stream alter has no media segments to process.")
        }
        let segments = mediaAssets.enumerated().map { index, asset in
            var headers = asset.additionalHeaderFields
            headers["Referer"] = asset.referer
            headers["User-Agent"] = asset.userAgent
            return RunnerAlterSegmentRequest(
                sourceIndex: index,
                url: asset.remoteURL.absoluteString,
                headers: headers,
                keyURL: asset.decryption?.keyURL.absoluteString,
                keyIV: asset.decryption?.iv.base64EncodedString(),
                ignoreError: asset.metadata["python_ignore_error"] == "true"
            )
        }
        let request = RunnerRequest(
            action: "stream_alter",
            scriptPath: plugin.scriptPath,
            sourceURL: sourceURL.absoluteString,
            className: downloader.className,
            requestHeaders: nil,
            maxAssets: nil,
            streamIndex: streamIndex,
            segments: segments
        )
        let response = try await run(request, scriptDirectory: plugin.scriptURL.deletingLastPathComponent())
        guard response.sha256 == nil || response.sha256 == plugin.digest else {
            throw PythonScriptBridgeError.invalidScript("The installed script changed while altering stream segments.")
        }
        guard let altered = response.alteredSegments else {
            throw PythonScriptBridgeError.invalidResponse("missing altered segment result")
        }
        guard altered.allSatisfy({ mediaAssets.indices.contains($0.sourceIndex) }) else {
            throw PythonScriptBridgeError.invalidResponse("alter returned an invalid source segment index")
        }

        var result: [ResolvedAsset] = []
        var mediaIndex = 0
        for asset in assets {
            guard asset.metadata["type"] == "hls_segment" else {
                result.append(asset)
                continue
            }
            for value in altered where value.sourceIndex == mediaIndex {
                result.append(try Self.resolvedAlteredSegment(value, source: asset))
            }
            mediaIndex += 1
        }
        guard result.contains(where: { $0.metadata["type"] == "hls_segment" }) else {
            throw PythonScriptBridgeError.scriptFailed("M3u8_stream alter removed every media segment.")
        }
        return Self.reindexedHLSAssets(result)
    }

    private static func resolvedAlteredSegment(
        _ value: RunnerAlteredSegment,
        source: ResolvedAsset
    ) throws -> ResolvedAsset {
        guard let remoteURL = URL(string: value.url),
              let scheme = remoteURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw PythonScriptBridgeError.invalidScript("alter returned an unsupported segment URL: \(value.url)")
        }
        let headerFields = validHeaders(value.headers ?? [:])
        let referer = cleanHeaderValue(headerFields.firstValue(caseInsensitiveKey: "Referer"))
            ?? source.referer
        let userAgent = cleanHeaderValue(headerFields.firstValue(caseInsensitiveKey: "User-Agent"))
            ?? source.userAgent
        let additionalHeaders = headerFields
            .filter { !["referer", "user-agent"].contains($0.key.lowercased()) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }

        let decryption: SegmentDecryption?
        if value.hasKey {
            let keyURL = value.keyURL.flatMap(URL.init(string:)) ?? source.decryption?.keyURL
            let iv = value.keyIV.flatMap { Data(base64Encoded: $0) } ?? source.decryption?.iv
            guard let keyURL, ["http", "https"].contains(keyURL.scheme?.lowercased() ?? ""),
                  let iv, iv.count == 16 else {
                throw PythonScriptBridgeError.invalidResponse("alter returned incomplete AES-128 key information")
            }
            decryption = SegmentDecryption(keyURL: keyURL, iv: iv)
        } else {
            decryption = nil
        }

        var assetMetadata = source.metadata
        assetMetadata["media_url"] = remoteURL.absoluteString
        assetMetadata["video_url"] = remoteURL.absoluteString
        assetMetadata["source_url"] = remoteURL.absoluteString
        assetMetadata["python_altered_segment"] = "true"
        assetMetadata["python_alter_source_index"] = String(value.sourceIndex)
        if value.ignoreError == true {
            assetMetadata["python_ignore_error"] = "true"
        } else {
            assetMetadata.removeValue(forKey: "python_ignore_error")
        }
        return ResolvedAsset(
            remoteURL: remoteURL,
            filename: source.filename,
            metadata: DownloadMetadata.clean(assetMetadata),
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders,
            decryption: decryption,
            xorKey: source.xorKey,
            pixivGridShuffle: source.pixivGridShuffle,
            pixivUgoiraPackage: source.pixivUgoiraPackage,
            lezhinImageShuffle: source.lezhinImageShuffle,
            pythonSegmentDecorator: source.pythonSegmentDecorator
        )
    }

    private static func reindexedHLSAssets(_ assets: [ResolvedAsset]) -> [ResolvedAsset] {
        let segmentTotal = assets.filter { $0.metadata["type"] == "hls_segment" }.count
        var segmentNumber = 0
        return assets.enumerated().map { index, asset in
            var copy = asset
            let isSegment = copy.metadata["type"] == "hls_segment"
            if isSegment {
                segmentNumber += 1
            }
            let ext = copy.remoteURL.pathExtension.trimmed.isEmpty
                ? ((copy.filename as NSString).pathExtension.trimmed.isEmpty ? "ts" : (copy.filename as NSString).pathExtension)
                : copy.remoteURL.pathExtension.lowercased()
            copy.filename = isSegment
                ? String(format: "%06d.%@", index, ext).sanitizedFilename()
                : String(format: "%06d-map.%@", index, ext).sanitizedFilename()
            copy.metadata["page"] = String(index + 1)
            copy.metadata["position"] = String(index + 1)
            copy.metadata["segment_index"] = String(index)
            if isSegment {
                copy.metadata["segment_number"] = String(segmentNumber)
                copy.metadata["segment_total"] = String(segmentTotal)
                copy.metadata["total_segments"] = String(segmentTotal)
            }
            return copy
        }
    }

    func decorateSegments(_ paths: [URL], using decorator: PythonSegmentDecorator) async throws {
        guard !paths.isEmpty else { return }
        let scriptURL = URL(fileURLWithPath: decorator.scriptPath)
        let request = RunnerRequest(
            action: "stream_decorate",
            scriptPath: decorator.scriptPath,
            sourceURL: decorator.sourceURL,
            className: decorator.downloaderClass,
            requestHeaders: nil,
            maxAssets: nil,
            streamIndex: decorator.streamIndex,
            segmentPaths: paths.map(\.path)
        )
        let response = try await run(request, scriptDirectory: scriptURL.deletingLastPathComponent())
        guard response.sha256 == nil || response.sha256 == decorator.scriptSHA256 else {
            throw PythonScriptBridgeError.invalidScript("The installed script changed while decorating stream segments.")
        }
        guard response.transformedCount == paths.count else {
            throw PythonScriptBridgeError.invalidResponse("decorated segment count does not match the request")
        }
    }

    func runHooks(
        plugin: PythonScriptPlugin,
        event: PythonHookEvent,
        names: [String],
        context: PythonHookContext
    ) async throws -> PythonHookExecutionResult {
        guard !names.isEmpty else {
            return PythonHookExecutionResult(context: context, logs: "")
        }
        let request = RunnerRequest(
            action: "hook",
            scriptPath: plugin.scriptPath,
            sourceURL: nil,
            className: nil,
            requestHeaders: nil,
            maxAssets: nil,
            hookEvent: event.rawValue,
            hookNames: names,
            hookContext: context
        )
        let response = try await run(request, scriptDirectory: plugin.scriptURL.deletingLastPathComponent())
        guard response.sha256 == nil || response.sha256 == plugin.digest else {
            throw PythonScriptBridgeError.invalidScript("The installed hook script changed. Reload it before downloading.")
        }
        guard let result = response.hookContext else {
            throw PythonScriptBridgeError.invalidResponse("missing hook context")
        }
        guard result.valid else {
            throw PythonScriptBridgeError.scriptFailed("hook marked the task invalid")
        }
        return PythonHookExecutionResult(context: result, logs: response.logs ?? "")
    }

    static func hookContext(
        job: DownloadJob,
        sourceURL: URL? = nil,
        resolved: ResolvedDownload? = nil,
        names: [String] = []
    ) -> PythonHookContext {
        let metadata = DownloadMetadata.clean(
            job.metadata.merging(resolved?.metadata ?? [:]) { _, resolvedValue in resolvedValue }
        )
        return PythonHookContext(
            sourceURL: sourceURL?.absoluteString ?? job.source,
            title: resolved?.title ?? job.title,
            artist: metadata["artist"] ?? metadata["author"],
            type: metadata["type"] ?? job.metadata["type"],
            status: job.status.rawValue,
            outputPath: job.outputPath,
            metadata: DownloadMetadata.clean(metadata),
            assets: resolved?.assets.map(PythonHookAssetContext.init) ?? [],
            names: names,
            total: resolved?.assets.count ?? job.total,
            completed: job.completed,
            errorMessage: job.metadata["last_error"],
            valid: true,
            single: metadata["python_single"] == "true"
        )
    }

    static func resolvedDownload(
        _ original: ResolvedDownload,
        applying context: PythonHookContext
    ) throws -> ResolvedDownload {
        let locksAssetCount: Bool
        switch original.packageMode {
        case .grouped, .groupedMedia:
            locksAssetCount = true
        case .files, .concatenate, .mux:
            locksAssetCount = false
        }
        if locksAssetCount, context.assets.count != original.assets.count {
            throw PythonScriptBridgeError.invalidScript(
                "Hooks cannot change the asset count of a grouped stream download."
            )
        }
        var usedNames: [String: Int] = [:]
        let assets = try context.assets.enumerated().map { index, value in
            guard let remoteURL = URL(string: value.url),
                  let scheme = remoteURL.scheme?.lowercased(),
                  ["http", "https", "file"].contains(scheme) else {
                throw PythonScriptBridgeError.invalidScript("Hook returned an unsupported asset URL at item \(index + 1).")
            }
            let old = original.assets.indices.contains(index) ? original.assets[index] : nil
            let filename = uniqueRelativeFilename(
                value.filename.trimmed.isEmpty ? defaultFilename(for: remoteURL, index: index) : value.filename,
                used: &usedNames
            )
            let headerFields = validHeaders(value.headers)
            let referer = cleanHeaderValue(value.referer)
                ?? headerFields.firstValue(caseInsensitiveKey: "Referer")
            let userAgent = cleanHeaderValue(value.userAgent)
                ?? headerFields.firstValue(caseInsensitiveKey: "User-Agent")
            let additionalHeaders = headerFields
                .filter { !["referer", "user-agent"].contains($0.key.lowercased()) }
                .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
                .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
            let preservesTransforms = old?.remoteURL == remoteURL
            return ResolvedAsset(
                remoteURL: remoteURL,
                filename: filename,
                metadata: DownloadMetadata.clean(value.metadata),
                referer: referer,
                userAgent: userAgent,
                additionalHeaders: additionalHeaders,
                decryption: preservesTransforms ? old?.decryption : nil,
                xorKey: preservesTransforms ? old?.xorKey : nil,
                pixivGridShuffle: preservesTransforms ? old?.pixivGridShuffle : nil,
                pixivUgoiraPackage: preservesTransforms ? old?.pixivUgoiraPackage : nil,
                lezhinImageShuffle: preservesTransforms ? old?.lezhinImageShuffle : nil,
                pythonSegmentDecorator: preservesTransforms ? old?.pythonSegmentDecorator : nil
            )
        }
        let title = context.title.trimmed.isEmpty ? original.title : context.title.trimmed
        let folderName = original.folderName == original.title ? title : original.folderName
        return ResolvedDownload(
            title: title,
            folderName: folderName,
            assets: assets,
            packageMode: original.packageMode,
            metadata: DownloadMetadata.clean(context.metadata),
            textMergePlan: original.textMergePlan,
            temporaryAssetDirectories: original.temporaryAssetDirectories
        )
    }

    static func staticMetadata(at scriptURL: URL) throws -> PythonScriptStaticMetadata {
        let values = try scriptURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else {
            throw PythonScriptBridgeError.invalidScript("Choose a .hds or .py script file.")
        }
        let fileSize = values.fileSize ?? 0
        guard fileSize <= maximumScriptSize else {
            throw PythonScriptBridgeError.invalidScript("Script exceeds the 128 MiB limit.")
        }
        let ext = scriptURL.pathExtension.lowercased()
        guard ext == "hds" || ext == "py" else {
            throw PythonScriptBridgeError.invalidScript("Only .hds and .py scripts are supported.")
        }
        let data = try Data(contentsOf: scriptURL, options: [.mappedIfSafe])
        let decoded = try decodeScript(data)
        var titles: [String: String] = [:]
        var author = ""
        var comments: [String] = []
        var signature = ""

        for line in decoded.text.components(separatedBy: .newlines).prefix(300) {
            let trimmed = line.trimmed
            guard trimmed.hasPrefix("#") else { continue }
            let content = String(trimmed.dropFirst()).trimmed
            guard let separator = content.firstIndex(of: ":") else { continue }
            let key = String(content[..<separator]).trimmed.lowercased()
            let value = String(content[content.index(after: separator)...]).trimmed
            guard !value.isEmpty else { continue }
            if key == "title" || key.hasPrefix("title_") {
                titles[key] = value
            } else if key == "author" {
                author = value
            } else if key == "comment" {
                comments.append(value)
            } else if key == "sign" {
                signature = value
            }
        }

        let language = Locale.current.language.languageCode?.identifier.lowercased() ?? ""
        let localizedTitle = titles["title_\(language)"]
            ?? titles["title"]
            ?? titles.sorted(by: { $0.key < $1.key }).first?.value
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return PythonScriptStaticMetadata(
            title: localizedTitle ?? scriptURL.deletingPathExtension().lastPathComponent,
            author: author,
            comment: comments.joined(separator: "\n"),
            signature: signature,
            encoding: decoded.encoding,
            digest: digest,
            byteCount: data.count
        )
    }

    static func pythonExecutableURL(
        configuredPath: String = "",
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let candidates = [
            configuredPath,
            environment["HITOMI_NATIVE_PYTHON"] ?? "",
            "/usr/bin/python3",
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3"
        ]
        for rawPath in candidates {
            let path = ExternalToolSettings.normalizedExecutablePath(rawPath, environment: environment)
            guard !path.isEmpty else { continue }
            if fileManager.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        for directory in (environment["PATH"] ?? "").components(separatedBy: ":") where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory).appendingPathComponent("python3")
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    static func runnerURL(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        if let override = environment["HITOMI_NATIVE_PYTHON_RUNNER"]?.trimmed, !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        if let bundled = Bundle.main.url(
            forResource: "hitomi_compat_runner",
            withExtension: "py",
            subdirectory: "Python"
        ), fileManager.fileExists(atPath: bundled.path) {
            return bundled
        }
        return nil
    }

    private func run(_ request: RunnerRequest, scriptDirectory: URL) async throws -> RunnerResponse {
        guard let python = Self.pythonExecutableURL(configuredPath: configuredPythonPath) else {
            throw PythonScriptBridgeError.runtimeUnavailable
        }
        guard let runner = Self.runnerURL() else {
            throw PythonScriptBridgeError.runnerUnavailable
        }
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-Python-\(UUID().uuidString)", isDirectory: true)
        try AppPaths.ensureDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let requestURL = directory.appendingPathComponent("request.json")
        let stdoutURL = directory.appendingPathComponent("stdout.log")
        let logURL = directory.appendingPathComponent("stderr.log")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try encoder.encode(request).write(to: requestURL, options: .atomic)

        var runnerEnvironment = [
            "PYTHONIOENCODING": "utf-8",
            "PYTHONDONTWRITEBYTECODE": "1"
        ]
        if let ytdlp = ExternalToolSettings.executableURL(
            kind: .ytdlp,
            environmentKey: "HITOMI_NATIVE_YTDLP",
            executableName: "yt-dlp",
            knownPaths: [
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp",
                "/usr/bin/yt-dlp"
            ]
        ) {
            runnerEnvironment["HITOMI_NATIVE_YTDLP"] = ytdlp.path
        }
        if let ffmpeg = ExternalToolSettings.executableURL(
            kind: .ffmpeg,
            environmentKey: "HITOMI_NATIVE_FFMPEG",
            executableName: "ffmpeg",
            knownPaths: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ]
        ) {
            runnerEnvironment["HITOMI_NATIVE_FFMPEG"] = ffmpeg.path
            let ffprobe = ffmpeg.deletingLastPathComponent().appendingPathComponent("ffprobe")
            if FileManager.default.isExecutableFile(atPath: ffprobe.path) {
                runnerEnvironment["HITOMI_NATIVE_FFPROBE"] = ffprobe.path
            }
        }
        if let renderer = try? await PythonWebRendererService.shared.connectionInfo() {
            runnerEnvironment["HITOMI_NATIVE_RENDER_ENDPOINT"] = renderer.endpoint
            runnerEnvironment["HITOMI_NATIVE_DOWNLOAD_ENDPOINT"] = renderer.downloadEndpoint
            runnerEnvironment["HITOMI_NATIVE_RENDER_TOKEN"] = renderer.token
        }

        try await ExternalProcessRunner.run(
            executable: python,
            arguments: [runner.path, "--request", requestURL.path],
            logURL: logURL,
            stdoutURL: stdoutURL,
            currentDirectoryURL: scriptDirectory,
            environment: runnerEnvironment,
            failureDescription: "Python script"
        )

        let outputSize = (try? stdoutURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard outputSize <= Self.maximumRunnerOutputSize else {
            throw PythonScriptBridgeError.invalidResponse("output exceeded 64 MiB")
        }
        let output = String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self)
        guard let line = output.components(separatedBy: .newlines).last(where: { $0.hasPrefix(Self.resultPrefix) }) else {
            let stderr = (try? String(contentsOf: logURL, encoding: .utf8))?.trimmed ?? ""
            throw PythonScriptBridgeError.invalidResponse(stderr.isEmpty ? "result marker not found" : stderr)
        }
        let encoded = String(line.dropFirst(Self.resultPrefix.count))
        guard let data = Data(base64Encoded: encoded) else {
            throw PythonScriptBridgeError.invalidResponse("result payload is not base64")
        }
        let response: RunnerResponse
        do {
            response = try JSONDecoder().decode(RunnerResponse.self, from: data)
        } catch {
            throw PythonScriptBridgeError.invalidResponse(error.localizedDescription)
        }
        guard response.ok else {
            if response.errorKind?.trimmed == "NativeOwnedFeature" {
                let feature = response.errorDetails?.feature?.value.trimmed
                let description = feature?.isEmpty == false
                    ? feature ?? "native resolver feature"
                    : Self.runnerFailureDescription(response)
                throw PythonScriptBridgeError.nativeDelegation(description)
            }
            if response.errorKind?.trimmed == "Disgusting" {
                throw PythonScriptBridgeError.taskReaction(
                    name: JobDisplayReaction.disgusting.rawValue,
                    message: Self.runnerFailureDescription(response)
                )
            }
            if response.errorKind?.trimmed == "Retry" {
                throw PythonScriptBridgeError.retryRequested(
                    status: response.errorDetails?.status?.value.trimmed ?? "wait",
                    message: Self.runnerFailureDescription(response)
                )
            }
            throw PythonScriptBridgeError.scriptFailed(Self.runnerFailureDescription(response))
        }
        return response
    }

    private static func runnerFailureDescription(_ response: RunnerResponse) -> String {
        let fallback = response.error?.trimmed.isEmpty == false ? response.error! : "unknown error"
        switch response.errorKind?.trimmed {
        case "LoginRequired":
            let method = response.errorDetails?.method?.value.trimmed ?? "cookies"
            let url = response.errorDetails?.url?.value.trimmed ?? ""
            return url.isEmpty
                ? "Login is required (method: \(method))."
                : "Login is required for \(url) (method: \(method))."
        case "BrowserRequired":
            return "This script requires browser authentication, but no compatible browser session is available."
        case "OutdatedExtension":
            return "The Python script extension is outdated and must be updated."
        case "Retry":
            let status = response.errorDetails?.status?.value.trimmed ?? "wait"
            return "The Python script requested a retry (status: \(status))."
        case "StopReading":
            return "The Python script stopped reading the task."
        case "Disgusting":
            let prefix = "Disgusting:"
            let message = fallback.hasPrefix(prefix)
                ? String(fallback.dropFirst(prefix.count)).trimmed
                : fallback
            return message.isEmpty ? "The Python script rejected this task." : message
        default:
            return fallback
        }
    }

    private static func decodeScript(_ data: Data) throws -> (text: String, encoding: String) {
        let candidates: [(String.Encoding, String)] = [
            (.utf8, "UTF-8"),
            (.utf16, "UTF-16"),
            (.shiftJIS, "Shift JIS"),
            (.windowsCP1252, "Windows-1252"),
            (.isoLatin1, "ISO-8859-1")
        ]
        for candidate in candidates {
            if let value = String(data: data, encoding: candidate.0) {
                return (value, candidate.1)
            }
        }
        throw PythonScriptBridgeError.invalidScript("Script encoding could not be detected.")
    }

    private static func defaultFilename(for url: URL, index: Int) -> String {
        let name = url.lastPathComponent.removingPercentEncoding?.trimmed ?? ""
        return name.isEmpty ? String(format: "%04d.bin", index + 1) : name.sanitizedFilename()
    }

    private static func streamOutputFilename(requested: String, title: String) -> String {
        let requestedName = (requested as NSString).lastPathComponent.trimmed
        let source = requestedName.isEmpty ? title : requestedName
        let stem = (source as NSString).deletingPathExtension.trimmed
        return "\(stem.isEmpty ? "stream" : stem).ts".sanitizedFilename()
    }

    private static func uniqueRelativeFilename(_ value: String, used: inout [String: Int]) -> String {
        let normalized = value.sanitizedRelativePath()
        let key = normalized.lowercased()
        let occurrence = (used[key] ?? 0) + 1
        used[key] = occurrence
        guard occurrence > 1 else { return normalized }
        let path = normalized as NSString
        let ext = path.pathExtension
        let base = path.deletingPathExtension
        return ext.isEmpty ? "\(base) \(occurrence)" : "\(base) \(occurrence).\(ext)"
    }

    private static func cleanHeaderValue(_ value: String?) -> String? {
        guard let value = value?.trimmed, !value.isEmpty,
              !value.contains("\r"), !value.contains("\n") else { return nil }
        return value
    }

    private static func validHeaders(_ headers: [String: String]) -> [String: String] {
        headers.reduce(into: [String: String]()) { result, pair in
            let name = pair.key.trimmed
            guard name.range(of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#, options: .regularExpression) != nil,
                  let value = cleanHeaderValue(pair.value) else { return }
            result[name] = value
        }
    }
}

enum PythonScriptPluginStore {
    static func load(from directory: URL = AppPaths.pythonPluginDirectory) -> [PythonScriptPlugin] {
        let fileManager = FileManager.default
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return files
            .filter { ["hds", "py"].contains($0.pathExtension.lowercased()) }
            .compactMap { scriptURL -> PythonScriptPlugin? in
                let metadata = try? PythonScriptBridge.staticMetadata(at: scriptURL)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                if let data = try? Data(contentsOf: sidecarURL(for: scriptURL)),
                   var plugin = try? decoder.decode(PythonScriptPlugin.self, from: data),
                   let metadata,
                   plugin.digest == metadata.digest {
                    plugin.scriptPath = scriptURL.path
                    plugin.isSession = false
                    return plugin
                }
                guard let metadata else { return nil }
                return PythonScriptPlugin(
                    digest: metadata.digest,
                    scriptPath: scriptURL.path,
                    title: metadata.title,
                    author: metadata.author,
                    comment: metadata.comment,
                    signature: metadata.signature,
                    encoding: metadata.encoding,
                    downloaders: [],
                    hooks: [],
                    themes: [],
                    isEnabled: false,
                    isSession: false,
                    importedAt: Date(),
                    lastError: "Reload to inspect this script"
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }

    static func save(_ plugin: PythonScriptPlugin) throws {
        guard !plugin.isSession else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(plugin).write(to: sidecarURL(for: plugin.scriptURL), options: .atomic)
    }

    static func remove(_ plugin: PythonScriptPlugin) throws {
        try? FileManager.default.removeItem(at: sidecarURL(for: plugin.scriptURL))
        if FileManager.default.fileExists(atPath: plugin.scriptPath) {
            try FileManager.default.removeItem(at: plugin.scriptURL)
        }
    }

    static func sidecarURL(for scriptURL: URL) -> URL {
        scriptURL.appendingPathExtension("hitominative.json")
    }
}

private struct RunnerRequest: Encodable {
    var action: String
    var scriptPath: String
    var sourceURL: String?
    var className: String?
    var requestHeaders: [String: String]?
    var maxAssets: Int?
    var streamIndex: Int? = nil
    var segments: [RunnerAlterSegmentRequest]? = nil
    var segmentPaths: [String]? = nil
    var hookEvent: String? = nil
    var hookNames: [String]? = nil
    var hookContext: PythonHookContext? = nil
}

private struct RunnerResponse: Decodable {
    var ok: Bool
    var error: String?
    var errorKind: String?
    var errorDetails: RunnerErrorDetails?
    var traceback: String?
    var encoding: String?
    var sha256: String?
    var downloaders: [PythonDownloaderDescriptor]?
    var hooks: [PythonHookDescriptor]?
    var themes: [PythonThemeDescriptor]?
    var selected: PythonDownloaderDescriptor?
    var result: RunnerDownloadResult?
    var alteredSegments: [RunnerAlteredSegment]?
    var transformedCount: Int?
    var hookContext: PythonHookContext?
    var logs: String?
}

private struct RunnerDownloadResult: Decodable {
    var title: String
    var artist: String?
    var sourceURL: String?
    var single: Bool
    var metadata: [String: String]?
    var assets: [RunnerAsset]
}

private struct RunnerAsset: Decodable {
    var url: String
    var filename: String
    var referer: String?
    var userAgent: String?
    var headers: [String: String]?
    var metadata: [String: String]?
    var stream: RunnerStreamDescriptor?
}

private struct RunnerStreamDescriptor: Decodable {
    var type: String
    var baseURL: String?
    var segmentReferer: String?
    var preferredResolution: String?
    var live: Bool
    var customURLCount: Int
    var customURLs: [String]?
    var hasDecorator: Bool?
    var hasAlter: Bool?
    var hasTransforms: Bool
    var postProcessing: Bool?
    var additionalStreams: [RunnerAsset]?
}

private struct RunnerAlterSegmentRequest: Encodable {
    var sourceIndex: Int
    var url: String
    var headers: [String: String]
    var keyURL: String?
    var keyIV: String?
    var ignoreError: Bool
}

private struct RunnerAlteredSegment: Decodable {
    var sourceIndex: Int
    var url: String
    var headers: [String: String]?
    var hasKey: Bool
    var keyURL: String?
    var keyIV: String?
    var ignoreError: Bool?
}

private struct RunnerErrorDetails: Decodable {
    var method: FlexibleString?
    var url: FlexibleString?
    var cookie: FlexibleBool?
    var w: FlexibleString?
    var h: FlexibleString?
    var fail: FlexibleBool?
    var status: FlexibleString?
    var feature: FlexibleString?
}

private extension Dictionary where Key == String, Value == String {
    func firstValue(caseInsensitiveKey key: String) -> String? {
        first { $0.key.caseInsensitiveCompare(key) == .orderedSame }?.value
    }
}
