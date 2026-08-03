import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct FlatOpacitySlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double

    var body: some View {
        GeometryReader { proxy in
            let thumbDiameter: CGFloat = 14
            let travel = max(0, proxy.size.width - thumbDiameter)
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.18))
                    .frame(height: 4)
                    .padding(.horizontal, thumbDiameter / 2)

                Capsule()
                    .fill(Color.accentColor)
                    .frame(width: thumbDiameter / 2 + travel * fraction, height: 4)
                    .padding(.leading, thumbDiameter / 2)

                Capsule()
                    .fill(Color.white.opacity(0.9))
                    .overlay {
                        Capsule()
                            .stroke(Color.primary.opacity(0.24), lineWidth: 0.5)
                    }
                    .frame(width: thumbDiameter, height: 18)
                    .offset(x: travel * fraction)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        updateValue(at: gesture.location.x, width: proxy.size.width, thumbDiameter: thumbDiameter)
                    }
            )
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppLocalization.text("Window Opacity"))
        .accessibilityValue("\(Int((value * 100).rounded()))%")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment:
                value = stepped(value + step)
            case .decrement:
                value = stepped(value - step)
            @unknown default:
                break
            }
        }
    }

    private func updateValue(at x: CGFloat, width: CGFloat, thumbDiameter: CGFloat) {
        let travel = max(1, width - thumbDiameter)
        let center = min(travel, max(0, x - thumbDiameter / 2))
        let raw = range.lowerBound + Double(center / travel) * (range.upperBound - range.lowerBound)
        value = stepped(raw)
    }

    private func stepped(_ candidate: Double) -> Double {
        let clamped = min(range.upperBound, max(range.lowerBound, candidate))
        let offset = clamped - range.lowerBound
        return min(range.upperBound, max(range.lowerBound, range.lowerBound + (offset / step).rounded() * step))
    }
}

private final class QueueThumbnailScaleMenuView: NSView {
    private let titleField = NSTextField(labelWithString: "")
    private let slider: NSSlider
    private let change: (QueueThumbnailScale) -> Void

    init(scale: QueueThumbnailScale, change: @escaping (QueueThumbnailScale) -> Void) {
        self.change = change
        slider = NSSlider(
            value: Double(scale.rawValue),
            minValue: 0,
            maxValue: Double(QueueThumbnailScale.allCases.count - 1),
            target: nil,
            action: nil
        )
        super.init(frame: NSRect(x: 0, y: 0, width: 224, height: 54))

        let imageView = NSImageView(image: NSImage(
            systemSymbolName: "photo",
            accessibilityDescription: AppLocalization.text("Thumbnail Size")
        ) ?? NSImage())
        imageView.symbolConfiguration = .init(pointSize: 13, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false

        titleField.stringValue = "\(AppLocalization.text("Thumbnail Size")) \(scale.label)"
        titleField.font = .menuFont(ofSize: 0)
        titleField.translatesAutoresizingMaskIntoConstraints = false

        slider.numberOfTickMarks = QueueThumbnailScale.allCases.count
        slider.allowsTickMarkValuesOnly = true
        slider.tickMarkPosition = .below
        slider.isContinuous = true
        slider.controlSize = .small
        slider.target = self
        slider.action = #selector(sliderChanged(_:))
        slider.setAccessibilityLabel(AppLocalization.text("Thumbnail Size"))
        slider.setAccessibilityValueDescription(scale.label)
        slider.translatesAutoresizingMaskIntoConstraints = false

        addSubview(imageView)
        addSubview(titleField)
        addSubview(slider)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 13),
            imageView.topAnchor.constraint(equalTo: topAnchor, constant: 8),
            imageView.widthAnchor.constraint(equalToConstant: 16),
            imageView.heightAnchor.constraint(equalToConstant: 16),
            titleField.leadingAnchor.constraint(equalTo: imageView.trailingAnchor, constant: 7),
            titleField.centerYAnchor.constraint(equalTo: imageView.centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -12),
            slider.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 35),
            slider.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            slider.topAnchor.constraint(equalTo: titleField.bottomAnchor, constant: 1),
            slider.heightAnchor.constraint(equalToConstant: 24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: 224, height: 54)
    }

    @objc private func sliderChanged(_ sender: NSSlider) {
        let scale = QueueThumbnailScale.normalized(index: Int(sender.doubleValue.rounded()))
        sender.doubleValue = Double(scale.rawValue)
        sender.setAccessibilityValueDescription(scale.label)
        titleField.stringValue = "\(AppLocalization.text("Thumbnail Size")) \(scale.label)"
        change(scale)
    }
}

private struct CompactOptionsMenuButton: NSViewRepresentable {
    let fontSize: CGFloat
    let interfaceLanguage: AppInterfaceLanguage
    let queueViewMode: QueueViewMode
    let queueThumbnailsHidden: Bool
    let queueThumbnailScale: QueueThumbnailScale
    let appearanceMode: AppAppearanceMode
    let setQueueViewMode: (QueueViewMode) -> Void
    let toggleQueueViewMode: () -> Void
    let setQueueThumbnailsHidden: (Bool) -> Void
    let setQueueThumbnailScale: (QueueThumbnailScale) -> Void
    let openSettings: () -> Void
    let openFontSettings: () -> Void
    let openShortcutSettings: () -> Void
    let setAppearanceMode: (AppAppearanceMode) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(configuration: self)
    }

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(
            title: AppLocalization.text("Options", language: interfaceLanguage),
            target: context.coordinator,
            action: #selector(Coordinator.showMenu(_:))
        )
        button.isBordered = false
        button.setButtonType(.momentaryPushIn)
        button.focusRingType = .none
        button.refusesFirstResponder = true
        configureTitle(button)
        button.setAccessibilityIdentifier("main.options-menu")
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.configuration = self
        configureTitle(nsView)
    }

    private func configureTitle(_ button: NSButton) {
        let title = AppLocalization.text("Options", language: interfaceLanguage)
        let font = NSFont.systemFont(ofSize: fontSize, weight: .regular)
        button.font = font
        button.contentTintColor = .labelColor
        button.attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .font: font,
                .foregroundColor: NSColor.labelColor
            ]
        )
        button.setAccessibilityLabel(title)
    }

    @MainActor
    final class Coordinator: NSObject {
        var configuration: CompactOptionsMenuButton

        init(configuration: CompactOptionsMenuButton) {
            self.configuration = configuration
        }

        @objc func showMenu(_ sender: NSButton) {
            defer {
                sender.state = .off
                sender.highlight(false)
                sender.needsDisplay = true
            }
            let menu = makeMenu()
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: sender.bounds.minY - 2),
                in: sender
            )
        }

        private func makeMenu() -> NSMenu {
            let menu = NSMenu()
            menu.autoenablesItems = false

            let viewMenu = NSMenu(title: AppLocalization.text("View"))
            viewMenu.autoenablesItems = false
            for mode in QueueViewMode.allCases {
                let item = QueueActionMenuItem(
                    title: mode.label,
                    systemImage: mode.systemImage
                ) { [configuration] in
                    configuration.setQueueViewMode(mode)
                }
                item.state = configuration.queueViewMode == mode ? .on : .off
                viewMenu.addItem(item)
            }
            viewMenu.addItem(.separator())
            viewMenu.addItem(QueueActionMenuItem(
                title: "Switch View",
                systemImage: "arrow.left.arrow.right",
                keyEquivalent: "v",
                modifierMask: .option,
                handler: configuration.toggleQueueViewMode
            ))

            let viewTitle = AppLocalization.text("View")
            let viewItem = NSMenuItem(title: viewTitle, action: nil, keyEquivalent: "")
            viewItem.image = menuImage(named: configuration.queueViewMode.systemImage, title: viewTitle)
            viewItem.submenu = viewMenu
            menu.addItem(viewItem)

            let hideItem = QueueActionMenuItem(
                title: "Hide Thumbnails",
                systemImage: "photo.slash",
                keyEquivalent: "t",
                modifierMask: .option
            ) { [configuration] in
                configuration.setQueueThumbnailsHidden(!configuration.queueThumbnailsHidden)
            }
            hideItem.state = configuration.queueThumbnailsHidden ? .on : .off
            menu.addItem(hideItem)

            let sliderItem = NSMenuItem()
            sliderItem.view = QueueThumbnailScaleMenuView(
                scale: configuration.queueThumbnailScale,
                change: configuration.setQueueThumbnailScale
            )
            menu.addItem(sliderItem)
            menu.addItem(.separator())

            menu.addItem(QueueActionMenuItem(
                title: "Settings...",
                systemImage: "gearshape",
                handler: configuration.openSettings
            ))
            menu.addItem(QueueActionMenuItem(
                title: "Font...",
                systemImage: "textformat",
                handler: configuration.openFontSettings
            ))
            menu.addItem(QueueActionMenuItem(
                title: "Shortcuts...",
                systemImage: "keyboard",
                handler: configuration.openShortcutSettings
            ))
            menu.addItem(.separator())

            let appearanceMenu = NSMenu(title: AppLocalization.text("Appearance"))
            appearanceMenu.autoenablesItems = false
            for mode in AppAppearanceMode.allCases {
                let item = QueueActionMenuItem(
                    title: mode.label,
                    systemImage: appearanceImage(for: mode)
                ) { [configuration] in
                    configuration.setAppearanceMode(mode)
                }
                item.state = configuration.appearanceMode == mode ? .on : .off
                appearanceMenu.addItem(item)
            }
            let appearanceTitle = AppLocalization.text("Appearance")
            let appearanceItem = NSMenuItem(title: appearanceTitle, action: nil, keyEquivalent: "")
            appearanceItem.image = menuImage(named: "circle.lefthalf.filled", title: appearanceTitle)
            appearanceItem.submenu = appearanceMenu
            menu.addItem(appearanceItem)
            return menu
        }

        private func appearanceImage(for mode: AppAppearanceMode) -> String {
            switch mode {
            case .system: return "circle.lefthalf.filled"
            case .light: return "sun.max"
            case .dark: return "moon"
            }
        }

        private func menuImage(named name: String, title: String) -> NSImage? {
            let image = NSImage(
                systemSymbolName: name,
                accessibilityDescription: title
            )?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
            image?.isTemplate = true
            return image
        }
    }
}

