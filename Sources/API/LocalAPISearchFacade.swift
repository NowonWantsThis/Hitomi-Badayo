import Foundation

@MainActor
struct LocalAPISearchFacade {
    private let service: LocalAPISearchService
    private let pageRenderer: LocalAPISearchPageRenderer

    init() {
        service = LocalAPISearchService()
        pageRenderer = LocalAPISearchPageRenderer()
    }

    init(
        service: LocalAPISearchService,
        pageRenderer: LocalAPISearchPageRenderer
    ) {
        self.service = service
        self.pageRenderer = pageRenderer
    }

    func response(
        request: LocalHTTPRequest,
        providers: [SearchProvider],
        bookmarks: [SearchBookmark],
        selectedProviderID: UUID,
        selectedProvider: SearchProvider?
    ) -> LocalHTTPResponse {
        service.response(
            request: request,
            build: build(
                request: request,
                providers: providers,
                selectedProviderID: selectedProviderID
            ),
            providers: providers,
            bookmarks: bookmarks,
            selectedProvider: selectedProvider
        )
    }

    func providersObject(
        request: LocalHTTPRequest,
        providers: [SearchProvider],
        bookmarks: [SearchBookmark],
        selectedProvider: SearchProvider?
    ) -> [String: Any] {
        service.providersObject(
            request: request,
            providers: providers,
            bookmarks: bookmarks,
            selectedProvider: selectedProvider
        )
    }

    func enqueueResponse(
        request: LocalHTTPRequest,
        providers: [SearchProvider],
        selectedProviderID: UUID,
        enqueue: (String) -> Int,
        startQueue: () -> Void,
        queueState: () -> (count: Int, isRunning: Bool)
    ) -> LocalHTTPResponse {
        service.enqueueResponse(
            request: request,
            build: build(
                request: request,
                providers: providers,
                selectedProviderID: selectedProviderID
            ),
            enqueue: enqueue,
            startQueue: startQueue,
            queueState: queueState
        )
    }

    func page(
        request: LocalHTTPRequest,
        providers: [SearchProvider],
        bookmarks: [SearchBookmark],
        selectedProviderID: UUID,
        selectedProvider: SearchProvider?
    ) -> String {
        let build = build(
            request: request,
            providers: providers,
            selectedProviderID: selectedProviderID
        )
        let selectedID = build.provider?.id ?? selectedProvider?.id
        return pageRenderer.page(
            password: password(from: request),
            build: build,
            providers: providers,
            selectedProviderID: selectedID,
            bookmarks: bookmarks.map { bookmark in
                let provider = SearchQueryFacade.provider(
                    for: bookmark,
                    in: providers
                )
                let providerName = provider?.name ?? bookmark.providerName
                return LocalAPISearchBookmarkPageItem(
                    title: bookmark.title.isEmpty
                        ? SearchQueryFacade.bookmarkTitle(
                            providerName: providerName,
                            query: bookmark.query
                        )
                        : bookmark.title,
                    providerName: providerName,
                    query: bookmark.query,
                    url: provider.flatMap {
                        SearchQueryFacade.searchURL(
                            provider: $0,
                            query: bookmark.query
                        )
                    }
                )
            }
        )
    }

    private func build(
        request: LocalHTTPRequest,
        providers: [SearchProvider],
        selectedProviderID: UUID
    ) -> LocalAPISearchBuild {
        service.build(
            from: request,
            providers: providers,
            selectedProviderID: selectedProviderID
        )
    }

    private func password(from request: LocalHTTPRequest) -> String {
        request.query["pw"] ?? request.query["password"] ?? ""
    }
}
