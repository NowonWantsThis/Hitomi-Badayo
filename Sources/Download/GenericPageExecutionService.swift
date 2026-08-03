import Foundation

protocol GenericPageResolving: AnyObject {
    func resolveIfPossible(
        _ url: URL,
        headers: HTTPRequestOptions
    ) async throws -> ResolvedDownload?
}

extension GenericPageResolver: GenericPageResolving {}

@MainActor
final class GenericPageExecutionService {
    let resolver: any GenericPageResolving

    init(resolver: any GenericPageResolving) {
        self.resolver = resolver
    }

    func execute(
        url: URL,
        headers: HTTPRequestOptions,
        reportStatus: (String) -> Void,
        downloadResolved: (ResolvedDownload, URL) async throws -> Void,
        downloadDirect: (URL) async throws -> Void
    ) async throws {
        reportStatus(Self.statusMessage)
        if let resolved = try await resolver.resolveIfPossible(
            url,
            headers: headers
        ) {
            try await downloadResolved(resolved, url)
        } else {
            try await downloadDirect(url)
        }
    }

    nonisolated static let statusMessage = "Scanning page media"
}
