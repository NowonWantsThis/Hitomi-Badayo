import Foundation

enum LocalAPIExecutionAction: String, CaseIterable {
    case start
    case stop
    case save
    case clear
    case complete
    case pdf
    case archive
    case comment
    case remove
    case delete
    case pause
    case resume
    case aria2Limits = "aria2_limits"
    case aria2Files = "aria2_files"
    case aria2Seed = "aria2_seed"
    case aria2FileList = "aria2_file_list"
    case aria2Peers = "aria2_peers"
    case updateCookies = "update_cookies"
    case download
}

@MainActor
struct LocalAPIExecutionCommandOperations {
    var startQueue: () -> Void
    var stopQueue: () -> Void
    var persistQueueAndSettings: () -> Void
    var clearFinished: () -> Int
    var enqueueInput: (LocalHTTPRequest) -> Int?
    var usesOriginalActionShape: (LocalHTTPRequest) -> Bool
    var state: () -> LocalAPIQueueCommandState
    var delegatedResponse:
        (LocalAPIExecutionAction, LocalHTTPRequest) async ->
            LocalHTTPResponse?
}

@MainActor
struct LocalAPIExecutionCommandService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder =
            LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func response(
        for request: LocalHTTPRequest,
        operations: LocalAPIExecutionCommandOperations
    ) async -> LocalHTTPResponse {
        let parameters = requestDecoder.parameters(from: request)
        guard let actionName = actionName(from: parameters) else {
            return LocalHTTPResponse.jsonObject([
                "error": "Missing action",
                "acceptedKeys": [
                    "action",
                    "command",
                    "cmd",
                    "f",
                    "function",
                    "name"
                ],
                "supported": Self.supportedActions
            ], status: 400)
        }
        guard let action = LocalAPIExecutionAction(
            rawValue: actionName
        ) else {
            return LocalHTTPResponse.jsonObject([
                "error": "Unsupported action",
                "action": actionName,
                "supported": Self.supportedActions
            ], status: 400)
        }

        switch action {
        case .start:
            operations.startQueue()
            let state = operations.state()
            return LocalHTTPResponse.jsonObject([
                "ok": true,
                "action": action.rawValue,
                "running": state.isRunning,
                "count": state.count
            ])
        case .stop:
            operations.stopQueue()
            let state = operations.state()
            return LocalHTTPResponse.jsonObject([
                "ok": true,
                "action": action.rawValue,
                "running": state.isRunning,
                "count": state.count
            ])
        case .save:
            operations.persistQueueAndSettings()
            let state = operations.state()
            return LocalHTTPResponse.jsonObject([
                "ok": true,
                "action": action.rawValue,
                "res": "saved",
                "err": "",
                "saved": true,
                "count": state.count,
                "status": state.apiStatus
            ])
        case .clear:
            let removed = operations.clearFinished()
            let state = operations.state()
            return LocalHTTPResponse.jsonObject([
                "ok": true,
                "action": action.rawValue,
                "removed": removed,
                "removedCount": removed,
                "count": state.count,
                "running": state.isRunning
            ])
        case .download:
            guard let added = operations.enqueueInput(request) else {
                return LocalHTTPResponse.jsonObject(
                    ["error": "Missing url"],
                    status: 400
                )
            }
            let shouldStart = (
                parameters["start"] ??
                parameters["run"] ??
                "1"
            ) != "0"
            if shouldStart {
                operations.startQueue()
            }
            let state = operations.state()
            let message =
                "\(added) URL\(added == 1 ? "" : "s") added"
            return LocalHTTPResponse.jsonObject([
                "ok": added > 0,
                "action": action.rawValue,
                "res": operations.usesOriginalActionShape(request)
                    ? "ok"
                    : message,
                "message": message,
                "added": added,
                "total": state.count,
                "running": state.isRunning
            ])
        default:
            if let response = await operations.delegatedResponse(
                action,
                request
            ) {
                return response
            }
            return LocalHTTPResponse.jsonObject([
                "error": "Unsupported action",
                "action": action.rawValue,
                "supported": Self.supportedActions
            ], status: 400)
        }
    }

    static let supportedActions =
        LocalAPIExecutionAction.allCases.map(\.rawValue)

    func actionName(
        from parameters: [String: String]
    ) -> String? {
        let raw = [
            parameters["action"],
            parameters["command"],
            parameters["cmd"],
            parameters["f"],
            parameters["function"],
            parameters["name"]
        ]
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty } ?? ""
        guard !raw.isEmpty else { return nil }

        let normalized = raw
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: ".", with: "_")
        switch normalized {
        case "start", "run", "resume_queue", "start_queue":
            return LocalAPIExecutionAction.start.rawValue
        case "stop", "cancel", "abort", "stop_queue",
             "cancel_queue":
            return LocalAPIExecutionAction.stop.rawValue
        case "save", "persist":
            return LocalAPIExecutionAction.save.rawValue
        case "clear", "clear_finished", "clear_done",
             "clear_completed":
            return LocalAPIExecutionAction.clear.rawValue
        case "complete", "finish", "done", "mark_finished",
             "manual_complete":
            return LocalAPIExecutionAction.complete.rawValue
        case "pdf", "create_pdf", "createpdf", "pdf_converter",
             "pdfconverter", "convert_pdf", "convertpdf",
             "make_pdf", "makepdf", "to_pdf", "topdf":
            return LocalAPIExecutionAction.pdf.rawValue
        case "zip", "create_zip", "createzip", "make_zip",
             "makezip", "archive", "create_archive",
             "createarchive", "pack", "package", "cbz",
             "create_cbz", "createcbz":
            return LocalAPIExecutionAction.archive.rawValue
        case "comment", "memo", "note", "set_comment":
            return LocalAPIExecutionAction.comment.rawValue
        case "remove", "remove_task", "remove_tasks":
            return LocalAPIExecutionAction.remove.rawValue
        case "delete", "delete_task", "delete_tasks",
             "delete_output":
            return LocalAPIExecutionAction.delete.rawValue
        case "pause", "pause_task", "pause_tasks":
            return LocalAPIExecutionAction.pause.rawValue
        case "resume", "resume_task", "resume_tasks":
            return LocalAPIExecutionAction.resume.rawValue
        case "aria2_limits", "aria2_limit", "limits", "limit",
             "speed", "speed_limit", "set_speed", "set_limit":
            return LocalAPIExecutionAction.aria2Limits.rawValue
        case "aria2_files", "aria2_file", "aria2_select",
             "select_file", "select_files", "files",
             "file_priority", "priority", "set_files":
            return LocalAPIExecutionAction.aria2Files.rawValue
        case "aria2_seed", "aria2_seeding", "seed", "seeding",
             "set_seed", "set_seed_time", "set_seedings",
             "setseedings":
            return LocalAPIExecutionAction.aria2Seed.rawValue
        case "aria2_file_list", "aria2_files_list", "show_files",
             "showfiles", "list_files", "list_torrent_files",
             "torrent_files":
            return LocalAPIExecutionAction.aria2FileList.rawValue
        case "aria2_peers", "aria2_peer", "peers", "peer",
             "show_peers", "show_peer":
            return LocalAPIExecutionAction.aria2Peers.rawValue
        case "update_cookies", "cookies", "cookie", "set_cookies":
            return LocalAPIExecutionAction.updateCookies.rawValue
        case "download", "add", "add_url", "add_urls", "enqueue":
            return LocalAPIExecutionAction.download.rawValue
        default:
            return normalized
        }
    }
}
