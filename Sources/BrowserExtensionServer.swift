import CryptoKit
import Darwin
import Foundation

enum BrowserExtensionMessageResult: Sendable {
    case accepted
    case rejected

    var status: Int {
        switch self {
        case .accepted: return 200
        case .rejected: return 400
        }
    }

    var closeCode: UInt16 {
        switch self {
        case .accepted: return BrowserExtensionServer.successCloseCode
        case .rejected: return 1008
        }
    }
}

final class BrowserExtensionServer: @unchecked Sendable {
    static let defaultPort: UInt16 = 6974
    static let successCloseCode: UInt16 = 3001

    private static let maximumHeaderBytes = 32 * 1024
    private static let maximumMessageBytes = 16 * 1024 * 1024
    private static let websocketGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

    let requestedPort: UInt16
    private let handler: @Sendable (String) async -> BrowserExtensionMessageResult
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var clientFDs = Set<Int32>()
    private var running = false
    private var listeningPortStorage: UInt16?

    var listeningPort: UInt16? {
        lock.lock()
        defer { lock.unlock() }
        return listeningPortStorage
    }

    init(
        port: UInt16 = BrowserExtensionServer.defaultPort,
        handler: @escaping @Sendable (String) async -> BrowserExtensionMessageResult
    ) {
        requestedPort = port
        self.handler = handler
    }

    deinit {
        stop()
    }

