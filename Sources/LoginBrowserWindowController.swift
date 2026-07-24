import AppKit
import WebKit

enum LoginBrowserAutoImportPolicy: Equatable {
    case none
    case pixivSession
    case chzzkSession
    case naverSession
    case twitterSession
    case pornhubSession
    case arcaliveSession
}

@MainActor
final class LoginBrowserWindowController: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    // macOS 27 WebKit can call back into a closed WKWebView while its owner is
    // being destroyed. Retain one controller per site and reuse it for the app lifetime.
    private static var activeControllers: [String: LoginBrowserWindowController] = [:]
    nonisolated static let googleLoginUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:90.0) Gecko/20100101 Firefox/90.0"
    nonisolated static let blockedHostSuffixes: Set<String> = [
        "ackcdn.net",
        "datetime-here2.com",
        "f-secure.com",
        "fingahvf.top",
        "hrazens.com",
        "porngur.com",
        "streamyourvid.com",
        "stripchat.com",
        "theonlygames.com",
        "webatam.com"
    ]

    private let window: NSWindow
    private let webView: WKWebView
    private let addressField = NSTextField()
    private let statusLabel = NSTextField(labelWithString: AppLocalization.text("Sign in, then save cookies."))
    private let backButton = NSButton()
    private let forwardButton = NSButton()
    private let reloadButton = NSButton()
    private let saveButton = NSButton()
    private var landingURL: URL
    private var autoImportPolicy: LoginBrowserAutoImportPolicy
    private var onCookiesImported: (Int, Int) -> Void
    private var lastAutoImportedSessionValue = ""
    private var cookieImportGeneration = 0
    private var isClearingWebsiteData = false
    private var needsCleanReload = false
    private var activeDownloads: [ObjectIdentifier: WKDownload] = [:]
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]

    static func open(
        url: URL,
        reuseKey: String? = nil,
        autoImportPolicy: LoginBrowserAutoImportPolicy = .none,
        onCookiesImported: @escaping (Int, Int) -> Void
    ) {
        let key = reuseKey ?? "login:\(url.host?.lowercased() ?? "browser")"
        if let controller = activeControllers[key] {
            controller.reopen(
                url: url,
                autoImportPolicy: autoImportPolicy,
                onCookiesImported: onCookiesImported
            )
            return
        }

        let controller = LoginBrowserWindowController(
            url: url,
            autoImportPolicy: autoImportPolicy,
            onCookiesImported: onCookiesImported
        )
        activeControllers[key] = controller
        controller.window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func closeAll() {
        let controllers = Array(activeControllers.values)
        for controller in controllers {
            controller.cancelDownloads()
            controller.webView.stopLoading()
            controller.webView.navigationDelegate = nil
            controller.webView.uiDelegate = nil
            controller.window.orderOut(nil)
        }
    }

    @discardableResult
    static func clearAllWebsiteData() async -> Int {
        let controllers = Array(activeControllers.values)
        for controller in controllers {
            await controller.clearWebsiteData()
        }
        return controllers.count
    }

    private init(
        url: URL,
        autoImportPolicy: LoginBrowserAutoImportPolicy,
        onCookiesImported: @escaping (Int, Int) -> Void
    ) {
        landingURL = url
        self.autoImportPolicy = autoImportPolicy
        self.onCookiesImported = onCookiesImported

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: configuration)

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = Self.windowTitle(for: autoImportPolicy)
        window.isReleasedWhenClosed = false
        window.center()

        super.init()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(interfaceLanguageDidChange(_:)),
            name: .hitomiBadayoInterfaceLanguageDidChange,
            object: nil
        )

        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.delegate = self
        configureContent(initialURL: url)
        load(url)
    }

    private func reopen(
        url: URL,
        autoImportPolicy: LoginBrowserAutoImportPolicy,
        onCookiesImported: @escaping (Int, Int) -> Void
    ) {
        landingURL = url
        self.autoImportPolicy = autoImportPolicy
        self.onCookiesImported = onCookiesImported
        webView.navigationDelegate = self
        webView.uiDelegate = self
        window.delegate = self
        window.title = Self.windowTitle(for: autoImportPolicy)
        if needsCleanReload || !window.isVisible {
            needsCleanReload = false
            load(url)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func configureContent(initialURL: URL) {
        let root = NSView()
        root.translatesAutoresizingMaskIntoConstraints = false

        let toolbar = NSStackView()
        toolbar.orientation = .horizontal
        toolbar.alignment = .centerY
        toolbar.spacing = 8
        toolbar.translatesAutoresizingMaskIntoConstraints = false

        backButton.target = self
        backButton.action = #selector(goBack)
        backButton.bezelStyle = .texturedRounded

        forwardButton.target = self
        forwardButton.action = #selector(goForward)
        forwardButton.bezelStyle = .texturedRounded

        reloadButton.target = self
        reloadButton.action = #selector(reload)
        reloadButton.bezelStyle = .texturedRounded

        addressField.stringValue = initialURL.absoluteString
        addressField.target = self
        addressField.action = #selector(loadAddress)
        addressField.lineBreakMode = .byTruncatingMiddle

        saveButton.target = self
        saveButton.action = #selector(saveCookies)
        saveButton.bezelStyle = .rounded
        refreshLocalizedChrome()

        toolbar.addArrangedSubview(backButton)
        toolbar.addArrangedSubview(forwardButton)
        toolbar.addArrangedSubview(reloadButton)
        toolbar.addArrangedSubview(addressField)
        toolbar.addArrangedSubview(saveButton)

        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        webView.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(toolbar)
        root.addSubview(webView)
        root.addSubview(statusLabel)
        window.contentView = root

        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10),
            toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 10),
            addressField.widthAnchor.constraint(greaterThanOrEqualToConstant: 360),

            webView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            webView.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 8),
            webView.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),

            statusLabel.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            statusLabel.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
            statusLabel.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -8)
        ])
    }

    @objc private func interfaceLanguageDidChange(_ notification: Notification) {
        refreshLocalizedChrome()
    }

    private func refreshLocalizedChrome() {
        window.title = Self.windowTitle(for: autoImportPolicy)
        let back = AppLocalization.text("Back")
        let forward = AppLocalization.text("Forward")
        let reload = AppLocalization.text("Reload")
        let save = AppLocalization.text("Save Cookies")
        backButton.image = NSImage(systemSymbolName: "chevron.left", accessibilityDescription: back)
        forwardButton.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: forward)
        reloadButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: reload)
        saveButton.title = save
        saveButton.image = NSImage(systemSymbolName: "key", accessibilityDescription: save)
        backButton.setAccessibilityLabel(back)
        forwardButton.setAccessibilityLabel(forward)
        reloadButton.setAccessibilityLabel(reload)
        saveButton.setAccessibilityLabel(save)
    }

    private func load(_ url: URL) {
        landingURL = url
        addressField.stringValue = url.absoluteString
        webView.customUserAgent = Self.customUserAgent(for: url)
        webView.load(URLRequest(url: url))
    }

    @objc private func loadAddress() {
        let raw = addressField.stringValue.trimmed
        guard !raw.isEmpty else { return }
        if let url = URL(string: raw), url.scheme != nil {
            load(url)
        } else if let url = URL(string: "https://\(raw)") {
            load(url)
        }
    }

    @objc private func goBack() {
        webView.goBack()
    }

    @objc private func goForward() {
        webView.goForward()
    }

    @objc private func reload() {
        webView.reload()
    }

    @objc private func saveCookies() {
        importCurrentCookies(automatically: false)
    }

    private func importCurrentCookies(automatically: Bool, confirmedSession: Bool = false) {
        guard !isClearingWebsiteData else { return }
        let generation = cookieImportGeneration
        webView.configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self,
                  !self.isClearingWebsiteData,
                  generation == self.cookieImportGeneration else { return }
            if automatically {
                let identity: String
                if confirmedSession {
                    let sessionCookies = Self.confirmedSessionCookies(
                        in: cookies,
                        policy: self.autoImportPolicy
                    )
                        .sorted { "\($0.domain)|\($0.name)" < "\($1.domain)|\($1.name)" }
                    guard !sessionCookies.isEmpty else { return }
                    identity = sessionCookies
                        .map { "\($0.domain)|\($0.name)=\($0.value)" }
                        .joined(separator: ";")
                } else {
                    guard let session = Self.autoImportCookie(in: cookies, policy: self.autoImportPolicy) else {
                        return
                    }
                    identity = "\(session.name)=\(session.value)"
                }
                guard identity != self.lastAutoImportedSessionValue else { return }
                self.lastAutoImportedSessionValue = identity
            }

            Task { [weak self] in
                guard let self,
                      !self.isClearingWebsiteData,
                      generation == self.cookieImportGeneration else { return }
                let result = await CookieStore.shared.importHTTPCookies(cookies)
                await MainActor.run {
                    guard !self.isClearingWebsiteData,
                          generation == self.cookieImportGeneration else { return }
                    if automatically {
                        switch self.autoImportPolicy {
                        case .pixivSession:
                            self.statusLabel.stringValue = AppLocalization.text("Pixiv login saved. Downloads resumed; you can close this window.")
                        case .chzzkSession:
                            self.statusLabel.stringValue = AppLocalization.text("Chzzk login saved. Downloads resumed; you can close this window.")
                        case .naverSession:
                            self.statusLabel.stringValue = AppLocalization.text("Naver login saved. Downloads resumed; you can close this window.")
                        case .twitterSession:
                            self.statusLabel.stringValue = AppLocalization.text("Twitter/X login saved. Downloads resumed; you can close this window.")
                        case .pornhubSession:
                            self.statusLabel.stringValue = AppLocalization.text("Pornhub Premium login saved. Downloads resumed; you can close this window.")
                        case .arcaliveSession:
                            self.statusLabel.stringValue = AppLocalization.text("Arcalive login saved. Downloads resumed; you can close this window.")
                        case .none:
                            self.statusLabel.stringValue = AppLocalization.text("Cookies saved.")
                        }
                    } else {
                        self.statusLabel.stringValue = result.skipped > 0
                            ? AppLocalization.format(
                                "Saved %@ cookies, skipped %@.",
                                String(result.imported),
                                String(result.skipped)
                            )
                            : AppLocalization.format(
                                "Saved %@ cookies.",
                                String(result.imported)
                            )
                    }
                    self.onCookiesImported(result.imported, result.skipped)
                }
            }
        }
    }

    private func clearWebsiteData() async {
        cookieImportGeneration &+= 1
        isClearingWebsiteData = true
        lastAutoImportedSessionValue = ""
        cancelDownloads()
        webView.stopLoading()
        statusLabel.stringValue = AppLocalization.text("Clearing cookies and login session...")

        let dataStore = webView.configuration.websiteDataStore
        let cookieStore = dataStore.httpCookieStore
        let cookies = await Self.cookies(in: cookieStore)
        for cookie in cookies {
            await Self.delete(cookie, from: cookieStore)
        }
        await withCheckedContinuation { continuation in
            dataStore.removeData(
                ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
                modifiedSince: .distantPast
            ) {
                continuation.resume()
            }
        }

        isClearingWebsiteData = false
        needsCleanReload = true
        statusLabel.stringValue = AppLocalization.text("Cookies and login session cleared. Sign in again.")
        if window.isVisible {
            needsCleanReload = false
            load(landingURL)
        }
    }

    private static func cookies(in store: WKHTTPCookieStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.getAllCookies { continuation.resume(returning: $0) }
        }
    }

    private static func delete(_ cookie: HTTPCookie, from store: WKHTTPCookieStore) async {
        await withCheckedContinuation { continuation in
            store.delete(cookie) { continuation.resume() }
        }
    }

