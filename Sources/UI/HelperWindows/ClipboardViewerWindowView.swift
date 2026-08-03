import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ClipboardViewerWindowView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var appStatusStore: AppStatusStore

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                editorPane
                    .frame(minWidth: 360, idealWidth: 440)

                candidatePane
                    .frame(minWidth: 360)
            }

            Divider()
            footer
        }
        .frame(width: 860, height: 600)
        .onAppear {
            manager.refreshClipboardViewer()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard Viewer")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(presentation.clipboardViewerSource) · change \(presentation.clipboardViewerChangeCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                manager.refreshClipboardViewer()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                navigation.closeClipboardViewer()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close clipboard viewer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard Text")
                    .font(.headline)
                Spacer()
                Text("\(presentation.clipboardViewerText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            TextEditor(text: Binding(
                get: { presentation.clipboardViewerText },
                set: { manager.setClipboardViewerText($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            HStack(spacing: 8) {
                Button {
                    manager.useClipboardViewerAsInput()
                } label: {
                    Label("Use as Input", systemImage: "text.badge.plus")
                }
                .disabled(presentation.clipboardViewerText.trimmed.isEmpty)

                Button {
                    manager.setClipboardViewerText("")
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(presentation.clipboardViewerText.isEmpty)
                .help("Clear text")
            }
        }
        .padding(14)
    }

    private var candidatePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Candidate URLs")
                    .font(.headline)
                Spacer()
                Text("\(presentation.clipboardViewerURLs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if presentation.clipboardViewerURLs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No URLs found")
                        .font(.headline)
                    Text("Refresh the clipboard or edit the text to inspect candidates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(presentation.clipboardViewerURLs.enumerated()), id: \.offset) { index, url in
                        ClipboardCandidateRow(index: index + 1, url: url)
                    }
                }
                .listStyle(.inset)
            }

            HStack(spacing: 8) {
                Button {
                    _ = manager.queueClipboardViewerURLs()
                } label: {
                    Label("Queue", systemImage: "plus")
                }
                .disabled(presentation.clipboardViewerURLs.isEmpty)

                Button {
                    _ = manager.queueClipboardViewerURLs(start: true)
                } label: {
                    Label("Queue & Start", systemImage: "play.fill")
                }
                .disabled(presentation.clipboardViewerURLs.isEmpty || queueStore.isRunning)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Watch Clipboard", isOn: Binding(
                get: { settingsStore.clipboardMonitorEnabled },
                set: { manager.setClipboardMonitorEnabled($0) }
            ))
            .toggleStyle(.switch)

            Toggle("Sound", isOn: Binding(
                get: { settingsStore.playSoundOnClipboardAdd },
                set: { manager.setPlaySoundOnClipboardAdd($0) }
            ))
            .toggleStyle(.switch)
            .disabled(!settingsStore.clipboardMonitorEnabled)

            Spacer()

            if !appStatusStore.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    appStatusStore.addSummary,
                    language: settingsStore.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct ClipboardCandidateRow: View {
    let index: Int
    let url: String

    private var hostText: String {
        URL(string: url)?.host ?? URL(fileURLWithPath: url).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Image(systemName: url.lowercased().hasPrefix("file://") ? "doc" : "link")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(hostText.isEmpty ? url : hostText)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .help(url)
    }
}
