import AppKit
import Combine
import SwiftUI

@MainActor
private final class OutputPreviewWindow: NSWindow {
    var requestClose: (() -> Void)?
    var selectAdjacentImage: ((Int) -> Void)?

    override func performClose(_ sender: Any?) {
        guard let requestClose else {
            super.performClose(sender)
            return
        }
        requestClose()
    }

    override func cancelOperation(_ sender: Any?) {
        guard let requestClose else {
            super.cancelOperation(sender)
            return
        }
        requestClose()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.intersection([.command, .option, .control, .shift]) == [.command],
           event.charactersIgnoringModifiers?.lowercased() == "w" {
            requestClose?()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            let modifiers = event.modifierFlags
                .intersection(.deviceIndependentFlagsMask)
            let commandModifiers = modifiers
                .intersection([.command, .option, .control, .shift])
            if commandModifiers.isEmpty {
                switch event.keyCode {
                case 126:
                    selectAdjacentImage?(-1)
                    return
                case 125:
                    selectAdjacentImage?(1)
                    return
                default:
                    break
                }
            }
        }
        super.sendEvent(event)
    }
}

@MainActor
final class OutputPreviewWindowController: NSObject, NSWindowDelegate {
    private let manager: DownloadManager
    private let presentation: AppPresentationStore
    private let queueStore: QueueStore
    private let settingsStore: SettingsStore
    private let pythonRuntimeStore: PythonRuntimeStore
    private var window: NSWindow?
    private var isCorrectingWindowFrame = false
    private var presentationGeneration = 0
    private var cancellables: Set<AnyCancellable> = []

    init(
        manager: DownloadManager,
        presentation: AppPresentationStore,
        queueStore: QueueStore,
        settingsStore: SettingsStore,
        pythonRuntimeStore: PythonRuntimeStore
    ) {
        self.manager = manager
        self.presentation = presentation
        self.queueStore = queueStore
        self.settingsStore = settingsStore
        self.pythonRuntimeStore = pythonRuntimeStore
        super.init()

        presentation.$showingOutputPreview
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.setVisible(isVisible)
            }
            .store(in: &cancellables)

