import Foundation

enum OutputPreviewFileScanner {
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp", "heic", "heif"
    ]
    private static let videoExtensions: Set<String> = [
        "mp4", "m4v", "mov", "webm", "mkv", "avi", "wmv", "flv", "ts"
    ]
    private static let audioExtensions: Set<String> = [
        "mp3", "m4a", "aac", "wav", "flac", "ogg", "opus"
    ]
    private static let documentExtensions: Set<String> = [
        "txt", "log", "md", "html", "htm", "json", "xml", "csv", "pdf"
    ]

    nonisolated static func files(at outputPath: String) -> [OutputPreviewFile] {
        let path = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty, !Task.isCancelled else { return [] }

        let fileManager = FileManager.default
        let root = URL(fileURLWithPath: path)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDirectory) else { return [] }

        let resolvedRoot = root.resolvingSymlinksInPath()
        if !isDirectory.boolValue {
            if isArchive(resolvedRoot), let archiveFiles = archiveFiles(in: resolvedRoot), !archiveFiles.isEmpty {
                return archiveFiles
            }
            guard isReadableFile(resolvedRoot, under: resolvedRoot, fileManager: fileManager) else { return [] }
            return [makeFile(url: resolvedRoot, relativePath: root.lastPathComponent, originalIndex: 0)]
        }

        guard !isUnsafeDirectoryRoot(resolvedRoot, fileManager: fileManager) else { return [] }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        let rootPrefix = resolvedRoot.path.hasSuffix("/") ? resolvedRoot.path : resolvedRoot.path + "/"
        var candidates: [(url: URL, relativePath: String)] = []
        for case let file as URL in enumerator {
            if Task.isCancelled { return [] }
            let resolved = file.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(rootPrefix),
                  isReadableFile(resolved, under: resolvedRoot, fileManager: fileManager) else {
                continue
            }
            candidates.append((resolved, String(resolved.path.dropFirst(rootPrefix.count))))
        }

        return candidates
            .sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
            .enumerated()
            .map { offset, candidate in
                makeFile(url: candidate.url, relativePath: candidate.relativePath, originalIndex: offset)
            }
    }

    nonisolated static func outputPathExists(_ outputPath: String) -> Bool {
        let path = outputPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else { return false }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else { return false }
        if isDirectory.boolValue {
            return !isUnsafeDirectoryRoot(
                URL(fileURLWithPath: path).resolvingSymlinksInPath(),
                fileManager: .default
            )
        }
        return FileManager.default.isReadableFile(atPath: path)
    }

    private nonisolated static func archiveFiles(in archive: URL) -> [OutputPreviewFile]? {
        guard let entries = try? ZipArchiveReader.entries(in: archive) else { return nil }
        let modificationTime = (try? archive.resourceValues(forKeys: [.contentModificationDateKey]))?
            .contentModificationDate?
            .timeIntervalSince1970 ?? 0
        let visible = entries.filter { entry in
            guard entry.isReadable else { return false }
            let ext = URL(fileURLWithPath: entry.name).pathExtension.lowercased()
            return mediaType(forExtension: ext) != .file
        }
        guard !visible.isEmpty else { return nil }

        return visible
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .enumerated()
            .map { offset, entry in
                OutputPreviewFile(
                    originalIndex: offset,
                    relativePath: entry.name,
                    displayPath: "\(archive.path)#\(entry.name)",
                    containerPath: archive.path,
                    byteCount: entry.uncompressedSize > UInt64(Int.max) ? Int.max : Int(entry.uncompressedSize),
                    mediaType: mediaType(forExtension: URL(fileURLWithPath: entry.name).pathExtension.lowercased()),
                    isArchiveEntry: true,
                    modificationTime: modificationTime
                )
            }
    }

    private nonisolated static func makeFile(
        url: URL,
        relativePath: String,
        originalIndex: Int
    ) -> OutputPreviewFile {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        return OutputPreviewFile(
            originalIndex: originalIndex,
            relativePath: relativePath,
            displayPath: url.path,
            containerPath: url.path,
            byteCount: values?.fileSize ?? 0,
            mediaType: mediaType(forExtension: url.pathExtension.lowercased()),
            isArchiveEntry: false,
            modificationTime: values?.contentModificationDate?.timeIntervalSince1970 ?? 0
        )
    }

    private nonisolated static func mediaType(forExtension ext: String) -> OutputPreviewMediaType {
        if imageExtensions.contains(ext) { return .image }
        if videoExtensions.contains(ext) { return .video }
        if audioExtensions.contains(ext) { return .audio }
        if documentExtensions.contains(ext) { return .document }
        return .file
    }

    private nonisolated static func isArchive(_ url: URL) -> Bool {
        ["zip", "cbz"].contains(url.pathExtension.lowercased())
    }

    private nonisolated static func isUnsafeDirectoryRoot(
        _ root: URL,
        fileManager: FileManager
    ) -> Bool {
        let blocked = [
            URL(fileURLWithPath: "/"),
            fileManager.homeDirectoryForCurrentUser,
            fileManager.temporaryDirectory,
            URL(fileURLWithPath: "/private/tmp")
        ]
        let path = root.standardizedFileURL.path
        return blocked.contains { candidate in
            candidate.resolvingSymlinksInPath().standardizedFileURL.path == path
        }
    }

    private nonisolated static func isReadableFile(
        _ file: URL,
        under root: URL,
        fileManager: FileManager
    ) -> Bool {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: file.path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              fileManager.isReadableFile(atPath: file.path) else {
            return false
        }
        if file == root { return true }
        let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
        return file.path.hasPrefix(rootPrefix)
    }
}
