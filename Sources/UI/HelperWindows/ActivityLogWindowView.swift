import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ActivityLogView: View {
    @ObservedObject var presentation: AppPresentationStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(localized("Log"), systemImage: "doc.text.magnifyingglass")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Toggle(localized("Auto Refresh && Scroll"), isOn: $presentation.activityLogAutoRefreshAndScroll)
                    .toggleStyle(.checkbox)
                Button(localized("Clear")) {
                    appStatusStore.clearActivityLog()
                }
                .disabled(appStatusStore.activityLog.isEmpty)
                .accessibilityLabel(localized("Clear"))
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if appStatusStore.activityLog.isEmpty {
                            Text(localized("No log entries"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(appStatusStore.activityLog) { entry in
                                ActivityLogRow(entry: entry, language: settingsStore.interfaceLanguage)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("activity-log-bottom")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: appStatusStore.activityLog.count) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
        .padding(20)
        .frame(width: 680)
        .frame(minHeight: 520)
        .accessibilityIdentifier("auxiliary.activity-log")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: settingsStore.interfaceLanguage)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard presentation.activityLogAutoRefreshAndScroll else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("activity-log-bottom", anchor: .bottom)
            }
        }
    }
}

private struct ActivityLogRow: View {
    var entry: ActivityLogEntry
    var language: AppInterfaceLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formattedTimestamp)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(AppLocalization.text(entry.category, language: language))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(AppLocalization.statusText(entry.message, language: language))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: entry.timestamp)
    }
}
