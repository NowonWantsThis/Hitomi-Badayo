import Foundation

struct LocalAPIBrowserSelection {
    var url: URL?
    var source: String
}

@MainActor
struct LocalAPIBrowserService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func selection(
        from request: LocalHTTPRequest,
        inputText: String,
        parameterURL: (String) -> URL?,
        fallbackURL: () -> URL?
    ) -> LocalAPIBrowserSelection {
        let parameters = requestDecoder.parameters(from: request)
        if let raw = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: [
                "url", "input", "text", "address", "href", "site",
                "target"
            ]
        ) {
            return LocalAPIBrowserSelection(
                url: parameterURL(raw),
                source: "parameter"
            )
        }

        return LocalAPIBrowserSelection(
            url: fallbackURL(),
            source: inputText.trimmed.isEmpty ? "queue" : "input"
        )
    }

    func object(
        request: LocalHTTPRequest,
        selection: LocalAPIBrowserSelection,
        cookieSummary: String
    ) -> [String: Any] {
        let password = request.query["pw"] ?? request.query["password"] ?? ""
        let auth = Self.authQuery(password)
        guard let url = selection.url else {
            return [
                "ok": false,
                "res": "error",
                "error": "Missing browser URL",
                "url": NSNull(),
                "source": selection.source,
                "cookieSummary": cookieSummary
            ] as [String: Any]
        }

        let urlString = url.absoluteString
        return [
            "ok": true,
            "res": "ok",
            "url": urlString,
            "browserURL": urlString,
            "source": selection.source,
            "cookieSummary": cookieSummary,
            "open": "/browser/open?url=\(Self.queryComponent(urlString))\(auth)"
        ] as [String: Any]
    }

    func openResponse(
        request: LocalHTTPRequest,
        selection: LocalAPIBrowserSelection,
        cookieSummary: String,
        openBrowser: (URL) -> Void
    ) -> LocalHTTPResponse {
        guard let url = selection.url else {
            return LocalHTTPResponse.jsonObject([
                "ok": false,
                "res": "error",
                "error": "Missing browser URL"
            ], status: 400)
        }

        let parameters = requestDecoder.parameters(from: request)
        let dryRun = LocalAPIRequestDecoder.truthy(parameters["dry_run"]) ||
            LocalAPIRequestDecoder.truthy(parameters["dryRun"])
        let openValue = parameters["open"] ?? parameters["run"]
        let shouldOpen = dryRun
            ? false
            : openValue.map(LocalAPIRequestDecoder.truthy) ?? true
        if shouldOpen {
            openBrowser(url)
        }

        return LocalHTTPResponse.jsonObject([
            "ok": true,
            "res": "ok",
            "opened": shouldOpen,
            "dryRun": !shouldOpen,
            "url": url.absoluteString,
            "source": selection.source,
            "cookieSummary": cookieSummary
        ] as [String: Any])
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
}
