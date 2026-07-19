import Darwin
import Foundation

struct Aria2FileEntry: Equatable {
    var index: Int
    var path: String
    var length: String
    var selected: Bool?
}

struct Aria2PeerEntry: Equatable, Identifiable {
    var peerID: String
    var ip: String
    var port: String
    var downloadSpeed: String
    var uploadSpeed: String
    var seeder: String
    var amChoking: String
    var peerChoking: String

    var id: String {
        [ip, port, peerID].filter { !$0.isEmpty }.joined(separator: ":")
    }

    var endpoint: String {
        port.isEmpty ? ip : "\(ip):\(port)"
    }

    var summary: String {
        var parts = [endpoint]
        if !downloadSpeed.isEmpty {
            parts.append("down \(downloadSpeed)")
        }
        if !uploadSpeed.isEmpty {
            parts.append("up \(uploadSpeed)")
        }
        if seeder == "true" {
            parts.append("seeder")
        }
        return parts.joined(separator: " ")
    }
}

struct TorrentPieceInfo: Equatable {
    let pieceLength: Int64
    let pieceCount: Int
    let totalLength: Int64
}

struct Aria2Result {
    let outputDirectory: URL
    let downloadedItems: [URL]
    let torrentPieceInfo: TorrentPieceInfo?

    init(outputDirectory: URL, downloadedItems: [URL], torrentPieceInfo: TorrentPieceInfo? = nil) {
        self.outputDirectory = outputDirectory
        self.downloadedItems = downloadedItems
        self.torrentPieceInfo = torrentPieceInfo
    }
}

private enum TorrentBencodeValue {
    case integer(Int64)
    case byteString(Data)
    case list([TorrentBencodeValue])
    case dictionary([String: TorrentBencodeValue])
}

private struct TorrentBencodeParser {
    private let bytes: [UInt8]
    private var index = 0

    init(_ data: Data) {
        bytes = Array(data)
    }

    mutating func parseRoot() throws -> TorrentBencodeValue {
        let value = try parseValue()
        guard index == bytes.count else { throw NativeDownloadError.unsupported("Invalid torrent bencode payload.") }
        return value
    }

    private mutating func parseValue() throws -> TorrentBencodeValue {
        guard index < bytes.count else { throw NativeDownloadError.unsupported("Unexpected end of torrent bencode payload.") }
        let byte = bytes[index]
        if byte == 105 {
            return try parseInteger()
        }
        if byte == 108 {
            return try parseList()
        }
        if byte == 100 {
            return try parseDictionary()
        }
        if byte >= 48 && byte <= 57 {
            return try parseByteString()
        }
        throw NativeDownloadError.unsupported("Unsupported torrent bencode token.")
    }

    private mutating func parseInteger() throws -> TorrentBencodeValue {
        index += 1
        let start = index
        while index < bytes.count, bytes[index] != 101 {
            index += 1
        }
        guard index < bytes.count,
              let text = String(bytes: bytes[start..<index], encoding: .utf8),
              let value = Int64(text) else {
            throw NativeDownloadError.unsupported("Invalid torrent integer.")
        }
        index += 1
        return .integer(value)
    }

    private mutating func parseByteString() throws -> TorrentBencodeValue {
        let start = index
        while index < bytes.count, bytes[index] >= 48, bytes[index] <= 57 {
            index += 1
        }
        guard index < bytes.count,
              bytes[index] == 58,
              let text = String(bytes: bytes[start..<index], encoding: .utf8),
              let length = Int(text),
              length <= bytes.count - index - 1 else {
            throw NativeDownloadError.unsupported("Invalid torrent byte string.")
        }
        index += 1
        let end = index + length
        let value = Data(bytes[index..<end])
        index = end
        return .byteString(value)
    }

