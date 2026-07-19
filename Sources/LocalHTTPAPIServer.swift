import Darwin
import Foundation

struct LocalHTTPRequest {
    var method: String
    var path: String
    var query: [String: String]
    var headers: [String: String]
    var body: Data

    var bodyText: String {
        String(data: body, encoding: .utf8) ?? ""
    }
}

struct LocalHTTPResponse {
    var status: Int
    var contentType: String
    var body: Data
    var headers: [String: String] = [:]

    static func text(_ text: String, status: Int = 200, contentType: String = "text/plain; charset=utf-8") -> LocalHTTPResponse {
        LocalHTTPResponse(status: status, contentType: contentType, body: Data(text.utf8))
    }

    static func html(_ text: String, status: Int = 200) -> LocalHTTPResponse {
        LocalHTTPResponse(status: status, contentType: "text/html; charset=utf-8", body: Data(text.utf8))
    }

    static func data(_ data: Data, contentType: String, status: Int = 200, headers: [String: String] = [:]) -> LocalHTTPResponse {
        LocalHTTPResponse(status: status, contentType: contentType, body: data, headers: headers)
    }

    static func jsonObject(_ object: Any, status: Int = 200) -> LocalHTTPResponse {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
        return LocalHTTPResponse(status: status, contentType: "application/json; charset=utf-8", body: data)
    }
}

final class LocalHTTPAPIServer: @unchecked Sendable {
    let port: UInt16
    private let handler: (LocalHTTPRequest) async -> LocalHTTPResponse
    private let lock = NSLock()
    private var socketFD: Int32 = -1
    private var isRunning = false

    init(port: UInt16, handler: @escaping (LocalHTTPRequest) async -> LocalHTTPResponse) {
        self.port = port
        self.handler = handler
    }

    func start() throws {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NativeDownloadError.unsupported("HTTP API socket could not be created.")
        }

        var yes: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0, listen(fd, SOMAXCONN) == 0 else {
            Darwin.close(fd)
            throw NativeDownloadError.unsupported("HTTP API port is unavailable.")
        }

        lock.lock()
        socketFD = fd
        isRunning = true
        lock.unlock()

