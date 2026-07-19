import CoreFoundation
import Foundation

enum OriginalHDTError: LocalizedError {
    case invalidRoot
    case missingHeader
    case invalidTask(index: Int, reason: String)
    case noTasks

    var errorDescription: String? {
        switch self {
        case .invalidRoot:
            return "The HDT file is not a JSON task array."
        case .missingHeader:
            return "The HDT header is missing or invalid."
        case .invalidTask(let index, let reason):
            return "HDT task \(index) is invalid: \(reason)"
        case .noTasks:
            return "The HDT file contains no importable tasks."
        }
    }
}

struct OriginalHDTDocument: Equatable {
    var jobs: [DownloadJob]
    var groups: [QueueGroup]
}

enum OriginalHDT {
    static let schemaVersion = "1.2"

    static func looksLikePackage(_ data: Data) -> Bool {
        guard let values = try? jsonArray(from: data),
              let header = values.first as? [String: Any] else {
            return false
        }
        return string(header["type"])?.caseInsensitiveCompare("HDT") == .orderedSame
    }

    static func decode(_ data: Data) throws -> [DownloadJob] {
        try decodeDocument(data).jobs
    }

    static func decodeDocument(_ data: Data) throws -> OriginalHDTDocument {
        let values = try jsonArray(from: data)
        guard let header = values.first as? [String: Any],
              string(header["type"])?.caseInsensitiveCompare("HDT") == .orderedSame else {
            throw OriginalHDTError.missingHeader
        }

        let packageVersion = string(header["version"]) ?? "unknown"
        var jobs: [DownloadJob] = []
        var groups: [QueueGroup] = []
        var pendingGroupChildren: [Int] = []
        for (offset, value) in values.dropFirst().enumerated() {
            let taskNumber = offset + 1
            guard let item = value as? [String: Any] else {
                throw OriginalHDTError.invalidTask(index: taskNumber, reason: "expected an object")
            }

            if bool(item["isGroup"]) == true {
                groups.append(applyGroup(item, to: pendingGroupChildren, in: &jobs))
                pendingGroupChildren.removeAll()
                continue
            }

            if let job = try decodeTask(item, packageVersion: packageVersion, index: taskNumber) {
                jobs.append(job)
                if bool(item["pad"]) == true {
                    pendingGroupChildren.append(jobs.index(before: jobs.endIndex))
                } else {
                    pendingGroupChildren.removeAll()
                }
            }
        }
        guard !jobs.isEmpty || !groups.isEmpty else { throw OriginalHDTError.noTasks }
        return OriginalHDTDocument(jobs: jobs, groups: groups)
    }

    static func encode(_ jobs: [DownloadJob]) throws -> Data {
        try encode(jobs, groups: inferredGroups(from: jobs))
    }

