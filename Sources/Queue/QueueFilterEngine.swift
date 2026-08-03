import Foundation

enum QueueFilterEngine {
    static func filteredJobs(
        _ jobs: [DownloadJob],
        query: String,
        duplicateKey: (DownloadJob) -> String
    ) -> [DownloadJob] {
        guard let expression = queueFilterExpression(from: query) else { return jobs }
        let context = queueFilterContext(for: jobs, duplicateKey: duplicateKey)
        return jobs.filter { queueFilterExpression(expression, matches: $0, context: context) }
    }

    static func host(for job: DownloadJob) -> String {
        queueFilterHost(for: job)
    }

    private struct QueueFilterToken {
        var field: String?
        var value: String
        var isNegated: Bool
    }

    private struct QueueFilterContext {
        var duplicateKeys: Set<String> = []
        var duplicateKeyByJobID: [UUID: String] = [:]
    }
    private typealias QueueFilterComparison = FilterComparison

    private enum QueueFilterCountKind {
        case pages
        case files
        case count
    }

    private enum QueueFilterScriptValue {
        case string(String)
        case number(Double)
        case bool(Bool)

        var stringValue: String {
            switch self {
            case .string(let value):
                return value
            case .number(let value):
                if value.rounded() == value {
                    return String(Int64(value))
                }
                return String(value)
            case .bool(let value):
                return value ? "true" : "false"
            }
        }

        var numberValue: Double? {
            switch self {
            case .number(let value):
                return value
            case .string(let value):
                return queueFilterScriptNumber(from: value)
            case .bool(let value):
                return value ? 1 : 0
            }
        }

        var boolValue: Bool {
            switch self {
            case .string(let value):
                let trimmed = value.trimmed.lowercased()
                guard !trimmed.isEmpty else { return false }
                return !["false", "0", "no", "off", "null", "nil", "none"].contains(trimmed)
            case .number(let value):
                return value != 0
            case .bool(let value):
                return value
            }
        }
    }

    private typealias QueueFilterLexeme = FilterLexeme

    private indirect enum QueueFilterExpression {
        case token(QueueFilterToken)
        case and([QueueFilterExpression])
        case or([QueueFilterExpression])
        case not(QueueFilterExpression)
    }

    private struct QueueFilterParser {
        var lexemes: [QueueFilterLexeme]
        var index = 0

        mutating func parse() -> QueueFilterExpression? {
            parseOr()
        }

        private mutating func parseOr() -> QueueFilterExpression? {
            guard var expression = parseAnd() else { return nil }
            var expressions = [expression]
            while consume(.or) {
                if let next = parseAnd() {
                    expressions.append(next)
                }
            }
            if expressions.count > 1 {
                expression = .or(expressions)
            }
            return expression
        }

        private mutating func parseAnd() -> QueueFilterExpression? {
            guard let first = parseNot() else { return nil }
            var expressions = [first]
            while true {
                if consume(.and) {
                    if let next = parseNot() {
                        expressions.append(next)
                    }
                    continue
                }
                guard startsPrimary(peek()) else { break }
                if let next = parseNot() {
                    expressions.append(next)
                } else {
                    break
                }
            }
            return expressions.count == 1 ? first : .and(expressions)
        }

        private mutating func parseNot() -> QueueFilterExpression? {
            if consume(.not), let expression = parseNot() {
                return .not(expression)
            }
            return parsePrimary()
        }

        private mutating func parsePrimary() -> QueueFilterExpression? {
            guard let lexeme = peek() else { return nil }
            switch lexeme {
            case .term(let piece):
                index += 1
                return QueueFilterEngine.queueFilterToken(from: piece).map(QueueFilterExpression.token)
            case .openGroup:
                index += 1
                let expression = parseOr()
                _ = consume(.closeGroup)
                return expression
            default:
                return nil
            }
        }

        private func peek() -> QueueFilterLexeme? {
            lexemes.indices.contains(index) ? lexemes[index] : nil
        }

        private mutating func consume(_ lexeme: QueueFilterLexeme) -> Bool {
            guard peek() == lexeme else { return false }
            index += 1
            return true
        }

        private func startsPrimary(_ lexeme: QueueFilterLexeme?) -> Bool {
            switch lexeme {
            case .term, .not, .openGroup:
                return true
            default:
                return false
            }
        }
    }

    private nonisolated static func queueFilterTokens(from query: String) -> [QueueFilterToken] {
        queueFilterPieces(from: query).compactMap(queueFilterToken(from:))
    }

    private nonisolated static func queueFilterExpression(from query: String) -> QueueFilterExpression? {
        let lexemes = queueFilterLexemes(from: query)
        guard !lexemes.isEmpty else { return nil }
        var parser = QueueFilterParser(lexemes: lexemes)
        return parser.parse()
    }

    private nonisolated static func queueFilterContext(
        for jobs: [DownloadJob],
        duplicateKey: (DownloadJob) -> String
    ) -> QueueFilterContext {
        var counts: [String: Int] = [:]
        var keysByJobID: [UUID: String] = [:]
        for job in jobs {
            let key = duplicateKey(job)
            counts[key, default: 0] += 1
            keysByJobID[job.id] = key
        }
        let duplicates = Set(counts.compactMap { key, count in count > 1 ? key : nil })
        return QueueFilterContext(duplicateKeys: duplicates, duplicateKeyByJobID: keysByJobID)
    }

