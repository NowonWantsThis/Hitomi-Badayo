import AppKit
import Foundation
import SwiftUI

struct JobInfoEntry: Identifiable, Equatable {
    let key: String
    let value: String

    var id: String { key }
    var label: String { JobInfoExtras.label(for: key) }
}

enum JobInfoExtras {
    static let preferredExtraKeys = [
        "last_error",
        "failed_segment_index",
        "failed_segment_total",
        "failed_segment_filename",
        "failed_segment_url",
        "skipped_segment_count",
        "skipped_segment_total",
        "skipped_segment_indexes",
        "skipped_segment_filenames",
        "skipped_segment_urls",
        "segment_count",
        "total_segments",
        "media_count",
        "map_count",
        "encrypted_count",
        "encrypted",
        "playlist_url",
        "manifest_url",
        "package_mode",
        "duration_seconds",
        "representation_id",
        "video_representation_id",
        "audio_representation_id",
        "bandwidth",
        "torrent_piece_count",
        "torrent_piece_size",
        "torrent_total_size"
    ]

    private static var preferredExtraKeySet: Set<String> {
        Set(preferredExtraKeys)
    }

    static func summaryEntries(for job: DownloadJob) -> [JobInfoEntry] {
        var entries = [
            JobInfoEntry(key: "status", value: job.statusDisplayText()),
            JobInfoEntry(key: "progress", value: String(format: "%.0f%%", job.progress * 100)),
            JobInfoEntry(key: "completed", value: "\(job.completed) / \(job.total)"),
            JobInfoEntry(key: "pinned", value: job.isPinned ? "Yes" : "No"),
            JobInfoEntry(key: "locked", value: job.isLocked ? "Yes" : "No"),
            JobInfoEntry(key: "message", value: AppLocalization.statusText(job.message)),
            JobInfoEntry(key: "comment", value: job.comment),
            JobInfoEntry(key: "range", value: job.rangeExpression),
            JobInfoEntry(key: "output_path", value: job.outputPath),
            JobInfoEntry(key: "source", value: job.source)
        ]
        if let counts = job.partialFailureCounts {
            entries.insert(
                JobInfoEntry(key: "successful_files", value: "\(counts.succeeded) / \(counts.total)"),
                at: 3
            )
            entries.insert(JobInfoEntry(key: "failed_files", value: String(counts.failed)), at: 4)
        }
        if let size = JobDisplayMetadata.byteCountText(for: job) {
            entries.insert(JobInfoEntry(key: "known_size", value: size), at: 3)
        }
        if let eta = JobDisplayMetadata.etaText(for: job) {
            entries.insert(JobInfoEntry(key: "eta", value: eta), at: 4)
        }
        return entries.filter { !$0.value.trimmed.isEmpty }
    }

    static func extraEntries(for job: DownloadJob) -> [JobInfoEntry] {
        let preferred = preferredExtraKeys.compactMap { key -> JobInfoEntry? in
            guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { return nil }
            return JobInfoEntry(key: key, value: value)
        }

        let dynamic = job.metadata.keys
            .filter { !preferredExtraKeySet.contains($0) && isExtraKey($0) }
            .sorted()
            .compactMap { key -> JobInfoEntry? in
                guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { return nil }
                return JobInfoEntry(key: key, value: value)
            }

        return preferred + dynamic
    }

    static func metadataEntries(for job: DownloadJob) -> [JobInfoEntry] {
        let extraKeys = Set(extraEntries(for: job).map(\.key))
        return job.metadata.keys
            .filter { !extraKeys.contains($0) }
            .sorted()
            .compactMap { key -> JobInfoEntry? in
                guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { return nil }
                return JobInfoEntry(key: key, value: value)
            }
    }

