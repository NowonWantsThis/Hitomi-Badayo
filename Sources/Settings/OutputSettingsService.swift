import Foundation

struct OutputSettingsSnapshot: Equatable {
    var sourceFolderNames: [String: String]
    var selectedSourceFolderID: String
    var outputSubfolderMode: OutputSubfolderMode
    var folderNameTemplate: String
    var fileNameTemplate: String
    var sourceFileNameTemplates: [String: String]
    var recordingFileNameTemplate: String
    var archiveCompletedFolders: Bool
    var archiveFileFormat: ArchiveFileFormat
    var deleteOriginalFolderAfterArchiving: Bool
    var hideArchiveIndicatorWhenFileMissing: Bool
    var sourceArchiveModes: [String: SourceArchiveMode]
    var sourceArchiveDeleteOriginal: [String: Bool]
}

struct OutputSettingsService {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> OutputSettingsSnapshot {
        let storedSourceFolderNames =
            defaults.dictionary(forKey: "sourceFolderNames")
                as? [String: String] ?? [:]
        let normalizedSourceFolderNames = Dictionary(
            uniqueKeysWithValues: storedSourceFolderNames.map {
                (
                    DownloadSourceFolderProfile.normalizedSourceID($0.key),
                    $0.value
                )
            }
        )
        var sourceFolderNames = normalizedSourceFolderNames
        for (sourceID, folderName) in normalizedSourceFolderNames
            where DownloadSourceFolderProfile
                .obsoleteDefaultFolderNames(for: sourceID)
                .contains(folderName) {
            sourceFolderNames[sourceID] =
                DownloadSourceFolderProfile.defaultFolderName(for: sourceID)
        }
        if sourceFolderNames != normalizedSourceFolderNames {
            defaults.set(sourceFolderNames, forKey: "sourceFolderNames")
        }

        let savedSourceFolderID = DownloadSourceFolderProfile
            .normalizedSourceID(
                defaults.string(forKey: "selectedSourceFolderID") ?? "hitomi"
            )
        let selectedSourceFolderID = DownloadSourceFolderProfile
            .settingsProfiles.contains { $0.id == savedSourceFolderID }
            ? savedSourceFolderID
            : "hitomi"

        let outputSubfolderMode: OutputSubfolderMode
        let folderNameTemplate: String
#if TESTING
        outputSubfolderMode = .none
        folderNameTemplate =
            defaults.string(forKey: "folderNameTemplate") ?? ""
#else
        let sourceFolderLayoutVersion =
            defaults.integer(forKey: "sourceFolderLayoutVersion")
        if sourceFolderLayoutVersion < 1 {
            outputSubfolderMode = .site
            defaults.set(
                OutputSubfolderMode.site.rawValue,
                forKey: "outputSubfolderMode"
            )
            let savedTemplate = defaults
                .string(forKey: "folderNameTemplate")?.trimmed ?? ""
            folderNameTemplate = savedTemplate.isEmpty
                ? DownloadSourceFolderProfile.originalDefaultFolderTemplate
                : savedTemplate
            defaults.set(folderNameTemplate, forKey: "folderNameTemplate")
            defaults.set(1, forKey: "sourceFolderLayoutVersion")
        } else {
            outputSubfolderMode = OutputSubfolderMode(
                rawValue: defaults.string(forKey: "outputSubfolderMode") ?? ""
            ) ?? .site
            folderNameTemplate = defaults.string(forKey: "folderNameTemplate")
                ?? DownloadSourceFolderProfile.originalDefaultFolderTemplate
        }
#endif

        let fileNameTemplate =
            defaults.string(forKey: "fileNameTemplate") ?? ""
        let recordingFileNameTemplate =
            defaults.string(forKey: "recordingFileNameTemplate") ?? ""
        var sourceFileNameTemplates = loadedSourceFileNameTemplates()

#if !TESTING
        let version = defaults.integer(forKey: "sourceFileNameTemplateVersion")
        if version < 1 {
            let legacyTemplate = fileNameTemplate.trimmed
            for sourceID in NameTemplate.originalSourceFileTemplateIDs
                where sourceID != "hitomi" &&
                    sourceFileNameTemplates[sourceID] == nil {
                sourceFileNameTemplates[sourceID] = legacyTemplate.isEmpty
                    ? NameTemplate.originalFileDefault(for: sourceID) ?? ""
                    : legacyTemplate
            }
        }
        if version < 2, sourceFileNameTemplates["hitomi"] == nil {
            let legacyTemplate = fileNameTemplate.trimmed
            sourceFileNameTemplates["hitomi"] = legacyTemplate.isEmpty
                ? NameTemplate.originalFileDefault(for: "hitomi") ?? ""
                : legacyTemplate
        }
        for sourceID in NameTemplate.originalSourceFileTemplateIDs
            where sourceFileNameTemplates[sourceID] == nil {
            sourceFileNameTemplates[sourceID] =
                NameTemplate.originalFileDefault(for: sourceID) ?? ""
        }
        defaults.set(2, forKey: "sourceFileNameTemplateVersion")
        persistSourceFileNameTemplates(sourceFileNameTemplates)
#endif

