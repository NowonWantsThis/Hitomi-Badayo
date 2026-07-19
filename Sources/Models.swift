import Foundation

enum JobStatus: String, CaseIterable, Codable, Hashable {
    case queued = "Queued"
    case resolving = "Resolving"
    case downloading = "Downloading"
    case finished = "Finished"
    case failed = "Failed"
    case cancelled = "Cancelled"

    var label: String {
        AppLocalization.text(rawValue)
    }
}

enum JobAccessReaction: Equatable {
    case cookies
    case login(provider: String)

    var systemImage: String {
        switch self {
        case .cookies: return "cookie.fill"
        case .login: return "key.fill"
        }
    }

    var helpText: String {
        switch self {
        case .cookies:
            return AppLocalization.text("쿠키를 업데이트하세요")
        case .login(let provider):
            guard !provider.isEmpty else { return AppLocalization.text("로그인") }
            return AppLocalization.format("Sign in to %@", provider)
        }
    }
}

enum JobDisplayReaction: String, Equatable {
    case disgusting

    init?(metadataValue: String?) {
        guard let value = metadataValue?.trimmed.lowercased(), !value.isEmpty else {
            return nil
        }
        self.init(rawValue: value)
    }

    var resourceName: String {
        rawValue
    }

    var accessibilityText: String {
        switch self {
        case .disgusting:
            return "Disgusting task reaction"
        }
    }
}

struct JobStatusColorPalette: Codable, Equatable {
    var queued: String
    var resolving: String
    var downloading: String
    var finished: String
    var failed: String
    var cancelled: String

    static let defaultPalette = JobStatusColorPalette(
        queued: "#6B7280",
        resolving: "#0A84FF",
        downloading: "#007AFF",
        finished: "#34C759",
        failed: "#FF3B30",
        cancelled: "#FF9500"
    )

    func hex(for status: JobStatus) -> String {
        switch status {
        case .queued: return queued
        case .resolving: return resolving
        case .downloading: return downloading
        case .finished: return finished
        case .failed: return failed
        case .cancelled: return cancelled
        }
    }

    mutating func setHex(_ value: String, for status: JobStatus) {
        switch status {
        case .queued: queued = value
        case .resolving: resolving = value
        case .downloading: downloading = value
        case .finished: finished = value
        case .failed: failed = value
        case .cancelled: cancelled = value
        }
    }

    func normalized(onlyWebColors: Bool = false) -> JobStatusColorPalette {
        var palette = self
        for status in JobStatus.allCases {
            let fallback = Self.defaultPalette.hex(for: status)
            let normalized = Self.normalizedHex(hex(for: status), fallback: fallback, onlyWebColors: onlyWebColors)
            palette.setHex(normalized, for: status)
        }
        return palette
    }

    static func normalizedHex(_ value: String, fallback: String? = nil, onlyWebColors: Bool = false) -> String {
        let trimmed = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
        var raw = trimmed.hasPrefix("#") ? String(trimmed.dropFirst()) : trimmed
        if raw.count == 3 {
            raw = raw.map { "\($0)\($0)" }.joined()
        }
        guard raw.count == 6, raw.allSatisfy(\.isHexDigit) else {
            return fallback ?? Self.defaultPalette.downloading
        }
        let red = Int(raw.prefix(2), radix: 16) ?? 0
        let green = Int(raw.dropFirst(2).prefix(2), radix: 16) ?? 0
        let blue = Int(raw.dropFirst(4).prefix(2), radix: 16) ?? 0
        if onlyWebColors {
            return String(
                format: "#%02X%02X%02X",
                webSafeComponent(red),
                webSafeComponent(green),
                webSafeComponent(blue)
            )
        }
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    private static func webSafeComponent(_ value: Int) -> Int {
        let clamped = max(0, min(255, value))
        let lower = (clamped / 51) * 51
        let upper = min(255, lower + 51)
        return (clamped - lower) <= (upper - clamped) ? lower : upper
    }
}

struct PageSelectorItem: Identifiable, Equatable {
    var index: Int
    var page: Int
    var title: String
    var detail: String
    var type: String

    var id: Int { index }
}

enum OutputSubfolderMode: String, CaseIterable, Codable {
    case none
    case site
    case date
    case siteAndDate

    var label: String {
        label(language: AppLocalization.currentLanguage())
    }

    func label(language: AppInterfaceLanguage) -> String {
        switch self {
        case .none: return AppLocalization.text("바로 저장", language: language)
        case .site: return AppLocalization.text("소스별", language: language)
        case .date: return AppLocalization.text("날짜별", language: language)
        case .siteAndDate: return AppLocalization.text("소스 + 날짜", language: language)
        }
    }
}

enum QueueSortMode: String, CaseIterable, Codable {
    case manual
    case title
    case status
    case site
    case progress
    case output

    var label: String {
        switch self {
        case .manual: return AppLocalization.text("수동")
        case .title: return AppLocalization.text("제목")
        case .status: return AppLocalization.text("상태")
        case .site: return AppLocalization.text("사이트")
        case .progress: return AppLocalization.text("진행률")
        case .output: return AppLocalization.text("결과물")
        }
    }
}

enum SearchResultSortMode: String, CaseIterable, Codable {
    case manual
    case title
    case site
    case date
    case pages
    case done

    var label: String {
        switch self {
        case .manual: return AppLocalization.text("Manual")
        case .title: return AppLocalization.text("Title")
        case .site: return AppLocalization.text("Site")
        case .date: return AppLocalization.text("Date")
        case .pages: return AppLocalization.text("Pages")
        case .done: return AppLocalization.text("Done")
        }
    }
}

enum SearchResultKnownFilter: String, CaseIterable, Codable {
    case all
    case notDownloaded
    case downloaded

    var label: String {
        switch self {
        case .all: return AppLocalization.text("All")
        case .notDownloaded: return AppLocalization.text("Not Done")
        case .downloaded: return AppLocalization.text("Done")
        }
    }
}

enum PixivUgoiraFileFormat: String, CaseIterable, Codable {
    case ugoira
    case zip
    case gif
    case webp
    case png

    var label: String {
        switch self {
        case .ugoira: return ".ugoira"
        case .zip: return ".zip"
        case .gif: return ".gif"
        case .webp: return ".webp"
        case .png: return ".png (APNG)"
        }
    }

    var requiresFFmpeg: Bool {
        switch self {
        case .gif, .webp, .png: return true
        case .ugoira, .zip: return false
        }
    }
}

enum YouTubeVideoCodec: String, CaseIterable, Codable, Hashable, Identifiable {
    case avc1
    case vp9
    case av1

    var id: String { rawValue }

    var label: String {
        switch self {
        case .avc1: return "AVC1 (H.264)"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        }
    }

    var compactLabel: String {
        switch self {
        case .avc1: return "AVC1"
        case .vp9: return "VP9"
        case .av1: return "AV1"
        }
    }

    static let originalDefaultPriority: [YouTubeVideoCodec] = [.avc1, .vp9, .av1]

    static let allPriorityOrders: [[YouTubeVideoCodec]] = [
        [.avc1, .vp9, .av1],
        [.avc1, .av1, .vp9],
        [.vp9, .avc1, .av1],
        [.vp9, .av1, .avc1],
        [.av1, .avc1, .vp9],
        [.av1, .vp9, .avc1]
    ]

    static func normalizedPriority(_ codecs: [YouTubeVideoCodec]) -> [YouTubeVideoCodec] {
        var result: [YouTubeVideoCodec] = []
        var seen = Set<YouTubeVideoCodec>()
        for codec in codecs where seen.insert(codec).inserted {
            result.append(codec)
        }
        for codec in originalDefaultPriority where seen.insert(codec).inserted {
            result.append(codec)
        }
        return result
    }

