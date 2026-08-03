import Foundation

struct SourceResolverAuthenticationActions {
    var waitForArcalive:
        (URL) async -> Void
    var waitForChzzk: () async -> Void
    var waitForNaverCafe: () async -> Void
    var waitForPixiv: () async -> Void
    var waitForPornhub: () async -> Void
    var waitForTwitter: () async -> Void
}

@MainActor
final class SourceResolverAuthenticationDispatchService {
    func wait(
        for request:
            SourceResolverAuthenticationRequest,
        actions:
            SourceResolverAuthenticationActions
    ) async {
        switch request {
        case .arcalive(let loginURL):
            await actions.waitForArcalive(loginURL)
        case .chzzk:
            await actions.waitForChzzk()
        case .naverCafe:
            await actions.waitForNaverCafe()
        case .pixiv:
            await actions.waitForPixiv()
        case .pornhub:
            await actions.waitForPornhub()
        case .twitter:
            await actions.waitForTwitter()
        }
    }
}
