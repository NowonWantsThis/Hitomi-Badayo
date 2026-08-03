import Foundation

struct TextViewerRawFile {
    var originalIndex: Int
    var url: URL
    var isArchiveEntry: Bool
}

enum TextViewerCommandResult: Equatable {
    case noTextToCopy
    case textCopied
    case selectTextFirst
    case browserUnavailable
    case browserOpened
    case noRawTextFileSelected
    case rawFileInsideArchive
    case textFileOpened

    var summary: String {
        switch self {
        case .noTextToCopy:
            return "No text to copy"
        case .textCopied:
            return "Text copied"
        case .selectTextFirst:
            return "Select text first"
        case .browserUnavailable:
            return "Text browser unavailable"
        case .browserOpened:
            return "Text browser opened"
        case .noRawTextFileSelected:
            return "No raw text file selected"
        case .rawFileInsideArchive:
            return "Raw file is inside an archive"
        case .textFileOpened:
            return "Text file opened"
        }
    }
}

@MainActor
final class TextViewerCommandService {
    let clipboardCommandService:
        ClipboardCommandService
    let outputCommandService:
        OutputCommandService
    let sourceLinkCommandService:
        SourceLinkCommandService

    init(
        clipboardCommandService:
            ClipboardCommandService,
        outputCommandService:
            OutputCommandService,
        sourceLinkCommandService:
            SourceLinkCommandService
    ) {
        self.clipboardCommandService =
            clipboardCommandService
        self.outputCommandService =
            outputCommandService
        self.sourceLinkCommandService =
            sourceLinkCommandService
    }

    func copy(
        document: TextViewerDocument
    ) -> TextViewerCommandResult {
        let text =
            document.errorMessage ?? document.text
        guard !text.isEmpty else {
            return .noTextToCopy
        }
        _ = clipboardCommandService.copyText(text)
        return .textCopied
    }

    func openInBrowser(
        entry: TextViewerEntry?,
        baseURLString: String,
        password: String,
        ensureServerAvailable: () -> Bool
    ) -> TextViewerCommandResult {
        guard let entry,
              let url = Self.browserURL(
                baseURLString: baseURLString,
                jobID: entry.jobID,
                fileIndex: entry.fileIndex,
                password: password
              ) else {
            return .selectTextFirst
        }
        guard ensureServerAvailable() else {
            return .browserUnavailable
        }
        _ = sourceLinkCommandService.openBrowserURL(
            url,
            skipExternalOpen: false
        )
        return .browserOpened
    }

    func openRawFile(
        entry: TextViewerEntry?,
        files: [TextViewerRawFile]?
    ) -> TextViewerCommandResult {
        guard let entry,
              let fileIndex = entry.fileIndex,
              let files else {
            return .noRawTextFileSelected
        }
        guard let file = files.first(where: {
            $0.originalIndex == fileIndex
        }),
        !file.isArchiveEntry else {
            return .rawFileInsideArchive
        }
        _ = outputCommandService.open(file.url)
        return .textFileOpened
    }

    func canOpenRawFile(
        entry: TextViewerEntry?,
        files: [TextViewerRawFile]?
    ) -> Bool {
        guard let entry,
              let fileIndex = entry.fileIndex,
              let files,
              let file = files.first(where: {
                  $0.originalIndex == fileIndex
              }) else {
            return false
        }
        return !file.isArchiveEntry
    }

    nonisolated static func browserURL(
        baseURLString: String,
        jobID: UUID,
        fileIndex: Int?,
        password: String
    ) -> URL? {
        let value = baseURLString.trimmed
        guard !value.isEmpty,
              var components =
                URLComponents(string: value) else {
            return nil
        }
        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.host == nil {
            components.host = "127.0.0.1"
        }
        components.path = "/text"

        var queryItems = [
            URLQueryItem(
                name: "uid",
                value: jobID.uuidString
            )
        ]
        if let fileIndex {
            queryItems.append(
                URLQueryItem(
                    name: "index",
                    value: "\(fileIndex)"
                )
            )
        }
        let password = password.trimmed
        if !password.isEmpty {
            queryItems.append(
                URLQueryItem(
                    name: "pw",
                    value: password
                )
            )
        }
        components.queryItems = queryItems
        return components.url
    }
}