    static func priority(fromStoredValue value: Any?, legacySort: String = "") -> [YouTubeVideoCodec] {
        let rawValues: [String]
        if let values = value as? [String] {
            rawValues = values
        } else if let string = value as? String,
                  let data = string.data(using: .utf8),
                  let values = try? JSONSerialization.jsonObject(with: data) as? [String] {
            rawValues = values
        } else {
            rawValues = []
        }

        let parsed = rawValues.compactMap(codec(from:))
        if !parsed.isEmpty {
            return normalizedPriority(parsed)
        }
        return priority(fromLegacySort: legacySort)
    }

    static func priority(fromLegacySort sort: String) -> [YouTubeVideoCodec] {
        let value = sort.trimmed.lowercased()
        let preferred: YouTubeVideoCodec?
        if value.contains("avc1") || value.contains("h264") || value.contains("h.264") {
            preferred = .avc1
        } else if value.contains("vp9") || value.contains("vp09") {
            preferred = .vp9
        } else if value.contains("av1") || value.contains("av01") {
            preferred = .av1
        } else {
            preferred = nil
        }
        guard let preferred else { return originalDefaultPriority }
        return [preferred] + originalDefaultPriority.filter { $0 != preferred }
    }

    static func priorityLabel(_ codecs: [YouTubeVideoCodec]) -> String {
        normalizedPriority(codecs)
            .map(\.compactLabel)
            .joined(separator: " > ")
    }

    static func ytdlpSortExpression(for codecs: [YouTubeVideoCodec]) -> String {
        let priority = normalizedPriority(codecs)
        let sortFields: String
        if priority == [.vp9, .av1, .avc1] {
            sortFields = "+vcodec:vp9"
        } else if priority == [.vp9, .avc1, .av1] {
            sortFields = "vcodec:vp9"
        } else if priority == [.av1, .avc1, .vp9] {
            sortFields = "vext:mp4,vcodec:av1"
        } else if priority == [.av1, .vp9, .avc1] {
            sortFields = "vcodec:av1"
        } else if priority == [.avc1, .av1, .vp9] {
            sortFields = "vext:mp4,vcodec:avc1"
        } else {
            sortFields = "vcodec:avc1"
        }
        return "res,\(sortFields),fps,br"
    }

    static func codec(from value: String) -> YouTubeVideoCodec? {
        let normalized = value.trimmed.lowercased()
        if normalized == "avc1" || normalized == "avc" || normalized == "h264" || normalized == "h.264" {
            return .avc1
        }
        if normalized == "vp9" || normalized == "vp09" {
            return .vp9
        }
        if normalized == "av1" || normalized == "av01" {
            return .av1
        }
        return nil
    }
}

enum ArchiveFileFormat: String, CaseIterable, Codable {
    case zip
    case cbz

    var label: String {
        switch self {
        case .zip: return "ZIP"
        case .cbz: return "CBZ"
        }
    }

    var fileExtension: String {
        switch self {
        case .zip: return "zip"
        case .cbz: return "cbz"
        }
    }
}

enum SourceArchiveMode: String, CaseIterable, Codable, Identifiable {
    case pass
    case zip
    case cbz

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pass: return AppLocalization.text("통과")
        case .zip: return "ZIP"
        case .cbz: return "CBZ"
        }
    }

    var originalIndex: Int {
        switch self {
        case .pass: return 0
        case .zip: return 1
        case .cbz: return 2
        }
    }

    var archiveFormat: ArchiveFileFormat? {
        switch self {
        case .pass: return nil
        case .zip: return .zip
        case .cbz: return .cbz
        }
    }

    init(originalIndex: Int) {
        switch originalIndex {
        case 1: self = .zip
        case 2: self = .cbz
        default: self = .pass
        }
    }
}

enum ImageConversionFormat: String, CaseIterable, Codable {
    case original
    case jpeg
    case png
    case tiff
    case bmp

    var label: String {
        switch self {
        case .original: return AppLocalization.text("원본")
        case .jpeg: return "JPEG"
        case .png: return "PNG"
        case .tiff: return "TIFF"
        case .bmp: return "BMP"
        }
    }

    var fileExtension: String? {
        switch self {
        case .original: return nil
        case .jpeg: return "jpg"
        case .png: return "png"
        case .tiff: return "tiff"
        case .bmp: return "bmp"
        }
    }
}

enum EHentaiSourceMode: String, CaseIterable, Codable, Identifiable {
    case automatic
    case hitomi
    case original

    var id: String { rawValue }

    var label: String {
        switch self {
        case .automatic: return AppLocalization.text("자동 (Hitomi 우선)")
        case .hitomi: return AppLocalization.text("Hitomi만")
        case .original: return AppLocalization.text("원본 사이트")
        }
    }

    var helpText: String {
        switch self {
        case .automatic:
            return AppLocalization.text("일치하는 Hitomi 갤러리를 먼저 찾고, 없으면 E-Hentai 또는 ExHentai 원본 주소를 사용합니다.")
        case .hitomi:
            return AppLocalization.text("일치하는 Hitomi 갤러리만 사용합니다.")
        case .original:
            return AppLocalization.text("입력한 E-Hentai 또는 ExHentai 주소를 그대로 사용합니다.")
        }
    }
}

enum TaskTagColor: String, CaseIterable, Codable, Identifiable {
    case red
    case orange
    case yellow
    case green
    case blue
    case purple
    case gray

    var id: String { rawValue }

    var label: String {
        switch self {
        case .red: return AppLocalization.text("빨강")
        case .orange: return AppLocalization.text("주황")
        case .yellow: return AppLocalization.text("노랑")
        case .green: return AppLocalization.text("초록")
        case .blue: return AppLocalization.text("파랑")
        case .purple: return AppLocalization.text("보라")
        case .gray: return AppLocalization.text("회색")
        }
    }

    var rgb: (red: UInt8, green: UInt8, blue: UInt8) {
        switch self {
        case .red: return (254, 0, 0)
        case .orange: return (255, 158, 0)
        case .yellow: return (254, 219, 0)
        case .green: return (0, 250, 95)
        case .blue: return (0, 186, 255)
        case .purple: return (245, 82, 230)
        case .gray: return (163, 163, 167)
        }
    }

    static func normalizedRawValues(_ values: [String]) -> [String] {
        var seen = Set<String>()
        return values.compactMap { value in
            let raw = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let compatibleRaw = raw == "cyan" ? TaskTagColor.blue.rawValue : raw
            guard TaskTagColor(rawValue: compatibleRaw) != nil,
                  seen.insert(compatibleRaw).inserted else {
                return nil
            }
            return compatibleRaw
        }
    }
}

enum TaskTagRestartDelay: Int, CaseIterable, Codable, Identifiable {
    case off = 0
    case after24Hours = 86_400
    case after7Days = 604_800

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .off: return AppLocalization.text("아무것도 안 함")
        case .after24Hours: return AppLocalization.text("24 시간 뒤 다시 시작")
        case .after7Days: return AppLocalization.text("7 일 뒤 다시 시작")
        }
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue)
    }
}

enum QueueCompletionAction: String, CaseIterable, Codable {
    case none
    case openDestination
    case quitApp

    var label: String {
        switch self {
        case .none: return AppLocalization.text("아무것도 안 함")
        case .openDestination: return AppLocalization.text("폴더 열기")
        case .quitApp: return AppLocalization.text("앱 종료")
        }
    }
}

struct AppAboutInfo: Codable, Equatable {
    var name: String
    var displayName: String
    var version: String
    var build: String
    var bundleIdentifier: String
    var architecture: String
    var minimumSystemVersion: String
    var operatingSystemVersion: String
    var latestVersionText: String
    var developedBy: String
    var licenseSummary: String
    var historySummary: String

    var currentVersionText: String {
        version
    }
}

enum OutputPreviewMode: String, CaseIterable, Codable, Identifiable {
    case paged
    case scroll
    case files

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paged: return AppLocalization.text("Paged")
        case .scroll: return AppLocalization.text("Scroll")
        case .files: return AppLocalization.text("Files")
        }
    }

    var systemImage: String {
        switch self {
        case .paged: return "rectangle.portrait"
        case .scroll: return "rectangle.stack"
        case .files: return "list.bullet.rectangle"
        }
    }
}

