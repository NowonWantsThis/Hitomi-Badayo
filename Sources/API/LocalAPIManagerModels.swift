import Foundation

typealias APIOutputFile =
    OutputContentFile
typealias APIChapterGroup =
    OutputChapterGroup

struct APITextSelection {
    var jobIndex: Int
    var job: DownloadJob
    var file: APIOutputFile?
    var text: String
    var bytesRead: Int
    var byteCount: Int
    var truncated: Bool
    var source: String
}

typealias APITextReadResult =
    OutputTextReadResult

#if TESTING
struct OutputContentFileSnapshotForTesting:
    Equatable
{
    var relativePath: String
    var displayName: String
    var displayPath: String
    var originalIndex: Int
    var byteCount: Int
    var isArchiveEntry: Bool
    var isText: Bool
}

struct OutputChapterGroupSnapshotForTesting:
    Equatable
{
    var title: String
    var path: String
    var indexes: [Int]
}
#endif

struct APIVideoThumbnailCacheEntry {
    var fileSize: Int?
    var modifiedAt: Date?
    var data: Data

    func matches(fileSize: Int?, modifiedAt: Date?) -> Bool {
        self.fileSize == fileSize && self.modifiedAt == modifiedAt
    }
}
