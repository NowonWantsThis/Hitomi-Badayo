import Foundation

struct BookmarkImportRecord {
    var title: String?
    var url: String
    var createdAt: Date?
    var tags: [String] = []
    var note: String? = nil
}

struct BookmarkTextHeader {
    var titleIndex: Int?
    var urlIndex: Int
    var createdAtIndex: Int?
    var tagsIndex: Int?
    var noteIndex: Int?
}

struct QueueJobPackage: Codable {
    var app: String = "HitomiBadayo"
    var format: String = "queue-jobs"
    var version: Int = 2
    var exportedAt: Date = Date()
    var jobs: [DownloadJob]
    var groups: [QueueGroup]? = nil
}

struct QueueImportDocument {
    var jobs: [DownloadJob]
    var groups: [QueueGroup]
}

struct QueueFilterBookmarkPackage: Codable {
    var app: String = "HitomiBadayo"
    var format: String = "queue-filter-bookmarks"
    var version: Int = 1
    var exportedAt: Date = Date()
    var bookmarks: [QueueFilterBookmark]
}

struct SearchProviderPackage: Codable {
    var app: String = "HitomiBadayo"
    var format: String = "search-providers"
    var version: Int = 1
    var exportedAt: Date = Date()
    var providers: [SearchProvider]
}

struct SearchBookmarkPackage: Codable {
    var app: String = "HitomiBadayo"
    var format: String = "search-bookmarks"
    var version: Int = 1
    var exportedAt: Date = Date()
    var bookmarks: [SearchBookmark]
}

struct SearchProviderTextHeader {
    var nameIndex: Int?
    var templateIndex: Int
    var createdAtIndex: Int?
}

struct SearchBookmarkTextHeader {
    var titleIndex: Int?
    var providerIndex: Int?
    var queryIndex: Int
    var createdAtIndex: Int?
}

struct QueueFilterBookmarkTextHeader {
    var titleIndex: Int?
    var queryIndex: Int
    var createdAtIndex: Int?
}