enum OutputPreviewMediaType: String, Codable, Sendable {
    case image
    case video
    case audio
    case document
    case file

    var label: String {
        switch self {
        case .image: return AppLocalization.text("Image")
        case .video: return AppLocalization.text("Video")
        case .audio: return AppLocalization.text("Audio")
        case .document: return AppLocalization.text("Document")
        case .file: return AppLocalization.text("File")
        }
    }

    var systemImage: String {
        switch self {
        case .image: return "photo"
        case .video: return "film"
        case .audio: return "waveform"
        case .document: return "doc.text"
        case .file: return "doc"
        }
    }
}

struct OutputPreviewFile: Identifiable, Equatable, Sendable {
    var originalIndex: Int
    var relativePath: String
    var displayPath: String
    var containerPath: String
    var byteCount: Int
    var mediaType: OutputPreviewMediaType
    var isArchiveEntry: Bool
    var modificationTime: TimeInterval = 0

    var id: Int { originalIndex }
    var filename: String { URL(fileURLWithPath: relativePath).lastPathComponent }
    var isImage: Bool { mediaType == .image }
}

enum AppAppearanceMode: String, CaseIterable, Codable {
    case system
    case light
    case dark

    var label: String {
        switch self {
        case .system: return AppLocalization.text("시스템")
        case .light: return AppLocalization.text("라이트")
        case .dark: return AppLocalization.text("다크")
        }
    }
}

enum QueueViewMode: String, CaseIterable, Codable {
    case list
    case icon

    var label: String {
        switch self {
        case .list: return AppLocalization.text("목록")
        case .icon: return AppLocalization.text("아이콘")
        }
    }

    var systemImage: String {
        switch self {
        case .list: return "list.bullet"
        case .icon: return "square.grid.3x3"
        }
    }
}

enum QueueThumbnailScale: Int, CaseIterable, Codable {
    case percent75
    case percent100
    case percent150
    case percent200
    case percent300
    case percent450

    var factor: Double {
        switch self {
        case .percent75: return 0.75
        case .percent100: return 1
        case .percent150: return 1.5
        case .percent200: return 2
        case .percent300: return 3
        case .percent450: return 4.5
        }
    }

    var label: String {
        "\(Int((factor * 100).rounded()))%"
    }

    static let defaultScale: QueueThumbnailScale = .percent100

    static func normalized(index: Int) -> QueueThumbnailScale {
        QueueThumbnailScale(rawValue: index) ?? defaultScale
    }
}

enum AppUIScale: String, CaseIterable, Codable {
    case percent70 = "70"
    case percent80 = "80"
    case percent90 = "90"
    case percent100 = "100"
    case percent110 = "110"
    case percent125 = "125"
    case percent140 = "140"

    var label: String {
        "\(percent)%"
    }

    var percent: Int {
        Int(rawValue) ?? 100
    }

    var factor: Double {
        Double(percent) / 100
    }

    static let defaultScale: AppUIScale = .percent100

    static func normalized(rawValue: String?) -> AppUIScale {
        guard let rawValue else { return defaultScale }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "%", with: "")
        guard !normalized.isEmpty else { return defaultScale }
        if let exact = allCases.first(where: { $0.rawValue == normalized }) {
            return exact
        }
        switch normalized {
        case "compact", "small":
            return .percent80
        case "smaller":
            return .percent70
        case "default", "normal", "standard", "medium":
            return .percent100
        case "large":
            return .percent125
        case "larger", "extra large", "extra-large", "xlarge", "xl":
            return .percent140
        default:
            guard let numeric = Double(normalized.replacingOccurrences(of: "x", with: "")) else {
                return defaultScale
            }
            let percent = numeric <= 3 ? Int((numeric * 100).rounded()) : Int(numeric.rounded())
            return allCases.min {
                abs($0.percent - percent) < abs($1.percent - percent)
            } ?? defaultScale
        }
    }
}

enum IncompleteRetryDelay: Int, CaseIterable, Codable, Identifiable {
    case minutes5 = 5
    case minutes10 = 10
    case minutes30 = 30
    case minutes60 = 60

    var id: Int { rawValue }

    var label: String {
        label(language: AppLocalization.currentLanguage())
    }

    func label(language: AppInterfaceLanguage) -> String {
        AppLocalization.format("%@ min", language: language, String(rawValue))
    }

    var seconds: TimeInterval {
        TimeInterval(rawValue * 60)
    }

    static let defaultDelay: IncompleteRetryDelay = .minutes5

    static func normalized(minutes: Int) -> IncompleteRetryDelay {
        IncompleteRetryDelay(rawValue: minutes) ?? defaultDelay
    }

    static func normalized(originalIndex: Int) -> IncompleteRetryDelay {
        allCases.indices.contains(originalIndex) ? allCases[originalIndex] : defaultDelay
    }
}

enum AppInterfaceFontSize: String, CaseIterable, Codable {
    case compact = "12"
    case regular = "13"
    case comfortable = "15"
    case large = "17"

    var label: String {
        "\(rawValue) pt"
    }

    var pointSize: Double {
        Double(rawValue) ?? Self.defaultSize.pointSize
    }

    static let defaultSize: AppInterfaceFontSize = .regular

    static func normalized(rawValue: String?) -> AppInterfaceFontSize {
        guard let rawValue else { return defaultSize }
        let normalized = rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "pt", with: "")
            .replacingOccurrences(of: "px", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return defaultSize }
        if let exact = allCases.first(where: { $0.rawValue == normalized }) {
            return exact
        }
        switch normalized {
        case "compact", "small", "smaller":
            return .compact
        case "default", "regular", "normal", "standard", "medium":
            return .regular
        case "comfortable", "larger":
            return .comfortable
        case "large", "extra large", "extra-large", "xlarge", "xl":
            return .large
        default:
            guard let numeric = Double(normalized) else {
                return defaultSize
            }
            return allCases.min {
                abs($0.pointSize - numeric) < abs($1.pointSize - numeric)
            } ?? defaultSize
        }
    }
}

enum SettingsWindowCategory: String, CaseIterable, Codable, Hashable, Identifiable {
    case general
    case network
    case live
    case theme
    case archive
    case plugins
    case advanced
    case hitomi
    case pixiv
    case youtube
    case social
    case torrent

    var id: String { rawValue }

    var label: String {
        switch self {
        case .general: return AppLocalization.text("일반")
        case .network: return AppLocalization.text("네트워크")
        case .live: return AppLocalization.text("녹화")
        case .theme: return AppLocalization.text("디스플레이")
        case .archive: return AppLocalization.text("압축")
        case .plugins: return AppLocalization.text("플러그인")
        case .advanced: return AppLocalization.text("고급")
        case .hitomi: return "Hitomi / E(x)Hentai"
        case .pixiv: return "Pixiv"
        case .youtube: return "YouTube"
        case .social: return AppLocalization.text("소셜")
        case .torrent: return AppLocalization.text("토렌트")
        }
    }

    var detail: String {
        switch self {
        case .general:
            return AppLocalization.text("저장 폴더, 이름, 대기열")
        case .network:
            return AppLocalization.text("프록시, 쿠키, HTTP API")
        case .live:
            return AppLocalization.text("녹화 및 HLS")
        case .theme:
            return AppLocalization.text("화면 모드, 배율, 색상")
        case .archive:
            return AppLocalization.text("ZIP, CBZ, 이미지 출력")
        case .plugins:
            return AppLocalization.text("스크립트 및 사이트 규칙")
        case .advanced:
            return AppLocalization.text("알림, 단축키, 도구")
        case .hitomi:
            return AppLocalization.text("WebP, 소스, 태그, 메타데이터")
        case .pixiv:
            return AppLocalization.text("우고이라 출력")
        case .youtube:
            return AppLocalization.text("yt-dlp 동영상 옵션")
        case .social:
            return "Instagram, X, Twitch"
        case .torrent:
            return AppLocalization.text("aria2 옵션")
        }
    }

