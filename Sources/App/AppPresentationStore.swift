import Combine
import Foundation

@MainActor
final class AppPresentationStore: ObservableObject {
    @Published var inputText = ""
    @Published var isURLInputFocused = false
    @Published var inputCursorUTF16Offset = 0
    @Published var inputAutocompleteSelectionIndex = 0
    @Published var isInputAutocompleteDismissed = false

    @Published var queueFilter = ""
    @Published var showingQueueControls = false
    @Published var settingsSearchText = ""
    @Published var selectedJobIDs: Set<UUID> = []
    @Published var isExternalDropTargeted = false
    @Published var draggedQueueJobIDs: Set<UUID> = []
    @Published var queueJobDropTarget: QueueJobDropTarget?

    @Published var clipboardViewerText = ""
    @Published var clipboardViewerSource = "Clipboard"
    @Published var clipboardViewerChangeCount = 0
    @Published var clipboardViewerURLs: [String] = []
    @Published var browserWindowURLText = ""
    @Published var browserWindowURLSource = "Inferred"
    @Published var textViewerFilter = ""
    @Published var textViewerSelectedEntryID = ""
    @Published var outputPreviewJobID: UUID?
    @Published var outputPreviewFiles: [OutputPreviewFile] = []
    @Published var outputPreviewIsLoading = false
    @Published var outputPreviewSelectedFileIndex = 0
    @Published var activityLogAutoRefreshAndScroll = true
    @Published var bookmarkFilter = ""
    @Published var editingBookmark: URLBookmark?
    @Published var bookmarkEditTitle = ""
    @Published var bookmarkEditTags = ""
    @Published var bookmarkEditNote = ""
    @Published var fontPreviewText = "Sekiya Asami / 1234567890 / Download queue"
    @Published var statusColorDraftPalette: JobStatusColorPalette = .defaultPalette
    @Published var shortcutEditorCommand: AppShortcutCommand = .pasteURLs
    @Published var shortcutEditorDraft: AppShortcut =
        AppShortcutCommand.pasteURLs.defaultShortcut
    @Published var shortcutEditorMessage = ""

    let settingsWindow = SettingsWindowPresentationState()
    @Published var showingSettingsWindow = false
    @Published var showingQuickAccessCustomization = false
    @Published var showingShortcutSettings = false
    @Published var showingFloatingMonitor = false
    @Published var showingStorageWarning = false
    @Published var showingJobRemovalConfirmation = false
    @Published var showingClearFinishedConfirmation = false
    @Published var showingClearBookmarksConfirmation = false
    @Published var showingRetryIncompleteJobsConfirmation = false
    @Published var showingCompletedJobsRemovalConfirmation = false
    @Published var showingOutputDeletionConfirmation = false
    @Published var showingDuplicateAdditionConfirmation = false
    @Published var showingJobGroupPrompt = false
    @Published var showingQueueGroupRemovalConfirmation = false
    @Published var showingQueueGroupRetryConfirmation = false
    @Published var showingStatistics = false
    @Published var showingActivityLog = false
    @Published var showingDirectories = false
    @Published var showingHistoryWindow = false
    @Published var showingSearcher = false
    @Published var showingMetadataFinder = false
    @Published var showingMetadataAnalysis = false
    @Published var showingDuplicateImageFinder = false
    @Published var showingClipboardViewer = false
    @Published var showingBrowserWindow = false
    @Published var showingTextViewer = false
    @Published var showingOutputPreview = false
    @Published var showingProgressWindow = false
    @Published var showingAbout = false
    @Published var showingHelp = false
    @Published var showingArtistRecommendations = false
    @Published var showingHitomiTaster = false
    @Published var showingStatusColorPicker = false
    @Published var showingFontSettings = false
}
