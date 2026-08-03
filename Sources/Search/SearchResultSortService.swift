import Foundation

enum SearchResultSortService {
    static func sortedResults(
        _ results: [SearchResultLink],
        mode: SearchResultSortMode,
        descending: Bool,
        knownSources: Set<String>
    ) -> [SearchResultLink] {
        guard mode != .manual || descending else { return results }
        let indexed = results.enumerated().map {
            (index: $0.offset, result: $0.element)
        }
        return indexed.sorted { lhs, rhs in
            if let missingComparison = missingComparison(
                lhs.result,
                rhs.result,
                mode: mode
            ) {
                return missingComparison == .orderedAscending
            }

            let resultComparison = comparison(
                lhs.result,
                rhs.result,
                mode: mode,
                knownSources: knownSources
            )
            if resultComparison == .orderedSame {
                return descending ? lhs.index > rhs.index : lhs.index < rhs.index
            }
            return descending
                ? resultComparison == .orderedDescending
                : resultComparison == .orderedAscending
        }.map(\.result)
    }

    private static func comparison(
        _ lhs: SearchResultLink,
        _ rhs: SearchResultLink,
        mode: SearchResultSortMode,
        knownSources: Set<String>
    ) -> ComparisonResult {
        switch mode {
        case .manual:
            return .orderedSame
        case .title:
            let result = lhs.title.localizedStandardCompare(rhs.title)
            return result == .orderedSame
                ? lhs.url.localizedStandardCompare(rhs.url)
                : result
        case .site:
            let result = SearchResultMetadataService.normalizedHost(for: lhs)
                .localizedStandardCompare(
                    SearchResultMetadataService.normalizedHost(for: rhs)
                )
            return result == .orderedSame
                ? lhs.url.localizedStandardCompare(rhs.url)
                : result
        case .date:
            let result = (SearchResultMetadataService.dateText(for: lhs) ?? "")
                .localizedStandardCompare(
                    SearchResultMetadataService.dateText(for: rhs) ?? ""
                )
            return result == .orderedSame
                ? lhs.title.localizedStandardCompare(rhs.title)
                : result
        case .pages:
            let lhsCount = SearchResultMetadataService.pageCount(for: lhs) ?? 0
            let rhsCount = SearchResultMetadataService.pageCount(for: rhs) ?? 0
            if lhsCount != rhsCount {
                return lhsCount < rhsCount
                    ? .orderedAscending
                    : .orderedDescending
            }
            return lhs.title.localizedStandardCompare(rhs.title)
        case .done:
            let lhsKnown = knownSources.contains(
                SearchResultKnownStateService.resultKey(lhs.url)
            )
            let rhsKnown = knownSources.contains(
                SearchResultKnownStateService.resultKey(rhs.url)
            )
            if lhsKnown != rhsKnown {
                return lhsKnown ? .orderedDescending : .orderedAscending
            }
            return lhs.title.localizedStandardCompare(rhs.title)
        }
    }

    private static func missingComparison(
        _ lhs: SearchResultLink,
        _ rhs: SearchResultLink,
        mode: SearchResultSortMode
    ) -> ComparisonResult? {
        switch mode {
        case .date:
            let lhsMissing = SearchResultMetadataService.dateText(for: lhs)?
                .trimmed.isEmpty ?? true
            let rhsMissing = SearchResultMetadataService.dateText(for: rhs)?
                .trimmed.isEmpty ?? true
            if lhsMissing != rhsMissing {
                return lhsMissing ? .orderedDescending : .orderedAscending
            }
        case .pages:
            let lhsMissing = SearchResultMetadataService.pageCount(for: lhs) == nil
            let rhsMissing = SearchResultMetadataService.pageCount(for: rhs) == nil
            if lhsMissing != rhsMissing {
                return lhsMissing ? .orderedDescending : .orderedAscending
            }
        default:
            break
        }
        return nil
    }
}
