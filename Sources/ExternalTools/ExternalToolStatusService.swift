import Foundation

enum ExternalToolStatusService {
    private struct Definition {
        var kind: ExternalToolKind
        var environmentKey: String
        var executableName: String
        var knownPaths: [String]
    }

    private static let definitions = [
        Definition(
            kind: .ytdlp,
            environmentKey: "HITOMI_NATIVE_YTDLP",
            executableName: "yt-dlp",
            knownPaths: [
                "/opt/homebrew/bin/yt-dlp",
                "/usr/local/bin/yt-dlp",
                "/usr/bin/yt-dlp"
            ]
        ),
        Definition(
            kind: .deno,
            environmentKey: "HITOMI_NATIVE_DENO",
            executableName: "deno",
            knownPaths: [
                "/opt/homebrew/bin/deno",
                "/usr/local/bin/deno",
                "/usr/bin/deno"
            ]
        ),
        Definition(
            kind: .ffmpeg,
            environmentKey: "HITOMI_NATIVE_FFMPEG",
            executableName: "ffmpeg",
            knownPaths: [
                "/opt/homebrew/bin/ffmpeg",
                "/usr/local/bin/ffmpeg",
                "/usr/bin/ffmpeg"
            ]
        ),
        Definition(
            kind: .aria2c,
            environmentKey: "HITOMI_NATIVE_ARIA2C",
            executableName: "aria2c",
            knownPaths: [
                "/opt/homebrew/bin/aria2c",
                "/usr/local/bin/aria2c",
                "/usr/bin/aria2c"
            ]
        )
    ]

    static func statuses(
        ytdlpPath: String,
        denoPath: String,
        ffmpegPath: String,
        aria2Path: String,
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> [ExternalToolStatus] {
        let configuredPaths = [ytdlpPath, denoPath, ffmpegPath, aria2Path]
        return zip(definitions, configuredPaths).map { definition, path in
            status(
                kind: definition.kind,
                configuredPath: path,
                environmentKey: definition.environmentKey,
                executableName: definition.executableName,
                knownPaths: definition.knownPaths,
                defaults: defaults,
                environment: environment,
                fileManager: fileManager
            )
        }
    }

    static func status(
        kind: ExternalToolKind,
        configuredPath: String,
        environmentKey: String,
        executableName: String,
        knownPaths: [String],
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) -> ExternalToolStatus {
        let resolvedURL = ExternalToolSettings.executableURL(
            kind: kind,
            environmentKey: environmentKey,
            executableName: executableName,
            knownPaths: knownPaths,
            configuredPath: configuredPath,
            defaults: defaults,
            environment: environment,
            fileManager: fileManager
        )
        return ExternalToolStatus(
            name: kind.displayName,
            configuredPath: ExternalToolSettings.normalizedExecutablePath(
                configuredPath,
                environment: environment
            ),
            resolvedPath: resolvedURL?.path ?? "",
            isAvailable: resolvedURL != nil
        )
    }
}