    private var legacySearchText: String {
        switch self {
        case .general: return "General folder names queue"
        case .network: return "Network proxy cookies HTTP API"
        case .live: return "Live recording HLS"
        case .theme: return "Theme appearance scale colors display"
        case .archive: return "Zip Archive CBZ image output compression"
        case .plugins: return "Plugin scripts site rules"
        case .advanced: return "Advanced alerts shortcuts tools"
        case .hitomi: return "Hitomi E-Hentai ExHentai WebP tags metadata"
        case .pixiv: return "Pixiv ugoira output"
        case .youtube: return "YouTube yt-dlp video options"
        case .social: return "Social Instagram Twitter X Twitch"
        case .torrent: return "Torrent aria2 options"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "gearshape"
        case .network: return "network"
        case .live: return "dot.radiowaves.left.and.right"
        case .theme: return "paintbrush"
        case .archive: return "archivebox"
        case .plugins: return "puzzlepiece.extension"
        case .advanced: return "slider.horizontal.3"
        case .hitomi: return "photo.on.rectangle"
        case .pixiv: return "p.circle"
        case .youtube: return "play.rectangle"
        case .social: return "person.2"
        case .torrent: return "arrow.down.circle"
        }
    }

    var searchText: String {
        "\(label) \(detail) \(rawValue) \(legacySearchText)"
    }
}

struct ActivityLogEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp = Date()
    var category: String
    var message: String
}

struct OutputDirectoryEntry: Identifiable, Codable, Equatable {
    var path: String
    var scope: String
    var queueCount: Int
    var historyCount: Int
    var sampleTitle: String
    var exists: Bool
    var isDirectory: Bool

    var id: String { path }
}

struct QueueGroup: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var comment: String
    var isExpanded: Bool
    var anchorJobID: UUID?
    var originalUID: String
    var isPinned: Bool
    var tags: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case comment
        case isExpanded
        case anchorJobID
        case originalUID
        case isPinned
        case tags
    }

    init(
        id: UUID = UUID(),
        name: String,
        comment: String = "",
        isExpanded: Bool = true,
        anchorJobID: UUID? = nil,
        originalUID: String = "",
        isPinned: Bool = false,
        tags: [String] = []
    ) {
        self.id = id
        self.name = name
        self.comment = comment
        self.isExpanded = isExpanded
        self.anchorJobID = anchorJobID
        self.originalUID = originalUID
        self.isPinned = isPinned
        self.tags = TaskTagColor.normalizedRawValues(tags)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Group"
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
        anchorJobID = try container.decodeIfPresent(UUID.self, forKey: .anchorJobID)
        originalUID = try container.decodeIfPresent(String.self, forKey: .originalUID) ?? ""
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        tags = TaskTagColor.normalizedRawValues(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
    }
}

enum QueueListEntry: Identifiable, Equatable {
    enum ID: Hashable {
        case group(UUID)
        case job(UUID)
    }

    case group(QueueGroup)
    case job(DownloadJob)

    var id: ID {
        switch self {
        case .group(let group): return .group(group.id)
        case .job(let job): return .job(job.id)
        }
    }
}

struct DownloadJob: Identifiable, Codable, Equatable {
    var id = UUID()
    var source: String
    var title: String
    var status: JobStatus = .queued
    var progress: Double = 0
    var completed: Int = 0
    var total: Int = 0
    var message: String = ""
    var outputPath: String = ""
    var metadata: [String: String] = [:]
    var tags: [String] = []
    var comment: String = ""
    var rangeExpression: String = ""
    var isPinned: Bool = false
    var isLocked: Bool = false
    var resolvedFilenames: [String] = []
    var resolvedURLs: [String] = []
    var messageHistory: [String] = []

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case title
        case status
        case progress
        case completed
        case total
        case message
        case outputPath
        case metadata
        case tags
        case comment
        case rangeExpression
        case isPinned
        case isLocked
        case resolvedFilenames
        case resolvedURLs
        case messageHistory
    }

    init(
        id: UUID = UUID(),
        source: String,
        title: String,
        status: JobStatus = .queued,
        progress: Double = 0,
        completed: Int = 0,
        total: Int = 0,
        message: String = "",
        outputPath: String = "",
        metadata: [String: String] = [:],
        tags: [String] = [],
        comment: String = "",
        rangeExpression: String = "",
        isPinned: Bool = false,
        isLocked: Bool = false,
        resolvedFilenames: [String] = [],
        resolvedURLs: [String] = [],
        messageHistory: [String] = []
    ) {
        self.id = id
        self.source = source
        self.title = title
        self.status = status
        self.progress = progress
        self.completed = completed
        self.total = total
        self.message = message
        self.outputPath = outputPath
        var normalizedMetadata = metadata
        var normalizedTags = TaskTagColor.normalizedRawValues(tags)
        if normalizedTags.isEmpty,
           let legacyColor = normalizedMetadata["label_color"],
           let migrated = TaskTagColor.normalizedRawValues([legacyColor]).first {
            normalizedTags = [migrated]
            normalizedMetadata.removeValue(forKey: "label_color")
        }
        self.metadata = normalizedMetadata
        self.tags = normalizedTags
        self.comment = comment
        self.rangeExpression = rangeExpression
        self.isPinned = isPinned
        self.isLocked = isLocked
        self.resolvedFilenames = Self.normalizedInfoValues(resolvedFilenames)
        self.resolvedURLs = Self.normalizedInfoValues(resolvedURLs)
        self.messageHistory = Self.normalizedInfoValues(messageHistory)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try container.decode(String.self, forKey: .source)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? source
        status = try container.decodeIfPresent(JobStatus.self, forKey: .status) ?? .queued
        progress = try container.decodeIfPresent(Double.self, forKey: .progress) ?? 0
        completed = try container.decodeIfPresent(Int.self, forKey: .completed) ?? 0
        total = try container.decodeIfPresent(Int.self, forKey: .total) ?? 0
        message = try container.decodeIfPresent(String.self, forKey: .message) ?? ""
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath) ?? ""
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
        tags = TaskTagColor.normalizedRawValues(
            try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        )
        if tags.isEmpty,
           let legacyColor = metadata["label_color"],
           let migrated = TaskTagColor.normalizedRawValues([legacyColor]).first {
            tags = [migrated]
            metadata.removeValue(forKey: "label_color")
        }
        comment = try container.decodeIfPresent(String.self, forKey: .comment) ?? ""
        rangeExpression = try container.decodeIfPresent(String.self, forKey: .rangeExpression) ?? ""
        isPinned = try container.decodeIfPresent(Bool.self, forKey: .isPinned) ?? false
        isLocked = try container.decodeIfPresent(Bool.self, forKey: .isLocked) ?? false
        resolvedFilenames = Self.normalizedInfoValues(
            try container.decodeIfPresent([String].self, forKey: .resolvedFilenames) ?? []
        )
        resolvedURLs = Self.normalizedInfoValues(
            try container.decodeIfPresent([String].self, forKey: .resolvedURLs) ?? []
        )
        messageHistory = Self.normalizedInfoValues(
            try container.decodeIfPresent([String].self, forKey: .messageHistory) ?? []
        )
    }

    mutating func recordMessage(_ value: String) {
        let normalized = value.trimmed
        guard !normalized.isEmpty, messageHistory.last != normalized else { return }
        messageHistory.append(normalized)
    }

    static func normalizedInfoValues(_ values: [String]) -> [String] {
        values.compactMap { value in
            let normalized = value.trimmed
            return normalized.isEmpty ? nil : normalized
        }
    }
}

