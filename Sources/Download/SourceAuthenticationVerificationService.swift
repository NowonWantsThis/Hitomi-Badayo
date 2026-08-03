import Foundation

enum SourceAuthenticationProvider:
    String,
    CaseIterable,
    Hashable,
    Sendable
{
    case pixiv
    case chzzk
    case naverCafe = "naver-cafe"
    case twitter
    case pornhubPremium = "pornhub-premium"
    case arcalive
}

struct SourceAuthenticationVerificationResult:
    Equatable,
    Sendable
{
    let provider: SourceAuthenticationProvider
    let isAuthenticated: Bool

    func summary(waitingCount: Int) -> String {
        guard isAuthenticated else {
            return missingAuthenticationSummary
        }

        switch provider {
        case .twitter, .pornhubPremium, .arcalive:
            if waitingCount == 0 {
                return "\(displayName) login saved"
            }
        case .pixiv, .chzzk, .naverCafe:
            break
        }

        return waitingCount == 1
            ? "\(displayName) login saved - retrying download"
            : "\(displayName) login saved - retrying \(waitingCount) downloads"
    }

    private var displayName: String {
        switch provider {
        case .pixiv:
            return "Pixiv"
        case .chzzk:
            return "Chzzk"
        case .naverCafe:
            return "Naver Cafe"
        case .twitter:
            return "Twitter/X"
        case .pornhubPremium:
            return "Pornhub Premium"
        case .arcalive:
            return "Arcalive"
        }
    }

    private var missingAuthenticationSummary: String {
        switch provider {
        case .pixiv:
            return "Pixiv login cookie not found"
        case .chzzk:
            return "Chzzk login cookie not found"
        case .naverCafe:
            return "Naver login cookie not found"
        case .twitter:
            return "Twitter/X login cookies not found"
        case .pornhubPremium:
            return "Pornhub Premium login was not detected"
        case .arcalive:
            return "Arcalive login cookie not found"
        }
    }
}

struct SourceAuthenticationVerificationService: Sendable {
    typealias CookieValueLoader =
        @Sendable (String, URL) async -> String?
    typealias CookieHeaderLoader =
        @Sendable (URL) async -> String?
    typealias PremiumSessionChecker =
        @Sendable () async -> Bool

    private let cookieValueLoader: CookieValueLoader
    private let cookieHeaderLoader: CookieHeaderLoader
    private let premiumSessionChecker:
        PremiumSessionChecker

    init(
        cookieValueLoader:
            @escaping CookieValueLoader = {
                CookieStore.shared.cookieValue(
                    named: $0,
                    for: $1
                )
            },
        cookieHeaderLoader:
            @escaping CookieHeaderLoader = {
                CookieStore.shared.cookieHeader(
                    for: $0
                )
            },
        premiumSessionChecker:
            @escaping PremiumSessionChecker = {
                (try? await PornhubMediaResolver
                    .premiumSessionIsAuthenticated()) == true
            }
    ) {
        self.cookieValueLoader = cookieValueLoader
        self.cookieHeaderLoader = cookieHeaderLoader
        self.premiumSessionChecker =
            premiumSessionChecker
    }

    func verify(
        _ provider: SourceAuthenticationProvider
    ) async -> SourceAuthenticationVerificationResult {
        let isAuthenticated: Bool
        switch provider {
        case .pixiv:
            let value = await cookieValueLoader(
                "PHPSESSID",
                SourceAuthenticationPolicy.pixivCookieURL
            )
            isAuthenticated =
                value.map(
                    Self.isLikelySignedInPixivSessionValue
                ) ?? false
        case .chzzk:
            isAuthenticated = await hasNaverSession(
                for:
                    SourceAuthenticationPolicy
                    .chzzkCookieURL
            )
        case .naverCafe:
            isAuthenticated = await hasNaverSession(
                for:
                    SourceAuthenticationPolicy
                    .naverCafeCookieURL
            )
        case .twitter:
            async let authToken =
                cookieValueLoader(
                    "auth_token",
                    SourceAuthenticationPolicy
                        .twitterCookieURL
                )
            async let csrf =
                cookieValueLoader(
                    "ct0",
                    SourceAuthenticationPolicy
                        .twitterCookieURL
                )
            let values = await (authToken, csrf)
            isAuthenticated =
                values.0?.trimmed.isEmpty == false &&
                values.1?.trimmed.isEmpty == false
        case .pornhubPremium:
            isAuthenticated =
                await premiumSessionChecker()
        case .arcalive:
            let header = await cookieHeaderLoader(
                SourceAuthenticationPolicy
                    .arcaliveCookieURL
            )
            isAuthenticated =
                header?.trimmed.isEmpty == false
        }

        return SourceAuthenticationVerificationResult(
            provider: provider,
            isAuthenticated: isAuthenticated
        )
    }

    static func isLikelySignedInPixivSessionValue(
        _ value: String
    ) -> Bool {
        let components = value.trimmed.split(
            separator: "_",
            maxSplits: 1,
            omittingEmptySubsequences: true
        )
        guard components.count == 2,
              !components[1].isEmpty else {
            return false
        }
        return components[0].allSatisfy(\.isNumber)
    }

    private func hasNaverSession(
        for url: URL
    ) async -> Bool {
        async let nidAut =
            cookieValueLoader("NID_AUT", url)
        async let nidSes =
            cookieValueLoader("NID_SES", url)
        let values = await (nidAut, nidSes)
        return [values.0, values.1].contains {
            $0?.trimmed.isEmpty == false
        }
    }
}

@MainActor
final class SourceAuthenticationVerificationCoordinator {
    private let service:
        SourceAuthenticationVerificationService
    private var tasks: [UUID: Task<Void, Never>] = [:]

    init(
        service:
            SourceAuthenticationVerificationService =
                SourceAuthenticationVerificationService()
    ) {
        self.service = service
    }

    var activeRequestCount: Int {
        tasks.count
    }

    @discardableResult
    func begin(
        provider: SourceAuthenticationProvider,
        completion:
            @escaping @MainActor (
                SourceAuthenticationVerificationResult
            ) -> Void
    ) -> UUID {
        let requestID = UUID()
        let service = service
        tasks[requestID] =
            Task { @MainActor [weak self] in
                let result =
                    await service.verify(provider)
                guard !Task.isCancelled,
                      self?.finish(requestID) == true else {
                    return
                }
                completion(result)
            }
        return requestID
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        tasks.removeAll()
        activeTasks.forEach { $0.cancel() }
        return activeTasks.count
    }

    @discardableResult
    private func finish(_ requestID: UUID) -> Bool {
        tasks.removeValue(forKey: requestID) != nil
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
