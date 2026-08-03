import SwiftUI

struct QueueEditorSheetRouterModifier: ViewModifier {
    let manager: DownloadManager
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var queueStore: QueueStore
    @ObservedObject var queueEditorStore: QueueEditorStore

    func body(content: Content) -> some View {
        content
            .sheet(item: $queueEditorStore.infoJob) { job in
                jobInfoView(for: job)
            }
            .sheet(item: $queueEditorStore.editingJob) { _ in
                JobEditSheet(
                    title: $queueEditorStore.jobEditTitle,
                    source: $queueEditorStore.jobEditSource,
                    input: $queueEditorStore.jobEditInput,
                    outputPath: $queueEditorStore.jobEditOutputPath,
                    artist: $queueEditorStore.jobEditArtist,
                    zipFile: $queueEditorStore.jobEditZipFile,
                    status: $queueEditorStore.jobEditStatus,
                    type: $queueEditorStore.jobEditType,
                    site: $queueEditorStore.jobEditSite,
                    date: $queueEditorStore.jobEditDate,
                    range: $queueEditorStore.jobEditRange,
                    names: queueEditorStore.jobEditNamesText,
                    comment: $queueEditorStore.jobEditComment,
                    thumbnailImage:
                        queueEditorStore.jobEditThumbnailImage,
                    thumbnailIsCustom:
                        queueEditorStore.jobEditThumbnailIsCustom,
                    thumbnailMessage:
                        queueEditorStore.jobEditThumbnailMessage,
                    selectThumbnail: {
                        manager.selectJobEditThumbnail()
                    },
                    saveThumbnail: {
                        manager.saveJobEditThumbnailAs()
                    },
                    resetThumbnail: {
                        manager.resetJobEditThumbnail()
                    },
                    cancel: {
                        manager.cancelEditingJob()
                    },
                    save: {
                        manager.saveEditingJob()
                    }
                )
            }
            .sheet(item: $queueEditorStore.pageSelectorJob) { _ in
                PageSelectorSheet(
                    manager: manager,
                    queueEditorStore: queueEditorStore
                )
            }
            .sheet(item: $presentation.editingBookmark) { bookmark in
                BookmarkEditSheet(
                    url: bookmark.url,
                    title: $presentation.bookmarkEditTitle,
                    tags: $presentation.bookmarkEditTags,
                    note: $presentation.bookmarkEditNote
                ) {
                    manager.cancelEditingBookmark()
                } save: {
                    manager.saveEditingBookmark()
                }
            }
            .sheet(item: $queueEditorStore.editingCommentJob) { job in
                JobCommentSheet(
                    title: queueEditorStore.editingCommentJobIDs.count > 1
                        ? "\(queueEditorStore.editingCommentJobIDs.count) Selected Jobs"
                        : job.title,
                    source: queueEditorStore.editingCommentJobIDs.count > 1
                        ? "Apply the comment to all selected jobs."
                        : job.source,
                    comment: $queueEditorStore.jobCommentText
                ) {
                    manager.cancelEditingJobComment()
                } save: {
                    manager.saveEditingJobComment()
                }
            }
    }

    private func jobInfoView(
        for job: DownloadJob
    ) -> JobInfoView {
        let current = queueStore.jobs.first {
            $0.id == job.id
        } ?? job
        return JobInfoView(
            job: current,
            queueIndex: manager.queueOrderIndex(
                for: current
            ),
            groupName: manager.jobGroupName(
                for: current
            )
        )
    }
}

struct AuxiliarySheetRouterModifier: ViewModifier {
    let manager: DownloadManager
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var libraryStore: LibraryStore
    @ObservedObject var queueStore: QueueStore
    @ObservedObject var queueEditorStore: QueueEditorStore
    let hostSize: CGSize

    private var rootFontSettingsPresentation: Binding<Bool> {
        Binding(
            get: {
                presentation.showingFontSettings &&
                    !presentation.showingSettingsWindow
            },
            set: {
                presentation.showingFontSettings = $0
            }
        )
    }

