import CryptoKit
import Foundation

struct APIItemRange {
    var range: Range<Int>
    var total: Int
}

struct LocalAPIStatusSnapshot {
    var now: Date
    var startedAt: Date
    var isRunning: Bool
    var jobs: [DownloadJob]
    var downloadSpeedBytesPerSecond: Int64?
    var downloadedSinceLaunchBytes: Int64?
    var uploadSpeedBytesPerSecond: Int64?
    var itemObjects: [[String: Any]]
}

struct LocalAPIFinderRequest {
    var field: MetadataFinderField
    var mode: MetadataFinderMode
    var query: String
    var limit: Int
}

struct LocalAPIAnalysisRequest {
    var field: MetadataAnalysisField
    var limit: Int
}

struct LocalAPIReadModelService {
    func range(
        from request: LocalHTTPRequest,
        total: Int
    ) -> APIItemRange {
        guard total > 0 else {
            return APIItemRange(range: 0..<0, total: total)
        }

        let hasExplicitRange = request.query["start"] != nil ||
            request.query["end"] != nil ||
            request.query["offset"] != nil ||
            request.query["from"] != nil ||
            request.query["limit"] != nil ||
            request.query["count"] != nil
        let hasPaging = request.query["p"] != nil ||
            request.query["page"] != nil ||
            request.query["step"] != nil
        guard hasExplicitRange || hasPaging else {
            return APIItemRange(range: 0..<total, total: total)
        }

        let pageStep = max(
            1,
            min(500, Int(request.query["step"] ?? "") ?? 50)
        )
        let page = max(
            0,
            Int(request.query["p"] ?? request.query["page"] ?? "") ?? 0
        )
        let startToken = request.query["start"] ??
            request.query["offset"] ??
            request.query["from"]
        let start = max(
            0,
            Int(startToken ?? "") ?? (hasPaging ? page * pageStep : 0)
        )
        let lowerBound = min(start, total)

        if let limitToken = request.query["limit"] ?? request.query["count"],
           request.query["end"] == nil,
           let limit = Int(limitToken) {
            let upperBound = min(lowerBound + max(0, limit), total)
            return APIItemRange(
                range: lowerBound..<upperBound,
                total: total
            )
        }

        if request.query["end"] == nil, hasPaging {
            let upperBound = min(lowerBound + pageStep, total)
            return APIItemRange(
                range: lowerBound..<upperBound,
                total: total
            )
        }

        let maxEnd = total - 1
        let endInclusive = min(
            max(0, Int(request.query["end"] ?? "") ?? maxEnd),
            maxEnd
        )
        let upperBound = lowerBound <= endInclusive
            ? min(endInclusive + 1, total)
            : lowerBound
        return APIItemRange(
            range: lowerBound..<upperBound,
            total: total
        )
    }

    func statusObject(_ snapshot: LocalAPIStatusSnapshot) -> [String: Any] {
        var object: [String: Any] = [
            "running": snapshot.isRunning,
            "count": snapshot.jobs.count,
            "queued": snapshot.jobs.filter { $0.status == .queued }.count,
            "downloading": snapshot.jobs.filter {
                $0.status == .downloading || $0.status == .resolving
            }.count,
            "finished": snapshot.jobs.filter { $0.status == .finished }.count,
            "failed": snapshot.jobs.filter { $0.status == .failed }.count
        ]
        object["startedAt"] = Self.dateString(snapshot.startedAt)
        object["uptimeSeconds"] = max(
            0,
            snapshot.now.timeIntervalSince(snapshot.startedAt)
        )
        object["downloadSpeedBytesPerSecond"] = Self.optionalInt64(
            snapshot.downloadSpeedBytesPerSecond
        )
        object["downloadedSinceLaunchBytes"] = Self.optionalInt64(
            snapshot.downloadedSinceLaunchBytes
        )
        object["uploadSpeedBytesPerSecond"] = Self.optionalInt64(
            snapshot.uploadSpeedBytesPerSecond
        )
        object["items"] = snapshot.itemObjects
        return object
    }

    func logObject(
        entries: [ActivityLogEntry],
        request: LocalHTTPRequest,
        limit: Int
    ) -> [String: Any] {
        let rangeInfo = range(from: request, total: entries.count)
        let visible = Array(entries[rangeInfo.range])
        return [
            "entries": logObjects(visible),
            "log": Self.activityLogText(visible),
            "count": rangeInfo.range.count,
            "total": rangeInfo.total,
            "start": rangeInfo.range.lowerBound,
            "end": rangeInfo.range.isEmpty
                ? rangeInfo.range.lowerBound
                : rangeInfo.range.upperBound - 1,
            "endExclusive": rangeInfo.range.upperBound,
            "limit": limit
        ]
    }

