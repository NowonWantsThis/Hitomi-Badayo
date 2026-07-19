import Foundation

struct AppUserData: Codable {
    var queueOrderVersion: Int = 2
    var bookmarks: [URLBookmark] = []
    var history: [DownloadHistoryEntry] = []
    var queue: [DownloadJob] = []
    var queueGroups: [QueueGroup] = []
    var siteRules: [SiteRule] = []
    var searchProviders: [SearchProvider] = SearchProvider.defaultProviders
    var searchBookmarks: [SearchBookmark] = []
    var queueFilterBookmarks: [QueueFilterBookmark] = []
    var inputTextDraft: String = ""

    enum CodingKeys: String, CodingKey {
        case queueOrderVersion
        case bookmarks
        case history
        case queue
        case queueGroups
        case siteRules
        case searchProviders
        case searchBookmarks
        case queueFilterBookmarks
        case inputTextDraft
    }

    init() {}

    init(bookmarks: [URLBookmark], history: [DownloadHistoryEntry], queue: [DownloadJob] = [], queueGroups: [QueueGroup] = [], siteRules: [SiteRule], searchProviders: [SearchProvider], searchBookmarks: [SearchBookmark] = [], queueFilterBookmarks: [QueueFilterBookmark] = [], inputTextDraft: String = "", queueOrderVersion: Int = 2) {
        self.queueOrderVersion = queueOrderVersion
        self.bookmarks = bookmarks
        self.history = history
        self.queue = queue
        self.queueGroups = queueGroups
        self.siteRules = siteRules
        self.searchProviders = searchProviders
        self.searchBookmarks = searchBookmarks
        self.queueFilterBookmarks = queueFilterBookmarks
        self.inputTextDraft = inputTextDraft
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        queueOrderVersion = try container.decodeIfPresent(Int.self, forKey: .queueOrderVersion) ?? 1
        bookmarks = try container.decodeIfPresent([URLBookmark].self, forKey: .bookmarks) ?? []
        history = try container.decodeIfPresent([DownloadHistoryEntry].self, forKey: .history) ?? []
        queue = try container.decodeIfPresent([DownloadJob].self, forKey: .queue) ?? []
        queueGroups = try container.decodeIfPresent([QueueGroup].self, forKey: .queueGroups) ?? []
        siteRules = try container.decodeIfPresent([SiteRule].self, forKey: .siteRules) ?? []
        searchProviders = try container.decodeIfPresent([SearchProvider].self, forKey: .searchProviders) ?? SearchProvider.defaultProviders
        searchBookmarks = try container.decodeIfPresent([SearchBookmark].self, forKey: .searchBookmarks) ?? []
        queueFilterBookmarks = try container.decodeIfPresent([QueueFilterBookmark].self, forKey: .queueFilterBookmarks) ?? []
        inputTextDraft = try container.decodeIfPresent(String.self, forKey: .inputTextDraft) ?? ""
    }
}

struct UserDataStore {
    private let storageURL: URL

    init(storageURL: URL = AppPaths.userDataURL) {
        self.storageURL = storageURL
    }

    func load() -> AppUserData {
        guard let data = try? Data(contentsOf: storageURL) else {
            return AppUserData()
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(AppUserData.self, from: data)) ?? AppUserData()
    }

    @discardableResult
    func save(_ userData: AppUserData) -> Bool {
        do {
            try FileManager.default.createDirectory(at: storageURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try Self.encodedData(for: userData)
            if let existing = try? Data(contentsOf: storageURL),
               existing == data {
                return true
            }
            try data.write(to: storageURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func encodedData(for userData: AppUserData) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(userData)
    }
}

enum URLIdentity {
    static func normalize(_ raw: String) -> String {
        let trimmed = raw.trimmed
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased() else {
            return trimmed
        }

        if scheme == "magnet" {
            return trimmed
        }

        guard scheme == "http" || scheme == "https" else {
            return trimmed
        }

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.scheme = scheme
        let host = components?.host?.lowercased()
        components?.host = host

        if components?.path == "/" {
            components?.path = ""
        }

        return components?.string ?? trimmed
    }
}