    func body(content: Content) -> some View {
        content
            .sheet(
                isPresented:
                    $presentation.showingSettingsWindow
            ) {
                SettingsWindowView(
                    manager: manager,
                    presentation: presentation,
                    settingsStore: settingsStore,
                    libraryStore: libraryStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingQuickAccessCustomization
            ) {
                QuickAccessCustomizationView(
                    manager: manager
                )
            }
            .sheet(
                isPresented:
                    rootFontSettingsPresentation
            ) {
                FontSettingsView(
                    manager: manager,
                    presentation: presentation
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingShortcutSettings
            ) {
                ShortcutSettingsView(
                    manager: manager,
                    presentation: presentation,
                    settingsStore: settingsStore
                )
            }
            .sheet(
                isPresented: $presentation.showingStatistics
            ) {
                StatisticsView(
                    manager: manager,
                    libraryStore: libraryStore,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented: $presentation.showingActivityLog
            ) {
                ActivityLogView(
                    presentation: presentation
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingHistoryWindow
            ) {
                HistoryWindowView(libraryStore: libraryStore)
            }
            .sheet(
                isPresented: $presentation.showingSearcher
            ) {
                SearcherWindowView(
                    manager: manager,
                    libraryStore: libraryStore,
                    queueStore: queueStore,
                    hostSize: hostSize
                )
            }
            .sheet(
                isPresented: $presentation.showingDirectories
            ) {
                DirectoriesView(
                    manager: manager,
                    libraryStore: libraryStore,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingMetadataFinder
            ) {
                MetadataFinderView(
                    manager: manager,
                    libraryStore: libraryStore,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingMetadataAnalysis
            ) {
                MetadataAnalysisView(
                    manager: manager,
                    libraryStore: libraryStore,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingDuplicateImageFinder
            ) {
                DuplicateImageFinderWindowView(
                    manager: manager
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingClipboardViewer
            ) {
                ClipboardViewerWindowView(
                    manager: manager,
                    presentation: presentation,
                    settingsStore: settingsStore,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingBrowserWindow
            ) {
                BrowserWindowView(
                    manager: manager,
                    presentation: presentation
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingTextViewer
            ) {
                TextViewerWindowView(
                    manager: manager,
                    presentation: presentation,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingProgressWindow
            ) {
                ProgressWindowView(
                    manager: manager,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented: $presentation.showingAbout
            ) {
                AboutView(
                    language: settingsStore.interfaceLanguage
                )
            }
            .sheet(
                isPresented: $presentation.showingHelp
            ) {
                HelpView()
            }
            .sheet(
                isPresented:
                    $presentation.showingStatusColorPicker
            ) {
                StatusColorPickerView(
                    manager: manager,
                    presentation: presentation,
                    settingsStore: settingsStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingArtistRecommendations
            ) {
                ArtistRecommendationsView(manager: manager)
                    .environmentObject(presentation)
                    .environmentObject(settingsStore)
                    .environmentObject(libraryStore)
                    .environmentObject(queueStore)
            }
            .sheet(
                isPresented:
                    $presentation.showingHitomiTaster
            ) {
                HitomiTasterWizardView(
                    manager: manager,
                    libraryStore: libraryStore,
                    queueStore: queueStore
                )
            }
            .sheet(
                isPresented:
                    $presentation.showingDuplicateAdditionConfirmation
            ) {
                DuplicateJobConfirmationView(
                    message:
                        queueEditorStore.duplicateAdditionMessage
                ) {
                    manager.confirmDuplicateAddition()
                } cancel: {
                    manager.cancelDuplicateAddition()
                }
            }
    }
}

private struct DuplicateJobConfirmationView: View {
    let message: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(
                    systemName:
                        "exclamationmark.triangle.fill"
                )
                .font(
                    .system(
                        size: 42,
                        weight: .semibold
                    )
                )
                .foregroundStyle(.orange)
                .frame(width: 54, height: 54)

                VStack(
                    alignment: .leading,
                    spacing: 8
                ) {
                    Text("Duplicate Tasks")
                        .font(.headline)
                    Text(message)
                        .fixedSize(
                            horizontal: false,
                            vertical: true
                        )
                }
                .frame(
                    maxWidth: .infinity,
                    alignment: .leading
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 22)

            Divider()

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel", action: cancel)
                    .keyboardShortcut(.cancelAction)
                    .frame(minWidth: 82)
                Button("OK", action: confirm)
                    .keyboardShortcut(.defaultAction)
                    .frame(minWidth: 82)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .frame(width: 460)
        .interactiveDismissDisabled()
    }
}

extension View {
    func queueEditorSheets(
        manager: DownloadManager,
        presentation: AppPresentationStore,
        queueStore: QueueStore,
        queueEditorStore: QueueEditorStore
    ) -> some View {
        modifier(
            QueueEditorSheetRouterModifier(
                manager: manager,
                presentation: presentation,
                queueStore: queueStore,
                queueEditorStore: queueEditorStore
            )
        )
    }

    func contentSheets(
        manager: DownloadManager,
        presentation: AppPresentationStore,
        settingsStore: SettingsStore,
        libraryStore: LibraryStore,
        queueStore: QueueStore,
        queueEditorStore: QueueEditorStore,
        hostSize: CGSize
    ) -> some View {
        queueEditorSheets(
            manager: manager,
            presentation: presentation,
            queueStore: queueStore,
            queueEditorStore: queueEditorStore
        )
            .modifier(
                AuxiliarySheetRouterModifier(
                    manager: manager,
                    presentation: presentation,
                    settingsStore: settingsStore,
                    libraryStore: libraryStore,
                    queueStore: queueStore,
                    queueEditorStore: queueEditorStore,
                    hostSize: hostSize
                )
            )
    }
}
