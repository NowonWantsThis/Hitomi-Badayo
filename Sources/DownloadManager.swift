import AppKit
import CryptoKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class DownloadManager:
    SourceJobExecutionCommandHandling,
    SourceJobExecutionCapabilityProviding
{
    let presentation: AppPresentationStore
    let appStatusStore: AppStatusStore
    let appCommandService: AppCommandService
    let appShortcutCommandService: AppShortcutCommandService
    let quickAccessCommandService: QuickAccessCommandService
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
    let queueExecutionService:
        QueueExecutionService
    let downloadCoordinator: DownloadCoordinator
    let assetDownloadExecutor: AssetDownloadExecutor
    let assetTransferService: AssetTransferService
    let mediaTransferCoordinator: MediaTransferCoordinator
    let mediaConcatenationCoordinator: MediaConcatenationCoordinator
    let mediaRemuxCoordinator: MediaRemuxCoordinator
    let mediaMuxCoordinator: MediaMuxCoordinator
    let directSegmentTransferService:
        DirectSegmentTransferService
    let assetDownloadJobStateService:
        AssetDownloadJobStateService
    let directTransferJobStateService:
        DirectTransferJobStateService
    let resolvedPackageJobStateService:
        ResolvedPackageJobStateService
    let resolvedFilesPackageCoordinator:
        ResolvedFilesPackageCoordinator
    let resolvedConcatenationPackageCoordinator:
        ResolvedConcatenationPackageCoordinator
    let resolvedMuxPackageCoordinator:
        ResolvedMuxPackageCoordinator
    let resolvedGroupedPackageCoordinator:
        ResolvedGroupedPackageCoordinator
    let niconicoLiveJobStateService:
        NiconicoLiveJobStateService
    let liveHLSJobStateService:
        LiveHLSJobStateService
    let liveHLSRecordingCoordinator:
        LiveHLSRecordingCoordinator
    let niconicoLiveRecordingCoordinator:
        NiconicoLiveRecordingCoordinator
    let resolvedDownloadRangeService: ResolvedDownloadRangeService
    let resolvedDownloadJobPreparationService:
        ResolvedDownloadJobPreparationService
    let resolvedDownloadExecutionPreparationService:
        ResolvedDownloadExecutionPreparationService
    let siteRequestHeaderService:
        SiteRequestHeaderService
    let resolvedPackageExecutionDispatchService:
        ResolvedPackageExecutionDispatchService
    let downloadExecutionFailurePolicy:
        DownloadExecutionFailurePolicy
    let downloadExecutionJobStateService:
        DownloadExecutionJobStateService
    let completedDownloadJobStateService:
        CompletedDownloadJobStateService
    let completedOutputMetadataService:
        CompletedOutputMetadataService
    let completedOutputMetadataBackfillCoordinator:
        CompletedOutputMetadataBackfillCoordinator
    let completedJobMetadataEnrichmentCoordinator:
        CompletedJobMetadataEnrichmentCoordinator
    let outputPreviewLoadCoordinator:
        OutputPreviewLoadCoordinator
    let textViewerReadModelService =
        TextViewerReadModelService()
    let textViewerCommandService:
        TextViewerCommandService
    let outputImageConversionCoordinator:
        OutputImageConversionCoordinator
    let autoRecordMonitorCoordinator:
        AutoRecordMonitorCoordinator
    let autoRecordCheckCommandCoordinator:
        AutoRecordCheckCommandCoordinator
    let jobEditThumbnailLoadCoordinator:
        JobEditThumbnailLoadCoordinator
    let jobEditThumbnailImageService:
        JobEditThumbnailImageService
    let queueRunCoordinator:
        QueueRunCoordinator
    let queueViewSelectionRestoreCoordinator:
        QueueViewSelectionRestoreCoordinator
    let publicIPLookupCoordinator:
        PublicIPLookupCoordinator
    let sourceAuthenticationPolicy:
        SourceAuthenticationPolicy
    let authenticationBrowserCommandService:
        AuthenticationBrowserCommandService
    let browserWindowCommandService:
        BrowserWindowCommandService
    let sourceAuthenticationVerificationCoordinator:
        SourceAuthenticationVerificationCoordinator
    let cookieManagementCoordinator:
        CookieManagementCoordinator
    let authenticationCookieImportService:
        AuthenticationCookieImportService
    let authenticationWaitCoordinator:
        AuthenticationWaitCoordinator
    let authenticationJobWaitService:
        AuthenticationJobWaitService
    let sourceResolverAuthenticationDispatchService:
        SourceResolverAuthenticationDispatchService
    let sourceResolverProgressJobStateService:
        SourceResolverProgressJobStateService
    let sourceExecutionJobStateService:
        SourceExecutionJobStateService
    let directFileJobCoordinator:
        DirectFileJobCoordinator
    let discordEmojiJobCoordinator:
        DiscordEmojiJobCoordinator
    let sourceResolverJobContextService:
        SourceResolverJobContextService
    let persistenceService: UserDataPersistenceService
    let outputService: OutputService
    let outputNamingService: OutputNamingService
    let outputContentFileService =
        OutputContentFileService()
    let outputViewSelectionService =
        OutputViewSelectionService()
    let outputFileHTTPResponseService =
        OutputFileHTTPResponseService()
    let outputOpenService: OutputOpenService
    let outputCommandService: OutputCommandService
    let outputJobCommandCoordinator:
        OutputJobCommandCoordinator
    let clipboardMonitorCoordinator:
        ClipboardMonitorCoordinator
    let clipboardCommandService:
        ClipboardCommandService
    let clipboardViewerCommandService:
        ClipboardViewerCommandService
    let galleryNumberCopyCoordinator:
        GalleryNumberCopyCoordinator
    let outputPathRepairService:
        OutputPathRepairService
    let duplicateImageScanService:
        DuplicateImageScanService
    let duplicateImageScanCoordinator:
        DuplicateImageScanCoordinator
    let sourceLinkCommandService:
        SourceLinkCommandService
    let workspaceItemCommandService:
        WorkspaceItemCommandService
    let documentPanelCommandService:
        DocumentPanelCommandService
    let confirmationDialogService:
        ConfirmationDialogService
    let imageConversionDialogService:
        ImageConversionDialogService
    let applicationMenuCommandService:
        ApplicationMenuCommandService
    let interfaceFontService:
        InterfaceFontService
    let queueCompletionCommandService:
        QueueCompletionCommandService
    let pdfOutputService: PDFOutputService
    let pdfJobStateService: PDFJobStateService
    let archiveJobStateService: ArchiveJobStateService
    let queueJobActionPolicy: QueueJobActionPolicy
    let externalToolOutputMetadataService:
        ExternalToolOutputMetadataService
    let ytdlpJobStateService: YTDLPJobStateService
    let ytdlpProgressUpdateService:
        YTDLPProgressUpdateService
    let ytdlpProgressDeliveryService:
        YTDLPProgressDeliveryService
    let nativeTransferProgressService:
        NativeTransferProgressService
    let aria2JobStateService: Aria2JobStateService
    let aria2RuntimeCommandService:
        Aria2RuntimeCommandService
    let aria2RuntimeCommandCoordinator:
        Aria2RuntimeCommandCoordinator
    let customCommandJobStateService:
        CustomCommandJobStateService
    let externalToolRuntime: ExternalToolRuntimeService
    let externalToolInstallCoordinator:
        ExternalToolInstallCoordinator
    let managedExternalToolCommandService:
        ManagedExternalToolCommandService
    let searchRequestCoordinator:
        SearchRequestCoordinator
    let searchResultFetchService:
        SearchResultFetchService
    let searchExecutionFacade:
        SearchExecutionFacade
    let searchUICommandFacade:
        SearchUICommandFacade
    let sourceResolverRegistry: SourceResolverRegistry
    let sourceResolverExecutor: SourceResolverExecutor
    let sourceExecutionRoutingService: SourceExecutionRoutingService
    let sourceExecutionDispatchService: SourceExecutionDispatchService
    let sourceResolverPlanExecutionService: SourceResolverPlanExecutionService
    let sourceResolverPlanJobCoordinator:
        SourceResolverPlanJobCoordinator
    let pythonPluginExecutionService: PythonPluginExecutionService
    let pythonSourceJobCoordinator:
        PythonSourceJobCoordinator
    let pythonPluginCommandCoordinator:
        PythonPluginCommandCoordinator
    let pythonNativeDelegationCoordinator:
        PythonNativeDelegationCoordinator
    let pythonHookRegistrationService: PythonHookRegistrationService
    let pythonHookExecutionService: PythonHookExecutionService
    let pythonExecutionLogService: PythonExecutionLogService
    let resolvedDownloadHookPreparationService:
        ResolvedDownloadHookPreparationService
    let pythonHookJobApplicationService:
        PythonHookJobApplicationService
    let syntheticPythonDownloadHookService:
        SyntheticPythonDownloadHookService
    let sourceResolverExecutionOptionsFactory: SourceResolverExecutionOptionsFactory
    let sourceJobExecutionRequestFactory:
        SourceJobExecutionRequestFactory
    let sourceJobExecutionCapabilitiesFactory:
        SourceJobExecutionCapabilitiesFactory
    let sourceJobExecutionActionFactory:
        SourceJobExecutionActionFactory
    let sourceInputRoutingService: SourceInputRoutingService
    let sourceInputExecutionDispatchService:
        SourceInputExecutionDispatchService
    let sourceJobExecutionService:
        SourceJobExecutionService
    let sourceJobExecutionPipeline:
        SourceJobExecutionPipeline
    let sourceJobExecutionCoordinator:
        SourceJobExecutionCoordinator
    let sourceJobStartHookPipeline:
        SourceJobStartHookPipeline
    let originalInputExecutionService: OriginalInputExecutionService
    let originalInputJobCoordinator:
        OriginalInputJobCoordinator
    let genericPageExecutionService: GenericPageExecutionService
    let genericPageJobCoordinator:
        GenericPageJobCoordinator
    let sourceResolverFallbackPolicy: SourceResolverFallbackPolicy

    private var addSummary: String {
        get { appStatusStore.addSummary }
        set { appStatusStore.setSummary(newValue) }
    }

    private var searchPresentationSnapshot: SearchPresentationSnapshot {
        SearchPresentationReadModelService.snapshot(
            results: searchStore.searchResults,
            filter: searchStore.searchResultFilter,
            knownFilter: settingsStore.searchResultKnownFilter,
            sortMode: settingsStore.searchResultSortMode,
            sortDescending: settingsStore.searchResultSortDescending,
            jobs: queueStore.jobs,
            history: libraryStore.history,
            destinationPath: settingsStore.destinationPath
        )
    }

    private var queuePresentationSnapshot: QueuePresentationSnapshot {
        QueuePresentationReadModelService.snapshot(
            jobs: queueStore.jobs,
            groups: queueStore.queueGroups,
            scheduler: queueScheduler,
            query: presentation.queueFilter,
            sortMode: settingsStore.queueSortMode,
            descending: settingsStore.queueSortDescending,
            selectedJobIDs: presentation.selectedJobIDs,
            pendingRemovalIDs: queueEditorStore.jobPendingRemovalIDs,
            language: settingsStore.interfaceLanguage
        )
    }

    private var themePresentationSnapshot: ThemePresentationSnapshot {
        ThemePresentationService.snapshot(
            plugins: pythonRuntimeStore.scriptPlugins,
            selectedThemeKey: settingsStore.selectedPythonThemeKey,
            appearanceMode: settingsStore.appAppearanceMode
        )
    }

    private var isPreparingForTermination = false
    private let localAPICorePageRenderer = LocalAPICorePageRenderer()
    private let localAPIDiagnosticFacade = LocalAPIDiagnosticFacade()
    private let localAPIDocsPageRenderer = LocalAPIDocsPageRenderer()
    private let localAPIExecutionCommandService =
        LocalAPIExecutionCommandService()
    private let localAPIHistoryFacade = LocalAPIHistoryFacade()
    private let localAPIInputFacade = LocalAPIInputFacade()
    private let localAPIPageSelectorFacade = LocalAPIPageSelectorFacade()
    private let localAPIListFacade = LocalAPIListFacade()
    private let localAPIQueueCommandService = LocalAPIQueueCommandService()
    private let localAPIWebUIPageRenderer = LocalAPIWebUIPageRenderer()
    private let localAPISearchFacade = LocalAPISearchFacade()
    private let localAPITextFacade = LocalAPITextFacade()
    private let localAPIViewPageRenderer = LocalAPIViewPageRenderer()
    private let localAPIViewFacade = LocalAPIViewFacade()
    private let localAPIFacade = LocalAPIFacade()
    private let localAPICookieService = LocalAPICookieService()
    private let localAPIAria2RuntimeService =
        LocalAPIAria2RuntimeService()
    private let localAPIJobCommandService =
        LocalAPIJobCommandService()
    private let localAPILoginService = LocalAPILoginService()
    private let localAPIRequestDecoder = LocalAPIRequestDecoder()
    private let localAPIServerCoordinator = LocalAPIServerCoordinator()
    private let localAPIStaticAssetService = LocalAPIStaticAssetService()
    private let localAPITaskMetadataService =
        LocalAPITaskMetadataService()
    private let localAPIJobPresentationService =
        LocalAPIJobPresentationService()
    private let localAPITaskSelectionService =
        LocalAPITaskSelectionService()
    private lazy var localAPIOutputCommandService:
        LocalAPIOutputCommandService = {
            let pdfOutput = self.pdfOutputService
            let output = self.outputService
            let pdfState = self.pdfJobStateService
            let archiveState = self.archiveJobStateService
            return LocalAPIOutputCommandService(
                pdfCreator: { outputPath, title in
                    try pdfOutput.createPDF(
                        fromOutputPath: outputPath,
                        title: title
                    )
                },
                archiveCreator: {
                    source,
                    destination,
                    deleteOriginal in
                    try output.archiveCompletedFolder(
                        source,
                        to: destination,
                        deleteOriginal: deleteOriginal
                    )
                },
                pdfStateRecorder: {
                    job,
                    pdfURL,
                    createdAt in
                    pdfState.recordingCreatedPDF(
                        job,
                        pdfURL: pdfURL,
                        createdAt: createdAt
                    )
                },
                archiveStateRecorder: {
                    job,
                    archiveURL,
                    format,
                    created,
                    deletedOriginal,
                    createdAt in
                    archiveState.recordingAPIArchive(
                        job,
                        archive: archiveURL,
                        format: format,
                        created: created,
                        deletedOriginal: deletedOriginal,
                        createdAt: createdAt
                    )
                }
            )
        }()
    private lazy var sourceInputClassificationService:
        SourceInputClassificationService = {
            SourceInputClassificationService(
                registry: self.sourceResolverRegistry,
                aria2Bridge: self.aria2Bridge,
                ytdlpBridge: self.ytdlpBridge
            )
        }()
    private var browserExtensionServer: BrowserExtensionServer?
    private var apiVideoThumbnailCache: [String: APIVideoThumbnailCacheEntry] = [:]
    private static let apiFontStack = LocalAPIHTMLStyle.fontStack
    private static let apiSVGFontStack = LocalAPIHTMLStyle.svgFontStack
    private nonisolated static let pendingQueueOutputDeletionMetadataKey = "pending_queue_output_deletion"
    private nonisolated static let liveStopRequestedMetadataKey =
        LiveHLSJobStateService.stopRequestedMetadataKey
    nonisolated static let directDownloadOverrideMetadataKey =
        SourceJobExecutionRequestFactory
            .directDownloadOverrideMetadataKey
    nonisolated static let scheduledRetryTimestampMetadataKey =
        DownloadRetryPolicy.timestampMetadataKey
    nonisolated static let scheduledRetryOriginalTitleMetadataKey =
        DownloadRetryPolicy.originalTitleMetadataKey
    private nonisolated static let scheduledRetryKindMetadataKey =
        DownloadRetryPolicy.kindMetadataKey
    private nonisolated static let scheduledRetryDelayMetadataKey =
        DownloadRetryPolicy.delayMetadataKey
    private nonisolated static let scheduledRetryForceMetadataKey =
        DownloadRetryPolicy.forceMetadataKey
    private var lastClipboardChangeCount = 0
    private var deferredAutoRemoveJobIDs: Set<UUID> = []
    private var defersAutoRemoveUntilQueueEnd = false
    private let appStartedAt = Date()
    private lazy var networkTrafficSampler = NetworkTrafficSampler(
        appStartedAt: appStartedAt
    )
    private let completionAlerts = CompletionAlertCenter()
    private let sleepPreventionAssertion = SleepPreventionAssertion()
    private var userData: AppUserData {
        get { persistenceService.userData }
        set { persistenceService.replaceUserData(newValue) }
    }
#if TESTING
    var testingJobStartDelayNanoseconds: UInt64 = 0
    var testingJobScheduledHandler: ((DownloadJob) -> Void)?
    var testingResolvedDownloads: [String: ResolvedDownload] = [:]
    var testingLoginBrowserOpenHandler: ((URL) -> Void)?
    var testingLoginBrowserRequestHandler:
        ((
            URL,
            String?,
            LoginBrowserAutoImportPolicy
        ) -> Void)?
    var testingClipboardInputText: String?
    var testingEnsureHTTPAPIAvailableForBrowserView:
        (() -> Bool)?
    var testingTrashItemHandler: ((URL) throws -> URL?)?
    var testingTrashedResultURLs: [URL] = []
#endif
    private var hitomiResolver: HitomiResolver { sourceResolverRegistry.hitomiResolver }
    private var nhentaiResolver: NHentaiResolver { sourceResolverRegistry.nhentaiResolver }
    private var nhentaiComResolver: NHentaiComResolver { sourceResolverRegistry.nhentaiComResolver }
    private var asmHentaiResolver: AsmHentaiResolver { sourceResolverRegistry.asmHentaiResolver }
    private var eHentaiResolver: EHentaiResolver { sourceResolverRegistry.eHentaiResolver }
    private var myReadingMangaResolver: MyReadingMangaResolver { sourceResolverRegistry.myReadingMangaResolver }
    private var narouResolver: NarouResolver { sourceResolverRegistry.narouResolver }
    private var kakuyomuResolver: KakuyomuResolver { sourceResolverRegistry.kakuyomuResolver }
    private var hamelnResolver: HamelnResolver { sourceResolverRegistry.hamelnResolver }
    private var artStationResolver: ArtStationResolver { sourceResolverRegistry.artStationResolver }
    private var imgurResolver: ImgurResolver { sourceResolverRegistry.imgurResolver }
    private var deviantArtResolver: DeviantArtResolver { sourceResolverRegistry.deviantArtResolver }
    private var discordEmojiResolver: DiscordEmojiResolver { sourceResolverRegistry.discordEmojiResolver }
    private var coubResolver: CoubResolver { sourceResolverRegistry.coubResolver }
    private var vimeoResolver: VimeoResolver { sourceResolverRegistry.vimeoResolver }
    private var tumblrResolver: TumblrResolver { sourceResolverRegistry.tumblrResolver }
    private var bdsmLrResolver: BDSMlrResolver { sourceResolverRegistry.bdsmLrResolver }
    private var lusciousResolver: LusciousResolver { sourceResolverRegistry.lusciousResolver }
    private var soundCloudResolver: SoundCloudResolver { sourceResolverRegistry.soundCloudResolver }
    private var tikTokResolver: TikTokResolver { sourceResolverRegistry.tikTokResolver }
    private var twitterCollectionResolver: TwitterCollectionResolver { sourceResolverRegistry.twitterCollectionResolver }
    private var twitterResolver: TwitterResolver { sourceResolverRegistry.twitterResolver }
    private var fediverseResolver: FediverseResolver { sourceResolverRegistry.fediverseResolver }
    private var bilibiliCollectionResolver: BilibiliCollectionResolver { sourceResolverRegistry.bilibiliCollectionResolver }
    private var bilibiliResolver: BilibiliResolver { sourceResolverRegistry.bilibiliResolver }
    private var fourChanResolver: FourChanResolver { sourceResolverRegistry.fourChanResolver }
    private var arcaliveResolver: ArcaliveResolver { sourceResolverRegistry.arcaliveResolver }
    private var dcInsideResolver: DCInsideResolver { sourceResolverRegistry.dcInsideResolver }
    private var flickrResolver: FlickrResolver { sourceResolverRegistry.flickrResolver }
    private var pinterestResolver: PinterestResolver { sourceResolverRegistry.pinterestResolver }
    private var wikiArtResolver: WikiArtResolver { sourceResolverRegistry.wikiArtResolver }
    private var newgroundsResolver: NewgroundsResolver { sourceResolverRegistry.newgroundsResolver }
    private var nijieResolver: NijieResolver { sourceResolverRegistry.nijieResolver }
    private var nozomiResolver: NozomiResolver { sourceResolverRegistry.nozomiResolver }
    private var v2phResolver: V2PHResolver { sourceResolverRegistry.v2phResolver }
    private var hentaiCosplayResolver: HentaiCosplayResolver { sourceResolverRegistry.hentaiCosplayResolver }
    private var hentaiFoundryResolver: HentaiFoundryResolver { sourceResolverRegistry.hentaiFoundryResolver }
    private var talkOPGGResolver: TalkOPGGResolver { sourceResolverRegistry.talkOPGGResolver }
    private var bcyResolver: BCYResolver { sourceResolverRegistry.bcyResolver }
    private var waybackMachineResolver: WaybackMachineResolver { sourceResolverRegistry.waybackMachineResolver }
    private var fc2Resolver: FC2Resolver { sourceResolverRegistry.fc2Resolver }
    private var pornhubCollectionResolver: PornhubCollectionResolver { sourceResolverRegistry.pornhubCollectionResolver }
    private var pornhubMediaResolver: PornhubMediaResolver { sourceResolverRegistry.pornhubMediaResolver }
    private var xVideoCollectionResolver: XVideoCollectionResolver { sourceResolverRegistry.xVideoCollectionResolver }
    private var xVideoPageResolver: XVideoPageResolver { sourceResolverRegistry.xVideoPageResolver }
    private var xHamsterCollectionResolver: XHamsterCollectionResolver { sourceResolverRegistry.xHamsterCollectionResolver }
    private var xHamsterGalleryResolver: XHamsterGalleryResolver { sourceResolverRegistry.xHamsterGalleryResolver }
    private var iwaraCollectionResolver: IwaraCollectionResolver { sourceResolverRegistry.iwaraCollectionResolver }
    private var iwaraImageResolver: IwaraImageResolver { sourceResolverRegistry.iwaraImageResolver }
    private var iwaraVideoResolver: IwaraVideoResolver { sourceResolverRegistry.iwaraVideoResolver }
    private var weiboStatusResolver: WeiboStatusResolver { sourceResolverRegistry.weiboStatusResolver }
    private var spankBangResolver: SpankBangResolver { sourceResolverRegistry.spankBangResolver }
    private var avgleResolver: AvgleResolver { sourceResolverRegistry.avgleResolver }
    private var kissJAVResolver: KissJAVResolver { sourceResolverRegistry.kissJAVResolver }
    private var tokyoMotionResolver: TokyoMotionResolver { sourceResolverRegistry.tokyoMotionResolver }
    private var etcVideoPageResolver: EtcVideoPageResolver { sourceResolverRegistry.etcVideoPageResolver }
    private var hiyobiResolver: HiyobiResolver { sourceResolverRegistry.hiyobiResolver }
    private var manatokiResolver: ManatokiResolver { sourceResolverRegistry.manatokiResolver }
    private var lhScanResolver: LHScanResolver { sourceResolverRegistry.lhScanResolver }
    private var jManaResolver: JManaResolver { sourceResolverRegistry.jManaResolver }
    private var webtoonResolver: WebtoonResolver { sourceResolverRegistry.webtoonResolver }
    private var naverWebtoonResolver: NaverWebtoonResolver { sourceResolverRegistry.naverWebtoonResolver }
    private var naverPostResolver: NaverPostResolver { sourceResolverRegistry.naverPostResolver }
    private var naverBlogResolver: NaverBlogResolver { sourceResolverRegistry.naverBlogResolver }
    private var naverCafeResolver: NaverCafeResolver { sourceResolverRegistry.naverCafeResolver }
    private var naverTVResolver: NaverTVResolver { sourceResolverRegistry.naverTVResolver }
    private var chzzkCollectionResolver: ChzzkCollectionResolver { sourceResolverRegistry.chzzkCollectionResolver }
    private var chzzkResolver: ChzzkResolver { sourceResolverRegistry.chzzkResolver }
    private var hanimeResolver: HanimeResolver { sourceResolverRegistry.hanimeResolver }
    private var instagramResolver: InstagramResolver { sourceResolverRegistry.instagramResolver }
    private var facebookPhotoCollectionResolver: FacebookPhotoCollectionResolver { sourceResolverRegistry.facebookPhotoCollectionResolver }
    private var facebookPhotoResolver: FacebookPhotoResolver { sourceResolverRegistry.facebookPhotoResolver }
    private var facebookVideoResolver: FacebookVideoResolver { sourceResolverRegistry.facebookVideoResolver }
    private var twitchClipCollectionResolver: TwitchClipCollectionResolver { sourceResolverRegistry.twitchClipCollectionResolver }
    private var twitchVODResolver: TwitchVODResolver { sourceResolverRegistry.twitchVODResolver }
    private var soopVODResolver: SOOPVODResolver { sourceResolverRegistry.soopVODResolver }
    private var kakaoTVResolver: KakaoTVResolver { sourceResolverRegistry.kakaoTVResolver }
    private var youtubeCollectionResolver: YouTubeCollectionResolver { sourceResolverRegistry.youtubeCollectionResolver }
    private var youtubeResolver: YouTubeResolver { sourceResolverRegistry.youtubeResolver }
    private var vLiveResolver: VLiveResolver { sourceResolverRegistry.vLiveResolver }
    private var niconicoResolver: NiconicoResolver { sourceResolverRegistry.niconicoResolver }
    private var niconicoLiveResolver: NiconicoLiveResolver { sourceResolverRegistry.niconicoLiveResolver }
    private var lezhinResolver: LezhinResolver { sourceResolverRegistry.lezhinResolver }
    private var kakaoWebtoonResolver: KakaoWebtoonResolver { sourceResolverRegistry.kakaoWebtoonResolver }
    private var kakaoPageResolver: KakaoPageResolver { sourceResolverRegistry.kakaoPageResolver }
    private var pixivArtworkResolver: PixivArtworkResolver { sourceResolverRegistry.pixivArtworkResolver }
    private var pixivArtworkExecutionOptions: PixivArtworkResolverExecutionOptions {
        PixivArtworkResolverExecutionOptions(
            ugoiraFileFormat: settingsStore.pixivUgoiraFileFormat,
            ugoiraDither: settingsStore.pixivUgoiraDither,
            ugoiraQuality: settingsStore.pixivUgoiraQuality
        )
    }
    private var pixivComicResolver: PixivComicResolver { sourceResolverRegistry.pixivComicResolver }
    private var pawchiveResolver: PawchiveResolver { sourceResolverRegistry.pawchiveResolver }
    private var comicWalkerResolver: ComicWalkerResolver { sourceResolverRegistry.comicWalkerResolver }
    private var sankakuResolver: SankakuResolver { sourceResolverRegistry.sankakuResolver }
    private var m3u8Resolver: M3U8Resolver { sourceResolverRegistry.m3u8Resolver }
    private var mpdResolver: MPDResolver { sourceResolverRegistry.mpdResolver }
    private var booruResolver: BooruResolver { sourceResolverRegistry.booruResolver }
    private var genericPageResolver: GenericPageResolver { sourceResolverRegistry.genericPageResolver }
    private var ytdlpBridge: YTDLPBridge { externalToolRuntime.ytdlpBridge }
    private var aria2Bridge: Aria2Bridge { externalToolRuntime.aria2Bridge }
    private var browserDPIBypassService: BrowserDPIBypassService {
        externalToolRuntime.browserDPIBypassService
    }

    init(
        niconicoLiveResolver: NiconicoLiveResolver = NiconicoLiveResolver(),
        sourceResolverRegistry: SourceResolverRegistry? = nil,
        sourceExecutionDispatchService: SourceExecutionDispatchService? = nil,
        sourceInputExecutionDispatchService:
            SourceInputExecutionDispatchService? = nil,
        presentation: AppPresentationStore? = nil,
        appStatusStore: AppStatusStore? = nil,
        appCommandService: AppCommandService? = nil,
        appShortcutCommandService: AppShortcutCommandService? = nil,
        quickAccessCommandService: QuickAccessCommandService? = nil,
        clipboardMonitorCoordinator:
            ClipboardMonitorCoordinator? = nil,
        clipboardCommandService:
            ClipboardCommandService? = nil,
        clipboardViewerCommandService:
            ClipboardViewerCommandService? = nil,
        sourceLinkCommandService:
            SourceLinkCommandService? = nil,
        browserWindowCommandService:
            BrowserWindowCommandService? = nil,
        workspaceItemCommandService:
            WorkspaceItemCommandService? = nil,
        documentPanelCommandService:
            DocumentPanelCommandService? = nil,
        confirmationDialogService:
            ConfirmationDialogService? = nil,
        imageConversionDialogService:
            ImageConversionDialogService? = nil,
        applicationMenuCommandService:
            ApplicationMenuCommandService? = nil,
        interfaceFontService:
            InterfaceFontService? = nil,
        queueCompletionCommandService:
            QueueCompletionCommandService? = nil,
        settingsStore: SettingsStore? = nil,
        searchStore: SearchStore? = nil,
        libraryStore: LibraryStore? = nil,
        queueStore: QueueStore? = nil,
        queueEditorStore: QueueEditorStore? = nil,
        duplicateImageStore: DuplicateImageStore? = nil,
        outputOperationStore: OutputOperationStore? = nil,
        externalToolStore: ExternalToolStore? = nil,
        aria2Store: Aria2Store? = nil,
        pythonRuntimeStore: PythonRuntimeStore? = nil,
        autoRecordStore: AutoRecordStore? = nil,
        networkStore: NetworkStore? = nil,
        cookieStatusStore: CookieStatusStore? = nil,
        queueScheduler: QueueScheduler? = nil,
        queueExecutionService:
            QueueExecutionService? = nil,
        downloadCoordinator: DownloadCoordinator? = nil,
        assetDownloadExecutor: AssetDownloadExecutor = AssetDownloadExecutor(),
        assetTransferService: AssetTransferService = AssetTransferService(),
        mediaTransferCoordinator: MediaTransferCoordinator? = nil,
        mediaConcatenationCoordinator:
            MediaConcatenationCoordinator? = nil,
        mediaRemuxCoordinator: MediaRemuxCoordinator? = nil,
        mediaMuxCoordinator: MediaMuxCoordinator? = nil,
        directSegmentTransferService:
            DirectSegmentTransferService =
                DirectSegmentTransferService(),
        assetDownloadJobStateService:
            AssetDownloadJobStateService? = nil,
        directTransferJobStateService:
            DirectTransferJobStateService? = nil,
        resolvedPackageJobStateService:
            ResolvedPackageJobStateService? = nil,
        niconicoLiveJobStateService:
            NiconicoLiveJobStateService? = nil,
        liveHLSJobStateService:
            LiveHLSJobStateService? = nil,
        liveHLSRecordingCoordinator:
            LiveHLSRecordingCoordinator? = nil,
        niconicoLiveRecordingCoordinator:
            NiconicoLiveRecordingCoordinator? = nil,
        resolvedDownloadRangeService:
            ResolvedDownloadRangeService =
                ResolvedDownloadRangeService(),
        resolvedDownloadJobPreparationService:
            ResolvedDownloadJobPreparationService? = nil,
        resolvedDownloadExecutionPreparationService:
            ResolvedDownloadExecutionPreparationService? = nil,
        siteRequestHeaderService:
            SiteRequestHeaderService? = nil,
        resolvedPackageExecutionDispatchService:
            ResolvedPackageExecutionDispatchService? = nil,
        downloadExecutionFailurePolicy:
            DownloadExecutionFailurePolicy? = nil,
        downloadExecutionJobStateService:
            DownloadExecutionJobStateService? = nil,
        completedDownloadJobStateService:
            CompletedDownloadJobStateService? = nil,
        completedOutputMetadataService:
            CompletedOutputMetadataService? = nil,
        completedOutputMetadataBackfillCoordinator:
            CompletedOutputMetadataBackfillCoordinator? = nil,
        completedJobMetadataEnrichmentCoordinator:
            CompletedJobMetadataEnrichmentCoordinator? = nil,
        outputPreviewLoadCoordinator:
            OutputPreviewLoadCoordinator? = nil,
        outputImageConversionCoordinator:
            OutputImageConversionCoordinator? = nil,
        autoRecordMonitorCoordinator:
            AutoRecordMonitorCoordinator? = nil,
        autoRecordCheckCommandCoordinator:
            AutoRecordCheckCommandCoordinator? = nil,
        jobEditThumbnailLoadCoordinator:
            JobEditThumbnailLoadCoordinator? = nil,
        jobEditThumbnailImageService:
            JobEditThumbnailImageService? = nil,
        queueRunCoordinator:
            QueueRunCoordinator? = nil,
        queueViewSelectionRestoreCoordinator:
            QueueViewSelectionRestoreCoordinator? = nil,
        publicIPLookupCoordinator:
            PublicIPLookupCoordinator? = nil,
        sourceAuthenticationPolicy:
            SourceAuthenticationPolicy? = nil,
        authenticationBrowserCommandService:
            AuthenticationBrowserCommandService? = nil,
        sourceAuthenticationVerificationCoordinator:
            SourceAuthenticationVerificationCoordinator? = nil,
        cookieManagementCoordinator:
            CookieManagementCoordinator? = nil,
        authenticationWaitCoordinator:
            AuthenticationWaitCoordinator? = nil,
        authenticationCookieImportService:
            AuthenticationCookieImportService? = nil,
        authenticationJobWaitService:
            AuthenticationJobWaitService? = nil,
        sourceResolverAuthenticationDispatchService:
            SourceResolverAuthenticationDispatchService? = nil,
        sourceResolverProgressJobStateService:
            SourceResolverProgressJobStateService? = nil,
        sourceExecutionJobStateService:
            SourceExecutionJobStateService? = nil,
        sourceResolverJobContextService:
            SourceResolverJobContextService? = nil,
        pythonPluginCommandCoordinator:
            PythonPluginCommandCoordinator? = nil,
        pythonNativeDelegationCoordinator:
            PythonNativeDelegationCoordinator? = nil,
        pythonHookRegistrationService:
            PythonHookRegistrationService? = nil,
        pythonHookExecutionService:
            PythonHookExecutionService? = nil,
        pythonExecutionLogService:
            PythonExecutionLogService? = nil,
        resolvedDownloadHookPreparationService:
            ResolvedDownloadHookPreparationService? = nil,
        pythonHookJobApplicationService:
            PythonHookJobApplicationService? = nil,
        sourceJobStartHookPipeline:
            SourceJobStartHookPipeline? = nil,
        syntheticPythonDownloadHookService:
            SyntheticPythonDownloadHookService? = nil,
        sourceJobExecutionRequestFactory:
            SourceJobExecutionRequestFactory =
                SourceJobExecutionRequestFactory(),
        sourceJobExecutionCapabilitiesFactory:
            SourceJobExecutionCapabilitiesFactory? = nil,
        sourceJobExecutionActionFactory:
            SourceJobExecutionActionFactory? = nil,
        persistenceService: UserDataPersistenceService? = nil,
        outputService: OutputService? = nil,
        outputNamingService:
            OutputNamingService = OutputNamingService(),
        outputOpenService: OutputOpenService? = nil,
        outputCommandService:
            OutputCommandService? = nil,
        outputJobCommandCoordinator:
            OutputJobCommandCoordinator? = nil,
        galleryNumberCopyCoordinator:
            GalleryNumberCopyCoordinator? = nil,
        outputPathRepairService:
            OutputPathRepairService =
                OutputPathRepairService(),
        duplicateImageScanService:
            DuplicateImageScanService =
                DuplicateImageScanService(),
        duplicateImageScanCoordinator:
            DuplicateImageScanCoordinator? = nil,
        pdfOutputService: PDFOutputService? = nil,
        pdfJobStateService: PDFJobStateService? = nil,
        archiveJobStateService:
            ArchiveJobStateService? = nil,
        queueJobActionPolicy:
            QueueJobActionPolicy? = nil,
        externalToolOutputMetadataService:
            ExternalToolOutputMetadataService? = nil,
        ytdlpJobStateService:
            YTDLPJobStateService? = nil,
        ytdlpProgressUpdateService:
            YTDLPProgressUpdateService? = nil,
        ytdlpProgressDeliveryService:
            YTDLPProgressDeliveryService? = nil,
        nativeTransferProgressService:
            NativeTransferProgressService? = nil,
        aria2JobStateService:
            Aria2JobStateService? = nil,
        aria2RuntimeCommandService:
            Aria2RuntimeCommandService =
                Aria2RuntimeCommandService(),
        aria2RuntimeCommandCoordinator:
            Aria2RuntimeCommandCoordinator? = nil,
        customCommandJobStateService:
            CustomCommandJobStateService? = nil,
        externalToolRuntime: ExternalToolRuntimeService? = nil,
        externalToolInstallCoordinator:
            ExternalToolInstallCoordinator? = nil,
        managedExternalToolCommandService:
            ManagedExternalToolCommandService? = nil,
        searchRequestCoordinator:
            SearchRequestCoordinator? = nil,
        searchResultFetchService:
            SearchResultFetchService? = nil,
        searchExecutionFacade:
            SearchExecutionFacade? = nil,
        sourceResolverFallbackPolicy: SourceResolverFallbackPolicy = SourceResolverFallbackPolicy()
    ) {
        let presentationStore =
            presentation ??
            appCommandService?.presentation ??
            AppPresentationStore()
        let appStatusState = appStatusStore ?? AppStatusStore()
        let settings: SettingsStore
        if let settingsStore {
            settings = settingsStore
        } else {
            settings = SettingsStore(
                interfaceFontService:
                    interfaceFontService ??
                    InterfaceFontService()
            )
        }
        let interfaceFonts =
            interfaceFontService ??
            settings.interfaceFontService
        settings.configureInterfaceFontService(
            interfaceFonts
        )
        let searchState = searchStore ?? SearchStore()
        let libraryState = libraryStore ?? LibraryStore()
        let queueState = queueStore ?? QueueStore()
        let queueEditorState = queueEditorStore ?? QueueEditorStore()
        let duplicateImages = duplicateImageStore ?? DuplicateImageStore()
        let outputOperations = outputOperationStore ?? OutputOperationStore()
        let externalTools = externalToolStore ?? ExternalToolStore()
        let aria2StoreState = aria2Store ?? Aria2Store()
        let pythonRuntimeState = pythonRuntimeStore ?? PythonRuntimeStore()
        let autoRecordState = autoRecordStore ?? AutoRecordStore()
        let networkState = networkStore ?? NetworkStore()
        let cookieStatus = cookieStatusStore ?? CookieStatusStore()
        let scheduler = queueScheduler ?? QueueScheduler()
        let queueExecution =
            queueExecutionService ??
            QueueExecutionService()
        let coordinator = downloadCoordinator ?? DownloadCoordinator()
        let assetJobState =
            assetDownloadJobStateService ??
            AssetDownloadJobStateService()
        let directTransferJobState =
            directTransferJobStateService ??
            DirectTransferJobStateService()
        let packageJobState =
            resolvedPackageJobStateService ??
            ResolvedPackageJobStateService()
        let filesPackageCoordinator =
            ResolvedFilesPackageCoordinator(
                queueStore: queueState,
                jobStateService: packageJobState
            )
        let concatenationPackageCoordinator =
            ResolvedConcatenationPackageCoordinator(
                queueStore: queueState,
                jobStateService: packageJobState
            )
        let muxPackageCoordinator =
            ResolvedMuxPackageCoordinator()
        let groupedPackageCoordinator =
            ResolvedGroupedPackageCoordinator(
                queueStore: queueState,
                jobStateService: packageJobState
            )
        let niconicoLiveJobState =
            niconicoLiveJobStateService ??
            NiconicoLiveJobStateService()
        let liveHLSJobState =
            liveHLSJobStateService ??
            LiveHLSJobStateService()
        let persistence = persistenceService ?? UserDataPersistenceService()
        let output = outputService ?? OutputService()
        let mediaTransfer = mediaTransferCoordinator ??
            MediaTransferCoordinator(
                assetDownloadExecutor: assetDownloadExecutor,
                assetTransferService: assetTransferService,
                outputService: output
            )
        let mediaConcatenation = mediaConcatenationCoordinator ??
            MediaConcatenationCoordinator()
        let mediaRemux = mediaRemuxCoordinator ??
            MediaRemuxCoordinator()
        let mediaMux = mediaMuxCoordinator ??
            MediaMuxCoordinator()
        let outputOpen =
            outputOpenService ??
            OutputOpenService()
        let outputCommands =
            outputCommandService ??
            OutputCommandService(
                outputOpenService: outputOpen
            )
        let outputJobCommands =
            outputJobCommandCoordinator ??
            OutputJobCommandCoordinator(
                outputCommandService:
                    outputCommands
            )
        let clipboardCommands =
            clipboardCommandService ??
            ClipboardCommandService()
        let clipboardViewerCommands =
            clipboardViewerCommandService ??
            ClipboardViewerCommandService(
                clipboardCommandService:
                    clipboardCommands
            )
        precondition(
            clipboardViewerCommands
                .clipboardCommandService ===
                clipboardCommands,
            "ClipboardViewerCommandService must use the manager's clipboard command service."
        )
        let clipboardMonitor =
            clipboardMonitorCoordinator ??
            ClipboardMonitorCoordinator()
        let galleryNumberCopies =
            galleryNumberCopyCoordinator ??
            GalleryNumberCopyCoordinator(
                clipboardCommandService:
                    clipboardCommands
            )
        let duplicateImageScans =
            duplicateImageScanCoordinator ??
            DuplicateImageScanCoordinator(
                service:
                    duplicateImageScanService
            )
        let sourceLinkCommands =
            sourceLinkCommandService ??
            SourceLinkCommandService(
                workspace: NSWorkspace.shared
            )
        let textViewerCommands =
            TextViewerCommandService(
                clipboardCommandService:
                    clipboardCommands,
                outputCommandService:
                    outputCommands,
                sourceLinkCommandService:
                    sourceLinkCommands
            )
        let workspaceItemCommands =
            workspaceItemCommandService ??
            WorkspaceItemCommandService(
                workspace: NSWorkspace.shared
            )
        let documentPanelCommands =
            documentPanelCommandService ??
            DocumentPanelCommandService()
        let confirmationDialogs =
            confirmationDialogService ??
            ConfirmationDialogService()
        let imageConversionDialogs =
            imageConversionDialogService ??
            ImageConversionDialogService()
        let applicationMenuCommands =
            applicationMenuCommandService ??
            ApplicationMenuCommandService()
        let queueCompletionCommands =
            queueCompletionCommandService ??
            QueueCompletionCommandService(
                workspaceItemCommandService:
                    workspaceItemCommands
            )
        let pdfOutput =
            pdfOutputService ??
            PDFOutputService(
                outputOpenService: outputOpen
            )
        let pdfJobState =
            pdfJobStateService ??
            PDFJobStateService()
        let archiveJobState =
            archiveJobStateService ??
            ArchiveJobStateService()
        let jobActionPolicy =
            queueJobActionPolicy ??
            QueueJobActionPolicy(
                outputService: output,
                outputOpenService: outputOpen
            )
        let externalOutputMetadata =
            externalToolOutputMetadataService ??
            ExternalToolOutputMetadataService()
        let ytdlpState =
            ytdlpJobStateService ??
            YTDLPJobStateService()
        let ytdlpProgressUpdates =
            ytdlpProgressUpdateService ??
            YTDLPProgressUpdateService()
        let ytdlpProgressDelivery =
            ytdlpProgressDeliveryService ??
            YTDLPProgressDeliveryService()
        let nativeTransferProgress =
            nativeTransferProgressService ??
            NativeTransferProgressService()
        let aria2State =
            aria2JobStateService ??
            Aria2JobStateService()
        let aria2RuntimeCommands =
            aria2RuntimeCommandCoordinator ??
            Aria2RuntimeCommandCoordinator()
        let customCommandState =
            customCommandJobStateService ??
            CustomCommandJobStateService()
        let toolRuntime = externalToolRuntime ?? ExternalToolRuntimeService()
        let toolInstallCoordinator =
            externalToolInstallCoordinator ??
            ExternalToolInstallCoordinator()
        let managedToolCommands =
            managedExternalToolCommandService ??
            ManagedExternalToolCommandService()
        let searchRequests =
            searchRequestCoordinator ??
            SearchRequestCoordinator()
        let searchResultFetcher =
            searchResultFetchService ??
            SearchResultFetchService()
        let searchExecution =
            searchExecutionFacade ??
            SearchExecutionFacade(
                requestCoordinator: searchRequests,
                fetchService: searchResultFetcher
            )
        let searchUICommands =
            SearchUICommandFacade(
                sourceLinkCommandService:
                    sourceLinkCommands,
                clipboardCommandService:
                    clipboardCommands,
                outputCommandService:
                    outputCommands
            )
        let resolverRegistry = sourceResolverRegistry ?? SourceResolverRegistry(
            niconicoLiveResolver: niconicoLiveResolver
        )
        let resolverExecutor = SourceResolverExecutor(registry: resolverRegistry)
        let executionRoutingService = SourceExecutionRoutingService(
            registry: resolverRegistry,
            executor: resolverExecutor
        )
        let executionDispatchService =
            sourceExecutionDispatchService ??
            SourceExecutionDispatchService()
        let planExecutionService = SourceResolverPlanExecutionService(
            executor: resolverExecutor,
            fallbackPolicy: sourceResolverFallbackPolicy
        )
        let pythonExecutionService = PythonPluginExecutionService()
        let pythonPluginCommands =
            pythonPluginCommandCoordinator ??
            PythonPluginCommandCoordinator()
        let resolverOptionsFactory = SourceResolverExecutionOptionsFactory()
        let jobExecutionCapabilitiesFactory =
            sourceJobExecutionCapabilitiesFactory ??
            SourceJobExecutionCapabilitiesFactory()
        let jobExecutionActionFactory =
            sourceJobExecutionActionFactory ??
            SourceJobExecutionActionFactory()
        let inputRoutingService = SourceInputRoutingService()
        let inputExecutionDispatchService =
            sourceInputExecutionDispatchService ??
            SourceInputExecutionDispatchService()
        let jobExecutionService =
            SourceJobExecutionService(
                inputRoutingService: inputRoutingService,
                inputExecutionDispatchService:
                    inputExecutionDispatchService,
                sourceRoutingService:
                    executionRoutingService,
                sourceExecutionDispatchService:
                    executionDispatchService
            )
        let jobPreparationService =
            resolvedDownloadJobPreparationService ??
            ResolvedDownloadJobPreparationService()
        let executionPreparationService =
            resolvedDownloadExecutionPreparationService ??
            ResolvedDownloadExecutionPreparationService(
                rangeService: resolvedDownloadRangeService,
                jobPreparationService: jobPreparationService
            )
        let requestHeaderService =
            siteRequestHeaderService ??
            SiteRequestHeaderService()
        let packageExecutionDispatchService =
            resolvedPackageExecutionDispatchService ??
            ResolvedPackageExecutionDispatchService()
        let executionFailurePolicy =
            downloadExecutionFailurePolicy ??
            DownloadExecutionFailurePolicy()
        let jobExecutionPipeline =
            SourceJobExecutionPipeline(
                executor: jobExecutionService,
                failurePolicy: executionFailurePolicy
            )
        let jobExecutionCoordinator =
            SourceJobExecutionCoordinator(
                requestFactory:
                    sourceJobExecutionRequestFactory,
                pipeline: jobExecutionPipeline
            )
        let executionJobStateService =
            downloadExecutionJobStateService ??
            DownloadExecutionJobStateService()
        let completedJobStateService =
            completedDownloadJobStateService ??
            CompletedDownloadJobStateService()
        let completedMetadataService =
            completedOutputMetadataService ??
            CompletedOutputMetadataService()
        let completedMetadataBackfillCoordinator =
            completedOutputMetadataBackfillCoordinator ??
            CompletedOutputMetadataBackfillCoordinator()
        let completedMetadataEnrichmentCoordinator =
            completedJobMetadataEnrichmentCoordinator ??
            CompletedJobMetadataEnrichmentCoordinator()
        let outputPreviewLoads =
            outputPreviewLoadCoordinator ??
            OutputPreviewLoadCoordinator()
        let outputImageConversions =
            outputImageConversionCoordinator ??
            OutputImageConversionCoordinator()
        let autoRecordMonitor =
            autoRecordMonitorCoordinator ??
            AutoRecordMonitorCoordinator()
        let autoRecordCheckCommands =
            autoRecordCheckCommandCoordinator ??
            AutoRecordCheckCommandCoordinator()
        let jobEditThumbnailLoads =
            jobEditThumbnailLoadCoordinator ??
            JobEditThumbnailLoadCoordinator()
        let jobEditThumbnailImages =
            jobEditThumbnailImageService ??
            JobEditThumbnailImageService()
        let queueRuns =
            queueRunCoordinator ??
            QueueRunCoordinator()
        let queueViewSelectionRestores =
            queueViewSelectionRestoreCoordinator ??
            QueueViewSelectionRestoreCoordinator()
        let publicIPLookup =
            publicIPLookupCoordinator ??
            PublicIPLookupCoordinator()
        let authenticationPolicy =
            sourceAuthenticationPolicy ??
            SourceAuthenticationPolicy()
        let authenticationBrowserCommands =
            authenticationBrowserCommandService ??
            AuthenticationBrowserCommandService(
                authenticationPolicy:
                    authenticationPolicy
            )
        precondition(
            authenticationBrowserCommands
                .authenticationPolicy ===
                authenticationPolicy,
            "AuthenticationBrowserCommandService must use the manager's authentication policy."
        )
        let browserWindowCommands =
            browserWindowCommandService ??
            BrowserWindowCommandService(
                authenticationPolicy:
                    authenticationPolicy,
                sourceLinkCommandService:
                    sourceLinkCommands
            )
        precondition(
            browserWindowCommands
                .authenticationPolicy ===
                authenticationPolicy &&
                browserWindowCommands
                .sourceLinkCommandService ===
                sourceLinkCommands,
            "BrowserWindowCommandService must use the manager's authentication and source-link services."
        )
        let authenticationVerification =
            sourceAuthenticationVerificationCoordinator ??
            SourceAuthenticationVerificationCoordinator()
        let cookieManagement =
            cookieManagementCoordinator ??
            CookieManagementCoordinator(
                service:
                    CookieManagementService(
                        sourceAuthenticationPolicy:
                            authenticationPolicy
                    )
            )
        let authenticationWaits =
            authenticationWaitCoordinator ??
            AuthenticationWaitCoordinator()
        let authenticationCookieImports =
            authenticationCookieImportService ??
            AuthenticationCookieImportService(
                authenticationPolicy:
                    authenticationPolicy,
                verificationCoordinator:
                    authenticationVerification,
                waitCoordinator:
                    authenticationWaits
            )
        precondition(
            authenticationCookieImports
                .authenticationPolicy ===
                authenticationPolicy &&
                authenticationCookieImports
                .verificationCoordinator ===
                authenticationVerification &&
                authenticationCookieImports
                .waitCoordinator ===
                authenticationWaits,
            "AuthenticationCookieImportService must use the manager's authentication services."
        )
        let authenticationJobWaits =
            authenticationJobWaitService ??
            AuthenticationJobWaitService(
                queueStore: queueState,
                waitCoordinator:
                    authenticationWaits
            )
        precondition(
            authenticationJobWaits.queueStore ===
                queueState &&
                authenticationJobWaits
                .waitCoordinator ===
                authenticationWaits,
            "AuthenticationJobWaitService must use the manager's queue and wait coordinator."
        )
        let sourceResolverAuthenticationDispatch =
            sourceResolverAuthenticationDispatchService ??
            SourceResolverAuthenticationDispatchService()
        let sourceResolverProgressJobState =
            sourceResolverProgressJobStateService ??
            SourceResolverProgressJobStateService()
        let sourceExecutionJobState =
            sourceExecutionJobStateService ??
            SourceExecutionJobStateService()
        let directFileJobCoordinator =
            DirectFileJobCoordinator(
                queueStore: queueState,
                jobStateService:
                    sourceExecutionJobState
            )
        let discordEmojiJobCoordinator =
            DiscordEmojiJobCoordinator(
                queueStore: queueState,
                jobStateService:
                    sourceExecutionJobState,
                resolver:
                    resolverRegistry
                    .discordEmojiResolver
            )
        let sourceResolverPlanJobCoordinator =
            SourceResolverPlanJobCoordinator(
                queueStore: queueState,
                jobStateService:
                    sourceExecutionJobState,
                planExecutionService:
                    planExecutionService
            )
        let sourceResolverJobContext =
            sourceResolverJobContextService ??
            SourceResolverJobContextService(
                queueStore: queueState,
                progressJobStateService:
                    sourceResolverProgressJobState,
                authenticationDispatchService:
                    sourceResolverAuthenticationDispatch
            )
        precondition(
            sourceResolverJobContext.queueStore ===
                queueState &&
                sourceResolverJobContext
                .progressJobStateService ===
                sourceResolverProgressJobState &&
                sourceResolverJobContext
                .authenticationDispatchService ===
                sourceResolverAuthenticationDispatch,
            "SourceResolverJobContextService must use the manager's queue and resolver services."
        )
        let nativeDelegationCoordinator =
            pythonNativeDelegationCoordinator ??
            PythonNativeDelegationCoordinator()
        let pythonSourceJobCoordinator =
            PythonSourceJobCoordinator(
                queueStore: queueState,
                jobStateService:
                    sourceExecutionJobState,
                executionService:
                    pythonExecutionService,
                nativeDelegationCoordinator:
                    nativeDelegationCoordinator
            )
        let hookRegistrationService =
            pythonHookRegistrationService ??
            PythonHookRegistrationService()
        let hookExecutionService =
            pythonHookExecutionService ??
            PythonHookExecutionService()
        let executionLogService =
            pythonExecutionLogService ??
            PythonExecutionLogService()
        let hookPreparationService =
            resolvedDownloadHookPreparationService ??
            ResolvedDownloadHookPreparationService()
        let hookJobApplicationService =
            pythonHookJobApplicationService ??
            PythonHookJobApplicationService()
        let startHookPipeline =
            sourceJobStartHookPipeline ??
            SourceJobStartHookPipeline(
                jobApplicationService:
                    hookJobApplicationService,
                failurePolicy:
                    executionFailurePolicy
            )
        let syntheticHookService =
            syntheticPythonDownloadHookService ??
            SyntheticPythonDownloadHookService()
        let originalInputService = OriginalInputExecutionService(
            registry: resolverRegistry,
            executor: resolverExecutor
        )
        let originalInputJobCoordinator =
            OriginalInputJobCoordinator(
                queueStore: queueState,
                jobStateService:
                    sourceExecutionJobState,
                executionService:
                    originalInputService
            )
        let genericPageService = GenericPageExecutionService(
            resolver: resolverRegistry.genericPageResolver
        )
        let genericPageJobCoordinator =
            GenericPageJobCoordinator(
                queueStore: queueState,
                jobStateService:
                    sourceExecutionJobState,
                executionService:
                    genericPageService
            )
        let commandService = appCommandService ?? AppCommandService(
            presentation: presentationStore
        )
        let quickAccessService =
            quickAccessCommandService ??
            QuickAccessCommandService()
        let shortcutCommandService =
            appShortcutCommandService ??
            AppShortcutCommandService()
        precondition(
            commandService.presentation === presentationStore,
            "AppCommandService must use the manager's AppPresentationStore."
        )
        self.presentation = presentationStore
        self.appStatusStore = appStatusState
        self.appCommandService = commandService
        self.appShortcutCommandService = shortcutCommandService
        self.quickAccessCommandService = quickAccessService
        self.settingsStore = settings
        self.searchStore = searchState
        self.libraryStore = libraryState
        self.queueStore = queueState
        self.queueEditorStore = queueEditorState
        self.duplicateImageStore = duplicateImages
        self.outputOperationStore = outputOperations
        self.externalToolStore = externalTools
        self.aria2Store = aria2StoreState
        self.pythonRuntimeStore = pythonRuntimeState
        self.autoRecordStore = autoRecordState
        self.networkStore = networkState
        self.cookieStatusStore = cookieStatus
        self.queueScheduler = scheduler
        self.queueExecutionService =
            queueExecution
        self.downloadCoordinator = coordinator
        self.assetDownloadExecutor = assetDownloadExecutor
        self.assetTransferService = assetTransferService
        self.mediaTransferCoordinator = mediaTransfer
        self.mediaConcatenationCoordinator = mediaConcatenation
        self.mediaRemuxCoordinator = mediaRemux
        self.mediaMuxCoordinator = mediaMux
        self.directSegmentTransferService =
            directSegmentTransferService
        self.assetDownloadJobStateService =
            assetJobState
        self.directTransferJobStateService =
            directTransferJobState
        self.resolvedPackageJobStateService =
            packageJobState
        self.resolvedFilesPackageCoordinator =
            filesPackageCoordinator
        self.resolvedConcatenationPackageCoordinator =
            concatenationPackageCoordinator
        self.resolvedMuxPackageCoordinator =
            muxPackageCoordinator
        self.resolvedGroupedPackageCoordinator =
            groupedPackageCoordinator
        self.niconicoLiveJobStateService =
            niconicoLiveJobState
        self.liveHLSJobStateService =
            liveHLSJobState
        self.liveHLSRecordingCoordinator =
            liveHLSRecordingCoordinator ??
            LiveHLSRecordingCoordinator()
        self.niconicoLiveRecordingCoordinator =
            niconicoLiveRecordingCoordinator ??
            NiconicoLiveRecordingCoordinator()
        self.resolvedDownloadRangeService =
            resolvedDownloadRangeService
        self.resolvedDownloadJobPreparationService =
            jobPreparationService
        self.resolvedDownloadExecutionPreparationService =
            executionPreparationService
        self.siteRequestHeaderService =
            requestHeaderService
        self.resolvedPackageExecutionDispatchService =
            packageExecutionDispatchService
        self.downloadExecutionFailurePolicy =
            executionFailurePolicy
        self.downloadExecutionJobStateService =
            executionJobStateService
        self.completedDownloadJobStateService =
            completedJobStateService
        self.completedOutputMetadataService =
            completedMetadataService
        self.completedOutputMetadataBackfillCoordinator =
            completedMetadataBackfillCoordinator
        self.completedJobMetadataEnrichmentCoordinator =
            completedMetadataEnrichmentCoordinator
        self.outputPreviewLoadCoordinator =
            outputPreviewLoads
        self.outputImageConversionCoordinator =
            outputImageConversions
        self.autoRecordMonitorCoordinator =
            autoRecordMonitor
        self.autoRecordCheckCommandCoordinator =
            autoRecordCheckCommands
        self.jobEditThumbnailLoadCoordinator =
            jobEditThumbnailLoads
        self.jobEditThumbnailImageService =
            jobEditThumbnailImages
        self.queueRunCoordinator =
            queueRuns
        self.queueViewSelectionRestoreCoordinator =
            queueViewSelectionRestores
        self.publicIPLookupCoordinator =
            publicIPLookup
        self.sourceAuthenticationPolicy =
            authenticationPolicy
        self.authenticationBrowserCommandService =
            authenticationBrowserCommands
        self.browserWindowCommandService =
            browserWindowCommands
        self.sourceAuthenticationVerificationCoordinator =
            authenticationVerification
        self.cookieManagementCoordinator =
            cookieManagement
        self.authenticationCookieImportService =
            authenticationCookieImports
        self.authenticationWaitCoordinator =
            authenticationWaits
        self.authenticationJobWaitService =
            authenticationJobWaits
        self.sourceResolverAuthenticationDispatchService =
            sourceResolverAuthenticationDispatch
        self.sourceResolverProgressJobStateService =
            sourceResolverProgressJobState
        self.sourceExecutionJobStateService =
            sourceExecutionJobState
        self.directFileJobCoordinator =
            directFileJobCoordinator
        self.discordEmojiJobCoordinator =
            discordEmojiJobCoordinator
        self.sourceResolverJobContextService =
            sourceResolverJobContext
        self.pythonNativeDelegationCoordinator =
            nativeDelegationCoordinator
        self.pythonHookRegistrationService =
            hookRegistrationService
        self.pythonHookExecutionService =
            hookExecutionService
        self.pythonExecutionLogService =
            executionLogService
        self.resolvedDownloadHookPreparationService =
            hookPreparationService
        self.pythonHookJobApplicationService =
            hookJobApplicationService
        self.syntheticPythonDownloadHookService =
            syntheticHookService
        self.sourceJobExecutionRequestFactory =
            sourceJobExecutionRequestFactory
        self.sourceJobExecutionCapabilitiesFactory =
            jobExecutionCapabilitiesFactory
        self.sourceJobExecutionActionFactory =
            jobExecutionActionFactory
        self.persistenceService = persistence
        self.outputService = output
        self.outputNamingService = outputNamingService
        self.outputOpenService = outputOpen
        self.outputCommandService = outputCommands
        self.outputJobCommandCoordinator =
            outputJobCommands
        self.clipboardMonitorCoordinator =
            clipboardMonitor
        self.clipboardCommandService =
            clipboardCommands
        self.clipboardViewerCommandService =
            clipboardViewerCommands
        self.lastClipboardChangeCount =
            clipboardCommands.currentChangeCount
        self.galleryNumberCopyCoordinator =
            galleryNumberCopies
        self.outputPathRepairService =
            outputPathRepairService
        self.duplicateImageScanService =
            duplicateImageScanService
        self.duplicateImageScanCoordinator =
            duplicateImageScans
        self.sourceLinkCommandService =
            sourceLinkCommands
        self.textViewerCommandService =
            textViewerCommands
        self.workspaceItemCommandService =
            workspaceItemCommands
        self.documentPanelCommandService =
            documentPanelCommands
        self.confirmationDialogService =
            confirmationDialogs
        self.imageConversionDialogService =
            imageConversionDialogs
        self.applicationMenuCommandService =
            applicationMenuCommands
        self.interfaceFontService =
            interfaceFonts
        self.queueCompletionCommandService =
            queueCompletionCommands
        self.pdfOutputService = pdfOutput
        self.pdfJobStateService = pdfJobState
        self.archiveJobStateService = archiveJobState
        self.queueJobActionPolicy = jobActionPolicy
        self.externalToolOutputMetadataService =
            externalOutputMetadata
        self.ytdlpJobStateService = ytdlpState
        self.ytdlpProgressUpdateService =
            ytdlpProgressUpdates
        self.ytdlpProgressDeliveryService =
            ytdlpProgressDelivery
        self.nativeTransferProgressService =
            nativeTransferProgress
        self.aria2JobStateService = aria2State
        self.aria2RuntimeCommandService =
            aria2RuntimeCommandService
        self.aria2RuntimeCommandCoordinator =
            aria2RuntimeCommands
        self.customCommandJobStateService =
            customCommandState
        self.externalToolRuntime = toolRuntime
        self.externalToolInstallCoordinator =
            toolInstallCoordinator
        self.managedExternalToolCommandService =
            managedToolCommands
        self.searchRequestCoordinator =
            searchRequests
        self.searchResultFetchService =
            searchResultFetcher
        self.searchExecutionFacade =
            searchExecution
        self.searchUICommandFacade =
            searchUICommands
        self.sourceResolverRegistry = resolverRegistry
        self.sourceResolverExecutor = resolverExecutor
        self.sourceExecutionRoutingService = executionRoutingService
        self.sourceExecutionDispatchService = executionDispatchService
        self.sourceResolverPlanExecutionService = planExecutionService
        self.sourceResolverPlanJobCoordinator =
            sourceResolverPlanJobCoordinator
        self.pythonPluginExecutionService = pythonExecutionService
        self.pythonSourceJobCoordinator =
            pythonSourceJobCoordinator
        self.pythonPluginCommandCoordinator =
            pythonPluginCommands
        self.sourceResolverExecutionOptionsFactory = resolverOptionsFactory
        self.sourceInputRoutingService = inputRoutingService
        self.sourceInputExecutionDispatchService =
            inputExecutionDispatchService
        self.sourceJobExecutionService =
            jobExecutionService
        self.sourceJobExecutionPipeline =
            jobExecutionPipeline
        self.sourceJobExecutionCoordinator =
            jobExecutionCoordinator
        self.sourceJobStartHookPipeline =
            startHookPipeline
        self.originalInputExecutionService = originalInputService
        self.originalInputJobCoordinator =
            originalInputJobCoordinator
        self.genericPageExecutionService = genericPageService
        self.genericPageJobCoordinator =
            genericPageJobCoordinator
        self.sourceResolverFallbackPolicy = sourceResolverFallbackPolicy
        let defaults = UserDefaults.standard
        var loadedUserData = persistence.userData
        var removedTransientTestRecords = 0
        if Self.shouldCleanTransientTestRecordsAtStartup {
            let queueCountBeforeTestArtifactCleanup = loadedUserData.queue.count
            let historyCountBeforeTestArtifactCleanup = loadedUserData.history.count
            loadedUserData.queue.removeAll {
                Self.isTransientTestRecord(source: $0.source, outputPath: $0.outputPath)
            }
            loadedUserData.history.removeAll {
                Self.isTransientTestRecord(source: $0.source, outputPath: $0.outputPath)
            }
            removedTransientTestRecords =
                queueCountBeforeTestArtifactCleanup - loadedUserData.queue.count +
                historyCountBeforeTestArtifactCleanup - loadedUserData.history.count
        }
        let migratedQueueOrder = loadedUserData.queueOrderVersion < 2
        if migratedQueueOrder {
            loadedUserData.queue = Self.migratedNewestFirstQueue(loadedUserData.queue)
            loadedUserData.queueOrderVersion = 2
        }
        if migratedQueueOrder || removedTransientTestRecords > 0 {
            _ = persistence.save(loadedUserData)
        }
        var restoredJobs = loadedUserData.queue.map { job in
            Self.isPendingQueueRemoval(job) ? job : Self.restoredQueueJob(job)
        }
        let restoredGroups = QueueGroupNormalizationService.normalizedGroups(
            loadedUserData.queueGroups,
            jobs: &restoredJobs,
            groupIDMetadataKey: QueueJobMetadataPolicy.groupIDMetadataKey
        )
        let migratedQueueGroups = restoredGroups != loadedUserData.queueGroups || restoredJobs != loadedUserData.queue
        loadedUserData.queue = restoredJobs
        loadedUserData.queueGroups = restoredGroups
        persistence.replaceUserData(loadedUserData)
        presentationStore.inputText = loadedUserData.inputTextDraft
        presentationStore.inputCursorUTF16Offset = (loadedUserData.inputTextDraft as NSString).length
        libraryState.replaceBookmarks(with: loadedUserData.bookmarks)
        libraryState.replaceHistory(with: loadedUserData.history)
        queueState.replace(with: QueueStoreSnapshot(
            jobs: restoredJobs,
            queueGroups: restoredGroups
        ))
        libraryState.replaceSiteRules(with: loadedUserData.siteRules)
        queueState.replaceQueueFilterBookmarks(
            with: loadedUserData.queueFilterBookmarks
        )
        searchState.replaceSearchBookmarks(
            with: loadedUserData.searchBookmarks
        )
        let loadedSearchProviders = loadedUserData.searchProviders
        searchState.replaceSearchProviders(with: loadedSearchProviders)
        searchState.selectedSearchProviderID =
            loadedSearchProviders.first?.id
            ?? SearchProvider.defaultProviders[0].id
        let savedAutoRemoveHookCommand = settings.autoRemoveHookCommand
        appStatusState.setAutoRemoveHookStatus(
            savedAutoRemoveHookCommand.trimmed.isEmpty
                ? "Auto-remove Hook Off"
                : "Auto-remove Hook Ready"
        )
        presentationStore.showingFloatingMonitor = Self.environmentBool("HITOMI_NATIVE_SHOW_FLOATING_MONITOR")
            ?? (defaults.object(forKey: "showingFloatingMonitor") as? Bool ?? false)
        presentationStore.shortcutEditorDraft =
            settings.shortcut(for: .pasteURLs)
        presentationStore.statusColorDraftPalette =
            settings.jobStatusColorPalette
        if let clipboardMonitorOverride = Self.environmentBool(
            "HITOMI_NATIVE_CLIPBOARD_MONITOR_ENABLED"
        ) {
            settings.clipboardMonitorEnabled = clipboardMonitorOverride
        }
        appStatusState.setQueueCompletionActionStatus(
            Self.queueCompletionActionStatusText(
                for: settings.queueCompletionAction
            )
        )
        networkState.setDPIBypassSnapshot(browserDPIBypassService.snapshot)
        let restoredAutoRecordEnabled = Self.environmentBool("HITOMI_NATIVE_AUTO_RECORD_ENABLED")
            ?? (defaults.object(forKey: "autoRecordEnabled") as? Bool ?? false)
        let restoredAutoRecordPaused = defaults.object(forKey: "autoRecordPaused") as? Bool ?? false
        let restoredAutoRecordURLsText = defaults.string(forKey: "autoRecordURLsText") ?? ""
        let savedAutoRecordInterval = defaults.object(forKey: "autoRecordIntervalMinutes") as? Int ?? 10
        let restoredAutoRecordInterval = String(
            Self.normalizedAutoRecordIntervalMinutes(
                from: String(savedAutoRecordInterval)
            )
        )
        autoRecordState.restore(
            isEnabled: restoredAutoRecordEnabled,
            isPaused: restoredAutoRecordPaused,
            urlsText: restoredAutoRecordURLsText,
            intervalMinutesString: restoredAutoRecordInterval,
            status: restoredAutoRecordEnabled
                ? (restoredAutoRecordPaused
                    ? "Automatic Recording Paused"
                    : "Automatic Recording Waiting")
                : "Automatic Recording Off"
        )
        _ = networkTrafficSampler
        _ = loadSiteRulePluginManifests()
        preparePythonScriptDirectories()
        pythonRuntimeState.replaceScriptPlugins(
            with: PythonScriptPluginStore.load()
        )
        refreshPythonScriptStatus()
        self.pythonPluginCommandCoordinator.begin { [weak self] in
            await self?.runEnabledPythonToolPlugins()
        }
        if migratedQueueOrder || migratedQueueGroups {
            persistUserData()
        }
        browserDPIBypassService.onUpdate = { [weak self] snapshot in
            guard let self else { return }
            self.networkStore.setDPIBypassSnapshot(snapshot)
            if snapshot.phase == .failed || snapshot.phase == .conflictingSystemProxy {
                self.settingsStore.dpiBypassMode = .off
                self.settingsStore.persistDPIBypassMode()
                self.addSummary = snapshot.diagnostic.isEmpty
                    ? "DPI Bypass Failed"
                    : snapshot.diagnostic
            }
        }
        if settings.dpiBypassMode.usesLocalProxy {
            browserDPIBypassService.start(
                mode: settings.dpiBypassMode,
                openSystemSettings: false
            )
        }
        if self.settingsStore.clipboardMonitorEnabled {
            startClipboardMonitor()
        }
        if self.settingsStore.httpAPIEnabled {
            startHTTPAPIServer()
        }
        if Self.environmentBool("HITOMI_NATIVE_BROWSER_EXTENSION_ENABLED") ?? Self.browserExtensionEnabledByDefault {
            startBrowserExtensionServer()
        }
        syncAutoRecordMonitor()
        recordActivity("App started", category: "App")
        cookieStatus.setSummary(
            CookieStore.hasPersistedStore
                ? "Saved cookies (loaded when needed)"
                : "No cookies"
        )
        if CookieStore.hasPersistedStore {
            self.cookieManagementCoordinator.begin(
                .loadPersistedSummary
            ) { [weak self] outcome in
                self?.cookieStatusStore.setSummary(
                    outcome.cookieSummary
                )
            }
        }
        if self.queueStore.jobs.contains(where: Self.isPendingQueueRemoval) {
            flushPendingQueueRemovals()
            persistQueue()
        }
        self.completedOutputMetadataBackfillCoordinator.start { [weak self] in
            await self?.backfillCompletedOutputMetadata()
        }
        restoreScheduledRetries()
    }

    private nonisolated static func environmentBool(_ key: String) -> Bool? {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmed.lowercased(),
              !raw.isEmpty else {
            return nil
        }
        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return nil
    }

    private nonisolated static var browserExtensionEnabledByDefault: Bool {
        #if TESTING
        false
        #else
        true
        #endif
    }

    private nonisolated static func environmentPort(_ key: String) -> String? {
        guard let raw = ProcessInfo.processInfo.environment[key]?.trimmed,
              let port = UInt16(raw),
              port > 0 else {
            return nil
        }
        return String(port)
    }

    deinit {
        HTTPClient.shared.resumeAllTransfers()
        externalToolRuntime.resumeAllProcessesForQueue()
        externalToolRuntime.terminateAllProcesses()
        sleepPreventionAssertion.release()
        localAPIServerCoordinator.stop()
        browserExtensionServer?.stop()
    }

    func prepareForTermination() {
        guard !isPreparingForTermination else { return }
        isPreparingForTermination = true
        queueStore.setQueueEnabled(false)
        queueStore.setRunning(false)

        queueRunCoordinator.cancelAndClear()
        queueViewSelectionRestoreCoordinator
            .cancelAndClear()
        cancelAllRunningJobTasks()
        authenticationWaitCoordinator.resumeAll()
        sourceAuthenticationVerificationCoordinator
            .cancelAll()
        cookieManagementCoordinator.cancelAll()
        completedOutputMetadataBackfillCoordinator.cancel()
        completedJobMetadataEnrichmentCoordinator
            .cancelAll()
        autoRecordMonitorCoordinator.cancelAndClear()
        autoRecordCheckCommandCoordinator.cancelAll()
        externalToolInstallCoordinator.cancelAndClear()
        outputPreviewLoadCoordinator.cancelAndClear()
        outputJobCommandCoordinator.cancelAll()
        galleryNumberCopyCoordinator
            .cancelAndClear()
        duplicateImageScanCoordinator
            .cancelAndClear()
        aria2RuntimeCommandCoordinator.cancelAll()
        pythonPluginCommandCoordinator.cancelAll()
        searchExecutionFacade.cancel()
        searchStore.isSearching = false
        publicIPLookupCoordinator.cancelAndClear()
        networkStore.setRefreshingPublicIP(false)
        autoRecordStore.setChecking(false)
        cancelAllScheduledRestarts()

        aria2Store.clearRuntimePausedJobs()
        externalToolRuntime.terminateAllProcesses(clearState: true)
        HTTPClient.shared.resumeAllTransfers()
        externalToolRuntime.resumeAllProcessesForQueue()

        releaseSleepPreventionAssertion()
        stopHTTPAPIServer()
        stopBrowserExtensionServer()
        externalToolRuntime.prepareDPIBypassForTermination()
        stopClipboardMonitor()
        normalizeActiveQueueOrder()
        settingsStore.persistSourceFileNameTemplates()
        settingsStore.persistPawchive()
        settingsStore.persistQuickAccessItems()
        settingsStore.persistWindowAppearance()
        persistUserData()
    }

    func activityLogText(entries: [ActivityLogEntry]? = nil) -> String {
        Self.activityLogText(entries ?? appStatusStore.activityLog)
    }

    func outputDirectoryEntries(fileManager: FileManager = .default) -> [OutputDirectoryEntry] {
        OutputDirectoryCatalogService.entries(
            jobs: queueStore.jobs,
            history: libraryStore.history,
            fileManager: fileManager
        )
    }

    func outputDirectoriesText(
        entries: [OutputDirectoryEntry]? = nil,
        language: AppInterfaceLanguage = AppLocalization.currentLanguage()
    ) -> String {
        OutputDirectoryCatalogService.text(
            entries: entries ?? outputDirectoryEntries(),
            language: language
        )
    }

    func metadataFinderResults(
        field: MetadataFinderField? = nil,
        query: String? = nil,
        mode: MetadataFinderMode? = nil,
        limit: Int = 500
    ) -> [MetadataFinderResult] {
        MetadataExplorerService.finderResults(
            jobs: queueStore.jobs,
            history: libraryStore.history,
            field: field ?? searchStore.metadataFinderField,
            query: query ?? searchStore.metadataFinderQuery,
            mode: mode ?? searchStore.metadataFinderMode,
            limit: limit
        )
    }

    func metadataAnalysisEntries(
        field: MetadataAnalysisField? = nil,
        limit: Int = 500
    ) -> [MetadataAnalysisEntry] {
        MetadataExplorerService.analysisEntries(
            jobs: queueStore.jobs,
            history: libraryStore.history,
            field: field ?? searchStore.metadataAnalysisField,
            limit: limit
        )
    }

    func applyMetadataFinderResult(_ result: MetadataFinderResult) {
        searchStore.searchQuery = Self.metadataFinderSearchToken(result)
        addSummary = "Finder result applied"
    }

    func applyMetadataAnalysisEntry(_ entry: MetadataAnalysisEntry) {
        searchStore.searchQuery = Self.metadataAnalysisSearchToken(entry)
        addSummary = "Analysis result applied"
    }

    private func recordActivity(_ message: String, category: String) {
        appStatusStore.recordActivity(message, category: category)
    }

    nonisolated static func activityLogText(_ entries: [ActivityLogEntry]) -> String {
        entries.map { entry in
            "[\(apiDateString(entry.timestamp))] [\(entry.category)] \(entry.message)"
        }.joined(separator: "\n")
    }

    nonisolated static func outputDirectoryPath(forOutputPath outputPath: String, fileManager: FileManager = .default) -> String? {
        OutputDirectoryCatalogService.directoryPath(
            forOutputPath: outputPath,
            fileManager: fileManager
        )
    }

    nonisolated static func metadataFinderKeys(for field: MetadataFinderField) -> [String] {
        MetadataExplorerService.finderKeys(for: field)
    }

    nonisolated static func metadataFinderValues(field: MetadataFinderField, metadata: [String: String]) -> [String] {
        MetadataExplorerService.finderValues(
            field: field,
            metadata: metadata
        )
    }

    nonisolated static func metadataAnalysisKeys(for field: MetadataAnalysisField) -> [String] {
        MetadataExplorerService.analysisKeys(for: field)
    }

    nonisolated static func metadataAnalysisValues(field: MetadataAnalysisField, metadata: [String: String]) -> [String] {
        MetadataExplorerService.analysisValues(
            field: field,
            metadata: metadata
        )
    }

    nonisolated static func metadataFinderSearchToken(_ result: MetadataFinderResult) -> String {
        MetadataExplorerService.finderSearchToken(result)
    }

    nonisolated static func metadataAnalysisSearchToken(_ entry: MetadataAnalysisEntry) -> String {
        MetadataExplorerService.analysisSearchToken(entry)
    }

    private var queueOrderedJobIndices: [Int] {
        queueScheduler.orderedIndices(for: queueStore.jobs)
    }

    private var queueOrderedJobs: [DownloadJob] {
        queueOrderedJobIndices.map { queueStore.jobs[$0] }
    }

    private var visibleQueueOrderedJobIndices: [Int] {
        queueOrderedJobIndices.filter { !Self.isPendingQueueRemoval(queueStore.jobs[$0]) }
    }

    private var visibleQueueOrderedJobs: [DownloadJob] {
        visibleQueueOrderedJobIndices.map { queueStore.jobs[$0] }
    }

    func queueOrderIndex(for job: DownloadJob) -> Int? {
        queueOrderedJobIndices.firstIndex { queueStore.jobs[$0].id == job.id }
    }

    nonisolated static func queueStatusGroupSummaryText(
        jobs inputJobs: [DownloadJob],
        filteredJobs: [DownloadJob],
        filterActive: Bool
    ) -> String {
        QueueListPresentationService.statusSummaryText(
            jobs: inputJobs,
            filteredJobs: filteredJobs,
            filterActive: filterActive
        )
    }

    func setQueueSortMode(_ mode: QueueSortMode) {
        settingsStore.queueSortMode = mode
        settingsStore.persistQueuePresentation()
        addSummary = mode == .manual ? "Queue sort: manual" : "Queue sort: \(mode.label)"
    }

    func setQueueSortDescending(_ descending: Bool) {
        settingsStore.queueSortDescending = descending
        settingsStore.persistQueuePresentation()
        addSummary = descending ? "Queue sort descending" : "Queue sort ascending"
    }

    func setSearchResultSortMode(_ mode: SearchResultSortMode) {
        settingsStore.searchResultSortMode = mode
        settingsStore.persistSearchResultPreferences()
        addSummary = mode == .manual ? "Search result sort: manual" : "Search result sort: \(mode.label)"
    }

    func setSearchResultKnownFilter(_ filter: SearchResultKnownFilter) {
        settingsStore.searchResultKnownFilter = filter
        settingsStore.persistSearchResultPreferences()
        addSummary = "Search filter: \(filter.label)"
    }

    func setSearchResultSortDescending(_ descending: Bool) {
        settingsStore.searchResultSortDescending = descending
        settingsStore.persistSearchResultPreferences()
        addSummary = descending ? "Search result sort descending" : "Search result sort ascending"
    }

    func statisticsSnapshot() -> AppStatistics {
        let generatedAt = Date()
        let outputURLs = statisticsOutputURLs()
        let outputStatistics = Self.outputStatistics(for: outputURLs)
        let duplicateExtraFileCount = duplicateImageStore.duplicateFileCount
        let appInfo = AppDiagnosticInfoService.bundleInfo()
        let diskStatus = Self.diskSpaceStatus(destinationPath: settingsStore.destinationPath, jobs: queueStore.jobs)
        let downloadSpeed = currentDownloadSpeedBytesPerSecond()
        let downloadedSinceLaunch = downloadedSinceAppStartByteCount()
        let uploadSpeed = currentUploadSpeedBytesPerSecond()

        return AppStatistics(
            generatedAt: generatedAt,
            appStartedAt: appStartedAt,
            appUptimeSeconds: max(0, generatedAt.timeIntervalSince(appStartedAt)),
            appName: appInfo.name,
            appVersion: appInfo.displayVersion,
            appBuild: appInfo.build,
            bundleIdentifier: appInfo.bundleIdentifier,
            minimumSystemVersion: appInfo.minimumSystemVersion,
            operatingSystemVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            applicationSupportPath: AppPaths.applicationSupportDirectory.path,
            userDataPath: AppPaths.userDataURL.path,
            totalJobs: queueStore.jobs.count,
            queuedJobs: queueStore.jobs.filter { $0.status == .queued }.count,
            resolvingJobs: queueStore.jobs.filter { $0.status == .resolving }.count,
            downloadingJobs: queueStore.jobs.filter { $0.status == .downloading }.count,
            finishedJobs: queueStore.jobs.filter { $0.status == .finished }.count,
            failedJobs: queueStore.jobs.filter { $0.status == .failed }.count,
            cancelledJobs: queueStore.jobs.filter { $0.status == .cancelled }.count,
            pinnedJobs: queueStore.jobs.filter(\.isPinned).count,
            lockedJobs: queueStore.jobs.filter(\.isLocked).count,
            historyCount: libraryStore.history.count,
            bookmarkCount: libraryStore.bookmarks.count,
            queueFilterBookmarkCount: queueStore.queueFilterBookmarks.count,
            siteRuleCount: libraryStore.siteRules.count,
            enabledSiteRuleCount:
                libraryStore.siteRules.filter(\.isEnabled).count,
            searchProviderCount: searchStore.searchProviders.count,
            duplicateGroupCount: duplicateImageStore.groups.count,
            duplicateExtraFileCount: duplicateExtraFileCount,
            outputRootPath: settingsStore.destinationPath,
            outputPathCount: outputURLs.count,
            outputFileCount: outputStatistics.fileCount,
            outputDirectoryCount: outputStatistics.directoryCount,
            outputByteCount: outputStatistics.byteCount,
            outputPathAnalysisSkippedCount: outputStatistics.skippedPathAnalysisCount,
            destinationAvailableByteCount: diskStatus.availableByteCount,
            destinationTotalByteCount: diskStatus.totalByteCount,
            estimatedQueuedByteCount: diskStatus.estimatedRequiredByteCount,
            destinationPathAnalysisSkipped: diskStatus.pathAnalysisSkipped,
            diskSpaceWarning: diskStatus.warning,
            autoRemoveFinishedJobs: settingsStore.autoRemoveFinishedJobs,
            autoRemoveHookCommand: settingsStore.autoRemoveHookCommand.trimmed,
            autoRemoveHookStatus: appStatusStore.autoRemoveHookStatus,
            showDownloadDate: settingsStore.showDownloadDate,
            numberPlaylistFiles: settingsStore.numberPlaylistFiles,
            uiScale: settingsStore.uiScale.label,
            jobConcurrency: Self.normalizedJobConcurrency(settingsStore.jobConcurrency),
            fileConcurrency: max(1, min(24, settingsStore.fileConcurrency)),
            publicIPStatus: networkStore.publicIPStatus,
            youtubeDownloadThumbnail: settingsStore.youtubeDownloadThumbnail,
            youtubeReversePlaylist: settingsStore.youtubeReversePlaylist,
            youtubeUseUploadDateForFileModificationTime: settingsStore.youtubeUseUploadDateForFileModificationTime,
            youtubeDownloadAutoSubtitles: settingsStore.youtubeDownloadAutoSubtitles,
            youtubeSubtitleLanguages: settingsStore.youtubeSubtitleLanguages.trimmed,
            youtubeEmbedChapters: settingsStore.youtubeEmbedChapters,
            youtubeVideoCodecSort: YouTubeVideoCodec.priorityLabel(settingsStore.youtubeVideoCodecPriority),
            youtubePreferEnhancedBitrate: settingsStore.youtubePreferEnhancedBitrate,
            youtubePreferredResolution: settingsStore.youtubePreferredResolution.trimmed,
            youtubePreferredAudioLanguage: settingsStore.youtubePreferredAudioLanguage.trimmed,
            downloadSpeedBytesPerSecond: downloadSpeed,
            downloadedSinceLaunchByteCount: downloadedSinceLaunch,
            uploadSpeedBytesPerSecond: uploadSpeed,
            aria2MaxDownloadLimit: aria2Store.maxDownloadLimit.trimmed,
            aria2MaxUploadLimit: aria2Store.maxUploadLimit.trimmed,
            aria2SeedTimeMinutes: aria2Store.seedTimeMinutes.trimmed,
            aria2SeedRatio: aria2Store.seedRatio.trimmed,
            aria2AnonymousMode: aria2Store.anonymousMode,
            httpAPIEnabled: settingsStore.httpAPIEnabled,
            clipboardMonitorEnabled: settingsStore.clipboardMonitorEnabled,
            notifyWhenJobCompletes: settingsStore.notifyWhenJobCompletes,
            notifyWhenQueueCompletes: settingsStore.notifyWhenQueueCompletes,
            playSoundWhenJobCompletes: settingsStore.playSoundWhenJobCompletes,
            playSoundOnClipboardAdd: settingsStore.playSoundOnClipboardAdd,
            queueCompletionAction: settingsStore.queueCompletionAction.label,
            queueCompletionActionStatus:
                appStatusStore.queueCompletionActionStatus,
            preventSleepWhileDownloading: settingsStore.preventSleepWhileDownloading,
            sleepPreventionActive: appStatusStore.sleepPreventionActive,
            historyEnabled: settingsStore.historyEnabled,
            externalTools: externalToolStatuses()
        )
    }

    nonisolated static func normalizedJobConcurrency(_ value: Int) -> Int {
        QueueScheduler.normalizedTaskLimit(value)
    }

    nonisolated static let defaultJobConcurrency = 4

    nonisolated static var shouldCleanTransientTestRecordsAtStartup: Bool {
        let environment = ProcessInfo.processInfo.environment
        if environment["HITOMI_NATIVE_ENABLE_TRANSIENT_TEST_CLEANUP"] == "1" {
            return true
        }
        return environment["HITOMI_NATIVE_SUPPORT_DIR"]?.isEmpty != false &&
            environment["HITOMI_NATIVE_USER_DATA"]?.isEmpty != false
    }

    nonisolated static func isTransientTestDestinationPath(_ path: String) -> Bool {
        SettingsStore.isTransientTestDestinationPath(path)
    }

    nonisolated static func isTransientTestRecord(source: String, outputPath: String) -> Bool {
        if isTransientTestDestinationPath(outputPath) {
            return true
        }
        guard let host = URL(string: source.trimmed)?.host?.lowercased() else {
            return false
        }
        return host == "test" || host.hasSuffix(".test")
    }

    nonisolated static func migratedNewestFirstQueue(_ inputJobs: [DownloadJob]) -> [DownloadJob] {
        let pinned = inputJobs.filter(\.isPinned)
        let unpinned = inputJobs.filter { !$0.isPinned }
        return pinned + Array(unpinned.reversed())
    }

    func currentDownloadSpeedBytesPerSecond() -> Int64? {
        networkTrafficSampler.currentDownloadSpeedBytesPerSecond()
    }

    func downloadedSinceAppStartByteCount() -> Int64? {
        networkTrafficSampler.downloadedSinceAppStartByteCount()
    }

    func currentUploadSpeedBytesPerSecond() -> Int64? {
        networkTrafficSampler.currentUploadSpeedBytesPerSecond()
    }

    nonisolated static func uploadSpeedBytesPerSecond(previous: NetworkTrafficSample?, current: NetworkTrafficSample) -> Int64? {
        NetworkTrafficSampler.speedBytesPerSecond(
            previous: previous,
            current: current
        )
    }

    nonisolated static func networkSpeedBytesPerSecond(previous: NetworkTrafficSample?, current: NetworkTrafficSample) -> Int64? {
        NetworkTrafficSampler.speedBytesPerSecond(
            previous: previous,
            current: current
        )
    }

    func artistRecommendations(limit: Int = 20) -> [ArtistRecommendation] {
        Self.artistRecommendations(
            jobs: queueStore.jobs,
            history: libraryStore.history,
            bookmarks: libraryStore.bookmarks,
            limit: limit
        )
    }

    func visibleArtistRecommendations(limit: Int = 60) -> [ArtistRecommendation] {
        let recommendations = artistRecommendations(
            limit: max(limit, 1) +
                searchStore.hiddenArtistRecommendationIDs.count
        )
        return searchStore.visibleArtistRecommendations(
            from: recommendations,
            limit: limit
        )
    }

    func applyArtistRecommendation(_ recommendation: ArtistRecommendation) {
        searchStore.searchQuery = recommendation.queryToken
        selectHitomiSearchProvider()
        addSummary = "Artist recommendation applied"
    }

    @discardableResult
    func copyArtistRecommendation(_ recommendation: ArtistRecommendation) -> Bool {
        let copied =
            clipboardCommandService.copyText(
                recommendation.name
            )
        addSummary = copied ? "Artist copied" : "Artist copy failed"
        return copied
    }

    func hideArtistRecommendation(_ recommendation: ArtistRecommendation) {
        searchStore.hideArtistRecommendation(id: recommendation.id)
        addSummary = "Artist recommendation hidden"
    }

    func clearHiddenArtistRecommendations() {
        searchStore.clearHiddenArtistRecommendations()
        addSummary = "Artist recommendations restored"
    }

    func clearArtistRecommendationFilter() {
        searchStore.clearArtistRecommendationFilter()
    }

    func refreshHitomiTasterReferenceCount() {
        searchStore.hitomiTasterReferenceCount =
            Self.hitomiTasterReferenceCount(
                jobs: queueStore.jobs,
                history: libraryStore.history,
                bookmarks: libraryStore.bookmarks
            )
    }

    func openHitomiTaster() {
        refreshHitomiTasterReferenceCount()
        if searchStore.hitomiTasterResults.isEmpty {
            searchStore.hitomiTasterStatus =
                searchStore.hitomiTasterReferenceCount > 0
                ? "\(searchStore.hitomiTasterReferenceCount) reference works ready"
                : "No reference works"
            searchStore.hitomiTasterProgress = 0
        }
        appCommandService.openAuxiliaryWindow(.hitomiTaster)
    }

    func trainHitomiTaster(limit: Int = 80) {
        refreshHitomiTasterReferenceCount()
        let model = searchStore.hitomiTasterModel
        searchStore.hitomiTasterTrainingLog = [
            "Model: \(model.originalLabel)",
            "Reading data...",
            "Reference works: \(searchStore.hitomiTasterReferenceCount)"
        ]
        searchStore.hitomiTasterProgress = 0.2

        guard searchStore.hitomiTasterReferenceCount >=
                model.minimumReferenceCount else {
            searchStore.hitomiTasterResults = []
            searchStore.hitomiTasterAccuracy = 0
            searchStore.hitomiTasterStatus =
                "Need at least \(model.minimumReferenceCount) reference works"
            searchStore.hitomiTasterTrainingLog.append(
                "[ERROR] Need at least \(model.minimumReferenceCount) works."
            )
            addSummary = searchStore.hitomiTasterStatus
            return
        }

        searchStore.hitomiTasterTrainingLog.append(
            "Analyzing local metadata..."
        )
        searchStore.hitomiTasterProgress = 0.4
        let recommendations = artistRecommendations(limit: max(limit * 3, 120))

        searchStore.hitomiTasterTrainingLog.append("Building model...")
        searchStore.hitomiTasterProgress = 0.62
        searchStore.hitomiTasterTrainingLog.append("Training...")
        searchStore.hitomiTasterProgress = 0.82

        searchStore.hitomiTasterResults = Self.hitomiTasterResults(
            recommendations: recommendations,
            model: model,
            referenceCount: searchStore.hitomiTasterReferenceCount,
            limit: limit
        )
        searchStore.hitomiTasterAccuracy = Self.hitomiTasterAccuracy(
            results: searchStore.hitomiTasterResults,
            referenceCount: searchStore.hitomiTasterReferenceCount,
            model: model
        )
        searchStore.hitomiTasterProgress = 1
        searchStore.hitomiTasterStatus = searchStore.hitomiTasterResults.isEmpty
            ? "No artists classified"
            : "\(searchStore.hitomiTasterResults.count) artists classified"
        searchStore.hitomiTasterTrainingLog.append("Classifying artists...")
        searchStore.hitomiTasterTrainingLog.append(
            "Accuracy \(String(format: "%.2f", searchStore.hitomiTasterAccuracy))%"
        )
        searchStore.hitomiTasterTrainingLog.append("Complete")
        addSummary = searchStore.hitomiTasterStatus
    }

    func visibleHitomiTasterResults(limit: Int = 200) -> [HitomiTasterResult] {
        searchStore.visibleHitomiTasterResults(limit: limit)
    }

    func applyHitomiTasterResult(_ result: HitomiTasterResult) {
        applyArtistRecommendation(result.recommendation)
        addSummary = "Hitomi Taster result applied"
    }

    @discardableResult
    func copyHitomiTasterResult(_ result: HitomiTasterResult) -> Bool {
        copyArtistRecommendation(result.recommendation)
    }

    func hideHitomiTasterResult(_ result: HitomiTasterResult) {
        hideArtistRecommendation(result.recommendation)
    }

    func clearHitomiTasterFilter() {
        searchStore.clearHitomiTasterFilter()
    }

    func exportHitomiTasterResults() {
        guard !searchStore.hitomiTasterResults.isEmpty else {
            addSummary = "No Hitomi Taster results"
            return
        }
        let contentTypes =
            UTType(filenameExtension: "xlsx")
                .map { [$0] } ?? []
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes:
                            contentTypes,
                        nameFieldStringValue:
                            "Hitomi-Taster.xlsx"
                    )
                ) else {
            return
        }
        do {
            try exportHitomiTasterResults(to: url)
        } catch {
            addSummary = "Hitomi Taster export failed"
        }
    }

    func exportHitomiTasterResults(to url: URL) throws {
        try HitomiTasterWorkbookWriter.write(
            results: searchStore.hitomiTasterResults,
            model: searchStore.hitomiTasterModel,
            referenceCount: searchStore.hitomiTasterReferenceCount,
            accuracy: searchStore.hitomiTasterAccuracy,
            to: url
        )
        addSummary =
            "\(searchStore.hitomiTasterResults.count) Hitomi Taster results exported"
    }

    nonisolated static func hitomiTasterReferenceCount(
        jobs inputJobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        bookmarks: [URLBookmark]
    ) -> Int {
        HitomiTasterService.referenceCount(
            jobs: inputJobs,
            history: history,
            bookmarks: bookmarks
        )
    }

    nonisolated static func hitomiTasterResults(
        recommendations: [ArtistRecommendation],
        model: HitomiTasterModel,
        referenceCount: Int,
        limit: Int = 80
    ) -> [HitomiTasterResult] {
        HitomiTasterService.results(
            recommendations: recommendations,
            model: model,
            referenceCount: referenceCount,
            limit: limit
        )
    }

    nonisolated static func hitomiTasterAccuracy(results: [HitomiTasterResult], referenceCount: Int, model: HitomiTasterModel) -> Double {
        HitomiTasterService.accuracy(
            results: results,
            referenceCount: referenceCount,
            model: model
        )
    }

    nonisolated static func artistRecommendations(
        jobs inputJobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        bookmarks: [URLBookmark],
        limit: Int = 20
    ) -> [ArtistRecommendation] {
        ArtistRecommendationService.recommendations(
            jobs: inputJobs,
            history: history,
            bookmarks: bookmarks,
            limit: limit
        )
    }

    nonisolated static func originalArtistNames(from metadata: [String: String]) -> [String] {
        ArtistRecommendationService.originalArtistNames(from: metadata)
    }

    nonisolated static func originalArtistDisplayName(from metadata: [String: String]) -> String? {
        ArtistRecommendationService.originalArtistDisplayName(from: metadata)
    }

    nonisolated static func appAboutInfo() -> AppAboutInfo {
        AppDiagnosticInfoService.aboutInfo()
    }

    private nonisolated static func appVersionObject() -> [String: Any] {
        AppDiagnosticInfoService.versionObject()
    }

    private nonisolated static func appAboutObject() -> [String: Any] {
        AppDiagnosticInfoService.aboutObject()
    }

    private nonisolated static func appHelpObject() -> [String: Any] {
        AppDiagnosticInfoService.helpObject()
    }

    private func externalToolStatuses() -> [ExternalToolStatus] {
        ExternalToolPresentationService.statuses(store: externalToolStore)
    }

    func refreshDiskSpaceWarning(showAlert: Bool = false) {
        let status = Self.diskSpaceStatus(destinationPath: settingsStore.destinationPath, jobs: queueStore.jobs)
        appStatusStore.setDiskSpaceWarning(status.warning)
        if status.hasWarning {
            addSummary = status.warning
            if showAlert {
                presentation.showingStorageWarning = true
            }
        }
    }

    nonisolated static func diskSpaceStatus(destinationPath: String, jobs inputJobs: [DownloadJob]) -> DiskSpaceStatus {
        OutputStatisticsService.diskSpaceStatus(
            destinationPath: destinationPath,
            jobs: inputJobs
        )
    }

    nonisolated static func estimatedQueuedByteCount(for inputJobs: [DownloadJob]) -> Int64 {
        OutputStatisticsService.estimatedQueuedByteCount(for: inputJobs)
    }

    private func statisticsOutputURLs() -> [URL] {
        OutputStatisticsService.uniqueRecordedOutputURLs(
            jobs: queueStore.jobs,
            history: libraryStore.history
        )
    }

    nonisolated static func outputURLs(
        for inputJobs: [DownloadJob],
        fileManager: FileManager = .default
    ) -> [URL] {
        OutputStatisticsService.outputURLs(
            for: inputJobs,
            fileManager: fileManager
        )
    }

    nonisolated static func outputStatistics(
        for inputJobs: [DownloadJob],
        fileManager: FileManager = .default
    ) -> OutputFileStatistics {
        OutputStatisticsService.statistics(
            for: inputJobs,
            fileManager: fileManager
        )
    }

    nonisolated static func outputSummaryText(
        for inputJobs: [DownloadJob],
        fileManager: FileManager = .default
    ) -> String {
        OutputStatisticsService.summaryText(
            for: inputJobs,
            fileManager: fileManager
        )
    }

    nonisolated static func outputStatistics(for urls: [URL]) -> OutputFileStatistics {
        OutputStatisticsService.statistics(for: urls)
    }

    nonisolated static func shouldSkipPathAnalysis(volumeIsLocal: Bool?) -> Bool {
        OutputStatisticsService.shouldSkipPathAnalysis(
            volumeIsLocal: volumeIsLocal
        )
    }

    nonisolated static func shouldSkipPathAnalysis(for url: URL) -> Bool {
        OutputStatisticsService.shouldSkipPathAnalysis(for: url)
    }


    typealias SearchResultKnownState = SearchKnownState

    typealias SearchResultMetadataCopy = SearchMetadataCopy

    func pasteURLs() {
        if let text = clipboardInputText(), !text.trimmed.isEmpty {
            setInputText(text)
        }
    }

    @discardableResult
    func pasteAndAddURLs(text: String? = nil) -> Int {
        let text = text ?? clipboardInputText()
        guard let text, !text.trimmed.isEmpty else { return 0 }
        setInputText(text)
        let before = queueStore.jobs.count
        addURLs(fallbackText: nil)
        return queueStore.jobs.count - before
    }

    @discardableResult
    func pasteAndDownloadURLs(text: String? = nil) -> Bool {
        let text = text ?? clipboardInputText()
        guard let text, !text.trimmed.isEmpty else { return false }

        setInputText(text)
        let before = queueStore.jobs.count
        addURLs(fallbackText: nil)
        let added = queueStore.jobs.count - before

        if settingsStore.startDownloadsOnPaste {
            if presentation.showingDuplicateAdditionConfirmation {
                queueEditorStore.requestQueueStartAfterDuplicateAddition()
            }
            if added > 0 {
                startQueue(addingInput: false)
            }
        }
        return true
    }

    private func clipboardInputText() -> String? {
#if TESTING
        if let testingClipboardInputText {
            return testingClipboardInputText
        }
#endif
        return clipboardCommandService.inputText()
    }

    func refreshClipboardViewer() {
        applyClipboardViewerState(
            clipboardViewerCommandService
                .refreshedState(
                    extractURLs: {
                        self.extractURLs(
                            from: $0
                        )
                    }
                )
        )
    }

    func refreshClipboardViewer(fileURLs: [URL], string: String?, changeCount: Int) {
        applyClipboardViewerState(
            clipboardViewerCommandService
                .refreshedState(
                    fileURLs: fileURLs,
                    string: string,
                    changeCount: changeCount,
                    extractURLs: {
                        self.extractURLs(
                            from: $0
                        )
                    }
                )
        )
    }

    func setClipboardViewerText(_ text: String) {
        applyClipboardViewerState(
            clipboardViewerCommandService
                .editedState(
                    text: text,
                    changeCount:
                        presentation.clipboardViewerChangeCount,
                    extractURLs: {
                        self.extractURLs(
                            from: $0
                        )
                    }
                )
        )
    }

    @discardableResult
    func queueClipboardViewerURLs(start: Bool = false) -> Int {
        let result =
            clipboardViewerCommandService
            .queue(
                text: presentation.clipboardViewerText,
                start: start,
                extractURLs: {
                    self.extractURLs(
                        from: $0
                    )
                },
                enqueue: {
                    self.enqueueURLStrings($0)
                },
                startQueue: {
                    self.startQueue(
                        addingInput: false
                    )
                }
            )
        presentation.clipboardViewerURLs = result.urls
        addSummary = result.summary
        return result.added
    }

    func useClipboardViewerAsInput() {
        addSummary =
            clipboardViewerCommandService
            .transferToInput(
                text: presentation.clipboardViewerText,
                setInputText: {
                    self.setInputText($0)
                }
            )
    }

    private func applyClipboardViewerState(
        _ state: ClipboardViewerContentState
    ) {
        presentation.clipboardViewerText = state.text
        presentation.clipboardViewerSource = state.source
        presentation.clipboardViewerChangeCount =
            state.changeCount
        presentation.clipboardViewerURLs = state.urls
    }

    func refreshBrowserWindowURL() {
        let selection =
            browserWindowCommandService.selection(
                inputText: presentation.inputText,
                jobs: queueStore.jobs,
                normalizingToken:
                    Self.normalizedInputToken
            )
        presentation.browserWindowURLText = selection.url?.absoluteString ?? ""
        presentation.browserWindowURLSource = selection.source
    }

    func setBrowserWindowURLText(_ text: String) {
        presentation.browserWindowURLText = text
        presentation.browserWindowURLSource = "manual"
    }

    func browserWindowTargetURL() -> URL? {
        browserWindowCommandService.targetURL(
            text: presentation.browserWindowURLText,
            normalizingToken: Self.normalizedInputToken
        )
    }

    func browserWindowTargetSummary() -> String {
        browserWindowCommandService.targetSummary(
            text: presentation.browserWindowURLText,
            source: presentation.browserWindowURLSource,
            normalizingToken:
                Self.normalizedInputToken
        )
    }

    func openBrowserWindowLogin() {
        guard let url = browserWindowTargetURL() else {
            addSummary = "No browser URL"
            return
        }
        openLoginBrowser(
            url: url,
            authenticationKey: nil
        )
    }

    func openBrowserWindowHTTPPage() {
        addSummary =
            browserWindowCommandService
            .openHTTPPage(
                targetURL:
                    browserWindowTargetURL(),
                baseURLString:
                    httpAPIBaseURLString(),
                password: settingsStore.httpAPIPassword,
                ensureServerAvailable: {
                    ensureHTTPAPIAvailableForBrowserView()
                }
            ).summary
    }

    private var outputPreviewPresentationSnapshot:
        OutputPreviewPresentationSnapshot {
        OutputPreviewPresentationService.snapshot(
            jobs: queueStore.jobs,
            selectedJobID: presentation.outputPreviewJobID,
            files: presentation.outputPreviewFiles,
            selectedFileIndex: presentation.outputPreviewSelectedFileIndex,
            isLoading: presentation.outputPreviewIsLoading
        )
    }

    func openOutputPreview(for job: DownloadJob) {
        presentation.outputPreviewJobID = job.id
        presentation.showingOutputPreview = true
        refreshOutputPreview(keepingSelection: false)
    }

    func closeOutputPreview() {
        outputPreviewLoadCoordinator.cancelAndClear()
        presentation.outputPreviewIsLoading = false
        presentation.showingOutputPreview = false
        presentation.outputPreviewFiles = []
        presentation.outputPreviewSelectedFileIndex = 0
        presentation.outputPreviewJobID = nil
        OutputPreviewImageProvider.purgeCache()
    }

    func openOutputPreviewForSelectedJobs() {
        let selectedIDs = presentation.selectedJobIDs
        if let selected = queueStore.jobs.first(where: { selectedIDs.contains($0.id) && canOpenOutputPreview(for: $0) }) {
            openOutputPreview(for: selected)
            return
        }
        if let first = queueStore.jobs.first(where: canOpenOutputPreview(for:)) {
            openOutputPreview(for: first)
            return
        }
        addSummary = "No previewable output"
    }

    func refreshOutputPreview(keepingSelection: Bool = true) {
        guard let job = outputPreviewPresentationSnapshot.job else {
            outputPreviewLoadCoordinator.cancelAndClear()
            presentation.outputPreviewIsLoading = false
            presentation.outputPreviewFiles = []
            presentation.outputPreviewSelectedFileIndex = 0
            return
        }

        let previousSelection = presentation.outputPreviewSelectedFileIndex
        let jobID = job.id
        presentation.outputPreviewIsLoading = true
        if !keepingSelection {
            presentation.outputPreviewFiles = []
            presentation.outputPreviewSelectedFileIndex = 0
        }

        outputPreviewLoadCoordinator.begin(
            resolveOutputPath: { [weak self] in
                guard let self else { return "" }
                return await self.repairedOutputPath(for: job)
            },
            shouldContinue: { [weak self] in
                guard let self else { return false }
                return self.presentation.showingOutputPreview &&
                    self.presentation.outputPreviewJobID == jobID
            },
            completion: { [weak self] files in
                guard let self else { return }
                self.presentation.outputPreviewFiles = files
                if keepingSelection,
                   files.contains(where: {
                       $0.originalIndex == previousSelection
                   }) {
                    self.presentation.outputPreviewSelectedFileIndex =
                        previousSelection
                } else {
                    self.presentation.outputPreviewSelectedFileIndex =
                        files.first(where: \.isImage)?
                            .originalIndex
                        ?? files.first?.originalIndex
                        ?? 0
                }
                self.presentation.outputPreviewIsLoading = false
            }
        )
    }

    func selectOutputPreviewFile(_ file: OutputPreviewFile) {
        presentation.outputPreviewSelectedFileIndex = file.originalIndex
    }

    func selectAdjacentOutputPreviewImage(direction: Int) {
        guard let next = OutputPreviewNavigationService.adjacentImageIndex(
            files: presentation.outputPreviewFiles,
            selectedFileIndex: presentation.outputPreviewSelectedFileIndex,
            direction: direction
        ) else { return }
        presentation.outputPreviewSelectedFileIndex = next
    }

    func canSelectAdjacentOutputPreviewImage(direction: Int) -> Bool {
        OutputPreviewNavigationService.adjacentImageIndex(
            files: presentation.outputPreviewFiles,
            selectedFileIndex: presentation.outputPreviewSelectedFileIndex,
            direction: direction
        ) != nil
    }

    func openSelectedOutputPreviewFile() {
        guard let file = outputPreviewPresentationSnapshot.selectedFile else {
            addSummary = "No preview file selected"
            return
        }
        openOutputPreviewFile(file)
    }

    func openOutputPreviewFile(_ file: OutputPreviewFile) {
        switch outputCommandService.openPreviewFile(file) {
        case .opened:
            addSummary = "Preview file opened"
        case .archiveEntryRevealed:
            addSummary = "Archive entry selected"
        case .revealed:
            break
        }
    }

    func revealOutputPreviewFile(_ file: OutputPreviewFile) {
        switch outputCommandService.revealPreviewFile(file) {
        case let .revealed(isArchiveEntry):
            addSummary =
                isArchiveEntry
                ? "Archive revealed"
                : "Preview file revealed"
        case .opened, .archiveEntryRevealed:
            break
        }
    }

    func openOutputPreviewInBrowser() {
        guard let job = outputPreviewPresentationSnapshot.job else {
            addSummary = "No preview task selected"
            return
        }
        openOutputBrowserView(for: job)
    }

    func openOutputPreviewFileInBrowser(_ file: OutputPreviewFile? = nil) {
        guard let job = outputPreviewPresentationSnapshot.job,
              let file = file ?? outputPreviewPresentationSnapshot.selectedFile,
              let url = outputPreviewBrowserFileURL(jobID: job.id, fileIndex: file.originalIndex) else {
            addSummary = "No preview file selected"
            return
        }
        guard ensureHTTPAPIAvailableForBrowserView() else {
            addSummary = "Preview browser unavailable"
            return
        }
        _ = sourceLinkCommandService.openBrowserURL(
            url,
            skipExternalOpen: false
        )
        addSummary = "Preview file opened in browser"
    }

    func createPDFForOutputPreview() {
        guard let job = outputPreviewPresentationSnapshot.job else {
            addSummary = "No preview task selected"
            return
        }
        createPDF(for: job)
    }

    func canOpenOutputPreview(for job: DownloadJob) -> Bool {
        guard let output = QueueThumbnailProvider.existingOutputURL(
            forOutputPath: job.outputPath,
            destinationPath: settingsStore.destinationPath,
            searchRelocatedOutputs: false
        ) else {
            return false
        }
        return OutputPreviewFileScanner.outputPathExists(output.path)
    }

    private func outputPreviewBrowserFileURL(jobID: UUID, fileIndex: Int) -> URL? {
        let value = httpAPIBaseURLString().trimmed
        guard !value.isEmpty, var components = URLComponents(string: value) else { return nil }
        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.host == nil {
            components.host = "127.0.0.1"
        }
        components.path = "/file"
        var queryItems = [
            URLQueryItem(name: "uid", value: jobID.uuidString),
            URLQueryItem(name: "index", value: "\(fileIndex)"),
            URLQueryItem(name: "disposition", value: "inline")
        ]
        let password = settingsStore.httpAPIPassword.trimmed
        if !password.isEmpty {
            queryItems.append(URLQueryItem(name: "pw", value: password))
        }
        components.queryItems = queryItems
        return components.url
    }

    func selectTextViewerEntry(_ entry: TextViewerEntry) {
        presentation.textViewerSelectedEntryID = entry.id
    }

    func ensureTextViewerSelection() {
        presentation.textViewerSelectedEntryID =
            textViewerReadModelService.ensuredSelectionID(
                for: queueStore.jobs,
                filter: presentation.textViewerFilter,
                currentSelectionID:
                    presentation.textViewerSelectedEntryID
            )
    }

    func selectedTextViewerEntry() -> TextViewerEntry? {
        textViewerReadModelService.selectedEntry(
            for: queueStore.jobs,
            filter: presentation.textViewerFilter,
            selectedEntryID: presentation.textViewerSelectedEntryID
        )
    }

    func selectedTextViewerDocument(limit: Int = 1_048_576) -> TextViewerDocument {
        textViewerReadModelService.selectedDocument(
            for: queueStore.jobs,
            filter: presentation.textViewerFilter,
            selectedEntryID: presentation.textViewerSelectedEntryID,
            limit: limit
        )
    }

    func copySelectedTextViewerDocument() {
        addSummary =
            textViewerCommandService.copy(
                document:
                    selectedTextViewerDocument()
            ).summary
    }

    func openSelectedTextViewerInBrowser() {
        addSummary =
            textViewerCommandService.openInBrowser(
                entry: selectedTextViewerEntry(),
                baseURLString:
                    httpAPIBaseURLString(),
                password: settingsStore.httpAPIPassword,
                ensureServerAvailable: {
                    ensureHTTPAPIAvailableForBrowserView()
                }
            ).summary
    }

    func openSelectedTextViewerRawFile() {
        let entry = selectedTextViewerEntry()
        addSummary =
            textViewerCommandService.openRawFile(
                entry: entry,
                files:
                    textViewerRawFiles(
                        for: entry
                    )
            ).summary
    }

    func canOpenSelectedTextViewerRawFile() -> Bool {
        let entry = selectedTextViewerEntry()
        return textViewerCommandService
            .canOpenRawFile(
                entry: entry,
                files:
                    textViewerRawFiles(
                        for: entry
                    )
            )
    }

    private func textViewerRawFiles(
        for entry: TextViewerEntry?
    ) -> [TextViewerRawFile]? {
        textViewerReadModelService.rawFiles(
            for: entry,
            jobs: queueStore.jobs
        )
    }

    nonisolated static func pasteInputText(fileURLs: [URL], string: String?) -> String? {
        ClipboardCommandService.inputText(
            fileURLs: fileURLs,
            string: string
        )
    }

    func setInputText(_ text: String) {
        let changed = presentation.inputText != text
        presentation.inputText = text
        presentation.inputCursorUTF16Offset = (text as NSString).length
        if changed {
            presentation.inputAutocompleteSelectionIndex = 0
            presentation.isInputAutocompleteDismissed = false
        }
        persistInputTextDraft()
    }

    private var visibleInputAutocompleteSuggestions: [String] {
        InputAutocompletePresentationService.visibleSuggestions(
            inputText: presentation.inputText,
            cursorUTF16Offset: presentation.inputCursorUTF16Offset,
            isInputFocused: presentation.isURLInputFocused,
            isDismissed: presentation.isInputAutocompleteDismissed
        )
    }

    private var availableInputAutocompleteSuggestions: [String] {
        InputAutocompletePresentationService.availableSuggestions(
            inputText: presentation.inputText,
            cursorUTF16Offset: presentation.inputCursorUTF16Offset
        )
    }

    func setURLInputFocused(_ focused: Bool) {
        presentation.isURLInputFocused = focused
        presentation.inputAutocompleteSelectionIndex = 0
        presentation.isInputAutocompleteDismissed = !focused
    }

    func setInputCursorUTF16Offset(_ offset: Int) {
        let clamped = min(
            max(offset, 0),
            (presentation.inputText as NSString).length
        )
        guard presentation.inputCursorUTF16Offset != clamped else { return }
        presentation.inputCursorUTF16Offset = clamped
        presentation.inputAutocompleteSelectionIndex = 0
    }

    @discardableResult
    func moveInputAutocompleteSelection(by delta: Int) -> Bool {
        let suggestions = visibleInputAutocompleteSuggestions
        guard !suggestions.isEmpty else { return false }
        presentation.inputAutocompleteSelectionIndex = min(
            max(presentation.inputAutocompleteSelectionIndex + delta, 0),
            suggestions.count - 1
        )
        return true
    }

    func setInputAutocompleteSelection(_ index: Int) {
        let suggestions = visibleInputAutocompleteSuggestions
        guard !suggestions.isEmpty else { return }
        presentation.inputAutocompleteSelectionIndex = min(max(index, 0), suggestions.count - 1)
    }

    @discardableResult
    func acceptInputAutocompleteSuggestion(_ explicitSuggestion: String? = nil) -> Bool {
        let suggestions = explicitSuggestion == nil
            ? visibleInputAutocompleteSuggestions
            : availableInputAutocompleteSuggestions
        guard !suggestions.isEmpty else { return false }
        let index = min(max(presentation.inputAutocompleteSelectionIndex, 0), suggestions.count - 1)
        let suggestion = explicitSuggestion ?? suggestions[index]
        guard suggestions.contains(suggestion) else { return false }

        let replacement = OriginalInputAutocomplete.replacingFragment(
            in: presentation.inputText,
            cursorUTF16Offset: presentation.inputCursorUTF16Offset,
            with: suggestion
        )
        presentation.inputText = replacement.text
        presentation.inputCursorUTF16Offset = replacement.cursorUTF16Offset
        presentation.inputAutocompleteSelectionIndex = 0
        presentation.isInputAutocompleteDismissed = true
        persistInputTextDraft()
        return true
    }

    @discardableResult
    func dismissInputAutocomplete() -> Bool {
        guard !visibleInputAutocompleteSuggestions.isEmpty else { return false }
        presentation.isInputAutocompleteDismissed = true
        presentation.inputAutocompleteSelectionIndex = 0
        return true
    }

    private func insertAddedJobsAtTop(_ newJobs: [DownloadJob], preservingVisualOrder: Bool = false) {
        guard !newJobs.isEmpty else { return }
        let orderedJobs = preservingVisualOrder ? newJobs : Array(newJobs.reversed())

        // Active workers retain their array position while awaiting network and file I/O.
        // Keep their physical positions stable while a UUID order preserves the visible queue.
        if queueStore.isRunning {
            queueScheduler.registerInsertedJobsAtTop(orderedJobs, among: queueStore.jobs)
            queueStore.insertJobs(orderedJobs, at: queueStore.jobs.endIndex)
            return
        }

        let insertionIndex = queueStore.jobs.firstIndex(where: { !$0.isPinned }) ?? queueStore.jobs.endIndex
        queueStore.insertJobs(orderedJobs, at: insertionIndex)
    }

    func addURLs() {
        addURLs(fallbackText: nil)
    }

    func addURLs(fallbackText: String?) {
        let sourceText = presentation.inputText.trimmed.isEmpty
            ? fallbackText ?? ""
            : presentation.inputText
        let items = inputItems(from: sourceText)
        let newJobs = jobsForAdding(items, promptForDuplicates: true)
        if !newJobs.isEmpty {
            insertAddedJobsAtTop(newJobs)
            persistQueue()
        }
        if !newJobs.isEmpty || presentation.showingDuplicateAdditionConfirmation {
            presentation.inputText = ""
            presentation.inputCursorUTF16Offset = 0
            presentation.inputAutocompleteSelectionIndex = 0
            presentation.isInputAutocompleteDismissed = true
            persistInputTextDraft()
        }
        if !newJobs.isEmpty {
            runQueuedJobsIfEnabled()
        }
    }

    func addLocalFilesAndFolders() {
        guard let selectedURLs =
            documentPanelCommandService
                .chooseOpenURLs(
                    OpenDocumentPanelRequest(
                        canChooseFiles: true,
                        canChooseDirectories: true,
                        allowsMultipleSelection: true
                    )
                ) else {
            return
        }
        let urls = selectedURLs.map {
            $0.standardizedFileURL.absoluteString
        }
        let newJobs = jobsForAdding(urls, promptForDuplicates: true)
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        addSummary = "\(newJobs.count) local item(s) added"
        persistQueue()
        runQueuedJobsIfEnabled()
    }

    @discardableResult
    func enqueueOpenedURLs(_ urls: [URL]) -> Int {
        let strings = urls.map { url -> String in
            if url.isFileURL {
                return url.standardizedFileURL.absoluteString
            }
            return url.absoluteString
        }
        let newJobs = jobsForAdding(strings, promptForDuplicates: true)
        guard !newJobs.isEmpty else { return 0 }
        insertAddedJobsAtTop(newJobs)
        addSummary = "\(newJobs.count) opened item(s) added"
        persistQueue()
        runQueuedJobsIfEnabled()
        return newJobs.count
    }

    @discardableResult
    func enqueueDroppedValues(_ values: [String]) -> Int {
        var inputs: [(url: String, metadata: [String: String])] = []
        for value in values {
            if let task = OriginalBrowserExtensionTask.parse(value),
               let item = inputItem(from: task, monitorableOnly: false) {
                inputs.append(item)
                continue
            }
            for line in value.components(separatedBy: .newlines) {
                let trimmed = line.trimmed
                guard !trimmed.isEmpty else { continue }

                if let fileURL = URL(string: trimmed), fileURL.isFileURL {
                    inputs.append((fileURL.standardizedFileURL.absoluteString, [:]))
                } else if trimmed.hasPrefix("/"), FileManager.default.fileExists(atPath: trimmed) {
                    inputs.append((URL(fileURLWithPath: trimmed).standardizedFileURL.absoluteString, [:]))
                } else {
                    inputs.append(contentsOf: inputItems(from: trimmed))
                }
            }
        }

        let newJobs = jobsForAdding(inputs, promptForDuplicates: true)
        guard !newJobs.isEmpty else {
            if !presentation.showingDuplicateAdditionConfirmation {
                addSummary = values.isEmpty ? "Drop did not contain a URL or file" : "No new dropped items"
            }
            return 0
        }
        insertAddedJobsAtTop(newJobs)
        addSummary = "\(newJobs.count) dropped item\(newJobs.count == 1 ? "" : "s") added"
        persistQueue()
        runQueuedJobsIfEnabled()
        return newJobs.count
    }

    func addMP3AudioURLs() {
        addMP3AudioURLs(
            fallbackText:
                clipboardCommandService
                .snapshot()
                .string
        )
    }

    func addMP3AudioURLs(fallbackText: String?) {
        let sourceText = presentation.inputText.trimmed.isEmpty
            ? fallbackText ?? ""
            : presentation.inputText
        let urls = extractURLs(from: sourceText)
        let metadata = [
            "media_request": "audio",
            "audio_format": "mp3"
        ]
        let newJobs = jobsForAdding(
            urls,
            metadata: metadata,
            titleSuffix: " [MP3]",
            promptForDuplicates: true
        )
        if !newJobs.isEmpty {
            insertAddedJobsAtTop(newJobs)
            persistQueue()
            runQueuedJobsIfEnabled()
        }
        if !newJobs.isEmpty || presentation.showingDuplicateAdditionConfirmation {
            presentation.inputText = ""
            presentation.inputCursorUTF16Offset = 0
            presentation.inputAutocompleteSelectionIndex = 0
            presentation.isInputAutocompleteDismissed = true
            persistInputTextDraft()
        }
    }

    func importURLList() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .plainText,
                            .text
                        ]
                    )
                ) else {
            return
        }
        do {
            try importURLList(from: url)
        } catch {
            addSummary = "URL import failed"
        }
    }

    func exportQueueURLs() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            .plainText
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-Queue.txt"
                    )
                ) else {
            return
        }
        do {
            try exportQueueURLs(to: url)
        } catch {
            addSummary = "URL export failed"
        }
    }

    func importURLList(from url: URL) throws {
        let text = ImportExportCodecService.importedText(
            from: try Data(contentsOf: url)
        )
        let newJobs = jobsForAdding(inputItems(from: text), promptForDuplicates: true)
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
        runQueuedJobsIfEnabled()
    }

    func exportQueueURLs(to url: URL) throws {
        let (exported, scope) = queueJobsForExport()
        let text = exported.map(\.source).joined(separator: "\n") + (exported.isEmpty ? "" : "\n")
        try text.write(to: url, atomically: true, encoding: .utf8)
        switch scope {
        case .selected:
            addSummary = "\(exported.count) selected URLs exported"
        case .filtered:
            addSummary = "\(exported.count) filtered URLs exported"
        case .all:
            addSummary = "\(exported.count) URLs exported"
        }
    }

    func importQueueJobs() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text,
                            Self.originalHDTContentType
                        ]
                    )
                ) else {
            return
        }
        do {
            _ = try importQueueJobs(from: url)
        } catch {
            addSummary = "Job import failed"
        }
    }

    func exportQueueJobs() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            Self.originalHDTContentType,
                            .json
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-Tasks.hdt"
                    )
                ) else {
            return
        }
        do {
            try exportQueueJobs(to: url)
        } catch {
            addSummary = "Job export failed"
        }
    }

    @discardableResult
    func importQueueJobs(from url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        let imported: QueueImportDocument
        if url.pathExtension.caseInsensitiveCompare("hdt") == .orderedSame {
            let document = try OriginalHDT.decodeDocument(data)
            imported = QueueImportDocument(jobs: document.jobs, groups: document.groups)
        } else {
            imported = try ImportExportCodecService.queueDocument(
                from: data,
                urlExtractor: { Self.extractURLs(fromTokenLine: $0) }
            )
        }

        let plan = QueueImportPlanningService.plan(
            document: imported,
            existingJobIDs: Set(queueStore.jobs.map(\.id)),
            existingGroupIDs: Set(queueStore.queueGroups.map(\.id)),
            groupIDMetadataKey: QueueJobMetadataPolicy.groupIDMetadataKey
        )
        let normalized = plan.jobs
        let importedGroups = plan.groups

        guard !normalized.isEmpty || !importedGroups.isEmpty else {
            addSummary = "No jobs imported"
            return 0
        }

        if !normalized.isEmpty {
            insertAddedJobsAtTop(normalized, preservingVisualOrder: true)
        }
        queueStore.insertQueueGroups(importedGroups, at: 0)
        for jobID in normalized.map(\.id) {
            _ = restoreScheduledRetryIfNeeded(for: jobID)
        }
        addSummary = importedGroups.isEmpty
            ? "\(normalized.count) jobs imported"
            : "\(normalized.count) jobs and \(importedGroups.count) groups imported"
        persistQueue()
        return normalized.count
    }

    func exportQueueJobs(to url: URL) throws {
        let (exported, scope) = queueJobsForExport()
        let exportedGroupIDs = Set(exported.compactMap { jobGroupID(for: $0) })
        let exportedGroups: [QueueGroup]
        switch scope {
        case .all:
            exportedGroups = queueStore.queueGroups
        case .selected, .filtered:
            exportedGroups = queueStore.queueGroups.filter { exportedGroupIDs.contains($0.id) }
        }
        let isHDT = url.pathExtension.caseInsensitiveCompare("hdt") == .orderedSame
        let data: Data
        if isHDT {
            data = try OriginalHDT.encode(exported, groups: exportedGroups)
        } else {
            let package = QueueJobPackage(exportedAt: Date(), jobs: exported, groups: exportedGroups)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            data = try encoder.encode(package)
        }
        try data.write(to: url, options: .atomic)
        let noun = isHDT ? "original tasks" : "jobs"
        switch scope {
        case .selected:
            addSummary = "\(exported.count) selected \(noun) exported"
        case .filtered:
            addSummary = "\(exported.count) filtered \(noun) exported"
        case .all:
            addSummary = "\(exported.count) \(noun) exported"
        }
    }

    func importOriginalTasks() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            Self.originalHDTContentType
                        ]
                    )
                ) else {
            return
        }
        do {
            _ = try importQueueJobs(from: url)
        } catch {
            addSummary = "HDT import failed: \(AppLocalization.errorText(error))"
        }
    }

    func exportOriginalTasks() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            Self.originalHDTContentType
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-Tasks.hdt"
                    )
                ) else {
            return
        }
        do {
            try exportQueueJobs(to: url)
        } catch {
            addSummary = "HDT export failed: \(AppLocalization.errorText(error))"
        }
    }

    func importOpenedTaskPackage(_ url: URL) {
        do {
            _ = try importQueueJobs(from: url)
        } catch {
            addSummary = "HDT import failed: \(AppLocalization.errorText(error))"
        }
    }

    private nonisolated static var originalHDTContentType: UTType {
        UTType(filenameExtension: "hdt") ?? .json
    }

    private enum QueueExportScope {
        case selected
        case filtered
        case all
    }

    private func queueJobsForExport() -> ([DownloadJob], QueueExportScope) {
        let orderedJobs = queueOrderedJobs
        let selected = orderedJobs.filter { presentation.selectedJobIDs.contains($0.id) }
        if !selected.isEmpty {
            return (selected, .selected)
        }
        if !presentation.queueFilter.trimmed.isEmpty {
            return (queuePresentationSnapshot.filteredJobs, .filtered)
        }
        return (orderedJobs, .all)
    }

    func saveCurrentQueueFilterBookmark() {
        let query = presentation.queueFilter.trimmed
        guard !query.isEmpty else {
            addSummary = "Enter a filter"
            return
        }

        let didUpdate = queueStore.upsertQueueFilterBookmark(
            title: ImportExportCodecService.queueFilterBookmarkTitle(
                for: query
            ),
            query: query
        )
        addSummary = didUpdate
            ? "Filter bookmark updated"
            : "Filter bookmark saved"
        persistQueueFilterBookmarks()
    }

    func applyQueueFilterBookmark(_ bookmark: QueueFilterBookmark) {
        presentation.queueFilter = bookmark.query
        addSummary = "Filter applied"
    }

    func removeQueueFilterBookmark(_ bookmark: QueueFilterBookmark) {
        queueStore.removeQueueFilterBookmark(id: bookmark.id)
        persistQueueFilterBookmarks()
        addSummary = "Filter bookmark removed"
    }

    func importQueueFilterBookmarks() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ]
                    )
                ) else {
            return
        }
        do {
            _ = try importQueueFilterBookmarks(from: url)
        } catch {
            addSummary = "Filter bookmark import failed"
        }
    }

    func exportQueueFilterBookmarks() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-FilterBookmarks.json"
                    )
                ) else {
            return
        }
        do {
            try exportQueueFilterBookmarks(to: url)
        } catch {
            addSummary = "Filter bookmark export failed"
        }
    }

    @discardableResult
    func importQueueFilterBookmarks(from url: URL) throws -> Int {
        let imported = try ImportExportCodecService.queueFilterBookmarks(
            from: try Data(contentsOf: url)
        )
        let added = mergeQueueFilterBookmarks(imported)
        addSummary = added == 0 ? "No new filter bookmarks" : "\(added) filter bookmarks imported"
        return added
    }

    func exportQueueFilterBookmarks(to url: URL) throws {
        let data = try ImportExportCodecService.queueFilterBookmarkData(
            queueStore.queueFilterBookmarks,
            destinationURL: url
        )
        try data.write(to: url, options: .atomic)
        addSummary = "\(queueStore.queueFilterBookmarks.count) filter bookmarks exported"
    }

    @discardableResult
    func enqueueClipboardText(_ text: String) -> Int {
        let newJobs = jobsForAdding(inputItems(from: text, monitorableOnly: true))
        guard !newJobs.isEmpty else { return 0 }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
        return newJobs.count
    }

    func bookmarkInputURLs() {
        let urls = extractURLs(from: presentation.inputText)
        addBookmarks(urls)
    }

    func importBookmarks() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .plainText,
                            .text,
                            .json
                        ]
                    )
                ) else {
            return
        }
        do {
            try importBookmarks(from: url)
        } catch {
            addSummary = "Bookmark import failed"
        }
    }

    func exportBookmarks() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            .plainText,
                            .text
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-Bookmarks.tsv"
                    )
                ) else {
            return
        }
        do {
            try exportBookmarks(to: url)
        } catch {
            addSummary = "Bookmark export failed"
        }
    }

    func importBookmarks(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let records = ImportExportCodecService.bookmarkImportRecords(
            from: data,
            normalizeInput: { Self.normalizedInputToken($0) },
            looksLikeURL: { Self.looksLikeURL($0) },
            urlExtractor: { Self.extractURLs(fromTokenLine: $0) }
        )
        let added = addBookmarkRecords(records)
        addSummary = added == 0 ? "No new bookmarks" : "\(added) bookmarks imported"
    }

    func exportBookmarks(to url: URL) throws {
        let exported = libraryStore.filteredBookmarks(
            matching: presentation.bookmarkFilter
        )
        let text = ImportExportCodecService.bookmarkExportText(exported)
        try text.write(to: url, atomically: true, encoding: .utf8)
        addSummary = presentation.bookmarkFilter.trimmed.isEmpty
            ? "\(exported.count) bookmarks exported"
            : "\(exported.count) filtered bookmarks exported"
    }

    func importSiteRules() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ]
                    )
                ) else {
            return
        }
        do {
            try importSiteRules(from: url)
        } catch {
            addSummary = "Rule import failed"
        }
    }

    func exportSiteRules() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            .json
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-SiteRules.json"
                    )
                ) else {
            return
        }
        do {
            try exportSiteRules(to: url)
        } catch {
            addSummary = "Rule export failed"
        }
    }

    func importSiteRules(from url: URL) throws {
        let data = try Data(contentsOf: url)
        let imported = try ImportExportCodecService.siteRules(
            from: data,
            sourceURL: url
        )
        let added = mergeImportedSiteRules(imported)
        addSummary = added == 0 ? "No new site rules" : "\(added) site rules imported"
    }

    func exportSiteRules(to url: URL) throws {
        let data = try ImportExportCodecService.siteRuleData(
            libraryStore.siteRules
        )
        try data.write(to: url, options: .atomic)
        addSummary = "\(libraryStore.siteRules.count) site rules exported"
    }

    func importPythonScript() {
        choosePythonScript(asPlugin: false)
    }

    func installPythonPlugin() {
        choosePythonScript(asPlugin: true)
    }

    private func choosePythonScript(asPlugin: Bool) {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        title: asPlugin
                            ? "Install Python Plugin"
                            : "Import Python Script",
                        message: asPlugin
                            ? "Choose a trusted compatible .hds or .py site, hook, or theme plugin."
                            : "Choose a trusted compatible .hds or .py script for this app session.",
                        prompt: asPlugin
                            ? "Install"
                            : "Import",
                        allowedContentTypes: [
                            UTType(
                                filenameExtension:
                                    "hds"
                            ) ?? .data,
                            UTType(
                                filenameExtension:
                                    "py"
                            ) ?? .plainText
                        ]
                    )
                ) else {
            return
        }
        do {
            let metadata = try PythonScriptBridge.staticMetadata(at: url)
            guard confirmPythonScriptExecution(metadata: metadata, asPlugin: asPlugin) else { return }
            pythonPluginCommandCoordinator.begin { [weak self] in
                guard let self else { return }
                do {
                    let plugin = try await self.importPythonScript(from: url, asPlugin: asPlugin)
                    if !asPlugin && !plugin.hasCompatibleEntryPoints && plugin.lastError == nil {
                        self.addSummary = "\(plugin.title) executed"
                    } else {
                        self.addSummary = !plugin.hasCompatibleEntryPoints
                            ? "Script ran, but no compatible Downloader, Hook, theme, or tool entry point was registered"
                            : "\(plugin.title) \(asPlugin ? "installed" : "imported")"
                    }
                } catch {
                    self.pythonRuntimeStore.setScriptStatus(
                        AppLocalization.errorText(error)
                    )
                    self.addSummary = "Python script import failed: \(AppLocalization.errorText(error))"
                }
            }
        } catch {
            pythonRuntimeStore.setScriptStatus(
                AppLocalization.errorText(error)
            )
            addSummary = "Python script import failed: \(AppLocalization.errorText(error))"
        }
    }

    @discardableResult
    func importPythonScript(from sourceURL: URL, asPlugin: Bool) async throws -> PythonScriptPlugin {
        let metadata = try PythonScriptBridge.staticMetadata(at: sourceURL)
        guard !pythonRuntimeStore.scriptPlugins.contains(where: {
            $0.digest == metadata.digest
        }) else {
            throw PythonScriptBridgeError.invalidScript("This script is already imported.")
        }
        let destinationDirectory = asPlugin ? AppPaths.pythonPluginDirectory : AppPaths.pythonSessionScriptDirectory
        try AppPaths.ensureDirectory(destinationDirectory)
        let destinationURL = AppPaths.uniqueFileURL(in: destinationDirectory, filename: sourceURL.lastPathComponent)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        do {
            var plugin = try await PythonScriptBridge(
                configuredPythonPath: externalToolStore.pythonPath
            ).inspect(scriptURL: destinationURL)
            plugin.isSession = !asPlugin
            let hasRegisteredEntryPoints = !plugin.downloaders.isEmpty ||
                !plugin.registeredHooks.isEmpty ||
                !plugin.registeredThemes.isEmpty
            if !hasRegisteredEntryPoints && !asPlugin {
                recordPythonScriptLogs(plugin.lastOutput ?? "", plugin: plugin, scope: "tool script")
                try? FileManager.default.removeItem(at: destinationURL)
                plugin.scriptPath = sourceURL.path
                plugin.isEnabled = false
                plugin.lastError = nil
                recordActivity("Executed Python tool script: \(plugin.title)", category: "Script")
                return plugin
            }
            plugin.runsOnLoad = !hasRegisteredEntryPoints && asPlugin
            plugin.isEnabled = plugin.hasCompatibleEntryPoints
            plugin.lastError = plugin.hasCompatibleEntryPoints ? nil : "No compatible Downloader, Hook, theme, or tool entry point"
            let scope = plugin.isToolPlugin ? "tool plugin" : (plugin.registeredThemes.isEmpty ? "load" : "theme")
            recordPythonScriptLogs(plugin.lastOutput ?? "", plugin: plugin, scope: scope)
            if asPlugin {
                try PythonScriptPluginStore.save(plugin)
            }
            pythonRuntimeStore.appendScriptPlugin(plugin)
            sortPythonScriptPlugins()
            refreshPythonScriptStatus()
            recordActivity("Loaded Python script: \(plugin.title)", category: "Plugin")
            return plugin
        } catch {
            try? FileManager.default.removeItem(at: destinationURL)
            throw error
        }
    }

    func reloadPythonScriptPlugins() {
        guard !pythonRuntimeStore.isReloadingScripts else { return }
        pythonPluginCommandCoordinator.begin { [weak self] in
            await self?.reloadPythonScriptPluginsNow()
        }
    }

    func reloadPythonScriptPluginsNow() async {
        guard !pythonRuntimeStore.isReloadingScripts else { return }
        pythonRuntimeStore.setReloadingScripts(true)
        pythonRuntimeStore.setScriptStatus("Reloading Python Scripts...")
        let current = pythonRuntimeStore.scriptPlugins
        var refreshed: [PythonScriptPlugin] = []
        var failed = 0

        for previous in current {
            do {
                var plugin = try await PythonScriptBridge(
                    configuredPythonPath: externalToolStore.pythonPath
                ).inspect(scriptURL: previous.scriptURL)
                plugin.isSession = previous.isSession
                plugin.importedAt = previous.importedAt
                plugin.runsOnLoad = previous.runsOnLoad
                plugin.isEnabled = previous.isEnabled && plugin.hasCompatibleEntryPoints
                plugin.lastError = plugin.hasCompatibleEntryPoints ? nil : "No compatible Downloader, Hook, theme, or tool entry point"
                recordPythonScriptLogs(plugin.lastOutput ?? "", plugin: plugin, scope: "reload")
                if !plugin.isSession {
                    try PythonScriptPluginStore.save(plugin)
                }
                refreshed.append(plugin)
            } catch {
                var plugin = previous
                plugin.isEnabled = false
                plugin.lastError = AppLocalization.errorText(error)
                if !plugin.isSession {
                    try? PythonScriptPluginStore.save(plugin)
                }
                refreshed.append(plugin)
                failed += 1
            }
        }

        pythonRuntimeStore.replaceScriptPlugins(with: refreshed)
        sortPythonScriptPlugins()
        pythonRuntimeStore.setReloadingScripts(false)
        refreshPythonScriptStatus()
        addSummary = failed == 0
            ? "\(refreshed.count) Python scripts reloaded"
            : "Python scripts reloaded with \(failed) failure\(failed == 1 ? "" : "s")"
    }

    func runEnabledPythonToolPlugins() async {
        let plugins = pythonRuntimeStore.scriptPlugins.filter {
            $0.isEnabled && $0.isToolPlugin
        }
        guard !plugins.isEmpty else { return }
        var failures = 0
        for previous in plugins {
            do {
                let inspected = try await PythonScriptBridge(
                    configuredPythonPath: externalToolStore.pythonPath
                ).inspect(scriptURL: previous.scriptURL)
                guard inspected.digest == previous.digest else {
                    throw PythonScriptBridgeError.invalidScript("The installed tool plugin changed. Reload it before running.")
                }
                guard let updated = pythonRuntimeStore.updateScriptPlugin(
                    id: previous.id,
                    {
                        $0.lastOutput = inspected.lastOutput
                        $0.lastError = nil
                    }
                ) else { continue }
                recordPythonScriptLogs(inspected.lastOutput ?? "", plugin: previous, scope: "startup")
                try? PythonScriptPluginStore.save(updated)
            } catch {
                guard let updated = pythonRuntimeStore.updateScriptPlugin(
                    id: previous.id,
                    {
                        $0.lastError = AppLocalization.errorText(error)
                    }
                ) else { continue }
                failures += 1
                try? PythonScriptPluginStore.save(updated)
                recordActivity("Tool plugin failed: \(previous.title) - \(AppLocalization.errorText(error))", category: "Script")
            }
        }
        refreshPythonScriptStatus()
        if failures > 0 {
            pythonRuntimeStore.setScriptStatus(
                "\(failures) tool plugins failed at startup"
            )
        }
    }

    func setPythonScriptPluginEnabled(_ plugin: PythonScriptPlugin, enabled: Bool) {
        guard let current = pythonRuntimeStore.scriptPlugins.first(where: {
            $0.id == plugin.id
        }) else { return }
        if enabled && !current.hasCompatibleEntryPoints {
            addSummary = "This script has no compatible Downloader, Hook, theme, or tool entry point"
            return
        }
        guard let updated = pythonRuntimeStore.updateScriptPlugin(
            id: current.id,
            { $0.isEnabled = enabled }
        ) else { return }
        if !updated.isSession {
            try? PythonScriptPluginStore.save(updated)
        }
        refreshPythonScriptStatus()
        addSummary = "\(updated.title) \(enabled ? "enabled" : "disabled")"
    }

    func removePythonScriptPlugin(_ plugin: PythonScriptPlugin) {
        guard let current = pythonRuntimeStore.scriptPlugins.first(where: {
            $0.id == plugin.id
        }) else { return }
        do {
            try PythonScriptPluginStore.remove(current)
            pythonRuntimeStore.removeScriptPlugin(id: current.id)
            refreshPythonScriptStatus()
            addSummary = "\(current.title) removed"
        } catch {
            addSummary = "Python script removal failed: \(AppLocalization.errorText(error))"
        }
    }

    func choosePythonExecutable() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        title: "Choose Python 3",
                        message:
                            "Choose a Python 3 executable used to run trusted .hds and .py scripts.",
                        prompt: "Choose"
                    )
                ) else {
            return
        }
        externalToolStore.pythonPath = url.path
        savePythonPath()
    }

    func savePythonPath() {
        externalToolStore.pythonPath =
            ExternalToolSettings.normalizedExecutablePath(
                externalToolStore.pythonPath
            )
        if externalToolStore.pythonPath.isEmpty {
            UserDefaults.standard.removeObject(forKey: "pythonScriptPythonPath")
        } else {
            UserDefaults.standard.set(
                externalToolStore.pythonPath,
                forKey: "pythonScriptPythonPath"
            )
        }
        refreshPythonScriptStatus()
        addSummary = PythonScriptBridge.pythonExecutableURL(
            configuredPath: externalToolStore.pythonPath
        ) == nil
            ? "Python 3 executable not found"
            : "Python 3 path saved"
    }

    func revealPythonPluginFolder() {
        do {
            _ = try workspaceItemCommandService
                .createDirectoryAndOpen(
                    AppPaths.pythonPluginDirectory
                )
        } catch {
            addSummary = "Plugin folder unavailable: \(AppLocalization.errorText(error))"
        }
    }

    private func preparePythonScriptDirectories() {
        try? FileManager.default.removeItem(at: AppPaths.pythonSessionScriptDirectory)
        try? AppPaths.ensureDirectory(AppPaths.pythonSessionScriptDirectory)
        try? AppPaths.ensureDirectory(AppPaths.pythonPluginDirectory)
    }

    private func confirmPythonScriptExecution(metadata: PythonScriptStaticMetadata, asPlugin: Bool) -> Bool {
        let author = metadata.author.trimmed.isEmpty ? "Unknown" : metadata.author
        let size = ByteCountFormatter.string(fromByteCount: Int64(metadata.byteCount), countStyle: .file)
        let signature = metadata.signature.trimmed.isEmpty
            ? "No script signature is present."
            : "A signature is present, but this port cannot verify the original app's signature format."
        let comment = metadata.comment.trimmed.isEmpty ? "" : "\n\n\(metadata.comment)"
        return confirmationDialogService.confirm(
            ConfirmationDialogRequest(
                style: .warning,
                message: asPlugin
                    ? "Install \(metadata.title)?"
                    : "Run \(metadata.title)?",
                informativeText:
                    "Author: \(author)\nEncoding: \(metadata.encoding) · \(size)\n\n\(signature)\nPython scripts can read or change files and access the network. Continue only if you trust this script.\(comment)",
                confirmButtonTitle: asPlugin
                    ? "Install Plugin"
                    : "Run Script",
                cancelButtonTitle: "Cancel"
            )
        )
    }

    private func sortPythonScriptPlugins() {
        pythonRuntimeStore.sortScriptPlugins { lhs, rhs in
            if lhs.isSession != rhs.isSession {
                return !lhs.isSession
            }
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private func refreshPythonThemeSelection() {
        let key = settingsStore.selectedPythonThemeKey
        let defaultLabel = AppLocalization.text("Default", language: settingsStore.interfaceLanguage)
        guard !key.isEmpty else {
            settingsStore.selectedPythonThemeKey = ""
            pythonRuntimeStore.setThemeStatus(
                "\(defaultLabel) · \(settingsStore.appAppearanceMode.label)"
            )
            return
        }
        guard let theme = themePresentationSnapshot.availableThemes.first(
            where: { $0.key == key }
        ) else {
            settingsStore.selectedPythonThemeKey = ""
            settingsStore.persistSelectedPythonThemeKey()
            pythonRuntimeStore.setThemeStatus(
                "\(defaultLabel) · \(settingsStore.appAppearanceMode.label)"
            )
            return
        }
        settingsStore.selectedPythonThemeKey = theme.key
        let appearance: String
        switch theme.appearance {
        case .system: appearance = settingsStore.appAppearanceMode.label
        case .light: appearance = AppLocalization.text("Light", language: settingsStore.interfaceLanguage)
        case .dark: appearance = AppLocalization.text("Dark", language: settingsStore.interfaceLanguage)
        }
        pythonRuntimeStore.setThemeStatus(
            "\(theme.displayName) · \(appearance)"
        )
    }

    private func refreshPythonScriptStatus() {
        let plugins = pythonRuntimeStore.scriptPlugins
        let enabled = plugins.filter(\.isEnabled).count
        let runtimeReady = PythonScriptBridge.pythonExecutableURL(
            configuredPath: externalToolStore.pythonPath
        ) != nil
        pythonRuntimeStore.setScriptStatus(
            runtimeReady
                ? "Python 3 Ready · \(enabled)/\(plugins.count) Enabled"
                : "Python 3 Missing · Select an Executable"
        )
        refreshPythonThemeSelection()
    }

    private func matchingPythonScriptPlugin(
        for url: URL
    ) -> (plugin: PythonScriptPlugin, downloader: PythonDownloaderDescriptor)? {
        for plugin in pythonRuntimeStore.scriptPlugins.reversed()
        where plugin.isEnabled {
            if let downloader = plugin.matchingDownloader(for: url) {
                return (plugin, downloader)
            }
        }
        return nil
    }

    private func effectivePythonHookCalls(
        for event: PythonHookEvent,
        matchingNames: Set<String>? = nil
    ) -> [EffectivePythonHookCall] {
        pythonHookRegistrationService.calls(
            for: event,
            matchingNames: matchingNames,
            plugins: pythonRuntimeStore.scriptPlugins
        )
    }

    private func runPythonHooks(
        event: PythonHookEvent,
        context initialContext: PythonHookContext,
        matchingNames: Set<String>? = nil
    ) async throws -> PythonHookContext {
        let calls = effectivePythonHookCalls(for: event, matchingNames: matchingNames)
        return try await pythonHookExecutionService.execute(
            event: event,
            initialContext: initialContext,
            calls: calls,
            configuredPythonPath: externalToolStore.pythonPath,
            reportStatus: { status in
                pythonRuntimeStore.setHookStatus(status)
            },
            recordLogs: { text, plugin, event in
                recordPythonHookLogs(
                    text,
                    plugin: plugin,
                    event: event
                )
            }
        )
    }

    private func runSyntheticPythonDownloadHooks(
        sourceURL: URL,
        title: String,
        filename: String? = nil,
        metadata: [String: String] = [:],
        jobIndex: Int
    ) async throws -> PythonHookContext? {
        guard queueStore.jobs.indices.contains(jobIndex) else {
            return nil
        }
        guard let context =
            try await syntheticPythonDownloadHookService.prepare(
                job: queueStore.jobs[jobIndex],
                sourceURL: sourceURL,
                title: title,
                filename: filename,
                metadata: metadata,
                requestOptions: { url in
                    requestOptions(for: url)
                },
                hasHooks: { event, names in
                    !effectivePythonHookCalls(
                        for: event,
                        matchingNames: names
                    ).isEmpty
                },
                runHooks: { event, hookContext, names in
                    try await runPythonHooks(
                        event: event,
                        context: hookContext,
                        matchingNames: names
                    )
                }
            ) else {
            return nil
        }
        applyPythonHookContext(context, toJobAt: jobIndex)
        queueStore.replaceJob(
            at: jobIndex,
            with: syntheticPythonDownloadHookService
                .markingDownloadHooksRan(queueStore.jobs[jobIndex])
        )
        persistQueue()
        return context
    }

    private func recordPythonHookLogs(_ text: String, plugin: PythonScriptPlugin, event: PythonHookEvent) {
        for record in pythonExecutionLogService.hookRecords(
            from: text,
            pluginTitle: plugin.title,
            eventLabel: event.shortLabel
        ) {
            recordActivity(record.message, category: record.category)
        }
    }

    private func recordPythonScriptLogs(_ text: String, plugin: PythonScriptPlugin, scope: String) {
        for record in pythonExecutionLogService.scriptRecords(
            from: text,
            pluginTitle: plugin.title,
            scope: scope
        ) {
            recordActivity(record.message, category: record.category)
        }
    }

    private func applyPythonHookContext(_ context: PythonHookContext, toJobAt index: Int) {
        guard queueStore.jobs.indices.contains(index) else { return }
        queueStore.replaceJob(
            at: index,
            with: pythonHookJobApplicationService.applying(
                context,
                to: queueStore.jobs[index]
            )
        )
        persistQueue()
    }

    @discardableResult
    func loadSiteRulePluginManifests(from directory: URL = AppPaths.pluginDirectory) -> Int {
        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            return 0
        }
        guard let enumerator = fileManager.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        let manifestURLs = enumerator
            .compactMap { $0 as? URL }
            .filter { url in
                guard url.pathExtension.lowercased() == "json" else { return false }
                let resourceValues = try? url.resourceValues(forKeys: [.isRegularFileKey])
                return resourceValues?.isRegularFile == true
            }
            .sorted { lhs, rhs in
                lhs.path.localizedStandardCompare(rhs.path) == .orderedAscending
            }

        let imported = manifestURLs.flatMap { url -> [SiteRule] in
            guard let data = try? Data(contentsOf: url),
                  let rules = try? ImportExportCodecService.siteRules(
                    from: data,
                    sourceURL: url
                  ) else {
                return []
            }
            return rules
        }

        return mergeImportedSiteRules(imported)
    }

    func enqueueBookmark(_ bookmark: URLBookmark) {
        let newJobs = jobsForAdding([bookmark.url])
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
    }

    func removeBookmark(_ bookmark: URLBookmark) {
        libraryStore.updateBookmarks {
            $0.removeAll { $0.id == bookmark.id }
        }
        persistBookmarks()
    }

    func sortBookmarksByTitle() {
        guard libraryStore.bookmarks.count > 1 else {
            addSummary = libraryStore.bookmarks.isEmpty
                ? "No bookmarks"
                : "Bookmarks already sorted"
            return
        }

        libraryStore.updateBookmarks { bookmarks in
            bookmarks.sort { lhs, rhs in
                let titleCompare = Self.bookmarkSortTitle(lhs)
                    .localizedStandardCompare(Self.bookmarkSortTitle(rhs))
                if titleCompare != .orderedSame {
                    return titleCompare == .orderedAscending
                }
                return lhs.url.localizedStandardCompare(rhs.url) == .orderedAscending
            }
        }
        persistBookmarks()
        addSummary = "Bookmarks sorted by name"
    }

    func clearBookmarks() {
        let removed = libraryStore.bookmarks.count
        guard removed > 0 else {
            addSummary = "No bookmarks"
            return
        }

        libraryStore.replaceBookmarks(with: [])
        presentation.editingBookmark = nil
        presentation.bookmarkFilter = ""
        persistBookmarks()
        addSummary = "\(removed) bookmarks cleared"
    }

    func beginEditingBookmark(_ bookmark: URLBookmark) {
        presentation.editingBookmark = bookmark
        presentation.bookmarkEditTitle = bookmark.title
        presentation.bookmarkEditTags = bookmark.tags.joined(separator: ", ")
        presentation.bookmarkEditNote = bookmark.note
    }

    func cancelEditingBookmark() {
        presentation.editingBookmark = nil
        presentation.bookmarkEditTitle = ""
        presentation.bookmarkEditTags = ""
        presentation.bookmarkEditNote = ""
    }

    func saveEditingBookmark() {
        guard let bookmark = presentation.editingBookmark else { return }
        updateBookmark(
            bookmark,
            title: presentation.bookmarkEditTitle,
            tagsText: presentation.bookmarkEditTags,
            note: presentation.bookmarkEditNote
        )
        cancelEditingBookmark()
    }

    func updateBookmark(_ bookmark: URLBookmark, title: String, tagsText: String, note: String) {
        guard let index = libraryStore.bookmarks.firstIndex(
            where: { $0.id == bookmark.id }
        ) else { return }
        let cleanedTitle = title.trimmed
        libraryStore.updateBookmarks { bookmarks in
            bookmarks[index].title = cleanedTitle.isEmpty
                ? ImportedCollectionMergeService.bookmarkTitle(
                    for: bookmarks[index].url
                )
                : cleanedTitle
            bookmarks[index].tags = ImportExportCodecService.bookmarkTags(
                from: tagsText
            )
            bookmarks[index].note = note.trimmed
        }
        persistBookmarks()
        addSummary = "Bookmark updated"
    }

    func beginEditingJob(_ job: DownloadJob) {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return }
        guard !isActive(current.status) else {
            addSummary = "Cancel active jobs before editing"
            return
        }
        queueEditorStore.beginEditingJob(
            current,
            namesText: Self.jobEditNamesText(for: current)
        )
        loadJobEditThumbnail(for: current, includeCustomOverride: true)
    }

    func cancelEditingJob() {
        jobEditThumbnailLoadCoordinator.cancelAndClear()
        queueEditorStore.resetJobEditing()
    }

    func saveEditingJob() {
        let editor = queueEditorStore
        guard let job = editor.editingJob else { return }
        var metadataUpdates = [
            "input": editor.jobEditInput,
            "artist": editor.jobEditArtist,
            "zipfile": editor.jobEditZipFile,
            "type": editor.jobEditType,
            "site": editor.jobEditSite,
            "date": editor.jobEditDate
        ]
        var newlyWrittenThumbnail: URL?
        if editor.jobEditThumbnailChanged {
            do {
                if let data = editor.jobEditThumbnailPNGData {
                    try AppPaths.ensureDirectory(AppPaths.customThumbnailDirectory)
                    let filename = "\(job.id.uuidString)-\(UUID().uuidString).png"
                    let url = AppPaths.customThumbnailDirectory.appendingPathComponent(filename)
                    try data.write(to: url, options: .atomic)
                    metadataUpdates[QueueThumbnailProvider.customThumbnailMetadataKey] = url.path
                    newlyWrittenThumbnail = url
                } else {
                    metadataUpdates[QueueThumbnailProvider.customThumbnailMetadataKey] = ""
                }
            } catch {
                addSummary = "Thumbnail update failed: \(AppLocalization.errorText(error))"
                return
            }
        }

        guard updateJob(
            job,
            title: editor.jobEditTitle,
            source: editor.jobEditSource,
            rangeExpression: editor.jobEditRange,
            comment: editor.jobEditComment,
            outputPath: editor.jobEditOutputPath,
            status: editor.jobEditStatus,
            metadataUpdates: metadataUpdates
        ) else {
            if let newlyWrittenThumbnail {
                try? FileManager.default.removeItem(at: newlyWrittenThumbnail)
            }
            return
        }
        if editor.jobEditThumbnailChanged {
            removeManagedCustomThumbnail(
                at: editor.jobEditOriginalThumbnailPath,
                keeping: newlyWrittenThumbnail
            )
            pruneManagedCustomThumbnails()
        }
        cancelEditingJob()
    }

    func selectJobEditThumbnail() {
        guard queueEditorStore.editingJob != nil else { return }
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        title: "Select Thumbnail",
                        prompt: "Select",
                        allowedContentTypes: [
                            .image
                        ]
                    )
                ) else {
            return
        }
        do {
            let data = try Data(contentsOf: url, options: [.mappedIfSafe])
            guard stageJobEditThumbnail(data: data) else { return }
            addSummary = "Custom thumbnail selected"
        } catch {
            queueEditorStore.jobEditThumbnailMessage =
                "Could not read thumbnail"
            addSummary = "Thumbnail selection failed: \(AppLocalization.errorText(error))"
        }
    }

    @discardableResult
    func stageJobEditThumbnail(data: Data) -> Bool {
        let editor = queueEditorStore
        guard editor.editingJob != nil,
              let staged =
                jobEditThumbnailImageService
                .stage(data: data) else {
            editor.jobEditThumbnailMessage = "Invalid image"
            return false
        }
        jobEditThumbnailLoadCoordinator.cancelAndClear()
        editor.jobEditThumbnailPNGData =
            staged.pngData
        editor.jobEditThumbnailImage = staged.image
        editor.jobEditThumbnailChanged = true
        editor.jobEditThumbnailIsCustom = true
        editor.jobEditThumbnailMessage = "Custom thumbnail"
        return true
    }

    func resetJobEditThumbnail() {
        let editor = queueEditorStore
        guard let job = editor.editingJob else { return }
        jobEditThumbnailLoadCoordinator.cancelAndClear()
        editor.jobEditThumbnailPNGData = nil
        editor.jobEditThumbnailChanged = true
        editor.jobEditThumbnailIsCustom = false
        editor.jobEditThumbnailImage = nil
        editor.jobEditThumbnailMessage = "Loading automatic thumbnail"
        var automaticJob = job
        automaticJob.metadata.removeValue(forKey: QueueThumbnailProvider.customThumbnailMetadataKey)
        loadJobEditThumbnail(for: automaticJob, includeCustomOverride: false)
    }

    func saveJobEditThumbnailAs() {
        let editor = queueEditorStore
        guard editor.jobEditThumbnailImage != nil else {
            editor.jobEditThumbnailMessage = "No thumbnail"
            return
        }
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        title: "Save Thumbnail",
                        prompt: "Save",
                        allowedContentTypes: [.png],
                        nameFieldStringValue:
                            "thumbnail.png"
                    )
                ) else {
            return
        }
        do {
            try exportJobEditThumbnail(to: url)
            addSummary = "Thumbnail saved"
        } catch {
            editor.jobEditThumbnailMessage = "Could not save thumbnail"
            addSummary = "Thumbnail save failed: \(AppLocalization.errorText(error))"
        }
    }

    func exportJobEditThumbnail(to url: URL) throws {
        let editor = queueEditorStore
        let data =
            editor.jobEditThumbnailPNGData ??
            editor.jobEditThumbnailImage.flatMap {
                jobEditThumbnailImageService
                    .pngData(from: $0)
            }
        guard let data else {
            throw NativeDownloadError.unsupported("No thumbnail is available.")
        }
        try data.write(to: url, options: .atomic)
    }

    private func loadJobEditThumbnail(for job: DownloadJob, includeCustomOverride: Bool) {
        let jobID = job.id
        let destination = settingsStore.destinationPath
        jobEditThumbnailLoadCoordinator.begin(
            job: job,
            destinationPath: destination,
            includeCustomOverride: includeCustomOverride,
            completion: { [weak self] image in
                guard let self,
                  self.queueEditorStore.editingJob?.id == jobID,
                  self.queueEditorStore.jobEditThumbnailPNGData == nil else {
                    return
                }
                let editor = self.queueEditorStore
                editor.jobEditThumbnailImage = image
                if image == nil {
                    editor.jobEditThumbnailMessage = "No thumbnail"
                } else {
                    editor.jobEditThumbnailMessage =
                        editor.jobEditThumbnailIsCustom
                        ? "Custom thumbnail"
                        : "Automatic thumbnail"
                }
            }
        )
    }

    private func removeManagedCustomThumbnail(at rawPath: String, keeping retainedURL: URL?) {
        guard let oldURL = managedCustomThumbnailURL(from: rawPath),
              oldURL.standardizedFileURL != retainedURL?.standardizedFileURL else {
            return
        }
        try? FileManager.default.removeItem(at: oldURL)
    }

    private func managedCustomThumbnailURL(from rawPath: String) -> URL? {
        let path = rawPath.trimmed
        guard !path.isEmpty else { return nil }
        let candidate: URL
        if let url = URL(string: path), url.isFileURL {
            candidate = url.standardizedFileURL
        } else {
            candidate = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        }
        let directory = AppPaths.customThumbnailDirectory.standardizedFileURL
        guard candidate.deletingLastPathComponent() == directory else { return nil }
        return candidate
    }

    private func pruneManagedCustomThumbnails(fileManager: FileManager = .default) {
        let directory = AppPaths.customThumbnailDirectory.standardizedFileURL
        guard let files = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return
        }
        let referenced = Set(queueStore.jobs.compactMap { job in
            managedCustomThumbnailURL(
                from: job.metadata[QueueThumbnailProvider.customThumbnailMetadataKey] ?? ""
            )?.standardizedFileURL.path
        })
        for file in files where !referenced.contains(file.standardizedFileURL.path) {
            try? fileManager.removeItem(at: file)
        }
    }

    func canOpenPageSelector(for job: DownloadJob) -> Bool {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return false }
        return localAPIPageSelectorFacade.pageTotal(
            for: current,
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        ) > 0 || !current.rangeExpression.trimmed.isEmpty
    }

    func beginPageSelector(for job: DownloadJob) {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return }
        let candidates = localAPIPageSelectorFacade.candidates(
            for: current,
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
        let total = localAPIPageSelectorFacade.pageTotal(
            for: current,
            candidateCount: candidates.count,
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
        guard total > 0 || !current.rangeExpression.trimmed.isEmpty else {
            addSummary = "No pages available"
            return
        }

        queueEditorStore.pageSelectorJob = current
        queueEditorStore.pageSelectorItems = candidates.prefix(2_000).map { candidate in
            PageSelectorItem(
                index: candidate.index,
                page: candidate.index + 1,
                title: candidate.title,
                detail: candidate.detail,
                type: candidate.type
            )
        }
        queueEditorStore.pageSelectorSelectedIndexes = Set(
            localAPIPageSelectorFacade.selectedIndexes(
                range: current.rangeExpression,
                total: total
            )
        )
        queueEditorStore.pageSelectorRangeText = current.rangeExpression
        queueEditorStore.pageSelectorMessage = pageSelectorStatusText(total: total)
    }

    func cancelPageSelector() {
        queueEditorStore.resetPageSelector()
    }

    func setPageSelectorItem(_ index: Int, selected: Bool) {
        if selected {
            queueEditorStore.pageSelectorSelectedIndexes.insert(index)
        } else {
            queueEditorStore.pageSelectorSelectedIndexes.remove(index)
        }
        updatePageSelectorRangeFromSelection()
    }

    func setPageSelectorRangeText(_ text: String) {
        queueEditorStore.pageSelectorRangeText = text
        syncPageSelectorSelectionFromRange()
    }

    func selectAllPageSelectorItems() {
        queueEditorStore.pageSelectorSelectedIndexes = Set(0..<pageSelectorTotal())
        queueEditorStore.pageSelectorRangeText = ""
        queueEditorStore.pageSelectorMessage = pageSelectorStatusText()
    }

    func savePageSelector() {
        guard let job = queueEditorStore.pageSelectorJob,
              let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            cancelPageSelector()
            return
        }
        guard !isActive(queueStore.jobs[index].status) else {
            queueEditorStore.pageSelectorMessage = "Cancel active jobs before editing pages"
            return
        }

        let range = queueEditorStore.pageSelectorRangeText.trimmed
        guard Self.isValidAssetRangeExpression(range) else {
            queueEditorStore.pageSelectorMessage = "Enter a valid range"
            return
        }
        let total = localAPIPageSelectorFacade.pageTotal(
            for: queueStore.jobs[index],
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
        if total > 0, !range.isEmpty {
            do {
                _ = try Self.assetIndexes(forRangeExpression: range, total: total)
            } catch {
                queueEditorStore.pageSelectorMessage = AppLocalization.errorText(error)
                return
            }
        }

        guard let updatedJob = queueStore.updateJob(at: index, {
            $0.rangeExpression = range
        }) else { return }
        if updatedJob.status == .finished {
            scheduleRestartIfNeeded(for: updatedJob)
        } else {
            cancelScheduledRestart(for: updatedJob.id)
        }
        addSummary = range.isEmpty ? "Page range cleared" : "Page range updated"
        persistQueue()
        cancelPageSelector()
    }

    private func updatePageSelectorRangeFromSelection() {
        let total = pageSelectorTotal()
        if total > 0, queueEditorStore.pageSelectorSelectedIndexes.count == total {
            queueEditorStore.pageSelectorRangeText = ""
        } else if queueEditorStore.pageSelectorSelectedIndexes.isEmpty {
            queueEditorStore.pageSelectorRangeText = "0"
        } else {
            queueEditorStore.pageSelectorRangeText = Self.compactRangeDescription(
                fromZeroBasedIndexes: queueEditorStore.pageSelectorSelectedIndexes.sorted()
            )
        }
        queueEditorStore.pageSelectorMessage = pageSelectorStatusText(total: total)
    }

    private func syncPageSelectorSelectionFromRange() {
        let total = pageSelectorTotal()
        guard total > 0 else {
            queueEditorStore.pageSelectorMessage = "No pages available"
            return
        }
        let range = queueEditorStore.pageSelectorRangeText.trimmed
        if range.isEmpty {
            queueEditorStore.pageSelectorSelectedIndexes = Set(0..<total)
            queueEditorStore.pageSelectorMessage = pageSelectorStatusText(total: total)
            return
        }
        guard Self.isValidAssetRangeExpression(range),
              let indexes = try? Self.assetIndexes(forRangeExpression: range, total: total) else {
            queueEditorStore.pageSelectorMessage = "Enter a valid range"
            return
        }
        queueEditorStore.pageSelectorSelectedIndexes = Set(indexes)
        queueEditorStore.pageSelectorMessage = pageSelectorStatusText(total: total)
    }

    private func pageSelectorTotal() -> Int {
        guard let job = queueEditorStore.pageSelectorJob,
              let current = queueStore.jobs.first(where: { $0.id == job.id }) else {
            return queueEditorStore.pageSelectorItems.count
        }
        return localAPIPageSelectorFacade.pageTotal(
            for: current,
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
    }

    private func pageSelectorStatusText(total: Int? = nil) -> String {
        let total = total ?? pageSelectorTotal()
        let selected = queueEditorStore.pageSelectorSelectedIndexes.count
        if queueEditorStore.pageSelectorItems.count < total {
            return "\(selected) / \(total) selected, showing \(queueEditorStore.pageSelectorItems.count)"
        }
        return "\(selected) / \(total) selected"
    }

    @discardableResult
    func updateJob(
        _ job: DownloadJob,
        title: String,
        source: String,
        rangeExpression: String,
        comment: String,
        outputPath: String? = nil,
        status: JobStatus? = nil,
        metadataUpdates: [String: String] = [:]
    ) -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return false }
        guard !isActive(queueStore.jobs[index].status) else {
            addSummary = "Cancel active jobs before editing"
            return false
        }

        let normalizedSource = Self.normalizedInputToken(source.trimmed)
        guard !normalizedSource.isEmpty else {
            addSummary = "Enter a URL"
            return false
        }

        let range = rangeExpression.trimmed
        guard Self.isValidAssetRangeExpression(range) else {
            addSummary = "Enter a valid range"
            return false
        }

        let jobID = queueStore.jobs[index].id
        guard let updatedJob = queueStore.updateJob(at: index, { queuedJob in
            queuedJob.source = normalizedSource
            queuedJob.title = title.trimmed.isEmpty ? normalizedSource : title.trimmed
            queuedJob.rangeExpression = range
            queuedJob.comment = comment.trimmed
            if let outputPath {
                queuedJob.outputPath = outputPath.trimmed
            }
            if let status {
                queuedJob.status = status
            }
            for (key, value) in metadataUpdates {
                let cleanedKey = key.trimmed
                guard !cleanedKey.isEmpty else { continue }
                let cleanedValue = value.trimmed
                if cleanedValue.isEmpty {
                    queuedJob.metadata.removeValue(forKey: cleanedKey)
                } else {
                    queuedJob.metadata[cleanedKey] = cleanedValue
                }
            }
            queuedJob.metadata["native_changed"] = "true"
        }) else { return false }
        if updatedJob.status == .finished {
            scheduleRestartIfNeeded(for: updatedJob)
        } else {
            cancelScheduledRestart(for: jobID)
        }
        addSummary = "Job updated"
        persistQueue()
        return true
    }

    private nonisolated static func jobEditNamesText(for job: DownloadJob, fileManager: FileManager = .default) -> String {
        let outputPath = job.outputPath.trimmed
        guard !outputPath.isEmpty else { return "" }

        let url = URL(fileURLWithPath: outputPath)
        var isDirectory = ObjCBool(false)
        if fileManager.fileExists(atPath: outputPath, isDirectory: &isDirectory), isDirectory.boolValue {
            let names = ((try? fileManager.contentsOfDirectory(atPath: outputPath)) ?? [])
                .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return names.prefix(500).joined(separator: "\n")
        }
        return url.lastPathComponent
    }

    func beginEditingJobComment(_ job: DownloadJob) {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return }
        queueEditorStore.beginEditingComments(for: [current])
    }

    func beginEditingJobComments(for selectedJobs: [DownloadJob]) {
        let selectedIDs = Set(selectedJobs.map(\.id))
        let current = queueStore.jobs.filter { selectedIDs.contains($0.id) }
        guard !current.isEmpty else { return }

        queueEditorStore.beginEditingComments(for: current)
    }

    func cancelEditingJobComment() {
        queueEditorStore.resetCommentEditing()
    }

    func saveEditingJobComment() {
        guard let job = queueEditorStore.editingCommentJob else { return }
        if queueEditorStore.editingCommentJobIDs.count > 1 {
            updateJobComments(
                queueEditorStore.editingCommentJobIDs,
                comment: queueEditorStore.jobCommentText
            )
        } else {
            updateJobComment(job, comment: queueEditorStore.jobCommentText)
        }
        cancelEditingJobComment()
    }

    func updateJobComment(_ job: DownloadJob, comment: String) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        guard let updatedJob = queueStore.updateJob(at: index, {
            $0.comment = comment.trimmed
        }) else { return }
        if updatedJob.status == .finished {
            scheduleRestartIfNeeded(for: updatedJob)
        } else {
            cancelScheduledRestart(for: updatedJob.id)
        }
        addSummary = updatedJob.comment.isEmpty ? "Comment cleared" : "Comment saved"
        persistQueue()
    }

    func updateJobComments(_ jobIDs: [UUID], comment: String) {
        let ids = Set(jobIDs)
        guard !ids.isEmpty else { return }

        let trimmed = comment.trimmed
        var updated = 0
        for index in queueStore.jobs.indices where ids.contains(queueStore.jobs[index].id) {
            guard let updatedJob = queueStore.updateJob(at: index, {
                $0.comment = trimmed
            }) else { continue }
            if updatedJob.status == .finished {
                scheduleRestartIfNeeded(for: updatedJob)
            } else {
                cancelScheduledRestart(for: updatedJob.id)
            }
            updated += 1
        }

        guard updated > 0 else { return }
        addSummary = trimmed.isEmpty ? "Comments cleared for \(updated) jobs" : "Comment saved for \(updated) jobs"
        persistQueue()
    }

    func clearHistory() {
        libraryStore.replaceHistory(with: [])
        persistHistory()
        addSummary = "History cleared"
    }

    func enqueueHistoryEntry(_ entry: DownloadHistoryEntry) {
        let requestMetadata = Self.mediaRequestMetadata(from: entry.metadata)
        let newJobs = jobsForAdding(
            [entry.source],
            checkHistory: false,
            metadata: requestMetadata,
            titleSuffix: DownloadRequestIdentityService
                .isAudioExtractionRequest(requestMetadata) ? " [MP3]" : ""
        )
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
    }

    func removeHistoryEntry(_ entry: DownloadHistoryEntry) {
        libraryStore.updateHistory {
            $0.removeAll { $0.id == entry.id }
        }
        persistHistory()
        addSummary = "History removed"
    }

    func revealHistoryOutput(_ entry: DownloadHistoryEntry) {
        guard let url = Self.revealURL(forOutputPath: entry.outputPath) else { return }
        _ = outputCommandService.reveal([url])
    }

    func setHistoryEnabled(_ enabled: Bool) {
        settingsStore.historyEnabled = enabled
        persistHistorySettings()
        addSummary = enabled ? "History on" : "History off"
    }

    func saveHistorySettings() {
        persistHistorySettings()
        trimHistoryToLimit()
        persistHistory()
        addSummary = settingsStore.historyEnabled ? "History saved" : "History off"
    }

    func addSiteRule() {
        let draft = presentation.settingsWindow
        let host = normalizedHostSuffix(draft.newSiteRuleHost)
        let urlPattern = SiteRule.normalizedURLPattern(
            draft.newSiteRuleURLPattern
        )
        let command = draft.newSiteRuleCommand.trimmed
        let referer = draft.newSiteRuleReferer.trimmed
        let userAgent = draft.newSiteRuleUserAgent.trimmed
        let hasHeaderOverrides = !referer.isEmpty || !userAgent.isEmpty
        guard !host.isEmpty else {
            addSummary = "Enter a host suffix"
            return
        }

        guard command.isEmpty || command.contains("{url}") else {
            addSummary = "Command must include {url}"
            return
        }

        let newRuleKey = "\(host)|\(urlPattern ?? "")"
        guard !libraryStore.siteRules.contains(
            where: { $0.matchKey == newRuleKey }
        ) else {
            addSummary = "Site rule already exists"
            return
        }

        let name = draft.newSiteRuleName.trimmed.isEmpty
            ? host
            : draft.newSiteRuleName.trimmed
        libraryStore.updateSiteRules {
            $0.append(SiteRule(
                id: UUID(),
                name: name,
                hostSuffix: host,
                urlPattern: urlPattern,
                handler: command.isEmpty
                    ? (hasHeaderOverrides ? .headers : .ytdlp)
                    : .customCommand,
                commandTemplate: command.isEmpty ? nil : command,
                refererTemplate: referer.isEmpty ? nil : referer,
                userAgent: userAgent.isEmpty ? nil : userAgent,
                archiveMode: draft.newSiteRuleArchiveMode,
                deleteOriginalAfterArchiving:
                    draft.newSiteRuleArchiveMode.archives &&
                    draft.newSiteRuleDeleteOriginalAfterArchiving,
                createdAt: Date()
            ))
        }
        persistSiteRules()
        draft.resetSiteRuleDraft()
        addSummary = "Site rule saved"
    }

    func removeSiteRule(_ rule: SiteRule) {
        libraryStore.updateSiteRules {
            $0.removeAll { $0.id == rule.id }
        }
        persistSiteRules()
        addSummary = "Site rule removed"
    }

    func setSiteRuleEnabled(_ rule: SiteRule, enabled: Bool) {
        guard let index = libraryStore.siteRules.firstIndex(
            where: { $0.id == rule.id }
        ) else { return }
        guard libraryStore.siteRules[index].isEnabled != enabled else { return }
        libraryStore.updateSiteRules {
            $0[index].isEnabled = enabled
        }
        persistSiteRules()
        addSummary = enabled ? "Site rule enabled" : "Site rule disabled"
    }

    @discardableResult
    private func mergeImportedSiteRules(_ imported: [SiteRule]) -> Int {
        var added = 0
        var mergedRules = libraryStore.siteRules
        var existingRuleKeys = Set(
            mergedRules.map(\.matchKey).filter { !$0.hasPrefix("|") }
        )
        var existingIDs = Set(mergedRules.map(\.id))

        for rule in imported {
            guard var normalized = normalizedImportedSiteRule(rule) else { continue }
            guard !existingRuleKeys.contains(normalized.matchKey) else { continue }
            if existingIDs.contains(normalized.id) {
                normalized.id = UUID()
            }
            existingRuleKeys.insert(normalized.matchKey)
            existingIDs.insert(normalized.id)
            mergedRules.append(normalized)
            added += 1
        }

        guard added > 0 else { return 0 }
        libraryStore.replaceSiteRules(with: mergedRules)
        persistSiteRules()
        return added
    }

    private func normalizedImportedSiteRule(_ rule: SiteRule) -> SiteRule? {
        let host = normalizedHostSuffix(rule.hostSuffix)
        guard !host.isEmpty else { return nil }
        let urlPattern = SiteRule.normalizedURLPattern(rule.urlPattern)
        let name = rule.name.trimmed.isEmpty ? host : rule.name.trimmed
        let command = rule.commandTemplate?.trimmed ?? ""
        guard command.isEmpty || command.contains("{url}") else { return nil }
        let referer = rule.refererTemplate?.trimmed ?? ""
        let userAgent = rule.userAgent?.trimmed ?? ""
        let hasHeaderOverrides = !referer.isEmpty || !userAgent.isEmpty

        let resolvedHandler: SiteRuleHandler
        if !command.isEmpty {
            resolvedHandler = .customCommand
        } else if rule.handler == .ytdlp {
            resolvedHandler = .ytdlp
        } else if hasHeaderOverrides {
            resolvedHandler = .headers
        } else {
            resolvedHandler = .ytdlp
        }

        return SiteRule(
            id: rule.id,
            name: name,
            hostSuffix: host,
            urlPattern: urlPattern,
            handler: resolvedHandler,
            commandTemplate: command.isEmpty ? nil : command,
            refererTemplate: referer.isEmpty ? nil : referer,
            userAgent: userAgent.isEmpty ? nil : userAgent,
            environment: rule.environment,
            options: rule.options,
            workingDirectoryTemplate: rule.workingDirectoryTemplate,
            archiveMode: rule.archiveMode,
            deleteOriginalAfterArchiving: rule.deleteOriginalAfterArchiving,
            isEnabled: rule.isEnabled,
            createdAt: rule.createdAt
        )
    }

    func addSearchProvider() {
        let name = searchStore.newSearchProviderName.trimmed
        let template = searchStore.newSearchProviderTemplate.trimmed

        guard !name.isEmpty, Self.isValidSearchTemplate(template) else {
            addSummary = "Enter a valid search template"
            return
        }

        searchStore.updateSearchProviders {
            $0.append(SearchProvider(
                id: UUID(),
                name: name,
                urlTemplate: template,
                createdAt: Date()
            ))
        }
        searchStore.selectedSearchProviderID =
            searchStore.searchProviders.last?.id
            ?? searchStore.selectedSearchProviderID
        persistSearchProviders()
        searchStore.newSearchProviderName = ""
        searchStore.newSearchProviderTemplate = ""
        addSummary = "Search provider saved"
    }

    func removeSearchProvider(_ provider: SearchProvider) {
        searchStore.updateSearchProviders {
            $0.removeAll { $0.id == provider.id }
        }
        if searchStore.selectedSearchProviderID == provider.id {
            searchStore.selectedSearchProviderID =
                searchStore.searchProviders.first?.id
                ?? SearchProvider.defaultProviders[0].id
        }
        persistSearchProviders()
        addSummary = "Search provider removed"
    }

    func moveSearchProvider(_ provider: SearchProvider, by offset: Int) {
        guard offset != 0,
              let index = searchStore.searchProviders.firstIndex(where: {
                  $0.id == provider.id
              }) else {
            return
        }
        let destination = index + offset
        guard searchStore.searchProviders.indices.contains(destination) else {
            addSummary = offset < 0 ? "Search provider already first" : "Search provider already last"
            return
        }
        searchStore.updateSearchProviders {
            $0.swapAt(index, destination)
        }
        persistSearchProviders()
        addSummary = "Search provider order saved"
    }

    func importSearchProviders() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ]
                    )
                ) else {
            return
        }
        do {
            _ = try importSearchProviders(from: url)
        } catch {
            addSummary = "Search provider import failed"
        }
    }

    func exportSearchProviders() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-SearchProviders.json"
                    )
                ) else {
            return
        }
        do {
            try exportSearchProviders(to: url)
        } catch {
            addSummary = "Search provider export failed"
        }
    }

    @discardableResult
    func importSearchProviders(from url: URL) throws -> Int {
        let imported = try ImportExportCodecService.searchProviders(
            from: try Data(contentsOf: url)
        )
        let added = mergeSearchProviders(imported)
        addSummary = added == 0 ? "No new search providers" : "\(added) search providers imported"
        return added
    }

    func exportSearchProviders(to url: URL) throws {
        let data = try ImportExportCodecService.searchProviderData(
            searchStore.searchProviders,
            destinationURL: url
        )
        try data.write(to: url, options: .atomic)
        addSummary =
            "\(searchStore.searchProviders.count) search providers exported"
    }

    func saveCurrentSearchBookmark() {
        let query = searchStore.searchQuery.trimmed
        guard !query.isEmpty else {
            addSummary = "Enter a search query"
            return
        }
        guard let provider = currentSearchProvider() else {
            addSummary = "No search provider"
            return
        }

        let key = Self.searchBookmarkKey(providerName: provider.name, query: query)
        searchStore.updateSearchBookmarks { bookmarks in
            bookmarks.removeAll {
                Self.searchBookmarkKey(
                    providerName: $0.providerName,
                    query: $0.query
                ) == key
            }
            bookmarks.insert(SearchBookmark(
                title: Self.searchBookmarkTitle(
                    providerName: provider.name,
                    query: query
                ),
                providerID: provider.id,
                providerName: provider.name,
                query: query
            ), at: 0)
        }
        persistSearchBookmarks()
        addSummary = "Search bookmark saved"
    }

    func importSearchBookmarks() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ]
                    )
                ) else {
            return
        }
        do {
            _ = try importSearchBookmarks(from: url)
        } catch {
            addSummary = "Search bookmark import failed"
        }
    }

    func exportSearchBookmarks() {
        guard let url =
            documentPanelCommandService
                .chooseSaveURL(
                    SaveDocumentPanelRequest(
                        allowedContentTypes: [
                            .json,
                            .plainText,
                            .text
                        ],
                        nameFieldStringValue:
                            "HitomiBadayo-SearchBookmarks.json"
                    )
                ) else {
            return
        }
        do {
            try exportSearchBookmarks(to: url)
        } catch {
            addSummary = "Search bookmark export failed"
        }
    }

    @discardableResult
    func importSearchBookmarks(from url: URL) throws -> Int {
        let imported = try ImportExportCodecService.searchBookmarks(
            from: try Data(contentsOf: url)
        )
        let added = mergeSearchBookmarks(imported)
        addSummary = added == 0 ? "No new search bookmarks" : "\(added) search bookmarks imported"
        return added
    }

    func exportSearchBookmarks(to url: URL) throws {
        let data = try ImportExportCodecService.searchBookmarkData(
            searchStore.searchBookmarks,
            destinationURL: url
        )
        try data.write(to: url, options: .atomic)
        addSummary =
            "\(searchStore.searchBookmarks.count) search bookmarks exported"
    }

    func applySearchBookmark(_ bookmark: SearchBookmark) {
        if let provider = Self.searchProvider(
            for: bookmark,
            in: searchStore.searchProviders
        ) {
            searchStore.selectedSearchProviderID = provider.id
        }
        searchStore.searchQuery = bookmark.query
        addSummary = "Search bookmark applied"
    }

    func enqueueSearchBookmark(_ bookmark: SearchBookmark) {
        guard let provider = Self.searchProvider(
                  for: bookmark,
                  in: searchStore.searchProviders
              ),
              let url = Self.searchURL(provider: provider, query: bookmark.query) else {
            addSummary = "Search provider not found"
            return
        }
        let newJobs = jobsForAdding([url.absoluteString])
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
    }

    func removeSearchBookmark(_ bookmark: SearchBookmark) {
        searchStore.updateSearchBookmarks {
            $0.removeAll { $0.id == bookmark.id }
        }
        persistSearchBookmarks()
        addSummary = "Search bookmark removed"
    }

    func resetSearchProviders() {
        searchStore.replaceSearchProviders(
            with: SearchProvider.defaultProviders
        )
        searchStore.selectedSearchProviderID =
            SearchProvider.defaultProviders[0].id
        persistSearchProviders()
        addSummary = "Search providers reset"
    }

    func setSearchDeduplicateResults(_ enabled: Bool) {
        settingsStore.searchDeduplicateResults = enabled
        settingsStore.persistSearchResultPreferences()
        if enabled {
            searchStore.replaceSearchResults(
                with: Self.processedSearchResults(
                    searchStore.searchResults,
                    deduplicate: true,
                    hideKnown: settingsStore.searchHideKnownResults,
                    knownSources: searchKnownSources(),
                    excludedHitomiTags: currentHitomiExcludedTags()
                )
            )
        }
        addSummary = enabled ? "Search dedup on" : "Search dedup off"
    }

    func setSearchHideKnownResults(_ enabled: Bool) {
        settingsStore.searchHideKnownResults = enabled
        settingsStore.persistSearchResultPreferences()
        if enabled {
            searchStore.replaceSearchResults(
                with: Self.processedSearchResults(
                    searchStore.searchResults,
                    deduplicate: settingsStore.searchDeduplicateResults,
                    hideKnown: true,
                    knownSources: searchKnownSources(),
                    excludedHitomiTags: currentHitomiExcludedTags()
                )
            )
        }
        addSummary = enabled ? "Known search results hidden" : "Known search results shown"
    }

    func saveHitomiExcludedTags() {
        let tags = Self.hitomiExcludedTags(
            from: settingsStore.hitomiExcludedTagsText
        )
        settingsStore.hitomiExcludedTagsText = tags.joined(separator: ", ")
        settingsStore.persistHitomiExcludedTags()
        if !tags.isEmpty {
            searchStore.replaceSearchResults(
                with: Self.processedSearchResults(
                    searchStore.searchResults,
                    deduplicate: settingsStore.searchDeduplicateResults,
                    hideKnown: settingsStore.searchHideKnownResults,
                    knownSources: searchKnownSources(),
                    excludedHitomiTags: tags
                )
            )
        }
        addSummary = tags.isEmpty ? "Hitomi excluded tags cleared" : "\(tags.count) Hitomi excluded tags saved"
    }

    func clearHitomiExcludedTags() {
        settingsStore.hitomiExcludedTagsText = ""
        settingsStore.persistHitomiExcludedTags()
        addSummary = "Hitomi excluded tags cleared"
    }

    func applyHitomiAdvancedSearchQuery() {
        let query = currentHitomiAdvancedSearchQuery()
        guard !query.isEmpty else {
            addSummary = "Enter Hitomi search fields"
            return
        }
        searchStore.searchQuery = query
        selectHitomiSearchProvider()
        addSummary = "Hitomi advanced query applied"
    }

    func appendHitomiAdvancedSearchQuery() {
        let query = currentHitomiAdvancedSearchQuery()
        guard !query.isEmpty else {
            addSummary = "Enter Hitomi search fields"
            return
        }
        searchStore.searchQuery = SearchTagTranslationService
            .appendingQueryToken(query, to: searchStore.searchQuery)
        selectHitomiSearchProvider()
        addSummary = "Hitomi advanced query added"
    }

    func clearHitomiAdvancedSearchFields() {
        searchStore.clearHitomiAdvancedSearchFields()
        addSummary = "Hitomi advanced fields cleared"
    }

    func translateSearchTagInput() {
        let translated = Self.translatedSearchQueryTags(
            from: searchStore.searchTagTranslationInput
        )
        searchStore.searchTagTranslationOutput = translated
        addSummary = translated.isEmpty ? "No tag translation" : "Search tag translated"
    }

    func insertTranslatedSearchTag() {
        let translated = currentTranslatedSearchTag()
        guard !translated.isEmpty else {
            addSummary = "No tag translation"
            return
        }
        searchStore.searchQuery = SearchTagTranslationService
            .appendingQueryToken(translated, to: searchStore.searchQuery)
        searchStore.searchTagTranslationOutput = translated
        addSummary = "Translated tag inserted"
    }

    func replaceSearchQueryWithTranslatedTag() {
        let translated = currentTranslatedSearchTag()
        guard !translated.isEmpty else {
            addSummary = "No tag translation"
            return
        }
        searchStore.searchQuery = translated
        searchStore.searchTagTranslationOutput = translated
        addSummary = "Search query replaced"
    }

    func clearSearchTagTranslation() {
        searchStore.clearSearchTagTranslation()
        addSummary = "Tag translation cleared"
    }

    func applySearchTagSuggestion(_ suggestion: SearchTagSuggestion) {
        searchStore.searchTagTranslationInput = suggestion.token
        searchStore.searchTagTranslationOutput = Self.translatedSearchQueryTags(
            from: suggestion.token
        )
        addSummary = "Tag suggestion selected"
    }

    func insertSearchTagSuggestion(_ suggestion: SearchTagSuggestion) {
        let translated = Self.translatedSearchQueryTags(from: suggestion.token)
        guard !translated.isEmpty else {
            addSummary = "No tag translation"
            return
        }
        searchStore.searchTagTranslationInput = suggestion.token
        searchStore.searchTagTranslationOutput = translated
        searchStore.searchQuery = SearchTagTranslationService
            .appendingQueryToken(translated, to: searchStore.searchQuery)
        addSummary = "Suggested tag inserted"
    }

    func openSearchURL() {
        guard let url = builtSearchURL() else {
            addSummary = "Enter a search query"
            return
        }
        searchUICommandFacade.openSearchURL(url)
    }

    func enqueueSearchURL() {
        guard let url = builtSearchURL() else {
            addSummary = "Enter a search query"
            return
        }
        let newJobs = jobsForAdding([url.absoluteString])
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
    }

    func fetchSearchResults() {
        guard let url = builtSearchURL() else {
            addSummary = "Enter a search query"
            return
        }
        guard persistProxySettingsForUse() else { return }

        cancelSearchResultsFetch(announce: false)
        searchStore.isSearching = true
        addSummary = "Searching"
        let headers = requestOptions(for: url)
        searchExecutionFacade.begin(
            url: url,
            options: headers,
            processResults: { [weak self] links in
                guard let self else { return [] }
                return Self.processedSearchResults(
                    links,
                    deduplicate: settingsStore.searchDeduplicateResults,
                    hideKnown: settingsStore.searchHideKnownResults,
                    knownSources: searchKnownSources(),
                    excludedHitomiTags: currentHitomiExcludedTags()
                )
            },
            completion: { [weak self] outcome in
                guard let self else { return }
                searchStore.isSearching = false
                switch outcome {
                case .success(let rawCount, let processed):
                    searchStore.replaceSearchResults(with: processed)
                    let hidden = max(0, rawCount - processed.count)
                    if processed.isEmpty {
                        addSummary = hidden > 0
                            ? "No new search results"
                            : "No search results"
                    } else {
                        addSummary = hidden > 0
                            ? "\(processed.count) search results, \(hidden) hidden"
                            : "\(processed.count) search results"
                    }
                case .cancelled:
                    addSummary = "Search cancelled"
                case .failed:
                    addSummary = "Search failed"
                }
            }
        )
    }

    func cancelSearchResultsFetch() {
        cancelSearchResultsFetch(announce: true)
    }

    private func cancelSearchResultsFetch(announce: Bool) {
        guard searchExecutionFacade.hasActiveRequest ||
                searchStore.isSearching else {
            return
        }
        searchExecutionFacade.cancel()
        searchStore.isSearching = false
        if announce {
            addSummary = "Search cancelled"
        }
    }

    func enqueueSearchResult(_ result: SearchResultLink) {
        let newJobs = jobsForAddingSearchResults([result])
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
    }

    nonisolated static func searchResultBrowserURL(for result: SearchResultLink) -> URL? {
        SearchUICommandFacade.browserURL(for: result)
    }

    nonisolated static func searchResultCopyTitle(for result: SearchResultLink) -> String? {
        SearchUICommandFacade.copyTitle(for: result)
    }

    func openSearchResult(_ result: SearchResultLink) {
        if let summary = searchUICommandFacade.openResult(result) {
            addSummary = summary
        }
    }

    func copySearchResultURL(_ result: SearchResultLink) {
        addSummary = searchUICommandFacade.copyResultURL(result)
    }

    func copySearchResultTitle(_ result: SearchResultLink) {
        addSummary = searchUICommandFacade.copyResultTitle(result)
    }

    nonisolated static func searchResultMetadataCopies(for result: SearchResultLink) -> [SearchResultMetadataCopy] {
        SearchResultMetadataService.copies(for: result)
    }

    nonisolated static func searchResultDateText(for result: SearchResultLink) -> String? {
        SearchResultMetadataService.dateText(for: result)
    }

    nonisolated static func searchResultPageCountText(for result: SearchResultLink) -> String? {
        SearchResultMetadataService.pageCountText(for: result)
    }

    func copySearchResultMetadata(_ item: SearchResultMetadataCopy) {
        addSummary = searchUICommandFacade.copyMetadata(
            label: item.label,
            value: item.value
        )
    }

    private nonisolated static func searchResultPageCount(for result: SearchResultLink) -> Int? {
        SearchResultMetadataService.pageCount(for: result)
    }

    func enqueueAllSearchResults() {
        let newJobs = jobsForAddingSearchResults(
            searchPresentationSnapshot.filteredResults
        )
        guard !newJobs.isEmpty else { return }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
    }

    nonisolated static func filteredSearchResults(
        _ results: [SearchResultLink],
        filter: String,
        knownSources: Set<String>
    ) -> [SearchResultLink] {
        SearchResultFilterEngine.filteredSearchResults(
            results,
            filter: filter,
            knownSources: knownSources
        )
    }

    nonisolated static func filteredSearchResults(
        _ results: [SearchResultLink],
        knownFilter: SearchResultKnownFilter,
        knownSources: Set<String>
    ) -> [SearchResultLink] {
        SearchResultFilterEngine.filteredSearchResults(
            results,
            knownFilter: knownFilter,
            knownSources: knownSources
        )
    }

    nonisolated static func processedSearchResults(
        _ results: [SearchResultLink],
        deduplicate: Bool,
        hideKnown: Bool,
        knownSources: Set<String>,
        excludedHitomiTags: [String] = []
    ) -> [SearchResultLink] {
        SearchResultFilterEngine.processedSearchResults(
            results,
            deduplicate: deduplicate,
            hideKnown: hideKnown,
            knownSources: knownSources,
            excludedHitomiTags: excludedHitomiTags
        )
    }

    private nonisolated static func searchResultFilterReferencesKnownSources(_ filter: String) -> Bool {
        SearchResultFilterEngine.searchResultFilterReferencesKnownSources(filter)
    }

    nonisolated static func hitomiExcludedTags(from text: String) -> [String] {
        SearchResultFilterEngine.hitomiExcludedTags(from: text)
    }
    private func currentHitomiExcludedTags() -> [String] {
        Self.hitomiExcludedTags(from: settingsStore.hitomiExcludedTagsText)
    }

    private func currentHitomiAdvancedSearchQuery() -> String {
        searchStore.hitomiAdvancedSearchQuery
    }

    nonisolated static func hitomiAdvancedSearchQuery(
        title: String,
        artist: String,
        group: String,
        series: String,
        character: String,
        tag: String,
        language: String,
        types: Set<HitomiAdvancedSearchType>,
        languagePreset: HitomiAdvancedLanguagePreset = .all,
        excludeWebtoon: Bool = false
    ) -> String {
        SearchTagTranslationService.advancedSearchQuery(
            title: title,
            artist: artist,
            group: group,
            series: series,
            character: character,
            tag: tag,
            language: language,
            types: types,
            languagePreset: languagePreset,
            excludeWebtoon: excludeWebtoon
        )
    }

    nonisolated static func translatedSearchQueryTags(from text: String) -> String {
        SearchTagTranslationService.translatedQueryTags(from: text)
    }

    nonisolated static func searchTagSuggestions(for text: String, limit: Int = 8) -> [SearchTagSuggestion] {
        SearchTagTranslationService.suggestions(for: text, limit: limit)
    }

    nonisolated static func translatedSearchTagToken(_ raw: String) -> String? {
        SearchTagTranslationService.translatedTagToken(raw)
    }

    private func currentTranslatedSearchTag() -> String {
        searchStore.translatedSearchTag
    }

    private func searchKnownSources() -> Set<String> {
        searchPresentationSnapshot.knownState.sources
    }

    nonisolated static func searchKnownSources(
        jobs inputJobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        destinationPath: String,
        fileManager: FileManager = .default
    ) -> Set<String> {
        SearchResultKnownStateService.knownState(
            jobs: inputJobs,
            history: history,
            destinationPath: destinationPath,
            fileManager: fileManager
        ).sources
    }

    nonisolated static func searchResultKnownState(
        jobs inputJobs: [DownloadJob],
        history: [DownloadHistoryEntry],
        destinationPath: String,
        fileManager: FileManager = .default
    ) -> SearchResultKnownState {
        SearchResultKnownStateService.knownState(
            jobs: inputJobs,
            history: history,
            destinationPath: destinationPath,
            fileManager: fileManager
        )
    }

    nonisolated static func searchResultIsKnown(
        _ result: SearchResultLink,
        knownState: SearchResultKnownState
    ) -> Bool {
        SearchResultKnownStateService.isKnown(
            result,
            knownState: knownState
        )
    }

    nonisolated static func searchResultFirstOutputOpenURL(
        for result: SearchResultLink,
        knownState: SearchResultKnownState,
        fileManager: FileManager = .default
    ) -> URL? {
        SearchResultKnownStateService.firstOutputOpenURL(
            for: result,
            knownState: knownState,
            fileManager: fileManager
        )
    }

    func openFirstOutputFile(forSearchResult result: SearchResultLink) {
        let url = Self.searchResultFirstOutputOpenURL(
            for: result,
            knownState: searchPresentationSnapshot.knownState
        )
        if let summary = searchUICommandFacade.openOutput(url) {
            addSummary = summary
        }
    }

    nonisolated static func searchResultGalleryID(for result: SearchResultLink) -> String? {
        SearchUICommandFacade.galleryID(for: result)
    }

    func copySearchResultGalleryID(_ result: SearchResultLink) {
        addSummary = searchUICommandFacade.copyGalleryID(result)
    }

    nonisolated static func hitomiSearchResultKeys(forGalleryID id: String) -> Set<String> {
        SearchResultKnownStateService.hitomiResultKeys(
            forGalleryID: id
        )
    }

    @discardableResult
    func clearFinished() -> Int {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before clearing finished jobs"
            return 0
        }

        let removableIDs = Set(queueStore.jobs.filter(isRemovableFinishedJob).map(\.id))
        removableIDs.forEach { cancelScheduledRestart(for: $0) }
        let removedJobs = queueStore.removeJobs(withIDs: removableIDs)
        addSummary = removedJobs.isEmpty
            ? "No removable finished jobs"
            : "\(removedJobs.count) finished jobs cleared"
        persistQueue()
        return removedJobs.count
    }

    func setSelectedJobIDs(_ ids: Set<UUID>) {
        let validIDs = Set(queueStore.jobs.lazy.filter { !Self.isPendingQueueRemoval($0) }.map(\.id))
        presentation.selectedJobIDs = ids.intersection(validIDs)
    }

    func selectRandomVisibleJob(randomIndex: ((Int) -> Int)? = nil) {
        let visibleJobs = queuePresentationSnapshot.filteredJobs
        let currentID = visibleJobs.first(where: { presentation.selectedJobIDs.contains($0.id) })?.id
        let candidates = visibleJobs.filter { $0.id != currentID }
        guard !candidates.isEmpty else {
            addSummary = "No other visible jobs"
            return
        }

        let proposedIndex = randomIndex?(candidates.count) ?? Int.random(in: candidates.indices)
        let index = min(max(0, proposedIndex), candidates.count - 1)
        let selected = candidates[index]
        setSelectedJobIDs([selected.id])
        addSummary = "Selected \(selected.title.isEmpty ? selected.source : selected.title)"
    }

    func openShortcutSettings() {
        beginEditingShortcut(presentation.shortcutEditorCommand)
        appCommandService.openShortcutSettings()
    }

    func openFloatingMonitor() {
        appCommandService.setFloatingMonitorVisible(true)
        addSummary = "Floating monitor shown"
    }

    func closeFloatingMonitor() {
        appCommandService.setFloatingMonitorVisible(false)
        addSummary = "Floating monitor hidden"
    }

    func toggleFloatingMonitor() {
        presentation.showingFloatingMonitor ? closeFloatingMonitor() : openFloatingMonitor()
    }

    func openClipboardViewer() {
        refreshClipboardViewer()
        appCommandService.openClipboardViewer()
    }

    func openBrowserWindow() {
        refreshBrowserWindowURL()
        appCommandService.openBrowserWindow()
    }

    func openTextViewer() {
        ensureTextViewerSelection()
        appCommandService.openTextViewer()
    }

    func clearSelectedJobs() {
        presentation.selectedJobIDs.removeAll()
    }

    func setAutoRemoveFinishedJobs(_ enabled: Bool) {
        settingsStore.autoRemoveFinishedJobs = enabled
        settingsStore.persistAutoRemoveSettings()
        addSummary = enabled ? "Auto remove finished on" : "Auto remove finished off"
    }

    func saveAutoRemoveHookCommand() {
        settingsStore.persistAutoRemoveSettings()
        appStatusStore.setAutoRemoveHookStatus(
            settingsStore.autoRemoveHookCommand.trimmed.isEmpty
                ? "Auto-remove Hook Off"
                : "Auto-remove Hook Saved"
        )
        addSummary = appStatusStore.autoRemoveHookStatus
    }

    func setShowDownloadDate(_ enabled: Bool) {
        settingsStore.showDownloadDate = enabled
        settingsStore.persistOutputPresentation()
        addSummary = enabled ? "Download date display on" : "Download date display off"
    }

    func setNumberPlaylistFiles(_ enabled: Bool) {
        settingsStore.numberPlaylistFiles = enabled
        settingsStore.persistOutputPresentation()
        addSummary = enabled ? "Playlist numbering on" : "Playlist numbering off"
    }

    func setRetryIncompleteAutomatically(_ enabled: Bool) {
        settingsStore.retryIncompleteAutomatically = enabled
        settingsStore.persistIncompleteRetry()
        addSummary = enabled ? "Incomplete retry on" : "Incomplete retry off"
    }

    func setIncompleteRetryDelay(_ delay: IncompleteRetryDelay) {
        settingsStore.incompleteRetryDelay = delay
        settingsStore.persistIncompleteRetry()
        addSummary = "Incomplete retry delay set to \(delay.label)"
    }

    func setSkipDuplicates(_ enabled: Bool) {
        settingsStore.skipDuplicates = enabled
        settingsStore.persistSkipDuplicates()
        addSummary = enabled ? "Duplicate skip on" : "Duplicate skip off"
    }

    func setPreferWebP(_ enabled: Bool) {
        settingsStore.preferWebP = enabled
        settingsStore.persistPreferWebP()
        addSummary = enabled ? "Hitomi WebP on" : "Hitomi WebP off"
    }

    func setEHentaiSourceMode(_ mode: EHentaiSourceMode) {
        settingsStore.eHentaiSourceMode = mode
        settingsStore.persistEHentaiSourceMode()
        addSummary = "E-Hentai source: \(mode.label)"
    }

    func setPreferOriginalEHentaiImages(_ enabled: Bool) {
        settingsStore.preferOriginalEHentaiImages = enabled
        settingsStore.persistPreferOriginalEHentaiImages()
        addSummary = enabled ? "E-Hentai original images on" : "E-Hentai original images off"
    }

    func setPreferJapaneseEHentaiTitle(_ enabled: Bool) {
        settingsStore.preferJapaneseEHentaiTitle = enabled
        settingsStore.persistPreferJapaneseEHentaiTitle()
        addSummary = enabled ? "E-Hentai Japanese title on" : "E-Hentai Japanese title off"
    }

    func setSaveHitomiGalleryInfoText(_ enabled: Bool) {
        settingsStore.saveHitomiGalleryInfoText = enabled
        settingsStore.persistSaveHitomiGalleryInfoText()
        addSummary = enabled ? "Hitomi info TXT on" : "Hitomi info TXT off"
    }

    func setAppAppearanceMode(_ mode: AppAppearanceMode) {
        guard settingsStore.appAppearanceMode != mode else { return }
        settingsStore.appAppearanceMode = mode
        settingsStore.persistAppAppearance()
        refreshPythonThemeSelection()
        addSummary = "Appearance set to \(mode.label)"
    }

    func setInterfaceLanguage(_ language: AppInterfaceLanguage) {
        guard settingsStore.interfaceLanguage != language else { return }
        settingsStore.interfaceLanguage = language
        applicationMenuCommandService
            .applyInterfaceLanguage(language)
        settingsStore.persistInterfaceLanguage()
        refreshLanguageDependentSummaries()
        NotificationCenter.default.post(
            name: .hitomiBadayoInterfaceLanguageDidChange,
            object: language
        )
        addSummary = AppLocalization.format(
            "Display language changed to %@",
            language: language,
            language.displayName
        )
    }

    private func refreshLanguageDependentSummaries() {
        appStatusStore.setQueueCompletionActionStatus(
            Self.queueCompletionActionStatusText(
                for: settingsStore.queueCompletionAction
            )
        )
        refreshPythonThemeSelection()
        if cookieStatusStore.isClearing {
            cookieStatusStore.setSummary(AppLocalization.text(
                "Deleting cookies and login sessions...",
                language: settingsStore.interfaceLanguage
            ))
        } else if cookieStatusStore.summary == "No cookies" {
            cookieStatusStore.setSummary(AppLocalization.text(
                "No cookies",
                language: settingsStore.interfaceLanguage
            ))
        }
    }

    func setSelectedPythonThemeKey(_ key: String) {
        let normalized = key.trimmed.lowercased()
        if normalized.isEmpty {
            settingsStore.selectedPythonThemeKey = ""
            settingsStore.persistSelectedPythonThemeKey()
            refreshPythonThemeSelection()
            addSummary = "Native theme selected"
            return
        }
        guard let theme = themePresentationSnapshot.availableThemes.first(
            where: { $0.key == normalized }
        ) else {
            addSummary = "Theme is unavailable"
            return
        }
        settingsStore.selectedPythonThemeKey = theme.key
        settingsStore.persistSelectedPythonThemeKey()
        refreshPythonThemeSelection()
        addSummary = "Theme set to \(theme.displayName)"
    }

    func setUIScale(_ scale: AppUIScale) {
        guard settingsStore.uiScale != scale else { return }
        settingsStore.uiScale = scale
        settingsStore.persistQueuePresentation()
        addSummary = "UI scale set to \(scale.label)"
    }

    func setQueueViewMode(_ mode: QueueViewMode) {
        guard settingsStore.queueViewMode != mode else { return }
        let selectionToRestore = presentation.selectedJobIDs
        queueViewSelectionRestoreCoordinator
            .cancelAndClear()
        settingsStore.queueViewMode = mode
        settingsStore.persistQueuePresentation()
        addSummary = "Queue view: \(mode.label.lowercased())"
        guard !selectionToRestore.isEmpty else { return }
        queueViewSelectionRestoreCoordinator
            .begin { [weak self] in
                guard let self,
                      self.settingsStore.queueViewMode == mode,
                      self.presentation.selectedJobIDs.isEmpty else {
                    return
                }
                self.setSelectedJobIDs(
                    selectionToRestore
                )
            }
    }

    func toggleQueueViewMode() {
        setQueueViewMode(settingsStore.queueViewMode == .list ? .icon : .list)
    }

    func setQueueThumbnailsHidden(_ hidden: Bool) {
        guard settingsStore.queueThumbnailsHidden != hidden else { return }
        settingsStore.queueThumbnailsHidden = hidden
        settingsStore.persistQueuePresentation()
        addSummary = hidden ? "Queue thumbnails hidden" : "Queue thumbnails shown"
    }

    func setQueueThumbnailScale(_ scale: QueueThumbnailScale) {
        guard settingsStore.queueThumbnailScale != scale else { return }
        settingsStore.queueThumbnailScale = scale
        settingsStore.persistQueuePresentation()
        addSummary = "Thumbnail size set to \(scale.label)"
    }

    func setMainWindowOpacity(_ value: Double) {
        let normalized = MainWindowAppearance.normalizedOpacity(value)
        guard settingsStore.mainWindowOpacity != normalized else { return }
        settingsStore.mainWindowOpacity = normalized
        settingsStore.persistWindowAppearance()
        addSummary = "Window opacity set to \(settingsStore.mainWindowOpacityPercentText)"
    }

    func setQuickAccessCommand(_ command: QuickAccessCommand, enabled: Bool) {
        settingsStore.setQuickAccessCommand(command, enabled: enabled)
    }

    func toggleAllQuickAccessCommands() {
        settingsStore.toggleAllQuickAccessCommands()
    }

    func moveQuickAccessCommand(_ command: QuickAccessCommand, relativeTo target: QuickAccessCommand) {
        settingsStore.moveQuickAccessCommand(
            command,
            relativeTo: target
        )
    }

    func canPerformQuickAccessCommand(_ command: QuickAccessCommand) -> Bool {
        quickAccessCommandService.canPerform(
            command,
            context: quickAccessCommandContext
        )
    }

    func isQuickAccessCommandActive(_ command: QuickAccessCommand) -> Bool {
        quickAccessCommandService.isActive(
            command,
            context: quickAccessCommandContext
        )
    }

    func performQuickAccessCommand(_ command: QuickAccessCommand) {
        quickAccessCommandService.perform(
            command,
            context: quickAccessCommandContext,
            actions: QuickAccessCommandActions(
                exportTasks: { self.exportOriginalTasks() },
                createGroup: { self.beginCreatingQueueGroup() },
                toggleQueueView: { self.toggleQueueViewMode() },
                selectRandomJob: { self.selectRandomVisibleJob() },
                setMainWindowAlwaysOnTop: {
                    self.setMainWindowAlwaysOnTop($0)
                },
                setAppearanceMode: {
                    self.setAppAppearanceMode($0)
                },
                importCookies: { self.importCookies() },
                openBrowser: { self.openBrowserWindow() }
            )
        )
    }

    private var quickAccessCommandContext: QuickAccessCommandContext {
        QuickAccessCommandContext(
            hasQueueContent: !queueStore.jobs.isEmpty || !queueStore.queueGroups.isEmpty,
            usesManualQueueSort: settingsStore.queueSortMode == .manual,
            isQueueRunning: queueStore.isRunning,
            canSelectRandomVisibleJob:
                queuePresentationSnapshot.canSelectRandomVisibleJob,
            mainWindowAlwaysOnTop: settingsStore.mainWindowAlwaysOnTop,
            appearanceMode: settingsStore.appAppearanceMode
        )
    }

    func setMainWindowAlwaysOnTop(_ enabled: Bool) {
        guard settingsStore.mainWindowAlwaysOnTop != enabled else { return }
        settingsStore.mainWindowAlwaysOnTop = enabled
        settingsStore.persistWindowAppearance()
        addSummary = enabled ? "Window stays on top" : "Window uses normal level"
    }

    func beginEditingShortcut(_ command: AppShortcutCommand) {
        presentation.shortcutEditorCommand = command
        presentation.shortcutEditorDraft = settingsStore.shortcut(for: command)
        presentation.shortcutEditorMessage = ""
    }

    func setShortcutDraftKey(_ key: AppShortcutKey) {
        presentation.shortcutEditorDraft.key = key
        if key == .none {
            presentation.shortcutEditorDraft.modifiers.removeAll()
        }
        presentation.shortcutEditorMessage = ""
    }

    func setShortcutDraftModifier(_ modifier: AppShortcutModifier, enabled: Bool) {
        if enabled {
            presentation.shortcutEditorDraft.modifiers.insert(modifier)
        } else {
            presentation.shortcutEditorDraft.modifiers.remove(modifier)
        }
        presentation.shortcutEditorMessage = ""
    }

    func recordShortcutDraft(
        from shortcut: AppShortcut?
    ) {
        let recording =
            appShortcutCommandService
            .draftRecording(for: shortcut)
        if let shortcut = recording.shortcut {
            presentation.shortcutEditorDraft = shortcut
        }
        presentation.shortcutEditorMessage =
            recording.message
    }

    func clearShortcutDraft() {
        presentation.shortcutEditorDraft = .none
        presentation.shortcutEditorMessage = "Shortcut cleared"
    }

    func resetShortcutDraft() {
        let command = presentation.shortcutEditorCommand
        presentation.shortcutEditorDraft = command.defaultShortcut
        presentation.shortcutEditorMessage =
            "Default restored for \(command.label)"
    }

    @discardableResult
    func saveShortcutDraft() -> Bool {
        let command = presentation.shortcutEditorCommand
        let normalized = presentation.shortcutEditorDraft.normalized()
        if let conflict = settingsStore.shortcutConflict(
            for: command,
            shortcut: normalized
        ) {
            presentation.shortcutEditorMessage =
                "\(normalized.displayText) conflicts with \(conflict.label)"
            addSummary = "Shortcut conflict"
            return false
        }
        settingsStore.setAppShortcut(normalized, for: command)
        presentation.shortcutEditorMessage =
            "\(command.label) set to \(normalized.displayText)"
        addSummary = presentation.shortcutEditorMessage
        return true
    }

    func resetAllShortcuts() {
        settingsStore.resetAppShortcuts()
        presentation.shortcutEditorDraft = settingsStore.shortcut(
            for: presentation.shortcutEditorCommand
        )
        presentation.shortcutEditorMessage = "All shortcuts reset"
        addSummary = "Shortcuts reset"
    }

    func setFloatingMonitorOpacity(_ value: Double) {
        let normalized = SettingsStore.normalizedFloatingMonitorOpacity(value)
        guard settingsStore.floatingMonitorOpacity != normalized else { return }
        settingsStore.floatingMonitorOpacity = normalized
        settingsStore.persistWindowAppearance()
        addSummary = "Floating monitor opacity set to \(settingsStore.floatingMonitorOpacityPercentText)"
    }

    func floatingMonitorSnapshot() -> FloatingMonitorSnapshot {
        let statistics = statisticsSnapshot()
        let progress = QueueProgressPresentationService.snapshot(
            jobs: queueStore.jobs
        )
        return FloatingMonitorSnapshot(
            isRunning: queueStore.isRunning,
            totalJobs: queueStore.jobs.count,
            activeJobs: progress.activeJobs.count,
            finishedJobs: statistics.finishedJobs,
            failedJobs: statistics.failedJobs,
            cancelledJobs: statistics.cancelledJobs,
            progressFraction: progress.fraction,
            completedUnits: progress.completedUnits,
            totalUnits: progress.totalUnits,
            downloadSpeedBytesPerSecond: statistics.downloadSpeedBytesPerSecond,
            uploadSpeedBytesPerSecond: statistics.uploadSpeedBytesPerSecond
        )
    }

    func setInterfaceFontFamily(_ family: String) {
        let normalized =
            interfaceFontService
            .normalizedFamily(family)
        guard settingsStore.interfaceFontFamily != normalized else { return }
        settingsStore.interfaceFontFamily = normalized
        settingsStore.persistInterfaceFont()
        addSummary = "Interface font set to \(normalized.isEmpty ? "System" : normalized)"
    }

    func setInterfaceFontSize(_ size: AppInterfaceFontSize) {
        guard settingsStore.interfaceFontSize != size else { return }
        settingsStore.interfaceFontSize = size
        settingsStore.persistInterfaceFont()
        addSummary = "Interface font size set to \(size.label)"
    }

    func resetInterfaceFont() {
        settingsStore.interfaceFontFamily = ""
        settingsStore.interfaceFontSize = .defaultSize
        settingsStore.persistInterfaceFont()
        addSummary = "Interface font reset"
    }

    func beginEditingStatusColors() {
        presentation.statusColorDraftPalette =
            settingsStore.jobStatusColorPalette
        appCommandService.openAuxiliaryWindow(.statusColorPicker)
    }

    func cancelEditingStatusColors() {
        presentation.statusColorDraftPalette =
            settingsStore.jobStatusColorPalette
        appCommandService.closeAuxiliaryWindow(.statusColorPicker)
    }

    func setDraftStatusColor(_ value: String, for status: JobStatus) {
        presentation.statusColorDraftPalette.setHex(value, for: status)
        if settingsStore.statusColorOnlyWebColors {
            presentation.statusColorDraftPalette =
                presentation.statusColorDraftPalette.normalized(
                    onlyWebColors: true
                )
        }
    }

    func setStatusColorOnlyWebColors(_ enabled: Bool) {
        settingsStore.statusColorOnlyWebColors = enabled
        if enabled {
            presentation.statusColorDraftPalette =
                presentation.statusColorDraftPalette.normalized(
                    onlyWebColors: true
                )
        }
    }

    func resetStatusColorDrafts() {
        presentation.statusColorDraftPalette = .defaultPalette
        if settingsStore.statusColorOnlyWebColors {
            presentation.statusColorDraftPalette =
                presentation.statusColorDraftPalette.normalized(
                    onlyWebColors: true
                )
        }
    }

    func saveStatusColors() {
        presentation.statusColorDraftPalette =
            presentation.statusColorDraftPalette.normalized(
                onlyWebColors: settingsStore.statusColorOnlyWebColors
            )
        settingsStore.jobStatusColorPalette =
            presentation.statusColorDraftPalette
        settingsStore.persistJobStatusColorSettings()
        appCommandService.closeAuxiliaryWindow(.statusColorPicker)
        addSummary = "Status colors saved"
    }

    func retryJob(_ job: DownloadJob) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        guard !isActive(queueStore.jobs[index].status) else {
            addSummary = "Cancel active jobs before retrying"
            return
        }

        queueJobForRetry(at: index)
        addSummary = "Job queued for retry"
        persistQueue()
        runQueuedJobsIfEnabled()
    }

    func canDirectDownloadJobs(startingAt job: DownloadJob) -> Bool {
        let targetIDs = presentation.selectedJobIDs.contains(job.id) ? presentation.selectedJobIDs : Set([job.id])
        return queueStore.jobs.indices.contains { index in
            targetIDs.contains(queueStore.jobs[index].id) && isDirectDownloadable(at: index)
        }
    }

    func directDownloadJobs(startingAt job: DownloadJob) {
        let targetIDs = presentation.selectedJobIDs.contains(job.id) ? presentation.selectedJobIDs : Set([job.id])
        var queued = 0

        for index in queueStore.jobs.indices.reversed() where targetIDs.contains(queueStore.jobs[index].id) {
            guard isDirectDownloadable(at: index) else { continue }
            queueStore.updateJob(at: index) {
                $0.metadata[Self.directDownloadOverrideMetadataKey] = "file"
            }
            queueJobForRetry(at: index)
            queued += 1
        }

        guard queued > 0 else {
            addSummary = "No directly downloadable jobs selected"
            return
        }

        addSummary = "\(queued) job\(queued == 1 ? "" : "s") queued for direct download"
        persistQueue()
        runQueuedJobsIfEnabled()
    }

    private func isDirectDownloadable(at index: Int) -> Bool {
        guard queueStore.jobs.indices.contains(index), !isActive(queueStore.jobs[index].status) else { return false }
        let job = queueStore.jobs[index]
        guard (job.metadata[Self.directDownloadOverrideMetadataKey]?.trimmed ?? "").isEmpty,
              (job.metadata[OriginalInputType.metadataKey]?.trimmed ?? "").isEmpty,
              let url = URL(string: job.source.trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let classification = apiInputClassification(for: job.source, url: url)
        return classification.resolver == "Direct File" || classification.resolver == "Generic Page"
    }

    func retryJobs(_ selectedJobs: [DownloadJob]) {
        let ids = selectedJobs.map(\.id)
        guard !ids.isEmpty else {
            addSummary = "No jobs selected for retry"
            return
        }

        var retried = 0
        var skippedActive = 0
        for id in ids {
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == id }) else { continue }
            guard !isActive(queueStore.jobs[index].status) else {
                skippedActive += 1
                continue
            }
            queueJobForRetry(at: index)
            retried += 1
        }

        if retried == 0 {
            addSummary = skippedActive > 0 ? "Cancel active jobs before retrying" : "No jobs selected for retry"
            return
        }

        addSummary = skippedActive > 0
            ? "\(retried) selected jobs queued for retry, \(skippedActive) active skipped"
            : "\(retried) selected jobs queued for retry"
        persistQueue()
        runQueuedJobsIfEnabled()
    }

    func canRetryJobs(for selectedJobs: [DownloadJob]) -> Bool {
        selectedJobs.contains { job in
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return false }
            return !isActive(queueStore.jobs[index].status)
        }
    }

    func retryJobs(startingAt job: DownloadJob) {
        retryJobs(Array(contextualJobs(startingAt: job).reversed()))
    }

    func canRetryJobs(startingAt job: DownloadJob) -> Bool {
        canRetryJobs(for: contextualJobs(startingAt: job))
    }

    func beginRetryIncompleteJobs() {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before restarting incomplete jobs"
            return
        }
        let ids = queueStore.jobs.reversed().filter(isRetryableIncompleteJob).map(\.id)
        guard !ids.isEmpty else {
            addSummary = "No incomplete jobs to restart"
            return
        }
        queueEditorStore.beginIncompleteRetry(jobIDs: ids)
        presentation.showingRetryIncompleteJobsConfirmation = true
    }

    func cancelPendingIncompleteJobRetry() {
        queueEditorStore.resetIncompleteRetry()
        presentation.showingRetryIncompleteJobsConfirmation = false
    }

    @discardableResult
    func retryPendingIncompleteJobs() -> Int {
        let ids = queueEditorStore.pendingIncompleteRetryJobIDs
        cancelPendingIncompleteJobRetry()
        return retryIncompleteJobs(jobIDs: ids)
    }

    @discardableResult
    func retryIncompleteJobs() -> Int {
        retryIncompleteJobs(jobIDs: queueStore.jobs.reversed().filter(isRetryableIncompleteJob).map(\.id))
    }

    func beginRemovingCompletedJobs() {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before removing completed jobs"
            return
        }
        let ids = queueStore.jobs.filter(isRemovableCompletedJob).map(\.id)
        guard !ids.isEmpty else {
            addSummary = "No completed jobs to remove"
            return
        }
        queueEditorStore.beginCompletedRemoval(jobIDs: ids)
        presentation.showingCompletedJobsRemovalConfirmation = true
    }

    func cancelPendingCompletedJobRemoval() {
        queueEditorStore.resetCompletedRemoval()
        presentation.showingCompletedJobsRemovalConfirmation = false
    }

    @discardableResult
    func removePendingCompletedJobs() -> Int {
        let ids = queueEditorStore.pendingCompletedRemovalJobIDs
        cancelPendingCompletedJobRemoval()
        return clearCompletedJobs(jobIDs: ids)
    }

    @discardableResult
    func clearCompletedJobs() -> Int {
        clearCompletedJobs(jobIDs: queueStore.jobs.filter(isRemovableCompletedJob).map(\.id))
    }

    @discardableResult
    private func retryIncompleteJobs(jobIDs: [UUID]) -> Int {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before restarting incomplete jobs"
            return 0
        }

        var retried = 0
        for id in jobIDs {
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == id }),
                  isRetryableIncompleteJob(queueStore.jobs[index]) else {
                continue
            }
            queueJobForRetry(at: index)
            retried += 1
        }
        guard retried > 0 else {
            addSummary = "No incomplete jobs to restart"
            return 0
        }

        addSummary = "\(retried) incomplete job\(retried == 1 ? "" : "s") restarted"
        persistQueue()
        runQueuedJobsIfEnabled()
        return retried
    }

    @discardableResult
    private func clearCompletedJobs(jobIDs: [UUID]) -> Int {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before removing completed jobs"
            return 0
        }

        let requested = Set(jobIDs)
        let ids = Set(queueStore.jobs.lazy.filter { requested.contains($0.id) && self.isRemovableCompletedJob($0) }.map(\.id))
        ids.forEach { cancelScheduledRestart(for: $0) }
        queueStore.removeJobs(withIDs: ids)
        presentation.selectedJobIDs.subtract(ids)
        addSummary = ids.isEmpty
            ? "No completed jobs to remove"
            : "\(ids.count) completed job\(ids.count == 1 ? "" : "s") removed"
        persistQueue()
        return ids.count
    }

    private func queueJobForRetry(at index: Int) {
        guard queueStore.jobs.indices.contains(index) else { return }
        let current = queueStore.jobs[index]
        cancelScheduledRestart(for: current.id)
        downloadCoordinator.storeRetrySnapshot(current)
        downloadCoordinator.resetOutcome(for: current.id)
        queueStore.updateJob(at: index) { job in
            job.title = job.source
            job.status = .queued
            job.progress = 0
            job.completed = 0
            job.total = 0
            job.message = ""
            job.outputPath = ""
            job.metadata.removeValue(forKey: "last_error")
            job.metadata.removeValue(forKey: "reaction")
        }
    }

    func markJobFinished(_ job: DownloadJob) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        _ = markJobFinished(at: index)
    }

    func canMarkJobFinished(_ job: DownloadJob) -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return false }
        return canMarkJobFinished(at: index)
    }

    @discardableResult
    func markJobsFinished(startingAt job: DownloadJob) -> Int {
        let targetIDs = contextualJobs(startingAt: job).reversed().map(\.id)
        var marked = 0
        var skippedActive = 0

        for id in targetIDs {
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == id }) else { continue }
            guard canMarkJobFinished(at: index) else {
                if isActive(queueStore.jobs[index].status) {
                    skippedActive += 1
                }
                continue
            }
            if markJobFinished(at: index) {
                marked += 1
            }
        }

        if marked == 0 {
            addSummary = skippedActive > 0
                ? "Pause or cancel active jobs before marking finished"
                : "No selected jobs can be marked finished"
        } else if skippedActive > 0 {
            addSummary = "\(marked) selected job\(marked == 1 ? "" : "s") marked finished, \(skippedActive) active skipped"
        } else {
            addSummary = "\(marked) selected job\(marked == 1 ? "" : "s") marked finished"
        }
        persistQueue()
        return marked
    }

    func canMarkJobsFinished(startingAt job: DownloadJob) -> Bool {
        contextualJobs(startingAt: job).contains { candidate in
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == candidate.id }) else { return false }
            return canMarkJobFinished(at: index)
        }
    }

    func moveJobUp(_ job: DownloadJob) {
        moveJob(job, offset: -1)
    }

    func moveJobDown(_ job: DownloadJob) {
        moveJob(job, offset: 1)
    }

    func moveSelectedJobsUp() {
        moveSelectedJobs(offset: -1)
    }

    func moveSelectedJobsDown() {
        moveSelectedJobs(offset: 1)
    }

    func queueJobIDsForDrag(startingAt jobID: UUID) -> Set<UUID> {
        let existingIDs = Set(queueStore.jobs.map(\.id))
        let selected = presentation.selectedJobIDs.intersection(existingIDs)
        if selected.contains(jobID) {
            return selected
        }
        setSelectedJobIDs([jobID])
        return [jobID]
    }

    func endQueueDrag() {
        presentation.draggedQueueJobIDs = []
        presentation.queueJobDropTarget = nil
    }

    @discardableResult
    func reorderJobs(
        _ movingIDs: Set<UUID>,
        relativeTo targetID: UUID,
        placeAfter: Bool
    ) -> Bool {
        guard settingsStore.queueSortMode == .manual else {
            addSummary = "Use Manual queue sort before dragging jobs"
            return false
        }
        guard presentation.queueFilter.trimmed.isEmpty else {
            addSummary = "Clear the queue filter before dragging jobs"
            return false
        }

        let orderedJobs = queueOrderedJobs
        let movingJobs = orderedJobs.filter { movingIDs.contains($0.id) }
        guard !movingJobs.isEmpty else { return false }
        guard !movingJobs.contains(where: Self.isPendingQueueRemoval) else {
            addSummary = "Wait for pending removals before moving jobs"
            return false
        }
        guard !movingIDs.contains(targetID),
              let target = orderedJobs.first(where: {
                  $0.id == targetID && !Self.isPendingQueueRemoval($0)
              }) else {
            return false
        }

        let pinStates = Set(movingJobs.map(\.isPinned))
        guard pinStates.count == 1, pinStates.first == target.isPinned else {
            addSummary = "Pinned and unpinned jobs stay in separate groups"
            return false
        }
        guard let reordered = QueueReorderingService.jobsByMoving(
            orderedJobs,
            movingIDs: movingIDs,
            relativeTo: targetID,
            placeAfter: placeAfter
        ), reordered.map(\.id) != orderedJobs.map(\.id) else {
            return false
        }

        applyQueueOrder(reordered)
        setSelectedJobIDs(movingIDs)
        addSummary = "\(movingJobs.count) job\(movingJobs.count == 1 ? "" : "s") reordered"
        persistQueue()
        return true
    }

    func canMoveJobUp(_ job: DownloadJob) -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return false }
        return canMoveJob(at: index, offset: -1)
    }

    func canMoveJobDown(_ job: DownloadJob) -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return false }
        return canMoveJob(at: index, offset: 1)
    }

    func canMoveSelectedJobsUp() -> Bool {
        canMoveSelectedJobs(offset: -1)
    }

    func canMoveSelectedJobsDown() -> Bool {
        canMoveSelectedJobs(offset: 1)
    }

    func canRemoveJobs(startingAt job: DownloadJob) -> Bool {
        return contextualJobs(startingAt: job).contains { candidate in
            !candidate.isLocked &&
                !Self.isPendingQueueRemoval(candidate)
        }
    }

    func beginRemovingJobs(startingAt job: DownloadJob) {
        let selected = contextualJobs(startingAt: job)
        let removable = selected.filter {
            !$0.isLocked &&
                !Self.isPendingQueueRemoval($0)
        }
        guard !removable.isEmpty else {
            if selected.contains(where: \.isLocked) {
                addSummary = "Unlock jobs before removing"
            } else {
                addSummary = "No removable jobs selected"
            }
            return
        }

        queueEditorStore.beginPendingJobRemoval(removable)
        presentation.showingJobRemovalConfirmation = true
    }

    func cancelPendingJobRemoval() {
        queueEditorStore.resetPendingJobRemoval()
        presentation.showingJobRemovalConfirmation = false
    }

    @discardableResult
    func removePendingJobs() -> Int {
        let pending = Set(queueEditorStore.jobPendingRemovalIDs)
        let selected = queueStore.jobs.filter { pending.contains($0.id) }
        let removed = removeJobs(selected)
        cancelPendingJobRemoval()
        return removed
    }

    @discardableResult
    func removeJobs(_ selectedJobs: [DownloadJob]) -> Int {
        let requestedIDs = Set(selectedJobs.map(\.id))
        let candidates = queueStore.jobs.filter { requestedIDs.contains($0.id) }
        let removable = candidates.filter {
            !$0.isLocked &&
                !Self.isPendingQueueRemoval($0)
        }
        guard !removable.isEmpty else {
            if candidates.contains(where: \.isLocked) {
                addSummary = "Unlock jobs before removing"
            } else {
                addSummary = "No removable jobs selected"
            }
            return 0
        }

        let removedCount = removeJobsFromQueue(removable)

        let skipped = candidates.count - removable.count
        if removedCount == 1 && skipped == 0 {
            addSummary = "Job removed"
        } else if skipped > 0 {
            addSummary = "\(removedCount) selected jobs removed, \(skipped) locked skipped"
        } else {
            addSummary = "\(removedCount) selected jobs removed"
        }
        return removedCount
    }

    func removeJob(_ job: DownloadJob) {
        _ = removeJobs([job])
    }

    @discardableResult
    private func removeJobsFromQueue(_ removable: [DownloadJob]) -> Int {
        let removableIDs = Set(removable.map(\.id))
        guard !removableIDs.isEmpty else { return 0 }

        removableIDs.forEach { cancelScheduledRestart(for: $0) }
        presentation.selectedJobIDs.subtract(removableIDs)

        let requiresDeferredOutputCleanup = queueStore.jobs.contains {
            removableIDs.contains($0.id) && Self.isPendingQueueOutputDeletion($0)
        }
        if queueStore.isRunning || downloadCoordinator.hasProcessingJobs || requiresDeferredOutputCleanup {
            for index in queueStore.jobs.indices where removableIDs.contains(queueStore.jobs[index].id) {
                let jobID = queueStore.jobs[index].id
                let shouldCancel = isActive(queueStore.jobs[index].status) ||
                    downloadCoordinator.isActive(jobID)
                queueStore.updateJob(at: index) {
                    $0.metadata[
                        QueueJobMetadataPolicy.pendingRemovalMetadataKey
                    ] = "true"
                }
                if queueStore.jobs[index].status == .queued || shouldCancel {
                    markCancelled(index, persist: false)
                    let message = shouldCancel
                        ? "Removed and cancelled"
                        : "Removed while queue was running"
                    queueStore.updateJob(at: index) {
                        $0.message = message
                        $0.recordMessage(message)
                    }
                }
                if shouldCancel {
                    cancelRunningJob(jobID)
                }
            }
            persistQueue()
            flushPendingQueueRemovals()
            persistQueue()
            return removableIDs.count
        }

        queueStore.removeJobs(withIDs: removableIDs)
        queueScheduler.removeJobs(withIDs: removableIDs)
        persistQueue()
        return removableIDs.count
    }

    private func flushPendingQueueRemovals() {
        let pendingIDs = Set(
            queueStore.jobs.lazy
                .filter(Self.isPendingQueueRemoval)
                .map(\.id)
        )
        guard !pendingIDs.isEmpty else { return }
        let pendingOutputDeletionIDs = Set(
            queueStore.jobs.lazy
                .filter {
                    pendingIDs.contains($0.id) &&
                        Self.isPendingQueueOutputDeletion($0)
                }
                .map(\.id)
        )

        let deletedAt = ISO8601DateFormatter().string(from: Date())
        if downloadCoordinator.processingJobsAreDisjoint(with: pendingOutputDeletionIDs) {
            for jobID in pendingOutputDeletionIDs {
                guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }) else { continue }

                let candidates = resolvedOutputDeletionCandidates(for: queueStore.jobs[index])
                guard !candidates.isEmpty else {
                    queueStore.updateJob(at: index) {
                        $0.outputPath = ""
                        $0.metadata.removeValue(forKey: Self.pendingQueueOutputDeletionMetadataKey)
                        $0.metadata["output_deleted_at"] = deletedAt
                    }
                    continue
                }
                guard !candidates.contains(where: {
                    let currentPendingOutputDeletionIDs = Set(
                        queueStore.jobs.lazy
                            .filter(Self.isPendingQueueOutputDeletion)
                            .map(\.id)
                    )
                    return isOutputDeletionCandidateShared(
                        $0,
                        excludingJobIDs: currentPendingOutputDeletionIDs
                    )
                }) else {
                    queueStore.updateJob(at: index) {
                        $0.metadata.removeValue(
                            forKey: QueueJobMetadataPolicy.pendingRemovalMetadataKey
                        )
                        $0.metadata.removeValue(forKey: Self.pendingQueueOutputDeletionMetadataKey)
                        $0.message = "Output is shared with another queue job"
                    }
                    continue
                }

                do {
                    let result = try trashOutputDeletionCandidates(candidates)
                    if result.failures.isEmpty {
                        if !result.resolvedPaths.isEmpty {
                            updateOutputPathAfterDeletingCandidates(at: index, trashedPaths: result.resolvedPaths)
                        }
                        queueStore.updateJob(at: index) {
                            $0.metadata.removeValue(forKey: Self.pendingQueueOutputDeletionMetadataKey)
                            $0.metadata["output_deleted_at"] = deletedAt
                        }
                        continue
                    }
                    if !result.resolvedPaths.isEmpty {
                        updateOutputPathAfterDeletingCandidates(at: index, trashedPaths: result.resolvedPaths)
                    }
                    queueStore.updateJob(at: index) {
                        if !result.resolvedPaths.isEmpty {
                            $0.metadata["output_deleted_at"] = deletedAt
                        }
                        $0.metadata.removeValue(
                            forKey: QueueJobMetadataPolicy.pendingRemovalMetadataKey
                        )
                        $0.metadata.removeValue(forKey: Self.pendingQueueOutputDeletionMetadataKey)
                        $0.metadata["output_delete_partial_at"] = deletedAt
                        $0.metadata["output_delete_failed_count"] = String(result.failures.count)
                        $0.message = "\(result.trashedItemCount) output item(s) moved; \(result.failures.count) failed"
                    }
                } catch {
                    queueStore.updateJob(at: index) {
                        $0.metadata.removeValue(
                            forKey: QueueJobMetadataPolicy.pendingRemovalMetadataKey
                        )
                        $0.metadata.removeValue(forKey: Self.pendingQueueOutputDeletionMetadataKey)
                        $0.metadata["output_delete_partial_at"] = deletedAt
                        $0.metadata["output_delete_failed_count"] = "1"
                        $0.message = "Output delete failed: \(AppLocalization.errorText(error))"
                    }
                }
            }
        }

        guard !downloadCoordinator.hasProcessingJobs, !queueStore.isRunning else { return }
        let removableIDs = Set(
            queueStore.jobs.lazy
                .filter {
                    Self.isPendingQueueRemoval($0) &&
                        !Self.isPendingQueueOutputDeletion($0)
                }
                .map(\.id)
        )
        removableIDs.forEach { cancelScheduledRestart(for: $0) }
        queueStore.removeJobs(withIDs: removableIDs)
        queueScheduler.removeJobs(withIDs: removableIDs)
        presentation.selectedJobIDs.subtract(removableIDs)
    }

#if TESTING
    func flushPendingQueueRemovalsForTesting() {
        flushPendingQueueRemovals()
        persistQueue()
    }
#endif

    func toggleJobPinned(_ job: DownloadJob) {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before pinning jobs"
            return
        }
        var isPinned = false
        guard queueStore.updateJob(id: job.id, {
            $0.isPinned.toggle()
            isPinned = $0.isPinned
        }) else {
            return
        }
        addSummary = isPinned ? "Job pinned" : "Job unpinned"
        persistQueue()
    }

    func toggleJobLocked(_ job: DownloadJob) {
        var isLocked = false
        guard queueStore.updateJob(id: job.id, {
            $0.isLocked.toggle()
            isLocked = $0.isLocked
        }) else {
            return
        }
        addSummary = isLocked ? "Job locked" : "Job unlocked"
        persistQueue()
    }

    func jobPinActionWillPin(startingAt job: DownloadJob) -> Bool {
        contextualJobs(startingAt: job).contains { !$0.isPinned }
    }

    func canToggleJobPins(startingAt job: DownloadJob) -> Bool {
        !queueStore.isRunning && !contextualJobs(startingAt: job).isEmpty
    }

    func toggleJobPins(startingAt job: DownloadJob) {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before pinning jobs"
            return
        }
        let targets = contextualJobs(startingAt: job)
        guard !targets.isEmpty else { return }
        let shouldPin = targets.contains { !$0.isPinned }
        let targetIDs = Set(targets.map(\.id))
        let updateCount = queueStore.updateJobs(withIDs: targetIDs) {
            $0.isPinned = shouldPin
        }
        addSummary = "\(updateCount) selected job\(updateCount == 1 ? "" : "s") \(shouldPin ? "pinned" : "unpinned")"
        persistQueue()
    }

    func jobLockActionWillLock(startingAt job: DownloadJob) -> Bool {
        contextualJobs(startingAt: job).contains { !$0.isLocked }
    }

    func toggleJobLocks(startingAt job: DownloadJob) {
        let targets = contextualJobs(startingAt: job)
        guard !targets.isEmpty else { return }
        let shouldLock = targets.contains { !$0.isLocked }
        let targetIDs = Set(targets.map(\.id))
        let updateCount = queueStore.updateJobs(withIDs: targetIDs) {
            $0.isLocked = shouldLock
        }
        addSummary = "\(updateCount) selected job\(updateCount == 1 ? "" : "s") \(shouldLock ? "locked" : "unlocked")"
        persistQueue()
    }

    func setTaskTagName(_ name: String, for tag: TaskTagColor) {
        settingsStore.setTaskTagName(name, for: tag)
    }

    func setTaskTagRestartDelay(_ delay: TaskTagRestartDelay, for tag: TaskTagColor) {
        settingsStore.setTaskTagRestartDelay(delay, for: tag)
        rescheduleFinishedJobs(using: tag)
        addSummary = delay == .off
            ? "\(settingsStore.taskTagDisplayName(tag)) tag timer off"
            : "\(settingsStore.taskTagDisplayName(tag)) tag timer: \(delay.label)"
    }

    func resetTaskTagNames() {
        settingsStore.resetTaskTagNames()
        addSummary = "Task tag names reset"
    }

    func isJobTagChecked(_ tag: TaskTagColor, for job: DownloadJob) -> Bool {
        let targetIDs = presentation.selectedJobIDs.contains(job.id) ? presentation.selectedJobIDs : Set([job.id])
        let targets = queueStore.jobs.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else { return false }
        return targets.allSatisfy { $0.tags.contains(tag.rawValue) }
    }

    func toggleJobTag(_ tag: TaskTagColor, for job: DownloadJob) {
        let targetIDs = presentation.selectedJobIDs.contains(job.id) ? presentation.selectedJobIDs : Set([job.id])
        let targets = queueStore.jobs.filter { targetIDs.contains($0.id) }
        guard !targets.isEmpty else { return }

        let shouldAdd = targets.contains { !$0.tags.contains(tag.rawValue) }
        let updateCount = queueStore.updateJobs(withIDs: targetIDs) { job in
            var tags = TaskTagColor.normalizedRawValues(job.tags)
            if shouldAdd {
                if !tags.contains(tag.rawValue) {
                    tags.append(tag.rawValue)
                }
            } else {
                tags.removeAll { $0 == tag.rawValue }
            }
            job.tags = tags
        }
        let name = settingsStore.taskTagDisplayName(tag)
        addSummary = shouldAdd
            ? "\(name) tag added to \(updateCount) job\(updateCount == 1 ? "" : "s")"
            : "\(name) tag removed from \(updateCount) job\(updateCount == 1 ? "" : "s")"
        for jobID in targets.map(\.id) {
            guard let current = queueStore.jobs.first(where: { $0.id == jobID }),
                  current.status == .finished else {
                continue
            }
            scheduleRestartIfNeeded(for: current)
        }
        persistQueue()
    }

    private func rescheduleFinishedJobs(using tag: TaskTagColor) {
        let jobIDs = queueStore.jobs.compactMap { job in
            job.status == .finished && job.tags.contains(tag.rawValue) ? job.id : nil
        }
        for jobID in jobIDs {
            guard let current = queueStore.jobs.first(where: { $0.id == jobID }) else { continue }
            scheduleRestartIfNeeded(for: current)
        }
        if !jobIDs.isEmpty {
            persistQueue()
        }
    }

    func jobGroupID(for job: DownloadJob) -> UUID? {
        if let id = QueueJobMetadataPolicy.metadataGroupID(for: job),
           queueStore.queueGroups.contains(where: { $0.id == id }) {
            return id
        }
        let legacyName = (job.metadata["group"] ?? job.metadata["group_name"] ?? "").trimmed
        guard !legacyName.isEmpty else { return nil }
        return queueStore.queueGroups.first {
            $0.name.caseInsensitiveCompare(legacyName) == .orderedSame
        }?.id
    }

    func jobGroupName(for job: DownloadJob) -> String? {
        if let groupID = jobGroupID(for: job),
           let group = queueStore.queueGroups.first(where: { $0.id == groupID }) {
            return group.name
        }
        let value = (job.metadata["group"] ?? job.metadata["group_name"] ?? "").trimmed
        return value.isEmpty ? nil : value
    }

    func jobs(in group: QueueGroup) -> [DownloadJob] {
        visibleQueueOrderedJobs.filter { jobGroupID(for: $0) == group.id }
    }

    func beginCreatingQueueGroup() {
        guard settingsStore.queueSortMode == .manual else {
            addSummary = "Groups can only be created while using manual sort."
            return
        }
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before creating a group"
            return
        }
        let selectedIDs = presentation.selectedJobIDs.intersection(Set(queueStore.jobs.map(\.id)))
        if queueStore.jobs.contains(where: { selectedIDs.contains($0.id) && jobGroupID(for: $0) != nil }) {
            addSummary = "One or more selected tasks already belong to a group."
            return
        }
        queueEditorStore.beginQueueGroupPrompt(
            action: .create(jobIDs: selectedIDs),
            pendingJob: nil,
            name: AppLocalization.text("New Group", language: settingsStore.interfaceLanguage)
        )
        presentation.showingJobGroupPrompt = true
    }

    func beginRenamingQueueGroup(_ group: QueueGroup) {
        guard queueStore.queueGroups.contains(where: { $0.id == group.id }) else { return }
        queueEditorStore.beginQueueGroupPrompt(
            action: .rename(groupID: group.id),
            pendingJob: nil,
            name: group.name
        )
        presentation.showingJobGroupPrompt = true
    }

    func beginMovingJobToNewGroup(_ job: DownloadJob) {
        guard settingsStore.queueSortMode == .manual else {
            addSummary = "Tasks can only be moved to groups while using manual sort."
            return
        }
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return }
        let jobIDs = presentation.selectedJobIDs.contains(current.id)
            ? presentation.selectedJobIDs.intersection(Set(queueStore.jobs.map(\.id)))
            : Set([current.id])
        queueEditorStore.beginQueueGroupPrompt(
            action: .move(jobIDs: jobIDs),
            pendingJob: current,
            name: AppLocalization.text("New Group", language: settingsStore.interfaceLanguage)
        )
        presentation.showingJobGroupPrompt = true
    }

    func savePendingJobGroup() {
        let name = queueEditorStore.jobGroupNameDraft.trimmed
        guard !name.isEmpty,
              let action = queueEditorStore.queueGroupPromptAction else {
            cancelPendingJobGroup()
            return
        }

        switch action {
        case .create(let jobIDs):
            _ = createQueueGroup(named: name, jobIDs: jobIDs)
        case .move(let jobIDs):
            if let existing = queueStore.queueGroups.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
                _ = moveJobs(jobIDs, toQueueGroup: existing.id)
            } else {
                let anchor = queueStore.jobs.first(where: { jobIDs.contains($0.id) })?.id
                var group = QueueGroup(name: name, anchorJobID: anchor)
                group.originalUID = group.id.uuidString
                queueStore.appendQueueGroup(group)
                _ = moveJobs(jobIDs, toQueueGroup: group.id)
            }
        case .rename(let groupID):
            renameQueueGroup(groupID, to: name)
        }
        cancelPendingJobGroup()
    }

    func cancelPendingJobGroup() {
        presentation.showingJobGroupPrompt = false
        queueEditorStore.resetQueueGroupPrompt()
    }

    @discardableResult
    func createQueueGroup(named rawName: String, jobIDs: Set<UUID>) -> QueueGroup? {
        let name = rawName.trimmed
        guard !name.isEmpty,
              settingsStore.queueSortMode == .manual,
              !queueStore.isRunning else { return nil }
        let selected = queueStore.jobs.filter { jobIDs.contains($0.id) }
        guard !selected.contains(where: { jobGroupID(for: $0) != nil }) else {
            addSummary = "One or more selected tasks already belong to a group."
            return nil
        }

        let selectedIndexes = queueStore.jobs.indices.filter { jobIDs.contains(queueStore.jobs[$0].id) }
        let insertionIndex = selectedIndexes.min() ?? 0
        var group = QueueGroup(
            name: name,
            anchorJobID: selected.first?.id ?? queueStore.jobs.first?.id
        )
        group.originalUID = group.id.uuidString
        queueStore.appendQueueGroup(group)

        if !selected.isEmpty {
            var reordered = queueStore.jobs.filter { !jobIDs.contains($0.id) }
            reordered.insert(contentsOf: selected, at: min(insertionIndex, reordered.count))
            queueStore.replaceJobs(with: reordered)
            applyQueueGroup(group, to: jobIDs)
            setSelectedJobIDs(jobIDs)
        }

        addSummary = selected.isEmpty
            ? "Group \(name) created"
            : "\(selected.count) jobs grouped as \(name)"
        persistQueue()
        return group
    }

    @discardableResult
    func moveJobs(_ jobIDs: Set<UUID>, toQueueGroup groupID: UUID?) -> Bool {
        guard settingsStore.queueSortMode == .manual else {
            addSummary = "Tasks can only be moved to groups while using manual sort."
            return false
        }
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before moving grouped jobs"
            return false
        }
        let movingJobs = queueStore.jobs.filter { jobIDs.contains($0.id) }
        guard !movingJobs.isEmpty,
              !movingJobs.contains(where: { isActive($0.status) }) else {
            return false
        }

        if let groupID {
            guard let target = queueStore.queueGroups.first(where: { $0.id == groupID }) else { return false }
            if movingJobs.allSatisfy({ jobGroupID(for: $0) == groupID }) {
                return false
            }

            let remaining = queueStore.jobs.filter { !jobIDs.contains($0.id) }
            let insertionIndex = remaining.firstIndex(where: { jobGroupID(for: $0) == groupID })
                ?? target.anchorJobID.flatMap { anchor in remaining.firstIndex(where: { $0.id == anchor }) }
                ?? remaining.endIndex
            var reordered = remaining
            reordered.insert(contentsOf: movingJobs, at: insertionIndex)
            queueStore.replaceJobs(with: reordered)
            applyQueueGroup(target, to: jobIDs)
            queueStore.updateQueueGroup(id: groupID) {
                $0.anchorJobID = movingJobs.first?.id
            }
            setSelectedJobIDs(jobIDs)
            addSummary = "\(movingJobs.count) job\(movingJobs.count == 1 ? "" : "s") moved to \(target.name)"
        } else {
            clearQueueGroup(from: jobIDs)
            addSummary = "\(movingJobs.count) job\(movingJobs.count == 1 ? "" : "s") removed from group"
        }
        persistQueue()
        return true
    }

    func moveJob(_ job: DownloadJob, toGroup rawGroup: String?) {
        let name = rawGroup?.trimmed ?? ""
        if name.isEmpty {
            _ = moveJobs([job.id], toQueueGroup: nil)
            return
        }
        if let group = queueStore.queueGroups.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            _ = moveJobs([job.id], toQueueGroup: group.id)
            return
        }
        var group = QueueGroup(name: name, anchorJobID: job.id)
        group.originalUID = group.id.uuidString
        queueStore.appendQueueGroup(group)
        _ = moveJobs([job.id], toQueueGroup: group.id)
    }

    func toggleQueueGroupExpanded(_ group: QueueGroup) {
        guard let updated = queueStore.updateQueueGroup(id: group.id, {
            $0.isExpanded.toggle()
        }) else { return }
        applyQueueGroup(updated, to: Set(jobs(in: updated).map(\.id)))
        if !updated.isExpanded {
            presentation.selectedJobIDs.subtract(jobs(in: updated).map(\.id))
        }
        addSummary = updated.isExpanded ? "Group expanded" : "Group collapsed"
        persistQueue()
    }

    func toggleQueueGroupPinned(_ group: QueueGroup) {
        guard !queueStore.isRunning else {
            addSummary = "Stop queue before pinning groups"
            return
        }
        guard let updated = queueStore.updateQueueGroup(id: group.id, {
            $0.isPinned.toggle()
        }) else { return }
        applyQueueGroup(updated, to: Set(jobs(in: updated).map(\.id)))
        addSummary = updated.isPinned ? "Group pinned" : "Group unpinned"
        persistQueue()
    }

    func toggleQueueGroupTag(_ tag: TaskTagColor, for group: QueueGroup) {
        guard let current = queueStore.queueGroups.first(where: { $0.id == group.id }) else { return }
        var values = Set(TaskTagColor.normalizedRawValues(current.tags))
        let added: Bool
        if values.remove(tag.rawValue) != nil {
            added = false
        } else {
            values.insert(tag.rawValue)
            added = true
        }
        guard let updated = queueStore.updateQueueGroup(id: group.id, {
            $0.tags = TaskTagColor.allCases.compactMap {
                values.contains($0.rawValue) ? $0.rawValue : nil
            }
        }) else { return }
        applyQueueGroup(updated, to: Set(jobs(in: updated).map(\.id)))
        addSummary = added ? "Group tag: \(tag.label)" : "Group tag removed: \(tag.label)"
        persistQueue()
    }

    func renameQueueGroup(_ groupID: UUID, to rawName: String) {
        let name = rawName.trimmed
        guard !name.isEmpty,
              let group = queueStore.updateQueueGroup(id: groupID, {
                  $0.name = name
              }) else { return }
        applyQueueGroup(group, to: Set(jobs(in: group).map(\.id)))
        addSummary = "Group renamed to \(name)"
        persistQueue()
    }

    func beginRemovingQueueGroup(_ group: QueueGroup) {
        guard queueStore.queueGroups.contains(where: { $0.id == group.id }) else { return }
        queueEditorStore.beginQueueGroupRemoval(group)
        presentation.showingQueueGroupRemovalConfirmation = true
    }

    func removePendingQueueGroup() {
        guard let group = queueEditorStore.queueGroupPendingRemoval else { return }
        let memberIDs = Set(jobs(in: group).map(\.id))
        clearQueueGroup(from: memberIDs)
        queueStore.removeQueueGroups(withIDs: [group.id])
        queueEditorStore.resetQueueGroupRemoval()
        presentation.showingQueueGroupRemovalConfirmation = false
        addSummary = "Group removed; \(memberIDs.count) jobs kept"
        persistQueue()
    }

    func cancelPendingQueueGroupRemoval() {
        queueEditorStore.resetQueueGroupRemoval()
        presentation.showingQueueGroupRemovalConfirmation = false
    }

    func beginRetryingQueueGroup(_ group: QueueGroup) {
        guard !jobs(in: group).isEmpty else { return }
        queueEditorStore.beginQueueGroupRetry(group)
        presentation.showingQueueGroupRetryConfirmation = true
    }

    func retryPendingQueueGroup() {
        guard let group = queueEditorStore.queueGroupPendingRetry else { return }
        let members = jobs(in: group)
        queueEditorStore.resetQueueGroupRetry()
        presentation.showingQueueGroupRetryConfirmation = false
        retryJobs(members)
    }

    func cancelPendingQueueGroupRetry() {
        queueEditorStore.resetQueueGroupRetry()
        presentation.showingQueueGroupRetryConfirmation = false
    }

    private func applyQueueGroup(_ group: QueueGroup, to jobIDs: Set<UUID>) {
        queueStore.updateJobs(withIDs: jobIDs) { job in
            job.metadata[QueueJobMetadataPolicy.groupIDMetadataKey] =
                group.id.uuidString
            job.metadata["group"] = group.name
            job.metadata.removeValue(forKey: "group_name")
            job.metadata["hdt_group_uid"] = group.originalUID
            job.metadata["hdt_group_expanded"] = group.isExpanded ? "true" : "false"
            job.metadata["hdt_group_pinned"] = group.isPinned ? "true" : "false"
            if group.tags.isEmpty {
                job.metadata.removeValue(forKey: "group_tags")
                job.metadata.removeValue(forKey: "hdt_group_tags")
            } else {
                job.metadata["group_tags"] = group.tags.joined(separator: ",")
                job.metadata.removeValue(forKey: "hdt_group_tags")
            }
            if group.comment.isEmpty {
                job.metadata.removeValue(forKey: "group_comment")
            } else {
                job.metadata["group_comment"] = group.comment
            }
        }
    }

    private func clearQueueGroup(from jobIDs: Set<UUID>) {
        queueStore.updateJobs(withIDs: jobIDs) { job in
            job.metadata.removeValue(
                forKey: QueueJobMetadataPolicy.groupIDMetadataKey
            )
            job.metadata.removeValue(forKey: "group")
            job.metadata.removeValue(forKey: "group_name")
            job.metadata.removeValue(forKey: "group_comment")
            job.metadata.removeValue(forKey: "hdt_group_uid")
            job.metadata.removeValue(forKey: "hdt_group_expanded")
            job.metadata.removeValue(forKey: "hdt_group_pinned")
            job.metadata.removeValue(forKey: "group_tags")
            job.metadata.removeValue(forKey: "hdt_group_tags")
        }
    }

    func jobImageConversionFormat(for job: DownloadJob) -> ImageConversionFormat? {
        guard let value = job.metadata["image_conversion_format"] else { return nil }
        return ImageConversionFormat(rawValue: value.lowercased())
    }

    func setJobImageConversionFormat(_ format: ImageConversionFormat?, for job: DownloadJob) {
        guard queueStore.jobs.contains(where: { $0.id == job.id }) else { return }
        if let format {
            queueStore.updateJob(id: job.id) {
                $0.metadata["image_conversion_format"] = format.rawValue
            }
            addSummary = format == .original
                ? "Job image conversion disabled"
                : "Job images will convert to \(format.label) on download"
        } else {
            queueStore.updateJob(id: job.id) {
                $0.metadata.removeValue(forKey: "image_conversion_format")
            }
            addSummary = "Job uses the default image conversion setting"
        }
        persistQueue()
    }

    func canConvertJobImages(for job: DownloadJob) -> Bool {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return false }
        return current.status == .finished &&
            !outputOperationStore.imageConversionJobIDs.contains(current.id)
    }

    func canConvertJobImages(startingAt job: DownloadJob) -> Bool {
        contextualJobs(startingAt: job).contains { canConvertJobImages(for: $0) }
    }

    func beginConvertingImages(startingAt job: DownloadJob) {
        guard canConvertJobImages(startingAt: job) else {
            addSummary = "No completed images available for conversion"
            return
        }

        let formats = ImageConversionFormat.allCases.filter { $0 != .original }
        guard !formats.isEmpty else { return }

        let preferredFormat =
            settingsStore.imageConversionFormat == .original
            ? ImageConversionFormat.jpeg
            : settingsStore.imageConversionFormat
        guard let selection =
            imageConversionDialogService
                .chooseConversion(
                    ImageConversionDialogRequest(
                        formats: formats,
                        preferredFormat:
                            preferredFormat,
                        initialQuality: 95,
                        language:
                            settingsStore.interfaceLanguage
                    )
                ) else {
            return
        }
        convertImages(
            startingAt: job,
            to: selection.format,
            quality: selection.quality
        )
    }

    func convertImages(
        startingAt job: DownloadJob,
        to format: ImageConversionFormat,
        quality: Int = 95
    ) {
        guard format != .original else {
            addSummary = "Choose a converted image format"
            return
        }

        let targets = contextualJobs(startingAt: job).filter { canConvertJobImages(for: $0) }
        guard !targets.isEmpty else {
            addSummary = "No completed images available for conversion"
            return
        }

        let requests = targets.map {
            OutputImageConversionRequest(jobID: $0.id, outputPath: $0.outputPath)
        }
        outputOperationStore.beginImageConversions(
            jobIDs: requests.map(\.jobID)
        )
        for request in requests {
            queueStore.updateJob(id: request.jobID) {
                $0.metadata["image_conversion_in_progress"] = "true"
                $0.metadata.removeValue(forKey: "image_conversion_error")
                $0.message = "Converting images to \(format.label)..."
            }
        }
        addSummary = "Converting images for \(requests.count) job\(requests.count == 1 ? "" : "s")..."
        persistQueue()

        let normalizedQuality = max(1, min(quality, 100))
        outputImageConversionCoordinator.start(
            requests: requests,
            format: format,
            quality: normalizedQuality
        ) { [weak self] results in
            self?.finishImageConversions(
                results,
                format: format,
                quality: normalizedQuality
            )
        }
    }

    private func finishImageConversions(
        _ results: [OutputImageConversionJobResult],
        format: ImageConversionFormat,
        quality: Int
    ) {
        var convertedJobCount = 0
        var convertedFileCount = 0
        var unchangedFileCount = 0
        var failedJobCount = 0
        let convertedAt = ISO8601DateFormatter().string(from: Date())

        for jobResult in results {
            outputOperationStore.finishImageConversion(
                jobID: jobResult.request.jobID
            )
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobResult.request.jobID }) else { continue }

            if let result = jobResult.result {
                queueStore.updateJob(at: index) { job in
                    job.metadata.removeValue(forKey: "image_conversion_in_progress")
                    if job.outputPath == jobResult.request.outputPath,
                       let primaryOutputPath = result.primaryOutputPath {
                        job.outputPath = primaryOutputPath
                    }
                    job.metadata["image_conversion_format"] = format.rawValue
                    job.metadata["image_conversion_quality"] = String(quality)
                    job.metadata["images_converted_at"] = convertedAt
                    job.metadata["images_converted_count"] = String(result.items.count)
                    job.metadata.removeValue(forKey: "image_conversion_error")
                    job.message = result.items.isEmpty
                        ? "No images needed conversion"
                        : "\(result.items.count) image\(result.items.count == 1 ? "" : "s") converted to \(format.label)"
                }
                convertedJobCount += 1
                convertedFileCount += result.items.count
                unchangedFileCount += result.unchangedCount
                refreshCompletedJobByteCountSynchronously(at: index)
            } else {
                failedJobCount += 1
                let description = jobResult.errorDescription ?? "Unknown conversion error"
                queueStore.updateJob(at: index) {
                    $0.metadata.removeValue(forKey: "image_conversion_in_progress")
                    $0.metadata["image_conversion_error"] = description
                    $0.message = "Image conversion failed: \(description)"
                }
            }
        }

        persistQueue()
        if failedJobCount > 0 {
            addSummary = "\(convertedFileCount) image(s) converted for \(convertedJobCount) job(s); \(failedJobCount) failed"
        } else if convertedFileCount > 0 {
            addSummary = "\(convertedFileCount) image(s) converted for \(convertedJobCount) job(s)"
        } else if unchangedFileCount > 0 {
            addSummary = "Selected images already use \(format.label)"
        } else {
            addSummary = "No convertible images found"
        }
    }

    func copySource(for job: DownloadJob) {
        addSummary =
            clipboardCommandService.copyText(job.source)
            ? "URL copied"
            : "Copy failed"
    }

    func artistName(for job: DownloadJob) -> String? {
        Self.originalArtistDisplayName(from: job.metadata)
    }

    func copyArtistName(for job: DownloadJob) {
        guard let artist = artistName(for: job) else {
            addSummary = "No artist name"
            return
        }
        addSummary =
            clipboardCommandService.copyText(artist)
            ? "Artist copied"
            : "Copy failed"
    }

    func copyGalleryNumbersInSaveFolder() {
        guard !outputOperationStore.isCopyingGalleryNumbers else { return }

        let root = URL(fileURLWithPath: settingsStore.destinationPath, isDirectory: true)
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            addSummary = "Save folder not found"
            return
        }

        outputOperationStore.setCopyingGalleryNumbers(true)
        addSummary = "Scanning gallery numbers..."

        let started =
            galleryNumberCopyCoordinator.begin(
                root: root
            ) { [weak self] outcome in
                guard let self else { return }
                self.outputOperationStore.setCopyingGalleryNumbers(false)
                switch outcome {
                case .copied(let count):
                    self.addSummary =
                        "Copied \(count) gallery ID\(count == 1 ? "" : "s")"
                case .copyFailed:
                    self.addSummary = "Copy failed"
                case .noNumbers:
                    self.addSummary =
                        "No gallery numbers found"
                }
            }
        if !started {
            outputOperationStore.setCopyingGalleryNumbers(
                galleryNumberCopyCoordinator.hasActiveScan
            )
        }
    }

    nonisolated static func browserSourceURL(for source: String) -> URL? {
        SourceLinkCommandService.browserURL(
            for: source
        )
    }

    func openSource(for job: DownloadJob) {
        let result = sourceLinkCommandService.openSource(
            job.source,
            skipExternalOpen:
                ProcessInfo.processInfo.environment[
                    "HITOMI_NATIVE_SKIP_EXTERNAL_OPEN"
                ] == "1"
        )
        switch result {
        case .unavailable:
            addSummary = "No browser URL"
        case .failed:
            addSummary = "Could not open source"
        case .opened:
            addSummary = "Source opened"
        }
    }

    func saveProxySettings() {
        guard persistManualProxySettings() else { return }
        addSummary = settingsStore.proxyEnabled ? "Proxy saved" : "Proxy off"
    }

    func setDPIBypassMode(_ mode: DPIBypassMode) {
        guard !networkStore.dpiBypassSnapshot.phase.isBusy else { return }
        settingsStore.dpiBypassMode = mode
        settingsStore.persistDPIBypassMode()
        browserDPIBypassService.setMode(mode, openSystemSettings: false)
        switch mode {
        case .off:
            addSummary = networkStore.dpiBypassSnapshot.hasRestorableProxySettings
                ? "Restoring network settings"
                : "DPI bypass off"
        case .appOnly:
            addSummary = networkStore.dpiBypassSnapshot.hasRestorableProxySettings
                ? "Switching DPI bypass to app only"
                : "Starting app-only DPI bypass"
        case .appAndBrowsers:
            addSummary = "Configuring app & browser DPI bypass"
        }
    }

    func restoreBrowserDPIProxySettings() {
        settingsStore.dpiBypassMode = .off
        settingsStore.persistDPIBypassMode()
        browserDPIBypassService.restoreSystemProxySettings()
        addSummary = "Restoring network settings"
    }

    var requiresBrowserDPIProxyRestorationBeforeTermination: Bool {
        browserDPIBypassService.requiresProxyRestorationBeforeTermination
    }

    func restoreBrowserDPIProxyBeforeTermination() async -> Bool {
        await browserDPIBypassService.restoreBeforeTermination()
    }

    func openBrowserDPIProxySettings() {
        if browserDPIBypassService.openSystemProxySettings() {
            addSummary = "macOS Proxy Settings opened"
        } else {
            addSummary = "Could not open macOS Network settings"
        }
    }

    func refreshBrowserDPIBypassStatus() {
        browserDPIBypassService.refreshSystemProxyState()
        networkStore.setDPIBypassSnapshot(browserDPIBypassService.snapshot)
        addSummary = "DPI bypass status refreshed"
    }

    func copyBrowserDPIProxyAddress() {
        if clipboardCommandService.copyText(
            networkStore.dpiBypassSnapshot.endpoint.displayValue
        ) {
            addSummary = "Proxy address copied"
        } else {
            addSummary = "Copy failed"
        }
    }

    func refreshPublicIP() {
        guard !networkStore.isRefreshingPublicIP else { return }
        guard persistProxySettingsForUse() else {
            networkStore.setPublicIPStatus("Proxy check failed: invalid proxy URL")
            return
        }
        let lookupURL = Self.publicIPLookupURL()
        let settings = NetworkSettings.load()
        networkStore.setRefreshingPublicIP(true)
        networkStore.setPublicIPStatus(
            Self.publicIPCheckingStatus(
                settings: settings,
                lookupURL: lookupURL
            )
        )

        let started =
            publicIPLookupCoordinator.begin(
                url: lookupURL
            ) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .success(let ip):
                    self.networkStore.setPublicIPStatus(
                        Self.publicIPStatusText(
                            ip: ip,
                            settings: settings,
                            lookupURL: lookupURL
                        )
                    )
                    self.addSummary =
                        "Public IP updated"
                case .failure(let errorDescription):
                    self.networkStore.setPublicIPStatus(
                        Self.publicIPFailureStatus(
                            settings: settings,
                            lookupURL: lookupURL,
                            errorDescription:
                                errorDescription
                        )
                    )
                    self.addSummary =
                        "Public IP check failed"
                }
                self.networkStore.setRefreshingPublicIP(false)
            }
        if !started {
            networkStore.setRefreshingPublicIP(
                publicIPLookupCoordinator
                    .hasActiveRequest
            )
        }
    }

    nonisolated static func publicIPLookupURL(
        environment: [String: String] =
            ProcessInfo.processInfo.environment
    ) -> URL {
        PublicIPLookupService.lookupURL(
            environment: environment
        )
    }

    nonisolated static func publicIPAddress(
        from text: String
    ) throws -> String {
        try PublicIPLookupService
            .publicIPAddress(from: text)
    }

    nonisolated static func publicIPCheckingStatus(
        settings: NetworkSettings,
        lookupURL: URL
    ) -> String {
        PublicIPLookupService.checkingStatus(
            settings: settings,
            lookupURL: lookupURL
        )
    }

    nonisolated static func publicIPStatusText(
        ip: String,
        settings: NetworkSettings,
        lookupURL: URL
    ) -> String {
        PublicIPLookupService.statusText(
            ip: ip,
            settings: settings,
            lookupURL: lookupURL
        )
    }

    nonisolated static func publicIPFailureStatus(
        settings: NetworkSettings,
        lookupURL: URL,
        errorDescription: String
    ) -> String {
        PublicIPLookupService.failureStatus(
            settings: settings,
            lookupURL: lookupURL,
            errorDescription: errorDescription
        )
    }

    func saveExternalToolPaths() {
        persistExternalToolPaths()
        addSummary = "Tool paths saved"
    }

    func isExternalToolAvailable(_ kind: ExternalToolKind) -> Bool {
        externalToolStatuses().first(where: { $0.name == kind.displayName })?.isAvailable == true
    }

    func resolvedExternalToolPath(_ kind: ExternalToolKind) -> String {
        externalToolStatuses().first(where: { $0.name == kind.displayName })?.resolvedPath ?? ""
    }

    func installManagedExternalTool(_ kind: ExternalToolKind) {
        guard !externalToolStore.isInstalling else { return }
        externalToolStore.setInstalling(true)
        externalToolStore.setInstallStatus(
            managedExternalToolCommandService
            .installingStatus(for: kind)
        )
        _ = externalToolInstallCoordinator.begin { [weak self] in
            guard let self else { return }
            await self.managedExternalToolCommandService
                .install(kind) { event in
                    self.applyManagedExternalToolCommandEvent(
                        event
                    )
                }
            self.externalToolStore.setInstalling(false)
        }
    }

    private func applyManagedExternalToolCommandEvent(
        _ event: ManagedExternalToolCommandEvent
    ) {
        switch event {
        case .status(let value):
            externalToolStore.setInstallStatus(value)
        case .summary(let value):
            addSummary = value
        case .installed(let result):
            applyManagedExternalTool(result)
        case .clearManagedPaths:
            clearManagedExternalToolPaths()
        }
    }

    func installAllManagedExternalTools() {
        guard !externalToolStore.isInstalling else { return }
        externalToolStore.setInstalling(true)
        _ = externalToolInstallCoordinator.begin { [weak self] in
            guard let self else { return }
            await self.managedExternalToolCommandService
                .installAll { event in
                    self.applyManagedExternalToolCommandEvent(
                        event
                    )
                }
            self.externalToolStore.setInstalling(false)
        }
    }

    func cancelManagedExternalToolInstallation() {
        externalToolInstallCoordinator.cancel()
    }

    func removeManagedExternalTools() {
        guard !externalToolStore.isInstalling else { return }
        externalToolStore.setInstalling(true)
        externalToolStore.setInstallStatus(
            managedExternalToolCommandService
            .removingStatus
        )
        _ = externalToolInstallCoordinator.begin { [weak self] in
            guard let self else { return }
            await self.managedExternalToolCommandService
                .remove { event in
                    self.applyManagedExternalToolCommandEvent(
                        event
                    )
                }
            self.externalToolStore.setInstalling(false)
        }
    }

    func revealManagedExternalTools() {
        let directory = ExternalToolSettings.managedBinDirectory
        _ = try? workspaceItemCommandService
            .createDirectoryAndOpen(directory)
    }

    private func applyManagedExternalTool(_ result: ManagedExternalToolInstallResult) {
        switch result.kind {
        case .ytdlp:
            externalToolStore.ytdlpPath = result.executableURL.path
        case .deno:
            externalToolStore.denoPath = result.executableURL.path
        case .ffmpeg:
            externalToolStore.ffmpegPath = result.executableURL.path
        case .aria2c:
            externalToolStore.aria2Path = result.executableURL.path
        }
        persistExternalToolPaths()
    }

    private func clearManagedExternalToolPaths() {
        let managedDirectory = ExternalToolSettings.managedBinDirectory.standardizedFileURL.path + "/"
        if ExternalToolSettings.normalizedExecutablePath(
            externalToolStore.ytdlpPath
        ).hasPrefix(managedDirectory) {
            externalToolStore.ytdlpPath = ""
        }
        if ExternalToolSettings.normalizedExecutablePath(
            externalToolStore.denoPath
        ).hasPrefix(managedDirectory) {
            externalToolStore.denoPath = ""
        }
        if ExternalToolSettings.normalizedExecutablePath(
            externalToolStore.ffmpegPath
        ).hasPrefix(managedDirectory) {
            externalToolStore.ffmpegPath = ""
        }
        if ExternalToolSettings.normalizedExecutablePath(
            externalToolStore.aria2Path
        ).hasPrefix(managedDirectory) {
            externalToolStore.aria2Path = ""
        }
        persistExternalToolPaths()
    }

    func saveFFmpegTranscodeOptions() {
        persistFFmpegTranscodeOptions()
        addSummary = externalToolStore.ffmpegTranscodeEnabled
            ? "ffmpeg transcode saved"
            : "ffmpeg transcode off"
    }

    func saveAria2Options() {
        persistAria2Options()
        addSummary = "aria2 options saved"
    }

    func pauseAria2(for job: DownloadJob) {
        guard queueStore.isQueueEnabled else { return }
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        if pauseAria2Job(at: index) {
            addSummary = "aria2 paused"
        } else {
            addSummary = "No running aria2 job to pause"
        }
    }

    func resumeAria2(for job: DownloadJob) {
        guard queueStore.isQueueEnabled else { return }
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        if resumeAria2Job(at: index) {
            addSummary = "aria2 resumed"
        } else {
            addSummary = "No paused aria2 job to resume"
        }
    }

    func canPauseAria2(for job: DownloadJob) -> Bool {
        queueStore.isQueueEnabled &&
            job.status == .downloading &&
            externalToolRuntime.processIsRunning(for: job.id, kind: .aria2) &&
            !aria2Store.isRuntimePaused(jobID: job.id)
    }

    func canResumeAria2(for job: DownloadJob) -> Bool {
        queueStore.isQueueEnabled &&
            job.status == .downloading &&
            externalToolRuntime.processIsRunning(for: job.id, kind: .aria2) &&
            aria2Store.isRuntimePaused(jobID: job.id)
    }

    func canApplyAria2RuntimeLimits(for job: DownloadJob) -> Bool {
        queueStore.isQueueEnabled &&
            job.status == .downloading &&
            externalToolRuntime.processIsRunning(for: job.id, kind: .aria2) &&
            externalToolRuntime.aria2RPCSession(for: job.id) != nil &&
            !aria2Store.isRuntimePaused(jobID: job.id)
    }

    func canApplyAria2RuntimeFileSelection(for job: DownloadJob) -> Bool {
        canApplyAria2RuntimeLimits(for: job)
    }

    func canApplyAria2RuntimeSeeding(for job: DownloadJob) -> Bool {
        canApplyAria2RuntimeLimits(for: job)
    }

    func canPreviewAria2Files(for job: DownloadJob) -> Bool {
        aria2URL(for: job) != nil
    }

    func canRefreshAria2Peers(for job: DownloadJob) -> Bool {
        canApplyAria2RuntimeLimits(for: job)
    }

    func applyCurrentAria2RuntimeLimits(for job: DownloadJob) {
        aria2RuntimeCommandCoordinator.begin {
            [weak self] in
            guard let self else { return }
            _ = await self.applyAria2RuntimeLimits(
                for: job,
                downloadLimit:
                    self.aria2Store.maxDownloadLimit,
                uploadLimit:
                    self.aria2Store.maxUploadLimit
            )
        }
    }

    func applyCurrentAria2RuntimeFileSelection(for job: DownloadJob) {
        aria2RuntimeCommandCoordinator.begin {
            [weak self] in
            guard let self else { return }
            _ = await self
                .applyAria2RuntimeFileSelection(
                    for: job,
                    selectedFiles:
                        self.aria2Store.selectedFiles
                )
        }
    }

    func applyCurrentAria2RuntimeSeeding(for job: DownloadJob) {
        aria2RuntimeCommandCoordinator.begin {
            [weak self] in
            guard let self else { return }
            _ = await self.applyAria2RuntimeSeeding(
                for: job,
                seedTimeMinutes:
                    self.aria2Store.seedTimeMinutes,
                seedRatio: self.aria2Store.seedRatio
            )
        }
    }

    func previewAria2Files(for job: DownloadJob) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            aria2Store.setFileEntries([])
            aria2Store.setFileListSummary("Task not found")
            return
        }
        aria2Store.setFileEntries([])
        aria2Store.setFileListSummary("Reading torrent file list")
        aria2RuntimeCommandCoordinator.begin {
            [weak self] in
            _ = await self?
                .loadAria2FileEntriesJob(at: index)
        }
    }

    func refreshAria2Peers(for job: DownloadJob) {
        aria2Store.setPeerSummary("Reading aria2 peers")
        aria2RuntimeCommandCoordinator.begin {
            [weak self] in
            _ = await self?.loadAria2Peers(for: job)
        }
    }

    @discardableResult
    func applyAria2RuntimeLimits(for job: DownloadJob, downloadLimit: String, uploadLimit: String) async -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            addSummary = "Task not found"
            return false
        }
        let ok = await applyAria2RuntimeLimitsJob(at: index, downloadLimit: downloadLimit, uploadLimit: uploadLimit)
        addSummary = ok ? "aria2 limits applied" : "No running aria2 job for limits"
        return ok
    }

    @discardableResult
    func applyAria2RuntimeFileSelection(for job: DownloadJob, selectedFiles: String) async -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            addSummary = "Task not found"
            return false
        }
        let ok = await applyAria2RuntimeFileSelectionJob(at: index, selectedFiles: selectedFiles)
        addSummary = ok ? "aria2 file selection applied" : "No running aria2 job for file selection"
        return ok
    }

    @discardableResult
    func applyAria2RuntimeSeeding(for job: DownloadJob, seedTimeMinutes: String, seedRatio: String) async -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            addSummary = "Task not found"
            return false
        }
        let ok = await applyAria2RuntimeSeedingJob(at: index, seedTimeMinutes: seedTimeMinutes, seedRatio: seedRatio)
        addSummary = ok ? "aria2 seeding applied" : "No running aria2 job for seeding"
        return ok
    }

    @discardableResult
    func loadAria2Peers(for job: DownloadJob) async -> [Aria2PeerEntry]? {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            aria2Store.setPeerEntries([])
            aria2Store.setPeerSummary("Task not found")
            addSummary = "Task not found"
            return nil
        }
        return await loadAria2PeersJob(at: index)
    }

    @discardableResult
    func loadAria2FileEntries(for job: DownloadJob) async -> [Aria2FileEntry]? {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            aria2Store.setFileEntries([])
            aria2Store.setFileListSummary("Task not found")
            addSummary = "Task not found"
            return nil
        }
        return await loadAria2FileEntriesJob(at: index)
    }

    @discardableResult
    private func pauseAria2Job(at index: Int, persist: Bool = true) -> Bool {
        guard queueStore.jobs.indices.contains(index),
              queueStore.jobs[index].status == .downloading,
              let control = externalToolRuntime.processControl(
                  for: queueStore.jobs[index].id,
                  kind: .aria2
              ),
              !aria2Store.isRuntimePaused(jobID: queueStore.jobs[index].id),
              control.suspend() else {
            return false
        }

        let jobID = queueStore.jobs[index].id
        aria2Store.setRuntimePaused(true, jobID: jobID)
        queueStore.updateJob(at: index) {
            $0.message = "aria2c paused"
            $0.metadata["aria2_runtime_paused"] = "true"
        }
        if persist {
            persistQueue()
        }
        return true
    }

    @discardableResult
    private func resumeAria2Job(at index: Int, persist: Bool = true) -> Bool {
        guard queueStore.jobs.indices.contains(index),
              queueStore.jobs[index].status == .downloading,
              let control = externalToolRuntime.processControl(
                  for: queueStore.jobs[index].id,
                  kind: .aria2
              ),
              aria2Store.isRuntimePaused(jobID: queueStore.jobs[index].id),
              control.resume() else {
            return false
        }

        let jobID = queueStore.jobs[index].id
        aria2Store.setRuntimePaused(false, jobID: jobID)
        queueStore.updateJob(at: index) {
            $0.message = "Running aria2c"
            $0.metadata["aria2_runtime_paused"] = "false"
        }
        if persist {
            persistQueue()
        }
        return true
    }

    private func cleanupAria2RuntimeControl(for jobID: UUID) {
        aria2Store.setRuntimePaused(false, jobID: jobID)
        externalToolRuntime.removeAria2RuntimeState(for: jobID)
    }

    @discardableResult
    private func applyAria2RuntimeLimitsJob(at index: Int, downloadLimit: String, uploadLimit: String, persist: Bool = true) async -> Bool {
        guard queueStore.jobs.indices.contains(index),
              queueStore.jobs[index].status == .downloading,
              let session = externalToolRuntime.aria2RPCSession(for: queueStore.jobs[index].id),
              externalToolRuntime.processIsRunning(for: queueStore.jobs[index].id, kind: .aria2),
              !aria2Store.isRuntimePaused(jobID: queueStore.jobs[index].id) else {
            return false
        }

        let jobID = queueStore.jobs[index].id
        do {
            let applied =
                try await aria2RuntimeCommandService
                .changeSpeedLimits(
                session: session,
                downloadLimit: downloadLimit,
                uploadLimit: uploadLimit
            )
            let down = applied["max_download_limit"] ?? ""
            let up = applied["max_upload_limit"] ?? ""
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["max_download_limit"] = down
                $0.metadata["max_upload_limit"] = up
                $0.metadata["runtime_max_download_limit"] = down
                $0.metadata["runtime_max_upload_limit"] = up
                $0.metadata["aria2_runtime_limit_error"] = ""
                $0.message = Self.aria2RuntimeLimitMessage(downloadLimit: down, uploadLimit: up)
            }) else { return false }
            if persist {
                persistQueue()
            }
            return true
        } catch {
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["aria2_runtime_limit_error"] = AppLocalization.errorText(error)
                $0.message = "aria2 limit update failed"
            }) else { return false }
            if persist {
                persistQueue()
            }
            return false
        }
    }

    private nonisolated static func aria2RuntimeLimitMessage(downloadLimit: String, uploadLimit: String) -> String {
        let parts = [
            downloadLimit.isEmpty ? nil : "down \(downloadLimit)",
            uploadLimit.isEmpty ? nil : "up \(uploadLimit)"
        ].compactMap { $0 }
        return parts.isEmpty ? "aria2c limits cleared" : "aria2c limits: \(parts.joined(separator: ", "))"
    }

    @discardableResult
    private func applyAria2RuntimeFileSelectionJob(at index: Int, selectedFiles: String, persist: Bool = true) async -> Bool {
        guard queueStore.jobs.indices.contains(index),
              queueStore.jobs[index].status == .downloading,
              let session = externalToolRuntime.aria2RPCSession(for: queueStore.jobs[index].id),
              externalToolRuntime.processIsRunning(for: queueStore.jobs[index].id, kind: .aria2),
              !aria2Store.isRuntimePaused(jobID: queueStore.jobs[index].id) else {
            return false
        }

        let jobID = queueStore.jobs[index].id
        do {
            let applied =
                try await aria2RuntimeCommandService
                .changeFileSelection(
                session: session,
                selectedFiles: selectedFiles
            )
            let files = applied["selected_files"] ?? ""
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["selected_files"] = files
                $0.metadata["runtime_selected_files"] = files
                $0.metadata["aria2_runtime_file_selection_error"] = ""
                $0.message = Self.aria2RuntimeFileSelectionMessage(selectedFiles: files)
            }) else { return false }
            if persist {
                persistQueue()
            }
            return true
        } catch {
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["aria2_runtime_file_selection_error"] = AppLocalization.errorText(error)
                $0.message = "aria2 file selection update failed"
            }) else { return false }
            if persist {
                persistQueue()
            }
            return false
        }
    }

    private nonisolated static func aria2RuntimeFileSelectionMessage(selectedFiles: String) -> String {
        selectedFiles.isEmpty ? "aria2c files unchanged" : "aria2c files: \(selectedFiles)"
    }

    @discardableResult
    private func applyAria2RuntimeSeedingJob(
        at index: Int,
        seedTimeMinutes: String,
        seedRatio: String,
        persist: Bool = true
    ) async -> Bool {
        guard queueStore.jobs.indices.contains(index),
              queueStore.jobs[index].status == .downloading,
              let session = externalToolRuntime.aria2RPCSession(for: queueStore.jobs[index].id),
              externalToolRuntime.processIsRunning(for: queueStore.jobs[index].id, kind: .aria2),
              !aria2Store.isRuntimePaused(jobID: queueStore.jobs[index].id) else {
            return false
        }

        let jobID = queueStore.jobs[index].id
        do {
            let applied =
                try await aria2RuntimeCommandService
                .changeSeeding(
                session: session,
                seedTimeMinutes: seedTimeMinutes,
                seedRatio: seedRatio
            )
            let seedTime = applied["seed_time_minutes"] ?? "0"
            let ratio = applied["seed_ratio"] ?? ""
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["seed_time_minutes"] = seedTime
                $0.metadata["seed_ratio"] = ratio
                $0.metadata["runtime_seed_time_minutes"] = seedTime
                $0.metadata["runtime_seed_ratio"] = ratio
                $0.metadata["aria2_runtime_seed_error"] = ""
                $0.message = Self.aria2RuntimeSeedingMessage(seedTimeMinutes: seedTime, seedRatio: ratio)
            }) else { return false }
            if persist {
                persistQueue()
            }
            return true
        } catch {
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["aria2_runtime_seed_error"] = AppLocalization.errorText(error)
                $0.message = "aria2 seeding update failed"
            }) else { return false }
            if persist {
                persistQueue()
            }
            return false
        }
    }

    private nonisolated static func aria2RuntimeSeedingMessage(seedTimeMinutes: String, seedRatio: String) -> String {
        let parts = [
            "seed \(seedTimeMinutes)m",
            seedRatio.isEmpty ? nil : "ratio \(seedRatio)"
        ].compactMap { $0 }
        return "aria2c seeding: \(parts.joined(separator: ", "))"
    }

    @discardableResult
    private func loadAria2PeersJob(at index: Int) async -> [Aria2PeerEntry]? {
        guard queueStore.jobs.indices.contains(index),
              queueStore.jobs[index].status == .downloading,
              let session = externalToolRuntime.aria2RPCSession(for: queueStore.jobs[index].id),
              externalToolRuntime.processIsRunning(for: queueStore.jobs[index].id, kind: .aria2),
              !aria2Store.isRuntimePaused(jobID: queueStore.jobs[index].id) else {
            aria2Store.setPeerEntries([])
            aria2Store.setPeerSummary("No running aria2 job for peers")
            addSummary = "No running aria2 job for peers"
            return nil
        }

        let jobID = queueStore.jobs[index].id
        do {
            let peers =
                try await aria2RuntimeCommandService
                .peerEntries(session: session)
            aria2Store.setPeerEntries(peers)
            aria2Store.setPeerSummary(Self.aria2PeerSummary(for: peers))
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["aria2_peer_count"] = String(peers.count)
                $0.metadata["aria2_runtime_peer_error"] = ""
            }) else { return nil }
            addSummary = peers.isEmpty ? "aria2 peers empty" : "aria2 peers updated"
            persistQueue()
            return peers
        } catch {
            aria2Store.setPeerEntries([])
            aria2Store.setPeerSummary(
                "Peer list failed: \(AppLocalization.errorText(error))"
            )
            guard queueStore.updateJob(id: jobID, {
                $0.metadata["aria2_runtime_peer_error"] = AppLocalization.errorText(error)
            }) else { return nil }
            addSummary = "aria2 peer list failed"
            persistQueue()
            return nil
        }
    }

    private nonisolated static func aria2PeerSummary(for peers: [Aria2PeerEntry]) -> String {
        guard !peers.isEmpty else { return "No aria2 peers" }
        let prefix = peers.prefix(4).map(\.summary).joined(separator: ", ")
        let suffix = peers.count > 4 ? ", ..." : ""
        return "\(peers.count) peers: \(prefix)\(suffix)"
    }

    func previewAria2Files() {
        persistExternalToolPaths()
        let urls = extractURLs(from: presentation.inputText)
        guard let source = urls.first,
              let url = URL(string: source.trimmed),
              aria2Bridge.canResolve(url) else {
            aria2Store.setFileEntries([])
            aria2Store.setFileListSummary("Paste a magnet or .torrent URL")
            return
        }

        let headers = requestOptions(for: url)
        aria2Store.setFileEntries([])
        aria2Store.setFileListSummary("Reading torrent file list")

        aria2RuntimeCommandCoordinator.begin {
            [weak self] in
            _ = await self?.loadAria2FileEntries(
                from: url,
                headers: headers,
                jobID: nil
            )
        }
    }

    @discardableResult
    private func loadAria2FileEntriesJob(at index: Int) async -> [Aria2FileEntry]? {
        guard queueStore.jobs.indices.contains(index),
              let url = aria2URL(for: queueStore.jobs[index]) else {
            aria2Store.setFileEntries([])
            aria2Store.setFileListSummary("No torrent source for file list")
            addSummary = "No torrent source for file list"
            return nil
        }

        let job = queueStore.jobs[index]
        let headers = requestOptions(for: url)
        return await loadAria2FileEntries(from: url, headers: headers, jobID: job.id)
    }

    @discardableResult
    private func loadAria2FileEntries(
        from url: URL,
        headers: HTTPRequestOptions,
        jobID: UUID?
    ) async -> [Aria2FileEntry]? {
        do {
            let entries = try await externalToolRuntime.executeAria2FileList(
                url: url,
                headers: headers
            )
            aria2Store.setFileEntries(entries)
            aria2Store.setFileListSummary(
                Self.aria2FileListSummary(for: entries)
            )
            if let jobID,
               queueStore.updateJob(id: jobID, {
                   $0.metadata["aria2_file_count"] = String(entries.count)
                   $0.metadata["aria2_file_list_error"] = ""
               }) {
                persistQueue()
            }
            addSummary = "aria2 files listed"
            return entries
        } catch {
            aria2Store.setFileEntries([])
            aria2Store.setFileListSummary(
                "File list failed: \(AppLocalization.errorText(error))"
            )
            if let jobID,
               queueStore.updateJob(id: jobID, {
                   $0.metadata["aria2_file_list_error"] = AppLocalization.errorText(error)
               }) {
                persistQueue()
            }
            addSummary = "aria2 file list failed"
            return nil
        }
    }

    private func aria2URL(for job: DownloadJob) -> URL? {
        let source = job.source.trimmed
        guard !source.isEmpty,
              let url = URL(string: source),
              aria2Bridge.canResolve(url) else {
            return nil
        }
        return url
    }

    func useAllAria2PreviewFiles() {
        applyAria2PreviewSelection(
            aria2Store.fileEntries.map(\.index),
            emptySummary: "No torrent files to select"
        )
    }

    func useSelectedAria2PreviewFiles() {
        let selected = aria2Store.fileEntries
            .filter { $0.selected != false }
            .map(\.index)
        applyAria2PreviewSelection(selected, emptySummary: "No selected torrent files")
    }

    func clearAria2FileSelection() {
        aria2Store.selectedFiles = ""
        persistAria2Options()
        aria2Store.setFileListSummary(
            aria2Store.fileEntries.isEmpty
                ? "Torrent file selection cleared"
                : Self.aria2FileListSummary(for: aria2Store.fileEntries)
        )
        addSummary = "aria2 file selection cleared"
    }

    private func applyAria2PreviewSelection(_ indexes: [Int], emptySummary: String) {
        let selection = Self.aria2SelectionExpression(for: indexes)
        guard !selection.isEmpty else {
            aria2Store.setFileListSummary(emptySummary)
            return
        }
        aria2Store.selectedFiles = selection
        persistAria2Options()
        aria2Store.setFileListSummary(
            "\(aria2Store.fileEntries.count) files, selected \(selection)"
        )
        addSummary = "aria2 files selected"
    }

    func saveAutoRecordSettings() {
        persistAutoRecordSettings()
        syncAutoRecordMonitor()
        addSummary = autoRecordStore.isEnabled
            ? "Automatic Recording Saved"
            : "Automatic Recording Off"
    }

    func setAutoRecordEnabled(_ enabled: Bool) {
        autoRecordStore.setEnabled(enabled)
        persistAutoRecordSettings()
        syncAutoRecordMonitor()
        addSummary = enabled ? "Automatic Recording On" : "Automatic Recording Off"
    }

    func setAutoRecordPaused(_ paused: Bool) {
        autoRecordStore.setPaused(paused)
        persistAutoRecordSettings()
        syncAutoRecordMonitor()
        addSummary = paused ? "Automatic Recording Paused" : "Automatic Recording Resumed"
    }

    func checkAutoRecordNow() {
        persistAutoRecordSettings()
        autoRecordCheckCommandCoordinator.begin {
            [weak self] in
            self?.performAutoRecordCheck(
                startQueueIfNeeded: true
            )
        }
    }

    private func persistAutoRecordSettings() {
        autoRecordStore.urlsText = normalizedAutoRecordURLsText(
            from: autoRecordStore.urlsText
        )
        let interval = Self.normalizedAutoRecordIntervalMinutes(
            from: autoRecordStore.intervalMinutesString
        )
        autoRecordStore.intervalMinutesString = String(interval)
        UserDefaults.standard.set(autoRecordStore.isEnabled, forKey: "autoRecordEnabled")
        UserDefaults.standard.set(autoRecordStore.isPaused, forKey: "autoRecordPaused")
        UserDefaults.standard.set(autoRecordStore.urlsText, forKey: "autoRecordURLsText")
        UserDefaults.standard.set(interval, forKey: "autoRecordIntervalMinutes")
    }

    private func syncAutoRecordMonitor() {
        autoRecordMonitorCoordinator.cancelAndClear()

        guard autoRecordStore.isEnabled else {
            autoRecordStore.setChecking(false)
            autoRecordStore.setStatus("Automatic Recording Off")
            return
        }
        guard !autoRecordStore.isPaused else {
            autoRecordStore.setChecking(false)
            autoRecordStore.setStatus("Automatic Recording Paused")
            return
        }

        autoRecordStore.setStatus("Automatic Recording Waiting")
        autoRecordMonitorCoordinator.start(
            check: { [weak self] in
                self?.performAutoRecordCheck(
                    startQueueIfNeeded: true
                )
            },
            intervalNanoseconds: { [weak self] in
                guard let self else {
                    return Self.autoRecordIntervalNanoseconds(
                        fromMinutes: 10
                    )
                }
                return Self.autoRecordIntervalNanoseconds(
                    from: self.autoRecordStore.intervalMinutesString
                )
            }
        )
    }

    @discardableResult
    private func performAutoRecordCheck(startQueueIfNeeded: Bool) -> Int {
        guard !autoRecordStore.isChecking else { return 0 }
        guard autoRecordStore.isEnabled else {
            autoRecordStore.setStatus("Automatic Recording Off")
            return 0
        }
        guard !autoRecordStore.isPaused else {
            autoRecordStore.setStatus("Automatic Recording Paused")
            return 0
        }

        let urls = autoRecordURLs()
        guard !urls.isEmpty else {
            autoRecordStore.setStatus("Automatic Recording URL Required")
            return 0
        }

        autoRecordStore.setChecking(true)
        autoRecordStore.setStatus("Checking Automatic Recording...")
        defer { autoRecordStore.setChecking(false) }

        let newJobs = jobsForAdding(
            urls,
            metadata: [
                "auto_record": "true",
                "recording": "true"
            ],
            titleSuffix: " [Auto]"
        )
        let added = newJobs.count
        if added > 0 {
            insertAddedJobsAtTop(newJobs)
            persistQueue()
            autoRecordStore.setStatus("Automatic Recording Added \(added) to Queue")
            addSummary = "Automatic Recording: Added \(added) to Queue"
            if startQueueIfNeeded,
               !queueRunCoordinator.hasActiveRun {
                startQueue(addingInput: false)
            }
        } else {
            autoRecordStore.setStatus(addSummary.trimmed.isEmpty
                ? "Automatic Recording Check: No New URLs"
                : "Automatic Recording Check: \(addSummary)")
        }
        return added
    }

    private func autoRecordURLs() -> [String] {
        extractMonitorableURLs(from: autoRecordStore.urlsText)
    }

    private func normalizedAutoRecordURLsText(from raw: String) -> String {
        var seen = Set<String>()
        return extractMonitorableURLs(from: raw)
            .filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }

    nonisolated static func normalizedAutoRecordIntervalMinutes(from raw: String) -> Int {
        let minutes = autoRecordIntervalMinutes(from: raw) ?? 10
        return min(1_440, max(1, Int(ceil(minutes))))
    }

    nonisolated static func autoRecordIntervalNanoseconds(from raw: String) -> UInt64 {
        autoRecordIntervalNanoseconds(fromMinutes: normalizedAutoRecordIntervalMinutes(from: raw))
    }

    private nonisolated static func autoRecordIntervalMinutes(from raw: String) -> Double? {
        let value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }

        if value.contains(":") {
            return FilterSyntaxCore.durationSeconds(from: value).map { $0 / 60 }
        }
        if value.range(of: #"[a-z]"#, options: .regularExpression) != nil {
            return FilterSyntaxCore.compoundDurationSeconds(from: value).map { $0 / 60 }
        }
        guard let minutes = Double(value), minutes >= 0 else {
            return nil
        }
        return minutes
    }

    private nonisolated static func autoRecordIntervalNanoseconds(fromMinutes minutes: Int) -> UInt64 {
        UInt64(minutes) * 60 * 1_000_000_000
    }

    nonisolated static func normalizedM3U8SegmentDelayMilliseconds(from raw: String) -> Int {
        SettingsStore.normalizedM3U8SegmentDelayMilliseconds(from: raw)
    }

    nonisolated static func m3u8SegmentRateLimitNanoseconds(from raw: String) -> UInt64 {
        UInt64(normalizedM3U8SegmentDelayMilliseconds(from: raw)) * 1_000_000
    }

    private func persistExternalToolPaths() {
        externalToolStore.ytdlpPath =
            ExternalToolSettings.normalizedExecutablePath(
                externalToolStore.ytdlpPath
            )
        externalToolStore.denoPath =
            ExternalToolSettings.normalizedExecutablePath(
                externalToolStore.denoPath
            )
        externalToolStore.ffmpegPath =
            ExternalToolSettings.normalizedExecutablePath(
                externalToolStore.ffmpegPath
            )
        externalToolStore.aria2Path =
            ExternalToolSettings.normalizedExecutablePath(
                externalToolStore.aria2Path
            )
        ExternalToolSettings.save(
            path: externalToolStore.ytdlpPath,
            for: .ytdlp
        )
        ExternalToolSettings.save(
            path: externalToolStore.denoPath,
            for: .deno
        )
        ExternalToolSettings.save(
            path: externalToolStore.ffmpegPath,
            for: .ffmpeg
        )
        ExternalToolSettings.save(
            path: externalToolStore.aria2Path,
            for: .aria2c
        )
    }

    private func persistFFmpegTranscodeOptions() {
        let options = ffmpegTranscodeOptionsForUse()
        externalToolStore.ffmpegTranscodeEnabled = options.enabled
        externalToolStore.ffmpegVideoCodec = options.videoCodec
        externalToolStore.ffmpegAudioCodec = options.audioCodec
        externalToolStore.ffmpegVideoBitrate = options.videoBitrate
        externalToolStore.ffmpegAudioBitrate = options.audioBitrate
        externalToolStore.ffmpegCRF = options.crf
        externalToolStore.ffmpegPreset = options.preset
        UserDefaults.standard.set(
            externalToolStore.ffmpegTranscodeEnabled,
            forKey: "ffmpegTranscodeEnabled"
        )
        UserDefaults.standard.set(
            externalToolStore.ffmpegVideoCodec,
            forKey: "ffmpegVideoCodec"
        )
        UserDefaults.standard.set(
            externalToolStore.ffmpegAudioCodec,
            forKey: "ffmpegAudioCodec"
        )
        UserDefaults.standard.set(
            externalToolStore.ffmpegVideoBitrate,
            forKey: "ffmpegVideoBitrate"
        )
        UserDefaults.standard.set(
            externalToolStore.ffmpegAudioBitrate,
            forKey: "ffmpegAudioBitrate"
        )
        UserDefaults.standard.set(
            externalToolStore.ffmpegCRF,
            forKey: "ffmpegCRF"
        )
        UserDefaults.standard.set(
            externalToolStore.ffmpegPreset,
            forKey: "ffmpegPreset"
        )
    }

    private func ffmpegTranscodeOptionsForUse() -> FFmpegTranscodeOptions {
        FFmpegTranscodeOptions(
            enabled: externalToolStore.ffmpegTranscodeEnabled,
            videoCodec: externalToolStore.ffmpegVideoCodec,
            audioCodec: externalToolStore.ffmpegAudioCodec,
            videoBitrate: externalToolStore.ffmpegVideoBitrate,
            audioBitrate: externalToolStore.ffmpegAudioBitrate,
            crf: externalToolStore.ffmpegCRF,
            preset: externalToolStore.ffmpegPreset
        ).normalized
    }

    private func persistAria2Options() {
        let options = aria2OptionsForUse()
        aria2Store.selectedFiles = options.selectedFiles
        aria2Store.seedTimeMinutes = options.seedTimeMinutes
        aria2Store.seedRatio = options.seedRatio
        aria2Store.maxDownloadLimit = options.maxDownloadLimit
        aria2Store.maxUploadLimit = options.maxUploadLimit
        aria2Store.trackers = options.trackerURLs
        aria2Store.anonymousMode = options.anonymousMode
        UserDefaults.standard.set(aria2Store.selectedFiles, forKey: "aria2SelectedFiles")
        UserDefaults.standard.set(aria2Store.seedTimeMinutes, forKey: "aria2SeedTimeMinutes")
        UserDefaults.standard.set(aria2Store.seedRatio, forKey: "aria2SeedRatio")
        UserDefaults.standard.set(aria2Store.maxDownloadLimit, forKey: "aria2MaxDownloadLimit")
        UserDefaults.standard.set(aria2Store.maxUploadLimit, forKey: "aria2MaxUploadLimit")
        UserDefaults.standard.set(aria2Store.trackers, forKey: "aria2Trackers")
        UserDefaults.standard.set(aria2Store.anonymousMode, forKey: "aria2AnonymousMode")
    }

    private func aria2OptionsForUse() -> Aria2Options {
        Aria2Options(
            selectedFiles: aria2Store.selectedFiles,
            seedTimeMinutes: aria2Store.seedTimeMinutes,
            seedRatio: aria2Store.seedRatio,
            maxDownloadLimit: aria2Store.maxDownloadLimit,
            maxUploadLimit: aria2Store.maxUploadLimit,
            trackerURLs: aria2Store.trackers,
            anonymousMode: aria2Store.anonymousMode
        )
    }

    nonisolated static func aria2Options(base: Aria2Options, comment: String) -> Aria2Options {
        var selectedFiles = base.selectedFiles
        var seedTimeMinutes = base.seedTimeMinutes
        var seedRatio = base.seedRatio
        var maxDownloadLimit = base.maxDownloadLimit
        var maxUploadLimit = base.maxUploadLimit
        var trackerURLs = base.trackerURLs
        var anonymousMode = base.anonymousMode

        for pair in aria2CommentPairs(from: comment) {
            let key = normalizedAria2CommentKey(pair.key)
            let value = pair.value.trimmed
            guard !key.isEmpty, !value.isEmpty else { continue }
            switch key {
            case "files":
                selectedFiles = value
            case "seed":
                seedTimeMinutes = value
            case "ratio":
                seedRatio = value
            case "down":
                maxDownloadLimit = value
            case "up":
                maxUploadLimit = value
            case "tracker":
                trackerURLs = value
            case "anon":
                anonymousMode = boolDirectiveValue(value) ?? anonymousMode
            default:
                continue
            }
        }

        return Aria2Options(
            selectedFiles: selectedFiles,
            seedTimeMinutes: seedTimeMinutes,
            seedRatio: seedRatio,
            maxDownloadLimit: maxDownloadLimit,
            maxUploadLimit: maxUploadLimit,
            trackerURLs: trackerURLs,
            anonymousMode: anonymousMode
        )
    }

    private nonisolated static func aria2CommentPairs(from comment: String) -> [(key: String, value: String)] {
        var pairs: [(key: String, value: String)] = []
        for line in comment.components(separatedBy: .newlines) {
            guard let directive = aria2DirectiveText(from: line) else { continue }
            let tokens = directiveTokens(from: directive)
            var index = 0
            while index < tokens.count {
                let token = tokens[index]
                if let separatorIndex = token.firstIndex(where: { $0 == "=" || $0 == ":" }) {
                    let key = String(token[..<separatorIndex])
                    let value = String(token[token.index(after: separatorIndex)...])
                    pairs.append((key, value))
                } else if index + 1 < tokens.count, !normalizedAria2CommentKey(token).isEmpty {
                    pairs.append((token, tokens[index + 1]))
                    index += 1
                }
                index += 1
            }
        }
        return pairs
    }

    private nonisolated static func aria2DirectiveText(from line: String) -> String? {
        let trimmed = line.trimmed
        let lower = trimmed.lowercased()
        if lower.hasPrefix("aria2:") || lower.hasPrefix("aria2=") {
            return String(trimmed.dropFirst(6)).trimmed
        }
        if lower.hasPrefix("aria2 ") {
            return String(trimmed.dropFirst(6)).trimmed
        }
        return nil
    }

    private nonisolated static func directiveTokens(from text: String) -> [String] {
        var tokens: [String] = []
        var token = ""
        var quote: Character?
        for character in text {
            if character == "\"" || character == "'" {
                if quote == character {
                    quote = nil
                } else if quote == nil {
                    quote = character
                } else {
                    token.append(character)
                }
            } else if character.isWhitespace, quote == nil {
                if !token.isEmpty {
                    tokens.append(token)
                    token = ""
                }
            } else {
                token.append(character)
            }
        }
        if !token.isEmpty {
            tokens.append(token)
        }
        return tokens
    }

    private nonisolated static func normalizedAria2CommentKey(_ raw: String) -> String {
        let key = raw
            .trimmed
            .lowercased()
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: ".", with: "-")
        switch key {
        case "file", "files", "select", "select-file", "selected-file", "selected-files":
            return "files"
        case "seed", "seed-time", "seed-minutes", "seed-time-minutes", "time":
            return "seed"
        case "ratio", "seed-ratio":
            return "ratio"
        case "down", "dl", "download", "download-limit", "max-download", "max-download-limit":
            return "down"
        case "up", "ul", "upload", "upload-limit", "max-upload", "max-upload-limit":
            return "up"
        case "tracker", "trackers", "bt-tracker":
            return "tracker"
        case "anon", "anonymous", "anonymous-mode", "privacy", "private":
            return "anon"
        default:
            return ""
        }
    }

    private nonisolated static func boolDirectiveValue(_ raw: String) -> Bool? {
        switch raw.trimmed.lowercased() {
        case "1", "true", "yes", "y", "on", "enable", "enabled":
            return true
        case "0", "false", "no", "n", "off", "disable", "disabled":
            return false
        default:
            return nil
        }
    }

    private nonisolated static func aria2FileListSummary(for entries: [Aria2FileEntry]) -> String {
        guard !entries.isEmpty else { return "No torrent files" }
        let prefix = entries.prefix(4).map { entry -> String in
            if entry.length.isEmpty {
                return "\(entry.index): \(entry.path)"
            }
            return "\(entry.index): \(entry.path) (\(entry.length))"
        }.joined(separator: ", ")
        let suffix = entries.count > 4 ? ", ..." : ""
        return "\(entries.count) files: \(prefix)\(suffix)"
    }

    nonisolated static func aria2SelectionExpression(for indexes: [Int]) -> String {
        let values = Array(Set(indexes.filter { $0 > 0 })).sorted()
        guard !values.isEmpty else { return "" }

        var ranges: [String] = []
        var start = values[0]
        var previous = values[0]

        for value in values.dropFirst() {
            if value == previous + 1 {
                previous = value
                continue
            }
            ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
            start = value
            previous = value
        }

        ranges.append(start == previous ? "\(start)" : "\(start)-\(previous)")
        return ranges.joined(separator: ",")
    }

    func setHTTPAPIEnabled(_ enabled: Bool) {
        settingsStore.httpAPIEnabled = enabled
        settingsStore.persistHTTPAPISettings()
        if enabled {
            startHTTPAPIServer()
        } else {
            stopHTTPAPIServer()
            addSummary = "HTTP API Off"
        }
    }

    func saveHTTPAPISettings() {
        settingsStore.persistHTTPAPISettings()
        if settingsStore.httpAPIEnabled {
            startHTTPAPIServer()
        }
        addSummary = settingsStore.httpAPIEnabled
            ? "HTTP API Saved"
            : "HTTP API Off"
    }

    func setClipboardMonitorEnabled(_ enabled: Bool) {
        settingsStore.clipboardMonitorEnabled = enabled
        settingsStore.persistClipboardAutomation()
        if enabled {
            startClipboardMonitor()
            addSummary = "Clipboard watch on"
        } else {
            stopClipboardMonitor()
            addSummary = "Clipboard watch off"
        }
    }

    func setStartDownloadsOnPaste(_ enabled: Bool) {
        settingsStore.startDownloadsOnPaste = enabled
        settingsStore.persistClipboardAutomation()
        addSummary = enabled ? "Paste starts downloads" : "Paste only adds to queue"
    }

    func setNotifyWhenJobCompletes(_ enabled: Bool) {
        settingsStore.notifyWhenJobCompletes = enabled
        persistCompletionAlertSettings()
        if enabled {
            completionAlerts.requestAuthorizationIfNeeded()
        }
        addSummary = enabled ? "Job notifications on" : "Job notifications off"
    }

    func setNotifyWhenQueueCompletes(_ enabled: Bool) {
        settingsStore.notifyWhenQueueCompletes = enabled
        persistCompletionAlertSettings()
        if enabled {
            completionAlerts.requestAuthorizationIfNeeded()
        }
        addSummary = enabled ? "Queue notifications on" : "Queue notifications off"
    }

    func setPlaySoundWhenJobCompletes(_ enabled: Bool) {
        settingsStore.playSoundWhenJobCompletes = enabled
        persistCompletionAlertSettings()
        addSummary = enabled ? "Completion sound on" : "Completion sound off"
    }

    func setPlaySoundOnClipboardAdd(_ enabled: Bool) {
        settingsStore.playSoundOnClipboardAdd = enabled
        persistCompletionAlertSettings()
        addSummary = enabled ? "Clipboard add sound on" : "Clipboard add sound off"
    }

    func setQueueCompletionAction(_ action: QueueCompletionAction) {
        settingsStore.queueCompletionAction = action
        appStatusStore.setQueueCompletionActionStatus(
            Self.queueCompletionActionStatusText(for: action)
        )
        persistCompletionAlertSettings()
        addSummary = action == .none ? "After Completion Disabled" : "After completion: \(action.label)"
    }

    func setPreventSleepWhileDownloading(_ enabled: Bool) {
        settingsStore.preventSleepWhileDownloading = enabled
        settingsStore.persistSleepPrevention()
        syncSleepPreventionAssertion()
        if enabled,
           queueStore.isRunning,
           !appStatusStore.sleepPreventionActive {
            addSummary = "Sleep prevention unavailable"
        } else {
            addSummary = enabled ? "Sleep prevention on" : "Sleep prevention off"
        }
    }

    func setLaunchAtLoginEnabled(_ enabled: Bool) {
        settingsStore.launchAtLoginEnabled = enabled
        settingsStore.persistLaunchAtLogin()
        addSummary = LaunchAtLoginSettings.apply(enabled: enabled)
    }

    private func syncSleepPreventionAssertion() {
        guard settingsStore.preventSleepWhileDownloading && queueStore.isRunning else {
            releaseSleepPreventionAssertion()
            return
        }

        if sleepPreventionAssertion.acquire() {
            appStatusStore.setSleepPreventionActive(true)
        } else {
            appStatusStore.setSleepPreventionActive(false)
            addSummary = "Sleep prevention unavailable"
        }
    }

    private func releaseSleepPreventionAssertion() {
        sleepPreventionAssertion.release()
        appStatusStore.setSleepPreventionActive(false)
    }

    func openDownloadDirectory(
        at configuredPath: String? = nil,
        fileManager: FileManager = .default
    ) {
        let path = (configuredPath ?? settingsStore.destinationPath).trimmed
        guard !path.isEmpty else {
            addSummary = "Could not open download folder"
            return
        }
        let directory = URL(
            fileURLWithPath: path,
            isDirectory: true
        ).standardizedFileURL

        switch outputCommandService.openDirectory(
            directory,
            fileManager: fileManager
        ) {
        case .opened:
            addSummary = "Download folder opened"
        case .unavailable, .cancelled, .revealed,
             .archiveOpened, .archiveFallbackOpened:
            addSummary = "Could not open download folder"
        }
    }

    func chooseDestination() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        canChooseFiles: false,
                        canChooseDirectories: true,
                        directoryURL:
                            URL(
                                fileURLWithPath:
                                    settingsStore.destinationPath
                            )
                    )
                ) else {
            return
        }
        settingsStore.destinationPath = url.path
        settingsStore.persistDestinationPath()
        refreshDiskSpaceWarning()
    }

    func scanDuplicateImages() {
        guard !duplicateImageStore.isScanning else { return }
        let roots = duplicateImageScanRootURLs()
        let similarityPercent = settingsStore.duplicateImageSimilarityPercent
        let excludeSameSource = settingsStore.duplicateImageExcludeSameSource
        duplicateImageStore.beginScan()

        let started =
            duplicateImageScanCoordinator.begin(
                roots: roots,
                similarityPercent:
                    similarityPercent,
                excludeSameSource:
                    excludeSameSource
            ) { [weak self] outcome in
                guard let self else { return }
                switch outcome {
                case .completed(let groups):
                    let selection =
                        self.duplicateImageScanService
                        .selection(
                        current: self.duplicateImageStore.selectedPath,
                        groups: groups,
                        minimumSimilarityPercent: similarityPercent
                    )
                    let summary =
                        self.duplicateImageScanService
                        .summary(
                        for: groups,
                        autoSelectedPath: selection.autoSelectedPath
                    )
                    self.duplicateImageStore.completeScan(
                        groups: groups,
                        selectedPath: selection.selectedPath,
                        autoSelectedPath: selection.autoSelectedPath,
                        summary: summary
                    )
                case .failed(let error):
                    self.duplicateImageStore.failScan(
                        summary:
                            "Duplicate scan failed: \(AppLocalization.errorText(error))"
                    )
                }
            }
        if !started {
            duplicateImageStore.setScanning(
                duplicateImageScanCoordinator
                    .hasActiveScan
            )
        }
    }

    func clearDuplicateImageResults() {
        duplicateImageStore.clearResults()
    }

    func setDuplicateImageThumbnails(_ enabled: Bool) {
        settingsStore.showDuplicateImageThumbnails = enabled
        settingsStore.persistDuplicateImageSettings()
    }

    func setLowPowerMode(_ enabled: Bool) {
        settingsStore.lowPowerMode = enabled
        settingsStore.persistDuplicateImageSettings()
        addSummary = enabled ? "Low power mode on" : "Low power mode off"
    }

    func setDuplicateImageSimilarityPercent(_ percent: Int) {
        let normalized =
            duplicateImageScanService
            .normalizedSimilarityPercent(percent)
        settingsStore.duplicateImageSimilarityPercent = normalized
        settingsStore.persistDuplicateImageSettings()
        let selection =
            duplicateImageScanService.selection(
            current: duplicateImageStore.selectedPath,
            groups: duplicateImageStore.groups,
            minimumSimilarityPercent: normalized
        )
        let summary: String?
        if duplicateImageStore.groups.isEmpty {
            summary = nil
        } else {
            summary =
                duplicateImageScanService.summary(
                for: duplicateImageStore.groups,
                autoSelectedPath: selection.autoSelectedPath
            )
        }
        duplicateImageStore.updateSelection(
            selectedPath: selection.selectedPath,
            autoSelectedPath: selection.autoSelectedPath,
            summary: summary
        )
    }

    func setDuplicateImageExcludeSameSource(_ enabled: Bool) {
        settingsStore.duplicateImageExcludeSameSource = enabled
        settingsStore.persistDuplicateImageSettings()
        addSummary = enabled ? "Same-source duplicates hidden" : "Same-source duplicates shown"
    }

    func addDuplicateImageFolder() {
        guard let urls =
            documentPanelCommandService
                .chooseOpenURLs(
                    OpenDocumentPanelRequest(
                        canChooseFiles: false,
                        canChooseDirectories: true,
                        allowsMultipleSelection: true,
                        directoryURL:
                            URL(
                                fileURLWithPath:
                                    settingsStore.destinationPath,
                                isDirectory: true
                            )
                    )
                ) else {
            return
        }
        for url in urls {
            addDuplicateImageFolderPath(url.path)
        }
    }

    func addDuplicateImageFolderPath(_ path: String) {
        settingsStore.duplicateImageFolderPaths =
            duplicateImageScanService
            .normalizedFolderPaths(
                settingsStore.duplicateImageFolderPaths +
                    [path]
            )
        settingsStore.persistDuplicateImageSettings()
        addSummary = settingsStore.duplicateImageFolderPaths.isEmpty ? "Duplicate scan uses save folder" : "Duplicate scan folder saved"
    }

    func removeDuplicateImageFolder(_ path: String) {
        guard let target =
            duplicateImageScanService
            .normalizedFolderPaths([path])
            .first else {
            return
        }
        settingsStore.duplicateImageFolderPaths = settingsStore.duplicateImageFolderPaths.filter { $0 != target }
        settingsStore.persistDuplicateImageSettings()
        addSummary = settingsStore.duplicateImageFolderPaths.isEmpty ? "Duplicate scan uses save folder" : "Duplicate scan folder removed"
    }

    func clearDuplicateImageFolders() {
        settingsStore.duplicateImageFolderPaths = []
        settingsStore.persistDuplicateImageSettings()
        addSummary = "Duplicate scan uses save folder"
    }

    private func duplicateImageScanRootURLs() -> [URL] {
        let paths = settingsStore.duplicateImageFolderPaths.isEmpty
            ? [settingsStore.destinationPath]
            : settingsStore.duplicateImageFolderPaths
        return duplicateImageScanService
            .normalizedFolderPaths(paths)
            .map {
                URL(
                    fileURLWithPath: $0,
                    isDirectory: true
                )
            }
    }

    func revealDuplicateImage(_ path: String) {
        duplicateImageStore.select(path: path)
        _ = workspaceItemCommandService.reveal(
            URL(fileURLWithPath: path)
        )
    }

    func selectDuplicateImage(_ path: String) {
        duplicateImageStore.select(path: path)
    }

    func openDuplicateImageFolder(_ path: String) {
        duplicateImageStore.select(path: path)
        guard let url =
            duplicateImageScanService
            .folderURL(forPath: path) else {
            addSummary = "Duplicate image folder not found"
            return
        }
        _ = workspaceItemCommandService.open(url)
    }

    func openSelectedDuplicateImageFolder() {
        let path = duplicateImageStore.selectedPath.trimmed
        guard !path.isEmpty else {
            addSummary = "Select a duplicate image first"
            return
        }
        openDuplicateImageFolder(path)
    }

    private func applyCookieManagementOutcome(
        _ outcome: CookieManagementOutcome
    ) {
        if outcome.operation == .clear {
            cookieStatusStore.completeClearing(
                summary: outcome.cookieSummary
            )
        } else {
            cookieStatusStore.setSummary(outcome.cookieSummary)
        }
        if let summary = outcome.addSummary {
            addSummary = summary
        }
    }

    func importCookies() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        allowedContentTypes: [
                            .plainText,
                            .text
                        ]
                    )
                ) else {
            return
        }

        cookieManagementCoordinator.begin(
            .importTextFile(url)
        ) { [weak self] in
            self?.applyCookieManagementOutcome($0)
        }
    }

    func importBrowserCookies() {
        guard let url =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        message:
                            "Choose a Firefox cookies.sqlite file or Chromium Cookies database."
                    )
                ) else {
            return
        }

        cookieManagementCoordinator.begin(
            .importBrowserDatabase(url)
        ) { [weak self] in
            self?.applyCookieManagementOutcome($0)
        }
    }

    func importDetectedBrowserCookies() {
        cookieManagementCoordinator.begin(
            .importDetectedBrowserDatabases
        ) { [weak self] in
            self?.applyCookieManagementOutcome($0)
        }
    }

    func openLoginBrowser() {
        guard let url =
            sourceAuthenticationPolicy.loginBrowserURL(
                inputText: presentation.inputText,
                jobs: queueStore.jobs,
                normalizingToken:
                    Self.normalizedInputToken
            )
        else {
            addSummary = "No login URL"
            return
        }
        openLoginBrowser(url: url, authenticationKey: nil)
    }

    nonisolated static func jobAccessReaction(for job: DownloadJob) -> JobAccessReaction? {
        SourceAuthenticationPolicy.shared
            .jobAccessReaction(
                for: job,
                normalizingToken:
                    normalizedInputToken
            )
    }

    func openAccessHelp(for job: DownloadJob) {
        let current = queueStore.jobs.first(where: { $0.id == job.id }) ?? job
        guard let reaction =
            sourceAuthenticationPolicy.jobAccessReaction(
                for: current,
                normalizingToken:
                    Self.normalizedInputToken
            )
        else {
            addSummary = "No login or cookie action for this job"
            return
        }

        switch reaction {
        case .cookies:
            presentation.settingsWindow.filter = ""
            appCommandService.openSettingsWindow(category: .network)
            addSummary = "Update cookies in Network settings"
        case .login:
            let authenticationKey =
                sourceAuthenticationPolicy
                .explicitProviderKey(for: current) ??
                sourceAuthenticationPolicy
                .inferredProviderKey(
                    for: current,
                    normalizingToken:
                        Self.normalizedInputToken
                )
            guard let url =
                sourceAuthenticationPolicy
                .loginBrowserURL(
                    for: current,
                    authenticationKey:
                        authenticationKey,
                    normalizingToken:
                        Self.normalizedInputToken
                )
            else {
                addSummary = "No login URL for this job"
                return
            }
            openLoginBrowser(url: url, authenticationKey: authenticationKey)
        }
    }

    private func openLoginBrowser(url: URL, authenticationKey: String?) {
        let request =
            authenticationBrowserCommandService
            .request(
                url: url,
                authenticationKey:
                    authenticationKey
            )
        presentLoginBrowser(request)
        addSummary = request.openedSummary
    }

    private func presentLoginBrowser(
        _ request:
            AuthenticationBrowserRequest
    ) {
#if TESTING
        if let testingLoginBrowserRequestHandler {
            testingLoginBrowserRequestHandler(
                request.url,
                request.reuseKey,
                request.autoImportPolicy
            )
            return
        }
        if let testingLoginBrowserOpenHandler {
            testingLoginBrowserOpenHandler(
                request.url
            )
            return
        }
#endif
        authenticationBrowserCommandService.open(
            request
        ) { [weak self] imported, skipped in
            guard let self else { return }
            if let provider = request.provider {
                self.applyImportedLoginCookies(
                    provider: provider,
                    imported: imported,
                    skipped: skipped
                )
                return
            }
            self.cookieStatusStore.setSummary(
                self.sourceAuthenticationPolicy.browserCookieSummary(
                    imported: imported,
                    skipped: skipped
                )
            )
            self.addSummary =
                imported > 0
                ? "Login cookies saved"
                : "No login cookies found"
        }
    }

    private func applyImportedLoginCookies(
        provider: SourceAuthenticationProvider,
        imported: Int,
        skipped: Int
    ) {
        authenticationCookieImportService.apply(
            provider: provider,
            imported: imported,
            skipped: skipped,
            setCookieSummary: {
                [weak self] in
                self?.cookieStatusStore.setSummary($0)
            },
            setSummary: {
                [weak self] in
                self?.addSummary = $0
            }
        )
    }

#if TESTING
    func testingOpenLoginBrowser(
        url: URL,
        authenticationKey: String?
    ) {
        openLoginBrowser(
            url: url,
            authenticationKey:
                authenticationKey
        )
    }

    func testingNotifyLoginCookiesImported(
        provider: SourceAuthenticationProvider,
        imported: Int,
        skipped: Int = 0
    ) {
        applyImportedLoginCookies(
            provider: provider,
            imported: imported,
            skipped: skipped
        )
    }
#endif

    private func presentLoginBrowser(
        provider:
            SourceAuthenticationProvider,
        loginURL: URL? = nil
    ) {
        presentLoginBrowser(
            authenticationBrowserCommandService
                .request(
                    provider: provider,
                    loginURL: loginURL
                )
        )
    }

    private func waitForTwitterLogin(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await authenticationJobWaitService.wait(
            jobID: queueStore.jobs[index].id,
            provider: "twitter",
            waitingMessage:
                "Waiting for Twitter/X login",
            requiredSummary:
                "Twitter/X login required",
            resumedMessage:
                "Reading Twitter/X media",
            persist: {
                self.persistQueue()
            },
            setSummary: {
                self.addSummary = $0
            }
        ) {
            self.presentLoginBrowser(
                provider: .twitter
            )
        }
    }

#if TESTING
    func testingNotifyTwitterLoginCookiesImported(imported: Int, skipped: Int = 0) {
        applyImportedLoginCookies(
            provider: .twitter,
            imported: imported,
            skipped: skipped
        )
    }

    func testingResumeTwitterLoginWaits() {
        authenticationWaitCoordinator
            .resumeAll(for: "twitter")
    }
#endif

    private func waitForPornhubLogin(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await authenticationJobWaitService.wait(
            jobID: queueStore.jobs[index].id,
            provider: "pornhub-premium",
            waitingMessage:
                "Waiting for Pornhub Premium login",
            requiredSummary:
                "Pornhub Premium login required",
            resumedMessage:
                "Reading Pornhub media",
            persist: {
                self.persistQueue()
            },
            setSummary: {
                self.addSummary = $0
            }
        ) {
            self.presentLoginBrowser(
                provider:
                    .pornhubPremium
            )
        }
    }

#if TESTING
    func testingResumePornhubLoginWaits() {
        authenticationWaitCoordinator
            .resumeAll(
                for: "pornhub-premium"
            )
    }
#endif

    private func waitForPixivLogin(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await authenticationJobWaitService.wait(
            jobID: queueStore.jobs[index].id,
            provider: "pixiv",
            waitingMessage:
                "Waiting for Pixiv login",
            requiredSummary:
                "Pixiv login required",
            resumedMessage:
                "Reading Pixiv artwork",
            persist: {
                self.persistQueue()
            },
            setSummary: {
                self.addSummary = $0
            }
        ) {
            self.presentLoginBrowser(
                provider: .pixiv
            )
        }
    }

#if TESTING
    func testingWaitForPixivLogin(
        at index: Int
    ) async {
        await waitForPixivLogin(at: index)
    }

    func testingResumePixivLoginWaits() {
        authenticationWaitCoordinator
            .resumeAll(for: "pixiv")
    }
#endif

    private func waitForChzzkLogin(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await authenticationJobWaitService.wait(
            jobID: queueStore.jobs[index].id,
            provider: "chzzk",
            waitingMessage:
                "Waiting for Chzzk login",
            requiredSummary:
                "Chzzk login required",
            resumedMessage:
                "Reading Chzzk media",
            persist: {
                self.persistQueue()
            },
            setSummary: {
                self.addSummary = $0
            }
        ) {
            self.presentLoginBrowser(
                provider: .chzzk
            )
        }
    }

#if TESTING
    func testingResumeChzzkLoginWaits() {
        authenticationWaitCoordinator
            .resumeAll(for: "chzzk")
    }
#endif

    private func waitForNaverCafeLogin(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await authenticationJobWaitService.wait(
            jobID: queueStore.jobs[index].id,
            provider: "naver-cafe",
            waitingMessage:
                "Waiting for Naver Cafe login",
            requiredSummary:
                "Naver Cafe login required",
            resumedMessage:
                "Reading Naver Cafe",
            persist: {
                self.persistQueue()
            },
            setSummary: {
                self.addSummary = $0
            }
        ) {
            self.presentLoginBrowser(
                provider: .naverCafe
            )
        }
    }

#if TESTING
    func testingResumeNaverCafeLoginWaits() {
        authenticationWaitCoordinator
            .resumeAll(for: "naver-cafe")
    }
#endif

    private func waitForArcaliveLogin(at index: Int, loginURL: URL) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await authenticationJobWaitService.wait(
            jobID: queueStore.jobs[index].id,
            provider: "arcalive",
            waitingMessage:
                "Waiting for Arcalive login",
            requiredSummary:
                "Arcalive login required",
            resumedMessage:
                "Reading Arcalive article",
            persist: {
                self.persistQueue()
            },
            setSummary: {
                self.addSummary = $0
            }
        ) {
            self.presentLoginBrowser(
                provider: .arcalive,
                loginURL: loginURL
            )
        }
    }

#if TESTING
    func testingWaitForArcaliveLogin(
        at index: Int,
        loginURL: URL
    ) async {
        await waitForArcaliveLogin(
            at: index,
            loginURL: loginURL
        )
    }

    func testingResumeArcaliveLoginWaits() {
        authenticationWaitCoordinator
            .resumeAll(for: "arcalive")
    }
#endif

    func clearCookies() {
        guard !cookieStatusStore.isClearing else { return }
        cookieStatusStore.beginClearing(
            summary: "Deleting cookies and login sessions..."
        )
        addSummary = "Deleting cookies and login sessions..."

        cookieManagementCoordinator.begin(.clear) {
            [weak self] in
            self?.applyCookieManagementOutcome($0)
        }
    }

    nonisolated static func loginBrowserURL(inputText: String, jobs inputJobs: [DownloadJob]) -> URL? {
        SourceAuthenticationPolicy.shared
            .loginBrowserURL(
                inputText: inputText,
                jobs: inputJobs,
                normalizingToken:
                    normalizedInputToken
            )
    }

    nonisolated static let pixivLoginURL =
        SourceAuthenticationPolicy.pixivLoginURL
    private nonisolated static let pixivCookieURL =
        SourceAuthenticationPolicy.pixivCookieURL
    nonisolated static let chzzkLoginURL =
        SourceAuthenticationPolicy.chzzkLoginURL
    private nonisolated static let chzzkCookieURL =
        SourceAuthenticationPolicy.chzzkCookieURL
    nonisolated static let naverCafeLoginURL =
        SourceAuthenticationPolicy.naverCafeLoginURL
    private nonisolated static let naverCafeCookieURL =
        SourceAuthenticationPolicy.naverCafeCookieURL
    nonisolated static let twitterLoginURL =
        SourceAuthenticationPolicy.twitterLoginURL
    private nonisolated static let twitterCookieURL =
        SourceAuthenticationPolicy.twitterCookieURL
    nonisolated static let pornhubPremiumLoginURL =
        SourceAuthenticationPolicy
        .pornhubPremiumLoginURL
    nonisolated static let arcaliveLoginURL =
        SourceAuthenticationPolicy.arcaliveLoginURL
    private nonisolated static let arcaliveCookieURL =
        SourceAuthenticationPolicy.arcaliveCookieURL

    private func refreshCookieSummary() async {
        let count = await CookieStore.shared.count
        await MainActor.run {
            self.cookieStatusStore.setSummary(
                self.sourceAuthenticationPolicy.storedCookieSummary(
                    count: count
                )
            )
        }
    }

    func revealOutput(for job: DownloadJob) {
        outputJobCommandCoordinator.reveal(
            resolveURLs: { [weak self] in
                guard let self else { return [] }
                let outputPath =
                    await self.repairedOutputPath(
                        for: job
                    )
                guard !Task.isCancelled,
                      let output =
                          QueueThumbnailProvider
                          .existingOutputURL(
                              forOutputPath:
                                  outputPath,
                              destinationPath:
                                  self.settingsStore.destinationPath,
                              searchRelocatedOutputs:
                                  false
                          ),
                      let url =
                          self.outputOpenService
                          .revealURL(
                              forOutputPath:
                                  output.path
                          ) else {
                    return []
                }
                return [url]
            },
            completion: { _ in }
        )
    }

    private func outputRevealURLs(startingAt job: DownloadJob) async -> [URL] {
        var seenPaths = Set<String>()
        var urls: [URL] = []
        for selected in contextualJobs(startingAt: job) {
            guard !Task.isCancelled else { break }
            let outputPath = await repairedOutputPath(for: selected)
            guard let existing = QueueThumbnailProvider.existingOutputURL(
                forOutputPath: outputPath,
                destinationPath: settingsStore.destinationPath,
                searchRelocatedOutputs: false
            ),
            let url = outputOpenService.revealURL(
                forOutputPath: existing.path
            ) else {
                continue
            }
            let key = url.resolvingSymlinksInPath().standardizedFileURL.path
            guard seenPaths.insert(key).inserted else { continue }
            urls.append(url)
        }
        return urls
    }

    func revealOutputs(startingAt job: DownloadJob) {
        outputJobCommandCoordinator.reveal(
            resolveURLs: { [weak self] in
                guard let self else { return [] }
                return await self.outputRevealURLs(
                    startingAt: job
                )
            },
            completion: { [weak self] result in
                guard let self else { return }
                guard case .revealed(let count) = result
                else {
                    self.addSummary =
                        "No output folder found"
                    return
                }
                self.addSummary = count == 1
                    ? "Output revealed"
                    : "Outputs revealed for \(count) jobs"
            }
        )
    }

    func canRevealOutputs(startingAt job: DownloadJob) -> Bool {
        contextualJobs(startingAt: job).contains { selected in
            queueJobActionPolicy.canRevealOutput(
                for: selected,
                destinationPath: settingsStore.destinationPath
            )
        }
    }

    func openFirstOutputFile(for job: DownloadJob) {
        outputJobCommandCoordinator.openFirst(
            resolveRequest: { [weak self] in
                guard let self else { return nil }
                let outputPath =
                    await self.repairedOutputPath(
                        for: job
                    )
                guard !Task.isCancelled else {
                    return nil
                }
                return self.outputOpenService
                    .openRequest(
                        for: job,
                        outputPath: outputPath
                    )
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .opened:
                    self.addSummary =
                        "Output file opened"
                case .unavailable:
                    self.addSummary =
                        "No output file found"
                default:
                    break
                }
            }
        )
    }

    func openArchiveOutput(for job: DownloadJob) {
        switch outputCommandService.openArchive(for: job) {
        case .archiveOpened(let format):
            addSummary = "\(format.label) archive opened"
        case .archiveFallbackOpened:
            addSummary = "Archive missing; downloaded file opened"
        default:
            addSummary = "No archive or downloaded file found"
        }
    }

    nonisolated static func firstRetainedArchiveOutputURL(
        for job: DownloadJob,
        fileManager: FileManager = .default
    ) -> URL? {
        OutputOpenService(
            fileManager: fileManager
        ).firstRetainedArchiveOutputURL(for: job)
    }

    nonisolated static func preferredFirstOutputOpenURL(
        for job: DownloadJob,
        fileManager: FileManager = .default
    ) -> URL? {
        let service = OutputOpenService(
            fileManager: fileManager
        )
        return service.preferredFirstOutputOpenURL(
            for: service.openRequest(for: job)
        )
    }

    func openFirstOutputFiles(startingAt job: DownloadJob) {
        let selectedJobs = contextualJobs(startingAt: job)
        guard !selectedJobs.isEmpty else {
            addSummary = "No output file found"
            return
        }
        outputJobCommandCoordinator.openFirstBatch(
            resolveRequests: { [weak self] in
                guard let self else { return [] }
                var requests:
                    [FirstOutputOpenRequest] = []
                for selected in selectedJobs {
                    guard !Task.isCancelled else {
                        return []
                    }
                    let outputPath =
                        await self.repairedOutputPath(
                            for: selected
                        )
                    requests.append(
                        self.outputOpenService
                        .openRequest(
                            for: selected,
                            outputPath: outputPath
                        )
                    )
                }
                return requests
            },
            confirmLargeBatch: { [weak self] count in
                guard let self else { return false }
                return self.confirmationDialogService
                    .confirm(
                        ConfirmationDialogRequest(
                            style: .warning,
                            message:
                                AppLocalization.format(
                                    "Open the first file for %@ tasks.",
                                    language:
                                        self.settingsStore.interfaceLanguage,
                                    String(count)
                                ),
                            informativeText:
                                AppLocalization.text(
                                    "Continue?",
                                    language:
                                        self.settingsStore.interfaceLanguage
                                ),
                            confirmButtonTitle:
                                AppLocalization.text(
                                    "Open",
                                    language:
                                        self.settingsStore.interfaceLanguage
                                ),
                            cancelButtonTitle:
                                AppLocalization.text(
                                    "Cancel",
                                    language:
                                        self.settingsStore.interfaceLanguage
                                )
                        )
                    )
            },
            completion: { [weak self] result in
                guard let self else { return }
                switch result {
                case .opened(let count):
                    self.addSummary = count == 1
                        ? "Output file opened"
                        : "First output file opened for \(count) jobs"
                case .unavailable:
                    self.addSummary =
                        "No output file found"
                default:
                    break
                }
            }
        )
    }

    func canOpenFirstOutputFile(for job: DownloadJob) -> Bool {
        queueJobActionPolicy.canOpenOutput(
            for: job,
            destinationPath: settingsStore.destinationPath
        )
    }

    func canOpenFirstOutputFiles(startingAt job: DownloadJob) -> Bool {
        contextualJobs(startingAt: job).contains { canOpenFirstOutputFile(for: $0) }
    }

    func contextualJobs(startingAt job: DownloadJob) -> [DownloadJob] {
        queueJobActionPolicy.contextualJobs(
            in: queueStore.jobs,
            selectedJobIDs: presentation.selectedJobIDs,
            startingAt: job
        )
    }

    private func repairedOutputPath(for job: DownloadJob) async -> String {
        let originalOutputPath = job.outputPath
        let currentDestinationPath = settingsStore.destinationPath
        let outputPath =
            await outputPathRepairService
            .existingOutputPath(
                for: originalOutputPath,
                destinationPath:
                    currentDestinationPath
            )
        guard !Task.isCancelled,
              let outputPath else {
            return job.outputPath
        }
        guard outputPath != job.outputPath,
              let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            return outputPath
        }
        queueStore.updateJob(at: index) {
            $0.outputPath = outputPath
        }
        persistQueue()
        return outputPath
    }

    func createPDF(for job: DownloadJob) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        do {
            let pdfURL = try pdfOutputService.createPDF(
                fromOutputPath: queueStore.jobs[index].outputPath,
                title: queueStore.jobs[index].title
            )
            queueStore.replaceJob(
                at: index,
                with: pdfJobStateService
                    .recordingCreatedPDF(
                        queueStore.jobs[index],
                        pdfURL: pdfURL,
                        createdAt:
                            ISO8601DateFormatter()
                            .string(from: Date())
                    )
            )
            persistQueue()
            addSummary = "PDF created: \(pdfURL.lastPathComponent)"
        } catch {
            addSummary = "PDF failed: \(AppLocalization.errorText(error))"
        }
    }

    func canCreatePDF(for job: DownloadJob) -> Bool {
        guard let output = QueueThumbnailProvider.existingOutputURL(
            forOutputPath: job.outputPath,
            destinationPath: settingsStore.destinationPath,
            searchRelocatedOutputs: false
        ) else {
            return false
        }
        var isDirectory = ObjCBool(false)
        guard FileManager.default.fileExists(atPath: output.path, isDirectory: &isDirectory) else {
            return false
        }
        if !isDirectory.boolValue {
            return Self.isPDFImageFile(output) || Self.isArchiveOutputFile(output)
        }
        return job.resolvedFilenames.isEmpty || job.resolvedFilenames.contains {
            Self.imageExtensions.contains(($0 as NSString).pathExtension.lowercased())
        }
    }

    func openOutputBrowserView(for job: DownloadJob) {
        guard canOpenOutputBrowserView(for: job) else {
            addSummary = "No browser-viewable output"
            return
        }
        guard ensureHTTPAPIAvailableForBrowserView(),
              let url = Self.browserViewURL(
                baseURLString: httpAPIBaseURLString(),
                jobID: job.id,
                password: settingsStore.httpAPIPassword
              ) else {
            addSummary = "Browser view unavailable"
            return
        }

        _ = sourceLinkCommandService.openBrowserURL(
            url,
            skipExternalOpen: false
        )
        addSummary = "Browser view opened"
    }

    func openOutputBrowserView(startingAt job: DownloadJob) {
        openOutputBrowserView(for: contextualJobs(startingAt: job))
    }

    func openOutputBrowserView(for selectedJobs: [DownloadJob]) {
        let selectedIDs = Set(selectedJobs.map(\.id))
        let viewableJobs = queueStore.jobs.filter { selectedIDs.contains($0.id) && canOpenOutputBrowserView(for: $0) }
        guard !viewableJobs.isEmpty else {
            addSummary = "No browser-viewable output"
            return
        }
        guard ensureHTTPAPIAvailableForBrowserView(),
              let url = Self.browserViewURL(
                baseURLString: httpAPIBaseURLString(),
                jobIDs: viewableJobs.map(\.id),
                password: settingsStore.httpAPIPassword
              ) else {
            addSummary = "Browser view unavailable"
            return
        }

        _ = sourceLinkCommandService.openBrowserURL(
            url,
            skipExternalOpen: false
        )
        addSummary = viewableJobs.count == 1 ? "Browser view opened" : "Browser view opened for \(viewableJobs.count) jobs"
    }

    func canOpenOutputBrowserView(for job: DownloadJob) -> Bool {
        queueJobActionPolicy.canOpenOutput(
            for: job,
            destinationPath: settingsStore.destinationPath
        )
    }

    func canOpenOutputBrowserView(for selectedJobs: [DownloadJob]) -> Bool {
        selectedJobs.contains { canOpenOutputBrowserView(for: $0) }
    }

    func canOpenOutputBrowserView(startingAt job: DownloadJob) -> Bool {
        canOpenOutputBrowserView(for: contextualJobs(startingAt: job))
    }

    private func resolvedOutputPath(
        for job: DownloadJob,
        searchRelocatedOutputs: Bool = true
    ) -> String {
        QueueThumbnailProvider.existingOutputURL(
            forOutputPath: job.outputPath,
            destinationPath: settingsStore.destinationPath,
            searchRelocatedOutputs: searchRelocatedOutputs
        )?.path ?? job.outputPath
    }

    private func resolvedOutputDeletionCandidates(
        for job: DownloadJob,
        searchRelocatedOutputs: Bool = true
    ) -> [OutputDeletionCandidate] {
        var resolvedJob = job
        resolvedJob.outputPath = resolvedOutputPath(
            for: job,
            searchRelocatedOutputs: searchRelocatedOutputs
        )
        return outputService.outputDeletionCandidates(for: resolvedJob)
    }

    func canDeleteOutput(for job: DownloadJob) -> Bool {
        queueJobActionPolicy.canDeleteOutput(
            for: job,
            destinationPath: settingsStore.destinationPath
        )
    }

    func canDeleteOutputsAndJobs(startingAt job: DownloadJob) -> Bool {
        return contextualJobs(startingAt: job).contains { selected in
            queueJobActionPolicy.canDeleteOutputAndJob(selected)
        }
    }

    func canMoveOutput(for job: DownloadJob) -> Bool {
        queueJobActionPolicy.canMoveOutput(
            for: job,
            destinationPath: settingsStore.destinationPath,
            imageConversionJobIDs:
                outputOperationStore.imageConversionJobIDs
        )
    }

    func canMoveOutputs(for selectedJobs: [DownloadJob]) -> Bool {
        selectedJobs.contains { canMoveOutput(for: $0) }
    }

    func canMoveOutputs(startingAt job: DownloadJob) -> Bool {
        canMoveOutputs(for: contextualJobs(startingAt: job))
    }

    func beginMovingOutputs(startingAt job: DownloadJob) {
        beginMovingOutputs(for: contextualJobs(startingAt: job))
    }

    func beginMovingOutput(for job: DownloadJob) {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return }
        guard !isActive(current.status) else {
            addSummary = "Cancel active jobs before moving output"
            return
        }
        guard !current.isLocked else {
            addSummary = "Unlock job before moving output"
            return
        }
        guard !outputOperationStore.imageConversionJobIDs.contains(current.id) else {
            addSummary = "Wait for image conversion before moving output"
            return
        }
        guard !resolvedOutputDeletionCandidates(for: current).isEmpty else {
            addSummary = "No output files found"
            return
        }

        guard let destination =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        title: "Move Output",
                        message:
                            "Choose a destination folder for this output.",
                        prompt: "Move",
                        canChooseFiles: false,
                        canChooseDirectories: true,
                        canCreateDirectories: true,
                        directoryURL:
                            URL(
                                fileURLWithPath:
                                    settingsStore.destinationPath,
                                isDirectory: true
                            )
                    )
                ) else {
            return
        }
        moveOutputs(for: [current], to: destination)
    }

    func beginMovingOutputs(for selectedJobs: [DownloadJob]) {
        let selectedIDs = Set(selectedJobs.map(\.id))
        let current = queueStore.jobs.filter { selectedIDs.contains($0.id) }
        guard !current.isEmpty else { return }
        guard canMoveOutputs(for: current) else {
            if current.contains(where: { isActive($0.status) }) {
                addSummary = "Cancel active jobs before moving output"
            } else if current.contains(where: \.isLocked) {
                addSummary = "Unlock job before moving output"
            } else if current.contains(where: {
                outputOperationStore.imageConversionJobIDs.contains($0.id)
            }) {
                addSummary = "Wait for image conversion before moving output"
            } else {
                addSummary = "No movable output found"
            }
            return
        }

        guard let destination =
            documentPanelCommandService
                .chooseOpenURL(
                    OpenDocumentPanelRequest(
                        title:
                            "Move Selected Outputs",
                        message:
                            "Choose a destination folder for selected outputs.",
                        prompt: "Move",
                        canChooseFiles: false,
                        canChooseDirectories: true,
                        canCreateDirectories: true,
                        directoryURL:
                            URL(
                                fileURLWithPath:
                                    settingsStore.destinationPath,
                                isDirectory: true
                            )
                    )
                ) else {
            return
        }
        moveOutputs(for: current, to: destination)
    }

    func moveOutputs(for selectedJobs: [DownloadJob], to destinationDirectory: URL) {
        let selectedIDs = Set(selectedJobs.map(\.id))
        guard !selectedIDs.isEmpty else { return }

        let indexes = queueStore.jobs.indices.filter { selectedIDs.contains(queueStore.jobs[$0].id) }
        guard !indexes.isEmpty else { return }

        var movedJobCount = 0
        var movedItemCount = 0
        var skippedCount = 0
        var failedJobCount = 0
        var blockedMessage: String?
        var firstFailureDescription: String?
        var didChange = false
        let movedAt = ISO8601DateFormatter().string(from: Date())

        for index in indexes {
            guard queueStore.jobs.indices.contains(index) else { continue }

            if isActive(queueStore.jobs[index].status) {
                blockedMessage = blockedMessage ?? "Cancel active jobs before moving output"
                skippedCount += 1
                continue
            }
            if queueStore.jobs[index].isLocked {
                blockedMessage = blockedMessage ?? "Unlock job before moving output"
                skippedCount += 1
                continue
            }
            if outputOperationStore.imageConversionJobIDs.contains(
                queueStore.jobs[index].id
            ) {
                blockedMessage = blockedMessage ?? "Wait for image conversion before moving output"
                skippedCount += 1
                continue
            }

            let resolvedPath = resolvedOutputPath(for: queueStore.jobs[index])
            var resolvedJob = queueStore.jobs[index]
            resolvedJob.outputPath = resolvedPath
            let candidates = outputService.outputDeletionCandidates(for: resolvedJob)
            guard !candidates.isEmpty else {
                skippedCount += 1
                continue
            }

            do {
                let result = try outputService.moveOutputCandidates(
                    candidates,
                    originalOutputPath: resolvedPath,
                    to: destinationDirectory
                )
                guard !result.items.isEmpty else {
                    skippedCount += 1
                    continue
                }

                queueStore.updateJob(at: index) {
                    if let primaryOutputPath = result.primaryOutputPath {
                        $0.outputPath = primaryOutputPath
                    }
                    $0.metadata["output_moved_at"] = movedAt
                    $0.metadata["output_moved_to"] = destinationDirectory.path
                    $0.metadata.removeValue(forKey: "output_move_error")
                    $0.message = "\(result.items.count) output item(s) moved"
                }
                movedJobCount += 1
                movedItemCount += result.items.count
                didChange = true
            } catch {
                failedJobCount += 1
                firstFailureDescription = firstFailureDescription ?? AppLocalization.errorText(error)
                queueStore.updateJob(at: index) {
                    $0.metadata["output_move_error"] = AppLocalization.errorText(error)
                    $0.message = "Output move failed: \(AppLocalization.errorText(error))"
                }
                didChange = true
            }
        }

        if didChange {
            persistQueue()
        }
        if failedJobCount > 0, movedJobCount > 0 {
            addSummary = "\(movedItemCount) output item(s) moved for \(movedJobCount) job(s); \(failedJobCount) failed"
        } else if failedJobCount > 0 {
            addSummary = "Output move failed: \(firstFailureDescription ?? "Unknown error")"
        } else if movedJobCount > 0 {
            addSummary = "\(movedItemCount) output item(s) moved for \(movedJobCount) job(s)"
        } else if let blockedMessage {
            addSummary = blockedMessage
        } else if skippedCount > 0 {
            addSummary = "Output already in selected folder"
        } else {
            addSummary = "No movable output found"
        }
    }

    func beginDeletingOutput(for job: DownloadJob, removeJobAfterDeletion: Bool = false) {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }) else { return }
        guard !isActive(current.status) else {
            addSummary = "Cancel active jobs before deleting output"
            return
        }
        guard !current.isLocked else {
            addSummary = "Unlock job before deleting output"
            return
        }

        let candidates = resolvedOutputDeletionCandidates(for: current)
        guard !candidates.isEmpty else {
            addSummary = "No output files found"
            return
        }

        queueEditorStore.beginOutputDeletion(
            job: current,
            jobIDs: [current.id],
            candidates: candidates,
            removeJobsAfterDeletion: removeJobAfterDeletion
        )
        presentation.showingOutputDeletionConfirmation = true
    }

    func beginDeletingOutputs(
        startingAt job: DownloadJob,
        removeJobsAfterDeletion: Bool = true
    ) {
        guard removeJobsAfterDeletion else {
            beginDeletingOutput(for: job)
            return
        }
        let selected = contextualJobs(startingAt: job)
        let removable = selected.filter {
            !$0.isLocked &&
                !Self.isPendingQueueRemoval($0)
        }
        guard !removable.isEmpty else {
            if selected.contains(where: \.isLocked) {
                addSummary = "Unlock jobs before deleting output"
            } else {
                addSummary = "No removable jobs selected"
            }
            return
        }

        var seenPaths = Set<String>()
        var candidates: [OutputDeletionCandidate] = []
        for candidate in removable.flatMap({ resolvedOutputDeletionCandidates(for: $0) }) {
            let key = URL(fileURLWithPath: candidate.path)
                .resolvingSymlinksInPath()
                .standardizedFileURL
                .path
            guard seenPaths.insert(key).inserted else { continue }
            candidates.append(candidate)
        }

        queueEditorStore.beginOutputDeletion(
            job: removable.first,
            jobIDs: removable.map(\.id),
            candidates: candidates,
            removeJobsAfterDeletion: true
        )
        presentation.showingOutputDeletionConfirmation = true
    }

    func cancelDeletingOutput() {
        queueEditorStore.resetOutputDeletion()
        presentation.showingOutputDeletionConfirmation = false
    }

    func trashOutputCandidates(_ candidateIDs: Set<String>) {
#if TESTING
        testingTrashedResultURLs = []
#endif
        if queueEditorStore.removeJobAfterOutputDeletion {
            trashOutputsAndRemovePendingJobs()
            cancelDeletingOutput()
            return
        }

        guard let job = queueEditorStore.outputDeletionJob,
              let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            cancelDeletingOutput()
            return
        }
        guard !isActive(queueStore.jobs[index].status) else {
            addSummary = "Cancel active jobs before deleting output"
            cancelDeletingOutput()
            return
        }
        guard !queueStore.jobs[index].isLocked else {
            addSummary = "Unlock job before deleting output"
            cancelDeletingOutput()
            return
        }

        let selected = queueEditorStore.outputDeletionCandidates.filter {
            candidateIDs.contains($0.id)
        }
        guard !selected.isEmpty else {
            cancelDeletingOutput()
            return
        }
        let pendingIDs = Set(
            queueEditorStore.outputDeletionJobIDs.isEmpty
                ? [job.id]
                : queueEditorStore.outputDeletionJobIDs
        )
        guard !selected.contains(where: {
            isOutputDeletionCandidateShared($0, excludingJobIDs: pendingIDs)
        }) else {
            addSummary = "Downloaded output is shared with another queue job. Job kept."
            cancelDeletingOutput()
            return
        }

        do {
            let result = try trashOutputDeletionCandidates(selected)
            if queueStore.jobs.indices.contains(index) {
                if !result.resolvedPaths.isEmpty {
                    updateOutputPathAfterDeletingCandidates(at: index, trashedPaths: result.resolvedPaths)
                    queueStore.updateJob(at: index) {
                        $0.metadata["output_deleted_at"] = ISO8601DateFormatter().string(from: Date())
                    }
                }

                if result.failures.isEmpty {
                    if result.trashedItemCount > 0 {
                        queueStore.updateJob(at: index) {
                            $0.message = "\(result.trashedItemCount) output item(s) moved to Trash"
                        }
                        addSummary = "\(result.trashedItemCount) output item(s) moved to Trash"
                    } else {
                        queueStore.updateJob(at: index) {
                            $0.message = "Downloaded output was already missing"
                        }
                        addSummary = "Downloaded output was already missing"
                    }
                } else {
                    let failedCount = result.failures.count
                    queueStore.updateJob(at: index) {
                        $0.metadata["output_delete_partial_at"] = ISO8601DateFormatter().string(from: Date())
                        $0.metadata["output_delete_failed_count"] = String(failedCount)
                        $0.message = "\(result.trashedItemCount) output item(s) moved; \(failedCount) failed"
                    }
                    addSummary = "\(result.trashedItemCount) output item(s) moved to Trash; \(failedCount) failed"
                }
                persistQueue()
            }
        } catch {
            addSummary = "Output delete failed: \(AppLocalization.errorText(error))"
        }
        cancelDeletingOutput()
    }

    private func trashOutputsAndRemovePendingJobs() {
        let pendingIDs = queueEditorStore.outputDeletionJobIDs.isEmpty
            ? queueEditorStore.outputDeletionJob.map { [$0.id] } ?? []
            : queueEditorStore.outputDeletionJobIDs
        guard !pendingIDs.isEmpty else { return }

        let result = trashOutputsAndRemoveJobs(withIDs: pendingIDs)
        updateOutputRemovalSummary(result, requestedCount: pendingIDs.count)
    }

    private func trashOutputsAndRemoveJobs(withIDs pendingIDs: [UUID]) -> JobOutputRemovalResult {
        var result = JobOutputRemovalResult()
        var didChange = false
        var removableJobIDs = Set<UUID>()
        let deletedAt = ISO8601DateFormatter().string(from: Date())
        let pendingIDSet = Set(pendingIDs)
        let shouldDeferSelectedOutputDeletion = pendingIDs.contains { jobID in
            guard let job = queueStore.jobs.first(where: { $0.id == jobID }) else { return false }
            return isActive(job.status) ||
                downloadCoordinator.isActive(jobID)
        }

        for jobID in pendingIDs {
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }) else { continue }
            if queueStore.jobs[index].isLocked {
                result.keptJobCount += 1
                continue
            }
            if shouldDeferSelectedOutputDeletion {
                queueStore.updateJob(at: index) {
                    $0.metadata[Self.pendingQueueOutputDeletionMetadataKey] = "true"
                }
                removableJobIDs.insert(queueStore.jobs[index].id)
                result.deferredOutputDeletionCount += 1
                didChange = true
                continue
            }

            let candidates = resolvedOutputDeletionCandidates(for: queueStore.jobs[index])
            guard !candidates.isEmpty else {
                removableJobIDs.insert(queueStore.jobs[index].id)
                didChange = true
                continue
            }
            if candidates.contains(where: {
                isOutputDeletionCandidateShared($0, excludingJobIDs: pendingIDSet)
            }) {
                result.failedItemCount += 1
                result.keptJobCount += 1
                queueStore.updateJob(at: index) {
                    $0.metadata["output_delete_partial_at"] = deletedAt
                    $0.metadata["output_delete_failed_count"] = "1"
                    $0.message = "Output is shared with another queue job"
                }
                didChange = true
                continue
            }

            do {
                let trashResult = try trashOutputDeletionCandidates(candidates)
                result.trashedItemCount += trashResult.trashedItemCount
                if trashResult.failures.isEmpty {
                    removableJobIDs.insert(queueStore.jobs[index].id)
                    didChange = true
                    continue
                }

                if !trashResult.resolvedPaths.isEmpty {
                    updateOutputPathAfterDeletingCandidates(at: index, trashedPaths: trashResult.resolvedPaths)
                }
                let failures = trashResult.failures.count
                result.failedItemCount += failures
                result.keptJobCount += 1
                queueStore.updateJob(at: index) {
                    if !trashResult.resolvedPaths.isEmpty {
                        $0.metadata["output_deleted_at"] = deletedAt
                    }
                    $0.metadata["output_delete_partial_at"] = deletedAt
                    $0.metadata["output_delete_failed_count"] = String(failures)
                    $0.message = "\(trashResult.trashedItemCount) output item(s) moved; \(failures) failed"
                }
                didChange = true
            } catch {
                result.failedItemCount += 1
                result.keptJobCount += 1
                queueStore.updateJob(at: index) {
                    $0.metadata["output_delete_partial_at"] = deletedAt
                    $0.metadata["output_delete_failed_count"] = "1"
                    $0.message = "Output delete failed: \(AppLocalization.errorText(error))"
                }
                didChange = true
            }
        }

        if !removableJobIDs.isEmpty {
            let removable = queueStore.jobs.filter { removableJobIDs.contains($0.id) }
            result.removedJobCount = removeJobsFromQueue(removable)
        } else if didChange {
            persistQueue()
        }
        return result
    }

    private func updateOutputRemovalSummary(_ result: JobOutputRemovalResult, requestedCount: Int) {
        if result.failedItemCount > 0 {
            if requestedCount == 1 {
                addSummary = "\(result.trashedItemCount) output item(s) moved to Trash; \(result.failedItemCount) failed. Job kept."
            } else {
                addSummary = "\(result.removedJobCount) job(s) removed, \(result.trashedItemCount) output item(s) moved to Trash; \(result.failedItemCount) failed and \(result.keptJobCount) job(s) kept"
            }
        } else if result.removedJobCount == 1 {
            addSummary = result.trashedItemCount > 0
                ? "Job removed and \(result.trashedItemCount) output item(s) moved to Trash"
                : "Job removed; downloaded output was already missing"
        } else if result.removedJobCount > 1 {
            addSummary = "\(result.removedJobCount) jobs removed and \(result.trashedItemCount) output item(s) moved to Trash"
        } else if result.keptJobCount > 0 {
            addSummary = "Cancel active jobs or unlock them before deleting output"
        }
    }

    private func isOutputDeletionCandidateShared(
        _ candidate: OutputDeletionCandidate,
        excludingJobIDs: Set<UUID>
    ) -> Bool {
        let candidatePath = URL(fileURLWithPath: candidate.path)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
        let candidatePrefix = candidatePath.hasSuffix("/") ? candidatePath : candidatePath + "/"

        return queueStore.jobs.contains { job in
            guard !excludingJobIDs.contains(job.id),
                  let output = QueueThumbnailProvider.existingOutputURL(
                    forOutputPath: job.outputPath,
                    destinationPath: settingsStore.destinationPath
                  ) else {
                return false
            }
            let outputPath = output.resolvingSymlinksInPath().standardizedFileURL.path
            let outputPrefix = outputPath.hasSuffix("/") ? outputPath : outputPath + "/"
            return outputPath == candidatePath ||
                outputPath.hasPrefix(candidatePrefix) ||
                candidatePath.hasPrefix(outputPrefix)
        }
    }

    nonisolated static func revealURL(forOutputPath path: String, fileManager: FileManager = .default) -> URL? {
        OutputOpenService(
            fileManager: fileManager
        ).revealURL(forOutputPath: path)
    }

    nonisolated static func firstOutputOpenURL(
        forOutputPath path: String,
        fileManager: FileManager = .default
    ) -> URL? {
        OutputOpenService(
            fileManager: fileManager
        ).firstOutputOpenURL(forOutputPath: path)
    }

    @discardableResult
    nonisolated static func createPDF(
        fromOutputPath path: String,
        title: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        try PDFOutputService(
            fileManager: fileManager
        ).createPDF(
            fromOutputPath: path,
            title: title
        )
    }

    nonisolated static func pdfImageFiles(fromOutputPath path: String, fileManager: FileManager = .default) -> [URL] {
        PDFOutputService(
            fileManager: fileManager
        ).imageFiles(
            fromOutputPath: path
        )
    }

    private nonisolated static func isPDFImageFile(_ url: URL) -> Bool {
        pdfImageExtensions.contains(url.pathExtension.lowercased())
    }

    nonisolated static func outputDeletionCandidates(
        for job: DownloadJob,
        fileManager: FileManager = .default
    ) -> [OutputDeletionCandidate] {
        OutputService(fileManager: fileManager).outputDeletionCandidates(for: job)
    }

    nonisolated static func moveOutputCandidates(
        _ candidates: [OutputDeletionCandidate],
        originalOutputPath: String,
        to destinationDirectory: URL,
        fileManager: FileManager = .default
    ) throws -> OutputMoveResult {
        try OutputService(fileManager: fileManager).moveOutputCandidates(
            candidates,
            originalOutputPath: originalOutputPath,
            to: destinationDirectory
        )
    }

    private nonisolated static let pdfImageExtensions = Set(["jpg", "jpeg", "png", "webp", "gif", "tif", "tiff", "bmp", "heic", "heif", "avif"])

    nonisolated static func browserViewURL(baseURLString: String, jobID: UUID, password: String, mode: String = "") -> URL? {
        browserViewURL(baseURLString: baseURLString, jobIDs: [jobID], password: password, mode: mode)
    }

    nonisolated static func browserViewURL(baseURLString: String, jobIDs: [UUID], password: String, mode: String = "") -> URL? {
        guard !jobIDs.isEmpty else { return nil }
        let value = baseURLString.trimmed
        guard !value.isEmpty, var components = URLComponents(string: value) else { return nil }
        if components.scheme == nil {
            components.scheme = "http"
        }
        if components.host == nil {
            components.host = "127.0.0.1"
        }
        components.path = "/view"

        let uniqueIDs = orderedUniqueJobIDs(jobIDs)
        var queryItems = [
            uniqueIDs.count == 1
                ? URLQueryItem(name: "uid", value: uniqueIDs[0].uuidString)
                : URLQueryItem(name: "uids", value: uniqueIDs.map(\.uuidString).joined(separator: ","))
        ]
        let password = password.trimmed
        if !password.isEmpty {
            queryItems.append(URLQueryItem(name: "pw", value: password))
        }
        let mode = mode.trimmed
        if !mode.isEmpty {
            queryItems.append(URLQueryItem(name: "mode", value: mode))
        }
        components.queryItems = queryItems
        return components.url
    }

    nonisolated static func textViewerURL(baseURLString: String, jobID: UUID, fileIndex: Int?, password: String) -> URL? {
        TextViewerCommandService.browserURL(
            baseURLString: baseURLString,
            jobID: jobID,
            fileIndex: fileIndex,
            password: password
        )
    }

    nonisolated static func browserHelperURL(baseURLString: String, targetURL: URL, password: String) -> URL? {
        BrowserWindowCommandService.helperURL(
            baseURLString: baseURLString,
            targetURL: targetURL,
            password: password
        )
    }

    private nonisolated static func orderedUniqueJobIDs(_ jobIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        var unique: [UUID] = []
        for id in jobIDs where seen.insert(id).inserted {
            unique.append(id)
        }
        return unique
    }

    private func ensureHTTPAPIAvailableForBrowserView() -> Bool {
#if TESTING
        if let testingEnsureHTTPAPIAvailableForBrowserView {
            return testingEnsureHTTPAPIAvailableForBrowserView()
        }
#endif
        if localAPIServerCoordinator.isRunning {
            return true
        }

        startHTTPAPIServer()
        return localAPIServerCoordinator.isRunning
    }

    private func httpAPIBaseURLString() -> String {
        let status = networkStore.httpAPIStatus.trimmed
        if status.hasPrefix("http://") || status.hasPrefix("https://") {
            return status
        }

        let port = settingsStore.httpAPIPortString.trimmed.isEmpty
            ? "8110"
            : settingsStore.httpAPIPortString.trimmed
        return "http://127.0.0.1:\(port)"
    }

    private struct JobOutputRemovalResult {
        var removedJobCount = 0
        var keptJobCount = 0
        var trashedItemCount = 0
        var failedItemCount = 0
        var deferredOutputDeletionCount = 0
    }

    private func trashOutputDeletionCandidates(_ candidates: [OutputDeletionCandidate]) throws -> OutputTrashResult {
        try outputService.trashOutputCandidates(
            candidates,
            protectedOutputRootPath: settingsStore.destinationPath,
            trashItem: { url in
                let resultingURL = try self.trashOutputItem(at: url)
#if TESTING
                if let resultingURL {
                    self.testingTrashedResultURLs.append(resultingURL)
                }
#endif
                return resultingURL
            }
        )
    }

    private func trashOutputItem(at url: URL) throws -> URL? {
#if TESTING
        if let handler = testingTrashItemHandler {
            return try handler(url)
        }
#endif
        var resultingURL: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resultingURL)
        return resultingURL as URL?
    }

    private func updateOutputPathAfterDeletingCandidates(at index: Int, trashedPaths: Set<String>) {
        guard queueStore.jobs.indices.contains(index) else { return }
        let rawPath = queueStore.jobs[index].outputPath
        let currentURL = URL(fileURLWithPath: rawPath)
        let currentPaths = Set([
            rawPath,
            currentURL.standardizedFileURL.path,
            currentURL.resolvingSymlinksInPath().standardizedFileURL.path
        ])
        guard !FileManager.default.fileExists(atPath: rawPath) ||
                !trashedPaths.isDisjoint(with: currentPaths) else {
            return
        }

        let replacementPath = resolvedOutputDeletionCandidates(for: queueStore.jobs[index]).first?.path ?? ""
        queueStore.updateJob(at: index) {
            $0.outputPath = replacementPath
        }
    }

    func startQueue(addingInput: Bool = true) {
        if addingInput {
            addURLs()
        }
        queueStore.setQueueEnabled(true)
        HTTPClient.shared.resumeAllTransfers()
        externalToolRuntime.resumeAllProcessesForQueue()
        guard !queueRunCoordinator.hasActiveRun else { return }
        guard queueStore.jobs.contains(where: { $0.status == .queued }) else { return }

        if ProcessInfo.processInfo.environment["HITOMI_NATIVE_DESTINATION_PATH"]?.trimmed.isEmpty != false {
            UserDefaults.standard.set(settingsStore.destinationPath, forKey: "destinationPath")
        }
        settingsStore.persistOutputSettingsSnapshot()
        settingsStore.persistAutoRemoveSettings()
        settingsStore.persistOutputPresentation()
        settingsStore.persistIncompleteRetry()
        settingsStore.persistDownloadBehavior()
        settingsStore.persistDuplicateImageSettings()
        settingsStore.persistAppAppearance()
        settingsStore.persistSelectedPythonThemeKey()
        settingsStore.persistQueuePresentation()
        settingsStore.persistQuickAccessItems()
        settingsStore.persistWindowAppearance()
        settingsStore.persistInterfaceFont()
        UserDefaults.standard.set(presentation.showingFloatingMonitor, forKey: "showingFloatingMonitor")
        settingsStore.persistJobStatusColorSettings()
        settingsStore.persistClipboardAutomation()
        settingsStore.persistLaunchAtLogin()
        persistCompletionAlertSettings()
        settingsStore.persistSleepPrevention()
        persistHistorySettings()
        settingsStore.persistYouTubeSnapshot()
        settingsStore.persistMediaSourceSnapshot()
        settingsStore.persistPixivUgoira()
        settingsStore.persistPawchive()
        settingsStore.persistHLS()
        persistAutoRecordSettings()
        persistExternalToolPaths()
        persistFFmpegTranscodeOptions()
        persistAria2Options()
        guard persistProxySettingsForUse() else {
            queueStore.setRunning(false)
            return
        }
        refreshDiskSpaceWarning(showAlert: true)

        queueScheduler.beginRun(jobs: queueStore.jobs)
        queueStore.setRunning(true)
        recordActivity("Queue started (\(queueStore.jobs.filter { $0.status == .queued }.count) queued, \(queueStore.jobs.count) total)", category: "Queue")
        syncSleepPreventionAssertion()
        resetQueueRunAlertState()
        queueRunCoordinator.start(
            operation: { [weak self] in
                await self?.runQueue()
            },
            completion: { [weak self] in
                guard let self else { return }
                self.releaseSleepPreventionAssertion()
                self.queueStore.setRunning(false)
                self.flushPendingQueueRemovals()
                self.normalizeActiveQueueOrder()
                self.persistQueue()
                self.runQueuedJobsIfEnabled()
            }
        )
    }

    func pauseQueue() {
        guard queueStore.isQueueEnabled else { return }
        queueStore.setQueueEnabled(false)
        HTTPClient.shared.pauseAllTransfers()
        externalToolRuntime.pauseAllProcessesForQueue()
        let message = "Queue paused"
        addSummary = message
        recordActivity(message, category: "Queue")
    }

    func resumeQueue() {
        let wasPaused = !queueStore.isQueueEnabled
        queueStore.setQueueEnabled(true)
        HTTPClient.shared.resumeAllTransfers()
        externalToolRuntime.resumeAllProcessesForQueue()
        if wasPaused {
            addSummary = "Queue resumed"
            recordActivity("Queue resumed", category: "Queue")
        }
        runQueuedJobsIfEnabled()
    }

    func toggleQueueEnabled() {
        if queueStore.isQueueEnabled {
            pauseQueue()
        } else {
            resumeQueue()
        }
    }

    func runQueuedJobsIfEnabled() {
        guard queueStore.isQueueEnabled,
              !queueRunCoordinator.hasActiveRun,
              queueStore.jobs.contains(where: { $0.status == .queued }) else {
            return
        }
        startQueue(addingInput: false)
    }

    private func launchJobTask(id: UUID) -> Task<Void, Never> {
        downloadCoordinator.launchJob(
            id: id,
            operation: { [weak self] in
                await self?.processJob(id: id)
            },
            onFinish: { [weak self] in
                guard let self,
                      self.queueStore.jobs.contains(where: Self.isPendingQueueRemoval) else {
                    return
                }
                self.flushPendingQueueRemovals()
                self.persistQueue()
            }
        )
    }

    private func cancelRunningJob(_ jobID: UUID) {
        downloadCoordinator.cancelJob(jobID)
        authenticationWaitCoordinator.resume(
            jobID: jobID
        )
        externalToolRuntime.terminateProcesses(for: jobID)
    }

    private func cancelAllRunningJobTasks() {
        downloadCoordinator.cancelAllJobs()
        externalToolRuntime.terminateAllProcesses()
    }

    func canStopLiveRecording(for job: DownloadJob) -> Bool {
        guard let current = queueStore.jobs.first(where: { $0.id == job.id }),
              isActive(current.status) else {
            return false
        }
        let nativeHLSIsActive = LiveHLSRecordingCoordinator
            .metadataIsTrue(current.metadata["live_active"]) &&
            LiveHLSRecordingCoordinator
            .metadataIsTrue(current.metadata["live_polling"])
        let ytdlpIsActive = LiveHLSRecordingCoordinator
            .metadataIsTrue(current.metadata["ytdlp_live"]) &&
            externalToolRuntime.processIsRunning(for: current.id, kind: .ytdlp)
        guard nativeHLSIsActive || ytdlpIsActive else { return false }
        return !LiveHLSRecordingCoordinator.metadataIsTrue(
            current.metadata[Self.liveStopRequestedMetadataKey]
        )
    }

    func stopLiveRecording(for job: DownloadJob) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }),
              canStopLiveRecording(for: queueStore.jobs[index]) else {
            addSummary = AppLocalization.text(
                "No live recording can be stopped",
                language: settingsStore.interfaceLanguage
            )
            return
        }

        let jobID = queueStore.jobs[index].id
        let isYTDLPLive = LiveHLSRecordingCoordinator.metadataIsTrue(
            queueStore.jobs[index].metadata["ytdlp_live"]
        )
        queueStore.updateJob(at: index) {
            $0.metadata[Self.liveStopRequestedMetadataKey] = "true"
            $0.metadata["live_stop_requested_at"] = ISO8601DateFormatter().string(from: Date())
            $0.metadata["transfer_active"] = "false"
            $0.message = "Stopping recording"
            $0.recordMessage($0.message)
            if isYTDLPLive {
                $0.metadata["ytdlp_stop_requested"] = "true"
            }
        }
        if isYTDLPLive {
            _ = externalToolRuntime.interruptProcess(
                for: jobID,
                kind: .ytdlp
            )
        }
        addSummary = AppLocalization.text(
            "Finishing live recording",
            language: settingsStore.interfaceLanguage
        )
        persistQueue()
    }

    func cancelQueue() {
        let wasRunning = queueRunCoordinator.cancel()
        cancelAllRunningJobTasks()
        authenticationWaitCoordinator.resumeAll()
        if !wasRunning {
            normalizeActiveQueueOrder()
            queueStore.setRunning(false)
            releaseSleepPreventionAssertion()
        }
        recordActivity("Queue cancelled", category: "Queue")
        cancelAllScheduledRestarts()
        for index in queueStore.jobs.indices where queueStore.jobs[index].status == .queued || queueStore.jobs[index].status == .resolving || queueStore.jobs[index].status == .downloading {
            markCancelled(index, persist: false)
        }
        persistQueue()
    }

    private func runQueue() async {
        let taskLimit = QueueScheduler.normalizedTaskLimit(settingsStore.jobConcurrency)
        guard taskLimit > 1 else {
            await runQueueSequentially()
            return
        }
        await runQueueConcurrently(taskLimit: taskLimit)
    }

    private func runQueueSequentially() async {
        await queueExecutionService.runSequentially(
            isEnabled: {
                self.queueStore.isQueueEnabled
            },
            nextJobID: {
                guard let index =
                    self.queueScheduler
                        .nextQueuedIndex(
                            in: self.queueStore.jobs
                        ) else {
                    return nil
                }
#if TESTING
                self.testingJobScheduledHandler?(
                    self.queueStore.jobs[index]
                )
#endif
                return self.queueStore.jobs[index].id
            },
            launchJob: { id in
                self.launchJobTask(id: id)
            }
        )
        if queueStore.isQueueEnabled, !queueStore.jobs.contains(where: { $0.status == .queued }) {
            handleQueueRunCompleted()
        }
    }

    private func runQueueConcurrently(taskLimit: Int) async {
        defersAutoRemoveUntilQueueEnd = true
        defer { defersAutoRemoveUntilQueueEnd = false }

        await queueExecutionService.runConcurrently(
            taskLimit: taskLimit,
            isEnabled: {
                self.queueStore.isQueueEnabled
            },
            reserveNextJobID: {
                self
                    .reserveNextQueuedJobForConcurrentRun()?
                    .id
            },
            launchJob: { id in
                self.launchJobTask(id: id)
            }
        )

        if queueStore.isQueueEnabled,
           !Task.isCancelled,
           !queueStore.jobs.contains(where: { $0.status == .queued }) {
            await flushDeferredAutoRemoveFinishedJobs()
            handleQueueRunCompleted()
        }
    }

    private func reserveNextQueuedJobForConcurrentRun() -> (index: Int, id: UUID)? {
        guard let index = queueScheduler.nextQueuedIndex(
            in: queueStore.jobs,
            serialGroup: { job in
                Self.isArcaliveQueueSource(job.source) ? "arcalive" : nil
            }
        ) else { return nil }
        let jobID = queueStore.jobs[index].id
#if TESTING
        testingJobScheduledHandler?(queueStore.jobs[index])
#endif
        queueStore.updateJob(at: index) {
            $0.status = .resolving
            $0.message = "Waiting for task slot"
        }
        persistQueue()
        return (index, jobID)
    }

    private func processJob(id: UUID) async {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == id }) else { return }
        await processJob(at: index)
    }

    private nonisolated static func isArcaliveQueueSource(_ source: String) -> Bool {
        guard let url = URL(string: source.trimmed) else { return false }
        return ArcaliveResolver.articleID(from: url) != nil
    }

    private func processJob(at index: Int) async {
        guard queueStore.jobs.indices.contains(index), queueStore.jobs[index].status != .cancelled else { return }
        queueStore.replaceJob(
            at: index,
            with: pythonHookJobApplicationService
                .preparingForStartHook(queueStore.jobs[index])
        )
        let startOutcome =
            await sourceJobStartHookPipeline.prepare(
                queueStore.jobs[index],
                runHooks: { context in
                    try await self.runPythonHooks(
                        event: .taskAboutToStart,
                        context: context
                    )
                }
            )
        switch startOutcome {
        case .prepared(let preparedJob):
            queueStore.replaceJob(at: index, with: preparedJob)
            persistQueue()
        case .failed(let disposition):
            handleExecutionFailure(
                disposition,
                context: .startHook,
                at: index
            )
            return
        }
        await processJobCore(at: index)
    }

    private func handleExecutionFailure(
        _ disposition:
            DownloadExecutionFailureDisposition,
        context: DownloadExecutionFailureContext,
        error: Error? = nil,
        at index: Int
    ) {
        switch downloadExecutionFailurePolicy.action(
            for: disposition,
            context: context
        ) {
        case .cancel:
            markCancelled(index)
        case .fail(
            let message,
            let reaction,
            let allowsIncompleteRetry,
            let attemptRecordingRetry
        ):
            if attemptRecordingRetry,
               let error,
               queueRecordingAutoRetryIfNeeded(
                   at: index,
                   error: error
               ) {
                return
            }
            markFailed(
                index,
                message: message,
                reaction: reaction,
                allowsIncompleteRetry: allowsIncompleteRetry
            )
        }
    }

    private func processJobCore(at index: Int) async {
        guard queueStore.jobs.indices.contains(index), queueStore.jobs[index].status != .cancelled else { return }
        let source = queueStore.jobs[index].source

#if TESTING
        let testingResolvedDownloadAvailable =
            testingResolvedDownloads[source] != nil
#else
        let testingResolvedDownloadAvailable = false
#endif
        await sourceJobExecutionCoordinator.execute(
            job: queueStore.jobs[index],
            testingResolvedDownloadAvailable:
                testingResolvedDownloadAvailable,
            pawchiveSiteAddresses: settingsStore.pawchiveSiteAddresses,
            pythonPluginAllowed:
                pythonNativeDelegationCoordinator
                    .allowsPythonPlugin(
                        for: queueStore.jobs[index].id
                    ),
            capabilities: {
                sourceJobExecutionCapabilities(
                    forJobAt: index
                )
            },
            actions: {
                sourceJobExecutionActions(
                    source: source,
                    jobIndex: index
                )
            },
            prepare: {
#if TESTING
                if self.testingJobStartDelayNanoseconds > 0 {
                    self.queueStore.updateJob(at: index) {
                        $0.status = .resolving
                        $0.message = "Testing start delay"
                    }
                    try await Task.sleep(
                        nanoseconds:
                            self.testingJobStartDelayNanoseconds
                    )
                }
#endif
            },
            isManuallyFinished: {
                self.isManuallyFinishedJob(at: index)
            },
            handleFailure: { error, disposition in
                self.handleExecutionFailure(
                    disposition,
                    context: .sourceExecution,
                    error: error,
                    at: index
                )
            }
        )
    }

    private func sourceJobExecutionCapabilities(
        forJobAt jobIndex: Int
    ) -> SourceJobExecutionCapabilities {
        sourceJobExecutionCapabilitiesFactory.makeCapabilities(
            forJobAt: jobIndex,
            provider: self
        )
    }

    func sourceJobRequestOptions(
        for url: URL
    ) -> HTTPRequestOptions {
        requestOptions(for: url)
    }

    func sourceJobResolverOptions(
        forJobAt jobIndex: Int
    ) -> SourceResolverExecutionOptions {
        sourceResolverExecutionOptions(forJobAt: jobIndex)
    }

    func sourceJobResolverContext(
        forJobAt jobIndex: Int
    ) -> SourceResolverExecutionContext {
        sourceResolverExecutionContext(forJobAt: jobIndex)
    }

    func sourceJobAria2CanResolve(_ url: URL) -> Bool {
        aria2Bridge.canResolve(url)
    }

    func sourceJobRetiredHTTPMessage(
        for url: URL
    ) -> String? {
        Self.retiredDaumWebtoonUnsupportedMessage(for: url)
    }

    func sourceJobPythonPlugin(
        for url: URL
    ) -> PythonSourceExecutionMatch? {
        guard let match = matchingPythonScriptPlugin(for: url) else {
            return nil
        }
        return PythonSourceExecutionMatch(
            plugin: match.plugin,
            downloader: match.downloader
        )
    }

    func sourceJobCustomCommandRule(
        for url: URL
    ) -> SiteRule? {
        matchingCustomCommandRule(for: url)
    }

    func sourceJobGenericPageCanResolve(_ url: URL) -> Bool {
        genericPageResolver.canResolve(url)
    }

    private func sourceResolverExecutionOptions(
        forJobAt jobIndex: Int
    ) -> SourceResolverExecutionOptions {
        sourceResolverExecutionOptionsFactory.makeOptions(
            rangeExpression: queueStore.jobs[jobIndex].rangeExpression,
            assetLimit:
                Self.finiteAssetRangeUpperBound(
                    queueStore.jobs[jobIndex].rangeExpression
                ),
            metadata: queueStore.jobs[jobIndex].metadata,
            preferences: SourceResolverExecutionPreferences(
                preferWebP: settingsStore.preferWebP,
                preferOriginalEHentaiImages:
                    settingsStore.preferOriginalEHentaiImages,
                preferJapaneseEHentaiTitle:
                    settingsStore.preferJapaneseEHentaiTitle,
                eHentaiSourceMode: settingsStore.eHentaiSourceMode,
                pawchiveSiteAddresses: settingsStore.pawchiveSiteAddresses,
                pawchiveDownloadLargeOriginalFiles:
                    settingsStore.pawchiveDownloadLargeOriginalFiles,
                pawchiveFileTypeSelection:
                    pawchiveFileTypeSelection,
                pixivArtwork: pixivArtworkExecutionOptions,
                youtubePreferredResolution:
                    settingsStore.youtubePreferredResolution,
                soopPreferredResolution:
                    settingsStore.soopPreferredResolution,
                youtubeVideoCodecPriority:
                    settingsStore.youtubeVideoCodecPriority,
                youtubeReversePlaylist:
                    settingsStore.youtubeReversePlaylist,
                numberPlaylistFiles: settingsStore.numberPlaylistFiles,
                instagramIncludeStories:
                    settingsStore.instagramIncludeStories
            )
        )
    }

    private func sourceJobExecutionActions(
        source: String,
        jobIndex: Int
    ) -> SourceJobExecutionActions {
        sourceJobExecutionActionFactory.makeActions(
            source: source,
            jobIndex: jobIndex,
            handler: self
        )
    }

    func canResolveSourceJobWithYTDLP(_ url: URL) -> Bool {
        ytdlpBridge.canResolve(
            url,
            siteRules: libraryStore.siteRules
        )
    }

    func executeSourceResolverPlan(
        _ plan: SourceResolverExecutionPlan,
        originalURL: URL,
        jobIndex: Int
    ) async throws {
        try await sourceResolverPlanJobCoordinator.execute(
            plan,
            originalURL: originalURL,
            jobIndex: jobIndex,
            persist: {
                persistQueue()
            },
            ytDLPCanResolve: {
                ytdlpBridge.canResolve(
                    originalURL,
                    siteRules: libraryStore.siteRules
                )
            },
            downloadResolved: { resolved, sourceURL in
                try await downloadResolved(
                    resolved,
                    sourceURL: sourceURL,
                    jobIndex: jobIndex
                )
            },
            downloadWithYTDLP: { fallbackURL in
                try await downloadWithYTDLP(
                    fallbackURL,
                    jobIndex: jobIndex
                )
            }
        )
    }

    func executeDiscordEmoji(
        _ request: DiscordEmojiRequest,
        source: String,
        jobIndex: Int
    ) async throws {
        try await discordEmojiJobCoordinator.execute(
            request,
            source: source,
            jobIndex: jobIndex,
            persist: {
                persistQueue()
            },
            downloadResolved: {
                resolved,
                sourceURL in
                try await downloadResolved(
                    resolved,
                    sourceURL: sourceURL,
                    jobIndex: jobIndex
                )
            }
        )
    }

    func executeTestingResolvedDownload(
        source: String,
        sourceURL: URL,
        jobIndex: Int
    ) async throws {
#if TESTING
        if let resolved = testingResolvedDownloads[source] {
            try await downloadResolved(
                resolved,
                sourceURL: sourceURL,
                jobIndex: jobIndex
            )
        }
#else
        _ = source
        _ = sourceURL
        _ = jobIndex
#endif
    }

    func executeDirectFile(
        _ url: URL,
        jobIndex: Int
    ) async throws {
        try await directFileJobCoordinator.execute(
            url,
            jobIndex: jobIndex,
            persist: {
                persistQueue()
            },
            download: { directURL in
                try await downloadDirect(
                    directURL,
                    jobIndex: jobIndex,
                    resolveHTMLMedia: false
                )
            }
        )
    }

    func executeOriginalInput(
        _ type: OriginalInputType,
        url: URL,
        jobIndex: Int
    ) async throws {
        try await originalInputJobCoordinator.execute(
            type,
            url: url,
            headers: requestOptions(for: url),
            options: OriginalInputExecutionOptions(
                rangeExpression: queueStore.jobs[jobIndex].rangeExpression,
                hitomi: HitomiResolverExecutionOptions(
                    preferWebP: settingsStore.preferWebP,
                    preferOriginalImages:
                        settingsStore.preferOriginalEHentaiImages,
                    preferJapaneseTitle:
                        settingsStore.preferJapaneseEHentaiTitle
                ),
                preferOriginalEHentaiImages:
                    settingsStore.preferOriginalEHentaiImages,
                preferJapaneseEHentaiTitle:
                    settingsStore.preferJapaneseEHentaiTitle,
                pixiv: pixivArtworkExecutionOptions
            ),
            context: sourceResolverExecutionContext(
                forJobAt: jobIndex
            ),
            jobIndex: jobIndex,
            persist: {
                persistQueue()
            },
            downloadResolved: { resolved, sourceURL in
                try await downloadResolved(
                    resolved,
                    sourceURL: sourceURL,
                    jobIndex: jobIndex
                )
            }
        )
    }

    func executePythonSource(
        _ script: PythonSourceExecutionMatch,
        sourceURL: URL,
        headers: HTTPRequestOptions,
        jobIndex: Int
    ) async throws {
        try await pythonSourceJobCoordinator.execute(
            script,
            sourceURL: sourceURL,
            headers: headers,
            jobIndex: jobIndex,
            configuredPythonPath: externalToolStore.pythonPath,
            persist: {
                persistQueue()
            },
            downloadResolved: { resolved, resolvedSourceURL in
                try await downloadResolved(
                    resolved,
                    sourceURL: resolvedSourceURL,
                    jobIndex: jobIndex
                )
            },
            executeNativeResolver: {
                await processJobCore(at: jobIndex)
            }
        )
    }

    func executeGenericPage(
        _ url: URL,
        headers: HTTPRequestOptions,
        jobIndex: Int
    ) async throws {
        try await genericPageJobCoordinator.execute(
            url: url,
            headers: headers,
            jobIndex: jobIndex,
            persist: {
                persistQueue()
            },
            downloadResolved: { resolved, sourceURL in
                try await downloadResolved(
                    resolved,
                    sourceURL: sourceURL,
                    jobIndex: jobIndex
                )
            },
            downloadDirect: { directURL in
                try await downloadDirect(
                    directURL,
                    jobIndex: jobIndex
                )
            }
        )
    }

    private func sourceResolverExecutionContext(
        forJobAt jobIndex: Int
    ) -> SourceResolverExecutionContext {
        sourceResolverJobContextService.makeContext(
            jobIndex: jobIndex,
            language: settingsStore.interfaceLanguage,
            persist: { [weak self] in
                self?.persistQueue()
            },
            authenticationActions:
                sourceResolverAuthenticationActions(
                    forJobAt: jobIndex
                )
        )
    }

    private func sourceResolverAuthenticationActions(
        forJobAt jobIndex: Int
    ) -> SourceResolverAuthenticationActions {
        SourceResolverAuthenticationActions(
            waitForArcalive: {
                [weak self] loginURL in
                guard let self else { return }
                await self.waitForArcaliveLogin(
                    at: jobIndex,
                    loginURL: loginURL
                )
            },
            waitForChzzk: { [weak self] in
                guard let self else { return }
                await self.waitForChzzkLogin(
                    at: jobIndex
                )
            },
            waitForNaverCafe: { [weak self] in
                guard let self else { return }
                await self.waitForNaverCafeLogin(
                    at: jobIndex
                )
            },
            waitForPixiv: { [weak self] in
                guard let self else { return }
                await self.waitForPixivLogin(
                    at: jobIndex
                )
            },
            waitForPornhub: { [weak self] in
                guard let self else { return }
                await self.waitForPornhubLogin(
                    at: jobIndex
                )
            },
            waitForTwitter: { [weak self] in
                guard let self else { return }
                await self.waitForTwitterLogin(
                    at: jobIndex
                )
            }
        )
    }

    private func reportSourceResolverProgress(
        _ progress: SourceResolverExecutionProgress,
        jobID: UUID
    ) {
        sourceResolverJobContextService
            .reportProgress(
                progress,
                jobID: jobID,
                language: settingsStore.interfaceLanguage,
                persist: {
                    self.persistQueue()
                }
            )
    }

#if TESTING
    func testingReportSourceResolverProgress(
        _ progress: SourceResolverExecutionProgress,
        jobID: UUID
    ) {
        reportSourceResolverProgress(
            progress,
            jobID: jobID
        )
    }
#endif

    private func waitForSourceResolverAuthentication(
        _ request: SourceResolverAuthenticationRequest,
        at jobIndex: Int
    ) async {
        await sourceResolverJobContextService
            .waitForAuthentication(
                request,
                actions:
                    sourceResolverAuthenticationActions(
                        forJobAt: jobIndex
                    )
            )
    }

#if TESTING
    func testingWaitForSourceResolverAuthentication(
        _ request: SourceResolverAuthenticationRequest,
        at jobIndex: Int
    ) async {
        await waitForSourceResolverAuthentication(
            request,
            at: jobIndex
        )
    }
#endif

    nonisolated static func isValidAssetRangeExpression(_ expression: String) -> Bool {
        ResolvedDownloadRangeService
            .isValidAssetRangeExpression(expression)
    }

    nonisolated static func assetIndexes(forRangeExpression expression: String, total: Int) throws -> [Int] {
        try ResolvedDownloadRangeService.assetIndexes(
            forRangeExpression: expression,
            total: total
        )
    }

    nonisolated static func finiteAssetRangeUpperBound(_ expression: String) -> Int? {
        ResolvedDownloadRangeService
            .finiteAssetRangeUpperBound(expression)
    }

    private nonisolated static func compactRangeDescription(
        fromZeroBasedIndexes indexes: [Int]
    ) -> String {
        ResolvedDownloadRangeService.compactRangeDescription(
            fromZeroBasedIndexes: indexes
        )
    }

    private func downloadResolved(_ resolved: ResolvedDownload, sourceURL: URL, jobIndex: Int) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        var previousMetadata = queueStore.jobs[jobIndex].metadata
        var resolved = resolved
        let temporaryAssetDirectories = resolved.temporaryAssetDirectories
        defer { Self.cleanupResolvedTemporaryAssetDirectories(temporaryAssetDirectories) }
        var sourceURL = sourceURL
        let hookPreparation =
            try await resolvedDownloadHookPreparationService.prepare(
                job: queueStore.jobs[jobIndex],
                resolved: resolved,
                sourceURL: sourceURL,
                previousMetadata: previousMetadata,
                hasHooks: { event, names in
                    !effectivePythonHookCalls(
                        for: event,
                        matchingNames: names
                    ).isEmpty
                },
                runHooks: { event, context, names in
                    try await runPythonHooks(
                        event: event,
                        context: context,
                        matchingNames: names
                    )
                },
                applySourceURL: { hookedSourceURL in
                    queueStore.updateJob(at: jobIndex) {
                        $0.source = hookedSourceURL.absoluteString
                    }
                }
            )
        resolved = hookPreparation.resolved
        sourceURL = hookPreparation.sourceURL
        previousMetadata = hookPreparation.previousMetadata
        let executionPreparation =
            try resolvedDownloadExecutionPreparationService.prepare(
                job: queueStore.jobs[jobIndex],
                resolved: resolved,
                sourceURL: sourceURL,
                previousMetadata: previousMetadata,
                applyHeaderRules: { download in
                    applyingHeaderRules(to: download)
                },
                outputRoot: { url, metadata in
                    try outputRoot(for: url, metadata: metadata)
                },
                folderName: { download, url in
                    templatedFolderName(
                        for: download,
                        sourceURL: url
                    )
                }
            )
        resolved = executionPreparation.resolved
        let root = executionPreparation.root
        let folderName = executionPreparation.folderName
        queueStore.replaceJob(
            at: jobIndex,
            with: executionPreparation.preparedJob
        )
        downloadCoordinator.removeRetrySnapshot(for: queueStore.jobs[jobIndex].id)
        persistQueue()

        if let sessionToken = resolved.metadata["niconico_live_session_token"] {
            try await downloadNiconicoLiveStream(
                resolved,
                sessionToken: sessionToken,
                root: root,
                sourceURL: sourceURL,
                jobIndex: jobIndex
            )
            return
        }

        try await resolvedPackageExecutionDispatchService.execute(
            resolved.packageMode,
            actions: ResolvedPackageExecutionActions(
                downloadFiles: {
                    try await self.executeResolvedFilesPackage(
                        resolved,
                        root: root,
                        folderName: folderName,
                        sourceURL: sourceURL,
                        jobIndex: jobIndex
                    )
                },
                concatenate: { outputFilename in
                    try await self.executeResolvedConcatenationPackage(
                        resolved,
                        outputFilename: outputFilename,
                        root: root,
                        folderName: folderName,
                        sourceURL: sourceURL,
                        jobIndex: jobIndex
                    )
                },
                mux: { videoAssets, audioAssets, outputFilename in
                    try await self.executeResolvedMuxPackage(
                        resolved,
                        videoAssets: videoAssets,
                        audioAssets: audioAssets,
                        outputFilename: outputFilename,
                        root: root,
                        folderName: folderName,
                        sourceURL: sourceURL,
                        jobIndex: jobIndex
                    )
                },
                grouped: { fileAssetIndexes, concatenations, muxes in
                    try await self.downloadGroupedPackage(
                        resolved,
                        fileAssetIndexes: fileAssetIndexes,
                        concatenations: concatenations,
                        muxes: muxes,
                        root: root,
                        folderName: folderName,
                        sourceURL: sourceURL,
                        jobIndex: jobIndex
                    )
                }
            )
        )
    }

    private func executeResolvedFilesPackage(
        _ resolved: ResolvedDownload,
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int
    ) async throws {
        try await resolvedFilesPackageCoordinator.execute(
            resolved,
            root: root,
            folderName: folderName,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            operations: ResolvedFilesPackageOperations(
                templatedAssets: {
                    assets,
                    title,
                    url,
                    metadata in
                    self.templatedAssets(
                        assets,
                        title: title,
                        sourceURL: url,
                        metadata: metadata
                    )
                },
                shouldSpaceOriginalModificationDates: {
                    url,
                    metadata,
                    assetMetadata in
                    Self.shouldSpaceOriginalModificationDates(
                        sourceURL: url,
                        metadata: metadata,
                        assetMetadata: assetMetadata
                    )
                },
                currentDate: Date.init,
                ensureDirectory: { folder in
                    try AppPaths.ensureDirectory(folder)
                },
                downloadAssets: {
                    assets,
                    folder,
                    spacingBase in
                    try await self.downloadAssets(
                        assets,
                        to: folder,
                        jobIndex: jobIndex,
                        modificationDateSpacingBase: spacingBase
                    )
                },
                writeMergedText: {
                    plan,
                    inputFiles,
                    folder in
                    try Self.writeMergedText(
                        plan: plan,
                        inputFiles: inputFiles,
                        to: folder
                    )
                },
                writeGalleryInfo: {
                    metadata,
                    url,
                    folder in
                    self.writeHitomiGalleryInfoTextIfNeeded(
                        metadata: metadata,
                        sourceURL: url,
                        folder: folder,
                        jobIndex: jobIndex
                    )
                },
                archiveFolder: {
                    folder,
                    url,
                    metadata in
                    try self.archiveFolderIfNeeded(
                        folder,
                        sourceURL: url,
                        metadata: metadata,
                        jobIndex: jobIndex
                    )
                },
                persist: {
                    self.persistQueue()
                },
                complete: {
                    await self.completeJob(at: jobIndex)
                }
            )
        )
    }

    private func executeResolvedConcatenationPackage(
        _ resolved: ResolvedDownload,
        outputFilename: String,
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int
    ) async throws {
        try await resolvedConcatenationPackageCoordinator.execute(
            resolved,
            outputFilename: outputFilename,
            root: root,
            folderName: folderName,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            operations: ResolvedConcatenationPackageOperations(
                temporaryFolder: { root, folderName in
                    root.appendingPathComponent(
                        ".\(folderName.sanitizedFilename(maxLength: 120))-\(UUID().uuidString)",
                        isDirectory: true
                    )
                },
                ensureDirectory: { folder in
                    try AppPaths.ensureDirectory(folder)
                },
                mergedMetadata: {
                    metadata,
                    assetMetadata in
                    Self.mergedNameTemplateMetadata(
                        metadata,
                        assetMetadata: assetMetadata
                    )
                },
                templatedOutputName: {
                    original,
                    title,
                    url,
                    total,
                    metadata,
                    packageMode in
                    self.templatedConcatenatedFileName(
                        original: original,
                        title: title,
                        sourceURL: url,
                        total: total,
                        metadata: metadata,
                        packageMode: packageMode
                    )
                },
                uniqueOutput: { root, filename in
                    AppPaths.uniqueFileURL(
                        in: root,
                        filename: filename
                    )
                },
                shouldPollLiveHLS: LiveHLSRecordingCoordinator.shouldPoll,
                downloadLiveHLS: {
                    resolved,
                    folder,
                    output in
                    try await self.downloadLiveHLSAndConcatenate(
                        resolved,
                        tempFolder: folder,
                        output: output,
                        jobIndex: jobIndex
                    )
                },
                downloadAndConcatenate: {
                    assets,
                    folder,
                    output in
                    try await self.downloadAndConcatenate(
                        assets,
                        tempFolder: folder,
                        output: output,
                        jobIndex: jobIndex
                    )
                },
                remuxHLS: { output, resolved in
                    try await self.remuxHLSIfNeeded(
                        output,
                        resolved: resolved,
                        jobIndex: jobIndex
                    )
                },
                applyModificationDate: {
                    output,
                    url,
                    metadata in
                    self.applyYouTubeUploadModificationDateIfNeeded(
                        to: output,
                        sourceURL: url,
                        metadata: metadata
                    )
                },
                persist: {
                    self.persistQueue()
                },
                complete: {
                    await self.completeJob(at: jobIndex)
                }
            )
        )
    }

    private func executeResolvedMuxPackage(
        _ resolved: ResolvedDownload,
        videoAssets: [ResolvedAsset],
        audioAssets: [ResolvedAsset],
        outputFilename: String,
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int
    ) async throws {
        try await resolvedMuxPackageCoordinator.execute(
            resolved,
            videoAssets: videoAssets,
            audioAssets: audioAssets,
            outputFilename: outputFilename,
            root: root,
            folderName: folderName,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            operations: ResolvedMuxPackageOperations(
                mergedMetadata: {
                    metadata,
                    assetMetadata in
                    Self.mergedNameTemplateMetadata(
                        metadata,
                        assetMetadata: assetMetadata
                    )
                },
                templatedFileName: {
                    original,
                    title,
                    url,
                    total,
                    metadata in
                    self.templatedFileName(
                        original: original,
                        title: title,
                        sourceURL: url,
                        index: nil,
                        total: total,
                        metadata: metadata
                    )
                },
                downloadAndMux: {
                    videoAssets,
                    audioAssets,
                    folderName,
                    outputFilename,
                    root,
                    jobIndex in
                    try await self.downloadAndMux(
                        videoAssets: videoAssets,
                        audioAssets: audioAssets,
                        folderName: folderName,
                        outputFilename: outputFilename,
                        root: root,
                        jobIndex: jobIndex
                    )
                }
            )
        )
    }

    @discardableResult
    private func downloadAssets(
        _ assets: [ResolvedAsset],
        to folder: URL,
        jobIndex: Int,
        modificationDateSpacingBase: Date? = nil
    ) async throws -> [URL] {
        let job = queueStore.jobs[jobIndex]
        let reportsNativeByteProgress =
            assets.count == 1 &&
            assets.first.map {
                shouldReportNativeTransferProgress(
                    asset: $0,
                    jobMetadata: job.metadata
                )
            } == true
        let progressHandler: HTTPDownloadProgressHandler? =
            reportsNativeByteProgress
                ? makeNativeTransferProgressHandler(jobID: job.id)
                : nil

        return try await mediaTransferCoordinator.execute(
            MediaTransferRequest(
                assets: assets,
                folder: folder,
                jobID: job.id,
                jobSourceURL: URL(string: job.source),
                jobMetadata: job.metadata,
                defaultConcurrency: settingsStore.fileConcurrency,
                hlsRateLimitNanoseconds:
                    Self.m3u8SegmentRateLimitNanoseconds(
                        from: settingsStore.m3u8SegmentDelayMillisecondsString
                    ),
                continueHLSSegmentFailures:
                    settingsStore.hlsContinueOnSegmentFailure,
                skipExistingDownloads: settingsStore.skipDuplicates,
                imageConversionFormat:
                    jobImageConversionFormat(for: job)
                    ?? settingsStore.imageConversionFormat,
                pythonRuntimePath: externalToolStore.pythonPath,
                useYouTubeUploadModificationDate:
                    settingsStore.youtubeUseUploadDateForFileModificationTime,
                modificationDateSpacingBase:
                    modificationDateSpacingBase,
                nativeTransferProgressHandler: progressHandler,
                reportsNativeByteProgress:
                    reportsNativeByteProgress
            ),
            onEvent: { event in
                self.applyMediaTransferEvent(
                    event,
                    jobIndex: jobIndex,
                    jobID: job.id
                )
            }
        )
    }

    private func applyMediaTransferEvent(
        _ event: MediaTransferEvent,
        jobIndex: Int,
        jobID: UUID
    ) {
        if case .finishingNativeTransfer = event {
            guard let currentIndex = queueStore.jobs.firstIndex(where: {
                $0.id == jobID
            }) else {
                return
            }
            queueStore.replaceJob(
                at: currentIndex,
                with: assetDownloadJobStateService
                    .finishingNativeTransfer(queueStore.jobs[currentIndex])
            )
            persistQueue()
            return
        }

        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        let job = queueStore.jobs[jobIndex]
        let updatedJob: DownloadJob
        switch event {
        case .skippedFailure(let failure, let total):
            updatedJob = assetDownloadJobStateService
                .recordingSkippedFailure(
                    failure,
                    total: total,
                    in: job
                )
        case .progress(
            let progress,
            let nativeDownloadedByteCount
        ):
            updatedJob = assetDownloadJobStateService
                .applyingProgress(
                    to: job,
                    skippedExisting:
                        progress.skippedExistingCount,
                    skippedFailures:
                        progress.skippedFailureCount,
                    nativeDownloadedByteCount:
                        nativeDownloadedByteCount
                )
        case .failure(let failure, let total):
            updatedJob = assetDownloadJobStateService
                .recordingFailure(
                    failure,
                    total: total,
                    in: job
                )
        case .deferredGalleryFailure(
            let assetCount,
            let downloadedItemCount,
            let skippedFailureCount
        ):
            updatedJob = assetDownloadJobStateService
                .recordingDeferredGalleryFailure(
                    in: job,
                    assetCount: assetCount,
                    downloadedItemCount: downloadedItemCount,
                    skippedFailureCount: skippedFailureCount
                )
        case .applyingPythonSegmentTransform:
            var applyingJob = job
            applyingJob.message = "Applying Python segment transform"
            updatedJob = applyingJob
        case .skippedExisting(let count):
            updatedJob = assetDownloadJobStateService
                .recordingSkippedExisting(
                    count,
                    in: job
                )
        case .finishingNativeTransfer:
            return
        }
        queueStore.replaceJob(at: jobIndex, with: updatedJob)
        persistQueue()
    }

    nonisolated static func writeMergedText(
        plan: ResolvedTextMergePlan,
        inputFiles: [URL],
        to folder: URL,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard !inputFiles.isEmpty else { throw NativeDownloadError.noFiles }
        try AppPaths.ensureDirectory(folder)
        let output = AppPaths.uniqueFileURL(
            in: folder,
            filename: plan.outputFilename.sanitizedFilename(maxLength: 180)
        )
        var completed = false
        defer {
            if !completed { try? fileManager.removeItem(at: output) }
        }
        fileManager.createFile(atPath: output.path, contents: Data(plan.header.utf8))
        let writer = try FileHandle(forWritingTo: output)
        defer { try? writer.close() }
        try writer.seekToEnd()

        let separator = Data(plan.separator.utf8)
        for input in inputFiles {
            try Task.checkCancellation()
            if !separator.isEmpty {
                try writer.write(contentsOf: separator)
            }
            do {
                let reader = try FileHandle(forReadingFrom: input)
                defer { try? reader.close() }
                while true {
                    let chunk = try reader.read(upToCount: 1_048_576) ?? Data()
                    if chunk.isEmpty { break }
                    try writer.write(contentsOf: chunk)
                }
            }
        }
        completed = true
        return output
    }

    nonisolated static func cleanupResolvedTemporaryAssetDirectories(
        _ directories: [URL],
        fileManager: FileManager = .default
    ) {
        let temporaryRoot = fileManager.temporaryDirectory.standardizedFileURL
        for rawCandidate in Set(directories.map(\.standardizedFileURL)) {
            guard rawCandidate.deletingLastPathComponent() == temporaryRoot,
                  rawCandidate.lastPathComponent.hasPrefix("HitomiBadayo-") ||
                    rawCandidate.lastPathComponent.hasPrefix("HitomiNative-") else {
                continue
            }
            try? fileManager.removeItem(at: rawCandidate)
        }
    }

    nonisolated static func assetDownloadConcurrency(defaultValue: Int, assets: [ResolvedAsset]) -> Int {
        MediaTransferPolicy.maximumConcurrency(
            defaultValue: defaultValue,
            assets: assets
        )
    }

    nonisolated static func assetProgressMessage(
        completed: Int,
        total: Int,
        skippedExisting: Int,
        skippedFailures: Int
    ) -> String {
        AssetDownloadJobStateService.progressMessage(
            completed: completed,
            total: total,
            skippedExisting: skippedExisting,
            skippedFailures: skippedFailures
        )
    }

    nonisolated static func assetCanSkipExistingOutput(_ asset: ResolvedAsset) -> Bool {
        MediaTransferPolicy.canSkipExistingOutput(asset)
    }

    nonisolated static func assetOutputFilename(_ asset: ResolvedAsset, imageConversionFormat: ImageConversionFormat) -> String {
        OutputService().outputFilename(
            for: asset,
            imageConversionFormat: imageConversionFormat
        )
    }

    nonisolated static func convertedImageFilename(
        _ filename: String,
        metadata: [String: String] = [:],
        remoteURL: URL? = nil,
        format: ImageConversionFormat
    ) -> String {
        OutputService().convertedImageFilename(
            filename,
            metadata: metadata,
            remoteURL: remoteURL,
            format: format
        )
    }

    nonisolated static func convertDownloadedImageIfNeeded(
        at url: URL,
        asset: ResolvedAsset,
        format: ImageConversionFormat,
        fileManager: FileManager = .default
    ) throws {
        try OutputService(fileManager: fileManager).convertDownloadedImageIfNeeded(
            at: url,
            asset: asset,
            format: format
        )
    }

    nonisolated static func convertOutputImages(
        forOutputPath outputPath: String,
        to format: ImageConversionFormat,
        quality: Int = 95,
        fileManager: FileManager = .default
    ) throws -> OutputImageConversionResult {
        try OutputService(fileManager: fileManager).convertOutputImages(
            forOutputPath: outputPath,
            to: format,
            quality: quality
        )
    }

    nonisolated static func convertImage(
        at url: URL,
        to format: ImageConversionFormat,
        quality: Int = 95,
        fileManager: FileManager = .default
    ) throws {
        try OutputService(fileManager: fileManager).convertImage(
            at: url,
            to: format,
            quality: quality
        )
    }

    nonisolated static func existingSkippableAssetURL(
        _ asset: ResolvedAsset,
        in folder: URL,
        skipDuplicates: Bool,
        outputFilename: String? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        MediaTransferPolicy.existingSkippableURL(
            asset,
            in: folder,
            skipDuplicates: skipDuplicates,
            outputFilename: outputFilename,
            fileManager: fileManager
        )
    }

    nonisolated static func assetUsesM3U8RateLimit(_ asset: ResolvedAsset) -> Bool {
        MediaTransferPolicy.usesM3U8RateLimit(asset)
    }

    nonisolated static func assetCanContinueAfterHLSFailure(_ asset: ResolvedAsset) -> Bool {
        MediaTransferPolicy.canContinueAfterHLSFailure(asset)
    }

    nonisolated static func assetCanDeferGalleryFailure(_ asset: ResolvedAsset) -> Bool {
        MediaTransferPolicy.canDeferGalleryFailure(asset)
    }

    nonisolated static func shouldSpaceOriginalModificationDates(
        sourceURL: URL,
        metadata: [String: String],
        assetMetadata: [[String: String]] = []
    ) -> Bool {
        MediaTransferPolicy.shouldSpaceOriginalModificationDates(
            sourceURL: sourceURL,
            metadata: metadata,
            assetMetadata: assetMetadata
        )
    }

    nonisolated static func originalModificationDate(baseDate: Date, index: Int) -> Date {
        MediaTransferPolicy.originalModificationDate(
            baseDate: baseDate,
            index: index
        )
    }

    nonisolated static func applyOriginalModificationDateSpacing(
        to url: URL,
        baseDate: Date,
        index: Int,
        fileManager: FileManager = .default
    ) throws {
        try MediaTransferPolicy.applyOriginalModificationDateSpacing(
            to: url,
            baseDate: baseDate,
            index: index,
            fileManager: fileManager
        )
    }

    nonisolated static func assetOriginalModificationDate(_ asset: ResolvedAsset) -> Date? {
        MediaTransferPolicy.originalModificationDate(for: asset)
    }

    nonisolated static func applyModificationDate(
        _ date: Date,
        to url: URL,
        fileManager: FileManager = .default
    ) throws {
        try MediaTransferPolicy.applyModificationDate(
            date,
            to: url,
            fileManager: fileManager
        )
    }

    private func applyYouTubeUploadModificationDateIfNeeded(
        to url: URL,
        sourceURL: URL?,
        metadata: [String: String]
    ) {
        guard settingsStore.youtubeUseUploadDateForFileModificationTime,
              let sourceURL,
              YTDLPBridge.isYouTubeSource(sourceURL, metadata: metadata),
              let date = YTDLPBridge.youtubeUploadModificationDate(from: metadata) else {
            return
        }
        try? Self.applyModificationDate(date, to: url)
    }

    private func archiveFolderIfNeeded(
        _ folder: URL,
        sourceURL: URL,
        metadata: [String: String],
        jobIndex: Int
    ) throws {
        let behavior = archiveBehavior(for: sourceURL, metadata: metadata)
        guard behavior.archive else { return }
        guard queueStore.jobs.indices.contains(jobIndex) else { return }

        queueStore.replaceJob(
            at: jobIndex,
            with: archiveJobStateService
                .preparingAutomaticArchive(
                    queueStore.jobs[jobIndex],
                    format: behavior.format
                )
        )
        persistQueue()

        let archived = try outputService.archiveCompletedFolder(
            folder,
            format: behavior.format,
            deleteOriginal: behavior.deleteOriginal
        )

        queueStore.replaceJob(
            at: jobIndex,
            with: archiveJobStateService
                .finishingAutomaticArchive(
                    queueStore.jobs[jobIndex],
                    archive: archived,
                    sourceFolder: folder,
                    format: behavior.format,
                    deletedOriginal: behavior.deleteOriginal,
                    ruleName: behavior.ruleName,
                    sourceURL: sourceURL,
                    sourceMetadata: metadata
                )
        )
        persistQueue()
    }

    func archiveBehavior(
        for sourceURL: URL,
        metadata: [String: String] = [:]
    ) -> (archive: Bool, deleteOriginal: Bool, ruleName: String?, format: ArchiveFileFormat) {
        if let rule = matchingArchiveRule(for: sourceURL) {
            switch rule.archiveMode {
            case .zip, .cbz:
                return (true, rule.deleteOriginalAfterArchiving, rule.name, rule.archiveMode.archiveFormat ?? .zip)
            case .none:
                return (false, false, rule.name, settingsStore.archiveFileFormat)
            case .default:
                break
            }
        }
        let sourceID = DownloadSourceFolderProfile.sourceID(for: sourceURL, metadata: metadata)
        let mode = sourceArchiveMode(for: sourceID)
        guard let format = mode.archiveFormat else {
            return (false, false, nil, settingsStore.archiveFileFormat)
        }
        return (true, sourceArchiveDeletesOriginal(for: sourceID), nil, format)
    }

    private func matchingArchiveRule(for url: URL) -> SiteRule? {
        guard url.host != nil else { return nil }
        return libraryStore.siteRules
            .filter { $0.archiveMode != .default }
            .sorted { $0.matchSpecificity > $1.matchSpecificity }
            .first { $0.matches(url) }
    }

#if TESTING
    func testingArchiveFolderIfNeeded(
        _ folder: URL,
        sourceURL: URL,
        metadata: [String: String] = [:],
        jobIndex: Int
    ) throws {
        try archiveFolderIfNeeded(
            folder,
            sourceURL: sourceURL,
            metadata: metadata,
            jobIndex: jobIndex
        )
    }
#endif

    private func writeHitomiGalleryInfoTextIfNeeded(metadata: [String: String], sourceURL: URL, folder: URL, jobIndex: Int) {
        guard settingsStore.saveHitomiGalleryInfoText, queueStore.jobs.indices.contains(jobIndex) else { return }
        do {
            if let url = try Self.writeHitomiGalleryInfoText(metadata: metadata, sourceURL: sourceURL, to: folder) {
                queueStore.updateJob(at: jobIndex) {
                    $0.metadata["info_text_path"] = url.path
                }
            }
        } catch {
            queueStore.updateJob(at: jobIndex) {
                $0.metadata["info_text_error"] = AppLocalization.errorText(error)
            }
        }
        persistQueue()
    }

    @discardableResult
    nonisolated static func writeHitomiGalleryInfoText(metadata: [String: String], sourceURL: URL, to folder: URL) throws -> URL? {
        guard isHitomiGalleryMetadata(metadata, sourceURL: sourceURL) else { return nil }
        try AppPaths.ensureDirectory(folder)
        let url = folder.appendingPathComponent("gallery-info.txt")
        try hitomiGalleryInfoText(metadata: metadata, sourceURL: sourceURL).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    nonisolated static func hitomiGalleryInfoText(metadata: [String: String], sourceURL: URL) -> String {
        let rows: [(String, String)] = [
            ("Title", metadataValue(metadata, keys: ["title"])),
            ("Gallery ID", metadataValue(metadata, keys: ["gallery_id", "media_id"])),
            ("Source", sourceURL.absoluteString),
            ("Site", metadataValue(metadata, keys: ["site"])),
            ("Type", metadataValue(metadata, keys: ["type", "category"])),
            ("Language", metadataValue(metadata, keys: ["language"])),
            ("Artist", metadataValue(metadata, keys: ["artist", "author", "creator"])),
            ("Group", metadataValue(metadata, keys: ["group", "circle"])),
            ("Parody", metadataValue(metadata, keys: ["parody", "series"])),
            ("Character", metadataValue(metadata, keys: ["character"])),
            ("Tags", metadataValue(metadata, keys: ["tags", "tag"])),
            ("Date", metadataValue(metadata, keys: ["date"])),
            ("Range", metadataValue(metadata, keys: ["range_indexes", "range"]))
        ]

        let body = rows
            .map { label, value in (label, value.trimmed) }
            .filter { !$0.1.isEmpty }
            .map { "\($0.0): \($0.1)" }
            .joined(separator: "\n")
        return body + "\n"
    }

    private nonisolated static func isHitomiGalleryMetadata(_ metadata: [String: String], sourceURL: URL) -> Bool {
        let site = metadataValue(metadata, keys: ["site"]).lowercased()
        if site == "hitomi" || site == "hitomi.la" {
            return true
        }
        if !metadataValue(metadata, keys: ["gallery_id"]).isEmpty,
           let host = sourceURL.host?.lowercased(),
           host == "hitomi.la" || host.hasSuffix(".hitomi.la") {
            return true
        }
        return false
    }

    nonisolated static func hitomiGalleryNumbers(in root: URL, fileManager: FileManager = .default) -> [String] {
        HitomiGalleryNumberService().numbers(
            in: root,
            fileManager: fileManager
        )
    }

    nonisolated static func hitomiGalleryNumbers(fromOutputName name: String) -> [String] {
        HitomiGalleryNumberService().numbers(
            fromOutputName: name
        )
    }

    private nonisolated static func hitomiGalleryNumbers(fromOutputFile url: URL) -> [String] {
        HitomiGalleryNumberService().numbers(
            fromOutputFile: url
        )
    }

    private nonisolated static func metadataValue(_ metadata: [String: String], keys: [String]) -> String {
        for key in keys {
            if let value = metadata.first(where: { $0.key.lowercased() == key.lowercased() })?.value.trimmed,
               !value.isEmpty {
                return value
            }
        }
        return ""
    }

    private func shouldReportNativeTransferProgress(
        asset: ResolvedAsset,
        jobMetadata: [String: String]
    ) -> Bool {
        nativeTransferProgressService.shouldReportProgress(
            for: asset,
            jobMetadata: jobMetadata
        )
    }

    private func makeNativeTransferProgressHandler(jobID: UUID) -> HTTPDownloadProgressHandler {
        { [weak self] update in
            Task<Void, Never> { @MainActor [weak self] in
                self?.applyNativeTransferProgress(update, jobID: jobID)
            }
        }
    }

    private func applyNativeTransferProgress(_ update: HTTPDownloadProgress, jobID: UUID) {
        guard queueStore.isQueueEnabled,
              let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[index].status == .downloading else { return }

        queueStore.replaceJob(
            at: index,
            with: nativeTransferProgressService.applying(
                update,
                to: queueStore.jobs[index],
                interfaceLanguage: settingsStore.interfaceLanguage
            )
        )
        persistQueue()
    }

    nonisolated static func remoteSegmentRanges(
        totalLength: Int64,
        segmentSize: Int64
    ) -> [(start: Int64, end: Int64)] {
        AssetTransferService.remoteSegmentRanges(
            totalLength: totalLength,
            segmentSize: segmentSize
        )
    }

    private func downloadAndConcatenate(
        _ assets: [ResolvedAsset],
        tempFolder: URL,
        output: URL,
        jobIndex: Int
    ) async throws {
        try await mediaConcatenationCoordinator.execute(
            MediaConcatenationRequest(
                assets: assets,
                temporaryFolder: tempFolder,
                output: output
            ),
            operations: MediaConcatenationOperations(
                downloadAssets: { assets, folder in
                    try await self.downloadAssets(
                        assets,
                        to: folder,
                        jobIndex: jobIndex
                    )
                },
                onEvent: { _ in
                    guard self.queueStore.jobs.indices.contains(jobIndex) else {
                        return
                    }
                    self.queueStore.updateJob(at: jobIndex) {
                        $0.message = "Joining segments"
                    }
                    self.persistQueue()
                }
            )
        )
    }

    private func downloadLiveHLSAndConcatenate(
        _ initialResolved: ResolvedDownload,
        tempFolder: URL,
        output: URL,
        jobIndex: Int
    ) async throws {
        try await liveHLSRecordingCoordinator.execute(
            LiveHLSRecordingRequest(
                initialResolved: initialResolved,
                tempFolder: tempFolder,
                output: output
            ),
            operations: LiveHLSRecordingOperations(
                fallbackConcatenate: {
                    assets,
                    fallbackFolder,
                    fallbackOutput in
                    try await self.downloadAndConcatenate(
                        assets,
                        tempFolder: fallbackFolder,
                        output: fallbackOutput,
                        jobIndex: jobIndex
                    )
                },
                downloadAssets: { assets, folder in
                    try await self.downloadAssets(
                        assets,
                        to: folder,
                        jobIndex: jobIndex
                    )
                },
                resolvePlaylist: { context in
                    try await self.m3u8Resolver.resolve(
                        context.playlistURL,
                        headers: context.headers,
                        additionalHeaders: context.additionalHeaders,
                        segmentReferer: context.segmentReferer
                    )
                },
                stopRequested: {
                    self.liveRecordingStopRequested(at: jobIndex)
                },
                onEvent: { event in
                    self.applyLiveHLSRecordingEvent(
                        event,
                        jobIndex: jobIndex
                    )
                }
            )
        )
    }

    private func liveRecordingStopRequested(at jobIndex: Int) -> Bool {
        queueStore.jobs.indices.contains(jobIndex) &&
            LiveHLSRecordingCoordinator.metadataIsTrue(
                queueStore.jobs[jobIndex].metadata[
                    Self.liveStopRequestedMetadataKey
                ]
            )
    }

    private func applyLiveHLSRecordingEvent(
        _ event: LiveHLSRecordingEvent,
        jobIndex: Int
    ) {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        let job = queueStore.jobs[jobIndex]
        let updatedJob: DownloadJob
        switch event {
        case .starting(let playlistURL, let pollInterval, let timeout):
            updatedJob = liveHLSJobStateService.starting(
                job,
                playlistURL: playlistURL,
                pollInterval: pollInterval,
                timeout: timeout
            )
        case .preparingBatch(let count, let isInitialSnapshot):
            updatedJob = liveHLSJobStateService.preparingBatch(
                job,
                count: count,
                isInitialSnapshot: isInitialSnapshot
            )
        case .preparingAppend:
            updatedJob = liveHLSJobStateService.preparingAppend(job)
        case .recordingBatch(
            let segmentCount,
            let mediaCount,
            let recordedDuration,
            let outputBytes,
            let speed,
            let recordedAt,
            let snapshotCount
        ):
            updatedJob = liveHLSJobStateService.recordingBatch(
                job,
                segmentCount: segmentCount,
                mediaCount: mediaCount,
                recordedDuration: recordedDuration,
                outputBytes: outputBytes,
                speed: speed,
                recordedAt: recordedAt,
                snapshotCount: snapshotCount
            )
        case .waitingForSegments:
            updatedJob = liveHLSJobStateService
                .waitingForSegments(job)
        case .recordingRefresh(let pollCount, let pollInterval):
            updatedJob = liveHLSJobStateService.recordingRefresh(
                job,
                pollCount: pollCount,
                pollInterval: pollInterval
            )
        case .recordingRefreshFailure(let pollCount, let errorText):
            updatedJob = liveHLSJobStateService
                .recordingRefreshFailure(
                    job,
                    pollCount: pollCount,
                    errorText: errorText
                )
        case .finishingPolling(
            let reason,
            let pollCount,
            let outputBytes,
            let hasPartialOutput
        ):
            updatedJob = liveHLSJobStateService.finishingPolling(
                job,
                reason: reason,
                pollCount: pollCount,
                outputBytes: outputBytes,
                hasPartialOutput: hasPartialOutput
            )
        case .recordingFailure(
            let cancelled,
            let pollCount,
            let outputBytes,
            let hasPartialOutput
        ):
            updatedJob = liveHLSJobStateService.recordingFailure(
                job,
                cancelled: cancelled,
                pollCount: pollCount,
                outputBytes: outputBytes,
                hasPartialOutput: hasPartialOutput
            )
        }
        queueStore.replaceJob(at: jobIndex, with: updatedJob)
        persistQueue()
    }

    nonisolated static func youtubeCollectionVideoID(fromFilename filename: String) -> String? {
        let basename = (filename as NSString).lastPathComponent
        for pattern in [
            #"\(([0-9A-Za-z_-]{10,})\)\."#,
            #"\(([0-9A-Za-z_-]{10,})\)"#
        ] {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(
                    in: basename,
                    range: NSRange(basename.startIndex..<basename.endIndex, in: basename)
                  ),
                  match.numberOfRanges > 1,
                  let range = Range(match.range(at: 1), in: basename) else {
                continue
            }
            return String(basename[range])
        }
        return nil
    }

    private nonisolated static func youtubeCollectionExistingOutputs(
        in directory: URL,
        candidateIDs: Set<String>,
        fileManager: FileManager = .default
    ) -> [String: URL] {
        guard !candidateIDs.isEmpty,
              let contents = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
              ) else {
            return [:]
        }

        var outputs: [String: URL] = [:]
        for url in contents.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) != true else {
                continue
            }
            let filename = url.lastPathComponent
            if let id = youtubeCollectionVideoID(fromFilename: filename),
               candidateIDs.contains(id) {
                outputs[id] = url
                continue
            }
            let stem = (filename as NSString).deletingPathExtension
            if let id = candidateIDs.first(where: { candidate in
                stem == candidate ||
                    stem.hasSuffix("-\(candidate)") ||
                    stem.hasSuffix(" \(candidate)") ||
                    stem.hasSuffix("_\(candidate)")
            }) {
                outputs[id] = url
            }
        }
        return outputs
    }

    private func downloadGroupedPackage(
        _ resolved: ResolvedDownload,
        fileAssetIndexes: [Int],
        concatenations: [ResolvedConcatenationGroup],
        muxes: [ResolvedMuxGroup],
        root: URL,
        folderName: String,
        sourceURL: URL,
        jobIndex: Int
    ) async throws {
        try await resolvedGroupedPackageCoordinator.execute(
            resolved,
            fileAssetIndexes: fileAssetIndexes,
            concatenations: concatenations,
            muxes: muxes,
            root: root,
            folderName: folderName,
            sourceURL: sourceURL,
            jobIndex: jobIndex,
            operations: ResolvedGroupedPackageOperations(
                ensureDirectory: { folder in
                    try AppPaths.ensureDirectory(folder)
                },
                existingYouTubeOutputs: {
                    folder,
                    candidateIDs in
                    Self.youtubeCollectionExistingOutputs(
                        in: folder,
                        candidateIDs: candidateIDs
                    )
                },
                mergedMetadata: {
                    metadata,
                    assetMetadata in
                    Self.mergedNameTemplateMetadata(
                        metadata,
                        assetMetadata: assetMetadata
                    )
                },
                templatedFileName: {
                    original,
                    title,
                    url,
                    index,
                    total,
                    metadata,
                    templateOverride in
                    self.templatedFileName(
                        original: original,
                        title: title,
                        sourceURL: url,
                        index: index,
                        total: total,
                        metadata: metadata,
                        templateOverride: templateOverride
                    )
                },
                recordingFileNameTemplate: {
                    self.settingsStore.recordingFileNameTemplate
                },
                shouldUseRecordingFileNameTemplate: {
                    packageMode,
                    metadata in
                    Self.shouldUseRecordingFileNameTemplate(
                        packageMode: packageMode,
                        metadata: metadata
                    )
                },
                uniqueOutput: { folder, filename in
                    AppPaths.uniqueFileURL(
                        in: folder,
                        filename: filename
                    )
                },
                temporaryStreamFolder: {
                    folder,
                    groupIndex in
                    folder.appendingPathComponent(
                        ".stream-\(groupIndex + 1)-\(UUID().uuidString)",
                        isDirectory: true
                    )
                },
                removeTemporaryFolder: { folder in
                    try? FileManager.default.removeItem(at: folder)
                },
                downloadAssets: { assets, folder in
                    _ = try await self.downloadAssets(
                        assets,
                        to: folder,
                        jobIndex: jobIndex
                    )
                },
                downloadAndConcatenate: {
                    assets,
                    folder,
                    output in
                    try await self.downloadAndConcatenate(
                        assets,
                        tempFolder: folder,
                        output: output,
                        jobIndex: jobIndex
                    )
                },
                remuxGroupedHLS: { output, metadata in
                    try await self.remuxGroupedHLSIfNeeded(
                        output,
                        metadata: metadata,
                        jobIndex: jobIndex
                    )
                },
                downloadGroupedMux: {
                    videoAssets,
                    audioAssets,
                    output,
                    groupIndex,
                    groupCount,
                    folder in
                    try await self.downloadGroupedMux(
                        videoAssets: videoAssets,
                        audioAssets: audioAssets,
                        output: output,
                        groupIndex: groupIndex,
                        groupCount: groupCount,
                        folder: folder,
                        jobIndex: jobIndex
                    )
                },
                applyModificationDate: {
                    output,
                    url,
                    metadata in
                    self.applyYouTubeUploadModificationDateIfNeeded(
                        to: output,
                        sourceURL: url,
                        metadata: metadata
                    )
                },
                writeGalleryInfo: {
                    metadata,
                    url,
                    folder in
                    self.writeHitomiGalleryInfoTextIfNeeded(
                        metadata: metadata,
                        sourceURL: url,
                        folder: folder,
                        jobIndex: jobIndex
                    )
                },
                archiveFolder: {
                    folder,
                    url,
                    metadata in
                    try self.archiveFolderIfNeeded(
                        folder,
                        sourceURL: url,
                        metadata: metadata,
                        jobIndex: jobIndex
                    )
                },
                persist: {
                    self.persistQueue()
                },
                complete: {
                    await self.completeJob(at: jobIndex)
                }
            )
        )
    }

    private func downloadGroupedMux(
        videoAssets: [ResolvedAsset],
        audioAssets: [ResolvedAsset],
        output: URL,
        groupIndex: Int,
        groupCount: Int,
        folder: URL,
        jobIndex: Int
    ) async throws {
        let workFolder = folder.appendingPathComponent(
            ".mux-\(groupIndex + 1)-\(UUID().uuidString)",
            isDirectory: true
        )
        let transcodeOptions = ffmpegTranscodeOptionsForUse()
        try await mediaMuxCoordinator.execute(
            MediaMuxRequest(
                videoAssets: videoAssets,
                audioAssets: audioAssets,
                workFolder: workFolder,
                output: output,
                options: transcodeOptions
            ),
            operations: mediaMuxOperations(jobIndex: jobIndex) {
                event in
                guard self.queueStore.jobs.indices.contains(jobIndex) else {
                    return false
                }
                let updatedJob: DownloadJob
                switch event {
                case .preparingVideo:
                    updatedJob =
                        self.resolvedPackageJobStateService
                        .preparingGroupedDASHVideo(
                            self.queueStore.jobs[jobIndex],
                            index: groupIndex + 1,
                            total: groupCount
                        )
                case .preparingAudio:
                    updatedJob =
                        self.resolvedPackageJobStateService
                        .preparingGroupedDASHAudio(
                            self.queueStore.jobs[jobIndex],
                            index: groupIndex + 1,
                            total: groupCount
                        )
                case .preparingFinalization(let transcoding):
                    updatedJob =
                        self.resolvedPackageJobStateService
                        .preparingGroupedDASHFinalization(
                            self.queueStore.jobs[jobIndex],
                            index: groupIndex + 1,
                            total: groupCount,
                            transcoding: transcoding
                        )
                case .completed(_, let options):
                    updatedJob =
                        self.resolvedPackageJobStateService
                        .recordingGroupedDASHCompletion(
                            self.queueStore.jobs[jobIndex],
                            transcoding: options.enabled
                        )
                }
                self.queueStore.replaceJob(
                    at: jobIndex,
                    with: updatedJob
                )
                self.persistQueue()
                return true
            }
        )
    }

    private func mediaMuxOperations(
        jobIndex: Int,
        onEvent: @escaping @MainActor (MediaMuxEvent) async -> Bool
    ) -> MediaMuxOperations {
        MediaMuxOperations(
            downloadAndConcatenate: { assets, folder, output in
                try await self.downloadAndConcatenate(
                    assets,
                    tempFolder: folder,
                    output: output,
                    jobIndex: jobIndex
                )
            },
            mux: { video, audio, output, options in
                try await self.externalToolRuntime.executeFFmpegMux(
                    video: video,
                    audio: audio,
                    output: output,
                    options: options
                )
            },
            onEvent: onEvent
        )
    }

    private func remuxGroupedHLSIfNeeded(
        _ output: URL,
        metadata: [String: String],
        jobIndex: Int
    ) async throws -> URL {
        guard queueStore.jobs.indices.contains(jobIndex) else { return output }
        let transcodeOptions = ffmpegTranscodeOptionsForUse()
        return try await mediaRemuxCoordinator.execute(
            MediaRemuxRequest(
                output: output,
                metadata: metadata,
                defaultEnabled: settingsStore.remuxM3U8ToMP4,
                options: transcodeOptions
            ),
            operations: MediaRemuxOperations(
                uniqueOutput: { directory, filename in
                    AppPaths.uniqueFileURL(
                        in: directory,
                        filename: filename
                    )
                },
                remux: { input, output, options in
                    try await self.externalToolRuntime
                        .executeFFmpegRemux(
                            input: input,
                            output: output,
                            options: options
                        )
                },
                onEvent: { event in
                    self.applyGroupedMediaRemuxEvent(
                        event,
                        jobIndex: jobIndex
                    )
                }
            )
        )
    }

    private func remuxHLSIfNeeded(
        _ output: URL,
        resolved: ResolvedDownload,
        jobIndex: Int
    ) async throws -> URL {
        guard queueStore.jobs.indices.contains(jobIndex) else { return output }
        let transcodeOptions = ffmpegTranscodeOptionsForUse()
        return try await mediaRemuxCoordinator.execute(
            MediaRemuxRequest(
                output: output,
                metadata: resolved.metadata,
                defaultEnabled: settingsStore.remuxM3U8ToMP4,
                options: transcodeOptions
            ),
            operations: MediaRemuxOperations(
                uniqueOutput: { directory, filename in
                    AppPaths.uniqueFileURL(
                        in: directory,
                        filename: filename
                    )
                },
                remux: { input, output, options in
                    try await self.externalToolRuntime
                        .executeFFmpegRemux(
                            input: input,
                            output: output,
                            options: options
                        )
                },
                onEvent: { event in
                    self.applyMediaRemuxEvent(
                        event,
                        jobIndex: jobIndex
                    )
                }
            )
        )
    }

    private nonisolated static func isHLSDownload(_ resolved: ResolvedDownload) -> Bool {
        MediaRemuxPolicy.isHLS(metadata: resolved.metadata)
    }

    nonisolated static func shouldRemuxHLS(defaultEnabled: Bool, metadata: [String: String]) -> Bool {
        MediaRemuxPolicy.shouldRemux(
            defaultEnabled: defaultEnabled,
            metadata: metadata
        )
    }

    private func applyGroupedMediaRemuxEvent(
        _ event: MediaRemuxEvent,
        jobIndex: Int
    ) {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        let updatedJob: DownloadJob
        switch event {
        case .preparing(let transcoding):
            updatedJob = resolvedPackageJobStateService
                .preparingGroupedHLSFinalization(
                    queueStore.jobs[jobIndex],
                    transcoding: transcoding
                )
        case .completed(_, let options):
            updatedJob = resolvedPackageJobStateService
                .recordingGroupedHLSCompletion(
                    queueStore.jobs[jobIndex],
                    transcoding: options.enabled
            )
        }
        queueStore.replaceJob(at: jobIndex, with: updatedJob)
        persistQueue()
    }

    private func applyMediaRemuxEvent(
        _ event: MediaRemuxEvent,
        jobIndex: Int
    ) {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        let updatedJob: DownloadJob
        switch event {
        case .preparing(let transcoding):
            updatedJob = resolvedPackageJobStateService
                .preparingHLSFinalization(
                    queueStore.jobs[jobIndex],
                    transcoding: transcoding
                )
        case .completed(let output, let options):
            updatedJob = resolvedPackageJobStateService
                .recordingHLSCompletion(
                    queueStore.jobs[jobIndex],
                    output: output,
                    options: options
            )
        }
        queueStore.replaceJob(at: jobIndex, with: updatedJob)
        persistQueue()
    }

    private func downloadNiconicoLiveStream(
        _ resolved: ResolvedDownload,
        sessionToken: String,
        root: URL,
        sourceURL: URL,
        jobIndex: Int
    ) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else {
            await niconicoLiveResolver.stopSession(sessionToken)
            throw NativeDownloadError.unsupported(
                "Niconico Live recording information is incomplete."
            )
        }
        let transcodeOptions = ffmpegTranscodeOptionsForUse()
        let jobID = queueStore.jobs[jobIndex].id
        try await niconicoLiveRecordingCoordinator.execute(
            NiconicoLiveRecordingRequest(
                resolved: resolved,
                sessionToken: sessionToken,
                root: root,
                sourceURL: sourceURL,
                jobID: jobID,
                options: transcodeOptions
            ),
            operations: NiconicoLiveRecordingOperations(
                outputName: { resolved, sourceURL in
                    self.templatedFileName(
                        original: resolved.metadata[
                            "live_output_filename"
                        ]?.trimmed ?? "recording.mp4",
                        title: resolved.title,
                        sourceURL: sourceURL,
                        index: nil,
                        total: 1,
                        metadata:
                            Self.mergedNameTemplateMetadata(
                                resolved.metadata,
                                assetMetadata:
                                    resolved.assets.first?
                                    .metadata ?? [:]
                            )
                    )
                },
                uniqueOutput: { root, filename in
                    AppPaths.uniqueFileURL(
                        in: root,
                        filename: filename
                    )
                },
                record: {
                    jobID,
                    videoPlaylist,
                    audioPlaylist,
                    output,
                    headers,
                    options,
                    onStart in
                    try await self.externalToolRuntime
                        .withProcessExecution(
                            for: jobID,
                            kind: .ffmpeg
                        ) { processControl in
                            await onStart()
                            try await self.externalToolRuntime
                                .executeFFmpegLiveRecording(
                                    videoPlaylist: videoPlaylist,
                                    audioPlaylist: audioPlaylist,
                                    output: output,
                                    headers: headers,
                                    options: options,
                                    processControl: processControl
                                )
                        }
                },
                stopSession: { token in
                    await self.niconicoLiveResolver.stopSession(token)
                },
                onEvent: { event in
                    guard self.queueStore.jobs.indices.contains(jobIndex),
                          self.queueStore.jobs[jobIndex].id == jobID else {
                        return
                    }
                    switch event {
                    case .starting(
                        let output,
                        let transcoding,
                        let startedAt
                    ):
                        self.queueStore.replaceJob(
                            at: jobIndex,
                            with:
                                self.niconicoLiveJobStateService
                                .starting(
                                    self.queueStore.jobs[jobIndex],
                                    output: output,
                                    transcoding: transcoding,
                                    startedAt: startedAt
                                )
                        )
                        self.persistQueue()
                    case .failure(
                        let cancelled,
                        let hasPartialOutput
                    ):
                        self.queueStore.replaceJob(
                            at: jobIndex,
                            with:
                                self.niconicoLiveJobStateService
                                .recordingFailure(
                                    self.queueStore.jobs[jobIndex],
                                    cancelled: cancelled,
                                    hasPartialOutput: hasPartialOutput
                                )
                        )
                        self.persistQueue()
                    case .completed(
                        let output,
                        let hadSeparateAudio,
                        let options,
                        let byteCount
                    ):
                        self.queueStore.replaceJob(
                            at: jobIndex,
                            with:
                                self.niconicoLiveJobStateService
                                .finishing(
                                    self.queueStore.jobs[jobIndex],
                                    output: output,
                                    hadSeparateAudio: hadSeparateAudio,
                                    options: options,
                                    byteCount: byteCount
                                )
                        )
                        await self.completeJob(at: jobIndex)
                    }
                }
            )
        )
    }

    private func downloadAndMux(
        videoAssets: [ResolvedAsset],
        audioAssets: [ResolvedAsset],
        folderName: String,
        outputFilename: String,
        root: URL,
        jobIndex: Int
    ) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        let workFolder = root.appendingPathComponent(
            ".\(folderName.sanitizedFilename(maxLength: 120))-\(UUID().uuidString)",
            isDirectory: true
        )
        let output = AppPaths.uniqueFileURL(
            in: root,
            filename: outputFilename
        )
        let transcodeOptions = ffmpegTranscodeOptionsForUse()
        try await mediaMuxCoordinator.execute(
            MediaMuxRequest(
                videoAssets: videoAssets,
                audioAssets: audioAssets,
                workFolder: workFolder,
                output: output,
                options: transcodeOptions
            ),
            operations: mediaMuxOperations(jobIndex: jobIndex) {
                event in
                switch event {
                case .preparingVideo:
                    guard self.queueStore.jobs.indices.contains(jobIndex) else {
                        return false
                    }
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.resolvedPackageJobStateService
                            .preparingDASHMux(
                                self.queueStore.jobs[jobIndex],
                                output: output
                            )
                    )
                    self.persistQueue()
                    return true
                case .preparingAudio:
                    if self.queueStore.jobs.indices.contains(jobIndex) {
                        self.queueStore.replaceJob(
                            at: jobIndex,
                            with:
                                self.resolvedPackageJobStateService
                                .preparingDASHAudio(self.queueStore.jobs[jobIndex])
                        )
                        self.persistQueue()
                    }
                    return true
                case .preparingFinalization(let transcoding):
                    guard self.queueStore.jobs.indices.contains(jobIndex) else {
                        return false
                    }
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.resolvedPackageJobStateService
                            .preparingDASHFinalization(
                                self.queueStore.jobs[jobIndex],
                                transcoding: transcoding
                            )
                    )
                    self.persistQueue()
                    return true
                case .completed(let output, let options):
                    guard self.queueStore.jobs.indices.contains(jobIndex) else {
                        return false
                    }
                    let metadata = self.queueStore.jobs[jobIndex].metadata
                    self.applyYouTubeUploadModificationDateIfNeeded(
                        to: output,
                        sourceURL: URL(
                            string: self.queueStore.jobs[jobIndex].source
                        ),
                        metadata: metadata
                    )
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.resolvedPackageJobStateService
                            .finishingDASHMux(
                                self.queueStore.jobs[jobIndex],
                                output: output,
                                options: options
                            )
                    )
                    await self.completeJob(at: jobIndex)
                    return true
                }
            }
        )
    }

    func downloadDirect(
        _ url: URL,
        jobIndex: Int,
        resolveHTMLMedia: Bool = true
    ) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        var url = url
        var hookedFilename: String?
        if let hooked = try await runSyntheticPythonDownloadHooks(
            sourceURL: url,
            title: (Self.directDownloadFilename(for: url) as NSString).deletingPathExtension,
            filename: Self.directDownloadFilename(for: url),
            metadata: ["type": "direct", "handler": "native"],
            jobIndex: jobIndex
        ) {
            if let hookedURL = URL(string: hooked.sourceURL.trimmed), !hooked.sourceURL.trimmed.isEmpty {
                url = hookedURL
            }
            hookedFilename = hooked.assets.first?.filename.trimmed
        }
        let root = try outputRoot(for: url)

        let provisionalName = hookedFilename?.isEmpty == false ? hookedFilename! : Self.directDownloadFilename(for: url)
        let provisionalOutputName = templatedFileName(
            original: provisionalName,
            title: (provisionalName as NSString).deletingPathExtension,
            sourceURL: url,
            index: 1,
            total: 1
        )

        let provisionalMetadata = Self.directDownloadMetadata(for: url, filename: provisionalName)
        queueStore.replaceJob(
            at: jobIndex,
            with:
                directTransferJobStateService
                .preparingDirectTransfer(
                    queueStore.jobs[jobIndex],
                    title: provisionalOutputName,
                    metadata: provisionalMetadata,
                    output: root.appendingPathComponent(
                        provisionalOutputName
                    )
                )
        )
        persistQueue()

        if await finishExistingSingleOutputIfNeeded(
            outputName: provisionalOutputName,
            root: root,
            metadata: provisionalMetadata,
            jobIndex: jobIndex
        ) {
            return
        }

        let headers = requestOptions(for: url)
        let headResponse = try? await HTTPClient.shared.head(from: url, referer: headers.referer, userAgent: headers.userAgent)
        let segmentDirective =
            queueStore.jobs.indices.contains(jobIndex)
            ? DirectSegmentPlanningService
                .directive(
                    from:
                        queueStore.jobs[jobIndex]
                        .comment
                )
            : nil
        if let headResponse,
           !LocalInputPreparationService
            .isHTMLResponse(headResponse),
           let splitSegments =
                DirectSegmentPlanningService
                .segments(
                    from: headResponse,
                    directive:
                        segmentDirective
                ) {
            let finalName = hookedFilename?.isEmpty == false ? hookedFilename! : Self.directDownloadFilename(for: url, response: headResponse)
            let outputName = templatedFileName(
                original: finalName,
                title: (finalName as NSString).deletingPathExtension,
                sourceURL: url,
                index: 1,
                total: 1
            )
            let metadata = Self.directDownloadMetadata(
                for: url,
                filename: finalName,
                response: headResponse,
                splitSegmentCount: splitSegments.count
            )
            if await finishExistingSingleOutputIfNeeded(outputName: outputName, root: root, metadata: metadata, jobIndex: jobIndex) {
                return
            }
            let destination = AppPaths.uniqueFileURL(in: root, filename: outputName)
            do {
                try await downloadDirectSegments(
                    url,
                    segments: splitSegments,
                    to: destination,
                    headers: headers,
                    jobIndex: jobIndex
                )

                if queueStore.jobs.indices.contains(jobIndex) {
                    queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            directTransferJobStateService
                            .finishingTransfer(
                                queueStore.jobs[jobIndex],
                                title: outputName,
                                output: destination,
                                metadata:
                                    Self.directDownloadMetadata(
                                        for: url,
                                        filename: finalName,
                                        response: headResponse,
                                        byteCount:
                                            splitSegments.last.map {
                                                $0.upperBound + 1
                                            },
                                        splitSegmentCount:
                                            splitSegments.count
                                    ),
                                completed: splitSegments.count
                            )
                    )
                    await completeJob(at: jobIndex)
                }
                return
            } catch {
                try? FileManager.default.removeItem(at: destination)
                if queueStore.jobs.indices.contains(jobIndex) {
                    queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            directTransferJobStateService
                            .restoringDirectTransfer(
                                queueStore.jobs[jobIndex],
                                title: provisionalOutputName,
                                metadata:
                                    Self.directDownloadMetadata(
                                        for: url,
                                        filename: provisionalName
                                    ),
                                output:
                                    root.appendingPathComponent(
                                        provisionalOutputName
                                    )
                            )
                    )
                    persistQueue()
                }
            }
        }

        if let headResponse,
           !LocalInputPreparationService
            .isHTMLResponse(headResponse) {
            let finalName = hookedFilename?.isEmpty == false ? hookedFilename! : Self.directDownloadFilename(for: url, response: headResponse)
            let outputName = templatedFileName(
                original: finalName,
                title: (finalName as NSString).deletingPathExtension,
                sourceURL: url,
                index: 1,
                total: 1
            )
            let metadata = Self.directDownloadMetadata(for: url, filename: finalName, response: headResponse)
            if await finishExistingSingleOutputIfNeeded(outputName: outputName, root: root, metadata: metadata, jobIndex: jobIndex) {
                return
            }
        }

        let temporary = root.appendingPathComponent(".direct-\(UUID().uuidString).download")
        defer {
            try? FileManager.default.removeItem(at: temporary)
        }

        let response = try await HTTPClient.shared.download(from: url, to: temporary, referer: headers.referer, userAgent: headers.userAgent)
        if resolveHTMLMedia,
           LocalInputPreparationService
            .isHTMLResponse(response),
           let data = try? Data(contentsOf: temporary),
           let html = String(data: data, encoding: .utf8),
           let resolved = GenericPageResolver.resolvedDownload(fromHTML: html, pageURL: url) {
            try await downloadResolved(resolved, sourceURL: url, jobIndex: jobIndex)
            return
        }

        let finalName = hookedFilename?.isEmpty == false ? hookedFilename! : Self.directDownloadFilename(for: url, response: response)
        let outputName = templatedFileName(
            original: finalName,
            title: (finalName as NSString).deletingPathExtension,
            sourceURL: url,
            index: 1,
            total: 1
        )
        let metadata = Self.directDownloadMetadata(for: url, filename: finalName, response: response, byteCount: try? temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize, splitSegmentCount: nil)
        if await finishExistingSingleOutputIfNeeded(outputName: outputName, root: root, metadata: metadata, jobIndex: jobIndex) {
            return
        }
        let destination = AppPaths.uniqueFileURL(in: root, filename: outputName)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: temporary, to: destination)

        if queueStore.jobs.indices.contains(jobIndex) {
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    directTransferJobStateService
                    .finishingTransfer(
                        queueStore.jobs[jobIndex],
                        title: outputName,
                        output: destination,
                        metadata:
                            Self.directDownloadMetadata(
                                for: url,
                                filename: finalName,
                                response: response,
                                byteCount:
                                    try? destination.resourceValues(
                                        forKeys: [.fileSizeKey]
                                    ).fileSize,
                                splitSegmentCount: nil
                            ),
                        completed: 1
                    )
            )
            await completeJob(at: jobIndex)
        }
    }

    func downloadLocalFile(_ url: URL, jobIndex: Int) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        let fileURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDirectory) else {
            throw NativeDownloadError.unsupported("Local file is unavailable.")
        }
        if isDirectory.boolValue {
            try await downloadLocalFolder(fileURL, jobIndex: jobIndex)
            return
        }

        if LocalInputPreparationService
            .isHTMLFile(fileURL),
           let html =
            LocalInputPreparationService
            .htmlString(from: fileURL),
           let resolved = GenericPageResolver.resolvedDownload(fromHTML: html, pageURL: fileURL) {
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    directTransferJobStateService
                    .preparingLocalHTMLScan(queueStore.jobs[jobIndex])
            )
            persistQueue()
            try await downloadResolved(resolved, sourceURL: fileURL, jobIndex: jobIndex)
            return
        }

        let root = try outputRoot(for: fileURL)
        let sourceFilename =
            LocalInputPreparationService
            .filename(for: fileURL)
        let originalFilename = Self.improvedOriginalLocalFilename(
            for: url,
            sourceFilename: sourceFilename
        )
        let originalMetadata =
            LocalInputPreparationService
            .fileMetadata(
                for: fileURL,
                filename: originalFilename
            )
        let hooked = try await runSyntheticPythonDownloadHooks(
            sourceURL: fileURL,
            title: (originalFilename as NSString).deletingPathExtension,
            filename: originalFilename,
            metadata: originalMetadata,
            jobIndex: jobIndex
        )
        let filename = hooked?.assets.first?.filename.trimmed.isEmpty == false
            ? hooked!.assets[0].filename.trimmed
            : originalFilename
        let basename = (filename as NSString).deletingPathExtension
        let metadata =
            LocalInputPreparationService
            .fileMetadata(
                for: fileURL,
                filename: filename
            )
        let outputName = templatedFileName(
            original: filename,
            title: basename,
            sourceURL: fileURL,
            index: 1,
            total: 1,
            metadata: metadata
        )
        let destination = AppPaths.uniqueFileURL(in: root, filename: outputName)

        queueStore.replaceJob(
            at: jobIndex,
            with:
                directTransferJobStateService
                .preparingLocalFileTransfer(
                    queueStore.jobs[jobIndex],
                    title: outputName,
                    metadata: metadata,
                    output: destination
                )
        )
        persistQueue()

        try FileManager.default.copyItem(at: fileURL, to: destination)

        if queueStore.jobs.indices.contains(jobIndex) {
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    directTransferJobStateService
                    .finishingTransfer(
                        queueStore.jobs[jobIndex],
                        metadata:
                            LocalInputPreparationService
                            .fileMetadata(
                                for: fileURL,
                                filename: filename,
                                byteCount:
                                    try? destination.resourceValues(
                                        forKeys: [.fileSizeKey]
                                    ).fileSize
                            ),
                        completed: 1
                    )
            )
            await completeJob(at: jobIndex)
        }
    }

    private func downloadLocalFolder(_ folderURL: URL, jobIndex: Int) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }

        let root = try outputRoot(for: folderURL)
        var folderName =
            LocalInputPreparationService
            .folderName(for: folderURL)
        let fileCount =
            LocalInputPreparationService
            .folderFileCount(in: folderURL)
        let metadata =
            LocalInputPreparationService
            .folderMetadata(
                for: folderURL,
                folderName: folderName,
                fileCount: fileCount
            )
        if let hooked = try await runSyntheticPythonDownloadHooks(
            sourceURL: folderURL,
            title: folderName,
            filename: folderName,
            metadata: metadata,
            jobIndex: jobIndex
        ), !hooked.title.trimmed.isEmpty {
            folderName = hooked.title.trimmed
        }
        let resolved = ResolvedDownload(
            title: folderName,
            folderName: folderName,
            assets: [],
            metadata: metadata
        )
        let outputFolderName = templatedFolderName(for: resolved, sourceURL: folderURL)
        let destination = AppPaths.uniqueDirectoryURL(in: root, name: outputFolderName)

        queueStore.replaceJob(
            at: jobIndex,
            with:
                directTransferJobStateService
                .preparingLocalFolderTransfer(
                    queueStore.jobs[jobIndex],
                    title: outputFolderName,
                    metadata: metadata,
                    output: destination,
                    fileCount: fileCount
                )
        )
        persistQueue()

        try AppPaths.ensureDirectory(destination.deletingLastPathComponent())
        try FileManager.default.copyItem(at: folderURL, to: destination)

        if queueStore.jobs.indices.contains(jobIndex) {
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    directTransferJobStateService
                    .finishingTransfer(
                        queueStore.jobs[jobIndex],
                        metadata:
                            LocalInputPreparationService
                            .folderMetadata(
                                for: folderURL,
                                folderName: folderName,
                                fileCount: fileCount
                            ),
                        completed: fileCount
                    )
            )
            await completeJob(at: jobIndex)
        }
    }

    @discardableResult
    func finishExistingSingleOutputIfNeeded(outputName: String, root: URL, metadata: [String: String], jobIndex: Int) async -> Bool {
        guard settingsStore.skipDuplicates,
              queueStore.jobs.indices.contains(jobIndex),
              Self.shouldSkipExistingSingleOutput(metadata),
              let existing = Self.existingOutputFileURL(in: root, filename: outputName) else {
            return false
        }

        queueStore.replaceJob(
            at: jobIndex,
            with:
                directTransferJobStateService
                .skippingExistingOutput(
                    queueStore.jobs[jobIndex],
                    output: existing,
                    metadata: metadata,
                    byteCount:
                        try? existing.resourceValues(
                            forKeys: [.fileSizeKey]
                        ).fileSize
                )
        )
        addSummary = "Skipped existing file"
        await completeJob(at: jobIndex)
        return true
    }

    nonisolated static func existingOutputFileURL(in directory: URL, filename: String, fileManager: FileManager = .default) -> URL? {
        let candidate = AppPaths.fileURL(in: directory, filename: filename)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: candidate.path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return nil
        }
        return candidate
    }

    private nonisolated static func shouldSkipExistingSingleOutput(_ metadata: [String: String]) -> Bool {
        let category = metadataValue(metadata, keys: ["category"]).lowercased()
        let type = metadataValue(metadata, keys: ["type"]).lowercased()
        guard type == "direct" || type == "local_file" else { return false }
        return category == "video"
    }

    private func downloadDirectSegments(_ url: URL, segments: [DirectSplitSegment], to destination: URL, headers: HTTPRequestOptions, jobIndex: Int) async throws {
        if queueStore.jobs.indices.contains(jobIndex) {
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    directTransferJobStateService
                    .preparingSegmentedTransfer(
                        queueStore.jobs[jobIndex],
                        output: destination,
                        segmentCount: segments.count
                    )
            )
            persistQueue()
        }

        try await directSegmentTransferService
            .download(
                url,
                segments: segments,
                to: destination,
                headers: headers,
                maximumConcurrentDownloads:
                    settingsStore.fileConcurrency,
                onProgress: { [weak self] _ in
                    guard let self,
                          self.queueStore.jobs.indices
                          .contains(jobIndex) else {
                        return
                    }
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.directTransferJobStateService
                            .recordingSegmentCompletion(
                                self.queueStore.jobs[jobIndex]
                            )
                    )
                    self.persistQueue()
                },
                onJoining: { [weak self] in
                    guard let self,
                          self.queueStore.jobs.indices
                          .contains(jobIndex) else {
                        return
                    }
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.directTransferJobStateService
                            .preparingSegmentJoin(
                                self.queueStore.jobs[jobIndex]
                            )
                    )
                    self.persistQueue()
                }
            )
    }

    nonisolated static func directDownloadFilename(for url: URL) -> String {
        DirectDownloadMetadataService.filename(
            for: url
        )
    }

    nonisolated static func directDownloadFilename(for url: URL, response: HTTPURLResponse?) -> String {
        DirectDownloadMetadataService.filename(
            for: url,
            response: response
        )
    }

    nonisolated static func directDownloadMetadata(for url: URL, filename: String, response: HTTPURLResponse? = nil, byteCount: Int? = nil, splitSegmentCount: Int? = nil) -> [String: String] {
        DirectDownloadMetadataService.metadata(
            for: url,
            filename: filename,
            response: response,
            byteCount: byteCount,
            splitSegmentCount:
                splitSegmentCount
        )
    }

    nonisolated static func improvedOriginalLocalFilename(for url: URL, sourceFilename: String) -> String {
        LocalInputPreparationService
            .improvedOriginalFilename(
                for: url,
                sourceFilename:
                    sourceFilename
            )
    }

    func downloadWithYTDLP(_ url: URL, jobIndex: Int) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        var url = url
        var title = url.host ?? "yt-dlp media"
        if let hooked = try await runSyntheticPythonDownloadHooks(
            sourceURL: url,
            title: title,
            metadata: YTDLPBridge.sourceMetadata(for: url).merging(["handler": "yt-dlp"]) { current, _ in current },
            jobIndex: jobIndex
        ) {
            if let hookedURL = URL(string: hooked.sourceURL.trimmed), !hooked.sourceURL.trimmed.isEmpty {
                url = hookedURL
            }
            if !hooked.title.trimmed.isEmpty {
                title = hooked.title.trimmed
            }
        }
        let root = try outputRoot(for: url)
        let audioFormat = DownloadRequestIdentityService.ytdlpAudioFormat(
            from: queueStore.jobs[jobIndex].metadata
        )
        let jobID = queueStore.jobs[jobIndex].id
        try await externalToolRuntime.withProcessExecution(
            for: jobID,
            kind: .ytdlp
        ) { processControl in
            ytdlpProgressUpdateService.beginTracking(
                jobID: jobID
            )
            defer {
                ytdlpProgressUpdateService.endTracking(
                    jobID: jobID
                )
                if let currentIndex = queueStore.jobs.firstIndex(where: { $0.id == jobID }) {
                    queueStore.replaceJob(
                        at: currentIndex,
                        with:
                            ytdlpJobStateService.clearingRuntimeState(
                                queueStore.jobs[currentIndex]
                            )
                    )
                }
            }

            queueStore.replaceJob(
                at: jobIndex,
                with:
                    ytdlpJobStateService.starting(
                        queueStore.jobs[jobIndex],
                        title: title,
                        audioFormat: audioFormat
                    )
            )
            persistQueue()
            let progressHandler =
                ytdlpProgressDeliveryService.handler(
                    jobID: jobID
                ) { [weak self] update, updateJobID in
                    self?.applyYTDLPRuntimeUpdate(
                        update,
                        jobID: updateJobID
                    )
                }

            let rawResult = try await externalToolRuntime.executeYTDLPDownload(
                url: url,
                root: root,
                headers: requestOptions(for: url),
                youtubePreferredLanguage: settingsStore.youtubePreferredLanguage,
                youtubePreferredResolution: settingsStore.youtubePreferredResolution,
                youtubePreferredAudioLanguage: settingsStore.youtubePreferredAudioLanguage,
                soopPreferredResolution: settingsStore.soopPreferredResolution,
                extractAudioFormat: audioFormat,
                writeYouTubeThumbnail: settingsStore.youtubeDownloadThumbnail,
                reverseYouTubePlaylist: settingsStore.youtubeReversePlaylist,
                numberPlaylistFiles: settingsStore.numberPlaylistFiles,
                writeYouTubeAutoSubtitles: settingsStore.youtubeDownloadAutoSubtitles,
                youtubeSubtitleLanguages: settingsStore.youtubeSubtitleLanguages,
                embedYouTubeChapters: settingsStore.youtubeEmbedChapters,
                youtubeVideoCodecSort: settingsStore.youtubeVideoCodecSort,
                preferYouTubeEnhancedBitrate: settingsStore.youtubePreferEnhancedBitrate,
                useYouTubeUploadDateForFileModificationTime: settingsStore.youtubeUseUploadDateForFileModificationTime,
                processControl: processControl,
                progressHandler: progressHandler
            )
            let result = try applyYTDLPFileTemplate(to: rawResult, sourceURL: url)
            let output = result.downloadedItems.count == 1 ? result.downloadedItems[0] : result.outputDirectory

            if queueStore.jobs.indices.contains(jobIndex) {
                let metadata =
                    externalToolOutputMetadataService.ytdlpMetadata(
                        for: url,
                        title: output.lastPathComponent,
                        result: result
                    )
                queueStore.replaceJob(
                    at: jobIndex,
                    with:
                        ytdlpJobStateService.finishing(
                            queueStore.jobs[jobIndex],
                            output: output,
                            metadata: metadata,
                            audioFormat: audioFormat,
                            wasInterrupted: result.wasInterrupted
                        )
                )
                await completeJob(at: jobIndex)
            }
        }
    }

    private func applyYTDLPRuntimeUpdate(_ update: YTDLPRuntimeUpdate, jobID: UUID) {
        guard queueStore.isQueueEnabled,
              let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[index].status == .downloading else { return }

        let snapshot =
            ytdlpProgressUpdateService.snapshot(
                applying: update,
                jobID: jobID
            )

        if let liveJob =
            ytdlpProgressUpdateService.applyingLiveMetadata(
                update,
                to: queueStore.jobs[index]
            ) {
            queueStore.replaceJob(at: index, with: liveJob)
            persistQueue()
        }
        queueStore.replaceJob(
            at: index,
            with:
                ytdlpProgressUpdateService.applyingTransferMetadata(
                    update,
                    snapshot: snapshot,
                    to: queueStore.jobs[index],
                    interfaceLanguage: settingsStore.interfaceLanguage
                )
        )
    }

    func downloadWithCustomCommand(_ url: URL, rule: SiteRule, jobIndex: Int) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        var url = url
        if let hooked = try await runSyntheticPythonDownloadHooks(
            sourceURL: url,
            title: rule.name,
            metadata: ["type": "command", "handler": rule.handler.rawValue, "rule": rule.name],
            jobIndex: jobIndex
        ), let hookedURL = URL(string: hooked.sourceURL.trimmed), !hooked.sourceURL.trimmed.isEmpty {
            url = hookedURL
        }
        let root = try outputRoot(for: url)

        queueStore.replaceJob(
            at: jobIndex,
            with:
                customCommandJobStateService.starting(
                    queueStore.jobs[jobIndex],
                    ruleName: rule.name
                )
        )
        persistQueue()

        let rawResult = try await externalToolRuntime.executeCustomCommand(
            url: url,
            rule: rule,
            root: root,
            headers: requestOptions(for: url)
        )
        let rawOutput = rawResult.outputItems.count == 1 ? rawResult.outputItems[0] : rawResult.outputDirectory
        let declaredTitle = [rawResult.manifestTitle, rawResult.manifestMetadata["title"]]
            .compactMap { $0?.trimmed }
            .first { !$0.isEmpty }
        let title = declaredTitle ?? rawOutput.lastPathComponent
        let folderedResult = try applyCustomCommandFolderTemplate(to: rawResult, root: root, sourceURL: url, title: title, rule: rule)
        let localResult = try applyCustomCommandFileTemplate(to: folderedResult, sourceURL: url, title: title, rule: rule)
        let result = try await downloadCustomCommandRemoteAssets(localResult, sourceURL: url, title: title, rule: rule, jobIndex: jobIndex)
        let output = result.outputItems.count == 1 ? result.outputItems[0] : result.outputDirectory

        if queueStore.jobs.indices.contains(jobIndex) {
            let metadata =
                externalToolOutputMetadataService.customCommandMetadata(
                    for: url,
                    rule: rule,
                    title: title,
                    result: result
                )
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    customCommandJobStateService.finishing(
                        queueStore.jobs[jobIndex],
                        title: title,
                        output: output,
                        metadata: metadata
                    )
            )
            await completeJob(at: jobIndex)
        }
    }

    func downloadWithAria2(_ url: URL, jobIndex: Int) async throws {
        guard queueStore.jobs.indices.contains(jobIndex) else { return }
        var url = url
        var title = url.scheme?.lowercased() == "magnet" ? "Magnet" : url.lastPathComponent
        if let hooked = try await runSyntheticPythonDownloadHooks(
            sourceURL: url,
            title: title.isEmpty ? "Torrent" : title,
            filename: url.lastPathComponent,
            metadata: ["type": url.scheme?.lowercased() == "magnet" ? "magnet" : "torrent", "handler": "aria2"],
            jobIndex: jobIndex
        ) {
            if let hookedURL = URL(string: hooked.sourceURL.trimmed), !hooked.sourceURL.trimmed.isEmpty {
                url = hookedURL
            }
            if !hooked.title.trimmed.isEmpty {
                title = hooked.title.trimmed
            }
        }
        let root = try outputRoot(for: url)
        let jobID = queueStore.jobs[jobIndex].id
        try await externalToolRuntime.withAria2Execution(for: jobID) { processControl, rpcSession in
            aria2Store.setRuntimePaused(false, jobID: jobID)
            defer {
                aria2Store.setRuntimePaused(false, jobID: jobID)
            }

            let options = Self.aria2Options(base: aria2OptionsForUse(), comment: queueStore.jobs[jobIndex].comment)
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    aria2JobStateService.starting(
                        queueStore.jobs[jobIndex],
                        title: title,
                        options: options,
                        hasRPCSession: rpcSession != nil
                    )
            )
            persistQueue()
            let result = try await externalToolRuntime.executeAria2Download(
                url: url,
                root: root,
                headers: requestOptions(for: url),
                options: options,
                processControl: processControl,
                rpcSession: rpcSession
            )
            let output = result.downloadedItems.count == 1 ? result.downloadedItems[0] : result.outputDirectory

            if queueStore.jobs.indices.contains(jobIndex) {
                let metadata =
                    externalToolOutputMetadataService.aria2Metadata(
                        for: url,
                        title: output.lastPathComponent,
                        result: result,
                        options: options
                    )
                queueStore.replaceJob(
                    at: jobIndex,
                    with:
                        aria2JobStateService.finishing(
                            queueStore.jobs[jobIndex],
                            output: output,
                            metadata: metadata,
                            options: options
                        )
                )
                await completeJob(at: jobIndex)
            }
        }
    }

    private func applyYTDLPFileTemplate(to result: YTDLPResult, sourceURL: URL) throws -> YTDLPResult {
        let metadata = DownloadMetadata.clean(
            YTDLPBridge.sourceMetadata(for: sourceURL)
                .merging(result.infoMetadata) { _, infoValue in infoValue }
        )
        let template = effectiveFileNameTemplate(for: sourceURL, metadata: metadata)
        guard !template.isEmpty, !result.downloadedItems.isEmpty else {
            return result
        }

        let total = result.downloadedItems.count
        let renamed = try result.downloadedItems.enumerated().map { offset, item in
            let original = item.lastPathComponent
            let fallbackTitle = (original as NSString).deletingPathExtension
            let title = metadata["media_title"] ?? metadata["title"] ?? fallbackTitle
            let outputName = templatedFileName(
                original: original,
                title: title,
                sourceURL: sourceURL,
                index: offset + 1,
                total: total,
                metadata: metadata
            )
            guard outputName != original else {
                return item
            }

            let destination = AppPaths.uniqueFileURL(in: item.deletingLastPathComponent(), filename: outputName)
            try FileManager.default.moveItem(at: item, to: destination)
            return destination
        }

        return YTDLPResult(
            outputDirectory: result.outputDirectory,
            downloadedItems: renamed,
            infoMetadata: result.infoMetadata,
            wasInterrupted: result.wasInterrupted
        )
    }

    private func applyCustomCommandFolderTemplate(to result: CustomCommandResult, root: URL, sourceURL: URL, title: String, rule: SiteRule) throws -> CustomCommandResult {
        let template = settingsStore.folderNameTemplate.trimmed
        let rawFolderName = result.manifestFolderName?.trimmed
        let explicitFolderName = rawFolderName?.isEmpty == false ? rawFolderName : nil
        guard !template.isEmpty || explicitFolderName != nil else {
            return result
        }

        var metadata = result.manifestMetadata
        metadata["title"] = metadata["title"] ?? title
        metadata["series"] = metadata["series"] ?? title
        metadata["tool"] = "custom-command"
        metadata["handler"] = rule.handler.rawValue
        metadata["rule"] = rule.name
        metadata["rule_host"] = rule.hostSuffix
        metadata["rule_pattern"] = rule.urlPattern ?? ""

        let targetName: String
        if !template.isEmpty {
            let context = nameTemplateContext(
                title: title,
                sourceURL: sourceURL,
                filename: explicitFolderName ?? result.outputDirectory.lastPathComponent,
                index: nil,
                total: result.outputItems.count,
                metadata: metadata
            )
            targetName = NameTemplate.folderName(
                template: template,
                fallback: explicitFolderName ?? result.outputDirectory.lastPathComponent,
                context: context
            )
        } else {
            targetName = (explicitFolderName ?? result.outputDirectory.lastPathComponent).sanitizedFilename(maxLength: 120)
        }

        guard !targetName.trimmed.isEmpty,
              targetName != result.outputDirectory.lastPathComponent else {
            return result
        }

        let oldDirectory = result.outputDirectory
        let oldResolved = oldDirectory.resolvingSymlinksInPath()
        let oldPrefix = oldResolved.path.hasSuffix("/") ? oldResolved.path : oldResolved.path + "/"
        let destination = AppPaths.uniqueDirectoryURL(in: root, name: targetName)
        try AppPaths.ensureDirectory(destination.deletingLastPathComponent())
        let remappedItems = result.outputItems.map { item -> URL in
            let resolved = item.resolvingSymlinksInPath()
            guard resolved.path.hasPrefix(oldPrefix) else {
                return destination.appendingPathComponent(item.lastPathComponent)
            }
            let relativePath = String(resolved.path.dropFirst(oldPrefix.count))
            return destination.appendingPathComponent(relativePath)
        }

        try FileManager.default.moveItem(at: oldDirectory, to: destination)
        return CustomCommandResult(
            outputDirectory: destination,
            outputItems: remappedItems,
            remoteAssets: result.remoteAssets,
            remoteVideoAssets: result.remoteVideoAssets,
            remoteAudioAssets: result.remoteAudioAssets,
            remotePackageMode: result.remotePackageMode,
            manifestTitle: result.manifestTitle,
            manifestFolderName: result.manifestFolderName,
            manifestMetadata: result.manifestMetadata
        )
    }

    private func applyCustomCommandFileTemplate(to result: CustomCommandResult, sourceURL: URL, title: String, rule: SiteRule) throws -> CustomCommandResult {
        var metadata = result.manifestMetadata
        metadata["title"] = metadata["title"] ?? title
        metadata["series"] = metadata["series"] ?? title
        metadata["tool"] = "custom-command"
        metadata["handler"] = rule.handler.rawValue
        metadata["rule"] = rule.name
        metadata["rule_host"] = rule.hostSuffix
        metadata["rule_pattern"] = rule.urlPattern ?? ""
        let template = effectiveFileNameTemplate(for: sourceURL, metadata: metadata)
        guard !template.isEmpty, !result.outputItems.isEmpty else {
            return result
        }

        let total = result.outputItems.count
        let renamed = try result.outputItems.enumerated().map { offset, item in
            let outputName = templatedFileName(
                original: item.lastPathComponent,
                title: title,
                sourceURL: sourceURL,
                index: offset + 1,
                total: total,
                metadata: metadata
            )
            guard outputName != item.lastPathComponent else {
                return item
            }

            let destination = AppPaths.uniqueFileURL(in: item.deletingLastPathComponent(), filename: outputName)
            try FileManager.default.moveItem(at: item, to: destination)
            return destination
        }

        return CustomCommandResult(
            outputDirectory: result.outputDirectory,
            outputItems: renamed,
            remoteAssets: result.remoteAssets,
            remoteVideoAssets: result.remoteVideoAssets,
            remoteAudioAssets: result.remoteAudioAssets,
            remotePackageMode: result.remotePackageMode,
            manifestTitle: result.manifestTitle,
            manifestFolderName: result.manifestFolderName,
            manifestMetadata: result.manifestMetadata
        )
    }

    private func customCommandTemplateMetadata(for result: CustomCommandResult, title: String, rule: SiteRule) -> [String: String] {
        var metadata = result.manifestMetadata
        metadata["title"] = metadata["title"] ?? title
        metadata["series"] = metadata["series"] ?? title
        metadata["tool"] = "custom-command"
        metadata["handler"] = rule.handler.rawValue
        metadata["rule"] = rule.name
        metadata["rule_host"] = rule.hostSuffix
        metadata["rule_pattern"] = rule.urlPattern ?? ""
        return DownloadMetadata.clean(metadata)
    }

    private func downloadCustomCommandRemoteAssets(_ result: CustomCommandResult, sourceURL: URL, title: String, rule: SiteRule, jobIndex: Int) async throws -> CustomCommandResult {
        guard !result.remoteAssets.isEmpty || !result.remoteVideoAssets.isEmpty || !result.remoteAudioAssets.isEmpty else {
            return result
        }

        switch result.remotePackageMode {
        case .files:
            return try await downloadCustomCommandRemoteFiles(result, sourceURL: sourceURL, title: title, rule: rule, jobIndex: jobIndex)
        case .concatenate(let outputFilename):
            return try await downloadCustomCommandRemoteConcatenate(result, outputFilename: outputFilename, sourceURL: sourceURL, title: title, rule: rule, jobIndex: jobIndex)
        case .mux(let outputFilename):
            return try await downloadCustomCommandRemoteMux(result, outputFilename: outputFilename, sourceURL: sourceURL, title: title, rule: rule, jobIndex: jobIndex)
        }
    }

    private func downloadCustomCommandRemoteFiles(_ result: CustomCommandResult, sourceURL: URL, title: String, rule: SiteRule, jobIndex: Int) async throws -> CustomCommandResult {
        let localCount = result.outputItems.count
        let total = localCount + result.remoteAssets.count
        let metadata = customCommandTemplateMetadata(for: result, title: title, rule: rule)
        let assets = result.remoteAssets.enumerated().map { offset, asset -> ResolvedAsset in
            var copy = asset
            let outputName = templatedFileName(
                original: asset.filename,
                title: title,
                sourceURL: sourceURL,
                index: localCount + offset + 1,
                total: total,
                metadata: metadata
            )
            copy.filename = outputName
            return assetWithHeaderRules(copy)
        }

        if queueStore.jobs.indices.contains(jobIndex) {
            let outputMetadata =
                externalToolOutputMetadataService.customCommandMetadata(
                    for: sourceURL,
                    rule: rule,
                    title: title,
                    result: result
                )
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    customCommandJobStateService.preparingRemoteAssets(
                        queueStore.jobs[jobIndex],
                        title: title,
                        metadata: outputMetadata,
                        total: assets.count,
                        message:
                            "Downloading \(assets.count) manifest assets",
                        output: result.outputDirectory
                    )
            )
            persistQueue()
        }

        let downloadedItems = try await downloadAssets(assets, to: result.outputDirectory, jobIndex: jobIndex)
        return CustomCommandResult(
            outputDirectory: result.outputDirectory,
            outputItems: result.outputItems + downloadedItems,
            remoteAssets: [],
            remoteVideoAssets: [],
            remoteAudioAssets: [],
            remotePackageMode: .files,
            manifestTitle: result.manifestTitle,
            manifestFolderName: result.manifestFolderName,
            manifestMetadata: result.manifestMetadata
        )
    }

    private func downloadCustomCommandRemoteConcatenate(_ result: CustomCommandResult, outputFilename: String, sourceURL: URL, title: String, rule: SiteRule, jobIndex: Int) async throws -> CustomCommandResult {
        let metadata = customCommandTemplateMetadata(for: result, title: title, rule: rule)
        let outputName = templatedFileName(
            original: outputFilename,
            title: title,
            sourceURL: sourceURL,
            index: nil,
            total: result.remoteAssets.count,
            metadata: metadata
        )
        let output = AppPaths.uniqueFileURL(in: result.outputDirectory, filename: outputName)
        let tempFolder = result.outputDirectory.appendingPathComponent(".manifest-concat-\(UUID().uuidString)", isDirectory: true)
        try AppPaths.ensureDirectory(tempFolder)

        let assets = result.remoteAssets.enumerated().map { offset, asset -> ResolvedAsset in
            var copy = asset
            let safeName = asset.filename.sanitizedFilename(maxLength: 150)
            copy.filename = String(format: "%05d-%@", offset + 1, safeName)
            return assetWithHeaderRules(copy)
        }

        if queueStore.jobs.indices.contains(jobIndex) {
            let outputMetadata =
                externalToolOutputMetadataService.customCommandMetadata(
                    for: sourceURL,
                    rule: rule,
                    title: title,
                    result: result
                )
            queueStore.replaceJob(
                at: jobIndex,
                with:
                    customCommandJobStateService.preparingRemoteAssets(
                        queueStore.jobs[jobIndex],
                        title: title,
                        metadata: outputMetadata,
                        total: assets.count,
                        message:
                            "Downloading \(assets.count) manifest segments",
                        output: result.outputDirectory
                    )
            )
            persistQueue()
        }

        try await downloadAndConcatenate(assets, tempFolder: tempFolder, output: output, jobIndex: jobIndex)
        return CustomCommandResult(
            outputDirectory: result.outputDirectory,
            outputItems: result.outputItems + [output],
            remoteAssets: [],
            remoteVideoAssets: [],
            remoteAudioAssets: [],
            remotePackageMode: result.remotePackageMode,
            manifestTitle: result.manifestTitle,
            manifestFolderName: result.manifestFolderName,
            manifestMetadata: result.manifestMetadata
        )
    }

    private func downloadCustomCommandRemoteMux(_ result: CustomCommandResult, outputFilename: String, sourceURL: URL, title: String, rule: SiteRule, jobIndex: Int) async throws -> CustomCommandResult {
        guard !result.remoteVideoAssets.isEmpty else {
            throw NativeDownloadError.unsupported("Custom command manifest mux mode requires video assets.")
        }
        guard !result.remoteAudioAssets.isEmpty else {
            throw NativeDownloadError.unsupported("Custom command manifest mux mode requires audio assets.")
        }

        let metadata = customCommandTemplateMetadata(for: result, title: title, rule: rule)
        let totalAssets = result.remoteVideoAssets.count + result.remoteAudioAssets.count
        let outputName = templatedFileName(
            original: outputFilename,
            title: title,
            sourceURL: sourceURL,
            index: nil,
            total: totalAssets,
            metadata: metadata
        )
        let output = AppPaths.uniqueFileURL(in: result.outputDirectory, filename: outputName)
        let workFolder = result.outputDirectory.appendingPathComponent(".manifest-mux-\(UUID().uuidString)", isDirectory: true)

        let videoAssets = result.remoteVideoAssets.enumerated().map { offset, asset -> ResolvedAsset in
            var copy = asset
            let safeName = asset.filename.sanitizedFilename(maxLength: 150)
            copy.filename = String(format: "%05d-%@", offset + 1, safeName)
            return assetWithHeaderRules(copy)
        }
        let audioAssets = result.remoteAudioAssets.enumerated().map { offset, asset -> ResolvedAsset in
            var copy = asset
            let safeName = asset.filename.sanitizedFilename(maxLength: 150)
            copy.filename = String(format: "%05d-%@", offset + 1, safeName)
            return assetWithHeaderRules(copy)
        }

        let transcodeOptions = ffmpegTranscodeOptionsForUse()
        try await mediaMuxCoordinator.execute(
            MediaMuxRequest(
                videoAssets: videoAssets,
                audioAssets: audioAssets,
                workFolder: workFolder,
                output: output,
                options: transcodeOptions
            ),
            operations: mediaMuxOperations(jobIndex: jobIndex) {
                event in
                guard self.queueStore.jobs.indices.contains(jobIndex) else {
                    return true
                }
                switch event {
                case .preparingVideo:
                    let outputMetadata =
                        self.externalToolOutputMetadataService
                        .customCommandMetadata(
                            for: sourceURL,
                            rule: rule,
                            title: title,
                            result: result
                        )
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.customCommandJobStateService
                            .preparingRemoteAssets(
                                self.queueStore.jobs[jobIndex],
                                title: title,
                                metadata: outputMetadata,
                                total: totalAssets,
                                message: "Downloading manifest video",
                                output: output
                            )
                    )
                case .preparingAudio:
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.customCommandJobStateService
                            .updatingMessage(
                                self.queueStore.jobs[jobIndex],
                                message: "Downloading manifest audio"
                            )
                    )
                case .preparingFinalization(let transcoding):
                    let message = transcoding
                        ? "Muxing and transcoding manifest audio/video"
                        : "Muxing manifest audio and video"
                    self.queueStore.replaceJob(
                        at: jobIndex,
                        with:
                            self.customCommandJobStateService
                            .updatingMessage(
                                self.queueStore.jobs[jobIndex],
                                message: message
                            )
                    )
                case .completed:
                    break
                }
                self.persistQueue()
                return true
            }
        )

        var manifestMetadata = result.manifestMetadata
        manifestMetadata["muxed"] = "true"
        manifestMetadata["postprocess"] = transcodeOptions.enabled ? "ffmpeg-transcode" : "ffmpeg-mux"
        if transcodeOptions.enabled {
            manifestMetadata["transcoded"] = "true"
            for (key, value) in transcodeOptions.metadata {
                manifestMetadata[key] = value
            }
        }

        return CustomCommandResult(
            outputDirectory: result.outputDirectory,
            outputItems: result.outputItems + [output],
            remoteAssets: [],
            remoteVideoAssets: [],
            remoteAudioAssets: [],
            remotePackageMode: result.remotePackageMode,
            manifestTitle: result.manifestTitle,
            manifestFolderName: result.manifestFolderName,
            manifestMetadata: manifestMetadata
        )
    }

    nonisolated static func ytdlpMetadata(for url: URL, title: String, result: YTDLPResult) -> [String: String] {
        ExternalToolOutputMetadataService().ytdlpMetadata(
            for: url,
            title: title,
            result: result
        )
    }

    nonisolated static func customCommandMetadata(for url: URL, rule: SiteRule, title: String, result: CustomCommandResult) -> [String: String] {
        ExternalToolOutputMetadataService().customCommandMetadata(
            for: url,
            rule: rule,
            title: title,
            result: result
        )
    }

    nonisolated static func aria2Metadata(for url: URL, title: String, result: Aria2Result, options: Aria2Options = .defaults) -> [String: String] {
        ExternalToolOutputMetadataService().aria2Metadata(
            for: url,
            title: title,
            result: result,
            options: options
        )
    }

    private func markCancelled(_ index: Int, persist: Bool = true) {
        guard queueStore.jobs.indices.contains(index) else { return }
        let jobID = queueStore.jobs[index].id
        if !Self.isPendingQueueRemoval(queueStore.jobs[index]),
           let snapshot = downloadCoordinator.retrySnapshot(for: jobID),
           queueStore.jobs[index].status == .queued || queueStore.jobs[index].status == .resolving {
            queueStore.replaceJob(
                at: index,
                with: restoredRetrySnapshot(snapshot)
            )
            downloadCoordinator.removeRetrySnapshot(for: jobID)
            if persist {
                persistQueue()
            }
            return
        }

        downloadCoordinator.removeRetrySnapshot(for: jobID)
        queueStore.replaceJob(
            at: index,
            with:
                downloadExecutionJobStateService.cancelling(
                    queueStore.jobs[index]
                )
        )
        if persist {
            persistQueue()
        }
    }

    private func markFailed(
        _ index: Int,
        message: String,
        reaction: String? = nil,
        allowsIncompleteRetry: Bool = true
    ) {
        guard queueStore.jobs.indices.contains(index) else { return }
        downloadCoordinator.markJobFailed(queueStore.jobs[index].id)
        recordActivity("Failed: \(queueStore.jobs[index].title) - \(message)", category: "Download")
        queueStore.replaceJob(
            at: index,
            with:
                downloadExecutionJobStateService.failing(
                    queueStore.jobs[index],
                    message: message,
                    reaction: reaction
                )
        )
        if Self.isPendingQueueRemoval(queueStore.jobs[index]) {
            persistQueue()
            return
        }
        if scheduleFailureRetryIfNeeded(at: index, allowsIncompleteRetry: allowsIncompleteRetry) {
            return
        }
        persistQueue()
    }

    @discardableResult
    private func scheduleFailureRetryIfNeeded(
        at index: Int,
        allowsIncompleteRetry: Bool
    ) -> Bool {
        guard queueStore.jobs.indices.contains(index) else { return false }
        let now = Date().timeIntervalSince1970
        if let releaseTarget = Self.releaseRetryTimestamp(for: queueStore.jobs[index]),
           releaseTarget > now - 0.5 {
            return scheduleRetry(
                for: queueStore.jobs[index].id,
                at: releaseTarget,
                kind: .release,
                force: true,
                delay: nil,
                announce: true,
                persist: true
            )
        }
        guard allowsIncompleteRetry, settingsStore.retryIncompleteAutomatically else { return false }
        return scheduleRetry(
            for: queueStore.jobs[index].id,
            at: now + settingsStore.incompleteRetryDelay.seconds,
            kind: .incomplete,
            force: false,
            delay: settingsStore.incompleteRetryDelay.seconds,
            announce: true,
            persist: true
        )
    }

    nonisolated static func failureAllowsIncompleteRetry(_ error: Error) -> Bool {
        DownloadRetryPolicy.failureAllowsIncompleteRetry(error)
    }

    private nonisolated static func releaseRetryTimestamp(for job: DownloadJob) -> TimeInterval? {
        DownloadRetryPolicy.releaseRetryTimestamp(for: job)
    }

#if TESTING
    func testingFailJob(_ jobID: UUID, error: Error) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }) else { return }
        markFailed(
            index,
            message: AppLocalization.errorText(error),
            allowsIncompleteRetry: Self.failureAllowsIncompleteRetry(error)
        )
    }

    func testingCancelScheduledRetry(_ jobID: UUID) {
        cancelScheduledRestart(for: jobID)
        persistQueue()
    }
#endif

    @discardableResult
    private func queueRecordingAutoRetryIfNeeded(at index: Int, error: Error) -> Bool {
        guard queueStore.jobs.indices.contains(index),
              !Self.isPendingQueueRemoval(queueStore.jobs[index]),
              Self.shouldAutoRetryRecordingFailure(job: queueStore.jobs[index]) else {
            return false
        }

        let currentRetryCount =
            downloadExecutionJobStateService.recordingRetryCount(
                from: queueStore.jobs[index].metadata
            )
        guard currentRetryCount < Self.maxRecordingAutoRetryCount else {
            return false
        }

        let nextRetryCount = currentRetryCount + 1
        let jobID = queueStore.jobs[index].id
        cancelScheduledRestart(for: jobID)
        downloadCoordinator.removeRetrySnapshot(for: jobID)
        downloadCoordinator.resetOutcome(for: jobID)

        let errorText = AppLocalization.errorText(error)
        queueStore.replaceJob(
            at: index,
            with:
                downloadExecutionJobStateService
                .queuingRecordingRetry(
                    queueStore.jobs[index],
                    nextRetryCount: nextRetryCount,
                    maximumRetryCount:
                        Self.maxRecordingAutoRetryCount,
                    errorText: errorText,
                    retryTimestamp:
                        ISO8601DateFormatter().string(
                            from: Date()
                        )
                )
        )
        addSummary = "Recording retry queued"
        persistQueue()
        return true
    }

    private nonisolated static let maxRecordingAutoRetryCount = 1

    nonisolated static func resolvedMetadataPreservingRuntimeState(
        _ resolved: [String: String],
        previous: [String: String]
    ) -> [String: String] {
        ResolvedDownloadJobPreparationService
            .resolvedMetadataPreservingRuntimeState(
                resolved,
                previous: previous
            )
    }

    nonisolated static func shouldAutoRetryRecordingFailure(job: DownloadJob) -> Bool {
        let cleaned = DownloadMetadata.clean(job.metadata)
        if shouldUseRecordingFileNameTemplate(
            packageMode: .concatenate(outputFilename: ""),
            metadata: cleaned
        ) {
            return true
        }

        let source = job.source.lowercased()
        if source.contains(".m3u8") || source.contains("/live") {
            return true
        }

        let retryMarkers = [
            cleaned["auto_record"],
            cleaned["record"],
            cleaned["recording"],
            cleaned["live"]
        ].compactMap { $0?.lowercased() }

        return retryMarkers.contains { value in
            ["1", "true", "yes", "on", "live", "record", "recording"].contains(value)
        }
    }

    private func extractURLs(from text: String) -> [String] {
        text
            .components(separatedBy: .newlines)
            .flatMap { line -> [String] in
                let trimmedLine = line.trimmed
                if let hitomiURL = Self.hitomiCustomURIString(from: Self.cleanedClipboardToken(trimmedLine)) {
                    return [hitomiURL]
                }
                if let sankakuURL = Self.sankakuTagInputURLString(from: trimmedLine) {
                    return [sankakuURL]
                }
                if let booruURL = Self.booruTagInputURLString(from: trimmedLine) {
                    return [booruURL]
                }
                if let searchURL = quickSearchURLString(from: trimmedLine) {
                    return [searchURL]
                }
                return trimmedLine
                    .components(separatedBy: .whitespacesAndNewlines)
                    .map(Self.normalizedInputToken)
            }
            .filter { !$0.isEmpty }
    }

    private func extractMonitorableURLs(from text: String) -> [String] {
        extractURLs(from: text)
            .map(Self.cleanedClipboardToken)
            .filter(Self.isMonitorableURL)
    }

    private func inputItems(
        from text: String,
        monitorableOnly: Bool = false
    ) -> [(url: String, metadata: [String: String])] {
        if let task = OriginalBrowserExtensionTask.parse(text),
           let item = inputItem(from: task, monitorableOnly: monitorableOnly) {
            return [item]
        }
        if text.hasPrefix(OriginalBrowserExtensionTask.header) {
            return []
        }

        return text.components(separatedBy: .newlines).flatMap { line in
            if let task = OriginalBrowserExtensionTask.parse(line),
               let item = inputItem(from: task, monitorableOnly: monitorableOnly) {
                return [item]
            }
            if line.hasPrefix(OriginalBrowserExtensionTask.header) {
                return []
            }
            if let overrideItems = originalInputTypeOverrideItems(
                from: line,
                monitorableOnly: monitorableOnly
            ) {
                return overrideItems
            }
            return extractURLs(from: line).compactMap { raw -> (url: String, metadata: [String: String])? in
                let url = monitorableOnly ? Self.cleanedClipboardToken(raw) : raw
                guard !monitorableOnly || Self.isMonitorableURL(url) else { return nil }
                return (url, [:])
            }
        }
    }

    private func originalInputTypeOverrideItems(
        from line: String,
        monitorableOnly: Bool
    ) -> [(url: String, metadata: [String: String])]? {
        let tokens = line.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }
        guard tokens.contains(where: { OriginalInputType.prefixedInput(from: $0) != nil }) else {
            return nil
        }

        return tokens.compactMap { token -> (url: String, metadata: [String: String])? in
            let override = OriginalInputType.prefixedInput(from: token)
            let normalized = override.map {
                Self.normalizedOriginalInputPayload($0.payload, type: $0.type)
            } ?? Self.normalizedInputToken(token)
            let url = monitorableOnly ? Self.cleanedClipboardToken(normalized) : normalized
            guard !url.isEmpty,
                  !monitorableOnly || Self.isMonitorableURL(url) else {
                return nil
            }
            let metadata = override.map { [OriginalInputType.metadataKey: $0.type.rawValue] } ?? [:]
            return (url, metadata)
        }
    }

    private nonisolated static func normalizedOriginalInputPayload(
        _ payload: String,
        type: OriginalInputType
    ) -> String {
        let token = cleanedClipboardToken(payload.trimmed)
        guard !token.isEmpty else { return "" }

        if token.range(of: #"^[0-9]+$"#, options: .regularExpression) != nil {
            switch type {
            case .hitomi:
                return "https://hitomi.la/galleries/\(token).html"
            case .pixiv:
                return "https://www.pixiv.net/en/users/\(token)"
            case .hiyobi:
                return "https://hiyobi.me/reader/\(token)"
            case .ehen:
                break
            }
        }
        return normalizedInputToken(token)
    }

    private func inputItem(
        from task: OriginalBrowserExtensionTask,
        monitorableOnly: Bool
    ) -> (url: String, metadata: [String: String])? {
        let url = Self.normalizedInputToken(task.url)
        guard !url.isEmpty,
              !monitorableOnly || Self.isMonitorableURL(Self.cleanedClipboardToken(url)) else {
            return nil
        }
        return (url, task.metadata)
    }

    func clipboardCandidateURLs(from text: String) -> [String] {
        clipboardViewerCommandService
            .candidateURLs(
                from: text,
                extractURLs: {
                    self.extractURLs(
                        from: $0
                    )
                }
            )
    }

    private func jobsForAdding(
        _ urls: [String],
        checkHistory: Bool = true,
        metadata: [String: String] = [:],
        titleSuffix: String = "",
        promptForDuplicates: Bool = false
    ) -> [DownloadJob] {
        let items = urls.map { (url: $0, metadata: metadata) }
        return jobsForAdding(
            items,
            checkHistory: checkHistory,
            titleSuffix: titleSuffix,
            promptForDuplicates: promptForDuplicates
        )
    }

    private func jobsForAddingSearchResults(_ results: [SearchResultLink]) -> [DownloadJob] {
        let items = results.map { result in
            (
                url: result.url,
                metadata: Self.searchResultQueueMetadata(for: result)
            )
        }
        return jobsForAdding(items)
    }

    private func jobsForAdding(
        _ items: [(url: String, metadata: [String: String])],
        checkHistory: Bool = true,
        titleSuffix: String = "",
        promptForDuplicates: Bool = false
    ) -> [DownloadJob] {
        var seen = Set(queueStore.jobs.compactMap { job -> String? in
            guard !Self.isTerminalOriginalLiveJob(job) else { return nil }
            return DownloadRequestIdentityService.duplicateKey(
                source: job.source,
                metadata: job.metadata
            )
        })
        let historySources = checkHistory && settingsStore.historyEnabled
            ? Set(libraryStore.history.compactMap { entry -> String? in
                guard !Self.isOriginalLiveInput(source: entry.source, metadata: entry.metadata) else { return nil }
                return DownloadRequestIdentityService.duplicateKey(
                    source: entry.source,
                    normalizedSource: entry.normalizedSource,
                    metadata: entry.metadata
                )
            })
            : []
        var skipped = 0
        var newJobs: [DownloadJob] = []
        var pending: [PendingDuplicateAddition] = []
        var pendingKeys = Set<String>()

        for item in items {
            let url = item.url
            let metadata = item.metadata
            let normalized = URLIdentity.normalize(url)
            guard !normalized.isEmpty else { continue }
            let duplicateKey = DownloadRequestIdentityService.duplicateKey(
                source: url,
                normalizedSource: normalized,
                metadata: metadata
            )

            if settingsStore.skipDuplicates && (seen.contains(duplicateKey) || historySources.contains(duplicateKey)) {
                skipped += 1
                if promptForDuplicates, pendingKeys.insert(duplicateKey).inserted {
                    pending.append(PendingDuplicateAddition(
                        source: url,
                        title: url + titleSuffix,
                        metadata: metadata
                    ))
                }
                continue
            }

            seen.insert(duplicateKey)
            newJobs.append(DownloadJob(source: url, title: url + titleSuffix, metadata: metadata))
        }

        if !pending.isEmpty {
            presentDuplicateAdditionConfirmation(pending, addedCount: newJobs.count)
        } else {
            addSummary = summary(added: newJobs.count, skipped: skipped)
        }
        return newJobs
    }

    func confirmDuplicateAddition() {
        let pendingState = queueEditorStore.consumeDuplicateAdditions()
        let pending = pendingState.additions
        presentation.showingDuplicateAdditionConfirmation = false
        guard !pending.isEmpty else { return }

        insertAddedJobsAtTop(pending.map {
            DownloadJob(source: $0.source, title: $0.title, metadata: $0.metadata)
        })
        addSummary = pending.count == 1
            ? "Duplicate job added again"
            : "\(pending.count) duplicate jobs added again"
        persistQueue()
        if pendingState.shouldStartQueue {
            startQueue(addingInput: false)
        } else {
            runQueuedJobsIfEnabled()
        }
    }

    func cancelDuplicateAddition() {
        let count = queueEditorStore.cancelDuplicateAdditionConfirmation()
        presentation.showingDuplicateAdditionConfirmation = false
        if count > 0 {
            addSummary = count == 1 ? "Duplicate job skipped" : "\(count) duplicate jobs skipped"
        }
    }

    private func presentDuplicateAdditionConfirmation(
        _ pending: [PendingDuplicateAddition],
        addedCount: Int
    ) {
        let message = pending.count == 1
            ? AppLocalization.text(
                "This task has already been added. Download it again?",
                language: settingsStore.interfaceLanguage
            )
            : AppLocalization.format(
                "%@ tasks have already been added. Download them again?",
                language: settingsStore.interfaceLanguage,
                String(pending.count)
            )
        queueEditorStore.beginDuplicateAdditionConfirmation(
            pending,
            message: message
        )
        presentation.showingDuplicateAdditionConfirmation = true
        addSummary = addedCount == 0
            ? "Duplicate waiting for confirmation"
            : "\(addedCount) added, \(pending.count) duplicate waiting for confirmation"
    }

    private nonisolated static func searchResultQueueMetadata(for result: SearchResultLink) -> [String: String] {
        var metadata = result.metadata
        let title = result.title.trimmed
        if !title.isEmpty {
            metadata["search_title"] = title
            metadata["search_result_title"] = title
        }
        if let site = result.siteIdentifier?.trimmed, !site.isEmpty {
            metadata["search_site"] = metadata["search_site"] ?? site
            metadata["site"] = metadata["site"] ?? site
        }
        if !result.metadataText.trimmed.isEmpty {
            metadata["search_metadata"] = result.metadataText.trimmed
        }
        metadata["search_result"] = "true"
        metadata["search_url"] = result.url
        metadata["source_url"] = metadata["source_url"] ?? result.url
        metadata["page_url"] = metadata["page_url"] ?? result.url
        return DownloadMetadata.clean(metadata)
    }

    private nonisolated static func mediaRequestMetadata(from metadata: [String: String]) -> [String: String] {
        guard DownloadRequestIdentityService
            .isAudioExtractionRequest(metadata) else { return [:] }
        return [
            "media_request": "audio",
            "audio_format": DownloadRequestIdentityService
                .ytdlpAudioFormat(from: metadata) ?? "mp3"
        ]
    }

    nonisolated static func isImprovedOriginalLiveInputURL(_ source: String) -> Bool {
        let value = source.trimmed
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else {
            return false
        }

        let lowercased = value.lowercased()
        if lowercased.contains("nicovideo.jp/user/") || lowercased.contains("ch.nicovideo.jp") {
            return true
        }
        if TwitchVODResolver.liveLogin(from: url) != nil ||
            SOOPVODResolver.liveID(from: url) != nil ||
            ChzzkResolver.liveID(from: url) != nil {
            return true
        }

        guard let host = url.host?.lowercased(),
              ["youtube.com", "www.youtube.com", "m.youtube.com", "music.youtube.com", "youtube.test", "www.youtube.test"].contains(host),
              let first = url.path.split(separator: "/", omittingEmptySubsequences: true).first else {
            return false
        }
        return (String(first).removingPercentEncoding ?? String(first)).hasPrefix("@")
    }

    private nonisolated static func isTerminalOriginalLiveJob(_ job: DownloadJob) -> Bool {
        switch job.status {
        case .finished, .failed, .cancelled:
            return isOriginalLiveInput(source: job.source, metadata: job.metadata)
        case .queued, .resolving, .downloading:
            return false
        }
    }

    private nonisolated static func isOriginalLiveInput(
        source: String,
        metadata: [String: String]
    ) -> Bool {
        if isImprovedOriginalLiveInputURL(source) {
            return true
        }

        var normalized: [String: String] = [:]
        for (key, value) in metadata {
            normalized[key.lowercased()] = value.trimmed.lowercased()
        }
        for key in ["live", "is_live", "was_live"] {
            let value = normalized[key, default: ""]
            if ["1", "true", "yes", "on", "live", "is_live", "was_live", "post_live"].contains(value) {
                return true
            }
        }
        return ["live_status", "type", "category", "extractor", "extractor_key"]
            .contains { normalized[$0, default: ""].contains("live") }
    }

    private nonisolated static func normalizedHistorySource(for job: DownloadJob) -> String {
        URLIdentity.normalize(job.source)
    }

    private func moveJob(_ job: DownloadJob, offset: Int) {
        guard settingsStore.queueSortMode == .manual else {
            addSummary = "Use Manual queue sort before moving jobs"
            return
        }
        guard presentation.queueFilter.trimmed.isEmpty else {
            addSummary = "Clear the queue filter before moving jobs"
            return
        }
        let orderedJobs = queueOrderedJobs
        guard orderedJobs.contains(where: { $0.id == job.id }) else { return }
        let reordered = QueueReorderingService.jobsByMovingSelectedJobs(
            orderedJobs,
            selectedIDs: [job.id],
            offset: offset
        )
        guard reordered.map(\.id) != orderedJobs.map(\.id) else {
            addSummary = QueueReorderingService.blockedSummary(
                jobIDs: [job.id],
                offset: offset,
                orderedJobs: orderedJobs
            )
            return
        }

        applyQueueOrder(reordered)
        setSelectedJobIDs([job.id])
        addSummary = "Job moved"
        persistQueue()
    }

    private func moveSelectedJobs(offset: Int) {
        guard settingsStore.queueSortMode == .manual else {
            addSummary = "Use Manual queue sort before moving jobs"
            return
        }
        guard presentation.queueFilter.trimmed.isEmpty else {
            addSummary = "Clear the queue filter before moving jobs"
            return
        }
        guard !presentation.selectedJobIDs.isEmpty else {
            addSummary = "Select jobs to move"
            return
        }

        let orderedJobs = queueOrderedJobs
        let reordered = QueueReorderingService.jobsByMovingSelectedJobs(
            orderedJobs,
            selectedIDs: presentation.selectedJobIDs,
            offset: offset
        )
        guard reordered.map(\.id) != orderedJobs.map(\.id) else {
            addSummary = QueueReorderingService.blockedSummary(
                jobIDs: presentation.selectedJobIDs,
                offset: offset,
                orderedJobs: orderedJobs
            )
            return
        }

        applyQueueOrder(reordered)
        setSelectedJobIDs(presentation.selectedJobIDs)
        addSummary = "\(presentation.selectedJobIDs.count) selected job\(presentation.selectedJobIDs.count == 1 ? "" : "s") moved"
        persistQueue()
    }

    private func canMoveJob(at index: Int, offset: Int) -> Bool {
        guard queueStore.jobs.indices.contains(index) else { return false }
        return canMoveQueueJobs([queueStore.jobs[index].id], offset: offset)
    }

    private func canMoveSelectedJobs(offset: Int) -> Bool {
        canMoveQueueJobs(presentation.selectedJobIDs, offset: offset)
    }

    private func canMoveQueueJobs(_ jobIDs: Set<UUID>, offset: Int) -> Bool {
        guard settingsStore.queueSortMode == .manual,
              presentation.queueFilter.trimmed.isEmpty,
              !jobIDs.isEmpty else {
            return false
        }
        return QueueReorderingService.canMoveSelectedJobs(
            queueOrderedJobs,
            selectedIDs: jobIDs,
            offset: offset
        )
    }

    private func applyQueueOrder(_ reordered: [DownloadJob]) {
        if queueStore.isRunning {
            queueScheduler.setActiveOrder(reordered.map(\.id))
        } else {
            queueStore.replaceJobs(with: reordered)
        }
    }

    private func addBookmarks(_ urls: [String]) {
        let records = urls.map { BookmarkImportRecord(title: nil, url: $0, createdAt: nil) }
        let added = addBookmarkRecords(records)
        addSummary = added == 0 ? "No new bookmarks" : "\(added) bookmarks saved"
    }

    @discardableResult
    private func mergeSearchProviders(_ imported: [SearchProvider]) -> Int {
        let result = ImportedCollectionMergeService.searchProviders(
            existing: searchStore.searchProviders,
            imported: imported
        )
        guard result.addedCount > 0 else { return 0 }
        searchStore.replaceSearchProviders(with: result.values)
        if !searchStore.searchProviders.contains(where: {
            $0.id == searchStore.selectedSearchProviderID
        }) {
            searchStore.selectedSearchProviderID =
                searchStore.searchProviders.first?.id
                ?? SearchProvider.defaultProviders[0].id
        }
        persistSearchProviders()
        return result.addedCount
    }

    @discardableResult
    private func mergeSearchBookmarks(_ imported: [SearchBookmark]) -> Int {
        let result = ImportedCollectionMergeService.searchBookmarks(
            existing: searchStore.searchBookmarks,
            imported: imported,
            providers: searchStore.searchProviders,
            fallbackProviderName: currentSearchProvider()?.name
                ?? SearchProvider.defaultProviders[0].name
        )
        guard result.addedCount > 0 else { return 0 }
        searchStore.replaceSearchBookmarks(with: result.values)
        persistSearchBookmarks()
        return result.addedCount
    }

    @discardableResult
    private func mergeQueueFilterBookmarks(_ imported: [QueueFilterBookmark]) -> Int {
        let result = ImportedCollectionMergeService.queueFilterBookmarks(
            existing: queueStore.queueFilterBookmarks,
            imported: imported
        )
        guard result.addedCount > 0 else { return 0 }
        queueStore.replaceQueueFilterBookmarks(with: result.values)
        persistQueueFilterBookmarks()
        return result.addedCount
    }

    @discardableResult
    private func addBookmarkRecords(_ records: [BookmarkImportRecord]) -> Int {
        let result = ImportedCollectionMergeService.bookmarks(
            existing: libraryStore.bookmarks,
            imported: records
        )
        libraryStore.replaceBookmarks(with: result.values)
        persistBookmarks()
        return result.addedCount
    }

    private nonisolated static func extractURLs(fromTokenLine line: String) -> [String] {
        let trimmedLine = line.trimmed
        if let hitomiURL = hitomiCustomURIString(from: cleanedClipboardToken(trimmedLine)) {
            return [hitomiURL]
        }
        if let sankakuURL = sankakuTagInputURLString(from: line) {
            return [sankakuURL]
        }
        if let booruURL = booruTagInputURLString(from: line) {
            return [booruURL]
        }
        return line
            .components(separatedBy: .whitespacesAndNewlines)
            .map(normalizedInputToken)
            .filter { !$0.isEmpty && looksLikeURL($0) }
    }

    private nonisolated static func looksLikeURL(_ value: String) -> Bool {
        SourceInputNormalizer.looksLikeURL(value)
    }

    private func completeJob(at index: Int) async {
        guard queueStore.jobs.indices.contains(index), queueStore.jobs[index].status == .finished else { return }
        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .recordingCompletionMessage(queueStore.jobs[index])
        )
        if Self.isPendingQueueRemoval(queueStore.jobs[index]) {
            queueStore.replaceJob(
                at: index,
                with:
                    completedDownloadJobStateService
                    .recordingCompletionTimestamp(
                        queueStore.jobs[index],
                        completedAt:
                            ISO8601DateFormatter().string(
                                from: Date()
                            )
                    )
            )
            persistQueue()
            return
        }
        if !effectivePythonHookCalls(for: .taskFinished).isEmpty {
            do {
                let names = apiOutputFiles(for: queueStore.jobs[index]).map { $0.url.path }
                let context = PythonScriptBridge.hookContext(
                    job: queueStore.jobs[index],
                    sourceURL: URL(string: queueStore.jobs[index].source.trimmed),
                    names: names
                )
                let hooked = try await runPythonHooks(event: .taskFinished, context: context)
                applyPythonHookContext(hooked, toJobAt: index)
            } catch PythonScriptBridgeError.retryRequested(_, let message) {
                markFailed(index, message: message, allowsIncompleteRetry: false)
                return
            } catch {
                markFailed(
                    index,
                    message: "Finished hook failed: \(AppLocalization.errorText(error))",
                    allowsIncompleteRetry: Self.failureAllowsIncompleteRetry(error)
                )
                return
            }
        }
        await refreshOriginalInfoOutputNames(at: index)
        await enrichCompletedJobMetadata(at: index)
        await refreshCompletedJobByteCount(at: index)
        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .recordingCompletionTimestamp(
                    queueStore.jobs[index],
                    completedAt:
                        ISO8601DateFormatter().string(
                            from: Date()
                        )
                )
        )
        recordHistory(for: index)
        scheduleRestartIfNeeded(for: queueStore.jobs[index])
        handleJobCompletionAlert(for: queueStore.jobs[index])
        await autoRemoveFinishedJobIfNeeded(at: index)
        persistQueue()
    }

    private func completeManuallyFinishedJob(at index: Int) {
        guard queueStore.jobs.indices.contains(index), queueStore.jobs[index].status == .finished else { return }
        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .recordingCompletionMessage(queueStore.jobs[index])
        )
        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .applyingResolvedFilenames(
                    completedOutputMetadataService
                        .resolvedFilenamesSynchronously(
                            at: queueStore.jobs[index].outputPath
                        ),
                    to: queueStore.jobs[index]
                )
        )
        refreshCompletedJobByteCountSynchronously(at: index)
        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .recordingCompletionTimestamp(
                    queueStore.jobs[index],
                    completedAt:
                        ISO8601DateFormatter().string(
                            from: Date()
                        )
                )
        )
        recordHistory(for: index)
        scheduleRestartIfNeeded(for: queueStore.jobs[index])
        handleJobCompletionAlert(for: queueStore.jobs[index])
        persistQueue()
    }

    private func refreshOriginalInfoOutputNames(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        let jobID = queueStore.jobs[index].id
        let outputPath = queueStore.jobs[index].outputPath
        let names =
            await completedOutputMetadataService
            .resolvedFilenames(at: outputPath)
        guard !names.isEmpty,
              let currentIndex = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[currentIndex].outputPath == outputPath else {
            return
        }
        queueStore.replaceJob(
            at: currentIndex,
            with:
                completedDownloadJobStateService
                .applyingResolvedFilenames(
                    names,
                    to: queueStore.jobs[currentIndex]
                )
        )
    }

    private func enrichCompletedJobMetadata(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        await enrichCompletedJobMetadata(for: queueStore.jobs[index].id)
    }

    private func refreshCompletedJobByteCount(at index: Int) async {
        guard queueStore.jobs.indices.contains(index) else { return }
        let jobID = queueStore.jobs[index].id
        let outputPath = queueStore.jobs[index].outputPath
        let byteCount =
            await completedOutputMetadataService
            .outputByteCountAsynchronously(
                forOutputPath: outputPath
            )
        guard let byteCount, byteCount > 0,
              let currentIndex = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[currentIndex].status == .finished,
              queueStore.jobs[currentIndex].outputPath == outputPath else {
            return
        }
        applyCompletedJobByteCount(byteCount, at: currentIndex)
    }

    private func refreshCompletedJobByteCountSynchronously(at index: Int) {
        guard queueStore.jobs.indices.contains(index),
              let byteCount =
                completedOutputMetadataService
                .outputByteCount(
                    forOutputPath:
                        queueStore.jobs[index].outputPath
                ),
              byteCount > 0 else {
            return
        }
        applyCompletedJobByteCount(byteCount, at: index)
    }

    private func applyCompletedJobByteCount(_ byteCount: Int64, at index: Int) {
        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .applyingLocalOutputByteCount(
                    byteCount,
                    to: queueStore.jobs[index]
                )
        )
    }

    private func backfillCompletedOutputMetadata() async {
        let candidates = queueStore.jobs.compactMap { job -> CompletedOutputMetadataCandidate? in
            guard job.status == .finished,
                  !job.outputPath.trimmed.isEmpty else {
                return nil
            }
            let needsByteCount =
                !completedOutputMetadataService
                .hasLocalOutputByteCount(job.metadata)
            let storedOutputExists =
                completedOutputMetadataService
                .outputPathExists(job.outputPath)
            guard needsByteCount || !storedOutputExists else { return nil }
            return CompletedOutputMetadataCandidate(
                jobID: job.id,
                originalOutputPath: job.outputPath,
                needsByteCount: needsByteCount
            )
        }
        guard !candidates.isEmpty else { return }

        let results =
            await completedOutputMetadataService
            .completedOutputMetadataResults(
                for: candidates,
                destinationPath: settingsStore.destinationPath
            )
        guard !Task.isCancelled else { return }

        var updatedCount = 0
        for result in results {
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == result.jobID }),
                  queueStore.jobs[index].status == .finished,
                  queueStore.jobs[index].outputPath == result.originalOutputPath else {
                continue
            }
            var changed = false
            if queueStore.jobs[index].outputPath != result.recoveredOutputPath {
                queueStore.updateJob(at: index) {
                    $0.outputPath = result.recoveredOutputPath
                }
                changed = true
            }
            if let byteCount = result.byteCount,
               byteCount > 0,
               !completedOutputMetadataService
               .hasLocalOutputByteCount(
                    queueStore.jobs[index].metadata
               ) {
                applyCompletedJobByteCount(byteCount, at: index)
                changed = true
            }
            if changed {
                updatedCount += 1
            }
        }
        if updatedCount > 0 {
            persistQueue()
        }
    }

    private nonisolated static func hasLocalOutputByteCount(_ metadata: [String: String]) -> Bool {
        CompletedOutputMetadataService()
            .hasLocalOutputByteCount(metadata)
    }

    nonisolated static func outputByteCount(
        forOutputPath outputPath: String,
        fileManager: FileManager = .default
    ) -> Int64? {
        CompletedOutputMetadataService()
            .outputByteCount(
                forOutputPath: outputPath,
                fileManager: fileManager
            )
    }

    private func enrichCompletedJobMetadata(for jobID: UUID) async {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[index].status == .finished,
              completedOutputMetadataService
              .metadataNeedsLocalDuration(
                    queueStore.jobs[index].metadata
              ) else {
            return
        }

        let seconds =
            await completedOutputMetadataService
            .durationSeconds(
                forOutputPath:
                    queueStore.jobs[index].outputPath,
                metadata: queueStore.jobs[index].metadata
            )
        guard let currentIndex = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              queueStore.jobs[currentIndex].status == .finished,
              completedOutputMetadataService
              .metadataNeedsLocalDuration(
                    queueStore.jobs[currentIndex].metadata
              ) else {
            return
        }

        let updated =
            completedOutputMetadataService
            .metadataByAddingDuration(
                to: queueStore.jobs[currentIndex].metadata,
                seconds: seconds
            )
        if updated != queueStore.jobs[currentIndex].metadata {
            queueStore.updateJob(at: currentIndex) {
                $0.metadata = updated
            }
        }
    }

    nonisolated static func metadataNeedsLocalDuration(_ metadata: [String: String]) -> Bool {
        CompletedOutputMetadataService()
            .metadataNeedsLocalDuration(metadata)
    }

    nonisolated static func singleOutputMediaFileURL(from output: URL) -> URL? {
        CompletedOutputMetadataService()
            .singleOutputMediaFileURL(from: output)
    }

    nonisolated static func isRetiredDaumWebtoonURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host?.lowercased() else {
            return false
        }

        if host == "webtoon.daum.net" || host.hasSuffix(".webtoon.daum.net") {
            return true
        }

        if host == "cartoon.media.daum.net" || host.hasSuffix(".cartoon.media.daum.net") {
            let marker = "\(url.path)?\(url.query ?? "")".lowercased()
            return marker.contains("webtoon")
        }

        return false
    }

    nonisolated static func retiredDaumWebtoonUnsupportedMessage(for url: URL) -> String? {
        guard isRetiredDaumWebtoonURL(url) else { return nil }
        return "Daum Webtoon support has ended. Use the migrated Kakao Webtoon URL on webtoon.kakao.com if it is available."
    }

    private func handleJobCompletionAlert(for job: DownloadJob) {
        guard job.metadata["manual_completion"] != "true" else { return }
        guard downloadCoordinator.beginJobCompletion(job.id) else { return }
        recordActivity("Finished: \(job.title)", category: "Download")

        if settingsStore.playSoundWhenJobCompletes {
            completionAlerts.playCompletionSound()
        }
        if settingsStore.notifyWhenJobCompletes {
            completionAlerts.notifyJobFinished(title: job.title, outputPath: job.outputPath)
        }
    }

    private func autoRemoveFinishedJobIfNeeded(at index: Int) async {
        guard settingsStore.autoRemoveFinishedJobs,
              queueStore.jobs.indices.contains(index),
              !Self.isPendingQueueRemoval(queueStore.jobs[index]) else {
            return
        }

        let job = queueStore.jobs[index]
        if defersAutoRemoveUntilQueueEnd {
            deferredAutoRemoveJobIDs.insert(job.id)
            return
        }

        guard job.status == .finished,
              job.metadata["manual_completion"] != "true",
              configuredRestartDelaySeconds(for: job) == nil,
              Self.scheduledRetryTimestamp(for: job) == nil,
              !isProtected(job) else {
            return
        }

        do {
            try await runAutoRemoveHookIfNeeded(for: job)
        } catch {
            let message = Self.autoRemoveHookErrorMessage(error)
            if let currentIndex = queueStore.jobs.firstIndex(where: { $0.id == job.id }) {
                queueStore.updateJob(at: currentIndex) {
                    $0.message = "Auto-remove Hook Failed"
                    $0.metadata["auto_remove_hook_error"] = message
                }
            }
            appStatusStore.setAutoRemoveHookStatus(
                "Auto-remove Hook Failed: \(message)"
            )
            addSummary = "Auto-remove Hook Failed"
            return
        }

        guard let currentIndex = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else {
            return
        }
        guard queueStore.jobs[currentIndex].status == .finished,
              !Self.isPendingQueueRemoval(queueStore.jobs[currentIndex]),
              queueStore.jobs[currentIndex].metadata["manual_completion"] != "true",
              configuredRestartDelaySeconds(for: queueStore.jobs[currentIndex]) == nil,
              Self.scheduledRetryTimestamp(for: queueStore.jobs[currentIndex]) == nil,
              !isProtected(queueStore.jobs[currentIndex]) else {
            return
        }

        downloadCoordinator.removeRetrySnapshot(for: job.id)
        downloadCoordinator.clearCompletionAlert(for: job.id)
        queueStore.removeJobs(withIDs: [queueStore.jobs[currentIndex].id])
        addSummary = "Finished job auto removed"
    }

    private func flushDeferredAutoRemoveFinishedJobs() async {
        guard !deferredAutoRemoveJobIDs.isEmpty else { return }
        let deferredIDs = deferredAutoRemoveJobIDs
        deferredAutoRemoveJobIDs.removeAll()
        let wasDeferring = defersAutoRemoveUntilQueueEnd
        defersAutoRemoveUntilQueueEnd = false
        defer { defersAutoRemoveUntilQueueEnd = wasDeferring }

        let orderedIDs = queueStore.jobs.map(\.id).filter { deferredIDs.contains($0) }
        for id in orderedIDs {
            guard let index = queueStore.jobs.firstIndex(where: { $0.id == id }) else { continue }
            await autoRemoveFinishedJobIfNeeded(at: index)
        }
    }

    private func runAutoRemoveHookIfNeeded(for job: DownloadJob) async throws {
        let template = settingsStore.autoRemoveHookCommand.trimmed
        guard !template.isEmpty else {
            appStatusStore.setAutoRemoveHookStatus("Auto-remove Hook Off")
            return
        }

        let context = Self.hookNameTemplateContext(for: job)
        let arguments = try Self.splitHookCommand(template).map {
            Self.expandedHookCommandToken($0, context: context)
        }
        guard let command = arguments.first, !command.trimmed.isEmpty else {
            throw NativeDownloadError.unsupported("Auto-remove hook command is empty.")
        }
        guard let executable = Self.executableURL(forHookCommand: command) else {
            throw NativeDownloadError.unsupported("Auto-remove hook executable was not found: \(command)")
        }

        try AppPaths.ensureDirectory(AppPaths.applicationSupportDirectory)
        let logURL = AppPaths.applicationSupportDirectory.appendingPathComponent("auto-remove-hook.log")
        appStatusStore.setAutoRemoveHookStatus("Auto-remove Hook Running")
        try await ExternalProcessRunner.run(
            executable: executable,
            arguments: Array(arguments.dropFirst()),
            logURL: logURL,
            currentDirectoryURL: Self.hookWorkingDirectory(for: job),
            failureDescription: "Auto-remove hook"
        )
        appStatusStore.setAutoRemoveHookStatus(
            "Auto-remove Hook Completed"
        )
    }

    private nonisolated static func splitHookCommand(_ template: String) throws -> [String] {
        var result: [String] = []
        var current = ""
        var quote: Character?
        var index = template.startIndex

        func appendCurrent() {
            if !current.isEmpty {
                result.append(current)
                current = ""
            }
        }

        while index < template.endIndex {
            let character = template[index]

            if character == "\\" {
                let nextIndex = template.index(after: index)
                if nextIndex < template.endIndex {
                    current.append(template[nextIndex])
                    index = template.index(after: nextIndex)
                } else {
                    current.append(character)
                    index = nextIndex
                }
                continue
            }

            if character == "\"" || character == "'" {
                if quote == nil {
                    quote = character
                    index = template.index(after: index)
                    continue
                }
                if quote == character {
                    quote = nil
                    index = template.index(after: index)
                    continue
                }
            }

            if quote == nil && Self.isHookCommandWhitespace(character) {
                appendCurrent()
                index = template.index(after: index)
                continue
            }

            current.append(character)
            index = template.index(after: index)
        }

        guard quote == nil else {
            throw NativeDownloadError.unsupported("Auto-remove hook has an unterminated quote.")
        }

        appendCurrent()
        return result
    }

    private nonisolated static func expandedHookCommandToken(_ token: String, context: NameTemplateContext) -> String {
        NameTemplate.string(template: token, context: context)
    }

    private nonisolated static func hookNameTemplateContext(for job: DownloadJob) -> NameTemplateContext {
        let sourceURL = URL(string: job.source)
        let outputURL = job.outputPath.isEmpty ? nil : URL(fileURLWithPath: job.outputPath)
        let outputDirectory = outputURL.flatMap { hookOutputDirectory(for: $0) }
        let metadata = hookCommandMetadata(for: job, sourceURL: sourceURL, outputURL: outputURL, outputDirectory: outputDirectory)
        let safeFilename = outputURL?.lastPathComponent ?? metadata["filename"] ?? job.title
        let basename = outputURL?.deletingPathExtension().lastPathComponent ?? metadata["basename"] ?? (safeFilename as NSString).deletingPathExtension
        let ext = outputURL?.pathExtension ?? metadata["ext"] ?? ""

        return NameTemplateContext(
            title: job.title,
            site: metadata["site"] ?? "",
            host: metadata["host"] ?? "",
            date: metadata["download_completed_at"] ?? metadata["date"] ?? dateFolderName(),
            id: job.id.uuidString,
            url: job.source,
            path: sourceURL?.path ?? metadata["path"] ?? "",
            slug: metadata["slug"] ?? sourceURL?.lastPathComponent ?? "",
            query: sourceURL?.query ?? metadata["query"] ?? "",
            filename: safeFilename,
            basename: basename,
            ext: ext,
            index: nil,
            total: job.total > 0 ? job.total : nil,
            metadata: metadata
        )
    }

    private nonisolated static func hookCommandMetadata(
        for job: DownloadJob,
        sourceURL: URL?,
        outputURL: URL?,
        outputDirectory: URL?
    ) -> [String: String] {
        let host = sourceURL?.host ?? ""
        let outputPath = outputURL?.path ?? job.outputPath
        let filename = outputURL?.lastPathComponent ?? ""
        let basename = outputURL?.deletingPathExtension().lastPathComponent ?? ""
        let ext = outputURL?.pathExtension ?? ""

        var metadata = job.metadata
        let sourceID = sourceURL.flatMap(sourceIdentifierValue) ?? ""

        let replacements: [String: String] = [
            "id": job.id.uuidString,
            "job_id": job.id.uuidString,
            "source_id": sourceID,
            "url": job.source,
            "source": job.source,
            "title": job.title,
            "status": job.status.rawValue,
            "message": job.message,
            "comment": job.comment,
            "output": outputPath,
            "outputPath": outputPath,
            "outputDir": outputDirectory?.path ?? "",
            "filename": filename,
            "basename": basename,
            "ext": ext,
            "host": host,
            "site": job.metadata["site"] ?? host,
            "path": sourceURL?.path ?? "",
            "query": sourceURL?.query ?? "",
            "completed": String(job.completed),
            "total": String(job.total),
            "progress": String(job.progress),
            "format": job.metadata["format"] ?? ext
        ]

        for (key, value) in replacements {
            metadata[key] = value
        }
        return metadata
    }

    private nonisolated static func sourceIdentifierValue(for url: URL) -> String {
        let basename = url.deletingPathExtension().lastPathComponent
        if !basename.isEmpty { return basename }
        if !url.lastPathComponent.isEmpty { return url.lastPathComponent }
        return url.host ?? ""
    }

    private nonisolated static func hookWorkingDirectory(for job: DownloadJob) -> URL? {
        guard !job.outputPath.isEmpty else { return nil }
        return hookOutputDirectory(for: URL(fileURLWithPath: job.outputPath))
    }

    private nonisolated static func hookOutputDirectory(for url: URL) -> URL {
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return url
        }
        return url.deletingLastPathComponent()
    }

    private nonisolated static func executableURL(forHookCommand command: String) -> URL? {
        let fileManager = FileManager.default
        let expanded = (command as NSString).expandingTildeInPath

        if expanded.contains("/") {
            let url = URL(fileURLWithPath: expanded)
            return fileManager.isExecutableFile(atPath: url.path) ? url : nil
        }

        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .components(separatedBy: ":")
            .filter { !$0.isEmpty }

        for folder in paths {
            let candidate = URL(fileURLWithPath: folder).appendingPathComponent(expanded)
            if fileManager.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }

        return nil
    }

    private nonisolated static func autoRemoveHookErrorMessage(_ error: Error) -> String {
        let text = String(describing: error).trimmed
        return text.isEmpty ? "unknown error" : text
    }

    private nonisolated static func isHookCommandWhitespace(_ character: Character) -> Bool {
        character.unicodeScalars.allSatisfy { CharacterSet.whitespacesAndNewlines.contains($0) }
    }

    private func resetQueueRunAlertState() {
        downloadCoordinator.resetQueueRunOutcome()
    }

    private func handleQueueRunCompleted() {
        let outcome = downloadCoordinator.queueRunOutcome
        guard outcome.hasResults else {
            resetQueueRunAlertState()
            return
        }

        let summary = Self.completionQueueSummary(
            finished: outcome.finished,
            failed: outcome.failed
        )
        recordActivity("Queue complete: \(summary)", category: "Queue")
        if settingsStore.notifyWhenQueueCompletes {
            completionAlerts.notifyQueueFinished(summary: summary)
        }
        appStatusStore.setQueueCompletionActionStatus(
            queueCompletionCommandService.perform(
                settingsStore.queueCompletionAction,
                summary: summary,
                destinationPath: settingsStore.destinationPath,
                language: settingsStore.interfaceLanguage
            )
        )
        resetQueueRunAlertState()
    }

    nonisolated static func queueCompletionActionStatusText(for action: QueueCompletionAction) -> String {
        QueueCompletionCommandService.statusText(
            for: action
        )
    }

    nonisolated static func completionQueueSummary(finished: Int, failed: Int) -> String {
        let finished = max(0, finished)
        let failed = max(0, failed)
        let pieces = [
            finished > 0 ? AppLocalization.format("%@ finished", String(finished)) : nil,
            failed > 0 ? AppLocalization.format("%@ failed", String(failed)) : nil
        ].compactMap { $0 }
        return pieces.isEmpty
            ? AppLocalization.text("No completed queue tasks")
            : pieces.joined(separator: AppLocalization.text(", "))
    }

    @discardableResult
    private func markJobFinished(at index: Int) -> Bool {
        guard queueStore.jobs.indices.contains(index) else { return false }
        let pausedActive = isPausedActiveJob(queueStore.jobs[index])
        guard canMarkJobFinished(at: index) else {
            addSummary = queueStore.jobs[index].status == .finished
                ? "Job is already finished"
                : "Pause or cancel active jobs before marking finished"
            return false
        }

        let jobID = queueStore.jobs[index].id
        if pausedActive {
            terminateRuntimeControlForManualCompletion(jobID: jobID)
        }
        downloadCoordinator.removeRetrySnapshot(for: jobID)
        cancelScheduledRestart(for: jobID)

        queueStore.replaceJob(
            at: index,
            with:
                completedDownloadJobStateService
                .markingFinishedManually(
                    queueStore.jobs[index],
                    pausedActive: pausedActive,
                    completedAt:
                        ISO8601DateFormatter().string(
                            from: Date()
                        )
                )
        )
        addSummary = "Job marked finished"
        completeManuallyFinishedJob(at: index)
        completedJobMetadataEnrichmentCoordinator
            .begin { [weak self] in
                await self?.enrichCompletedJobMetadata(
                    for: jobID
                )
                self?.persistQueue()
            }
        return true
    }

    private func canMarkJobFinished(at index: Int) -> Bool {
        guard queueStore.jobs.indices.contains(index) else { return false }
        let job = queueStore.jobs[index]
        guard job.status != .finished else { return false }
        if !isActive(job.status) {
            return true
        }
        return isPausedActiveJob(job)
    }

    private func isPausedActiveJob(_ job: DownloadJob) -> Bool {
        isActive(job.status) &&
            (aria2Store.isRuntimePaused(jobID: job.id) ||
                job.metadata["aria2_runtime_paused"] == "true")
    }

    private func terminateRuntimeControlForManualCompletion(jobID: UUID) {
        externalToolRuntime.processControl(for: jobID, kind: .aria2)?.terminate()
        cleanupAria2RuntimeControl(for: jobID)
    }

    private func isManuallyFinishedJob(at index: Int) -> Bool {
        queueStore.jobs.indices.contains(index) &&
            queueStore.jobs[index].status == .finished &&
            queueStore.jobs[index].metadata["manual_completion"] == "true"
    }

    func scheduleRestartIfNeeded(for job: DownloadJob) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == job.id }) else { return }
        let current = queueStore.jobs[index]
        guard current.status == .finished,
              let delay = configuredRestartDelaySeconds(for: current) else {
            cancelScheduledRestart(for: current.id)
            return
        }

        let storedKind = current.metadata[Self.scheduledRetryKindMetadataKey]
            .flatMap(ScheduledRetryKind.init(rawValue:))
        let storedDelay = current.metadata[Self.scheduledRetryDelayMetadataKey]
            .flatMap(Double.init)
        let existingTarget = Self.scheduledRetryTimestamp(for: current)
        let target: TimeInterval
        if storedKind == .restart,
           let storedDelay,
           abs(storedDelay - delay) < 0.001,
           let existingTarget {
            target = existingTarget
        } else {
            target = Date().timeIntervalSince1970 + delay
        }

        _ = scheduleRetry(
            for: current.id,
            at: target,
            kind: .restart,
            force: false,
            delay: delay,
            announce: true,
            persist: true
        )
    }

    func hasScheduledRestart(for job: DownloadJob) -> Bool {
        downloadCoordinator.hasScheduledRetryTask(for: job.id)
    }

    func restoreScheduledRetries() {
        var changed = false
        for jobID in queueStore.jobs.map(\.id) {
            changed = restoreScheduledRetryIfNeeded(for: jobID) || changed
        }
        if changed {
            persistQueue()
        }
    }

    @discardableResult
    private func restoreScheduledRetryIfNeeded(for jobID: UUID) -> Bool {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }) else { return false }
        let job = queueStore.jobs[index]
        if let target = Self.scheduledRetryTimestamp(for: job) {
            let kind = scheduledRetryKind(for: job)
            let delay = job.metadata[Self.scheduledRetryDelayMetadataKey].flatMap(Double.init)
            let force = Self.metadataBool(job.metadata[Self.scheduledRetryForceMetadataKey])
            return scheduleRetry(
                for: jobID,
                at: target,
                kind: kind,
                force: force,
                delay: delay,
                announce: false,
                persist: false
            )
        }

        guard job.status == .finished,
              let delay = configuredRestartDelaySeconds(for: job) else {
            return false
        }
        return scheduleRetry(
            for: jobID,
            at: Date().timeIntervalSince1970 + delay,
            kind: .restart,
            force: false,
            delay: delay,
            announce: false,
            persist: false
        )
    }

    @discardableResult
    private func scheduleRetry(
        for jobID: UUID,
        at target: TimeInterval,
        kind: ScheduledRetryKind,
        force: Bool,
        delay: TimeInterval?,
        announce: Bool,
        persist: Bool
    ) -> Bool {
        guard target.isFinite, target > 1,
              let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              Self.isScheduledRetryEligible(queueStore.jobs[index], kind: kind) else {
            return false
        }

        stopScheduledRetryTask(for: jobID)
        let originalTitle = Self.scheduledRetryOriginalTitle(for: queueStore.jobs[index])
        queueStore.updateJob(at: index) {
            $0.metadata[Self.scheduledRetryTimestampMetadataKey] = Self.retryTimestampString(target)
            $0.metadata[Self.scheduledRetryOriginalTitleMetadataKey] = originalTitle
            $0.metadata[Self.scheduledRetryKindMetadataKey] = kind.rawValue
            $0.metadata[Self.scheduledRetryForceMetadataKey] = force ? "true" : "false"
            if let delay {
                $0.metadata[Self.scheduledRetryDelayMetadataKey] = Self.retryTimestampString(delay)
            } else {
                $0.metadata.removeValue(forKey: Self.scheduledRetryDelayMetadataKey)
            }
        }
        updateScheduledRetryCountdown(for: jobID, target: target)

        downloadCoordinator.scheduleRetryTask(id: jobID) { [weak self] in
            while !Task.isCancelled {
                guard let self,
                      let currentIndex = self.queueStore.jobs.firstIndex(where: { $0.id == jobID }),
                      let currentTarget = Self.scheduledRetryTimestamp(for: self.queueStore.jobs[currentIndex]),
                      abs(currentTarget - target) < 0.001 else {
                    return
                }

                if Self.retryRemainingSeconds(target: currentTarget) <= 0 {
                    self.runScheduledRestart(for: jobID)
                    return
                }

                self.updateScheduledRetryCountdown(for: jobID, target: currentTarget)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    return
                }
            }
        }

        if announce {
            addSummary = kind == .restart
                ? "Restart scheduled in \(Self.restartDelayDescription(for: max(0, target - Date().timeIntervalSince1970)))"
                : "Retry scheduled in \(Self.restartDelayDescription(for: max(0, target - Date().timeIntervalSince1970)))"
        }
        if persist {
            persistQueue()
        }
        return true
    }

    private func updateScheduledRetryCountdown(for jobID: UUID, target: TimeInterval) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              let title = Self.scheduledRetryCountdownTitle(
                target: target,
                identifier: Self.scheduledRetryIdentifier(for: queueStore.jobs[index])
              ) else {
            return
        }
        queueStore.updateJob(at: index) {
            $0.title = title
        }
    }

    private func runScheduledRestart(for jobID: UUID) {
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }),
              let target = Self.scheduledRetryTimestamp(for: queueStore.jobs[index]),
              Self.retryRemainingSeconds(target: target) <= 0 else {
            return
        }

        let kind = scheduledRetryKind(for: queueStore.jobs[index])
        guard Self.isScheduledRetryEligible(queueStore.jobs[index], kind: kind),
              kind != .restart || configuredRestartDelaySeconds(for: queueStore.jobs[index]) != nil else {
            cancelScheduledRestart(for: jobID)
            persistQueue()
            return
        }

        stopScheduledRetryTask(for: jobID)
        clearScheduledRetryState(at: index, restoreTitle: true)
        queueJobForRetry(at: index)
        addSummary = kind == .restart ? "Restart timer queued job" : "Delayed retry queued job"
        persistQueue()
        startQueue(addingInput: false)
    }

    private func cancelScheduledRestart(for jobID: UUID) {
        stopScheduledRetryTask(for: jobID)
        guard let index = queueStore.jobs.firstIndex(where: { $0.id == jobID }) else { return }
        clearScheduledRetryState(at: index, restoreTitle: true)
    }

    private func cancelAllScheduledRestarts() {
        downloadCoordinator.cancelAllScheduledRetryTasks()
    }

    private func stopScheduledRetryTask(for jobID: UUID) {
        downloadCoordinator.cancelScheduledRetryTask(jobID)
    }

    private func clearScheduledRetryState(at index: Int, restoreTitle: Bool) {
        guard queueStore.jobs.indices.contains(index) else { return }
        queueStore.updateJob(at: index) {
            if restoreTitle {
                let originalTitle = Self.scheduledRetryOriginalTitle(for: $0)
                if !originalTitle.trimmed.isEmpty {
                    $0.title = originalTitle
                }
            }
            $0.metadata.removeValue(forKey: Self.scheduledRetryTimestampMetadataKey)
            $0.metadata.removeValue(forKey: Self.scheduledRetryOriginalTitleMetadataKey)
            $0.metadata.removeValue(forKey: Self.scheduledRetryKindMetadataKey)
            $0.metadata.removeValue(forKey: Self.scheduledRetryDelayMetadataKey)
            $0.metadata.removeValue(forKey: Self.scheduledRetryForceMetadataKey)
        }
    }

    nonisolated static func restartDelaySeconds(from comment: String) -> TimeInterval? {
        OriginalRuntimeCompatibility.restartDelaySeconds(from: comment)
    }

    nonisolated static func restartDelaySeconds(for job: DownloadJob) -> TimeInterval? {
        restartDelaySeconds(from: job.comment)
            ?? restartDelaySeconds(from: job.metadata["group_comment"] ?? "")
    }

    nonisolated static func taskTagRestartDelaySeconds(
        for tags: [String],
        timers: [String: Int]
    ) -> TimeInterval? {
        TaskTagColor.normalizedRawValues(tags)
            .compactMap { timers[$0] }
            .filter { $0 > 0 }
            .min()
            .map(TimeInterval.init)
    }

    func configuredRestartDelaySeconds(for job: DownloadJob) -> TimeInterval? {
        Self.restartDelaySeconds(for: job)
            ?? Self.taskTagRestartDelaySeconds(
                for: job.tags,
                timers: settingsStore.taskTagRestartTimers
            )
    }

    nonisolated static func scheduledRetryTimestamp(for job: DownloadJob) -> TimeInterval? {
        scheduledRetryTimestamp(from: job.metadata)
    }

    nonisolated static func scheduledRetryTimestamp(from metadata: [String: String]) -> TimeInterval? {
        DownloadRetryPolicy.scheduledRetryTimestamp(from: metadata)
    }

    nonisolated static func retryRemainingSeconds(
        target: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970
    ) -> Int {
        DownloadRetryPolicy.remainingSeconds(target: target, now: now)
    }

    nonisolated static func scheduledRetryCountdownTitle(
        target: TimeInterval,
        now: TimeInterval = Date().timeIntervalSince1970,
        identifier: String
    ) -> String? {
        DownloadRetryPolicy.countdownTitle(
            target: target,
            now: now,
            identifier: identifier
        )
    }

    private nonisolated static func scheduledRetryOriginalTitle(for job: DownloadJob) -> String {
        for key in [scheduledRetryOriginalTitleMetadataKey, "title0", "original_title"] {
            if let value = job.metadata[key]?.trimmed, !value.isEmpty {
                return value
            }
        }
        return job.title.trimmed.isEmpty ? job.source : job.title
    }

    private nonisolated static func scheduledRetryIdentifier(for job: DownloadJob) -> String {
        let releaseTimestamp = [
            job.metadata["release_timestamp"],
            job.metadata["hdt_release_timestamp"]
        ].compactMap { $0?.trimmed }.first { !$0.isEmpty }
        if releaseTimestamp != nil {
            let galleryID = [
                job.metadata["gallery_id"],
                job.metadata["gallery_number"],
                job.metadata["hdt_gallery_number"],
                job.metadata["gal_num"]
            ].compactMap { $0?.trimmed }.first { !$0.isEmpty }
            if let galleryID {
                return galleryID.replacingOccurrences(of: "#-*-", with: "")
            }
        }
        return scheduledRetryOriginalTitle(for: job)
    }

    private func scheduledRetryKind(for job: DownloadJob) -> ScheduledRetryKind {
        if let raw = job.metadata[Self.scheduledRetryKindMetadataKey]?.trimmed,
           let kind = ScheduledRetryKind(rawValue: raw) {
            return kind
        }
        if job.metadata["release_timestamp"]?.trimmed.isEmpty == false ||
            job.metadata["hdt_release_timestamp"]?.trimmed.isEmpty == false {
            return .release
        }
        if job.status == .finished, configuredRestartDelaySeconds(for: job) != nil {
            return .restart
        }
        return .imported
    }

    private nonisolated static func isScheduledRetryEligible(
        _ job: DownloadJob,
        kind: ScheduledRetryKind
    ) -> Bool {
        DownloadRetryPolicy.isEligible(job, kind: kind)
    }

    private nonisolated static func retryTimestampString(_ value: TimeInterval) -> String {
        DownloadRetryPolicy.timestampString(value)
    }

    private nonisolated static func metadataBool(_ raw: String?) -> Bool {
        DownloadRetryPolicy.metadataBool(raw)
    }

    private nonisolated static func restartDelayDescription(for seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return seconds > 0 ? "\(hours)h \(minutes)m \(seconds)s" : "\(hours)h \(minutes)m"
        }
        if minutes > 0 {
            return seconds > 0 ? "\(minutes)m \(seconds)s" : "\(minutes)m"
        }
        return "\(seconds)s"
    }

    private func recordHistory(for index: Int) {
        guard queueStore.jobs.indices.contains(index) else { return }
        guard settingsStore.historyEnabled else { return }
        let job = queueStore.jobs[index]
        let normalized = Self.normalizedHistorySource(for: job)
        let limit = settingsStore.historyLimit
        libraryStore.updateHistory { history in
            history.removeAll {
                DownloadRequestIdentityService.duplicateKey(
                    source: $0.source,
                    normalizedSource: $0.normalizedSource,
                    metadata: $0.metadata
                ) == DownloadRequestIdentityService.duplicateKey(
                    source: job.source,
                    normalizedSource: normalized,
                    metadata: job.metadata
                )
            }
            history.insert(DownloadHistoryEntry(
                id: UUID(),
                source: job.source,
                normalizedSource: normalized,
                title: job.title,
                outputPath: job.outputPath,
                completedAt: Date(),
                metadata: job.metadata
            ), at: 0)
            if history.count > limit {
                history.removeSubrange(limit..<history.count)
            }
        }
        persistHistory()
    }

    private func persistHistorySettings() {
        settingsStore.persistHistory()
    }

    private func persistCompletionAlertSettings() {
        settingsStore.persistCompletionAlerts()
    }

    private func trimHistoryToLimit() {
        let limit = settingsStore.historyLimit
        guard libraryStore.history.count > limit else { return }
        libraryStore.updateHistory {
            $0.removeSubrange(limit..<$0.count)
        }
    }

    nonisolated static func duplicateImageGroups(
        in root: URL,
        similarityPercent: Int = 100,
        excludeSameSource: Bool = false
    ) throws -> [DuplicateImageGroup] {
        try DuplicateImageScanService().groups(
            in: root,
            similarityPercent: similarityPercent,
            excludeSameSource: excludeSameSource
        )
    }

    nonisolated static func duplicateImageGroups(
        in roots: [URL],
        similarityPercent: Int = 100,
        excludeSameSource: Bool = false
    ) throws -> [DuplicateImageGroup] {
        try DuplicateImageScanService().groups(
            in: roots,
            similarityPercent: similarityPercent,
            excludeSameSource: excludeSameSource
        )
    }

    nonisolated static func duplicateImageFolderURL(forPath path: String, fileManager: FileManager = .default) -> URL? {
        DuplicateImageScanService().folderURL(
            forPath: path,
            fileManager: fileManager
        )
    }

    nonisolated static func duplicateImageAutoSelectionCandidate(
        in groups: [DuplicateImageGroup],
        minimumSimilarityPercent: Int,
        fileManager: FileManager = .default
    ) -> String? {
        DuplicateImageScanService()
            .autoSelectionCandidate(
                in: groups,
                minimumSimilarityPercent:
                    minimumSimilarityPercent,
                fileManager: fileManager
            )
    }

    private func summary(added: Int, skipped: Int) -> String {
        if added == 0 && skipped == 0 {
            return ""
        }
        if skipped == 0 {
            return "\(added) added"
        }
        return "\(added) added, \(skipped) duplicates skipped"
    }

    private nonisolated static func bookmarkSortTitle(_ bookmark: URLBookmark) -> String {
        let title = bookmark.title.trimmed
        return title.isEmpty ? bookmark.url : title
    }

    private func normalizedHostSuffix(_ host: String) -> String {
        SiteRule.normalizedHostSuffix(host)
    }

    private func builtSearchURL() -> URL? {
        SearchQueryFacade.builtURL(
            providers: searchStore.searchProviders,
            selectedProviderID: searchStore.selectedSearchProviderID,
            query: searchStore.searchQuery
        )
    }

    private func currentSearchProvider() -> SearchProvider? {
        SearchQueryFacade.selectedProvider(
            in: searchStore.searchProviders,
            selectedProviderID: searchStore.selectedSearchProviderID
        )
    }

    private func selectHitomiSearchProvider() {
        if let provider = SearchQueryFacade.hitomiProvider(
            in: searchStore.searchProviders
        ) {
            searchStore.selectedSearchProviderID = provider.id
        }
    }

    private func quickSearchURLString(from line: String) -> String? {
        SearchQueryFacade.quickURL(
            from: line,
            providers: searchStore.searchProviders,
            selectedProviderID: searchStore.selectedSearchProviderID
        )?.absoluteString
    }

    nonisolated static func searchURL(provider: SearchProvider, query: String) -> URL? {
        SearchQueryFacade.searchURL(
            provider: provider,
            query: query
        )
    }

    private nonisolated static func isValidSearchTemplate(_ template: String) -> Bool {
        SearchQueryFacade.isValidTemplate(template)
    }

    private nonisolated static func renderedSearchTemplate(_ template: String, query: String) -> String {
        SearchQueryFacade.renderedTemplate(
            template,
            query: query
        )
    }

    nonisolated static func quickSearchRequest(from line: String) -> (providerKey: String?, query: String)? {
        guard let request = SearchQueryFacade.quickRequest(
            from: line
        ) else {
            return nil
        }
        return (request.providerKey, request.query)
    }

    private nonisolated static func searchProvider(matching rawKey: String, in providers: [SearchProvider]) -> SearchProvider? {
        SearchQueryFacade.provider(
            matching: rawKey,
            in: providers
        )
    }

    private nonisolated static func searchProvider(for bookmark: SearchBookmark, in providers: [SearchProvider]) -> SearchProvider? {
        SearchQueryFacade.provider(
            for: bookmark,
            in: providers
        )
    }

    private nonisolated static func searchBookmarkTitle(providerName: String, query: String) -> String {
        SearchQueryFacade.bookmarkTitle(
            providerName: providerName,
            query: query
        )
    }

    private nonisolated static func searchBookmarkKey(providerName: String, query: String) -> String {
        SearchQueryFacade.bookmarkKey(
            providerName: providerName,
            query: query
        )
    }

    private nonisolated static func searchProviderKey(_ value: String) -> String {
        SearchQueryFacade.providerKey(value)
    }

    private func matchingCustomCommandRule(for url: URL) -> SiteRule? {
        guard url.host != nil else { return nil }
        return libraryStore.siteRules
            .filter {
                $0.handler == .customCommand &&
                    !($0.commandTemplate?.trimmed.isEmpty ?? true)
            }
            .sorted { $0.matchSpecificity > $1.matchSpecificity }
            .first { $0.matches(url) }
    }

    func requestOptions(for url: URL, explicitReferer: String? = nil) -> HTTPRequestOptions {
        siteRequestHeaderService.requestOptions(
            for: url,
            explicitReferer: explicitReferer,
            siteRules: libraryStore.siteRules
        )
    }

    private func applyingHeaderRules(to resolved: ResolvedDownload) -> ResolvedDownload {
        siteRequestHeaderService.applyingHeaderRules(
            to: resolved,
            siteRules: libraryStore.siteRules
        )
    }

    private func assetWithHeaderRules(_ asset: ResolvedAsset) -> ResolvedAsset {
        siteRequestHeaderService.applyingHeaderRules(
            to: asset,
            siteRules: libraryStore.siteRules
        )
    }

    private func templatedFolderName(for resolved: ResolvedDownload, sourceURL: URL) -> String {
        outputNamingService.folderName(
            for: resolved,
            sourceURL: sourceURL,
            template: settingsStore.folderNameTemplate
        )
    }

    private func templatedAssets(_ assets: [ResolvedAsset], title: String, sourceURL: URL, metadata: [String: String]) -> [ResolvedAsset] {
        let template = effectiveFileNameTemplate(for: sourceURL, metadata: metadata)
        return outputNamingService.assets(
            assets,
            title: title,
            sourceURL: sourceURL,
            metadata: metadata,
            fileNameTemplate: template
        )
    }

    private nonisolated static func nameTemplateIndex(for asset: ResolvedAsset, fallback: Int) -> Int {
        OutputNamingService.nameTemplateIndex(
            for: asset,
            fallback: fallback
        )
    }

    nonisolated static func mergedNameTemplateMetadata(_ metadata: [String: String], assetMetadata: [String: String]) -> [String: String] {
        OutputNamingService.mergedNameTemplateMetadata(
            metadata,
            assetMetadata: assetMetadata
        )
    }

    private func templatedConcatenatedFileName(
        original: String,
        title: String,
        sourceURL: URL,
        total: Int?,
        metadata: [String: String],
        packageMode: DownloadPackageMode
    ) -> String {
        outputNamingService.concatenatedFileName(
            original: original,
            title: title,
            sourceURL: sourceURL,
            total: total,
            metadata: metadata,
            packageMode: packageMode,
            fileNameTemplate: effectiveFileNameTemplate(
                for: sourceURL,
                metadata: metadata
            ),
            recordingFileNameTemplate: settingsStore.recordingFileNameTemplate
        )
    }

    nonisolated static func shouldUseRecordingFileNameTemplate(packageMode: DownloadPackageMode, metadata: [String: String]) -> Bool {
        OutputNamingService.shouldUseRecordingFileNameTemplate(
            packageMode: packageMode,
            metadata: metadata
        )
    }

    private func effectiveFileNameTemplate(for sourceURL: URL, metadata: [String: String]) -> String {
        let sourceID = DownloadSourceFolderProfile.sourceID(for: sourceURL, metadata: metadata)
        return sourceFileNameTemplate(for: sourceID).trimmed
    }

    private func templatedFileName(
        original: String,
        title: String,
        sourceURL: URL,
        index: Int?,
        total: Int?,
        metadata: [String: String] = [:],
        templateOverride: String? = nil
    ) -> String {
        outputNamingService.fileName(
            original: original,
            title: title,
            sourceURL: sourceURL,
            index: index,
            total: total,
            metadata: metadata,
            template: effectiveFileNameTemplate(
                for: sourceURL,
                metadata: metadata
            ),
            templateOverride: templateOverride
        )
    }

    private func nameTemplateContext(title: String, sourceURL: URL, filename: String, index: Int?, total: Int?, metadata: [String: String] = [:]) -> NameTemplateContext {
        outputNamingService.nameTemplateContext(
            title: title,
            sourceURL: sourceURL,
            filename: filename,
            index: index,
            total: total,
            metadata: metadata
        )
    }

    nonisolated static func templateDate(from metadata: [String: String]) -> String? {
        OutputNamingService.templateDate(from: metadata)
    }

    nonisolated static func templateIdentifier(from metadata: [String: String]) -> String? {
        OutputNamingService.templateIdentifier(from: metadata)
    }

    private func outputRoot(for sourceURL: URL, metadata: [String: String] = [:]) throws -> URL {
        let sourceID = DownloadSourceFolderProfile.sourceID(for: sourceURL, metadata: metadata)
        return try outputService.prepareOutputRoot(
            OutputRootRequest(
                destinationPath: settingsStore.destinationPath,
                subfolderMode: settingsStore.outputSubfolderMode,
                sourceFolderName: effectiveSourceFolderName(for: sourceID),
                dateFolderName: Self.dateFolderName()
            )
        )
    }

#if TESTING
    func testingOutputRoot(for sourceURL: URL, metadata: [String: String] = [:]) throws -> URL {
        try outputRoot(for: sourceURL, metadata: metadata)
    }

    func testingEffectiveFileNameTemplate(
        for sourceURL: URL,
        metadata: [String: String] = [:]
    ) -> String {
        effectiveFileNameTemplate(for: sourceURL, metadata: metadata)
    }

    func testingTemplatedFileName(
        original: String,
        title: String,
        sourceURL: URL,
        index: Int?,
        total: Int?,
        metadata: [String: String] = [:]
    ) -> String {
        templatedFileName(
            original: original,
            title: title,
            sourceURL: sourceURL,
            index: index,
            total: total,
            metadata: metadata
        )
    }
#endif

    private nonisolated static func dateFolderName(_ date: Date = Date()) -> String {
        OutputNamingService.dateFolderName(date)
    }

    private func persistSearchProviders() {
        userData.searchProviders = searchStore.searchProviders
        persistUserData()
    }

    private func persistBookmarks() {
        userData.bookmarks = libraryStore.bookmarks
        persistUserData()
    }

    private func persistHistory() {
        userData.history = libraryStore.history
        persistUserData()
    }

    private func persistSiteRules() {
        userData.siteRules = libraryStore.siteRules
        persistUserData()
    }

    private func persistSearchBookmarks() {
        userData.searchBookmarks = searchStore.searchBookmarks
        persistUserData()
    }

    private func persistQueueFilterBookmarks() {
        userData.queueFilterBookmarks = queueStore.queueFilterBookmarks
        persistUserData()
    }

    private func persistQueue() {
        persistUserData()
    }

    private func persistInputTextDraft() {
        guard userData.inputTextDraft != presentation.inputText else { return }
        userData.inputTextDraft = presentation.inputText
        persistUserData()
    }

    private func persistUserData() {
        persistenceService.replaceQueue(with: queueStore.persistenceSnapshot(
            orderedJobs: queueOrderedJobs
        ))
        userData.queueFilterBookmarks = queueStore.queueFilterBookmarks
        userData.inputTextDraft = presentation.inputText
        if persistenceService.save() {
            appStatusStore.setPersistenceWarning("")
        } else {
            let warning = "Storage warning: queue list could not be saved. Check disk space or permissions."
            if appStatusStore.persistenceWarning != warning {
                presentation.showingStorageWarning = true
            }
            appStatusStore.setPersistenceWarning(warning)
            addSummary = warning
        }
    }

    private func normalizeActiveQueueOrder() {
        guard let orderedJobs = queueScheduler.finishRun(reordering: queueStore.jobs) else { return }
        queueStore.replaceJobs(with: orderedJobs)
    }

    func setHTTPViewerLazyLoading(_ enabled: Bool) {
        guard settingsStore.httpViewerLazyLoading != enabled else { return }
        settingsStore.httpViewerLazyLoading = enabled
        settingsStore.persistHTTPAPISettings()
        addSummary = enabled ? "HTTP viewer lazy loading on" : "HTTP viewer lazy loading off"
    }

    var browserExtensionListeningPort: UInt16? {
        browserExtensionServer?.listeningPort
    }

    private func startBrowserExtensionServer() {
        stopBrowserExtensionServer()
        let portString = Self.environmentPort("HITOMI_NATIVE_BROWSER_EXTENSION_PORT")
            ?? String(BrowserExtensionServer.defaultPort)
        guard let port = UInt16(portString), port > 0 else {
            networkStore.setBrowserExtensionStatus(
                "Browser extension port is invalid"
            )
            return
        }

        let server = BrowserExtensionServer(port: port) { [weak self] message in
            guard let self else { return .rejected }
            return await self.handleBrowserExtensionMessage(message)
        }
        do {
            try server.start()
            browserExtensionServer = server
            networkStore.setBrowserExtensionStatus(
                "ws://127.0.0.1:\(server.listeningPort ?? port)"
            )
        } catch {
            networkStore.setBrowserExtensionStatus(
                "Browser extension unavailable"
            )
            recordActivity("Browser extension server failed on port \(port)", category: "App")
        }
    }

    private func stopBrowserExtensionServer() {
        browserExtensionServer?.stop()
        browserExtensionServer = nil
        networkStore.setBrowserExtensionStatus("Browser extension off")
    }

    private func handleBrowserExtensionMessage(_ message: String) async -> BrowserExtensionMessageResult {
        if let payload = OriginalBrowserExtensionCookiePayload.parse(message) {
            let result = await CookieStore.shared.replaceBrowserExtensionCookies(payload)
            cookieStatusStore.setSummary(
                sourceAuthenticationPolicy.browserCookieSummary(
                    imported: result.imported,
                    skipped: result.skipped
                )
            )
            addSummary = result.imported > 0 ? "Browser extension cookies updated" : "No browser cookies found"
            return .accepted
        }

        guard OriginalBrowserExtensionTask.parse(message) != nil else {
            recordActivity("Browser extension rejected an invalid message", category: "App")
            return .rejected
        }
        let items = inputItems(from: message)
        guard !items.isEmpty else {
            recordActivity("Browser extension rejected an invalid task URL", category: "App")
            return .rejected
        }

        let newJobs = jobsForAdding(items, promptForDuplicates: true)
        if !newJobs.isEmpty {
            insertAddedJobsAtTop(newJobs)
            persistQueue()
            runQueuedJobsIfEnabled()
        }
        return .accepted
    }

    private func startHTTPAPIServer() {
        stopHTTPAPIServer()
        settingsStore.persistHTTPAPISettings()

        guard let portValue = UInt16(settingsStore.httpAPIPortString),
              portValue > 0 else {
            settingsStore.httpAPIEnabled = false
            networkStore.setHTTPAPIStatus("Invalid HTTP API Port")
            addSummary = networkStore.httpAPIStatus
            settingsStore.persistHTTPAPISettings()
            return
        }

        do {
            try localAPIServerCoordinator.start(
                port: portValue
            ) { [weak self] request in
                guard let self else {
                    return LocalHTTPResponse.jsonObject(
                        ["error": "App is closing"],
                        status: 503
                    )
                }
                return await self.response(forAPIRequest: request)
            }
            networkStore.setHTTPAPIStatus(
                "http://127.0.0.1:\(portValue)"
            )
        } catch {
            settingsStore.httpAPIEnabled = false
            networkStore.setHTTPAPIStatus("HTTP API Failed to Start")
            addSummary = "HTTP API Failed to Start"
            settingsStore.persistHTTPAPISettings()
        }
    }

    private func stopHTTPAPIServer() {
        localAPIServerCoordinator.stop()
        networkStore.setHTTPAPIStatus("HTTP API Off")
    }

    private func response(forAPIRequest request: LocalHTTPRequest) async -> LocalHTTPResponse {
        await localAPIFacade.response(
            for: request,
            password: settingsStore.httpAPIPassword,
            operations: LocalAPIFacadeOperations(
                staticAsset: { [self] request in
                    apiStaticAssetResponse(request)
                },
                login: { [self] request in
                    localAPILoginService.response(
                        for: request,
                        password: settingsStore.httpAPIPassword
                    )
                },
                loginRedirect: { [self] request in
                    localAPILoginService.redirectResponse(for: request)
                },
                authorized: { [self] route, request in
                    await response(
                        forAuthorizedAPIRequest: request,
                        route: route
                    )
                }
            )
        )
    }

    private func response(
        forAuthorizedAPIRequest request: LocalHTTPRequest,
        route: LocalAPIRoute
    ) async -> LocalHTTPResponse {
        switch route {
        case .index:
            return LocalHTTPResponse.html(apiIndexPage(passwordQuery: request.query["pw"] ?? request.query["password"] ?? ""))
        case .webUI:
            return LocalHTTPResponse.html(apiWebUI(request))
        case .docs:
            return LocalHTTPResponse.html(apiDocsPage(passwordQuery: request.query["pw"] ?? request.query["password"] ?? ""))
        case .aboutPage:
            return LocalHTTPResponse.html(apiAboutPage(request))
        case .aboutObject:
            return LocalHTTPResponse.jsonObject(Self.appAboutObject())
        case .helpPage:
            return LocalHTTPResponse.html(apiHelpPage(request))
        case .helpObject:
            return LocalHTTPResponse.jsonObject(Self.appHelpObject())
        case .list:
            return LocalHTTPResponse.html(apiListPage(request))
        case .view:
            return apiViewResponse(request)
        case .file:
            return apiFileResponse(request)
        case .thumbnail:
            return await apiThumbResponse(request)
        case .events:
            return apiEventsResponse()
        case .webSocket:
            return apiWebSocketResponse(request)
        case .status:
            return LocalHTTPResponse.jsonObject(apiStatusObject())
        case .logPage:
            return LocalHTTPResponse.html(apiLogPage(request))
        case .logObject:
            return LocalHTTPResponse.jsonObject(apiLogObject(request))
        case .clearLog:
            return apiLogClearResponse(request)
        case .directoriesPage:
            return LocalHTTPResponse.html(apiDirectoriesPage(request))
        case .directoriesObject:
            return LocalHTTPResponse.jsonObject(apiDirectoriesObject(request))
        case .finderPage:
            return LocalHTTPResponse.html(apiFinderPage(request))
        case .finderObject:
            return LocalHTTPResponse.jsonObject(apiFinderObject(request))
        case .analysisPage:
            return LocalHTTPResponse.html(apiAnalysisPage(request))
        case .analysisObject:
            return LocalHTTPResponse.jsonObject(apiAnalysisObject(request))
        case .statistics:
            return LocalHTTPResponse.jsonObject(apiStatisticsObject())
        case .version:
            return LocalHTTPResponse.jsonObject(Self.appVersionObject())
        case .count:
            return LocalHTTPResponse.jsonObject(["count": visibleQueueOrderedJobs.count])
        case .items:
            return LocalHTTPResponse.jsonObject(apiItemsObject(request))
        case .historyPage:
            return LocalHTTPResponse.html(apiHistoryPage(request))
        case .historyObject:
            return LocalHTTPResponse.jsonObject(apiHistoryObject(request))
        case .requeueHistory:
            return apiHistoryRequeueResponse(request)
        case .removeHistory:
            return apiHistoryRemoveResponse(request)
        case .clearHistory:
            return apiHistoryClearResponse(request)
        case .searchPage:
            return LocalHTTPResponse.html(apiSearchPage(request))
        case .search:
            return apiSearchResponse(request)
        case .searchProviders:
            return LocalHTTPResponse.jsonObject(apiSearchProvidersObject(request))
        case .enqueueSearch:
            return apiSearchEnqueueResponse(request)
        case .clipboardPage:
            return LocalHTTPResponse.html(apiClipboardPage(request))
        case .clipboardObject:
            return LocalHTTPResponse.jsonObject(apiClipboardObject(request))
        case .enqueueClipboard:
            return apiClipboardEnqueueResponse(request)
        case .watchClipboard:
            return apiClipboardWatchResponse(request)
        case .browserPage:
            return LocalHTTPResponse.html(apiBrowserPage(request))
        case .browserObject:
            return LocalHTTPResponse.jsonObject(apiBrowserObject(request))
        case .openBrowser:
            return apiBrowserOpenResponse(request)
        case .textPage:
            return LocalHTTPResponse.html(apiTextPage(request))
        case .text:
            return apiTextResponse(request)
        case .pageSelectorPage:
            return LocalHTTPResponse.html(apiPageSelectorPage(request))
        case .pageSelectorObject:
            return LocalHTTPResponse.jsonObject(apiPageSelectorObject(request))
        case .updatePageSelector:
            return apiPageSelectorUpdateResponse(request)
        case .item:
            return apiInfoResponse(request)
        case .originalNames:
            return apiNamesResponse(request, originalShape: true)
        case .names:
            return apiNamesResponse(request, originalShape: false)
        case .types:
            return LocalHTTPResponse.jsonObject(apiTypesObject(request))
        case .headers:
            return LocalHTTPResponse.jsonObject(apiHeadersObject(request))
        case .info:
            return apiInfoResponse(request)
        case .pdf:
            return apiPDFResponse(request)
        case .archive:
            return apiArchiveResponse(request)
        case .download:
            let items = apiInputItems(from: request)
            let parameters = apiParameters(from: request)
            return localAPIQueueCommandService.enqueueInput(
                hasInput: !items.isEmpty,
                shouldStart: (
                    parameters["start"] ??
                        parameters["run"] ?? "1"
                ) != "0",
                usesOriginalActionShape: apiUsesOriginalActionShape(
                    request
                ),
                enqueue: { [self] in
                    enqueueInputItems(items)
                },
                start: { [self] in
                    startQueue(addingInput: false)
                },
                state: { [self] in
                    localAPIQueueCommandState()
                }
            )
        case .execute:
            return await apiExecResponse(request)
        case .start:
            return localAPIQueueCommandService.start(
                action: { [self] in
                    startQueue(addingInput: false)
                },
                state: { [self] in
                    localAPIQueueCommandState()
                }
            )
        case .stop:
            return localAPIQueueCommandService.stop(
                action: { [self] in cancelQueue() },
                state: { [self] in
                    localAPIQueueCommandState()
                }
            )
        case .pause:
            return apiAria2RuntimeControlResponse(request, pause: true)
        case .resume:
            return apiAria2RuntimeControlResponse(request, pause: false)
        case .aria2Limits:
            return await apiAria2RuntimeLimitsResponse(request)
        case .aria2FileSelection:
            return await apiAria2RuntimeFileSelectionResponse(request)
        case .aria2Seeding:
            return await apiAria2RuntimeSeedingResponse(request)
        case .aria2FileList:
            return await apiAria2FileListResponse(request)
        case .aria2Peers:
            return await apiAria2PeersResponse(request)
        case .clear:
            return localAPIQueueCommandService.clearFinished(
                action: { [self] in clearFinished() },
                state: { [self] in
                    localAPIQueueCommandState()
                }
            )
        case .complete:
            return apiCompleteResponse(request)
        case .comment:
            return apiCommentResponse(request)
        case .save:
            return localAPIQueueCommandService.save(
                persistQueue: { [self] in persistQueue() },
                persistSettings: { [self] in
                    settingsStore.persistHTTPAPISettings()
                },
                state: { [self] in
                    localAPIQueueCommandState()
                }
            )
        case .updateCookies:
            return await apiUpdateCookiesResponse(request)
        case .remove:
            return apiRemoveResponse(request)
        case .delete:
            return apiDeleteResponse(request)
        case .deleteFile:
            return apiDeleteFileResponse(request)
        case .preflight, .staticAsset, .login, .notFound:
            return LocalHTTPResponse.jsonObject(["error": "Not found"], status: 404)
        }
    }

    private func enqueueURLStrings(_ urls: [String]) -> Int {
        let newJobs = jobsForAdding(urls)
        guard !newJobs.isEmpty else { return 0 }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
        return newJobs.count
    }

    private func enqueueInputItems(_ items: [(url: String, metadata: [String: String])]) -> Int {
        let newJobs = jobsForAdding(items)
        guard !newJobs.isEmpty else { return 0 }
        insertAddedJobsAtTop(newJobs)
        persistQueue()
        return newJobs.count
    }

    private func localAPIQueueCommandState() -> LocalAPIQueueCommandState {
        LocalAPIQueueCommandState(
            count: queueStore.jobs.count,
            isRunning: queueStore.isRunning,
            apiStatus: networkStore.httpAPIStatus
        )
    }

    private func apiStatusObject() -> [String: Any] {
        let visibleJobs = visibleQueueOrderedJobs
        return localAPIDiagnosticFacade.statusObject(
            LocalAPIStatusSnapshot(
                now: Date(),
                startedAt: appStartedAt,
                isRunning: queueStore.isRunning,
                jobs: visibleJobs,
                downloadSpeedBytesPerSecond: currentDownloadSpeedBytesPerSecond(),
                downloadedSinceLaunchBytes: downloadedSinceAppStartByteCount(),
                uploadSpeedBytesPerSecond: currentUploadSpeedBytesPerSecond(),
                itemObjects: apiJobObjects()
            )
        )
    }

    private func apiLogObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPIDiagnosticFacade.logObject(
            request: request,
            entries: appStatusStore.activityLog,
            limit: AppStatusStore.activityLogLimit
        )
    }

    private func apiDirectoriesObject(_ request: LocalHTTPRequest) -> [String: Any] {
        let entries = outputDirectoryEntries()
        return localAPIDiagnosticFacade.directoriesObject(
            request: request,
            entries: entries
        ) { [self] visible in
            outputDirectoriesText(entries: visible)
        }
    }

    private func apiFinderObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPIDiagnosticFacade.finderObject(request: request) { [self] build in
            metadataFinderResults(
                field: build.field,
                query: build.query,
                mode: build.mode,
                limit: build.limit
            )
        }
    }

    private func apiAnalysisObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPIDiagnosticFacade.analysisObject(request: request) { [self] build in
            metadataAnalysisEntries(
                field: build.field,
                limit: build.limit
            )
        }
    }

    private func apiStatisticsObject() -> [String: Any] {
        localAPIDiagnosticFacade.statisticsObject(statisticsSnapshot())
    }

    private func apiEventsResponse() -> LocalHTTPResponse {
        localAPIDiagnosticFacade.eventsResponse(
            statusObject: apiStatusObject()
        )
    }

    private func apiWebSocketResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIDiagnosticFacade.webSocketResponse(
            request: request,
            statusObject: apiStatusObject()
        )
    }

    private func apiJobObjects() -> [[String: Any]] {
        apiJobObjects(in: visibleQueueOrderedJobs.indices)
    }

    private func apiItemsObject(_ request: LocalHTTPRequest) -> [String: Any] {
        let rangeInfo = apiItemRange(from: request)
        return [
            "items": apiJobObjects(in: rangeInfo.range),
            "count": rangeInfo.range.count,
            "total": rangeInfo.total,
            "start": rangeInfo.range.lowerBound,
            "end": rangeInfo.range.isEmpty ? rangeInfo.range.lowerBound : rangeInfo.range.upperBound - 1,
            "endExclusive": rangeInfo.range.upperBound
        ]
    }

    private func apiItemRange(from request: LocalHTTPRequest) -> APIItemRange {
        apiRange(from: request, total: visibleQueueOrderedJobs.count)
    }

    private func apiRange(from request: LocalHTTPRequest, total: Int) -> APIItemRange {
        localAPIDiagnosticFacade.range(from: request, total: total)
    }

    private func apiJobObjects(in range: Range<Int>) -> [[String: Any]] {
        let orderedJobs = visibleQueueOrderedJobs
        return localAPIJobPresentationService.objects(
            jobs: orderedJobs,
            in: range
        ) { [self] job in
            LocalAPIJobRuntimePresentation(
                isPaused: aria2Store.isRuntimePaused(jobID: job.id),
                handler: externalToolRuntime.processControl(
                    for: job.id,
                    kind: .aria2
                ) == nil ? "" : "aria2",
                canLimit: canApplyAria2RuntimeLimits(for: job),
                canSelectFiles: canApplyAria2RuntimeFileSelection(for: job),
                canSeed: canApplyAria2RuntimeSeeding(for: job),
                canListFiles: canPreviewAria2Files(for: job),
                canShowPeers: canRefreshAria2Peers(for: job)
            )
        }
    }

    private func apiHistoryObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPIHistoryFacade.object(
            request: request,
            history: libraryStore.history,
            enabled: settingsStore.historyEnabled,
            limit: settingsStore.historyLimit,
            authQuery: { [self] password in apiAuthQuery(password) }
        )
    }

    private func apiHistoryRequeueResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIHistoryFacade.requeueResponse(
            request: request,
            history: libraryStore.history,
            enqueue: { [self] entry in
                let before = queueStore.jobs.count
                enqueueHistoryEntry(entry)
                return queueStore.jobs.count - before
            },
            startQueue: { [self] in
                startQueue(addingInput: false)
            },
            queueState: { [self] in
                (queueStore.jobs.count, queueStore.isRunning)
            }
        )
    }

    private func apiHistoryRemoveResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        var history = libraryStore.history
        return localAPIHistoryFacade.removeResponse(
            request: request,
            history: &history,
            persist: { [self] updatedHistory in
                libraryStore.replaceHistory(with: updatedHistory)
                persistHistory()
            }
        )
    }

    private func apiHistoryClearResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIHistoryFacade.clearResponse(
            historyCount: libraryStore.history.count,
            clear: { [self] in
                clearHistory()
                return libraryStore.history.count
            }
        )
    }

    private func apiSearchResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPISearchFacade.response(
            request: request,
            providers: searchStore.searchProviders,
            bookmarks: searchStore.searchBookmarks,
            selectedProviderID: searchStore.selectedSearchProviderID,
            selectedProvider: currentSearchProvider()
        )
    }

    private func apiSearchProvidersObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPISearchFacade.providersObject(
            request: request,
            providers: searchStore.searchProviders,
            bookmarks: searchStore.searchBookmarks,
            selectedProvider: currentSearchProvider()
        )
    }

    private func apiSearchEnqueueResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPISearchFacade.enqueueResponse(
            request: request,
            providers: searchStore.searchProviders,
            selectedProviderID: searchStore.selectedSearchProviderID,
            enqueue: { [self] url in
                enqueueURLStrings([url])
            },
            startQueue: { [self] in
                startQueue(addingInput: false)
            },
            queueState: { [self] in
                (queueStore.jobs.count, queueStore.isRunning)
            }
        )
    }

    private func apiClipboardObject(_ request: LocalHTTPRequest, explicitText: String? = nil, source: String? = nil) -> [String: Any] {
        localAPIInputFacade.clipboardObject(
            request: request,
            explicitText: explicitText,
            source: source,
            monitorEnabled: settingsStore.clipboardMonitorEnabled,
            changeCount: clipboardCommandService.currentChangeCount,
            clipboardText: { [self] in clipboardInputText() },
            candidateURLs: { [self] text in
                clipboardCandidateURLs(from: text)
            },
            inputTypeObjects: { [self] text in
                localAPITaskMetadataService.inputTypeObjects(
                    from: text,
                    quickSearchURL: { [self] line in
                        quickSearchURLString(from: line)
                    },
                    classify: { [self] source, url in
                        apiInputClassification(
                            for: source,
                            url: url
                        )
                    }
                )
            }
        )
    }

    private func apiClipboardEnqueueResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIInputFacade.clipboardEnqueueResponse(
            request: request,
            monitorEnabled: settingsStore.clipboardMonitorEnabled,
            clipboardText: { [self] in clipboardInputText() },
            candidateURLs: { [self] text in
                clipboardCandidateURLs(from: text)
            },
            enqueue: { [self] urls in enqueueURLStrings(urls) },
            startQueue: { [self] in startQueue(addingInput: false) },
            queueState: { [self] in (queueStore.jobs.count, queueStore.isRunning) }
        )
    }

    private func apiClipboardWatchResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIInputFacade.clipboardWatchResponse(
            request: request,
            currentEnabled: settingsStore.clipboardMonitorEnabled,
            setEnabled: { [self] enabled in
                setClipboardMonitorEnabled(enabled)
            },
            currentState: { [self] in
                (settingsStore.clipboardMonitorEnabled, addSummary)
            }
        )
    }

    private func apiBrowserObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPIInputFacade.browserObject(
            request: request,
            inputText: presentation.inputText,
            cookieSummary: cookieStatusStore.summary,
            parameterURL: { [self] raw in
                sourceAuthenticationPolicy.firstWebURL(
                    from: raw,
                    normalizingToken:
                        Self.normalizedInputToken
                )
            },
            fallbackURL: { [self] in
                sourceAuthenticationPolicy.loginBrowserURL(
                    inputText: presentation.inputText,
                    jobs: queueStore.jobs,
                    normalizingToken:
                        Self.normalizedInputToken
                )
            }
        )
    }

    private func apiBrowserOpenResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIInputFacade.browserOpenResponse(
            request: request,
            inputText: presentation.inputText,
            cookieSummary: cookieStatusStore.summary,
            parameterURL: { [self] raw in
                sourceAuthenticationPolicy.firstWebURL(
                    from: raw,
                    normalizingToken: Self.normalizedInputToken
                )
            },
            fallbackURL: { [self] in
                sourceAuthenticationPolicy.loginBrowserURL(
                    inputText: presentation.inputText,
                    jobs: queueStore.jobs,
                    normalizingToken: Self.normalizedInputToken
                )
            },
            openBrowser: { [self] url in
                openLoginBrowser(
                    url: url,
                    authenticationKey: nil
                )
                addSummary = "Login browser opened"
            }
        )
    }

#if TESTING
    func testingAPIBrowserOpenResponse(
        query: [String: String]
    ) -> LocalHTTPResponse {
        apiBrowserOpenResponse(
            LocalHTTPRequest(
                method: "POST",
                path: "/api/browser/open",
                query: query,
                headers: [:],
                body: Data()
            )
        )
    }
#endif

    private func apiNamesResponse(
        _ request: LocalHTTPRequest,
        originalShape: Bool
    ) -> LocalHTTPResponse {
        localAPITaskMetadataService.namesResponse(
            request: request,
            originalShape: originalShape,
            jobs: queueStore.jobs,
            selectedJobIndex: apiJobIndex(from: request),
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
    }
    private func apiUsesOriginalActionShape(_ request: LocalHTTPRequest) -> Bool {
        if request.path.lowercased().hasPrefix("/api/") {
            return false
        }

        let parameters = apiParameters(from: request)
        let shape = (parameters["format"] ??
            parameters["shape"] ??
            parameters["response"] ??
            "").trimmed.lowercased()
        if ["object", "native", "full", "detail", "details"].contains(shape) {
            return false
        }
        return !Self.apiTruthy(parameters["native"]) &&
            !Self.apiTruthy(parameters["details"])
    }

    private func apiTypesObject(
        _ request: LocalHTTPRequest? = nil
    ) -> [String: Any] {
        localAPITaskMetadataService.typesObject(
            request: request,
            jobs: queueStore.jobs,
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            },
            quickSearchURL: { [self] line in
                quickSearchURLString(from: line)
            },
            classify: { [self] source, url in
                apiInputClassification(
                    for: source,
                    url: url
                )
            }
        )
    }
    private func apiInputClassification(
        for source: String,
        url: URL?
    ) -> SourceInputClassification {
        sourceInputClassificationService.classification(
            for: source,
            url: url,
            pawchiveSiteAddresses: settingsStore.pawchiveSiteAddresses,
            siteRules: libraryStore.siteRules
        )
    }
    private func apiHeadersObject(
        _ request: LocalHTTPRequest
    ) -> [String: Any] {
        localAPITaskMetadataService.headersObject(
            request: request,
            port: settingsStore.httpAPIPortString,
            password: settingsStore.httpAPIPassword
        )
    }

    private func apiUpdateCookiesResponse(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        let outcome = await localAPICookieService.updateResponse(
            for: request
        )
        if let summary = outcome.cookieSummary {
            cookieStatusStore.setSummary(summary)
        }
        return outcome.response
    }

    private func apiInfoResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let jobIndex = apiJobIndex(from: request) else {
            return LocalHTTPResponse.jsonObject(["error": "Task not found"], status: 404)
        }

        let password = request.query["pw"] ?? request.query["password"] ?? ""
        let logicalIndex = queueOrderedJobIndices.firstIndex(of: jobIndex) ?? jobIndex
        let job = queueStore.jobs[jobIndex]
        let info = apiJobInfoObject(job: job, index: logicalIndex, auth: apiAuthQuery(password))
        let legacy = OriginalHDT.lightTaskObject(job, pageCount: info["fileCount"] as? Int)
        var response = info
        for (key, value) in legacy where response[key] == nil {
            response[key] = value
        }
        response["item"] = legacy
        return LocalHTTPResponse.jsonObject(response)
    }

    private func apiPDFResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        let jobIndex = apiJobIndex(from: request)
        return localAPIOutputCommandService.pdfResponse(
            for: request,
            job: jobIndex.map { queueStore.jobs[$0] },
            index: jobIndex
        ) { [self] updatedJob in
            guard let jobIndex else { return }
            queueStore.replaceJob(at: jobIndex, with: updatedJob)
            persistQueue()
        }
    }

    private func apiArchiveResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        let jobIndex = apiJobIndex(from: request)
        return localAPIOutputCommandService.archiveResponse(
            for: request,
            job: jobIndex.map { queueStore.jobs[$0] },
            index: jobIndex
        ) { [self] updatedJob in
            guard let jobIndex else { return }
            queueStore.replaceJob(at: jobIndex, with: updatedJob)
            persistQueue()
        }
    }
    private func apiJobInfoObject(job: DownloadJob, index: Int, auth: String) -> [String: Any] {
        let files = apiOutputFiles(for: job)
        return localAPIJobPresentationService.infoObject(
            job: job,
            index: index,
            auth: auth,
            files: files,
            chapters: apiChapterGroups(files),
            pdfAvailable: pdfOutputService.hasImageSources(
                fromOutputPath: job.outputPath
            )
        )
    }

    private func apiChapterGroups(_ files: [APIOutputFile]) -> [APIChapterGroup] {
        outputViewSelectionService
            .chapterGroups(in: files)
    }

    private func apiLoginPage() -> String {
        localAPICorePageRenderer.loginPage()
    }

    private func apiDocsPage(passwordQuery: String) -> String {
        localAPIDocsPageRenderer.page(password: passwordQuery)
    }

    private func apiAboutPage(_ request: LocalHTTPRequest) -> String {
        let password = request.query["pw"] ?? request.query["password"] ?? ""
        return localAPICorePageRenderer.aboutPage(
            password: password,
            about: Self.appAboutInfo()
        )
    }

    private func apiHelpPage(_ request: LocalHTTPRequest) -> String {
        let password = request.query["pw"] ?? request.query["password"] ?? ""
        return localAPICorePageRenderer.helpPage(password: password)
    }

    private func apiIndexPage(passwordQuery: String) -> String {
        localAPICorePageRenderer.indexPage(
            password: passwordQuery,
            apiEnabled: settingsStore.httpAPIEnabled,
            dateText: Self.apiDateString(Date())
        )
    }

    private func apiLogPage(_ request: LocalHTTPRequest) -> String {
        localAPIDiagnosticFacade.logPage(
            request: request,
            entries: appStatusStore.activityLog
        )
    }

    private func apiLogClearResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIDiagnosticFacade.clearLogResponse(
            request: request,
            clear: { [self] in
                appStatusStore.clearActivityLog()
                return appStatusStore.activityLog.count
            },
            standaloneAuthQuery: { [self] password in
                apiAuthStandaloneQuery(password)
            }
        )
    }

    private func apiDirectoriesPage(_ request: LocalHTTPRequest) -> String {
        let entries = outputDirectoryEntries()
        return localAPIDiagnosticFacade.directoriesPage(
            request: request,
            entries: entries
        ) { [self] visible in
            outputDirectoriesText(entries: visible)
        }
    }

    private func apiFinderPage(_ request: LocalHTTPRequest) -> String {
        localAPIDiagnosticFacade.finderPage(request: request) { [self] build in
            metadataFinderResults(
                field: build.field,
                query: build.query,
                mode: build.mode
            )
        }
    }

    private func apiAnalysisPage(_ request: LocalHTTPRequest) -> String {
        localAPIDiagnosticFacade.analysisPage(request: request) { [self] build in
            metadataAnalysisEntries(field: build.field)
        }
    }

    private func apiBrowserPage(_ request: LocalHTTPRequest) -> String {
        localAPIInputFacade.browserPage(
            request: request,
            inputText: presentation.inputText,
            cookieSummary: cookieStatusStore.summary,
            parameterURL: { [self] raw in
                sourceAuthenticationPolicy.firstWebURL(
                    from: raw,
                    normalizingToken: Self.normalizedInputToken
                )
            },
            fallbackURL: { [self] in
                sourceAuthenticationPolicy.loginBrowserURL(
                    inputText: presentation.inputText,
                    jobs: queueStore.jobs,
                    normalizingToken: Self.normalizedInputToken
                )
            }
        )
    }

    private func apiClipboardPage(_ request: LocalHTTPRequest) -> String {
        localAPIInputFacade.clipboardPage(
            request: request,
            monitorEnabled: settingsStore.clipboardMonitorEnabled,
            clipboardText: { [self] in clipboardInputText() },
            candidateURLs: { [self] text in
                clipboardCandidateURLs(from: text)
            },
            classify: { [self] url in
                apiInputClassification(
                    for: url,
                    url: URL(string: url)
                )
            }
        )
    }

    private func apiSearchPage(_ request: LocalHTTPRequest) -> String {
        localAPISearchFacade.page(
            request: request,
            providers: searchStore.searchProviders,
            bookmarks: searchStore.searchBookmarks,
            selectedProviderID: searchStore.selectedSearchProviderID,
            selectedProvider: currentSearchProvider()
        )
    }

    private func apiHistoryPage(_ request: LocalHTTPRequest) -> String {
        localAPIHistoryFacade.page(
            request: request,
            history: libraryStore.history
        )
    }

    private func apiListPage(_ request: LocalHTTPRequest) -> String {
        localAPIListFacade.page(
            request: request,
            jobs: visibleQueueOrderedJobs,
            outputFiles: { [self] job in apiOutputFiles(for: job) },
            fileSize: { [self] file in apiOutputFileSize(file) },
            modifiedDate: { [self] file in apiOutputFileModifiedDate(file) }
        )
    }

    private func apiWebUI(_ request: LocalHTTPRequest) -> String {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        let listURL = apiWebUIListURL(
            from: request,
            passwordQuery: password
        )
        return localAPIWebUIPageRenderer.page(
            passwordQuery: password,
            listURL: listURL
        )
    }

    private func apiWebUIListURL(from request: LocalHTTPRequest, passwordQuery: String) -> String {
        var queryItems: [(String, String)] = []
        for key in ["p", "step", "single"] {
            if let value = request.query[key]?.trimmed, !value.isEmpty {
                queryItems.append((key, value))
            }
        }
        if !passwordQuery.isEmpty {
            queryItems.append(("pw", passwordQuery))
        }
        guard !queryItems.isEmpty else { return "/list" }
        let query = queryItems
            .map { "\(Self.queryComponent($0.0))=\(Self.queryComponent($0.1))" }
            .joined(separator: "&")
        return "/list?\(query)"
    }

    private func apiPageSelectorObject(_ request: LocalHTTPRequest) -> [String: Any] {
        localAPIPageSelectorFacade.object(
            for: request,
            jobs: queueStore.jobs,
            selectedJobIndex: apiJobIndex(from: request),
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            },
            authQuery: { [self] password in
                apiAuthQuery(password)
            }
        )
    }

    private func apiPageSelectorPage(_ request: LocalHTTPRequest) -> String {
        localAPIPageSelectorFacade.page(
            for: request,
            jobs: queueStore.jobs,
            selectedJobIndex: apiJobIndex(from: request),
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
    }
    private func apiPageSelectorUpdateResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIPageSelectorFacade.updateResponse(
            for: request,
            jobs: queueStore.jobs,
            selectedJobIndex: apiJobIndex(from: request),
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            },
            authQuery: { [self] password in
                apiAuthQuery(password)
            }
        ) { [self] jobIndex, range in
            queueStore.updateJob(at: jobIndex) {
                $0.rangeExpression = range
            }
            if queueStore.jobs[jobIndex].status == .finished {
                scheduleRestartIfNeeded(for: queueStore.jobs[jobIndex])
            } else {
                cancelScheduledRestart(for: queueStore.jobs[jobIndex].id)
            }
            addSummary = range.isEmpty
                ? "Page range cleared"
                : "Page range updated"
            persistQueue()
        }
    }

    private func apiTextResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPITextFacade.response(
            for: request,
            jobs: queueStore.jobs,
            selectJobIndex: { [self] request in
                apiJobIndex(from: request)
            },
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            },
            authQuery: { [self] password in
                apiAuthQuery(password)
            }
        )
    }

    private func apiTextPage(_ request: LocalHTTPRequest) -> String {
        localAPITextFacade.page(
            for: request,
            jobs: queueStore.jobs,
            selectJobIndex: { [self] request in
                apiJobIndex(from: request)
            },
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            }
        )
    }

#if TESTING
    func outputContentFileSnapshotsForTesting(
        for job: DownloadJob
    ) -> [OutputContentFileSnapshotForTesting] {
        apiOutputFiles(for: job).map { file in
            OutputContentFileSnapshotForTesting(
                relativePath: file.relativePath,
                displayName:
                    Self.apiOutputDisplayName(file),
                displayPath:
                    Self.apiOutputDisplayPath(file),
                originalIndex: file.originalIndex,
                byteCount: apiOutputFileSize(file),
                isArchiveEntry:
                    file.archiveEntry != nil,
                isText:
                    localAPITextFacade.isTextFile(file)
            )
        }
    }

    func outputTextContentForTesting(
        for job: DownloadJob,
        originalIndex: Int,
        limit: Int
    ) throws -> TextViewerContentReadResult? {
        guard let file =
                apiOutputFiles(for: job)
                .first(where: {
                    $0.originalIndex == originalIndex
                }),
              localAPITextFacade.isTextFile(file) else {
            return nil
        }
        let read = try localAPITextFacade.readTextFile(
            file,
            limit: limit
        )
        return TextViewerContentReadResult(
            text: read.text,
            bytesRead: read.bytesRead,
            truncated: read.truncated
        )
    }

    func outputChapterGroupsForTesting(
        for job: DownloadJob
    ) -> [OutputChapterGroupSnapshotForTesting] {
        apiChapterGroups(
            apiOutputFiles(for: job)
        ).map {
            OutputChapterGroupSnapshotForTesting(
                title: $0.title,
                path: $0.path,
                indexes: $0.indexes
            )
        }
    }

    func selectedOutputPathsForTesting(
        for job: DownloadJob,
        query: [String: String]
    ) -> [String] {
        let request = LocalHTTPRequest(
            method: "GET",
            path: "/view",
            query: query,
            headers: [:],
            body: Data()
        )
        return localAPIViewFacade.selectedFiles(
            apiOutputFiles(for: job),
            query: request.query
        ).map(\.relativePath)
    }

    func sortedOutputPathsForTesting(
        for job: DownloadJob,
        query: [String: String]
    ) -> [String] {
        localAPIViewFacade.sortedFiles(
            apiOutputFiles(for: job),
            preferences:
                APIViewPreferences(query: query)
        ).map(\.relativePath)
    }

    func selectedChapterIndexForTesting(
        for job: DownloadJob,
        query: [String: String]
    ) -> Int? {
        let request = LocalHTTPRequest(
            method: "GET",
            path: "/view",
            query: query,
            headers: [:],
            body: Data()
        )
        return localAPIViewFacade.selectedChapterIndex(
            in: apiOutputFiles(for: job),
            query: request.query
            )
    }

    func outputFileHTTPResponseForTesting(
        method: String = "GET",
        path: String = "/file",
        query: [String: String],
        headers: [String: String] = [:]
    ) -> LocalHTTPResponse {
        apiFileResponse(
            LocalHTTPRequest(
                method: method,
                path: path,
                query: query,
                headers: headers,
                body: Data()
            )
        )
    }
#endif

    private func apiViewResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIViewFacade.response(
            for: request,
            jobs: queueStore.jobs,
            jobIndexes: apiJobIndexes(from: request),
            orderedJobIndices: queueOrderedJobIndices,
            lazyLoadingDefault: settingsStore.httpViewerLazyLoading,
            outputFiles: { [self] job in
                apiOutputFiles(for: job)
            },
            authQuery: { [self] password in
                apiAuthQuery(password)
            }
        )
    }

    private func apiFileIndexText(from request: LocalHTTPRequest) -> String? {
        localAPIViewFacade.fileIndexText(from: request)
    }

    private func apiFileResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        guard let file = apiRequestedFile(from: request) else {
            return LocalHTTPResponse.jsonObject(["error": "File not found"], status: 404)
        }
        return outputFileHTTPResponseService
            .response(
                for: file,
                request: request,
                parameters:
                    apiParameters(from: request)
            )
    }

    private func apiThumbResponse(_ request: LocalHTTPRequest) async -> LocalHTTPResponse {
        let files = apiJob(from: request).map(apiOutputFiles(for:)) ?? []
        let requested = (apiFileIndexText(from: request) != nil) ? apiRequestedFile(from: request) : nil
        let selected = requested ?? files.first { Self.imageExtensions.contains($0.url.pathExtension.lowercased()) } ?? files.first
        guard let selected else {
            return apiPlaceholderThumb(title: "No files")
        }

        let ext = selected.url.pathExtension.lowercased()
        if Self.imageExtensions.contains(ext),
           let data = try? apiOutputFileData(selected) {
            return LocalHTTPResponse.data(data, contentType: Self.mimeType(for: selected.url))
        }

        if selected.archiveEntry == nil,
           Self.videoExtensions.contains(ext),
           let data = await apiVideoThumbnailData(for: selected) {
            return LocalHTTPResponse.data(
                data,
                contentType: "image/jpeg",
                headers: ["Cache-Control": "private, max-age=3600"]
            )
        }

        return apiPlaceholderThumb(title: selected.relativePath)
    }

    private func apiVideoThumbnailData(for file: APIOutputFile) async -> Data? {
        let key = apiVideoThumbnailCacheKey(for: file.url)
        let values = try? file.url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let fileSize = values?.fileSize
        let modifiedAt = values?.contentModificationDate

        if let cached = apiVideoThumbnailCache[key],
           cached.matches(fileSize: fileSize, modifiedAt: modifiedAt) {
            return cached.data
        }

        guard let data = await MediaFileMetadataReader.thumbnailJPEGData(for: file.url) else {
            apiVideoThumbnailCache.removeValue(forKey: key)
            return nil
        }

        apiVideoThumbnailCache[key] = APIVideoThumbnailCacheEntry(
            fileSize: fileSize,
            modifiedAt: modifiedAt,
            data: data
        )
        pruneAPIVideoThumbnailCache(keeping: key)
        return data
    }

    private func pruneAPIVideoThumbnailCache(keeping key: String) {
        let maximumCachedVideoThumbnails = 128
        guard apiVideoThumbnailCache.count > maximumCachedVideoThumbnails else { return }
        let removableKeys = apiVideoThumbnailCache.keys.filter { $0 != key }
        for removable in removableKeys.prefix(apiVideoThumbnailCache.count - maximumCachedVideoThumbnails) {
            apiVideoThumbnailCache.removeValue(forKey: removable)
        }
    }

    private func apiVideoThumbnailCacheKey(for url: URL) -> String {
        url.standardizedFileURL.path
    }

    private func apiStaticAssetResponse(_ request: LocalHTTPRequest) -> LocalHTTPResponse {
        localAPIStaticAssetService.response(for: request)
    }

    private func apiCommentResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        localAPIJobCommandService.commentResponse(
            request: request,
            job: apiJob(from: request),
            update: { [self] jobID, comment in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return nil
                }
                queueStore.updateJob(at: index) {
                    $0.comment = comment
                }
                if queueStore.jobs[index].status == .finished {
                    scheduleRestartIfNeeded(for: queueStore.jobs[index])
                } else {
                    cancelScheduledRestart(for: jobID)
                }
                persistQueue()
                return queueStore.jobs[index]
            }
        )
    }
    private func apiExecResponse(
        _ request: LocalHTTPRequest
    ) async -> LocalHTTPResponse {
        await localAPIExecutionCommandService.response(
            for: request,
            operations: LocalAPIExecutionCommandOperations(
                startQueue: { [self] in
                    startQueue(addingInput: false)
                },
                stopQueue: { [self] in cancelQueue() },
                persistQueueAndSettings: { [self] in
                    persistQueue()
                    settingsStore.persistHTTPAPISettings()
                },
                clearFinished: { [self] in
                    clearFinished()
                },
                enqueueInput: { [self] request in
                    let items = apiInputItems(from: request)
                    guard !items.isEmpty else { return nil }
                    return enqueueInputItems(items)
                },
                usesOriginalActionShape: { [self] request in
                    apiUsesOriginalActionShape(request)
                },
                state: { [self] in
                    localAPIQueueCommandState()
                },
                delegatedResponse: { [self] action, request in
                    switch action {
                    case .complete:
                        return apiCompleteResponse(request)
                    case .pdf:
                        return apiPDFResponse(request)
                    case .archive:
                        return apiArchiveResponse(request)
                    case .comment:
                        return apiCommentResponse(request)
                    case .remove:
                        return apiRemoveResponse(request)
                    case .delete:
                        return apiDeleteResponse(request)
                    case .pause:
                        return apiAria2RuntimeControlResponse(
                            request,
                            pause: true
                        )
                    case .resume:
                        return apiAria2RuntimeControlResponse(
                            request,
                            pause: false
                        )
                    case .aria2Limits:
                        return await apiAria2RuntimeLimitsResponse(
                            request
                        )
                    case .aria2Files:
                        return await
                            apiAria2RuntimeFileSelectionResponse(
                                request
                            )
                    case .aria2Seed:
                        return await apiAria2RuntimeSeedingResponse(
                            request
                        )
                    case .aria2FileList:
                        return await apiAria2FileListResponse(request)
                    case .aria2Peers:
                        return await apiAria2PeersResponse(request)
                    case .updateCookies:
                        return await apiUpdateCookiesResponse(request)
                    default:
                        return nil
                    }
                }
            )
        )
    }
    private func apiAria2TargetJobIDs(
        _ request: LocalHTTPRequest
    ) -> [UUID] {
        apiJobIndexes(from: request).compactMap { index in
            queueStore.jobs.indices.contains(index) ? queueStore.jobs[index].id : nil
        }
    }

    private func apiAria2RuntimeControlResponse(
        _ request: LocalHTTPRequest,
        pause: Bool
    ) -> LocalHTTPResponse {
        localAPIAria2RuntimeService.controlResponse(
            targetJobIDs: apiAria2TargetJobIDs(request),
            pause: pause,
            apply: { [self] jobID, shouldPause in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return false
                }
                return shouldPause
                    ? pauseAria2Job(at: index, persist: false)
                    : resumeAria2Job(at: index, persist: false)
            },
            persist: { [self] in persistQueue() },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }

    private func apiAria2RuntimeLimitsResponse(
        _ request: LocalHTTPRequest
    ) async -> LocalHTTPResponse {
        await localAPIAria2RuntimeService.limitsResponse(
            request: request,
            targetJobIDs: apiAria2TargetJobIDs(request),
            defaultDownloadLimit: aria2Store.maxDownloadLimit,
            defaultUploadLimit: aria2Store.maxUploadLimit,
            apply: {
                [self] jobID,
                downloadLimit,
                uploadLimit in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return false
                }
                return await applyAria2RuntimeLimitsJob(
                    at: index,
                    downloadLimit: downloadLimit,
                    uploadLimit: uploadLimit,
                    persist: false
                )
            },
            persist: { [self] in persistQueue() },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }

    private func apiAria2RuntimeFileSelectionResponse(
        _ request: LocalHTTPRequest
    ) async -> LocalHTTPResponse {
        await localAPIAria2RuntimeService.fileSelectionResponse(
            request: request,
            targetJobIDs: apiAria2TargetJobIDs(request),
            defaultSelectedFiles: aria2Store.selectedFiles,
            apply: { [self] jobID, selectedFiles in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return nil
                }
                guard await applyAria2RuntimeFileSelectionJob(
                    at: index,
                    selectedFiles: selectedFiles,
                    persist: false
                ) else {
                    return nil
                }
                return
                    queueStore.jobs[index].metadata[
                        "runtime_selected_files"
                    ] ??
                    queueStore.jobs[index].metadata["selected_files"] ??
                    ""
            },
            persist: { [self] in persistQueue() },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }

    private func apiAria2RuntimeSeedingResponse(
        _ request: LocalHTTPRequest
    ) async -> LocalHTTPResponse {
        await localAPIAria2RuntimeService.seedingResponse(
            request: request,
            targetJobIDs: apiAria2TargetJobIDs(request),
            defaultSeedTimeMinutes: aria2Store.seedTimeMinutes,
            defaultSeedRatio: aria2Store.seedRatio,
            apply: {
                [self] jobID,
                seedTimeMinutes,
                seedRatio in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return nil
                }
                guard await applyAria2RuntimeSeedingJob(
                    at: index,
                    seedTimeMinutes: seedTimeMinutes,
                    seedRatio: seedRatio,
                    persist: false
                ) else {
                    return nil
                }
                return LocalAPIAria2SeedingResult(
                    seedTimeMinutes:
                        queueStore.jobs[index].metadata[
                            "runtime_seed_time_minutes"
                        ] ??
                        queueStore.jobs[index].metadata[
                            "seed_time_minutes"
                        ] ??
                        "",
                    seedRatio:
                        queueStore.jobs[index].metadata[
                            "runtime_seed_ratio"
                        ] ??
                        queueStore.jobs[index].metadata["seed_ratio"] ??
                        ""
                )
            },
            persist: { [self] in persistQueue() },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }

    private func apiAria2FileListResponse(
        _ request: LocalHTTPRequest
    ) async -> LocalHTTPResponse {
        await localAPIAria2RuntimeService.fileListResponse(
            targetJobIDs: apiAria2TargetJobIDs(request),
            summary: aria2Store.fileListSummary,
            load: { [self] jobID in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return nil
                }
                return await loadAria2FileEntriesJob(at: index)
            },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }

    private func apiAria2PeersResponse(
        _ request: LocalHTTPRequest
    ) async -> LocalHTTPResponse {
        await localAPIAria2RuntimeService.peersResponse(
            targetJobIDs: apiAria2TargetJobIDs(request),
            load: { [self] jobID in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return nil
                }
                return await loadAria2PeersJob(at: index)
            },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }
    private func apiCompleteResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        let selected = apiJobIndexes(from: request).map { queueStore.jobs[$0] }
        return localAPIJobCommandService.completeResponse(
            jobs: selected,
            canComplete: { [self] jobID in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return false
                }
                return canMarkJobFinished(at: index)
            },
            complete: { [self] jobID in
                guard let index = queueStore.jobs.firstIndex(
                    where: { $0.id == jobID }
                ) else {
                    return false
                }
                return markJobFinished(at: index)
            },
            jobCount: { [self] in queueStore.jobs.count }
        )
    }

    private func apiRemoveResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        let selected = apiJobIndexes(from: request).map { queueStore.jobs[$0] }
        return localAPIJobCommandService.removeResponse(
            jobs: selected,
            usesOriginalActionShape:
                apiUsesOriginalActionShape(request),
            isActive: { [self] job in
                isActive(job.status) ||
                    downloadCoordinator.isActive(job.id)
            },
            remove: { [self] selectedJobs in
                removeJobsFromQueue(selectedJobs)
            },
            updateSummary: { [self] summary in
                addSummary = summary
            },
            visibleJobCount: { [self] in
                visibleQueueOrderedJobs.count
            }
        )
    }

    private func apiDeleteResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        let selected = apiJobIndexes(from: request).map { queueStore.jobs[$0] }
        return localAPIJobCommandService.deleteResponse(
            jobs: selected,
            usesOriginalActionShape:
                apiUsesOriginalActionShape(request),
            isActive: { [self] job in
                isActive(job.status) ||
                    downloadCoordinator.isActive(job.id)
            },
            delete: { [self] jobIDs in
                let result = trashOutputsAndRemoveJobs(
                    withIDs: jobIDs
                )
                return LocalAPIJobDeletionResult(
                    removedJobCount: result.removedJobCount,
                    keptJobCount: result.keptJobCount,
                    trashedItemCount: result.trashedItemCount,
                    failedItemCount: result.failedItemCount
                )
            },
            deletionPending: { [self] jobID in
                queueStore.jobs.first(where: { $0.id == jobID }).map {
                    Self.isPendingQueueOutputDeletion($0)
                } == true
            },
            updateSummary: { [self] summary in
                addSummary = summary
            },
            visibleJobCount: { [self] in
                visibleQueueOrderedJobs.count
            }
        )
    }

    private func apiDeleteFileResponse(
        _ request: LocalHTTPRequest
    ) -> LocalHTTPResponse {
        let job = apiJob(from: request)
        return localAPIJobCommandService.deleteFileResponse(
            job: job,
            isActive: job.map { isActive($0.status) } ?? false,
            file: apiRequestedFile(from: request),
            remainingFileCount: { [self] job in
                apiOutputFiles(for: job).count
            },
            persist: { [self] in persistQueue() }
        )
    }
    private func apiRequestedFile(from request: LocalHTTPRequest) -> APIOutputFile? {
        guard let job = apiJob(from: request) else { return nil }
        let files = apiOutputFiles(for: job)
        guard !files.isEmpty else { return nil }
        let index = Int(apiFileIndexText(from: request) ?? "0") ?? 0
        guard files.indices.contains(index) else { return nil }
        return files[index]
    }

    private func apiJobIndex(
        from request: LocalHTTPRequest
    ) -> Int? {
        apiJobIndexes(from: request).first
    }

    private func apiJobIndexes(
        from request: LocalHTTPRequest
    ) -> [Int] {
        localAPITaskSelectionService.indexes(
            from: request,
            jobs: queueStore.jobs,
            visibleOrderedJobIndices:
                visibleQueueOrderedJobIndices,
            isPendingRemoval: Self.isPendingQueueRemoval
        )
    }
    private func apiJob(from request: LocalHTTPRequest) -> DownloadJob? {
        apiJobIndex(from: request).map { queueStore.jobs[$0] }
    }

    private func apiOutputFiles(for job: DownloadJob) -> [APIOutputFile] {
        outputContentFileService.files(
            at: job.outputPath
        )
    }

    private nonisolated static func isArchiveOutputFile(_ url: URL) -> Bool {
        OutputContentFileService
            .isArchiveOutputFile(url)
    }

    private func apiOutputFileData(_ file: APIOutputFile) throws -> Data {
        try OutputContentFileService.data(
            for: file
        )
    }

    private func apiOutputFileSize(_ file: APIOutputFile) -> Int {
        OutputContentFileService.fileSize(file)
    }

    private func apiOutputFileModifiedDate(_ file: APIOutputFile) -> Date? {
        OutputContentFileService.modifiedDate(file)
    }

    private static func apiOutputDisplayName(_ file: APIOutputFile) -> String {
        OutputContentFileService.displayName(file)
    }

    private static func apiOutputDisplayPath(_ file: APIOutputFile) -> String {
        OutputContentFileService.displayPath(file)
    }

    private func apiPlaceholderThumb(title: String) -> LocalHTTPResponse {
        let safeTitle = Self.htmlEscape(title)
        let svg = """
        <svg xmlns="http://www.w3.org/2000/svg" width="320" height="180" viewBox="0 0 320 180">
          <rect width="320" height="180" fill="#f1f3f4"/>
          <rect x="18" y="18" width="284" height="144" rx="10" fill="#ffffff" stroke="#d7d9dc"/>
          <text x="160" y="95" text-anchor="middle" font-family="\(Self.apiSVGFontStack)" font-size="14" fill="#5f6368">\(safeTitle)</text>
        </svg>
        """
        return LocalHTTPResponse.data(Data(svg.utf8), contentType: "image/svg+xml; charset=utf-8")
    }

    private func apiMessagePage(title: String, message: String) -> String {
        localAPIViewPageRenderer.messagePage(
            title: title,
            message: message
        )
    }

    private func apiAuthQuery(_ password: String) -> String {
        guard !password.isEmpty,
              let encoded = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ""
        }
        return "&pw=\(encoded)"
    }

    private func apiAuthStandaloneQuery(_ password: String) -> String {
        guard !password.isEmpty,
              let encoded = password.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return ""
        }
        return "?pw=\(encoded)"
    }

    private func apiInputItems(from request: LocalHTTPRequest) -> [(url: String, metadata: [String: String])] {
        localAPIRequestDecoder.inputItems(from: request) { [self] input in
            inputItems(from: input)
        }
    }

    private nonisolated static func apiTruthy(_ value: String?) -> Bool {
        LocalAPIRequestDecoder.truthy(value)
    }

    private nonisolated static func apiFirstParameterValue(in parameters: [String: String], keys: [String]) -> String? {
        LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: keys
        )
    }

    private nonisolated static func apiParameterValueAllowingEmpty(in parameters: [String: String], keys: [String]) -> String? {
        LocalAPIRequestDecoder.parameterValueAllowingEmpty(
            in: parameters,
            keys: keys
        )
    }

    private func apiParameters(from request: LocalHTTPRequest) -> [String: String] {
        localAPIRequestDecoder.parameters(from: request)
    }

    private func apiListValues(from text: String) -> [String] {
        localAPIRequestDecoder.listValues(from: text)
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static let imageExtensions =
        OutputContentFileService.imageExtensions
    private static let videoExtensions =
        OutputContentFileService.videoExtensions
    private static let audioExtensions =
        OutputContentFileService.audioExtensions
    private static let documentExtensions =
        OutputContentFileService.documentExtensions

    private static func apiMediaType(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        if imageExtensions.contains(ext) { return "image" }
        if videoExtensions.contains(ext) { return "video" }
        if audioExtensions.contains(ext) { return "audio" }
        if documentExtensions.contains(ext) { return "document" }
        return "file"
    }

    private nonisolated static func apiDateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }

    private static func mimeType(for url: URL) -> String {
        OutputFileHTTPResponseService
            .mimeType(for: url)
    }

    private static func htmlEscape(_ value: String) -> String {
        LocalAPIHTMLStyle.escape(value)
    }

    private func persistProxySettingsForUse() -> Bool {
        guard !settingsStore.dpiBypassMode.usesLocalProxy else {
            return true
        }
        return persistManualProxySettings()
    }

    private func persistManualProxySettings() -> Bool {
        if settingsStore.proxyEnabled {
            guard let normalized = NetworkSettings.normalizedProxyURLString(settingsStore.proxyURLString) else {
                addSummary = "Enter a valid proxy URL"
                return false
            }
            settingsStore.proxyURLString = normalized
        }

        settingsStore.proxyBypassList = NetworkSettings.normalizedBypassList(
            settingsStore.proxyBypassList
        )
        settingsStore.persistManualNetworkSettings()
        return true
    }

    private func startClipboardMonitor() {
        stopClipboardMonitor()
        lastClipboardChangeCount =
            clipboardCommandService
            .currentChangeCount
        scanClipboardForURLs(force: true)
        clipboardMonitorCoordinator.start { [weak self] in
            self?.scanClipboardForURLs()
        }
    }

    private func stopClipboardMonitor() {
        clipboardMonitorCoordinator.stop()
    }

    private func scanClipboardForURLs(force: Bool = false) {
        let snapshot =
            clipboardCommandService.snapshot()
        processClipboardSnapshot(
            snapshot.string,
            changeCount: snapshot.changeCount,
            force: force
        )
    }

    @discardableResult
    func processClipboardSnapshot(_ text: String?, changeCount: Int, force: Bool = false) -> Int {
        guard force || changeCount != lastClipboardChangeCount else { return 0 }
        lastClipboardChangeCount = changeCount
        guard let text, !text.trimmed.isEmpty else { return 0 }
        let added = enqueueClipboardText(text)
        if added > 0 {
            if settingsStore.playSoundOnClipboardAdd {
                completionAlerts.playClipboardSound()
            }
            addSummary = "\(added) clipboard URLs added"
        }
        return added
    }

    private nonisolated static func cleanedClipboardToken(_ raw: String) -> String {
        SourceInputNormalizer.cleanedToken(raw)
    }

    private nonisolated static func normalizedInputToken(_ raw: String) -> String {
        SourceInputNormalizer.normalizedToken(raw)
    }

    private nonisolated static func hitomiCustomURIString(from token: String) -> String? {
        SourceInputNormalizer.hitomiCustomURIString(from: token)
    }

    private nonisolated static func sankakuTagInputURLString(from raw: String) -> String? {
        SourceInputNormalizer.sankakuTagInputURLString(from: raw)
    }

    private nonisolated static func booruTagInputURLString(from raw: String) -> String? {
        SourceInputNormalizer.booruTagInputURLString(from: raw)
    }

    private static func isMonitorableURL(_ text: String) -> Bool {
        guard let url = URL(string: text), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https" || scheme == "magnet" || scheme == "file"
    }

    private static func restoredQueueJob(_ job: DownloadJob) -> DownloadJob {
        QueueRecoveryPolicy.restorePersistedJob(job)
    }

    private nonisolated static func isPendingQueueRemoval(_ job: DownloadJob) -> Bool {
        QueueJobMetadataPolicy.isPendingRemoval(job)
    }

    private nonisolated static func isPendingQueueOutputDeletion(_ job: DownloadJob) -> Bool {
        job.metadata[pendingQueueOutputDeletionMetadataKey]?.trimmed.lowercased() == "true"
    }

    private func restoredRetrySnapshot(_ snapshot: DownloadJob) -> DownloadJob {
        QueueRecoveryPolicy.restoreCancelledRetrySnapshot(snapshot)
    }

    private func isActive(_ status: JobStatus) -> Bool {
        status == .resolving || status == .downloading
    }

    private func isRetryableIncompleteJob(_ job: DownloadJob) -> Bool {
        QueueRecoveryPolicy.isRetryableIncompleteJob(
            job,
            isFolded: isFoldedQueueJob(job)
        )
    }

    private func isRemovableCompletedJob(_ job: DownloadJob) -> Bool {
        job.status == .finished &&
            (job.total <= 0 || job.completed >= job.total) &&
            !isProtected(job) &&
            !isFoldedQueueJob(job)
    }

    private func isRemovableFinishedJob(_ job: DownloadJob) -> Bool {
        !isProtected(job) && (job.status == .finished || job.status == .failed || job.status == .cancelled)
    }

    private func isFoldedQueueJob(_ job: DownloadJob) -> Bool {
        guard let groupID = jobGroupID(for: job),
              let group = queueStore.queueGroups.first(where: { $0.id == groupID }) else {
            return false
        }
        return !group.isExpanded
    }

    private func isProtected(_ job: DownloadJob) -> Bool {
        job.isLocked
    }
}

actor AsyncSemaphore {
    private var value: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = max(1, value)
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }

        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func signal() {
        if waiters.isEmpty {
            value += 1
        } else {
            waiters.removeFirst().resume()
        }
    }

    func withPermit<T: Sendable>(
        _ operation: @Sendable () async throws -> T
    ) async throws -> T {
        await wait()
        do {
            try Task.checkCancellation()
            let result = try await operation()
            signal()
            return result
        } catch {
            signal()
            throw error
        }
    }
}
