import Combine
import Foundation
import SwiftUI

@MainActor
final class SettingsStore: ObservableObject {
    @Published var interfaceLanguage: AppInterfaceLanguage
    @Published var destinationPath: String
    @Published var uiScale: AppUIScale
    @Published var queueViewMode: QueueViewMode
    @Published var queueSortMode: QueueSortMode
    @Published var queueSortDescending: Bool
    @Published var queueThumbnailsHidden: Bool
    @Published var queueThumbnailScale: QueueThumbnailScale
    @Published var mainWindowOpacity: Double
    @Published var mainWindowAlwaysOnTop: Bool
    @Published var floatingMonitorOpacity: Double
    @Published var jobStatusColorPalette: JobStatusColorPalette
    @Published var statusColorOnlyWebColors: Bool
    @Published private(set) var taskTagNames: [String: String]
    @Published private(set) var taskTagRestartTimers: [String: Int]
    @Published var lowPowerMode: Bool
    @Published var showDuplicateImageThumbnails: Bool
    @Published var duplicateImageSimilarityPercent: Int
    @Published var duplicateImageExcludeSameSource: Bool
    @Published var duplicateImageFolderPaths: [String]
    @Published var interfaceFontFamily: String
    @Published var interfaceFontSize: AppInterfaceFontSize
    @Published var appAppearanceMode: AppAppearanceMode
    @Published var selectedPythonThemeKey: String
    @Published var autoRemoveFinishedJobs: Bool
    @Published var autoRemoveHookCommand: String
    @Published var launchAtLoginEnabled: Bool
    @Published var proxyEnabled: Bool
    @Published var proxyURLString: String
    @Published var proxyBypassList: String
    @Published var dpiBypassMode: DPIBypassMode
    @Published var httpAPIEnabled: Bool
    @Published var httpAPIPortString: String
    @Published var httpAPIPassword: String
    @Published var httpViewerLazyLoading: Bool
    @Published private(set) var quickAccessItems: [QuickAccessItem]
    @Published private(set) var appShortcutAssignments:
        [AppShortcutCommand: AppShortcut]
    @Published var searchDeduplicateResults: Bool
    @Published var searchHideKnownResults: Bool
    @Published var searchResultKnownFilter: SearchResultKnownFilter
    @Published var searchResultSortMode: SearchResultSortMode
    @Published var searchResultSortDescending: Bool
    @Published var hitomiExcludedTagsText: String
    @Published var jobConcurrency: Int
    @Published var fileConcurrency: Int
    @Published var preferWebP: Bool
    @Published var eHentaiSourceMode: EHentaiSourceMode
    @Published var preferOriginalEHentaiImages: Bool
    @Published var preferJapaneseEHentaiTitle: Bool
    @Published var saveHitomiGalleryInfoText: Bool
    @Published var skipDuplicates: Bool
    @Published var notifyWhenJobCompletes: Bool
    @Published var notifyWhenQueueCompletes: Bool
    @Published var playSoundWhenJobCompletes: Bool
    @Published var playSoundOnClipboardAdd: Bool
    @Published var queueCompletionAction: QueueCompletionAction
    @Published var historyEnabled: Bool
    @Published var historyLimitString: String
    @Published var clipboardMonitorEnabled: Bool
    @Published var startDownloadsOnPaste: Bool
    @Published var showDownloadDate: Bool
    @Published var numberPlaylistFiles: Bool
    @Published var imageConversionFormat: ImageConversionFormat
    @Published var outputSubfolderMode: OutputSubfolderMode
    @Published var selectedSourceFolderID: String
    @Published var sourceFolderNames: [String: String]
    @Published var folderNameTemplate: String
    @Published var fileNameTemplate: String
    @Published var sourceFileNameTemplates: [String: String]
    @Published var recordingFileNameTemplate: String
    @Published var archiveCompletedFolders: Bool
    @Published var archiveFileFormat: ArchiveFileFormat
    @Published var deleteOriginalFolderAfterArchiving: Bool
    @Published var hideArchiveIndicatorWhenFileMissing: Bool
    @Published var sourceArchiveModes: [String: SourceArchiveMode]
    @Published var sourceArchiveDeleteOriginal: [String: Bool]
    @Published var retryIncompleteAutomatically: Bool
    @Published var incompleteRetryDelay: IncompleteRetryDelay
    @Published var preventSleepWhileDownloading: Bool
    @Published var pixivUgoiraFileFormat: PixivUgoiraFileFormat
    @Published var pixivUgoiraDither: Bool
    @Published var pixivUgoiraQuality: Int
    @Published var pawchiveSiteAddresses: [String]
    @Published var pawchiveDownloadLargeOriginalFiles: Bool
    @Published var pawchiveDownloadImages: Bool
    @Published var pawchiveDownloadVideos: Bool
    @Published var pawchiveDownloadHTML: Bool
    @Published var pawchiveDownloadOtherFiles: Bool
    @Published var remuxM3U8ToMP4: Bool
    @Published var hlsContinueOnSegmentFailure: Bool
    @Published var m3u8SegmentDelayMillisecondsString: String
    @Published var youtubePreferredLanguage: String
    @Published var youtubeDownloadThumbnail: Bool
    @Published var youtubeReversePlaylist: Bool
    @Published var youtubeUseUploadDateForFileModificationTime: Bool
    @Published var youtubeDownloadAutoSubtitles: Bool
    @Published var youtubeSubtitleLanguages: String
    @Published var youtubeEmbedChapters: Bool
    @Published var youtubeVideoCodecPriority: [YouTubeVideoCodec]
    @Published var youtubeVideoCodecSort: String
    @Published var youtubePreferEnhancedBitrate: Bool
    @Published var youtubePreferredResolution: String
    @Published var youtubePreferredAudioLanguage: String
    @Published var instagramIncludeStories: Bool
    @Published var soopPreferredResolution: String

    private let defaults: UserDefaults
    private let outputSettingsService: OutputSettingsService
    private(set) var interfaceFontService: InterfaceFontService