struct URLBookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var url: String
    var createdAt: Date
    var tags: [String]
    var note: String

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case url
        case createdAt
        case tags
        case note
    }

    init(id: UUID, title: String, url: String, createdAt: Date, tags: [String] = [], note: String = "") {
        self.id = id
        self.title = title
        self.url = url
        self.createdAt = createdAt
        self.tags = tags
        self.note = note
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        url = try container.decode(String.self, forKey: .url)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        note = try container.decodeIfPresent(String.self, forKey: .note) ?? ""
    }
}

struct DownloadHistoryEntry: Identifiable, Codable, Equatable {
    var id: UUID
    var source: String
    var normalizedSource: String
    var title: String
    var outputPath: String
    var completedAt: Date
    var metadata: [String: String]

    enum CodingKeys: String, CodingKey {
        case id
        case source
        case normalizedSource
        case title
        case outputPath
        case completedAt
        case metadata
    }

    init(
        id: UUID = UUID(),
        source: String,
        normalizedSource: String,
        title: String,
        outputPath: String,
        completedAt: Date,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.source = source
        self.normalizedSource = normalizedSource
        self.title = title
        self.outputPath = outputPath
        self.completedAt = completedAt
        self.metadata = metadata
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        source = try container.decode(String.self, forKey: .source)
        normalizedSource = try container.decodeIfPresent(String.self, forKey: .normalizedSource) ?? URLIdentity.normalize(source)
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? source
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath) ?? ""
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt) ?? Date()
        metadata = try container.decodeIfPresent([String: String].self, forKey: .metadata) ?? [:]
    }
}

struct DuplicateImageGroup: Identifiable, Codable, Equatable {
    var hash: String
    var byteCount: Int64
    var files: [String]
    var width: Int?
    var height: Int?
    var minByteCount: Int64? = nil
    var maxByteCount: Int64? = nil
    var similarityPercent: Int? = nil

    var id: String {
        hash
    }
}

struct OutputFileStatistics: Equatable {
    var fileCount: Int = 0
    var directoryCount: Int = 0
    var byteCount: Int64 = 0
    var skippedPathAnalysisCount: Int = 0
}

struct NetworkTrafficSample: Equatable {
    var timestamp: Date
    var byteCount: UInt64
}

enum OutputDeletionCandidateKind: String, Equatable {
    case folder
    case file
    case archive

    var label: String {
        switch self {
        case .folder: return AppLocalization.text("Folder")
        case .file: return AppLocalization.text("File")
        case .archive: return AppLocalization.text("Archive")
        }
    }
}

struct OutputDeletionCandidate: Identifiable, Equatable {
    var path: String
    var kind: OutputDeletionCandidateKind

    var id: String {
        path
    }

    var filename: String {
        URL(fileURLWithPath: path).lastPathComponent
    }

    var displayLabel: String {
        "\(kind.label): \(filename)"
    }
}

struct OutputMoveItem: Equatable {
    var originalPath: String
    var movedPath: String
    var kind: OutputDeletionCandidateKind
}

struct OutputMoveResult: Equatable {
    var items: [OutputMoveItem]
    var primaryOutputPath: String?
}

struct OutputImageConversionItem: Equatable, Sendable {
    var originalPath: String
    var convertedPath: String
}

struct OutputImageConversionResult: Equatable, Sendable {
    var items: [OutputImageConversionItem]
    var unchangedCount: Int
    var primaryOutputPath: String?
}

struct ExternalToolStatus: Identifiable, Equatable {
    var name: String
    var configuredPath: String
    var resolvedPath: String
    var isAvailable: Bool

    var id: String {
        name
    }
}

struct DiskSpaceStatus: Equatable {
    var path: String
    var availableByteCount: Int64?
    var totalByteCount: Int64?
    var estimatedRequiredByteCount: Int64
    var warning: String
    var pathAnalysisSkipped: Bool = false

    var hasWarning: Bool {
        !warning.isEmpty
    }
}

struct AppStatistics: Equatable {
    var generatedAt: Date
    var appStartedAt: Date
    var appUptimeSeconds: TimeInterval
    var appName: String
    var appVersion: String
    var appBuild: String
    var bundleIdentifier: String
    var minimumSystemVersion: String
    var operatingSystemVersion: String
    var applicationSupportPath: String
    var userDataPath: String
    var totalJobs: Int
    var queuedJobs: Int
    var resolvingJobs: Int
    var downloadingJobs: Int
    var finishedJobs: Int
    var failedJobs: Int
    var cancelledJobs: Int
    var pinnedJobs: Int
    var lockedJobs: Int
    var historyCount: Int
    var bookmarkCount: Int
    var queueFilterBookmarkCount: Int
    var siteRuleCount: Int
    var enabledSiteRuleCount: Int
    var searchProviderCount: Int
    var duplicateGroupCount: Int
    var duplicateExtraFileCount: Int
    var outputRootPath: String
    var outputPathCount: Int
    var outputFileCount: Int
    var outputDirectoryCount: Int
    var outputByteCount: Int64
    var outputPathAnalysisSkippedCount: Int
    var destinationAvailableByteCount: Int64?
    var destinationTotalByteCount: Int64?
    var estimatedQueuedByteCount: Int64
    var destinationPathAnalysisSkipped: Bool
    var diskSpaceWarning: String
    var autoRemoveFinishedJobs: Bool
    var autoRemoveHookCommand: String
    var autoRemoveHookStatus: String
    var showDownloadDate: Bool
    var numberPlaylistFiles: Bool
    var uiScale: String
    var jobConcurrency: Int
    var fileConcurrency: Int
    var publicIPStatus: String
    var youtubeDownloadThumbnail: Bool
    var youtubeReversePlaylist: Bool
    var youtubeUseUploadDateForFileModificationTime: Bool
    var youtubeDownloadAutoSubtitles: Bool
    var youtubeSubtitleLanguages: String
    var youtubeEmbedChapters: Bool
    var youtubeVideoCodecSort: String
    var youtubePreferEnhancedBitrate: Bool
    var youtubePreferredResolution: String
    var youtubePreferredAudioLanguage: String
    var downloadSpeedBytesPerSecond: Int64?
    var downloadedSinceLaunchByteCount: Int64?
    var uploadSpeedBytesPerSecond: Int64?
    var aria2MaxDownloadLimit: String
    var aria2MaxUploadLimit: String
    var aria2SeedTimeMinutes: String
    var aria2SeedRatio: String
    var aria2AnonymousMode: Bool
    var httpAPIEnabled: Bool
    var clipboardMonitorEnabled: Bool
    var notifyWhenJobCompletes: Bool
    var notifyWhenQueueCompletes: Bool
    var playSoundWhenJobCompletes: Bool
    var playSoundOnClipboardAdd: Bool
    var queueCompletionAction: String
    var queueCompletionActionStatus: String
    var preventSleepWhileDownloading: Bool
    var sleepPreventionActive: Bool
    var historyEnabled: Bool
    var externalTools: [ExternalToolStatus]

    var activeJobs: Int {
        resolvingJobs + downloadingJobs
    }

    var queueActiveFraction: Double {
        guard totalJobs > 0 else { return 0 }
        return min(1, max(0, Double(activeJobs) / Double(totalJobs)))
    }

    var queueCompletedFraction: Double {
        guard totalJobs > 0 else { return 0 }
        return min(1, max(0, Double(finishedJobs) / Double(totalJobs)))
    }

    var destinationUsedFraction: Double? {
        guard let total = destinationTotalByteCount,
              let available = destinationAvailableByteCount,
              total > 0,
              available >= 0 else {
            return nil
        }
        return min(1, max(0, Double(total - min(available, total)) / Double(total)))
    }

    static func speedFraction(_ byteCount: Int64?, softLimitBytesPerSecond: Int64 = 10 * 1024 * 1024) -> Double {
        guard let byteCount, softLimitBytesPerSecond > 0 else { return 0 }
        return min(1, max(0, Double(byteCount) / Double(softLimitBytesPerSecond)))
    }
}

