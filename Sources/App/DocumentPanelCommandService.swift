import AppKit
import Foundation
import UniformTypeIdentifiers

struct OpenDocumentPanelRequest {
    var title: String? = nil
    var message: String? = nil
    var prompt: String? = nil
    var canChooseFiles = true
    var canChooseDirectories = false
    var canCreateDirectories: Bool? = nil
    var allowsMultipleSelection = false
    var allowedContentTypes:
        [UTType] = []
    var directoryURL: URL? = nil
}

struct SaveDocumentPanelRequest {
    var title: String? = nil
    var message: String? = nil
    var prompt: String? = nil
    var allowedContentTypes:
        [UTType] = []
    var nameFieldStringValue = ""
    var directoryURL: URL? = nil
}

@MainActor
final class DocumentPanelCommandService {
    typealias OpenHandler =
        (OpenDocumentPanelRequest) -> [URL]?
    typealias SaveHandler =
        (SaveDocumentPanelRequest) -> URL?

    private let openHandler: OpenHandler?
    private let saveHandler: SaveHandler?

    init(
        openHandler: OpenHandler? = nil,
        saveHandler: SaveHandler? = nil
    ) {
        self.openHandler = openHandler
        self.saveHandler = saveHandler
    }

    func chooseOpenURL(
        _ request: OpenDocumentPanelRequest
    ) -> URL? {
        chooseOpenURLs(request)?.first
    }

    func chooseOpenURLs(
        _ request: OpenDocumentPanelRequest
    ) -> [URL]? {
        if let openHandler {
            return openHandler(request)
        }

        let panel = NSOpenPanel()
        if let title = request.title {
            panel.title = title
        }
        if let message = request.message {
            panel.message = message
        }
        if let prompt = request.prompt {
            panel.prompt = prompt
        }
        panel.canChooseFiles =
            request.canChooseFiles
        panel.canChooseDirectories =
            request.canChooseDirectories
        if let canCreateDirectories =
            request.canCreateDirectories {
            panel.canCreateDirectories =
                canCreateDirectories
        }
        panel.allowsMultipleSelection =
            request.allowsMultipleSelection
        if !request.allowedContentTypes.isEmpty {
            panel.allowedContentTypes =
                request.allowedContentTypes
        }
        panel.directoryURL =
            request.directoryURL

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.urls
    }

    func chooseSaveURL(
        _ request: SaveDocumentPanelRequest
    ) -> URL? {
        if let saveHandler {
            return saveHandler(request)
        }

        let panel = NSSavePanel()
        if let title = request.title {
            panel.title = title
        }
        if let message = request.message {
            panel.message = message
        }
        if let prompt = request.prompt {
            panel.prompt = prompt
        }
        if !request.allowedContentTypes.isEmpty {
            panel.allowedContentTypes =
                request.allowedContentTypes
        }
        panel.nameFieldStringValue =
            request.nameFieldStringValue
        panel.directoryURL =
            request.directoryURL

        guard panel.runModal() == .OK else {
            return nil
        }
        return panel.url
    }
}