    func directoriesObject(
        entries: [OutputDirectoryEntry],
        text: String,
        request: LocalHTTPRequest
    ) -> [String: Any] {
        let rangeInfo = range(from: request, total: entries.count)
        let visible = Array(entries[rangeInfo.range])
        return [
            "directories": directoryObjects(visible),
            "dirs": visible.map(\.path),
            "text": text,
            "count": rangeInfo.range.count,
            "total": rangeInfo.total,
            "start": rangeInfo.range.lowerBound,
            "end": rangeInfo.range.isEmpty
                ? rangeInfo.range.lowerBound
                : rangeInfo.range.upperBound - 1,
            "endExclusive": rangeInfo.range.upperBound
        ]
    }

    func finderRequest(from request: LocalHTTPRequest) -> LocalAPIFinderRequest {
        LocalAPIFinderRequest(
            field: finderField(from: request),
            mode: finderMode(from: request),
            query: request.query["q"] ??
                request.query["query"] ??
                request.query["search"] ??
                "",
            limit: max(
                1,
                min(
                    1_000,
                    Int(
                        request.query["limit"] ??
                            request.query["count"] ??
                            ""
                    ) ?? 500
                )
            )
        )
    }

    func finderObject(
        request: LocalAPIFinderRequest,
        results: [MetadataFinderResult]
    ) -> [String: Any] {
        [
            "field": request.field.rawValue,
            "fieldLabel": request.field.label,
            "mode": request.mode.rawValue,
            "modeLabel": request.mode.label,
            "query": request.query,
            "count": results.count,
            "results": finderResultObjects(results)
        ]
    }

    func analysisRequest(
        from request: LocalHTTPRequest
    ) -> LocalAPIAnalysisRequest {
        LocalAPIAnalysisRequest(
            field: analysisField(from: request),
            limit: max(
                1,
                min(
                    1_000,
                    Int(
                        request.query["limit"] ??
                            request.query["count"] ??
                            ""
                    ) ?? 500
                )
            )
        )
    }

    func analysisObject(
        request: LocalAPIAnalysisRequest,
        entries: [MetadataAnalysisEntry]
    ) -> [String: Any] {
        let objects = analysisEntryObjects(entries)
        return [
            "field": request.field.rawValue,
            "fieldLabel": request.field.label,
            "count": entries.count,
            "total": entries.reduce(0) { $0 + $1.totalCount },
            "entries": objects,
            "results": objects
        ]
    }

