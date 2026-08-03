import Foundation

@MainActor
struct LocalAPIHistoryFacade {
    private let service: LocalAPIHistoryService
    private let pageRenderer: LocalAPIHistoryPageRenderer
    private let readModelService: LocalAPIReadModelService

    init() {
        service = LocalAPIHistoryService()
        pageRenderer = LocalAPIHistoryPageRenderer()
        readModelService = LocalAPIReadModelService()
    }

    init(
        service: LocalAPIHistoryService,
        pageRenderer: LocalAPIHistoryPageRenderer,
        readModelService: LocalAPIReadModelService
    ) {
        self.service = service
        self.pageRenderer = pageRenderer
        self.readModelService = readModelService
    }

    func object(
        request: LocalHTTPRequest,
        history: [DownloadHistoryEntry],
        enabled: Bool,
        limit: Int,
        authQuery: (String) -> String
    ) -> [String: Any] {
        service.object(
            history: history,
            request: request,
            enabled: enabled,
            limit: limit,
            auth: authQuery(password(from: request))
        )
    }

    func page(
        request: LocalHTTPRequest,
        history: [DownloadHistoryEntry]
    ) -> String {
        let pairs = service.filteredPairs(
            history: history,
            request: request
        )
        let rangeInfo = readModelService.range(
            from: request,
            total: pairs.count
        )
        let visible = Array(pairs[rangeInfo.range])
        let step = max(
            1,
            min(500, Int(request.query["step"] ?? "") ?? 50)
        )
        let page = max(
            0,
            Int(request.query["p"] ?? request.query["page"] ?? "") ?? 0
        )
        let pageCount = max(
            1,
            Int(ceil(Double(max(1, rangeInfo.total)) / Double(step)))
        )
        return pageRenderer.page(
            password: password(from: request),
            state: LocalAPIHistoryPageState(
                items: visible.map { index, entry in
                    LocalAPIHistoryPageItem(
                        index: index,
                        id: entry.id,
                        source: entry.source,
                        title: entry.title,
                        outputPath: entry.outputPath,
                        completedText: LocalAPIHistoryService.dateString(
                            entry.completedAt
                        ),
                        site: entry.metadata["site"] ??
                            entry.metadata["host"] ?? ""
                    )
                },
                visibleCount: rangeInfo.range.count,
                totalCount: rangeInfo.total,
                step: step,
                page: page,
                pageCount: pageCount,
                query: service.query(from: request),
                showsPaging: request.query["p"] != nil ||
                    request.query["page"] != nil ||
                    request.query["step"] != nil
            )
        )
    }

    func requeueResponse(
        request: LocalHTTPRequest,
        history: [DownloadHistoryEntry],
        enqueue: (DownloadHistoryEntry) -> Int,
        startQueue: () -> Void,
        queueState: () -> (count: Int, isRunning: Bool)
    ) -> LocalHTTPResponse {
        service.requeueResponse(
            request: request,
            history: history,
            enqueue: enqueue,
            startQueue: startQueue,
            queueState: queueState
        )
    }

    func removeResponse(
        request: LocalHTTPRequest,
        history: inout [DownloadHistoryEntry],
        persist: ([DownloadHistoryEntry]) -> Void
    ) -> LocalHTTPResponse {
        let result = service.removeResponse(
            request: request,
            history: &history
        )
        if result.didChange {
            persist(history)
        }
        return result.response
    }

    func clearResponse(
        historyCount: Int,
        clear: () -> Int
    ) -> LocalHTTPResponse {
        service.clearResponse(
            removedCount: historyCount,
            remainingCount: clear()
        )
    }

    private func password(from request: LocalHTTPRequest) -> String {
        request.query["pw"] ?? request.query["password"] ?? ""
    }
}