    private mutating func parseList() throws -> TorrentBencodeValue {
        index += 1
        var values: [TorrentBencodeValue] = []
        while index < bytes.count, bytes[index] != 101 {
            values.append(try parseValue())
        }
        guard index < bytes.count else { throw NativeDownloadError.unsupported("Unterminated torrent list.") }
        index += 1
        return .list(values)
    }

    private mutating func parseDictionary() throws -> TorrentBencodeValue {
        index += 1
        var values: [String: TorrentBencodeValue] = [:]
        while index < bytes.count, bytes[index] != 101 {
            guard case let .byteString(keyData) = try parseByteString(),
                  let key = String(data: keyData, encoding: .utf8) else {
                throw NativeDownloadError.unsupported("Invalid torrent dictionary key.")
            }
            values[key] = try parseValue()
        }
        guard index < bytes.count else { throw NativeDownloadError.unsupported("Unterminated torrent dictionary.") }
        index += 1
        return .dictionary(values)
    }
}

struct Aria2Options: Equatable {
    var selectedFiles: String
    var seedTimeMinutes: String
    var seedRatio: String
    var maxDownloadLimit: String
    var maxUploadLimit: String
    var trackerURLs: String
    var anonymousMode: Bool

    static let defaults = Aria2Options(
        selectedFiles: "",
        seedTimeMinutes: "0",
        seedRatio: "",
        maxDownloadLimit: "",
        maxUploadLimit: "",
        trackerURLs: "",
        anonymousMode: false
    )

    init(selectedFiles: String, seedTimeMinutes: String, seedRatio: String, maxDownloadLimit: String, maxUploadLimit: String, trackerURLs: String, anonymousMode: Bool) {
        self.selectedFiles = Self.normalizedFileSelection(selectedFiles)
        self.seedTimeMinutes = Self.normalizedInteger(seedTimeMinutes, defaultValue: "0")
        self.seedRatio = Self.normalizedDecimal(seedRatio)
        self.maxDownloadLimit = Self.normalizedLimit(maxDownloadLimit)
        self.maxUploadLimit = Self.normalizedLimit(maxUploadLimit)
        self.trackerURLs = Self.normalizedTrackers(trackerURLs)
        self.anonymousMode = anonymousMode
    }

    var arguments: [String] {
        var values = ["--seed-time=\(seedTimeMinutes)"]
        if !selectedFiles.isEmpty {
            values.append("--select-file=\(selectedFiles)")
        }
        if !seedRatio.isEmpty {
            values.append("--seed-ratio=\(seedRatio)")
        }
        if !maxDownloadLimit.isEmpty {
            values.append("--max-download-limit=\(maxDownloadLimit)")
        }
        if !maxUploadLimit.isEmpty {
            values.append("--max-upload-limit=\(maxUploadLimit)")
        }
        if !trackerURLs.isEmpty {
            values.append("--bt-tracker=\(trackerURLs)")
        }
        if anonymousMode {
            values.append(contentsOf: [
                "--enable-dht=false",
                "--enable-dht6=false",
                "--enable-peer-exchange=false",
                "--bt-enable-lpd=false",
                "--bt-require-crypto=true",
                "--bt-min-crypto-level=arc4"
            ])
        }
        return values
    }

