import AppKit
import Foundation
import WebKit

struct FacebookPhotoCollectionRenderResult {
    var finalURL: URL
    var html: String
    var photoLinks: [String]
}

private enum FacebookPhotoCollectionRenderError: LocalizedError {
    case cancelled
    case emptyDocument
    case navigation(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Facebook photo rendering was cancelled."
        case .emptyDocument:
            return "Facebook returned an empty photo page."
        case .navigation(let message):
            return "Facebook photo navigation failed: \(message)"
        case .timedOut:
            return "Facebook photo rendering timed out."
        }
    }
}

@MainActor
final class FacebookPhotoCollectionWebRenderer: NSObject, WKNavigationDelegate {
    private static let maximumHTMLSize = 24 * 1024 * 1024
    static let stableIterationLimit = 5
    static let timeoutInterval: TimeInterval = 3_600
    private static let scrollDelayNanoseconds: UInt64 = 750_000_000
    private static let timeoutNanoseconds = UInt64(timeoutInterval * 1_000_000_000)

    private let url: URL
    private let referer: String?
    private let userAgent: String?
    private let cookieHeader: String?
    private let itemLimit: Int
    private let webView: WKWebView

    private var continuation: CheckedContinuation<FacebookPhotoCollectionRenderResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    private init(
        url: URL,
        referer: String?,
        userAgent: String?,
        cookieHeader: String?,
        itemLimit: Int
    ) {
        self.url = url
        self.referer = referer
        self.userAgent = userAgent
        self.cookieHeader = cookieHeader
        self.itemLimit = max(1, itemLimit)

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        webView = WKWebView(
            frame: NSRect(x: -10_000, y: -10_000, width: 1280, height: 900),
            configuration: configuration
        )
        super.init()
        webView.navigationDelegate = self
    }

    static func render(
        url: URL,
        referer: String?,
        userAgent: String?,
        cookieHeader: String?,
        itemLimit: Int
    ) async throws -> FacebookPhotoCollectionRenderResult {
        let renderer = FacebookPhotoCollectionWebRenderer(
            url: url,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            itemLimit: itemLimit
        )
        return try await renderer.start()
    }

    private func start() async throws -> FacebookPhotoCollectionRenderResult {
        await seedCookies()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                startTimeout()

                var request = URLRequest(
                    url: url,
                    cachePolicy: .reloadIgnoringLocalAndRemoteCacheData,
                    timeoutInterval: Self.timeoutInterval
                )
                if let referer, !referer.trimmed.isEmpty {
                    request.setValue(referer, forHTTPHeaderField: "Referer")
                }
                if let userAgent, !userAgent.trimmed.isEmpty {
                    webView.customUserAgent = userAgent
                }
                webView.load(request)
            }
        } onCancel: { [weak self] in
            Task { @MainActor in
                self?.complete(.failure(FacebookPhotoCollectionRenderError.cancelled))
            }
        }
    }

    private func seedCookies() async {
        guard let host = url.host,
              let cookieHeader,
              !cookieHeader.trimmed.isEmpty else {
            return
        }
        let domain = host.hasSuffix("facebook.com") ? ".facebook.com" : host
        for field in cookieHeader.split(separator: ";") {
            let pair = field.split(separator: "=", maxSplits: 1).map {
                String($0).trimmingCharacters(in: .whitespacesAndNewlines)
            }
            guard pair.count == 2, !pair[0].isEmpty,
                  let cookie = HTTPCookie(properties: [
                    .domain: domain,
                    .path: "/",
                    .name: pair[0],
                    .value: pair[1],
                    .secure: url.scheme?.lowercased() == "https" ? "TRUE" : "FALSE"
                  ]) else {
                continue
            }
            await withCheckedContinuation { continuation in
                webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
    }

    private func startTimeout() {
        timeoutTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.timeoutNanoseconds)
            } catch {
                return
            }
            self?.complete(.failure(FacebookPhotoCollectionRenderError.timedOut))
        }
    }

    private func beginScrollingIfNeeded() {
        guard renderTask == nil, continuation != nil else { return }
        renderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await collectRenderedPage()
                complete(.success(result))
            } catch is CancellationError {
                complete(.failure(FacebookPhotoCollectionRenderError.cancelled))
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func collectRenderedPage() async throws -> FacebookPhotoCollectionRenderResult {
        var photoLinks: [String] = []
        var seenLinks = Set<String>()
        var stableIterations = 0

        while photoLinks.count < itemLimit {
            try Task.checkCancellation()
            let state = try await collectPhotoStateAndScroll()
            let previousLinkCount = seenLinks.count
            for link in state.links where seenLinks.insert(link).inserted {
                photoLinks.append(link)
            }

            if seenLinks.count == previousLinkCount {
                stableIterations += 1
            } else {
                stableIterations = 0
            }
            if stableIterations >= Self.stableIterationLimit { break }
            try await Task.sleep(nanoseconds: Self.scrollDelayNanoseconds)
        }

        let htmlValue = try await evaluateJavaScript(
            "document.documentElement ? document.documentElement.outerHTML : (document.body ? document.body.innerHTML : '')"
        )
        let html = htmlValue as? String ?? ""
        guard !html.trimmed.isEmpty else {
            throw FacebookPhotoCollectionRenderError.emptyDocument
        }
        guard html.utf8.count <= Self.maximumHTMLSize else {
            throw NativeDownloadError.unsupported("Facebook rendered HTML exceeded the 24 MiB limit.")
        }

        let cookies = await renderedCookies()
        if !cookies.isEmpty {
            _ = await CookieStore.shared.importHTTPCookies(cookies)
        }
        return FacebookPhotoCollectionRenderResult(
            finalURL: webView.url ?? url,
            html: html,
            photoLinks: photoLinks
        )
    }

    private func collectPhotoStateAndScroll() async throws -> (links: [String], height: Double) {
        let script = #"""
        (() => {
          const key = '__hitomiNativeFacebookPhotoLinks';
          const known = new Set(Array.isArray(window[key]) ? window[key] : []);
          const photoPattern = /(?:[?&]fbid=\d{4,}|\/photos\/(?:[^/?#]+\/)?\d{4,})(?:[/?#&]|$)/i;
          for (const anchor of document.querySelectorAll('a[href]')) {
            const href = anchor.href || anchor.getAttribute('href') || '';
            if (photoPattern.test(href) && (anchor.querySelector('img') || href.includes('photo'))) {
              known.add(href);
            }
          }
          window[key] = Array.from(known);
          const root = document.documentElement;
          const body = document.body;
          const height = Math.max(root ? root.scrollHeight : 0, body ? body.scrollHeight : 0);
          window.scrollTo(0, height);
          return { links: window[key], height };
        })()
        """#
        let value = try await evaluateJavaScript(script)
        let object = value as? [String: Any] ?? [:]
        let links = object["links"] as? [String] ?? []
        let height = (object["height"] as? NSNumber)?.doubleValue ?? 0
        return (links, height)
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

    private func renderedCookies() async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    private func complete(_ result: Result<FacebookPhotoCollectionRenderResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        renderTask?.cancel()
        timeoutTask = nil
        renderTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        continuation.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.beginScrollingIfNeeded()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(FacebookPhotoCollectionRenderError.navigation(error.localizedDescription)))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(FacebookPhotoCollectionRenderError.navigation(error.localizedDescription)))
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(FacebookPhotoCollectionRenderError.navigation("Web content process terminated.")))
        }
    }
}
