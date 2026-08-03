import AppKit
import Foundation

struct ClipboardSnapshot: Equatable {
    var fileURLs: [URL]
    var string: String?
    var changeCount: Int
}

@MainActor
protocol ClipboardStringReplacing: AnyObject {
    func replaceString(_ value: String) -> Bool
}

@MainActor
protocol ClipboardSnapshotReading: AnyObject {
    var changeCount: Int { get }

    func snapshot() -> ClipboardSnapshot
}

@MainActor
final class SystemPasteboardStringWriter:
    ClipboardStringReplacing
{
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    func replaceString(_ value: String) -> Bool {
        pasteboard.clearContents()
        return pasteboard.setString(
            value,
            forType: .string
        )
    }
}

@MainActor
final class SystemPasteboardSnapshotReader:
    ClipboardSnapshotReading
{
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    var changeCount: Int {
        pasteboard.changeCount
    }

    func snapshot() -> ClipboardSnapshot {
        let objects =
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [
                    .urlReadingFileURLsOnly:
                        true
                ]
            ) ?? []
        let fileURLs =
            objects.compactMap { object in
                if let url = object as? URL {
                    return url
                }
                if let url = object as? NSURL {
                    return url as URL
                }
                return nil
            }
        return ClipboardSnapshot(
            fileURLs: fileURLs,
            string:
                pasteboard.string(
                    forType: .string
                ),
            changeCount:
                pasteboard.changeCount
        )
    }
}

@MainActor
final class ClipboardCommandService {
    let writer: any ClipboardStringReplacing
    let reader: any ClipboardSnapshotReading

    init(
        writer: (any ClipboardStringReplacing)? = nil,
        reader: (any ClipboardSnapshotReading)? = nil
    ) {
        self.writer =
            writer ?? SystemPasteboardStringWriter()
        self.reader =
            reader ??
            SystemPasteboardSnapshotReader()
    }

    func copyText(_ value: String) -> Bool {
        writer.replaceString(value)
    }

    func snapshot() -> ClipboardSnapshot {
        reader.snapshot()
    }

    func inputText() -> String? {
        let snapshot = snapshot()
        return Self.inputText(
            fileURLs: snapshot.fileURLs,
            string: snapshot.string
        )
    }

    var currentChangeCount: Int {
        reader.changeCount
    }

    nonisolated static func inputText(
        fileURLs: [URL],
        string: String?
    ) -> String? {
        let fileURLText =
            fileURLs
                .filter(\.isFileURL)
                .map {
                    $0.standardizedFileURL
                        .absoluteString
                }
        if !fileURLText.isEmpty {
            return fileURLText.joined(
                separator: "\n"
            )
        }

        guard let string,
          !string.trimmed.isEmpty else {
            return nil
        }
        return string
    }
}
