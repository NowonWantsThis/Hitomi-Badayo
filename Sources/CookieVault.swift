import CryptoKit
import Foundation

private struct EncryptedCookieJarFile: Codable {
    let version: Int
    let savedAt: Date
    let algorithm: String
    let payload: Data
}

struct CookieVault {
    private let storageURL: URL
    private let keyProvider: CookieKeyProvider

    init(storageURL: URL, keyProvider: CookieKeyProvider = .default) {
        self.storageURL = storageURL
        self.keyProvider = keyProvider
    }

    func load() -> (cookies: [StoredCookie], needsEncryptedRewrite: Bool) {
        guard let data = try? Data(contentsOf: storageURL) else {
            return ([], false)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let encrypted = try? decoder.decode(EncryptedCookieJarFile.self, from: data) {
            if let plaintext = try? decrypt(encrypted.payload),
               let jar = try? decoder.decode(CookieJarFile.self, from: plaintext) {
                return (jar.cookies.filter { !$0.isExpired }, false)
            }
            preserveUnreadableEncryptedStore()
            return ([], false)
        }

        if let jar = try? decoder.decode(CookieJarFile.self, from: data) {
            return (jar.cookies.filter { !$0.isExpired }, true)
        }

        return ([], false)
    }

    func save(_ cookies: [StoredCookie]) throws {
        try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let jar = CookieJarFile(version: 1, savedAt: Date(), cookies: cookies)
        let plaintext = try encoder.encode(jar)
        let encrypted = EncryptedCookieJarFile(
            version: 2,
            savedAt: Date(),
            algorithm: "AES.GCM.256.LocalKey",
            payload: try encrypt(plaintext)
        )
        let data = try encoder.encode(encrypted)
        try data.write(to: storageURL, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: storageURL.path)
    }

    private func encrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try keyProvider.keyData())
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else {
            throw NativeDownloadError.unsupported("Could not build encrypted cookie payload.")
        }
        return combined
    }

    private func decrypt(_ data: Data) throws -> Data {
        let key = SymmetricKey(data: try keyProvider.keyData())
        let box = try AES.GCM.SealedBox(combined: data)
        return try AES.GCM.open(box, using: key)
    }

    private func preserveUnreadableEncryptedStore() {
        let backupURL = storageURL
            .deletingPathExtension()
            .appendingPathExtension("keychain-backup.json")
        guard !FileManager.default.fileExists(atPath: backupURL.path) else { return }
        do {
            try FileManager.default.copyItem(at: storageURL, to: backupURL)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backupURL.path)
        } catch {
            return
        }
    }
}

private enum CookieKeyProviderError: LocalizedError {
    case timedOut

    var errorDescription: String? {
        switch self {
        case .timedOut:
            return "Cookie encryption key lookup timed out."
        }
    }
}

private final class CookieKeyResultBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedResult: Result<Data, Error>?

    func store(_ result: Result<Data, Error>) {
        lock.lock()
        storedResult = result
        lock.unlock()
    }

    func result() -> Result<Data, Error>? {
        lock.lock()
        defer { lock.unlock() }
        return storedResult
    }
}

final class CookieKeyProvider: @unchecked Sendable {
    static let `default` = CookieKeyProvider(
        operationTimeout: 2,
        keyOperation: { try CookieKeyProvider.defaultFileBackedKey() }
    )
    typealias KeyOperation = @Sendable () throws -> Data

    private let operationTimeout: TimeInterval
    private let keyOperation: KeyOperation
    private let resultLock = NSLock()
    private var cachedKeyResult: Result<Data, Error>?

    init(
        operationTimeout: TimeInterval,
        keyOperation: @escaping KeyOperation
    ) {
        self.operationTimeout = max(0.05, operationTimeout)
        self.keyOperation = keyOperation
    }

    func keyData() throws -> Data {
        let environment = ProcessInfo.processInfo.environment
        if let path = environment["HITOMI_BADAYO_COOKIE_KEY_FILE"] ?? environment["HITOMI_NATIVE_COOKIE_KEY_FILE"],
           !path.isEmpty {
            return try Self.fileBackedKey(at: URL(fileURLWithPath: path))
        }

        resultLock.lock()
        defer { resultLock.unlock() }
        if let cachedKeyResult {
            return try cachedKeyResult.get()
        }
        let result = Result { try keyWithinTimeout() }
        cachedKeyResult = result
        return try result.get()
    }

    private static func fileBackedKey(at url: URL) throws -> Data {
        if let existing = try? Data(contentsOf: url), existing.count == 32 {
            return existing
        }

        let data = SymmetricKey(size: .bits256).withUnsafeBytes { Data($0) }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return data
    }

    private func keyWithinTimeout() throws -> Data {
        let resultBox = CookieKeyResultBox()
        let semaphore = DispatchSemaphore(value: 0)
        let keyOperation = self.keyOperation
        DispatchQueue.global(qos: .utility).async {
            resultBox.store(Result { try keyOperation() })
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + operationTimeout) == .success else {
            throw CookieKeyProviderError.timedOut
        }
        guard let result = resultBox.result() else {
            throw NativeDownloadError.unsupported("Cookie encryption key lookup returned no result.")
        }
        return try result.get()
    }

    private static func defaultFileBackedKey() throws -> Data {
        let url = AppPaths.applicationSupportDirectory
            .appendingPathComponent("cookie-encryption.key")
        return try fileBackedKey(at: url)
    }
}
