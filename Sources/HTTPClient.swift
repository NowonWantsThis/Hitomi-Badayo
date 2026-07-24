import Foundation

private actor HTTPRequestRateLimiter {
    private let minimumInterval: TimeInterval
    private var nextRequestTime: TimeInterval = 0

    init(minimumInterval: TimeInterval) {
        self.minimumInterval = max(0, minimumInterval)
    }

    func wait() async throws {
        let now = ProcessInfo.processInfo.systemUptime
        let scheduled = max(now, nextRequestTime)
        nextRequestTime = scheduled + minimumInterval
        let delay = scheduled - now
        guard delay > 0 else { return }
        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
    }
}

private enum HTTPDownloadValidationError: LocalizedError {
    case tooSmall(URL, Int64)
    case html(URL)

    var errorDescription: String? {
        switch self {
        case .tooSmall(let url, let bytes):
            return "Image response was too small (\(bytes) bytes): \(url.absoluteString)"
        case .html(let url):
            return "Image request returned an HTML page: \(url.absoluteString)"
        }
    }
}

struct HTTPDownloadProgress: Equatable, Sendable {
    var downloadedBytes: Int64
    var totalBytes: Int64?
    var speedBytesPerSecond: Int64?
}

typealias HTTPDownloadProgressHandler = @Sendable (HTTPDownloadProgress) -> Void

