import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct HistoryWindowView: View {
    @ObservedObject var libraryStore: LibraryStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = libraryStore.historyPlainText(
            language: settingsStore.interfaceLanguage
        )

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(localized("History"), systemImage: "clock.arrow.circlepath")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(libraryStore.history.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(localized("Copy")) {
                    copy(text)
                }
                .disabled(libraryStore.history.isEmpty)
                .accessibilityLabel(localized("Copy"))
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
        }
        .padding(20)
        .frame(width: 720)
        .frame(minHeight: 520)
        .accessibilityIdentifier("auxiliary.history")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: settingsStore.interfaceLanguage)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
