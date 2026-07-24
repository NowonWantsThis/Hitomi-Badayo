import AppKit
import Combine
import Darwin
import Foundation

@MainActor
final class OriginalJobInfoLoader: ObservableObject {
    @Published private(set) var outputFiles: [OutputPreviewFile] = []

    func load(outputPath: String) async {
        let files = await Task.detached(priority: .utility) {
            OutputPreviewFileScanner.files(at: outputPath)
        }.value
        guard !Task.isCancelled else { return }
        outputFiles = files
    }
}

struct OriginalJobInfoFileEntry: Identifiable, Equatable {
    var index: Int
    var name: String
    var isAvailable: Bool

    var id: Int { index }
    var displayText: String {
        String(format: "[%04d] %@", index + 1, name)
    }
}

struct OriginalJobInfoDocument: Equatable {
    var title: String
    var propertyLines: [String]
    var galleryLines: [String]
    var files: [OriginalJobInfoFileEntry]
    var urls: [String]
    var messages: [String]

    var plainText: String {
        var sections = [propertyLines.joined(separator: "\n")]
        if !galleryLines.isEmpty {
            sections.append("[Gallery]\n" + galleryLines.joined(separator: "\n"))
        }
        sections.append("[File Names]\n" + files.map(\.displayText).joined(separator: "\n"))
        sections.append("[URLs]\n" + numbered(urls).joined(separator: "\n"))
        if !messages.isEmpty {
            sections.append("[Messages]\n" + numbered(messages).joined(separator: "\n"))
        }
        return sections.joined(separator: "\n\n\n")
    }

    static func make(
        job: DownloadJob,
        queueIndex: Int?,
        groupName: String?,
        outputFiles: [OutputPreviewFile],
        appVersion: String = currentAppVersion(),
        platform: String = ProcessInfo.processInfo.operatingSystemVersionString,
        locale: String = Locale.current.identifier,
        screenResolution: String = currentScreenResolution(),
        isAdministrator: Bool = geteuid() == 0,
        now: Date = Date()
    ) -> OriginalJobInfoDocument {
        let metadata = job.metadata
        let format = first(metadata, ["format", "ext", "extension"])
            ?? URL(fileURLWithPath: job.outputPath).pathExtension.lowercased()
        let itemVersion = first(metadata, ["hdt_item_version", "version", "resolver_version"]) ?? appVersion
        let buildDate = first(metadata, ["release_timestamp", "build_date", "date_compile"]) ?? ""
        let versionSuffix = buildDate.isEmpty ? "" : " (\(buildDate))"
        let input = first(metadata, ["gallery_id", "gallery_number", "gal_num", "media_id", "input"]) ?? ""
        let type = first(metadata, ["type", "site", "handler", "python_downloader_type"]) ?? ""
        let artist = first(metadata, ["artist", "artists", "author", "creator"]) ?? ""
        let archive = archivePath(job.outputPath)
        let rangeParsed = first(metadata, ["range_p", "parsed_range"]) ?? ""
        let date = first(metadata, [
            "download_completed_at", "live_started_at", "date", "upload_date", "created_at", "timestamp"
        ]) ?? ""
        let elapsed = elapsedDescription(from: date, now: now)
        let extras = metadata.keys.sorted().map { key in
            "\(key)=\(metadata[key] ?? "")"
        }.joined(separator: ", ")
        let live = boolean(first(metadata, ["live", "is_live"])) ?? false
        let paused = boolean(first(metadata, ["hdt_paused", "paused"])) ?? false
        let changed = boolean(first(metadata, ["native_changed", "changed"]))
            ?? (job.title != job.source || !job.comment.isEmpty)
        let single = boolean(first(metadata, ["single"]))
            ?? (job.total == 1 || (job.total == 0 && !job.outputPath.isEmpty && archive.isEmpty))
        let valid = job.status != .failed
        let done = job.status == .finished
        let normalizedGroupName = groupName?.trimmed ?? ""
        let group = normalizedGroupName.isEmpty ? "False" : normalizedGroupName
        let order = queueIndex.map { String($0 + 1) } ?? "?"
        let tags = "[" + job.tags.map { "'\($0)'" }.joined(separator: ", ") + "]"
        let time = date.isEmpty ? "" : "\(date)\(elapsed)"
        let ytdl = first(metadata, ["ytdlp_version", "yt_dlp_version", "ytdl_version", "ytdl"]) ?? ""
        let segment = first(metadata, ["segment_count", "total_segments", "v3"]) ?? ""
        let fileResult = job.partialFailureCounts.map {
            "\($0.succeeded) succeeded / \($0.failed) failed / \($0.total) total"
        } ?? "\(job.completed) completed / \(job.total) total"

        let propertyLines = [
            job.title,
            "",
            "status: \(job.statusDisplayText())",
            "files: \(fileResult)",
            "version: \(itemVersion)\(versionSuffix)",
            "platform / locale: \(platform) / \(locale)",
            "order / group / uid: \(order) / \(group) / \(job.id.uuidString)",
            "input: \(input)",
            "type: \(type)",
            "single: \(single)",
            "url: \(job.source)",
            "dir: \(job.outputPath)",
            "zip: \(archive)",
            "artist: \(artist)",
            "valid / done: \(valid) / \(done)",
            "range / range_p: \(job.rangeExpression) / \(rangeParsed)",
            "time: \(time)",
            "tags: \(tags)",
            "lock: \(job.isLocked)",
            "color: \(first(metadata, ["hdt_label_color", "label_color"]) ?? job.status.rawValue)",
            "paused: \(paused)",
            "format: \(format)",
            "p2f: \(boolean(first(metadata, ["p2f"])) ?? false)",
            "segment: \(segment)",
            "admin: \(isAdministrator)",
            "res: \(screenResolution)",
            "goodbyedpi: \(first(metadata, ["goodbyedpi", "dpi"]) ?? "")",
            "ytdl: \(ytdl)",
            "pinned: \(job.isPinned)",
            "extras: {\(extras)}",
            "live: \(live)",
            "changed: \(changed)"
        ]

        let galleryKeys = [
            "gallery_id", "gallery_number", "site", "type", "artist", "artists", "group",
            "groups", "series", "characters", "language", "tags", "date"
        ]
        let galleryLines = galleryKeys.compactMap { key -> String? in
            guard let value = metadata[key]?.trimmed, !value.isEmpty else { return nil }
            return "\(key): \(value)"
        }

        var messages = DownloadJob.normalizedInfoValues(job.messageHistory)
        let currentMessage = job.message.trimmed
        if !currentMessage.isEmpty, messages.last != currentMessage {
            messages.append(currentMessage)
        }

        return OriginalJobInfoDocument(
            title: job.title,
            propertyLines: propertyLines,
            galleryLines: galleryLines,
            files: fileEntries(job: job, outputFiles: outputFiles),
            urls: DownloadJob.normalizedInfoValues(job.resolvedURLs.isEmpty ? [job.source] : job.resolvedURLs),
            messages: messages
        )
    }

