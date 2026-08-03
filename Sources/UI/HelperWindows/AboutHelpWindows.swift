import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct AboutView: View {
    let language: AppInterfaceLanguage
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let about = DownloadManager.appAboutInfo()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: 64, height: 64)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 4) {
                    Text(about.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(AppLocalization.format(
                        "Current: %@",
                        language: language,
                        about.currentVersionText
                    ))
                        .font(.subheadline)
                    Text(AppLocalization.format(
                        "Latest: %@",
                        language: language,
                        localized(about.latestVersionText)
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AboutPanel(title: localized("About")) {
                        Text(localized(about.developedBy))
                        Text("\(about.architecture) · macOS \(about.minimumSystemVersion)+")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    AboutPanel(title: localized("Licenses")) {
                        Text(localized(about.licenseSummary))
                    }

                    AboutPanel(title: localized("History")) {
                        Text(localized(about.historySummary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    copy(about.currentVersionText)
                } label: {
                    Label(localized("Copy Version"), systemImage: "doc.on.doc")
                }
                .accessibilityLabel(localized("Copy Version"))
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 620, height: 620)
        .environment(\.locale, language.locale)
        .accessibilityIdentifier("auxiliary.about")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct AboutPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Help", systemImage: "questionmark.circle")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HelpPanel(title: "Add URLs") {
                        Text("Paste URLs into the main input and use Add or Start Queue. Empty Add can read supported URLs from the clipboard.")
                        Text("Task rows expose Info, Edit, Comment, Retry, PDF, ZIP/CBZ, Move, Delete, and browser viewing actions.")
                    }

                    HelpPanel(title: "Original-Style Helper Windows") {
                        Text("Use Log, Dirs, Finder, Analysis, History, Search, Clipboard, Browser, Text, and Pages from the toolbar, app menu, or local WebUI.")
                    }

                    HelpPanel(title: "HTTP API") {
                        Text("Enable the local HTTP API to use /webui, /docs, /about, /help, and JSON routes such as /api/about and /api/help.")
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

private struct HelpPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
