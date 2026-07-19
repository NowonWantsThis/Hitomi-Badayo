import Foundation

enum TwitterGraphQLAPIError: LocalizedError {
    case authenticationRequired(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .authenticationRequired(let message): return message
        case .unavailable(let message): return message
        }
    }
}

struct TwitterGraphQLTimelinePage {
    var user: [String: Any]
    var tweets: [[String: Any]]
    var bottomCursor: String?
}

final class TwitterGraphQLAPI {
    static let bearerToken = "Bearer AAAAAAAAAAAAAAAAAAAAANRILgAAAAAAnNwIzUejRCOuH5E6I8xnZz4puTs%3D1Zv7ttfk8LF81IUq16cHjhLTvJu4FA33AGWWjCpTnA"
    static let tweetResultOperation = "/graphql/4hhGRbehkcUVTKf8n0f0xw/TweetResultByRestId"
    static let userByScreenNameOperation = "/graphql/2qvSHpkWTMS9i0zJAwDNiA/UserByScreenName"
    static let userMediaOperation = "/graphql/IS3w9vvPg1SJysLErvnFGg/UserMedia"
    static let userLikesOperation = "/graphql/4X8QeWbeJ0jwGHaXSxExRw/Likes"
    static let improvedTweetResultOperation = "/graphql/Vg2Akr5FzUmF0sTplA5k6g/TweetResultByRestId"
    static let improvedUserByScreenNameOperation = "/graphql/-xfUfZsnR_zqjFd-IfrN5A/UserByScreenName"
    static let improvedUserMediaOperation = "/graphql/8B9DqlaGvYyOvTCzzZWtNA/UserMedia"
    static let improvedUserLikesOperation = "/graphql/uxjTlmrTI61zreSIV1urbw/Likes"

    private let sourceURL: URL
    private let options: HTTPRequestOptions
    private let webHost: String
    private let apiHost: String
    private var guestToken: String?
    private var generatedCSRFToken: String?

    init(sourceURL: URL, options: HTTPRequestOptions = HTTPRequestOptions()) {
        self.sourceURL = sourceURL
        self.options = options
        if sourceURL.host?.lowercased().hasSuffix(".test") == true {
            webHost = "x.test"
            apiHost = "api.x.test"
        } else {
            webHost = "x.com"
            apiHost = "api.x.com"
        }
    }

    func tweetChain(tweetID: String) async throws -> [[String: Any]] {
        var results: [[String: Any]] = []
        var seen = Set<String>()
        var currentID: String? = tweetID

        while let id = currentID, seen.insert(id).inserted, results.count < 32 {
            var tweet = try await tweetResultByRestID(id)
            if !results.isEmpty, var legacy = tweet["legacy"] as? [String: Any] {
                legacy["quoted_by_id_str"] = id
                tweet["legacy"] = legacy
            }
            results.append(tweet)
            currentID = Self.stringValue((tweet["legacy"] as? [String: Any])?["quoted_status_id_str"])
        }
        return results
    }

    func tweetResultByRestID(_ tweetID: String) async throws -> [String: Any] {
        let response = try await call(
            operation: Self.tweetResultOperation,
            fallbackOperations: [Self.improvedTweetResultOperation],
            variables: [
                "tweetId": tweetID,
                "withCommunity": false,
                "includePromotedContent": false,
                "withVoice": false
            ],
            features: Self.paginationFeatures(),
            fieldToggles: Self.articleFieldToggles(richContent: true)
        )
        guard let result = Self.dictionary(response, path: ["data", "tweetResult", "result"]),
              let tweet = Self.unwrappedTweet(result) else {
            throw NativeDownloadError.unsupported("Twitter/X did not return the requested post.")
        }
        try Self.validateAvailableTweet(tweet)
        return tweet
    }

    func userByScreenName(_ screenName: String) async throws -> [String: Any] {
        let response = try await call(
            operation: Self.userByScreenNameOperation,
            fallbackOperations: [Self.improvedUserByScreenNameOperation],
            variables: [
                "screen_name": screenName,
                "withHighlightedLabel": true
            ],
            features: nil,
            fieldToggles: [
                "withPayments": false,
                "withAuxiliaryUserLabels": false
            ]
        )
        guard let user = Self.dictionary(response, path: ["data", "user"]) else {
            throw NativeDownloadError.unsupported("Twitter/X did not return the requested profile.")
        }
        return user
    }

