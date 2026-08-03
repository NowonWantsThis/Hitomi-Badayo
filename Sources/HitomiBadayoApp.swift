import SwiftUI

#if !TESTING
private extension NSWindow {
    @objc func terminateHitomiBadayo(_ sender: Any?) {
        AppTerminationCoordinator.terminate()
    }
}

@MainActor
final class HitomiBadayoApplicationDelegate: NSObject, NSApplicationDelegate, ApplicationTerminationPreparing {
    weak var manager: DownloadManager?
    weak var settingsStore: SettingsStore?
    var shortcutController: AppShortcutController?
    private var sheetObservers: [NSObjectProtocol] = []
    private var menuObservers: [NSObjectProtocol] = []
    private var isApplyingMainMenuLocalization = false
    private let terminationPreparation = ApplicationTerminationPreparation()
    private weak var modalQuitItem: NSMenuItem?
    private var standardQuitTarget: AnyObject?
    private var standardQuitAction: Selector?

    func applicationDidFinishLaunching(_ notification: Notification) {
        shortcutController?.start()
        let center = NotificationCenter.default
        menuObservers = [
            center.addObserver(
                forName: NSMenu.didBeginTrackingNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let menu = notification.object as? NSMenu else { return }
                MainActor.assumeIsolated {
                    self?.localizeTrackedMenu(menu)
                }
            },
            center.addObserver(
                forName: NSWindow.didBecomeKeyNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.installStableMainMenu()
                    }
                }
            }
        ]
        installStableMainMenu()
        // SwiftUI can finish materializing the standard Edit/Window menus
        // after applicationDidFinishLaunching. Reapply localization on the
        // next main-loop turn so a clean install starts in English even when
        // the macOS display language is different.
        DispatchQueue.main.async { [weak self] in
            self?.installStableMainMenu()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            self?.installStableMainMenu()
        }
        sheetObservers = [
            center.addObserver(
                forName: NSWindow.willBeginSheetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.installModalQuitCommand()
                    }
                }
            },
            center.addObserver(
                forName: NSWindow.didEndSheetNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        self?.restoreStandardQuitCommandIfPossible()
                    }
                }
            }
        ]
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard manager?.requiresBrowserDPIProxyRestorationBeforeTermination == true,
              !terminationPreparation.isPrepared else {
            return .terminateNow
        }
        prepareForApplicationTermination { restored in
            guard restored else { return }
            sender.terminate(nil)
        }
        return .terminateCancel
    }

    func prepareForApplicationTermination(
        _ completion: @escaping @MainActor (Bool) -> Void
    ) {
        terminationPreparation.prepare(
            operation: { [weak manager] in
                guard let manager,
                      manager.requiresBrowserDPIProxyRestorationBeforeTermination else {
                    return true
                }
                return await manager.restoreBrowserDPIProxyBeforeTermination()
            },
            completion: { [weak manager] restored in
                if !restored {
                    manager?.appStatusStore.setSummary(
                        "Restore network settings before quitting"
                    )
                }
                completion(restored)
            }
        )
    }

    func applicationWillTerminate(_ notification: Notification) {
        sheetObservers.forEach { NotificationCenter.default.removeObserver($0) }
        sheetObservers.removeAll()
        menuObservers.forEach { NotificationCenter.default.removeObserver($0) }
        menuObservers.removeAll()
        shortcutController?.stop()
        manager?.prepareForTermination()
        PythonWebRendererService.shared.stop()
        LoginBrowserWindowController.closeAll()
    }

    private func installStableMainMenu() {
        guard !isApplyingMainMenuLocalization else { return }
        isApplyingMainMenuLocalization = true
        defer { isApplyingMainMenuLocalization = false }
        AppMainMenuPruner.simplify(
            NSApplication.shared.mainMenu,
            language: settingsStore?.interfaceLanguage ?? .english
        )
        guard let menu = AppMainMenuPruner.makeStableMainMenu(
            from: NSApplication.shared.mainMenu
        ) else { return }
        AppMainMenuPruner.simplify(
            menu,
            language: settingsStore?.interfaceLanguage ?? .english
        )
        if let application = NSApplication.shared as? HitomiBadayoApplication {
            application.installStableMainMenu(menu)
        } else {
            NSApplication.shared.mainMenu = menu
        }
    }

    private func localizeTrackedMenu(_ menu: NSMenu) {
        guard !isApplyingMainMenuLocalization else { return }
        isApplyingMainMenuLocalization = true
        defer { isApplyingMainMenuLocalization = false }
        let appName = NSApplication.shared.mainMenu?.items.first?.title ?? "Hitomi Badayo"
        AppMainMenuPruner.localizeTrackedMenu(
            menu,
            language: settingsStore?.interfaceLanguage ?? .english,
            appName: appName
        )
    }

    private func installModalQuitCommand() {
        guard let sheet = NSApplication.shared.windows.compactMap(\.attachedSheet).first,
              let quitItem = applicationQuitMenuItem() else {
            return
        }
        if modalQuitItem == nil {
            standardQuitTarget = quitItem.target as AnyObject?
            standardQuitAction = quitItem.action
            modalQuitItem = quitItem
        }
        quitItem.target = sheet
        quitItem.action = #selector(NSWindow.terminateHitomiBadayo(_:))
        quitItem.isEnabled = true
    }

    private func restoreStandardQuitCommandIfPossible() {
        guard !NSApplication.shared.windows.contains(where: { $0.attachedSheet != nil }),
              let quitItem = modalQuitItem else {
            return
        }
        quitItem.target = standardQuitTarget
        quitItem.action = standardQuitAction
        modalQuitItem = nil
        standardQuitTarget = nil
        standardQuitAction = nil
    }

    private func applicationQuitMenuItem() -> NSMenuItem? {
        guard let mainMenu = NSApplication.shared.mainMenu else { return nil }
        for item in mainMenu.items {
            if let quitItem = item.submenu?.items.first(where: {
                $0.keyEquivalent.lowercased() == "q" &&
                    $0.keyEquivalentModifierMask.contains(.command)
            }) {
                return quitItem
            }
        }
        return nil
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        if url.pathExtension.caseInsensitiveCompare("hdt") == .orderedSame {
            manager?.importOpenedTaskPackage(url)
        } else {
            manager?.enqueueOpenedURLs([url])
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        let taskPackages = urls.filter { $0.pathExtension.caseInsensitiveCompare("hdt") == .orderedSame }
        let queueInputs = urls.filter { $0.pathExtension.caseInsensitiveCompare("hdt") != .orderedSame }
        taskPackages.forEach { manager?.importOpenedTaskPackage($0) }
        if !queueInputs.isEmpty {
            manager?.enqueueOpenedURLs(queueInputs)
        }
    }
}

