import Foundation

enum LegacyPreferencesMigrator {
    static let previousBadayoBundleIdentifier = "local.codex.HitomiBadayo"
    static let previousBundleIdentifier = "local.codex.HitomiDownloader"
    static let legacyBundleIdentifier = "local.codex.HitomiNative"
    static let sourceBundleIdentifiers = [
        previousBadayoBundleIdentifier,
        previousBundleIdentifier,
        legacyBundleIdentifier
    ]
    private static let migrationVersionKey = "legacyPreferencesMigrationVersion"
    private static let currentMigrationVersion = 3

    private struct StoredShortcut: Codable {
        var key: String
        var modifiers: Set<String>
    }

    static func migrateIfNeeded() {
        migrateIfNeeded(
            defaults: .standard,
            legacyBundleIdentifiers: sourceBundleIdentifiers,
            currentBundleIdentifier: Bundle.main.bundleIdentifier
        )
    }

    static func migrateIfNeeded(
        defaults: UserDefaults,
        legacyBundleIdentifier: String,
        currentBundleIdentifier: String?
    ) {
        migrateIfNeeded(
            defaults: defaults,
            legacyBundleIdentifiers: [legacyBundleIdentifier],
            currentBundleIdentifier: currentBundleIdentifier
        )
    }

    private static func migrateIfNeeded(
        defaults: UserDefaults,
        legacyBundleIdentifiers: [String],
        currentBundleIdentifier: String?
    ) {
        let sourceIdentifiers = legacyBundleIdentifiers.filter {
            currentBundleIdentifier != $0
        }
        guard !sourceIdentifiers.isEmpty else { return }
        let previousVersion = defaults.integer(forKey: migrationVersionKey)
        guard previousVersion < currentMigrationVersion else { return }

        if previousVersion < 1 {
            for sourceIdentifier in sourceIdentifiers {
                guard let legacyValues = defaults.persistentDomain(forName: sourceIdentifier) else {
                    continue
                }
                for (key, value) in legacyValues
                    where key != migrationVersionKey && defaults.object(forKey: key) == nil {
                    defaults.set(value, forKey: key)
                }
            }
        }

        if previousVersion < 2 {
            defaults.set(false, forKey: "clipboardMonitorEnabled")
            if defaults.object(forKey: "startDownloadsOnPaste") == nil {
                defaults.set(true, forKey: "startDownloadsOnPaste")
            }
            migrateDefaultPasteShortcut(defaults: defaults)
        }

        if previousVersion < 3 {
            migrateLegacySupportPaths(defaults: defaults)
        }

        defaults.set(currentMigrationVersion, forKey: migrationVersionKey)
    }

    private static func migrateLegacySupportPaths(defaults: UserDefaults) {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        let oldPrefix = base.appendingPathComponent("HitomiNative", isDirectory: true).path
        let newPrefix = base.appendingPathComponent("Hitomi Badayo", isDirectory: true).path
        for key in [
            "externalToolYTDLPPath",
            "externalToolFFmpegPath",
            "externalToolAria2Path",
            "pythonScriptPythonPath"
        ] {
            guard let path = defaults.string(forKey: key), path.hasPrefix(oldPrefix) else {
                continue
            }
            defaults.set(newPrefix + String(path.dropFirst(oldPrefix.count)), forKey: key)
        }
    }

    private static func migrateDefaultPasteShortcut(defaults: UserDefaults) {
        guard let data = defaults.data(forKey: "appShortcutAssignments"),
              var shortcuts = try? JSONDecoder().decode([String: StoredShortcut].self, from: data),
              let paste = shortcuts["pasteURLs"],
              paste.key == "v",
              paste.modifiers == Set(["command", "shift"]) else {
            return
        }

        shortcuts["pasteURLs"] = StoredShortcut(key: "v", modifiers: ["command"])
        if let migrated = try? JSONEncoder().encode(shortcuts) {
            defaults.set(migrated, forKey: "appShortcutAssignments")
        }
    }
}
