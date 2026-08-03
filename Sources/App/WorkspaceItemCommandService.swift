import Foundation

enum WorkspaceItemCommandResult: Equatable {
    case opened
    case revealed
    case failed
}

@MainActor
final class WorkspaceItemCommandService {
    let workspace: any WorkspaceCommandOpening
    private let fileManager: FileManager

    init(
        workspace: any WorkspaceCommandOpening,
        fileManager: FileManager = .default
    ) {
        self.workspace = workspace
        self.fileManager = fileManager
    }

    func open(
        _ url: URL
    ) -> WorkspaceItemCommandResult {
        workspace.open(url) ? .opened : .failed
    }

    func reveal(
        _ url: URL
    ) -> WorkspaceItemCommandResult {
        workspace.activateFileViewerSelecting([url])
        return .revealed
    }

    func createDirectoryAndOpen(
        _ url: URL
    ) throws -> WorkspaceItemCommandResult {
        try fileManager.createDirectory(
            at: url,
            withIntermediateDirectories: true
        )
        return open(url)
    }
}
