import AppKit
import Foundation
import WebKit

struct PythonWebRendererConnection: Sendable {
    let endpoint: String
    let downloadEndpoint: String
    let token: String
}

private struct PythonWebRenderRequest: Decodable {
    var url: String
    var headers: [String: String]?
    var timeout: Double?
    var delay: Double?
    var checkBody: Bool?
}

private struct PythonWebDownloadRequest: Decodable {
    var url: String
    var path: String
    var headers: [String: String]?
    var timeout: Double?
}

struct PythonWebRenderedPage: Encodable, Sendable {
    var url: String
    var html: String
    var cookies: [String: String]
}

struct PythonWebDownloadedFile: Encodable, Sendable {
    var url: String
    var path: String
    var filename: String
}

private enum PythonWebRendererError: LocalizedError {
    case cancelled
    case emptyBody
    case navigation(String)
    case download(String)
    case outputTooLarge
    case timedOut
    case unsupportedURL

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Browser rendering was cancelled."
        case .emptyBody:
            return "Browser rendering returned an empty document."
        case .navigation(let message):
            return "Browser navigation failed: \(message)"
        case .download(let message):
            return "Browser download failed: \(message)"
        case .outputTooLarge:
            return "Browser-rendered HTML exceeded the 16 MiB limit."
        case .timedOut:
            return "Browser rendering timed out."
        case .unsupportedURL:
            return "Browser rendering only accepts HTTP and HTTPS URLs."
        }
    }
}

@MainActor
final class PythonWebRendererService {
    static let shared = PythonWebRendererService()

    private var server: LocalHTTPAPIServer?
    private var connection: PythonWebRendererConnection?

    private init() {}

    func stop() {
        server?.stop()
        server = nil
        connection = nil
    }

    func connectionInfo() throws -> PythonWebRendererConnection {
        if let connection {
            return connection
        }

        _ = NSApplication.shared
        let token = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        var attemptedPorts: Set<UInt16> = []
        var lastError: Error?

        for _ in 0..<32 {
            let port = UInt16.random(in: 49_152...65_535)
            guard attemptedPorts.insert(port).inserted else { continue }
            let candidate = LocalHTTPAPIServer(port: port) { [weak self] request in
                guard let self else {
                    return .jsonObject(["error": "Browser renderer is unavailable."], status: 503)
                }
                return await self.handle(request, token: token)
            }
            do {
                try candidate.start()
                let value = PythonWebRendererConnection(
                    endpoint: "http://127.0.0.1:\(port)/render",
                    downloadEndpoint: "http://127.0.0.1:\(port)/download",
                    token: token
                )
                server = candidate
                connection = value
                return value
            } catch {
                candidate.stop()
                lastError = error
            }
        }

        throw lastError ?? PythonWebRendererError.navigation("No loopback port was available.")
    }

    func renderPage(
        url: URL,
        headers: [String: String] = [:],
        timeout: Double = 90,
        delay: Double = 1,
        checkBody: Bool = true
    ) async throws -> PythonWebRenderedPage {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw PythonWebRendererError.unsupportedURL
        }

