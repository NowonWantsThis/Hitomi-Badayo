import Foundation

struct LocalAPIClipboardInput {
    var text: String
    var source: String
}

@MainActor
struct LocalAPIClipboardService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func input(
        from request: LocalHTTPRequest,
        clipboardText: () -> String?
    ) -> LocalAPIClipboardInput {
        let parameters = requestDecoder.parameters(from: request)
        if let value = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["text", "input", "data", "clipboard", "url", "urls"]
        ) {
            return LocalAPIClipboardInput(text: value, source: "parameter")
        }

        let body = request.bodyText
        let contentType = request.headers["content-type"]?.lowercased() ?? ""
        if !body.trimmed.isEmpty,
           !contentType.contains("application/json"),
           !contentType.contains("application/x-www-form-urlencoded") {
            return LocalAPIClipboardInput(text: body, source: "body")
        }

        return LocalAPIClipboardInput(
            text: clipboardText() ?? "",
            source: "clipboard"
        )
    }

    func object(
        request: LocalHTTPRequest,
        explicitText: String? = nil,
        source: String? = nil,
        monitorEnabled: Bool,
        changeCount: Int,
        clipboardText: () -> String?,
        candidateURLs: (String) -> [String],
        inputTypeObjects: (String) -> [[String: Any]]
    ) -> [String: Any] {
        let input = explicitText.map {
            LocalAPIClipboardInput(
                text: $0,
                source: source ?? "explicit"
            )
        } ?? input(from: request, clipboardText: clipboardText)
        let urls = candidateURLs(input.text)
        let monitorable = urls.filter(Self.isMonitorableURL)
        let auth = Self.authQuery(
            request.query["pw"] ?? request.query["password"] ?? ""
        )
        return [
            "ok": true,
            "watch": monitorEnabled,
            "watching": monitorEnabled,
            "enabled": monitorEnabled,
            "changeCount": changeCount,
            "source": input.source,
            "text": input.text,
            "urls": urls,
            "items": urls,
            "count": urls.count,
            "urlCount": urls.count,
            "monitorable": monitorable,
            "monitorableCount": monitorable.count,
            "inputTypes": input.text.trimmed.isEmpty
                ? []
                : inputTypeObjects(input.text),
            "enqueue": "/clipboard/enqueue?start=0\(auth)",
            "watchAction": "/clipboard/watch\(auth)"
        ] as [String: Any]
    }

    func enqueueResponse(
        request: LocalHTTPRequest,
        monitorEnabled: Bool,
        clipboardText: () -> String?,
        candidateURLs: (String) -> [String],
        enqueue: ([String]) -> Int,
        startQueue: () -> Void,
        queueState: () -> (count: Int, isRunning: Bool)
    ) -> LocalHTTPResponse {
        let input = input(from: request, clipboardText: clipboardText)
        let urls = candidateURLs(input.text)
        guard !urls.isEmpty else {
            return LocalHTTPResponse.jsonObject([
                "ok": false,
                "res": "error",
                "error": "Missing clipboard URLs",
                "watch": monitorEnabled,
                "count": 0
            ], status: 400)
        }

        let added = enqueue(urls)
        let parameters = requestDecoder.parameters(from: request)
        let shouldStart = (
            parameters["start"] ?? parameters["run"] ?? "0"
        ) != "0"
        if added > 0, shouldStart {
            startQueue()
        }
        let state = queueState()
        let message = "\(added) clipboard URL\(added == 1 ? "" : "s") added"
        return LocalHTTPResponse.jsonObject([
            "ok": added > 0,
            "res": added > 0 ? "ok" : "skipped",
            "message": message,
            "added": added,
            "total": state.count,
            "running": state.isRunning,
            "watch": monitorEnabled,
            "source": input.source,
            "urls": urls
        ] as [String: Any])
    }

    func watchResponse(
        request: LocalHTTPRequest,
        currentEnabled: Bool,
        setEnabled: (Bool) -> Void,
        currentState: () -> (enabled: Bool, message: String)
    ) -> LocalHTTPResponse {
        let parameters = requestDecoder.parameters(from: request)
        let raw = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: [
                "enabled", "enable", "watch", "watching", "value",
                "state", "on"
            ]
        )?.lowercased()
        let enabled: Bool
        if raw == nil || raw == "toggle" {
            enabled = !currentEnabled
        } else {
            enabled = LocalAPIRequestDecoder.truthy(raw)
        }
        setEnabled(enabled)
        let state = currentState()
        return LocalHTTPResponse.jsonObject([
            "ok": true,
            "res": "ok",
            "watch": state.enabled,
            "watching": state.enabled,
            "enabled": state.enabled,
            "message": state.message
        ])
    }

    private static func isMonitorableURL(_ text: String) -> Bool {
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased() else {
            return false
        }
        return ["http", "https", "magnet", "file"].contains(scheme)
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
}