struct FloatingMonitorSnapshot: Equatable {
    var isRunning: Bool
    var totalJobs: Int
    var activeJobs: Int
    var finishedJobs: Int
    var failedJobs: Int
    var cancelledJobs: Int
    var progressFraction: Double
    var completedUnits: Int
    var totalUnits: Int
    var downloadSpeedBytesPerSecond: Int64?
    var uploadSpeedBytesPerSecond: Int64?

    var percent: Int {
        Int((min(1, max(0, progressFraction)) * 100).rounded())
    }

    var stateLabel: String {
        if totalJobs == 0 {
            return AppLocalization.text("No tasks")
        }
        return AppLocalization.text(isRunning ? "Queue running" : "Queue idle")
    }

    var statusLine: String {
        guard totalJobs > 0 else { return AppLocalization.text("No tasks") }
        return AppLocalization.format(
            "%@%% [%@/%@] · %@ active · %@/%@ finished",
            String(percent),
            String(completedUnits),
            String(max(1, totalUnits)),
            String(activeJobs),
            String(finishedJobs),
            String(totalJobs)
        )
    }
}

enum TextViewerEntryKind: String, Codable, Equatable {
    case file
    case message

    var label: String {
        switch self {
        case .file: return AppLocalization.text("File")
        case .message: return AppLocalization.text("Task Messages")
        }
    }
}

struct TextViewerEntry: Identifiable, Equatable {
    var id: String
    var jobID: UUID
    var fileIndex: Int?
    var kind: TextViewerEntryKind
    var title: String
    var source: String
    var status: JobStatus
    var displayName: String
    var detail: String
    var byteCount: Int

    var searchText: String {
        "\(title) \(source) \(status.rawValue) \(displayName) \(detail) \(kind.label)"
    }
}

struct TextViewerDocument: Equatable {
    var entry: TextViewerEntry?
    var text: String
    var bytesRead: Int
    var byteCount: Int
    var truncated: Bool
    var errorMessage: String?

    var isEmpty: Bool {
        text.isEmpty && errorMessage == nil
    }
}

enum SiteRuleHandler: String, Codable, CaseIterable {
    case ytdlp = "yt-dlp"
    case customCommand = "command"
    case headers = "headers"
}

enum SiteArchiveMode: String, Codable, CaseIterable {
    case `default`
    case zip
    case cbz
    case none

    var label: String {
        switch self {
        case .default: return AppLocalization.text("기본값")
        case .zip: return "ZIP"
        case .cbz: return "CBZ"
        case .none: return AppLocalization.text("압축 안 함")
        }
    }

    var archiveFormat: ArchiveFileFormat? {
        switch self {
        case .zip:
            return .zip
        case .cbz:
            return .cbz
        case .default, .none:
            return nil
        }
    }

    var archives: Bool {
        archiveFormat != nil
    }
}

struct SiteRule: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var hostSuffix: String
    var urlPattern: String? = nil
    var handler: SiteRuleHandler
    var commandTemplate: String? = nil
    var refererTemplate: String? = nil
    var userAgent: String? = nil
    var environment: [String: String] = [:]
    var options: [String: String] = [:]
    var workingDirectoryTemplate: String? = nil
    var archiveMode: SiteArchiveMode = .default
    var deleteOriginalAfterArchiving: Bool = false
    var isEnabled: Bool = true
    var createdAt: Date

    init(
        id: UUID,
        name: String,
        hostSuffix: String,
        urlPattern: String? = nil,
        handler: SiteRuleHandler,
        commandTemplate: String? = nil,
        refererTemplate: String? = nil,
        userAgent: String? = nil,
        environment: [String: String] = [:],
        options: [String: String] = [:],
        workingDirectoryTemplate: String? = nil,
        archiveMode: SiteArchiveMode = .default,
        deleteOriginalAfterArchiving: Bool = false,
        isEnabled: Bool = true,
        createdAt: Date
    ) {
        self.id = id
        self.name = name
        self.hostSuffix = hostSuffix
        self.urlPattern = urlPattern
        self.handler = handler
        self.commandTemplate = commandTemplate
        self.refererTemplate = refererTemplate
        self.userAgent = userAgent
        self.environment = DownloadMetadata.clean(environment)
        self.options = DownloadMetadata.clean(options)
        self.workingDirectoryTemplate = workingDirectoryTemplate?.trimmed.isEmpty == false ? workingDirectoryTemplate?.trimmed : nil
        self.archiveMode = archiveMode
        self.deleteOriginalAfterArchiving = deleteOriginalAfterArchiving && archiveMode.archives
        self.isEnabled = isEnabled
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case hostSuffix
        case urlPattern
        case handler
        case commandTemplate
        case refererTemplate
        case userAgent
        case environment
        case options
        case workingDirectoryTemplate
        case archiveMode
        case deleteOriginalAfterArchiving
        case isEnabled
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        hostSuffix = try container.decode(String.self, forKey: .hostSuffix)
        urlPattern = try container.decodeIfPresent(String.self, forKey: .urlPattern)
        handler = try container.decode(SiteRuleHandler.self, forKey: .handler)
        commandTemplate = try container.decodeIfPresent(String.self, forKey: .commandTemplate)
        refererTemplate = try container.decodeIfPresent(String.self, forKey: .refererTemplate)
        userAgent = try container.decodeIfPresent(String.self, forKey: .userAgent)
        environment = DownloadMetadata.clean(try container.decodeIfPresent([String: String].self, forKey: .environment) ?? [:])
        options = DownloadMetadata.clean(try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:])
        let workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectoryTemplate)?.trimmed ?? ""
        workingDirectoryTemplate = workingDirectory.isEmpty ? nil : workingDirectory
        archiveMode = try container.decodeIfPresent(SiteArchiveMode.self, forKey: .archiveMode) ?? .default
        deleteOriginalAfterArchiving = (try container.decodeIfPresent(Bool.self, forKey: .deleteOriginalAfterArchiving) ?? false) && archiveMode.archives
        isEnabled = try container.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    var matchKey: String {
        "\(Self.normalizedHostSuffix(hostSuffix))|\(Self.normalizedURLPattern(urlPattern) ?? "")"
    }

    var matchSpecificity: Int {
        Self.normalizedHostSuffix(hostSuffix).count + (Self.normalizedURLPattern(urlPattern)?.count ?? 0)
    }

    func matches(_ url: URL) -> Bool {
        guard isEnabled else { return false }
        guard let host = url.host?.lowercased() else { return false }
        let suffix = Self.normalizedHostSuffix(hostSuffix)
        guard !suffix.isEmpty, host == suffix || host.hasSuffix("." + suffix) else { return false }
        guard let pattern = Self.normalizedURLPattern(urlPattern) else { return true }
        return Self.wildcardMatches(pattern: pattern, value: Self.pathAndQuery(from: url))
    }

    static func normalizedHostSuffix(_ host: String) -> String {
        var value = host.trimmed.lowercased()
        if let url = URL(string: value), let parsedHost = url.host {
            value = parsedHost.lowercased()
        }
        value = value.trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard value.contains("."), !value.contains("/") else { return "" }
        return value
    }

    static func normalizedURLPattern(_ pattern: String?) -> String? {
        guard var value = pattern?.trimmed, !value.isEmpty else { return nil }

        if let parsed = URL(string: value), parsed.scheme != nil || parsed.host != nil {
            value = pathAndQuery(from: parsed)
        }

        if !value.hasPrefix("/") && !value.hasPrefix("*") {
            value = "/" + value
        }
        return value.isEmpty ? nil : value
    }

    static func pathAndQuery(from url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path
        guard let query = url.query, !query.isEmpty else { return path }
        return "\(path)?\(query)"
    }

    private static func wildcardMatches(pattern: String, value: String) -> Bool {
        var patternIndex = pattern.startIndex
        var valueIndex = value.startIndex
        var starIndex: String.Index?
        var valueCheckpoint = value.startIndex

        while valueIndex < value.endIndex {
            if patternIndex < pattern.endIndex && pattern[patternIndex] == "*" {
                starIndex = patternIndex
                patternIndex = pattern.index(after: patternIndex)
                valueCheckpoint = valueIndex
            } else if patternIndex < pattern.endIndex && pattern[patternIndex] == value[valueIndex] {
                patternIndex = pattern.index(after: patternIndex)
                valueIndex = value.index(after: valueIndex)
            } else if let starIndex {
                patternIndex = pattern.index(after: starIndex)
                guard valueCheckpoint < value.endIndex else { return false }
                valueCheckpoint = value.index(after: valueCheckpoint)
                valueIndex = valueCheckpoint
            } else {
                return false
            }
        }

        while patternIndex < pattern.endIndex && pattern[patternIndex] == "*" {
            patternIndex = pattern.index(after: patternIndex)
        }
        return patternIndex == pattern.endIndex
    }
}

