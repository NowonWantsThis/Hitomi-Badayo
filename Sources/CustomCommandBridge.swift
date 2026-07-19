import Foundation

struct CustomCommandResult {
    let outputDirectory: URL
    let outputItems: [URL]
    var remoteAssets: [ResolvedAsset] = []
    var remoteVideoAssets: [ResolvedAsset] = []
    var remoteAudioAssets: [ResolvedAsset] = []
    var remotePackageMode: CustomCommandRemotePackageMode = .files
    var manifestTitle: String? = nil
    var manifestFolderName: String? = nil
    var manifestMetadata: [String: String] = [:]
}

enum CustomCommandRemotePackageMode: Equatable {
    case files
    case concatenate(outputFilename: String)
    case mux(outputFilename: String)

    var label: String {
        switch self {
        case .files:
            return "files"
        case .concatenate:
            return "concatenate"
        case .mux:
            return "mux"
        }
    }
}

final class CustomCommandBridge {
    private struct RemoteAssetDefaults {
        var baseURL: URL?
        var referer: String?
        var userAgent: String?
        var headers: [String: String]

        static let empty = RemoteAssetDefaults(baseURL: nil, referer: nil, userAgent: nil, headers: [:])

        func merged(with overrides: RemoteAssetDefaults) -> RemoteAssetDefaults {
            var mergedHeaders = headers
            for (key, value) in overrides.headers {
                mergedHeaders[key] = value
            }
            return RemoteAssetDefaults(
                baseURL: overrides.baseURL ?? baseURL,
                referer: overrides.referer ?? referer,
                userAgent: overrides.userAgent ?? userAgent,
                headers: mergedHeaders
            )
        }
    }

    private struct CommandManifest {
        var title: String?
        var folderName: String?
        var metadata: [String: String]
        var outputPaths: [String]?
        var remoteAssets: [ResolvedAsset]
        var remoteVideoAssets: [ResolvedAsset]
        var remoteAudioAssets: [ResolvedAsset]
        var remotePackageMode: CustomCommandRemotePackageMode
    }

