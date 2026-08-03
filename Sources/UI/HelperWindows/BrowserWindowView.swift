import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowserWindowView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject var presentation: AppPresentationStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var cookieStatusStore: CookieStatusStore

    private var targetURL: URL? {
        manager.browserWindowTargetURL()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 660, height: 360)
        .onAppear {
            if presentation.browserWindowURLText.trimmed.isEmpty {
                manager.refreshBrowserWindowURL()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Browser")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Open a native WKWebView login browser and save cookies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                navigation.closeBrowser()
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close browser helper")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("https://example.com/login", text: Binding(
                        get: { presentation.browserWindowURLText },
                        set: { manager.setBrowserWindowURLText($0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        manager.refreshBrowserWindowURL()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("Use inferred URL")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                BrowserInfoRow(title: "Target", value: manager.browserWindowTargetSummary(), systemImage: "link")
                BrowserInfoRow(
                    title: "Cookies",
                    value: AppLocalization.statusText(
                        cookieStatusStore.summary,
                        language: settingsStore.interfaceLanguage
                    ),
                    systemImage: "key"
                )
            }

            HStack(spacing: 8) {
                Button {
                    manager.openBrowserWindowLogin()
                } label: {
                    Label("Open Login Browser", systemImage: "person.crop.circle.badge.key")
                }
                .disabled(targetURL == nil)

                Button {
                    manager.openBrowserWindowHTTPPage()
                } label: {
                    Label("HTTP Page", systemImage: "network")
                }
                .disabled(targetURL == nil)

                Button {
                    manager.clearCookies()
                } label: {
                    Label("Delete Cookies and Login Sessions", systemImage: "trash")
                }
                .disabled(cookieStatusStore.isClearing)
                .help(AppLocalization.text(
                    "Delete app cookies and embedded-browser login sessions",
                    language: settingsStore.interfaceLanguage
                ))
                .accessibilityIdentifier("browser.clear-cookies")
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                manager.importCookies()
            } label: {
                Label("Import Text", systemImage: "key")
            }

            Button {
                manager.importBrowserCookies()
            } label: {
                Label("Import Browser", systemImage: "globe")
            }

            Button {
                manager.importDetectedBrowserCookies()
            } label: {
                Label("Detect", systemImage: "magnifyingglass")
            }

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

struct BrowserInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
