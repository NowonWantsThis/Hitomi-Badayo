import Foundation

struct FourChanSearchResultResolver: SearchResultResolving {
    func supports(_ baseURL: URL) -> Bool {
        guard let host = baseURL.host?.lowercased() else { return false }
        return Self.isSupportedHost(host)
    }

    static func isSupportedHost(_ host: String) -> Bool {
        host == "boards.4chan.org" ||
            host == "boards.4channel.org" ||
            host == "4chan.org" ||
            host == "www.4chan.org" ||
            host == "4channel.org" ||
            host == "www.4channel.org" ||
            host == "a.4cdn.org" ||
            host == "boards.4chan.test" ||
            host == "boards.4channel.test" ||
            host == "a.4cdn.test"
    }

    static func dataAttributeLinkValue(
        in attributes: [String: String],
        baseURL: URL?
    ) -> String? {
        guard let baseURL,
              let host = baseURL.host?.lowercased(),
              isSupportedHost(host),
              let board = dataAttributeBoard(in: attributes) ??
                boardFromBaseURL(baseURL),
              let threadID = dataAttributeThreadID(in: attributes),
              dataAttributeLooksLikeThreadCard(attributes) else {
            return nil
        }
        return "/\(board)/thread/\(threadID)"
    }

    func extract(from context: SearchResultResolverContext) -> [SearchResultLink] {
        var results: [SearchResultLink] = []
        var indexByThreadID: [String: Int] = [:]

        for anchor in context.anchors {
            guard results.count < context.limit,
                  let absolute = context.resolvedURL(for: anchor),
                  let thread = thread(from: absolute),
                  let target = threadURL(for: thread, sourceURL: absolute) else {
                continue
            }

            let resultID = "\(thread.board)-\(thread.id)"
            let title = context.title(
                for: anchor,
                fallback: "4chan \(thread.board) \(thread.id)"
            )
            SearchResultResolverSupport.appendUniqueResult(
                title: title,
                url: target,
                id: resultID,
                sitePrefix: "4chan",
                results: &results,
                indexByID: &indexByThreadID,
                metadata: metadata(thread: thread, title: title)
            )
        }

        return results
    }

    private func thread(from url: URL) -> (board: String, id: String)? {
        guard let host = url.host?.lowercased(), Self.isSupportedHost(host) else { return nil }
        let parts = url.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard parts.count >= 3,
              parts[1].lowercased() == "thread" else {
            return nil
        }

        let board = parts[0].trimmed
        let id = (parts[2] as NSString).deletingPathExtension.trimmed
        guard !board.isEmpty, !id.isEmpty, id.allSatisfy(\.isNumber) else {
            return nil
        }
        return (board, id)
    }

    private func threadURL(
        for thread: (board: String, id: String),
        sourceURL: URL
    ) -> URL? {
        let sourceHost = sourceURL.host?.lowercased() ?? ""
        var components = URLComponents()
        components.scheme = sourceURL.scheme ?? "https"
        if sourceHost.hasSuffix(".test") {
            components.host = sourceHost.contains("4channel")
                ? "boards.4channel.test"
                : "boards.4chan.test"
        } else {
            components.host = sourceHost.contains("4channel")
                ? "boards.4channel.org"
                : "boards.4chan.org"
        }
        components.path = "/\(thread.board)/thread/\(thread.id)"
        return components.url
    }

    private func metadata(
        thread: (board: String, id: String),
        title: String
    ) -> [String: String] {
        DownloadMetadata.clean([
            "id": thread.id,
            "thread_id": thread.id,
            "media_id": thread.id,
            "gallery_id": thread.id,
            "board_id": thread.board,
            "channel": thread.board,
            "tag": thread.board,
            "category": "4chan",
            "type": "thread",
            "title": title,
            "search_title": title
        ])
    }

    private static func dataAttributeBoard(
        in attributes: [String: String]
    ) -> String? {
        firstAttributeValue(
            in: attributes,
            keys: [
                "data-board", "data-board-id", "data-boardid", "board"
            ],
            matching: isBoardID
        )
    }

    private static func boardFromBaseURL(_ baseURL: URL) -> String? {
        guard let host = baseURL.host?.lowercased(),
              isSupportedHost(host) else {
            return nil
        }
        let parts = baseURL.path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        guard let first = parts.first, isBoardID(first) else {
            return nil
        }
        return first
    }

    private static func dataAttributeThreadID(
        in attributes: [String: String]
    ) -> String? {
        let keys = [
            "data-thread-id", "data-threadid", "data-no",
            "data-post-id", "thread-id"
        ]
        if let value = firstAttributeValue(
            in: attributes,
            keys: keys,
            matching: isThreadID
        ) {
            return value
        }
        if let id = attributes["data-id"]?.trimmed,
           isThreadID(id),
           typeHint(
               in: attributes,
               containsAnyOf: ["thread", "op"]
           ) {
            return id
        }
        return nil
    }

    private static func dataAttributeLooksLikeThreadCard(
        _ attributes: [String: String]
    ) -> Bool {
        let keys = [
            "data-thread-id", "data-threadid", "data-no", "thread-id"
        ]
        if keys.contains(where: {
            attributes[$0]?.trimmed.isEmpty == false
        }) {
            return true
        }
        return typeHint(
            in: attributes,
            containsAnyOf: ["thread", "op"]
        )
    }

    private static func isBoardID(_ value: String) -> Bool {
        value.range(
            of: #"^[A-Za-z0-9]{1,16}$"#,
            options: .regularExpression
        ) != nil
    }

    private static func isThreadID(_ value: String) -> Bool {
        value.range(
            of: #"^[0-9]+$"#,
            options: .regularExpression
        ) != nil
    }

    private static func firstAttributeValue(
        in attributes: [String: String],
        keys: [String],
        matching predicate: (String) -> Bool
    ) -> String? {
        for key in keys {
            if let value = attributes[key]?.trimmed,
               predicate(value) {
                return value
            }
        }
        return nil
    }

    private static func typeHint(
        in attributes: [String: String],
        containsAnyOf needles: [String]
    ) -> Bool {
        let keys = [
            "data-type", "data-kind", "data-content-type",
            "data-renderer", "class", "role"
        ]
        let values = keys.compactMap {
            attributes[$0]?.lowercased()
        }
        return values.contains { value in
            needles.contains { value.contains($0) }
        }
    }
}
