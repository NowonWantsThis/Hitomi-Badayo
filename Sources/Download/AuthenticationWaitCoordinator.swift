import Foundation

@MainActor
final class AuthenticationWaitCoordinator {
    private static let providerOrder = [
        "pixiv",
        "chzzk",
        "naver-cafe",
        "twitter",
        "pornhub-premium",
        "arcalive"
    ]

    private var continuations:
        [String: [UUID: CheckedContinuation<Void, Never>]] =
        [:]

    var waitingCount: Int {
        continuations.values.reduce(0) {
            $0 + $1.count
        }
    }

    func waitingCount(
        for provider: String
    ) -> Int {
        continuations[provider]?.count ?? 0
    }

    func wait(
        jobID: UUID,
        provider: String,
        onRegistered: @MainActor @escaping () -> Void
    ) async {
        await withTaskCancellationHandler {
            await withCheckedContinuation {
                continuation in
                if Task.isCancelled {
                    continuation.resume()
                    return
                }
                var providerContinuations =
                    continuations[provider] ?? [:]
                let previous =
                    providerContinuations.updateValue(
                        continuation,
                        forKey: jobID
                    )
                continuations[provider] =
                    providerContinuations
                previous?.resume()
                onRegistered()
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.resume(
                    jobID: jobID,
                    provider: provider
                )
            }
        }
    }

    @discardableResult
    func resume(
        jobID: UUID,
        provider: String
    ) -> Bool {
        guard var providerContinuations =
            continuations[provider],
            let continuation =
            providerContinuations.removeValue(
                forKey: jobID
            )
        else {
            return false
        }
        if providerContinuations.isEmpty {
            continuations.removeValue(
                forKey: provider
            )
        } else {
            continuations[provider] =
                providerContinuations
        }
        continuation.resume()
        return true
    }

    @discardableResult
    func resume(jobID: UUID) -> Int {
        var resumed = 0
        for provider in orderedProviders() {
            if resume(
                jobID: jobID,
                provider: provider
            ) {
                resumed += 1
            }
        }
        return resumed
    }

    @discardableResult
    func resumeAll(
        for provider: String
    ) -> Int {
        guard let providerContinuations =
            continuations.removeValue(
                forKey: provider
            )
        else {
            return 0
        }
        let values =
            Array(providerContinuations.values)
        values.forEach { $0.resume() }
        return values.count
    }

    @discardableResult
    func resumeAll() -> Int {
        var resumed = 0
        for provider in orderedProviders() {
            resumed += resumeAll(for: provider)
        }
        return resumed
    }

    private func orderedProviders() -> [String] {
        let known = Set(Self.providerOrder)
        let additional = continuations.keys
            .filter { !known.contains($0) }
            .sorted()
        return Self.providerOrder + additional
    }
}