@main
struct HitomiBadayoApp: App {
    @NSApplicationDelegateAdaptor(HitomiBadayoApplicationDelegate.self) private var appDelegate
    @StateObject private var presentation: AppPresentationStore
    @StateObject private var appStatusStore: AppStatusStore
    @StateObject private var settingsStore: SettingsStore
    @StateObject private var searchStore: SearchStore
    @StateObject private var libraryStore: LibraryStore
    @StateObject private var queueStore: QueueStore
    @StateObject private var queueEditorStore: QueueEditorStore
    @StateObject private var duplicateImageStore: DuplicateImageStore
    @StateObject private var outputOperationStore: OutputOperationStore
    @StateObject private var externalToolStore: ExternalToolStore
    @StateObject private var aria2Store: Aria2Store
    @StateObject private var pythonRuntimeStore: PythonRuntimeStore
    @StateObject private var autoRecordStore: AutoRecordStore
    @StateObject private var networkStore: NetworkStore
    @StateObject private var cookieStatusStore: CookieStatusStore
    private let container: AppContainer

    init() {
        AppPaths.migrateLegacyApplicationSupportIfNeeded()
        LegacyPreferencesMigrator.migrateIfNeeded()
        HitomiBadayoApplication.install()
        let container = AppContainer()
        self.container = container
        _presentation = StateObject(wrappedValue: container.presentation)
        _appStatusStore = StateObject(wrappedValue: container.appStatusStore)
        _settingsStore = StateObject(wrappedValue: container.settingsStore)
        _searchStore = StateObject(wrappedValue: container.searchStore)
        _libraryStore = StateObject(wrappedValue: container.libraryStore)
        _queueStore = StateObject(wrappedValue: container.queueStore)
        _queueEditorStore = StateObject(
            wrappedValue: container.queueEditorStore
        )
        _duplicateImageStore = StateObject(
            wrappedValue: container.duplicateImageStore
        )
        _outputOperationStore = StateObject(
            wrappedValue: container.outputOperationStore
        )
        _externalToolStore = StateObject(
            wrappedValue: container.externalToolStore
        )
        _aria2Store = StateObject(wrappedValue: container.aria2Store)
        _pythonRuntimeStore = StateObject(
            wrappedValue: container.pythonRuntimeStore
        )
        _autoRecordStore = StateObject(
            wrappedValue: container.autoRecordStore
        )
        _networkStore = StateObject(
            wrappedValue: container.networkStore
        )
        _cookieStatusStore = StateObject(
            wrappedValue: container.cookieStatusStore
        )
        appDelegate.manager = container.manager
        appDelegate.settingsStore = container.settingsStore
        appDelegate.shortcutController = container.shortcutController
        AppMainMenuPruner.configureEditCommands(manager: container.manager)
        DispatchQueue.main.async { [container] in
            container.shortcutController.start()
        }
    }

