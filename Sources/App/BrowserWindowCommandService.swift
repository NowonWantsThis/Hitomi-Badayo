import Foundation

enum BrowserWindowHTTPPageCommandResult:
    Equatable
{
    case missingURL
    case unavailable
    case opened

    var summary: String {
        switch self {
        case .missingURL:
            return "No browser URL"
        case .unavailable:
            return "Browser page unavailable"
        case .opened:
            return "Browser page opened"
        }
    }
}

@MainActor
final class BrowserWindowCommandService {
    let authenticationPolicy:
        SourceAuthenticationPolicy
    let sourceLinkCommandService:
        SourceLinkCommandService

    init(
        authenticationPolicy:
            SourceAuthenticationPolicy,
        sourceLinkCommandService:
            SourceLinkCommandService
    ) {
        self.authenticationPolicy =
            authenticationPolicy
        self.sourceLinkCommandService =
            sourceLinkCommandService
    }

    func selection(
        inputText: String,
        jobs: [DownloadJob],
        normalizingToken:
            (String) -> String
    ) -> SourceAuthenticationURLSelection {
        authenticationPolicy.browserURLSelection(
            inputText: inputText,
            jobs: jobs,
            normalizingToken:
                normalizingToken
        )
    }

    func targetURL(
        text: String,
        normalizingToken:
            (String) -> String
    ) -> URL? {
        authenticationPolicy.firstWebURL(
            from: text,
            normalizingToken:
                normalizingToken
        )
    }

    func targetSummary(
        text: String,
        source: String,
        normalizingToken:
            (String) -> String
    ) -> String {
        guard let url = targetURL(
            text: text,
            normalizingToken:
                normalizingToken
        ) else {
            return "No browser URL"
        }
        return "\(url.absoluteString) · \(source)"
    }

    func openHTTPPage(
        targetURL: URL?,
        baseURLString: String,
        password: String,
        ensureServerAvailable:
            () -> Bool
    ) -> BrowserWindowHTTPPageCommandResult {
        guard let targetURL,
              let url = Self.helperURL(
                baseURLString:
                    baseURLString,
                targetURL: targetURL,
                password: password
              ) else {
            return .missingURL
        }
        guard ensureServerAvailable() else {
            return .unavailable
        }
        _ = sourceLinkCommandService
            .openBrowserURL(
                url,
                skipExternalOpen: false
            )
        return .opened
    }

    nonisolated static func helperURL(
        baseURLString: String,
        targetURL: URL,
        password: String
    ) -> URL? {
        let value = baseURLString.trimmed
        guard !value.isEmpty,
              var components =
                URLComponents(string: value)
        else {
            return nil
        }
        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.host == nil {
            components.host = "127.0.0.1"
        }
        components.path = "/browser"

        var queryItems = [
            URLQueryItem(
                name: "url",
                value:
                    targetURL.absoluteString
            )
        ]
        let password = password.trimmed
        if !password.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "pw",
                    value: password
                )
            )
        }
        components.queryItems = queryItems
        return components.url
    }
}
