import Foundation

enum DownloadContentClassifier {
    static func category(
        forExtension rawExtension: String,
        contentType rawContentType: String
    ) -> String {
        let ext = rawExtension.lowercased()
        let contentType = rawContentType.lowercased()

        if contentType.contains("text/html") ||
            contentType.contains("application/xhtml+xml") ||
            ["html", "htm"].contains(ext) {
            return "page"
        }
        if contentType.hasPrefix("image/") ||
            ["jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "svg"]
                .contains(ext) {
            return "image"
        }
        if contentType.hasPrefix("video/") ||
            ["mp4", "m4v", "mov", "webm", "mkv", "avi"].contains(ext) {
            return "video"
        }
        if contentType.hasPrefix("audio/") ||
            ["mp3", "m4a", "aac", "flac", "wav", "ogg"].contains(ext) {
            return "audio"
        }
        if contentType == "application/pdf" ||
            contentType == "application/epub+zip" ||
            contentType == "application/msword" ||
            contentType == "application/rtf" ||
            contentType.hasPrefix(
                "application/vnd.openxmlformats-officedocument."
            ) ||
            contentType.hasPrefix(
                "application/vnd.oasis.opendocument."
            ) ||
            [
                "pdf", "epub", "mobi", "azw", "azw3", "doc", "docx",
                "rtf", "xls", "xlsx", "ppt", "pptx", "odt", "ods",
                "odp", "txt", "csv"
            ].contains(ext) {
            return "document"
        }
        if contentType == "application/vnd.comicbook+zip" ||
            contentType == "application/vnd.comicbook-rar" ||
            contentType == "application/vnd.rar" ||
            contentType == "application/x-cbr" ||
            contentType == "application/x-cbz" ||
            contentType == "application/x-comicbook+zip" ||
            contentType == "application/x-comicbook-rar" ||
            contentType == "application/gzip" ||
            contentType == "application/x-gzip" ||
            contentType == "application/x-tar" ||
            contentType == "application/x-gtar" ||
            contentType == "application/x-gtar-compressed" ||
            contentType == "application/tar+gzip" ||
            contentType == "application/x-compressed-tar" ||
            contentType == "application/x-bzip2" ||
            contentType == "application/x-xz" ||
            contentType == "application/zstd" ||
            contentType == "application/x-zstd" ||
            [
                "zip", "rar", "7z", "cbz", "cbr", "tar", "gz", "tgz",
                "bz2", "xz", "zst"
            ].contains(ext) {
            return "archive"
        }
        return "file"
    }
}
