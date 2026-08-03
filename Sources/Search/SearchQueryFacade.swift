import Foundation

struct SearchQuickRequest: Equatable {
    var providerKey: String?
    var query: String
}

enum SearchQueryFacade {
    nonisolated static func builtURL(
        providers: [SearchProvider],
        selectedProviderID: UUID,
        query: String
    ) -> URL? {
        guard let provider = selectedProvider(
            in: providers,
            selectedProviderID: selectedProviderID
        ) else {
            return nil
        }
        return searchURL(provider: provider, query: query)
    }

    nonisolated static func selectedProvider(
        in providers: [SearchProvider],
        selectedProviderID: UUID
    ) -> SearchProvider? {
        providers.first {
            $0.id == selectedProviderID
        } ?? providers.first
    }

    nonisolated static func hitomiProvider(
        in providers: [SearchProvider]
    ) -> SearchProvider? {
        provider(matching: "hitomi", in: providers) ??
            providers.first {
                $0.name.localizedCaseInsensitiveContains(
                    "hitomi"
                )
            }
    }

    nonisolated static func quickURL(
        from line: String,
        providers: [SearchProvider],
        selectedProviderID: UUID
    ) -> URL? {
        guard let request = quickRequest(from: line) else {
            return nil
        }
        let resolvedProvider: SearchProvider?
        if let key = request.providerKey {
            resolvedProvider = provider(
                matching: key,
                in: providers
            )
        } else {
            resolvedProvider = selectedProvider(
                in: providers,
                selectedProviderID: selectedProviderID
            )
        }
        guard let resolvedProvider else {
            return nil
        }
        return searchURL(
            provider: resolvedProvider,
            query: request.query
        )
    }

    nonisolated static func searchURL(
        provider: SearchProvider,
        query: String
    ) -> URL? {
        let query = query.trimmed
        guard !query.isEmpty else {
            return nil
        }
        return URL(
            string: renderedTemplate(
                provider.urlTemplate,
                query: query
            )
        )
    }

    nonisolated static func isValidTemplate(
        _ template: String
    ) -> Bool {
        guard template.contains("{query}") ||
                template.contains("{query+}") else {
            return false
        }
        return URL(
            string: renderedTemplate(
                template,
                query: "test query"
            )
        ) != nil
    }

    nonisolated static func renderedTemplate(
        _ template: String,
        query: String
    ) -> String {
        let allowed = CharacterSet.urlQueryAllowed
            .subtracting(
                CharacterSet(charactersIn: "&+")
            )
        let encoded = query.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? query
        let plusEncoded = encoded.replacingOccurrences(
            of: "%20",
            with: "+"
        )
        return template
            .replacingOccurrences(
                of: "{query+}",
                with: plusEncoded
            )
            .replacingOccurrences(
                of: "{query}",
                with: encoded
            )
    }

    nonisolated static func quickRequest(
        from line: String
    ) -> SearchQuickRequest? {
        let value = line.trimmed
        guard !value.isEmpty else {
            return nil
        }

        if value.hasPrefix("?") {
            let query = String(value.dropFirst()).trimmed
            return query.isEmpty
                ? nil
                : SearchQuickRequest(
                    providerKey: nil,
                    query: query
                )
        }

        if let bracketEnd = value.firstIndex(of: "]"),
           value.hasPrefix("[") {
            let key = String(
                value[
                    value.index(after: value.startIndex)..<bracketEnd
                ]
            ).trimmed
            let query = String(
                value[value.index(after: bracketEnd)...]
            ).trimmed
            if !key.isEmpty, !query.isEmpty {
                return SearchQuickRequest(
                    providerKey: key,
                    query: query
                )
            }
        }

        guard let separator = value.firstIndex(of: ":") else {
            return nil
        }
        let key = String(value[..<separator]).trimmed
        let query = String(
            value[value.index(after: separator)...]
        ).trimmed
        guard !key.isEmpty,
              !query.isEmpty,
              key.range(
                of: #"^[A-Za-z][A-Za-z0-9 _.-]*$"#,
                options: .regularExpression
              ) != nil else {
            return nil
        }
        return SearchQuickRequest(
            providerKey: key,
            query: query
        )
    }

    nonisolated static func provider(
        matching rawKey: String,
        in providers: [SearchProvider]
    ) -> SearchProvider? {
        let key = providerKey(rawKey)
        guard !key.isEmpty else {
            return nil
        }
        if let provider = providers.first(where: {
            providerKey($0.name) == key
        }) {
            return provider
        }
        if key == "yt" {
            return providers.first {
                providerKey($0.name) == "youtube"
            }
        }
        let matching = providers.filter {
            providerKey($0.name).hasPrefix(key)
        }
        return matching.count == 1 ? matching[0] : nil
    }

    nonisolated static func provider(
        for bookmark: SearchBookmark,
        in providers: [SearchProvider]
    ) -> SearchProvider? {
        if let id = bookmark.providerID,
           let provider = providers.first(where: {
               $0.id == id
           }) {
            return provider
        }
        return provider(
            matching: bookmark.providerName,
            in: providers
        ) ?? providers.first
    }

    nonisolated static func bookmarkTitle(
        providerName: String,
        query: String
    ) -> String {
        let prefix = providerName.trimmed.isEmpty
            ? "Search"
            : providerName.trimmed
        let query = query.trimmed
        let value = query.count > 80
            ? "\(query.prefix(77))..."
            : query
        return "\(prefix): \(value)"
    }

    nonisolated static func bookmarkKey(
        providerName: String,
        query: String
    ) -> String {
        "\(providerKey(providerName))|\(query.trimmed.lowercased())"
    }

    nonisolated static func providerKey(
        _ value: String
    ) -> String {
        value.lowercased().filter {
            $0.isLetter || $0.isNumber
        }
    }
}
