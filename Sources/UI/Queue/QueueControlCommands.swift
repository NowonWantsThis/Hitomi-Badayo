import SwiftUI

struct QueueControlCommands {
    private let manager: DownloadManager?

    init(manager: DownloadManager? = nil) {
        self.manager = manager
    }

    @MainActor
    func start(addingInput: Bool = true) {
        manager?.startQueue(addingInput: addingInput)
    }

    @MainActor
    func pause() {
        manager?.pauseQueue()
    }

    @MainActor
    func resume() {
        manager?.resumeQueue()
    }

    @MainActor
    func toggleEnabled() {
        manager?.toggleQueueEnabled()
    }

    @MainActor
    func cancel() {
        manager?.cancelQueue()
    }
}

private struct QueueControlCommandsKey: EnvironmentKey {
    static let defaultValue = QueueControlCommands()
}

extension EnvironmentValues {
    var queueControlCommands: QueueControlCommands {
        get { self[QueueControlCommandsKey.self] }
        set { self[QueueControlCommandsKey.self] = newValue }
    }
}
