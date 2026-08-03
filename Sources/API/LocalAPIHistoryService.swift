import Foundation

struct LocalAPIHistoryMutationResult {
    var response: LocalHTTPResponse
    var didChange: Bool
}

@MainActor
struct LocalAPIHistoryService {
    private let requestDecoder: LocalAPIRequestDecoder
    private let readModelService: LocalAPIReadModelService

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder(),
        readModelService: LocalAPIReadModelService = LocalAPIReadModelService()
    ) {
        self.requestDecoder = requestDecoder
        self.readModelService = readModelService
    }

    func object(
        history: [DownloadHistoryEntry],
        request: LocalHTTPRequest,
        enabled: Bool,
        limit: Int,
        auth: String
    ) -> [String: Any] {
        let pairs = filteredPairs(history: history, request: request)
        let rangeInfo = readModelService.range(
            from: request,
            total: pairs.count
        )
        let visible = Array(pairs[rangeInfo.range])
        let visibleObjects = objects(visible, auth: auth)
        return [
            "items": visibleObjects,
            "history": visibleObjects,
            "count": rangeInfo.range.count,
            "total": rangeInfo.total,
            "start": rangeInfo.range.lowerBound,
            "end": rangeInfo.range.isEmpty
                ? rangeInfo.range.lowerBound
                : rangeInfo.range.upperBound - 1,
            "endExclusive": rangeInfo.range.upperBound,
            "enabled": enabled,
            "limit": limit,
            "query": query(from: request)
        ]
    }

    func filteredPairs(
        history: [DownloadHistoryEntry],
        request: LocalHTTPRequest
    ) -> [(Int, DownloadHistoryEntry)] {
        let pairs = history.enumerated().map { ($0.offset, $0.element) }
        let search = query(from: request).lowercased()
        guard !search.isEmpty else { return pairs }
        let terms = search
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        return pairs.filter { _, entry in
            let haystack = [
                entry.source,
                entry.normalizedSource,
                entry.title,
                entry.outputPath,
                entry.metadata.keys.joined(separator: " "),
                entry.metadata.values.joined(separator: " ")
            ].joined(separator: "\n").lowercased()
            return terms.allSatisfy { haystack.contains($0) }
        }
    }

    func query(from request: LocalHTTPRequest) -> String {
        LocalAPIRequestDecoder.firstParameterValue(
            in: request.query,
            keys: ["q", "query", "filter", "search"]
        )?.trimmed ?? ""
    }

    func objects(
        _ pairs: [(Int, DownloadHistoryEntry)],
        auth: String
    ) -> [[String: Any]] {
        pairs.map { index, entry in
            let enqueue = "/download?url=\(Self.queryComponent(entry.source))&start=0\(auth)"
            return [
                "index": index,
                "id": entry.id.uuidString,
                "source": entry.source,
                "normalizedSource": entry.normalizedSource,
                "title": entry.title,
                "outputPath": entry.outputPath,
                "completedAt": Self.dateString(entry.completedAt),
                "metadata": entry.metadata,
                "download": enqueue,
                "enqueue": enqueue
            ] as [String: Any]
        }
    }

    func indexes(
        history: [DownloadHistoryEntry],
        request: LocalHTTPRequest
    ) -> [Int] {
        let parameters = requestDecoder.parameters(from: request)
        let explicitIDs = parameters["ids"] ??
            parameters["history_ids"] ??
            parameters["historyIds"]
        if let explicitIDs {
            return indexes(
                history: history,
                tokens: requestDecoder.listValues(from: explicitIDs)
            )
        }
        if let id = parameters["id"] ??
            parameters["history_id"] ??
            parameters["historyId"] {
            return indexes(history: history, tokens: [id])
        }
        if let source = parameters["source"] ?? parameters["url"] {
            let normalized = URLIdentity.normalize(source)
            return history.indices.filter {
                history[$0].source == source ||
                    history[$0].normalizedSource == normalized ||
                    URLIdentity.normalize(history[$0].source) == normalized
            }
        }
        if !query(from: request).isEmpty {
            return filteredPairs(history: history, request: request).map(\.0)
        }
        if let rawIndexes = parameters["indexes"] ?? parameters["indices"] {
            return indexes(
                history: history,
                tokens: requestDecoder.listValues(from: rawIndexes)
            )
        }
        if let index = parameters["index"] ??
            parameters["idx"] ??
            parameters["i"],
           let value = Int(index),
           history.indices.contains(value) {
            return [value]
        }
        return []
    }

    func requeueResponse(
        request: LocalHTTPRequest,
        history: [DownloadHistoryEntry],
        enqueue: (DownloadHistoryEntry) -> Int,
        startQueue: () -> Void,
        queueState: () -> (count: Int, isRunning: Bool)
    ) -> LocalHTTPResponse {
        let selectedIndexes = indexes(history: history, request: request)
        guard !selectedIndexes.isEmpty else {
            return Self.missingEntryResponse()
        }

        var added = 0
        var ids: [String] = []
        for index in selectedIndexes {
            let entry = history[index]
            let delta = enqueue(entry)
            if delta > 0 {
                added += delta
                ids.append(entry.id.uuidString)
            }
        }
        let parameters = requestDecoder.parameters(from: request)
        if added > 0,
           (parameters["start"] ?? parameters["run"] ?? "0") != "0" {
            startQueue()
        }
        let state = queueState()
        return LocalHTTPResponse.jsonObject([
            "ok": added > 0,
            "res": added > 0 ? "ok" : "skipped",
            "requeued": added > 0,
            "requeuedCount": added,
            "added": added,
            "id": ids.first ?? "",
            "ids": ids,
            "count": state.count,
            "historyCount": history.count,
            "running": state.isRunning
        ])
    }

    func removeResponse(
        request: LocalHTTPRequest,
        history: inout [DownloadHistoryEntry]
    ) -> LocalAPIHistoryMutationResult {
        let selectedIndexes = indexes(history: history, request: request)
        guard !selectedIndexes.isEmpty else {
            return LocalAPIHistoryMutationResult(
                response: Self.missingEntryResponse(),
                didChange: false
            )
        }

        let removedIDs = selectedIndexes.sorted(by: >).map { index in
            let id = history[index].id.uuidString
            history.remove(at: index)
            return id
        }
        return LocalAPIHistoryMutationResult(
            response: LocalHTTPResponse.jsonObject([
                "ok": !removedIDs.isEmpty,
                "res": !removedIDs.isEmpty ? "ok" : "skipped",
                "removed": !removedIDs.isEmpty,
                "removedCount": removedIDs.count,
                "id": removedIDs.last ?? "",
                "ids": Array(removedIDs.reversed()),
                "count": history.count
            ]),
            didChange: !removedIDs.isEmpty
        )
    }

    func clearResponse(
        removedCount: Int,
        remainingCount: Int
    ) -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject([
            "ok": true,
            "res": "ok",
            "cleared": true,
            "removed": removedCount,
            "removedCount": removedCount,
            "count": remainingCount
        ])
    }

    private func indexes(
        history: [DownloadHistoryEntry],
        tokens: [String]
    ) -> [Int] {
        var indexes: [Int] = []
        var seen = Set<Int>()
        for token in tokens {
            let value = token.trimmed
            let index: Int?
            if let uuid = UUID(uuidString: value) {
                index = history.firstIndex { $0.id == uuid }
            } else if let numeric = Int(value), history.indices.contains(numeric) {
                index = numeric
            } else {
                index = nil
            }
            guard let index, seen.insert(index).inserted else { continue }
            indexes.append(index)
        }
        return indexes
    }

    private static func missingEntryResponse() -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject(
            ["error": "History entry not found"],
            status: 404
        )
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }

    static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
