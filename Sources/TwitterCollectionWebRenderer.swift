import AppKit
import Foundation
import WebKit

struct TwitterCollectionRenderResult {
    var finalURL: URL
    var html: String
    var statusLinks: [String]
}

private enum TwitterCollectionRenderError: LocalizedError {
    case cancelled
    case emptyDocument
    case navigation(String)
    case timedOut

    var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Twitter/X profile rendering was cancelled."
        case .emptyDocument:
            return "Twitter/X returned an empty profile page."
        case .navigation(let message):
            return "Twitter/X profile navigation failed: \(message)"
        case .timedOut:
            return "Twitter/X profile rendering timed out."
        }
    }
}

@MainActor
final class TwitterCollectionWebRenderer: NSObject, WKNavigationDelegate {
    private static let maximumHTMLSize = 24 * 1024 * 1024
    static let stableIterationLimit = 5
    static let timeoutInterval: TimeInterval = 3_600
    private static let scrollDelayNanoseconds: UInt64 = 750_000_000

    private let url: URL
    private let referer: String?
    private let userAgent: String?
    private let cookieHeader: String?
    private let itemLimit: Int
    private let webView: WKWebView

    private var continuation: CheckedContinuation<TwitterCollectionRenderResult, Error>?
    private var timeoutTask: Task<Void, Never>?
    private var committedPageFallbackTask: Task<Void, Never>?
    private var renderTask: Task<Void, Never>?

    private init(url: URL, referer: String?, userAgent: String?, cookieHeader: String?, itemLimit: Int) {
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
    ) async throws -> TwitterCollectionRenderResult {
        let renderer = TwitterCollectionWebRenderer(
            url: url,
            referer: referer,
            userAgent: userAgent,
            cookieHeader: cookieHeader,
            itemLimit: itemLimit
        )
        return try await renderer.start()
    }

    private func start() async throws -> TwitterCollectionRenderResult {
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
                self?.complete(.failure(TwitterCollectionRenderError.cancelled))
            }
        }
    }

    private func seedCookies() async {
        guard let host = url.host,
              let cookieHeader,
              !cookieHeader.trimmed.isEmpty else {
            return
        }
        let domain: String
        if host == "x.com" || host.hasSuffix(".x.com") {
            domain = ".x.com"
        } else if host == "twitter.com" || host.hasSuffix(".twitter.com") {
            domain = ".twitter.com"
        } else {
            domain = host
        }
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
                try await Task.sleep(
                    nanoseconds: UInt64(Self.timeoutInterval * 1_000_000_000)
                )
            } catch {
                return
            }
            self?.complete(.failure(TwitterCollectionRenderError.timedOut))
        }
    }

    private func startCommittedPageFallback() {
        guard committedPageFallbackTask == nil else { return }
        committedPageFallbackTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
            self?.beginScrollingIfNeeded()
        }
    }

    private func beginScrollingIfNeeded() {
        guard renderTask == nil, continuation != nil else { return }
        committedPageFallbackTask?.cancel()
        committedPageFallbackTask = nil
        renderTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let result = try await collectRenderedPage()
                complete(.success(result))
            } catch is CancellationError {
                complete(.failure(TwitterCollectionRenderError.cancelled))
            } catch {
                complete(.failure(error))
            }
        }
    }

    private func collectRenderedPage() async throws -> TwitterCollectionRenderResult {
        var statusLinks: [String] = []
        var seenLinks = Set<String>()
        var lastHeight = -1.0
        var stableIterations = 0

        while seenLinks.count < itemLimit {
            try Task.checkCancellation()
            let state = try await collectStatusStateAndScroll()
            let previousLinkCount = seenLinks.count
            for link in state.links where seenLinks.insert(link).inserted {
                statusLinks.append(link)
            }

            if state.height <= lastHeight + 1, seenLinks.count == previousLinkCount {
                stableIterations += 1
            } else {
                stableIterations = 0
            }
            lastHeight = max(lastHeight, state.height)
            if stableIterations >= Self.stableIterationLimit { break }
            try await Task.sleep(nanoseconds: Self.scrollDelayNanoseconds)
        }

        let htmlValue = try await evaluateJavaScript(
            "document.documentElement ? document.documentElement.outerHTML : (document.body ? document.body.innerHTML : '')"
        )
        let html = htmlValue as? String ?? ""
        guard !html.trimmed.isEmpty else {
            throw TwitterCollectionRenderError.emptyDocument
        }
        guard html.utf8.count <= Self.maximumHTMLSize else {
            throw NativeDownloadError.unsupported("Twitter/X rendered HTML exceeded the 24 MiB limit.")
        }

        let cookies = await renderedCookies()
        if !cookies.isEmpty {
            _ = await CookieStore.shared.importHTTPCookies(cookies)
        }
        return TwitterCollectionRenderResult(
            finalURL: webView.url ?? url,
            html: html,
            statusLinks: statusLinks
        )
    }

    private func collectStatusStateAndScroll() async throws -> (links: [String], height: Double) {
        let script = #"""
        (() => {
          const key = '__hitomiNativeTwitterStatusLinks';
          const known = new Set(Array.isArray(window[key]) ? window[key] : []);
          const statusPattern = /\/(?:i\/web\/status|[A-Za-z0-9_]{1,15}\/status)\/\d+(?:[/?#]|$)/i;
          for (const anchor of document.querySelectorAll('a[href]')) {
            const href = anchor.href || anchor.getAttribute('href') || '';
            if (statusPattern.test(href)) known.add(href);
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

    private func complete(_ result: Result<TwitterCollectionRenderResult, Error>) {
        guard let continuation else { return }
        self.continuation = nil
        timeoutTask?.cancel()
        committedPageFallbackTask?.cancel()
        renderTask?.cancel()
        timeoutTask = nil
        committedPageFallbackTask = nil
        renderTask = nil
        webView.stopLoading()
        webView.navigationDelegate = nil
        continuation.resume(with: result)
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.startCommittedPageFallback()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self] in
            self?.beginScrollingIfNeeded()
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(TwitterCollectionRenderError.navigation(error.localizedDescription)))
        }
    }

    nonisolated func webView(
        _ webView: WKWebView,
        didFailProvisionalNavigation navigation: WKNavigation!,
        withError error: Error
    ) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(TwitterCollectionRenderError.navigation(error.localizedDescription)))
        }
    }

    nonisolated func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        Task { @MainActor [weak self] in
            self?.complete(.failure(TwitterCollectionRenderError.navigation("Web content process terminated.")))
        }
    }
}
