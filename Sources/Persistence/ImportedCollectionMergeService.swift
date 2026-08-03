import Foundation

struct ImportedCollectionMergeResult<Value> {
    var values: [Value]
    var addedCount: Int
}

enum ImportedCollectionMergeService {
    static func searchProviders(
        existing: [SearchProvider],
        imported: [SearchProvider]
    ) -> ImportedCollectionMergeResult<SearchProvider> {
        var values = existing
        var existingIDs = Set(existing.map(\.id))
        var existingKeys = Set(existing.map {
            ImportExportCodecService.searchProviderImportKey(
                name: $0.name,
                urlTemplate: $0.urlTemplate
            )
        })
        var added = 0

        for provider in imported {
            let name = provider.name.trimmed.isEmpty
                ? ImportExportCodecService.searchProviderName(
                    forTemplate: provider.urlTemplate
                )
                : provider.name.trimmed
            let template = provider.urlTemplate.trimmed
            guard !name.isEmpty,
                  SearchQueryFacade.isValidTemplate(template) else {
                continue
            }
            let key = ImportExportCodecService.searchProviderImportKey(
                name: name,
                urlTemplate: template
            )
            guard existingKeys.insert(key).inserted else { continue }
            let id = existingIDs.insert(provider.id).inserted
                ? provider.id
                : UUID()
            values.append(
                SearchProvider(
                    id: id,
                    name: name,
                    urlTemplate: template,
                    createdAt: provider.createdAt
                )
            )
            added += 1
        }
        return ImportedCollectionMergeResult(
            values: values,
            addedCount: added
        )
    }

    static func searchBookmarks(
        existing: [SearchBookmark],
        imported: [SearchBookmark],
        providers: [SearchProvider],
        fallbackProviderName: String
    ) -> ImportedCollectionMergeResult<SearchBookmark> {
        var values = existing
        var existingIDs = Set(existing.map(\.id))
        var existingKeys = Set(existing.map {
            SearchQueryFacade.bookmarkKey(
                providerName: $0.providerName,
                query: $0.query
            )
        })
        var added = 0

        for bookmark in imported {
            let query = bookmark.query.trimmed
            guard !query.isEmpty else { continue }
            let rawProviderName = bookmark.providerName.trimmed
            let providerName = rawProviderName.isEmpty
                ? fallbackProviderName
                : rawProviderName
            let key = SearchQueryFacade.bookmarkKey(
                providerName: providerName,
                query: query
            )
            guard existingKeys.insert(key).inserted else { continue }
            let provider = SearchQueryFacade.provider(
                matching: providerName,
                in: providers
            )
            let resolvedProviderName = provider?.name ?? providerName
            let title = bookmark.title.trimmed.isEmpty
                ? SearchQueryFacade.bookmarkTitle(
                    providerName: resolvedProviderName,
                    query: query
                )
                : bookmark.title.trimmed
            let id = existingIDs.insert(bookmark.id).inserted
                ? bookmark.id
                : UUID()
            values.append(
                SearchBookmark(
                    id: id,
                    title: title,
                    providerID: provider?.id,
                    providerName: resolvedProviderName,
                    query: query,
                    createdAt: bookmark.createdAt
                )
            )
            added += 1
        }
        return ImportedCollectionMergeResult(
            values: values,
            addedCount: added
        )
    }

    static func queueFilterBookmarks(
        existing: [QueueFilterBookmark],
        imported: [QueueFilterBookmark]
    ) -> ImportedCollectionMergeResult<QueueFilterBookmark> {
        var values = existing
        var existingQueries = Set(
            existing.map { $0.query.trimmed.lowercased() }
        )
        var added = 0

        for bookmark in imported {
            let query = bookmark.query.trimmed
            guard !query.isEmpty else { continue }
            guard existingQueries.insert(query.lowercased()).inserted else {
                continue
            }
            let title = bookmark.title.trimmed.isEmpty
                ? ImportExportCodecService.queueFilterBookmarkTitle(
                    for: query
                )
                : bookmark.title.trimmed
            values.append(
                QueueFilterBookmark(
                    id: bookmark.id,
                    title: title,
                    query: query,
                    createdAt: bookmark.createdAt
                )
            )
            added += 1
        }
        return ImportedCollectionMergeResult(
            values: values,
            addedCount: added
        )
    }

    static func bookmarks(
        existing: [URLBookmark],
        imported: [BookmarkImportRecord]
    ) -> ImportedCollectionMergeResult<URLBookmark> {
        var values = existing
        var existingURLs = Set(existing.map { URLIdentity.normalize($0.url) })
        var added = 0

        for record in imported {
            let normalizedURL = SourceInputNormalizer.normalizedToken(record.url)
            guard !normalizedURL.isEmpty else { continue }
            let normalized = URLIdentity.normalize(normalizedURL)
            guard !normalized.isEmpty,
                  !existingURLs.contains(normalized) else {
                continue
            }
            existingURLs.insert(normalized)
            let title = record.title?.trimmed
            values.append(
                URLBookmark(
                    id: UUID(),
                    title: title?.isEmpty == false
                        ? title!
                        : bookmarkTitle(for: normalizedURL),
                    url: normalizedURL,
                    createdAt: record.createdAt ?? Date(),
                    tags: ImportExportCodecService.normalizedBookmarkTags(
                        record.tags
                    ),
                    note: record.note?.trimmed ?? ""
                )
            )
            added += 1
        }
        return ImportedCollectionMergeResult(
            values: values,
            addedCount: added
        )
    }

    static func bookmarkTitle(for url: String) -> String {
        if let parsed = URL(string: url),
           let host = parsed.host,
           !host.isEmpty {
            let last = parsed.lastPathComponent
            return last.isEmpty ? host : "\(host)/\(last)"
        }
        if url.hasPrefix("magnet:") {
            return "Magnet"
        }
        return url
    }
}
