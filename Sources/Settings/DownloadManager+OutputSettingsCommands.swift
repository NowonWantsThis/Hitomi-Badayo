import Foundation

extension DownloadManager {
    func setOutputSubfolderMode(_ mode: OutputSubfolderMode) {
        settingsStore.outputSubfolderMode = mode
        settingsStore.persistOutputSubfolderMode()
        appStatusStore.setSummary("Output grouping saved")
    }

    func selectSourceFolder(_ sourceID: String) {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        settingsStore.selectedSourceFolderID =
            DownloadSourceFolderProfile.settingsProfiles.contains {
            $0.id == normalized
        } ? normalized : "hitomi"
        settingsStore.persistSelectedSourceFolderID()
    }

    func sourceFolderName(for sourceID: String) -> String {
        OutputSettingsReadModelService.sourceFolderName(
            settings: settingsStore,
            sourceID: sourceID
        )
    }

    func setSourceFolderName(_ folderName: String, for sourceID: String) {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        settingsStore.sourceFolderNames[normalized] = folderName
        settingsStore.persistSourceFolderNames()
        appStatusStore.setSummary("Source folder saved")
    }

    func resetSourceFolderName(for sourceID: String) {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        settingsStore.sourceFolderNames.removeValue(forKey: normalized)
        settingsStore.persistSourceFolderNames()
        appStatusStore.setSummary("Source folder reset")
    }

    func sourceArchiveMode(for sourceID: String) -> SourceArchiveMode {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        if let mode = settingsStore.sourceArchiveModes[normalized] {
            return mode
        }
        if DownloadSourceFolderProfile.isSettingsSourceID(normalized) {
            return .pass
        }
        guard settingsStore.archiveCompletedFolders else { return .pass }
        return settingsStore.archiveFileFormat == .cbz ? .cbz : .zip
    }

    func sourceArchiveDeletesOriginal(for sourceID: String) -> Bool {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        if let deleteOriginal = settingsStore.sourceArchiveDeleteOriginal[normalized] {
            return deleteOriginal
        }
        if DownloadSourceFolderProfile.isSettingsSourceID(normalized) {
            return false
        }
        return settingsStore.archiveCompletedFolders &&
            settingsStore.deleteOriginalFolderAfterArchiving
    }

    func setSourceArchiveMode(
        _ mode: SourceArchiveMode,
        for sourceID: String
    ) {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        let profile = DownloadSourceFolderProfile(id: normalized)
        guard profile.supportsFolderArchive else { return }
        settingsStore.sourceArchiveModes[normalized] = mode
        settingsStore.persistSourceArchiveSettings()
        appStatusStore.setSummary("\(profile.displayName): \(mode.label)")
    }

    func setSourceArchiveDeleteOriginal(
        _ enabled: Bool,
        for sourceID: String
    ) {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        let profile = DownloadSourceFolderProfile(id: normalized)
        guard profile.supportsFolderArchive else { return }
        settingsStore.sourceArchiveDeleteOriginal[normalized] = enabled
        settingsStore.persistSourceArchiveSettings()
        appStatusStore.setSummary(
            enabled
                ? "Delete \(profile.displayName) folder after archive"
                : "Keep \(profile.displayName) folder"
        )
    }

    func setHideArchiveIndicatorWhenFileMissing(_ enabled: Bool) {
        settingsStore.hideArchiveIndicatorWhenFileMissing = enabled
        settingsStore.persistArchiveSettings()
        appStatusStore.setSummary(
            enabled
                ? "Missing archive icons hidden"
                : "Recorded archive icons kept"
        )
    }

    func sourceFileNameTemplate(for sourceID: String) -> String {
        OutputSettingsReadModelService.sourceFileNameTemplate(
            settings: settingsStore,
            sourceID: sourceID
        )
    }

    func setSelectedSourceFileNameTemplate(_ template: String) {
        setSourceFileNameTemplate(template, for: settingsStore.selectedSourceFolderID)
    }

    func setSourceFileNameTemplate(
        _ template: String,
        for sourceID: String
    ) {
        let normalized = DownloadSourceFolderProfile.normalizedSourceID(
            sourceID
        )
        guard NameTemplate.originalFileDefault(for: normalized) != nil else {
            setFileNameTemplate(template)
            return
        }
        settingsStore.sourceFileNameTemplates[normalized] = template
        settingsStore.persistSourceFileNameTemplates()
    }

    func applySelectedSourceFileNamePreset(_ template: String) {
        setSelectedSourceFileNameTemplate(template)
        let selectedProfile = DownloadSourceFolderProfile(
            id: settingsStore.selectedSourceFolderID
        )
        appStatusStore.setSummary(
            "\(selectedProfile.displayName) file format selected"
        )
    }

    func setHitomiFilenameTypeNumber(_ typeNumber: Int) {
        let normalized = min(2, max(0, typeNumber))
        setSourceFileNameTemplate(
            NameTemplate.originalHitomiFileTemplate(typeNumber: normalized),
            for: "hitomi"
        )
        appStatusStore.setSummary("Hitomi file format selected")
    }

    func applyFolderNamePreset(_ template: String) {
        setFolderNameTemplate(template)
        appStatusStore.setSummary("Folder format selected")
    }

    func applyFileNamePreset(_ template: String) {
        setFileNameTemplate(template)
        appStatusStore.setSummary("File format selected")
    }

    func applyRecordingFileNamePreset(_ template: String) {
        setRecordingFileNameTemplate(template)
        appStatusStore.setSummary("Recording format selected")
    }

    func setFolderNameTemplate(_ template: String) {
        settingsStore.folderNameTemplate = template
        settingsStore.persistFolderNameTemplate()
    }

