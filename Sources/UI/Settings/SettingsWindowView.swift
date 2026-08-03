import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsWindowView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject private var settingsStore: SettingsStore
    @ObservedObject private var appPresentation: AppPresentationStore
    @ObservedObject private var presentation: SettingsWindowPresentationState
    @ObservedObject private var libraryStore: LibraryStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var externalToolStore: ExternalToolStore
    @EnvironmentObject private var aria2Store: Aria2Store
    @EnvironmentObject private var pythonRuntimeStore: PythonRuntimeStore
    @EnvironmentObject private var searchStore: SearchStore
    @EnvironmentObject private var autoRecordStore: AutoRecordStore
    @EnvironmentObject private var networkStore: NetworkStore
    @EnvironmentObject private var cookieStatusStore: CookieStatusStore

    init(
        manager: DownloadManager,
        presentation appPresentation: AppPresentationStore,
        settingsStore: SettingsStore,
        libraryStore: LibraryStore
    ) {
        self.manager = manager
        self.settingsStore = settingsStore
        self.appPresentation = appPresentation
        presentation = appPresentation.settingsWindow
        self.libraryStore = libraryStore
    }

    private enum SettingsRowDetailPlacement: Equatable {
        case label
        case fullWidth
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: settingsStore.interfaceLanguage)
    }

    private func localizedStatus(_ value: String) -> String {
        AppLocalization.statusText(value, language: settingsStore.interfaceLanguage)
    }

    private var themePresentation: ThemePresentationSnapshot {
        ThemePresentationService.snapshot(
            plugins: pythonRuntimeStore.scriptPlugins,
            selectedThemeKey: settingsStore.selectedPythonThemeKey,
            appearanceMode: settingsStore.appAppearanceMode
        )
    }

    private var outputSettingsPresentation:
        OutputSettingsPresentationSnapshot {
        OutputSettingsReadModelService.snapshot(settings: settingsStore)
    }

    private var visibleCategories: [SettingsWindowCategory] {
        let query = presentation.filter.trimmed.lowercased()
        guard !query.isEmpty else { return SettingsWindowCategory.allCases }
        return SettingsWindowCategory.allCases.filter {
            $0.searchText.lowercased().contains(query)
        }
    }

    private var statusColorSummary: String {
        localized(
            settingsStore.jobStatusColorPalette == .defaultPalette
                ? "Default Palette"
                : "Custom Palette"
        )
    }

    private var filteredArchiveSourceProfiles: [DownloadSourceFolderProfile] {
        let query = presentation.archiveFilter.trimmed.lowercased()
        guard !query.isEmpty else {
            return outputSettingsPresentation.sourceFolderProfiles
        }
        return outputSettingsPresentation.sourceFolderProfiles.filter {
            $0.displayName.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                header

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        selectedCategoryContent

                        if !appStatusStore.addSummary.isEmpty {
                            Text(localizedStatus(appStatusStore.addSummary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 10)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .id(settingsStore.interfaceLanguage)
        .frame(
            minWidth: 620,
            idealWidth: 920,
            maxWidth: .infinity,
            minHeight: 540,
            idealHeight: 660,
            maxHeight: .infinity
        )
        .environment(\.locale, settingsStore.interfaceLanguage.locale)
        .sheet(isPresented: $appPresentation.showingFontSettings) {
            FontSettingsView(
                manager: manager,
                presentation: appPresentation
            )
        }
    }

    private var sidebar: some View {
        SettingsSidebarView(
            title: localized("Settings"),
            searchPlaceholder: localized("Search"),
            clearSearchHelp: localized("Clear Search"),
            categories: visibleCategories,
            filter: $presentation.filter,
            selectedCategory: $presentation.category
        )
    }

    private var header: some View {
        SettingsHeaderView(
            category: presentation.category,
            closeHelp: localized("Close Settings"),
            close: navigation.closeSettings
        )
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch presentation.category {
        case .general:
            generalSettings
        case .network:
            networkSettings
        case .live:
            liveSettings
        case .theme:
            themeSettings
        case .archive:
            archiveSettings
        case .plugins:
            pluginSettings
        case .advanced:
            advancedSettings
        case .hitomi:
            hitomiSettings
        case .pixiv:
            pixivSettings
        case .kemonoFriends:
            kemonoFriendsSettings
        case .youtube:
            youtubeSettings
        case .social:
            socialSettings
        case .torrent:
            torrentSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Language", systemImage: "globe") {
                settingsRow("Display Language") {
                    trailingSettingsControl {
                        Picker("", selection: Binding(
                            get: { settingsStore.interfaceLanguage },
                            set: { manager.setInterfaceLanguage($0) }
                        )) {
                            ForEach(AppInterfaceLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel(AppLocalization.text("Display Language", language: settingsStore.interfaceLanguage))
                        .accessibilityIdentifier("settings.interface-language")
                    }
                }
            }

            settingsSection("Save Folder", systemImage: "folder") {
                settingsRow("Save Location") {
                    HStack(spacing: 8) {
                        Text(settingsStore.destinationPath)
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        iconButton("folder", help: "Choose Download Folder") {
                            manager.chooseDestination()
                        }
                    }
                }

                settingsRow("Folders by Source") {
                    VStack(alignment: .trailing, spacing: 5) {
                        sourceFolderProfileMenu

                        HStack(spacing: 6) {
                            TextField(
                                DownloadSourceFolderProfile.defaultFolderName(
                                    for: settingsStore.selectedSourceFolderID
                                ),
                                text: Binding(
                                    get: {
                                        manager.sourceFolderName(
                                            for: settingsStore.selectedSourceFolderID
                                        )
                                    },
                                    set: {
                                        manager.setSourceFolderName(
                                            $0,
                                            for: settingsStore.selectedSourceFolderID
                                        )
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 186)
                            .accessibilityLabel(AppLocalization.text("Source Folder Name", language: settingsStore.interfaceLanguage))
                            .accessibilityIdentifier("settings.source-folder-name")

                            iconButton("arrow.counterclockwise", help: "Reset Source Folder Name") {
                                manager.resetSourceFolderName(
                                    for: settingsStore.selectedSourceFolderID
                                )
                            }
                            .accessibilityIdentifier("settings.source-folder-reset")
                        }
                        .frame(width: 220, alignment: .trailing)

                        Text(
                            outputSettingsPresentation
                                .selectedSourceFolderPreviewPath
                        )
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 220, alignment: .trailing)
                            .accessibilityIdentifier("settings.source-folder-preview")
                    }
                    .frame(width: 220, alignment: .trailing)
                }

                settingsRow("Folder Layout") {
                    trailingSettingsControl {
                        Picker("", selection: Binding(
                            get: { settingsStore.outputSubfolderMode },
                            set: { manager.setOutputSubfolderMode($0) }
                        )) {
                            ForEach(OutputSubfolderMode.allCases, id: \.self) { mode in
                                Text(mode.label(language: settingsStore.interfaceLanguage)).tag(mode)
                            }
                        }
                        .id("output-folder-layout-\(settingsStore.interfaceLanguage.rawValue)")
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel(AppLocalization.text("Download Folder Layout", language: settingsStore.interfaceLanguage))
                        .accessibilityIdentifier("settings.output-folder-layout")
                    }
                }
            }

            settingsSection("Queue", systemImage: "list.bullet.rectangle") {
                settingsRow("Concurrent Tasks") {
                    Stepper(value: $settingsStore.jobConcurrency, in: 1...12) {
                        Text("\(settingsStore.jobConcurrency)")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 150, alignment: .trailing)
                }

                settingsRow("Threads per Task") {
                    Stepper(value: $settingsStore.fileConcurrency, in: 1...24) {
                        Text("\(settingsStore.fileConcurrency)")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 150, alignment: .trailing)
                }

                settingsRow("Retry Incomplete") {
                    trailingSettingsControl {
                        HStack(spacing: 10) {
                            incompleteRetryDelayMenu

                            Toggle("", isOn: Binding(
                                get: { settingsStore.retryIncompleteAutomatically },
                                set: { manager.setRetryIncompleteAutomatically($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityLabel(AppLocalization.text("Automatically retry incomplete downloads", language: settingsStore.interfaceLanguage))
                            .accessibilityIdentifier("settings.incomplete-retry-toggle")
                        }
                    }
                }

                settingsRow("Skip Duplicate URLs") {
                    settingsSwitch("Skip Duplicate URLs", isOn: Binding(
                        get: { settingsStore.skipDuplicates },
                        set: { manager.setSkipDuplicates($0) }
                    ))
                    .accessibilityIdentifier("settings.skip-duplicates")
                }

                settingsRow("Automatically remove completed tasks") {
                    settingsSwitch("Automatically remove completed tasks", isOn: Binding(
                        get: { settingsStore.autoRemoveFinishedJobs },
                        set: { manager.setAutoRemoveFinishedJobs($0) }
                    ))
                    .accessibilityIdentifier("settings.auto-remove-finished")
                }

                settingsRow("Show download date") {
                    settingsSwitch("Show download date", isOn: Binding(
                        get: { settingsStore.showDownloadDate },
                        set: { manager.setShowDownloadDate($0) }
                    ))
                    .accessibilityIdentifier("settings.show-download-date")
                }

                settingsRow("Number playlist files") {
                    settingsSwitch("Number playlist files", isOn: Binding(
                        get: { settingsStore.numberPlaylistFiles },
                        set: { manager.setNumberPlaylistFiles($0) }
                    ))
                    .accessibilityIdentifier("settings.number-playlist-files")
                }
            }

            settingsSection("Naming", systemImage: "textformat") {
                settingsRow("Work Folder") {
                    editableTemplatePicker(
                        placeholder: DownloadSourceFolderProfile.originalDefaultFolderTemplate,
                        text: Binding(
                            get: { settingsStore.folderNameTemplate },
                            set: { manager.setFolderNameTemplate($0) }
                        ),
                        presets: NameTemplate.originalFolderPresets,
                        accessibilityPrefix: "settings.folder-template"
                    ) {
                        manager.applyFolderNamePreset($0)
                    }
                }

                settingsRow("Individual Files") {
                    if DownloadSourceFolderProfile.normalizedSourceID(
                        settingsStore.selectedSourceFolderID
                    ) == "hitomi" &&
                        outputSettingsPresentation
                            .usesOriginalHitomiFilenameMode {
                        hitomiFilenameTypePicker
                    } else {
                        editableTemplatePicker(
                            placeholder: NameTemplate.originalFileDefault(
                                for: settingsStore.selectedSourceFolderID
                            ) ?? "{index:04}-{basename}",
                            text: Binding(
                                get: {
                                    outputSettingsPresentation
                                        .selectedSourceFileNameTemplate
                                },
                                set: { manager.setSelectedSourceFileNameTemplate($0) }
                            ),
                            presets:
                                outputSettingsPresentation
                                    .selectedSourceFileNamePresets,
                            accessibilityPrefix: "settings.file-template"
                        ) {
                            manager.applySelectedSourceFileNamePreset($0)
                        }
                    }
                }

                settingsRow("Recording File") {
                    trailingSettingsControl {
                        HStack(spacing: 8) {
                            editableTemplatePicker(
                                placeholder: "[artist] date:%Y-%m-%d %H:%M; title",
                                text: Binding(
                                    get: { settingsStore.recordingFileNameTemplate },
                                    set: { manager.setRecordingFileNameTemplate($0) }
                                ),
                                presets: NameTemplate.originalRecordingPresets,
                                accessibilityPrefix: "settings.recording-template"
                            ) {
                                manager.applyRecordingFileNamePreset($0)
                            }
                        }
                    }
                }
            }
        }
    }

    private var networkSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("DPI Bypass", systemImage: "checkmark.shield") {
                settingsRow(
                    "Mode",
                    detail: settingsStore.dpiBypassMode.detailLocalizationKey,
                    detailPlacement: .fullWidth
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: networkStore.dpiBypassSnapshot.phase.systemImage)
                            .foregroundStyle(browserDPIBypassStatusColor(
                                networkStore.dpiBypassSnapshot.phase
                            ))
                            .frame(width: 18, height: 18)
                            .help(browserDPIBypassStatusHelp)
                            .accessibilityLabel(localized(
                                networkStore.dpiBypassSnapshot.phase.localizationKey
                            ))
                            .accessibilityValue(browserDPIBypassStatusHelp)
                            .accessibilityIdentifier("settings.browser-dpi-status")

                        Picker("", selection: Binding(
                            get: { settingsStore.dpiBypassMode },
                            set: { manager.setDPIBypassMode($0) }
                        )) {
                            ForEach(DPIBypassMode.allCases) { mode in
                                Text(localized(mode.localizationKey))
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(localized("DPI Bypass Mode"))
                        .accessibilityIdentifier("settings.browser-dpi-mode")
                        .disabled(networkStore.dpiBypassSnapshot.phase.isBusy)
                    }
                }

                if !networkStore.dpiBypassSnapshot.diagnostic.isEmpty {
                    Label {
                        Text(localizedStatus(networkStore.dpiBypassSnapshot.diagnostic))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.browser-dpi-diagnostic")
                }

                if networkStore.dpiBypassSnapshot.hasRestorableProxySettings {
                    settingsRow("Saved Network Settings") {
                        Button {
                            manager.restoreBrowserDPIProxySettings()
                        } label: {
                            Label(localized("Restore"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(networkStore.dpiBypassSnapshot.phase.isBusy)
                        .accessibilityIdentifier("settings.browser-dpi-restore")
                    }
                }

                Button {
                    presentation.browserDPIAdvancedExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: presentation.browserDPIAdvancedExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 14)
                        Label(localized("Advanced"), systemImage: "slider.horizontal.3")
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel(localized("Advanced"))
                .accessibilityValue(localized(presentation.browserDPIAdvancedExpanded ? "On" : "Off"))
                .accessibilityIdentifier("settings.browser-dpi-advanced")

                if presentation.browserDPIAdvancedExpanded {
                    settingsRow("Proxy Address") {
                        HStack(spacing: 8) {
                            Text(networkStore.dpiBypassSnapshot.endpoint.displayValue)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .textSelection(.enabled)
                                .layoutPriority(1)
                                .accessibilityIdentifier("settings.browser-dpi-address")
                            iconButton("doc.on.doc", help: "Copy Proxy Address") {
                                manager.copyBrowserDPIProxyAddress()
                            }
                            .accessibilityIdentifier("settings.browser-dpi-copy")
                            iconButton("arrow.clockwise", help: "Refresh Proxy Status") {
                                manager.refreshBrowserDPIBypassStatus()
                            }
                            .accessibilityIdentifier("settings.browser-dpi-refresh")
                            iconButton("gearshape", help: "Open macOS Proxy Settings") {
                                manager.openBrowserDPIProxySettings()
                            }
                            .accessibilityIdentifier("settings.browser-dpi-open-settings")
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
            }

            settingsSection("Proxy", systemImage: "network") {
                settingsRow(
                    "Use Proxy",
                    detail: settingsStore.proxyEnabled && settingsStore.dpiBypassMode.usesLocalProxy
                        ? "DPI bypass first; saved proxy resumes when off"
                        : "Manual proxy for supported downloads"
                ) {
                    settingsSwitch("Use Proxy", isOn: Binding(
                        get: { settingsStore.proxyEnabled },
                        set: { enabled in
                            settingsStore.proxyEnabled = enabled
                            if !enabled {
                                manager.saveProxySettings()
                            }
                        }
                    ))
                }

                settingsRow("URL") {
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:8080", text: $settingsStore.proxyURLString)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!settingsStore.proxyEnabled)
                        iconButton("checkmark", help: "Save Proxy Settings") {
                            manager.saveProxySettings()
                        }
                        .disabled(!settingsStore.proxyEnabled)
                    }
                }

                settingsRow("Bypass Addresses") {
                    TextField("example.com, *.internal.test", text: $settingsStore.proxyBypassList)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!settingsStore.proxyEnabled)
                }

                settingsRow("Public IP") {
                    HStack(spacing: 8) {
                        iconButton(networkStore.isRefreshingPublicIP ? "hourglass" : "arrow.clockwise", help: "Check Public IP") {
                            manager.refreshPublicIP()
                        }
                        .disabled(networkStore.isRefreshingPublicIP)
                        Text(localizedStatus(networkStore.publicIPStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            settingsSection("Cookies", systemImage: "key") {
                settingsRow("Import") {
                    HStack(spacing: 8) {
                        iconButton("key", help: "Import cookies.txt or a Cookie header") {
                            manager.importCookies()
                        }
                        iconButton("globe", help: "Import Browser Cookies") {
                            manager.importBrowserCookies()
                        }
                        iconButton("magnifyingglass", help: "Locate Browser Cookie Database") {
                            manager.importDetectedBrowserCookies()
                        }
                        iconButton("person.crop.circle.badge.key", help: "Open Login Browser") {
                            manager.openLoginBrowser()
                        }
                        cookieClearButton()
                        Text(localizedStatus(cookieStatusStore.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            settingsSection("HTTP API", systemImage: "server.rack") {
                settingsRow("HTTP API") {
                    settingsSwitch("HTTP API", isOn: Binding(
                        get: { settingsStore.httpAPIEnabled },
                        set: { manager.setHTTPAPIEnabled($0) }
                    ))
                }

                if settingsStore.httpAPIEnabled {
                    settingsRow("Lazy-load images") {
                        settingsSwitch("Lazy-load images", isOn: Binding(
                            get: { settingsStore.httpViewerLazyLoading },
                            set: { manager.setHTTPViewerLazyLoading($0) }
                        ))
                    }

                    settingsRow("Port") {
                        HStack(spacing: 8) {
                            TextField(
                                "8110",
                                text: $settingsStore.httpAPIPortString
                            )
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 90)
                            SecureField(
                                localized("Password"),
                                text: $settingsStore.httpAPIPassword
                            )
                                .textFieldStyle(.roundedBorder)
                            iconButton("checkmark", help: "Save HTTP API Settings") {
                                manager.saveHTTPAPISettings()
                            }
                        }
                    }

                    settingsRow("Status") {
                        Text(localizedStatus(networkStore.httpAPIStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private func browserDPIBypassStatusColor(_ phase: BrowserDPIBypassPhase) -> Color {
        switch phase {
        case .active:
            return .green
        case .failed, .conflictingSystemProxy, .restoreRequired:
            return .red
        case .starting, .detectingNetwork, .configuringSystemProxy,
             .restoringSystemProxy, .waitingForSystemProxy,
             .partiallyConfigured, .waitingForProxyRemoval:
            return .orange
        case .off:
            return .secondary
        }
    }

    private var browserDPIBypassStatusHelp: String {
        let snapshot = networkStore.dpiBypassSnapshot
        let diagnostic = snapshot.diagnostic.trimmed
        return [
            localized(snapshot.phase.localizationKey),
            snapshot.networkService.trimmed,
            diagnostic.isEmpty ? "" : localizedStatus(diagnostic)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private var liveSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Automatic Recording", systemImage: "record.circle") {
                settingsRow("Enable Automatic Recording") {
                    settingsSwitch("Enable Automatic Recording", isOn: Binding(
                        get: { autoRecordStore.isEnabled },
                        set: { manager.setAutoRecordEnabled($0) }
                    ))
                }

                settingsRow("Automatic Recording Paused") {
                    settingsSwitch("Automatic Recording Paused", isOn: Binding(
                        get: { autoRecordStore.isPaused },
                        set: { manager.setAutoRecordPaused($0) }
                    ))
                    .disabled(!autoRecordStore.isEnabled)
                }

                settingsRow("Check Interval") {
                    HStack(spacing: 8) {
                        TextField("10", text: $autoRecordStore.intervalMinutesString)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                        iconButton(autoRecordStore.isChecking ? "hourglass" : "arrow.clockwise", help: "Check Automatic Recording Sources Now") {
                            manager.checkAutoRecordNow()
                        }
                        .disabled(autoRecordStore.isChecking || autoRecordStore.isPaused)
                        iconButton("checkmark", help: "Save Automatic Recording Settings") {
                            manager.saveAutoRecordSettings()
                        }
                    }
                }

                settingsRow("Source") {
                    TextEditor(text: $autoRecordStore.urlsText)
                        .font(.caption)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.separator, lineWidth: 1)
                        )
                }

                settingsRow("Status") {
                    Text(localizedStatus(autoRecordStore.status))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            settingsSection("HLS", systemImage: "film.stack") {
                settingsRow("Remux to MP4") {
                    settingsSwitch("Remux to MP4", isOn: Binding(
                        get: { settingsStore.remuxM3U8ToMP4 },
                        set: { settingsStore.remuxM3U8ToMP4 = $0 }
                    ))
                }

                settingsRow("Skip failed items") {
                    settingsSwitch("Skip failed items", isOn: Binding(
                        get: { settingsStore.hlsContinueOnSegmentFailure },
                        set: { settingsStore.hlsContinueOnSegmentFailure = $0 }
                    ))
                }

                settingsRow("Delay") {
                    HStack(spacing: 8) {
                        TextField(localized("Delay (ms)"), text: Binding(
                            get: { settingsStore.m3u8SegmentDelayMillisecondsString },
                            set: { settingsStore.m3u8SegmentDelayMillisecondsString = $0 }
                        ))
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        iconButton("checkmark", help: "Save HLS Settings") {
                            manager.saveM3U8RemuxSetting()
                        }
                    }
                }

                settingsRow("Prevent sleep while downloading") {
                    settingsSwitch("Prevent sleep while downloading", isOn: Binding(
                        get: { settingsStore.preventSleepWhileDownloading },
                        set: { manager.setPreventSleepWhileDownloading($0) }
                    ))
                }
            }
        }
    }

    private var themeSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                settingsRow("Theme") {
                    trailingSettingsControl {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { settingsStore.selectedPythonThemeKey },
                                set: { manager.setSelectedPythonThemeKey($0) }
                            )) {
                                Text(localized("Default")).tag("")
                                ForEach(themePresentation.availableThemes) { theme in
                                    Text(theme.displayName).tag(theme.key)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 174, alignment: .trailing)
                            .accessibilityLabel(localized("Theme"))
                            .accessibilityIdentifier("settings.theme-picker")

                            iconButton("puzzlepiece.extension", help: "Open Theme Plugin") {
                                navigation.openSettings(.plugins)
                            }
                            .frame(width: 38)
                            .accessibilityIdentifier("settings.theme-plugin")
                        }
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                settingsRow("Appearance") {
                    trailingSettingsControl {
                        Picker("", selection: Binding(
                            get: { settingsStore.appAppearanceMode },
                            set: { manager.setAppAppearanceMode($0) }
                        )) {
                            ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220, alignment: .trailing)
                        .disabled(
                            themePresentation.activeTheme?.appearance != nil &&
                                themePresentation.activeTheme?.appearance != .system
                        )
                        .accessibilityLabel(localized("Appearance"))
                        .accessibilityIdentifier("settings.appearance")
                    }
                }

                settingsRow("UI Scale") {
                    trailingSettingsControl {
                        uiScaleSelector
                            .frame(width: 110, alignment: .trailing)
                    }
                }

                settingsRow("Font") {
                    trailingSettingsControl {
                        HStack(spacing: 10) {
                            Text(settingsStore.interfaceFontSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button {
                                navigation.open(.fontSettings)
                            } label: {
                                Label(localized("Edit"), systemImage: "textformat.size")
                            }
                            .accessibilityIdentifier("settings.font-edit")
                        }
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                settingsRow("Low Power Mode") {
                    trailingSettingsControl {
                        settingsSwitch("Low Power Mode", isOn: Binding(
                            get: { settingsStore.lowPowerMode },
                            set: { manager.setLowPowerMode($0) }
                        ))
                    }
                }

                settingsRow("Launch at Login") {
                    trailingSettingsControl {
                        settingsSwitch("Launch at Login", isOn: Binding(
                            get: { settingsStore.launchAtLoginEnabled },
                            set: { manager.setLaunchAtLoginEnabled($0) }
                        ))
                    }
                }
            }

            settingsSection("Queue Colors", systemImage: "paintpalette") {
                settingsRow("Status Colors") {
                    trailingSettingsControl {
                        HStack(spacing: 10) {
                            Text(statusColorSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button {
                                manager.beginEditingStatusColors()
                            } label: {
                                Label(localized("Edit"), systemImage: "paintpalette")
                            }
                            .accessibilityIdentifier("settings.status-colors-edit")
                        }
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                settingsRow("Duplicate Preview") {
                    trailingSettingsControl {
                        settingsSwitch("Show Thumbnails in Duplicate Image Preview", isOn: Binding(
                            get: { settingsStore.showDuplicateImageThumbnails },
                            set: { manager.setDuplicateImageThumbnails($0) }
                        ))
                        .disabled(settingsStore.lowPowerMode)
                    }
                }

                settingsRow("Similarity") {
                    trailingSettingsControl {
                        Stepper(value: Binding(
                            get: { settingsStore.duplicateImageSimilarityPercent },
                            set: { manager.setDuplicateImageSimilarityPercent($0) }
                        ), in: 70...100) {
                            Text("\(settingsStore.duplicateImageSimilarityPercent)%")
                                .monospacedDigit()
                        }
                        .frame(maxWidth: 170, alignment: .trailing)
                    }
                }
            }

            settingsSection("Task Tags", systemImage: "tag") {
                ForEach(TaskTagColor.allCases) { tag in
                    settingsRow(tag.label) {
                        trailingSettingsControl {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                                TextField(tag.label, text: Binding(
                                    get: { settingsStore.taskTagDisplayName(tag) },
                                    set: { manager.setTaskTagName($0, for: tag) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 170)
                                .accessibilityLabel(AppLocalization.format(
                                    "%@ Tag Name",
                                    language: settingsStore.interfaceLanguage,
                                    AppLocalization.text(tag.label, language: settingsStore.interfaceLanguage)
                                ))
                                .accessibilityIdentifier("settings.task-tag-name.\(tag.rawValue)")

                                taskTagRestartTimerMenu(tag)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                settingsRow("Reset") {
                    trailingSettingsControl {
                        iconButton("arrow.counterclockwise", help: "Reset Task Tag Names") {
                            manager.resetTaskTagNames()
                        }
                        .accessibilityIdentifier("settings.task-tag-reset")
                    }
                }
            }
        }
    }

    private func trailingSettingsControl<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var sourceFolderProfileMenu: some View {
        SourceFolderPopUpButton(
            profiles: outputSettingsPresentation.sourceFolderProfiles,
            selectedID: settingsStore.selectedSourceFolderID,
            language: settingsStore.interfaceLanguage
        ) {
            manager.selectSourceFolder($0)
        }
        .frame(width: 220, height: 24)
    }

    private func editableTemplatePicker(
        placeholder: String,
        text: Binding<String>,
        presets: [String],
        accessibilityPrefix: String,
        apply: @escaping (String) -> Void
    ) -> some View {
        EditablePresetComboBox(
            placeholder: placeholder,
            text: text,
            presets: presets,
            accessibilityIdentifier: accessibilityPrefix,
            onPreset: apply
        )
        .frame(width: 220, height: 26)
        .help(AppLocalization.text(
            "Choose a preset or edit the format directly",
            language: settingsStore.interfaceLanguage
        ))
    }

    private var hitomiFilenameTypePicker: some View {
        Picker("", selection: Binding(
            get: {
                outputSettingsPresentation.selectedHitomiFilenameTypeNumber
            },
            set: { manager.setHitomiFilenameTypeNumber($0) }
        )) {
            Text(localized("Original Filename")).tag(0)
            Text(localized("Four-Digit Number (0000)")).tag(1)
            Text(localized("Four-Digit Number + Original Filename")).tag(2)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
        .accessibilityLabel(AppLocalization.text(
            "Hitomi Filename Format",
            language: settingsStore.interfaceLanguage
        ))
        .accessibilityValue(
            outputSettingsPresentation.selectedSourceFileNameTemplate
        )
        .accessibilityIdentifier("settings.file-template")
    }

    private func settingsFavicon(resourceKey: String) -> NSImage? {
        guard let source = SiteFaviconCatalog.image(resourceKey: resourceKey),
              let image = source.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func taskTagRestartTimerMenu(_ tag: TaskTagColor) -> some View {
        let selected = settingsStore.taskTagRestartDelay(for: tag)
        let description = settingsStore.taskTagRestartTimerDescription(for: tag)
        return Menu {
            ForEach(TaskTagRestartDelay.allCases) { delay in
                Button {
                    manager.setTaskTagRestartDelay(delay, for: tag)
                } label: {
                    if selected == delay {
                        Label(delay.label, systemImage: "checkmark")
                    } else {
                        Text(delay.label)
                    }
                }
            }
        } label: {
            Image(systemName: selected == .off ? "clock" : "clock.fill")
                .foregroundStyle(selected == .off ? Color.secondary : Color.accentColor)
                .frame(width: 24, height: 24, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(AppLocalization.format(
            "After completion: %@",
            language: settingsStore.interfaceLanguage,
            description
        ))
        .accessibilityLabel(AppLocalization.format(
            "%@ Tag Restart Timer",
            language: settingsStore.interfaceLanguage,
            AppLocalization.text(tag.label, language: settingsStore.interfaceLanguage)
        ))
        .accessibilityValue(description)
        .accessibilityIdentifier("settings.task-tag-timer.\(tag.rawValue)")
    }

    private var uiScaleSelector: some View {
        Picker(localized("UI Scale"), selection: Binding(
            get: { settingsStore.uiScale },
            set: { manager.setUIScale($0) }
        )) {
            ForEach(AppUIScale.allCases, id: \.self) { scale in
                Text(scale.label)
                    .tag(scale)
                    .accessibilityIdentifier("settings.ui-scale.\(scale.rawValue)")
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel(AppLocalization.text("UI Scale", language: settingsStore.interfaceLanguage))
        .accessibilityIdentifier("settings.ui-scale-selector")
    }

    private var incompleteRetryDelayMenu: some View {
        Picker("", selection: Binding(
            get: { settingsStore.incompleteRetryDelay },
            set: { manager.setIncompleteRetryDelay($0) }
        )) {
            ForEach(IncompleteRetryDelay.allCases) { delay in
                Text(delay.label(language: settingsStore.interfaceLanguage))
                    .tag(delay)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 100, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(!settingsStore.retryIncompleteAutomatically)
        .accessibilityLabel(AppLocalization.text(
            "Incomplete retry delay",
            language: settingsStore.interfaceLanguage
        ))
        .accessibilityValue(settingsStore.incompleteRetryDelay.label(language: settingsStore.interfaceLanguage))
        .accessibilityIdentifier("settings.incomplete-retry-delay")
    }

    private var archiveSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Images", systemImage: "photo") {
                settingsRow("Format Conversion") {
                    Picker("", selection: Binding(
                        get: { settingsStore.imageConversionFormat },
                        set: { manager.setImageConversionFormat($0) }
                    )) {
                        ForEach(ImageConversionFormat.allCases, id: \.self) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170, alignment: .trailing)
                }
            }

            settingsSection("Archive Icon", systemImage: "archivebox.fill") {
                settingsRow("Hide Missing Archive Icons") {
                    settingsSwitch(
                        "Hide Missing Archive Icons",
                        isOn: Binding(
                            get: { settingsStore.hideArchiveIndicatorWhenFileMissing },
                            set: { manager.setHideArchiveIndicatorWhenFileMissing($0) }
                        )
                    )
                    .accessibilityIdentifier("settings.hide-missing-archive-indicator")
                }
            }

            settingsSection("Archive by Source", systemImage: "archivebox") {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(localized("Search Sources"), text: $presentation.archiveFilter)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.archive-source-filter")
                    if !presentation.archiveFilter.trimmed.isEmpty {
                        Button {
                            presentation.archiveFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help(AppLocalization.text("Clear Source Search", language: settingsStore.interfaceLanguage))
                    }
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(filteredArchiveSourceProfiles.enumerated()), id: \.element.id) { index, profile in
                        archiveSourceRow(profile)
                        if index < filteredArchiveSourceProfiles.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func archiveSourceRow(_ profile: DownloadSourceFolderProfile) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = settingsFavicon(resourceKey: profile.faviconKey) {
                    Image(nsImage: image)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "questionmark.square")
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
            }

            Text(profile.displayName)
                .font(.subheadline)
                .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if profile.supportsFolderArchive {
                Picker("", selection: Binding(
                    get: { manager.sourceArchiveMode(for: profile.id) },
                    set: { manager.setSourceArchiveMode($0, for: profile.id) }
                )) {
                    ForEach(SourceArchiveMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 88, alignment: .trailing)
                .accessibilityLabel(AppLocalization.format(
                    "%@ Archive Format",
                    language: settingsStore.interfaceLanguage,
                    profile.displayName
                ))
                .accessibilityIdentifier("settings.archive-mode.\(profile.id)")

                settingsSwitch(
                    "Delete Original Files",
                    isOn: Binding(
                    get: { manager.sourceArchiveDeletesOriginal(for: profile.id) },
                    set: { manager.setSourceArchiveDeleteOriginal($0, for: profile.id) }
                ))
                .controlSize(.small)
                .disabled(manager.sourceArchiveMode(for: profile.id) == .pass)
                .accessibilityLabel(AppLocalization.format(
                    "%@ Delete Original Folder",
                    language: settingsStore.interfaceLanguage,
                    profile.displayName
                ))
                .accessibilityIdentifier("settings.archive-delete.\(profile.id)")
            } else {
                Text(localized("Single File"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 144, alignment: .trailing)
                    .accessibilityIdentifier("settings.archive-single.\(profile.id)")
            }
        }
        .frame(minHeight: 28)
        .opacity(profile.supportsFolderArchive ? 1 : 0.55)
    }

    private var pluginSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Python Scripts", systemImage: "terminal") {
                settingsRow("Runtime") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField(
                                localized("Automatically Select Python 3"),
                                text: $externalToolStore.pythonPath
                            )
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    manager.savePythonPath()
                                }
                            iconButton("folder", help: "Choose Python 3 Executable") {
                                manager.choosePythonExecutable()
                            }
                            iconButton("checkmark", help: "Save Python Path") {
                                manager.savePythonPath()
                            }
                        }
                        Text(localizedStatus(pythonRuntimeStore.scriptStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                settingsRow("Scripts") {
                    HStack(spacing: 8) {
                        iconButton("doc.badge.plus", help: "Import Script into Current Session") {
                            manager.importPythonScript()
                        }
                        iconButton("plus", help: "Install Python Plugin") {
                            manager.installPythonPlugin()
                        }
                        iconButton("arrow.clockwise", help: "Reload Python Scripts") {
                            manager.reloadPythonScriptPlugins()
                        }
                        .disabled(pythonRuntimeStore.isReloadingScripts)
                        iconButton("folder", help: "Show Python Plugin Folder") {
                            manager.revealPythonPluginFolder()
                        }
                        Text("\(pythonRuntimeStore.scriptPlugins.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                settingsRow("Hook Status") {
                    Text(localizedStatus(pythonRuntimeStore.hookStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                settingsRow("Theme Status") {
                    Text(localizedStatus(pythonRuntimeStore.themeStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if pythonRuntimeStore.scriptPlugins.isEmpty {
                    Text(localized("No Python scripts"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(pythonRuntimeStore.scriptPlugins) { plugin in
                            PythonScriptPluginRow(plugin: plugin) { enabled in
                                manager.setPythonScriptPluginEnabled(plugin, enabled: enabled)
                            } remove: {
                                manager.removePythonScriptPlugin(plugin)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120, maxHeight: 220)
                }
            }

            settingsSection("Site Rules", systemImage: "puzzlepiece.extension") {
                settingsRow("Import / Export") {
                    HStack(spacing: 8) {
                        iconButton("square.and.arrow.down", help: "Import Site Rules") {
                            manager.importSiteRules()
                        }
                        iconButton("square.and.arrow.up", help: "Export Site Rules") {
                            manager.exportSiteRules()
                        }
                        Text("\(libraryStore.siteRules.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                settingsRow("Rules") {
                    HStack(spacing: 8) {
                        TextField(localized("Name"), text: $presentation.newSiteRuleName)
                            .textFieldStyle(.roundedBorder)
                        TextField("host.com", text: $presentation.newSiteRuleHost)
                            .textFieldStyle(.roundedBorder)
                        iconButton("plus", help: "Save Site Rule") {
                            manager.addSiteRule()
                        }
                    }
                }

                settingsRow("Address Pattern") {
                    TextField(localized("/path/* or /view?id=*"), text: $presentation.newSiteRuleURLPattern)
                        .textFieldStyle(.roundedBorder)
                }

                settingsRow("Command") {
                    TextField(localized("Command {url} {output}"), text: $presentation.newSiteRuleCommand)
                        .textFieldStyle(.roundedBorder)
                }

                settingsRow("Headers") {
                    HStack(spacing: 8) {
                        TextField("referer {url}", text: $presentation.newSiteRuleReferer)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("User Agent"), text: $presentation.newSiteRuleUserAgent)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                settingsRow("Archive") {
                    Picker("", selection: $presentation.newSiteRuleArchiveMode) {
                        ForEach(SiteArchiveMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130, alignment: .trailing)
                }

                settingsRow("Delete Original After Archiving") {
                    settingsSwitch(
                        "Delete Original After Archiving",
                        isOn: $presentation.newSiteRuleDeleteOriginalAfterArchiving
                    )
                    .disabled(!presentation.newSiteRuleArchiveMode.archives)
                }

                if libraryStore.siteRules.isEmpty {
                    Text(localized("No site rules"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(libraryStore.siteRules) { rule in
                            SiteRuleRow(rule: rule) { enabled in
                                manager.setSiteRuleEnabled(rule, enabled: enabled)
                            } remove: {
                                manager.removeSiteRule(rule)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120)
                }
            }
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Notifications", systemImage: "bell") {
                settingsRow("Task Notifications") {
                    settingsSwitch("Task Notifications", isOn: Binding(
                        get: { settingsStore.notifyWhenJobCompletes },
                        set: { manager.setNotifyWhenJobCompletes($0) }
                    ))
                    .accessibilityIdentifier("settings.notify-job")
                }

                settingsRow("Queue Completion Notification") {
                    settingsSwitch("Queue Completion Notification", isOn: Binding(
                        get: { settingsStore.notifyWhenQueueCompletes },
                        set: { manager.setNotifyWhenQueueCompletes($0) }
                    ))
                    .accessibilityIdentifier("settings.notify-queue")
                }

                settingsRow("Task Completion Sound") {
                    settingsSwitch("Task Completion Sound", isOn: Binding(
                        get: { settingsStore.playSoundWhenJobCompletes },
                        set: { manager.setPlaySoundWhenJobCompletes($0) }
                    ))
                    .accessibilityIdentifier("settings.sound-job")
                }

                settingsRow("Clipboard Add Sound") {
                    settingsSwitch("Clipboard Add Sound", isOn: Binding(
                        get: { settingsStore.playSoundOnClipboardAdd },
                        set: { manager.setPlaySoundOnClipboardAdd($0) }
                    ))
                    .accessibilityIdentifier("settings.sound-clipboard")
                }

                settingsRow("After Completion") {
                    Picker("", selection: Binding(
                        get: { settingsStore.queueCompletionAction },
                        set: { manager.setQueueCompletionAction($0) }
                    )) {
                        ForEach(QueueCompletionAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170, alignment: .trailing)
                }
            }

            settingsSection("Automation", systemImage: "bolt") {
                settingsRow("Monitor Clipboard") {
                    settingsSwitch("Monitor Clipboard", isOn: Binding(
                        get: { settingsStore.clipboardMonitorEnabled },
                        set: { manager.setClipboardMonitorEnabled($0) }
                    ))
                    .accessibilityIdentifier("settings.clipboard-monitor")
                }

                settingsRow("Start Immediately When Pasted") {
                    settingsSwitch("Start Immediately When Pasted", isOn: Binding(
                        get: { settingsStore.startDownloadsOnPaste },
                        set: { manager.setStartDownloadsOnPaste($0) }
                    ))
                    .accessibilityIdentifier("settings.start-on-paste")
                    .help(AppLocalization.text(
                        "Press Command-V in the main window to add clipboard URLs and start the queue",
                        language: settingsStore.interfaceLanguage
                    ))
                }

                settingsRow("Auto-remove Hook") {
                    HStack(spacing: 8) {
                        TextField("auto-remove hook {url} {output}", text: $settingsStore.autoRemoveHookCommand)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save Auto-remove Hook") {
                            manager.saveAutoRemoveHookCommand()
                        }
                    }
                }

                settingsRow("Hook Status") {
                    Text(localizedStatus(appStatusStore.autoRemoveHookStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                settingsRow("Shortcuts") {
                    HStack(spacing: 10) {
                        Button {
                            navigation.openShortcuts()
                        } label: {
                            Label(localized("Edit"), systemImage: "keyboard")
                        }
                        Text(settingsStore.appShortcutSummary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                settingsRow("Floating Monitor") {
                    HStack(spacing: 10) {
                        settingsSwitch("Show Floating Monitor", isOn: Binding(
                            get: { appPresentation.showingFloatingMonitor },
                            set: { navigation.setFloatingMonitorVisible($0) }
                        ))
                        .help(AppLocalization.text("Show Floating Monitor", language: settingsStore.interfaceLanguage))

                        Slider(value: Binding(
                            get: { settingsStore.floatingMonitorOpacity },
                            set: { manager.setFloatingMonitorOpacity($0) }
                        ), in: 0.45...1)
                        .frame(maxWidth: 150)
                        .help(AppLocalization.text("Floating Monitor Opacity", language: settingsStore.interfaceLanguage))

                        Text(settingsStore.floatingMonitorOpacityPercentText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            settingsSection("External Tools", systemImage: "terminal") {
                settingsRow("Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if externalToolStore.isInstalling {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(localizedStatus(externalToolStore.installStatus))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(localizedStatus(
                            ExternalToolPresentationService.availabilitySummary(
                                store: externalToolStore,
                                language: settingsStore.interfaceLanguage
                            )
                        ))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                settingsRow("yt-dlp") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("yt-dlp Path"),
                            text: $externalToolStore.ytdlpPath
                        )
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.ytdlp)
                        iconButton("square.and.arrow.down", help: "Install or Update yt-dlp") {
                            manager.installManagedExternalTool(.ytdlp)
                        }
                        .disabled(externalToolStore.isInstalling)
                    }
                }

                settingsRow("Deno") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("Deno Path"),
                            text: $externalToolStore.denoPath
                        )
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.deno)
                        iconButton("square.and.arrow.down", help: "Install or Update Deno") {
                            manager.installManagedExternalTool(.deno)
                        }
                        .disabled(externalToolStore.isInstalling)
                    }
                }

                settingsRow("ffmpeg") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("ffmpeg Path"),
                            text: $externalToolStore.ffmpegPath
                        )
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.ffmpeg)
                        iconButton("square.and.arrow.down", help: "Install or Update FFmpeg and ffprobe") {
                            manager.installManagedExternalTool(.ffmpeg)
                        }
                        .disabled(externalToolStore.isInstalling)
                    }
                }

                settingsRow("aria2c") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("aria2c Path"),
                            text: $externalToolStore.aria2Path
                        )
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.aria2c)
                        iconButton("arrow.clockwise", help: "Restore Bundled aria2c") {
                            manager.installManagedExternalTool(.aria2c)
                        }
                        .disabled(externalToolStore.isInstalling)
                    }
                }

                settingsRow("Manage") {
                    HStack(spacing: 10) {
                        Button {
                            manager.installAllManagedExternalTools()
                        } label: {
                            Label(localized("Install All"), systemImage: "square.and.arrow.down")
                        }
                        .disabled(externalToolStore.isInstalling)

                        iconButton("checkmark", help: "Save External Tool Paths") {
                            manager.saveExternalToolPaths()
                        }

                        if externalToolStore.isInstalling {
                            iconButton("xmark", help: "Cancel Tool Installation") {
                                manager.cancelManagedExternalToolInstallation()
                            }
                        }

                        iconButton("folder", help: "Show Managed Tools Folder") {
                            manager.revealManagedExternalTools()
                        }

                        iconButton("trash", help: "Remove Downloaded Managed Tools") {
                            manager.removeManagedExternalTools()
                        }
                        .disabled(externalToolStore.isInstalling)
                    }
                }
            }

            settingsSection("ffmpeg", systemImage: "wand.and.stars") {
                settingsRow("Enable Transcoding") {
                    settingsSwitch(
                        "Enable Transcoding",
                        isOn: $externalToolStore.ffmpegTranscodeEnabled
                    )
                }

                settingsRow("Codec") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("Video Codec"),
                            text: $externalToolStore.ffmpegVideoCodec
                        )
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            localized("Audio Codec"),
                            text: $externalToolStore.ffmpegAudioCodec
                        )
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(!externalToolStore.ffmpegTranscodeEnabled)
                }

                settingsRow("Quality") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("Video Bitrate"),
                            text: $externalToolStore.ffmpegVideoBitrate
                        )
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            localized("Audio Bitrate"),
                            text: $externalToolStore.ffmpegAudioBitrate
                        )
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(!externalToolStore.ffmpegTranscodeEnabled)
                }

                settingsRow("Preset") {
                    HStack(spacing: 8) {
                        TextField("CRF", text: $externalToolStore.ffmpegCRF)
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            localized("Preset"),
                            text: $externalToolStore.ffmpegPreset
                        )
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save FFmpeg Transcoding Options") {
                            manager.saveFFmpegTranscodeOptions()
                        }
                    }
                    .disabled(!externalToolStore.ffmpegTranscodeEnabled)
                }
            }
        }
    }

    private var hitomiSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Hitomi", systemImage: "photo.on.rectangle") {
                settingsRow("Prefer WebP") {
                    settingsSwitch("Prefer WebP", isOn: Binding(
                        get: { settingsStore.preferWebP },
                        set: { manager.setPreferWebP($0) }
                    ))
                }

                settingsRow("Save Info TXT") {
                    settingsSwitch("Save Info TXT", isOn: Binding(
                        get: { settingsStore.saveHitomiGalleryInfoText },
                        set: { manager.setSaveHitomiGalleryInfoText($0) }
                    ))
                }

                settingsRow("E-Hentai Source") {
                    Picker("", selection: Binding(
                        get: { settingsStore.eHentaiSourceMode },
                        set: { manager.setEHentaiSourceMode($0) }
                    )) {
                        ForEach(EHentaiSourceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(settingsStore.eHentaiSourceMode.helpText)
                    .accessibilityLabel(AppLocalization.text("E-Hentai Source", language: settingsStore.interfaceLanguage))
                    .accessibilityIdentifier("settings.ehentai-source-mode")
                }

                settingsRow("Prefer Original Size") {
                    settingsSwitch("Prefer Original Size", isOn: Binding(
                        get: { settingsStore.preferOriginalEHentaiImages },
                        set: { manager.setPreferOriginalEHentaiImages($0) }
                    ))
                    .help(AppLocalization.text(
                        "Use original-size E-Hentai and ExHentai files when available",
                        language: settingsStore.interfaceLanguage
                    ))
                }

                settingsRow("Use Japanese title when available") {
                    settingsSwitch("Use Japanese title when available", isOn: Binding(
                        get: { settingsStore.preferJapaneseEHentaiTitle },
                        set: { manager.setPreferJapaneseEHentaiTitle($0) }
                    ))
                    .help(AppLocalization.text(
                        "Prefer Japanese titles for E-Hentai and ExHentai save names when available",
                        language: settingsStore.interfaceLanguage
                    ))
                    .accessibilityLabel(AppLocalization.text(
                        "Use Japanese title when available",
                        language: settingsStore.interfaceLanguage
                    ))
                    .accessibilityIdentifier("settings.ehentai-japanese-title")
                }

                settingsRow("Excluded Tags") {
                    HStack(spacing: 8) {
                        TextField(
                            "female:example, male:example",
                            text: $settingsStore.hitomiExcludedTagsText
                        )
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save Hitomi Excluded Tags") {
                            manager.saveHitomiExcludedTags()
                        }
                        iconButton("xmark.circle", help: "Clear Hitomi Excluded Tags") {
                            manager.clearHitomiExcludedTags()
                        }
                        .disabled(settingsStore.hitomiExcludedTagsText.trimmed.isEmpty)
                    }
                }

                settingsRow("Tag Translation") {
                    HStack(spacing: 8) {
                        TextField(localized("Tag"), text: $searchStore.searchTagTranslationInput)
                            .textFieldStyle(.roundedBorder)
                        iconButton("arrow.triangle.2.circlepath", help: "Translate Search Tags") {
                            manager.translateSearchTagInput()
                        }
                        iconButton("plus", help: "Insert Translated Tags") {
                            manager.insertTranslatedSearchTag()
                        }
                        iconButton("arrow.left.arrow.right", help: "Replace Search Terms with Translated Tags") {
                            manager.replaceSearchQueryWithTranslatedTag()
                        }
                    }
                }

                if !searchStore.searchTagTranslationOutput.trimmed.isEmpty {
                    Text(searchStore.searchTagTranslationOutput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var pixivSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Pixiv", systemImage: "p.circle") {
                settingsRow("Ugoira") {
                    HStack(spacing: 8) {
                        Picker("", selection: Binding(
                            get: { settingsStore.pixivUgoiraFileFormat },
                            set: { settingsStore.pixivUgoiraFileFormat = $0 }
                        )) {
                            ForEach(PixivUgoiraFileFormat.allCases, id: \.self) { format in
                                Text(format.label).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 130, alignment: .trailing)
                        iconButton("checkmark", help: "Save Pixiv Ugoira Format") {
                            manager.savePixivUgoiraFileFormat()
                        }
                    }
                }
                settingsRow("GIF palette dithering", detail: "Reduce GIF color banding") {
                    settingsSwitch("GIF palette dithering", isOn: Binding(
                        get: { settingsStore.pixivUgoiraDither },
                        set: { settingsStore.pixivUgoiraDither = $0 }
                    ))
                        .disabled(settingsStore.pixivUgoiraFileFormat != .gif)
                }
                settingsRow("Quality") {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(settingsStore.pixivUgoiraQuality) },
                                set: { settingsStore.pixivUgoiraQuality = Int($0.rounded()) }
                            ),
                            in: 1...100
                        )
                        .frame(minWidth: 180, idealWidth: 320, maxWidth: 420)
                        .accessibilityLabel(localized("Quality"))
                        .accessibilityValue("\(settingsStore.pixivUgoiraQuality)")
                        .accessibilityIdentifier("settings.pixiv-quality")
                        Text("\(settingsStore.pixivUgoiraQuality)")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(maxWidth: 464, alignment: .trailing)
                    .disabled(!settingsStore.pixivUgoiraFileFormat.requiresFFmpeg)
                }
            }
        }
    }

    private var kemonoFriendsSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Kemono friends", systemImage: "network") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Archive Addresses"))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    pawchiveSiteAddressList
                }

                settingsRow("PSD Originals") {
                    trailingSettingsControl {
                        settingsSwitch("Download PSD Originals", isOn: Binding(
                            get: { settingsStore.pawchiveDownloadLargeOriginalFiles },
                            set: { manager.setPawchiveDownloadLargeOriginalFiles($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-large-originals")
                    }
                }
            }

            settingsSection("File Types to Download", systemImage: "line.3.horizontal.decrease.circle") {
                settingsRow("Image Files", detail: "JPEG, PNG, GIF") {
                    trailingSettingsControl {
                        settingsSwitch("Image Files", isOn: Binding(
                            get: { settingsStore.pawchiveDownloadImages },
                            set: { manager.setPawchiveDownloadImages($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-images")
                    }
                }

                settingsRow("Video Files", detail: "MP4, MKV") {
                    trailingSettingsControl {
                        settingsSwitch("Video Files", isOn: Binding(
                            get: { settingsStore.pawchiveDownloadVideos },
                            set: { manager.setPawchiveDownloadVideos($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-videos")
                    }
                }

                settingsRow("HTML Files", detail: "Save posts as HTML") {
                    trailingSettingsControl {
                        settingsSwitch("HTML Files", isOn: Binding(
                            get: { settingsStore.pawchiveDownloadHTML },
                            set: { manager.setPawchiveDownloadHTML($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-html")
                    }
                }

                settingsRow("Other Files", detail: "Archives and attachments") {
                    trailingSettingsControl {
                        settingsSwitch("Other Files", isOn: Binding(
                            get: { settingsStore.pawchiveDownloadOtherFiles },
                            set: { manager.setPawchiveDownloadOtherFiles($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-other")
                    }
                }
            }
        }
    }

    private var pawchiveSiteAddressList: some View {
        VStack(spacing: 0) {
            if settingsStore.pawchiveSiteAddresses.isEmpty && !presentation.isAddingPawchiveSiteAddress {
                Text(localized("No addresses added"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(Array(settingsStore.pawchiveSiteAddresses.enumerated()), id: \.element) { index, address in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 38)
                    }

                    Button {
                        presentation.pawchiveSelectedSiteAddress = address
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(address)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(
                            presentation.pawchiveSelectedSiteAddress == address
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(address)
                    .accessibilityIdentifier("settings.pawchive-address.row")
                }

                if presentation.isAddingPawchiveSiteAddress {
                    if !settingsStore.pawchiveSiteAddresses.isEmpty {
                        Divider()
                            .padding(.leading, 38)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        TextField(
                            localized("Enter an archive address"),
                            text: $presentation.pawchiveSiteAddressDraft
                        )
                        .textFieldStyle(.plain)
                        .onSubmit(commitPawchiveSiteAddress)
                        .accessibilityIdentifier("settings.pawchive-address.input")

                        iconButton("checkmark", help: "Add archive address") {
                            commitPawchiveSiteAddress()
                        }
                        .disabled(presentation.pawchiveSiteAddressDraft.trimmed.isEmpty)

                        iconButton("xmark", help: "Cancel") {
                            cancelAddingPawchiveSiteAddress()
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                }
            }

            Divider()

            HStack(spacing: 0) {
                Button {
                    beginAddingPawchiveSiteAddress()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(presentation.isAddingPawchiveSiteAddress)
                .help(localized("Add archive address"))
                .accessibilityIdentifier("settings.pawchive-address.add")

                Divider()
                    .frame(height: 18)

                Button {
                    removeSelectedPawchiveSiteAddress()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(presentation.pawchiveSelectedSiteAddress.isEmpty)
                .help(localized("Remove archive address"))
                .accessibilityIdentifier("settings.pawchive-address.remove")

                Spacer(minLength: 8)

                Button {
                    manager.resetPawchiveSiteAddresses()
                    presentation.pawchiveSelectedSiteAddress = settingsStore.pawchiveSiteAddresses.first ?? ""
                    cancelAddingPawchiveSiteAddress()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(settingsStore.pawchiveSiteAddresses == PawchiveResolver.defaultSiteAddresses)
                .help(localized("Restore default archive addresses"))
                .accessibilityIdentifier("settings.pawchive-address.reset")
            }
            .padding(.horizontal, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func beginAddingPawchiveSiteAddress() {
        presentation.pawchiveSiteAddressDraft = ""
        presentation.isAddingPawchiveSiteAddress = true
    }

    private func commitPawchiveSiteAddress() {
        let normalized = PawchiveResolver.normalizedSiteAddress(
            presentation.pawchiveSiteAddressDraft
        )
        manager.addPawchiveSiteAddress()
        guard let normalized,
              settingsStore.pawchiveSiteAddresses.contains(where: {
                  $0.caseInsensitiveCompare(normalized) == .orderedSame
              }) else {
            return
        }
        presentation.pawchiveSelectedSiteAddress = normalized
        presentation.isAddingPawchiveSiteAddress = false
    }

    private func cancelAddingPawchiveSiteAddress() {
        presentation.pawchiveSiteAddressDraft = ""
        presentation.isAddingPawchiveSiteAddress = false
    }

    private func removeSelectedPawchiveSiteAddress() {
        let selected = presentation.pawchiveSelectedSiteAddress
        guard !selected.isEmpty else { return }
        manager.removePawchiveSiteAddress(selected)
        presentation.pawchiveSelectedSiteAddress = settingsStore.pawchiveSiteAddresses.first ?? ""
    }

    private var youtubeSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("YouTube", systemImage: "play.rectangle") {
                settingsRow("Language") {
                    HStack(spacing: 8) {
                        TextField(localized("Language"), text: Binding(
                            get: { settingsStore.youtubePreferredLanguage },
                            set: { settingsStore.youtubePreferredLanguage = $0 }
                        ))
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save YouTube Language") {
                            manager.saveYouTubePreferredLanguage()
                        }
                    }
                }

                settingsRow("Download Thumbnail") {
                    trailingSettingsControl {
                        settingsSwitch("Download Thumbnail", isOn: Binding(
                            get: { settingsStore.youtubeDownloadThumbnail },
                            set: { manager.setYouTubeDownloadThumbnail($0) }
                        ))
                    }
                }

                settingsRow("Reverse Playlist", detail: "Last item first") {
                    trailingSettingsControl {
                        settingsSwitch("Reverse Playlist", isOn: Binding(
                            get: { settingsStore.youtubeReversePlaylist },
                            set: { manager.setYouTubeReversePlaylist($0) }
                        ))
                    }
                }

                settingsRow("Use Upload Date as File Modification Date") {
                    trailingSettingsControl {
                        settingsSwitch("Use Upload Date as File Modification Date", isOn: Binding(
                            get: { settingsStore.youtubeUseUploadDateForFileModificationTime },
                            set: { manager.setYouTubeUseUploadDateForFileModificationTime($0) }
                        ))
                        .accessibilityLabel(AppLocalization.text(
                            "Set file modification date to upload date",
                            language: settingsStore.interfaceLanguage
                        ))
                        .accessibilityIdentifier("settings.youtube-upload-date-mtime")
                    }
                }

                settingsRow("Embed Chapters") {
                    trailingSettingsControl {
                        settingsSwitch("Embed Chapters", isOn: Binding(
                            get: { settingsStore.youtubeEmbedChapters },
                            set: { manager.setYouTubeEmbedChapters($0) }
                        ))
                    }
                }

                settingsRow("Enhanced Bitrate") {
                    trailingSettingsControl {
                        settingsSwitch("Enhanced Bitrate", isOn: Binding(
                            get: { settingsStore.youtubePreferEnhancedBitrate },
                            set: { manager.setYouTubePreferEnhancedBitrate($0) }
                        ))
                    }
                }

                settingsRow("Resolution") {
                    HStack(spacing: 8) {
                        TextField("1080p", text: Binding(
                            get: { settingsStore.youtubePreferredResolution },
                            set: { settingsStore.youtubePreferredResolution = $0 }
                        ))
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save YouTube Resolution") {
                            manager.saveYouTubePreferredResolution()
                        }
                    }
                }

                settingsRow("Audio") {
                    HStack(spacing: 8) {
                        TextField(localized("Audio Language"), text: Binding(
                            get: { settingsStore.youtubePreferredAudioLanguage },
                            set: { settingsStore.youtubePreferredAudioLanguage = $0 }
                        ))
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save YouTube Audio Tracks") {
                            manager.saveYouTubePreferredAudioLanguage()
                        }
                    }
                }

                settingsRow("Subtitles", detail: "Include auto-generated subtitles") {
                    trailingSettingsControl {
                        HStack(spacing: 8) {
                            settingsSwitch("Include automatically generated subtitles", isOn: Binding(
                                get: { settingsStore.youtubeDownloadAutoSubtitles },
                                set: { manager.setYouTubeDownloadAutoSubtitles($0) }
                            ))
                            TextField("all", text: Binding(
                                get: { settingsStore.youtubeSubtitleLanguages },
                                set: { settingsStore.youtubeSubtitleLanguages = $0 }
                            ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            iconButton("checkmark", help: "Save YouTube Subtitle Settings") {
                                manager.saveYouTubeSubtitleSettings()
                            }
                        }
                    }
                }

                settingsRow("Codec Priority") {
                    trailingSettingsControl {
                        YouTubeCodecPriorityMenu(
                            codecPriority: settingsStore.youtubeVideoCodecPriority,
                            language: settingsStore.interfaceLanguage,
                            onSelect: manager.setYouTubeVideoCodecPriority
                        )
                    }
                }
            }
        }
    }

    private var socialSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Browser Login", systemImage: "person.crop.circle.badge.key") {
                settingsRow("Cookies") {
                    HStack(spacing: 8) {
                        iconButton("person.crop.circle.badge.key", help: "Open Login Browser") {
                            manager.openLoginBrowser()
                        }
                        iconButton("globe", help: "Import Browser Cookies") {
                            manager.importBrowserCookies()
                        }
                        cookieClearButton()
                        Text(localizedStatus(cookieStatusStore.summary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            settingsSection("Instagram", systemImage: "camera") {
                settingsRow("Include active stories") {
                    settingsSwitch("Include active stories", isOn: Binding(
                        get: { settingsStore.instagramIncludeStories },
                        set: { manager.setInstagramIncludeStories($0) }
                    ))
                }
            }

            settingsSection("SOOP / Afreeca", systemImage: "antenna.radiowaves.left.and.right") {
                settingsRow("Resolution") {
                    HStack(spacing: 8) {
                        TextField("720p", text: Binding(
                            get: { settingsStore.soopPreferredResolution },
                            set: { settingsStore.soopPreferredResolution = $0 }
                        ))
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save SOOP/Afreeca Resolution") {
                            manager.saveSOOPPreferredResolution()
                        }
                    }
                }
            }

            settingsSection("Search Tools", systemImage: "text.magnifyingglass") {
                settingsRow("Searcher") {
                    HStack(spacing: 8) {
                        Button {
                            navigation.open(.searcher)
                        } label: {
                            Label(localized("Open"), systemImage: "text.magnifyingglass")
                        }
                        Button {
                            navigation.open(.history)
                        } label: {
                            Label(localized("History"), systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
        }
    }

    private var torrentSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("aria2", systemImage: "arrow.down.circle") {
                settingsRow("Files") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("Files 1,3-5"),
                            text: $aria2Store.selectedFiles
                        )
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            localized("Seed time (min)"),
                            text: $aria2Store.seedTimeMinutes
                        )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                        iconButton("list.bullet.rectangle", help: "Show Torrent File List") {
                            manager.previewAria2Files()
                        }
                    }
                }

                settingsRow("Speed Limits") {
                    HStack(spacing: 8) {
                        TextField(
                            localized("Down 2M"),
                            text: $aria2Store.maxDownloadLimit
                        )
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            localized("Up 512K"),
                            text: $aria2Store.maxUploadLimit
                        )
                            .textFieldStyle(.roundedBorder)
                        TextField(
                            localized("Seed ratio"),
                            text: $aria2Store.seedRatio
                        )
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                    }
                }

                settingsRow("Anonymous Mode") {
                    settingsSwitch(
                        "Anonymous Mode",
                        isOn: $aria2Store.anonymousMode
                    )
                }

                settingsRow("Trackers") {
                    HStack(spacing: 8) {
                        TextField(
                            "udp://tracker.example/announce",
                            text: $aria2Store.trackers
                        )
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save aria2 Options") {
                            manager.saveAria2Options()
                        }
                    }
                }

                if !aria2Store.fileListSummary.isEmpty {
                    Text(localizedStatus(aria2Store.fileListSummary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !aria2Store.peerSummary.isEmpty {
                    Text(localizedStatus(aria2Store.peerSummary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    ForEach(Array(aria2Store.peerEntries.prefix(6))) { peer in
                        Text(peer.summary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(AppLocalization.text(title, language: settingsStore.interfaceLanguage))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        detail: String? = nil,
        detailPlacement: SettingsRowDetailPlacement = .label,
        @ViewBuilder control: () -> Content
    ) -> some View {
        let localizedTitle = AppLocalization.text(title, language: settingsStore.interfaceLanguage)
        let localizedDetail = detail.map {
            AppLocalization.text($0, language: settingsStore.interfaceLanguage)
        }
        let hasInlineDetail = detailPlacement == .label && localizedDetail != nil

        return VStack(
            alignment: .leading,
            spacing: detailPlacement == .fullWidth && localizedDetail != nil ? 5 : 0
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedTitle)
                            .font(.system(
                                size: NSFont.systemFontSize + 1,
                                weight: .semibold
                            ))
                            .fixedSize(horizontal: false, vertical: true)

                        if detailPlacement == .label, let localizedDetail {
                            Text(localizedDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(localizedDetail)
                        }
                    }
                    .frame(
                        minHeight: hasInlineDetail ? nil : 28,
                        alignment: .leading
                    )
                    .frame(
                        minWidth: 132,
                        idealWidth: 132,
                        maxWidth: 220,
                        alignment: .leading
                    )

                    control()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(1)
                }
                .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedTitle)
                            .font(.system(
                                size: NSFont.systemFontSize + 1,
                                weight: .semibold
                            ))
                            .fixedSize(horizontal: false, vertical: true)

                        if detailPlacement == .label, let localizedDetail {
                            Text(localizedDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(localizedDetail)
                        }
                    }
                    .frame(
                        minHeight: hasInlineDetail ? nil : 28,
                        alignment: .leading
                    )

                    control()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if detailPlacement == .fullWidth, let localizedDetail {
                Text(localizedDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(localizedDetail)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 34, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSwitch(
        _ accessibilityTitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(AppLocalization.text(
                accessibilityTitle,
                language: settingsStore.interfaceLanguage
            ))
    }

    private func toolAvailabilityIcon(_ kind: ExternalToolKind) -> some View {
        let available = manager.isExternalToolAvailable(kind)
        let path = manager.resolvedExternalToolPath(kind)
        return Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundColor(available ? .green : .secondary)
            .help(
                available
                    ? AppLocalization.format(
                        "In use: %@",
                        language: settingsStore.interfaceLanguage,
                        path
                    )
                    : AppLocalization.format(
                        "%@ is unavailable",
                        language: settingsStore.interfaceLanguage,
                        kind.displayName
                    )
            )
    }

    private func iconButton(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .help(AppLocalization.text(help, language: settingsStore.interfaceLanguage))
    }

    private func cookieClearButton() -> some View {
        Button {
            manager.clearCookies()
        } label: {
            Label(localized("Delete Cookies and Login Sessions"), systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .disabled(cookieStatusStore.isClearing)
        .help(AppLocalization.text(
            "Delete app cookies and embedded-browser login sessions",
            language: settingsStore.interfaceLanguage
        ))
        .accessibilityIdentifier("settings.clear-cookies")
    }
}