    private nonisolated static func queueFilterExpression(_ expression: QueueFilterExpression, matches job: DownloadJob, context: QueueFilterContext) -> Bool {
        switch expression {
        case .token(let token):
            let matched = queueFilterToken(token, matches: job, context: context)
            return token.isNegated ? !matched : matched
        case .and(let expressions):
            return expressions.allSatisfy { queueFilterExpression($0, matches: job, context: context) }
        case .or(let expressions):
            return expressions.contains { queueFilterExpression($0, matches: job, context: context) }
        case .not(let expression):
            return !queueFilterExpression(expression, matches: job, context: context)
        }
    }

    private nonisolated static func queueFilterLexemes(from query: String) -> [QueueFilterLexeme] {
        FilterSyntaxCore.lexemes(from: query)
    }

    private nonisolated static func queueFilterToken(from piece: String) -> QueueFilterToken? {
        var value = piece.trimmed
        guard !value.isEmpty else { return nil }

        var isNegated = false
        while value.hasPrefix("-") {
            isNegated = true
            value.removeFirst()
            value = value.trimmed
        }
        guard !value.isEmpty else { return nil }

        if let comparison = queueFilterDurationComparisonToken(from: value, isNegated: isNegated) {
            return comparison
        }
        if let comparison = queueFilterCountComparisonToken(from: value, isNegated: isNegated) {
            return comparison
        }

        if let separator = value.firstIndex(of: ":") {
            let field = String(value[..<separator]).trimmed.lowercased()
            let fieldValue = stripFilterQuotes(String(value[value.index(after: separator)...]).trimmed)
            guard !field.isEmpty, !fieldValue.isEmpty || queueFilterAllowsEmptyValue(for: field) else { return nil }
            return QueueFilterToken(field: field, value: fieldValue.lowercased(), isNegated: isNegated)
        }

        return QueueFilterToken(field: nil, value: stripFilterQuotes(value).lowercased(), isNegated: isNegated)
    }

    private nonisolated static func queueFilterDurationComparisonToken(from value: String, isNegated: Bool) -> QueueFilterToken? {
        guard let match = value.range(
            of: #"^(dur|duration|duration_seconds)\s*(<=|>=|<|>)\s*(.+)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) else {
            return nil
        }

        let matched = String(value[match])
        guard let regex = try? NSRegularExpression(
            pattern: #"^(dur|duration|duration_seconds)\s*(<=|>=|<|>)\s*(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(matched.startIndex..<matched.endIndex, in: matched)
        guard let result = regex.firstMatch(in: matched, range: range),
              result.numberOfRanges == 4,
              let opRange = Range(result.range(at: 2), in: matched),
              let valueRange = Range(result.range(at: 3), in: matched) else {
            return nil
        }

        let op = String(matched[opRange])
        let threshold = stripFilterQuotes(String(matched[valueRange]).trimmed)
        guard !threshold.isEmpty else { return nil }
        return QueueFilterToken(field: "duration\(op)", value: threshold.lowercased(), isNegated: isNegated)
    }

    private nonisolated static func queueFilterCountComparisonToken(from value: String, isNegated: Bool) -> QueueFilterToken? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^(pages?|page_count|pagecount|count|files?|file_count|filecount|media_count|mediacount|total)\s*(<=|>=|<|>)\s*(.+)$"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let result = regex.firstMatch(in: value, range: range),
              result.numberOfRanges == 4,
              let fieldRange = Range(result.range(at: 1), in: value),
              let opRange = Range(result.range(at: 2), in: value),
              let valueRange = Range(result.range(at: 3), in: value) else {
            return nil
        }

        let rawField = String(value[fieldRange]).lowercased()
        let canonicalField: String
        switch rawField {
        case "page", "pages", "page_count", "pagecount":
            canonicalField = "pages"
        case "file", "files", "file_count", "filecount", "media_count", "mediacount":
            canonicalField = "files"
        default:
            canonicalField = "count"
        }

        let op = String(value[opRange])
        let threshold = stripFilterQuotes(String(value[valueRange]).trimmed)
        guard !threshold.isEmpty else { return nil }
        return QueueFilterToken(field: "\(canonicalField)\(op)", value: threshold.lowercased(), isNegated: isNegated)
    }

    private nonisolated static func queueFilterAllowsEmptyValue(for field: String) -> Bool {
        [
            "done", "complete", "completed",
            "bad", "failed",
            "dup", "duplicate", "duplicated",
            "live", "record", "recording",
            "tag", "tags",
            "pinned", "pin",
            "locked", "lock"
        ].contains(field)
    }

    private nonisolated static func queueFilterPieces(from query: String) -> [String] {
        FilterSyntaxCore.pieces(from: query)
    }

    private nonisolated static func stripFilterQuotes(_ value: String) -> String {
        FilterSyntaxCore.strippingQuotes(from: value)
    }