        let operation = PythonWebPageRenderOperation(
            url: url,
            headers: normalizedHeaders(headers),
            timeout: min(max(timeout, 1), 90),
            delay: min(max(delay, 0), 10),
            checkBody: checkBody
        )
        return try await operation.render()
    }

    func downloadPage(
        url: URL,
        destination: URL,
        headers: [String: String] = [:],
        timeout: Double = 120
    ) async throws -> PythonWebDownloadedFile {
        guard let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            throw PythonWebRendererError.unsupportedURL
        }
        guard destination.isFileURL,
              !destination.lastPathComponent.trimmed.isEmpty else {
            throw PythonWebRendererError.download("The destination path is invalid.")
        }

        let operation = PythonWebPageDownloadOperation(
            url: url,
            destination: destination,
            headers: normalizedHeaders(headers),
            timeout: min(max(timeout, 1), 600)
        )
        return try await operation.download()
    }

    private func handle(_ request: LocalHTTPRequest, token: String) async -> LocalHTTPResponse {
        guard request.method == "POST" else {
            return errorResponse("Only POST is supported.", status: 405)
        }
        guard request.path == "/render" || request.path == "/download" else {
            return errorResponse("Not found.", status: 404)
        }
        guard request.headers["authorization"] == "Bearer \(token)" else {
            return errorResponse("Unauthorized.", status: 401)
        }
        guard request.body.count <= 256 * 1024 else {
            return errorResponse("Render request exceeded the 256 KiB limit.", status: 413)
        }

        if request.path == "/download" {
            return await handleDownload(request)
        }

        let input: PythonWebRenderRequest
        do {
            input = try JSONDecoder().decode(PythonWebRenderRequest.self, from: request.body)
        } catch {
            return errorResponse("Invalid render request.", status: 400)
        }

        guard input.url.utf8.count <= 8 * 1024,
              let url = URL(string: input.url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false else {
            return errorResponse(PythonWebRendererError.unsupportedURL.localizedDescription, status: 422)
        }

        let timeout = min(max(input.timeout ?? 90, 1), 90)
        let delay = min(max(input.delay ?? 1, 0), 10)

        do {
            let response = try await renderPage(
                url: url,
                headers: input.headers ?? [:],
                timeout: timeout,
                delay: delay,
                checkBody: input.checkBody ?? true
            )
            let data = try JSONEncoder().encode(response)
            return .data(data, contentType: "application/json; charset=utf-8")
        } catch PythonWebRendererError.timedOut {
            return errorResponse(PythonWebRendererError.timedOut.localizedDescription, status: 504)
        } catch PythonWebRendererError.outputTooLarge {
            return errorResponse(PythonWebRendererError.outputTooLarge.localizedDescription, status: 413)
        } catch PythonWebRendererError.emptyBody {
            return errorResponse(PythonWebRendererError.emptyBody.localizedDescription, status: 422)
        } catch {
            return errorResponse(error.localizedDescription, status: 502)
        }
    }

    private func handleDownload(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        let input: PythonWebDownloadRequest
        do {
            input = try JSONDecoder().decode(PythonWebDownloadRequest.self, from: request.body)
        } catch {
            return errorResponse("Invalid download request.", status: 400)
        }

        guard input.url.utf8.count <= 8 * 1024,
              input.path.utf8.count <= 32 * 1024,
              let url = URL(string: input.url),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              url.host?.isEmpty == false,
              input.path.hasPrefix("/") else {
            return errorResponse("Browser download request is invalid.", status: 422)
        }

        do {
            let response = try await downloadPage(
                url: url,
                destination: URL(fileURLWithPath: input.path),
                headers: input.headers ?? [:],
                timeout: min(max(input.timeout ?? 120, 1), 600)
            )
            return .data(
                try JSONEncoder().encode(response),
                contentType: "application/json; charset=utf-8"
            )
        } catch PythonWebRendererError.timedOut {
            return errorResponse(PythonWebRendererError.timedOut.localizedDescription, status: 504)
        } catch PythonWebRendererError.unsupportedURL {
            return errorResponse(PythonWebRendererError.unsupportedURL.localizedDescription, status: 422)
        } catch {
            return errorResponse(error.localizedDescription, status: 502)
        }
    }

    private func normalizedHeaders(_ headers: [String: String]) -> [String: String] {
        let blocked = Set(["connection", "content-length", "host", "transfer-encoding"])
        var result: [String: String] = [:]
        for (name, value) in headers.prefix(100) {
            let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleanName.isEmpty,
                  cleanName.utf8.count <= 256,
                  cleanValue.utf8.count <= 8 * 1024,
                  !cleanName.contains("\r"), !cleanName.contains("\n"),
                  !cleanValue.contains("\r"), !cleanValue.contains("\n"),
                  !blocked.contains(cleanName.lowercased()) else { continue }
            result[cleanName] = cleanValue
        }
        return result
    }

    private func errorResponse(_ message: String, status: Int) -> LocalHTTPResponse {
        .jsonObject(["error": message], status: status)
    }
}

