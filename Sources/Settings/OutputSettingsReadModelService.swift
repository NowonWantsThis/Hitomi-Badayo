import Foundation

struct OutputSettingsPresentationSnapshot {
    let folderNameTemplateAutocompleteSuggestions: [NameTemplateToken]
    let sourceFolderProfiles: [DownloadSourceFolderProfile]
    let selectedSourceFolderProfile: DownloadSourceFolderProfile
    let selectedSourceFolderPreviewPath: String
    let selectedSourceFileNameTemplate: String
    let selectedSourceFileNamePresets: [String]
    let selectedHitomiFilenameTypeNumber: Int
    let usesOriginalHitomiFilenameMode: Bool
    let fileNameTemplateAutocompleteSuggestions: [NameTemplateToken]
    let recordingFileNameTemplateAutocompleteSuggestions: [NameTemplateToken]
}

@MainActor
enum OutputSettingsReadModelService {
    static func snapshot(
        settings: SettingsStore
    ) -> OutputSettingsPresentationSnapshot {
        let selectedSourceID = DownloadSourceFolderProfile.normalizedSourceID(
            settings.selectedSourceFolderID
        )
        let selectedTemplate = sourceFileNameTemplate(
            settings: settings,
            sourceID: selectedSourceID
        )
        let hitomiTemplate = sourceFileNameTemplate(
            settings: settings,
            sourceID: "hitomi"
        )
        let selectedFolderName = effectiveSourceFolderName(
            settings: settings,
            sourceID: selectedSourceID
        )

        return OutputSettingsPresentationSnapshot(
            folderNameTemplateAutocompleteSuggestions:
                NameTemplate.autocompleteSuggestions(
                    in: settings.folderNameTemplate,
                    tokens: NameTemplate.folderTokenSuggestions
                ),
            sourceFolderProfiles: DownloadSourceFolderProfile.settingsProfiles,
            selectedSourceFolderProfile:
                DownloadSourceFolderProfile(id: selectedSourceID),
            selectedSourceFolderPreviewPath: URL(
                fileURLWithPath: settings.destinationPath,
                isDirectory: true
            )
                .appendingPathComponent(
                    selectedFolderName,
                    isDirectory: true
                )
                .path,
            selectedSourceFileNameTemplate: selectedTemplate,
            selectedSourceFileNamePresets:
                NameTemplate.originalFilePresets(for: selectedSourceID),
            selectedHitomiFilenameTypeNumber:
                NameTemplate.originalHitomiFilenameTypeNumber(
                    for: hitomiTemplate
                ) ?? 1,
            usesOriginalHitomiFilenameMode:
                NameTemplate.originalHitomiFilenameTypeNumber(
                    for: hitomiTemplate
                ) != nil,
            fileNameTemplateAutocompleteSuggestions:
                NameTemplate.autocompleteSuggestions(
                    in: settings.fileNameTemplate,
                    tokens: NameTemplate.fileTokenSuggestions
                ),
            recordingFileNameTemplateAutocompleteSuggestions:
                NameTemplate.autocompleteSuggestions(
                    in: settings.recordingFileNameTemplate,
                    tokens: NameTemplate.fileTokenSuggestions
                )
        )
    }

    static func sourceFolderName(
        settings: SettingsStore,
        sourceID: String
    ) -> String {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(sourceID)
        return settings.sourceFolderNames[normalized]
            ?? DownloadSourceFolderProfile.defaultFolderName(for: normalized)
    }

    static func effectiveSourceFolderName(
        settings: SettingsStore,
        sourceID: String
    ) -> String {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(sourceID)
        let configured = sourceFolderName(
            settings: settings,
            sourceID: normalized
        ).trimmed
        let fallback = DownloadSourceFolderProfile.defaultFolderName(
            for: normalized
        )
        return (configured.isEmpty ? fallback : configured)
            .sanitizedRelativePath(maxComponentLength: 120)
    }

    static func sourceFileNameTemplate(
        settings: SettingsStore,
        sourceID: String
    ) -> String {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(sourceID)
        guard NameTemplate.originalFileDefault(for: normalized) != nil else {
            return settings.fileNameTemplate
        }
        if let template = settings.sourceFileNameTemplates[normalized] {
            return template
        }
        if normalized == "hitomi" {
            let legacyTemplate = settings.fileNameTemplate.trimmed
            return legacyTemplate.isEmpty
                ? NameTemplate.originalFileDefault(for: normalized) ?? ""
                : settings.fileNameTemplate
        }
        return settings.fileNameTemplate
    }
}
