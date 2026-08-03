import Foundation

final class ArchiveJobStateService {
    func preparingAutomaticArchive(
        _ job: DownloadJob,
        format: ArchiveFileFormat
    ) -> DownloadJob {
        var updated = job
        updated.message = "Creating \(format.label)"
        return updated
    }

    func finishingAutomaticArchive(
        _ job: DownloadJob,
        archive: URL,
        sourceFolder: URL,
        format: ArchiveFileFormat,
        deletedOriginal: Bool,
        ruleName: String?,
        sourceURL: URL,
        sourceMetadata: [String: String]
    ) -> DownloadJob {
        var updated = job
        updated.outputPath = archive.path
        updated.metadata["archive_format"] = format.rawValue
        updated.metadata["archive_path"] = archive.path
        updated.metadata["archived_folder_path"] =
            sourceFolder.path
        updated.metadata["archive_deleted_original"] =
            deletedOriginal ? "true" : "false"
        updated.metadata["archive_setting"] =
            automaticArchiveSetting(
                ruleName: ruleName,
                sourceURL: sourceURL,
                sourceMetadata: sourceMetadata
            )
        return updated
    }

    func recordingAPIArchive(
        _ job: DownloadJob,
        archive: URL,
        format: ArchiveFileFormat,
        created: Bool,
        deletedOriginal: Bool,
        createdAt: String
    ) -> DownloadJob {
        var updated = job
        updated.metadata["archive_path"] = archive.path
        updated.metadata["archive_format"] = format.rawValue
        updated.metadata["archive_created_at"] = createdAt
        updated.metadata["archive_deleted_original"] =
            deletedOriginal ? "true" : "false"
        updated.message =
            "\(format.label) \(created ? "created" : "ready")"
        return updated
    }

    private func automaticArchiveSetting(
        ruleName: String?,
        sourceURL: URL,
        sourceMetadata: [String: String]
    ) -> String {
        if let ruleName {
            return "site:\(ruleName)"
        }
        let sourceID = DownloadSourceFolderProfile.sourceID(
            for: sourceURL,
            metadata: sourceMetadata
        )
        return DownloadSourceFolderProfile
            .isSettingsSourceID(sourceID)
            ? "source:\(sourceID)"
            : "global"
    }
}
