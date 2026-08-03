import Foundation

struct SourceExecutionActions {
    var ytDLPCanResolve: (URL) -> Bool
    var downloadWithYTDLP: (URL) async throws -> Void
    var downloadWithAria2: (URL) async throws -> Void
    var executeResolverPlan:
        (SourceResolverExecutionPlan, URL) async throws -> Void
    var executePythonPlugin:
        (PythonSourceExecutionMatch, URL) async throws -> Void
    var downloadWithCustomCommand:
        (URL, SiteRule) async throws -> Void
    var executeGenericPage: (URL) async throws -> Void
    var downloadDirect: (URL) async throws -> Void
}

@MainActor
final class SourceExecutionDispatchService {
    func execute(
        _ route: SourceExecutionRoute,
        url: URL,
        actions: SourceExecutionActions
    ) async throws {
        switch route {
        case .audioExtraction:
            guard actions.ytDLPCanResolve(url) else {
                throw NativeDownloadError.unsupported(
                    "MP3 audio extraction requires a yt-dlp supported media URL."
                )
            }
            try await actions.downloadWithYTDLP(url)
        case .aria2:
            try await actions.downloadWithAria2(url)
        case .pawchive(let plan), .builtIn(let plan):
            try await actions.executeResolverPlan(plan, url)
        case .pythonPlugin(let script):
            try await actions.executePythonPlugin(script, url)
        case .customCommand(let rule):
            try await actions.downloadWithCustomCommand(url, rule)
        case .ytDLP:
            try await actions.downloadWithYTDLP(url)
        case .genericPage:
            try await actions.executeGenericPage(url)
        case .direct:
            try await actions.downloadDirect(url)
        }
    }
}
