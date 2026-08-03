import AppKit
import Foundation
import SwiftUI

struct BookmarkRow: View {
    let bookmark: URLBookmark
    let enqueue: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add bookmark to queue")

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(bookmark.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit bookmark")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove bookmark")
        }
        .padding(.vertical, 4)
    }

    private var metadataText: String {
        let tags = bookmark.tags.map { "#\($0)" }.joined(separator: " ")
        let note = bookmark.note.trimmed
        if tags.isEmpty { return note }
        if note.isEmpty { return tags }
        return "\(tags) - \(note)"
    }
}

struct BookmarkEditSheet: View {
    let url: String
    @Binding var title: String
    @Binding var tags: String
    @Binding var note: String
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bookmark")
                .font(.headline)

            Text(url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Tags", text: $tags)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $note)
                .font(.system(size: 12))
                .frame(minHeight: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

struct JobEditSheet: View {
    @Binding var title: String
    @Binding var source: String
    @Binding var input: String
    @Binding var outputPath: String
    @Binding var artist: String
    @Binding var zipFile: String
    @Binding var status: JobStatus
    @Binding var type: String
    @Binding var site: String
    @Binding var date: String
    @Binding var range: String
    let names: String
    @Binding var comment: String
    let thumbnailImage: NSImage?
    let thumbnailIsCustom: Bool
    let thumbnailMessage: String
    let selectThumbnail: () -> Void
    let saveThumbnail: () -> Void
    let resetThumbnail: () -> Void
    let cancel: () -> Void
    let save: () -> Void

    private let statusOptions: [JobStatus] = [.queued, .finished, .failed, .cancelled]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit Job")
                    .font(.headline)
                Spacer()
                Picker("Status", selection: $status) {
                    ForEach(statusOptions, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 190)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Thumbnail") {
                        HStack(spacing: 12) {
                            Button(action: selectThumbnail) {
                                JobEditThumbnailPreview(image: thumbnailImage)
                            }
                            .buttonStyle(.plain)
                            .help("Select thumbnail")
                            .accessibilityLabel("Select thumbnail")
                            .contextMenu {
                                Button(action: selectThumbnail) {
                                    Label("Select Thumbnail...", systemImage: "photo.badge.plus")
                                }
                                Button(action: saveThumbnail) {
                                    Label("Save Thumbnail As...", systemImage: "square.and.arrow.down")
                                }
                                .disabled(thumbnailImage == nil)
                                Button(action: resetThumbnail) {
                                    Label("Use Automatic Thumbnail", systemImage: "arrow.counterclockwise")
                                }
                                .disabled(!thumbnailIsCustom)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Label(
                                    thumbnailMessage,
                                    systemImage: thumbnailIsCustom ? "pin.fill" : "photo"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                                HStack(spacing: 6) {
                                    Button(action: selectThumbnail) {
                                        Image(systemName: "photo.badge.plus")
                                            .frame(width: 24, height: 22)
                                    }
                                    .help("Select thumbnail")
                                    .accessibilityLabel("Select thumbnail")

                                    Button(action: saveThumbnail) {
                                        Image(systemName: "square.and.arrow.down")
                                            .frame(width: 24, height: 22)
                                    }
                                    .disabled(thumbnailImage == nil)
                                    .help("Save thumbnail as")
                                    .accessibilityLabel("Save thumbnail as")

                                    Button(action: resetThumbnail) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .frame(width: 24, height: 22)
                                    }
                                    .disabled(!thumbnailIsCustom)
                                    .help("Use automatic thumbnail")
                                    .accessibilityLabel("Use automatic thumbnail")
                                }
                                .buttonStyle(.borderless)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
                    }

                    GroupBox("Source") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Input", text: $input)
                                .textFieldStyle(.roundedBorder)
                            TextField("URL", text: $source)
                                .textFieldStyle(.roundedBorder)
                            TextField("Folder", text: $outputPath)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 2)
                    }

                    GroupBox("Metadata") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Title")
                                    .foregroundStyle(.secondary)
                                TextField("Title", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Artist")
                                    .foregroundStyle(.secondary)
                                TextField("Artist", text: $artist)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Zip")
                                    .foregroundStyle(.secondary)
                                TextField("Zip file", text: $zipFile)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Type")
                                    .foregroundStyle(.secondary)
                                TextField("Type", text: $type)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Site")
                                    .foregroundStyle(.secondary)
                                TextField("Site", text: $site)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Date")
                                    .foregroundStyle(.secondary)
                                TextField("Date", text: $date)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Range")
                                    .foregroundStyle(.secondary)
                                TextField("Range", text: $range)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 2)
                    }

                    GroupBox("Names") {
                        TextEditor(text: .constant(names.isEmpty ? "No output names" : names))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(names.isEmpty ? .secondary : .primary)
                            .frame(minHeight: 84)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.18))
                            )
                    }

                    GroupBox("Comment") {
                        TextEditor(text: $comment)
                            .font(.system(size: 12))
                            .frame(minHeight: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                    }
                }
            }
            .frame(minHeight: 420)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 640)
    }
}

private struct JobEditThumbnailPreview: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            if let image {
                GeometryReader { proxy in
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.14)
                            .blur(radius: 10, opaque: true)
                            .opacity(0.62)

                        Color.black.opacity(0.08)

                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 112, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct PageSelectorSheet: View {
    let manager: DownloadManager
    @ObservedObject var queueEditorStore: QueueEditorStore

    private var title: String {
        queueEditorStore.pageSelectorJob?.title ?? "Pages"
    }

    private var source: String {
        queueEditorStore.pageSelectorJob?.source ?? ""
    }

    private var canEdit: Bool {
        guard let status = queueEditorStore.pageSelectorJob?.status else { return false }
        return status != .resolving && status != .downloading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pages", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text(queueEditorStore.pageSelectorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                TextField("1-3,5", text: Binding(
                    get: { queueEditorStore.pageSelectorRangeText },
                    set: { manager.setPageSelectorRangeText($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(!canEdit)

                Button {
                    manager.selectAllPageSelectorItems()
                } label: {
                    Label("All", systemImage: "checkmark.circle")
                }
                .disabled(!canEdit)
            }

            if queueEditorStore.pageSelectorItems.isEmpty {
                Text("No pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(queueEditorStore.pageSelectorItems) { item in
                        Toggle(isOn: Binding(
                            get: { queueEditorStore.pageSelectorSelectedIndexes.contains(item.index) },
                            set: { manager.setPageSelectorItem(item.index, selected: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("[ \(String(format: "%02d", item.page)) ] \(item.title)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if !item.detail.trimmed.isEmpty {
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!canEdit)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 320)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    manager.cancelPageSelector()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK") {
                    manager.savePageSelector()
                }
                .disabled(!canEdit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 580, height: 620)
    }
}

struct JobCommentSheet: View {
    let title: String
    let source: String
    @Binding var comment: String
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Job Comment")
                .font(.headline)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            TextEditor(text: $comment)
                .font(.system(size: 12))
                .frame(minHeight: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}
