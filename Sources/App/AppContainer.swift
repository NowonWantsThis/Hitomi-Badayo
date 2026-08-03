import Foundation

@MainActor
final class AppContainer {
    let presentation: AppPresentationStore
    let appStatusStore: AppStatusStore
    let appCommandService: AppCommandService
    let settingsStore: SettingsStore
    let searchStore: SearchStore
    let libraryStore: LibraryStore
    let queueStore: QueueStore
    let queueEditorStore: QueueEditorStore
    let duplicateImageStore: DuplicateImageStore
    let outputOperationStore: OutputOperationStore
    let externalToolStore: ExternalToolStore
    let aria2Store: Aria2Store
    let pythonRuntimeStore: PythonRuntimeStore
    let autoRecordStore: AutoRecordStore
    let networkStore: NetworkStore
    let cookieStatusStore: CookieStatusStore

    let queueScheduler: QueueScheduler
    let downloadCoordinator: DownloadCoordinator
    let persistenceService: UserDataPersistenceService
    let outputService: OutputService
    let externalToolRuntime: ExternalToolRuntimeService
    let sourceResolverRegistry: SourceResolverRegistry
    let manager: DownloadManager

    let navigationCommands: AppNavigationCommands
    let queueControlCommands: QueueControlCommands
    let inputCommands: InputCommands

    let statusBarController: StatusBarController
    let floatingMonitorController: FloatingMonitorController
    let outputPreviewWindowController: OutputPreviewWindowController
    let dockTileController: DockTileController
    let shortcutController: AppShortcutController

    init() {
        let presentation = AppPresentationStore()
        let appStatusStore = AppStatusStore()
        let appCommandService = AppCommandService(
            presentation: presentation
        )
        let settingsStore = SettingsStore()
        let searchStore = SearchStore()
        let libraryStore = LibraryStore()
        let queueStore = QueueStore()
        let queueEditorStore = QueueEditorStore()
        let duplicateImageStore = DuplicateImageStore()
        let outputOperationStore = OutputOperationStore()
        let externalToolStore = ExternalToolStore()
        let aria2Store = Aria2Store()
        let pythonRuntimeStore = PythonRuntimeStore()
        let autoRecordStore = AutoRecordStore()
        let networkStore = NetworkStore()
        let cookieStatusStore = CookieStatusStore()
        let queueScheduler = QueueScheduler()
        let downloadCoordinator = DownloadCoordinator()
        let persistenceService = UserDataPersistenceService()
        let outputService = OutputService()
        let externalToolRuntime = ExternalToolRuntimeService()
        let sourceResolverRegistry = SourceResolverRegistry()
        let manager = DownloadManager(
            sourceResolverRegistry: sourceResolverRegistry,
            presentation: presentation,
            appStatusStore: appStatusStore,
            appCommandService: appCommandService,
            settingsStore: settingsStore,
            searchStore: searchStore,
            libraryStore: libraryStore,
            queueStore: queueStore,
            queueEditorStore: queueEditorStore,
            duplicateImageStore: duplicateImageStore,
            outputOperationStore: outputOperationStore,
            externalToolStore: externalToolStore,
            aria2Store: aria2Store,
            pythonRuntimeStore: pythonRuntimeStore,
            autoRecordStore: autoRecordStore,
            networkStore: networkStore,
            cookieStatusStore: cookieStatusStore,
            queueScheduler: queueScheduler,
            downloadCoordinator: downloadCoordinator,
            persistenceService: persistenceService,
            outputService: outputService,
            externalToolRuntime: externalToolRuntime
        )

        self.presentation = presentation
        self.appStatusStore = appStatusStore
        self.appCommandService = appCommandService
        self.settingsStore = settingsStore
        self.searchStore = searchStore
        self.libraryStore = libraryStore
        self.queueStore = queueStore
        self.queueEditorStore = queueEditorStore
        self.duplicateImageStore = duplicateImageStore
        self.outputOperationStore = outputOperationStore
        self.externalToolStore = externalToolStore
        self.aria2Store = aria2Store
        self.pythonRuntimeStore = pythonRuntimeStore
        self.autoRecordStore = autoRecordStore
        self.networkStore = networkStore
        self.cookieStatusStore = cookieStatusStore
        self.queueScheduler = queueScheduler
        self.downloadCoordinator = downloadCoordinator
        self.persistenceService = persistenceService
        self.outputService = outputService
        self.externalToolRuntime = externalToolRuntime
        self.sourceResolverRegistry = sourceResolverRegistry
        self.manager = manager

        navigationCommands = AppNavigationCommands(
            service: appCommandService
        )
        queueControlCommands = QueueControlCommands(manager: manager)
        inputCommands = InputCommands(manager: manager)

        statusBarController = StatusBarController(
            manager: manager,
            queueStore: queueStore,
            settingsStore: settingsStore
        )
        floatingMonitorController = FloatingMonitorController(
            manager: manager,
            presentation: presentation,
            settingsStore: settingsStore,
            queueStore: queueStore,
            appCommandService: appCommandService,
            queueControlCommands: queueControlCommands
        )
        outputPreviewWindowController = OutputPreviewWindowController(
            manager: manager,
            presentation: presentation,
            queueStore: queueStore,
            settingsStore: settingsStore,
            pythonRuntimeStore: pythonRuntimeStore
        )
        dockTileController = DockTileController(queueStore: queueStore)
        shortcutController = AppShortcutController(
            manager: manager,
            settingsStore: settingsStore,
            presentation: presentation
        )
    }
}