    func statisticsObject(_ statistics: AppStatistics) -> [String: Any] {
        [
            "generatedAt": Self.dateString(statistics.generatedAt),
            "app": [
                "name": statistics.appName,
                "version": statistics.appVersion,
                "build": statistics.appBuild,
                "bundleIdentifier": statistics.bundleIdentifier,
                "minimumSystemVersion": statistics.minimumSystemVersion,
                "operatingSystemVersion": statistics.operatingSystemVersion
            ],
            "runtime": [
                "startedAt": Self.dateString(statistics.appStartedAt),
                "uptimeSeconds": statistics.appUptimeSeconds,
                "downloadSpeedBytesPerSecond": Self.optionalInt64(
                    statistics.downloadSpeedBytesPerSecond
                ),
                "downloadedSinceLaunchBytes": Self.optionalInt64(
                    statistics.downloadedSinceLaunchByteCount
                ),
                "uploadSpeedBytesPerSecond": Self.optionalInt64(
                    statistics.uploadSpeedBytesPerSecond
                )
            ],
            "paths": [
                "downloads": statistics.outputRootPath,
                "applicationSupport": statistics.applicationSupportPath,
                "userData": statistics.userDataPath
            ],
            "queue": [
                "total": statistics.totalJobs,
                "active": statistics.activeJobs,
                "queued": statistics.queuedJobs,
                "resolving": statistics.resolvingJobs,
                "downloading": statistics.downloadingJobs,
                "finished": statistics.finishedJobs,
                "failed": statistics.failedJobs,
                "cancelled": statistics.cancelledJobs,
                "pinned": statistics.pinnedJobs,
                "locked": statistics.lockedJobs,
                "taskSlots": statistics.jobConcurrency,
                "fileThreads": statistics.fileConcurrency
            ],
            "library": [
                "history": statistics.historyCount,
                "bookmarks": statistics.bookmarkCount,
                "filterBookmarks": statistics.queueFilterBookmarkCount,
                "siteRules": statistics.siteRuleCount,
                "enabledSiteRules": statistics.enabledSiteRuleCount,
                "searchProviders": statistics.searchProviderCount,
                "duplicateGroups": statistics.duplicateGroupCount,
                "duplicateExtras": statistics.duplicateExtraFileCount
            ],
            "output": [
                "knownPaths": statistics.outputPathCount,
                "files": statistics.outputFileCount,
                "folders": statistics.outputDirectoryCount,
                "totalBytes": statistics.outputByteCount,
                "skippedPaths": statistics.outputPathAnalysisSkippedCount,
                "availableBytes": Self.optionalInt64(
                    statistics.destinationAvailableByteCount
                ),
                "volumeBytes": Self.optionalInt64(
                    statistics.destinationTotalByteCount
                ),
                "estimatedQueuedBytes": statistics.estimatedQueuedByteCount,
                "pathAnalysisSkipped": statistics.destinationPathAnalysisSkipped,
                "warning": statistics.diskSpaceWarning
            ],
            "network": [
                "publicIP": statistics.publicIPStatus,
                "httpAPI": statistics.httpAPIEnabled,
                "clipboardWatch": statistics.clipboardMonitorEnabled
            ],
            "aria2": [
                "downloadLimit": statistics.aria2MaxDownloadLimit,
                "uploadLimit": statistics.aria2MaxUploadLimit,
                "seedTimeMinutes": statistics.aria2SeedTimeMinutes,
                "seedRatio": statistics.aria2SeedRatio,
                "anonymousMode": statistics.aria2AnonymousMode
            ],
            "alerts": [
                "jobNotification": statistics.notifyWhenJobCompletes,
                "queueNotification": statistics.notifyWhenQueueCompletes,
                "jobSound": statistics.playSoundWhenJobCompletes,
                "clipboardSound": statistics.playSoundOnClipboardAdd,
                "queueCompletionAction": statistics.queueCompletionAction,
                "queueCompletionActionStatus": statistics.queueCompletionActionStatus
            ],
            "externalTools": statistics.externalTools.map { tool in
                [
                    "name": tool.name,
                    "configuredPath": tool.configuredPath,
                    "resolvedPath": tool.resolvedPath,
                    "available": tool.isAvailable
                ] as [String: Any]
            }
        ]
    }

    func eventsResponse(statusObject: [String: Any]) -> LocalHTTPResponse {
        let json = Self.jsonString(statusObject)
        let body = """
        retry: 3000
        event: status
        data: \(json)


        """
        return LocalHTTPResponse(
            status: 200,
            contentType: "text/event-stream; charset=utf-8",
            body: Data(body.utf8),
            headers: [
                "Cache-Control": "no-cache",
                "X-Accel-Buffering": "no"
            ]
        )
    }

