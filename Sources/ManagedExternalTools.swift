import CryptoKit
import Foundation

struct ManagedExternalToolSources: Sendable {
    var ytdlpBinaryURL: URL
    var ytdlpChecksumsURL: URL
    var denoArchiveURL: URL
    var denoChecksumsURL: URL
    var ffmpegArchiveURL: URL
    var ffprobeArchiveURL: URL
    var allowsInsecureLocalhost: Bool = false

    static let production = ManagedExternalToolSources(
        ytdlpBinaryURL: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/2026.07.04/yt-dlp_macos")!,
        ytdlpChecksumsURL: URL(string: "https://github.com/yt-dlp/yt-dlp/releases/download/2026.07.04/SHA2-256SUMS")!,
        denoArchiveURL: URL(string: "https://github.com/denoland/deno/releases/download/v2.9.4/deno-aarch64-apple-darwin.zip")!,
        denoChecksumsURL: URL(string: "https://github.com/denoland/deno/releases/download/v2.9.4/deno-aarch64-apple-darwin.zip.sha256sum")!,
        ffmpegArchiveURL: URL(string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1783011502_8.1.2/ffmpeg.zip")!,
        ffprobeArchiveURL: URL(string: "https://ffmpeg.martin-riedl.de/download/macos/arm64/1783011502_8.1.2/ffprobe.zip")!
    )
}

struct ManagedExternalToolInstallResult: Sendable {
    var kind: ExternalToolKind
    var executableURL: URL
    var auxiliaryURLs: [URL]
    var version: String
}

enum ManagedExternalToolError: LocalizedError {
    case invalidResponse(String)
    case unsafeURL(String)
    case oversizedDownload(String)
    case missingChecksum(String)
    case checksumMismatch(String)
    case invalidExecutable(String)
    case bundledToolMissing(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse(let value): return "Invalid tool download response: \(value)"
        case .unsafeURL(let value): return "Refusing unsafe tool URL: \(value)"
        case .oversizedDownload(let value): return "Tool download is unexpectedly large: \(value)"
        case .missingChecksum(let value): return "No SHA-256 checksum was published for \(value)."
        case .checksumMismatch(let value): return "SHA-256 verification failed for \(value)."
        case .invalidExecutable(let value): return "Downloaded tool is not a valid macOS executable: \(value)"
        case .bundledToolMissing(let value): return "Bundled \(value) is missing from this app build."
        }
    }
}

