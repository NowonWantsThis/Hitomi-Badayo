import Foundation

enum ImportExportCodecService {
    typealias URLExtractor = (String) -> [String]
    typealias InputNormalizer = (String) -> String
    typealias URLValidator = (String) -> Bool

    static func queueDocument(
        from data: Data,
        urlExtractor: URLExtractor
    ) throws -> QueueImportDocument {
        let data = dataByStrippingUTF8BOM(data)
        if OriginalHDT.looksLikePackage(data) {
            let document = try OriginalHDT.decodeDocument(data)
            return QueueImportDocument(
                jobs: document.jobs,
                groups: document.groups
            )
        }

        let decoder = iso8601Decoder()
        if let package = try? decoder.decode(QueueJobPackage.self, from: data) {
            return QueueImportDocument(
                jobs: package.jobs,
                groups: package.groups ?? []
            )
        }
        if let jobs = try? decoder.decode([DownloadJob].self, from: data) {
            return QueueImportDocument(jobs: jobs, groups: [])
        }
        if let userData = try? decoder.decode(AppUserData.self, from: data),
           !userData.queue.isEmpty || !userData.queueGroups.isEmpty {
            return QueueImportDocument(
                jobs: userData.queue,
                groups: userData.queueGroups
            )
        }

        let urls = importedText(from: data)
            .components(separatedBy: .newlines)
            .flatMap(urlExtractor)
        guard !urls.isEmpty else {
            throw NativeDownloadError.unsupported("No jobs found.")
        }
        return QueueImportDocument(
            jobs: urls.map { DownloadJob(source: $0, title: $0) },
            groups: []
        )
    }

    static func searchProviders(from data: Data) throws -> [SearchProvider] {
        let data = dataByStrippingUTF8BOM(data)
        let decoder = iso8601Decoder()
        if let package = try? decoder.decode(SearchProviderPackage.self, from: data) {
            return package.providers
        }
        if let providers = try? decoder.decode([SearchProvider].self, from: data) {
            return providers
        }
        if let userData = try? decoder.decode(AppUserData.self, from: data),
           !userData.searchProviders.isEmpty {
            return userData.searchProviders
        }
        return searchProviders(fromText: importedText(from: data))
    }

    static func searchProviderData(
        _ providers: [SearchProvider],
        destinationURL: URL
    ) throws -> Data {
        if shouldExportDelimitedText(to: destinationURL) {
            return Data(searchProviderExportText(providers).utf8)
        }
        return try encodedJSON(SearchProviderPackage(providers: providers))
    }