    init(
        defaults: UserDefaults = .standard,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        interfaceFontService: InterfaceFontService? = nil
    ) {
        self.defaults = defaults
        let interfaceFonts =
            interfaceFontService ??
            InterfaceFontService()
        self.interfaceFontService = interfaceFonts
        let requestedInterfaceLanguage =
            environment["HITOMI_NATIVE_INTERFACE_LANGUAGE"]
            ?? defaults.string(forKey: AppInterfaceLanguage.defaultsKey)
        let selectedInterfaceLanguage = AppInterfaceLanguage.normalized(
            requestedInterfaceLanguage
        )
        interfaceLanguage = selectedInterfaceLanguage
        defaults.set(
            selectedInterfaceLanguage.rawValue,
            forKey: AppInterfaceLanguage.defaultsKey
        )

        let environmentDestinationPath = (
            environment["HITOMI_BADAYO_DESTINATION_PATH"] ??
                environment["HITOMI_NATIVE_DESTINATION_PATH"]
        )?.trimmed ?? ""
        let savedDestinationPath = defaults.string(forKey: "destinationPath") ?? ""
        let usableSavedDestinationPath = Self.isTransientTestDestinationPath(
            savedDestinationPath
        ) ? "" : savedDestinationPath
        if environmentDestinationPath.isEmpty,
           !savedDestinationPath.isEmpty,
           usableSavedDestinationPath.isEmpty {
            defaults.removeObject(forKey: "destinationPath")
        }
        destinationPath = environmentDestinationPath.isEmpty
            ? (
                usableSavedDestinationPath.isEmpty
                    ? AppPaths.defaultDownloadDirectory.path
                    : usableSavedDestinationPath
            )
            : environmentDestinationPath

        uiScale = AppUIScale.normalized(
            rawValue: defaults.string(forKey: "uiScale")
        )
        queueViewMode = QueueViewMode(
            rawValue: defaults.string(forKey: "queueViewMode") ?? ""
        ) ?? .list
        queueSortMode = QueueSortMode(
            rawValue: defaults.string(forKey: "queueSortMode") ?? ""
        ) ?? .manual
        queueSortDescending =
            defaults.object(forKey: "queueSortDescending") as? Bool ?? false
        queueThumbnailsHidden =
            defaults.object(forKey: "queueThumbnailsHidden") as? Bool ?? false
        queueThumbnailScale = QueueThumbnailScale.normalized(
            index: defaults.object(forKey: "queueThumbnailScaleIndex") as? Int
                ?? QueueThumbnailScale.defaultScale.rawValue
        )
        mainWindowOpacity = MainWindowAppearance.normalizedOpacity(
            defaults.object(forKey: "mainWindowOpacity") as? Double
                ?? MainWindowAppearance.defaultOpacity
        )
        mainWindowAlwaysOnTop =
            defaults.object(forKey: "mainWindowAlwaysOnTop") as? Bool ?? false
        floatingMonitorOpacity = Self.normalizedFloatingMonitorOpacity(
            defaults.object(forKey: "floatingMonitorOpacity") as? Double ?? 0.92
        )
        jobStatusColorPalette = Self.loadJobStatusColorPalette(
            defaults: defaults
        )
        statusColorOnlyWebColors =
            defaults.object(forKey: "jobStatusColorOnlyWebColors") as? Bool
            ?? false
        taskTagNames = Self.loadTaskTagNames(defaults: defaults)
        taskTagRestartTimers = Self.loadTaskTagRestartTimers(
            defaults: defaults
        )
        lowPowerMode = defaults.object(forKey: "lowPowerMode") as? Bool ?? false
        showDuplicateImageThumbnails =
            defaults.object(forKey: "showDuplicateImageThumbnails") as? Bool ?? true
        let duplicateImageScanService = DuplicateImageScanService()
        duplicateImageSimilarityPercent = duplicateImageScanService
            .normalizedSimilarityPercent(
                defaults.object(forKey: "duplicateImageSimilarityPercent") as? Int ?? 100
            )
        duplicateImageExcludeSameSource =
            defaults.object(forKey: "duplicateImageExcludeSameSource") as? Bool ?? false
        duplicateImageFolderPaths = duplicateImageScanService.normalizedFolderPaths(
            defaults.stringArray(forKey: "duplicateImageFolderPaths") ?? []
        )
        interfaceFontFamily = interfaceFonts.normalizedFamily(
            defaults.string(forKey: "interfaceFontFamily") ?? ""
        )
        interfaceFontSize = AppInterfaceFontSize.normalized(
            rawValue: defaults.string(forKey: "interfaceFontSize")
        )
        appAppearanceMode = AppAppearanceMode(
            rawValue: defaults.string(forKey: "appAppearanceMode") ?? ""
        ) ?? .system
        selectedPythonThemeKey = defaults
            .string(forKey: "selectedPythonThemeKey")?
            .trimmed
            .lowercased() ?? ""
        autoRemoveFinishedJobs =
            defaults.object(forKey: "autoRemoveFinishedJobs") as? Bool ?? false
        autoRemoveHookCommand =
            defaults.string(forKey: "autoRemoveHookCommand") ?? ""
        launchAtLoginEnabled = LaunchAtLoginSettings.load(
            defaults: defaults
        )
        let manualNetworkSettings = NetworkSettings.loadManual(
            defaults: defaults
        )
        proxyEnabled = manualNetworkSettings.proxyEnabled
        proxyURLString = manualNetworkSettings.proxyURLString
        proxyBypassList = manualNetworkSettings.proxyBypassList
        dpiBypassMode = DPIBypassMode.load(
            defaults: defaults,
            environment: environment
        )
        httpAPIEnabled = Self.environmentBool(
            "HITOMI_NATIVE_HTTP_API_ENABLED",
            environment: environment
        ) ?? (defaults.object(forKey: "httpAPIEnabled") as? Bool ?? false)
        httpAPIPortString = Self.environmentPort(
            "HITOMI_NATIVE_HTTP_API_PORT",
            environment: environment
        ) ?? defaults.string(forKey: "httpAPIPortString") ?? "8110"
        httpAPIPassword = defaults.string(forKey: "httpAPIPassword") ?? ""
        httpViewerLazyLoading =
            defaults.object(forKey: "httpViewerLazyLoading") as? Bool ?? true
        quickAccessItems = QuickAccessConfiguration.load(defaults: defaults)
        appShortcutAssignments = Self.loadAppShortcutAssignments(
            defaults: defaults
        )
        searchDeduplicateResults =
            defaults.object(forKey: "searchDeduplicateResults") as? Bool
            ?? true
        searchHideKnownResults =
            defaults.object(forKey: "searchHideKnownResults") as? Bool
            ?? false
        searchResultKnownFilter = SearchResultKnownFilter(
            rawValue: defaults.string(forKey: "searchResultKnownFilter") ?? ""
        ) ?? .all
        searchResultSortMode = SearchResultSortMode(
            rawValue: defaults.string(forKey: "searchResultSortMode") ?? ""
        ) ?? .manual
        searchResultSortDescending =
            defaults.object(forKey: "searchResultSortDescending") as? Bool
            ?? false
        hitomiExcludedTagsText =
            defaults.string(forKey: "hitomiExcludedTagsText") ?? ""

        let outputSettingsService = OutputSettingsService(defaults: defaults)
        self.outputSettingsService = outputSettingsService
        let outputSettings = outputSettingsService.load()
        outputSubfolderMode = outputSettings.outputSubfolderMode
        selectedSourceFolderID = outputSettings.selectedSourceFolderID
        sourceFolderNames = outputSettings.sourceFolderNames
        folderNameTemplate = outputSettings.folderNameTemplate
        fileNameTemplate = outputSettings.fileNameTemplate
        sourceFileNameTemplates = outputSettings.sourceFileNameTemplates
        recordingFileNameTemplate = outputSettings.recordingFileNameTemplate
        archiveCompletedFolders = outputSettings.archiveCompletedFolders
        archiveFileFormat = outputSettings.archiveFileFormat
        deleteOriginalFolderAfterArchiving =
            outputSettings.deleteOriginalFolderAfterArchiving
        hideArchiveIndicatorWhenFileMissing =
            outputSettings.hideArchiveIndicatorWhenFileMissing
        sourceArchiveModes = outputSettings.sourceArchiveModes
        sourceArchiveDeleteOriginal =
            outputSettings.sourceArchiveDeleteOriginal

        let savedJobConcurrency = defaults.integer(forKey: "jobConcurrency")
        jobConcurrency = QueueScheduler.normalizedTaskLimit(
            savedJobConcurrency > 0 ? savedJobConcurrency : 4
        )

        let savedFileConcurrency = defaults.integer(forKey: "concurrency")
        fileConcurrency = savedFileConcurrency > 0 ? max(1, savedFileConcurrency) : 4

        preferWebP = defaults.object(forKey: "preferWebP") as? Bool ?? true
        eHentaiSourceMode = EHentaiSourceMode(
            rawValue: defaults.string(forKey: "eHentaiSourceMode") ?? ""
        ) ?? .automatic
        preferOriginalEHentaiImages =
            defaults.object(forKey: "preferOriginalEHentaiImages") as? Bool ?? false
        preferJapaneseEHentaiTitle =
            defaults.object(forKey: "preferJapaneseEHentaiTitle") as? Bool
            ?? defaults.object(forKey: "ehenJapanese") as? Bool
            ?? false
        saveHitomiGalleryInfoText =
            defaults.object(forKey: "saveHitomiGalleryInfoText") as? Bool ?? false
        skipDuplicates = defaults.object(forKey: "skipDuplicates") as? Bool ?? true
        notifyWhenJobCompletes =
            defaults.object(forKey: "notifyWhenJobCompletes") as? Bool ?? false
        notifyWhenQueueCompletes =
            defaults.object(forKey: "notifyWhenQueueCompletes") as? Bool ?? false
        playSoundWhenJobCompletes =
            defaults.object(forKey: "playSoundWhenJobCompletes") as? Bool ?? false
        playSoundOnClipboardAdd =
            defaults.object(forKey: "playSoundOnClipboardAdd") as? Bool ?? false
        queueCompletionAction = QueueCompletionAction(
            rawValue: defaults.string(forKey: "queueCompletionAction") ?? ""
        ) ?? .none
        historyEnabled = defaults.object(forKey: "historyEnabled") as? Bool ?? true
        let savedHistoryLimit = defaults.integer(forKey: "historyLimit")
        historyLimitString = String(savedHistoryLimit > 0 ? savedHistoryLimit : 1_000)
        clipboardMonitorEnabled =
            defaults.object(forKey: "clipboardMonitorEnabled") as? Bool ?? false
        startDownloadsOnPaste =
            defaults.object(forKey: "startDownloadsOnPaste") as? Bool ?? true
        showDownloadDate =
            defaults.object(forKey: "showDownloadDate") as? Bool ?? false
        numberPlaylistFiles =
            defaults.object(forKey: "numberPlaylistFiles") as? Bool ?? false
        imageConversionFormat = ImageConversionFormat(
            rawValue: defaults.string(forKey: "imageConversionFormat") ?? ""
        ) ?? .original
        retryIncompleteAutomatically =
            defaults.object(forKey: "retryIncompleteAutomatically") as? Bool
            ?? defaults.object(forKey: "incomplete") as? Bool
            ?? false
        if let savedMinutes = defaults.object(forKey: "incompleteRetryDelayMinutes") as? Int {
            incompleteRetryDelay = IncompleteRetryDelay.normalized(minutes: savedMinutes)
        } else {
            incompleteRetryDelay = IncompleteRetryDelay.normalized(
                originalIndex: defaults.object(forKey: "incompleteTime") as? Int ?? 0
            )
        }
        preventSleepWhileDownloading =
            defaults.object(forKey: "preventSleepWhileDownloading") as? Bool ?? false
        pixivUgoiraFileFormat = PixivUgoiraFileFormat(
            rawValue: defaults.string(forKey: "pixivUgoiraFileFormat") ?? ""
        ) ?? .ugoira
        pixivUgoiraDither =
            defaults.object(forKey: "pixivUgoiraDither") as? Bool ?? true
        pixivUgoiraQuality = min(
            max(1, defaults.object(forKey: "pixivUgoiraQuality") as? Int ?? 90),
            100
        )
        if defaults.object(forKey: "pawchiveSiteAddresses") != nil {
            pawchiveSiteAddresses = PawchiveResolver.normalizedSiteAddresses(
                defaults.stringArray(forKey: "pawchiveSiteAddresses") ?? []
            )
        } else {
            pawchiveSiteAddresses = PawchiveResolver.defaultSiteAddresses
        }
        pawchiveDownloadLargeOriginalFiles =
            defaults.object(forKey: "pawchiveDownloadLargeOriginalFiles") as? Bool ?? false
        pawchiveDownloadImages =
            defaults.object(forKey: "pawchiveDownloadImages") as? Bool ?? true
        pawchiveDownloadVideos =
            defaults.object(forKey: "pawchiveDownloadVideos") as? Bool ?? true
        pawchiveDownloadHTML =
            defaults.object(forKey: "pawchiveDownloadHTML") as? Bool ?? true
        pawchiveDownloadOtherFiles =
            defaults.object(forKey: "pawchiveDownloadOtherFiles") as? Bool ?? true
        remuxM3U8ToMP4 =
            defaults.object(forKey: "remuxM3U8ToMP4") as? Bool ?? false
        hlsContinueOnSegmentFailure =
            defaults.object(forKey: "hlsContinueOnSegmentFailure") as? Bool ?? false
        let savedM3U8Delay =
            defaults.object(forKey: "m3u8SegmentDelayMilliseconds") as? Int ?? 0
        m3u8SegmentDelayMillisecondsString = savedM3U8Delay > 0
            ? String(Self.normalizedM3U8SegmentDelayMilliseconds(from: String(savedM3U8Delay)))
            : ""
        youtubePreferredLanguage =
            defaults.string(forKey: "youtubePreferredLanguage") ?? ""
        youtubeDownloadThumbnail =
            defaults.object(forKey: "youtubeDownloadThumbnail") as? Bool ?? false
        youtubeReversePlaylist =
            defaults.object(forKey: "youtubeReversePlaylist") as? Bool ?? false
        youtubeUseUploadDateForFileModificationTime =
            defaults.object(forKey: "youtubeUseUploadDateForFileModificationTime") as? Bool
            ?? true
        youtubeDownloadAutoSubtitles =
            defaults.object(forKey: "youtubeDownloadAutoSubtitles") as? Bool ?? false
        youtubeSubtitleLanguages =
            defaults.string(forKey: "youtubeSubtitleLanguages") ?? ""
        youtubeEmbedChapters =
            defaults.object(forKey: "youtubeEmbedChapters") as? Bool ?? false
        let storedCodecPriority =
            defaults.object(forKey: "youtubeVideoCodecPriority")
            ?? defaults.object(forKey: "CODECS_PRI")
        let loadedYouTubeVideoCodecPriority = YouTubeVideoCodec.priority(
            fromStoredValue: storedCodecPriority,
            legacySort: defaults.string(forKey: "youtubeVideoCodecSort") ?? ""
        )
        youtubeVideoCodecPriority = loadedYouTubeVideoCodecPriority
        youtubeVideoCodecSort = YouTubeVideoCodec.ytdlpSortExpression(
            for: loadedYouTubeVideoCodecPriority
        )
        youtubePreferEnhancedBitrate =
            defaults.object(forKey: "youtubePreferEnhancedBitrate") as? Bool ?? false
        youtubePreferredResolution =
            defaults.string(forKey: "youtubePreferredResolution") ?? ""
        youtubePreferredAudioLanguage =
            defaults.string(forKey: "youtubePreferredAudioLanguage") ?? ""
        instagramIncludeStories =
            defaults.object(forKey: "instagramIncludeStories") as? Bool ?? false
        soopPreferredResolution =
            defaults.string(forKey: "soopPreferredResolution") ?? ""
    }

