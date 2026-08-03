import Foundation

struct SourceAuthenticationURLSelection: Equatable {
    var url: URL?
    var source: String
}

final class SourceAuthenticationPolicy: @unchecked Sendable {
    static let shared = SourceAuthenticationPolicy()

    static let pixivLoginURL =
        URL(string: "https://accounts.pixiv.net/login")!
    static let pixivCookieURL =
        URL(string: "https://www.pixiv.net/")!
    static let chzzkLoginURL =
        URL(
            string:
                "https://nid.naver.com/nidlogin.login?url=https://chzzk.naver.com"
        )!
    static let chzzkCookieURL =
        URL(string: "https://chzzk.naver.com/")!
    static let naverCafeLoginURL =
        URL(
            string:
                "https://nid.naver.com/nidlogin.login?url=https://cafe.naver.com"
        )!
    static let naverCafeCookieURL =
        URL(string: "https://cafe.naver.com/")!
    static let twitterLoginURL =
        URL(string: "https://x.com/i/flow/login")!
    static let twitterCookieURL =
        URL(string: "https://x.com/")!
    static let pornhubPremiumLoginURL =
        URL(
            string:
                "https://www.pornhubpremium.com/premium/login"
        )!
    static let arcaliveLoginURL =
        URL(string: "https://arca.live/u/login?goto=%2F")!
    static let arcaliveCookieURL =
        URL(string: "https://arca.live/")!

    private static let supportedProviderKeys = Set([
        "pixiv",
        "chzzk",
        "naver-cafe",
        "twitter",
        "pornhub-premium",
        "arcalive"
    ])

    func browserURLSelection(
        inputText: String,
        jobs: [DownloadJob],
        normalizingToken: (String) -> String
    ) -> SourceAuthenticationURLSelection {
        if let url = firstWebURL(
            from: inputText,
            normalizingToken: normalizingToken
        ) {
            return SourceAuthenticationURLSelection(
                url: url,
                source: "input"
            )
        }
        for job in jobs {
            if let url = webURL(
                fromNormalizedToken:
                    normalizingToken(job.source.trimmed)
            ) {
                return SourceAuthenticationURLSelection(
                    url: url,
                    source: "queue"
                )
            }
        }
        return SourceAuthenticationURLSelection(
            url: URL(string: "https://hitomi.la"),
            source: "default"
        )
    }

    func loginBrowserURL(
        inputText: String,
        jobs: [DownloadJob],
        normalizingToken: (String) -> String
    ) -> URL? {
        browserURLSelection(
            inputText: inputText,
            jobs: jobs,
            normalizingToken: normalizingToken
        ).url
    }

    func loginBrowserURL(
        for job: DownloadJob,
        authenticationKey: String?,
        normalizingToken: (String) -> String
    ) -> URL? {
        switch authenticationKey {
        case "pixiv":
            return Self.pixivLoginURL
        case "chzzk":
            return Self.chzzkLoginURL
        case "naver-cafe":
            return Self.naverCafeLoginURL
        case "twitter":
            return Self.twitterLoginURL
        case "pornhub-premium":
            return Self.pornhubPremiumLoginURL
        case "arcalive":
            return Self.arcaliveLoginURL
        default:
            return firstWebURL(
                from: job.source,
                normalizingToken: normalizingToken
            )
        }
    }

    func explicitProviderKey(
        for job: DownloadJob
    ) -> String? {
        let explicit =
            (job.metadata["authentication_waiting"] ?? "")
            .trimmed
            .lowercased()
        return Self.supportedProviderKeys.contains(explicit)
            ? explicit
            : nil
    }

    func inferredProviderKey(
        for job: DownloadJob,
        normalizingToken: (String) -> String
    ) -> String? {
        guard let url = firstWebURL(
            from: job.source,
            normalizingToken: normalizingToken
        ) else {
            return nil
        }
        return providerKey(for: url)
    }