@MainActor
private final class PythonWebPageRenderOperation: NSObject, WKNavigationDelegate {
    private static let maximumHTMLSize = 16 * 1024 * 1024

    private let url: URL
    private let headers: [String: String]
    private let timeout: TimeInterval
    private let delay: TimeInterval
    private let checkBody: Bool
    private let webView: WKWebView

    private var continuation: CheckedContinuation<PythonWebRenderedPage, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var captureTask: Task<Void, Never>?

    init(url: URL, headers: [String: String], timeout: TimeInterval, delay: TimeInterval, checkBody: Bool) {
        self.url = url
        self.headers = headers
        self.timeout = timeout
        self.delay = delay
        self.checkBody = checkBody

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(frame: NSRect(x: -10_000, y: -10_000, width: 1024, height: 768), configuration: configuration)
        super.init()
        webView.navigationDelegate = self
    }

    func render() async throws -> PythonWebRenderedPage {
        await seedRequestCookies()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startTimeout()

                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: timeout
                )
                for (name, value) in headers {
                    if name.caseInsensitiveCompare("User-Agent") == .orderedSame {
                        webView.customUserAgent = value
                    } else {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                }
                webView.load(request)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.complete(.failure(PythonWebRendererError.cancelled))
            }
        }
    }

    private func seedRequestCookies() async {
        guard let host = url.host,
              let cookieHeader = headers.first(where: {
                  $0.key.caseInsensitiveCompare("Cookie") == .orderedSame
              })?.value else { return }

        for field in cookieHeader.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2, !pair[0].isEmpty,
                  let cookie = HTTPCookie(properties: [
                    .domain: host,
                    .path: "/",
                    .name: pair[0],
                    .value: pair[1],
                    .secure: url.scheme?.lowercased() == "https" ? "TRUE" : "FALSE"
                  ]) else { continue }
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            complete(.failure(PythonWebRendererError.timedOut))
        }
    }

    private func scheduleCapture() {
        guard captureTask == nil, continuation != nil else { return }
        captureTask = Task { @MainActor [weak self] in
            guard let self else { return }
            if delay > 0 {
                do {
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                } catch {
                    return
                }
            }
            await captureDocument()
        }
    }

    private func captureDocument() async {
        do {
            let script = """
            (() => {
                if (document.documentElement) return document.documentElement.outerHTML;
                if (document.body) return document.body.innerHTML;
                return '';
            })()
            """
            let value = try await evaluateJavaScript(script)
            let html = value as? String ?? ""
            if checkBody && html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw PythonWebRendererError.emptyBody
            }
            guard html.utf8.count <= Self.maximumHTMLSize else {
                throw PythonWebRendererError.outputTooLarge
            }
            let cookies = await renderedCookies()
            let finalURL = webView.url?.absoluteString ?? url.absoluteString
            complete(.success(PythonWebRenderedPage(url: finalURL, html: html, cookies: cookies)))
        } catch {
            complete(.failure(error))
        }
    }

    private func evaluateJavaScript(_ script: String) async throws -> Any? {
        try await withCheckedThrowingContinuation { continuation in
            webView.evaluateJavaScript(script) { value, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: value)
                }
            }
        }
    }

    private func renderedCookies() async -> [String: String] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: Dictionary(cookies.map { ($0.name, $0.value) }, uniquingKeysWith: { _, latest in latest }))
            }
        }
    }

    private func complete(_ result: Result<PythonWebRenderedPage, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        captureTask?.cancel()
        timeoutTask = nil
        captureTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        continuation.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.scheduleCapture()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(PythonWebRendererError.navigation(error.localizedDescription)))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(PythonWebRendererError.navigation(error.localizedDescription)))
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(PythonWebRendererError.navigation("Web content process terminated.")))
        }
    }
}