    func setFileNameTemplate(_ template: String) {
        settingsStore.fileNameTemplate = template
        settingsStore.persistFileNameTemplate()
    }

    func setRecordingFileNameTemplate(_ template: String) {
        settingsStore.recordingFileNameTemplate = template
        settingsStore.persistRecordingFileNameTemplate()
    }

    func setImageConversionFormat(_ format: ImageConversionFormat) {
        settingsStore.imageConversionFormat = format
        settingsStore.persistOutputPresentation()
        appStatusStore.setSummary(
            format == .original
                ? "Image conversion off"
                : "Convert images to \(format.label)"
        )
    }

    func saveNameTemplates() {
        settingsStore.folderNameTemplate = settingsStore.folderNameTemplate.trimmed
        settingsStore.fileNameTemplate = settingsStore.fileNameTemplate.trimmed
        settingsStore.sourceFileNameTemplates = settingsStore.sourceFileNameTemplates.mapValues(\.trimmed)
        settingsStore.recordingFileNameTemplate = settingsStore.recordingFileNameTemplate.trimmed
        settingsStore.persistFolderNameTemplate()
        settingsStore.persistFileNameTemplate()
        settingsStore.persistSourceFileNameTemplates()
        settingsStore.persistRecordingFileNameTemplate()
        appStatusStore.setSummary("Name formats saved")
    }

    func setArchiveCompletedFolders(_ enabled: Bool) {
        settingsStore.archiveCompletedFolders = enabled
        if !enabled {
            settingsStore.deleteOriginalFolderAfterArchiving = false
        }
        let mode: SourceArchiveMode = enabled
            ? (settingsStore.archiveFileFormat == .cbz ? .cbz : .zip)
            : .pass
        for profile in DownloadSourceFolderProfile.settingsProfiles
            where profile.supportsFolderArchive {
            settingsStore.sourceArchiveModes[profile.id] = mode
        }
        settingsStore.persistArchiveSettings()
        settingsStore.persistSourceArchiveSettings()
        appStatusStore.setSummary(
            enabled
                ? "\(settingsStore.archiveFileFormat.label) archive on"
                : "Archive folders off"
        )
    }

    func setArchiveFileFormat(_ format: ArchiveFileFormat) {
        settingsStore.archiveFileFormat = format
        let mode: SourceArchiveMode = format == .cbz ? .cbz : .zip
        for profile in DownloadSourceFolderProfile.settingsProfiles
            where profile.supportsFolderArchive &&
                sourceArchiveMode(for: profile.id) != .pass {
            settingsStore.sourceArchiveModes[profile.id] = mode
        }
        settingsStore.persistArchiveSettings()
        settingsStore.persistSourceArchiveSettings()
        appStatusStore.setSummary("Archive format: \(format.label)")
    }

    func setDeleteOriginalFolderAfterArchiving(_ enabled: Bool) {
        settingsStore.deleteOriginalFolderAfterArchiving = enabled &&
            settingsStore.archiveCompletedFolders
        for profile in DownloadSourceFolderProfile.settingsProfiles
            where profile.supportsFolderArchive &&
                sourceArchiveMode(for: profile.id) != .pass {
            settingsStore.sourceArchiveDeleteOriginal[profile.id] =
                settingsStore.deleteOriginalFolderAfterArchiving
        }
        settingsStore.persistArchiveSettings()
        settingsStore.persistSourceArchiveSettings()
        appStatusStore.setSummary(
            settingsStore.deleteOriginalFolderAfterArchiving
                ? "Delete after archive on"
                : "Delete after archive off"
        )
    }

    func insertFolderNameToken(_ token: String) {
        settingsStore.folderNameTemplate = NameTemplate.appending(
            token: token,
            to: settingsStore.folderNameTemplate
        )
        settingsStore.persistFolderNameTemplate(trimmed: true)
        appStatusStore.setSummary("Name token inserted")
    }

    func insertFileNameToken(_ token: String) {
        settingsStore.fileNameTemplate = NameTemplate.appending(
            token: token,
            to: settingsStore.fileNameTemplate
        )
        settingsStore.persistFileNameTemplate(trimmed: true)
        appStatusStore.setSummary("Name token inserted")
    }

    func insertRecordingFileNameToken(_ token: String) {
        settingsStore.recordingFileNameTemplate = NameTemplate.appending(
            token: token,
            to: settingsStore.recordingFileNameTemplate
        )
        settingsStore.persistRecordingFileNameTemplate(trimmed: true)
        appStatusStore.setSummary("Name token inserted")
    }

    func completeFolderNameToken(_ token: String) {
        settingsStore.folderNameTemplate = NameTemplate.completingAutocomplete(
            in: settingsStore.folderNameTemplate,
            with: token
        )
        settingsStore.persistFolderNameTemplate(trimmed: true)
        appStatusStore.setSummary("Name token completed")
    }

    func completeFileNameToken(_ token: String) {
        settingsStore.fileNameTemplate = NameTemplate.completingAutocomplete(
            in: settingsStore.fileNameTemplate,
            with: token
        )
        settingsStore.persistFileNameTemplate(trimmed: true)
        appStatusStore.setSummary("Name token completed")
    }

    func completeRecordingFileNameToken(_ token: String) {
        settingsStore.recordingFileNameTemplate = NameTemplate.completingAutocomplete(
            in: settingsStore.recordingFileNameTemplate,
            with: token
        )
        settingsStore.persistRecordingFileNameTemplate(trimmed: true)
        appStatusStore.setSummary("Name token completed")
    }

    func effectiveSourceFolderName(for sourceID: String) -> String {
        OutputSettingsReadModelService.effectiveSourceFolderName(
            settings: settingsStore,
            sourceID: sourceID
        )
    }
}
