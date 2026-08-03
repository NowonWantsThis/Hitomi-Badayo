import Foundation

@MainActor
struct LocalAPIInputFacade {
    private let browserService: LocalAPIBrowserService
    private let clipboardService: LocalAPIClipboardService
    private let pageRenderer: LocalAPIInputPageRenderer

    init() {
        browserService = LocalAPIBrowserService()
        clipboardService = LocalAPIClipboardService()
        pageRenderer = LocalAPIInputPageRenderer()
    }

    init(
        browserService: LocalAPIBrowserService,
        clipboardService: LocalAPIClipboardService,
        pageRenderer: LocalAPIInputPageRenderer
    ) {
        self.browserService = browserService
        self.clipboardService = clipboardService
        self.pageRenderer = pageRenderer
    }

    func browserObject(
        request: LocalHTTPRequest,
        inputText: String,
        cookieSummary: String,
        parameterURL: (String) -> URL?,
        fallbackURL: () -> URL?
    ) -> [String: Any] {
        browserService.object(
            request: request,
            selection: browserSelection(
                request: request,
                inputText: inputText,
                parameterURL: parameterURL,
                fallbackURL: fallbackURL
            ),
            cookieSummary: cookieSummary
        )
    }

    func browserPage(
        request: LocalHTTPRequest,
        inputText: String,
        cookieSummary: String,
        parameterURL: (String) -> URL?,
        fallbackURL: () -> URL?
    ) -> String {
        pageRenderer.browserPage(
            password: password(from: request),
            selection: browserSelection(
                request: request,
                inputText: inputText,
                parameterURL: parameterURL,
                fallbackURL: fallbackURL
            ),
            cookieSummary: cookieSummary
        )
    }

    func browserOpenResponse(
        request: LocalHTTPRequest,
        inputText: String,
        cookieSummary: String,
        parameterURL: (String) -> URL?,
        fallbackURL: () -> URL?,
        openBrowser: (URL) -> Void
    ) -> LocalHTTPResponse {
        browserService.openResponse(
            request: request,
            selection: browserSelection(
                request: request,
                inputText: inputText,
                parameterURL: parameterURL,
                fallbackURL: fallbackURL
            ),
            cookieSummary: cookieSummary,
            openBrowser: openBrowser
        )
    }

    func clipboardObject(
        request: LocalHTTPRequest,
        explicitText: String? = nil,
        source: String? = nil,
        monitorEnabled: Bool,
        changeCount: Int,
        clipboardText: () -> String?,
        candidateURLs: (String) -> [String],
        inputTypeObjects: (String) -> [[String: Any]]
    ) -> [String: Any] {
        clipboardService.object(
            request: request,
            explicitText: explicitText,
            source: source,
            monitorEnabled: monitorEnabled,
            changeCount: changeCount,
            clipboardText: clipboardText,
            candidateURLs: candidateURLs,
            inputTypeObjects: inputTypeObjects
        )
    }

    func clipboardPage(
        request: LocalHTTPRequest,
        monitorEnabled: Bool,
        clipboardText: () -> String?,
        candidateURLs: (String) -> [String],
        classify: (String) -> SourceInputClassification
    ) -> String {
        let input = clipboardService.input(
            from: request,
            clipboardText: clipboardText
        )
        let urls = candidateURLs(input.text)
        return pageRenderer.clipboardPage(
            password: password(from: request),
            inputText: input.text,
            items: urls.map { url in
                let classification = classify(url)
                return LocalAPIClipboardPageItem(
                    url: url,
                    type: classification.type,
                    resolver: classification.resolver
                )
            },
            monitorEnabled: monitorEnabled
        )
    }

    func clipboardEnqueueResponse(
        request: LocalHTTPRequest,
        monitorEnabled: Bool,
        clipboardText: () -> String?,
        candidateURLs: (String) -> [String],
        enqueue: ([String]) -> Int,
        startQueue: () -> Void,
        queueState: () -> (count: Int, isRunning: Bool)
    ) -> LocalHTTPResponse {
        clipboardService.enqueueResponse(
            request: request,
            monitorEnabled: monitorEnabled,
            clipboardText: clipboardText,
            candidateURLs: candidateURLs,
            enqueue: enqueue,
            startQueue: startQueue,
            queueState: queueState
        )
    }

    func clipboardWatchResponse(
        request: LocalHTTPRequest,
        currentEnabled: Bool,
        setEnabled: (Bool) -> Void,
        currentState: () -> (enabled: Bool, message: String)
    ) -> LocalHTTPResponse {
        clipboardService.watchResponse(
            request: request,
            currentEnabled: currentEnabled,
            setEnabled: setEnabled,
            currentState: currentState
        )
    }

    private func browserSelection(
        request: LocalHTTPRequest,
        inputText: String,
        parameterURL: (String) -> URL?,
        fallbackURL: () -> URL?
    ) -> LocalAPIBrowserSelection {
        browserService.selection(
            from: request,
            inputText: inputText,
            parameterURL: parameterURL,
            fallbackURL: fallbackURL
        )
    }

    private func password(from request: LocalHTTPRequest) -> String {
        request.query["pw"] ?? request.query["password"] ?? ""
    }
}