    static func normalizedFileSelection(_ raw: String) -> String {
        let compact = raw.filter { !$0.isWhitespace }
        guard !compact.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "0123456789,-")
        guard compact.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return "" }

        var parts: [String] = []
        for part in compact.split(separator: ",", omittingEmptySubsequences: true) {
            let text = String(part)
            if text.contains("-") {
                let bounds = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
                guard bounds.count == 2,
                      bounds.allSatisfy({ !$0.isEmpty && Int($0) != nil }) else {
                    return ""
                }
            } else if Int(text) == nil {
                return ""
            }
            parts.append(text)
        }
        return parts.joined(separator: ",")
    }

    private static func normalizedInteger(_ raw: String, defaultValue: String) -> String {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return defaultValue }
        guard let value = Int(trimmed), value >= 0 else { return defaultValue }
        return String(value)
    }

    private static func normalizedDecimal(_ raw: String) -> String {
        let trimmed = raw.trimmed
        guard !trimmed.isEmpty else { return "" }
        let allowed = CharacterSet(charactersIn: "0123456789.")
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              trimmed.filter({ $0 == "." }).count <= 1,
              let value = Double(trimmed),
              value >= 0,
              value.isFinite else {
            return ""
        }
        return trimmed
    }

    static func normalizedLimit(_ raw: String) -> String {
        let trimmed = raw.trimmed.uppercased()
        guard !trimmed.isEmpty else { return "" }
        let suffix = trimmed.last.map(String.init) ?? ""
        let hasUnit = ["K", "M", "G"].contains(suffix)
        let numeric = hasUnit ? String(trimmed.dropLast()) : trimmed
        guard let value = Int(numeric), value >= 0 else { return "" }
        return "\(value)\(hasUnit ? suffix : "")"
    }

    private static func normalizedTrackers(_ raw: String) -> String {
        let separators = CharacterSet(charactersIn: ",;\n\r\t ")
        var values: [String] = []
        var seen = Set<String>()
        for part in raw.components(separatedBy: separators) {
            let value = part.trimmed
            guard !value.isEmpty,
                  let url = URL(string: value),
                  let scheme = url.scheme?.lowercased(),
                  ["http", "https", "udp", "ws", "wss"].contains(scheme),
                  url.host?.isEmpty == false else {
                continue
            }
            let key = value.lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            values.append(value)
        }
        return values.joined(separator: ",")
    }
}

struct Aria2RPCSession: Equatable {
    let port: UInt16
    let secret: String

    var endpoint: URL {
        URL(string: "http://127.0.0.1:\(port)/jsonrpc")!
    }

    static func make(environment: [String: String] = ProcessInfo.processInfo.environment) -> Aria2RPCSession? {
        let configuredSecret = environment["HITOMI_NATIVE_ARIA2_RPC_SECRET"]?.trimmed
        let secret = configuredSecret?.isEmpty == false ? configuredSecret! : UUID().uuidString.replacingOccurrences(of: "-", with: "")
        if let override = environment["HITOMI_NATIVE_ARIA2_RPC_PORT"]?.trimmed,
           let port = UInt16(override),
           port > 0 {
            return Aria2RPCSession(port: port, secret: secret)
        }
        guard let port = availableLoopbackPort() else { return nil }
        return Aria2RPCSession(port: port, secret: secret)
    }

    private static func availableLoopbackPort() -> UInt16? {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        defer { Darwin.close(fd) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else { return nil }

        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &bound) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard nameResult == 0 else { return nil }
        return UInt16(bigEndian: bound.sin_port)
    }
}

enum Aria2RPCClient {
    static func changeSpeedLimits(session: Aria2RPCSession, downloadLimit: String, uploadLimit: String) async throws -> [String: String] {
        let normalizedDownload = Aria2Options.normalizedLimit(downloadLimit)
        let normalizedUpload = Aria2Options.normalizedLimit(uploadLimit)
        let perDownloadOptions = [
            "max-download-limit": normalizedDownload.isEmpty ? "0" : normalizedDownload,
            "max-upload-limit": normalizedUpload.isEmpty ? "0" : normalizedUpload
        ]
        let globalOptions = [
            "max-overall-download-limit": normalizedDownload.isEmpty ? "0" : normalizedDownload,
            "max-overall-upload-limit": normalizedUpload.isEmpty ? "0" : normalizedUpload
        ]

        _ = try await request(session: session, method: "aria2.changeGlobalOption", params: [token(session), globalOptions])
        let gids = (try? await activeGIDs(session: session)) ?? []
        for gid in gids.prefix(1) {
            _ = try await request(session: session, method: "aria2.changeOption", params: [token(session), gid, perDownloadOptions])
        }

        return [
            "max_download_limit": normalizedDownload,
            "max_upload_limit": normalizedUpload
        ]
    }

