import Foundation

final class QueueJobActionPolicy {
    private static let pendingRemovalMetadataKey =
        "pending_queue_removal"

    private let outputService: OutputService
    private let outputOpenService: OutputOpenService
    private let fileManager: FileManager

    init(
        outputService: OutputService,
        outputOpenService: OutputOpenService,
        fileManager: FileManager = .default
    ) {
        self.outputService = outputService
        self.outputOpenService = outputOpenService
        self.fileManager = fileManager
    }

    func contextualJobs(
        in jobs: [DownloadJob],
        selectedJobIDs: Set<UUID>,
        startingAt job: DownloadJob
    ) -> [DownloadJob] {
        guard jobs.contains(where: {
            $0.id == job.id && !isPendingRemoval($0)
        }) else {
            return []
        }
        let targetIDs = selectedJobIDs.contains(job.id)
            ? selectedJobIDs
            : Set([job.id])
        return jobs.filter {
            targetIDs.contains($0.id) &&
                !isPendingRemoval($0)
        }
    }

    func canRevealOutput(
        for job: DownloadJob,
        destinationPath: String
    ) -> Bool {
        let output = existingOutputURL(
            for: job,
            destinationPath: destinationPath
        )
        return output.flatMap {
            outputOpenService.revealURL(
                forOutputPath: $0.path
            )
        } != nil
    }

    func canOpenOutput(
        for job: DownloadJob,
        destinationPath: String
    ) -> Bool {
        guard let output = existingOutputURL(
            for: job,
            destinationPath: destinationPath
        ) else {
            return false
        }
        return OutputPreviewFileScanner.outputPathExists(
            output.path
        )
    }

    func canDeleteOutput(
        for job: DownloadJob,
        destinationPath: String
    ) -> Bool {
        !isActive(job.status) &&
            !job.isLocked &&
            !outputDeletionCandidates(
                for: job,
                destinationPath: destinationPath
            ).isEmpty
    }

    func canDeleteOutputAndJob(
        _ job: DownloadJob
    ) -> Bool {
        !job.isLocked && !isPendingRemoval(job)
    }

    func canMoveOutput(
        for job: DownloadJob,
        destinationPath: String,
        imageConversionJobIDs: Set<UUID>
    ) -> Bool {
        !isActive(job.status) &&
            !job.isLocked &&
            !imageConversionJobIDs.contains(job.id) &&
            !outputDeletionCandidates(
                for: job,
                destinationPath: destinationPath
            ).isEmpty
    }

    private func existingOutputURL(
        for job: DownloadJob,
        destinationPath: String
    ) -> URL? {
        QueueThumbnailProvider.existingOutputURL(
            forOutputPath: job.outputPath,
            destinationPath: destinationPath,
            searchRelocatedOutputs: false,
            fileManager: fileManager
        )
    }

    private func outputDeletionCandidates(
        for job: DownloadJob,
        destinationPath: String
    ) -> [OutputDeletionCandidate] {
        var resolvedJob = job
        resolvedJob.outputPath =
            existingOutputURL(
                for: job,
                destinationPath: destinationPath
            )?.path ?? job.outputPath
        return outputService.outputDeletionCandidates(
            for: resolvedJob
        )
    }

    private func isPendingRemoval(
        _ job: DownloadJob
    ) -> Bool {
        job.metadata[
            Self.pendingRemovalMetadataKey
        ]?.trimmed.lowercased() == "true"
    }

    private func isActive(
        _ status: JobStatus
    ) -> Bool {
        status == .resolving ||
            status == .downloading
    }
}
