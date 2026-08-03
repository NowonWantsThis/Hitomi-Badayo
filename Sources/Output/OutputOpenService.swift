import Foundation

struct FirstOutputOpenRequest: Sendable {
    var outputPath: String
    var archivedFolderPath: String?
    var archivePath: String?
}

final class OutputOpenService: @unchecked Sendable {
    private static let archiveExtensions = [
        "zip",
        "cbz",
        "rar",
        "7z"
    ]
    private static let imageExtensions = Set([
        "jpg",
        "jpeg",
        "png",
        "webp",
        "gif",
        "tif",
        "tiff",
        "bmp",
        "heic",
        "heif",
        "avif"
    ])

    private let fileManager: FileManager

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func revealURL(
        forOutputPath path: String
    ) -> URL? {
        let value = path.trimmed
        guard !value.isEmpty else {
            return nil
        }

        let output = URL(fileURLWithPath: value)
        if fileManager.fileExists(atPath: output.path) {
            return output
        }

        return archiveSiblingURL(
            forMissingOutput: output
        ) ?? output
    }

    func archiveSiblingURL(
        forMissingOutput output: URL
    ) -> URL? {
        for ext in Self.archiveExtensions {
            let candidate = output.appendingPathExtension(ext)
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        return nil
    }

    func firstOutputOpenURL(
        forOutputPath path: String
    ) -> URL? {
        let value = path.trimmed
        guard !value.isEmpty else {
            return nil
        }

        let output = URL(fileURLWithPath: value)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: output.path,
            isDirectory: &isDirectory
        ) {
            if !isDirectory.boolValue {
                return fileManager.isReadableFile(
                    atPath: output.path
                ) ? output : nil
            }

            if let firstFile = firstReadableFile(in: output) {
                return firstFile
            }

            return archiveSiblingURL(
                forMissingOutput: output
            )
        }

        return archiveSiblingURL(
            forMissingOutput: output
        )
    }

    func openRequest(
        for job: DownloadJob,
        outputPath: String? = nil
    ) -> FirstOutputOpenRequest {
        FirstOutputOpenRequest(
            outputPath: outputPath ?? job.outputPath,
            archivedFolderPath:
                job.metadata["archived_folder_path"]?.trimmed,
            archivePath:
                job.metadata["archive_path"]?.trimmed
        )
    }

    func preferredFirstOutputOpenURL(
        for request: FirstOutputOpenRequest
    ) -> URL? {
        let outputPath = request.outputPath.trimmed
        var folderCandidates: [URL] = []
        var checkedFolders = Set<String>()
        let hasGeneratedArchive =
            !(request.archivePath?.trimmed.isEmpty ?? true) ||
            !(request.archivedFolderPath?.trimmed.isEmpty ?? true)

        func appendFolder(_ rawPath: String?) {
            guard let rawPath,
                  !rawPath.trimmed.isEmpty else {
                return
            }
            let url = URL(
                fileURLWithPath: rawPath.trimmed
            ).standardizedFileURL
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(
                atPath: url.path,
                isDirectory: &isDirectory
            ),
            isDirectory.boolValue,
            checkedFolders.insert(url.path).inserted else {
                return
            }
            folderCandidates.append(url)
        }

        func appendArchiveFolder(_ rawPath: String?) {
            guard let rawPath,
                  !rawPath.trimmed.isEmpty else {
                return
            }
            let url = URL(
                fileURLWithPath: rawPath.trimmed
            ).standardizedFileURL
            guard ArchiveFileFormat(
                rawValue: url.pathExtension.lowercased()
            ) != nil else {
                return
            }
            appendFolder(
                url.deletingPathExtension().path
            )
        }

        appendFolder(request.archivedFolderPath)
        appendArchiveFolder(request.archivePath)

        if !outputPath.isEmpty {
            let output = URL(
                fileURLWithPath: outputPath
            ).standardizedFileURL
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(
                atPath: output.path,
                isDirectory: &isDirectory
            ) {
                if isDirectory.boolValue {
                    appendFolder(output.path)
                } else {
                    appendArchiveFolder(output.path)
                }
            } else if let sibling = archiveSiblingURL(
                forMissingOutput: output
            ) {
                appendArchiveFolder(sibling.path)
            }
        }

        for folder in folderCandidates {
            if let image = firstReadableFile(
                in: folder,
                matchingExtensions: Self.imageExtensions
            ) {
                return image
            }
        }

        for folder in folderCandidates {
            if let file = firstReadableFile(in: folder) {
                return file
            }
        }

        if hasGeneratedArchive {
            return nil
        }

        if !outputPath.isEmpty {
            return firstOutputOpenURL(
                forOutputPath: outputPath
            )
        }
        return nil
    }

    func firstRetainedArchiveOutputURL(
        for job: DownloadJob
    ) -> URL? {
        var candidatePaths: [String] = []
        if let archivedFolderPath =
            job.metadata["archived_folder_path"]?.trimmed,
           !archivedFolderPath.isEmpty {
            candidatePaths.append(archivedFolderPath)
        }

        let outputURL = URL(
            fileURLWithPath: job.outputPath.trimmed
        )
        if ArchiveFileFormat(
            rawValue: outputURL.pathExtension.lowercased()
        ) != nil {
            candidatePaths.append(
                outputURL.deletingPathExtension().path
            )
        }

        var checkedPaths = Set<String>()
        for path in candidatePaths {
            let normalizedPath = URL(
                fileURLWithPath: path
            ).standardizedFileURL.path
            guard checkedPaths.insert(
                normalizedPath
            ).inserted,
            let output = firstOutputOpenURL(
                forOutputPath: normalizedPath
            ) else {
                continue
            }
            return output
        }
        return nil
    }

    private func firstReadableFile(
        in folder: URL,
        matchingExtensions: Set<String>? = nil
    ) -> URL? {
        let folderPath = folder
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        guard let enumerator =
                fileManager.enumerator(atPath: folderPath) else {
            return nil
        }

        var firstRelativePath: String?
        while let relativePath =
                enumerator.nextObject() as? String {
            let name =
                (relativePath as NSString).lastPathComponent
            guard !name.isEmpty,
                  !name.hasPrefix(".") else {
                enumerator.skipDescendants()
                continue
            }
            let fileType =
                enumerator.fileAttributes?[.type]
                as? FileAttributeType
            if fileType == .typeSymbolicLink {
                enumerator.skipDescendants()
                continue
            }
            guard fileType == .typeRegular else {
                continue
            }
            if let matchingExtensions,
               !matchingExtensions.contains(
                    (relativePath as NSString)
                        .pathExtension
                        .lowercased()
               ) {
                continue
            }
            let path = (folderPath as NSString)
                .appendingPathComponent(relativePath)
            guard fileManager.isReadableFile(
                atPath: path
            ) else {
                continue
            }
            if let current = firstRelativePath {
                if relativePath.localizedStandardCompare(
                    current
                ) == .orderedAscending {
                    firstRelativePath = relativePath
                }
            } else {
                firstRelativePath = relativePath
            }
        }

        guard let firstRelativePath else {
            return nil
        }
        return URL(
            fileURLWithPath:
                (folderPath as NSString)
                .appendingPathComponent(firstRelativePath)
        )
    }
}