    func run(url: URL, rule: SiteRule, root: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> CustomCommandResult {
        guard let template = rule.commandTemplate?.trimmed, !template.isEmpty else {
            throw NativeDownloadError.unsupported("Custom command is empty.")
        }
        guard template.contains("{url}") else {
            throw NativeDownloadError.unsupported("Custom command must include {url}.")
        }

        try AppPaths.ensureDirectory(root)

        let host = (url.host ?? "site").replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
        let baseName = rule.name.trimmed.isEmpty ? "\(host) command" : "\(rule.name) command"
        let outputDirectory = AppPaths.uniqueDirectoryURL(in: root, name: baseName)
        try AppPaths.ensureDirectory(outputDirectory)

        let arguments = try Self.splitArguments(template).map {
            Self.expand($0, url: url, host: host, outputDirectory: outputDirectory, headers: headers, rule: rule)
        }
        guard let command = arguments.first, !command.trimmed.isEmpty else {
            throw NativeDownloadError.unsupported("Custom command is empty.")
        }
        guard let executable = executableURL(for: command) else {
            throw NativeDownloadError.unsupported("Custom command executable was not found: \(command)")
        }

        let contextURL = outputDirectory.appendingPathComponent(".hitomi-native-context.json")
        let contextJSON = try Self.contextJSON(
            for: url,
            host: host,
            outputDirectory: outputDirectory,
            headers: headers,
            rule: rule
        )
        try Data(contextJSON.utf8).write(to: contextURL, options: .atomic)
        let environment = Self.environment(
            for: url,
            host: host,
            outputDirectory: outputDirectory,
            headers: headers,
            rule: rule,
            contextURL: contextURL,
            contextJSON: contextJSON
        )
        let logURL = outputDirectory.appendingPathComponent("custom-command.log")
        let stdoutURL = outputDirectory.appendingPathComponent(".hitomi-native-stdout.txt")
        let workingDirectory = try workingDirectory(
            for: rule,
            url: url,
            host: host,
            outputDirectory: outputDirectory,
            headers: headers
        )
        try await run(
            executable: executable,
            arguments: Array(arguments.dropFirst()),
            logURL: logURL,
            stdoutURL: stdoutURL,
            workingDirectory: workingDirectory,
            environment: environment
        )

        let manifest = try commandManifest(in: outputDirectory)
            ?? commandManifest(fromStandardOutput: stdoutURL, outputDirectory: outputDirectory)
        let items: [URL]
        if let outputPaths = manifest?.manifest.outputPaths {
            items = try manifestOutputItems(outputPaths, in: outputDirectory)
        } else {
            items = try outputItems(in: outputDirectory, excluding: [logURL, contextURL, stdoutURL] + Self.manifestURLs(in: outputDirectory))
        }
        let remoteAssets = manifest?.manifest.remoteAssets ?? []
        let remoteVideoAssets = manifest?.manifest.remoteVideoAssets ?? []
        let remoteAudioAssets = manifest?.manifest.remoteAudioAssets ?? []
        guard !items.isEmpty || !remoteAssets.isEmpty || !remoteVideoAssets.isEmpty || !remoteAudioAssets.isEmpty else {
            throw NativeDownloadError.unsupported("Custom command finished, but no output file was created.")
        }

        try? FileManager.default.removeItem(at: logURL)
        try? FileManager.default.removeItem(at: contextURL)
        try? FileManager.default.removeItem(at: stdoutURL)
        return CustomCommandResult(
            outputDirectory: outputDirectory,
            outputItems: items,
            remoteAssets: remoteAssets,
            remoteVideoAssets: remoteVideoAssets,
            remoteAudioAssets: remoteAudioAssets,
            remotePackageMode: manifest?.manifest.remotePackageMode ?? .files,
            manifestTitle: manifest?.manifest.title,
            manifestFolderName: manifest?.manifest.folderName,
            manifestMetadata: manifest?.manifest.metadata ?? [:]
        )
    }

    private func executableURL(for command: String) -> URL? {
        let fileManager = FileManager.default
        let expanded = (command as NSString).expandingTildeInPath

        if expanded.contains("/") {
            let url = URL(fileURLWithPath: expanded)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .components(separatedBy: ":")
            .filter { !$0.isEmpty }

        for folder in paths {
            let candidate = URL(fileURLWithPath: folder).appendingPathComponent(expanded)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private func run(
        executable: URL,
        arguments: [String],
        logURL: URL,
        stdoutURL: URL,
        workingDirectory: URL,
        environment: [String: String]
    ) async throws {
        try await ExternalProcessRunner.run(
            executable: executable,
            arguments: arguments,
            logURL: logURL,
            stdoutURL: stdoutURL,
            currentDirectoryURL: workingDirectory,
            environment: environment,
            failureDescription: "Custom command"
        )
    }

    private func workingDirectory(
        for rule: SiteRule,
        url: URL,
        host: String,
        outputDirectory: URL,
        headers: HTTPRequestOptions
    ) throws -> URL {
        guard let template = rule.workingDirectoryTemplate?.trimmed, !template.isEmpty else {
            return outputDirectory
        }

        let expanded = Self.expand(
            template,
            url: url,
            host: host,
            outputDirectory: outputDirectory,
            headers: headers,
            rule: rule
        )
        let expandedPath = (expanded as NSString).expandingTildeInPath
        let url = expandedPath.hasPrefix("/")
            ? URL(fileURLWithPath: expandedPath, isDirectory: true)
            : outputDirectory.appendingPathComponent(expandedPath, isDirectory: true)
        try AppPaths.ensureDirectory(url)
        return url
    }

    private func outputItems(in directory: URL, excluding excludedURLs: [URL]) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let excludedPaths = Set(excludedURLs.map { $0.standardizedFileURL.path })
        var items: [URL] = []
        for case let file as URL in enumerator {
            if excludedPaths.contains(file.standardizedFileURL.path) { continue }
            if file.lastPathComponent.hasSuffix(".part") { continue }
            let values = try? file.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                items.append(file)
            }
        }

        return items.sorted { $0.path < $1.path }
    }

    private func manifestOutputItems(_ paths: [String], in directory: URL) throws -> [URL] {
        let root = directory.resolvingSymlinksInPath()
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        var items: [URL] = []
        var seen = Set<String>()

        for rawPath in paths {
            let trimmed = rawPath.trimmed
            guard !trimmed.isEmpty else { continue }
            let candidate = trimmed.hasPrefix("/")
                ? URL(fileURLWithPath: trimmed)
                : directory.appendingPathComponent(trimmed)
            let resolved = candidate.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(rootPrefix), seen.insert(resolved.path).inserted else {
                continue
            }
            let values = try? resolved.resourceValues(forKeys: [.isRegularFileKey])
            if values?.isRegularFile == true {
                items.append(resolved)
            }
        }

        return items.sorted { $0.path < $1.path }
    }

    private func commandManifest(in directory: URL) throws -> (manifest: CommandManifest, url: URL)? {
        for url in Self.manifestURLs(in: directory) where FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                if let object = jsonObject as? [String: Any] {
                    return (Self.commandManifest(from: object), url)
                }
                if let array = jsonObject as? [Any] {
                    return (Self.commandManifest(fromEntries: array), url)
                }
                if let string = jsonObject as? String {
                    return (Self.commandManifest(fromLines: string), url)
                }
                throw NativeDownloadError.unsupported("Custom command manifest must be a JSON object, JSON array, JSON string, or line list.")
            }
            if let text = String(data: data, encoding: .utf8), !text.trimmed.isEmpty {
                return (Self.commandManifest(fromLines: text), url)
            }
            throw NativeDownloadError.unsupported("Custom command manifest is empty.")
        }
        return nil
    }