    func persistDownloadBehavior() {
        defaults.set(
            QueueScheduler.normalizedTaskLimit(jobConcurrency),
            forKey: "jobConcurrency"
        )
        defaults.set(fileConcurrency, forKey: "concurrency")
        persistPreferWebP()
        persistEHentaiSourceMode()
        persistPreferOriginalEHentaiImages()
        persistPreferJapaneseEHentaiTitle()
        persistSaveHitomiGalleryInfoText()
        persistSkipDuplicates()
        persistCompletionAlerts()
    }

    func persistInterfaceLanguage() {
        defaults.set(
            interfaceLanguage.rawValue,
            forKey: AppInterfaceLanguage.defaultsKey
        )
    }

    func persistDestinationPath() {
        defaults.set(destinationPath, forKey: "destinationPath")
    }

    func persistQueuePresentation() {
        defaults.set(uiScale.rawValue, forKey: "uiScale")
        defaults.set(queueViewMode.rawValue, forKey: "queueViewMode")
        defaults.set(queueSortMode.rawValue, forKey: "queueSortMode")
        defaults.set(queueSortDescending, forKey: "queueSortDescending")
        defaults.set(queueThumbnailsHidden, forKey: "queueThumbnailsHidden")
        defaults.set(
            queueThumbnailScale.rawValue,
            forKey: "queueThumbnailScaleIndex"
        )
    }