struct ContentView: View {
    let manager: DownloadManager
    let queueScheduler: QueueScheduler
    @Environment(\.appNavigationCommands) private var navigation
    @Environment(\.queueControlCommands) private var queueCommands
    @Environment(\.inputCommands) private var inputCommands
    @EnvironmentObject private var presentation: AppPresentationStore
    @EnvironmentObject private var appStatusStore: AppStatusStore
    @EnvironmentObject private var settingsWindow: SettingsWindowPresentationState
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var searchStore: SearchStore
    @EnvironmentObject private var libraryStore: LibraryStore
    @EnvironmentObject private var queueStore: QueueStore
    @EnvironmentObject private var queueEditorStore: QueueEditorStore
    @EnvironmentObject private var duplicateImageStore: DuplicateImageStore
    @EnvironmentObject private var outputOperationStore: OutputOperationStore
    @EnvironmentObject private var externalToolStore: ExternalToolStore
    @EnvironmentObject private var aria2Store: Aria2Store
    @EnvironmentObject private var pythonRuntimeStore: PythonRuntimeStore
    @EnvironmentObject private var autoRecordStore: AutoRecordStore
    @EnvironmentObject private var networkStore: NetworkStore
    @EnvironmentObject private var cookieStatusStore: CookieStatusStore