    private func commandManifest(fromStandardOutput stdoutURL: URL, outputDirectory: URL) throws -> (manifest: CommandManifest, url: URL)? {
        guard FileManager.default.fileExists(atPath: stdoutURL.path) else { return nil }
        let data = try Data(contentsOf: stdoutURL)
        guard let text = String(data: data, encoding: .utf8)?.trimmed, !text.isEmpty else { return nil }

        if let jsonObject = try? JSONSerialization.jsonObject(with: Data(text.utf8), options: [.fragmentsAllowed]) {
            if let object = jsonObject as? [String: Any] {
                return (Self.commandManifest(from: object), stdoutURL)
            }
            if let array = jsonObject as? [Any] {
                let manifest = Self.commandManifest(fromEntries: array)
                return stdoutManifestIsActionable(manifest, outputDirectory: outputDirectory) ? (manifest, stdoutURL) : nil
            }
            if let string = jsonObject as? String {
                let manifest = Self.commandManifest(fromLines: string)
                return stdoutManifestIsActionable(manifest, outputDirectory: outputDirectory) ? (manifest, stdoutURL) : nil
            }
            return nil
        }

        if let manifest = stdoutManifestFromJSONLine(text, outputDirectory: outputDirectory) {
            return (manifest, stdoutURL)
        }

        let manifest = Self.commandManifest(fromLines: text)
        return stdoutManifestIsActionable(manifest, outputDirectory: outputDirectory) ? (manifest, stdoutURL) : nil
    }

    private func stdoutManifestFromJSONLine(_ text: String, outputDirectory: URL) -> CommandManifest? {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(\.trimmed)
            .filter { !$0.isEmpty }

        for line in lines.reversed() {
            guard let payload = Self.stdoutManifestPayload(from: line),
                  let jsonObject = try? JSONSerialization.jsonObject(with: Data(payload.utf8), options: [.fragmentsAllowed]) else {
                continue
            }

            let manifest: CommandManifest
            let explicit: Bool
            if let object = jsonObject as? [String: Any] {
                manifest = Self.commandManifest(from: object)
                explicit = Self.stdoutObjectLooksLikeManifest(object)
            } else if let array = jsonObject as? [Any] {
                manifest = Self.commandManifest(fromEntries: array)
                explicit = false
            } else if let string = jsonObject as? String {
                manifest = Self.commandManifest(fromLines: string)
                explicit = false
            } else {
                continue
            }

            if explicit || stdoutManifestIsActionable(manifest, outputDirectory: outputDirectory) {
                return manifest
            }
        }
        return nil
    }

    private static func stdoutManifestPayload(from line: String) -> String? {
        let prefixes = [
            "HITOMI_NATIVE_MANIFEST:",
            "HITOMI_NATIVE_MANIFEST_JSON:",
            "HITOMI_NATIVE_MANIFEST=",
            "HITOMI_NATIVE_MANIFEST_JSON="
        ]
        for prefix in prefixes where line.hasPrefix(prefix) {
            let payload = String(line.dropFirst(prefix.count)).trimmed
            return payload.isEmpty ? nil : payload
        }
        guard line.hasPrefix("{") || line.hasPrefix("[") || line.hasPrefix("\"") else {
            return nil
        }
        return line
    }

    private static func stdoutObjectLooksLikeManifest(_ object: [String: Any]) -> Bool {
        let manifestKeys: Set<String> = [
            "title", "name", "folderName", "folder", "directory", "outputDirectory",
            "metadata", "files", "outputFiles", "outputs", "items",
            "assets", "downloads", "remoteAssets", "remoteFiles", "urls",
            "videoAssets", "videoFiles", "videos", "video",
            "audioAssets", "audioFiles", "audios", "audio",
            "packageMode", "mode", "outputFilename", "filename",
            "baseURL", "baseUrl", "headers", "referer", "userAgent"
        ]
        return object.keys.contains { manifestKeys.contains($0) }
    }