    func persistWindowAppearance() {
        defaults.set(mainWindowOpacity, forKey: "mainWindowOpacity")
        defaults.set(mainWindowAlwaysOnTop, forKey: "mainWindowAlwaysOnTop")
        defaults.set(floatingMonitorOpacity, forKey: "floatingMonitorOpacity")
    }

    func persistJobStatusColorSettings() {
        jobStatusColorPalette = jobStatusColorPalette.normalized(
            onlyWebColors: statusColorOnlyWebColors
        )
        if let data = try? JSONEncoder().encode(jobStatusColorPalette) {
            defaults.set(data, forKey: "jobStatusColorPalette")
        }
        defaults.set(
            statusColorOnlyWebColors,
            forKey: "jobStatusColorOnlyWebColors"
        )
    }

    func taskTagDisplayName(_ tag: TaskTagColor) -> String {
        let custom = taskTagNames[tag.rawValue]?.trimmed ?? ""
        return custom.isEmpty ? tag.label : custom
    }

    func setTaskTagName(_ name: String, for tag: TaskTagColor) {
        taskTagNames[tag.rawValue] = String(name.trimmed.prefix(80))
        persistTaskTagNames()
    }

    func resetTaskTagNames() {
        taskTagNames = Dictionary(
            uniqueKeysWithValues: TaskTagColor.allCases.map {
                ($0.rawValue, $0.label)
            }
        )
        persistTaskTagNames()
    }

    func taskTagRestartDelay(
        for tag: TaskTagColor
    ) -> TaskTagRestartDelay? {
        TaskTagRestartDelay(
            rawValue: taskTagRestartTimers[tag.rawValue] ?? 0
        )
    }

    func taskTagRestartTimerDescription(
        for tag: TaskTagColor
    ) -> String {
        let seconds = taskTagRestartTimers[tag.rawValue] ?? 0
        if let delay = TaskTagRestartDelay(rawValue: seconds) {
            return delay.label
        }
        guard seconds > 0 else { return TaskTagRestartDelay.off.label }
        return "Restart after \(Self.restartDelayDescription(seconds))"
    }

    func setTaskTagRestartDelay(
        _ delay: TaskTagRestartDelay,
        for tag: TaskTagColor
    ) {
        taskTagRestartTimers[tag.rawValue] = delay.rawValue
        persistTaskTagRestartTimers()
    }

