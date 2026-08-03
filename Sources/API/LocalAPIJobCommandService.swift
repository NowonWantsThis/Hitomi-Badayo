import Foundation

struct LocalAPIJobDeletionResult: Equatable {
    var removedJobCount: Int
    var keptJobCount: Int
    var trashedItemCount: Int
    var failedItemCount: Int
}

@MainActor
struct LocalAPIJobCommandService {
    private let requestDecoder: LocalAPIRequestDecoder
    private let fileManager: FileManager

    init(
        requestDecoder: LocalAPIRequestDecoder =
            LocalAPIRequestDecoder(),
        fileManager: FileManager = .default
    ) {
        self.requestDecoder = requestDecoder
        self.fileManager = fileManager
    }

    func commentResponse(
        request: LocalHTTPRequest,
        job: DownloadJob?,
        update: (UUID, String) -> DownloadJob?
    ) -> LocalHTTPResponse {
        guard let job else {
            return taskNotFoundResponse()
        }

        let parameters = requestDecoder.parameters(from: request)
        let comment = (
            parameters["comment"] ??
            parameters["text"] ??
            parameters["value"] ??
            request.bodyText
        ).trimmed
        guard let updated = update(job.id, comment) else {
            return taskNotFoundResponse()
        }

        return LocalHTTPResponse.jsonObject([
            "updated": true,
            "id": updated.id.uuidString,
            "comment": updated.comment
        ])
    }

    func completeResponse(
        jobs: [DownloadJob],
        canComplete: (UUID) -> Bool,
        complete: (UUID) -> Bool,
        jobCount: () -> Int
    ) -> LocalHTTPResponse {
        guard !jobs.isEmpty else {
            return taskNotFoundResponse()
        }
        guard jobs.allSatisfy({ canComplete($0.id) }) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Active task cannot be marked finished"],
                status: 400
            )
        }

        let ids = jobs.compactMap { job in
            complete(job.id) ? job.id.uuidString : nil
        }
        return LocalHTTPResponse.jsonObject([
            "completed": !ids.isEmpty,
            "completedCount": ids.count,
            "id": ids.first ?? "",
            "ids": ids,
            "count": jobCount()
        ])
    }

    func removeResponse(
        jobs: [DownloadJob],
        usesOriginalActionShape: Bool,
        isActive: (DownloadJob) -> Bool,
        remove: ([DownloadJob]) -> Int,
        updateSummary: (String) -> Void,
        visibleJobCount: () -> Int
    ) -> LocalHTTPResponse {
        guard !jobs.isEmpty else {
            return taskNotFoundResponse()
        }
        guard jobs.allSatisfy({ !$0.isLocked }) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Locked task cannot be removed"],
                status: 400
            )
        }

        let cancelledCount = jobs.filter(isActive).count
        let removedIDs = jobs.map { $0.id.uuidString }
        let removedCount = remove(jobs)
        let message =
            "\(removedIDs.count) task" +
            "\(removedIDs.count == 1 ? "" : "s") removed"
        updateSummary(
            cancelledCount > 0
                ? message + "; \(cancelledCount) active transfer" +
                    "\(cancelledCount == 1 ? "" : "s") cancelled"
                : message
        )
        return LocalHTTPResponse.jsonObject([
            "ok": removedCount > 0,
            "res": usesOriginalActionShape ? "ok" : message,
            "message": message,
            "removed": removedCount > 0,
            "removedCount": removedCount,
            "cancelledCount": cancelledCount,
            "id": removedIDs.first ?? "",
            "ids": removedIDs,
            "count": visibleJobCount()
        ])
    }

    func deleteResponse(
        jobs: [DownloadJob],
        usesOriginalActionShape: Bool,
        isActive: (DownloadJob) -> Bool,
        delete: ([UUID]) -> LocalAPIJobDeletionResult,
        deletionPending: (UUID) -> Bool,
        updateSummary: (String) -> Void,
        visibleJobCount: () -> Int
    ) -> LocalHTTPResponse {
        guard !jobs.isEmpty else {
            return taskNotFoundResponse()
        }
        guard jobs.allSatisfy({ !$0.isLocked }) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Locked task cannot be deleted"],
                status: 400
            )
        }

        let cancelledCount = jobs.filter(isActive).count
        let jobIDs = jobs.map(\.id)
        let ids = jobIDs.map(\.uuidString)
        let result = delete(jobIDs)
        let pending = jobIDs.contains(where: deletionPending)
        let accepted = result.removedJobCount > 0 &&
            result.failedItemCount == 0
        let taskSuffix = result.removedJobCount == 1 ? "" : "s"
        let message = pending
            ? "\(result.removedJobCount) task\(taskSuffix) removed; " +
                "active output cleanup pending"
            : "\(result.removedJobCount) task\(taskSuffix) removed, " +
                "\(result.trashedItemCount) output" +
                "\(result.trashedItemCount == 1 ? "" : "s") " +
                "moved to Trash"
        updateSummary(message)

        return LocalHTTPResponse.jsonObject([
            "ok": accepted,
            "res": usesOriginalActionShape ? "ok" : message,
            "message": message,
            "deleted": result.trashedItemCount > 0 || pending,
            "deleteAccepted": accepted,
            "removed": result.removedJobCount > 0,
            "deletedCount": result.trashedItemCount,
            "removedCount": result.removedJobCount,
            "cancelledCount": cancelledCount,
            "failedCount": result.failedItemCount,
            "keptCount": result.keptJobCount,
            "deletionPending": pending,
            "id": ids.first ?? "",
            "ids": ids,
            "count": visibleJobCount()
        ])
    }

    func deleteFileResponse(
        job: DownloadJob?,
        isActive: Bool,
        file: OutputContentFile?,
        remainingFileCount: (DownloadJob) -> Int,
        persist: () -> Void
    ) -> LocalHTTPResponse {
        guard let job else {
            return taskNotFoundResponse()
        }
        guard !isActive else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Active task file cannot be deleted"],
                status: 400
            )
        }
        guard !job.isLocked else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Locked task file cannot be deleted"],
                status: 400
            )
        }
        guard let file else {
            return LocalHTTPResponse.jsonObject(
                ["error": "File not found"],
                status: 404
            )
        }
        guard file.archiveEntry == nil else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Archive entries cannot be deleted"],
                status: 400
            )
        }

        do {
            let path = file.url.path
            try fileManager.removeItem(at: file.url)
            let remaining = remainingFileCount(job)
            persist()
            return LocalHTTPResponse.jsonObject([
                "deleted": true,
                "uid": job.id.uuidString,
                "index": file.originalIndex,
                "path": path,
                "relativePath": file.relativePath,
                "remainingFileCount": remaining
            ])
        } catch {
            return LocalHTTPResponse.jsonObject(
                ["error": AppLocalization.errorText(error)],
                status: 400
            )
        }
    }

    private func taskNotFoundResponse() -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject(
            ["error": "Task not found"],
            status: 404
        )
    }
}
