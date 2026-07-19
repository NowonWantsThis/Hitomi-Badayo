import Foundation

enum ExternalToolKind: String, CaseIterable, Sendable {
    case ytdlp
    case ffmpeg
    case aria2c

    var displayName: String {
        switch self {
        case .ytdlp: return "yt-dlp"
        case .ffmpeg: return "FFmpeg"
        case .aria2c: return "aria2c"
        }
    }

    var executableName: String {
        switch self {
        case .ytdlp: return "yt-dlp"
        case .ffmpeg: return "ffmpeg"
        case .aria2c: return "aria2c"
        }
    }

    var defaultsKey: String {
        switch self {
        case .ytdlp: return "externalToolYTDLPPath"
        case .ffmpeg: return "externalToolFFmpegPath"
        case .aria2c: return "externalToolAria2Path"
        }
    }
}

enum ExternalToolSettings {
    static var managedBinDirectory: URL {
        AppPaths.applicationSupportDirectory
            .appendingPathComponent("Tools", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
    }

    static func managedExecutableURL(for kind: ExternalToolKind) -> URL {
        managedBinDirectory.appendingPathComponent(kind.executableName)
    }

    static func bundledExecutableURL(
        for kind: ExternalToolKind,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let toolDirectory: URL?
        if let override = environment["HITOMI_NATIVE_BUNDLED_TOOLS"]?.trimmed,
           !override.isEmpty {
            toolDirectory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            toolDirectory = Bundle.main.resourceURL?
                .appendingPathComponent("Tools", isDirectory: true)
        }

        guard let candidate = toolDirectory?.appendingPathComponent(kind.executableName),
              fileManager.isExecutableFile(atPath: candidate.path) else {
            return nil
        }
        return candidate
    }

    static func path(for kind: ExternalToolKind, defaults: UserDefaults = .standard) -> String {
        defaults.string(forKey: kind.defaultsKey) ?? ""
    }

    static func save(path: String, for kind: ExternalToolKind, defaults: UserDefaults = .standard) {
        let trimmed = normalizedExecutablePath(path)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: kind.defaultsKey)
        } else {
            defaults.set(trimmed, forKey: kind.defaultsKey)
        }
    }

    static func normalizedExecutablePath(
        _ raw: String,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> String {
        var value = raw.trimmed
        if value.count >= 2,
           let first = value.first,
           let last = value.last,
           (first == "\"" || first == "'"),
           first == last {
            value = String(value.dropFirst().dropLast()).trimmed
        }
        value = value.replacingOccurrences(of: "\\ ", with: " ")

        if value.lowercased().hasPrefix("file://"),
           let url = URL(string: value),
           url.isFileURL {
            value = url.path
        }

        if value == "~" || value.hasPrefix("~/") {
            let configuredHome = environment["HOME"]?.trimmed
            let home = (configuredHome?.isEmpty == false ? configuredHome : nil) ?? NSHomeDirectory()
            value = home + String(value.dropFirst())
        }
        return value.trimmed
    }

    static func executableURL(
        kind: ExternalToolKind,
        environmentKey: String,
        executableName: String,
        knownPaths: [String],
        configuredPath: String? = nil,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> URL? {
        let immediatePath = normalizedExecutablePath(configuredPath ?? "", environment: environment)
        if !immediatePath.isEmpty {
            let url = URL(fileURLWithPath: immediatePath)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let savedPath = normalizedExecutablePath(path(for: kind, defaults: defaults), environment: environment)
        if !savedPath.isEmpty {
            let url = URL(fileURLWithPath: savedPath)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        if let override = environment[environmentKey].map({ normalizedExecutablePath($0, environment: environment) }),
           !override.isEmpty {
            let url = URL(fileURLWithPath: override)
            if fileManager.isExecutableFile(atPath: url.path) {
                return url
            }
        }

        let managed = managedExecutableURL(for: kind)
        if fileManager.isExecutableFile(atPath: managed.path) {
            return managed
        }

        if let bundled = bundledExecutableURL(for: kind, environment: environment, fileManager: fileManager) {
            return bundled
        }

        for path in knownPaths where fileManager.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        let pathValue = environment["PATH"] ?? ""
        for folder in pathValue.components(separatedBy: ":") where !folder.isEmpty {
            let candidate = URL(fileURLWithPath: folder).appendingPathComponent(executableName)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }
}
