import Foundation

enum GalleryNumberCopyOutcome:
    Equatable,
    Sendable
{
    case copied(count: Int)
    case copyFailed
    case noNumbers
}

@MainActor
final class GalleryNumberCopyCoordinator {
    typealias Scanner =
        @Sendable (URL) async -> [String]

    let clipboardCommandService:
        ClipboardCommandService
    private let scanner: Scanner
    private var task: Task<Void, Never>?

    init(
        service:
            HitomiGalleryNumberService =
                HitomiGalleryNumberService(),
        clipboardCommandService:
            ClipboardCommandService,
        scanner: Scanner? = nil
    ) {
        self.clipboardCommandService =
            clipboardCommandService
        if let scanner {
            self.scanner = scanner
        } else {
            self.scanner = { root in
                let scanTask =
                    Task.detached(
                        priority: .userInitiated
                    ) {
                        service.numbers(in: root)
                    }
                return await withTaskCancellationHandler {
                    await scanTask.value
                } onCancel: {
                    scanTask.cancel()
                }
            }
        }
    }

    var hasActiveScan: Bool {
        task != nil
    }

    @discardableResult
    func begin(
        root: URL,
        completion:
            @escaping @MainActor (
                GalleryNumberCopyOutcome
            ) -> Void
    ) -> Bool {
        guard task == nil else {
            return false
        }
        let scanner = scanner
        task = Task { @MainActor [weak self] in
            let numbers = await scanner(root)
            guard !Task.isCancelled,
                  let self,
                  self.task != nil else {
                return
            }
            self.task = nil
            guard !numbers.isEmpty else {
                completion(.noNumbers)
                return
            }
            completion(
                self.clipboardCommandService
                    .copyText(
                        numbers.joined(
                            separator: "\n"
                        )
                    )
                ? .copied(count: numbers.count)
                : .copyFailed
            )
        }
        return true
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        guard let task else {
            return false
        }
        self.task = nil
        task.cancel()
        return true
    }

    deinit {
        task?.cancel()
    }
}