        DispatchQueue.global(qos: .utility).async { [weak self] in
            self?.acceptLoop(fd: fd)
        }
    }

    func stop() {
        lock.lock()
        let fd = socketFD
        socketFD = -1
        isRunning = false
        lock.unlock()

        if fd >= 0 {
            shutdown(fd, SHUT_RDWR)
            Darwin.close(fd)
        }
    }

    private func acceptLoop(fd: Int32) {
        while running(fd: fd) {
            var clientAddress = sockaddr()
            var length = socklen_t(MemoryLayout<sockaddr>.size)
            let client = Darwin.accept(fd, &clientAddress, &length)
            if client < 0 {
                if errno == EINTR { continue }
                break
            }

            Task.detached(priority: .utility) { [weak self] in
                await self?.handle(client: client)
            }
        }
    }

    private func running(fd: Int32) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return isRunning && socketFD == fd
    }

    private func handle(client: Int32) async {
        defer {
            Darwin.close(client)
        }

        guard let request = readRequest(from: client) else {
            send(LocalHTTPResponse.jsonObject(["error": "Bad request"], status: 400), to: client, request: nil)
            return
        }

        let response = await handler(request)
        send(response, to: client, request: request)
    }

    private func readRequest(from client: Int32) -> LocalHTTPRequest? {
        var buffer = Data()
        var chunk = [UInt8](repeating: 0, count: 4096)

        while buffer.count < 1024 * 1024 {
            let count = recv(client, &chunk, chunk.count, 0)
            if count <= 0 { return nil }
            buffer.append(contentsOf: chunk.prefix(count))
            if let request = Self.parseRequest(buffer) {
                return request
            }
        }

        return nil
    }

    private func send(_ response: LocalHTTPResponse, to client: Int32, request: LocalHTTPRequest?) {
        let isSwitchingProtocols = response.status == 101
        let corsOrigin = Self.corsOrigin(for: request, port: port)
        let requestedHeaders = request?.headers["access-control-request-headers"]?.trimmed
        let allowHeaders = requestedHeaders?.isEmpty == false
            ? requestedHeaders!
            : "Authorization, Content-Type, X-Hitomi-Password, Range, If-None-Match, If-Modified-Since"
        var headers = isSwitchingProtocols
            ? [
                "Connection": "Upgrade",
                "Access-Control-Allow-Origin": corsOrigin
            ]
            : [
                "Content-Type": response.contentType,
                "Content-Length": String(response.body.count),
                "Connection": "close",
                "Access-Control-Allow-Origin": corsOrigin,
                "Access-Control-Allow-Methods": "GET, POST, HEAD, OPTIONS",
                "Access-Control-Allow-Headers": allowHeaders,
                "Access-Control-Expose-Headers": "Accept-Ranges, Content-Disposition, Content-Length, Content-Range, ETag, Last-Modified",
                "Access-Control-Max-Age": "86400",
                "Vary": "Origin, Access-Control-Request-Method, Access-Control-Request-Headers"
            ]
        response.headers.forEach { headers[$0.key] = $0.value }

        var text = "HTTP/1.1 \(response.status) \(reasonPhrase(for: response.status))\r\n"
        for key in headers.keys.sorted() {
            text += "\(key): \(headers[key] ?? "")\r\n"
        }
        text += "\r\n"

        var data = Data(text.utf8)
        data.append(response.body)
        data.withUnsafeBytes { rawBuffer in
            guard let base = rawBuffer.baseAddress else { return }
            var sent = 0
            while sent < data.count {
                let written = Darwin.send(client, base.advanced(by: sent), data.count - sent, 0)
                if written <= 0 { break }
                sent += written
            }
        }
    }

    private static func corsOrigin(for request: LocalHTTPRequest?, port: UInt16) -> String {
        guard let origin = request?.headers["origin"]?.trimmed, !origin.isEmpty else {
            return "http://127.0.0.1:\(port)"
        }
        if origin == "null" {
            return "null"
        }
        guard let components = URLComponents(string: origin),
              let scheme = components.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = components.host?.lowercased() else {
            return "http://127.0.0.1:\(port)"
        }
        if host == "localhost" || host == "127.0.0.1" || host == "::1" {
            return origin
        }
        return "http://127.0.0.1:\(port)"
    }

    private static func parseRequest(_ data: Data) -> LocalHTTPRequest? {
        guard let marker = data.firstRange(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<marker.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<separator]).lowercased()
            let value = String(line[line.index(after: separator)...]).trimmed
            headers[key] = value
        }

        let contentLength = Int(headers["content-length"] ?? "0") ?? 0
        let bodyStart = marker.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data.subdata(in: bodyStart..<(bodyStart + contentLength))

        let target = requestParts[1]
        let components = URLComponents(string: target)
        let path = components?.path ?? target.components(separatedBy: "?").first ?? target
        let queryItems: [URLQueryItem] = components?.queryItems ?? []
        var query: [String: String] = [:]
        for item in queryItems {
            mergeParameter(name: item.name, value: item.value ?? "", into: &query)
        }

        return LocalHTTPRequest(
            method: requestParts[0].uppercased(),
            path: path,
            query: query,
            headers: headers,
            body: body
        )
    }

    private static func mergeParameter(name: String, value: String, into parameters: inout [String: String]) {
        guard !name.isEmpty else { return }
        if let existing = parameters[name], !existing.isEmpty {
            parameters[name] = existing + "\n" + value
        } else {
            parameters[name] = value
        }
    }

    private func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 101: return "Switching Protocols"
        case 201: return "Created"
        case 202: return "Accepted"
        case 302: return "Found"
        case 304: return "Not Modified"
        case 204: return "No Content"
        case 206: return "Partial Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 403: return "Forbidden"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Content Too Large"
        case 416: return "Range Not Satisfiable"
        case 422: return "Unprocessable Content"
        case 502: return "Bad Gateway"
        case 503: return "Service Unavailable"
        case 504: return "Gateway Timeout"
        default: return "OK"
        }
    }
}
