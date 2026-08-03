import Foundation

struct OutputContentFile {
    var url: URL
    var relativePath: String
    var originalIndex: Int = 0
    var archiveURL: URL? = nil
    var archiveEntry: ZipArchiveReader.Entry? = nil
}

struct OutputTextReadResult {
    var text: String
    var bytesRead: Int
    var truncated: Bool
}

struct OutputContentFileService {
    static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp",
        "avif", "bmp", "heic", "heif"
    ]
    static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv",
        "avi", "wmv", "flv", "ts"
    ]
    static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac",
        "ogg", "opus"
    ]
    static let documentExtensions: Set<String> = [
        "txt", "log", "md", "html", "htm",
        "json", "xml", "csv"
    ]

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func files(
        at outputPath: String
    ) -> [OutputContentFile] {
        let path = outputPath.trimmed
        guard !path.isEmpty else {
            return []
        }
        let root = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            return []
        }

        let resolvedRoot =
            root.resolvingSymlinksInPath()
        if !isDirectory.boolValue {
            if Self.isArchiveOutputFile(
                resolvedRoot
            ),
            let archiveFiles = archiveFiles(
                in: resolvedRoot
            ),
            !archiveFiles.isEmpty {
                return archiveFiles
            }
            guard isReadableFile(
                resolvedRoot,
                under: resolvedRoot
            ) else {
                return []
            }
            return [
                OutputContentFile(
                    url: resolvedRoot,
                    relativePath:
                        root.lastPathComponent,
                    originalIndex: 0
                )
            ]
        }

        guard let enumerator =
                fileManager.enumerator(
                    at: root,
                    includingPropertiesForKeys: [
                        .isRegularFileKey
                    ],
                    options: [.skipsHiddenFiles]
                ) else {
            return []
        }

        let rootPrefix =
            resolvedRoot.path.hasSuffix("/")
            ? resolvedRoot.path
            : resolvedRoot.path + "/"
        var files: [OutputContentFile] = []
        for case let file as URL in enumerator {
            let resolved =
                file.resolvingSymlinksInPath()
            guard isReadableFile(
                resolved,
                under: resolvedRoot
            ),
            resolved.path.hasPrefix(rootPrefix) else {
                continue
            }
            let relative = String(
                resolved.path.dropFirst(
                    rootPrefix.count
                )
            )
            files.append(
                OutputContentFile(
                    url: resolved,
                    relativePath: relative
                )
            )
        }

        return files
            .sorted {
                $0.relativePath
                    .localizedStandardCompare(
                        $1.relativePath
                    ) == .orderedAscending
            }
            .enumerated()
            .map { offset, file in
                OutputContentFile(
                    url: file.url,
                    relativePath:
                        file.relativePath,
                    originalIndex: offset
                )
            }
    }

    func textCandidateFiles(
        in files: [OutputContentFile]
    ) -> [OutputContentFile] {
        files.filter(isTextFile)
    }

    func isTextFile(
        _ file: OutputContentFile
    ) -> Bool {
        Self.documentExtensions.contains(
            file.url.pathExtension.lowercased()
        )
    }

    func readTextFile(
        _ file: OutputContentFile,
        limit: Int
    ) throws -> OutputTextReadResult {
        let maxBytes = max(1, limit)
        let data: Data
        let truncated: Bool
        if file.archiveEntry != nil {
            let fullData = try Self.data(for: file)
            truncated = fullData.count > maxBytes
            data =
                truncated
                ? Data(fullData.prefix(maxBytes))
                : fullData
        } else {
            let handle = try FileHandle(
                forReadingFrom: file.url
            )
            defer {
                try? handle.close()
            }
            let readData =
                try handle.read(
                    upToCount: maxBytes + 1
                ) ?? Data()
            truncated = readData.count > maxBytes
            data =
                truncated
                ? Data(readData.prefix(maxBytes))
                : readData
        }
        let text =
            String(data: data, encoding: .utf8)
            ?? String(decoding: data, as: UTF8.self)
        return OutputTextReadResult(
            text: text,
            bytesRead: data.count,
            truncated: truncated
        )
    }

    static func data(
        for file: OutputContentFile
    ) throws -> Data {
        if let archiveURL = file.archiveURL,
           let archiveEntry = file.archiveEntry {
            return try ZipArchiveReader.data(
                for: archiveEntry,
                in: archiveURL
            )
        }
        return try Data(contentsOf: file.url)
    }

    static func fileSize(
        _ file: OutputContentFile
    ) -> Int {
        if let entry = file.archiveEntry {
            return entry.uncompressedSize >
                UInt64(Int.max)
                ? Int.max
                : Int(entry.uncompressedSize)
        }
        return (
            try? file.url.resourceValues(
                forKeys: [.fileSizeKey]
            ).fileSize
        ) ?? 0
    }

    static func modifiedDate(
        _ file: OutputContentFile
    ) -> Date? {
        let url = file.archiveURL ?? file.url
        return try? url.resourceValues(
            forKeys: [.contentModificationDateKey]
        ).contentModificationDate
    }

    static func displayName(
        _ file: OutputContentFile
    ) -> String {
        if file.archiveEntry != nil {
            return URL(
                fileURLWithPath: file.relativePath
            ).lastPathComponent
        }
        return file.url.lastPathComponent
    }

    static func displayPath(
        _ file: OutputContentFile
    ) -> String {
        if let archiveURL = file.archiveURL {
            return
                "\(archiveURL.path)#\(file.relativePath)"
        }
        return file.url.path
    }

    static func isArchiveOutputFile(
        _ url: URL
    ) -> Bool {
        ["zip", "cbz"].contains(
            url.pathExtension.lowercased()
        )
    }

    private func archiveFiles(
        in archive: URL
    ) -> [OutputContentFile]? {
        guard let entries =
                try? ZipArchiveReader.entries(
                    in: archive
                ) else {
            return nil
        }
        let visible = entries.filter { entry in
            entry.isReadable &&
                Self.isArchiveViewerEntry(
                    entry.name
                )
        }
        guard !visible.isEmpty else {
            return nil
        }

        return visible
            .sorted {
                $0.name.localizedStandardCompare(
                    $1.name
                ) == .orderedAscending
            }
            .enumerated()
            .map { offset, entry in
                OutputContentFile(
                    url:
                        archive.appendingPathComponent(
                            entry.name
                        ),
                    relativePath: entry.name,
                    originalIndex: offset,
                    archiveURL: archive,
                    archiveEntry: entry
                )
            }
    }

    private static func isArchiveViewerEntry(
        _ name: String
    ) -> Bool {
        let ext = URL(
            fileURLWithPath: name
        ).pathExtension.lowercased()
        return imageExtensions.contains(ext) ||
            videoExtensions.contains(ext) ||
            audioExtensions.contains(ext) ||
            documentExtensions.contains(ext) ||
            ext == "pdf"
    }

    private func isReadableFile(
        _ file: URL,
        under root: URL
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(
            atPath: file.path,
            isDirectory: &isDirectory
        ),
        !isDirectory.boolValue,
        fileManager.isReadableFile(
            atPath: file.path
        ) else {
            return false
        }
        if file == root {
            return true
        }
        return file.path.hasPrefix(
            root.path.hasSuffix("/")
                ? root.path
                : root.path + "/"
        )
    }
}