    private func persistTaskTagNames() {
        let custom: [String: String] = Dictionary(
            uniqueKeysWithValues: TaskTagColor.allCases.compactMap { tag in
                guard let value = taskTagNames[tag.rawValue]?.trimmed,
                      !value.isEmpty,
                      value != tag.label else {
                    return nil
                }
                return (tag.rawValue, String(value.prefix(80)))
            }
        )
        defaults.set(custom, forKey: "taskTagNames")
    }

    private func persistTaskTagRestartTimers() {
        let timers = Dictionary(
            uniqueKeysWithValues: TaskTagColor.allCases.map { tag in
                (
                    tag.rawValue,
                    max(0, taskTagRestartTimers[tag.rawValue] ?? 0)
                )
            }
        )
        taskTagRestartTimers = timers
        defaults.set(timers, forKey: "taskTagRestartTimers")
        if let data = try? JSONEncoder().encode(timers),
           let json = String(data: data, encoding: .utf8) {
            defaults.set(json, forKey: "tag_timer")
        }
    }

    func persistDisplaySettings() {
        persistQueuePresentation()
        persistWindowAppearance()
        persistJobStatusColorSettings()
        persistDuplicateImageSettings()
        persistInterfaceFont()
        persistAppAppearance()
    }

    var mainWindowOpacityPercentText: String {
        "\(Int((mainWindowOpacity * 100).rounded()))%"
    }

    var floatingMonitorOpacityPercentText: String {
        "\(Int((floatingMonitorOpacity * 100).rounded()))%"
    }

    func persistDuplicateImageSettings() {
        defaults.set(lowPowerMode, forKey: "lowPowerMode")
        defaults.set(
            showDuplicateImageThumbnails,
            forKey: "showDuplicateImageThumbnails"
        )
        defaults.set(
            duplicateImageSimilarityPercent,
            forKey: "duplicateImageSimilarityPercent"
        )
        defaults.set(
            duplicateImageExcludeSameSource,
            forKey: "duplicateImageExcludeSameSource"
        )
        defaults.set(
            duplicateImageFolderPaths,
            forKey: "duplicateImageFolderPaths"
        )
    }

    var duplicateImageScanFolderSummary: String {
        if duplicateImageFolderPaths.isEmpty {
            return "Save folder"
        }
        if duplicateImageFolderPaths.count == 1 {
            return URL(
                fileURLWithPath: duplicateImageFolderPaths[0]
            ).lastPathComponent
        }
        return "\(duplicateImageFolderPaths.count) folders"
    }

    var effectiveDuplicateImageThumbnails: Bool {
        showDuplicateImageThumbnails && !lowPowerMode
    }

    func configureInterfaceFontService(_ service: InterfaceFontService) {
        interfaceFontService = service
        interfaceFontFamily = service.normalizedFamily(interfaceFontFamily)
    }

    func persistInterfaceFont() {
        defaults.set(interfaceFontFamily, forKey: "interfaceFontFamily")
        defaults.set(interfaceFontSize.rawValue, forKey: "interfaceFontSize")
    }

    var interfaceFont: Font? {
        let family = interfaceFontService.normalizedFamily(
            interfaceFontFamily
        )
        let pointSize = CGFloat(interfaceFontSize.pointSize)
        if family.isEmpty {
            return interfaceFontSize == .defaultSize
                ? nil
                : .system(size: pointSize)
        }
        return .custom(family, size: pointSize)
    }

    var interfaceFontSummary: String {
        let family = interfaceFontService.normalizedFamily(
            interfaceFontFamily
        )
        let displayFamily = family.isEmpty
            ? AppLocalization.text("System", language: interfaceLanguage)
            : family
        return "\(displayFamily) / \(interfaceFontSize.label)"
    }

    var interfaceFontFamilyOptions: [String] {
        interfaceFontService.familyOptions()
    }

    func persistAppAppearance() {
        defaults.set(appAppearanceMode.rawValue, forKey: "appAppearanceMode")
    }

    func persistSelectedPythonThemeKey() {
        selectedPythonThemeKey = selectedPythonThemeKey
            .trimmed
            .lowercased()
        if selectedPythonThemeKey.isEmpty {
            defaults.removeObject(forKey: "selectedPythonThemeKey")
        } else {
            defaults.set(
                selectedPythonThemeKey,
                forKey: "selectedPythonThemeKey"
            )
        }
    }

    func persistAutoRemoveSettings() {
        defaults.set(
            autoRemoveFinishedJobs,
            forKey: "autoRemoveFinishedJobs"
        )
        autoRemoveHookCommand = autoRemoveHookCommand.trimmed
        defaults.set(
            autoRemoveHookCommand,
            forKey: "autoRemoveHookCommand"
        )
    }

    func persistLaunchAtLogin() {
        defaults.set(
            launchAtLoginEnabled,
            forKey: LaunchAtLoginSettings.enabledKey
        )
    }

    func persistManualNetworkSettings() {
        NetworkSettings(
            proxyEnabled: proxyEnabled,
            proxyURLString: proxyURLString,
            proxyBypassList: proxyBypassList
        ).save(defaults: defaults)
    }

    func persistDPIBypassMode() {
        dpiBypassMode.save(defaults: defaults)
    }

    func persistHTTPAPISettings() {
        httpAPIPortString = httpAPIPortString.trimmed.isEmpty
            ? "8110"
            : httpAPIPortString.trimmed
        httpAPIPassword = httpAPIPassword.trimmed
        defaults.set(httpAPIEnabled, forKey: "httpAPIEnabled")
        defaults.set(httpAPIPortString, forKey: "httpAPIPortString")
        defaults.set(httpAPIPassword, forKey: "httpAPIPassword")
        defaults.set(httpViewerLazyLoading, forKey: "httpViewerLazyLoading")
    }

    var enabledQuickAccessItems: [QuickAccessItem] {
        quickAccessItems.filter(\.isEnabled)
    }

    var areAllQuickAccessCommandsEnabled: Bool {
        !quickAccessItems.isEmpty &&
            quickAccessItems.allSatisfy(\.isEnabled)
    }

    func setQuickAccessCommand(
        _ command: QuickAccessCommand,
        enabled: Bool
    ) {
        guard let index = quickAccessItems.firstIndex(where: {
            $0.command == command
        }),
        quickAccessItems[index].isEnabled != enabled else {
            return
        }
        quickAccessItems[index].isEnabled = enabled
        persistQuickAccessItems()
    }

    func toggleAllQuickAccessCommands() {
        let enabled = !areAllQuickAccessCommandsEnabled
        quickAccessItems = quickAccessItems.map {
            QuickAccessItem(command: $0.command, isEnabled: enabled)
        }
        persistQuickAccessItems()
    }