private final class HTTPDownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let handler: HTTPDownloadProgressHandler
    private let lock = NSLock()
    private var lastEmissionTime = Date.timeIntervalSinceReferenceDate
    private var lastEmissionBytes: Int64 = 0
    private var continuation: CheckedContinuation<(URL, URLResponse), Error>?
    private var downloadedFileURL: URL?
    private var downloadError: Error?
    private var task: URLSessionDownloadTask?
    private var retainedSession: URLSession?
    private var cancellationRequested = false
    private var pauseRequested = false
    private var taskSuspendedByPause = false

    init(handler: @escaping HTTPDownloadProgressHandler) {
        self.handler = handler
    }

    func download(
        request: URLRequest,
        resumeData: Data?,
        configuration: URLSessionConfiguration
    ) async throws -> (URL, URLResponse) {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let session = URLSession(
                    configuration: configuration,
                    delegate: self,
                    delegateQueue: nil
                )
                let task = resumeData.map(session.downloadTask(withResumeData:)) ??
                    session.downloadTask(with: request)

                lock.lock()
                self.continuation = continuation
                self.task = task
                retainedSession = session
                let shouldCancel = cancellationRequested
                if !shouldCancel {
                    task.resume()
                    if pauseRequested {
                        task.suspend()
                        taskSuspendedByPause = true
                    }
                }
                lock.unlock()

                if shouldCancel {
                    task.cancel()
                }
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        lock.lock()
        cancellationRequested = true
        let task = task
        let wasSuspended = taskSuspendedByPause
        taskSuspendedByPause = false
        lock.unlock()
        if wasSuspended {
            task?.resume()
        }
        task?.cancel()
    }

    func setPaused(_ paused: Bool) {
        lock.lock()
        pauseRequested = paused
        let task = task
        let shouldSuspend = paused && task != nil && !taskSuspendedByPause
        let shouldResume = !paused && taskSuspendedByPause
        if shouldSuspend {
            taskSuspendedByPause = true
        } else if shouldResume {
            taskSuspendedByPause = false
        }
        lock.unlock()

        if shouldSuspend {
            task?.suspend()
        } else if shouldResume {
            task?.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let now = Date.timeIntervalSinceReferenceDate
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : nil

        lock.lock()
        let elapsed = now - lastEmissionTime
        let isComplete = total.map { totalBytesWritten >= $0 } ?? false
        guard lastEmissionBytes == 0 || elapsed >= 0.15 || isComplete else {
            lock.unlock()
            return
        }
        let delta = max(0, totalBytesWritten - lastEmissionBytes)
        let speed = elapsed > 0.01 ? Int64(Double(delta) / elapsed) : nil
        lastEmissionTime = now
        lastEmissionBytes = totalBytesWritten
        lock.unlock()

        handler(HTTPDownloadProgress(
            downloadedBytes: max(0, totalBytesWritten),
            totalBytes: total,
            speedBytesPerSecond: speed
        ))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        let retainedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-HTTPDownload-\(UUID().uuidString)")
        do {
            try FileManager.default.moveItem(at: location, to: retainedURL)
            lock.lock()
            downloadedFileURL = retainedURL
            lock.unlock()
        } catch {
            lock.lock()
            downloadError = error
            lock.unlock()
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        let fileURL = downloadedFileURL
        downloadedFileURL = nil
        let retainedError = downloadError
        downloadError = nil
        self.task = nil
        taskSuspendedByPause = false
        let retainedSession = retainedSession
        self.retainedSession = nil
        lock.unlock()

        retainedSession?.finishTasksAndInvalidate()
        guard let continuation else {
            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            return
        }
        if let error {
            if let fileURL {
                try? FileManager.default.removeItem(at: fileURL)
            }
            continuation.resume(throwing: error)
        } else if let retainedError {
            continuation.resume(throwing: retainedError)
        } else if let fileURL, let response = task.response {
            continuation.resume(returning: (fileURL, response))
        } else {
            continuation.resume(throwing: URLError(.cannotCreateFile))
        }
    }
}

final class HTTPClient {
    static let shared = HTTPClient()

#if TESTING
    nonisolated(unsafe) static var testingProtocolClasses: [AnyClass]?
#endif

    private let defaultMaxRetryAttempts = 3
    private let hitomiImageMaxRetryAttempts = 23
    private let hitomiImageRetryDelaySeconds: Double = 1
    private let maxRetryAfterSeconds: Double = 120
    private let retryableStatusCodes: Set<Int> = [408, 429, 500, 502, 503, 504, 509]
    private let retryableURLErrorCodes: Set<URLError.Code> = [
        .timedOut,
        .cannotFindHost,
        .cannotConnectToHost,
        .networkConnectionLost,
        .dnsLookupFailed,
        .notConnectedToInternet
    ]
    private let sessionCacheLock = NSLock()
    private var cachedSessions: [String: URLSession] = [:]
    private let transferStateLock = NSLock()
    private var transfersPaused = false
    private var queueSuspendedSessionTasks: [ObjectIdentifier: URLSessionTask] = [:]
    private var activeProgressDelegates: [ObjectIdentifier: HTTPDownloadProgressDelegate] = [:]
    private let hitomiWebPRequestLimiter = HTTPRequestRateLimiter(minimumInterval: 1.0 / 3.0)
    private let hitomiOriginalRequestLimiter = HTTPRequestRateLimiter(minimumInterval: 1.0)

    private init() {}

    func pauseAllTransfers() {
        transferStateLock.lock()
        transfersPaused = true
        let delegates = Array(activeProgressDelegates.values)
        transferStateLock.unlock()

        delegates.forEach { $0.setPaused(true) }
        suspendCachedSessionTasksIfPaused()
    }

    func resumeAllTransfers() {
        transferStateLock.lock()
        transfersPaused = false
        let tasks = Array(queueSuspendedSessionTasks.values)
        queueSuspendedSessionTasks.removeAll()
        let delegates = Array(activeProgressDelegates.values)
        transferStateLock.unlock()

        tasks.forEach { task in
            if task.state == .suspended {
                task.resume()
            }
        }
        delegates.forEach { $0.setPaused(false) }
    }

    private var areTransfersPaused: Bool {
        transferStateLock.lock()
        defer { transferStateLock.unlock() }
        return transfersPaused
    }

    private func waitUntilTransfersResume() async throws {
        while areTransfersPaused {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    private func registerProgressDelegate(_ delegate: HTTPDownloadProgressDelegate) {
        transferStateLock.lock()
        activeProgressDelegates[ObjectIdentifier(delegate)] = delegate
        let paused = transfersPaused
        transferStateLock.unlock()
        delegate.setPaused(paused)
    }

    private func unregisterProgressDelegate(_ delegate: HTTPDownloadProgressDelegate) {
        transferStateLock.lock()
        activeProgressDelegates.removeValue(forKey: ObjectIdentifier(delegate))
        transferStateLock.unlock()
    }

    private func suspendCachedSessionTasksIfPaused() {
        sessionCacheLock.lock()
        let sessions = Array(cachedSessions.values)
        sessionCacheLock.unlock()

        sessions.forEach { session in
            session.getAllTasks { [weak self] tasks in
                self?.suspendSessionTasksIfPaused(tasks)
            }
        }
    }

    private func suspendSessionTasksIfPaused(_ tasks: [URLSessionTask]) {
        transferStateLock.lock()
        guard transfersPaused else {
            transferStateLock.unlock()
            return
        }
        for task in tasks where task.state == .running {
            task.suspend()
            queueSuspendedSessionTasks[ObjectIdentifier(task)] = task
        }
        transferStateLock.unlock()
    }

    private func makeSession(for url: URL) -> URLSession {
        let networkSettings = NetworkSettings.load()
        let cacheKey = sessionCacheKey(for: url, networkSettings: networkSettings)

        sessionCacheLock.lock()
        defer { sessionCacheLock.unlock() }
        if let cached = cachedSessions[cacheKey] {
            return cached
        }

        let config = makeSessionConfiguration(for: url, networkSettings: networkSettings)
        let session = URLSession(configuration: config)
        cachedSessions[cacheKey] = session
        return session
    }

    private func makeSessionConfiguration(
        for url: URL,
        networkSettings: NetworkSettings? = nil
    ) -> URLSessionConfiguration {
        let networkSettings = networkSettings ?? NetworkSettings.load()
        let proxy = networkSettings.connectionProxyDictionary(for: url)
        let config = URLSessionConfiguration.ephemeral
        NetworkSessionPrivacy.disableSystemCredentialPersistence(in: config)
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 600
        config.httpMaximumConnectionsPerHost = 24
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (Macintosh; Apple Silicon Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8",
            "Accept-Language": "en-US,en;q=0.9"
        ]
#if TESTING
        if let protocolClasses = Self.testingProtocolClasses {
            config.protocolClasses = protocolClasses
        }
#endif
        if let proxy {
            config.connectionProxyDictionary = proxy
        }
        return config
    }

    private func sessionCacheKey(for url: URL, networkSettings: NetworkSettings) -> String {
        let connection = networkSettings.proxyArgument(for: url) ?? "direct"
#if TESTING
        let protocols = Self.testingProtocolClasses?
            .map { String(reflecting: $0) }
            .joined(separator: ",") ?? "system"
        return "\(connection)|\(protocols)"
#else
        return connection
#endif
    }

#if TESTING
    var cachedSessionCountForTesting: Int {
        sessionCacheLock.lock()
        defer { sessionCacheLock.unlock() }
        return cachedSessions.count
    }

    func resetCachedSessionsForTesting() {
        resumeAllTransfers()
        sessionCacheLock.lock()
        let sessions = Array(cachedSessions.values)
        cachedSessions.removeAll()
        sessionCacheLock.unlock()
        sessions.forEach { $0.invalidateAndCancel() }
    }

    var transfersPausedForTesting: Bool {
        areTransfersPaused
    }
#endif

    func data(
        from url: URL,
        referer: String? = nil,
        userAgent: String? = nil,
        additionalHeaders: [String: String] = [:],
        retryLimitOverride: Int? = nil
    ) async throws -> Data {
        let (data, _) = try await dataResponse(
            from: url,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders,
            retryLimitOverride: retryLimitOverride
        )
        return data
    }

    func dataResponse(
        from url: URL,
        referer: String? = nil,
        userAgent: String? = nil,
        additionalHeaders: [String: String] = [:],
        acceptedStatusCodes: Set<Int> = [],
        retryLimitOverride: Int? = nil
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Cookie") == nil,
           let cookie = await CookieStore.shared.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        let session = makeSession(for: url)
        let maxRetryAttempts = max(0, retryLimitOverride ?? retryAttemptLimit(for: url))
        for attempt in 0...maxRetryAttempts {
            do {
                try await waitBeforeImageRequestIfNeeded(url)
                try await waitUntilTransfersResume()
                let (data, response) = try await session.data(for: request)
                await CookieStore.shared.storeCookies(from: response, url: url)
                if let http = response as? HTTPURLResponse,
                   shouldRetry(statusCode: http.statusCode, url: url, attempt: attempt),
                   attempt < maxRetryAttempts {
                    try await waitBeforeRetry(attempt: attempt, response: http, url: url)
                    continue
                }
                guard let http = response as? HTTPURLResponse else {
                    throw NativeDownloadError.unsupported("Request did not return an HTTP response from \(url.absoluteString)")
                }
                if !acceptedStatusCodes.contains(http.statusCode) {
                    try validate(response: response, url: url)
                }
                return (data, http)
            } catch {
                guard shouldRetry(error: error), attempt < maxRetryAttempts else {
                    throw error
                }
                try await waitBeforeRetry(attempt: attempt, response: nil, url: url)
            }
        }
        throw NativeDownloadError.unsupported("Request retry limit exceeded for \(url.absoluteString)")
    }

    func string(
        from url: URL,
        referer: String? = nil,
        userAgent: String? = nil,
        additionalHeaders: [String: String] = [:],
        retryLimitOverride: Int? = nil
    ) async throws -> String {
        let data = try await data(
            from: url,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders,
            retryLimitOverride: retryLimitOverride
        )
        if let text = String(data: data, encoding: .utf8) {
            return text
        }
        if let text = String(data: data, encoding: .isoLatin1) {
            return text
        }
        return String(decoding: data, as: UTF8.self)
    }

    func postJSON(to url: URL, body: Data, referer: String? = nil, userAgent: String? = nil, additionalHeaders: [String: String] = [:]) async throws -> Data {
        let (data, _) = try await postJSONResponse(
            to: url,
            body: body,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders
        )
        return data
    }

    func postJSONResponse(to url: URL, body: Data, referer: String? = nil, userAgent: String? = nil, additionalHeaders: [String: String] = [:]) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = body
#if TESTING
        let testingRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(body, forKey: "HitomiBadayoTestingHTTPBody", in: testingRequest)
        request = testingRequest as URLRequest
#endif
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Cookie") == nil,
           let cookie = await CookieStore.shared.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let session = makeSession(for: url)
        try await waitUntilTransfersResume()
        let (data, response) = try await session.data(for: request)
        await CookieStore.shared.storeCookies(from: response, url: url)
        try validate(response: response, url: url)
        guard let http = response as? HTTPURLResponse else {
            throw NativeDownloadError.unsupported("POST did not return an HTTP response from \(url.absoluteString)")
        }
        return (data, http)
    }

    func postForm(to url: URL, fields: [String: String], referer: String? = nil, userAgent: String? = nil, additionalHeaders: [String: String] = [:]) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        let body = fields
            .map { key, value in
                "\(Self.formEscape(key))=\(Self.formEscape(value))"
            }
            .joined(separator: "&")
        request.httpBody = body.data(using: .utf8)
#if TESTING
        if let body = request.httpBody {
            let testingRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
            URLProtocol.setProperty(body, forKey: "HitomiBadayoTestingHTTPBody", in: testingRequest)
            request = testingRequest as URLRequest
        }
#endif
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/plain, */*", forHTTPHeaderField: "Accept")
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Cookie") == nil,
           let cookie = await CookieStore.shared.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let session = makeSession(for: url)
        try await waitUntilTransfersResume()
        let (data, response) = try await session.data(for: request)
        await CookieStore.shared.storeCookies(from: response, url: url)
        try validate(response: response, url: url)
        return data
    }

    @discardableResult
    func download(
        from url: URL,
        to destination: URL,
        referer: String? = nil,
        userAgent: String? = nil,
        additionalHeaders: [String: String] = [:],
        retryLimitOverride: Int? = nil,
        progressHandler: HTTPDownloadProgressHandler? = nil
    ) async throws -> HTTPURLResponse? {
        let (temporaryURL, response) = try await downloadTemporary(
            from: url,
            referer: referer,
            userAgent: userAgent,
            additionalHeaders: additionalHeaders,
            retryLimitOverride: retryLimitOverride,
            progressHandler: progressHandler
        )

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        return response
    }

    func downloadTemporary(
        from url: URL,
        referer: String? = nil,
        userAgent: String? = nil,
        additionalHeaders: [String: String] = [:],
        retryLimitOverride: Int? = nil,
        progressHandler: HTTPDownloadProgressHandler? = nil
    ) async throws -> (fileURL: URL, response: HTTPURLResponse?) {
        var request = URLRequest(url: url)
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Cookie") == nil,
           let cookie = await CookieStore.shared.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let session = makeSession(for: url)
        let maxRetryAttempts = max(0, retryLimitOverride ?? retryAttemptLimit(for: url))
        var resumeData: Data?
        for attempt in 0...maxRetryAttempts {
            do {
                try await waitBeforeImageRequestIfNeeded(url)
                try await waitUntilTransfersResume()
                let result: (URL, URLResponse)
                if let progressHandler {
                    let delegate = HTTPDownloadProgressDelegate(handler: progressHandler)
                    registerProgressDelegate(delegate)
                    defer { unregisterProgressDelegate(delegate) }
                    result = try await delegate.download(
                        request: request,
                        resumeData: resumeData,
                        configuration: makeSessionConfiguration(for: url)
                    )
                } else if let pendingResumeData = resumeData {
                    result = try await session.download(resumeFrom: pendingResumeData)
                } else {
                    result = try await session.download(for: request)
                }
                resumeData = nil
                let (temporaryURL, response) = result
                await CookieStore.shared.storeCookies(from: response, url: url)
                if let http = response as? HTTPURLResponse,
                   shouldRetry(statusCode: http.statusCode, url: url, attempt: attempt),
                   attempt < maxRetryAttempts {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    try await waitBeforeRetry(attempt: attempt, response: http, url: url)
                    continue
                }
                do {
                    try validate(response: response, url: url)
                    try validateDownloadedImageIfNeeded(
                        temporaryURL,
                        response: response as? HTTPURLResponse,
                        sourceURL: url
                    )
                } catch {
                    try? FileManager.default.removeItem(at: temporaryURL)
                    throw error
                }
                return (temporaryURL, response as? HTTPURLResponse)
            } catch {
                if let recovered = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data,
                   !recovered.isEmpty {
                    resumeData = recovered
                }
                guard shouldRetry(error: error), attempt < maxRetryAttempts else {
                    throw error
                }
                try await waitBeforeRetry(attempt: attempt, response: nil, url: url)
            }
        }
        throw NativeDownloadError.unsupported("Download retry limit exceeded for \(url.absoluteString)")
    }

    func head(from url: URL, referer: String? = nil, userAgent: String? = nil, additionalHeaders: [String: String] = [:]) async throws -> HTTPURLResponse? {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        if let referer {
            request.setValue(referer, forHTTPHeaderField: "Referer")
        }
        if let userAgent {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }
        if request.value(forHTTPHeaderField: "Cookie") == nil,
           let cookie = await CookieStore.shared.cookieHeader(for: url) {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }

        let session = makeSession(for: url)
        let maxRetryAttempts = retryAttemptLimit(for: url)
        for attempt in 0...maxRetryAttempts {
            do {
                try await waitUntilTransfersResume()
                let (_, response) = try await session.data(for: request)
                await CookieStore.shared.storeCookies(from: response, url: url)
                if let http = response as? HTTPURLResponse,
                   shouldRetry(statusCode: http.statusCode, url: url, attempt: attempt),
                   attempt < maxRetryAttempts {
                    try await waitBeforeRetry(attempt: attempt, response: http, url: url)
                    continue
                }
                try validate(response: response, url: url)
                return response as? HTTPURLResponse
            } catch {
                guard shouldRetry(error: error), attempt < maxRetryAttempts else {
                    throw error
                }
                try await waitBeforeRetry(attempt: attempt, response: nil, url: url)
            }
        }
        throw NativeDownloadError.unsupported("HEAD retry limit exceeded for \(url.absoluteString)")
    }

    private func shouldRetry(statusCode: Int, url: URL, attempt: Int) -> Bool {
        if statusCode == 404, isHitomiImageCDNURL(url) {
            return attempt < 3
        }
        return retryableStatusCodes.contains(statusCode)
    }

    private func shouldRetry(error: Error) -> Bool {
        if error is HTTPDownloadValidationError {
            return true
        }
        guard let urlError = error as? URLError else {
            return false
        }
        return retryableURLErrorCodes.contains(urlError.code)
    }

    private func retryAttemptLimit(for url: URL) -> Int {
        isHitomiImageCDNURL(url) ? hitomiImageMaxRetryAttempts : defaultMaxRetryAttempts
    }

    private func isHitomiImageCDNURL(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased(),
              host.hasSuffix(".gold-usergeneratedcontent.net"),
              let firstLabel = host.split(separator: ".").first,
              firstLabel.count > 1,
              firstLabel.first == "w",
              firstLabel.dropFirst().allSatisfy(\.isNumber) else {
            return false
        }
        return true
    }

    private func waitBeforeImageRequestIfNeeded(_ url: URL) async throws {
        guard isHitomiImageCDNURL(url) else { return }
        if url.pathExtension.lowercased() == "webp" {
            try await hitomiWebPRequestLimiter.wait()
        } else {
            try await hitomiOriginalRequestLimiter.wait()
        }
    }

    private func validateDownloadedImageIfNeeded(
        _ fileURL: URL,
        response: HTTPURLResponse?,
        sourceURL: URL
    ) throws {
        guard isHitomiImageCDNURL(sourceURL) || Self.isEHentaiImageHost(sourceURL.host?.lowercased() ?? "") else {
            return
        }
        let size = Int64((try fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        guard size >= 128 else {
            throw HTTPDownloadValidationError.tooSmall(sourceURL, size)
        }
        let contentType = response?.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        let reader = try FileHandle(forReadingFrom: fileURL)
        defer { try? reader.close() }
        let prefix = try reader.read(upToCount: 1_024) ?? Data()
        let text = String(data: prefix, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        if contentType.contains("text/html") || text.hasPrefix("<!doctype html") || text.hasPrefix("<html") {
            throw HTTPDownloadValidationError.html(sourceURL)
        }
    }

    private static func isEHentaiImageHost(_ host: String) -> Bool {
        host.contains("hath.network") ||
            host.contains("ehgt.org") ||
            host.contains("e-hentai.org") ||
            host.contains("exhentai.org") ||
            host.contains("e-hentai.test") ||
            host.contains("exhentai.test")
    }

    private func waitBeforeRetry(attempt: Int, response: HTTPURLResponse?, url: URL) async throws {
        let seconds = retryDelaySeconds(attempt: attempt, response: response, url: url)
        guard seconds > 0 else { return }
        let nanoseconds = UInt64(seconds * 1_000_000_000)
        try await Task.sleep(nanoseconds: nanoseconds)
    }

    private func retryDelaySeconds(attempt: Int, response: HTTPURLResponse?, url: URL) -> Double {
        if let retryAfter = response?.value(forHTTPHeaderField: "Retry-After")?.trimmed,
           !retryAfter.isEmpty {
            if let seconds = Double(retryAfter) {
                return min(max(seconds, 0), maxRetryAfterSeconds)
            }
            if let date = Self.retryAfterDateFormatter.date(from: retryAfter) {
                return min(max(date.timeIntervalSinceNow, 0), maxRetryAfterSeconds)
            }
        }
        if isHitomiImageCDNURL(url) {
            return hitomiImageRetryDelaySeconds
        }
        return min(pow(2.0, Double(attempt)), maxRetryAfterSeconds)
    }

    private static func formEscape(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&+=")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private func validate(response: URLResponse, url: URL) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard 200..<300 ~= http.statusCode else {
            throw NativeDownloadError.httpStatus(http.statusCode, url)
        }
    }

    private static let retryAfterDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter
    }()
}
