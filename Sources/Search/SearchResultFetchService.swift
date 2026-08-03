import Foundation

@MainActor
final class SearchResultFetchService {
    typealias HTMLFetcher =
        @MainActor (
            URL,
            HTTPRequestOptions
        ) async throws -> String
    typealias LinkExtractor =
        @MainActor (
            String,
            URL
        ) -> [SearchResultLink]

    private let fetchHTML: HTMLFetcher
    private let extractLinks: LinkExtractor

    init(
        fetchHTML:
            @escaping HTMLFetcher = { url, options in
                try await HTTPClient.shared.string(
                    from: url,
                    referer: options.referer,
                    userAgent: options.userAgent
                )
            },
        extractLinks:
            @escaping LinkExtractor = { html, url in
                SearchResultExtractor.extractLinks(
                    from: html,
                    baseURL: url
                )
            }
    ) {
        self.fetchHTML = fetchHTML
        self.extractLinks = extractLinks
    }

    func fetchLinks(
        from url: URL,
        options: HTTPRequestOptions
    ) async throws -> [SearchResultLink] {
        let html = try await fetchHTML(url, options)
        try Task.checkCancellation()
        let links = extractLinks(html, url)
        try Task.checkCancellation()
        return links
    }
}
