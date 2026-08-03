import Foundation

enum SourceLinkCommandResult: Equatable {
    case unavailable
    case opened
    case failed
}

@MainActor
final class SourceLinkCommandService {
    let workspace: any WorkspaceCommandOpening

    init(
        workspace: any WorkspaceCommandOpening
    ) {
        self.workspace = workspace
    }

    nonisolated static func browserURL(
        for source: String
    ) -> URL? {
        guard let url = URL(string: source.trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return nil
        }
        return url
    }

    func openSource(
        _ source: String,
        skipExternalOpen: Bool
    ) -> SourceLinkCommandResult {
        guard let url = Self.browserURL(
            for: source
        ) else {
            return .unavailable
        }
        return openBrowserURL(
            url,
            skipExternalOpen: skipExternalOpen
        )
    }

    func openBrowserURL(
        _ url: URL,
        skipExternalOpen: Bool
    ) -> SourceLinkCommandResult {
        guard Self.browserURL(
            for: url.absoluteString
        ) != nil else {
            return .unavailable
        }
        guard skipExternalOpen ||
                workspace.open(url) else {
            return .failed
        }
        return .opened
    }
}
