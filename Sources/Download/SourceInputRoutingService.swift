import Foundation

enum SourceInputRoute: Equatable {
    case discordEmoji(DiscordEmojiRequest)
    case testingResolved(URL)
    case aria2(URL)
    case localFile(URL)
    case directFile(URL)
    case originalInput(OriginalInputType, URL)
    case web(URL)
}

struct SourceInputRoutingService {
    func route(
        source: String,
        directDownloadOverride: Bool,
        originalInputType: OriginalInputType?,
        testingResolvedDownloadAvailable: Bool = false,
        aria2CanResolve: (URL) -> Bool,
        retiredHTTPMessage: (URL) -> String?
    ) throws -> SourceInputRoute {
        if let request = DiscordEmojiResolver.request(from: source) {
            return .discordEmoji(request)
        }

        guard let url = URL(string: source.trimmed),
              let scheme = url.scheme?.lowercased() else {
            throw NativeDownloadError.invalidURL(source)
        }

        if testingResolvedDownloadAvailable {
            return .testingResolved(url)
        }

        if scheme == "magnet" {
            return .aria2(url)
        }

        if scheme == "file" {
            return aria2CanResolve(url) ? .aria2(url) : .localFile(url)
        }

        guard scheme == "http" || scheme == "https" else {
            throw NativeDownloadError.unsupported(
                "Unsupported URL scheme: \(scheme)"
            )
        }

        if directDownloadOverride {
            return .directFile(url)
        }

        if let message = retiredHTTPMessage(url) {
            throw NativeDownloadError.unsupported(message)
        }

        if let originalInputType {
            return .originalInput(originalInputType, url)
        }

        return .web(url)
    }
}