    static func searchProviderName(forTemplate template: String) -> String {
        let rendered = SearchQueryFacade.renderedTemplate(
            template,
            query: "test"
        )
        guard let url = URL(string: rendered),
              let host = url.host?.trimmed,
              !host.isEmpty else {
            return "Search"
        }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func searchProviderImportKey(
        name: String,
        urlTemplate: String
    ) -> String {
        "\(SearchQueryFacade.providerKey(name))|\(urlTemplate.trimmed.lowercased())"
    }

    static func searchBookmarks(from data: Data) throws -> [SearchBookmark] {
        let data = dataByStrippingUTF8BOM(data)
        let decoder = iso8601Decoder()
        if let package = try? decoder.decode(SearchBookmarkPackage.self, from: data) {
            return package.bookmarks
        }
        if let bookmarks = try? decoder.decode([SearchBookmark].self, from: data) {
            return bookmarks
        }
        if let userData = try? decoder.decode(AppUserData.self, from: data),
           !userData.searchBookmarks.isEmpty {
            return userData.searchBookmarks
        }
        return searchBookmarks(fromText: importedText(from: data))
    }

    static func searchBookmarkData(
        _ bookmarks: [SearchBookmark],
        destinationURL: URL
    ) throws -> Data {
        if shouldExportDelimitedText(to: destinationURL) {
            return Data(searchBookmarkExportText(bookmarks).utf8)
        }
        return try encodedJSON(SearchBookmarkPackage(bookmarks: bookmarks))
    }

    static func queueFilterBookmarks(
        from data: Data
    ) throws -> [QueueFilterBookmark] {
        let data = dataByStrippingUTF8BOM(data)
        let decoder = iso8601Decoder()
        if let package = try? decoder.decode(
            QueueFilterBookmarkPackage.self,
            from: data
        ) {
            return package.bookmarks
        }
        if let bookmarks = try? decoder.decode(
            [QueueFilterBookmark].self,
            from: data
        ) {
            return bookmarks
        }
        if let userData = try? decoder.decode(AppUserData.self, from: data),
           !userData.queueFilterBookmarks.isEmpty {
            return userData.queueFilterBookmarks
        }
        return queueFilterBookmarks(fromText: importedText(from: data))
    }

    static func queueFilterBookmarkData(
        _ bookmarks: [QueueFilterBookmark],
        destinationURL: URL
    ) throws -> Data {
        if shouldExportDelimitedText(to: destinationURL) {
            return Data(queueFilterBookmarkExportText(bookmarks).utf8)
        }
        return try encodedJSON(
            QueueFilterBookmarkPackage(
                exportedAt: Date(),
                bookmarks: bookmarks
            )
        )
    }

    static func bookmarkImportRecords(
        from data: Data,
        normalizeInput: InputNormalizer,
        looksLikeURL: URLValidator,
        urlExtractor: URLExtractor
    ) -> [BookmarkImportRecord] {
        let data = dataByStrippingUTF8BOM(data)
        let decoder = iso8601Decoder()
        if let bookmarks = try? decoder.decode([URLBookmark].self, from: data) {
            return bookmarks.map {
                BookmarkImportRecord(
                    title: $0.title,
                    url: $0.url,
                    createdAt: $0.createdAt,
                    tags: $0.tags,
                    note: $0.note
                )
            }
        }
        if let userData = try? decoder.decode(AppUserData.self, from: data),
           !userData.bookmarks.isEmpty {
            return userData.bookmarks.map {
                BookmarkImportRecord(
                    title: $0.title,
                    url: $0.url,
                    createdAt: $0.createdAt,
                    tags: $0.tags,
                    note: $0.note
                )
            }
        }
        return bookmarkImportRecords(
            fromText: importedText(from: data),
            normalizeInput: normalizeInput,
            looksLikeURL: looksLikeURL,
            urlExtractor: urlExtractor
        )
    }

    static func bookmarkExportText(_ bookmarks: [URLBookmark]) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "title\turl\tcreated_at\ttags\tnote"
        let rows = bookmarks.map { bookmark in
            [
                tsvField(bookmark.title),
                tsvField(bookmark.url),
                formatter.string(from: bookmark.createdAt),
                tsvField(bookmark.tags.joined(separator: ",")),
                tsvField(bookmark.note)
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func normalizedBookmarkTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        return tags.compactMap { raw in
            let cleaned = raw.trimmed.trimmingCharacters(
                in: CharacterSet(charactersIn: "#")
            )
            guard !cleaned.isEmpty else { return nil }
            let key = cleaned.lowercased()
            guard seen.insert(key).inserted else { return nil }
            return cleaned
        }
    }

    static func siteRules(
        from data: Data,
        sourceURL: URL? = nil
    ) throws -> [SiteRule] {
        let data = dataByStrippingUTF8BOM(data)
        let decoder = iso8601Decoder()
        if let package = try? decoder.decode(SiteRulePackage.self, from: data) {
            return package.rules
        }
        if let rules = try? decoder.decode([SiteRule].self, from: data) {
            return rules
        }
        if let manifest = try? decoder.decode(
            SiteRulePluginManifest.self,
            from: data
        ) {
            return manifest.siteRules(sourceURL: sourceURL)
        }
        return try decoder.decode([SiteRulePluginRule].self, from: data)
            .compactMap {
                $0.siteRule(pluginName: nil, sourceURL: sourceURL)
            }
    }

    static func siteRuleData(_ rules: [SiteRule]) throws -> Data {
        try encodedJSON(SiteRulePackage(rules: rules))
    }

    static func shouldExportDelimitedText(to url: URL) -> Bool {
        ["tsv", "txt", "text"].contains(url.pathExtension.lowercased())
    }

    private static func searchProviders(fromText text: String) -> [SearchProvider] {
        var providers: [SearchProvider] = []
        let formatter = ISO8601DateFormatter()
        var header: SearchProviderTextHeader?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let delimiter: Character = trimmed.contains("\t") ? "\t" : ","
            let fields = splitDelimited(trimmed, delimiter: delimiter)
            if let detectedHeader = searchProviderHeader(from: fields) {
                header = detectedHeader
                continue
            }

            let name: String
            let template: String
            let createdAt: Date
            if let header {
                template = value(at: header.templateIndex, in: fields).trimmed
                let rawName = header.nameIndex.map {
                    value(at: $0, in: fields).trimmed
                } ?? ""
                name = rawName.isEmpty
                    ? searchProviderName(forTemplate: template)
                    : rawName
                createdAt = header.createdAtIndex.flatMap {
                    formatter.date(from: value(at: $0, in: fields).trimmed)
                } ?? Date()
            } else if fields.count >= 2 {
                name = fields[0].trimmed
                template = fields[1].trimmed
                createdAt = fields.count >= 3
                    ? formatter.date(from: fields[2].trimmed) ?? Date()
                    : Date()
            } else {
                continue
            }

            guard !template.isEmpty else { continue }
            providers.append(
                SearchProvider(
                    id: UUID(),
                    name: name.isEmpty
                        ? searchProviderName(forTemplate: template)
                        : name,
                    urlTemplate: template,
                    createdAt: createdAt
                )
            )
        }
        return providers
    }

    private static func searchProviderHeader(
        from fields: [String]
    ) -> SearchProviderTextHeader? {
        let normalized = fields.map(normalizedDelimitedHeader)
        guard let templateIndex = normalized.firstIndex(where: {
            searchProviderTemplateHeaderNames.contains($0)
        }) else {
            return nil
        }
        return SearchProviderTextHeader(
            nameIndex: normalized.firstIndex(where: {
                searchProviderNameHeaderNames.contains($0)
            }),
            templateIndex: templateIndex,
            createdAtIndex: normalized.firstIndex(where: {
                searchProviderCreatedAtHeaderNames.contains($0)
            })
        )
    }

    private static let searchProviderNameHeaderNames: Set<String> = [
        "name", "title", "provider", "site", "label", "제목", "이름",
        "제공자", "사이트"
    ]
    private static let searchProviderTemplateHeaderNames: Set<String> = [
        "template", "url_template", "search_template", "url", "search_url",
        "provider_url", "검색_url", "검색주소"
    ]
    private static let searchProviderCreatedAtHeaderNames: Set<String> = [
        "created_at", "createdat", "created", "date", "time", "timestamp",
        "생성일", "날짜"
    ]

    private static func searchProviderExportText(
        _ providers: [SearchProvider]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "name\turl_template\tcreated_at"
        let rows = providers.map { provider in
            [
                tsvField(provider.name),
                tsvField(provider.urlTemplate),
                formatter.string(from: provider.createdAt)
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func searchBookmarks(fromText text: String) -> [SearchBookmark] {
        var bookmarks: [SearchBookmark] = []
        let formatter = ISO8601DateFormatter()
        var header: SearchBookmarkTextHeader?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let delimiter: Character = trimmed.contains("\t") ? "\t" : ","
            let fields = splitDelimited(trimmed, delimiter: delimiter)
            if let detectedHeader = searchBookmarkHeader(from: fields) {
                header = detectedHeader
                continue
            }

            let title: String
            let providerName: String
            let query: String
            let createdAt: Date
            if let header {
                let headerQuery = value(
                    at: header.queryIndex,
                    in: fields
                ).trimmed
                query = headerQuery.isEmpty && fields.count == 1
                    ? fields[0].trimmed
                    : headerQuery
                title = header.titleIndex.map {
                    value(at: $0, in: fields).trimmed
                } ?? ""
                providerName = header.providerIndex.map {
                    value(at: $0, in: fields).trimmed
                } ?? ""
                createdAt = header.createdAtIndex.flatMap {
                    formatter.date(from: value(at: $0, in: fields).trimmed)
                } ?? Date()
            } else if fields.count >= 3 {
                title = fields[0].trimmed
                providerName = fields[1].trimmed
                query = fields[2].trimmed
                createdAt = fields.count >= 4
                    ? formatter.date(from: fields[3].trimmed) ?? Date()
                    : Date()
            } else if fields.count >= 2 {
                title = ""
                providerName = fields[0].trimmed
                query = fields[1].trimmed
                createdAt = Date()
            } else {
                title = ""
                providerName = ""
                query = fields.first?.trimmed ?? trimmed
                createdAt = Date()
            }
            guard !query.isEmpty else { continue }
            bookmarks.append(
                SearchBookmark(
                    title: title,
                    providerID: nil,
                    providerName: providerName,
                    query: query,
                    createdAt: createdAt
                )
            )
        }
        return bookmarks
    }

    private static func searchBookmarkHeader(
        from fields: [String]
    ) -> SearchBookmarkTextHeader? {
        let normalized = fields.map(normalizedDelimitedHeader)
        guard let queryIndex = normalized.firstIndex(where: {
            searchBookmarkQueryHeaderNames.contains($0)
        }) else {
            return nil
        }
        return SearchBookmarkTextHeader(
            titleIndex: normalized.firstIndex(where: {
                searchBookmarkTitleHeaderNames.contains($0)
            }),
            providerIndex: normalized.firstIndex(where: {
                searchBookmarkProviderHeaderNames.contains($0)
            }),
            queryIndex: queryIndex,
            createdAtIndex: normalized.firstIndex(where: {
                searchBookmarkCreatedAtHeaderNames.contains($0)
            })
        )
    }

    private static let searchBookmarkTitleHeaderNames: Set<String> = [
        "title", "name", "label", "bookmark", "bookmark_title",
        "search_title", "제목", "이름"
    ]
    private static let searchBookmarkProviderHeaderNames: Set<String> = [
        "provider", "provider_name", "site", "engine", "search_provider",
        "제공자", "사이트", "검색제공자"
    ]
    private static let searchBookmarkQueryHeaderNames: Set<String> = [
        "query", "search", "keyword", "keywords", "text", "value",
        "filter", "검색", "검색어", "쿼리"
    ]
    private static let searchBookmarkCreatedAtHeaderNames: Set<String> = [
        "created_at", "createdat", "created", "date", "time", "timestamp",
        "생성일", "날짜"
    ]

    private static func searchBookmarkExportText(
        _ bookmarks: [SearchBookmark]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "title\tprovider_name\tquery\tcreated_at"
        let rows = bookmarks.map { bookmark in
            [
                tsvField(bookmark.title),
                tsvField(bookmark.providerName),
                tsvField(bookmark.query),
                formatter.string(from: bookmark.createdAt)
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    private static func queueFilterBookmarks(
        fromText text: String
    ) -> [QueueFilterBookmark] {
        var bookmarks: [QueueFilterBookmark] = []
        let formatter = ISO8601DateFormatter()
        var header: QueueFilterBookmarkTextHeader?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmed
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }
            let delimiter: Character = trimmed.contains("\t") ? "\t" : ","
            let fields = splitDelimited(trimmed, delimiter: delimiter)
            if let detectedHeader = queueFilterBookmarkHeader(from: fields) {
                header = detectedHeader
                continue
            }

            if let header {
                let headerQuery = value(
                    at: header.queryIndex,
                    in: fields
                ).trimmed
                let query = headerQuery.isEmpty && fields.count == 1
                    ? fields[0].trimmed
                    : headerQuery
                guard !query.isEmpty else { continue }
                let title = header.titleIndex.map {
                    value(at: $0, in: fields).trimmed
                } ?? ""
                bookmarks.append(
                    QueueFilterBookmark(
                        title: title.isEmpty
                            ? queueFilterBookmarkTitle(for: query)
                            : title,
                        query: query,
                        createdAt: header.createdAtIndex.flatMap {
                            formatter.date(
                                from: value(at: $0, in: fields).trimmed
                            )
                        } ?? Date()
                    )
                )
            } else if fields.count >= 2 {
                let title = fields[0].trimmed
                let query = fields[1].trimmed
                guard !query.isEmpty else { continue }
                bookmarks.append(
                    QueueFilterBookmark(
                        title: title.isEmpty
                            ? queueFilterBookmarkTitle(for: query)
                            : title,
                        query: query,
                        createdAt: fields.count >= 3
                            ? formatter.date(from: fields[2].trimmed) ?? Date()
                            : Date()
                    )
                )
            } else if let query = fields.first?.trimmed, !query.isEmpty {
                bookmarks.append(
                    QueueFilterBookmark(
                        title: queueFilterBookmarkTitle(for: query),
                        query: query
                    )
                )
            } else {
                bookmarks.append(
                    QueueFilterBookmark(
                        title: queueFilterBookmarkTitle(for: trimmed),
                        query: trimmed
                    )
                )
            }
        }
        return bookmarks
    }

    private static func queueFilterBookmarkHeader(
        from fields: [String]
    ) -> QueueFilterBookmarkTextHeader? {
        let normalized = fields.map(normalizedDelimitedHeader)
        guard let queryIndex = normalized.firstIndex(where: {
            queueFilterBookmarkQueryHeaderNames.contains($0)
        }) else {
            return nil
        }
        return QueueFilterBookmarkTextHeader(
            titleIndex: normalized.firstIndex(where: {
                queueFilterBookmarkTitleHeaderNames.contains($0)
            }),
            queryIndex: queryIndex,
            createdAtIndex: normalized.firstIndex(where: {
                queueFilterBookmarkCreatedAtHeaderNames.contains($0)
            })
        )
    }

    private static let queueFilterBookmarkTitleHeaderNames: Set<String> = [
        "title", "name", "label", "bookmark", "bookmark_title",
        "filter_title", "제목", "이름"
    ]
    private static let queueFilterBookmarkQueryHeaderNames: Set<String> = [
        "query", "filter", "filter_query", "queue_filter", "search",
        "keyword", "keywords", "text", "value", "쿼리", "필터", "검색",
        "검색어"
    ]
    private static let queueFilterBookmarkCreatedAtHeaderNames: Set<String> = [
        "created_at", "createdat", "created", "date", "time", "timestamp",
        "생성일", "날짜"
    ]

    private static func queueFilterBookmarkExportText(
        _ bookmarks: [QueueFilterBookmark]
    ) -> String {
        let formatter = ISO8601DateFormatter()
        let header = "title\tquery\tcreated_at"
        let rows = bookmarks.map { bookmark in
            [
                tsvField(bookmark.title),
                tsvField(bookmark.query),
                formatter.string(from: bookmark.createdAt)
            ].joined(separator: "\t")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }

    static func queueFilterBookmarkTitle(for query: String) -> String {
        let cleaned = query.trimmed
        guard cleaned.count > 48 else { return cleaned }
        return String(cleaned.prefix(45)) + "..."
    }

    private static func bookmarkImportRecords(
        fromText text: String,
        normalizeInput: InputNormalizer,
        looksLikeURL: URLValidator,
        urlExtractor: URLExtractor
    ) -> [BookmarkImportRecord] {
        let formatter = ISO8601DateFormatter()
        var records: [BookmarkImportRecord] = []
        var header: BookmarkTextHeader?

        for line in text.components(separatedBy: .newlines) {
            let trimmedLine = line.trimmed
            guard !trimmedLine.isEmpty, !trimmedLine.hasPrefix("#") else {
                continue
            }
            let fields = trimmedLine.contains("\t")
                ? splitDelimited(trimmedLine, delimiter: "\t")
                : splitDelimited(trimmedLine, delimiter: ",")
            if let detectedHeader = bookmarkHeader(from: fields) {
                header = detectedHeader
                continue
            }

            if let header {
                let rawURL = value(at: header.urlIndex, in: fields).trimmed
                let normalizedURL = normalizeInput(rawURL)
                guard !rawURL.isEmpty, looksLikeURL(normalizedURL) else {
                    for url in urlExtractor(trimmedLine) {
                        records.append(
                            BookmarkImportRecord(
                                title: nil,
                                url: url,
                                createdAt: nil
                            )
                        )
                    }
                    continue
                }

                let title = header.titleIndex.map {
                    value(at: $0, in: fields).trimmed
                } ?? ""
                let note = header.noteIndex.map {
                    value(at: $0, in: fields).trimmed
                } ?? ""
                records.append(
                    BookmarkImportRecord(
                        title: title.isEmpty ? nil : title,
                        url: rawURL,
                        createdAt: header.createdAtIndex.flatMap {
                            formatter.date(
                                from: value(at: $0, in: fields).trimmed
                            )
                        },
                        tags: header.tagsIndex.map {
                            bookmarkTags(from: value(at: $0, in: fields))
                        } ?? [],
                        note: note.isEmpty ? nil : note
                    )
                )
                continue
            }

            let normalizedSecondField = fields.count >= 2
                ? normalizeInput(fields[1])
                : ""
            if fields.count >= 2,
               !looksLikeURL(normalizeInput(fields[0])),
               looksLikeURL(normalizedSecondField) {
                records.append(
                    BookmarkImportRecord(
                        title: fields[0],
                        url: fields[1],
                        createdAt: fields.count >= 3
                            ? formatter.date(from: fields[2])
                            : nil,
                        tags: fields.count >= 4
                            ? bookmarkTags(from: fields[3])
                            : [],
                        note: fields.count >= 5 ? fields[4] : nil
                    )
                )
            } else {
                for url in urlExtractor(trimmedLine) {
                    records.append(
                        BookmarkImportRecord(
                            title: nil,
                            url: url,
                            createdAt: nil
                        )
                    )
                }
            }
        }

        return records
    }

    private static func bookmarkHeader(
        from fields: [String]
    ) -> BookmarkTextHeader? {
        let normalized = fields.map(normalizedDelimitedHeader)
        guard let urlIndex = normalized.firstIndex(where: {
            bookmarkURLHeaderNames.contains($0)
        }) else {
            return nil
        }
        return BookmarkTextHeader(
            titleIndex: normalized.firstIndex(where: {
                bookmarkTitleHeaderNames.contains($0)
            }),
            urlIndex: urlIndex,
            createdAtIndex: normalized.firstIndex(where: {
                bookmarkCreatedAtHeaderNames.contains($0)
            }),
            tagsIndex: normalized.firstIndex(where: {
                bookmarkTagsHeaderNames.contains($0)
            }),
            noteIndex: normalized.firstIndex(where: {
                bookmarkNoteHeaderNames.contains($0)
            })
        )
    }

    private static let bookmarkTitleHeaderNames: Set<String> = [
        "title", "name", "label", "bookmark", "bookmark_title", "url_title",
        "site", "제목", "이름", "사이트"
    ]
    private static let bookmarkURLHeaderNames: Set<String> = [
        "url", "uri", "link", "href", "address", "source", "source_url",
        "bookmark_url", "target", "주소", "링크"
    ]
    private static let bookmarkCreatedAtHeaderNames: Set<String> = [
        "created_at", "createdat", "created", "date", "time", "timestamp",
        "added_at", "addedat", "생성일", "날짜", "추가일"
    ]
    private static let bookmarkTagsHeaderNames: Set<String> = [
        "tags", "tag", "labels", "label_tags", "categories", "category",
        "keywords", "keyword", "태그", "분류"
    ]
    private static let bookmarkNoteHeaderNames: Set<String> = [
        "note", "notes", "memo", "comment", "comments", "description",
        "desc", "remark", "remarks", "메모", "비고", "설명", "코멘트"
    ]

    private static func normalizedDelimitedHeader(_ value: String) -> String {
        stripLeadingUnicodeBOM(value)
            .trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
    }

    private static func value(at index: Int, in fields: [String]) -> String {
        guard fields.indices.contains(index) else { return "" }
        return fields[index]
    }

    private static func splitDelimited(
        _ line: String,
        delimiter: Character
    ) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var index = line.startIndex
        while index < line.endIndex {
            let character = line[index]
            if character == "\"" {
                let next = line.index(after: index)
                if inQuotes, next < line.endIndex, line[next] == "\"" {
                    field.append("\"")
                    index = line.index(after: next)
                    continue
                }
                inQuotes.toggle()
            } else if character == delimiter, !inQuotes {
                fields.append(
                    field.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                field = ""
            } else {
                field.append(character)
            }
            index = line.index(after: index)
        }
        fields.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        return fields
    }

    static func importedText(from data: Data) -> String {
        let bytes = Array(data.prefix(3))
        if bytes.count >= 2, bytes[0] == 0xFF, bytes[1] == 0xFE {
            let body = Data(data.dropFirst(2))
            return stripLeadingUnicodeBOM(
                String(data: body, encoding: .utf16LittleEndian) ?? ""
            )
        }
        if bytes.count >= 2, bytes[0] == 0xFE, bytes[1] == 0xFF {
            let body = Data(data.dropFirst(2))
            return stripLeadingUnicodeBOM(
                String(data: body, encoding: .utf16BigEndian) ?? ""
            )
        }
        let stripped = dataByStrippingUTF8BOM(data)
        let text = String(data: stripped, encoding: .utf8)
            ?? String(decoding: stripped, as: UTF8.self)
        return stripLeadingUnicodeBOM(text)
    }

    private static func dataByStrippingUTF8BOM(_ data: Data) -> Data {
        let utf8BOM: [UInt8] = [0xEF, 0xBB, 0xBF]
        guard data.starts(with: utf8BOM) else { return data }
        return Data(data.dropFirst(utf8BOM.count))
    }

    private static func stripLeadingUnicodeBOM(_ value: String) -> String {
        guard value.first == "\u{FEFF}" else { return value }
        return String(value.dropFirst())
    }

    static func bookmarkTags(from value: String) -> [String] {
        normalizedBookmarkTags(
            value.components(
                separatedBy: CharacterSet(charactersIn: ",;")
            )
        )
    }

    private static func tsvField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }

    private static func iso8601Decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private static func encodedJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(value)
    }
}
