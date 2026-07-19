import Foundation

struct NiconicoLiveCookie: Equatable, Sendable {
    let name: String
    let value: String
    let domain: String
    let path: String
    let secure: Bool
    let expires: String
}

struct NiconicoLiveStreamHandshake: Equatable, Sendable {
    let masterPlaylistURL: URL
    let availableQualities: [String]
    let cookies: [NiconicoLiveCookie]

    var cookieHeader: String {
        cookies.compactMap { cookie in
            let name = cookie.name.trimmed
            let value = cookie.value.trimmed
            guard !name.isEmpty,
                  name.range(of: #"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$"#, options: .regularExpression) != nil,
                  !value.contains("\r"),
                  !value.contains("\n"),
                  !value.contains(";") else {
                return nil
            }
            return "\(name)=\(value)"
        }.joined(separator: "; ")
    }
}

protocol NiconicoLiveWebSocket: AnyObject, Sendable {
    func send(text: String) async throws
    func receiveText() async throws -> String
    func close() async
}

typealias NiconicoLiveWebSocketFactory = @Sendable (URLRequest) -> any NiconicoLiveWebSocket

final class URLSessionNiconicoLiveWebSocket: NiconicoLiveWebSocket, @unchecked Sendable {
    private let session: URLSession
    private let task: URLSessionWebSocketTask

    init(request: URLRequest) {
        let configuration = URLSessionConfiguration.ephemeral
        NetworkSessionPrivacy.disableSystemCredentialPersistence(in: configuration)
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 0
        session = URLSession(configuration: configuration)
        task = session.webSocketTask(with: request)
        task.resume()
    }

    func send(text: String) async throws {
        try await task.send(.string(text))
    }

    func receiveText() async throws -> String {
        switch try await task.receive() {
        case .string(let text):
            return text
        case .data(let data):
            return String(decoding: data, as: UTF8.self)
        @unknown default:
            throw NativeDownloadError.unsupported("Niconico Live returned an unknown WebSocket message.")
        }
    }

