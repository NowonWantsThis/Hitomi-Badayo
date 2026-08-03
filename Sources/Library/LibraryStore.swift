import Combine
import Foundation

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var bookmarks: [URLBookmark]
    @Published private(set) var history: [DownloadHistoryEntry]
    @Published private(set) var siteRules: [SiteRule]

    init(
        bookmarks: [URLBookmark] = [],
        history: [DownloadHistoryEntry] = [],
        siteRules: [SiteRule] = []
    ) {
        self.bookmarks = bookmarks
        self.history = history
        self.siteRules = siteRules
    }

    func replaceBookmarks(with replacement: [URLBookmark]) {
        bookmarks = replacement
    }

    func updateBookmarks(
        _ update: (inout [URLBookmark]) -> Void
    ) {
        update(&bookmarks)
    }

    func filteredBookmarks(matching filter: String) -> [URLBookmark] {
        let tokens = filter
            .components(separatedBy: .whitespacesAndNewlines)
            .map {
                $0.trimmed
                    .trimmingCharacters(
                        in: CharacterSet(charactersIn: "#")
                    )
                    .lowercased()
            }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return bookmarks }

        return bookmarks.filter { bookmark in
            let haystack = [
                bookmark.title,
                bookmark.url,
                bookmark.note,
                bookmark.tags.joined(separator: " ")
            ]
                .joined(separator: " ")
                .lowercased()
            return tokens.allSatisfy { haystack.contains($0) }
        }
    }

    func replaceHistory(with replacement: [DownloadHistoryEntry]) {
        history = replacement
    }

    func updateHistory(
        _ update: (inout [DownloadHistoryEntry]) -> Void
    ) {
        update(&history)
    }

    func historyPlainText(
        language: AppInterfaceLanguage = AppLocalization.currentLanguage()
    ) -> String {
        guard !history.isEmpty else {
            return AppLocalization.text("No history", language: language)
        }
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return history.enumerated().map { index, entry in
            var lines = [
                "[\(index + 1)] \(entry.title.trimmed.isEmpty ? entry.source : entry.title)",
                "\(AppLocalization.text("URL", language: language)): \(entry.source)",
                "\(AppLocalization.text("Output", language: language)): \(entry.outputPath)",
                "\(AppLocalization.text("Completed", language: language)): \(formatter.string(from: entry.completedAt))"
            ]
            let metadata = entry.metadata
                .filter {
                    !$0.key.trimmed.isEmpty && !$0.value.trimmed.isEmpty
                }
                .sorted {
                    $0.key.localizedStandardCompare($1.key) == .orderedAscending
                }
            if !metadata.isEmpty {
                lines.append(
                    "\(AppLocalization.text("Metadata", language: language)):"
                )
                lines.append(
                    contentsOf: metadata.map { "  \($0.key): \($0.value)" }
                )
            }
            return lines.joined(separator: "\n")
        }
        .joined(separator: "\n\n")
    }

    func replaceSiteRules(with replacement: [SiteRule]) {
        siteRules = replacement
    }

    func updateSiteRules(
        _ update: (inout [SiteRule]) -> Void
    ) {
        update(&siteRules)
    }
}
