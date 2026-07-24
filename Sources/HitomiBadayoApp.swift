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
                    manager?.addSummary = "Restore network settings before quitting"
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
            language: self.manager?.interfaceLanguage ?? .english
        )
        guard let menu = AppMainMenuPruner.makeStableMainMenu(
            from: NSApplication.shared.mainMenu
        ) else { return }
        AppMainMenuPruner.simplify(
            menu,
            language: self.manager?.interfaceLanguage ?? .english
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
            language: manager?.interfaceLanguage ?? .english,
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
    @StateObject private var manager: DownloadManager
    private let statusBarController: StatusBarController
    private let floatingMonitorController: FloatingMonitorController
    private let outputPreviewWindowController: OutputPreviewWindowController
    private let dockTileController: DockTileController
    private let shortcutController: AppShortcutController

    init() {
        AppPaths.migrateLegacyApplicationSupportIfNeeded()
        LegacyPreferencesMigrator.migrateIfNeeded()
        HitomiBadayoApplication.install()
        let manager = DownloadManager()
        _manager = StateObject(wrappedValue: manager)
        statusBarController = StatusBarController(manager: manager)
        floatingMonitorController = FloatingMonitorController(manager: manager)
        outputPreviewWindowController = OutputPreviewWindowController(manager: manager)
        dockTileController = DockTileController(manager: manager)
        shortcutController = AppShortcutController(manager: manager)
        appDelegate.manager = manager
        appDelegate.shortcutController = shortcutController
        DispatchQueue.main.async { [shortcutController] in
            shortcutController.start()
        }
    }

    var body: some Scene {
        WindowGroup("Hitomi Badayo") {
            ContentView()
                .environmentObject(manager)
                .environment(\.locale, manager.interfaceLanguage.locale)
                .preferredColorScheme(manager.preferredColorScheme)
                .tint(manager.activeThemeTintColor)
                .frame(
                    minWidth: MainWindowLayout.minimumSize.width,
                    minHeight: MainWindowLayout.minimumSize.height
                )
                .background(MainWindowFrameRestorer(
                    opacity: manager.mainWindowOpacity,
                    alwaysOnTop: manager.mainWindowAlwaysOnTop
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
                    manager.showingAbout = true
                } label: {
                    Text(AppLocalization.text("About Hitomi Badayo", language: manager.interfaceLanguage))
                }
            }

            CommandGroup(replacing: .appSettings) {
                Button {
                    manager.openSettingsWindow()
                } label: {
                    Text(AppLocalization.text("Settings...", language: manager.interfaceLanguage))
                }
                .keyboardShortcut(manager.keyboardShortcut(for: .settings))
            }
        }
    }
}
#endif
