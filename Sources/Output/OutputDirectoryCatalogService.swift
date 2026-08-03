import Foundation

enum OutputDirectoryCatalogService {
    nonisolated static func entries(
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        fileManager: FileManager = .default
    ) -> [OutputDirectoryEntry] {
        var directories: [String: Accumulator] = [:]

        for job in jobs {
            addDirectory(
                path: job.outputPath,
                title: job.title,
                isQueueEntry: true,
                directories: &directories,
                fileManager: fileManager
            )
        }

        for entry in history {
            addDirectory(
                path: entry.outputPath,
                title: entry.title,
                isQueueEntry: false,
                directories: &directories,
                fileManager: fileManager
            )
        }

        return directories.values
            .map { accumulator in
                OutputDirectoryEntry(
                    path: accumulator.path,
                    scope: scope(
                        queueCount: accumulator.queueCount,
                        historyCount: accumulator.historyCount
                    ),
                    queueCount: accumulator.queueCount,
                    historyCount: accumulator.historyCount,
                    sampleTitle: accumulator.sampleTitle,
                    exists: accumulator.exists,
                    isDirectory: accumulator.isDirectory
                )
            }
            .sorted {
                $0.path.localizedStandardCompare($1.path) == .orderedAscending
            }
    }

    nonisolated static func text(
        entries: [OutputDirectoryEntry],
        language: AppInterfaceLanguage
    ) -> String {
        guard !entries.isEmpty else {
            return AppLocalization.text("No directories", language: language)
        }

        let lines = entries.map { entry -> String in
            let counts = countText(
                queueCount: entry.queueCount,
                historyCount: entry.historyCount,
                language: language
            )
            let stateKey = entry.exists
                ? (entry.isDirectory ? "Exists" : "File Parent")
                : "Missing"
            let state = AppLocalization.text(stateKey, language: language)
            let suffix = entry.sampleTitle.trimmed.isEmpty
                ? ""
                : " - \(entry.sampleTitle)"
            let scope = AppLocalization.text(entry.scope, language: language)
            return "[\(scope)] \(entry.path)\n  \(counts), \(state)\(suffix)"
        }
        return AppLocalization.format(
            "Download Path History (%@)",
            language: language,
            String(entries.count)
        ) + "\n\n" + lines.joined(separator: "\n")
    }

    nonisolated static func directoryPath(
        forOutputPath outputPath: String,
        fileManager: FileManager = .default
    ) -> String? {
        let cleaned = (outputPath as NSString).expandingTildeInPath.trimmed
        guard !cleaned.isEmpty else { return nil }

        let url = URL(fileURLWithPath: cleaned)
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) {
            return isDirectory.boolValue
                ? url.path
                : url.deletingLastPathComponent().path
        }

        if !url.pathExtension.trimmed.isEmpty {
            return url.deletingLastPathComponent().path
        }
        return url.path
    }

    private nonisolated static func addDirectory(
        path: String,
        title: String,
        isQueueEntry: Bool,
        directories: inout [String: Accumulator],
        fileManager: FileManager
    ) {
        guard let directoryPath = directoryPath(
            forOutputPath: path,
            fileManager: fileManager
        ) else {
            return
        }
        let standardizedPath = URL(
            fileURLWithPath: directoryPath,
            isDirectory: true
        ).standardizedFileURL.path
        var isDirectoryObject = ObjCBool(false)
        let exists = fileManager.fileExists(
            atPath: standardizedPath,
            isDirectory: &isDirectoryObject
        )
        var accumulator = directories[standardizedPath] ??
            Accumulator(path: standardizedPath)
        if isQueueEntry {
            accumulator.queueCount += 1
        } else {
            accumulator.historyCount += 1
        }
        if accumulator.sampleTitle.trimmed.isEmpty {
            accumulator.sampleTitle = title
        }
        accumulator.exists = accumulator.exists || exists
        accumulator.isDirectory = accumulator.isDirectory ||
            (exists && isDirectoryObject.boolValue)
        directories[standardizedPath] = accumulator
    }

    private nonisolated static func scope(
        queueCount: Int,
        historyCount: Int
    ) -> String {
        switch (queueCount > 0, historyCount > 0) {
        case (true, true):
            return "Queue + History"
        case (true, false):
            return "Queue"
        case (false, true):
            return "History"
        default:
            return "Unknown"
        }
    }

    private nonisolated static func countText(
        queueCount: Int,
        historyCount: Int,
        language: AppInterfaceLanguage
    ) -> String {
        let pieces = [
            queueCount > 0
                ? AppLocalization.format(
                    "%@ queue",
                    language: language,
                    String(queueCount)
                )
                : nil,
            historyCount > 0
                ? AppLocalization.format(
                    "%@ history",
                    language: language,
                    String(historyCount)
                )
                : nil
        ].compactMap { $0 }
        return pieces.isEmpty
            ? AppLocalization.text("0 items", language: language)
            : pieces.joined(separator: ", ")
    }

    private struct Accumulator {
        var path: String
        var queueCount = 0
        var historyCount = 0
        var sampleTitle = ""
        var exists = false
        var isDirectory = false
    }
}
