import Foundation

struct LocalAPIAria2SeedingResult: Equatable {
    var seedTimeMinutes: String
    var seedRatio: String
}

@MainActor
struct LocalAPIAria2RuntimeService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder =
            LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func controlResponse(
        targetJobIDs: [UUID],
        pause: Bool,
        apply: (UUID, Bool) -> Bool,
        persist: () -> Void,
        jobCount: () -> Int
    ) -> LocalHTTPResponse {
        guard !targetJobIDs.isEmpty else {
            return taskNotFoundResponse()
        }

        var ids: [String] = []
        var skipped = 0
        for jobID in targetJobIDs {
            if apply(jobID, pause) {
                ids.append(jobID.uuidString)
            } else {
                skipped += 1
            }
        }

        if !ids.isEmpty {
            persist()
        }

        let key = pause ? "paused" : "resumed"
        return LocalHTTPResponse.jsonObject([
            key: !ids.isEmpty,
            "\(key)Count": ids.count,
            "skippedCount": skipped,
            "id": ids.first ?? "",
            "ids": ids,
            "count": jobCount()
        ])
    }

    func limitsResponse(
        request: LocalHTTPRequest,
        targetJobIDs: [UUID],
        defaultDownloadLimit: String,
        defaultUploadLimit: String,
        apply: (UUID, String, String) async -> Bool,
        persist: () -> Void,
        jobCount: () -> Int
    ) async -> LocalHTTPResponse {
        guard !targetJobIDs.isEmpty else {
            return taskNotFoundResponse()
        }

        let parameters = requestDecoder.parameters(from: request)
        let downloadLimit = parameters["down"] ??
            parameters["download"] ??
            parameters["download_limit"] ??
            parameters["max_download_limit"] ??
            defaultDownloadLimit
        let uploadLimit = parameters["up"] ??
            parameters["upload"] ??
            parameters["upload_limit"] ??
            parameters["max_upload_limit"] ??
            defaultUploadLimit

        var ids: [String] = []
        var skipped = 0
        for jobID in targetJobIDs {
            if await apply(jobID, downloadLimit, uploadLimit) {
                ids.append(jobID.uuidString)
            } else {
                skipped += 1
            }
        }

        if !ids.isEmpty {
            persist()
        }

        let normalizedDownload =
            Aria2Options.normalizedLimit(downloadLimit)
        let normalizedUpload =
            Aria2Options.normalizedLimit(uploadLimit)
        return LocalHTTPResponse.jsonObject([
            "updated": !ids.isEmpty,
            "updatedCount": ids.count,
            "skippedCount": skipped,
            "id": ids.first ?? "",
            "ids": ids,
            "down": normalizedDownload,
            "up": normalizedUpload,
            "maxDownloadLimit": normalizedDownload,
            "maxUploadLimit": normalizedUpload,
            "count": jobCount()
        ])
    }

    func fileSelectionResponse(
        request: LocalHTTPRequest,
        targetJobIDs: [UUID],
        defaultSelectedFiles: String,
        apply: (UUID, String) async -> String?,
        persist: () -> Void,
        jobCount: () -> Int
    ) async -> LocalHTTPResponse {
        guard !targetJobIDs.isEmpty else {
            return taskNotFoundResponse()
        }

        let parameters = requestDecoder.parameters(from: request)
        let selectedFiles = parameters["files"] ??
            parameters["file"] ??
            parameters["select"] ??
            parameters["select_file"] ??
            parameters["select-file"] ??
            parameters["selected"] ??
            parameters["selected_files"] ??
            parameters["file_priority"] ??
            parameters["priority"] ??
            defaultSelectedFiles

        var ids: [String] = []
        var appliedFiles: [String] = []
        var skipped = 0
        for jobID in targetJobIDs {
            if let files = await apply(jobID, selectedFiles) {
                ids.append(jobID.uuidString)
                appliedFiles.append(files)
            } else {
                skipped += 1
            }
        }

        if !ids.isEmpty {
            persist()
        }

        let firstFiles = appliedFiles.first ?? ""
        return LocalHTTPResponse.jsonObject([
            "updated": !ids.isEmpty,
            "updatedCount": ids.count,
            "skippedCount": skipped,
            "id": ids.first ?? "",
            "ids": ids,
            "files": firstFiles,
            "selectedFiles": firstFiles,
            "appliedFiles": appliedFiles,
            "count": jobCount()
        ])
    }

    func seedingResponse(
        request: LocalHTTPRequest,
        targetJobIDs: [UUID],
        defaultSeedTimeMinutes: String,
        defaultSeedRatio: String,
        apply:
            (UUID, String, String) async ->
                LocalAPIAria2SeedingResult?,
        persist: () -> Void,
        jobCount: () -> Int
    ) async -> LocalHTTPResponse {
        guard !targetJobIDs.isEmpty else {
            return taskNotFoundResponse()
        }

        let parameters = requestDecoder.parameters(from: request)
        let seedTime = parameters["seed"] ??
            parameters["seed_time"] ??
            parameters["seed-time"] ??
            parameters["seed_minutes"] ??
            parameters["seed-time-minutes"] ??
            parameters["time"] ??
            parameters["minutes"] ??
            defaultSeedTimeMinutes
        let seedRatio = parameters["ratio"] ??
            parameters["seed_ratio"] ??
            parameters["seed-ratio"] ??
            defaultSeedRatio

        var ids: [String] = []
        var appliedSeedTimes: [String] = []
        var appliedRatios: [String] = []
        var skipped = 0
        for jobID in targetJobIDs {
            if let result = await apply(
                jobID,
                seedTime,
                seedRatio
            ) {
                ids.append(jobID.uuidString)
                appliedSeedTimes.append(result.seedTimeMinutes)
                appliedRatios.append(result.seedRatio)
            } else {
                skipped += 1
            }
        }

        if !ids.isEmpty {
            persist()
        }

        return LocalHTTPResponse.jsonObject([
            "updated": !ids.isEmpty,
            "updatedCount": ids.count,
            "skippedCount": skipped,
            "id": ids.first ?? "",
            "ids": ids,
            "seedTimeMinutes": appliedSeedTimes.first ?? "",
            "seedRatio": appliedRatios.first ?? "",
            "appliedSeedTimes": appliedSeedTimes,
            "appliedSeedRatios": appliedRatios,
            "count": jobCount()
        ])
    }

    func fileListResponse(
        targetJobIDs: [UUID],
        summary: String,
        load: (UUID) async -> [Aria2FileEntry]?,
        jobCount: () -> Int
    ) async -> LocalHTTPResponse {
        guard !targetJobIDs.isEmpty else {
            return taskNotFoundResponse()
        }

        var ids: [String] = []
        var allFiles: [[String: Any]] = []
        var fileGroups: [[String: Any]] = []
        var skipped = 0
        for jobID in targetJobIDs {
            guard let entries = await load(jobID) else {
                skipped += 1
                continue
            }
            let objects = entries.map(Self.fileEntryObject)
            ids.append(jobID.uuidString)
            allFiles.append(contentsOf: objects)
            fileGroups.append([
                "id": jobID.uuidString,
                "fileCount": objects.count,
                "files": objects
            ])
        }

        return LocalHTTPResponse.jsonObject([
            "ok": !ids.isEmpty,
            "updated": !ids.isEmpty,
            "id": ids.first ?? "",
            "ids": ids,
            "fileCount": allFiles.count,
            "files": allFiles,
            "items": allFiles,
            "fileGroups": fileGroups,
            "skippedCount": skipped,
            "summary": summary,
            "count": jobCount()
        ])
    }

    func peersResponse(
        targetJobIDs: [UUID],
        load: (UUID) async -> [Aria2PeerEntry]?,
        jobCount: () -> Int
    ) async -> LocalHTTPResponse {
        guard !targetJobIDs.isEmpty else {
            return taskNotFoundResponse()
        }

        var ids: [String] = []
        var allPeers: [[String: Any]] = []
        var peerGroups: [[String: Any]] = []
        var skipped = 0
        for jobID in targetJobIDs {
            guard let peers = await load(jobID) else {
                skipped += 1
                continue
            }
            let objects = peers.map(Self.peerObject)
            ids.append(jobID.uuidString)
            allPeers.append(contentsOf: objects)
            peerGroups.append([
                "id": jobID.uuidString,
                "peerCount": objects.count,
                "peers": objects
            ])
        }

        return LocalHTTPResponse.jsonObject([
            "ok": !ids.isEmpty,
            "updated": !ids.isEmpty,
            "id": ids.first ?? "",
            "ids": ids,
            "peerCount": allPeers.count,
            "peers": allPeers,
            "items": allPeers,
            "peerGroups": peerGroups,
            "skippedCount": skipped,
            "count": jobCount()
        ])
    }

    private func taskNotFoundResponse() -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject(
            ["error": "Task not found"],
            status: 404
        )
    }

    private nonisolated static func fileEntryObject(
        _ entry: Aria2FileEntry
    ) -> [String: Any] {
        [
            "index": entry.index,
            "path": entry.path,
            "length": entry.length,
            "selected": entry.selected.map { $0 as Any } ?? NSNull(),
            "summary": entry.length.isEmpty
                ? "\(entry.index): \(entry.path)"
                : "\(entry.index): \(entry.path) (\(entry.length))"
        ]
    }

    private nonisolated static func peerObject(
        _ peer: Aria2PeerEntry
    ) -> [String: Any] {
        [
            "id": peer.id,
            "peerId": peer.peerID,
            "ip": peer.ip,
            "port": peer.port,
            "endpoint": peer.endpoint,
            "downloadSpeed": peer.downloadSpeed,
            "uploadSpeed": peer.uploadSpeed,
            "seeder": peer.seeder,
            "amChoking": peer.amChoking,
            "peerChoking": peer.peerChoking,
            "summary": peer.summary
        ]
    }
}