    private var queuePresentation: QueuePresentationSnapshot {
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

    private var searchPresentation: SearchPresentationSnapshot {
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

    private var mainUIScale: CGFloat {
        CGFloat(settingsStore.uiScale.factor)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * mainUIScale
    }

    private var scaledInterfaceFont: Font {
        let size = CGFloat(settingsStore.interfaceFontSize.pointSize) * mainUIScale
        let family = settingsStore.interfaceFontFamily.trimmed
        return family.isEmpty ? .system(size: size) : .custom(family, size: size)
    }

    var body: some View {
        GeometryReader { geometry in
            content(hostSize: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func content(hostSize: CGSize) -> some View {
        scaledContent
        .contentSheets(
            manager: manager,
            presentation: presentation,
            settingsStore: settingsStore,
            libraryStore: libraryStore,
            queueStore: queueStore,
            queueEditorStore: queueEditorStore,
            hostSize: hostSize
        )
        .alert("Storage Warning", isPresented: $presentation.showingStorageWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(appStatusStore.storageWarningText)
        }
        .alert(
            queueEditorStore.queueGroupPromptTitle(language: settingsStore.interfaceLanguage),
            isPresented: $presentation.showingJobGroupPrompt
        ) {
            TextField("Group Name", text: $queueEditorStore.jobGroupNameDraft)
            Button(queueEditorStore.queueGroupPromptButtonTitle(language: settingsStore.interfaceLanguage)) {
                manager.savePendingJobGroup()
            }
            .disabled(queueEditorStore.jobGroupNameDraft.trimmed.isEmpty)
            Button("Cancel", role: .cancel) {
                manager.cancelPendingJobGroup()
            }
        } message: {
            Text(queueEditorStore.queueGroupPromptMessage(language: settingsStore.interfaceLanguage))
        }
        .alert("Remove this group?", isPresented: $presentation.showingQueueGroupRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                manager.removePendingQueueGroup()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingQueueGroupRemoval()
            }
        } message: {
            let group = queueEditorStore.queueGroupPendingRemoval
            let count = group.map { queuePresentation.jobs(in: $0).count } ?? 0
            Text(AppLocalization.format(
                "Only \"%@\" will be removed. Its %@ tasks and downloaded files will be kept.",
                language: settingsStore.interfaceLanguage,
                group?.name ?? AppLocalization.text("This Group", language: settingsStore.interfaceLanguage),
                String(count)
            ))
        }
        .alert("Restart tasks in this group?", isPresented: $presentation.showingQueueGroupRetryConfirmation) {
            Button("Restart") {
                manager.retryPendingQueueGroup()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingQueueGroupRetry()
            }
        } message: {
            let group = queueEditorStore.queueGroupPendingRetry
            let count = group.map { queuePresentation.jobs(in: $0).count } ?? 0
            Text(AppLocalization.format(
                "Restart %@ tasks.",
                language: settingsStore.interfaceLanguage,
                String(count)
            ))
        }
        .alert("Remove from the list?", isPresented: $presentation.showingJobRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                manager.removePendingJobs()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingJobRemoval()
            }
        } message: {
            Text(queuePresentation.removalConfirmationMessage)
        }
        .alert("Clear Finished Items?", isPresented: $presentation.showingClearFinishedConfirmation) {
            Button("Clear", role: .destructive) {
                manager.clearFinished()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(queuePresentation.removableFinishedJobCount) finished, failed, or cancelled queue item(s)? Downloaded files will not be deleted.")
        }
        .alert("Clear Bookmarks?", isPresented: $presentation.showingClearBookmarksConfirmation) {
            Button("Clear", role: .destructive) {
                manager.clearBookmarks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(libraryStore.bookmarks.count) bookmark(s)? Queued jobs and downloaded files will not be deleted.")
        }
        .alert("Restart incomplete tasks?", isPresented: $presentation.showingRetryIncompleteJobsConfirmation) {
            Button("Restart") {
                manager.retryPendingIncompleteJobs()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingIncompleteJobRetry()
            }
        } message: {
            Text(queueEditorStore.retryIncompleteJobsConfirmationMessage(
                language: settingsStore.interfaceLanguage
            ))
        }
        .alert("Remove completed tasks?", isPresented: $presentation.showingCompletedJobsRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                manager.removePendingCompletedJobs()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingCompletedJobRemoval()
            }
        } message: {
            Text(queueEditorStore.completedJobsRemovalConfirmationMessage(
                language: settingsStore.interfaceLanguage
            ))
        }
        .confirmationDialog(
            outputDeletionConfirmationTitle,
            isPresented: $presentation.showingOutputDeletionConfirmation,
            titleVisibility: .visible
        ) {
            if queueEditorStore.removeJobAfterOutputDeletion {
                Button(
                    outputDeletionDestructiveTitle,
                    role: .destructive
                ) {
                    manager.trashOutputCandidates(
                        Set(queueEditorStore.outputDeletionCandidates.map(\.id))
                    )
                }
            } else {
                ForEach(queueEditorStore.outputDeletionCandidates) { candidate in
                    Button(candidate.displayLabel, role: .destructive) {
                        manager.trashOutputCandidates([candidate.id])
                    }
                }
                if queueEditorStore.outputDeletionCandidates.count > 1 {
                    Button("All Downloaded Output", role: .destructive) {
                        manager.trashOutputCandidates(
                            Set(queueEditorStore.outputDeletionCandidates.map(\.id))
                        )
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                manager.cancelDeletingOutput()
            }
        } message: {
            Text(queueEditorStore.outputDeletionConfirmationMessage(
                jobs: queueStore.jobs,
                language: settingsStore.interfaceLanguage
            ))
        }
        .task {
            await configureUITestFixtures()
        }
    }

    private var outputDeletionConfirmationTitle: String {
        queueEditorStore.outputDeletionConfirmationTitle(
            jobs: queueStore.jobs,
            language: settingsStore.interfaceLanguage
        )
    }

    private var outputDeletionDestructiveTitle: String {
        queueEditorStore.outputDeletionDestructiveTitle(
            jobs: queueStore.jobs,
            language: settingsStore.interfaceLanguage
        )
    }

    private func configureUITestFixtures() async {
        await Task.yield()
        let environment = ProcessInfo.processInfo.environment
        if environment["HITOMI_NATIVE_UI_TEST_CONTEXT_MENU"] == "1" ||
            environment["HITOMI_NATIVE_UI_TEST_DUPLICATE"] == "1" ||
            environment["HITOMI_NATIVE_UI_TEST_OUTPUT_PREVIEW"] == "1" ||
            environment["HITOMI_NATIVE_UI_TEST_JOB_INFO"] == "1" ||
            environment["HITOMI_NATIVE_UI_TEST_ARCHIVE_BADGE"] == "1" {
            let configuredFixtureOutputPath = environment["HITOMI_NATIVE_UI_TEST_OUTPUT_PATH"]?.trimmed ?? ""
            let fixtureOutputPath = configuredFixtureOutputPath.isEmpty
                ? FileManager.default.temporaryDirectory.path
                : configuredFixtureOutputPath
            let testsGroupArtistFallback = environment["HITOMI_NATIVE_UI_TEST_GROUP_ARTIST"] == "1"
            let testsActionsDuringDownload = environment["HITOMI_NATIVE_UI_TEST_RUNNING_ACTIONS"] == "1"
            let testsArchiveBadge = environment["HITOMI_NATIVE_UI_TEST_ARCHIVE_BADGE"] == "1"
            var fixtureMetadata = [
                "artist": testsGroupArtistFallback ? "unknown" : "sailor_yamao",
                "site": "Hitomi",
                "groups": testsGroupArtistFallback ? "Circle One, Circle Two" : "Reference",
                "known_size": "18.2 MB"
            ]
            if testsArchiveBadge {
                fixtureMetadata["archive_format"] = "zip"
                fixtureMetadata["archive_path"] = fixtureOutputPath
                fixtureMetadata["archive_deleted_original"] = "true"
            }
            let fixture = DownloadJob(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000404")!,
                source: "https://hitomi.la/galleries/4040886.html",
                title: testsActionsDuringDownload
                    ? "[Fixture] An intentionally very long downloaded work title that must remain fully separated from every hover action in the toolbar (4040886)"
                    : (testsGroupArtistFallback
                        ? "[Fixture] Original group artist fallback (4040886)"
                        : "[Fixture] Original context menu layout (4040886)"),
                status: .finished,
                progress: 1,
                completed: 28,
                total: 28,
                outputPath: fixtureOutputPath,
                metadata: fixtureMetadata,
                tags: ["red", "blue"],
                comment: "Recovered information fixture",
                rangeExpression: "1-28",
                isPinned: !testsActionsDuringDownload,
                resolvedFilenames: ["0000.webp", "0001.webp"],
                resolvedURLs: [
                    "https://a.hitomi.la/images/0001.webp",
                    "https://b.hitomi.la/images/0002.webp"
                ],
                messageHistory: ["Resolving", "Downloading 28 files", "Done"]
            )
            if testsActionsDuringDownload {
                let active = DownloadJob(
                    source: "https://fixture.test/active-download",
                    title: "[Fixture] Active download",
                    status: .downloading,
                    progress: 0.4,
                    completed: 4,
                    total: 10
                )
                queueStore.replaceJobs(with: [fixture, active])
                queueStore.setRunning(true)
            } else {
                queueStore.replaceJobs(with: [fixture])
            }
            presentation.selectedJobIDs = [fixture.id]
            if environment["HITOMI_NATIVE_UI_TEST_OUTPUT_PREVIEW"] == "1" {
                await Task.yield()
                manager.openOutputPreview(for: fixture)
            } else if environment["HITOMI_NATIVE_UI_TEST_JOB_INFO"] == "1" {
                await Task.yield()
                queueEditorStore.infoJob = fixture
            }
        }
        if environment["HITOMI_NATIVE_UI_TEST_DUPLICATE"] == "1",
           let source = queueStore.jobs.first?.source {
            settingsStore.skipDuplicates = true
            inputCommands.setText(source)
            inputCommands.addURLs(fallbackText: nil)
        }
        if let maintenanceAction = environment["HITOMI_NATIVE_UI_TEST_QUEUE_MAINTENANCE"]?.trimmed.lowercased(),
           maintenanceAction == "retry" || maintenanceAction == "clear" {
            queueCommands.pause()
            let failed = DownloadJob(
                source: "https://fixture.test/failed",
                title: "[Fixture] Failed",
                status: .failed
            )
            let incomplete = DownloadJob(
                source: "https://fixture.test/incomplete",
                title: "[Fixture] Incomplete",
                status: .finished,
                completed: 1,
                total: 2
            )
            let completed = DownloadJob(
                source: "https://fixture.test/completed",
                title: "[Fixture] Completed",
                status: .finished,
                progress: 1,
                completed: 2,
                total: 2
            )
            let lockedCompleted = DownloadJob(
                source: "https://fixture.test/locked",
                title: "[Fixture] Locked",
                status: .finished,
                progress: 1,
                completed: 1,
                total: 1,
                isLocked: true
            )
            queueStore.replaceJobs(with: [failed, incomplete, completed, lockedCompleted])
            presentation.selectedJobIDs = []
            await Task.yield()
            if maintenanceAction == "retry" {
                manager.beginRetryIncompleteJobs()
            } else {
                manager.beginRemovingCompletedJobs()
            }
        }
        if let accessReaction = environment["HITOMI_NATIVE_UI_TEST_ACCESS_REACTION"]?.trimmed.lowercased(),
           accessReaction == "login" || accessReaction == "cookie" {
            queueCommands.pause()
            let ordinary = DownloadJob(
                source: "https://www.pixiv.net/artworks/147110120",
                title: "[Fixture] Ordinary Pixiv task",
                status: .queued,
                metadata: ["site": "Pixiv"]
            )
            let attention: DownloadJob
            if accessReaction == "login" {
                attention = DownloadJob(
                    source: "https://www.pixiv.net/artworks/147109308",
                    title: "[Fixture] Waiting for Pixiv login",
                    status: .resolving,
                    message: "Waiting for Pixiv login",
                    metadata: [
                        "authentication_waiting": "pixiv",
                        "site": "Pixiv"
                    ]
                )
            } else {
                attention = DownloadJob(
                    source: "https://hitomi.la/galleries/4040886.html",
                    title: "[Fixture] Cookie update required",
                    status: .failed,
                    message: "Cookie update required",
                    metadata: ["site": "Hitomi"]
                )
            }
            queueStore.replaceJobs(with: [ordinary, attention])
            presentation.selectedJobIDs = []
        }
        if environment["HITOMI_NATIVE_UI_TEST_TASK_REACTION"]?.trimmed.lowercased() == "disgusting" {
            queueCommands.pause()
            let ordinary = DownloadJob(
                source: "https://fixture.test/ordinary",
                title: "[Fixture] Ordinary task",
                status: .queued
            )
            let reaction = DownloadJob(
                source: "https://fixture.test/disgusting",
                title: "[Fixture] Disgusting reaction",
                status: .failed,
                message: "Rejected by the original script",
                metadata: ["reaction": "disgusting"]
            )
            queueStore.replaceJobs(with: [ordinary, reaction])
            presentation.selectedJobIDs = [reaction.id]
        }
        if environment["HITOMI_NATIVE_UI_TEST_DELAYED_RETRY"] == "1" {
            queueCommands.pause()
            let retry = DownloadJob(
                id: UUID(uuidString: "00000000-0000-4000-8000-000000000172")!,
                source: "https://fixture.test/delayed-retry",
                title: "[Fixture] Persistent delayed retry",
                status: .failed,
                message: "Temporary failure",
                metadata: [
                    "site": "Direct",
                    "t_retry": String(Date().timeIntervalSince1970 + 125),
                    "retry_original_title": "[Fixture] Persistent delayed retry",
                    "retry_kind": "imported"
                ]
            )
            queueStore.replaceJobs(with: [retry])
            presentation.selectedJobIDs = []
            manager.restoreScheduledRetries()
        }
        if environment["HITOMI_NATIVE_UI_TEST_QUEUE_GROUPS"] == "1" {
            configureQueueGroupUITestFixture()
        }
        if let rawViewMode = environment["HITOMI_NATIVE_UI_TEST_QUEUE_VIEW"],
           let viewMode = QueueViewMode(rawValue: rawViewMode.lowercased()) {
            settingsStore.queueViewMode = viewMode
        }
        if environment["HITOMI_NATIVE_UI_TEST_HIDE_QUEUE_THUMBNAILS"] == "1" {
            settingsStore.queueThumbnailsHidden = true
        }
        if let rawScale = environment["HITOMI_NATIVE_UI_TEST_QUEUE_THUMBNAIL_SCALE"],
           let thumbnailScale = queueThumbnailScale(fromTestValue: rawScale) {
            settingsStore.queueThumbnailScale = thumbnailScale
        }
        if environment["HITOMI_NATIVE_UI_TEST_GENERAL_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.general)
        } else if environment["HITOMI_NATIVE_UI_TEST_NETWORK_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.network)
        } else if environment["HITOMI_NATIVE_UI_TEST_YOUTUBE_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.youtube)
        } else if environment["HITOMI_NATIVE_UI_TEST_HITOMI_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.hitomi)
        } else if environment["HITOMI_NATIVE_UI_TEST_PIXIV_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.pixiv)
        } else if environment["HITOMI_NATIVE_UI_TEST_KEMONO_FRIENDS_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.kemonoFriends)
        } else if environment["HITOMI_NATIVE_UI_TEST_SOCIAL_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.social)
        } else if environment["HITOMI_NATIVE_UI_TEST_THEME_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.theme)
        } else if environment["HITOMI_NATIVE_UI_TEST_ARCHIVE_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.archive)
        } else if environment["HITOMI_NATIVE_UI_TEST_SETTINGS"] == "1" {
            await Task.yield()
            navigation.openSettings(.advanced)
        }
        if environment["HITOMI_NATIVE_UI_TEST_ABOUT"] == "1" {
            await Task.yield()
            navigation.open(.about)
        }
        if let auxiliaryWindow = environment["HITOMI_NATIVE_UI_TEST_AUXILIARY_WINDOW"]?.trimmed.lowercased(),
           !auxiliaryWindow.isEmpty {
            configureAuxiliaryLocalizationUITestFixture(
                window: auxiliaryWindow,
                outputPath: environment["HITOMI_NATIVE_UI_TEST_OUTPUT_PATH"]?.trimmed
            )
        }
    }

    private func configureAuxiliaryLocalizationUITestFixture(window: String, outputPath: String?) {
        let configuredOutputPath = outputPath ?? ""
        let fixtureOutputPath = configuredOutputPath.isEmpty
            ? FileManager.default.temporaryDirectory.path
            : configuredOutputPath
        let source = "https://fixture.test/artist/sample"
        let completedAt = Date(timeIntervalSince1970: 1_784_680_800)
        let metadata = [
            "artist": "Sekiya Asami",
            "creator": "Sekiya Asami",
            "site": "Fixture",
            "file_count": "12"
        ]
        let fixture = DownloadJob(
            source: source,
            title: "Sekiya Asami - Localization Fixture",
            status: .finished,
            progress: 1,
            completed: 12,
            total: 12,
            outputPath: fixtureOutputPath,
            metadata: metadata
        )
        queueStore.replaceJobs(with: [fixture])
        libraryStore.replaceHistory(with: [
            DownloadHistoryEntry(
                source: source,
                normalizedSource: source,
                title: fixture.title,
                outputPath: fixtureOutputPath,
                completedAt: completedAt,
                metadata: metadata
            )
        ])
        appStatusStore.replaceActivityLog(with: [
            ActivityLogEntry(
                timestamp: completedAt,
                category: "Download",
                message: "Done"
            )
        ])

        switch window {
        case "font":
            navigation.open(.fontSettings)
        case "statistics":
            navigation.open(.statistics)
        case "activity":
            navigation.open(.activityLog)
        case "history":
            navigation.open(.history)
        case "directories":
            navigation.open(.directories)
        case "artists":
            navigation.open(.artistRecommendations)
        default:
            break
        }
    }

    private func configureQueueGroupUITestFixture() {
        let expandedGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000101")!
        let collapsedGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000102")!
        let emptyGroupID = UUID(uuidString: "00000000-0000-4000-8000-000000000103")!
        let firstID = UUID(uuidString: "00000000-0000-4000-8000-000000000201")!
        let secondID = UUID(uuidString: "00000000-0000-4000-8000-000000000202")!
        let hiddenID = UUID(uuidString: "00000000-0000-4000-8000-000000000203")!
        let looseID = UUID(uuidString: "00000000-0000-4000-8000-000000000204")!
        let expandedMetadata = [
            "queue_group_id": expandedGroupID.uuidString,
            "group": "Reference Batch",
            "site": "Hitomi",
            "known_size": "4.2 MB"
        ]
        queueStore.replaceJobs(with: [
            DownloadJob(
                id: firstID,
                source: "https://hitomi.la/galleries/4040886.html",
                title: "Expanded child one",
                status: .finished,
                progress: 1,
                completed: 12,
                total: 12,
                metadata: expandedMetadata
            ),
            DownloadJob(
                id: secondID,
                source: "https://www.pixiv.net/artworks/147110120",
                title: "Expanded child two",
                status: .queued,
                completed: 0,
                total: 8,
                metadata: expandedMetadata.merging(["site": "Pixiv"]) { _, new in new }
            ),
            DownloadJob(
                id: hiddenID,
                source: "https://example.com/collapsed-child",
                title: "Collapsed child hidden",
                status: .queued,
                metadata: [
                    "queue_group_id": collapsedGroupID.uuidString,
                    "group": "Collapsed Batch",
                    "site": "Direct"
                ]
            ),
            DownloadJob(
                id: looseID,
                source: "https://example.com/loose-job",
                title: "Ungrouped queue item",
                status: .failed,
                message: "Fixture failure",
                metadata: ["site": "Direct"]
            )
        ])
        queueStore.replaceQueueGroups(with: [
            QueueGroup(
                id: expandedGroupID,
                name: "Reference Batch",
                comment: "Expanded group",
                isExpanded: true,
                anchorJobID: firstID,
                originalUID: "fixture-expanded",
                isPinned: true,
                tags: ["red", "blue"]
            ),
            QueueGroup(
                id: collapsedGroupID,
                name: "Collapsed Batch",
                comment: "One hidden task",
                isExpanded: false,
                anchorJobID: hiddenID,
                originalUID: "fixture-collapsed"
            ),
            QueueGroup(
                id: emptyGroupID,
                name: "Empty Batch",
                originalUID: "fixture-empty"
            )
        ])
        manager.setQueueSortMode(.manual)
        manager.setQueueSortDescending(false)
        presentation.queueFilter = ""
        manager.setSelectedJobIDs([])
    }

    private func queueThumbnailScale(fromTestValue rawValue: String) -> QueueThumbnailScale? {
        guard let percent = Int(rawValue.replacingOccurrences(of: "%", with: "")) else {
            return nil
        }
        return QueueThumbnailScale.allCases.first {
            Int(($0.factor * 100).rounded()) == percent
        }
    }

    private var scaledContent: some View {
        UIScaledRoot(scale: settingsStore.uiScale.factor) {
            VStack(spacing: 0) {
                compactMenuBar
                Divider()
                compactToolbar
                Divider()
                queuePane
            }
        }
        .font(scaledInterfaceFont)
        .foregroundStyle(themePresentation.foregroundColor ?? Color.primary)
        .background(
            themePresentation.backgroundColor ??
                Color(nsColor: .windowBackgroundColor)
        )
        .onDrop(
            of: QueueDropTypes.externalTypeIdentifiers,
            isTargeted: $presentation.isExternalDropTargeted,
            perform: handleExternalDrop
        )
        .overlay {
            if showsExternalDropOverlay {
                ZStack {
                    Color(nsColor: .windowBackgroundColor)
                        .opacity(0.9)
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.accentColor, style: StrokeStyle(lineWidth: scaled(3), dash: [scaled(8), scaled(6)]))
                        .padding(scaled(10))
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: scaled(42), weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .allowsHitTesting(false)
            }
        }
    }

    private func handleExternalDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !providers.isEmpty else { return false }
        Task { @MainActor in
            let values = await QueueDropInputLoader.load(providers)
            manager.enqueueDroppedValues(values)
        }
        return true
    }

    private var showsExternalDropOverlay: Bool {
        presentation.isExternalDropTargeted
            || ProcessInfo.processInfo.environment["HITOMI_NATIVE_UI_TEST_DROP_OVERLAY"] == "1"
    }

    private var statusColorSummary: String {
        settingsStore.jobStatusColorPalette == .defaultPalette
            ? "Default Palette"
            : "Custom Palette"
    }

    private var canStartQueue: Bool {
        !presentation.inputText.trimmed.isEmpty || queueStore.jobs.contains { $0.status == .queued }
    }

    private var completedQueueJobCount: Int {
        queueStore.jobs.filter {
            $0.status == .finished || $0.status == .failed || $0.status == .cancelled
        }.count
    }

    private var overallQueueProgress: Double {
        guard !queueStore.jobs.isEmpty else { return 0 }
        let total = queueStore.jobs.reduce(0.0) { partial, job in
            switch job.status {
            case .finished, .failed, .cancelled:
                return partial + 1
            case .resolving, .downloading:
                return partial + min(1, max(0, job.progress))
            case .queued:
                return partial
            }
        }
        return total / Double(queueStore.jobs.count)
    }

    private var knownQueueByteCount: Int64 {
        let keys = ["byte_count", "content_length", "filesize", "file_size", "total_bytes", "expected_bytes", "size"]
        return queueStore.jobs.reduce(0) { partial, job in
            let byteCount = keys.lazy.compactMap { key -> Int64? in
                guard let raw = job.metadata[key]?.trimmed,
                      let value = Int64(raw),
                      value > 0 else {
                    return nil
                }
                return value
            }.first ?? 0
            return partial + byteCount
        }
    }

    private var knownQueueSizeText: String {
        guard knownQueueByteCount > 0 else { return "" }
        return ByteCountFormatter.string(fromByteCount: knownQueueByteCount, countStyle: .file)
    }

    private var inputAutocompleteSuggestions: [String] {
        InputAutocompletePresentationService.visibleSuggestions(
            inputText: presentation.inputText,
            cursorUTF16Offset: presentation.inputCursorUTF16Offset,
            isInputFocused: presentation.isURLInputFocused,
            isDismissed: presentation.isInputAutocompleteDismissed
        )
    }

    private var compactMenuFontSize: CGFloat {
        max(9, CGFloat(settingsStore.interfaceFontSize.pointSize) + 1)
    }

    private func compactMenuTitle(_ key: String) -> some View {
        Text(AppLocalization.text(key, language: settingsStore.interfaceLanguage))
            .font(.system(size: compactMenuFontSize, weight: .regular))
            .fontWeight(.regular)
            .lineLimit(1)
            .fixedSize()
    }

    private var compactMenuBar: some View {
        HStack(spacing: scaled(26)) {
            Menu {
                Button {
                    queueCommands.start()
                } label: {
                    Label("Start Queue", systemImage: "play.fill")
                }
                .disabled(queueStore.isRunning || !canStartQueue)

                Button {
                    queueCommands.cancel()
                } label: {
                    Label("Stop Queue", systemImage: "stop.fill")
                }
                .disabled(!queueStore.isRunning)

                Divider()
                Button {
                    inputCommands.pasteAndDownload()
                } label: {
                    Label("Paste and Add", systemImage: "doc.on.clipboard")
                }
                Button {
                    inputCommands.addLocalFilesAndFolders()
                } label: {
                    Label("Add Files or Folders...", systemImage: "folder.badge.plus")
                }
                Button {
                    manager.beginCreatingQueueGroup()
                } label: {
                    Label("New Group", systemImage: "folder.badge.plus")
                }
                .keyboardShortcut("g", modifiers: .command)

                Divider()
                Button {
                    manager.importOriginalTasks()
                } label: {
                    Label("Import Tasks...", systemImage: "square.and.arrow.down")
                }
                Button {
                    manager.exportOriginalTasks()
                } label: {
                    Label("Export Tasks...", systemImage: "square.and.arrow.up")
                }
                .disabled(
                    (queueStore.jobs.isEmpty && queueStore.queueGroups.isEmpty) ||
                    (!presentation.queueFilter.trimmed.isEmpty &&
                        queuePresentation.filteredJobs.isEmpty &&
                        presentation.selectedJobIDs.isEmpty)
                )

                Divider()
                Button {
                    requestClearFinished()
                } label: {
                    Label("Remove All Completed Tasks", systemImage: "checkmark.circle")
                }
                .disabled(queuePresentation.removableFinishedJobCount == 0)
            } label: {
                compactMenuTitle("Task")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Button {
                    navigation.open(.searcher)
                } label: {
                    Label("Searcher...", systemImage: "magnifyingglass")
                }
                Button {
                    manager.importPythonScript()
                } label: {
                    Label("Import Script...", systemImage: "doc.badge.plus")
                }

                Divider()
                Button {
                    navigation.openDuplicateImageFinder()
                } label: {
                    Label("Find Duplicate Images...", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("tools.duplicate-image-finder")

                Button {
                    navigation.open(.artistRecommendations)
                } label: {
                    Label("Artist Recommendations...", systemImage: "person.2")
                }
                .accessibilityIdentifier("tools.artist-recommendations")

                Button {
                    manager.selectRandomVisibleJob()
                } label: {
                    Label("Pick One at Random", systemImage: "dice")
                }
                .disabled(!queuePresentation.canSelectRandomVisibleJob)
                .accessibilityIdentifier("tools.select-random-job")

                Button {
                    manager.copyGalleryNumbersInSaveFolder()
                } label: {
                    Label("Copy All Gallery IDs in Save Folder", systemImage: "number.square")
                }
                .disabled(outputOperationStore.isCopyingGalleryNumbers)
                .accessibilityIdentifier("tools.copy-gallery-ids")

                Divider()
                Button {
                    navigation.open(.history)
                } label: {
                    Label("History...", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    navigation.open(.statistics)
                } label: {
                    Label("Info & Statistics...", systemImage: "chart.bar.xaxis")
                }
                Button {
                    navigation.open(.activityLog)
                } label: {
                    Label("Activity Log...", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    navigation.open(.directories)
                } label: {
                    Label("Download Path History...", systemImage: "folder")
                }
            } label: {
                compactMenuTitle("Tools")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            CompactOptionsMenuButton(
                fontSize: compactMenuFontSize,
                interfaceLanguage: settingsStore.interfaceLanguage,
                queueViewMode: settingsStore.queueViewMode,
                queueThumbnailsHidden: settingsStore.queueThumbnailsHidden,
                queueThumbnailScale: settingsStore.queueThumbnailScale,
                appearanceMode: settingsStore.appAppearanceMode,
                setQueueViewMode: manager.setQueueViewMode,
                toggleQueueViewMode: manager.toggleQueueViewMode,
                setQueueThumbnailsHidden: manager.setQueueThumbnailsHidden,
                setQueueThumbnailScale: manager.setQueueThumbnailScale,
                openSettings: { navigation.openSettings() },
                openFontSettings: { navigation.open(.fontSettings) },
                openShortcutSettings: navigation.openShortcuts,
                setAppearanceMode: manager.setAppAppearanceMode
            )
            .fixedSize()

            Menu {
                Button {
                    navigation.open(.help)
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                Button {
                    navigation.open(.about)
                } label: {
                    Label("About Hitomi Badayo", systemImage: "info.circle")
                }
            } label: {
                compactMenuTitle("Help")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Spacer(minLength: scaled(12))

            if !settingsStore.enabledQuickAccessItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: scaled(2)) {
                        ForEach(settingsStore.enabledQuickAccessItems) { item in
                            Button {
                                manager.performQuickAccessCommand(item.command)
                            } label: {
                                Image(systemName: item.command.systemImage)
                                    .font(.system(size: scaled(14), weight: .semibold))
                                    .foregroundStyle(
                                        manager.isQuickAccessCommandActive(item.command)
                                            ? Color.accentColor
                                            : Color.secondary
                                    )
                                    .frame(width: scaled(26), height: scaled(26))
                                    .background {
                                        if manager.isQuickAccessCommandActive(item.command) {
                                            RoundedRectangle(cornerRadius: 5)
                                                .fill(Color.accentColor.opacity(0.13))
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .disabled(!manager.canPerformQuickAccessCommand(item.command))
                            .help(item.command.localizedLabel(language: settingsStore.interfaceLanguage))
                            .accessibilityLabel(item.command.localizedLabel(language: settingsStore.interfaceLanguage))
                            .accessibilityIdentifier("quick-access.action.\(item.command.rawValue)")
                        }
                    }
                }
                .frame(
                    width: min(
                        120,
                        scaled(
                            CGFloat(
                                settingsStore.enabledQuickAccessItems.count
                            ) * 28
                        )
                    ),
                    height: scaled(28)
                )
            }

            Button {
                navigation.open(.quickAccessCustomization)
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: scaled(10), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: scaled(22), height: scaled(26))
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("Customize Quick Access Toolbar", language: settingsStore.interfaceLanguage))
            .accessibilityLabel(AppLocalization.text("Customize Quick Access Toolbar", language: settingsStore.interfaceLanguage))
            .accessibilityIdentifier("quick-access.customize")

            FlatOpacitySlider(value: Binding(
                get: { settingsStore.mainWindowOpacity },
                set: { manager.setMainWindowOpacity($0) }
            ), range: MainWindowAppearance.minimumOpacity...1, step: 0.01)
            .frame(width: scaled(92), height: scaled(18))
            .offset(y: scaled(-2))
            .help(AppLocalization.format(
                "Window Opacity: %@",
                language: settingsStore.interfaceLanguage,
                settingsStore.mainWindowOpacityPercentText
            ))
        }
        .font(.system(size: scaled(14)))
        .padding(.horizontal, scaled(14))
        .padding(.vertical, scaled(7))
        .background(.bar)
    }

    private var compactToolbar: some View {
        HStack(spacing: scaled(10)) {
            Button {
                queueCommands.toggleEnabled()
            } label: {
                ZStack {
                    Circle()
                        .fill(queueStore.isQueueEnabled ? Color.accentColor : Color.red)
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: scaled(34), height: scaled(34))
                    Image(systemName: queueStore.isQueueEnabled ? "play.fill" : "pause.fill")
                        .font(.system(size: scaled(17), weight: .bold))
                        .foregroundStyle(queueStore.isQueueEnabled ? Color.accentColor : Color.red)
                        .offset(x: queueStore.isQueueEnabled ? scaled(1) : 0)
                }
                .frame(width: scaled(54), height: scaled(54))
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text(
                queueStore.isQueueEnabled ? "Pause Queue" : "Resume Queue",
                language: settingsStore.interfaceLanguage
            ))

            HStack(spacing: scaled(8)) {
                Button {
                    inputCommands.pasteAndDownload()
                } label: {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .font(.system(size: scaled(20), weight: .medium))
                        .frame(width: scaled(32), height: scaled(38))
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text("Paste and Add", language: settingsStore.interfaceLanguage))
                .contextMenu {
                    Button {
                        inputCommands.paste()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        inputCommands.pasteAndDownload()
                    } label: {
                        Label("Paste and Add", systemImage: "text.badge.plus")
                    }
                    Divider()
                    Button {
                        inputCommands.addLocalFilesAndFolders()
                    } label: {
                        Label("Add Files or Folders...", systemImage: "folder.badge.plus")
                    }
                    Button {
                        inputCommands.importURLList()
                    } label: {
                        Label("Import URL List...", systemImage: "square.and.arrow.down")
                    }
                }

                OriginalURLTextField(text: Binding(
                    get: { presentation.inputText },
                    set: { inputCommands.setText($0) }
                ), cursorUTF16Offset: presentation.inputCursorUTF16Offset,
                placeholder: "Enter a URL", fontSize: scaled(15), onFocusChange: {
                    inputCommands.setFocused($0)
                }, onCursorChange: {
                    inputCommands.setCursorUTF16Offset($0)
                }, onMoveCompletion: {
                    let delta = $0
                    guard !inputAutocompleteSuggestions.isEmpty else { return false }
                    DispatchQueue.main.async {
                        inputCommands.moveAutocompleteSelection(by: delta)
                    }
                    return true
                }, onAcceptCompletion: {
                    guard !inputAutocompleteSuggestions.isEmpty else { return false }
                    DispatchQueue.main.async {
                        inputCommands.acceptAutocompleteSuggestion()
                    }
                    return true
                }, onDismissCompletion: {
                    guard !inputAutocompleteSuggestions.isEmpty else { return false }
                    DispatchQueue.main.async {
                        inputCommands.dismissAutocomplete()
                    }
                    return true
                }) {
                    inputCommands.addURLs()
                }
                .frame(maxWidth: .infinity, minHeight: scaled(38))
                .overlay(alignment: .bottomLeading) {
                    if !inputAutocompleteSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(inputAutocompleteSuggestions.enumerated()), id: \.element) { index, suggestion in
                                Button {
                                    inputCommands.acceptAutocompleteSuggestion(suggestion)
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: scaled(14)))
                                        .foregroundStyle(
                                            index == presentation.inputAutocompleteSelectionIndex
                                                ? Color.white
                                                : Color.primary
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, scaled(10))
                                        .padding(.vertical, scaled(5))
                                        .background(
                                            index == presentation.inputAutocompleteSelectionIndex
                                                ? Color.accentColor
                                                : Color.clear
                                        )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .onHover { hovering in
                                    if hovering {
                                        inputCommands.setAutocompleteSelection(index)
                                    }
                                }
                            }
                        }
                        .frame(minWidth: scaled(150), maxWidth: scaled(240), alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .overlay {
                            Rectangle()
                                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                        }
                        .shadow(color: Color.black.opacity(0.2), radius: scaled(3), y: scaled(1))
                        .offset(y: scaled(28))
                        .zIndex(20)
                    }
                }
                .zIndex(20)
            }
            .padding(.horizontal, scaled(10))
            .frame(height: scaled(50))
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: scaled(6))
                    .stroke(Color(nsColor: .separatorColor), lineWidth: max(0.5, scaled(1)))
            )

            Button {
                inputCommands.addURLs()
            } label: {
                Image(systemName: "arrow.down.to.line")
                    .font(.system(size: scaled(26), weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: scaled(82), height: scaled(50))
                    .background(
                        RoundedRectangle(cornerRadius: scaled(6))
                            .fill(Color.accentColor)
                    )
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("Add to Queue", language: settingsStore.interfaceLanguage))
            .contextMenu {
                Button {
                    inputCommands.addMP3AudioURLs()
                } label: {
                    Label("Add as MP3 Audio", systemImage: "music.note")
                }
                Button {
                    inputCommands.bookmarkURLs()
                } label: {
                    Label("Bookmark", systemImage: "star")
                }
            }
        }
        .padding(.horizontal, scaled(10))
        .padding(.vertical, scaled(8))
        .background(.bar)
        .zIndex(20)
    }

    private var selectedQueueJobs: [DownloadJob] {
        let ids = presentation.selectedJobIDs
        guard !ids.isEmpty else { return [] }
        return queueStore.jobs.filter { ids.contains($0.id) }
    }

    private var queueScrollSnapshot: QueueSelectionScrollSnapshot {
        QueueSelectionScroll.snapshot(
            selectedIDs: presentation.selectedJobIDs,
            visibleJobs: queuePresentation.filteredJobs,
            layoutSignature: [
                "downloadDate=\(settingsStore.showDownloadDate)",
                "view=\(settingsStore.queueViewMode.rawValue)",
                "thumbsHidden=\(settingsStore.queueThumbnailsHidden)",
                "thumbScale=\(settingsStore.queueThumbnailScale.rawValue)"
            ].joined(separator: ";")
        )
    }

    private var queueGridBlocks: [QueueGridBlock] {
        var blocks: [QueueGridBlock] = []
        var pendingJobs: [DownloadJob] = []

        func flushPendingJobs() {
            guard !pendingJobs.isEmpty else { return }
            blocks.append(.jobs(pendingJobs))
            pendingJobs.removeAll(keepingCapacity: true)
        }

        for entry in queuePresentation.listEntries {
            switch entry {
            case .group(let group):
                flushPendingJobs()
                blocks.append(.group(group))
            case .job(let job):
                pendingJobs.append(job)
            }
        }
        flushPendingJobs()
        return blocks
    }

    private var queuePane: some View {
        VStack(spacing: 0) {
            if presentation.showingQueueControls ||
                !presentation.queueFilter.trimmed.isEmpty {
                compactQueueControls
                Divider()
            }

            if queueStore.jobs.isEmpty && queueStore.queueGroups.isEmpty {
                emptyState
            } else if queuePresentation.listEntries.isEmpty {
                noMatchesState
            } else if settingsStore.queueViewMode == .icon {
                iconQueueContent
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { presentation.selectedJobIDs },
                        set: { manager.setSelectedJobIDs($0) }
                    )) {
                        ForEach(Array(queuePresentation.listEntries.enumerated()), id: \.element.id) { index, entry in
                            switch entry {
                            case .group(let group):
                                QueueGroupRow(
                                    group: group,
                                    jobs: queuePresentation.jobs(in: group),
                                    toggleExpanded: {
                                        manager.toggleQueueGroupExpanded(group)
                                    },
                                    rename: {
                                        manager.beginRenamingQueueGroup(group)
                                    },
                                    retryAll: {
                                        manager.beginRetryingQueueGroup(group)
                                    },
                                    togglePin: {
                                        manager.toggleQueueGroupPinned(group)
                                    },
                                    toggleTag: { tag in
                                        manager.toggleQueueGroupTag(tag, for: group)
                                    },
                                    tagName: { tag in
                                        settingsStore.taskTagDisplayName(tag)
                                    },
                                    openTagSettings: {
                                        navigation.openSettings(.theme)
                                    },
                                    removeGroup: {
                                        manager.beginRemovingQueueGroup(group)
                                    }
                                )
                                .selectionDisabled(true)
                                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                .listRowSeparator(.hidden)
                                .listRowBackground(
                                    index.isMultiple(of: 2)
                                        ? Color.primary.opacity(0.03)
                                        : Color.clear
                                )

                            case .job(let job):
                                queueJobRow(job, viewMode: .list)
                                    .tag(job.id)
                                    .id(job.id)
                                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                                    .listRowSeparator(.hidden)
                                    .listRowBackground(
                                        index.isMultiple(of: 2)
                                            ? Color.primary.opacity(0.03)
                                            : Color.clear
                                    )
                                    .modifier(QueueRowDragModifier(
                                        jobID: job.id,
                                        draggedIDs: $presentation.draggedQueueJobIDs,
                                        activeTarget: $presentation.queueJobDropTarget,
                                        move: { movingIDs, targetID, placeAfter in
                                            manager.reorderJobs(
                                                movingIDs,
                                                relativeTo: targetID,
                                                placeAfter: placeAfter
                                            )
                                        }
                                    ))
                            }
                        }
                    }
                    .listStyle(.plain)
                    .onAppear {
                        scrollToSelectedQueueJob(with: proxy)
                    }
                    .onChange(of: queueScrollSnapshot) { _, _ in
                        scrollToSelectedQueueJob(with: proxy)
                    }
                }
            }

            Divider()
            compactQueueStatusBar
        }
    }

    private var queueIconGridColumns: [GridItem] {
        let cellWidth = scaled(88 * CGFloat(settingsStore.queueThumbnailScale.factor))
        return [
            GridItem(
                .adaptive(minimum: cellWidth, maximum: cellWidth),
                spacing: scaled(8),
                alignment: .top
            )
        ]
    }

    private var iconQueueContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: scaled(6)) {
                    ForEach(queueGridBlocks) { block in
                        switch block {
                        case .group(let group):
                            queueGroupRow(group)
                                .frame(maxWidth: .infinity)
                                .background(Color.primary.opacity(0.03))

                        case .jobs(let jobs):
                            LazyVGrid(columns: queueIconGridColumns, alignment: .leading, spacing: scaled(8)) {
                                ForEach(jobs) { job in
                                    queueJobRow(job, viewMode: .icon)
                                        .id(job.id)
                                        .onTapGesture {
                                            selectQueueGridJob(job)
                                        }
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(.horizontal, scaled(8))
                .padding(.vertical, scaled(6))
            }
            .onAppear {
                scrollToSelectedQueueJob(with: proxy)
            }
            .onChange(of: queueScrollSnapshot) { _, _ in
                scrollToSelectedQueueJob(with: proxy)
            }
        }
    }

    private func queueGroupRow(_ group: QueueGroup) -> some View {
        QueueGroupRow(
            group: group,
            jobs: queuePresentation.jobs(in: group),
            toggleExpanded: {
                manager.toggleQueueGroupExpanded(group)
            },
            rename: {
                manager.beginRenamingQueueGroup(group)
            },
            retryAll: {
                manager.beginRetryingQueueGroup(group)
            },
            togglePin: {
                manager.toggleQueueGroupPinned(group)
            },
            toggleTag: { tag in
                manager.toggleQueueGroupTag(tag, for: group)
            },
            tagName: { tag in
                settingsStore.taskTagDisplayName(tag)
            },
            openTagSettings: {
                navigation.openSettings(.theme)
            },
            removeGroup: {
                manager.beginRemovingQueueGroup(group)
            }
        )
    }

    private func queueJobRow(_ job: DownloadJob, viewMode: QueueViewMode) -> some View {
        ManagedQueueJobRow(
            manager: manager,
            presentation: presentation,
            settingsStore: settingsStore,
            queueStore: queueStore,
            queueEditorStore: queueEditorStore,
            job: job,
            viewMode: viewMode,
            groupOptions: queuePresentation.groupOptions,
            retryableIncompleteJobCount:
                queuePresentation.retryableIncompleteJobCount,
            removableCompletedJobCount:
                queuePresentation.removableCompletedJobCount,
            requestRemove: {
                requestRemoveJob(job)
            },
            selectIconJob: {
                selectQueueGridJob(job)
            }
        )
    }

    private func selectQueueGridJob(_ job: DownloadJob) {
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if modifiers.contains(.command) {
            var selection = presentation.selectedJobIDs
            if selection.contains(job.id) {
                selection.remove(job.id)
            } else {
                selection.insert(job.id)
            }
            manager.setSelectedJobIDs(selection)
            return
        }

        if modifiers.contains(.shift), !presentation.selectedJobIDs.isEmpty {
            let visibleIDs = queuePresentation.listEntries.compactMap { entry -> UUID? in
                guard case .job(let visibleJob) = entry else { return nil }
                return visibleJob.id
            }
            if let anchor = visibleIDs.first(where: presentation.selectedJobIDs.contains),
               let anchorIndex = visibleIDs.firstIndex(of: anchor),
               let targetIndex = visibleIDs.firstIndex(of: job.id) {
                manager.setSelectedJobIDs(Set(visibleIDs[min(anchorIndex, targetIndex)...max(anchorIndex, targetIndex)]))
                return
            }
        }

        manager.setSelectedJobIDs([job.id])
    }

    private var compactQueueControls: some View {
        HStack(spacing: scaled(8)) {
            Image(systemName: "line.3.horizontal.decrease")
                .foregroundStyle(.secondary)

            TextField("Filter Queue", text: $presentation.queueFilter)
                .textFieldStyle(.plain)
                .frame(maxWidth: scaled(230))

            queueFilterBookmarkMenu

            Spacer(minLength: scaled(8))

            Text(selectedQueueJobs.isEmpty
                ? "\(queuePresentation.filteredJobs.count) / \(queueStore.jobs.count)"
                : AppLocalization.format(
                    "%@ selected · %@ / %@",
                    language: settingsStore.interfaceLanguage,
                    String(selectedQueueJobs.count),
                    String(queuePresentation.filteredJobs.count),
                    String(queueStore.jobs.count)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)

            Menu {
                Picker("Sort", selection: Binding(
                    get: { settingsStore.queueSortMode },
                    set: { manager.setQueueSortMode($0) }
                )) {
                    ForEach(QueueSortMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Button {
                    manager.setQueueSortDescending(
                        !settingsStore.queueSortDescending
                    )
                } label: {
                    Label(
                        settingsStore.queueSortDescending
                            ? "Descending"
                            : "Ascending",
                        systemImage: settingsStore.queueSortDescending
                            ? "arrow.down"
                            : "arrow.up"
                    )
                }

                if !selectedQueueJobs.isEmpty {
                    Divider()
                    Button {
                        manager.openOutputBrowserView(for: selectedQueueJobs)
                    } label: {
                        Label("Preview Selected Output", systemImage: "eye")
                    }
                    .disabled(!manager.canOpenOutputBrowserView(for: selectedQueueJobs))

                    Button {
                        manager.beginEditingJobComments(for: selectedQueueJobs)
                    } label: {
                        Label("Edit Selected Comments...", systemImage: "text.bubble")
                    }

                    Button {
                        manager.beginMovingOutputs(for: selectedQueueJobs)
                    } label: {
                        Label("Move Selected Output...", systemImage: "folder.badge.plus")
                    }
                    .disabled(!manager.canMoveOutputs(for: selectedQueueJobs))

                    Button {
                        manager.retryJobs(selectedQueueJobs)
                    } label: {
                        Label("Restart Selected Tasks", systemImage: "arrow.clockwise")
                    }
                    .disabled(!manager.canRetryJobs(for: selectedQueueJobs))

                    Button {
                        manager.moveSelectedJobsUp()
                    } label: {
                        Label("Move Up", systemImage: "chevron.up")
                    }
                    .disabled(!manager.canMoveSelectedJobsUp())

                    Button {
                        manager.moveSelectedJobsDown()
                    } label: {
                        Label("Move Down", systemImage: "chevron.down")
                    }
                    .disabled(!manager.canMoveSelectedJobsDown())

                    Button {
                        manager.clearSelectedJobs()
                    } label: {
                        Label("Clear Selection", systemImage: "xmark.circle")
                    }
                }

                Divider()
                Button {
                    requestClearFinished()
                } label: {
                    Label("Remove All Completed Tasks", systemImage: "checkmark.circle")
                }
                .disabled(queuePresentation.removableFinishedJobCount == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(selectedQueueJobs.isEmpty
                ? AppLocalization.text("Queue Options", language: settingsStore.interfaceLanguage)
                : AppLocalization.format(
                    "%@ selected",
                    language: settingsStore.interfaceLanguage,
                    String(selectedQueueJobs.count)
                ))
        }
        .padding(.horizontal, scaled(10))
        .padding(.vertical, scaled(7))
        .background(.bar)
    }

    private var compactQueueStatusBar: some View {
        VStack(spacing: scaled(2)) {
            HStack(spacing: scaled(10)) {
                Button {
                    presentation.showingQueueControls.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .frame(width: scaled(24), height: scaled(24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(presentation.queueFilter.trimmed.isEmpty ? Color.secondary : Color.accentColor)
                .help(AppLocalization.text("Filter and Sort", language: settingsStore.interfaceLanguage))

                Button {
                    navigation.open(.searcher)
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: scaled(24), height: scaled(24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(AppLocalization.text("Search", language: settingsStore.interfaceLanguage))

                CompactLinearProgress(value: overallQueueProgress)
                    .frame(maxWidth: .infinity)

                Text(selectedQueueJobs.isEmpty
                    ? "\(completedQueueJobCount) / \(queueStore.jobs.count)"
                    : AppLocalization.format(
                        "%@ selected · %@ / %@",
                        language: settingsStore.interfaceLanguage,
                        String(selectedQueueJobs.count),
                        String(completedQueueJobCount),
                        String(queueStore.jobs.count)
                    ))
                    .font(.system(size: scaled(12)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help(knownQueueSizeText.isEmpty ? "Queue Progress" : knownQueueSizeText)
            }

            HStack(spacing: scaled(12)) {
                Spacer()

                Button {
                    manager.openDownloadDirectory(
                        at: settingsStore.destinationPath
                    )
                } label: {
                    Image(systemName: "folder.fill")
                        .frame(width: scaled(24), height: scaled(24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(AppLocalization.text(
                    "Open Download Folder",
                    language: settingsStore.interfaceLanguage
                ))
                .accessibilityIdentifier("queue.open-download-root")
                .contextMenu {
                    Button {
                        navigation.open(.directories)
                    } label: {
                        Label("Download Path History...", systemImage: "list.bullet.rectangle")
                    }
                }
            }
        }
        .padding(.horizontal, scaled(10))
        .padding(.vertical, scaled(5))
        .background(.bar)
    }

    private func scrollToSelectedQueueJob(with proxy: ScrollViewProxy) {
        guard let targetID = queueScrollSnapshot.targetID else { return }
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.18)) {
                proxy.scrollTo(targetID, anchor: .center)
            }
        }
    }

    private var queueFilterBookmarkMenu: some View {
        Menu {
            Button {
                manager.saveCurrentQueueFilterBookmark()
            } label: {
                Label("Save Filter", systemImage: "bookmark")
            }
            .disabled(presentation.queueFilter.trimmed.isEmpty)

            if !queueStore.queueFilterBookmarks.isEmpty {
                Divider()
                ForEach(queueStore.queueFilterBookmarks) { bookmark in
                    Button {
                        manager.applyQueueFilterBookmark(bookmark)
                    } label: {
                        Label(bookmark.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                Menu {
                    ForEach(queueStore.queueFilterBookmarks) { bookmark in
                        Button(role: .destructive) {
                            manager.removeQueueFilterBookmark(bookmark)
                        } label: {
                            Label(bookmark.title, systemImage: "trash")
                        }
                    }
                } label: {
                    Label("Remove Filter", systemImage: "trash")
                }
            }

            Divider()
            Button {
                manager.importQueueFilterBookmarks()
            } label: {
                Label("Import Filters...", systemImage: "square.and.arrow.down")
            }
            Button {
                manager.exportQueueFilterBookmarks()
            } label: {
                Label("Export Filters...", systemImage: "square.and.arrow.up")
            }
            .disabled(queueStore.queueFilterBookmarks.isEmpty)
        } label: {
            Image(
                systemName: queueStore.queueFilterBookmarks.isEmpty
                    ? "bookmark"
                    : "bookmark.fill"
            )
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(AppLocalization.text("Filter Bookmarks", language: settingsStore.interfaceLanguage))
    }

    private func requestRemoveJob(_ job: DownloadJob) {
        manager.beginRemovingJobs(startingAt: job)
    }

    private func requestClearFinished() {
        guard queuePresentation.removableFinishedJobCount > 0 else {
            manager.clearFinished()
            return
        }
        presentation.showingClearFinishedConfirmation = true
    }

    private var emptyState: some View {
        VStack(spacing: scaled(12)) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: scaled(42), weight: .light))
                .foregroundStyle(.secondary)
            Text("The queue is empty")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noMatchesState: some View {
        VStack(spacing: scaled(12)) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .font(.system(size: scaled(38), weight: .light))
                .foregroundStyle(.secondary)
            Text("No matching tasks")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
