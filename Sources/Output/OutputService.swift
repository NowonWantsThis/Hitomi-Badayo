import AppKit
import Foundation
import ImageIO

struct OutputRootRequest {
    var destinationPath: String
    var subfolderMode: OutputSubfolderMode
    var sourceFolderName: String
    var dateFolderName: String
}

private struct OutputMoveOperation {
    var source: URL
    var destination: URL
    var kind: OutputDeletionCandidateKind
    var isPrimary: Bool
    var isNoOp: Bool
}

struct OutputTrashResult {
    var resolvedPaths = Set<String>()
    var trashedItemCount = 0
    var failures: [String] = []
}

final class OutputService {
    private let fileManager: FileManager
    private static let archiveExtensions = ["zip", "cbz", "rar", "7z"]
    private static let convertibleImageExtensions: Set<String> = [
        "avif", "bmp", "gif", "heic", "heif", "jpeg", "jpg", "png", "tif", "tiff", "webp"
    ]

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    func prepareOutputRoot(_ request: OutputRootRequest) throws -> URL {
        var root = URL(fileURLWithPath: request.destinationPath, isDirectory: true)

        switch request.subfolderMode {
        case .none:
            break
        case .site:
            root = AppPaths.directoryURL(in: root, name: request.sourceFolderName)
        case .date:
            root.appendPathComponent(request.dateFolderName, isDirectory: true)
        case .siteAndDate:
            root = AppPaths.directoryURL(in: root, name: request.sourceFolderName)
            root.appendPathComponent(request.dateFolderName, isDirectory: true)
        }

        try AppPaths.ensureDirectory(root)
        return root
    }

    func outputFilename(
        for asset: ResolvedAsset,
        imageConversionFormat: ImageConversionFormat
    ) -> String {
        guard !assetIsPixivUgoira(asset) else {
            return asset.filename
        }
        return convertedImageFilename(
            asset.filename,
            metadata: asset.metadata,
            remoteURL: asset.remoteURL,
            format: imageConversionFormat
        )
    }

    func convertedImageFilename(
        _ filename: String,
        metadata: [String: String] = [:],
        remoteURL: URL? = nil,
        format: ImageConversionFormat
    ) -> String {
        guard let targetExtension = format.fileExtension,
              isConvertibleImage(filename: filename, metadata: metadata, remoteURL: remoteURL) else {
            return filename
        }

        let path = filename as NSString
        let currentExtension = path.pathExtension.lowercased()
        if currentExtension == targetExtension {
            return filename
        }

        let base = path.deletingPathExtension
        if base.trimmed.isEmpty || currentExtension.isEmpty {
            return "\(filename).\(targetExtension)"
        }
        return "\(base).\(targetExtension)"
    }

    func convertDownloadedImageIfNeeded(
        at url: URL,
        asset: ResolvedAsset,
        format: ImageConversionFormat
    ) throws {
        guard !assetIsPixivUgoira(asset) else { return }
        guard let targetExtension = format.fileExtension,
              isConvertibleImage(filename: asset.filename, metadata: asset.metadata, remoteURL: asset.remoteURL) else {
            return
        }
        if (asset.filename as NSString).pathExtension.lowercased() == targetExtension {
            return
        }
        try convertImage(at: url, to: format)
    }

    func convertImage(
        at url: URL,
        to format: ImageConversionFormat,
        quality: Int = 95
    ) throws {
        guard bitmapFileType(for: format) != nil else { return }
        let data = try convertedImageData(at: url, to: format, quality: quality)

        let temporary = url.deletingLastPathComponent()
            .appendingPathComponent(".\(url.lastPathComponent).convert-\(UUID().uuidString)")
        try data.write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
        try fileManager.moveItem(at: temporary, to: url)
    }

