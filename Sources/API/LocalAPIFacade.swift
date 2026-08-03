import Foundation

struct LocalAPIFacadeOperations {
    var staticAsset: (LocalHTTPRequest) -> LocalHTTPResponse
    var login: (LocalHTTPRequest) -> LocalHTTPResponse
    var loginRedirect: (LocalHTTPRequest) -> LocalHTTPResponse
    var authorized: (
        LocalAPIRoute,
        LocalHTTPRequest
    ) async -> LocalHTTPResponse
}

@MainActor
struct LocalAPIFacade {
    private let router: LocalAPIRouter
    private let authorizationPolicy: LocalAPIAuthorizationPolicy

    init(
        router: LocalAPIRouter = LocalAPIRouter(),
        authorizationPolicy: LocalAPIAuthorizationPolicy =
            LocalAPIAuthorizationPolicy()
    ) {
        self.router = router
        self.authorizationPolicy = authorizationPolicy
    }

    func response(
        for request: LocalHTTPRequest,
        password: String,
        operations: LocalAPIFacadeOperations
    ) async -> LocalHTTPResponse {
        let route = router.route(for: request)

        switch route {
        case .preflight:
            return LocalHTTPResponse.data(
                Data(),
                contentType: "text/plain; charset=utf-8",
                status: 204
            )
        case .staticAsset:
            return operations.staticAsset(request)
        case .login:
            return operations.login(request)
        default:
            break
        }

        guard authorizationPolicy.isAuthorized(
            request,
            password: password
        ) else {
            if request.method == "GET", router.isWebUIPath(request.path) {
                return operations.loginRedirect(request)
            }
            return LocalHTTPResponse.jsonObject(
                ["error": "Unauthorized"],
                status: 401
            )
        }

        return await operations.authorized(route, request)
    }
}