    static func changeFileSelection(session: Aria2RPCSession, selectedFiles: String) async throws -> [String: String] {
        let trimmed = selectedFiles.trimmed
        let lowercased = trimmed.lowercased()
        let gids = try await activeGIDs(session: session)
        guard let gid = gids.first else {
            throw NativeDownloadError.unsupported("No active aria2 download.")
        }

        let normalized: String
        if trimmed.isEmpty || ["all", "*"].contains(lowercased) {
            normalized = try await allFileSelection(session: session, gid: gid)
        } else {
            normalized = Aria2Options.normalizedFileSelection(trimmed)
            guard !normalized.isEmpty else {
                throw NativeDownloadError.unsupported("Invalid aria2 file selection.")
            }
        }
        guard !normalized.isEmpty else {
            throw NativeDownloadError.unsupported("No aria2 torrent files were available.")
        }

        _ = try await request(session: session, method: "aria2.changeOption", params: [token(session), gid, ["select-file": normalized]])
        return ["selected_files": normalized]
    }

    static func changeSeeding(session: Aria2RPCSession, seedTimeMinutes: String, seedRatio: String) async throws -> [String: String] {
        let normalized = Aria2Options(
            selectedFiles: "",
            seedTimeMinutes: seedTimeMinutes,
            seedRatio: seedRatio,
            maxDownloadLimit: "",
            maxUploadLimit: "",
            trackerURLs: "",
            anonymousMode: false
        )
        let gids = try await activeGIDs(session: session)
        guard let gid = gids.first else {
            throw NativeDownloadError.unsupported("No active aria2 download.")
        }

        var options = ["seed-time": normalized.seedTimeMinutes]
        if !normalized.seedRatio.isEmpty {
            options["seed-ratio"] = normalized.seedRatio
        }
        _ = try await request(session: session, method: "aria2.changeOption", params: [token(session), gid, options])
        return [
            "seed_time_minutes": normalized.seedTimeMinutes,
            "seed_ratio": normalized.seedRatio
        ]
    }

    static func peerEntries(session: Aria2RPCSession) async throws -> [Aria2PeerEntry] {
        let gids = try await activeGIDs(session: session)
        guard let gid = gids.first else {
            throw NativeDownloadError.unsupported("No active aria2 download.")
        }

        let result = try await request(session: session, method: "aria2.getPeers", params: [token(session), gid])
        guard let objects = result as? [[String: Any]] else { return [] }
        return objects.map { object in
            Aria2PeerEntry(
                peerID: stringValue(object["peerId"]),
                ip: stringValue(object["ip"]),
                port: stringValue(object["port"]),
                downloadSpeed: stringValue(object["downloadSpeed"]),
                uploadSpeed: stringValue(object["uploadSpeed"]),
                seeder: boolStringValue(object["seeder"]),
                amChoking: boolStringValue(object["amChoking"]),
                peerChoking: boolStringValue(object["peerChoking"])
            )
        }
    }

    private static func activeGIDs(session: Aria2RPCSession) async throws -> [String] {
        let result = try await request(session: session, method: "aria2.tellActive", params: [token(session), ["gid"]])
        guard let objects = result as? [[String: Any]] else { return [] }
        return objects.compactMap { $0["gid"] as? String }.filter { !$0.isEmpty }
    }

    private static func allFileSelection(session: Aria2RPCSession, gid: String) async throws -> String {
        let result = try await request(session: session, method: "aria2.getFiles", params: [token(session), gid])
        guard let objects = result as? [[String: Any]] else { return "" }
        let indexes = objects.compactMap { object -> Int? in
            if let string = object["index"] as? String {
                return Int(string)
            }
            if let number = object["index"] as? NSNumber {
                return number.intValue
            }
            if let int = object["index"] as? Int {
                return int
            }
            return nil
        }
        return compressedFileSelection(indexes)
    }

