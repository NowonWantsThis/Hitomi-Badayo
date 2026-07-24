import Foundation

@MainActor
protocol ApplicationTerminationPreparing: AnyObject {
    func prepareForApplicationTermination(
        _ completion: @escaping @MainActor (Bool) -> Void
    )
}

@MainActor
final class ApplicationTerminationPreparation {
    private enum State {
        case idle
        case preparing
        case prepared
    }

    private var state = State.idle
    private var task: Task<Void, Never>?
    private var completions: [@MainActor (Bool) -> Void] = []

    var isPrepared: Bool {
        state == .prepared
    }

    func prepare(
        operation: @escaping @MainActor () async -> Bool,
        completion: @escaping @MainActor (Bool) -> Void
    ) {
        switch state {
        case .prepared:
            completion(true)
        case .preparing:
            completions.append(completion)
        case .idle:
            state = .preparing
            completions = [completion]
            task = Task { [weak self] in
                guard let self else { return }
                let succeeded = await operation()
                state = succeeded ? .prepared : .idle
                task = nil
                let pending = completions
                completions.removeAll()
                pending.forEach { $0(succeeded) }
            }
        }
    }
}