    private nonisolated static func queueFilterToken(_ token: QueueFilterToken, matches job: DownloadJob, context: QueueFilterContext) -> Bool {
        let value = token.value
        if value.isEmpty {
            switch token.field {
            case "done", "complete", "completed":
                return queueFilterDone(job, matches: "true")
            case "bad", "failed":
                return queueFilterBad(job, matches: "true")
            case "dup", "duplicate", "duplicated":
                return queueFilterDuplicate(job, context: context, matches: "true")
            case "live", "record", "recording":
                return queueFilterLive(job, matches: "true")
            case "tag", "tags":
                return queueFilterTags(job, matches: "none")
            case "pinned", "pin":
                return queueFilterBool(job.isPinned, matches: "true")
            case "locked", "lock":
                return queueFilterBool(job.isLocked, matches: "true")
            default:
                return true
            }
        }

        switch token.field {
        case nil:
            return queueFilterHaystack(for: job).contains(value)
        case "status", "state":
            return queueFilterStatus(job.status, matches: value)
        case "done", "complete", "completed":
            return queueFilterDone(job, matches: value)
        case "bad", "failed":
            return queueFilterBad(job, matches: value)
        case "dup", "duplicate", "duplicated":
            return queueFilterDuplicate(job, context: context, matches: value)
        case "live", "record", "recording":
            return queueFilterLive(job, matches: value)
        case "duration<", "duration<=", "duration>", "duration>=":
            guard let field = token.field,
                  let comparison = QueueFilterComparison(rawValue: String(field.dropFirst("duration".count))) else {
                return false
            }
            return queueFilterDuration(job, comparison: comparison, threshold: value)
        case "pages<", "pages<=", "pages>", "pages>=":
            guard let field = token.field,
                  let comparison = QueueFilterComparison(rawValue: String(field.dropFirst("pages".count))) else {
                return false
            }
            return queueFilterCount(job, kind: .pages, comparison: comparison, threshold: value)
        case "files<", "files<=", "files>", "files>=":
            guard let field = token.field,
                  let comparison = QueueFilterComparison(rawValue: String(field.dropFirst("files".count))) else {
                return false
            }
            return queueFilterCount(job, kind: .files, comparison: comparison, threshold: value)
        case "count<", "count<=", "count>", "count>=":
            guard let field = token.field,
                  let comparison = QueueFilterComparison(rawValue: String(field.dropFirst("count".count))) else {
                return false
            }
            return queueFilterCount(job, kind: .count, comparison: comparison, threshold: value)
        case "title", "name":
            return [job.title, job.source, job.comment]
                .joined(separator: " ")
                .lowercased()
                .contains(value) ||
                queueFilterSemanticMetadata(job, keys: queueFilterArtistMetadataKeys, matches: value)
        case "url", "source", "src":
            return job.source.lowercased().contains(value)
        case "site", "host", "domain":
            return queueFilterHost(for: job).contains(value)
        case "message", "msg", "error":
            return job.message.lowercased().contains(value)
        case "comment", "memo", "note":
            return job.comment.lowercased().contains(value)
        case "range", "page", "pages":
            return job.rangeExpression.lowercased().contains(value) ||
                queueFilterCount(job, kind: .pages, matches: value)
        case "count", "total":
            return queueFilterCount(job, kind: .count, matches: value)
        case "file", "files", "file_count", "filecount", "media_count", "mediacount":
            return queueFilterCount(job, kind: .files, matches: value)
        case "page_count", "pagecount":
            return queueFilterCount(job, kind: .pages, matches: value)
        case "output", "path", "folder":
            return job.outputPath.lowercased().contains(value)
        case "script", "extractor", "extractor_key", "handler", "tool", "rule":
            if let conditionMatch = queueFilterScriptCondition(job, matches: value) {
                return conditionMatch
            }
            return queueFilterScript(job, matches: value)
        case "tag", "tags":
            return queueFilterTags(job, matches: value)
        case "artist", "artists", "author", "authors", "creator", "creators",
             "uploader", "uploaders", "channel", "channels", "user", "username",
             "group", "groups", "circle", "circles":
            return queueFilterSemanticMetadata(job, keys: queueFilterArtistMetadataKeys, matches: value)
        case "pinned", "pin":
            return queueFilterBool(job.isPinned, matches: value)
        case "locked", "lock":
            return queueFilterBool(job.isLocked, matches: value)
        case "meta", "metadata":
            return job.metadata
                .map { "\($0.key) \($0.value)" }
                .joined(separator: " ")
                .lowercased()
                .contains(value)
        default:
            if let field = token.field,
               let metadataValue = job.metadata.first(where: { $0.key.lowercased() == field })?.value.lowercased() {
                return metadataValue.contains(value)
            }
            if let field = token.field {
                return queueFilterHaystack(for: job).contains("\(field):\(value)")
            }
            return false
        }
    }

    private nonisolated static func queueFilterHaystack(for job: DownloadJob) -> String {
        [
            job.title,
            job.source,
            queueFilterHost(for: job),
            job.status.rawValue,
            job.isPinned ? "pinned pin" : "unpinned",
            job.isLocked ? "locked lock" : "unlocked",
            job.message,
            job.comment,
            job.rangeExpression,
            job.outputPath,
            job.tags.joined(separator: " "),
            job.metadata
                .map { "\($0.key) \($0.value)" }
                .joined(separator: " ")
        ].joined(separator: " ").lowercased()
    }