    private static func compressedFileSelection(_ indexes: [Int]) -> String {
        let sorted = Array(Set(indexes.filter { $0 > 0 })).sorted()
        guard let first = sorted.first else { return "" }

        var ranges: [String] = []
        var start = first
        var previous = first
        for value in sorted.dropFirst() {
            if value == previous + 1 {
                previous = value
                continue
            }
            ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = value
            previous = value
        }
        ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return ranges.joined(separator: ",")
    }

    private static func stringValue(_ value: Any?) -> String {
        switch value {
        case let string as String:
            return string
        case let number as NSNumber:
            return number.stringValue
        case let int as Int:
            return String(int)
        case let bool as Bool:
            return bool ? "true" : "false"
        default:
            return ""
        }
    }

    private static func boolStringValue(_ value: Any?) -> String {
        let raw = stringValue(value).trimmed.lowercased()
        switch raw {
        case "1", "true", "yes":
            return "true"
        case "0", "false", "no":
            return "false"
        default:
            return raw
        }
    }

    private static func request(session: Aria2RPCSession, method: String, params: [Any]) async throws -> Any? {
        let payload: [String: Any] = [
            "jsonrpc": "2.0",
            "id": UUID().uuidString,
            "method": method,
            "params": params
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        var request = URLRequest(url: session.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = data

        let configuration = URLSessionConfiguration.ephemeral
        NetworkSessionPrivacy.disableSystemCredentialPersistence(in: configuration)
        configuration.timeoutIntervalForRequest = 2
        configuration.timeoutIntervalForResource = 2
        let urlSession = URLSession(configuration: configuration)
        let (responseData, response) = try await urlSession.data(for: request)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
            throw NativeDownloadError.unsupported("aria2 RPC request failed.")
        }
        let object = try JSONSerialization.jsonObject(with: responseData) as? [String: Any]
        if let error = object?["error"] as? [String: Any] {
            let rawMessage = (error["message"] as? String)?.trimmed ?? ""
            let message = rawMessage.isEmpty ? "unknown aria2 RPC error" : rawMessage
            throw NativeDownloadError.unsupported("aria2 RPC failed: \(message)")
        }
        return object?["result"]
    }

    private static func token(_ session: Aria2RPCSession) -> String {
        "token:\(session.secret)"
    }
}

final class Aria2Bridge {
    func canResolve(_ url: URL) -> Bool {
        if url.scheme?.lowercased() == "magnet" {
            return true
        }
        return url.path.lowercased().hasSuffix(".torrent")
    }

    func download(
        url: URL,
        to root: URL,
        headers: HTTPRequestOptions = HTTPRequestOptions(),
        options: Aria2Options = .defaults,
        processControl: ExternalProcessControl? = nil,
        rpcSession: Aria2RPCSession? = nil
    ) async throws -> Aria2Result {
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("aria2c is unavailable. Open Settings > External Tools to restore the bundled tool or choose an executable.")
        }

        try AppPaths.ensureDirectory(root)

        let outputDirectory = AppPaths.uniqueDirectoryURL(in: root, name: "\(title(from: url)) torrent")
        try AppPaths.ensureDirectory(outputDirectory)
        let torrentPieceInfo = Self.torrentPieceInfo(for: url)

        let logURL = outputDirectory.appendingPathComponent("aria2c.log")
        var arguments = [
            "--summary-interval=0",
            "--console-log-level=warn",
            "--allow-overwrite=false",
            "--auto-file-renaming=true",
            "--dir=\(outputDirectory.path)"
        ]
        arguments.append(contentsOf: options.arguments)
        if let rpcSession {
            arguments.append(contentsOf: [
                "--enable-rpc=true",
                "--rpc-listen-all=false",
                "--rpc-listen-port=\(rpcSession.port)",
                "--rpc-secret=\(rpcSession.secret)"
            ])
        }