    private func stdoutManifestIsActionable(_ manifest: CommandManifest, outputDirectory: URL) -> Bool {
        if !manifest.remoteAssets.isEmpty || !manifest.remoteVideoAssets.isEmpty || !manifest.remoteAudioAssets.isEmpty {
            return true
        }
        guard let outputPaths = manifest.outputPaths, !outputPaths.isEmpty else { return false }
        return (try? manifestOutputItems(outputPaths, in: outputDirectory).isEmpty == false) ?? false
    }

    private static func manifestURLs(in directory: URL) -> [URL] {
        [
            "hitomi-native-manifest.json",
            ".hitomi-native-manifest.json",
            ".hitomi-native.json"
        ].map { directory.appendingPathComponent($0) }
    }

    private static func commandManifest(from object: [String: Any]) -> CommandManifest {
        let title = stringValue(object["title"] ?? object["name"])
        let folderName = stringValue(object["folderName"] ?? object["folder"] ?? object["directory"] ?? object["outputDirectory"])
        let metadataObject = object["metadata"] as? [String: Any] ?? [:]
        let metadata = metadataObject.reduce(into: [String: String]()) { result, pair in
            if let value = stringValue(pair.value), !value.trimmed.isEmpty {
                result[pair.key] = value
            }
        }
        let outputPaths = stringList(
            object["files"] ?? object["outputFiles"] ?? object["outputs"] ?? object["items"]
        )
        let assetDefaults = remoteAssetDefaults(from: object)
        let remoteAssets = Self.remoteAssets(
            from: object["assets"] ?? object["downloads"] ?? object["remoteAssets"] ?? object["remoteFiles"] ?? object["urls"],
            defaults: assetDefaults
        )
        let remoteVideoAssets = Self.remoteAssets(
            from: object["videoAssets"] ?? object["videoFiles"] ?? object["videos"] ?? object["video"],
            defaults: assetDefaults
        )
        let remoteAudioAssets = Self.remoteAssets(
            from: object["audioAssets"] ?? object["audioFiles"] ?? object["audios"] ?? object["audio"],
            defaults: assetDefaults
        )
        var remotePackageMode = remotePackageMode(from: object)
        if case .files = remotePackageMode,
           !remoteVideoAssets.isEmpty || !remoteAudioAssets.isEmpty {
            remotePackageMode = .mux(outputFilename: outputFilename(from: object, fallback: "manifest-output.mp4"))
        }

        return CommandManifest(
            title: title?.trimmed.isEmpty == false ? title : nil,
            folderName: folderName?.trimmed.isEmpty == false ? folderName : nil,
            metadata: metadata,
            outputPaths: outputPaths,
            remoteAssets: remoteAssets,
            remoteVideoAssets: remoteVideoAssets,
            remoteAudioAssets: remoteAudioAssets,
            remotePackageMode: remotePackageMode
        )
    }

    private static func commandManifest(fromEntries entries: [Any]) -> CommandManifest {
        let resolved = manifestEntries(from: entries, defaults: .empty)
        return CommandManifest(
            title: nil,
            folderName: nil,
            metadata: [:],
            outputPaths: resolved.outputPaths,
            remoteAssets: resolved.remoteAssets,
            remoteVideoAssets: [],
            remoteAudioAssets: [],
            remotePackageMode: .files
        )
    }

    private static func commandManifest(fromLines text: String) -> CommandManifest {
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")
            .map(\.trimmed)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
        return commandManifest(fromEntries: lines)
    }

    private static func manifestEntries(from entries: [Any], defaults: RemoteAssetDefaults) -> (outputPaths: [String], remoteAssets: [ResolvedAsset]) {
        var outputPaths: [String] = []
        var remoteAssetList: [ResolvedAsset] = []

        for (offset, entry) in entries.enumerated() {
            if let raw = entry as? String {
                if let asset = remoteAsset(from: raw, index: offset + 1, defaults: defaults) {
                    remoteAssetList.append(asset)
                } else {
                    let path = raw.trimmed
                    if !path.isEmpty {
                        outputPaths.append(path)
                    }
                }
                continue
            }

            if let object = entry as? [String: Any] {
                if let asset = remoteAsset(from: object, index: offset + 1, defaults: defaults) {
                    remoteAssetList.append(asset)
                    continue
                }

                let nestedDefaults = defaults.merged(with: remoteAssetDefaults(from: object))
                let nestedValue = object["items"] ?? object["assets"] ?? object["files"] ?? object["urls"] ?? object["downloads"]
                let nested = remoteAssets(from: nestedValue, defaults: nestedDefaults)
                if !nested.isEmpty {
                    remoteAssetList.append(contentsOf: nested)
                    continue
                }

                if let path = stringValue(object["path"] ?? object["file"] ?? object["filename"] ?? object["output"] ?? object["name"])?.trimmed,
                   !path.isEmpty {
                    outputPaths.append(path)
                }
                continue
            }

            if let nested = entry as? [Any] {
                let resolved = manifestEntries(from: nested, defaults: defaults)
                outputPaths.append(contentsOf: resolved.outputPaths)
                remoteAssetList.append(contentsOf: resolved.remoteAssets)
            }
        }

        var seenPaths = Set<String>()
        let uniqueOutputPaths = outputPaths.filter { seenPaths.insert($0).inserted }
        var seenAssets = Set<String>()
        let uniqueRemoteAssets = remoteAssetList.filter { asset in
            seenAssets.insert(URLIdentity.normalize(asset.remoteURL.absoluteString)).inserted
        }
        return (uniqueOutputPaths, uniqueRemoteAssets)
    }