        let archiveCompletedFolders =
            defaults.object(forKey: "archiveCompletedFolders") as? Bool ?? false
        let archiveFileFormat = ArchiveFileFormat(
            rawValue: defaults.string(forKey: "archiveFileFormat") ?? ""
        ) ?? .zip
        let deleteOriginalFolderAfterArchiving =
            defaults.object(forKey: "deleteOriginalFolderAfterArchiving")
                as? Bool ?? false
        let hideArchiveIndicatorWhenFileMissing =
            defaults.object(forKey: "hideArchiveIndicatorWhenFileMissing")
                as? Bool ?? true
        let sourceArchive = loadSourceArchiveSettings(
            legacyArchiveEnabled: archiveCompletedFolders,
            legacyFormat: archiveFileFormat,
            legacyDeleteOriginal: deleteOriginalFolderAfterArchiving
        )
        if sourceArchive.didMigrate {
            persistSourceArchiveSettings(
                modes: sourceArchive.modes,
                deleteOriginal: sourceArchive.deleteOriginal
            )
        }

        return OutputSettingsSnapshot(
            sourceFolderNames: sourceFolderNames,
            selectedSourceFolderID: selectedSourceFolderID,
            outputSubfolderMode: outputSubfolderMode,
            folderNameTemplate: folderNameTemplate,
            fileNameTemplate: fileNameTemplate,
            sourceFileNameTemplates: sourceFileNameTemplates,
            recordingFileNameTemplate: recordingFileNameTemplate,
            archiveCompletedFolders: archiveCompletedFolders,
            archiveFileFormat: archiveFileFormat,
            deleteOriginalFolderAfterArchiving:
                deleteOriginalFolderAfterArchiving,
            hideArchiveIndicatorWhenFileMissing:
                hideArchiveIndicatorWhenFileMissing,
            sourceArchiveModes: sourceArchive.modes,
            sourceArchiveDeleteOriginal: sourceArchive.deleteOriginal
        )
    }

    func persistSourceArchiveSettings(
        modes: [String: SourceArchiveMode],
        deleteOriginal: [String: Bool]
    ) {
        let rawModes = modes.mapValues(\.rawValue)
        let originalModes = modes.mapValues(\.originalIndex)
        defaults.set(rawModes, forKey: "sourceArchiveModes")
        defaults.set(deleteOriginal, forKey: "sourceArchiveDeleteOriginal")
        defaults.set(Self.jsonString(originalModes), forKey: "zip_ext")
        defaults.set(Self.jsonString(deleteOriginal), forKey: "zip_rm")
        defaults.set(1, forKey: "sourceArchiveSettingsVersion")
    }

    func persistOutputSubfolderMode(_ mode: OutputSubfolderMode) {
        defaults.set(mode.rawValue, forKey: "outputSubfolderMode")
    }

    func persistSelectedSourceFolderID(_ sourceID: String) {
        defaults.set(sourceID, forKey: "selectedSourceFolderID")
    }

    func persistSourceFolderNames(_ names: [String: String]) {
        defaults.set(names, forKey: "sourceFolderNames")
    }

    func persistFolderNameTemplate(_ template: String) {
        defaults.set(template, forKey: "folderNameTemplate")
    }

    func persistFileNameTemplate(_ template: String) {
        defaults.set(template, forKey: "fileNameTemplate")
    }

    func persistRecordingFileNameTemplate(_ template: String) {
        defaults.set(template, forKey: "recordingFileNameTemplate")
    }

    func persistArchiveSettings(
        archiveCompletedFolders: Bool,
        archiveFileFormat: ArchiveFileFormat,
        deleteOriginalFolderAfterArchiving: Bool,
        hideArchiveIndicatorWhenFileMissing: Bool
    ) {
        defaults.set(
            archiveCompletedFolders,
            forKey: "archiveCompletedFolders"
        )
        defaults.set(archiveFileFormat.rawValue, forKey: "archiveFileFormat")
        defaults.set(
            deleteOriginalFolderAfterArchiving && archiveCompletedFolders,
            forKey: "deleteOriginalFolderAfterArchiving"
        )
        defaults.set(
            hideArchiveIndicatorWhenFileMissing,
            forKey: "hideArchiveIndicatorWhenFileMissing"
        )
    }

