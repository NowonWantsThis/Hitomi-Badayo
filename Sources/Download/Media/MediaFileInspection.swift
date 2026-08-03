import Foundation

enum MediaFileInspection {
    static func hasContent(_ url: URL) -> Bool {
        byteCount(url) > 0
    }

    static func byteCount(_ url: URL) -> Int64 {
        Int64(
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize)
                ?? 0
        )
    }
}
