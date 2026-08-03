import Foundation

@MainActor
final class SourceResolverAuthenticationCoordinator {
    func resolve<Value, AuthenticationRequest>(
        operation: @MainActor () async throws -> Value,
        authenticationRequest: (Error) -> AuthenticationRequest?,
        waitForAuthentication: @MainActor (AuthenticationRequest) async -> Void,
        ensureActive: @MainActor () throws -> Void
    ) async throws -> Value {
        while true {
            do {
                return try await operation()
            } catch {
                guard let request = authenticationRequest(error) else {
                    throw error
                }
                try Task.checkCancellation()
                await waitForAuthentication(request)
                try Task.checkCancellation()
                try ensureActive()
            }
        }
    }
}
