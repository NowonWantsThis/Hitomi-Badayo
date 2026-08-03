import Foundation

struct CookieTextImportValues:
    Equatable,
    Sendable
{
    let imported: Int
    let skipped: Int
}

struct BrowserCookieImportValues:
    Equatable,
    Sendable
{
    let browserName: String
    let imported: Int
    let skipped: Int
    let encryptedSkipped: Int
    let profilesScanned: Int
}

enum CookieManagementOperation:
    Equatable,
    Sendable
{
    case loadPersistedSummary
    case importTextFile(URL)
    case importBrowserDatabase(URL)
    case importDetectedBrowserDatabases
    case clear
}

struct CookieManagementOutcome:
    Equatable,
    Sendable
{
    let operation: CookieManagementOperation
    let cookieSummary: String
    let addSummary: String?
}

struct CookieManagementService: Sendable {
    typealias TextReader =
        @Sendable (URL) throws -> String
    typealias TextImporter =
        @Sendable (String) async ->
            CookieTextImportValues
    typealias BrowserImporter =
        @Sendable (URL) async throws ->
            BrowserCookieImportValues
    typealias BrowserDetector =
        @Sendable () async throws ->
            BrowserCookieImportValues
    typealias BrowserSessionClearer =
        @MainActor @Sendable () async -> Int
    typealias CookieClearer =
        @Sendable () async -> Void
    typealias CookieCounter =
        @Sendable () async -> Int

    private let sourceAuthenticationPolicy:
        SourceAuthenticationPolicy
    private let textReader: TextReader
    private let textImporter: TextImporter
    private let browserImporter: BrowserImporter
    private let browserDetector: BrowserDetector
    private let browserSessionClearer:
        BrowserSessionClearer
    private let cookieClearer: CookieClearer
    private let cookieCounter: CookieCounter

    init(
        sourceAuthenticationPolicy:
            SourceAuthenticationPolicy =
                SourceAuthenticationPolicy(),
        textReader:
            @escaping TextReader = {
                try String(
                    contentsOf: $0,
                    encoding: .utf8
                )
            },
        textImporter:
            @escaping TextImporter = {
                let result =
                    CookieStore.shared
                    .importText($0)
                return CookieTextImportValues(
                    imported: result.imported,
                    skipped: result.skipped
                )
            },
        browserImporter:
            @escaping BrowserImporter = {
                let result =
                    try CookieStore.shared
                    .importBrowserDatabase(from: $0)
                return BrowserCookieImportValues(
                    browserName: result.browserName,
                    imported: result.imported,
                    skipped: result.skipped,
                    encryptedSkipped:
                        result.encryptedSkipped,
                    profilesScanned:
                        result.profilesScanned
                )
            },
        browserDetector:
            @escaping BrowserDetector = {
                let result =
                    try CookieStore.shared
                    .importDetectedBrowserDatabases()
                return BrowserCookieImportValues(
                    browserName: result.browserName,
                    imported: result.imported,
                    skipped: result.skipped,
                    encryptedSkipped:
                        result.encryptedSkipped,
                    profilesScanned:
                        result.profilesScanned
                )
            },
        browserSessionClearer:
            @escaping BrowserSessionClearer = {
                await LoginBrowserWindowController
                    .clearAllWebsiteData()
            },
        cookieClearer:
            @escaping CookieClearer = {
                CookieStore.shared.clear()
            },
        cookieCounter:
            @escaping CookieCounter = {
                CookieStore.shared.count
            }
    ) {
        self.sourceAuthenticationPolicy =
            sourceAuthenticationPolicy
        self.textReader = textReader
        self.textImporter = textImporter
        self.browserImporter = browserImporter
        self.browserDetector = browserDetector
        self.browserSessionClearer =
            browserSessionClearer
        self.cookieClearer = cookieClearer
        self.cookieCounter = cookieCounter
    }

    func perform(
        _ operation: CookieManagementOperation
    ) async -> CookieManagementOutcome {
        switch operation {
        case .loadPersistedSummary:
            return await loadPersistedSummary()
        case .importTextFile(let url):
            return await importTextFile(from: url)
        case .importBrowserDatabase(let url):
            return await importBrowserDatabase(
                from: url
            )
        case .importDetectedBrowserDatabases:
            return await importDetectedBrowserDatabases()
        case .clear:
            return await clear()
        }
    }