    func providerKey(for url: URL) -> String? {
        guard let host = url.host?.lowercased() else {
            return nil
        }
        if Self.host(
            host,
            matches: ["pixiv.net", "pixiv.test"]
        ) {
            return "pixiv"
        }
        if Self.host(
            host,
            matches: [
                "chzzk.naver.com",
                "chzzk.naver.test",
                "nid.naver.com"
            ]
        ) {
            return "chzzk"
        }
        if Self.host(
            host,
            matches: ["cafe.naver.com", "cafe.naver.test"]
        ) {
            return "naver-cafe"
        }
        if Self.host(
            host,
            matches: [
                "x.com",
                "twitter.com",
                "x.test",
                "twitter.test"
            ]
        ) {
            return "twitter"
        }
        if Self.host(
            host,
            matches: [
                "pornhubpremium.com",
                "pornhubpremium.net",
                "pornhubpremium.org"
            ]
        ) {
            return "pornhub-premium"
        }
        if Self.host(
            host,
            matches: ["arca.live", "arca.test"]
        ) {
            return "arcalive"
        }
        return nil
    }

    func providerName(
        for key: String,
        job: DownloadJob,
        normalizingToken: (String) -> String
    ) -> String {
        switch key {
        case "pixiv":
            return "Pixiv"
        case "chzzk":
            return "Chzzk"
        case "naver-cafe":
            return "Naver Cafe"
        case "twitter":
            return "Twitter/X"
        case "pornhub-premium":
            return "Pornhub Premium"
        case "arcalive":
            return "Arcalive"
        default:
            let site = (job.metadata["site"] ?? "").trimmed
            if !site.isEmpty {
                return site
            }
            return firstWebURL(
                from: job.source,
                normalizingToken: normalizingToken
            )?.host ?? ""
        }
    }

    func jobAccessReaction(
        for job: DownloadJob,
        normalizingToken: (String) -> String
    ) -> JobAccessReaction? {
        if let authenticationKey = explicitProviderKey(
            for: job
        ) {
            return .login(
                provider: providerName(
                    for: authenticationKey,
                    job: job,
                    normalizingToken: normalizingToken
                )
            )
        }

        let message = [
            job.message,
            job.metadata["last_error"] ?? ""
        ]
        .joined(separator: " ")
        .trimmed
        .lowercased()
        let cookieFlag = [
            "cookie_required",
            "cookies_required",
            "cookie_expired"
        ].contains { key in
            guard let value =
                job.metadata[key]?.trimmed.lowercased()
            else {
                return false
            }
            return [
                "1",
                "true",
                "yes",
                "on",
                "required",
                "expired"
            ].contains(value)
        }
        let needsAttention = [
            "required",
            "waiting",
            "missing",
            "not found",
            "expired",
            "update",
            "refresh",
            "needed",
            "필요",
            "대기",
            "없",
            "만료",
            "업데이트"
        ].contains { message.contains($0) }

        if cookieFlag ||
            ((message.contains("cookie") ||
                message.contains("Cookies")) &&
                needsAttention) {
            return .cookies
        }
        if (message.contains("login") ||
            message.contains("authentication") ||
            message.contains("Sign In")) &&
            needsAttention {
            let providerKey = inferredProviderKey(
                for: job,
                normalizingToken: normalizingToken
            )
            return .login(
                provider: providerName(
                    for: providerKey ?? "",
                    job: job,
                    normalizingToken: normalizingToken
                )
            )
        }
        return nil
    }

    func firstWebURL(
        from text: String,
        normalizingToken: (String) -> String
    ) -> URL? {
        for rawLine in text.components(separatedBy: .newlines) {
            let normalized =
                normalizingToken(rawLine.trimmed)
            if let url = webURL(
                fromNormalizedToken: normalized
            ) {
                return url
            }
        }
        return nil
    }

    func browserCookieSummary(
        imported: Int,
        skipped: Int
    ) -> String {
        skipped > 0
            ? "Saved \(imported) cookies, skipped \(skipped)."
            : "Saved \(imported) cookies."
    }

    func storedCookieSummary(count: Int) -> String {
        count == 0
            ? "No cookies"
            : "Saved \(count) cookies."
    }

    private func webURL(
        fromNormalizedToken token: String
    ) -> URL? {
        guard let url = URL(string: token),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return url
    }

    private static func host(
        _ host: String,
        matches domains: [String]
    ) -> Bool {
        domains.contains {
            host == $0 || host.hasSuffix(".\($0)")
        }
    }
}
