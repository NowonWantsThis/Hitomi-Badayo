import Foundation

enum PublicIPLookupOutcome: Equatable, Sendable {
    case success(String)
    case failure(String)
}

struct PublicIPLookupService: Sendable {
    typealias Fetcher =
        @Sendable (URL) async throws -> String

    private let fetcher: Fetcher

    init(
        fetcher:
            @escaping Fetcher = {
                try await HTTPClient.shared.string(from: $0)
            }
    ) {
        self.fetcher = fetcher
    }

    func lookup(at url: URL) async -> PublicIPLookupOutcome {
        do {
            let text = try await fetcher(url)
            return .success(
                try Self.publicIPAddress(from: text)
            )
        } catch {
            return .failure(
                AppLocalization.errorText(error)
            )
        }
    }

    static func lookupURL(
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> URL {
        if let value =
            environment[
                "HITOMI_NATIVE_PUBLIC_IP_URL"
            ]?.trimmed,
           !value.isEmpty,
           let url = URL(string: value) {
            return url
        }
        return URL(
            string: "https://api.ipify.org?format=text"
        )!
    }

    static func publicIPAddress(
        from text: String
    ) throws -> String {
        let trimmed = text.trimmed
        if let data = trimmed.data(using: .utf8),
           let object =
               try? JSONSerialization
               .jsonObject(with: data) as? [String: Any],
           let value = object["ip"] as? String,
           let normalized =
               normalizedPublicIPAddress(value) {
            return normalized
        }

        for token in trimmed.split(
            whereSeparator: {
                $0.isWhitespace ||
                    $0 == "," ||
                    $0 == "\""
            }
        ) {
            if let normalized =
                normalizedPublicIPAddress(
                    String(token)
                ) {
                return normalized
            }
        }

        throw NativeDownloadError.unsupported(
            "No public IP address was found."
        )
    }

    static func checkingStatus(
        settings: NetworkSettings,
        lookupURL: URL
    ) -> String {
        if let proxy =
            settings.proxyArgument(for: lookupURL) {
            return "Checking public IP via \(proxyDisplayName(proxy))..."
        }
        if settings.proxyEnabled &&
            settings.bypassesProxy(for: lookupURL) {
            return "Checking public IP directly (proxy bypassed)..."
        }
        return "Checking public IP directly..."
    }

    static func statusText(
        ip: String,
        settings: NetworkSettings,
        lookupURL: URL
    ) -> String {
        if let proxy =
            settings.proxyArgument(for: lookupURL) {
            return "Proxy public IP \(ip) · \(proxyDisplayName(proxy))"
        }
        if settings.proxyEnabled &&
            settings.bypassesProxy(for: lookupURL) {
            return "Direct public IP \(ip) (proxy bypassed)"
        }
        return "Direct public IP \(ip)"
    }

    static func failureStatus(
        settings: NetworkSettings,
        lookupURL: URL,
        errorDescription: String
    ) -> String {
        if let proxy =
            settings.proxyArgument(for: lookupURL) {
            return "Proxy public IP check failed · \(proxyDisplayName(proxy)): \(errorDescription)"
        }
        if settings.proxyEnabled &&
            settings.bypassesProxy(for: lookupURL) {
            return "Direct public IP check failed (proxy bypassed): \(errorDescription)"
        }
        return "Direct public IP check failed: \(errorDescription)"
    }

    private static func normalizedPublicIPAddress(
        _ value: String
    ) -> String? {
        let normalized =
            value.trimmed.trimmingCharacters(
                in:
                    CharacterSet(
                        charactersIn: "[](){}<>"
                    )
            )
        guard !normalized.isEmpty else { return nil }
        if normalized.range(
            of: #"^([0-9]{1,3}\.){3}[0-9]{1,3}$"#,
            options: .regularExpression
        ) != nil {
            let pieces =
                normalized.split(separator: ".")
                .compactMap { Int($0) }
            return pieces.count == 4 &&
                pieces.allSatisfy {
                    (0...255).contains($0)
                }
                ? normalized
                : nil
        }
        if normalized.contains(":"),
           normalized.range(
               of: #"^[A-Fa-f0-9:.%]+$"#,
               options: .regularExpression
           ) != nil {
            return normalized
        }
        return nil
    }

    private static func proxyDisplayName(
        _ proxy: String
    ) -> String {
        guard
            let components =
                URLComponents(string: proxy),
            let scheme = components.scheme,
            let host = components.host
        else {
            return proxy
        }
        var text = "\(scheme)://\(host)"
        if let port = components.port {
            text += ":\(port)"
        }
        return text
    }
}

@MainActor
final class PublicIPLookupCoordinator {
    private let service: PublicIPLookupService
    private var task: Task<Void, Never>?
    private var activeRequestID: UUID?

    init(
        service:
            PublicIPLookupService =
                PublicIPLookupService()
    ) {
        self.service = service
    }

    var hasActiveRequest: Bool {
        task != nil || activeRequestID != nil
    }

    @discardableResult
    func begin(
        url: URL,
        completion:
            @escaping @MainActor (
                PublicIPLookupOutcome
            ) -> Void
    ) -> Bool {
        guard !hasActiveRequest else {
            return false
        }

        let requestID = UUID()
        let service = service
        activeRequestID = requestID
        task = Task { @MainActor [weak self] in
            let outcome = await service.lookup(at: url)
            guard !Task.isCancelled,
                  self?.finish(requestID) == true else {
                return
            }
            completion(outcome)
        }
        return true
    }

    @discardableResult
    func cancelAndClear() -> Bool {
        let hadActiveRequest = hasActiveRequest
        task?.cancel()
        task = nil
        activeRequestID = nil
        return hadActiveRequest
    }

    @discardableResult
    private func finish(_ requestID: UUID) -> Bool {
        guard activeRequestID == requestID else {
            return false
        }
        task = nil
        activeRequestID = nil
        return true
    }

    deinit {
        task?.cancel()
    }
}