#if TESTING
    static func testingSetCookie(_ cookie: HTTPCookie, reuseKey: String) async -> Bool {
        guard let controller = activeControllers[reuseKey] else { return false }
        await withCheckedContinuation { continuation in
            controller.webView.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
                continuation.resume()
            }
        }
        return true
    }

    static func testingCookies(reuseKey: String) async -> [HTTPCookie] {
        guard let controller = activeControllers[reuseKey] else { return [] }
        return await cookies(in: controller.webView.configuration.websiteDataStore.httpCookieStore)
    }

    static func testingImportCurrentCookies(reuseKey: String, automatically: Bool) -> Bool {
        guard let controller = activeControllers[reuseKey] else { return false }
        controller.importCurrentCookies(automatically: automatically)
        return true
    }
#endif

    nonisolated static func isSignedInPixivSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard cookie.name.caseInsensitiveCompare("PHPSESSID") == .orderedSame,
              (domain == "pixiv.net" || domain.hasSuffix(".pixiv.net")) else {
            return false
        }
        return isLikelySignedInPixivSessionValue(cookie.value)
    }

    nonisolated static func isLikelySignedInPixivSessionValue(_ value: String) -> Bool {
        let components = value.trimmed.split(separator: "_", maxSplits: 1, omittingEmptySubsequences: true)
        guard components.count == 2, !components[1].isEmpty else { return false }
        return components[0].allSatisfy(\.isNumber)
    }

    nonisolated static func isSignedInChzzkSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        let validName = cookie.name.caseInsensitiveCompare("NID_AUT") == .orderedSame ||
            cookie.name.caseInsensitiveCompare("NID_SES") == .orderedSame
        return validName &&
            (domain == "naver.com" || domain.hasSuffix(".naver.com")) &&
            cookie.value.trimmed.count >= 8
    }

    nonisolated static func isSignedInTwitterSessionCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cookie.name.caseInsensitiveCompare("auth_token") == .orderedSame &&
            (domain == "x.com" || domain.hasSuffix(".x.com") ||
                domain == "twitter.com" || domain.hasSuffix(".twitter.com")) &&
            !cookie.value.trimmed.isEmpty
    }

    private nonisolated static func isTwitterCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "x.com" || domain.hasSuffix(".x.com") ||
            domain == "twitter.com" || domain.hasSuffix(".twitter.com")
    }

    private nonisolated static func isPornhubCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "pornhub.com" || domain.hasSuffix(".pornhub.com") ||
            domain == "pornhubpremium.com" || domain.hasSuffix(".pornhubpremium.com")
    }

    private nonisolated static func isArcaliveCookie(_ cookie: HTTPCookie) -> Bool {
        let domain = cookie.domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return domain == "arca.live" || domain.hasSuffix(".arca.live") ||
            domain == "arca.test" || domain.hasSuffix(".arca.test")
    }

    private nonisolated static func confirmedSessionCookies(
        in cookies: [HTTPCookie],
        policy: LoginBrowserAutoImportPolicy
    ) -> [HTTPCookie] {
        switch policy {
        case .pornhubSession:
            return cookies.filter(isPornhubCookie)
        case .arcaliveSession:
            return cookies.filter(isArcaliveCookie)
        case .twitterSession:
            let sessionCookies = cookies.filter(isTwitterCookie)
            let hasAuthToken = sessionCookies.contains(where: isSignedInTwitterSessionCookie)
            let hasCSRF = sessionCookies.contains {
                $0.name.caseInsensitiveCompare("ct0") == .orderedSame && !$0.value.trimmed.isEmpty
            }
            return hasAuthToken && hasCSRF ? sessionCookies : []
        case .none, .pixivSession, .chzzkSession, .naverSession:
            return cookies
        }
    }

    private nonisolated static func autoImportCookie(
        in cookies: [HTTPCookie],
        policy: LoginBrowserAutoImportPolicy
    ) -> HTTPCookie? {
        switch policy {
        case .none:
            return nil
        case .pixivSession:
            return cookies.first(where: isSignedInPixivSessionCookie)
        case .chzzkSession:
            return cookies.first(where: isSignedInChzzkSessionCookie)
        case .naverSession:
            return cookies.first(where: isSignedInChzzkSessionCookie)
        case .twitterSession:
            return cookies.first(where: isSignedInTwitterSessionCookie)
        case .pornhubSession:
            return nil
        case .arcaliveSession:
            return nil
        }
    }

    private static func windowTitle(for policy: LoginBrowserAutoImportPolicy) -> String {
        switch policy {
        case .none: return AppLocalization.text("Login Browser")
        case .pixivSession: return AppLocalization.text("Sign In | pixiv - Web Browser")
        case .chzzkSession: return AppLocalization.text("Sign In | Chzzk - Web Browser")
        case .naverSession: return AppLocalization.text("Sign In | Naver Cafe - Web Browser")
        case .twitterSession: return AppLocalization.text("Sign In | Twitter/X - Web Browser")
        case .pornhubSession: return AppLocalization.text("Sign In | Pornhub Premium - Web Browser")
        case .arcaliveSession: return AppLocalization.text("Sign In | Arcalive - Web Browser")
        }
    }

    nonisolated static func shouldBlock(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")),
              !host.isEmpty else {
            return false
        }
        return blockedHostSuffixes.contains { suffix in
            host == suffix || host.hasSuffix(".\(suffix)")
        }
    }

    nonisolated static func customUserAgent(for url: URL) -> String? {
        let host = url.host?.lowercased() ?? ""
        return host == "accounts.google.com" || host.hasSuffix(".accounts.google.com")
            ? googleLoginUserAgent
            : nil
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.allow)
            return
        }

        if Self.shouldBlock(url) {
            Task { @MainActor in
                statusLabel.stringValue = AppLocalization.format(
                    "Blocked: %@",
                    url.host ?? url.absoluteString
                )
            }
            decisionHandler(.cancel)
            return
        }

        if navigationAction.shouldPerformDownload {
            decisionHandler(.download)
            return
        }

        Task { @MainActor in
            webView.customUserAgent = Self.customUserAgent(for: url)
        }
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationResponse: WKNavigationResponse,
        decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void
    ) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition")?
            .lowercased() ?? ""
        decisionHandler(!navigationResponse.canShowMIMEType || disposition.contains("attachment") ? .download : .allow)
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        begin(download)
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        begin(download)
    }

    private func begin(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        activeDownloads[key] = download
        download.delegate = self
        statusLabel.stringValue = AppLocalization.text("Starting download...")
    }

    private func cancelDownloads() {
        for download in activeDownloads.values {
            download.delegate = nil
            download.cancel(nil)
        }
        activeDownloads.removeAll()
        downloadDestinations.removeAll()
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping (URL?) -> Void
    ) {
        do {
            let environment = ProcessInfo.processInfo.environment
            let environmentPath = (
                environment["HITOMI_BADAYO_DESTINATION_PATH"] ??
                    environment["HITOMI_NATIVE_DESTINATION_PATH"]
            )?.trimmed ?? ""
            let savedPath = UserDefaults.standard.string(forKey: "destinationPath")?.trimmed ?? ""
            let selectedPath = environmentPath.isEmpty ? savedPath : environmentPath
            let directory = selectedPath.isEmpty
                ? AppPaths.defaultDownloadDirectory
                : URL(fileURLWithPath: selectedPath, isDirectory: true)
            try AppPaths.ensureDirectory(directory)
            let destination = AppPaths.uniqueFileURL(
                in: directory,
                filename: suggestedFilename.sanitizedFilename()
            )
            downloadDestinations[ObjectIdentifier(download)] = destination
            statusLabel.stringValue = AppLocalization.format(
                "Downloading %@...",
                destination.lastPathComponent
            )
            completionHandler(destination)
        } catch {
            statusLabel.stringValue = AppLocalization.format(
                "Download failed: %@",
                AppLocalization.errorText(error)
            )
            completionHandler(nil)
        }
    }

    func downloadDidFinish(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let destination = downloadDestinations.removeValue(forKey: key)
        activeDownloads.removeValue(forKey: key)
        statusLabel.stringValue = destination.map {
            AppLocalization.format("Downloaded %@.", $0.lastPathComponent)
        } ?? AppLocalization.text("Download finished.")
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        let key = ObjectIdentifier(download)
        downloadDestinations.removeValue(forKey: key)
        activeDownloads.removeValue(forKey: key)
        statusLabel.stringValue = (error as NSError).code == NSURLErrorCancelled
            ? AppLocalization.text("Download cancelled.")
            : AppLocalization.format("Download failed: %@", AppLocalization.errorText(error))
    }

    func download(
        _ download: WKDownload,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        decisionHandler: @escaping (WKDownload.RedirectPolicy) -> Void
    ) {
        decisionHandler(.allow)
    }

    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil,
           let url = navigationAction.request.url,
           !Self.shouldBlock(url) {
            Task { @MainActor in
                load(url)
            }
        }
        return nil
    }

    nonisolated func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        Task { @MainActor in
            if let url = webView.url {
                addressField.stringValue = url.absoluteString
            }
            statusLabel.stringValue = AppLocalization.text("Loading...")
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor [weak self, weak webView] in
            guard let self, let webView else { return }
            if let url = webView.url {
                addressField.stringValue = url.absoluteString
            }
            statusLabel.stringValue = AppLocalization.text("Sign in, then save cookies.")
            if autoImportPolicy == .twitterSession {
                for attempt in 0..<5 {
                    guard window.isVisible else { return }
                    if attempt > 0 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    importCurrentCookies(automatically: true, confirmedSession: true)
                }
            } else if autoImportPolicy == .pornhubSession {
                for attempt in 0..<5 {
                    guard window.isVisible else { return }
                    if attempt > 0 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    let value = try? await webView.evaluateJavaScript(
                        "document.getElementById('profileMenuDropdown') !== null"
                    )
                    if value as? Bool == true {
                        importCurrentCookies(automatically: true, confirmedSession: true)
                        break
                    }
                }
            } else if autoImportPolicy == .arcaliveSession {
                for attempt in 0..<5 {
                    guard window.isVisible else { return }
                    if attempt > 0 {
                        try? await Task.sleep(nanoseconds: 400_000_000)
                    }
                    let value = try? await webView.evaluateJavaScript(
                        """
                        (() => {
                          const path = (location.pathname || '').toLowerCase();
                          const blocked = document.querySelector('.h-captcha, div.text-muted');
                          const article = document.querySelector('div.article-content');
                          const signedIn = document.querySelector('a[href*=\"/u/logout\"], form[action*=\"/u/logout\"]');
                          return !blocked && !path.startsWith('/u/login') && Boolean(article || signedIn);
                        })()
                        """
                    )
                    if value as? Bool == true {
                        importCurrentCookies(automatically: true, confirmedSession: true)
                        break
                    }
                }
            } else {
                importCurrentCookies(automatically: true)
            }
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            statusLabel.stringValue = AppLocalization.format(
                "Load failed: %@",
                AppLocalization.errorText(error)
            )
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            statusLabel.stringValue = AppLocalization.format(
                "Load failed: %@",
                AppLocalization.errorText(error)
            )
        }
    }

    nonisolated func windowWillClose(_ notification: Notification) {
        MainActor.assumeIsolated {
            cancelDownloads()
            webView.stopLoading()
            webView.navigationDelegate = nil
            webView.uiDelegate = nil
        }
    }
}