    func timelinePage(
        user: [String: Any],
        kind: TwitterCollectionKind,
        cursor: String?
    ) async throws -> TwitterGraphQLTimelinePage {
        guard let userID = Self.userID(in: user) else {
            throw NativeDownloadError.unsupported("Twitter/X profile id was missing.")
        }

        var variables: [String: Any] = [
            "userId": userID,
            "count": 100,
            "includePromotedContent": false,
            "withClientEventToken": false,
            "withBirdwatchNotes": false,
            "withVoice": true
        ]
        if let cursor, !cursor.isEmpty {
            variables["cursor"] = cursor
        }
        let operation = kind == .likes ? Self.userLikesOperation : Self.userMediaOperation
        let fallbackOperation = kind == .likes ? Self.improvedUserLikesOperation : Self.improvedUserMediaOperation
        let response = try await call(
            operation: operation,
            fallbackOperations: [fallbackOperation],
            variables: variables,
            features: Self.paginationFeatures(),
            fieldToggles: Self.articleFieldToggles(richContent: true)
        )
        let instructions = Self.timelineInstructions(in: response)
        guard !instructions.isEmpty else {
            throw NativeDownloadError.unsupported("Twitter/X collection response did not contain a timeline.")
        }

        var tweets: [[String: Any]] = []
        var bottomCursor: String?
        for instruction in instructions {
            let type = Self.stringValue(instruction["type"]) ?? ""
            var entries: [[String: Any]] = []
            switch type {
            case "TimelineAddEntries":
                entries = instruction["entries"] as? [[String: Any]] ?? []
            case "TimelineAddToModule":
                entries = instruction["moduleItems"] as? [[String: Any]] ?? []
            case "TimelinePinEntry", "TimelineReplaceEntry":
                if let entry = instruction["entry"] as? [String: Any] {
                    entries = [entry]
                }
            default:
                continue
            }

            for entry in entries {
                if let cursorValue = Self.bottomCursor(in: entry) {
                    bottomCursor = cursorValue
                }
                guard let result = Self.firstTweetResult(in: entry),
                      let tweet = Self.unwrappedTweet(result) else {
                    continue
                }
                tweets.append(contentsOf: Self.expandedTimelineTweets(tweet))
            }
        }

        return TwitterGraphQLTimelinePage(user: user, tweets: tweets, bottomCursor: bottomCursor)
    }

    static func tweetID(in tweet: [String: Any]) -> String? {
        let legacy = tweet["legacy"] as? [String: Any]
        return stringValue(legacy?["id_str"]) ??
            stringValue(tweet["rest_id"]) ??
            stringValue(tweet["id"])
    }

    static func ownerUsername(in tweet: [String: Any]) -> String? {
        let author = authorResult(in: tweet)
        let legacy = author?["legacy"] as? [String: Any]
        return stringValue(legacy?["screen_name"]) ??
            stringValue(author?["screen_name"]) ??
            stringValue((tweet["legacy"] as? [String: Any])?["screen_name"])
    }

    static func displayName(in user: [String: Any]) -> String? {
        let result = user["result"] as? [String: Any] ?? user
        let legacy = result["legacy"] as? [String: Any]
        return stringValue(legacy?["name"]) ?? stringValue(result["name"])
    }

    static func profileImageURL(in user: [String: Any]) -> URL? {
        let result = user["result"] as? [String: Any] ?? user
        let legacy = result["legacy"] as? [String: Any]
        let raw = stringValue(legacy?["profile_image_url_https"]) ??
            stringValue(legacy?["profile_image_url"]) ??
            stringValue(result["profile_image_url_https"])
        return raw.flatMap(URL.init(string:))
    }

    static func mediaPayload(from tweet: [String: Any]) -> [String: Any] {
        var payload: [String: Any] = [:]
        if let legacy = tweet["legacy"] as? [String: Any] {
            payload["legacy"] = legacy
        }
        if let core = tweet["core"] as? [String: Any] {
            payload["core"] = core
        }
        if let restID = tweet["rest_id"] {
            payload["rest_id"] = restID
        }
        if let typename = tweet["__typename"] {
            payload["__typename"] = typename
        }
        return payload.isEmpty ? tweet : payload
    }

