import Foundation

enum AppInterfaceLanguage: String, CaseIterable, Codable, Hashable, Identifiable {
    case english
    case japanese
    case simplifiedChinese
    case traditionalChinese
    case korean

    static let defaultsKey = "interfaceLanguage"

    var id: String { rawValue }

    var localeIdentifier: String {
        switch self {
        case .english: return "en"
        case .japanese: return "ja"
        case .simplifiedChinese: return "zh-Hans"
        case .traditionalChinese: return "zh-Hant"
        case .korean: return "ko"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    // Language names stay in their own language so the picker remains usable.
    var displayName: String {
        switch self {
        case .english: return "English"
        case .japanese: return "日本語"
        case .simplifiedChinese: return "简体中文"
        case .traditionalChinese: return "繁體中文"
        case .korean: return "한국어"
        }
    }

    static func normalized(_ value: String?) -> AppInterfaceLanguage {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "en", "eng", "english":
            return .english
        case "ja", "jpn", "japanese", "日本語":
            return .japanese
        case "zh", "zh-cn", "zh-sg", "zh-hans", "simplifiedchinese", "chinese-simplified",
             "simplified chinese", "简体中文", "簡體中文", "简体", "簡體":
            return .simplifiedChinese
        case "zh-tw", "zh-hk", "zh-mo", "zh-hant", "traditionalchinese", "chinese-traditional",
             "traditional chinese", "繁體中文", "繁体中文", "繁體", "繁体":
            return .traditionalChinese
        case "ko", "kor", "korean", "한국어":
            return .korean
        default:
            return .english
        }
    }
}

enum AppLocalization {
    static func currentLanguage(defaults: UserDefaults = .standard) -> AppInterfaceLanguage {
        AppInterfaceLanguage.normalized(defaults.string(forKey: AppInterfaceLanguage.defaultsKey))
    }

    static func text(
        _ key: String,
        language: AppInterfaceLanguage = currentLanguage(),
        bundle: Bundle = .main
    ) -> String {
        guard !key.isEmpty else { return key }
        if let path = bundle.path(forResource: language.localeIdentifier, ofType: "lproj"),
           let localizedBundle = Bundle(path: path) {
            return localizedBundle.localizedString(
                forKey: key,
                value: fallbackText(key, language: language),
                table: nil
            )
        }
        return fallbackText(key, language: language)
    }

    static func format(
        _ key: String,
        language: AppInterfaceLanguage = currentLanguage(),
        bundle: Bundle = .main,
        _ arguments: CVarArg...
    ) -> String {
        String(
            format: text(key, language: language, bundle: bundle),
            locale: language.locale,
            arguments: arguments
        )
    }