    func moveQuickAccessCommand(
        _ command: QuickAccessCommand,
        relativeTo target: QuickAccessCommand
    ) {
        guard command != target,
              let sourceIndex = quickAccessItems.firstIndex(where: {
                  $0.command == command
              }),
              let targetIndex = quickAccessItems.firstIndex(where: {
                  $0.command == target
              }) else {
            return
        }
        let item = quickAccessItems.remove(at: sourceIndex)
        quickAccessItems.insert(
            item,
            at: min(targetIndex, quickAccessItems.count)
        )
        persistQuickAccessItems()
    }

    func persistQuickAccessItems() {
        QuickAccessConfiguration.save(
            quickAccessItems,
            defaults: defaults
        )
    }

    var activeAppShortcutCount: Int {
        AppShortcutCommand.allCases.filter {
            shortcut(for: $0).isActive
        }.count
    }

    var appShortcutSummary: String {
        AppLocalization.format(
            "%@ active shortcuts",
            language: interfaceLanguage,
            String(activeAppShortcutCount)
        )
    }

    func shortcut(for command: AppShortcutCommand) -> AppShortcut {
        (
            appShortcutAssignments[command] ?? command.defaultShortcut
        ).normalized()
    }

    func keyboardShortcut(
        for command: AppShortcutCommand
    ) -> KeyboardShortcut? {
        shortcut(for: command).keyboardShortcut
    }

    func shortcutDisplay(for command: AppShortcutCommand) -> String {
        shortcut(for: command).displayText
    }

    func shortcutConflict(
        for command: AppShortcutCommand,
        shortcut: AppShortcut
    ) -> AppShortcutCommand? {
        let normalized = shortcut.normalized()
        guard normalized.isActive else { return nil }
        return AppShortcutCommand.allCases.first { candidate in
            candidate != command &&
                self.shortcut(for: candidate) == normalized
        }
    }

    func setAppShortcut(
        _ shortcut: AppShortcut,
        for command: AppShortcutCommand
    ) {
        appShortcutAssignments[command] = shortcut.normalized()
        persistAppShortcutAssignments()
    }

    func resetAppShortcuts() {
        appShortcutAssignments = Self.defaultAppShortcutAssignments()
        persistAppShortcutAssignments()
    }

    func persistSearchResultPreferences() {
        defaults.set(
            searchDeduplicateResults,
            forKey: "searchDeduplicateResults"
        )
        defaults.set(
            searchHideKnownResults,
            forKey: "searchHideKnownResults"
        )
        defaults.set(
            searchResultKnownFilter.rawValue,
            forKey: "searchResultKnownFilter"
        )
        defaults.set(
            searchResultSortMode.rawValue,
            forKey: "searchResultSortMode"
        )
        defaults.set(
            searchResultSortDescending,
            forKey: "searchResultSortDescending"
        )
    }

    func persistHitomiExcludedTags() {
        defaults.set(
            hitomiExcludedTagsText,
            forKey: "hitomiExcludedTagsText"
        )
    }

    func persistPreferWebP() {
        defaults.set(preferWebP, forKey: "preferWebP")
    }

    func persistEHentaiSourceMode() {
        defaults.set(eHentaiSourceMode.rawValue, forKey: "eHentaiSourceMode")
    }

    func persistPreferOriginalEHentaiImages() {
        defaults.set(
            preferOriginalEHentaiImages,
            forKey: "preferOriginalEHentaiImages"
        )
    }

    func persistPreferJapaneseEHentaiTitle() {
        defaults.set(
            preferJapaneseEHentaiTitle,
            forKey: "preferJapaneseEHentaiTitle"
        )
        defaults.set(preferJapaneseEHentaiTitle, forKey: "ehenJapanese")
    }

    func persistSaveHitomiGalleryInfoText() {
        defaults.set(
            saveHitomiGalleryInfoText,
            forKey: "saveHitomiGalleryInfoText"
        )
    }

    func persistSkipDuplicates() {
        defaults.set(skipDuplicates, forKey: "skipDuplicates")
    }

    func persistCompletionAlerts() {
        defaults.set(notifyWhenJobCompletes, forKey: "notifyWhenJobCompletes")
        defaults.set(notifyWhenQueueCompletes, forKey: "notifyWhenQueueCompletes")
        defaults.set(playSoundWhenJobCompletes, forKey: "playSoundWhenJobCompletes")
        defaults.set(playSoundOnClipboardAdd, forKey: "playSoundOnClipboardAdd")
        defaults.set(queueCompletionAction.rawValue, forKey: "queueCompletionAction")
    }

    var historyLimit: Int {
        Self.normalizedHistoryLimit(from: historyLimitString)
    }

    func persistHistory() {
        historyLimitString = String(historyLimit)
        defaults.set(historyEnabled, forKey: "historyEnabled")
        defaults.set(historyLimit, forKey: "historyLimit")
    }

    func persistClipboardAutomation() {
        defaults.set(clipboardMonitorEnabled, forKey: "clipboardMonitorEnabled")
        defaults.set(startDownloadsOnPaste, forKey: "startDownloadsOnPaste")
    }

    func persistOutputPresentation() {
        defaults.set(showDownloadDate, forKey: "showDownloadDate")
        defaults.set(numberPlaylistFiles, forKey: "numberPlaylistFiles")
        defaults.set(imageConversionFormat.rawValue, forKey: "imageConversionFormat")
    }

    func persistOutputSubfolderMode() {
        outputSettingsService.persistOutputSubfolderMode(outputSubfolderMode)
    }

    func persistSelectedSourceFolderID() {
        outputSettingsService.persistSelectedSourceFolderID(
            selectedSourceFolderID
        )
    }

    func persistSourceFolderNames() {
        outputSettingsService.persistSourceFolderNames(sourceFolderNames)
    }

    func persistFolderNameTemplate(trimmed: Bool = false) {
        outputSettingsService.persistFolderNameTemplate(
            trimmed ? folderNameTemplate.trimmed : folderNameTemplate
        )
    }

    func persistFileNameTemplate(trimmed: Bool = false) {
        outputSettingsService.persistFileNameTemplate(
            trimmed ? fileNameTemplate.trimmed : fileNameTemplate
        )
    }

    func persistSourceFileNameTemplates() {
        outputSettingsService.persistSourceFileNameTemplates(
            sourceFileNameTemplates
        )
    }

