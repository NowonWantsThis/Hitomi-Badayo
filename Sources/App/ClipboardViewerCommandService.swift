import Foundation

struct ClipboardViewerContentState:
    Equatable
{
    var text: String
    var source: String
    var changeCount: Int
    var urls: [String]
}

struct ClipboardViewerQueueCommandResult:
    Equatable
{
    var urls: [String]
    var added: Int
    var summary: String
}

@MainActor
final class ClipboardViewerCommandService {
    let clipboardCommandService:
        ClipboardCommandService

    init(
        clipboardCommandService:
            ClipboardCommandService
    ) {
        self.clipboardCommandService =
            clipboardCommandService
    }

    func refreshedState(
        extractURLs:
            (String) -> [String]
    ) -> ClipboardViewerContentState {
        let snapshot =
            clipboardCommandService.snapshot()
        return refreshedState(
            fileURLs: snapshot.fileURLs,
            string: snapshot.string,
            changeCount:
                snapshot.changeCount,
            extractURLs: extractURLs
        )
    }

    func refreshedState(
        fileURLs: [URL],
        string: String?,
        changeCount: Int,
        extractURLs:
            (String) -> [String]
    ) -> ClipboardViewerContentState {
        let text =
            ClipboardCommandService.inputText(
                fileURLs: fileURLs,
                string: string
            ) ?? ""
        return ClipboardViewerContentState(
            text: text,
            source:
                fileURLs.isEmpty
                ? "Clipboard text"
                : "\(fileURLs.count) file item\(fileURLs.count == 1 ? "" : "s")",
            changeCount: changeCount,
            urls: candidateURLs(
                from: text,
                extractURLs: extractURLs
            )
        )
    }

    func editedState(
        text: String,
        changeCount: Int,
        extractURLs:
            (String) -> [String]
    ) -> ClipboardViewerContentState {
        ClipboardViewerContentState(
            text: text,
            source: "Edited",
            changeCount: changeCount,
            urls: candidateURLs(
                from: text,
                extractURLs: extractURLs
            )
        )
    }

    func candidateURLs(
        from text: String,
        extractURLs:
            (String) -> [String]
    ) -> [String] {
        var seen = Set<String>()
        var output: [String] = []
        for url in extractURLs(text) {
            let key = URLIdentity.normalize(url)
            guard !key.isEmpty,
                  seen.insert(key).inserted
            else {
                continue
            }
            output.append(url)
        }
        return output
    }

    func queue(
        text: String,
        start: Bool,
        extractURLs:
            (String) -> [String],
        enqueue:
            ([String]) -> Int,
        startQueue: () -> Void
    ) -> ClipboardViewerQueueCommandResult {
        let urls = candidateURLs(
            from: text,
            extractURLs: extractURLs
        )
        let added = enqueue(urls)
        if added > 0, start {
            startQueue()
        }
        return ClipboardViewerQueueCommandResult(
            urls: urls,
            added: added,
            summary:
                added == 0
                ? "No clipboard URLs added"
                : "\(added) clipboard URL\(added == 1 ? "" : "s") added"
        )
    }

    func transferToInput(
        text: String,
        setInputText:
            (String) -> Void
    ) -> String {
        setInputText(text)
        return text.trimmed.isEmpty
            ? "Clipboard viewer is empty"
            : "Clipboard copied to input"
    }
}