    private func call(
        operation: String,
        fallbackOperations: [String] = [],
        variables: [String: Any],
        features: [String: Any]?,
        fieldToggles: [String: Any]?
    ) async throws -> [String: Any] {
        var attempted = Set<String>()
        var missingOperationError: Error?
        for candidate in [operation] + fallbackOperations where attempted.insert(candidate).inserted {
            do {
                return try await callOnce(
                    operation: candidate,
                    variables: variables,
                    features: features,
                    fieldToggles: fieldToggles
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                guard Self.isMissingOperation(error) else { throw error }
                missingOperationError = error
            }
        }
        throw missingOperationError ?? NativeDownloadError.unsupported("Twitter/X GraphQL operation was unavailable.")
    }

    private func callOnce(
        operation: String,
        variables: [String: Any],
        features: [String: Any]?,
        fieldToggles: [String: Any]?
    ) async throws -> [String: Any] {
        var components = URLComponents()
        components.scheme = "https"
        components.host = webHost
        components.path = "/i/api\(operation)"
        var queryItems = [URLQueryItem(name: "variables", value: try Self.compactJSON(variables))]
        if let features {
            queryItems.append(URLQueryItem(name: "features", value: try Self.compactJSON(features)))
        }
        if let fieldToggles {
            queryItems.append(URLQueryItem(name: "fieldToggles", value: try Self.compactJSON(fieldToggles)))
        }
        components.queryItems = queryItems
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL("Twitter/X GraphQL request")
        }

        let headers = try await requestHeaders()
        let data = try await HTTPClient.shared.data(
            from: url,
            referer: "https://\(webHost)/",
            userAgent: options.userAgent,
            additionalHeaders: headers
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NativeDownloadError.unsupported("Twitter/X returned invalid GraphQL data.")
        }
        if let errors = object["errors"] as? [[String: Any]], !errors.isEmpty {
            let messages = errors.compactMap { Self.stringValue($0["message"]) }
            throw NativeDownloadError.unsupported(
                messages.isEmpty ? "Twitter/X GraphQL request failed." : messages.joined(separator: ", ")
            )
        }
        return object
    }

    private func requestHeaders() async throws -> [String: String] {
        let cookieURL = URL(string: "https://\(webHost)/")!
        let authToken = await CookieStore.shared.cookieValue(named: "auth_token", for: cookieURL)
        let savedCSRF = await CookieStore.shared.cookieValue(named: "ct0", for: cookieURL)
        if generatedCSRFToken == nil {
            generatedCSRFToken = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        }

        var headers = Self.baseHeaders(webHost: webHost)
        headers["x-csrf-token"] = savedCSRF ?? generatedCSRFToken
        if authToken != nil {
            headers["x-twitter-auth-type"] = "OAuth2Session"
        } else {
            if guestToken == nil {
                guestToken = try await activateGuest(headers: headers)
            }
            headers["x-guest-token"] = guestToken
        }
        return headers
    }

    private func activateGuest(headers: [String: String]) async throws -> String {
        var components = URLComponents()
        components.scheme = "https"
        components.host = apiHost
        components.path = "/1.1/guest/activate.json"
        guard let url = components.url else {
            throw NativeDownloadError.invalidURL("Twitter/X guest activation")
        }
        let data = try await HTTPClient.shared.postJSON(
            to: url,
            body: Data("{}".utf8),
            referer: "https://\(webHost)/",
            userAgent: options.userAgent,
            additionalHeaders: headers
        )
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = Self.stringValue(object["guest_token"]),
              !token.isEmpty else {
            throw NativeDownloadError.unsupported("Twitter/X guest session could not be created.")
        }
        return token
    }

    private static func baseHeaders(webHost: String) -> [String: String] {
        [
            "Accept": "application/json, text/plain, */*",
            "authorization": bearerToken,
            "x-twitter-client-language": "en",
            "x-twitter-active-user": "yes",
            "Origin": "https://\(webHost)",
            "Referer": "https://\(webHost)/"
        ]
    }

