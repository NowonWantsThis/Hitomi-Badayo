import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DirectoriesView: View {
    let manager: DownloadManager
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = manager.outputDirectoryEntries()
        let text = manager.outputDirectoriesText(entries: entries, language: settingsStore.interfaceLanguage)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(localized("Download Path History"), systemImage: "folder")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(localized("Copy")) {
                    copy(text)
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel(localized("Copy"))
                Button(localized("Open First")) {
                    openFirstDirectory(entries)
                }
                .disabled(firstOpenableDirectory(entries) == nil)
                .accessibilityLabel(localized("Open First"))
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .padding(20)
        .frame(width: 680)
        .frame(minHeight: 480)
        .accessibilityIdentifier("auxiliary.directories")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: settingsStore.interfaceLanguage)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openFirstDirectory(_ entries: [OutputDirectoryEntry]) {
        guard let path = firstOpenableDirectory(entries) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func firstOpenableDirectory(_ entries: [OutputDirectoryEntry]) -> String? {
        entries.first { $0.exists && $0.isDirectory }?.path
    }
}