        presentation.$outputPreviewJobID
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.window?.title = self.windowTitle
                if self.presentation.showingOutputPreview {
                    self.show()
                }
            }
            .store(in: &cancellables)

        queueStore.$jobs
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.window?.title = self?.windowTitle ?? "Output Preview"
            }
            .store(in: &cancellables)
    }

    private var windowTitle: String {
        let title = OutputPreviewPresentationService.snapshot(
            jobs: queueStore.jobs,
            selectedJobID: presentation.outputPreviewJobID,
            files: presentation.outputPreviewFiles,
            selectedFileIndex: presentation.outputPreviewSelectedFileIndex,
            isLoading: presentation.outputPreviewIsLoading
        ).title.trimmed
        return title.isEmpty || title == "Output Preview" ? "Output Preview" : "Output Preview - \(title)"
    }

    private var themePresentation: ThemePresentationSnapshot {
        ThemePresentationService.snapshot(
            plugins: pythonRuntimeStore.scriptPlugins,
            selectedThemeKey: settingsStore.selectedPythonThemeKey,
            appearanceMode: settingsStore.appAppearanceMode
        )
    }

    private func setVisible(_ isVisible: Bool) {
        if isVisible {
            show()
        } else {
            dismissWindow()
        }
    }

    private func show() {
        let window = window ?? makeWindow()
        if self.window == nil {
            presentationGeneration += 1
        }
        self.window = window
        window.title = windowTitle
        keepOnScreen(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let visibleFrame = targetVisibleFrame()
        let contentSize = OutputPreviewLayoutPolicy.windowSize(for: visibleFrame.size)
        let window = OutputPreviewWindow(
            contentRect: NSRect(origin: .zero, size: contentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = windowTitle
        window.identifier = NSUserInterfaceItemIdentifier("HitomiBadayoOutputPreview")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.tabbingMode = .disallowed
        window.delegate = self
        window.requestClose = { [weak self] in
            self?.closePreview()
        }
        window.selectAdjacentImage = { [weak manager] direction in
            manager?.selectAdjacentOutputPreviewImage(direction: direction)
        }
        window.standardWindowButton(.closeButton)?.isEnabled = true
        let hostingController = NSHostingController(
            rootView: OutputPreviewWindowView(
                manager: manager,
                presentation: presentation,
                queueStore: queueStore,
                requestClose: { [weak self] in
                    self?.closePreview()
                }
            )
                .preferredColorScheme(themePresentation.preferredColorScheme)
                .tint(themePresentation.tintColor)
        )
        hostingController.sizingOptions = []
        window.contentViewController = hostingController

        let requestedFrame = window.frameRect(forContentRect: NSRect(origin: .zero, size: contentSize))
        window.setFrame(
            OutputPreviewLayoutPolicy.centeredFrame(size: requestedFrame.size, in: visibleFrame),
            display: false
        )
        return window
    }

    private func closePreview() {
        if let currentWindow = window {
            dismissWindow(currentWindow, closeModel: true)
        } else {
            manager.closeOutputPreview()
        }
    }

    private func keepOnScreen(_ window: NSWindow) {
        let visibleFrame = targetVisibleFrame()
        updateSizeLimits(for: window, in: visibleFrame)
        correctUndersizedFrame(window, in: visibleFrame)
        guard !visibleFrame.contains(window.frame) else { return }
        window.setFrame(
            OutputPreviewLayoutPolicy.centeredFrame(size: window.frame.size, in: visibleFrame),
            display: false
        )
    }

    private func updateSizeLimits(for window: NSWindow, in visibleFrame: NSRect) {
        let frameOverhead = max(0, window.frame.height - window.contentLayoutRect.height)
        let maximum = NSSize(
            width: visibleFrame.width,
            height: max(1, visibleFrame.height - frameOverhead)
        )
        window.contentMinSize = NSSize(
            width: min(OutputPreviewLayoutPolicy.minimumContentSize.width, maximum.width),
            height: min(OutputPreviewLayoutPolicy.minimumContentSize.height, maximum.height)
        )
        window.contentMaxSize = maximum
    }

    private func correctUndersizedFrame(_ window: NSWindow, in visibleFrame: NSRect) {
        guard !isCorrectingWindowFrame else { return }
        let contentSize = window.contentLayoutRect.size
        let minimum = window.contentMinSize
        guard contentSize.width + 0.5 < minimum.width ||
                contentSize.height + 0.5 < minimum.height else {
            return
        }

        let correctedContent = NSSize(
            width: max(contentSize.width, minimum.width),
            height: max(contentSize.height, minimum.height)
        )
        let correctedFrame = window.frameRect(
            forContentRect: NSRect(origin: .zero, size: correctedContent)
        )
        isCorrectingWindowFrame = true
        window.setFrame(
            OutputPreviewLayoutPolicy.centeredFrame(size: correctedFrame.size, in: visibleFrame),
            display: true
        )
        isCorrectingWindowFrame = false
    }

    private func dismissWindow() {
        guard let window else { return }
        dismissWindow(window, closeModel: false)
    }

    private func dismissWindow(_ window: NSWindow, closeModel: Bool) {
        guard self.window === window else { return }
        presentationGeneration += 1
        let dismissalGeneration = presentationGeneration
        self.window = nil
        window.orderOut(nil)
        (window as? OutputPreviewWindow)?.requestClose = nil
        window.delegate = nil
        window.close()

        // Close the native window before SwiftUI releases its visible rows. This
        // keeps every close path responsive and prevents hidden preview windows
        // from accumulating in NSApplication.windows.
        DispatchQueue.main.async { [weak self, window] in
            window.contentViewController = nil
            OutputPreviewImageProvider.purgeCache()

            guard closeModel,
                  let self,
                  self.presentationGeneration == dismissalGeneration else {
                return
            }
            self.manager.closeOutputPreview()
        }
    }

    private func targetVisibleFrame() -> NSRect {
        NSApp.keyWindow?.screen?.visibleFrame
            ?? NSApp.mainWindow?.screen?.visibleFrame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closePreview()
        return false
    }

    func windowDidResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        let visibleFrame = window.screen?.visibleFrame ?? targetVisibleFrame()
        updateSizeLimits(for: window, in: visibleFrame)
        correctUndersizedFrame(window, in: visibleFrame)
    }
}