    private static func paginationFeatures() -> [String: Any] {
        [
            "rweb_video_screen_enabled": false,
            "rweb_cashtags_enabled": false,
            "profile_label_improvements_pcf_label_in_post_enabled": true,
            "responsive_web_profile_redirect_enabled": true,
            "rweb_tipjar_consumption_enabled": true,
            "responsive_web_graphql_exclude_directive_enabled": true,
            "verified_phone_label_enabled": false,
            "creator_subscriptions_tweet_preview_api_enabled": true,
            "responsive_web_graphql_timeline_navigation_enabled": true,
            "responsive_web_graphql_skip_user_profile_image_extensions_enabled": false,
            "premium_content_api_read_enabled": false,
            "communities_web_enable_tweet_community_results_fetch": true,
            "c9s_tweet_anatomy_moderator_badge_enabled": true,
            "responsive_web_grok_analyze_button_fetch_trends_enabled": false,
            "responsive_web_grok_analyze_post_followups_enabled": true,
            "rweb_cashtags_composer_attachment_enabled": false,
            "responsive_web_jetfuel_frame": false,
            "responsive_web_grok_share_attachment_enabled": true,
            "responsive_web_grok_annotations_enabled": true,
            "articles_preview_enabled": true,
            "responsive_web_edit_tweet_api_enabled": true,
            "rweb_conversational_replies_downvote_enabled": false,
            "graphql_is_translatable_rweb_tweet_is_translatable_enabled": true,
            "view_counts_everywhere_api_enabled": true,
            "longform_notetweets_consumption_enabled": true,
            "responsive_web_twitter_article_tweet_consumption_enabled": true,
            "content_disclosure_indicator_enabled": true,
            "content_disclosure_ai_generated_indicator_enabled": true,
            "tweet_awards_web_tipping_enabled": false,
            "responsive_web_grok_show_grok_translated_post": false,
            "responsive_web_grok_analysis_button_from_backend": true,
            "post_ctas_fetch_enabled": true,
            "creator_subscriptions_quote_tweet_preview_enabled": false,
            "freedom_of_speech_not_reach_fetch_enabled": true,
            "standardized_nudges_misinfo": true,
            "tweet_with_visibility_results_prefer_gql_limited_actions_policy_enabled": true,
            "longform_notetweets_rich_text_read_enabled": true,
            "longform_notetweets_inline_media_enabled": true,
            "responsive_web_grok_image_annotation_enabled": true,
            "responsive_web_grok_imagine_annotation_enabled": true,
            "responsive_web_grok_community_note_auto_translation_is_enabled": true,
            "responsive_web_enhance_cards_enabled": false
        ]
    }

    private static func articleFieldToggles(richContent: Bool) -> [String: Any] {
        [
            "withPayments": false,
            "withAuxiliaryUserLabels": false,
            "withArticleRichContentState": richContent,
            "withArticlePlainText": false,
            "withArticleSummaryText": false,
            "withArticleVoiceOver": false,
            "withGrokAnalyze": false,
            "withDisallowedReplyControls": false
        ]
    }

    private static func isMissingOperation(_ error: Error) -> Bool {
        guard let nativeError = error as? NativeDownloadError else { return false }
        if case NativeDownloadError.httpStatus(let status, _) = nativeError {
            return status == 404
        }
        return false
    }