    private static func remotePackageMode(from object: [String: Any]) -> CustomCommandRemotePackageMode {
        let rawMode = stringValue(object["packageMode"] ?? object["mode"] ?? object["package"] ?? object["remotePackageMode"])?
            .trimmed
            .lowercased() ?? ""
        if ["mux", "merge", "av", "audio-video", "video-audio", "dash-mux"].contains(rawMode) {
            return .mux(outputFilename: outputFilename(from: object, fallback: "manifest-output.mp4"))
        }
        if ["concat", "concatenate", "join", "joined", "single"].contains(rawMode) {
            return .concatenate(outputFilename: outputFilename(from: object, fallback: "manifest-output.bin"))
        }
        return .files
    }

    private static func outputFilename(from object: [String: Any], fallback: String) -> String {
        let outputFilename = stringValue(
            object["outputFilename"] ??
                object["outputFile"] ??
                object["resultFilename"] ??
                object["concatFilename"] ??
                object["muxFilename"] ??
                object["remoteOutputFilename"]
        )?.trimmed ?? ""
        return outputFilename.isEmpty ? fallback : outputFilename
    }

    private static func remoteAssetDefaults(from object: [String: Any]) -> RemoteAssetDefaults {
        let rawBaseURL = stringValue(
            object["baseURL"] ??
                object["baseUrl"] ??
                object["assetBaseURL"] ??
                object["assetBaseUrl"] ??
                object["mediaBaseURL"] ??
                object["mediaBaseUrl"] ??
                object["downloadBaseURL"] ??
                object["downloadBaseUrl"]
        )?.trimmed ?? ""
        let baseURL = rawBaseURL.isEmpty ? nil : URL(string: rawBaseURL).flatMap { isDownloadableAssetURL($0) ? $0 : nil }

        return RemoteAssetDefaults(
            baseURL: baseURL,
            referer: headerString(
                in: object,
                directKeys: ["referer", "referrer", "Referer", "Referrer"],
                headerNames: ["referer", "referrer"]
            )?.trimmed,
            userAgent: headerString(
                in: object,
                directKeys: ["userAgent", "user_agent", "UserAgent", "User-Agent"],
                headerNames: ["user-agent", "useragent", "user_agent"]
            )?.trimmed,
            headers: additionalHeaderStrings(in: object)
        )
    }

    private static func remoteAssets(from value: Any?, defaults: RemoteAssetDefaults = .empty) -> [ResolvedAsset] {
        guard let value else { return [] }
        if let string = value as? String {
            return string
                .components(separatedBy: .newlines)
                .enumerated()
                .compactMap { index, raw in remoteAsset(from: raw, index: index + 1, defaults: defaults) }
        }
        if let strings = value as? [String] {
            return strings.enumerated().compactMap { index, raw in
                remoteAsset(from: raw, index: index + 1, defaults: defaults)
            }
        }
        if let objects = value as? [[String: Any]] {
            return objects.enumerated().compactMap { index, object in
                remoteAsset(from: object, index: index + 1, defaults: defaults)
            }
        }
        if let values = value as? [Any] {
            return values.enumerated().compactMap { index, value in
                if let raw = value as? String {
                    return remoteAsset(from: raw, index: index + 1, defaults: defaults)
                }
                if let object = value as? [String: Any] {
                    return remoteAsset(from: object, index: index + 1, defaults: defaults)
                }
                return nil
            }
        }
        if let object = value as? [String: Any] {
            if let asset = remoteAsset(from: object, index: 1, defaults: defaults) {
                return [asset]
            }
            let nestedDefaults = defaults.merged(with: remoteAssetDefaults(from: object))
            return remoteAssets(
                from: object["items"] ?? object["assets"] ?? object["files"] ?? object["urls"] ?? object["downloads"],
                defaults: nestedDefaults
            )
        }
        return []
    }

