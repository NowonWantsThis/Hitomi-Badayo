import CryptoKit
import Foundation

enum LocalInputPreparationService {
    static func fileMetadata(
        for url: URL,
        filename: String,
        byteCount: Int? = nil
    ) -> [String: String] {
        let ext =
            (filename as NSString)
            .pathExtension
            .lowercased()
        let basename =
            (filename as NSString)
            .deletingPathExtension
        let size =
            byteCount ??
            (
                try? url.resourceValues(
                    forKeys: [.fileSizeKey]
                )
                .fileSize
            )
        return DownloadMetadata.clean([
            "series": basename,
            "category":
                DownloadContentClassifier
                .category(
                    forExtension: ext,
                    contentType: ""
                ),
            "type": "local_file",
            "download_mode": "copy",
            "format": ext,
            "host": "local",
            "site": "local",
            "filename": filename,
            "basename": basename,
            "ext": ext,
            "slug":
                DirectDownloadMetadataService
                .sourceSlug(
                    from: url,
                    fallback: basename
                ),
            "path": url.path,
            "url": url.absoluteString,
            "byte_count":
                size.map(String.init) ?? "",
            "title": basename
        ])
    }

    static func filename(
        for url: URL
    ) -> String {
        let name =
            url.lastPathComponent
            .removingPercentEncoding?
            .trimmed ??
            url.lastPathComponent.trimmed
        return name.isEmpty
            ? "local-file"
            : name
    }

    static func improvedOriginalFilename(
        for url: URL,
        sourceFilename: String
    ) -> String {
        let ext =
            (sourceFilename as NSString)
            .pathExtension
        let stem =
            (sourceFilename as NSString)
            .deletingPathExtension
            .sanitizedFilename(
                maxLength: 180
            )
        let digest =
            Insecure.MD5
            .hash(
                data:
                    Data(
                        url.absoluteString
                            .utf8
                    )
            )
            .prefix(4)
            .map {
                String(
                    format: "%02x",
                    $0
                )
            }
            .joined()
        let suffix =
            " (\(digest))" +
            (
                ext.isEmpty
                ? ""
                : ".\(ext)"
            )
        let maximumCharacters = 180
        let maximumBytes = 240
        let characterLimit =
            max(
                1,
                maximumCharacters -
                    suffix.count
            )
        let byteLimit =
            max(
                1,
                maximumBytes -
                    suffix.utf8.count
            )
        var cleanStem = ""
        var usedBytes = 0
        for character in
            stem.prefix(characterLimit) {
            let bytes =
                String(character)
                .utf8
                .count
            guard usedBytes + bytes <=
                    byteLimit else {
                break
            }
            cleanStem.append(character)
            usedBytes += bytes
        }
        cleanStem =
            cleanStem
            .trimmingCharacters(
                in:
                    CharacterSet(
                        charactersIn:
                            " .-"
                    )
                    .union(
                        .whitespacesAndNewlines
                    )
            )
        if cleanStem.isEmpty {
            cleanStem = "download"
        }
        return "\(cleanStem)\(suffix)"
            .sanitizedFilename(
                maxLength:
                    maximumCharacters
            )
    }

    static func folderName(
        for url: URL
    ) -> String {
        let name =
            url.lastPathComponent
            .removingPercentEncoding?
            .trimmed ??
            url.lastPathComponent.trimmed
        return name.isEmpty
            ? "local-folder"
            : name
    }

    static func folderFileCount(
        in url: URL
    ) -> Int {
        guard let enumerator =
                FileManager.default
                .enumerator(
                    at: url,
                    includingPropertiesForKeys: [
                        .isRegularFileKey
                    ],
                    options: [
                        .skipsHiddenFiles
                    ]
                ) else {
            return 0
        }
        var count = 0
        for case let file as URL
            in enumerator {
            let values =
                try? file.resourceValues(
                    forKeys: [
                        .isRegularFileKey
                    ]
                )
            if values?.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    static func folderMetadata(
        for url: URL,
        folderName: String,
        fileCount: Int
    ) -> [String: String] {
        DownloadMetadata.clean([
            "series": folderName,
            "category": "folder",
            "type": "local_folder",
            "download_mode": "copy",
            "host": "local",
            "site": "local",
            "filename": folderName,
            "basename": folderName,
            "slug":
                DirectDownloadMetadataService
                .sourceSlug(
                    from: url,
                    fallback: folderName
                ),
            "path": url.path,
            "url": url.absoluteString,
            "file_count":
                String(fileCount),
            "media_count":
                String(fileCount),
            "title": folderName
        ])
    }

    static func isHTMLFile(
        _ url: URL
    ) -> Bool {
        [
            "html",
            "htm",
            "xhtml"
        ].contains(
            url.pathExtension.lowercased()
        )
    }

    static func htmlString(
        from url: URL
    ) -> String? {
        if let text =
            try? String(
                contentsOf: url,
                encoding: .utf8
            ) {
            return text
        }
        if let text =
            try? String(
                contentsOf: url,
                encoding: .isoLatin1
            ) {
            return text
        }
        return nil
    }

    static func isHTMLResponse(
        _ response: HTTPURLResponse?
    ) -> Bool {
        let contentType =
            response?
            .value(
                forHTTPHeaderField:
                    "Content-Type"
            )?
            .lowercased() ?? ""
        return contentType.contains(
            "text/html"
        ) ||
            contentType.contains(
                "application/xhtml+xml"
            )
    }
}
