import AppKit
import Foundation

@MainActor
protocol WorkspaceCommandOpening: AnyObject {
    @discardableResult
    func open(_ url: URL) -> Bool

    func activateFileViewerSelecting(
        _ fileURLs: [URL]
    )
}

extension NSWorkspace: WorkspaceCommandOpening {}

enum OutputCommandResult: Equatable {
    case unavailable
    case cancelled
    case revealed(count: Int)
    case opened(count: Int)
    case archiveOpened(format: ArchiveFileFormat)
    case archiveFallbackOpened
}

enum OutputPreviewCommandResult: Equatable {
    case opened
    case archiveEntryRevealed
    case revealed(isArchiveEntry: Bool)
}

@MainActor
final class OutputCommandService {
    let outputOpenService: OutputOpenService
    let workspace: any WorkspaceCommandOpening
    private let fileManager: FileManager

    init(
        outputOpenService: OutputOpenService,
        workspace: any WorkspaceCommandOpening =
            NSWorkspace.shared,
        fileManager: FileManager = .default
    ) {
        self.outputOpenService = outputOpenService
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func reveal(
        _ urls: [URL]
    ) -> OutputCommandResult {
        guard !urls.isEmpty else {
            return .unavailable
        }
        workspace.activateFileViewerSelecting(urls)
        return .revealed(count: urls.count)
    }

    func open(
        _ url: URL
    ) -> OutputCommandResult {
        guard workspace.open(url) else {
            return .unavailable
        }
        return .opened(count: 1)
    }

    func openDirectory(
        _ url: URL,
        fileManager overrideFileManager: FileManager? = nil
    ) -> OutputCommandResult {
        let directory = url.standardizedFileURL
        let fileManager = overrideFileManager ?? self.fileManager
        var isDirectory = ObjCBool(false)

        if fileManager.fileExists(
            atPath: directory.path,
            isDirectory: &isDirectory
        ) {
            guard isDirectory.boolValue else {
                return .unavailable
            }
        } else {
            do {
                try fileManager.createDirectory(
                    at: directory,
                    withIntermediateDirectories: true
                )
            } catch {
                return .unavailable
            }
        }

        return open(directory)
    }

    func openFirstOutput(
        for request: FirstOutputOpenRequest
    ) async -> OutputCommandResult {
        let outputOpenService = outputOpenService
        let url = await Task.detached(
            priority: .userInitiated
        ) {
            outputOpenService
                .preferredFirstOutputOpenURL(
                    for: request
                )
        }.value
        guard !Task.isCancelled else {
            return .cancelled
        }
        guard let url else {
            return .unavailable
        }
        workspace.open(url)
        return .opened(count: 1)
    }

    func openFirstOutputs(
        for requests: [FirstOutputOpenRequest],
        confirmLargeBatch: (Int) -> Bool
    ) async -> OutputCommandResult {
        let outputOpenService = outputOpenService
        let urls = await Task.detached(
            priority: .userInitiated
        ) {
            requests.compactMap {
                outputOpenService
                    .preferredFirstOutputOpenURL(for: $0)
            }
        }.value
        guard !Task.isCancelled else {
            return .cancelled
        }
        guard !urls.isEmpty else {
            return .unavailable
        }
        if urls.count > 10,
           !confirmLargeBatch(urls.count) {
            return .cancelled
        }
        for url in urls {
            workspace.open(url)
        }
        return .opened(count: urls.count)
    }

    func openArchive(
        for job: DownloadJob
    ) -> OutputCommandResult {
        if let artifact = JobArchiveArtifact.existing(
            for: job,
            fileManager: fileManager
        ) {
            workspace.open(artifact.url)
            return .archiveOpened(
                format: artifact.format
            )
        }

        if let fallback =
            outputOpenService
            .firstRetainedArchiveOutputURL(for: job) {
            workspace.open(fallback)
            return .archiveFallbackOpened
        }

        return .unavailable
    }

    func openPreviewFile(
        _ file: OutputPreviewFile
    ) -> OutputPreviewCommandResult {
        if file.isArchiveEntry {
            workspace.activateFileViewerSelecting([
                URL(fileURLWithPath: file.containerPath)
            ])
            return .archiveEntryRevealed
        }

        workspace.open(
            URL(fileURLWithPath: file.displayPath)
        )
        return .opened
    }

    func revealPreviewFile(
        _ file: OutputPreviewFile
    ) -> OutputPreviewCommandResult {
        let path =
            file.isArchiveEntry
            ? file.containerPath
            : file.displayPath
        workspace.activateFileViewerSelecting([
            URL(fileURLWithPath: path)
        ])
        return .revealed(
            isArchiveEntry: file.isArchiveEntry
        )
    }
}