    private func loadPersistedSummary()
        async -> CookieManagementOutcome
    {
        let count = await cookieCounter()
        return CookieManagementOutcome(
            operation: .loadPersistedSummary,
            cookieSummary:
                count == 0
                ? "No readable saved cookies"
                : "\(count) saved cookies",
            addSummary: nil
        )
    }

    private func importTextFile(
        from url: URL
    ) async -> CookieManagementOutcome {
        do {
            let text = try textReader(url)
            let result = await textImporter(text)
            var summary =
                "\(result.imported) cookies"
            if result.skipped > 0 {
                summary +=
                    ", \(result.skipped) skipped"
            }
            return CookieManagementOutcome(
                operation: .importTextFile(url),
                cookieSummary: summary,
                addSummary: nil
            )
        } catch {
            return CookieManagementOutcome(
                operation: .importTextFile(url),
                cookieSummary:
                    "Cookie import failed",
                addSummary: nil
            )
        }
    }

    private func importBrowserDatabase(
        from url: URL
    ) async -> CookieManagementOutcome {
        do {
            let result = try await browserImporter(url)
            var summary =
                "\(result.imported) \(result.browserName) cookies"
            let skipped =
                result.skipped +
                result.encryptedSkipped
            if skipped > 0 {
                summary += ", \(skipped) skipped"
            }
            return CookieManagementOutcome(
                operation:
                    .importBrowserDatabase(url),
                cookieSummary: summary,
                addSummary: nil
            )
        } catch {
            return CookieManagementOutcome(
                operation:
                    .importBrowserDatabase(url),
                cookieSummary:
                    "Browser cookie import failed",
                addSummary: nil
            )
        }
    }

    private func importDetectedBrowserDatabases()
        async -> CookieManagementOutcome
    {
        do {
            let result = try await browserDetector()
            var summary =
                sourceAuthenticationPolicy
                .browserCookieSummary(
                    imported: result.imported,
                    skipped: result.skipped
                )
            if result.profilesScanned > 1 {
                summary +=
                    " from \(result.profilesScanned) profiles"
            }
            let skipped =
                result.skipped +
                result.encryptedSkipped
            if skipped > 0 {
                summary += ", \(skipped) skipped"
            }
            return CookieManagementOutcome(
                operation:
                    .importDetectedBrowserDatabases,
                cookieSummary: summary,
                addSummary: nil
            )
        } catch {
            return CookieManagementOutcome(
                operation:
                    .importDetectedBrowserDatabases,
                cookieSummary: "No browser cookies",
                addSummary: nil
            )
        }
    }

    private func clear()
        async -> CookieManagementOutcome
    {
        let browserSessionCount =
            await browserSessionClearer()
        await cookieClearer()
        return CookieManagementOutcome(
            operation: .clear,
            cookieSummary: "No cookies",
            addSummary:
                browserSessionCount == 0
                ? "Cookies deleted"
                : "Cookies and embedded-browser login sessions deleted"
        )
    }
}

@MainActor
final class CookieManagementCoordinator {
    private let service: CookieManagementService
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        service:
            CookieManagementService =
                CookieManagementService()
    ) {
        self.service = service
    }

    var activeOperationCount: Int {
        tasks.count
    }

    @discardableResult
    func begin(
        _ operation: CookieManagementOperation,
        completion:
            @escaping @MainActor (
                CookieManagementOutcome
            ) -> Void
    ) -> UUID {
        let operationID = UUID()
        let service = service
        tasks[operationID] =
            Task { @MainActor [weak self] in
                let outcome =
                    await service.perform(operation)
                guard !Task.isCancelled,
                      self?.finish(operationID) == true
                else {
                    return
                }
                completion(outcome)
            }
        return operationID
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        return activeTasks.count
    }

    @discardableResult
    private func finish(_ operationID: UUID) -> Bool {
        tasks.removeValue(forKey: operationID) != nil
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
