import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct TextViewerWindowView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var settingsStore: SettingsStore
    private let readModelService = TextViewerReadModelService()

    private var entries: [TextViewerEntry] {
        readModelService.visibleEntries(
            for: queueStore.jobs,
            filter: presentation.textViewerFilter
        )
    }

    private var selectedDocument: TextViewerDocument {
        readModelService.selectedDocument(
            for: queueStore.jobs,
            filter: presentation.textViewerFilter,
            selectedEntryID: presentation.textViewerSelectedEntryID
        )
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            detail
                .frame(minWidth: 520)
        }
        .frame(width: 900, height: 620)
        .onAppear {
            manager.ensureTextViewerSelection()
        }
        .onChange(of: presentation.textViewerFilter) {
            manager.ensureTextViewerSelection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Text Viewer", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField("Filter", text: $presentation.textViewerFilter)
                    .textFieldStyle(.roundedBorder)
                if !presentation.textViewerFilter.trimmed.isEmpty {
                    Button {
                        presentation.textViewerFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filter")
                }
            }

            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No text output")
                        .font(.headline)
                    Text("Completed text, log, JSON, XML, CSV, HTML, Markdown files, messages, and comments appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(entries) { entry in
                            TextViewerEntryRow(
                                entry: entry,
                                isSelected: presentation.textViewerSelectedEntryID == entry.id
                            ) {
                                manager.selectTextViewerEntry(entry)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var detail: some View {
        let document = selectedDocument
        return VStack(alignment: .leading, spacing: 0) {
            detailHeader(document)
            Divider()
            detailBody(document)
            Divider()
            detailFooter(document)
        }
    }

    private func detailHeader(_ document: TextViewerDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.entry?.kind == .message ? "text.bubble" : "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.entry?.displayName ?? "Text Viewer")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.entry?.title ?? "No text selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                manager.copySelectedTextViewerDocument()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(document.text.isEmpty && document.errorMessage == nil)

            Button {
                manager.openSelectedTextViewerRawFile()
            } label: {
                Image(systemName: "doc")
            }
            .disabled(!manager.canOpenSelectedTextViewerRawFile())
            .help("Open raw text file")

            Button {
                manager.openSelectedTextViewerInBrowser()
            } label: {
                Image(systemName: "safari")
            }
            .disabled(document.entry == nil)
            .help("Open in local text browser")

            Button {
                navigation.closeTextViewer()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close text viewer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func detailBody(_ document: TextViewerDocument) -> some View {
        Group {
            if let error = document.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("Text could not be read")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if document.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No text selected")
                        .font(.headline)
                    Text("Choose a text-capable queue item on the left.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: .constant(document.text))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(12)
            }
        }
    }

    private func detailFooter(_ document: TextViewerDocument) -> some View {
        HStack(spacing: 12) {
            if let entry = document.entry {
                Label(entry.kind.label, systemImage: entry.kind == .message ? "text.bubble" : "doc.text")
                Label(entry.status.label, systemImage: JobStatusStyle.iconName(for: entry.status))
                Label(byteText(document.byteCount), systemImage: "externaldrive")
                if document.truncated {
                    Label("Truncated at \(byteText(document.bytesRead))", systemImage: "scissors")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("No text output files or task messages.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !appStatusStore.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    appStatusStore.addSummary,
                    language: settingsStore.interfaceLanguage
                ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func byteText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, byteCount)), countStyle: .file)
    }
}

struct TextViewerEntryRow: View {
    let entry: TextViewerEntry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: entry.kind == .message ? "text.bubble" : "doc.text")
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(entry.detail)
    }
}