    func close() async {
        task.cancel(with: .normalClosure, reason: nil)
        session.invalidateAndCancel()
    }
}

actor NiconicoLiveSeatSession {
    private enum CommunicationResult {
        case disconnected
    }

    private let webSocketURL: URL
    private let origin: String
    private let userAgent: String?
    private let cookieHeader: String?
    private let maximumQuality: String
    private let socketFactory: NiconicoLiveWebSocketFactory
    private let reconnectDelayNanoseconds: UInt64
    private var activeSocket: (any NiconicoLiveWebSocket)?
    private var keepAliveTask: Task<Void, Never>?
    private var stopped = false

    init(
        webSocketURL: URL,
        origin: String = "https://live.nicovideo.jp",
        userAgent: String?,
        cookieHeader: String?,
        maximumQuality: String,
        socketFactory: @escaping NiconicoLiveWebSocketFactory = { URLSessionNiconicoLiveWebSocket(request: $0) },
        reconnectDelayNanoseconds: UInt64 = 10_000_000_000
    ) {
        self.webSocketURL = webSocketURL
        self.origin = origin
        self.userAgent = userAgent
        self.cookieHeader = cookieHeader
        self.maximumQuality = maximumQuality.trimmed.isEmpty ? "normal" : maximumQuality.trimmed
        self.socketFactory = socketFactory
        self.reconnectDelayNanoseconds = reconnectDelayNanoseconds
    }

    func start() async throws -> NiconicoLiveStreamHandshake {
        guard !stopped, keepAliveTask == nil else {
            throw NativeDownloadError.unsupported("Niconico Live seat session is not available.")
        }

        let socket = socketFactory(Self.webSocketRequest(
            url: webSocketURL,
            origin: origin,
            userAgent: userAgent,
            cookieHeader: cookieHeader
        ))
        activeSocket = socket

        do {
            try await socket.send(text: try Self.startWatchingPayload(reconnect: false, quality: "abr"))
            let handshake = try await receiveHandshake(from: socket)
            keepAliveTask = Task { [weak self] in
                await self?.maintainSeat(startingWith: socket)
            }
            return handshake
        } catch {
            activeSocket = nil
            await socket.close()
            throw error
        }
    }

    func stop() async {
        guard !stopped else { return }
        stopped = true
        let task = keepAliveTask
        keepAliveTask = nil
        task?.cancel()
        let socket = activeSocket
        activeSocket = nil
        await socket?.close()
        _ = await task?.result
    }

    private func receiveHandshake(from socket: any NiconicoLiveWebSocket) async throws -> NiconicoLiveStreamHandshake {
        while !stopped {
            try Task.checkCancellation()
            let text = try await socket.receiveText()
            guard let message = Self.messageObject(from: text),
                  let type = message["type"] as? String else {
                continue
            }

            switch type {
            case "stream":
                return try Self.streamHandshake(from: message)
            case "ping":
                try await respondToPing(on: socket)
            case "disconnect":
                throw NativeDownloadError.unsupported("Niconico Live disconnected before playback started.")
            case "error":
                throw NativeDownloadError.unsupported(Self.serverErrorDescription(from: message))
            default:
                continue
            }
        }
        throw CancellationError()
    }

    private func maintainSeat(startingWith initialSocket: any NiconicoLiveWebSocket) async {
        var socket = initialSocket
        var reconnect = false

        while !stopped, !Task.isCancelled {
            do {
                if reconnect {
                    socket = socketFactory(Self.webSocketRequest(
                        url: webSocketURL,
                        origin: origin,
                        userAgent: userAgent,
                        cookieHeader: cookieHeader
                    ))
                    activeSocket = socket
                    try await socket.send(text: try Self.startWatchingPayload(
                        reconnect: true,
                        quality: maximumQuality
                    ))
                }

                let result = try await communicate(with: socket)
                if result == .disconnected {
                    break
                }
            } catch {
                await socket.close()
                if stopped || Task.isCancelled {
                    break
                }
                do {
                    try await Task.sleep(nanoseconds: reconnectDelayNanoseconds)
                } catch {
                    break
                }
                reconnect = true
                continue
            }
            reconnect = true
        }

        await socket.close()
        activeSocket = nil
    }

    private func communicate(with socket: any NiconicoLiveWebSocket) async throws -> CommunicationResult {
        while !stopped, !Task.isCancelled {
            let text = try await socket.receiveText()
            guard let message = Self.messageObject(from: text),
                  let type = message["type"] as? String else {
                continue
            }

            switch type {
            case "ping":
                try await respondToPing(on: socket)
            case "disconnect":
                return .disconnected
            case "error":
                throw NativeDownloadError.unsupported(Self.serverErrorDescription(from: message))
            default:
                continue
            }
        }
        throw CancellationError()
    }

    private func respondToPing(on socket: any NiconicoLiveWebSocket) async throws {
        try await socket.send(text: #"{"type":"pong"}"#)
        try await socket.send(text: #"{"type":"keepSeat"}"#)
    }

    static func webSocketRequest(
        url: URL,
        origin: String,
        userAgent: String?,
        cookieHeader: String?
    ) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(origin, forHTTPHeaderField: "Origin")
        if let userAgent = userAgent?.trimmed, !userAgent.isEmpty {
            request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        }
        if let cookieHeader = cookieHeader?.trimmed, !cookieHeader.isEmpty {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    static func startWatchingPayload(reconnect: Bool, quality: String) throws -> String {
        let object: [String: Any] = [
            "data": [
                "reconnect": reconnect,
                "room": [
                    "commentable": true,
                    "protocol": "webSocket"
                ],
                "stream": [
                    "accessRightMethod": "single_cookie",
                    "chasePlay": false,
                    "latency": "high",
                    "protocol": "hls",
                    "quality": quality.trimmed.isEmpty ? "normal" : quality.trimmed
                ]
            ],
            "type": "startWatching"
        ]
        return String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }

    private static func messageObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func streamHandshake(from message: [String: Any]) throws -> NiconicoLiveStreamHandshake {
        guard let data = message["data"] as? [String: Any],
              let rawURI = data["uri"] as? String,
              let masterURL = URL(string: rawURI),
              let scheme = masterURL.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            throw NativeDownloadError.unsupported("Niconico Live did not return an HLS playlist.")
        }

        let qualities = (data["availableQualities"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .map(\.trimmed)
            .filter { !$0.isEmpty }
        let cookies = (data["cookies"] as? [[String: Any]] ?? []).compactMap { item -> NiconicoLiveCookie? in
            guard let name = item["name"] as? String,
                  let value = item["value"] as? String else {
                return nil
            }
            return NiconicoLiveCookie(
                name: name,
                value: value,
                domain: item["domain"] as? String ?? "",
                path: item["path"] as? String ?? "/",
                secure: item["secure"] as? Bool ?? true,
                expires: item["expires"] as? String ?? ""
            )
        }
        return NiconicoLiveStreamHandshake(
            masterPlaylistURL: masterURL,
            availableQualities: qualities,
            cookies: cookies
        )
    }

    private static func serverErrorDescription(from message: [String: Any]) -> String {
        if let body = message["body"] as? [String: Any],
           let code = body["code"] as? String,
           !code.trimmed.isEmpty {
            return "Niconico Live error: \(code.trimmed)"
        }
        if let data = message["data"] as? [String: Any],
           let code = data["code"] as? String,
           !code.trimmed.isEmpty {
            return "Niconico Live error: \(code.trimmed)"
        }
        return "Niconico Live returned a playback error."
    }
}

actor NiconicoLiveSessionRegistry {
    static let shared = NiconicoLiveSessionRegistry()

    private var sessions: [String: NiconicoLiveSeatSession] = [:]

    func register(_ session: NiconicoLiveSeatSession) -> String {
        let token = UUID().uuidString
        sessions[token] = session
        return token
    }

    func stop(_ token: String) async {
        guard let session = sessions.removeValue(forKey: token) else { return }
        await session.stop()
    }

    func stopAll() async {
        let active = Array(sessions.values)
        sessions.removeAll()
        for session in active {
            await session.stop()
        }
    }

    func activeSessionCount() -> Int {
        sessions.count
    }
}