    static func encode(_ jobs: [DownloadJob], groups: [QueueGroup]) throws -> Data {
        var values: [Any] = [["type": "HDT", "version": schemaVersion]]
        var emittedGroupIDs = Set<UUID>()
        var emittedJobIDs = Set<UUID>()

        func emit(_ group: QueueGroup) {
            guard emittedGroupIDs.insert(group.id).inserted else { return }
            let members = jobs.filter { belongsToGroup($0, group: group) }
            for job in members {
                emittedJobIDs.insert(job.id)
                var task = encodeTask(job)
                task["pad"] = true
                values.append(task)
            }
            values.append(encodeGroup(group, jobs: members))
        }

        for job in jobs {
            for group in groups where group.anchorJobID == job.id {
                emit(group)
            }
            if emittedJobIDs.contains(job.id) { continue }
            if let group = groups.first(where: { belongsToGroup(job, group: $0) }) {
                emit(group)
            } else {
                emittedJobIDs.insert(job.id)
                values.append(encodeTask(job))
            }
        }
        for group in groups {
            emit(group)
        }
        return try JSONSerialization.data(withJSONObject: values, options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    private static func applyGroup(
        _ item: [String: Any],
        to childIndices: [Int],
        in jobs: inout [DownloadJob]
    ) -> QueueGroup {
        let name = nonemptyString(item["title"])
            ?? nonemptyString(item["title0"])
            ?? "Group"
        let comment = string(item["comment"]) ?? ""
        let uid = string(item["uid"]) ?? ""
        let expanded = bool(item["groupExpanded"]) ?? true
        let isPinned = bool(item["pin"]) ?? false
        let tags = TaskTagColor.normalizedRawValues(
            array(item["tags"]).compactMap(string)
        )
        let groupID = UUID()
        let group = QueueGroup(
            id: groupID,
            name: name,
            comment: comment,
            isExpanded: expanded,
            anchorJobID: childIndices.first.flatMap { jobs.indices.contains($0) ? jobs[$0].id : nil },
            originalUID: uid.isEmpty ? groupID.uuidString : uid,
            isPinned: isPinned,
            tags: tags
        )

        for index in childIndices where jobs.indices.contains(index) {
            jobs[index].metadata["queue_group_id"] = group.id.uuidString
            jobs[index].metadata["group"] = name
            jobs[index].metadata.removeValue(forKey: "group_name")
            if !comment.isEmpty {
                jobs[index].metadata["group_comment"] = comment
            }
            if !uid.isEmpty {
                jobs[index].metadata["hdt_group_uid"] = uid
            }
            jobs[index].metadata["hdt_group_expanded"] = expanded ? "true" : "false"
            jobs[index].metadata["hdt_group_pinned"] = isPinned ? "true" : "false"
            if !tags.isEmpty {
                jobs[index].metadata["group_tags"] = tags.joined(separator: ",")
            }
        }
        return group
    }

    private static func decodeTask(
        _ item: [String: Any],
        packageVersion: String,
        index: Int
    ) throws -> DownloadJob? {
        let isGroup = bool(item["isGroup"]) ?? false
        if isGroup { return nil }
        let source = string(item["url"])
            ?? array(item["urls"]).compactMap(string).first
            ?? ""
        if source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw OriginalHDTError.invalidTask(index: index, reason: "URL is missing")
        }

        let title = nonemptyString(item["title"])
            ?? nonemptyString(item["title0"])
            ?? source
        let progressValues = array(item["pbar"])
        let completed = max(0, integer(progressValues[safe: 0]) ?? 0)
        let total = max(0, integer(progressValues[safe: 1]) ?? 0)
        let status = importedStatus(item)
        let progress: Double
        if status == .finished {
            progress = 1
        } else if total > 0 {
            progress = min(1, max(0, Double(completed) / Double(total)))
        } else {
            progress = 0
        }

        var metadata = stringDictionary(item["data"])
        metadata["hdt_version"] = packageVersion
        metadata["hdt_item_version"] = string(item["ver"]) ?? packageVersion
        copyMetadata("hdt_type", from: item["type"], into: &metadata)
        copyMetadata("hdt_label_color", from: item["label_color"], into: &metadata)
        copyMetadata("hdt_uid", from: item["uid"], into: &metadata)
        copyMetadata("hdt_gallery_number", from: item["gal_num"], into: &metadata)
        copyMetadata("hdt_release_timestamp", from: item["release_timestamp"], into: &metadata)
        copyMetadata("release_timestamp", from: item["release_timestamp"], into: &metadata)
        copyMetadata("format", from: item["format"], into: &metadata)
        copyMetadata("date", from: item["time"], into: &metadata)
        copyMetadata("artist", from: item["artist"], into: &metadata)
        copyMetadata("byte_count", from: item["filesize_total"] ?? item["filesize"], into: &metadata)
        copyMetadata("reaction", from: item["reaction"], into: &metadata)
        copyMetadata("t_retry", from: item["t_retry"], into: &metadata)
        if let originalTitle = nonemptyString(item["title0"]) {
            metadata["title0"] = originalTitle
            if numericMetadataValue(string(item["t_retry"])) != nil {
                metadata["retry_original_title"] = originalTitle
            }
        }
        if let type = nonemptyString(item["type"]) {
            metadata["type"] = metadata["type"] ?? type
            metadata["site"] = metadata["site"] ?? type
        }
        let taskTags = TaskTagColor.normalizedRawValues(
            array(item["tags"]).compactMap(string)
        )
        if bool(item["paused"]) == true {
            metadata["hdt_paused"] = "true"
        }
        if bool(item["live"]) == true {
            metadata["live"] = "true"
        }
        let trackers = array(item["trackers"]).compactMap(string).filter { !$0.isEmpty }
        if !trackers.isEmpty {
            metadata["trackers"] = trackers.joined(separator: ",")
        }

        let directory = string(item["dir"]) ?? ""
        let archive = string(item["name_zip"]) ?? ""
        let outputPath: String
        if archive.isEmpty {
            outputPath = directory
        } else if (archive as NSString).isAbsolutePath || directory.isEmpty {
            outputPath = archive
        } else {
            outputPath = URL(fileURLWithPath: directory, isDirectory: true)
                .appendingPathComponent(archive)
                .path
        }

        let identifier = string(item["uid"]).flatMap(UUID.init(uuidString:)) ?? UUID()
        let progressMessage = string(progressValues[safe: 2]) ?? ""
        let resolvedFilenames = array(item["names"]).compactMap(string)
        let resolvedURLs = array(item["urls"]).compactMap(string)
        let messageHistory = array(item["msgs"]).compactMap(string)
        let message = nonemptyString(item["subtitle"])
            ?? messageHistory.last
            ?? progressMessage

        return DownloadJob(
            id: identifier,
            source: source,
            title: title,
            status: status,
            progress: progress,
            completed: completed,
            total: total,
            message: message,
            outputPath: outputPath,
            metadata: metadata,
            tags: taskTags,
            comment: string(item["comment"]) ?? "",
            rangeExpression: string(item["range"]) ?? "",
            isPinned: bool(item["pin"]) ?? false,
            isLocked: bool(item["lock"]) ?? false,
            resolvedFilenames: resolvedFilenames,
            resolvedURLs: resolvedURLs,
            messageHistory: messageHistory
        )
    }

    static func lightTaskObject(_ job: DownloadJob, pageCount: Int? = nil) -> [String: Any] {
        let full = encodeTask(job)
        let metadata = job.metadata
        let done = job.status == .finished
        let paused = bool(firstMetadata(metadata, keys: ["hdt_paused", "paused"])) ?? false
        let canExposeTerminalValues = done || paused
        let pages = max(0, pageCount ?? max(job.completed, job.total))

        var object: [String: Any] = [
            "ver": full["ver"] ?? schemaVersion,
            "title": job.title,
            "gal_num": full["gal_num"] ?? "",
            "music": full["music"] ?? false,
            "anime": full["anime"] ?? false,
            "valid": job.status != .failed,
            "dir": job.outputPath,
            "label_color": canExposeTerminalValues ? (full["label_color"] ?? NSNull()) : NSNull(),
            "url": job.source,
            "type": full["type"] ?? "direct",
            "filesize": canExposeTerminalValues ? (full["filesize"] ?? 0) : 0,
            "pbar": full["pbar"] ?? [job.completed, job.total, "%v / %m"],
            "time": full["time"] ?? "",
            "version": full["version"] ?? "HitomiBadayo",
            "uid": job.id.uuidString
        ]

        func add(_ key: String, _ value: Any?, when condition: Bool) {
            guard condition, let value else { return }
            object[key] = value
        }

        let artist = firstMetadata(metadata, keys: ["artist", "author", "creator"]) ?? ""
        add("artist", artist, when: !artist.isEmpty)
        if !done {
            object["done"] = false
        }

        let archiveName = full["name_zip"] as? String ?? ""
        add("name_zip", archiveName, when: done && !archiveName.isEmpty)

        let retryTimestamp = numericMetadataValue(firstMetadata(metadata, keys: ["t_retry"]))
        add("t_retry", retryTimestamp, when: retryTimestamp != nil)
        add("range", job.rangeExpression, when: !job.rangeExpression.isEmpty)
        let parsedRange = firstMetadata(metadata, keys: ["range_p", "parsed_range"]) ?? ""
        add("range_p", parsedRange, when: !parsedRange.isEmpty)

        let originalTitle = firstMetadata(
            metadata,
            keys: ["retry_original_title", "title0", "original_title"]
        ) ?? job.title
        add("title0", originalTitle, when: !originalTitle.isEmpty)
        let tags = full["tags"] as? [String] ?? []
        add("tags", tags, when: !tags.isEmpty)
        add("subtitle", job.message, when: !job.message.isEmpty)
        add("lock", true, when: job.isLocked)
        add("paused", true, when: paused)
        add("comment", job.comment, when: !job.comment.isEmpty)

        let duration = firstMetadata(metadata, keys: ["duration", "dur"]) ?? ""
        add("dur", duration, when: !duration.isEmpty)
        if job.status == .downloading,
           let totalSize = full["filesize_total"] as? Int,
           totalSize > 0 {
            object["filesize_total"] = totalSize
        }

        let thumbnail = full["icon_thumb"] as? String ?? ""
        add("icon_thumb", thumbnail, when: !thumbnail.isEmpty)
        let pageSelectorIndex = integer(firstMetadata(metadata, keys: ["ps_index"])) ?? 0
        add("ps_index", pageSelectorIndex, when: pageSelectorIndex != 0)

        let isPad = groupName(in: metadata) != nil || (bool(firstMetadata(metadata, keys: ["pad"])) ?? false)
        add("pad", true, when: isPad)
        object["groupExpanded"] = bool(firstMetadata(metadata, keys: ["hdt_group_expanded", "groupExpanded"])) ?? false

        let format = full["format"] as? String ?? ""
        add("format", format, when: !format.isEmpty)
        object["p2f"] = bool(firstMetadata(metadata, keys: ["p2f"])) ?? false

        let retryDirectory = firstMetadata(metadata, keys: ["dir_retry"]) ?? ""
        add("dir_retry", retryDirectory, when: !done && !retryDirectory.isEmpty)
        add("pin", true, when: job.isPinned)

        let live = bool(firstMetadata(metadata, keys: ["live"])) ?? false
        add("live", true, when: done && live)
        let releaseTimestamp = full["release_timestamp"] as? String ?? ""
        add("release_timestamp", releaseTimestamp, when: !releaseTimestamp.isEmpty)
        let trackers = full["trackers"] as? [String] ?? []
        add("trackers", trackers, when: !trackers.isEmpty)

        if let seeding = firstMetadata(metadata, keys: ["seeding"]) {
            if let value = bool(seeding) {
                object["seeding"] = value
            } else if let value = integer(seeding) {
                object["seeding"] = value
            } else {
                object["seeding"] = seeding
            }
        }

        object["pages"] = pages
        object["lazy"] = false
        return object
    }

    private static func encodeTask(_ job: DownloadJob) -> [String: Any] {
        let metadata = job.metadata
        let type = firstMetadata(metadata, keys: ["type", "site", "handler", "python_downloader_type"]) ?? "direct"
        let artist = firstMetadata(metadata, keys: ["artist", "author", "creator"]) ?? ""
        let galleryNumber = firstMetadata(metadata, keys: ["gallery_id", "gallery_number", "media_id"]) ?? ""
        let format = firstMetadata(metadata, keys: ["format", "ext", "extension"]) ?? ""
        let date = firstMetadata(metadata, keys: ["date", "completed_at", "downloaded_at"]) ?? ""
        let byteCount = integer(firstMetadata(metadata, keys: ["byte_count", "filesize", "total_bytes"])) ?? 0
        let tags = TaskTagColor.normalizedRawValues(job.tags)
        let trackers = splitList(firstMetadata(metadata, keys: ["trackers", "tracker"]) ?? "")
        let outputExtension = URL(fileURLWithPath: job.outputPath).pathExtension.lowercased()
        let archiveName = ["zip", "cbz"].contains(outputExtension) ? job.outputPath : ""
        let music = firstMetadata(metadata, keys: ["media_request", "category"])?.lowercased() == "audio"
            || !firstMetadata(metadata, keys: ["audio_format"]).orEmpty.isEmpty
        let anime = firstMetadata(metadata, keys: ["category", "media_type"])?.lowercased() == "video"

        let originalTitle = firstMetadata(
            metadata,
            keys: ["retry_original_title", "title0", "original_title"]
        ) ?? job.title
        let retryTimestamp = numericMetadataValue(firstMetadata(metadata, keys: ["t_retry"])) ?? 0

        var object: [String: Any] = [
            "ver": schemaVersion,
            "title": job.title,
            "title0": originalTitle,
            "gal_num": galleryNumber,
            "music": music,
            "anime": anime,
            "valid": job.status != .failed,
            "dir": job.outputPath,
            "label_color": labelColor(for: job.status),
            "url": job.source,
            "type": type,
            "filesize": byteCount,
            "filesize_total": byteCount,
            "pbar": [job.completed, job.total, "%v / %m"],
            "time": date,
            "version": "HitomiBadayo",
            "uid": job.id.uuidString,
            "artist": artist,
            "done": job.status == .finished,
            "name_zip": archiveName,
            "urls": job.resolvedURLs,
            "t_retry": retryTimestamp,
            "range": job.rangeExpression,
            "range_p": "",
            "dones": job.status == .finished ? job.resolvedFilenames : [],
            "tags": tags,
            "msgs": job.messageHistory.isEmpty
                ? (job.message.isEmpty ? [] : [job.message])
                : job.messageHistory,
            "subtitle": job.message,
            "lock": job.isLocked,
            "paused": metadata["hdt_paused"]?.lowercased() == "true",
            "isGroup": false,
            "comment": job.comment,
            "dur": firstMetadata(metadata, keys: ["duration", "dur"]) ?? "",
            "names": job.resolvedFilenames,
            "icon_thumb": firstMetadata(metadata, keys: ["thumbnail", "thumbnail_url", "cover"]) ?? "",
            "ps_index": 0,
            "pad": false,
            "groupExpanded": false,
            "format": format,
            "data": metadata,
            "p2f": false,
            "alerts": [:],
            "dir_retry": "",
            "names_old": [],
            "imgs_tmp": [],
            "iconFixed": false,
            "pin": job.isPinned,
            "live": metadata["live"]?.lowercased() == "true",
            "release_timestamp": firstMetadata(metadata, keys: ["release_timestamp", "hdt_release_timestamp"]) ?? "",
            "trackers": trackers,
            "files_lazy": [],
            "extras": ["hitomi_native": true]
        ]
        if let reaction = firstMetadata(metadata, keys: ["reaction"]) {
            object["reaction"] = reaction
        }
        return object
    }

    private static func encodeGroup(_ group: QueueGroup, jobs: [DownloadJob]) -> [String: Any] {
        let metadata = jobs.first?.metadata ?? [:]
        let inheritedComment = jobs.lazy
            .compactMap { firstMetadata($0.metadata, keys: ["group_comment"]) }
            .first ?? ""
        let comment = group.comment.isEmpty ? inheritedComment : group.comment
        let inheritedUID = firstMetadata(metadata, keys: ["hdt_group_uid"]) ?? ""
        let uid = group.originalUID.isEmpty
            ? (inheritedUID.isEmpty ? group.id.uuidString : inheritedUID)
            : group.originalUID
        var object: [String: Any] = [
            "ver": schemaVersion,
            "title": group.name,
            "title0": group.name,
            "uid": uid,
            "isGroup": true,
            "groupExpanded": group.isExpanded,
            "comment": comment
        ]
        let tags = TaskTagColor.normalizedRawValues(group.tags)
        if !tags.isEmpty {
            object["tags"] = tags
        }
        if group.isPinned {
            object["pin"] = true
        }
        return object
    }

    private static func inferredGroups(from jobs: [DownloadJob]) -> [QueueGroup] {
        var groups: [QueueGroup] = []
        var explicitGroupIDs = Set<UUID>()
        var legacyNames = Set<String>()

        for job in jobs {
            guard let name = groupName(in: job.metadata) else { continue }
            let explicitID = firstMetadata(job.metadata, keys: ["queue_group_id"])
                .flatMap(UUID.init(uuidString:))
            if let explicitID {
                guard explicitGroupIDs.insert(explicitID).inserted else { continue }
            } else {
                let key = name.lowercased()
                guard legacyNames.insert(key).inserted else { continue }
            }

            let id = explicitID ?? UUID()
            let originalUID = firstMetadata(job.metadata, keys: ["hdt_group_uid"]) ?? id.uuidString
            let tags = TaskTagColor.normalizedRawValues(
                splitList(firstMetadata(job.metadata, keys: ["group_tags", "hdt_group_tags"]) ?? "")
            )
            groups.append(QueueGroup(
                id: id,
                name: name,
                comment: firstMetadata(job.metadata, keys: ["group_comment"]) ?? "",
                isExpanded: bool(firstMetadata(job.metadata, keys: ["hdt_group_expanded"])) ?? true,
                anchorJobID: job.id,
                originalUID: originalUID,
                isPinned: bool(firstMetadata(job.metadata, keys: ["hdt_group_pinned"])) ?? false,
                tags: tags
            ))
        }
        return groups
    }

    private static func belongsToGroup(_ job: DownloadJob, group: QueueGroup) -> Bool {
        if let id = firstMetadata(job.metadata, keys: ["queue_group_id"])
            .flatMap(UUID.init(uuidString:)) {
            return id == group.id
        }
        return groupName(in: job.metadata) == group.name
    }

    private static func importedStatus(_ item: [String: Any]) -> JobStatus {
        if bool(item["done"]) == true { return .finished }
        let label = string(item["label_color"])?.lowercased() ?? ""
        if bool(item["valid"]) == false || label.contains("error") || label.contains("fail") || label.contains("invalid") {
            return .failed
        }
        if label.contains("cancel") || label.contains("stop") { return .cancelled }
        if label.contains("download") { return .downloading }
        if label.contains("read") || label.contains("resolv") { return .resolving }
        return .queued
    }

    private static func labelColor(for status: JobStatus) -> String {
        switch status {
        case .queued: return "ready"
        case .resolving: return "reading"
        case .downloading: return "downloading"
        case .finished: return "downloaded"
        case .failed: return "error"
        case .cancelled: return "stopped"
        }
    }

    private static func jsonArray(from data: Data) throws -> [Any] {
        let stripped = stripUTF8BOM(data)
        guard let values = try JSONSerialization.jsonObject(with: stripped) as? [Any] else {
            throw OriginalHDTError.invalidRoot
        }
        return values
    }

    private static func stripUTF8BOM(_ data: Data) -> Data {
        let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
        return data.starts(with: bom) ? Data(data.dropFirst(bom.count)) : data
    }

    private static func string(_ value: Any?) -> String? {
        guard let value, !(value is NSNull) else { return nil }
        if let value = value as? String { return value }
        if let number = value as? NSNumber {
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        }
        return nil
    }

    private static func nonemptyString(_ value: Any?) -> String? {
        guard let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        guard let value = string(value)?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        return Int(value) ?? Double(value).map(Int.init)
    }

    private static func numericMetadataValue(_ value: String?) -> NSNumber? {
        guard let raw = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              let number = Double(raw),
              number.isFinite else {
            return nil
        }
        if number.rounded() == number,
           number >= Double(Int64.min),
           number <= Double(Int64.max) {
            return NSNumber(value: Int64(number))
        }
        return NSNumber(value: number)
    }

    private static func bool(_ value: Any?) -> Bool? {
        guard let value, !(value is NSNull) else { return nil }
        if let number = value as? NSNumber { return number.boolValue }
        switch string(value)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "yes", "on": return true
        case "0", "false", "no", "off", "": return false
        default: return nil
        }
    }

    private static func array(_ value: Any?) -> [Any] {
        value as? [Any] ?? []
    }

    private static func stringDictionary(_ value: Any?) -> [String: String] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: String] = [:]
        for (key, value) in dictionary {
            if let scalar = string(value) {
                result[key] = scalar
            } else if JSONSerialization.isValidJSONObject(value),
                      let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
                      let encoded = String(data: data, encoding: .utf8) {
                result[key] = encoded
            }
        }
        return result
    }

    private static func copyMetadata(_ key: String, from value: Any?, into metadata: inout [String: String]) {
        if let value = string(value), !value.isEmpty {
            metadata[key] = value
        }
    }

    private static func firstMetadata(_ metadata: [String: String], keys: [String]) -> String? {
        for key in keys {
            if let value = metadata.first(where: { $0.key.caseInsensitiveCompare(key) == .orderedSame })?.value,
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return value
            }
        }
        return nil
    }

    private static func groupName(in metadata: [String: String]) -> String? {
        firstMetadata(metadata, keys: ["group", "group_name"])
    }

    private static func splitList(_ value: String) -> [String] {
        value
            .components(separatedBy: CharacterSet(charactersIn: ",;\n"))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension Optional where Wrapped == String {
    var orEmpty: String { self ?? "" }
}