    func persistRecordingFileNameTemplate(trimmed: Bool = false) {
        outputSettingsService.persistRecordingFileNameTemplate(
            trimmed
                ? recordingFileNameTemplate.trimmed
                : recordingFileNameTemplate
        )
    }

    func persistArchiveSettings() {
        outputSettingsService.persistArchiveSettings(
            archiveCompletedFolders: archiveCompletedFolders,
            archiveFileFormat: archiveFileFormat,
            deleteOriginalFolderAfterArchiving:
                deleteOriginalFolderAfterArchiving,
            hideArchiveIndicatorWhenFileMissing:
                hideArchiveIndicatorWhenFileMissing
        )
    }

    func persistSourceArchiveSettings() {
        outputSettingsService.persistSourceArchiveSettings(
            modes: sourceArchiveModes,
            deleteOriginal: sourceArchiveDeleteOriginal
        )
    }

    func persistOutputSettingsSnapshot() {
        persistOutputSubfolderMode()
        persistSelectedSourceFolderID()
        persistSourceFolderNames()
        persistFolderNameTemplate(trimmed: true)
        persistFileNameTemplate(trimmed: true)
        persistSourceFileNameTemplates()
        persistRecordingFileNameTemplate(trimmed: true)
        persistArchiveSettings()
    }

    func persistIncompleteRetry() {
        let originalIndex =
            IncompleteRetryDelay.allCases.firstIndex(of: incompleteRetryDelay) ?? 0
        defaults.set(
            retryIncompleteAutomatically,
            forKey: "retryIncompleteAutomatically"
        )
        defaults.set(retryIncompleteAutomatically, forKey: "incomplete")
        defaults.set(
            incompleteRetryDelay.rawValue,
            forKey: "incompleteRetryDelayMinutes"
        )
        defaults.set(originalIndex, forKey: "incompleteTime")
    }

    func persistSleepPrevention() {
        defaults.set(
            preventSleepWhileDownloading,
            forKey: "preventSleepWhileDownloading"
        )
    }

    func persistPixivUgoira() {
        pixivUgoiraQuality = min(max(1, pixivUgoiraQuality), 100)
        defaults.set(pixivUgoiraFileFormat.rawValue, forKey: "pixivUgoiraFileFormat")
        defaults.set(pixivUgoiraDither, forKey: "pixivUgoiraDither")
        defaults.set(pixivUgoiraQuality, forKey: "pixivUgoiraQuality")
    }

    func persistPawchive() {
        pawchiveSiteAddresses = PawchiveResolver.normalizedSiteAddresses(
            pawchiveSiteAddresses
        )
        defaults.set(pawchiveSiteAddresses, forKey: "pawchiveSiteAddresses")
        defaults.set(
            pawchiveDownloadLargeOriginalFiles,
            forKey: "pawchiveDownloadLargeOriginalFiles"
        )
        defaults.set(pawchiveDownloadImages, forKey: "pawchiveDownloadImages")
        defaults.set(pawchiveDownloadVideos, forKey: "pawchiveDownloadVideos")
        defaults.set(pawchiveDownloadHTML, forKey: "pawchiveDownloadHTML")
        defaults.set(pawchiveDownloadOtherFiles, forKey: "pawchiveDownloadOtherFiles")
    }

    @discardableResult
    func persistHLS() -> Int {
        let delay = Self.normalizedM3U8SegmentDelayMilliseconds(
            from: m3u8SegmentDelayMillisecondsString
        )
        m3u8SegmentDelayMillisecondsString = delay > 0 ? String(delay) : ""
        defaults.set(remuxM3U8ToMP4, forKey: "remuxM3U8ToMP4")
        defaults.set(
            hlsContinueOnSegmentFailure,
            forKey: "hlsContinueOnSegmentFailure"
        )
        defaults.set(delay, forKey: "m3u8SegmentDelayMilliseconds")
        return delay
    }

    nonisolated static func normalizedM3U8SegmentDelayMilliseconds(
        from raw: String
    ) -> Int {
        let value = Int(raw.trimmed) ?? 0
        return min(60_000, max(0, value))
    }

    func persistYouTubePreferredLanguage() {
        youtubePreferredLanguage = youtubePreferredLanguage.trimmed
        defaults.set(youtubePreferredLanguage, forKey: "youtubePreferredLanguage")
    }

    func persistYouTubeDownloadThumbnail() {
        defaults.set(youtubeDownloadThumbnail, forKey: "youtubeDownloadThumbnail")
    }

    func persistYouTubeReversePlaylist() {
        defaults.set(youtubeReversePlaylist, forKey: "youtubeReversePlaylist")
    }

    func persistYouTubeUploadDatePreference() {
        defaults.set(
            youtubeUseUploadDateForFileModificationTime,
            forKey: "youtubeUseUploadDateForFileModificationTime"
        )
    }

    func persistYouTubeSubtitles() {
        youtubeSubtitleLanguages = youtubeSubtitleLanguages
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        defaults.set(
            youtubeDownloadAutoSubtitles,
            forKey: "youtubeDownloadAutoSubtitles"
        )
        defaults.set(youtubeSubtitleLanguages, forKey: "youtubeSubtitleLanguages")
    }

    func persistYouTubeEmbedChapters() {
        defaults.set(youtubeEmbedChapters, forKey: "youtubeEmbedChapters")
    }

    func persistYouTubeEnhancedBitrate() {
        defaults.set(
            youtubePreferEnhancedBitrate,
            forKey: "youtubePreferEnhancedBitrate"
        )
    }

    func persistYouTubeCodecPriority() {
        youtubeVideoCodecPriority = YouTubeVideoCodec.normalizedPriority(
            youtubeVideoCodecPriority
        )
        youtubeVideoCodecSort = YouTubeVideoCodec.ytdlpSortExpression(
            for: youtubeVideoCodecPriority
        )
        let rawPriority = youtubeVideoCodecPriority.map(\.rawValue)
        let originalJSON = (try? JSONSerialization.data(withJSONObject: rawPriority))
            .flatMap { String(data: $0, encoding: .utf8) }
            ?? "[\"avc1\",\"vp9\",\"av1\"]"
        defaults.set(rawPriority, forKey: "youtubeVideoCodecPriority")
        defaults.set(originalJSON, forKey: "CODECS_PRI")
        defaults.set(youtubeVideoCodecSort, forKey: "youtubeVideoCodecSort")
    }

    func persistYouTubePreferredResolution() {
        youtubePreferredResolution = youtubePreferredResolution.trimmed
        defaults.set(youtubePreferredResolution, forKey: "youtubePreferredResolution")
    }

