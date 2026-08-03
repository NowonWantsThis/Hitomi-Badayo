import AppKit
import Foundation
import SwiftUI

struct HistoryRow: View {
    let entry: DownloadHistoryEntry
    let enqueue: () -> Void
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add history item to queue")

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: reveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .disabled(entry.outputPath.isEmpty)
            .help("Reveal history output")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove history item")
        }
        .padding(.vertical, 4)
    }
}

struct DuplicateImageGroupRow: View {
    let group: DuplicateImageGroup
    let showsThumbnails: Bool
    let selectedPath: String
    let autoSelectedPath: String
    let select: (String) -> Void
    let reveal: (String) -> Void
    let openFolder: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("\(group.files.count) files")
                    .font(.system(size: 12, weight: .semibold))
                Text(byteCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !resolutionText.isEmpty {
                    Text(resolutionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let similarityText {
                    Text(similarityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(group.hash.prefix(10)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if showsThumbnails {
                HStack(spacing: 6) {
                    ForEach(Array(group.files.prefix(3)), id: \.self) { path in
                        DuplicateImageThumbnail(path: path) {
                            select(path)
                            reveal(path)
                        }
                    }
                }
            }

            ForEach(Array(group.files.prefix(3)), id: \.self) { path in
                HStack(spacing: 6) {
                    if isMarked(path) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(markerColor(for: path))
                            .frame(width: 14)
                            .help(markerHelp(for: path))
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                    }
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                    Spacer()
                    Button {
                        select(path)
                        reveal(path)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal image")

                    Button {
                        select(path)
                        openFolder(path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Open containing folder")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    select(path)
                }
                .onTapGesture(count: 2) {
                    select(path)
                    openFolder(path)
                }
            }

            if group.files.count > 3 {
                Text("+\(group.files.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let first = group.files.first {
                Button {
                    select(first)
                    openFolder(first)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                Button {
                    select(first)
                    reveal(first)
                } label: {
                    Label("Reveal Image", systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var byteCountText: String {
        let minimum = group.minByteCount ?? group.byteCount
        let maximum = group.maxByteCount ?? group.byteCount
        if minimum > 0, maximum > 0, minimum != maximum {
            let low = ByteCountFormatter.string(fromByteCount: minimum, countStyle: .file)
            let high = ByteCountFormatter.string(fromByteCount: maximum, countStyle: .file)
            return "\(low) to \(high)"
        }
        return ByteCountFormatter.string(fromByteCount: group.byteCount, countStyle: .file)
    }

    private func isMarked(_ path: String) -> Bool {
        selectedPath == path || autoSelectedPath == path
    }

    private func markerColor(for path: String) -> Color {
        autoSelectedPath == path ? .red : .accentColor
    }

    private func markerHelp(for path: String) -> String {
        autoSelectedPath == path ? "Auto-selected duplicate candidate" : "Selected duplicate image"
    }

    private var resolutionText: String {
        guard let width = group.width,
              let height = group.height,
              width > 0,
              height > 0 else {
            return ""
        }
        return "\(width)x\(height)"
    }

    private var similarityText: String? {
        guard let similarity = group.similarityPercent,
              similarity < 100 else {
            return nil
        }
        return "~\(similarity)%"
    }
}

private struct DuplicateImageThumbnail: View {
    let path: String
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            ZStack {
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(URL(fileURLWithPath: path).lastPathComponent)
    }
}

struct SearchProviderRow: View {
    let provider: SearchProvider
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(provider.urlTemplate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .help("Move search provider up")

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .help("Move search provider down")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove search provider")
        }
        .padding(.vertical, 4)
    }
}

struct SearchBookmarkRow: View {
    let bookmark: SearchBookmark
    let apply: () -> Void
    let enqueue: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: apply) {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Apply search bookmark")

            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add bookmarked search to queue")

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(bookmark.providerName) · \(bookmark.query)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove search bookmark")
        }
        .padding(.vertical, 4)
    }
}

struct SearchResultRow: View {
    let result: SearchResultLink
    let galleryID: String?
    let metadataCopies: [DownloadManager.SearchResultMetadataCopy]
    let dateText: String?
    let pageCountText: String?
    let isDone: Bool
    let canOpenFirstOutput: Bool
    let enqueue: () -> Void
    let openSource: () -> Void
    let copyURL: () -> Void
    let copyTitle: () -> Void
    let copyMetadata: (DownloadManager.SearchResultMetadataCopy) -> Void
    let openFirstOutput: () -> Void
    let copyGalleryID: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add result to queue")

            Button(action: openSource) {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Open result link")

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hasSecondaryMetadata {
                    HStack(spacing: 8) {
                        if let dateText, !dateText.trimmed.isEmpty {
                            Label(dateText, systemImage: "calendar")
                                .lineLimit(1)
                        }
                        if let pageCountText, !pageCountText.trimmed.isEmpty {
                            Label(pageCountText, systemImage: "doc.text")
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: copyTitle) {
                Image(systemName: "textformat")
            }
            .buttonStyle(.borderless)
            .help("Copy result title")

            Button(action: copyURL) {
                Image(systemName: "link")
            }
            .buttonStyle(.borderless)
            .help("Copy result URL")

            if !metadataCopies.isEmpty {
                Menu {
                    ForEach(metadataCopies) { item in
                        Button("\(item.label): \(item.value)") {
                            copyMetadata(item)
                        }
                    }
                } label: {
                    Image(systemName: "person.text.rectangle")
                }
                .menuStyle(.borderlessButton)
                .help("Copy result metadata")
            }

            if let galleryID {
                Text("#\(galleryID)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: copyGalleryID) {
                    Image(systemName: "number.circle")
                }
                .buttonStyle(.borderless)
                .help("Copy gallery ID")
            }

            if isDone {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .help("Already in queue, history, or saved output")
            }

            Button(action: openFirstOutput) {
                Image(systemName: "doc.viewfinder")
            }
            .buttonStyle(.borderless)
            .disabled(!canOpenFirstOutput)
            .help("Open first output file")
        }
        .padding(.vertical, 4)
    }

    private var hasSecondaryMetadata: Bool {
        !(dateText?.trimmed.isEmpty ?? true) || !(pageCountText?.trimmed.isEmpty ?? true)
    }
}

enum JobStatusStyle {
    static func iconName(for job: DownloadJob) -> String {
        job.partialFailureCounts == nil ? iconName(for: job.status) : "exclamationmark.triangle.fill"
    }

    static func iconName(for status: JobStatus) -> String {
        switch status {
        case .queued: return "clock"
        case .resolving: return "magnifyingglass"
        case .downloading: return "arrow.down"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    static func colorName(for status: JobStatus) -> String {
        switch status {
        case .queued: return "secondary"
        case .resolving: return "blue"
        case .downloading: return "accent"
        case .finished: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }

    static func color(for status: JobStatus) -> Color {
        switch status {
        case .queued: return .secondary
        case .resolving: return .blue
        case .downloading: return .accentColor
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    static func color(for job: DownloadJob) -> Color {
        job.partialFailureCounts == nil ? color(for: job.status) : .orange
    }

    static func color(for status: JobStatus, palette: JobStatusColorPalette) -> Color {
        Color(hexRGB: palette.hex(for: status)) ?? color(for: status)
    }

    static func color(for job: DownloadJob, palette: JobStatusColorPalette) -> Color {
        job.partialFailureCounts == nil ? color(for: job.status, palette: palette) : .orange
    }
}
