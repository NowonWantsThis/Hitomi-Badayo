import Foundation

struct AppBundleMetadata: Equatable {
    var name: String
    var version: String
    var build: String
    var releaseChannel: String
    var bundleIdentifier: String
    var minimumSystemVersion: String

    var displayVersion: String {
        releaseChannel.isEmpty ? version : "\(version) \(releaseChannel)"
    }
}

enum AppDiagnosticInfoService {
    static func bundleInfo(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:],
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> AppBundleMetadata {
        AppBundleMetadata(
            name: infoString(
                "CFBundleName",
                in: infoDictionary,
                fallback: "Hitomi Badayo"
            ),
            version: infoString(
                "CFBundleShortVersionString",
                in: infoDictionary,
                fallback: "0.1.0"
            ),
            build: infoString(
                "CFBundleVersion",
                in: infoDictionary,
                fallback: "1"
            ),
            releaseChannel: infoString(
                "HitomiBadayoReleaseChannel",
                in: infoDictionary,
                fallback: ""
            ),
            bundleIdentifier: bundleIdentifier ?? infoString(
                "CFBundleIdentifier",
                in: infoDictionary,
                fallback: "io.github.nowonwantsthis.HitomiBadayo"
            ),
            minimumSystemVersion: infoString(
                "LSMinimumSystemVersion",
                in: infoDictionary,
                fallback: "14.0"
            )
        )
    }

    static func aboutInfo(
        bundleInfo: AppBundleMetadata? = nil,
        operatingSystemVersion: String =
            ProcessInfo.processInfo.operatingSystemVersionString
    ) -> AppAboutInfo {
        let info = bundleInfo ?? self.bundleInfo()
        return AppAboutInfo(
            name: info.name,
            displayName: info.name,
            version: info.displayVersion,
            build: info.build,
            bundleIdentifier: info.bundleIdentifier,
            architecture: architectureName,
            minimumSystemVersion: info.minimumSystemVersion,
            operatingSystemVersion: operatingSystemVersion,
            latestVersionText: "Native macOS build",
            developedBy:
                "A native macOS downloader recreated through reverse engineering.",
            licenseSummary:
                "Hitomi Badayo is released under the MIT License. The bundled aria2c helper remains GPL-2.0-or-later, the bundled SpoofDPI helper remains Apache-2.0, and managed tools retain their respective upstream licenses. See Third-Party Notices in the app resources.",
            historySummary:
                "Version 0.5.0 completes the maintainability refactor while preserving existing behavior, settings, saved data, and download output."
        )
    }

    static func versionObject(
        about: AppAboutInfo? = nil
    ) -> [String: Any] {
        let info = about ?? aboutInfo()
        return [
            "name": info.name,
            "display_name": info.displayName,
            "version": info.version,
            "build": info.build,
            "bundle_id": info.bundleIdentifier,
            "architecture": info.architecture,
            "minimum_system_version": info.minimumSystemVersion,
            "os": info.operatingSystemVersion
        ]
    }

    static func aboutObject(
        about: AppAboutInfo? = nil
    ) -> [String: Any] {
        let info = about ?? aboutInfo()
        return [
            "name": info.name,
            "displayName": info.displayName,
            "version": info.version,
            "build": info.build,
            "current": info.currentVersionText,
            "latest": info.latestVersionText,
            "bundleIdentifier": info.bundleIdentifier,
            "architecture": info.architecture,
            "minimumSystemVersion": info.minimumSystemVersion,
            "operatingSystemVersion": info.operatingSystemVersion,
            "developedBy": info.developedBy,
            "licenseSummary": info.licenseSummary,
            "historySummary": info.historySummary
        ]
    }

    static func helpObject() -> [String: Any] {
        [
            "title": "Hitomi Badayo Help",
            "summary":
                "Native macOS help for queueing URLs, managing tasks, inspecting original-style helper windows, and using the local HTTP API.",
            "sections": [
                "Add URLs or paste clipboard links into the main input, then start the queue.",
                "Use task context menus for info, edit, comments, retry, PDF, ZIP/CBZ, move, delete, and browser viewing.",
                "Use Log, Dirs, Finder, Analysis, History, Search, Clipboard, Browser, Text, and Pages helper windows from the toolbar or HTTP UI.",
                "Enable the local HTTP API to use /docs, /webui, /about, /help, and compatibility routes."
            ],
            "routes": [
                "docs": "/docs",
                "webui": "/webui",
                "about": "/about",
                "apiAbout": "/api/about",
                "apiHelp": "/api/help"
            ]
        ]
    }

    private static var architectureName: String {
#if arch(arm64)
        "ARM64"
#elseif arch(x86_64)
        "x86_64"
#else
        "Unknown Architecture"
#endif
    }

    private static func infoString(
        _ key: String,
        in infoDictionary: [String: Any],
        fallback: String
    ) -> String {
        guard let value = infoDictionary[key] as? String,
              !value.trimmed.isEmpty else {
            return fallback
        }
        return value
    }
}