    static func statusText(
        _ value: String,
        language: AppInterfaceLanguage = currentLanguage(),
        bundle: Bundle = .main
    ) -> String {
        guard !value.isEmpty else { return value }

        let exact = text(value, language: language, bundle: bundle)
        if exact != value || (language == .english && !containsHangul(value)) {
            return exact
        }

        if value.hasSuffix(" Active Shortcuts") {
            let count = String(value.dropLast(" Active Shortcuts".count))
            return format("%@ Active Shortcuts", language: language, bundle: bundle, count)
        }

        if value.hasPrefix("Python 3 Ready · "), value.hasSuffix(" Enabled") {
            let count = value
                .dropFirst("Python 3 Ready · ".count)
                .dropLast(" Enabled".count)
            return format(
                "Python 3 Ready · %@ Enabled",
                language: language,
                bundle: bundle,
                String(count)
            )
        }

        if value.hasPrefix("Automatic Recording Added "), value.hasSuffix(" to Queue") {
            let count = value
                .dropFirst("Automatic Recording Added ".count)
                .dropLast(" to Queue".count)
            return format(
                "Automatic Recording Added %@ to Queue",
                language: language,
                bundle: bundle,
                String(count)
            )
        }

        if value.hasPrefix("Automatic Recording: Added "), value.hasSuffix(" to Queue") {
            let count = value
                .dropFirst("Automatic Recording: Added ".count)
                .dropLast(" to Queue".count)
            return format(
                "Automatic Recording: Added %@ to Queue",
                language: language,
                bundle: bundle,
                String(count)
            )
        }

        if value.hasPrefix("Installing "), value.hasSuffix("…") {
            return format(
                "Installing %@…",
                language: language,
                bundle: bundle,
                String(value.dropFirst("Installing ".count).dropLast())
            )
        }
        if let range = value.range(of: " Ready: ") {
            return format(
                "%@ Ready: %@",
                language: language,
                bundle: bundle,
                String(value[..<range.lowerBound]),
                String(value[range.upperBound...])
            )
        }
        if let range = value.range(of: " Installation Failed: ") {
            return format(
                "%@ Installation Failed: %@",
                language: language,
                bundle: bundle,
                String(value[..<range.lowerBound]),
                String(value[range.upperBound...])
            )
        }
        if value.hasPrefix("Running "), value.hasSuffix(" Hook...") {
            return format(
                "Running %@ Hook...",
                language: language,
                bundle: bundle,
                String(value.dropFirst("Running ".count).dropLast(" Hook...".count))
            )
        }
        if let range = value.range(of: " Hook Failed: ") {
            return format(
                "%@ Hook Failed: %@",
                language: language,
                bundle: bundle,
                String(value[..<range.lowerBound]),
                String(value[range.upperBound...])
            )
        }

        let replacements = [
            "Managed Tools Removed",
            "Removing Managed Tools",
            "Tool Installation Cancelled",
            "Tool Installation Failed",
            "Tool Removal Failed",
            "Auto-remove Hook",
            "Automatic Recording",
            "Python Scripts",
            "Select an Executable",
            "Proxy Bypassed",
            "Public IP",
            "Check Failed",
            "Checking",
            "Via",
            "Direct",
            "Proxy",
            "Ready",
            "Missing",
            "Pause",
            "Restart",
            "Waiting",
            "Running",
            "Complete",
            "Off",
            "On",
            "URL Required",
            "No New URLs",
            "Installation Failed",
            "Removal Failed",
            "Bundled",
            "Remains Available"
        ]
        let localized = replacements.reduce(value) { result, key in
            result.replacingOccurrences(
                of: "(?<![A-Za-z])\(NSRegularExpression.escapedPattern(for: key))(?![A-Za-z])",
                with: text(key, language: language, bundle: bundle),
                options: .regularExpression
            )
        }
        if localized != value {
            return localized
        }

        // Older queue records may contain Korean status strings from builds
        // released before English became the canonical source language.
        if language != .korean, containsHangul(value) {
            if value.contains("시간이 초과") {
                return text("The request timed out.", language: language, bundle: bundle)
            }
            return text("Status message unavailable.", language: language, bundle: bundle)
        }
        return value
    }

    static func errorText(
        _ error: Error,
        language: AppInterfaceLanguage = currentLanguage(),
        bundle: Bundle = .main
    ) -> String {
        if error is CancellationError {
            return text("Cancelled", language: language, bundle: bundle)
        }

        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            let code = URLError.Code(rawValue: nsError.code)
            let key: String
            switch code {
            case .timedOut:
                key = "The request timed out."
            case .notConnectedToInternet:
                key = "The Internet connection appears to be offline."
            case .networkConnectionLost:
                key = "The network connection was lost."
            case .cannotFindHost, .dnsLookupFailed:
                key = "The host could not be found."
            case .cannotConnectToHost:
                key = "Could not connect to the server."
            case .secureConnectionFailed, .serverCertificateHasBadDate,
                 .serverCertificateUntrusted, .serverCertificateHasUnknownRoot,
                 .serverCertificateNotYetValid, .clientCertificateRejected,
                 .clientCertificateRequired:
                key = "A secure connection could not be established."
            case .userAuthenticationRequired, .userCancelledAuthentication:
                key = "Authentication is required."
            case .resourceUnavailable:
                key = "The requested resource is unavailable."
            case .dataNotAllowed:
                key = "Network access is not allowed."
            case .badURL, .unsupportedURL:
                key = "The URL is invalid or unsupported."
            case .cannotDecodeContentData, .cannotDecodeRawData,
                 .cannotParseResponse:
                key = "The server response could not be decoded."
            case .cancelled:
                key = "Cancelled"
            default:
                return format(
                    "Network request failed (error %@).",
                    language: language,
                    bundle: bundle,
                    String(nsError.code)
                )
            }
            return text(key, language: language, bundle: bundle)
        }

        let description = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if language != .korean, containsHangul(description) {
            return format(
                "Operation failed (%@, error %@).",
                language: language,
                bundle: bundle,
                nsError.domain,
                String(nsError.code)
            )
        }
        return statusText(description, language: language, bundle: bundle)
    }

    private static func fallbackText(_ key: String, language _: AppInterfaceLanguage) -> String {
        key
    }

    private static func containsHangul(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0xAC00...0xD7AF).contains(Int(scalar.value)) ||
                (0x1100...0x11FF).contains(Int(scalar.value)) ||
                (0x3130...0x318F).contains(Int(scalar.value))
        }
    }
}

extension Notification.Name {
    static let hitomiBadayoInterfaceLanguageDidChange =
        Notification.Name("HitomiBadayoInterfaceLanguageDidChange")
}