    func start() throws {
        lock.lock()
        let alreadyRunning = running
        lock.unlock()
        guard !alreadyRunning else { return }

        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NativeDownloadError.unsupported("Browser extension socket could not be created.")
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = requestedPort.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0, listen(fd, SOMAXCONN) == 0 else {
            Darwin.close(fd)
            throw NativeDownloadError.unsupported("Browser extension port is unavailable.")
        }

        guard let boundPort = Self.boundPort(for: fd) else {
            Darwin.close(fd)
            throw NativeDownloadError.unsupported("Browser extension port could not be determined.")
        }

        lock.lock()
        socketFD = fd
        listeningPortStorage = boundPort
        running = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop(listener: fd)
        }
    }

    func stop() {
        lock.lock()
        let listener = socketFD
        let clients = Array(clientFDs)
        socketFD = -1
        listeningPortStorage = nil
        running = false
        lock.unlock()

        if listener >= 0 {
            shutdown(listener, SHUT_RDWR)
            Darwin.close(listener)
        }
        clients.forEach { shutdown($0, SHUT_RDWR) }
    }

    private func acceptLoop(listener: Int32) {
        while isRunning(listener: listener) {
            var address = sockaddr_storage()
            var length = socklen_t(MemoryLayout<sockaddr_storage>.size)
            let client = withUnsafeMutablePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.accept(listener, $0, &length)
                }
            }
            if client < 0 {
                if errno == EINTR { continue }
                break
            }

            configure(client: client)
            guard register(client: client, listener: listener) else {
                Darwin.close(client)
                continue
            }

            Task.detached(priority: .utility) { [weak self] in
                guard let self else {
                    Darwin.close(client)
                    return
                }
                await self.handle(client: client)
            }
        }

        lock.lock()
        let shouldClose = socketFD == listener
        if shouldClose {
            socketFD = -1
            listeningPortStorage = nil
            running = false
        }
        lock.unlock()
        if shouldClose {
            Darwin.close(listener)
        }
    }

    private func handle(client: Int32) async {
        defer {
            finish(client: client)
        }

        guard performHandshake(client: client) else { return }

        switch readTextMessage(from: client) {
        case .text(let message):
            let result = await handler(message)
            _ = sendText("{\"status\":\(result.status)}", to: client)
            _ = sendClose(code: result.closeCode, to: client)
        case .closed:
            return
        case .invalid:
            _ = sendClose(code: 1002, to: client)
        }
    }

    private func performHandshake(client: Int32) -> Bool {
        guard let header = readHeader(from: client),
              let requestLine = header.lines.first,
              requestLine.hasPrefix("GET "),
              requestLine.hasSuffix(" HTTP/1.1"),
              header.headers["upgrade"]?.lowercased() == "websocket",
              Self.containsToken("upgrade", in: header.headers["connection"]),
              header.headers["sec-websocket-version"]?.trimmed == "13",
              let key = header.headers["sec-websocket-key"]?.trimmed,
              Data(base64Encoded: key)?.count == 16 else {
            return false
        }

        let source = Data((key + Self.websocketGUID).utf8)
        let accept = Data(Insecure.SHA1.hash(data: source)).base64EncodedString()
        let response = "HTTP/1.1 101 Switching Protocols\r\n" +
            "Upgrade: websocket\r\n" +
            "Connection: Upgrade\r\n" +
            "Sec-WebSocket-Accept: \(accept)\r\n" +
            "\r\n"
        return sendAll(Data(response.utf8), to: client)
    }

    private func readHeader(from client: Int32) -> (lines: [String], headers: [String: String])? {
        let marker = Data("\r\n\r\n".utf8)
        var data = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while data.count <= Self.maximumHeaderBytes {
            let count = recv(client, &chunk, chunk.count, 0)
            guard count > 0 else { return nil }
            data.append(contentsOf: chunk.prefix(count))
            guard let range = data.range(of: marker) else { continue }
            guard range.upperBound == data.endIndex,
                  let text = String(data: data[..<range.lowerBound], encoding: .utf8) else {
                return nil
            }

            let lines = text.components(separatedBy: "\r\n")
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                guard let separator = line.firstIndex(of: ":") else { return nil }
                let name = String(line[..<separator]).trimmed.lowercased()
                let value = String(line[line.index(after: separator)...]).trimmed
                guard !name.isEmpty else { return nil }
                headers[name] = value
            }
            return (lines, headers)
        }
        return nil
    }

    private enum MessageReadResult {
        case text(String)
        case closed
        case invalid
    }

    private struct Frame {
        let final: Bool
        let opcode: UInt8
        let payload: Data
    }

    private func readTextMessage(from client: Int32) -> MessageReadResult {
        var fragmented = Data()
        var isReadingTextFragments = false

        while true {
            guard let frame = readFrame(from: client) else { return .invalid }
            switch frame.opcode {
            case 0x0:
                guard isReadingTextFragments else { return .invalid }
                fragmented.append(frame.payload)
                guard fragmented.count <= Self.maximumMessageBytes else { return .invalid }
                if frame.final {
                    guard let text = String(data: fragmented, encoding: .utf8) else { return .invalid }
                    return .text(text)
                }
            case 0x1:
                guard !isReadingTextFragments else { return .invalid }
                if frame.final {
                    guard let text = String(data: frame.payload, encoding: .utf8) else { return .invalid }
                    return .text(text)
                }
                fragmented = frame.payload
                isReadingTextFragments = true
            case 0x8:
                if frame.payload.count == 1 { return .invalid }
                _ = sendFrame(opcode: 0x8, payload: frame.payload, to: client)
                return .closed
            case 0x9:
                guard frame.final, frame.payload.count <= 125 else { return .invalid }
                guard sendFrame(opcode: 0xA, payload: frame.payload, to: client) else { return .closed }
            case 0xA:
                guard frame.final, frame.payload.count <= 125 else { return .invalid }
            default:
                return .invalid
            }
        }
    }

    private func readFrame(from client: Int32) -> Frame? {
        guard let prefix = readExactly(2, from: client) else { return nil }
        let first = prefix[prefix.startIndex]
        let second = prefix[prefix.index(after: prefix.startIndex)]
        guard first & 0x70 == 0, second & 0x80 != 0 else { return nil }

        let final = first & 0x80 != 0
        let opcode = first & 0x0F
        let isControl = opcode >= 0x8
        var length = UInt64(second & 0x7F)
        if length == 126 {
            guard let extended = readExactly(2, from: client) else { return nil }
            length = extended.reduce(0) { ($0 << 8) | UInt64($1) }
        } else if length == 127 {
            guard let extended = readExactly(8, from: client),
                  (extended.first ?? 0) & 0x80 == 0 else { return nil }
            length = extended.reduce(0) { ($0 << 8) | UInt64($1) }
        }

        guard length <= UInt64(Self.maximumMessageBytes),
              !isControl || (final && length <= 125),
              let mask = readExactly(4, from: client),
              let encoded = readExactly(Int(length), from: client) else {
            return nil
        }

        let maskBytes = Array(mask)
        var payload = Array(encoded)
        for index in payload.indices {
            payload[index] ^= maskBytes[index % 4]
        }
        return Frame(final: final, opcode: opcode, payload: Data(payload))
    }

    private func sendText(_ text: String, to client: Int32) -> Bool {
        sendFrame(opcode: 0x1, payload: Data(text.utf8), to: client)
    }

    private func sendClose(code: UInt16, to client: Int32) -> Bool {
        let payload = Data([UInt8(code >> 8), UInt8(code & 0xFF)])
        return sendFrame(opcode: 0x8, payload: payload, to: client)
    }

    private func sendFrame(opcode: UInt8, payload: Data, to client: Int32) -> Bool {
        var frame = Data([0x80 | opcode])
        switch payload.count {
        case 0...125:
            frame.append(UInt8(payload.count))
        case 126...65_535:
            frame.append(126)
            frame.append(UInt8((payload.count >> 8) & 0xFF))
            frame.append(UInt8(payload.count & 0xFF))
        default:
            frame.append(127)
            let length = UInt64(payload.count)
            for shift in stride(from: 56, through: 0, by: -8) {
                frame.append(UInt8((length >> UInt64(shift)) & 0xFF))
            }
        }
        frame.append(payload)
        return sendAll(frame, to: client)
    }

    private func readExactly(_ count: Int, from client: Int32) -> Data? {
        guard count >= 0 else { return nil }
        if count == 0 { return Data() }

        var data = Data(count: count)
        let success = data.withUnsafeMutableBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return false }
            var received = 0
            while received < count {
                let result = recv(client, base.advanced(by: received), count - received, 0)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                received += result
            }
            return true
        }
        return success ? data : nil
    }

    private func sendAll(_ data: Data, to client: Int32) -> Bool {
        data.withUnsafeBytes { rawBuffer -> Bool in
            guard let base = rawBuffer.baseAddress else { return data.isEmpty }
            var sent = 0
            while sent < data.count {
                let result = Darwin.send(client, base.advanced(by: sent), data.count - sent, 0)
                if result < 0, errno == EINTR { continue }
                guard result > 0 else { return false }
                sent += result
            }
            return true
        }
    }

    private func isRunning(listener: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return running && socketFD == listener
    }

    private func register(client: Int32, listener: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard running, socketFD == listener else { return false }
        clientFDs.insert(client)
        return true
    }

    private func finish(client: Int32) {
        lock.lock()
        clientFDs.remove(client)
        lock.unlock()
        Darwin.close(client)
    }

    private func configure(client: Int32) {
        var yes: Int32 = 1
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, socklen_t(MemoryLayout<Int32>.size))
        _ = fcntl(client, F_SETFD, FD_CLOEXEC)
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(client, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
    }

    private static func boundPort(for fd: Int32) -> UInt16? {
        var address = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let result = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard result == 0 else { return nil }
        return UInt16(bigEndian: address.sin_port)
    }

    private static func containsToken(_ token: String, in value: String?) -> Bool {
        value?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
            .contains(token.lowercased()) == true
    }
}
