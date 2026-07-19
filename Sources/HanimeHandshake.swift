import CryptoKit
import Foundation
import JavaScriptCore

struct HanimeRequestSignature: Equatable {
    var value: String
    var timestamp: Int
}

enum HanimeHandshakeError: LocalizedError {
    case invalidConfiguration
    case invalidEncryptedToken
    case invalidSignature(String)
    case scriptFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration:
            return "Hanime's current API configuration is invalid."
        case .invalidEncryptedToken:
            return "Hanime returned an invalid encrypted handshake token."
        case .invalidSignature(let message):
            return message.isEmpty
                ? "Hanime's signature module did not return a valid signature."
                : "Hanime's signature module did not return a valid signature: \(message)"
        case .scriptFailed(let message):
            return "Hanime's signature module failed: \(message)"
        }
    }
}

enum HanimeSignatureGenerator {
    private static let maximumScriptSize = 2 * 1024 * 1024

    static func generate(script: String, pageURL: URL) throws -> HanimeRequestSignature {
        guard !script.trimmed.isEmpty, script.utf8.count <= maximumScriptSize else {
            throw HanimeHandshakeError.invalidSignature("script is empty or too large")
        }
        guard let context = JSContext() else {
            throw HanimeHandshakeError.invalidSignature("JavaScriptCore context creation failed")
        }

        var exceptionMessage = ""
        context.exceptionHandler = { _, exception in
            exceptionMessage = exception?.toString() ?? "unknown JavaScript error"
        }

        let href = javascriptLiteral(pageURL.absoluteString)
        let origin = javascriptLiteral(originString(for: pageURL))
        let shim = """
        var window = globalThis;
        var top = window;
        window.top = window;
        var navigator = { language: "en-US", userAgent: "Mozilla/5.0" };
        var document = { location: { href: \(href), origin: \(origin) } };
        var location = document.location;
        window.location = location;
        var CustomEvent = function(name, init) {
          this.type = name;
          this.detail = init && init.detail;
        };
        window.__hitomiNativeListeners = {};
        window.addEventListener = function(name, handler) {
          (window.__hitomiNativeListeners[name] || (window.__hitomiNativeListeners[name] = [])).push(handler);
        };
        window.dispatchEvent = function(event) {
          (window.__hitomiNativeListeners[event.type] || []).forEach(function(handler) { handler(event); });
          return true;
        };
        var console = { log: function() {}, error: function() {} };
        """

        context.evaluateScript(shim)
        if !exceptionMessage.isEmpty {
            throw HanimeHandshakeError.scriptFailed(exceptionMessage)
        }
        context.evaluateScript(script)
        if !exceptionMessage.isEmpty {
            throw HanimeHandshakeError.scriptFailed(exceptionMessage)
        }

        var listenerReady = false
        for _ in 0..<200 {
            context.evaluateScript("0")
            let count = context.evaluateScript(
                "Number((window.__hitomiNativeListeners.e || []).length)"
            )?.toInt32() ?? 0
            if count > 0 {
                listenerReady = true
                break
            }
            _ = RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        guard listenerReady else {
            throw HanimeHandshakeError.invalidSignature(
                exceptionMessage.isEmpty ? "request event listener was not registered" : exceptionMessage
            )
        }

        context.evaluateScript(
            "window.dispatchEvent(new CustomEvent('e', { detail: {} }))"
        )
        if !exceptionMessage.isEmpty {
            throw HanimeHandshakeError.scriptFailed(exceptionMessage)
        }

        let signature = context.evaluateScript(
            "String(window.ssignature || '')"
        )?.toString() ?? ""
        let timestampText = context.evaluateScript(
            "String(window.stime || '')"
        )?.toString() ?? ""
        guard signature.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil,
              let timestamp = Int(timestampText), timestamp > 0 else {
            throw HanimeHandshakeError.invalidSignature(exceptionMessage)
        }
        return HanimeRequestSignature(value: signature, timestamp: timestamp)
    }

    private static func originString(for url: URL) -> String {
        guard let scheme = url.scheme, let host = url.host else { return "https://hanime.tv" }
        if let port = url.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    private static func javascriptLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let array = String(data: data, encoding: .utf8),
              array.count >= 2 else {
            return "\"\""
        }
        return String(array.dropFirst().dropLast())
    }
}

enum HanimeHandshakeCrypto {
    private static let keySeed = Data("htv-insecure-handshake-v1".utf8)
    private static let authenticatedData = Data("htv-insecure-v1".utf8)

    static func encodeJSONObject(_ object: Any, nonceData: Data? = nil) throws -> String {
        guard JSONSerialization.isValidJSONObject(object) else {
            throw HanimeHandshakeError.invalidEncryptedToken
        }
        let plaintext = try JSONSerialization.data(withJSONObject: object)
        let nonce: AES.GCM.Nonce
        if let nonceData {
            guard nonceData.count == 12 else {
                throw HanimeHandshakeError.invalidEncryptedToken
            }
            nonce = try AES.GCM.Nonce(data: nonceData)
        } else {
            nonce = AES.GCM.Nonce()
        }
        let sealed = try AES.GCM.seal(
            plaintext,
            using: key,
            nonce: nonce,
            authenticating: authenticatedData
        )
        let envelope: [String: Any] = [
            "v": 1,
            "alg": "AES-256-GCM",
            "iv": base64URLEncode(Data(nonce)),
            "tag": base64URLEncode(sealed.tag),
            "data": base64URLEncode(sealed.ciphertext)
        ]
        let envelopeData = try JSONSerialization.data(withJSONObject: envelope)
        return base64URLEncode(envelopeData)
    }

    static func decodeJSONObject(_ encoded: String) throws -> Any {
        guard let envelopeData = base64URLDecode(encoded),
              let envelope = try JSONSerialization.jsonObject(with: envelopeData) as? [String: Any],
              let ivText = envelope["iv"] as? String,
              let tagText = envelope["tag"] as? String,
              let ciphertextText = envelope["data"] as? String,
              let iv = base64URLDecode(ivText),
              let tag = base64URLDecode(tagText),
              let ciphertext = base64URLDecode(ciphertextText),
              iv.count == 12, tag.count == 16 else {
            throw HanimeHandshakeError.invalidEncryptedToken
        }
        let nonce = try AES.GCM.Nonce(data: iv)
        let sealed = try AES.GCM.SealedBox(
            nonce: nonce,
            ciphertext: ciphertext,
            tag: tag
        )
        let plaintext = try AES.GCM.open(
            sealed,
            using: key,
            authenticating: authenticatedData
        )
        return try JSONSerialization.jsonObject(with: plaintext)
    }

    private static var key: SymmetricKey {
        SymmetricKey(data: Data(SHA256.hash(data: keySeed)))
    }

    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func base64URLDecode(_ value: String) -> Data? {
        var base64 = value
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        base64 += String(repeating: "=", count: (4 - base64.count % 4) % 4)
        return Data(base64Encoded: base64)
    }
}