        if let proxy = NetworkSettings.load().proxyArgument(for: url) {
            arguments.append("--all-proxy=\(proxy)")
        }

        if let referer = headers.referer?.trimmed, !referer.isEmpty {
            arguments.append("--referer=\(referer)")
        }

        if let userAgent = headers.userAgent?.trimmed, !userAgent.isEmpty {
            arguments.append("--user-agent=\(userAgent)")
        }

        arguments.append(sourceArgument(for: url))

        try await run(executable: executable, arguments: arguments, logURL: logURL, processControl: processControl)

        let items = try outputItems(in: outputDirectory)
        guard !items.isEmpty else {
            throw NativeDownloadError.unsupported("aria2c finished, but no downloaded file was created.")
        }

        try? FileManager.default.removeItem(at: logURL)
        return Aria2Result(outputDirectory: outputDirectory, downloadedItems: items, torrentPieceInfo: torrentPieceInfo)
    }

    func listFiles(url: URL, headers: HTTPRequestOptions = HTTPRequestOptions()) async throws -> [Aria2FileEntry] {
        guard let executable = executableURL() else {
            throw NativeDownloadError.unsupported("aria2c is unavailable. Open Settings > External Tools to restore the bundled tool or choose an executable.")
        }

        let workDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayoAria2FileList-\(UUID().uuidString)", isDirectory: true)
        try AppPaths.ensureDirectory(workDirectory)
        defer {
            try? FileManager.default.removeItem(at: workDirectory)
        }

        let logURL = workDirectory.appendingPathComponent("aria2c-show-files.log")
        var arguments = [
            "--show-files=true",
            "--summary-interval=0",
            "--console-log-level=warn",
            "--dir=\(workDirectory.path)"
        ]

        if let proxy = NetworkSettings.load().proxyArgument(for: url) {
            arguments.append("--all-proxy=\(proxy)")
        }

        if let referer = headers.referer?.trimmed, !referer.isEmpty {
            arguments.append("--referer=\(referer)")
        }

        if let userAgent = headers.userAgent?.trimmed, !userAgent.isEmpty {
            arguments.append("--user-agent=\(userAgent)")
        }

        arguments.append(sourceArgument(for: url))
        try await run(executable: executable, arguments: arguments, logURL: logURL)

        let data = (try? Data(contentsOf: logURL)) ?? Data()
        let entries = Self.parseFileList(String(decoding: data, as: UTF8.self))
        guard !entries.isEmpty else {
            throw NativeDownloadError.unsupported("aria2c did not return a torrent file list.")
        }
        return entries
    }

    private func title(from url: URL) -> String {
        if url.scheme?.lowercased() == "magnet",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let displayName = components.queryItems?.first(where: { $0.name == "dn" })?.value,
           !displayName.trimmed.isEmpty {
            return displayName.sanitizedFilename(maxLength: 80)
        }

        let last = url.deletingPathExtension().lastPathComponent
        if !last.trimmed.isEmpty {
            return last.sanitizedFilename(maxLength: 80)
        }

        return "torrent"
    }

    private func sourceArgument(for url: URL) -> String {
        url.isFileURL ? url.path : url.absoluteString
    }

    private func executableURL() -> URL? {
        ExternalToolSettings.executableURL(
            kind: .aria2c,
            environmentKey: "HITOMI_NATIVE_ARIA2C",
            executableName: "aria2c",
            knownPaths: [
                "/opt/homebrew/bin/aria2c",
                "/usr/local/bin/aria2c",
                "/usr/bin/aria2c"
            ]
        )
    }

    private func run(
        executable: URL,
        arguments: [String],
        logURL: URL,
        processControl: ExternalProcessControl? = nil
    ) async throws {
        try await ExternalProcessRunner.run(
            executable: executable,
            arguments: arguments,
            logURL: logURL,
            control: processControl,
            failureDescription: "aria2c"
        )
    }