struct SiteRulePackage: Codable, Equatable {
    var format: String = "HitomiBadayoSiteRules"
    var version: Int = 1
    var exportedAt: Date = Date()
    var rules: [SiteRule]
}

struct HTTPRequestOptions: Equatable {
    var referer: String? = nil
    var userAgent: String? = nil

    var isEmpty: Bool {
        (referer?.trimmed.isEmpty ?? true) && (userAgent?.trimmed.isEmpty ?? true)
    }
}

struct SearchProvider: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var urlTemplate: String
    var createdAt: Date

    static var defaultProviders: [SearchProvider] {
        [
            SearchProvider(
                id: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!,
                name: "Hitomi",
                urlTemplate: "https://hitomi.la/search.html?{query}",
                createdAt: Date(timeIntervalSince1970: 0)
            ),
            SearchProvider(
                id: UUID(uuidString: "22222222-2222-4222-8222-222222222222")!,
                name: "YouTube",
                urlTemplate: "https://www.youtube.com/results?search_query={query}",
                createdAt: Date(timeIntervalSince1970: 0)
            )
        ]
    }
}

enum HitomiAdvancedSearchType: String, CaseIterable, Codable, Hashable, Identifiable {
    case doujinshi
    case manga
    case artistCG = "artistcg"
    case gameCG = "gamecg"
    case anime
    case imageSet = "imageset"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .doujinshi: return "Doujinshi"
        case .manga: return "Manga"
        case .artistCG: return "Artist CG"
        case .gameCG: return "Game CG"
        case .anime: return "Anime"
        case .imageSet: return "Image Set"
        }
    }

    var queryToken: String {
        "type:\(rawValue)"
    }
}

enum HitomiAdvancedLanguagePreset: String, CaseIterable, Codable, Hashable, Identifiable {
    case all
    case korean
    case japanese
    case english
    case chinese
    case spanish
    case notAvailable
    case koreanAndNotAvailable
    case excludeKorean

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return AppLocalization.text("All")
        case .korean: return AppLocalization.text("Korean")
        case .japanese: return AppLocalization.text("Japanese")
        case .english: return AppLocalization.text("English")
        case .chinese: return AppLocalization.text("Chinese")
        case .spanish: return AppLocalization.text("Spanish")
        case .notAvailable: return "N/A"
        case .koreanAndNotAvailable: return AppLocalization.text("Korean + N/A")
        case .excludeKorean: return AppLocalization.text("-Korean")
        }
    }

    var queryTokens: [String] {
        switch self {
        case .all: return []
        case .korean: return ["language:korean"]
        case .japanese: return ["language:japanese"]
        case .english: return ["language:english"]
        case .chinese: return ["language:chinese"]
        case .spanish: return ["language:spanish"]
        case .notAvailable: return ["language:n/a"]
        case .koreanAndNotAvailable: return ["language:korean", "language:n/a"]
        case .excludeKorean: return ["-language:korean"]
        }
    }
}

struct SearchBookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var providerID: UUID?
    var providerName: String
    var query: String
    var createdAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        providerID: UUID?,
        providerName: String,
        query: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.providerID = providerID
        self.providerName = providerName
        self.query = query
        self.createdAt = createdAt
    }
}

enum MetadataFinderField: String, CaseIterable, Codable, Identifiable {
    case artist
    case group
    case series
    case character
    case tag

    var id: String { rawValue }

    var label: String {
        switch self {
        case .artist: return AppLocalization.text("Artist")
        case .group: return AppLocalization.text("Group")
        case .series: return AppLocalization.text("Series")
        case .character: return AppLocalization.text("Character")
        case .tag: return AppLocalization.text("Tag")
        }
    }

    var originalLabel: String {
        switch self {
        case .artist: return "작가"
        case .group: return "그룹"
        case .series: return "시리즈"
        case .character: return "캐릭터"
        case .tag: return "태그"
        }
    }
}

enum MetadataFinderMode: String, CaseIterable, Codable, Identifiable {
    case plain
    case regex
    case fuzzy

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plain: return AppLocalization.text("Default")
        case .regex: return AppLocalization.text("Regex")
        case .fuzzy: return AppLocalization.text("Fuzzy")
        }
    }
}

struct MetadataFinderResult: Identifiable, Codable, Equatable {
    var field: MetadataFinderField
    var value: String
    var queueCount: Int
    var historyCount: Int
    var sampleTitle: String
    var sampleSource: String
    var score: Int?

    var id: String {
        "\(field.rawValue)|\(value.lowercased())"
    }

    var totalCount: Int {
        queueCount + historyCount
    }
}

enum MetadataAnalysisField: String, CaseIterable, Codable, Identifiable {
    case artist
    case group
    case type
    case series
    case character
    case tag
    case language

    var id: String { rawValue }

    var label: String {
        switch self {
        case .artist: return AppLocalization.text("Artist")
        case .group: return AppLocalization.text("Group")
        case .type: return AppLocalization.text("Type")
        case .series: return AppLocalization.text("Series")
        case .character: return AppLocalization.text("Character")
        case .tag: return AppLocalization.text("Tag")
        case .language: return AppLocalization.text("Language")
        }
    }
}

struct MetadataAnalysisEntry: Identifiable, Codable, Equatable {
    var field: MetadataAnalysisField
    var value: String
    var queueCount: Int
    var historyCount: Int
    var sampleTitle: String
    var sampleSource: String

    var id: String {
        "\(field.rawValue)|\(value.lowercased())"
    }

    var totalCount: Int {
        queueCount + historyCount
    }
}

struct SearchResultLink: Identifiable, Equatable {
    let id: UUID
    var title: String
    var url: String
    var siteIdentifier: String?
    var metadataText: String
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        title: String,
        url: String,
        siteIdentifier: String? = nil,
        metadataText: String = "",
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteIdentifier = siteIdentifier
        self.metadataText = metadataText
        self.metadata = metadata
    }
}

struct SearchTagSuggestion: Identifiable, Equatable {
    var title: String
    var token: String
    var detail: String

    var id: String {
        "\(token)|\(title)"
    }
}

struct ArtistRecommendation: Identifiable, Equatable {
    var name: String
    var score: Double
    var jobCount: Int
    var historyCount: Int
    var bookmarkCount: Int
    var relatedTerms: [String]
    var exampleTitle: String
    var lastSeen: Date?

    var id: String {
        name.lowercased()
    }

    var queryToken: String {
        let trimmed = name.trimmed
        guard trimmed.contains(" ") else { return "artist:\(trimmed)" }
        return "artist:\"\(trimmed.replacingOccurrences(of: "\"", with: ""))\""
    }

    var searchText: String {
        ([name, queryToken, exampleTitle] + relatedTerms).joined(separator: " ")
    }
}

enum HitomiTasterModel: String, CaseIterable, Codable, Identifiable {
    case shallow
    case deep

    var id: String { rawValue }

    var label: String {
        switch self {
        case .shallow: return "Shallow"
        case .deep: return "Deep"
        }
    }