@MainActor
private final class PythonWebPageDownloadOperation: NSObject, WKDownloadDelegate {
    private let url: URL
    private let requestedDestination: URL
    private let headers: [String: String]
    private let timeout: TimeInterval
    private let webView: WKWebView

    private var continuation: CheckedContinuation<PythonWebDownloadedFile, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var activeDownload: WKDownload?
    private var finalDestination: URL?
    private var finalResponseURL: URL?

    init(url: URL, destination: URL, headers: [String: String], timeout: TimeInterval) {
        self.url = url
        requestedDestination = destination.standardizedFileURL
        self.headers = headers
        self.timeout = timeout

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(
            frame: NSRect(x: -10_000, y: -10_000, width: 1024, height: 768),
            configuration: configuration
        )
        super.init()
    }

    func download() async throws -> PythonWebDownloadedFile {
        await seedRequestCookies()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startTimeout()

                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: timeout
                )
                for (name, value) in headers {
                    if name.caseInsensitiveCompare("User-Agent") == .orderedSame {
                        webView.customUserAgent = value
                    } else {
                        request.setValue(value, forHTTPHeaderField: name)
                    }
                }
                webView.startDownload(using: request) { [weak self] download in
                    guard let self else {
                        download.cancel(nil)
                        return
                    }
                    guard self.continuation != nil else {
                        download.cancel(nil)
                        return
                    }
                    self.activeDownload = download
                    download.delegate = self
                }
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.cancel()
            }
        }
    }

    private func seedRequestCookies() async {
        guard let host = url.host,
              let cookieHeader = headers.first(where: {
                  $0.key.caseInsensitiveCompare("Cookie") == .orderedSame
              })?.value else { return }

        for field in cookieHeader.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2, !pair[0].isEmpty,
                  let cookie = HTTPCookie(properties: [
                    .domain: host,
                    .path: "/",
                    .name: pair[0],
                    .value: pair[1],
                    .secure: url.scheme?.lowercased() == "https" ? "TRUE" : "FALSE"
                  ]) else { continue }
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            } catch {
                return
            }
            cancel(with: PythonWebRendererError.timedOut)
        }
    }

    private func cancel(with error: Error = PythonWebRendererError.cancelled) {
        activeDownload?.delegate = nil
        activeDownload?.cancel(nil)
        complete(.failure(error))
    }

    private func complete(_ result: Result<PythonWebDownloadedFile, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        timeoutTask = nil
        activeDownload?.delegate = nil
        activeDownload = nil
        continuation.resume(with: result)
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        do {
            let directory = requestedDestination.deletingLastPathComponent()
            try AppPaths.ensureDirectory(directory)
            let filename = requestedDestination.lastPathComponent.trimmed.isEmpty
                ? suggestedFilename.sanitizedFilename()
                : requestedDestination.lastPathComponent.sanitizedFilename()
            let destination = AppPaths.uniqueFileURL(in: directory, filename: filename)
            finalDestination = destination
            finalResponseURL = response.url
            completionHandler(destination)
        } catch {
            completionHandler(nil)
            complete(.failure(PythonWebRendererError.download(error.localizedDescription)))
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let destination = finalDestination,
              FileManager.default.fileExists(atPath: destination.path) else {
            complete(.failure(PythonWebRendererError.download("WebKit did not create the destination file.")))
            return
        }
        complete(.success(PythonWebDownloadedFile(
            url: (finalResponseURL ?? url).absoluteString,
            path: destination.path,
            filename: destination.lastPathComponent
        )))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        complete(.failure(PythonWebRendererError.download(error.localizedDescription)))
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }
}
