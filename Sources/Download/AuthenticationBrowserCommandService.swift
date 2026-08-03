import Foundation

struct AuthenticationBrowserRequest:
    Equatable
{
    var provider:
        SourceAuthenticationProvider?
    var url: URL
    var reuseKey: String?
    var autoImportPolicy:
        LoginBrowserAutoImportPolicy
    var openedSummary: String
}

@MainActor
final class AuthenticationBrowserCommandService {
    let authenticationPolicy:
        SourceAuthenticationPolicy

    init(
        authenticationPolicy:
            SourceAuthenticationPolicy
    ) {
        self.authenticationPolicy =
            authenticationPolicy
    }

    func request(
        url: URL,
        authenticationKey: String?
    ) -> AuthenticationBrowserRequest {
        if let authenticationKey,
           let provider =
            SourceAuthenticationProvider(
                rawValue: authenticationKey
            ) {
            return request(provider: provider)
        }

        if let providerKey =
            authenticationPolicy.providerKey(
                for: url
            ),
           let provider =
            SourceAuthenticationProvider(
                rawValue: providerKey
            ) {
            return request(
                provider: provider,
                loginURL:
                    provider == .arcalive
                    ? url
                    : nil
            )
        }

        return AuthenticationBrowserRequest(
            provider: nil,
            url: url,
            reuseKey: nil,
            autoImportPolicy: .none,
            openedSummary:
                "Login browser opened"
        )
    }

    func request(
        provider: SourceAuthenticationProvider,
        loginURL: URL? = nil
    ) -> AuthenticationBrowserRequest {
        switch provider {
        case .pixiv:
            return AuthenticationBrowserRequest(
                provider: provider,
                url:
                    SourceAuthenticationPolicy
                    .pixivLoginURL,
                reuseKey: "pixiv-login",
                autoImportPolicy:
                    .pixivSession,
                openedSummary:
                    "Pixiv login browser opened"
            )
        case .chzzk:
            return AuthenticationBrowserRequest(
                provider: provider,
                url:
                    SourceAuthenticationPolicy
                    .chzzkLoginURL,
                reuseKey: "chzzk-login",
                autoImportPolicy:
                    .chzzkSession,
                openedSummary:
                    "Chzzk login browser opened"
            )
        case .naverCafe:
            return AuthenticationBrowserRequest(
                provider: provider,
                url:
                    SourceAuthenticationPolicy
                    .naverCafeLoginURL,
                reuseKey: "naver-cafe-login",
                autoImportPolicy:
                    .naverSession,
                openedSummary:
                    "Naver Cafe login browser opened"
            )
        case .twitter:
            return AuthenticationBrowserRequest(
                provider: provider,
                url:
                    SourceAuthenticationPolicy
                    .twitterLoginURL,
                reuseKey: "twitter-login",
                autoImportPolicy:
                    .twitterSession,
                openedSummary:
                    "Twitter/X login browser opened"
            )
        case .pornhubPremium:
            return AuthenticationBrowserRequest(
                provider: provider,
                url:
                    SourceAuthenticationPolicy
                    .pornhubPremiumLoginURL,
                reuseKey:
                    "pornhub-premium-login",
                autoImportPolicy:
                    .pornhubSession,
                openedSummary:
                    "Pornhub Premium login browser opened"
            )
        case .arcalive:
            return AuthenticationBrowserRequest(
                provider: provider,
                url:
                    loginURL ??
                    SourceAuthenticationPolicy
                    .arcaliveLoginURL,
                reuseKey: "arcalive-login",
                autoImportPolicy:
                    .arcaliveSession,
                openedSummary:
                    "Arcalive login browser opened"
            )
        }
    }

    func open(
        _ request:
            AuthenticationBrowserRequest,
        onCookiesImported:
            @escaping @MainActor (
                Int,
                Int
            ) -> Void
    ) {
        LoginBrowserWindowController.open(
            url: request.url,
            reuseKey: request.reuseKey,
            autoImportPolicy:
                request.autoImportPolicy,
            onCookiesImported:
                onCookiesImported
        )
    }
}
