import CryptoKit
import Foundation

struct LocalAPIAuthorizationPolicy {
    private let requestDecoder: LocalAPIRequestDecoder

    init(requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder()) {
        self.requestDecoder = requestDecoder
    }

    func isAuthorized(
        _ request: LocalHTTPRequest,
        password rawPassword: String
    ) -> Bool {
        let password = rawPassword.trimmed
        guard !password.isEmpty else { return true }

        let parameters = requestDecoder.parameters(from: request)
        if parameters["pw"] == password || parameters["password"] == password {
            return true
        }
        if request.headers["x-hitomi-password"] == password {
            return true
        }
        if request.headers["authorization"] == "Bearer \(password)" {
            return true
        }
        if let ticket = requestDecoder.ticket(from: request),
           Self.acceptedAuthTickets(for: password).contains(ticket) {
            return true
        }
        return false
    }

    nonisolated static func authTicket(for password: String) -> String {
        var data = Data("#hiotmi".utf8)
        data.append(Data(password.utf8))
        let digest = Insecure.MD5.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func acceptedAuthTickets(
        for password: String
    ) -> Set<String> {
        [
            authTicket(for: password),
            sha256AuthTicket(for: password)
        ]
    }

    private nonisolated static func sha256AuthTicket(
        for password: String
    ) -> String {
        let digest = SHA256.hash(
            data: Data((password + "#hiotmi").utf8)
        )
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
