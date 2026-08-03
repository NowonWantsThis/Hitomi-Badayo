import Foundation

struct SearchPresentationSnapshot {
    let filteredResults: [SearchResultLink]
    let knownState: SearchKnownState
}

enum SearchPresentationReadModelService {
    static func snapshot(
        results: [SearchResultLink],
        filter: String,
        knownFilter: SearchResultKnownFilter,
        sortMode: SearchResultSortMode,
        sortDescending: Bool,
        jobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        destinationPath: String,
        fileManager: FileManager = .default
    ) -> SearchPresentationSnapshot {
        let knownState = SearchResultKnownStateService.knownState(
            jobs: jobs,
            history: history,
            destinationPath: destinationPath,
            fileManager: fileManager
        )
        let query = filter.trimmed
        let textFiltered = query.isEmpty
            ? results
            : SearchResultFilterEngine.filteredSearchResults(
                results,
                filter: query,
                knownSources: knownState.sources
            )
        let filtered = SearchResultFilterEngine.filteredSearchResults(
            textFiltered,
            knownFilter: knownFilter,
            knownSources: knownState.sources
        )
        let sorted = SearchResultSortService.sortedResults(
            filtered,
            mode: sortMode,
            descending: sortDescending,
            knownSources: knownState.sources
        )
        return SearchPresentationSnapshot(
            filteredResults: sorted,
            knownState: knownState
        )
    }
}
