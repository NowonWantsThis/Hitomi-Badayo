import Foundation

enum SettingsSectionID: String, CaseIterable, Hashable {
    case urls
    case alerts
    case saveTo
    case tools
    case network
    case youtube
    case soop
    case pixiv
    case hls
    case record
    case externalTools
    case ffmpeg
    case aria2
    case httpAPI
    case search
    case bookmarks
    case history
    case siteRules
}

struct SettingsSearchResult: Identifiable, Equatable {
    var section: SettingsSectionID
    var title: String
    var detail: String

    var id: String { section.rawValue }
}

enum SettingsSearchIndex {
    private struct Entry {
        var section: SettingsSectionID
        var title: String
        var detail: String
        var keywords: [String]
    }

    static func matches(for query: String, limit: Int? = nil) -> [SettingsSearchResult] {
        let tokens = normalizedTokens(in: query)
        guard !tokens.isEmpty else { return [] }

        let matched = entries.filter { entry in
            let haystack = normalizedSearchText(for: entry)
            let words = normalizedTokens(in: haystack)
            return tokens.allSatisfy { token in
                if token.count <= 3 {
                    return words.contains(token)
                }
                return haystack.contains(token)
            }
        }
        .map { SettingsSearchResult(section: $0.section, title: $0.title, detail: $0.detail) }

        guard let limit else { return matched }
        return Array(matched.prefix(limit))
    }

    static func hasQuery(_ query: String) -> Bool {
        !normalizedTokens(in: query).isEmpty
    }

    static func normalizedTokens(in query: String) -> [String] {
        query
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
            .split { !$0.isLetter && !$0.isNumber }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private static func normalizedSearchText(for entry: Entry) -> String {
        ([entry.title, entry.detail] + entry.keywords)
            .joined(separator: " ")
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
            .lowercased()
    }

    private static let entries: [Entry] = [
        Entry(
            section: .urls,
            title: "URLs",
            detail: "Input, paste, queue import/export, duplicates, appearance, UI scale, clipboard, login, sleep",
            keywords: ["주소", "입력", "붙여넣기", "클립보드", "중복", "저사양", "다크모드", "스케일", "배율", "ui scale", "zoom", "부팅", "절전", "자동 제거", "playlist", "number"]
        ),
        Entry(
            section: .alerts,
            title: "Alerts",
            detail: "Notifications, sounds, shortcuts, floating monitor, after queue complete",
            keywords: ["알림", "소리", "완료", "종료", "queue complete", "sound", "shortcut", "shortcuts", "hotkey", "keyboard", "단축키", "키보드", "floating", "float", "monitor", "always on top", "플로팅", "모니터", "항상 위"]
        ),
        Entry(
            section: .saveTo,
            title: "Save To",
            detail: "Destination, grouping, archive, image conversion, filename templates",
            keywords: ["저장", "폴더", "경로", "압축", "zip", "cbz", "이미지", "변환", "파일명", "형식", "format", "template"]
        ),
        Entry(
            section: .tools,
            title: "Tools",
            detail: "Duplicate images, scan folders, gallery IDs",
            keywords: ["도구", "중복 이미지", "유사도", "썸네일", "같은 소스", "갤러리", "번호"]
        ),
        Entry(
            section: .network,
            title: "Network",
            detail: "Proxy, Tor, bypass, public IP",
            keywords: ["네트워크", "프록시", "proxy", "tor", "토르", "우회", "bypass", "public ip", "아이피", "socks"]
        ),
        Entry(
            section: .youtube,
            title: "YouTube",
            detail: "Language, thumbnail, playlist, upload-date file time, chapters, codec, resolution, audio, subtitles",
            keywords: ["유튜브", "언어", "썸네일", "재생목록", "업로드 날짜", "파일 수정일", "mtime", "챕터", "코덱", "해상도", "오디오", "자막", "subtitle"]
        ),
        Entry(
            section: .soop,
            title: "SOOP",
            detail: "SOOP/Afreeca preferred resolution",
            keywords: ["숲", "아프리카", "afreeca", "해상도", "resolution"]
        ),
        Entry(
            section: .pixiv,
            title: "Pixiv",
            detail: "Ugoira file format",
            keywords: ["픽시브", "ugoira", "움짤", "zip", "파일 형식"]
        ),
        Entry(
            section: .hls,
            title: "HLS",
            detail: "M3U8 remux, skip bad segments, segment delay",
            keywords: ["m3u8", "mp4", "remux", "리먹스", "hls", "segment", "세그먼트", "delay", "지연"]
        ),
        Entry(
            section: .record,
            title: "Record",
            detail: "Auto record URLs, pause, interval",
            keywords: ["녹화", "자동 녹화", "record", "interval", "간격", "pause", "라이브"]
        ),
        Entry(
            section: .externalTools,
            title: "External Tools",
            detail: "Install, update, or choose yt-dlp, Deno, FFmpeg, and aria2c",
            keywords: ["외부 도구", "설치", "업데이트", "경로", "path", "install", "update", "yt-dlp", "deno", "javascript", "ejs", "ffmpeg", "aria2", "aria2c"]
        ),
        Entry(
            section: .ffmpeg,
            title: "ffmpeg",
            detail: "Transcode codec, bitrate, CRF, preset",
            keywords: ["변환", "트랜스코드", "codec", "bitrate", "crf", "preset", "코덱", "비트레이트"]
        ),
        Entry(
            section: .aria2,
            title: "aria2",
            detail: "Torrent files, seed, speed limits, trackers, anonymous mode",
            keywords: ["토렌트", "torrent", "자석", "magnet", "seed", "시드", "속도", "limit", "tracker", "트래커", "anonymous"]
        ),
        Entry(
            section: .httpAPI,
            title: "HTTP API",
            detail: "HTTP API, port, password, browser viewer lazy loading",
            keywords: ["http", "api", "포트", "password", "비밀번호", "viewer", "브라우저", "lazy"]
        ),
        Entry(
            section: .search,
            title: "Search",
            detail: "Providers, query, search results, tags, exclusions, translations",
            keywords: ["검색", "검색기", "provider", "query", "태그", "제외", "번역", "자동완성", "결과"]
        ),
        Entry(
            section: .bookmarks,
            title: "Bookmarks",
            detail: "Saved URLs, bookmark import/export, filter",
            keywords: ["북마크", "즐겨찾기", "bookmark", "url", "import", "export", "필터"]
        ),
        Entry(
            section: .history,
            title: "History",
            detail: "Download history, retention limit, requeue, reveal",
            keywords: ["기록", "작업 기록", "history", "보관", "제한", "다시 추가", "requeue"]
        ),
        Entry(
            section: .siteRules,
            title: "Site Rules",
            detail: "Host rules, path patterns, custom command, headers, archive overrides",
            keywords: ["사이트", "규칙", "rule", "host", "pattern", "command", "명령", "referer", "user agent", "archive"]
        )
    ]
}