    private static func compactJSON(_ value: Any) throws -> String {
        guard JSONSerialization.isValidJSONObject(value) else {
            throw NativeDownloadError.unsupported("Twitter/X GraphQL parameters were invalid.")
        }
        let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    private static func timelineInstructions(in response: [String: Any]) -> [[String: Any]] {
        let paths = [
            ["data", "user", "result", "timeline", "timeline", "instructions"],
            ["data", "user", "result", "timeline_v2", "timeline", "instructions"],
            ["data", "user", "result", "timeline", "instructions"]
        ]
        for path in paths {
            if let instructions = value(response, path: path) as? [[String: Any]] {
                return instructions
            }
        }
        return firstInstructions(in: response) ?? []
    }

    private static func firstInstructions(in value: Any) -> [[String: Any]]? {
        if let dictionary = value as? [String: Any] {
            if let instructions = dictionary["instructions"] as? [[String: Any]] {
                return instructions
            }
            for child in dictionary.values {
                if let instructions = firstInstructions(in: child) {
                    return instructions
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let instructions = firstInstructions(in: child) {
                    return instructions
                }
            }
        }
        return nil
    }

    private static func firstTweetResult(in entry: [String: Any]) -> [String: Any]? {
        let paths = [
            ["content", "itemContent", "tweet_results", "result"],
            ["item", "itemContent", "tweet_results", "result"],
            ["content", "content", "itemContent", "tweet_results", "result"],
            ["content", "items", "0", "item", "itemContent", "tweet_results", "result"]
        ]
        for path in paths {
            if let result = dictionary(entry, path: path) {
                return result
            }
        }
        return firstTweetResultRecursively(in: entry)
    }

    private static func firstTweetResultRecursively(in value: Any) -> [String: Any]? {
        if let dictionary = value as? [String: Any] {
            if let tweetResults = dictionary["tweet_results"] as? [String: Any],
               let result = tweetResults["result"] as? [String: Any] {
                return result
            }
            for (key, child) in dictionary where
                key != "quoted_status_result" && key != "retweeted_status_result" {
                if let result = firstTweetResultRecursively(in: child) {
                    return result
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let result = firstTweetResultRecursively(in: child) {
                    return result
                }
            }
        }
        return nil
    }

    private static func expandedTimelineTweets(_ rawTweet: [String: Any]) -> [[String: Any]] {
        guard (try? validateAvailableTweet(rawTweet)) != nil else { return [] }
        var tweet = rawTweet
        if let legacy = tweet["legacy"] as? [String: Any],
           let retweetedStatus = legacy["retweeted_status_result"] as? [String: Any],
           let result = retweetedStatus["result"] as? [String: Any],
           var retweet = unwrappedTweet(result) {
            if var retweetLegacy = retweet["legacy"] as? [String: Any] {
                retweetLegacy["retweeted_status_id_str"] = stringValue(retweet["rest_id"])
                retweet["legacy"] = retweetLegacy
            }
            retweet["_retweet_id_str"] = stringValue(tweet["rest_id"])
            tweet = retweet
        }

        var expanded = [tweet]
        var current = tweet
        var seen = Set(expanded.compactMap(tweetID))
        while let quoteContainer = current["quoted_status_result"] as? [String: Any],
              let quoteResult = quoteContainer["result"] as? [String: Any],
              var quote = unwrappedTweet(quoteResult),
              let quoteID = tweetID(in: quote),
              seen.insert(quoteID).inserted {
            if var legacy = quote["legacy"] as? [String: Any] {
                legacy["quoted_by_id_str"] = tweetID(in: current)
                quote["legacy"] = legacy
            }
            expanded.append(quote)
            current = quote
        }
        return expanded
    }

    private static func bottomCursor(in entry: [String: Any]) -> String? {
        let entryID = stringValue(entry["entryId"])?.lowercased() ?? ""
        if entryID.hasPrefix("cursor-bottom-") {
            return cursorValue(in: entry["content"])
        }
        return bottomCursorRecursively(in: entry)
    }

    private static func bottomCursorRecursively(in value: Any) -> String? {
        if let dictionary = value as? [String: Any] {
            let cursorType = stringValue(dictionary["cursorType"])?.lowercased()
            if cursorType == "bottom", let value = stringValue(dictionary["value"]), !value.isEmpty {
                return value
            }
            for child in dictionary.values {
                if let cursor = bottomCursorRecursively(in: child) {
                    return cursor
                }
            }
        } else if let array = value as? [Any] {
            for child in array {
                if let cursor = bottomCursorRecursively(in: child) {
                    return cursor
                }
            }
        }
        return nil
    }

    private static func cursorValue(in value: Any?) -> String? {
        if let dictionary = value as? [String: Any] {
            if let value = stringValue(dictionary["value"]), !value.isEmpty {
                return value
            }
            if let itemContent = dictionary["itemContent"] {
                return cursorValue(in: itemContent)
            }
        }
        return nil
    }

    private static func unwrappedTweet(_ result: [String: Any]) -> [String: Any]? {
        if let tweet = result["tweet"] as? [String: Any] {
            return tweet
        }
        return result
    }

    private static func validateAvailableTweet(_ tweet: [String: Any]) throws {
        guard stringValue(tweet["__typename"]) == "TweetUnavailable" else { return }
        let reason = stringValue(tweet["reason"]) ?? "unknown"
        switch reason {
        case "NsfwLoggedOut":
            throw TwitterGraphQLAPIError.authenticationRequired("Twitter/X login is required for this sensitive post.")
        case "Protected":
            throw TwitterGraphQLAPIError.unavailable("This Twitter/X post belongs to a protected account.")
        default:
            throw TwitterGraphQLAPIError.unavailable("Twitter/X post is unavailable (\(reason)).")
        }
    }

    private static func authorResult(in tweet: [String: Any]) -> [String: Any]? {
        dictionary(tweet, path: ["core", "user_results", "result"])
    }

    private static func userID(in user: [String: Any]) -> String? {
        let result = user["result"] as? [String: Any] ?? user
        return stringValue(result["rest_id"]) ??
            stringValue(result["id_str"]) ??
            stringValue((result["legacy"] as? [String: Any])?["id_str"])
    }

    private static func dictionary(_ root: [String: Any], path: [String]) -> [String: Any]? {
        value(root, path: path) as? [String: Any]
    }

    private static func value(_ root: Any, path: [String]) -> Any? {
        var current: Any = root
        for key in path {
            if let index = Int(key), let array = current as? [Any], array.indices.contains(index) {
                current = array[index]
            } else if let dictionary = current as? [String: Any], let next = dictionary[key] {
                current = next
            } else {
                return nil
            }
        }
        return current
    }

    private static func stringValue(_ value: Any?) -> String? {
        switch value {
        case let value as String:
            return value
        case let value as NSNumber:
            return value.stringValue
        default:
            return nil
        }
    }
}