    private static func remoteAsset(from raw: String, index: Int, defaults: RemoteAssetDefaults) -> ResolvedAsset? {
        let text = raw.trimmed
        guard !text.isEmpty,
              let url = assetURL(from: text, baseURL: defaults.baseURL),
              isDownloadableAssetURL(url) else {
            return nil
        }
        return ResolvedAsset(
            remoteURL: url,
            filename: filename(from: url, fallback: "asset-\(index)"),
            referer: defaults.referer,
            userAgent: defaults.userAgent,
            additionalHeaders: resolvedHeaders(defaults.headers)
        )
    }

    private static func remoteAsset(from object: [String: Any], index: Int, defaults: RemoteAssetDefaults) -> ResolvedAsset? {
        let assetDefaults = defaults.merged(with: remoteAssetDefaults(from: object))
        guard let rawURL = stringValue(object["url"] ?? object["src"] ?? object["href"] ?? object["remoteURL"]),
              let url = assetURL(from: rawURL.trimmed, baseURL: assetDefaults.baseURL),
              isDownloadableAssetURL(url) else {
            return nil
        }
        let filenameCandidate = stringValue(object["filename"] ?? object["fileName"] ?? object["name"] ?? object["path"])?.trimmed ?? ""
        let filename = filenameCandidate.isEmpty ? Self.filename(from: url, fallback: "asset-\(index)") : filenameCandidate
        return ResolvedAsset(
            remoteURL: url,
            filename: filename,
            referer: headerString(
                in: object,
                directKeys: ["referer", "referrer", "Referer", "Referrer"],
                headerNames: ["referer", "referrer"]
            )?.trimmed ?? assetDefaults.referer,
            userAgent: headerString(
                in: object,
                directKeys: ["userAgent", "user_agent", "UserAgent", "User-Agent"],
                headerNames: ["user-agent", "useragent", "user_agent"]
            )?.trimmed ?? assetDefaults.userAgent,
            additionalHeaders: resolvedHeaders(assetDefaults.headers)
        )
    }

