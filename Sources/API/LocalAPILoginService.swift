import Foundation

struct LocalAPILoginService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder()) {
        self.requestDecoder = requestDecoder
    }

    func response(
        for request: LocalHTTPRequest,
        password rawPassword: String
    ) -> LocalHTTPResponse {
        guard request.method == "POST" else {
            let redirect = LocalAPIHTMLStyle.escape(
                request.query["redirect"] ?? "/webui"
            )
            let placeholder = LocalAPIHTMLStyle.escape("Password")
            return LocalHTTPResponse.html("""
            <!doctype html>
            <html><head><meta charset="utf-8"><title>Hitomi Badayo Login</title></head>
            <body style="font:14px \(LocalAPIHTMLStyle.svgFontStack);padding:24px;">
              <h1>Hitomi Badayo HTTP API</h1>
              <form action="/login" method="post">
                <input type="hidden" name="redirect" value="\(redirect)">
                <input type="password" name="pw" placeholder="\(placeholder)" autofocus>
                <button type="submit">Login</button>
              </form>
            </body></html>
            """)
        }

        let password = rawPassword.trimmed
        let parameters = requestDecoder.parameters(from: request)
        guard !password.isEmpty,
              parameters["pw"] == password ||
                parameters["password"] == password else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Unauthorized"],
                status: 401
            )
        }

        let redirect = requestDecoder.safeRedirect(
            parameters["redirect"] ??
                request.query["redirect"] ?? "/webui"
        )
        let ticket = LocalAPIAuthorizationPolicy.authTicket(for: password)
        return LocalHTTPResponse(
            status: 302,
            contentType: "text/plain; charset=utf-8",
            body: Data("Redirecting".utf8),
            headers: [
                "Location": redirect,
                "Set-Cookie": "ticket=\(ticket); Path=/; HttpOnly; SameSite=Lax"
            ]
        )
    }

    func redirectResponse(for request: LocalHTTPRequest) -> LocalHTTPResponse {
        let target = redirectTarget(for: request)
        let location = "/login?redirect=\(Self.queryComponent(target))"
        return LocalHTTPResponse(
            status: 302,
            contentType: "text/plain; charset=utf-8",
            body: Data("Redirecting".utf8),
            headers: ["Location": location]
        )
    }

    private func redirectTarget(for request: LocalHTTPRequest) -> String {
        let query = request.query
            .sorted { $0.key < $1.key }
            .flatMap { key, value -> [String] in
                value
                    .components(separatedBy: .newlines)
                    .map {
                        "\(Self.queryComponent(key))=\(Self.queryComponent($0))"
                    }
            }
            .joined(separator: "&")
        return query.isEmpty ? request.path : "\(request.path)?\(query)"
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }
}
