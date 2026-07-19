import CommonCrypto
import Foundation

enum HLSDecrypter {
    static func decryptAES128CBC(data: Data, key: Data, iv: Data) throws -> Data {
        guard key.count == kCCKeySizeAES128 else {
            throw NativeDownloadError.encryptedPlaylist("Invalid AES-128 key length: \(key.count)")
        }
        guard iv.count == kCCBlockSizeAES128 else {
            throw NativeDownloadError.encryptedPlaylist("Invalid AES-128 IV length: \(iv.count)")
        }

        let outputCapacity = data.count + kCCBlockSizeAES128
        var output = Data(count: outputCapacity)
        var moved = 0

        let status = output.withUnsafeMutableBytes { outputBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(kCCDecrypt),
                            CCAlgorithm(kCCAlgorithmAES),
                            CCOptions(kCCOptionPKCS7Padding),
                            keyBytes.baseAddress,
                            key.count,
                            ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outputBytes.baseAddress,
                            outputCapacity,
                            &moved
                        )
                    }
                }
            }
        }

        guard status == kCCSuccess else {
            throw NativeDownloadError.encryptedPlaylist("AES-128 segment decryption failed: \(status)")
        }

        output.removeSubrange(moved..<output.count)
        return output
    }
}
