import Foundation

enum SourceInputExecutionResult: Equatable {
    case handled
    case web(URL)
}

struct SourceInputExecutionActions {
    var downloadDiscordEmoji:
        (DiscordEmojiRequest) async throws -> Void
    var downloadTestingResolved: (URL) async throws -> Void
    var downloadWithAria2: (URL) async throws -> Void
    var downloadLocalFile: (URL) async throws -> Void
    var downloadDirectFile: (URL) async throws -> Void
    var downloadOriginalInput:
        (OriginalInputType, URL) async throws -> Void
}

@MainActor
final class SourceInputExecutionDispatchService {
    func execute(
        _ route: SourceInputRoute,
        actions: SourceInputExecutionActions
    ) async throws -> SourceInputExecutionResult {
        switch route {
        case .discordEmoji(let request):
            try await actions.downloadDiscordEmoji(request)
            return .handled
        case .testingResolved(let url):
            try await actions.downloadTestingResolved(url)
            return .handled
        case .aria2(let url):
            try await actions.downloadWithAria2(url)
            return .handled
        case .localFile(let url):
            try await actions.downloadLocalFile(url)
            return .handled
        case .directFile(let url):
            try await actions.downloadDirectFile(url)
            return .handled
        case .originalInput(let type, let url):
            try await actions.downloadOriginalInput(type, url)
            return .handled
        case .web(let url):
            return .web(url)
        }
    }
}
