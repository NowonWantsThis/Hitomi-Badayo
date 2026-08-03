import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MetadataFinderView: View {
    let manager: DownloadManager
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var searchStore: SearchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let results = manager.metadataFinderResults(
            field: searchStore.metadataFinderField,
            query: searchStore.metadataFinderQuery,
            mode: searchStore.metadataFinderMode
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Finder", systemImage: "magnifyingglass")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Field", selection: $searchStore.metadataFinderField) {
                    ForEach(MetadataFinderField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    TextField(
                        "Search \(searchStore.metadataFinderField.label.lowercased())",
                        text: $searchStore.metadataFinderQuery
                    )
                        .textFieldStyle(.roundedBorder)
                    Picker("Mode", selection: $searchStore.metadataFinderMode) {
                        ForEach(MetadataFinderMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .frame(width: 140)
                }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if results.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        ForEach(results) { result in
                            MetadataFinderResultRow(result: result) {
                                copy(DownloadManager.metadataFinderSearchToken(result))
                            } apply: {
                                manager.applyMetadataFinderResult(result)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .padding(20)
        .frame(width: 760)
        .frame(minHeight: 540)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MetadataFinderResultRow: View {
    var result: MetadataFinderResult
    var copy: () -> Void
    var apply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.value)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                    Text("\(result.totalCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                copy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy search token")
            Button {
                apply()
            } label: {
                Image(systemName: "arrow.turn.down.left")
            }
            .help("Use in search")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
    }

    private var detailText: String {
        let pieces = [
            result.queueCount > 0 ? "\(result.queueCount) queue" : nil,
            result.historyCount > 0 ? "\(result.historyCount) history" : nil,
            result.score.map { "score \($0)" },
            result.sampleTitle.trimmed.isEmpty ? nil : result.sampleTitle
        ].compactMap { $0 }
        return pieces.joined(separator: " · ")
    }
}

struct MetadataAnalysisView: View {
    let manager: DownloadManager
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var searchStore: SearchStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = manager.metadataAnalysisEntries(
            field: searchStore.metadataAnalysisField
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Analysis", systemImage: "chart.pie")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Picker("Field", selection: $searchStore.metadataAnalysisField) {
                ForEach(MetadataAnalysisField.allCases) { field in
                    Text(field.label).tag(field)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Total")
                        .frame(width: 56, alignment: .trailing)
                    Text("Queue")
                        .frame(width: 56, alignment: .trailing)
                    Text("History")
                        .frame(width: 64, alignment: .trailing)
                    Text("Token")
                        .frame(width: 92, alignment: .center)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text("No metadata")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            ForEach(entries) { entry in
                                MetadataAnalysisEntryRow(entry: entry) {
                                    copy(DownloadManager.metadataAnalysisSearchToken(entry))
                                } apply: {
                                    manager.applyMetadataAnalysisEntry(entry)
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .padding(20)
        .frame(width: 820)
        .frame(minHeight: 560)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MetadataAnalysisEntryRow: View {
    var entry: MetadataAnalysisEntry
    var copy: () -> Void
    var apply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.value)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(entry.totalCount)")
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
            Text("\(entry.queueCount)")
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("\(entry.historyCount)")
                .frame(width: 64, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button {
                    copy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy search token")

                Button {
                    apply()
                } label: {
                    Image(systemName: "arrow.turn.down.left")
                }
                .help("Use in search")
            }
            .buttonStyle(.borderless)
            .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .textSelection(.enabled)
    }

    private var detailText: String {
        let pieces = [
            entry.sampleTitle.trimmed.isEmpty ? nil : entry.sampleTitle,
            entry.sampleSource.trimmed.isEmpty ? nil : entry.sampleSource
        ].compactMap { $0 }
        return pieces.isEmpty ? DownloadManager.metadataAnalysisSearchToken(entry) : pieces.joined(separator: " · ")
    }
}
