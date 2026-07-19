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
        if exact != value || language == .korean {
            return exact
        }

        if value.hasPrefix("활성 단축키 "), value.hasSuffix("개") {
            let count = value
                .dropFirst("활성 단축키 ".count)
                .dropLast()
            return format("활성 단축키 %@개", language: language, bundle: bundle, String(count))
        }

        if value.hasPrefix("Python 3 준비됨 · ") {
            let detail = String(value.dropFirst("Python 3 준비됨 · ".count))
            if detail.hasSuffix("개 사용") {
                let count = detail.dropLast("개 사용".count)
                return format(
                    "Python 3 준비됨 · %@개 사용",
                    language: language,
                    bundle: bundle,
                    String(count)
                )
            }
        }

        if value.hasPrefix("자동 녹화 "), value.hasSuffix("개 대기열 추가") {
            let count = value
                .dropFirst("자동 녹화 ".count)
                .dropLast("개 대기열 추가".count)
            return format(
                "자동 녹화 %@개 대기열 추가",
                language: language,
                bundle: bundle,
                String(count)
            )
        }

        if value.hasPrefix("자동 녹화: "), value.hasSuffix("개 대기열 추가") {
            let count = value
                .dropFirst("자동 녹화: ".count)
                .dropLast("개 대기열 추가".count)
            return format(
                "자동 녹화: %@개 대기열 추가",
                language: language,
                bundle: bundle,
                String(count)
            )
        }

        if value.hasSuffix(" 설치 중…") {
            return format(
                "%@ 설치 중…",
                language: language,
                bundle: bundle,
                String(value.dropLast(" 설치 중…".count))
            )
        }
        if let range = value.range(of: " 준비됨: ") {
            return format(
                "%@ 준비됨: %@",
                language: language,
                bundle: bundle,
                String(value[..<range.lowerBound]),
                String(value[range.upperBound...])
            )
        }
        if let range = value.range(of: " 설치 실패: ") {
            return format(
                "%@ 설치 실패: %@",
                language: language,
                bundle: bundle,
                String(value[..<range.lowerBound]),
                String(value[range.upperBound...])
            )
        }
        if value.hasSuffix(" 후크 실행 중...") {
            return format(
                "%@ 후크 실행 중...",
                language: language,
                bundle: bundle,
                String(value.dropLast(" 후크 실행 중...".count))
            )
        }
        if let range = value.range(of: " 후크 실패: ") {
            return format(
                "%@ 후크 실패: %@",
                language: language,
                bundle: bundle,
                String(value[..<range.lowerBound]),
                String(value[range.upperBound...])
            )
        }

        let replacements = [
            "관리 도구 제거됨",
            "관리 도구 제거 중",
            "도구 설치 취소됨",
            "도구 설치 실패",
            "도구 제거 실패",
            "자동 제거 후크",
            "자동 녹화",
            "Python 스크립트",
            "실행 파일을 선택하세요",
            "프록시 제외",
            "공인 IP",
            "확인 실패",
            "확인 중",
            "경유",
            "직접",
            "프록시",
            "준비됨",
            "없음",
            "일시 정지",
            "다시 시작",
            "대기 중",
            "실행 중",
            "완료",
            "꺼짐",
            "켜짐",
            "URL 필요",
            "새 URL 없음",
            "설치 실패",
            "제거 실패",
            "내장",
            "계속 사용 가능"
        ]
        return replacements.reduce(value) { result, key in
            result.replacingOccurrences(
                of: key,
                with: text(key, language: language, bundle: bundle)
            )
        }
    }

    private static func fallbackText(_ key: String, language: AppInterfaceLanguage) -> String {
        switch language {
        case .korean:
            return koreanFallback[key] ?? key
        case .english, .japanese, .simplifiedChinese, .traditionalChinese:
            return englishFallback[key] ?? key
        }
    }

    private static let englishFallback: [String: String] = [
        "일반": "General",
        "네트워크": "Network",
        "녹화": "Recording",
        "디스플레이": "Display",
        "압축": "Archive",
        "플러그인": "Plugins",
        "고급": "Advanced",
        "소셜": "Social",
        "토렌트": "Torrent",
        "설정": "Settings",
        "검색": "Search",
        "언어": "Language",
        "표시 언어": "Display language",
        "작업": "Task",
        "도구": "Tools",
        "옵션": "Options",
        "도움말": "Help",
        "보기": "View",
        "대기열 시작": "Start Queue",
        "대기열 중지": "Stop Queue",
        "녹화 중지": "Stop Recording",
        "미리보기": "Preview",
        "출력 폴더 열기": "Open Output Folder",
        "작업과 다운로드 파일 삭제": "Delete Task and Downloaded Files",
        "목록에서만 제거": "Remove from List Only",
        "상세": "More",
        "쿠키 없음": "No cookies"
    ]

    private static let koreanFallback: [String: String] = [
        "About Hitomi Badayo": "Hitomi Badayo 정보",
        "Settings...": "설정...",
        "Start": "시작",
        "Cancel": "중지",
        "Clear": "정리",
        "Settings": "설정",
        "Progress": "진행 상황",
        "History": "작업 기록",
        "Browser": "브라우저",
        "Output Preview": "결과물 미리보기",
        "Stopping recording": "녹화 중지 중",
        "Finalizing recording": "녹화 마무리 중",
        "Recording stopped": "녹화 중지됨",
        "Recording YouTube live": "유튜브 생방송 녹화 중",
        "Downloading with yt-dlp": "yt-dlp로 다운로드 중",
        "Language": "언어",
        "General": "일반",
        "Network": "네트워크",
        "Display": "디스플레이",
        "Plugins": "플러그인",
        "Advanced": "고급",
        "Social": "소셜",
        "Torrent": "토렌트"
    ]
}

extension Notification.Name {
    static let hitomiBadayoInterfaceLanguageDidChange =
        Notification.Name("HitomiBadayoInterfaceLanguageDidChange")
}