    private func loadedSourceFileNameTemplates() -> [String: String] {
        let stored = defaults.dictionary(forKey: "sourceFileNameTemplates")
            as? [String: String] ?? [:]
        var loaded = Dictionary(
            uniqueKeysWithValues: stored.map {
                (
                    DownloadSourceFolderProfile.normalizedSourceID($0.key),
                    $0.value
                )
            }
        )
        for sourceID in NameTemplate.originalSourceFileTemplateIDs {
            guard loaded[sourceID] == nil,
                  let preferenceKey =
                    NameTemplate.originalFilePreferenceKey(for: sourceID),
                  defaults.object(forKey: preferenceKey) != nil else {
                continue
            }
            loaded[sourceID] = defaults.string(forKey: preferenceKey) ?? ""
        }
        if loaded["hitomi"] == nil,
           defaults.object(forKey: "hitomiFilenameTypeNumber") != nil {
            loaded["hitomi"] = NameTemplate.originalHitomiFileTemplate(
                typeNumber: defaults.integer(forKey: "hitomiFilenameTypeNumber")
            )
        }
        return loaded
    }

    func persistSourceFileNameTemplates(
        _ templates: [String: String]
    ) {
        defaults.set(templates, forKey: "sourceFileNameTemplates")
        for sourceID in NameTemplate.originalSourceFileTemplateIDs {
            guard let key = NameTemplate.originalFilePreferenceKey(
                for: sourceID
            ) else {
                continue
            }
            if let template = templates[sourceID] {
                defaults.set(template, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        if let template = templates["hitomi"],
           let typeNumber = NameTemplate.originalHitomiFilenameTypeNumber(
                for: template
           ) {
            defaults.set(typeNumber, forKey: "hitomiFilenameTypeNumber")
        }
    }

    private func loadSourceArchiveSettings(
        legacyArchiveEnabled: Bool,
        legacyFormat: ArchiveFileFormat,
        legacyDeleteOriginal: Bool
    ) -> (
        modes: [String: SourceArchiveMode],
        deleteOriginal: [String: Bool],
        didMigrate: Bool
    ) {
        var modes: [String: SourceArchiveMode] = [:]
        if let stored = defaults.dictionary(forKey: "sourceArchiveModes") {
            for (sourceID, value) in stored {
                guard let rawValue = value as? String,
                      let mode = SourceArchiveMode(rawValue: rawValue) else {
                    continue
                }
                modes[DownloadSourceFolderProfile
                    .normalizedSourceID(sourceID)] = mode
            }
        }
        if let original = Self.decodedDictionary(
            defaults.string(forKey: "zip_ext"),
            as: [String: Int].self
        ) {
            for (sourceID, index) in original
                where modes[DownloadSourceFolderProfile
                    .normalizedSourceID(sourceID)] == nil {
                modes[DownloadSourceFolderProfile
                    .normalizedSourceID(sourceID)] =
                    SourceArchiveMode(originalIndex: index)
            }
        }

        var deleteOriginal: [String: Bool] = [:]
        if let stored = defaults.dictionary(
            forKey: "sourceArchiveDeleteOriginal"
        ) {
            for (sourceID, value) in stored {
                guard let enabled = value as? Bool else { continue }
                deleteOriginal[DownloadSourceFolderProfile
                    .normalizedSourceID(sourceID)] = enabled
            }
        }
        if let original = Self.decodedDictionary(
            defaults.string(forKey: "zip_rm"),
            as: [String: Bool].self
        ) {
            for (sourceID, enabled) in original
                where deleteOriginal[DownloadSourceFolderProfile
                    .normalizedSourceID(sourceID)] == nil {
                deleteOriginal[DownloadSourceFolderProfile
                    .normalizedSourceID(sourceID)] = enabled
            }
        }

        let didMigrate =
            defaults.integer(forKey: "sourceArchiveSettingsVersion") < 1
        if didMigrate && legacyArchiveEnabled {
            let legacyMode: SourceArchiveMode =
                legacyFormat == .cbz ? .cbz : .zip
            for profile in DownloadSourceFolderProfile.settingsProfiles
                where profile.supportsFolderArchive {
                if modes[profile.id] == nil {
                    modes[profile.id] = legacyMode
                }
                if deleteOriginal[profile.id] == nil {
                    deleteOriginal[profile.id] = legacyDeleteOriginal
                }
            }
        }
        return (modes, deleteOriginal, didMigrate)
    }

    private static func decodedDictionary<Value: Decodable>(
        _ json: String?,
        as type: [String: Value].Type
    ) -> [String: Value]? {
        guard let json, let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }

    private static func jsonString<Value: Encodable>(_ value: Value) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}