    var originalLabel: String {
        switch self {
        case .shallow: return "SHALLOW v0.1"
        case .deep: return "DEEP v0.1"
        }
    }

    var detail: String {
        switch self {
        case .shallow:
            return "Fast artist scoring from local queue, history, and bookmarks."
        case .deep:
            return "Richer scoring that weighs repeated signals, related tags, and recency."
        }
    }

    var minimumReferenceCount: Int {
        switch self {
        case .shallow: return 3
        case .deep: return 6
        }
    }
}

struct HitomiTasterResult: Identifiable, Equatable {
    var rank: Int
    var recommendation: ArtistRecommendation
    var model: HitomiTasterModel
    var adjustedScore: Double
    var confidence: Double

    var id: String {
        "\(model.rawValue):\(recommendation.id)"
    }

    var name: String { recommendation.name }
    var queryToken: String { recommendation.queryToken }
    var relatedTerms: [String] { recommendation.relatedTerms }
    var exampleTitle: String { recommendation.exampleTitle }
    var jobCount: Int { recommendation.jobCount }
    var historyCount: Int { recommendation.historyCount }
    var bookmarkCount: Int { recommendation.bookmarkCount }

    var signalCount: Int {
        jobCount + historyCount + bookmarkCount
    }

    var searchText: String {
        "\(rank) \(name) \(queryToken) \(exampleTitle) \(relatedTerms.joined(separator: " ")) \(model.label)"
    }
}

struct QueueFilterBookmark: Identifiable, Codable, Equatable {
    var id: UUID
    var title: String
    var query: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, query: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.query = query
        self.createdAt = createdAt
    }
}

struct ResolvedRequestHeader: Hashable {
    var name: String
    var value: String
}

struct PythonSegmentDecorator: Hashable {
    let scriptPath: String
    let scriptSHA256: String
    let sourceURL: String
    let downloaderClass: String
    let streamIndex: Int
}

struct ResolvedAsset: Identifiable, Hashable {
    let id = UUID()
    let remoteURL: URL
    var filename: String
    var metadata: [String: String] = [:]
    var referer: String?
    var userAgent: String? = nil
    var additionalHeaders: [ResolvedRequestHeader] = []
    var decryption: SegmentDecryption? = nil
    var xorKey: String? = nil
    var pixivGridShuffle: PixivGridShuffle? = nil
    var pixivUgoiraPackage: PixivUgoiraPackage? = nil
    var lezhinImageShuffle: LezhinImageShuffle? = nil
    var pythonSegmentDecorator: PythonSegmentDecorator? = nil
    var alternativeRemoteURLs: [URL] = []

    var additionalHeaderFields: [String: String] {
        additionalHeaders.reduce(into: [String: String]()) { result, header in
            result[header.name] = header.value
        }
    }
}

struct SegmentDecryption: Hashable {
    let keyURL: URL
    let iv: Data
}

struct PixivGridShuffle: Hashable {
    let key: String
    let width: Int
    let height: Int
    let gridSize: Int
}

struct PixivUgoiraFrame: Hashable, Codable {
    let file: String
    let delay: Int
}

struct PixivUgoiraPackage: Hashable {
    let frames: [PixivUgoiraFrame]
    let artworkURL: String
    var outputFormat: PixivUgoiraFileFormat = .ugoira
    var dither: Bool = true
    var quality: Int = 90
}

struct LezhinImageShuffle: Hashable {
    let seed: String
    let gridSize: Int
}

struct ResolvedDownload {
    let title: String
    let folderName: String
    let assets: [ResolvedAsset]
    var packageMode: DownloadPackageMode = .files
    var metadata: [String: String] = [:]
    var textMergePlan: ResolvedTextMergePlan? = nil
    var temporaryAssetDirectories: [URL] = []
}

struct ResolvedTextMergePlan {
    var outputFilename: String
    var header: String
    var separator: String
}

enum DownloadMetadata {
    static func clean(_ metadata: [String: String]) -> [String: String] {
        metadata.compactMapValues { value in
            let cleaned = value.trimmed
            return cleaned.isEmpty ? nil : cleaned
        }
    }
}

enum DownloadPackageMode {
    case files
    case concatenate(outputFilename: String)
    case mux(videoAssets: [ResolvedAsset], audioAssets: [ResolvedAsset], outputFilename: String)
    case grouped(fileAssetIndexes: [Int], concatenations: [ResolvedConcatenationGroup])
    case groupedMedia(
        fileAssetIndexes: [Int],
        concatenations: [ResolvedConcatenationGroup],
        muxes: [ResolvedMuxGroup]
    )
}

struct ResolvedConcatenationGroup {
    var assetIndexes: [Int]
    var outputFilename: String
    var metadata: [String: String] = [:]
}

struct ResolvedMuxGroup {
    var videoAssetIndexes: [Int]
    var audioAssetIndexes: [Int]
    var outputFilename: String
    var metadata: [String: String] = [:]
}

struct HitomiGallery: Decodable {
    let id: FlexibleString?
    let title: String?
    let japaneseTitle: String?
    let videoFilename: String?
    let type: String?
    let language: String?
    let languageLocalName: String?
    let date: String?
    let artists: [HitomiNamedValue]?
    let groups: [HitomiNamedValue]?
    let parodys: [HitomiNamedValue]?
    let characters: [HitomiNamedValue]?
    let tags: [HitomiNamedValue]?
    let files: [HitomiFile]

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case japaneseTitle = "japanese_title"
        case videoFilename = "videofilename"
        case type
        case language
        case languageLocalName = "language_localname"
        case date
        case artists
        case groups
        case parodys
        case characters
        case tags
        case files
    }
}

struct HitomiNamedValue: Decodable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let dictionary = try? container.decode([String: FlexibleString].self) {
            value = [
                "artist",
                "group",
                "parody",
                "character",
                "tag",
                "name",
                "value"
            ]
            .compactMap { dictionary[$0]?.value.trimmed }
            .first { !$0.isEmpty } ?? ""
            return
        }
        value = ""
    }
}

struct FlexibleString: Codable, Hashable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
            return
        }
        if let int = try? container.decode(Int.self) {
            value = String(int)
            return
        }
        if let double = try? container.decode(Double.self) {
            value = String(double)
            return
        }
        value = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

struct HitomiFile: Codable, Hashable {
    let name: String
    let hash: String?
    let width: Int?
    let height: Int?
    let hasWebP: FlexibleBool?
    let hasAvif: FlexibleBool?

    enum CodingKeys: String, CodingKey {
        case name
        case hash
        case width
        case height
        case hasWebP = "haswebp"
        case hasAvif = "hasavif"
    }
}

struct FlexibleBool: Codable, Hashable {
    let value: Bool

    init(_ value: Bool) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let bool = try? container.decode(Bool.self) {
            value = bool
            return
        }
        if let int = try? container.decode(Int.self) {
            value = int != 0
            return
        }
        if let string = try? container.decode(String.self) {
            let lowered = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            value = ["1", "true", "yes", "y"].contains(lowered)
            return
        }
        value = false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}

enum NativeDownloadError: LocalizedError {
    case invalidURL(String)
    case unsupported(String)
    case httpStatus(Int, URL)
    case missingGalleryID(String)
    case invalidGalleryData
    case noFiles
    case invalidPlaylist
    case encryptedPlaylist(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .invalidURL(let text):
            return "Invalid URL: \(text)"
        case .unsupported(let text):
            return text
        case .httpStatus(let status, let url):
            return "HTTP \(status) from \(url.absoluteString)"
        case .missingGalleryID(let text):
            return "Could not find a gallery id in \(text)"
        case .invalidGalleryData:
            return "The gallery metadata could not be parsed."
        case .noFiles:
            return "No downloadable files were found."
        case .invalidPlaylist:
            return "The playlist could not be parsed."
        case .encryptedPlaylist(let text):
            return text
        case .cancelled:
            return "Cancelled"
        }
    }
}
