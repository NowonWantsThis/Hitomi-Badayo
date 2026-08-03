import Foundation

struct OutputImageConversionRequest: Equatable, Sendable {
    var jobID: UUID
    var outputPath: String
}

struct OutputImageConversionJobResult: Equatable, Sendable {
    var request: OutputImageConversionRequest
    var result: OutputImageConversionResult?
    var errorDescription: String?
}

@MainActor
final class OutputImageConversionCoordinator {
    typealias Converter =
        @Sendable (
            OutputImageConversionRequest,
            ImageConversionFormat,
            Int
        ) -> OutputImageConversionJobResult

    private let converter: Converter
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var activeOperationIDs: Set<UUID> = []

    init(
        converter:
            @escaping Converter = {
                request,
                format,
                quality in
                do {
                    return OutputImageConversionJobResult(
                        request: request,
                        result:
                            try OutputService()
                            .convertOutputImages(
                                forOutputPath:
                                    request.outputPath,
                                to: format,
                                quality: quality
                            ),
                        errorDescription: nil
                    )
                } catch {
                    return OutputImageConversionJobResult(
                        request: request,
                        result: nil,
                        errorDescription:
                            AppLocalization.errorText(error)
                    )
                }
            }
    ) {
        self.converter = converter
    }

    var activeOperationCount: Int {
        activeOperationIDs.count
    }

    @discardableResult
    func start(
        requests: [OutputImageConversionRequest],
        format: ImageConversionFormat,
        quality: Int,
        completion:
            @escaping @MainActor (
                [OutputImageConversionJobResult]
            ) -> Void
    ) -> UUID {
        let operationID = UUID()
        let converter = converter
        activeOperationIDs.insert(operationID)

        let task = Task { @MainActor [weak self] in
            let conversionTask = Task.detached(
                priority: .userInitiated
            ) {
                requests.map {
                    converter($0, format, quality)
                }
            }
            let results = await withTaskCancellationHandler {
                await conversionTask.value
            } onCancel: {
                conversionTask.cancel()
            }

            guard !Task.isCancelled,
                  self?.finish(operationID) == true else {
                return
            }
            completion(results)
        }
        tasks[operationID] = task
        return operationID
    }

    @discardableResult
    func cancel(_ operationID: UUID) -> Bool {
        guard activeOperationIDs.remove(operationID) != nil else {
            return false
        }
        tasks.removeValue(forKey: operationID)?.cancel()
        return true
    }

    @discardableResult
    func cancelAll() -> Int {
        let activeTasks = Array(tasks.values)
        let count = activeOperationIDs.count
        tasks.removeAll()
        activeOperationIDs.removeAll()
        activeTasks.forEach { $0.cancel() }
        return count
    }

    @discardableResult
    private func finish(_ operationID: UUID) -> Bool {
        guard activeOperationIDs.remove(operationID) != nil else {
            return false
        }
        tasks.removeValue(forKey: operationID)
        return true
    }

    deinit {
        tasks.values.forEach { $0.cancel() }
    }
}