    private static func fileEntries(
        job: DownloadJob,
        outputFiles: [OutputPreviewFile]
    ) -> [OriginalJobInfoFileEntry] {
        let actualNames = outputFiles.map(\.relativePath)
        let expectedNames = DownloadJob.normalizedInfoValues(job.resolvedFilenames)
        let primaryNames = expectedNames.isEmpty ? actualNames : expectedNames
        var entries = primaryNames.enumerated().map { offset, name in
            OriginalJobInfoFileEntry(
                index: offset,
                name: name,
                isAvailable: job.status == .finished || outputContains(name, actualNames: actualNames)
            )
        }

        let expectedKeys = Set(expectedNames.map(normalizedFileKey))
        for name in actualNames where !expectedKeys.contains(normalizedFileKey(name)) {
            entries.append(OriginalJobInfoFileEntry(index: entries.count, name: name, isAvailable: true))
        }
        return entries
    }

    private static func outputContains(_ name: String, actualNames: [String]) -> Bool {
        let key = normalizedFileKey(name)
        return actualNames.contains { normalizedFileKey($0) == key }
    }

    private static func normalizedFileKey(_ value: String) -> String {
        value.replacingOccurrences(of: "\\", with: "/").lowercased()
    }

    private static func first(_ metadata: [String: String], _ keys: [String]) -> String? {
        keys.lazy.compactMap { metadata[$0]?.trimmed }.first { !$0.isEmpty }
    }

    private static func boolean(_ value: String?) -> Bool? {
        guard let normalized = value?.trimmed.lowercased(), !normalized.isEmpty else { return nil }
        if ["1", "true", "yes", "y", "on"].contains(normalized) { return true }
        if ["0", "false", "no", "n", "off"].contains(normalized) { return false }
        return nil
    }

    private static func archivePath(_ outputPath: String) -> String {
        let ext = URL(fileURLWithPath: outputPath).pathExtension.lowercased()
        return ["zip", "cbz"].contains(ext) ? outputPath : ""
    }

    private static func elapsedDescription(from value: String, now: Date) -> String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: value) else { return "" }
        return " - \(max(0, Int(now.timeIntervalSince(date))))s elapsed"
    }

    private static func currentAppVersion() -> String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        if !version.isEmpty, !build.isEmpty { return "\(version) (\(build))" }
        return version.isEmpty ? "HitomiBadayo" : version
    }

    private static func currentScreenResolution() -> String {
        guard let frame = NSScreen.main?.frame else { return "" }
        return "\(Int(frame.width))x\(Int(frame.height))"
    }

    private func numbered(_ values: [String]) -> [String] {
        values.enumerated().map { offset, value in
            String(format: "[%04d] %@", offset + 1, value)
        }
    }
}
