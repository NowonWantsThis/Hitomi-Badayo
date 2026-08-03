import Foundation

@MainActor
struct LocalAPIDiagnosticFacade {
    private let readModelService: LocalAPIReadModelService
    private let diagnosticPageRenderer: LocalAPIDiagnosticPageRenderer
    private let metadataPageRenderer: LocalAPIMetadataPageRenderer
    private let requestDecoder: LocalAPIRequestDecoder

    init() {
        readModelService = LocalAPIReadModelService()
        diagnosticPageRenderer = LocalAPIDiagnosticPageRenderer()
        metadataPageRenderer = LocalAPIMetadataPageRenderer()
        requestDecoder = LocalAPIRequestDecoder()
    }

    init(
        readModelService: LocalAPIReadModelService,
        diagnosticPageRenderer: LocalAPIDiagnosticPageRenderer,
        metadataPageRenderer: LocalAPIMetadataPageRenderer,
        requestDecoder: LocalAPIRequestDecoder
    ) {
        self.readModelService = readModelService
        self.diagnosticPageRenderer = diagnosticPageRenderer
        self.metadataPageRenderer = metadataPageRenderer
        self.requestDecoder = requestDecoder
    }

    func statusObject(_ snapshot: LocalAPIStatusSnapshot) -> [String: Any] {
        readModelService.statusObject(snapshot)
    }

    func logObject(
        request: LocalHTTPRequest,
        entries: [ActivityLogEntry],
        limit: Int
    ) -> [String: Any] {
        readModelService.logObject(
            entries: entries,
            request: request,
            limit: limit
        )
    }

    func logPage(
        request: LocalHTTPRequest,
        entries: [ActivityLogEntry]
    ) -> String {
        let password = password(from: request)
        let autoRefresh =
            (request.query["auto"] ?? request.query["refresh"] ?? "1") != "0"
        return diagnosticPageRenderer.logPage(
            password: password,
            logText: LocalAPIReadModelService.activityLogText(entries),
            isEmpty: entries.isEmpty,
            autoRefresh: autoRefresh
        )
    }

    func clearLogResponse(
        request: LocalHTTPRequest,
        clear: () -> Int,
        standaloneAuthQuery: (String) -> String
    ) -> LocalHTTPResponse {
        let remainingCount = clear()
        if request.path.lowercased().hasPrefix("/api/") {
            return LocalHTTPResponse.jsonObject([
                "cleared": true,
                "count": remainingCount
            ])
        }

        let parameters = requestDecoder.parameters(from: request)
        let password = parameters["pw"] ?? parameters["password"] ?? ""
        return LocalHTTPResponse(
            status: 302,
            contentType: "text/plain; charset=utf-8",
            body: Data("Redirecting".utf8),
            headers: [
                "Location": "/log\(standaloneAuthQuery(password))"
            ]
        )
    }

    func directoriesObject(
        request: LocalHTTPRequest,
        entries: [OutputDirectoryEntry],
        text: ([OutputDirectoryEntry]) -> String
    ) -> [String: Any] {
        let rangeInfo = readModelService.range(
            from: request,
            total: entries.count
        )
        return readModelService.directoriesObject(
            entries: entries,
            text: text(Array(entries[rangeInfo.range])),
            request: request
        )
    }

    func directoriesPage(
        request: LocalHTTPRequest,
        entries: [OutputDirectoryEntry],
        text: ([OutputDirectoryEntry]) -> String
    ) -> String {
        diagnosticPageRenderer.directoriesPage(
            password: password(from: request),
            text: text(entries),
            isEmpty: entries.isEmpty
        )
    }

    func finderObject(
        request: LocalHTTPRequest,
        results: (LocalAPIFinderRequest) -> [MetadataFinderResult]
    ) -> [String: Any] {
        let build = readModelService.finderRequest(from: request)
        return readModelService.finderObject(
            request: build,
            results: results(build)
        )
    }

    func finderPage(
        request: LocalHTTPRequest,
        results: (LocalAPIFinderRequest) -> [MetadataFinderResult]
    ) -> String {
        let build = readModelService.finderRequest(from: request)
        return metadataPageRenderer.finderPage(
            password: password(from: request),
            field: build.field,
            mode: build.mode,
            query: build.query,
            items: results(build).map { result in
                LocalAPIFinderPageItem(
                    result: result,
                    searchToken: LocalAPIReadModelService.searchToken(
                        field: result.field.rawValue,
                        value: result.value
                    )
                )
            }
        )
    }

    func analysisObject(
        request: LocalHTTPRequest,
        entries: (LocalAPIAnalysisRequest) -> [MetadataAnalysisEntry]
    ) -> [String: Any] {
        let build = readModelService.analysisRequest(from: request)
        return readModelService.analysisObject(
            request: build,
            entries: entries(build)
        )
    }

    func analysisPage(
        request: LocalHTTPRequest,
        entries: (LocalAPIAnalysisRequest) -> [MetadataAnalysisEntry]
    ) -> String {
        let build = readModelService.analysisRequest(from: request)
        return metadataPageRenderer.analysisPage(
            password: password(from: request),
            field: build.field,
            items: entries(build).map { entry in
                LocalAPIAnalysisPageItem(
                    entry: entry,
                    searchToken: LocalAPIReadModelService.searchToken(
                        field: entry.field.rawValue,
                        value: entry.value
                    )
                )
            }
        )
    }

    func statisticsObject(_ statistics: AppStatistics) -> [String: Any] {
        readModelService.statisticsObject(statistics)
    }

    func eventsResponse(
        statusObject: [String: Any]
    ) -> LocalHTTPResponse {
        readModelService.eventsResponse(statusObject: statusObject)
    }

    func webSocketResponse(
        request: LocalHTTPRequest,
        statusObject: [String: Any]
    ) -> LocalHTTPResponse {
        readModelService.webSocketResponse(
            request: request,
            statusObject: statusObject
        )
    }

    func range(
        from request: LocalHTTPRequest,
        total: Int
    ) -> APIItemRange {
        readModelService.range(from: request, total: total)
    }

    private func password(from request: LocalHTTPRequest) -> String {
        request.query["pw"] ?? request.query["password"] ?? ""
    }
}
