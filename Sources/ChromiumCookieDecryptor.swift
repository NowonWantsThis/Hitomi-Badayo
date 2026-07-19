import CommonCrypto
import CryptoKit
import Foundation

struct ChromiumCookieDecryptor {
    let browserName: String

    static func context(for sourceURL: URL) -> ChromiumCookieDecryptor? {
        let path = sourceURL.path.lowercased()
        let candidates: [(needle: String, browser: String)] = [
            ("google/chrome for testing", "Chrome for Testing"),
            ("google/chrome canary", "Chrome Canary"),
            ("google/chrome beta", "Chrome Beta"),
            ("google/chrome", "Chrome"),
            ("chromium", "Chromium"),
            ("bravesoftware/brave-browser-nightly", "Brave Nightly"),
            ("bravesoftware/brave-browser-beta", "Brave Beta"),
            ("bravesoftware/brave-browser", "Brave"),
            ("microsoft edge canary", "Microsoft Edge Canary"),
            ("microsoft edge dev", "Microsoft Edge Dev"),
            ("microsoft edge beta", "Microsoft Edge Beta"),
            ("microsoft edge", "Microsoft Edge"),
            ("vivaldi", "Vivaldi"),
            ("operagx", "Opera GX"),
            ("opera", "Opera"),
            ("arc/user data", "Arc"),
            ("naver/whale", "Naver Whale"),
            ("whale", "Whale"),
            ("yandex/yandexbrowser", "Yandex Browser"),
            ("thorium", "Thorium"),
            ("ungoogled-chromium", "Ungoogled Chromium")
        ]

        for candidate in candidates where path.contains(candidate.needle) {
            return ChromiumCookieDecryptor(browserName: candidate.browser)
        }

        return ChromiumCookieDecryptor(browserName: "Chromium")
    }

    func decryptCookieValue(_ encryptedValue: Data, hostKey: String) throws -> String {
        let key = try deriveKey()
        let iv = Data(repeating: 0x20, count: kCCBlockSizeAES128)
        let ciphertext = encryptedValue.droppingChromiumPrefix()
        let decrypted = try HLSDecrypter.decryptAES128CBC(data: ciphertext, key: key, iv: iv)
        let payload = decrypted.removingChromiumHostDigest(for: hostKey)

        guard let value = String(data: payload, encoding: .utf8) else {
            throw NativeDownloadError.unsupported("Chromium cookie value was decrypted but is not UTF-8.")
        }

        return value
    }

    private func deriveKey() throws -> Data {
        let password = try safeStoragePassword()
        let salt = Data("saltysalt".utf8)
        let keySize = kCCKeySizeAES128
        var key = Data(count: keySize)

        let status = key.withUnsafeMutableBytes { keyBytes in
            password.withUnsafeBytes { passwordBytes in
                salt.withUnsafeBytes { saltBytes in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passwordBytes.baseAddress?.assumingMemoryBound(to: Int8.self),
                        password.count,
                        saltBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA1),
                        1003,
                        keyBytes.baseAddress?.assumingMemoryBound(to: UInt8.self),
                        keySize
                    )
                }
            }
        }

        guard status == kCCSuccess else {
            throw NativeDownloadError.unsupported("Could not derive Chromium cookie key: \(status)")
        }

        return key
    }

    private func safeStoragePassword() throws -> Data {
        if let override = ProcessInfo.processInfo.environment["HITOMI_NATIVE_CHROMIUM_COOKIE_PASSWORD"], !override.isEmpty {
            return Data(override.utf8)
        }
        throw NativeDownloadError.unsupported(
            "Direct \(browserName) Safe Storage access is disabled to prevent macOS Keychain prompts. Use the in-app login browser instead."
        )
    }
}

private extension Data {
    func droppingChromiumPrefix() -> Data {
        if count > 3 {
            let prefix = String(decoding: prefix(3), as: UTF8.self)
            if prefix == "v10" || prefix == "v11" {
                return dropFirst(3)
            }
        }

        return self
    }

    func removingChromiumHostDigest(for hostKey: String) -> Data {
        guard count > 32 else { return self }
        let digest = Data(SHA256.hash(data: Data(hostKey.utf8)))
        guard prefix(32).elementsEqual(digest) else { return self }
        return dropFirst(32)
    }
}
