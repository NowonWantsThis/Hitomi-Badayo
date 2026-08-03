import Foundation

struct LocalAPISearchBuild {
    var query: String
    var provider: SearchProvider?
    var providerKey: String
    var providerMissing: Bool
    var url: URL?
}

@MainActor
struct LocalAPISearchService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func build(
        from request: LocalHTTPRequest,
        providers: [SearchProvider],
        selectedProviderID: UUID
    ) -> LocalAPISearchBuild {
        let parameters = requestDecoder.parameters(from: request)
        let rawInput = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["input", "text", "data"]
        )
        let rawQuery = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["q", "query", "search", "keyword", "keywords"]
        )
        let explicitProviderKey = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: [
                "provider", "provider_name", "providerName", "engine",
                "site", "name"
            ]
        )

        var query = (rawQuery ?? rawInput ?? "").trimmed
        var parsedProviderKey: String?
        let shouldParseQuickSearch = rawQuery == nil ||
            LocalAPIRequestDecoder.truthy(parameters["quick"])
        if shouldParseQuickSearch,
           let parsed = SearchQueryFacade.quickRequest(from: query) {
            parsedProviderKey = parsed.providerKey
            query = parsed.query
        }

        let providerKey = (
            explicitProviderKey ?? parsedProviderKey ?? ""
        ).trimmed
        let provider: SearchProvider?
        let providerMissing: Bool
        if providerKey.isEmpty {
            provider = SearchQueryFacade.selectedProvider(
                in: providers,
                selectedProviderID: selectedProviderID
            )
            providerMissing = false
        } else {
            provider = SearchQueryFacade.provider(
                matching: providerKey,
                in: providers
            )
            providerMissing = provider == nil
        }
        return LocalAPISearchBuild(
            query: query,
            provider: provider,
            providerKey: providerKey,
            providerMissing: providerMissing,
            url: provider.flatMap {
                SearchQueryFacade.searchURL(provider: $0, query: query)
            }
        )
    }

    func response(
        request: LocalHTTPRequest,
        build: LocalAPISearchBuild,
        providers: [SearchProvider],
        bookmarks: [SearchBookmark],
        selectedProvider: SearchProvider?
    ) -> LocalHTTPResponse {
        if build.providerMissing {
            return Self.providerMissingResponse(build.providerKey)
        }
        return LocalHTTPResponse.jsonObject(
            object(
                request: request,
                build: build,
                providers: providers,
                bookmarks: bookmarks,
                selectedProvider: selectedProvider
            )
        )
    }

    func providersObject(
        request: LocalHTTPRequest,
        providers: [SearchProvider],
        bookmarks: [SearchBookmark],
        selectedProvider: SearchProvider?
    ) -> [String: Any] {
        let auth = Self.authQuery(
            request.query["pw"] ?? request.query["password"] ?? ""
        )
        let selectedID = selectedProvider?.id
        var object: [String: Any] = [
            "count": providers.count,
            "providers": providerObjects(
                providers,
                selectedID: selectedID
            ),
            "bookmarks": bookmarkObjects(
                bookmarks,
                providers: providers,
                auth: auth
            ),
            "bookmarkCount": bookmarks.count
        ]
        if let selectedProvider {
            object["selectedProvider"] = providerObject(
                selectedProvider,
                selectedID: selectedProvider.id
            )
        } else {
            object["selectedProvider"] = NSNull()
        }
        return object
    }

    func object(
        request: LocalHTTPRequest,
        build: LocalAPISearchBuild,
        providers: [SearchProvider],
        bookmarks: [SearchBookmark],
        selectedProvider: SearchProvider?
    ) -> [String: Any] {
        let password = request.query["pw"] ?? request.query["password"] ?? ""
        let auth = Self.authQuery(password)
        let provider = build.provider
        let urlString = build.url?.absoluteString
        var object = providersObject(
            request: request,
            providers: providers,
            bookmarks: bookmarks,
            selectedProvider: selectedProvider
        )
        object["ok"] = build.query.isEmpty || urlString != nil
        object["res"] = urlString == nil && !build.query.isEmpty
            ? "error"
            : "ok"
        object["query"] = build.query
        object["provider"] = provider?.name ?? build.providerKey
        object["providerID"] = provider?.id.uuidString ?? ""
        object["url"] = urlString.map { $0 as Any } ?? NSNull()
        object["searchURL"] = urlString.map { $0 as Any } ?? NSNull()
        object["enqueue"] = enqueueLink(
            query: build.query,
            provider: provider,
            auth: auth
        ).map { $0 as Any } ?? NSNull()
        object["download"] = urlString.map {
            "/download?url=\(Self.queryComponent($0))&start=0\(auth)" as Any
        } ?? NSNull()
        return object
    }

    func enqueueResponse(
        request: LocalHTTPRequest,
        build: LocalAPISearchBuild,
        enqueue: (String) -> Int,
        startQueue: () -> Void,
        queueState: () -> (count: Int, isRunning: Bool)
    ) -> LocalHTTPResponse {
        if build.providerMissing {
            return Self.providerMissingResponse(build.providerKey)
        }
        guard let url = build.url else {
            return LocalHTTPResponse.jsonObject([
                "ok": false,
                "res": "error",
                "error": "Missing search query"
            ], status: 400)
        }

        let added = enqueue(url.absoluteString)
        let parameters = requestDecoder.parameters(from: request)
        let shouldStart = (
            parameters["start"] ?? parameters["run"] ?? "0"
        ) != "0"
        if added > 0, shouldStart {
            startQueue()
        }
        let state = queueState()
        let message = "\(added) URL\(added == 1 ? "" : "s") added"
        return LocalHTTPResponse.jsonObject([
            "ok": added > 0,
            "res": added > 0 ? "ok" : "skipped",
            "message": message,
            "added": added,
            "total": state.count,
            "running": state.isRunning,
            "provider": build.provider?.name ?? "",
            "providerID": build.provider?.id.uuidString ?? "",
            "query": build.query,
            "url": url.absoluteString
        ])
    }

    func providerObjects(
        _ providers: [SearchProvider],
        selectedID: UUID?
    ) -> [[String: Any]] {
        providers.map { providerObject($0, selectedID: selectedID) }
    }

    func providerObject(
        _ provider: SearchProvider,
        selectedID: UUID?
    ) -> [String: Any] {
        [
            "id": provider.id.uuidString,
            "name": provider.name,
            "urlTemplate": provider.urlTemplate,
            "createdAt": Self.dateString(provider.createdAt),
            "selected": provider.id == selectedID
        ]
    }

    func bookmarkObjects(
        _ bookmarks: [SearchBookmark],
        providers: [SearchProvider],
        auth: String
    ) -> [[String: Any]] {
        bookmarks.map { bookmark in
            let provider = SearchQueryFacade.provider(
                for: bookmark,
                in: providers
            )
            let url = provider.flatMap {
                SearchQueryFacade.searchURL(
                    provider: $0,
                    query: bookmark.query
                )
            }
            return [
                "id": bookmark.id.uuidString,
                "title": bookmark.title,
                "provider": provider?.name ?? bookmark.providerName,
                "providerID": provider?.id.uuidString ??
                    bookmark.providerID?.uuidString ??
                    "",
                "query": bookmark.query,
                "createdAt": Self.dateString(bookmark.createdAt),
                "url": url.map { $0.absoluteString as Any } ?? NSNull(),
                "enqueue": enqueueLink(
                    query: bookmark.query,
                    provider: provider,
                    auth: auth
                ).map { $0 as Any } ?? NSNull()
            ] as [String: Any]
        }
    }

    func enqueueLink(
        query: String,
        provider: SearchProvider?,
        auth: String
    ) -> String? {
        guard let provider, !query.trimmed.isEmpty else { return nil }
        return "/search/enqueue?provider=\(Self.queryComponent(provider.name))&q=\(Self.queryComponent(query))&start=0\(auth)"
    }

    private static func providerMissingResponse(
        _ providerKey: String
    ) -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject([
            "ok": false,
            "res": "error",
            "error": "Search provider not found",
            "provider": providerKey
        ], status: 404)
    }

    private static func authQuery(_ password: String) -> String {
        guard !password.isEmpty,
              let encoded = password.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed
              ) else {
            return ""
        }
        return "&pw=\(encoded)"
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }

    private static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
