import Foundation

struct SearchKnownState: Equatable {
    var sources: Set<String> = []
    var outputPaths: [String: String] = [:]
}

enum SearchResultKnownStateService {
    nonisolated static func knownState(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        destinationPath: String,
        fileManager: FileManager = .default
    ) -> SearchKnownState {
        let outputPaths = knownOutputPaths(
            jobs: jobs,
            history: history,
            destinationPath: destinationPath,
            fileManager: fileManager
        )
        var sources = Set(outputPaths.keys)
        for job in jobs {
            sources.formUnion(sourceKeys(for: job.source))
        }
        for entry in history {
            sources.formUnion(sourceKeys(for: entry.source))
        }
        return SearchKnownState(
            sources: sources,
            outputPaths: outputPaths
        )
    }

    nonisolated static func isKnown(
        _ result: SearchResultLink,
        knownState: SearchKnownState
    ) -> Bool {
        knownState.sources.contains(resultKey(result.url))
    }

    nonisolated static func firstOutputOpenURL(
        for result: SearchResultLink,
        knownState: SearchKnownState,
        fileManager: FileManager = .default
    ) -> URL? {
        guard let outputPath = knownState.outputPaths[resultKey(result.url)] else {
            return nil
        }
        return OutputOpenService(fileManager: fileManager)
            .firstOutputOpenURL(forOutputPath: outputPath)
    }

    nonisolated static func hitomiResultKeys(
        forGalleryID id: String
    ) -> Set<String> {
        let value = id.trimmed
        guard value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil else {
            return []
        }
        return Set([
            "https://hitomi.la/reader/\(value).html",
            "https://hitomi.la/reader/\(value)",
            "https://hitomi.la/galleries/\(value).html",
            "https://hitomi.la/galleries/\(value)",
            "https://hitomi.la/g/\(value)",
            "https://hitomi.la/lofi/\(value).html",
            "https://hitomi.la/lofi/\(value)",
            "https://hitomi.la/mpv/\(value)",
            "https://hitomi.la/mpv/\(value).html",
            "https://hitomi.la/galleryblock/\(value)"
        ].map(resultKey))
    }

    private nonisolated static func knownOutputPaths(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        destinationPath: String,
        fileManager: FileManager
    ) -> [String: String] {
        var outputPaths: [String: String] = [:]
        for job in jobs where !job.outputPath.trimmed.isEmpty {
            addKnownOutputPath(
                job.outputPath,
                source: job.source,
                to: &outputPaths
            )
        }
        for entry in history where !entry.outputPath.trimmed.isEmpty {
            addKnownOutputPath(
                entry.outputPath,
                source: entry.source,
                to: &outputPaths
            )
        }

        let rootPath = destinationPath.trimmed
        if !rootPath.isEmpty {
            addHitomiOutputPaths(
                in: URL(fileURLWithPath: rootPath, isDirectory: true),
                to: &outputPaths,
                fileManager: fileManager
            )
        }
        return outputPaths
    }

    private nonisolated static func addKnownOutputPath(
        _ outputPath: String,
        source: String,
        to outputPaths: inout [String: String]
    ) {
        for key in sourceKeys(for: source) where outputPaths[key] == nil {
            outputPaths[key] = outputPath
        }
    }

    private nonisolated static func addHitomiOutputPaths(
        in root: URL,
        to outputPaths: inout [String: String],
        fileManager: FileManager
    ) {
        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: root.path,
            isDirectory: &isDirectory
        ) else {
            return
        }

        let galleryNumberService = HitomiGalleryNumberService()
        func record(_ ids: [String], output: URL) {
            for id in ids {
                for key in hitomiResultKeys(forGalleryID: id)
                    where outputPaths[key] == nil {
                    outputPaths[key] = output.path
                }
            }
        }

        if !isDirectory.boolValue {
            record(
                galleryNumberService.numbers(fromOutputFile: root),
                output: root
            )
            return
        }

        record(
            galleryNumberService.numbers(
                fromOutputName: root.lastPathComponent
            ),
            output: root
        )
        let resourceKeys: [URLResourceKey] = [
            .isDirectoryKey,
            .isRegularFileKey
        ]
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else {
            return
        }

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: Set(resourceKeys)
            ) else {
                continue
            }
            if values.isDirectory == true {
                record(
                    galleryNumberService.numbers(
                        fromOutputName: url.lastPathComponent
                    ),
                    output: url
                )
            } else if values.isRegularFile == true {
                let ids = galleryNumberService.numbers(fromOutputFile: url)
                let output = HitomiGalleryNumberService
                    .isGalleryInfoFilename(url.lastPathComponent)
                    ? url.deletingLastPathComponent()
                    : url
                record(ids, output: output)
            }
        }
    }

    private nonisolated static func sourceKeys(
        for source: String
    ) -> Set<String> {
        var keys = Set([resultKey(source)])
        guard let url = URL(string: source),
              let host = url.host?.lowercased(),
              host == "hitomi.la" || host == "www.hitomi.la",
              let id = HitomiResolver.galleryID(from: url) else {
            return keys
        }
        keys.formUnion(hitomiResultKeys(forGalleryID: id))
        return keys
    }

    nonisolated static func resultKey(_ value: String) -> String {
        URLIdentity.normalize(value)
    }
}