    private static func assetURL(from raw: String, baseURL: URL?) -> URL? {
        URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private static func headerString(in object: [String: Any], directKeys: [String], headerNames: Set<String>) -> String? {
        for key in directKeys {
            if let value = stringValue(object[key]), !value.trimmed.isEmpty {
                return value
            }
        }

        guard let headers = object["headers"] as? [String: Any] else {
            return nil
        }

        for (key, value) in headers {
            let normalized = key.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if headerNames.contains(normalized),
               let value = stringValue(value),
               !value.trimmed.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func additionalHeaderStrings(in object: [String: Any]) -> [String: String] {
        guard let headers = object["headers"] as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, rawValue) in headers {
            let name = key.trimmed
            let normalized = name.lowercased()
            guard isSafeHeaderName(name),
                  !["referer", "referrer", "user-agent", "useragent", "user_agent"].contains(normalized),
                  let value = stringValue(rawValue)?.trimmed,
                  isSafeHeaderValue(value) else {
                continue
            }
            result[name] = value
        }
        return result
    }

    private static func resolvedHeaders(_ headers: [String: String]) -> [ResolvedRequestHeader] {
        headers
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
            .map { ResolvedRequestHeader(name: $0.key, value: $0.value) }
    }

    private static func isSafeHeaderName(_ value: String) -> Bool {
        guard !value.isEmpty else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!#$%&'*+-.^_`|~")
        return value.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func isSafeHeaderValue(_ value: String) -> Bool {
        !value.isEmpty && !value.contains("\r") && !value.contains("\n")
    }

    private static func isDownloadableAssetURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    private static func filename(from url: URL, fallback: String) -> String {
        let last = url.lastPathComponent
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map(String.init)?
            .trimmed ?? ""
        return last.isEmpty ? fallback : last
    }

    private static func stringList(_ value: Any?) -> [String]? {
        guard let value else { return nil }
        if let array = value as? [String] {
            return array.map(\.trimmed).filter { !$0.isEmpty }
        }
        if let array = value as? [[String: Any]] {
            let paths = array.compactMap { item in
                stringValue(item["path"] ?? item["file"] ?? item["filename"])
            }.map(\.trimmed).filter { !$0.isEmpty }
            return paths
        }
        if let string = value as? String {
            let paths = string
                .components(separatedBy: .newlines)
                .map(\.trimmed)
                .filter { !$0.isEmpty }
            return paths
        }
        return nil
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    private static func splitArguments(_ template: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var index = template.startIndex

        func appendCurrent() {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }

        while index < template.endIndex {
            let character = template[index]

            if character == "\\" {
                let nextIndex = template.index(after: index)
                if nextIndex < template.endIndex {
                    current.append(template[nextIndex])
                    index = template.index(after: nextIndex)
                } else {
                    current.append(character)
                    index = nextIndex
                }
                continue
            }

            if character == "\"" || character == "'" {
                if quote == nil {
                    quote = character
                    index = template.index(after: index)
                    continue
                }
                if quote == character {
                    quote = nil
                    index = template.index(after: index)
                    continue
                }
            }

            if quote == nil && character.isShellWhitespace {
                appendCurrent()
                index = template.index(after: index)
                continue
            }

            current.append(character)
            index = template.index(after: index)
        }

        guard quote == nil else {
            throw NativeDownloadError.unsupported("Custom command has an unterminated quote.")
        }

        appendCurrent()
        return result
    }

    private static func expand(
        _ token: String,
        url: URL,
        host: String,
        outputDirectory: URL,
        headers: HTTPRequestOptions,
        rule: SiteRule? = nil
    ) -> String {
        let pluginManifest = rule?.environment["HITOMI_NATIVE_PLUGIN_MANIFEST"] ?? ""
        let pluginDirectory = rule?.environment["HITOMI_NATIVE_PLUGIN_MANIFEST_DIR"] ?? ""
        return token
            .replacingOccurrences(of: "{url}", with: url.absoluteString)
            .replacingOccurrences(of: "{output}", with: outputDirectory.path)
            .replacingOccurrences(of: "{outputDir}", with: outputDirectory.path)
            .replacingOccurrences(of: "{host}", with: host)
            .replacingOccurrences(of: "{path}", with: url.path)
            .replacingOccurrences(of: "{query}", with: url.query ?? "")
            .replacingOccurrences(of: "{referer}", with: headers.referer ?? "")
            .replacingOccurrences(of: "{userAgent}", with: headers.userAgent ?? "")
            .replacingOccurrences(of: "{ruleName}", with: rule?.name ?? "")
            .replacingOccurrences(of: "{ruleHost}", with: rule?.hostSuffix ?? "")
            .replacingOccurrences(of: "{rulePattern}", with: rule?.urlPattern ?? "")
            .replacingOccurrences(of: "{pluginManifest}", with: pluginManifest)
            .replacingOccurrences(of: "{pluginManifestDir}", with: pluginDirectory)
            .replacingOccurrences(of: "{pluginDir}", with: pluginDirectory)
    }

    private static func environment(
        for url: URL,
        host: String,
        outputDirectory: URL,
        headers: HTTPRequestOptions,
        rule: SiteRule,
        contextURL: URL? = nil,
        contextJSON: String? = nil
    ) -> [String: String] {
        var values = [
            "HITOMI_NATIVE_URL": url.absoluteString,
            "HITOMI_NATIVE_OUTPUT": outputDirectory.path,
            "HITOMI_NATIVE_OUTPUT_DIR": outputDirectory.path,
            "HITOMI_NATIVE_HOST": host,
            "HITOMI_NATIVE_PATH": url.path,
            "HITOMI_NATIVE_QUERY": url.query ?? "",
            "HITOMI_NATIVE_RULE_NAME": rule.name,
            "HITOMI_NATIVE_RULE_HOST": rule.hostSuffix,
            "HITOMI_NATIVE_RULE_PATTERN": rule.urlPattern ?? "",
            "HITOMI_NATIVE_REFERER": headers.referer ?? "",
            "HITOMI_NATIVE_USER_AGENT": headers.userAgent ?? "",
            "HITOMI_NATIVE_WORKING_DIR": expandedWorkingDirectory(
                for: rule,
                url: url,
                host: host,
                outputDirectory: outputDirectory,
                headers: headers
            ),
            "HITOMI_NATIVE_CWD": expandedWorkingDirectory(
                for: rule,
                url: url,
                host: host,
                outputDirectory: outputDirectory,
                headers: headers
            )
        ]

        if let contextURL {
            values["HITOMI_NATIVE_CONTEXT_FILE"] = contextURL.path
        }
        if let contextJSON {
            values["HITOMI_NATIVE_CONTEXT_JSON"] = contextJSON
        }

        values.merge(
            optionEnvironment(
                for: rule.options,
                url: url,
                host: host,
                outputDirectory: outputDirectory,
                headers: headers,
                rule: rule
            )
        ) { _, optionValue in optionValue }

        for (key, value) in rule.environment {
            let name = sanitizedEnvironmentName(key)
            guard !name.isEmpty else { continue }
            values[name] = expand(value, url: url, host: host, outputDirectory: outputDirectory, headers: headers, rule: rule)
        }

        return DownloadMetadata.clean(values)
    }

    private static func sanitizedEnvironmentName(_ raw: String) -> String {
        let trimmed = raw.trimmed
        guard trimmed.range(of: #"^[A-Za-z_][A-Za-z0-9_]*$"#, options: .regularExpression) != nil else {
            return ""
        }
        return trimmed
    }

    private static func optionEnvironment(
        for options: [String: String],
        url: URL,
        host: String,
        outputDirectory: URL,
        headers: HTTPRequestOptions,
        rule: SiteRule? = nil
    ) -> [String: String] {
        let expanded = DownloadMetadata.clean(
            options.mapValues {
                expand($0, url: url, host: host, outputDirectory: outputDirectory, headers: headers, rule: rule)
            }
        )
        guard !expanded.isEmpty else { return [:] }

        var values: [String: String] = [:]
        if JSONSerialization.isValidJSONObject(expanded),
           let data = try? JSONSerialization.data(withJSONObject: expanded, options: [.sortedKeys]),
           let json = String(data: data, encoding: .utf8) {
            values["HITOMI_NATIVE_OPTIONS_JSON"] = json
        }

        for (key, value) in expanded {
            let suffix = sanitizedOptionEnvironmentSuffix(key)
            guard !suffix.isEmpty else { continue }
            values["HITOMI_NATIVE_OPTION_\(suffix)"] = value
        }

        return values
    }

    private static func sanitizedOptionEnvironmentSuffix(_ raw: String) -> String {
        var result = ""
        var previousWasUnderscore = false

        for scalar in raw.trimmed.unicodeScalars {
            let value = scalar.value
            let outputScalar: UnicodeScalar?
            switch value {
            case 48...57, 65...90:
                outputScalar = UnicodeScalar(value)
            case 97...122:
                outputScalar = UnicodeScalar(value - 32)
            default:
                outputScalar = nil
            }

            if let outputScalar {
                result.unicodeScalars.append(outputScalar)
                previousWasUnderscore = false
            } else if !previousWasUnderscore {
                result.append("_")
                previousWasUnderscore = true
            }
        }

        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    private static func expandedWorkingDirectory(
        for rule: SiteRule,
        url: URL,
        host: String,
        outputDirectory: URL,
        headers: HTTPRequestOptions
    ) -> String {
        guard let template = rule.workingDirectoryTemplate?.trimmed, !template.isEmpty else {
            return outputDirectory.path
        }
        let expanded = expand(template, url: url, host: host, outputDirectory: outputDirectory, headers: headers, rule: rule)
        let expandedPath = (expanded as NSString).expandingTildeInPath
        return expandedPath.hasPrefix("/") ? expandedPath : outputDirectory.appendingPathComponent(expandedPath).path
    }

    private static func contextJSON(
        for url: URL,
        host: String,
        outputDirectory: URL,
        headers: HTTPRequestOptions,
        rule: SiteRule
    ) throws -> String {
        let expandedOptions = DownloadMetadata.clean(
            rule.options.mapValues {
                expand($0, url: url, host: host, outputDirectory: outputDirectory, headers: headers, rule: rule)
            }
        )
        var object: [String: Any] = [
            "version": 1,
            "app": "HitomiBadayo",
            "url": url.absoluteString,
            "output": outputDirectory.path,
            "outputDir": outputDirectory.path,
            "host": host,
            "path": url.path,
            "query": url.query ?? "",
            "referer": headers.referer ?? "",
            "userAgent": headers.userAgent ?? "",
            "workingDirectory": expandedWorkingDirectory(
                for: rule,
                url: url,
                host: host,
                outputDirectory: outputDirectory,
                headers: headers
            ),
            "rule": [
                "name": rule.name,
                "host": rule.hostSuffix,
                "pattern": rule.urlPattern ?? "",
                "handler": rule.handler.rawValue
            ],
            "options": expandedOptions
        ]
        let pluginManifest = rule.environment["HITOMI_NATIVE_PLUGIN_MANIFEST"] ?? ""
        let pluginDirectory = rule.environment["HITOMI_NATIVE_PLUGIN_MANIFEST_DIR"] ?? ""
        if !pluginManifest.isEmpty || !pluginDirectory.isEmpty {
            object["plugin"] = [
                "manifest": pluginManifest,
                "manifestDir": pluginDirectory
            ]
        }
        let data = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        guard let json = String(data: data, encoding: .utf8) else {
            throw NativeDownloadError.unsupported("Custom command context could not be encoded.")
        }
        return json
    }

    private static func tail(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(6).joined(separator: " ")
        return tail.isEmpty ? "no diagnostic output" : tail
    }
}

private extension Character {
    var isShellWhitespace: Bool {
        unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }
}
