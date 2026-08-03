import CoreGraphics
import Foundation
import ImageIO

final class PDFOutputService {
    private struct ImageSource {
        var fileURL: URL?
        var archiveURL: URL?
        var archiveEntry: ZipArchiveReader.Entry?
    }

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
    private let outputOpenService: OutputOpenService

    init(
        fileManager: FileManager = .default,
        outputOpenService: OutputOpenService? = nil
    ) {
        self.fileManager = fileManager
        self.outputOpenService =
            outputOpenService ??
            OutputOpenService(fileManager: fileManager)
    }

    @discardableResult
    func createPDF(
        fromOutputPath path: String,
        title: String
    ) throws -> URL {
        let images = imageSources(fromOutputPath: path)
        guard !images.isEmpty else {
            throw NativeDownloadError.noFiles
        }

        let output = outputURL(
            fromOutputPath: path,
            title: title
        )
        try AppPaths.ensureDirectory(
            output.deletingLastPathComponent()
        )

        guard let consumer = CGDataConsumer(
            url: output as CFURL
        ) else {
            throw NativeDownloadError.unsupported(
                "PDF output could not be opened."
            )
        }
        guard let context = CGContext(
            consumer: consumer,
            mediaBox: nil,
            nil
        ) else {
            throw NativeDownloadError.unsupported(
                "PDF context could not be created."
            )
        }

        var written = 0
        var archiveDataCache: [URL: Data] = [:]
        for imageSource in images {
            guard let source = try cgImageSource(
                for: imageSource,
                archiveDataCache: &archiveDataCache
            ),
            let image = CGImageSourceCreateImageAtIndex(
                source,
                0,
                nil
            ) else {
                continue
            }

            let page = CGRect(
                x: 0,
                y: 0,
                width: max(1, image.width),
                height: max(1, image.height)
            )
            context.beginPDFPage([
                kCGPDFContextMediaBox as String: page
            ] as CFDictionary)
            context.setFillColor(
                CGColor(gray: 1, alpha: 1)
            )
            context.fill(page)
            context.draw(image, in: page)
            context.endPDFPage()
            written += 1
        }

        context.closePDF()

        guard written > 0 else {
            try? fileManager.removeItem(at: output)
            throw NativeDownloadError.noFiles
        }

        return output
    }

    func imageFiles(
        fromOutputPath path: String
    ) -> [URL] {
        let value = path.trimmed
        guard !value.isEmpty else {
            return []
        }

        let root = URL(fileURLWithPath: value)
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            return []
        }

        if !isDirectory.boolValue {
            return isImageFile(root) ? [root] : []
        }

        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey
            ],
            options: [
                .skipsHiddenFiles,
                .skipsPackageDescendants
            ],
            errorHandler: { _, _ in true }
        ) else {
            return []
        }

        var files: [URL] = []
        for case let url as URL in enumerator {
            guard isImageFile(url),
                  let values = try? url.resourceValues(
                    forKeys: [.isRegularFileKey]
                  ),
                  values.isRegularFile == true else {
                continue
            }
            files.append(url)
        }

        return files.sorted {
            $0.path.localizedStandardCompare($1.path) ==
                .orderedAscending
        }
    }

    func hasImageSources(
        fromOutputPath path: String
    ) -> Bool {
        !imageSources(
            fromOutputPath: path
        ).isEmpty
    }

    private func imageSources(
        fromOutputPath path: String
    ) -> [ImageSource] {
        let value = path.trimmed
        guard !value.isEmpty else {
            return []
        }

        let root = URL(fileURLWithPath: value)
        var isDirectory = ObjCBool(false)
        if !fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) {
            if let archive =
                outputOpenService.archiveSiblingURL(
                    forMissingOutput: root
                ) {
                return archiveImageSources(from: archive)
            }
            return []
        }

        if !isDirectory.boolValue {
            if isImageFile(root) {
                return [
                    ImageSource(fileURL: root)
                ]
            }
            return isArchiveOutputFile(root)
                ? archiveImageSources(from: root)
                : []
        }

        return imageFiles(
            fromOutputPath: path
        ).map { url in
            ImageSource(fileURL: url)
        }
    }

    private func archiveImageSources(
        from archive: URL
    ) -> [ImageSource] {
        guard let entries = try? ZipArchiveReader.entries(
            in: archive
        ) else {
            return []
        }
        return entries
            .filter {
                $0.isReadable &&
                    isImageEntryName($0.name)
            }
            .sorted {
                $0.name.localizedStandardCompare($1.name) ==
                    .orderedAscending
            }
            .map { entry in
                ImageSource(
                    archiveURL: archive,
                    archiveEntry: entry
                )
            }
    }

    private func cgImageSource(
        for image: ImageSource,
        archiveDataCache: inout [URL: Data]
    ) throws -> CGImageSource? {
        if let fileURL = image.fileURL {
            return CGImageSourceCreateWithURL(
                fileURL as CFURL,
                nil
            )
        }

        guard let archiveURL = image.archiveURL,
              let archiveEntry = image.archiveEntry else {
            return nil
        }

        let archiveData: Data
        if let cached = archiveDataCache[archiveURL] {
            archiveData = cached
        } else {
            archiveData = try Data(contentsOf: archiveURL)
            archiveDataCache[archiveURL] = archiveData
        }

        let data = try ZipArchiveReader.data(
            for: archiveEntry,
            inArchiveData: archiveData
        )
        return CGImageSourceCreateWithData(
            data as CFData,
            nil
        )
    }

    private func outputURL(
        fromOutputPath path: String,
        title: String
    ) -> URL {
        let value = path.trimmed
        let output = URL(
            fileURLWithPath:
                value.isEmpty
                ? AppPaths.defaultDownloadDirectory.path
                : value
        )
        var isDirectory = ObjCBool(false)
        let exists = fileManager.fileExists(
            atPath: output.path,
            isDirectory: &isDirectory
        )
        let parent = output.deletingLastPathComponent()
        let fallbackName =
            exists && isDirectory.boolValue
            ? output.lastPathComponent
            : (output.lastPathComponent as NSString)
                .deletingPathExtension
        let rawName =
            title.trimmed.isEmpty
            ? fallbackName
            : title
        return AppPaths.uniqueFileURL(
            in: parent,
            filename:
                "\(rawName.sanitizedFilename(maxLength: 120)).pdf"
        )
    }

    private func isImageFile(_ url: URL) -> Bool {
        Self.imageExtensions.contains(
            url.pathExtension.lowercased()
        )
    }

    private func isImageEntryName(
        _ name: String
    ) -> Bool {
        Self.imageExtensions.contains(
            URL(fileURLWithPath: name)
                .pathExtension
                .lowercased()
        )
    }

    private func isArchiveOutputFile(
        _ url: URL
    ) -> Bool {
        ["zip", "cbz"].contains(
            url.pathExtension.lowercased()
        )
    }
}
