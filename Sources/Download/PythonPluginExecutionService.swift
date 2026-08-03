import Foundation

@MainActor
final class PythonPluginExecutionService {
    typealias Resolver = @MainActor (
        String,
        PythonSourceExecutionMatch,
        URL,
        HTTPRequestOptions
    ) async throws -> ResolvedDownload

    private let resolver: Resolver

    init(
        resolver: @escaping Resolver = { pythonPath, match, sourceURL, headers in
            try await PythonScriptBridge(
                configuredPythonPath: pythonPath
            ).resolve(
                plugin: match.plugin,
                downloader: match.downloader,
                sourceURL: sourceURL,
                headers: headers
            )
        }
    ) {
        self.resolver = resolver
    }

    func execute(
        _ match: PythonSourceExecutionMatch,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        configuredPythonPath: String,
        downloadResolved: (ResolvedDownload, URL) async throws -> Void,
        delegateToNativeResolver: (String) async -> Void
    ) async throws {
        do {
            let resolved = try await resolver(
                configuredPythonPath,
                match,
                sourceURL,
                headers
            )
            try await downloadResolved(resolved, sourceURL)
        } catch PythonScriptBridgeError.nativeDelegation(let feature) {
            await delegateToNativeResolver(feature)
        }
    }
}