    private var themePresentation: ThemePresentationSnapshot {
        ThemePresentationService.snapshot(
            plugins: pythonRuntimeStore.scriptPlugins,
            selectedThemeKey: settingsStore.selectedPythonThemeKey,
            appearanceMode: settingsStore.appAppearanceMode
        )
    }

    var body: some Scene {
        WindowGroup("Hitomi Badayo") {
            ContentView(
                manager: container.manager,
                queueScheduler: container.queueScheduler
            )
                .environmentObject(presentation)
                .environmentObject(presentation.settingsWindow)
                .environmentObject(appStatusStore)
                .environmentObject(settingsStore)
                .environmentObject(searchStore)
                .environmentObject(libraryStore)
                .environmentObject(queueStore)
                .environmentObject(queueEditorStore)
                .environmentObject(duplicateImageStore)
                .environmentObject(outputOperationStore)
                .environmentObject(externalToolStore)
                .environmentObject(aria2Store)
                .environmentObject(pythonRuntimeStore)
                .environmentObject(autoRecordStore)
                .environmentObject(networkStore)
                .environmentObject(cookieStatusStore)
                .environment(
                    \.appNavigationCommands,
                    container.navigationCommands
                )
                .environment(
                    \.queueControlCommands,
                    container.queueControlCommands
                )
                .environment(\.inputCommands, container.inputCommands)
                .environment(\.locale, settingsStore.interfaceLanguage.locale)
                .preferredColorScheme(themePresentation.preferredColorScheme)
                .tint(themePresentation.tintColor)
                .frame(
                    minWidth: MainWindowLayout.minimumSize.width,
                    minHeight: MainWindowLayout.minimumSize.height
                )
                .background(MainWindowFrameRestorer(
                    opacity: settingsStore.mainWindowOpacity,
                    alwaysOnTop: settingsStore.mainWindowAlwaysOnTop
                ))
        }
        .windowStyle(.titleBar)
        .defaultSize(
            width: MainWindowLayout.defaultSize.width,
            height: MainWindowLayout.defaultSize.height
        )
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button {
                    container.navigationCommands.open(.about)
                } label: {
                    Text(AppLocalization.text(
                        "About Hitomi Badayo",
                        language: settingsStore.interfaceLanguage
                    ))
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button {
                    container.navigationCommands.openSettings()
                } label: {
                    Text(AppLocalization.text(
                        "Settings...",
                        language: settingsStore.interfaceLanguage
                    ))
                }
                .keyboardShortcut(
                    settingsStore.keyboardShortcut(for: .settings)
                )
            }
        }
    }
}
#endif
