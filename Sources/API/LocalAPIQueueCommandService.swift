import Foundation

struct LocalAPIQueueCommandState {
    var count: Int
    var isRunning: Bool
    var apiStatus: String
}

@MainActor
struct LocalAPIQueueCommandService {
    func enqueueInput(
        hasInput: Bool,
        shouldStart: Bool,
        usesOriginalActionShape: Bool,
        enqueue: () -> Int,
        start: () -> Void,
        state: () -> LocalAPIQueueCommandState
    ) -> LocalHTTPResponse {
        guard hasInput else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Missing url"],
                status: 400
            )
        }

        let added = enqueue()
        if shouldStart {
            start()
        }
        let snapshot = state()
        let message = "\(added) URL\(added == 1 ? "" : "s") added"
        return LocalHTTPResponse.jsonObject([
            "ok": added > 0,
            "res": usesOriginalActionShape ? "ok" : message,
            "message": message,
            "added": added,
            "total": snapshot.count,
            "running": snapshot.isRunning
        ])
    }

    func start(
        action: () -> Void,
        state: () -> LocalAPIQueueCommandState
    ) -> LocalHTTPResponse {
        action()
        return LocalHTTPResponse.jsonObject([
            "running": state().isRunning
        ])
    }

    func stop(
        action: () -> Void,
        state: () -> LocalAPIQueueCommandState
    ) -> LocalHTTPResponse {
        action()
        return LocalHTTPResponse.jsonObject([
            "running": state().isRunning
        ])
    }

    func clearFinished(
        action: () -> Int,
        state: () -> LocalAPIQueueCommandState
    ) -> LocalHTTPResponse {
        let removed = action()
        let snapshot = state()
        return LocalHTTPResponse.jsonObject([
            "count": snapshot.count,
            "removed": removed,
            "removedCount": removed,
            "running": snapshot.isRunning
        ])
    }

    func save(
        persistQueue: () -> Void,
        persistSettings: () -> Void,
        state: () -> LocalAPIQueueCommandState
    ) -> LocalHTTPResponse {
        persistQueue()
        persistSettings()
        let snapshot = state()
        return LocalHTTPResponse.jsonObject([
            "ok": true,
            "res": "saved",
            "err": "",
            "saved": true,
            "count": snapshot.count,
            "status": snapshot.apiStatus
        ])
    }
}