    private nonisolated static let queueFilterArtistMetadataKeys: Set<String> = [
        "artist", "artists", "artist_name", "artist_names", "artistid", "artist_id",
        "author", "authors", "author_name", "author_names",
        "creator", "creators", "creator_name", "creator_names",
        "uploader", "uploaders", "uploader_name", "uploader_id",
        "channel", "channels", "channel_name", "channel_id",
        "user", "username", "user_name", "user_id", "uid",
        "member", "member_name", "owner", "owner_name",
        "group", "groups", "group_name", "group_names",
        "circle", "circles", "circle_name", "circle_names",
        "team", "studio", "publisher"
    ]

    private nonisolated static func queueFilterSemanticMetadata(
        _ job: DownloadJob,
        keys: Set<String>,
        matches value: String
    ) -> Bool {
        let normalizedNeedle = normalizedQueueFilterIdentifier(value)
        for (key, rawValue) in job.metadata {
            let normalizedKey = key.lowercased()
            guard keys.contains(normalizedKey) || keys.contains(normalizedQueueFilterIdentifier(normalizedKey)) else {
                continue
            }
            let haystack = rawValue.lowercased()
            if haystack.contains(value) {
                return true
            }
            if !normalizedNeedle.isEmpty,
               normalizedQueueFilterIdentifier(haystack).contains(normalizedNeedle) {
                return true
            }
        }
        return false
    }

    private nonisolated static func queueFilterTags(_ job: DownloadJob, matches value: String) -> Bool {
        let needle = value.trimmed.lowercased()
        let tags = queueFilterTagValues(for: job)
        let hasTags = !tags.isEmpty
        if needle.isEmpty {
            return !hasTags
        }
        if queueFilterBool(hasTags, matches: needle) {
            return true
        }
        if queueFilterNoTagAliases.contains(needle) ||
            queueFilterNoTagAliases.contains(normalizedQueueFilterIdentifier(needle)) {
            return !hasTags
        }
        if queueFilterAnyTagAliases.contains(needle) ||
            queueFilterAnyTagAliases.contains(normalizedQueueFilterIdentifier(needle)) {
            return hasTags
        }

        let normalizedNeedle = normalizedQueueFilterIdentifier(needle)
        for tag in tags {
            let lowercasedTag = tag.lowercased()
            if lowercasedTag.contains(needle) {
                return true
            }
            if !normalizedNeedle.isEmpty,
               normalizedQueueFilterIdentifier(lowercasedTag).contains(normalizedNeedle) {
                return true
            }
        }
        return false
    }

    private nonisolated static let queueFilterNoTagAliases: Set<String> = [
        "none", "missing", "empty", "untagged", "tagless", "notags", "no_tag", "no-tags",
        "no tags", "태그없음", "태그_없음", "태그-없음", "Missing"
    ]

    private nonisolated static let queueFilterAnyTagAliases: Set<String> = [
        "any", "exists", "present", "tagged", "hastags", "has_tag", "has-tags", "has tags"
    ]

    private nonisolated static func queueFilterTagValues(for job: DownloadJob) -> [String] {
        var values = TaskTagColor.normalizedRawValues(job.tags)
        for (key, rawValue) in job.metadata where queueFilterIsTagMetadataKey(key) {
            appendQueueFilterTagValues(from: rawValue, to: &values)
        }
        return values
    }

    private nonisolated static func queueFilterIsTagMetadataKey(_ key: String) -> Bool {
        let lowercased = key.lowercased()
        let normalized = normalizedQueueFilterIdentifier(lowercased)
        return lowercased == "tag" ||
            lowercased == "tags" ||
            lowercased == "hashtag" ||
            lowercased == "hashtags" ||
            lowercased == "keyword" ||
            lowercased == "keywords" ||
            lowercased.hasPrefix("tag_string") ||
            normalized.hasPrefix("tagstring")
    }

    private nonisolated static func appendQueueFilterTagValues(from rawValue: String, to values: inout [String]) {
        let raw = rawValue.trimmed
        guard queueFilterLooksLikeTagValue(raw) else { return }
        values.append(raw)

        let separators = CharacterSet(charactersIn: ",;\n\t|")
        for piece in raw.components(separatedBy: separators) {
            let tag = piece
                .trimmed
                .trimmingCharacters(in: CharacterSet(charactersIn: "#\"'[](){}"))
                .trimmed
            guard queueFilterLooksLikeTagValue(tag) else { continue }
            values.append(tag)
        }
    }