    func persistYouTubePreferredAudioLanguage() {
        youtubePreferredAudioLanguage =
            YTDLPBridge.normalizedYouTubeAudioLanguage(youtubePreferredAudioLanguage) ?? ""
        defaults.set(
            youtubePreferredAudioLanguage,
            forKey: "youtubePreferredAudioLanguage"
        )
    }

    func persistYouTubeSnapshot() {
        persistYouTubePreferredLanguage()
        persistYouTubeDownloadThumbnail()
        persistYouTubeReversePlaylist()
        persistYouTubeUploadDatePreference()
        persistYouTubeSubtitles()
        persistYouTubeEmbedChapters()
        persistYouTubeEnhancedBitrate()
        persistYouTubeCodecPriority()
        persistYouTubePreferredResolution()
        persistYouTubePreferredAudioLanguage()
    }

    func persistInstagramIncludeStories() {
        defaults.set(instagramIncludeStories, forKey: "instagramIncludeStories")
    }

    func persistSOOPPreferredResolution() {
        soopPreferredResolution = soopPreferredResolution.trimmed
        defaults.set(soopPreferredResolution, forKey: "soopPreferredResolution")
    }

    func persistMediaSourceSnapshot() {
        persistInstagramIncludeStories()
        persistSOOPPreferredResolution()
    }

    nonisolated static func normalizedHistoryLimit(from raw: String) -> Int {
        let value = Int(raw.trimmed) ?? 1_000
        return min(5_000, max(1, value))
    }

    nonisolated static func normalizedFloatingMonitorOpacity(
        _ value: Double
    ) -> Double {
        guard value.isFinite else { return 0.92 }
        return min(1, max(0.45, value))
    }

    private nonisolated static func loadJobStatusColorPalette(
        defaults: UserDefaults
    ) -> JobStatusColorPalette {
        guard let data = defaults.data(forKey: "jobStatusColorPalette"),
              let palette = try? JSONDecoder().decode(
                  JobStatusColorPalette.self,
                  from: data
              ) else {
            return .defaultPalette
        }
        return palette.normalized()
    }

    private nonisolated static func defaultAppShortcutAssignments()
        -> [AppShortcutCommand: AppShortcut] {
        Dictionary(
            uniqueKeysWithValues: AppShortcutCommand.allCases.map { command in
                (command, command.defaultShortcut)
            }
        )
    }

    private nonisolated static func loadAppShortcutAssignments(
        defaults: UserDefaults
    ) -> [AppShortcutCommand: AppShortcut] {
        var assignments = defaultAppShortcutAssignments()
        guard let data = defaults.data(forKey: "appShortcutAssignments"),
              let decoded = try? JSONDecoder().decode(
                  [String: AppShortcut].self,
                  from: data
              ) else {
            return assignments
        }
        for (rawCommand, shortcut) in decoded {
            guard let command = AppShortcutCommand(rawValue: rawCommand) else {
                continue
            }
            assignments[command] = shortcut.normalized()
        }
        return assignments
    }

    private func persistAppShortcutAssignments() {
        let rawAssignments = Dictionary(
            uniqueKeysWithValues: AppShortcutCommand.allCases.map { command in
                (command.rawValue, shortcut(for: command))
            }
        )
        if let data = try? JSONEncoder().encode(rawAssignments) {
            defaults.set(data, forKey: "appShortcutAssignments")
        }
    }

    private nonisolated static func loadTaskTagNames(
        defaults: UserDefaults
    ) -> [String: String] {
        let stored = defaults.dictionary(forKey: "taskTagNames")
            as? [String: String] ?? [:]
        return Dictionary(
            uniqueKeysWithValues: TaskTagColor.allCases.map { tag in
                let name = stored[tag.rawValue]?.trimmed ?? ""
                return (
                    tag.rawValue,
                    name.isEmpty ? tag.label : String(name.prefix(80))
                )
            }
        )
    }

    private nonisolated static func loadTaskTagRestartTimers(
        defaults: UserDefaults
    ) -> [String: Int] {
        var stored: [String: Int] = [:]
        if let dictionary = defaults.dictionary(
            forKey: "taskTagRestartTimers"
        ) {
            for (key, value) in dictionary {
                if let number = value as? NSNumber {
                    stored[key] = max(0, number.intValue)
                } else if let text = value as? String,
                          let seconds = Int(text) {
                    stored[key] = max(0, seconds)
                }
            }
        } else if let originalJSON = defaults.string(forKey: "tag_timer"),
                  let data = originalJSON.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode(
                      [String: Int].self,
                      from: data
                  ) {
            stored = decoded.mapValues { max(0, $0) }
        }
        return Dictionary(
            uniqueKeysWithValues: TaskTagColor.allCases.map { tag in
                (tag.rawValue, stored[tag.rawValue] ?? 0)
            }
        )
    }

    private nonisolated static func restartDelayDescription(
        _ rawSeconds: Int
    ) -> String {
        let totalSeconds = max(0, rawSeconds)
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return seconds > 0
                ? "\(hours)h \(minutes)m \(seconds)s"
                : "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return seconds > 0
                ? "\(minutes)m \(seconds)s"
                : "\(minutes)m"
        }
        return "\(seconds)s"
    }

    private nonisolated static func environmentBool(
        _ key: String,
        environment: [String: String]
    ) -> Bool? {
        guard let raw = environment[key]?.trimmed.lowercased(),
              !raw.isEmpty else {
            return nil
        }
        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return nil
    }

    private nonisolated static func environmentPort(
        _ key: String,
        environment: [String: String]
    ) -> String? {
        guard let raw = environment[key]?.trimmed,
              let port = UInt16(raw),
              port > 0 else {
            return nil
        }
        return String(port)
    }

    nonisolated static func isTransientTestDestinationPath(_ path: String) -> Bool {
        let standardized = (path.trimmed as NSString).standardizingPath
        guard !standardized.isEmpty else { return false }
        if standardized.hasPrefix("/tmp/HitomiBadayo-") ||
            standardized.hasPrefix("/private/tmp/HitomiBadayo-") ||
            standardized.hasPrefix("/tmp/HitomiNative-") ||
            standardized.hasPrefix("/private/tmp/HitomiNative-") {
            return true
        }
        return ["HitomiBadayo", "HitomiNative"].contains { prefix in
            standardized.range(
                of: "^/(?:private/)?var/folders/.+/T/\(prefix)-[^/]+(?:/|$)",
                options: .regularExpression
            ) != nil
        }
    }
}