    func convertOutputImages(
        forOutputPath outputPath: String,
        to format: ImageConversionFormat,
        quality: Int = 95
    ) throws -> OutputImageConversionResult {
        guard let targetExtension = format.fileExtension else {
            return OutputImageConversionResult(items: [], unchangedCount: 0, primaryOutputPath: outputPath)
        }

        let value = (outputPath.trimmed as NSString).expandingTildeInPath
        guard !value.isEmpty else {
            return OutputImageConversionResult(items: [], unchangedCount: 0, primaryOutputPath: nil)
        }

        let root = URL(fileURLWithPath: value).standardizedFileURL
        var rootIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: root.path, isDirectory: &rootIsDirectory) else {
            return OutputImageConversionResult(items: [], unchangedCount: 0, primaryOutputPath: nil)
        }

        let files = outputImageFiles(at: root, isDirectory: rootIsDirectory.boolValue)
        var items: [OutputImageConversionItem] = []
        var unchangedCount = 0
        var primaryOutputPath = root.path

        for source in files {
            let sourceExtension = source.pathExtension.lowercased()
            if sourceExtension == targetExtension {
                unchangedCount += 1
                continue
            }

            let destination = source.deletingPathExtension().appendingPathExtension(targetExtension)
            if source.standardizedFileURL == destination.standardizedFileURL {
                unchangedCount += 1
                continue
            }
            guard !fileManager.fileExists(atPath: destination.path) else {
                throw NativeDownloadError.unsupported(
                    "Image conversion destination already exists: \(destination.lastPathComponent)"
                )
            }

            let data = try convertedImageData(at: source, to: format, quality: quality)
            let temporary = destination.deletingLastPathComponent()
                .appendingPathComponent(".\(destination.lastPathComponent).convert-\(UUID().uuidString)")
            do {
                try data.write(to: temporary, options: .atomic)
                try fileManager.moveItem(at: temporary, to: destination)
                do {
                    try fileManager.removeItem(at: source)
                } catch {
                    try? fileManager.removeItem(at: destination)
                    throw error
                }
            } catch {
                try? fileManager.removeItem(at: temporary)
                throw error
            }

            items.append(OutputImageConversionItem(
                originalPath: source.path,
                convertedPath: destination.path
            ))
            if !rootIsDirectory.boolValue {
                primaryOutputPath = destination.path
            }
        }