    private nonisolated static func queueFilterLooksLikeTagValue(_ value: String) -> Bool {
        let trimmed = value.trimmed
        guard !trimmed.isEmpty else { return false }
        let normalized = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "#\"'[](){}"))
            .trimmed
            .lowercased()
        guard !normalized.isEmpty else { return false }
        return ![
            "-", "--", "[]", "{}", "()", "null", "nil", "none", "no tags", "untagged"
        ].contains(normalized)
    }

    private nonisolated static func queueFilterStatus(_ status: JobStatus, matches value: String) -> Bool {
        let normalized = status.rawValue.lowercased()
        guard !normalized.contains(value) else { return true }
        switch status {
        case .queued:
            return ["queue", "queued", "wait", "waiting", "pending"].contains(value)
        case .resolving:
            return ["resolve", "resolving", "read", "reading"].contains(value)
        case .downloading:
            return ["download", "downloading", "active", "running"].contains(value)
        case .finished:
            return ["finish", "finished", "done", "complete", "completed"].contains(value)
        case .failed:
            return ["fail", "failed", "error"].contains(value)
        case .cancelled:
            return ["cancel", "cancelled", "canceled", "stop", "stopped"].contains(value)
        }
    }

    private nonisolated static func queueFilterDone(_ job: DownloadJob, matches value: String) -> Bool {
        queueFilterBool(job.status == .finished, matches: value)
    }

    private nonisolated static func queueFilterBad(_ job: DownloadJob, matches value: String) -> Bool {
        let haystack = [
            job.status.rawValue,
            job.message,
            job.metadata["last_error"] ?? "",
            job.metadata["failed_segment_url"] ?? "",
            job.metadata["failed_segment_filename"] ?? "",
            job.metadata["failed_segment_index"] ?? ""
        ].joined(separator: " ").lowercased()
        let isBad = job.status == .failed ||
            !job.metadata["last_error", default: ""].trimmed.isEmpty ||
            !job.metadata["failed_segment_url", default: ""].trimmed.isEmpty ||
            haystack.contains("error") ||
            haystack.contains("failed") ||
            haystack.contains("bad")
        return queueFilterBool(isBad, matches: value)
    }

    private nonisolated static func queueFilterDuplicate(_ job: DownloadJob, context: QueueFilterContext, matches value: String) -> Bool {
        let key = context.duplicateKeyByJobID[job.id] ?? ""
        return queueFilterBool(context.duplicateKeys.contains(key), matches: value)
    }

    private nonisolated static func queueFilterLive(_ job: DownloadJob, matches value: String) -> Bool {
        var metadata: [String: String] = [:]
        for (key, value) in job.metadata {
            metadata[key.lowercased()] = value.lowercased()
        }
        let liveFlag = metadata["live", default: ""]
        let liveStatus = metadata["live_status", default: ""]
        let wasLive = metadata["was_live", default: ""]
        let type = metadata["type", default: ""]
        let category = metadata["category", default: ""]
        let extractor = metadata["extractor_key", default: metadata["extractor", default: ""]]
        let host = queueFilterHost(for: job)
        let path = URL(string: job.source)?.path.lowercased() ?? ""
        let text = [
            job.title,
            job.source,
            job.message,
            type,
            category,
            extractor,
            liveStatus,
            wasLive
        ].joined(separator: " ").lowercased()

        let isLive = queueFilterBool(true, matches: liveFlag) ||
            ["is_live", "is live", "live", "post_live", "was_live", "was live"].contains(liveFlag) ||
            ["is_live", "is live", "live", "post_live", "was_live", "was live"].contains(liveStatus) ||
            queueFilterBool(true, matches: wasLive) ||
            type.contains("live") ||
            category.contains("live") ||
            extractor.contains("live") ||
            host.hasPrefix("live.") ||
            path.contains("/live") ||
            path.contains("/watch/lv") ||
            text.contains(" livestream") ||
            text.contains(" live stream") ||
            text.contains("recording")
        return queueFilterBool(isLive, matches: value)
    }

    private nonisolated static func queueFilterScriptCondition(_ job: DownloadJob, matches rawValue: String) -> Bool? {
        let expression = stripFilterQuotes(rawValue).trimmed
        let lowercased = expression.lowercased()
        guard lowercased.contains("item.") || lowercased.contains("item[") else {
            return nil
        }
        return queueFilterScriptBooleanExpression(expression, matches: job)
    }

    private nonisolated static func queueFilterScriptBooleanExpression(_ expression: String, matches job: DownloadJob) -> Bool? {
        let trimmed = queueFilterScriptStripOuterGroup(expression.trimmed)
        guard !trimmed.isEmpty else { return nil }

        let orParts = queueFilterScriptSplitTopLevel(trimmed, separator: "||")
        if orParts.count > 1 {
            var sawValue = false
            for part in orParts {
                if let matched = queueFilterScriptBooleanExpression(part, matches: job) {
                    sawValue = true
                    if matched {
                        return true
                    }
                }
            }
            return sawValue ? false : nil
        }

        let andParts = queueFilterScriptSplitTopLevel(trimmed, separator: "&&")
        if andParts.count > 1 {
            var sawValue = false
            for part in andParts {
                guard let matched = queueFilterScriptBooleanExpression(part, matches: job) else {
                    continue
                }
                sawValue = true
                if !matched {
                    return false
                }
            }
            return sawValue ? true : nil
        }

        if trimmed.hasPrefix("!") {
            let remainder = String(trimmed.dropFirst()).trimmed
            guard let matched = queueFilterScriptBooleanExpression(remainder, matches: job) else {
                return nil
            }
            return !matched
        }

        return queueFilterScriptComparison(trimmed, matches: job)
    }

    private nonisolated static func queueFilterScriptComparison(_ expression: String, matches job: DownloadJob) -> Bool? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^item(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[\s*['"]([^'"]+)['"]\s*\])\s*(===|!==|==|!=|>=|<=|>|<)\s*(.+)$"#,
            options: []
        ) else {
            return nil
        }
        let range = NSRange(expression.startIndex..<expression.endIndex, in: expression)
        if let match = regex.firstMatch(in: expression, range: range),
           match.numberOfRanges == 5,
           let opRange = Range(match.range(at: 3), in: expression),
           let rhsRange = Range(match.range(at: 4), in: expression) {
            let fieldRange = Range(match.range(at: 1), in: expression) ?? Range(match.range(at: 2), in: expression)
            guard let fieldRange else { return nil }
            let field = String(expression[fieldRange])
            let op = String(expression[opRange])
            let lhs = queueFilterScriptValue(for: field, job: job) ?? .string("")
            let rhs = queueFilterScriptLiteralValue(from: String(expression[rhsRange]))
            return queueFilterScriptCompare(lhs, rhs, op: op)
        }

        if let field = queueFilterScriptBareItemField(expression) {
            return (queueFilterScriptValue(for: field, job: job) ?? .string("")).boolValue
        }
        return nil
    }

    private nonisolated static func queueFilterScriptBareItemField(_ expression: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: #"^item(?:\.([A-Za-z_][A-Za-z0-9_]*)|\[\s*['"]([^'"]+)['"]\s*\])$"#,
            options: []
        ) else {
            return nil
        }
        let range = NSRange(expression.startIndex..<expression.endIndex, in: expression)
        guard let match = regex.firstMatch(in: expression, range: range) else {
            return nil
        }
        let fieldRange = Range(match.range(at: 1), in: expression) ?? Range(match.range(at: 2), in: expression)
        return fieldRange.map { String(expression[$0]) }
    }

    private nonisolated static func queueFilterScriptValue(for field: String, job: DownloadJob) -> QueueFilterScriptValue? {
        let normalizedField = normalizedQueueFilterIdentifier(field)
        switch normalizedField {
        case "title", "name":
            return .string(job.title)
        case "url", "source", "src":
            return .string(job.source)
        case "status", "state":
            return .string(job.status.rawValue)
        case "message", "msg", "error":
            return .string(job.message)
        case "comment", "memo", "note":
            return .string(job.comment)
        case "output", "path", "folder":
            return .string(job.outputPath)
        case "site", "host", "domain":
            return .string(queueFilterHost(for: job))
        case "type":
            return queueFilterScriptMetadataValue(
                job,
                keys: ["type", "category", "site", "extractor_key", "extractor", "handler"]
            ).map(QueueFilterScriptValue.string)
        case "filesize", "filesizebytes", "filebytes", "bytes", "bytecount", "contentlength", "size", "totalbytes", "expectedbytes":
            return .number(Double(DownloadJobMetadataMetrics.estimatedByteCount(for: job)))
        case "progress":
            return .number(job.progress)
        case "completed":
            return .number(Double(job.completed))
        case "total", "count":
            return .number(Double(job.total))
        case "done", "complete", "finished":
            return .bool(job.status == .finished)
        case "bad", "failed":
            return .bool(queueFilterBad(job, matches: "true"))
        case "pinned", "pin":
            return .bool(job.isPinned)
        case "locked", "lock":
            return .bool(job.isLocked)
        default:
            return queueFilterScriptMetadataValue(job, normalizedField: normalizedField).map(QueueFilterScriptValue.string)
        }
    }

    private nonisolated static func queueFilterScriptMetadataValue(_ job: DownloadJob, keys: [String]) -> String? {
        for key in keys {
            if let value = queueFilterScriptMetadataValue(job, normalizedField: normalizedQueueFilterIdentifier(key)) {
                return value
            }
        }
        return nil
    }

    private nonisolated static func queueFilterScriptMetadataValue(_ job: DownloadJob, normalizedField: String) -> String? {
        for (key, value) in job.metadata {
            guard normalizedQueueFilterIdentifier(key) == normalizedField else { continue }
            let trimmed = value.trimmed
            guard !trimmed.isEmpty else { continue }
            return trimmed
        }
        return nil
    }

    private nonisolated static func queueFilterScriptLiteralValue(from rawValue: String) -> QueueFilterScriptValue {
        let stripped = stripFilterQuotes(rawValue.trimmed)
        let lowercased = stripped.lowercased()
        if ["true", "yes", "on"].contains(lowercased) {
            return .bool(true)
        }
        if ["false", "no", "off"].contains(lowercased) {
            return .bool(false)
        }
        if let number = queueFilterScriptNumber(from: stripped) {
            return .number(number)
        }
        return .string(stripped)
    }

    private nonisolated static func queueFilterScriptCompare(
        _ lhs: QueueFilterScriptValue,
        _ rhs: QueueFilterScriptValue,
        op: String
    ) -> Bool {
        if [">", ">=", "<", "<="].contains(op),
           let lhsNumber = lhs.numberValue,
           let rhsNumber = rhs.numberValue {
            switch op {
            case ">": return lhsNumber > rhsNumber
            case ">=": return lhsNumber >= rhsNumber
            case "<": return lhsNumber < rhsNumber
            case "<=": return lhsNumber <= rhsNumber
            default: break
            }
        }

        if ["==", "===", "!=", "!=="].contains(op) {
            let equal: Bool
            if let lhsNumber = lhs.numberValue,
               let rhsNumber = rhs.numberValue,
               !(lhs.stringValue.trimmed.isEmpty || rhs.stringValue.trimmed.isEmpty) {
                equal = lhsNumber == rhsNumber
            } else {
                equal = lhs.stringValue.trimmed.lowercased() == rhs.stringValue.trimmed.lowercased()
            }
            return op.hasPrefix("!") ? !equal : equal
        }

        return false
    }

    private nonisolated static func queueFilterScriptNumber(from rawValue: String) -> Double? {
        let value = rawValue
            .trimmed
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "_", with: "")
        guard !value.isEmpty else { return nil }
        if let number = Double(value), number.isFinite {
            return number
        }

        let factors = queueFilterScriptSplitTopLevel(value, separator: "*")
        guard factors.count > 1 else { return nil }
        var product = 1.0
        for factor in factors {
            guard let number = Double(factor.trimmed), number.isFinite else {
                return nil
            }
            product *= number
        }
        return product
    }

    private nonisolated static func queueFilterScriptStripOuterGroup(_ expression: String) -> String {
        var current = expression.trimmed
        while current.hasPrefix("("), current.hasSuffix(")") {
            let inner = String(current.dropFirst().dropLast())
            guard queueFilterScriptParenthesesAreBalanced(inner) else { break }
            current = inner.trimmed
        }
        return current
    }

    private nonisolated static func queueFilterScriptParenthesesAreBalanced(_ expression: String) -> Bool {
        var depth = 0
        var quote: Character?
        for character in expression {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                continue
            }
            guard quote == nil else { continue }
            if character == "(" {
                depth += 1
            } else if character == ")" {
                depth -= 1
                if depth < 0 {
                    return false
                }
            }
        }
        return depth == 0 && quote == nil
    }

    private nonisolated static func queueFilterScriptSplitTopLevel(_ expression: String, separator: String) -> [String] {
        guard !separator.isEmpty else { return [expression] }
        var parts: [String] = []
        var current = ""
        var quote: Character?
        var depth = 0
        var index = expression.startIndex

        while index < expression.endIndex {
            let character = expression[index]
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                }
                current.append(character)
                index = expression.index(after: index)
                continue
            }

            if quote == nil {
                if character == "(" {
                    depth += 1
                } else if character == ")" {
                    depth = max(0, depth - 1)
                }

                if depth == 0, expression[index...].hasPrefix(separator) {
                    parts.append(current.trimmed)
                    current = ""
                    index = expression.index(index, offsetBy: separator.count)
                    continue
                }
            }

            current.append(character)
            index = expression.index(after: index)
        }

        parts.append(current.trimmed)
        return parts.filter { !$0.isEmpty }
    }

    private nonisolated static func queueFilterScript(_ job: DownloadJob, matches value: String) -> Bool {
        let haystack = queueFilterScriptText(for: job)
        let needle = value.trimmed.lowercased()
        guard !needle.isEmpty else { return !haystack.isEmpty }
        if haystack.contains(needle) {
            return true
        }

        let normalizedNeedle = normalizedQueueFilterIdentifier(needle)
        return !normalizedNeedle.isEmpty &&
            normalizedQueueFilterIdentifier(haystack).contains(normalizedNeedle)
    }

    private nonisolated static func queueFilterScriptText(for job: DownloadJob) -> String {
        let scriptKeys: Set<String> = [
            "script", "script_id", "script_key", "script_name",
            "extractor", "extractor_key", "extractorkey",
            "handler", "tool",
            "rule", "rule_id", "rule_host", "rule_pattern",
            "site", "host", "category", "type"
        ]
        var parts: [String] = []
        var hasBridgeMarker = false

        for (key, rawValue) in job.metadata {
            let normalizedKey = normalizedQueueFilterIdentifier(key)
            guard scriptKeys.contains(key.lowercased()) || scriptKeys.contains(normalizedKey) else {
                continue
            }
            let value = rawValue.trimmed
            guard !value.isEmpty else { continue }
            parts.append(value)
            parts.append("\(key):\(value)")
            if ["handler", "tool", "extractor", "extractor_key", "extractorkey", "script", "script_name"].contains(key.lowercased()) ||
                ["handler", "tool", "extractor", "extractorkey", "script", "scriptname"].contains(normalizedKey) {
                hasBridgeMarker = true
            }
        }

        let host = queueFilterHost(for: job)
        if !host.isEmpty {
            parts.append(host)
            parts.append(contentsOf: host.split(separator: ".").map(String.init))
        }

        let lower = parts.joined(separator: " ").lowercased()
        if lower.contains("yt-dlp") || lower.contains("ytdlp") {
            parts.append(contentsOf: ["yt-dlp", "ytdlp", "youtube-dl", "external"])
        }
        if lower.contains("command") {
            parts.append(contentsOf: ["command", "custom command", "customcommand", "script"])
        }
        if lower.contains("aria2") || lower.contains("torrent") || lower.contains("magnet") {
            parts.append(contentsOf: ["aria2", "aria2c", "torrent", "magnet"])
        }
        if !hasBridgeMarker {
            parts.append("native")
        }

        return parts.joined(separator: " ").lowercased()
    }

    private nonisolated static func normalizedQueueFilterIdentifier(_ value: String) -> String {
        value.lowercased().filter { $0.isLetter || $0.isNumber }
    }

    private nonisolated static func queueFilterDuration(
        _ job: DownloadJob,
        comparison: QueueFilterComparison,
        threshold: String
    ) -> Bool {
        guard let duration = queueFilterDurationSeconds(for: job),
              let thresholdSeconds = durationSeconds(from: threshold) else {
            return false
        }

        switch comparison {
        case .lessThan:
            return duration < thresholdSeconds
        case .lessThanOrEqual:
            return duration <= thresholdSeconds
        case .greaterThan:
            return duration > thresholdSeconds
        case .greaterThanOrEqual:
            return duration >= thresholdSeconds
        }
    }

    private nonisolated static func queueFilterDurationSeconds(for job: DownloadJob) -> Double? {
        var lowercased: [String: String] = [:]
        for (key, value) in job.metadata {
            lowercased[key.lowercased()] = value
        }
        if let value = lowercased["duration_seconds"].flatMap(durationSeconds) {
            return value
        }
        if let value = lowercased["duration"].flatMap(durationSeconds) {
            return value
        }
        if let value = lowercased["duration_string"].flatMap(durationSeconds) {
            return value
        }
        if let raw = lowercased["duration_ms"]?.trimmed,
           let milliseconds = Double(raw) {
            return milliseconds / 1000
        }
        return nil
    }

    private nonisolated static func queueFilterCount(
        _ job: DownloadJob,
        kind: QueueFilterCountKind,
        comparison: QueueFilterComparison,
        threshold: String
    ) -> Bool {
        guard let count = queueFilterCountValue(for: job, kind: kind),
              let threshold = queueFilterInteger(from: threshold) else {
            return false
        }

        switch comparison {
        case .lessThan:
            return count < threshold
        case .lessThanOrEqual:
            return count <= threshold
        case .greaterThan:
            return count > threshold
        case .greaterThanOrEqual:
            return count >= threshold
        }
    }

    private nonisolated static func queueFilterCount(
        _ job: DownloadJob,
        kind: QueueFilterCountKind,
        matches value: String
    ) -> Bool {
        let trimmed = value.trimmed
        guard let count = queueFilterCountValue(for: job, kind: kind) else {
            return false
        }
        if let comparison = queueFilterInlineComparison(from: trimmed) {
            return queueFilterCount(job, kind: kind, comparison: comparison.comparison, threshold: comparison.threshold)
        }
        guard let expected = queueFilterInteger(from: trimmed) else {
            return false
        }
        return count == expected
    }

    private nonisolated static func queueFilterCountValue(for job: DownloadJob, kind: QueueFilterCountKind) -> Int? {
        var lowercased: [String: String] = [:]
        for (key, value) in job.metadata {
            lowercased[key.lowercased()] = value
        }

        let metadataKeys: [String]
        switch kind {
        case .pages:
            metadataKeys = [
                "range_total", "page_count", "pagecount", "pages", "total_pages",
                "file_count", "filecount", "media_count", "mediacount", "asset_count"
            ]
        case .files:
            metadataKeys = [
                "range_selected", "file_count", "filecount", "media_count", "mediacount",
                "asset_count", "range_total", "page_count", "pagecount", "pages", "total_pages"
            ]
        case .count:
            metadataKeys = [
                "range_selected", "file_count", "filecount", "media_count", "mediacount",
                "asset_count", "range_total", "page_count", "pagecount", "pages", "total_pages"
            ]
        }

        for key in metadataKeys {
            if let count = lowercased[key].flatMap(queueFilterInteger) {
                return count
            }
        }

        if job.total > 0 {
            return job.total
        }
        if job.completed > 0 {
            return job.completed
        }
        return nil
    }

    private nonisolated static func queueFilterInlineComparison(from value: String) -> (comparison: QueueFilterComparison, threshold: String)? {
        FilterSyntaxCore.inlineComparison(from: value)
    }

    private nonisolated static func queueFilterInteger(from raw: String) -> Int? {
        FilterSyntaxCore.nonnegativeInteger(from: raw)
    }

    private nonisolated static func durationSeconds(from raw: String) -> Double? {
        FilterSyntaxCore.durationSeconds(from: raw)
    }

    private nonisolated static func compoundDurationSeconds(from value: String) -> Double? {
        FilterSyntaxCore.compoundDurationSeconds(from: value)
    }

    private nonisolated static func queueFilterHost(for job: DownloadJob) -> String {
        FilterSyntaxCore.normalizedHost(from: job.source)
    }

    private nonisolated static func queueFilterBool(_ flag: Bool, matches value: String) -> Bool {
        FilterSyntaxCore.bool(flag, matches: value)
    }
}