    func webSocketResponse(
        request: LocalHTTPRequest,
        statusObject: [String: Any]
    ) -> LocalHTTPResponse {
        guard let key = request.headers["sec-websocket-key"]?.trimmed,
              !key.isEmpty else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Missing WebSocket key"],
                status: 400
            )
        }
        let version = request.headers["sec-websocket-version"]?.trimmed
        guard version == nil || version == "13" else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Unsupported WebSocket version"],
                status: 400
            )
        }

        var body = Self.webSocketTextFrame(Self.jsonString(statusObject))
        body.append(contentsOf: [0x88, 0x00])
        return LocalHTTPResponse(
            status: 101,
            contentType: "",
            body: body,
            headers: [
                "Upgrade": "websocket",
                "Connection": "Upgrade",
                "Sec-WebSocket-Accept": Self.webSocketAcceptKey(for: key),
                "Cache-Control": "no-cache"
            ]
        )
    }

    private func logObjects(
        _ entries: [ActivityLogEntry]
    ) -> [[String: Any]] {
        entries.map { entry in
            [
                "id": entry.id.uuidString,
                "timestamp": Self.dateString(entry.timestamp),
                "category": entry.category,
                "message": entry.message,
                "line": "[\(Self.dateString(entry.timestamp))] [\(entry.category)] \(entry.message)"
            ]
        }
    }

    private func directoryObjects(
        _ entries: [OutputDirectoryEntry]
    ) -> [[String: Any]] {
        entries.map { entry in
            [
                "path": entry.path,
                "scope": entry.scope,
                "queueCount": entry.queueCount,
                "historyCount": entry.historyCount,
                "sampleTitle": entry.sampleTitle,
                "exists": entry.exists,
                "isDirectory": entry.isDirectory
            ]
        }
    }

    private func finderField(
        from request: LocalHTTPRequest
    ) -> MetadataFinderField {
        let raw = (
            request.query["field"] ??
                request.query["tab"] ??
                request.query["type"] ??
                request.query["kind"] ??
                "artist"
        ).trimmed.lowercased()
        switch raw {
        case "artist", "artists", "author", "creator", "작가":
            return .artist
        case "group", "groups", "circle", "그룹":
            return .group
        case "series", "parody", "시리즈":
            return .series
        case "character", "characters", "char", "캐릭터":
            return .character
        case "tag", "tags", "태그":
            return .tag
        default:
            return MetadataFinderField(rawValue: raw) ?? .artist
        }
    }

    private func finderMode(
        from request: LocalHTTPRequest
    ) -> MetadataFinderMode {
        let raw = (
            request.query["mode"] ??
                request.query["find"] ??
                request.query["engine"] ??
                "plain"
        ).trimmed.lowercased()
        switch raw {
        case "default", "plain", "normal", "평범하게":
            return .plain
        case "regex", "regexp", "regular", "정규식":
            return .regex
        case "fuzzy", "퍼지":
            return .fuzzy
        default:
            return MetadataFinderMode(rawValue: raw) ?? .plain
        }
    }

    private func finderResultObjects(
        _ results: [MetadataFinderResult]
    ) -> [[String: Any]] {
        results.map { result in
            var object: [String: Any] = [
                "field": result.field.rawValue,
                "value": result.value,
                "queueCount": result.queueCount,
                "historyCount": result.historyCount,
                "totalCount": result.totalCount,
                "sampleTitle": result.sampleTitle,
                "sampleSource": result.sampleSource,
                "searchToken": Self.searchToken(
                    field: result.field.rawValue,
                    value: result.value
                )
            ]
            object["score"] = result.score.map {
                NSNumber(value: $0)
            } ?? NSNull()
            return object
        }
    }

    private func analysisField(
        from request: LocalHTTPRequest
    ) -> MetadataAnalysisField {
        let raw = (
            request.query["field"] ??
                request.query["tab"] ??
                request.query["type"] ??
                request.query["kind"] ??
                "artist"
        ).trimmed.lowercased()
        switch raw {
        case "artist", "artists", "author", "creator", "작가":
            return .artist
        case "group", "groups", "circle", "그룹":
            return .group
        case "type", "types", "kind", "종류":
            return .type
        case "series", "parody", "시리즈":
            return .series
        case "character", "characters", "char", "캐릭터":
            return .character
        case "tag", "tags", "태그":
            return .tag
        case "language", "languages", "lang", "언어":
            return .language
        default:
            return MetadataAnalysisField(rawValue: raw) ?? .artist
        }
    }

    private func analysisEntryObjects(
        _ entries: [MetadataAnalysisEntry]
    ) -> [[String: Any]] {
        entries.map { entry in
            [
                "field": entry.field.rawValue,
                "value": entry.value,
                "queueCount": entry.queueCount,
                "historyCount": entry.historyCount,
                "totalCount": entry.totalCount,
                "sampleTitle": entry.sampleTitle,
                "sampleSource": entry.sampleSource,
                "searchToken": Self.searchToken(
                    field: entry.field.rawValue,
                    value: entry.value
                )
            ]
        }
    }

    static func searchToken(field: String, value: String) -> String {
        let escaped = value.replacingOccurrences(of: "\"", with: "\\\"")
        if value.contains(where: { $0.isWhitespace }) {
            return "\(field):\"\(escaped)\""
        }
        return "\(field):\(value)"
    }

    static func activityLogText(
        _ entries: [ActivityLogEntry]
    ) -> String {
        entries.map { entry in
            "[\(dateString(entry.timestamp))] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }

    private static func optionalInt64(_ value: Int64?) -> Any {
        value.map { NSNumber(value: $0) } ?? NSNull()
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func jsonString(_ object: [String: Any]) -> String {
        let data = (
            try? JSONSerialization.data(
                withJSONObject: object,
                options: [.sortedKeys]
            )
        ) ?? Data("{}".utf8)
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func webSocketAcceptKey(for key: String) -> String {
        let payload = Data(
            (key.trimmed + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8
        )
        let digest = Insecure.SHA1.hash(data: payload)
        return Data(digest).base64EncodedString()
    }

    private static func webSocketTextFrame(_ text: String) -> Data {
        let payload = Data(text.utf8)
        var frame = Data([0x81])
        if payload.count <= 125 {
            frame.append(UInt8(payload.count))
        } else if payload.count <= UInt16.max {
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xff))
            frame.append(UInt8(payload.count & 0xff))
        } else {
            frame.append(127)
            var count = UInt64(payload.count).bigEndian
            withUnsafeBytes(of: &count) { frame.append(contentsOf: $0) }
        }
        frame.append(payload)
        return frame
    }
}