        return OutputImageConversionResult(
            items: items,
            unchangedCount: unchangedCount,
            primaryOutputPath: primaryOutputPath
        )
    }

    func outputDeletionCandidates(for job: DownloadJob) -> [OutputDeletionCandidate] {
        let path = job.outputPath.trimmed
        guard !path.isEmpty else { return [] }

        let output = URL(fileURLWithPath: path)
        var candidates: [OutputDeletionCandidate] = []
        var seenPaths = Set<String>()

        func append(_ url: URL, preferredKind: OutputDeletionCandidateKind? = nil) {
            var isDirectory: ObjCBool = false
            guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }
            let resolvedPath = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seenPaths.insert(resolvedPath).inserted else { return }

            let kind = preferredKind ?? outputDeletionCandidateKind(
                for: url,
                isDirectory: isDirectory.boolValue
            )
            candidates.append(OutputDeletionCandidate(path: url.path, kind: kind))
        }

        append(output)
        if Self.archiveExtensions.contains(output.pathExtension.lowercased()) {
            append(output.deletingPathExtension(), preferredKind: .folder)
        } else {
            for archive in archiveSiblingURLs(for: output) {
                append(archive, preferredKind: .archive)
            }
        }

        return candidates
    }

    func moveOutputCandidates(
        _ candidates: [OutputDeletionCandidate],
        originalOutputPath: String,
        to destinationDirectory: URL
    ) throws -> OutputMoveResult {
        let operations = try outputMoveOperations(
            for: candidates,
            originalOutputPath: originalOutputPath,
            destinationDirectory: destinationDirectory
        )

        var movedItems: [OutputMoveItem] = []
        var primaryOutputPath: String?

        for operation in operations {
            if operation.isNoOp {
                if operation.isPrimary {
                    primaryOutputPath = operation.source.path
                }
                continue
            }

            try fileManager.moveItem(at: operation.source, to: operation.destination)
            movedItems.append(OutputMoveItem(
                originalPath: operation.source.path,
                movedPath: operation.destination.path,
                kind: operation.kind
            ))
            if operation.isPrimary {
                primaryOutputPath = operation.destination.path
            }
        }

        if primaryOutputPath == nil {
            primaryOutputPath = movedItems.first?.movedPath
        }

        return OutputMoveResult(items: movedItems, primaryOutputPath: primaryOutputPath)
    }

    func trashOutputCandidates(
        _ candidates: [OutputDeletionCandidate],
        protectedOutputRootPath: String,
        trashItem: (URL) throws -> URL?
    ) throws -> OutputTrashResult {
        var prepared: [(candidate: OutputDeletionCandidate, url: URL, safetyURL: URL)] = []
        for candidate in candidates {
            let url = URL(fileURLWithPath: candidate.path).standardizedFileURL
            let safetyURL = url.resolvingSymlinksInPath()
            guard isSafeOutputDeletionURL(
                safetyURL,
                protectedOutputRootPath: protectedOutputRootPath
            ) else {
                throw NativeDownloadError.unsupported("Refusing to delete \(url.lastPathComponent).")
            }
            prepared.append((candidate, url, safetyURL))
        }

        var result = OutputTrashResult()
        for item in prepared {
            if !fileManager.fileExists(atPath: item.url.path) {
                result.resolvedPaths.insert(item.url.path)
                result.resolvedPaths.insert(item.safetyURL.standardizedFileURL.path)
                continue
            }

            do {
                _ = try trashItem(item.url)
                result.trashedItemCount += 1
                result.resolvedPaths.insert(item.url.path)
                result.resolvedPaths.insert(item.safetyURL.standardizedFileURL.path)
            } catch {
                if !fileManager.fileExists(atPath: item.url.path) {
                    result.resolvedPaths.insert(item.url.path)
                    result.resolvedPaths.insert(item.safetyURL.standardizedFileURL.path)
                } else {
                    result.failures.append(
                        "\(item.candidate.filename): \(AppLocalization.errorText(error))"
                    )
                }
            }
        }
        return result
    }

    @discardableResult
    func archiveCompletedFolder(
        _ folder: URL,
        format: ArchiveFileFormat,
        deleteOriginal: Bool
    ) throws -> URL {
        let destination = AppPaths.uniqueFileURL(
            in: folder.deletingLastPathComponent(),
            filename: "\(folder.lastPathComponent).\(format.fileExtension)"
        )
        return try archiveCompletedFolder(
            folder,
            to: destination,
            deleteOriginal: deleteOriginal
        )
    }

    @discardableResult
    func archiveCompletedFolder(
        _ folder: URL,
        to archive: URL? = nil,
        deleteOriginal: Bool
    ) throws -> URL {
        let destination = archive ?? AppPaths.uniqueFileURL(
            in: folder.deletingLastPathComponent(),
            filename: "\(folder.lastPathComponent).zip"
        )
        let sourcePath = folder.standardizedFileURL.path
        let destinationPath = destination.standardizedFileURL.path
        guard destinationPath != sourcePath,
              !destinationPath.hasPrefix(sourcePath.hasSuffix("/") ? sourcePath : "\(sourcePath)/") else {
            throw NativeDownloadError.unsupported("Archive destination must be outside the source folder.")
        }

        do {
            try ZipArchiveWriter.archiveDirectory(folder, to: destination, fileManager: fileManager)
        } catch {
            try? fileManager.removeItem(at: destination)
            throw error
        }
        if deleteOriginal {
            try fileManager.removeItem(at: folder)
        }
        return destination
    }

    private func convertedImageData(
        at url: URL,
        to format: ImageConversionFormat,
        quality: Int
    ) throws -> Data {
        guard let fileType = bitmapFileType(for: format) else {
            throw NativeDownloadError.unsupported("Image conversion format is unavailable.")
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw NativeDownloadError.unsupported("Image conversion failed: \(url.lastPathComponent)")
        }

        let bitmap = NSBitmapImageRep(cgImage: image)
        var properties: [NSBitmapImageRep.PropertyKey: Any] = [:]
        if format == .jpeg {
            properties[.compressionFactor] = Double(max(1, min(quality, 100))) / 100
        }
        guard let data = bitmap.representation(using: fileType, properties: properties) else {
            throw NativeDownloadError.unsupported("Image conversion failed: \(url.lastPathComponent)")
        }
        return data
    }

    private func outputImageFiles(at root: URL, isDirectory: Bool) -> [URL] {
        if !isDirectory {
            let ext = root.pathExtension.lowercased()
            return Self.convertibleImageExtensions.contains(ext) && fileManager.isReadableFile(atPath: root.path)
                ? [root]
                : []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isReadableKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [URL] = []
        for case let file as URL in enumerator {
            let ext = file.pathExtension.lowercased()
            guard Self.convertibleImageExtensions.contains(ext),
                  let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .isReadableKey]),
                  values.isRegularFile == true,
                  values.isReadable != false else {
                continue
            }
            files.append(file)
        }
        return files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private func archiveSiblingURLs(for output: URL) -> [URL] {
        Self.archiveExtensions.map { output.appendingPathExtension($0) }
            .filter { fileManager.fileExists(atPath: $0.path) }
    }

    private func outputDeletionCandidateKind(
        for url: URL,
        isDirectory: Bool
    ) -> OutputDeletionCandidateKind {
        if isDirectory { return .folder }
        if Self.archiveExtensions.contains(url.pathExtension.lowercased()) { return .archive }
        return .file
    }

    private func outputMoveOperations(
        for candidates: [OutputDeletionCandidate],
        originalOutputPath: String,
        destinationDirectory: URL
    ) throws -> [OutputMoveOperation] {
        let destination = try normalizedOutputMoveDestination(destinationDirectory)
        let destinationResolved = destination.resolvingSymlinksInPath().standardizedFileURL
        let original = URL(fileURLWithPath: originalOutputPath).standardizedFileURL
        let originalResolved = original.resolvingSymlinksInPath().standardizedFileURL
        var reservedPaths = Set<String>()
        var operations: [OutputMoveOperation] = []

        for candidate in candidates {
            let source = URL(fileURLWithPath: candidate.path).standardizedFileURL
            var isDirectory = ObjCBool(false)
            guard fileManager.fileExists(atPath: source.path, isDirectory: &isDirectory) else { continue }

            let sourceResolved = source.resolvingSymlinksInPath().standardizedFileURL
            guard isSafeOutputMoveSource(sourceResolved) else {
                throw NativeDownloadError.unsupported("Refusing to move \(source.lastPathComponent).")
            }
            if isDirectory.boolValue && isOutputMoveDestination(destinationResolved, inside: sourceResolved) {
                throw NativeDownloadError.unsupported("Choose a folder outside \(source.lastPathComponent).")
            }

            let target = uniqueOutputMoveDestination(
                for: source,
                isDirectory: isDirectory.boolValue,
                in: destination,
                reservedPaths: reservedPaths
            )
            let sourcePath = source.standardizedFileURL.path
            let targetPath = target.standardizedFileURL.path
            let isNoOp = sourcePath == targetPath
            if !isNoOp {
                reservedPaths.insert(targetPath)
            }

            let isPrimary = sourcePath == original.path ||
                sourceResolved.path == originalResolved.path
            operations.append(OutputMoveOperation(
                source: source,
                destination: target,
                kind: candidate.kind,
                isPrimary: isPrimary,
                isNoOp: isNoOp
            ))
        }

        return operations
    }

    @discardableResult
    private func normalizedOutputMoveDestination(_ destinationDirectory: URL) throws -> URL {
        let destination = destinationDirectory.standardizedFileURL
        try AppPaths.ensureDirectory(destination)

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: destination.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NativeDownloadError.unsupported("Destination is not a folder.")
        }
        return destination
    }

    private func uniqueOutputMoveDestination(
        for source: URL,
        isDirectory: Bool,
        in destinationDirectory: URL,
        reservedPaths: Set<String>
    ) -> URL {
        let safeName = source.lastPathComponent.sanitizedFilename()
        let sourcePath = source.standardizedFileURL.path

        func isUnavailable(_ url: URL) -> Bool {
            let path = url.standardizedFileURL.path
            if path == sourcePath {
                return false
            }
            return reservedPaths.contains(path) || fileManager.fileExists(atPath: path)
        }

        if isDirectory {
            var candidate = destinationDirectory.appendingPathComponent(safeName, isDirectory: true)
            var counter = 2
            while isUnavailable(candidate) {
                candidate = destinationDirectory
                    .appendingPathComponent("\(safeName) \(counter)", isDirectory: true)
                counter += 1
            }
            return candidate
        }

        let base = (safeName as NSString).deletingPathExtension
        let ext = (safeName as NSString).pathExtension
        var candidate = destinationDirectory.appendingPathComponent(safeName)
        var counter = 2
        while isUnavailable(candidate) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            candidate = destinationDirectory.appendingPathComponent(name)
            counter += 1
        }
        return candidate
    }

    private func isSafeOutputMoveSource(_ url: URL) -> Bool {
        let path = url.standardizedFileURL.path
        guard path != "/" else { return false }
        return !url.lastPathComponent.trimmed.isEmpty
    }

    private func isOutputMoveDestination(_ destination: URL, inside source: URL) -> Bool {
        let destinationPath = destination.standardizedFileURL.path
        let sourcePath = source.standardizedFileURL.path
        let sourcePrefix = sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
        return destinationPath == sourcePath || destinationPath.hasPrefix(sourcePrefix)
    }

    private func isSafeOutputDeletionURL(
        _ url: URL,
        protectedOutputRootPath: String
    ) -> Bool {
        let path = url.standardizedFileURL.path
        guard path != "/" else { return false }
        guard !url.lastPathComponent.trimmed.isEmpty else { return false }

        let protectedRoot = URL(fileURLWithPath: protectedOutputRootPath, isDirectory: true)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        return path != protectedRoot
    }

    private func assetIsPixivUgoira(_ asset: ResolvedAsset) -> Bool {
        if asset.pixivUgoiraPackage != nil { return true }
        let type = metadataValue(asset.metadata, keys: ["media_type", "type"]).lowercased()
        return type == "ugoira"
    }

    private func bitmapFileType(for format: ImageConversionFormat) -> NSBitmapImageRep.FileType? {
        switch format {
        case .original: return nil
        case .jpeg: return .jpeg
        case .png: return .png
        case .tiff: return .tiff
        case .bmp: return .bmp
        }
    }

    private func isConvertibleImage(
        filename: String,
        metadata: [String: String],
        remoteURL: URL?
    ) -> Bool {
        let candidates = [
            (filename as NSString).pathExtension.lowercased(),
            metadataValue(metadata, keys: ["format", "media_format", "ext", "extension"]),
            remoteURL?.pathExtension.lowercased() ?? ""
        ]
            .map { $0.lowercased().trimmed }
            .filter { !$0.isEmpty }
        if !candidates.isEmpty {
            return candidates.contains { Self.convertibleImageExtensions.contains($0) }
        }

        let category = metadataValue(metadata, keys: ["category", "media_type", "type"]).lowercased()
        return ["image", "photo", "picture"].contains(category)
    }

    private func metadataValue(_ metadata: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = metadata.first(where: { $0.key.lowercased() == key.lowercased() })?.value.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return ""
    }
}