    static func label(for key: String) -> String {
        switch key {
        case "known_size": return "Known Size"
        case "eta": return "ETA"
        case "last_error": return "Last Error"
        case "failed_segment_index": return "Failed Segment"
        case "failed_segment_total": return "Failed Segment Total"
        case "failed_segment_filename": return "Failed Segment File"
        case "failed_segment_url": return "Failed Segment URL"
        case "skipped_segment_count": return "Skipped Segments"
        case "skipped_segment_total": return "Skipped Segment Total"
        case "skipped_segment_indexes": return "Skipped Segment Indexes"
        case "skipped_segment_filenames": return "Skipped Segment Files"
        case "skipped_segment_urls": return "Skipped Segment URLs"
        case "successful_files": return "Successful Files / Total"
        case "failed_files": return "Failed Files"
        case "segment_count": return "Segments"
        case "total_segments": return "Total Segments"
        case "media_count": return "Media"
        case "map_count": return "Init Maps"
        case "encrypted_count": return "Encrypted Segments"
        case "playlist_url": return "Playlist URL"
        case "manifest_url": return "Manifest URL"
        case "package_mode": return "Package Mode"
        case "duration_seconds": return "Duration"
        case "representation_id": return "Representation"
        case "video_representation_id": return "Video Representation"
        case "audio_representation_id": return "Audio Representation"
        case "torrent_piece_count": return "Pieces"
        case "torrent_piece_size": return "Piece Size"
        case "torrent_total_size": return "Torrent Size"
        case "torrent_piece_length": return "Piece Length Bytes"
        case "torrent_total_length": return "Torrent Size Bytes"
        case "output_path": return "Output"
        case "pinned": return "Pinned"
        case "locked": return "Locked"
        case "comment": return "Comment"
        default:
            return key
                .split(separator: "_")
                .map { part in
                    part.prefix(1).uppercased() + part.dropFirst()
                }
                .joined(separator: " ")
        }
    }

    private static func isExtraKey(_ key: String) -> Bool {
        key.hasSuffix("_count") ||
            key.hasSuffix("_url") ||
            key.hasSuffix("_seconds") ||
            key.contains("segment") ||
            key.contains("playlist") ||
            key.contains("manifest") ||
            key.contains("representation")
    }
}

struct JobInfoView: View {
    let job: DownloadJob
    let queueIndex: Int?
    let groupName: String?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = OriginalJobInfoLoader()

    private var document: OriginalJobInfoDocument {
        OriginalJobInfoDocument.make(
            job: job,
            queueIndex: queueIndex,
            groupName: groupName,
            outputFiles: loader.outputFiles
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(job.id.uuidString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(document.plainText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(AppLocalization.text("Copy task information"))

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(AppLocalization.text("Close"))
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    diagnosticText(document.propertyLines.joined(separator: "\n"))

                    if !document.galleryLines.isEmpty {
                        infoSection("Gallery") {
                            diagnosticText(document.galleryLines.joined(separator: "\n"))
                        }
                    }

                    infoSection("File Names") {
                        if document.files.isEmpty {
                            diagnosticText("(empty)")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(document.files) { file in
                                diagnosticText(file.displayText)
                                    .foregroundStyle(file.isAvailable ? Color.primary : Color.red)
                            }
                        }
                    }

                    infoSection("URLs") {
                        if document.urls.isEmpty {
                            diagnosticText("(empty)")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(document.urls.enumerated()), id: \.offset) { offset, url in
                                diagnosticText(numbered(offset, url))
                            }
                        }
                    }

                    if !document.messages.isEmpty {
                        infoSection("Messages") {
                            ForEach(Array(document.messages.enumerated()), id: \.offset) { offset, message in
                                diagnosticText(numbered(offset, message))
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 700, minHeight: 580)
        .task(id: job.outputPath) {
            await loader.load(outputPath: job.outputPath)
        }
    }

    private func infoSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("[\(title)]")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            content()
        }
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numbered(_ offset: Int, _ value: String) -> String {
        String(format: "[%04d] %@", offset + 1, value)
    }
}