    private func outputItems(in directory: URL) throws -> [URL] {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var items: [URL] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            guard name != "aria2c.log", !name.hasSuffix(".aria2") else { continue }
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            if values.isRegularFile == true {
                items.append(url)
            }
        }

        return items.sorted { $0.path < $1.path }
    }

    static func torrentPieceInfo(for url: URL) -> TorrentPieceInfo? {
        guard url.isFileURL,
              url.pathExtension.lowercased() == "torrent",
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return torrentPieceInfo(from: data)
    }

    static func torrentPieceInfo(from data: Data) -> TorrentPieceInfo? {
        var parser = TorrentBencodeParser(data)
        guard case let .dictionary(root)? = try? parser.parseRoot(),
              case let .dictionary(info)? = root["info"],
              case let .integer(pieceLength)? = info["piece length"],
              pieceLength > 0,
              case let .byteString(pieces)? = info["pieces"],
              pieces.count >= 20,
              pieces.count % 20 == 0 else {
            return nil
        }

        let totalLength = torrentTotalLength(from: info)
        guard totalLength > 0 else { return nil }
        return TorrentPieceInfo(
            pieceLength: pieceLength,
            pieceCount: pieces.count / 20,
            totalLength: totalLength
        )
    }

    private static func torrentTotalLength(from info: [String: TorrentBencodeValue]) -> Int64 {
        if case let .integer(length)? = info["length"], length > 0 {
            return length
        }

        guard case let .list(files)? = info["files"] else { return 0 }
        return files.reduce(Int64(0)) { total, value in
            guard case let .dictionary(file) = value,
                  case let .integer(length)? = file["length"],
                  length > 0 else {
                return total
            }
            return total + length
        }
    }

    private static func tail(_ text: String) -> String {
        let lines = text
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .filter { !$0.isEmpty }
        let tail = lines.suffix(6).joined(separator: " ")
        return tail.isEmpty ? "no diagnostic output" : tail
    }

    private static func parseFileList(_ text: String) -> [Aria2FileEntry] {
        var entries: [Aria2FileEntry] = []
        var currentIndex: Int?
        var currentPath = ""
        var currentLength = ""
        var currentSelected: Bool?

        func flushCurrent() {
            guard let index = currentIndex, !currentPath.trimmed.isEmpty else { return }
            entries.append(Aria2FileEntry(index: index, path: currentPath.trimmed, length: currentLength.trimmed, selected: currentSelected))
            currentIndex = nil
            currentPath = ""
            currentLength = ""
            currentSelected = nil
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty else { continue }

            if trimmed.lowercased().hasPrefix("file:") {
                flushCurrent()
                currentIndex = Int(String(trimmed.dropFirst(5)).trimmed)
                continue
            }

            if trimmed.hasPrefix("path=") {
                currentPath = String(trimmed.dropFirst(5))
                continue
            }

            if trimmed.hasPrefix("length=") {
                currentLength = String(trimmed.dropFirst(7))
                continue
            }

            if trimmed.hasPrefix("selected=") {
                let value = String(trimmed.dropFirst(9)).lowercased()
                currentSelected = value == "true" || value == "yes" || value == "1"
                continue
            }

            let tableParts = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
            if tableParts.count == 2,
               let index = Int(String(tableParts[0]).trimmed),
               !String(tableParts[1]).trimmed.isEmpty {
                flushCurrent()
                currentIndex = index
                currentPath = String(tableParts[1]).trimmed
                continue
            }

            if trimmed.hasPrefix("|"),
               var last = entries.last {
                let length = String(trimmed.dropFirst()).trimmed
                if !length.isEmpty, last.length.isEmpty {
                    last.length = length
                    entries[entries.count - 1] = last
                }
            }
        }

        flushCurrent()
        return entries.sorted { $0.index < $1.index }
    }
}
