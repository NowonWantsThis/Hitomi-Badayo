import Foundation

@MainActor
final class AuthenticationCookieImportService {
    let authenticationPolicy:
        SourceAuthenticationPolicy
    let verificationCoordinator:
        SourceAuthenticationVerificationCoordinator
    let waitCoordinator:
        AuthenticationWaitCoordinator

    init(
        authenticationPolicy:
            SourceAuthenticationPolicy,
        verificationCoordinator:
            SourceAuthenticationVerificationCoordinator,
        waitCoordinator:
            AuthenticationWaitCoordinator
    ) {
        self.authenticationPolicy =
            authenticationPolicy
        self.verificationCoordinator =
            verificationCoordinator
        self.waitCoordinator = waitCoordinator
    }

    func apply(
        provider: SourceAuthenticationProvider,
        imported: Int,
        skipped: Int,
        setCookieSummary:
            @escaping @MainActor (String) -> Void,
        setSummary:
            @escaping @MainActor (String) -> Void
    ) {
        setCookieSummary(
            authenticationPolicy
                .browserCookieSummary(
                    imported: imported,
                    skipped: skipped
                )
        )

        verificationCoordinator.begin(
            provider: provider
        ) { [weak self] result in
            guard let self else { return }
            let waitingCount =
                waitCoordinator.waitingCount(
                    for: provider.rawValue
                )
            setSummary(
                result.summary(
                    waitingCount: waitingCount
                )
            )
            guard result.isAuthenticated else {
                return
            }
            waitCoordinator.resumeAll(
                for: provider.rawValue
            )
        }
    }
}