actor ManagedExternalToolInstaller {
    static let shared = ManagedExternalToolInstaller()

    func install(
        _ kind: ExternalToolKind,
        sources: ManagedExternalToolSources = .production
    ) async throws -> ManagedExternalToolInstallResult {
        switch kind {
        case .ytdlp:
            return try await installYTDLP(sources: sources)
        case .deno:
            return try await installDeno(sources: sources)
        case .ffmpeg:
            return try await installFFmpeg(sources: sources)
        case .aria2c:
            return try await installBundledAria2()
        }
    }

    func removeManagedTools() throws {
        let directory = ExternalToolSettings.managedBinDirectory
        guard FileManager.default.fileExists(atPath: directory.path) else { return }
        try FileManager.default.removeItem(at: directory)
    }

    private func installYTDLP(
        sources: ManagedExternalToolSources
    ) async throws -> ManagedExternalToolInstallResult {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let checksums = try await downloadText(
            sources.ytdlpChecksumsURL,
            sources: sources,
            maximumBytes: 2 * 1_024 * 1_024
        )
        guard let expected = expectedChecksum(for: "yt-dlp_macos", in: checksums) else {
            throw ManagedExternalToolError.missingChecksum("yt-dlp_macos")
        }

        let artifact = try await downloadFile(
            sources.ytdlpBinaryURL,
            into: workspace,
            filename: "yt-dlp_macos",
            sources: sources,
            maximumBytes: 150 * 1_024 * 1_024
        )
        try verifyChecksum(expected, fileURL: artifact.fileURL)
        let version = try await validateExecutable(artifact.fileURL, arguments: ["--version"])
        let installed = try installExecutable(artifact.fileURL, kind: .ytdlp)
        return ManagedExternalToolInstallResult(
            kind: .ytdlp,
            executableURL: installed,
            auxiliaryURLs: [],
            version: version
        )
    }

    private func installDeno(
        sources: ManagedExternalToolSources
    ) async throws -> ManagedExternalToolInstallResult {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let archiveName = "deno-aarch64-apple-darwin.zip"
        let checksums = try await downloadText(
            sources.denoChecksumsURL,
            sources: sources,
            maximumBytes: 64 * 1_024
        )
        guard let expected = expectedChecksum(for: archiveName, in: checksums) else {
            throw ManagedExternalToolError.missingChecksum(archiveName)
        }

        let artifact = try await downloadFile(
            sources.denoArchiveURL,
            into: workspace,
            filename: archiveName,
            sources: sources,
            maximumBytes: 150 * 1_024 * 1_024
        )
        try verifyChecksum(expected, fileURL: artifact.fileURL)

        let extraction = workspace.appendingPathComponent("deno-extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
        let logURL = workspace.appendingPathComponent("deno-extract.log")
        try await ExternalProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", artifact.fileURL.path, extraction.path],
            logURL: logURL,
            failureDescription: "Extracting Deno"
        )

        guard let executable = findExecutable(named: "deno", in: extraction) else {
            throw ManagedExternalToolError.invalidExecutable("deno")
        }
        let version = try await validateExecutable(executable, arguments: ["--version"])
        let installed = try installExecutable(executable, kind: .deno)
        return ManagedExternalToolInstallResult(
            kind: .deno,
            executableURL: installed,
            auxiliaryURLs: [],
            version: version
        )
    }

    private func installFFmpeg(
        sources: ManagedExternalToolSources
    ) async throws -> ManagedExternalToolInstallResult {
        let workspace = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: workspace) }

        let ffmpeg = try await downloadVerifiedFFmpegArchive(
            sources.ffmpegArchiveURL,
            executableName: "ffmpeg",
            workspace: workspace,
            sources: sources,
            maximumBytes: 350 * 1_024 * 1_024
        )
        let ffprobe = try await downloadVerifiedFFmpegArchive(
            sources.ffprobeArchiveURL,
            executableName: "ffprobe",
            workspace: workspace,
            sources: sources,
            maximumBytes: 200 * 1_024 * 1_024
        )

        let version = try await validateExecutable(ffmpeg, arguments: ["-version"])
        _ = try await validateExecutable(ffprobe, arguments: ["-version"])
        let installedFFmpeg = try installExecutable(ffmpeg, kind: .ffmpeg)
        let installedFFprobe = try installExecutable(ffprobe, filename: "ffprobe")
        return ManagedExternalToolInstallResult(
            kind: .ffmpeg,
            executableURL: installedFFmpeg,
            auxiliaryURLs: [installedFFprobe],
            version: version
        )
    }

    private func installBundledAria2() async throws -> ManagedExternalToolInstallResult {
        guard let bundled = ExternalToolSettings.bundledExecutableURL(for: .aria2c) else {
            throw ManagedExternalToolError.bundledToolMissing("aria2c")
        }
        let version = try await validateExecutable(bundled, arguments: ["--version"])
        let installed = try installExecutable(bundled, kind: .aria2c)
        return ManagedExternalToolInstallResult(
            kind: .aria2c,
            executableURL: installed,
            auxiliaryURLs: [],
            version: version
        )
    }

    private func downloadVerifiedFFmpegArchive(
        _ url: URL,
        executableName: String,
        workspace: URL,
        sources: ManagedExternalToolSources,
        maximumBytes: Int64
    ) async throws -> URL {
        let artifact = try await downloadFile(
            url,
            into: workspace,
            filename: "\(executableName).zip",
            sources: sources,
            maximumBytes: maximumBytes
        )
        let checksumURL = artifact.finalURL.appendingPathExtension("sha256")
        let checksumText = try await downloadText(
            checksumURL,
            sources: sources,
            maximumBytes: 64 * 1_024
        )
        guard let expected = expectedChecksum(for: "\(executableName).zip", in: checksumText) else {
            throw ManagedExternalToolError.missingChecksum("\(executableName).zip")
        }
        try verifyChecksum(expected, fileURL: artifact.fileURL)

        let extraction = workspace.appendingPathComponent("\(executableName)-extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extraction, withIntermediateDirectories: true)
        let logURL = workspace.appendingPathComponent("\(executableName)-extract.log")
        try await ExternalProcessRunner.run(
            executable: URL(fileURLWithPath: "/usr/bin/ditto"),
            arguments: ["-x", "-k", artifact.fileURL.path, extraction.path],
            logURL: logURL,
            failureDescription: "Extracting \(executableName)"
        )

        guard let executable = findExecutable(named: executableName, in: extraction) else {
            throw ManagedExternalToolError.invalidExecutable(executableName)
        }
        return executable
    }

    private func downloadText(
        _ url: URL,
        sources: ManagedExternalToolSources,
        maximumBytes: Int
    ) async throws -> String {
        try validateDownloadURL(url, sources: sources)
        let session = makeSession(for: url)
        let (data, response) = try await session.data(from: url)
        try validate(response: response, finalURL: response.url, sources: sources)
        guard data.count <= maximumBytes else {
            throw ManagedExternalToolError.oversizedDownload(url.lastPathComponent)
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func downloadFile(
        _ url: URL,
        into workspace: URL,
        filename: String,
        sources: ManagedExternalToolSources,
        maximumBytes: Int64
    ) async throws -> (fileURL: URL, finalURL: URL) {
        try validateDownloadURL(url, sources: sources)
        let session = makeSession(for: url)
        let (temporary, response) = try await session.download(from: url)
        try validate(response: response, finalURL: response.url, sources: sources)

        let size = (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        guard size > 0, size <= maximumBytes else {
            throw ManagedExternalToolError.oversizedDownload(filename)
        }
        let destination = workspace.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: temporary, to: destination)
        return (destination, response.url ?? url)
    }

    private func makeSession(for url: URL) -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        NetworkSessionPrivacy.disableSystemCredentialPersistence(in: configuration)
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 1_800
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        configuration.httpAdditionalHeaders = [
            "User-Agent": "HitomiBadayo/0.3 ExternalToolInstaller",
            "Accept": "application/octet-stream,text/plain,*/*"
        ]
        if let proxy = NetworkSettings.load().connectionProxyDictionary(for: url) {
            configuration.connectionProxyDictionary = proxy
        }
        return URLSession(configuration: configuration)
    }

    private func validate(
        response: URLResponse,
        finalURL: URL?,
        sources: ManagedExternalToolSources
    ) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw ManagedExternalToolError.invalidResponse(finalURL?.absoluteString ?? "unknown")
        }
        if let finalURL {
            try validateDownloadURL(finalURL, sources: sources)
        }
    }

    private func validateDownloadURL(
        _ url: URL,
        sources: ManagedExternalToolSources
    ) throws {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "https" { return }
        let host = url.host?.lowercased() ?? ""
        if sources.allowsInsecureLocalhost,
           scheme == "http",
           host == "127.0.0.1" || host == "localhost" || host == "::1" {
            return
        }
        throw ManagedExternalToolError.unsafeURL(url.absoluteString)
    }

    private func expectedChecksum(for filename: String, in text: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let fields = line.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count >= 2 else { continue }
            let hash = String(fields[0]).lowercased()
            let name = String(fields.last!).trimmingCharacters(in: CharacterSet(charactersIn: "*"))
            if name == filename,
               hash.count == 64,
               hash.allSatisfy({ $0.isHexDigit }) {
                return hash
            }
        }
        return nil
    }

    private func verifyChecksum(_ expected: String, fileURL: URL) throws {
        let actual = try sha256Hex(fileURL)
        guard actual.caseInsensitiveCompare(expected) == .orderedSame else {
            throw ManagedExternalToolError.checksumMismatch(fileURL.lastPathComponent)
        }
    }

    private func sha256Hex(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let data = try handle.read(upToCount: 1_024 * 1_024), !data.isEmpty {
            hasher.update(data: data)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func findExecutable(named name: String, in directory: URL) -> URL? {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }
        for case let url as URL in enumerator where url.lastPathComponent == name {
            if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
                return url
            }
        }
        return nil
    }

    private func validateExecutable(_ url: URL, arguments: [String]) async throws -> String {
        guard try isMachOExecutable(url) else {
            throw ManagedExternalToolError.invalidExecutable(url.lastPathComponent)
        }
        if !FileManager.default.isExecutableFile(atPath: url.path) {
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
        let directory = try temporaryWorkspace()
        defer { try? FileManager.default.removeItem(at: directory) }
        let log = directory.appendingPathComponent("version.log")
        let output = directory.appendingPathComponent("version.txt")
        try await ExternalProcessRunner.run(
            executable: url,
            arguments: arguments,
            logURL: log,
            stdoutURL: output,
            failureDescription: url.lastPathComponent
        )
        let stdout = (try? String(contentsOf: output, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        let firstLine = (stdout + "\n" + stderr)
            .components(separatedBy: .newlines)
            .map { $0.trimmed }
            .first { !$0.isEmpty }
        guard let firstLine else {
            throw ManagedExternalToolError.invalidExecutable(url.lastPathComponent)
        }
        return firstLine
    }

    private func isMachOExecutable(_ url: URL) throws -> Bool {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        guard let data = try handle.read(upToCount: 4), data.count == 4 else { return false }
        let bytes = Array(data)
        return bytes == [0xcf, 0xfa, 0xed, 0xfe] ||
            bytes == [0xfe, 0xed, 0xfa, 0xcf] ||
            bytes == [0xca, 0xfe, 0xba, 0xbe] ||
            bytes == [0xca, 0xfe, 0xba, 0xbf]
    }

    private func installExecutable(
        _ source: URL,
        kind: ExternalToolKind
    ) throws -> URL {
        try installExecutable(source, filename: kind.executableName)
    }

    private func installExecutable(_ source: URL, filename: String) throws -> URL {
        let directory = ExternalToolSettings.managedBinDirectory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(filename)
        let staged = directory.appendingPathComponent(".\(filename)-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staged) }
        try FileManager.default.copyItem(at: source, to: staged)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: staged.path)

        let backup = directory.appendingPathComponent(".\(filename)-backup-\(UUID().uuidString)")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.moveItem(at: destination, to: backup)
        }
        do {
            try FileManager.default.moveItem(at: staged, to: destination)
            try? FileManager.default.removeItem(at: backup)
        } catch {
            if FileManager.default.fileExists(atPath: backup.path) {
                try? FileManager.default.moveItem(at: backup, to: destination)
            }
            throw error
        }
        return destination
    }

    private func temporaryWorkspace() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HitomiBadayo-Tools-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
