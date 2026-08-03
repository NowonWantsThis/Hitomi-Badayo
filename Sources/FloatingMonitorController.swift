import AppKit
import Combine
import SwiftUI

struct FloatingMonitorPlacement {
    static let defaultSize = NSSize(width: 340, height: 150)

    static func defaultFrame(in visibleFrame: NSRect, size: NSSize = defaultSize, margin: CGFloat = 22) -> NSRect {
        let width = min(max(260, size.width), max(260, visibleFrame.width - margin * 2))
        let height = min(max(120, size.height), max(120, visibleFrame.height - margin * 2))
        let x = min(
            max(visibleFrame.minX + margin, visibleFrame.maxX - width - margin),
            visibleFrame.maxX - width
        )
        let y = max(visibleFrame.minY + margin, visibleFrame.minY)
        return NSRect(x: x, y: y, width: width, height: height)
    }
}

@MainActor
final class FloatingMonitorController: NSObject, NSWindowDelegate {
    private let manager: DownloadManager
    private let presentation: AppPresentationStore
    private let settingsStore: SettingsStore
    private let queueStore: QueueStore
    private let navigationCommands: AppNavigationCommands
    private let queueControlCommands: QueueControlCommands
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []

    init(
        manager: DownloadManager,
        presentation: AppPresentationStore,
        settingsStore: SettingsStore,
        queueStore: QueueStore,
        appCommandService: AppCommandService,
        queueControlCommands: QueueControlCommands
    ) {
        self.manager = manager
        self.presentation = presentation
        self.settingsStore = settingsStore
        self.queueStore = queueStore
        navigationCommands = AppNavigationCommands(
            service: appCommandService
        )
        self.queueControlCommands = queueControlCommands
        super.init()

        presentation.$showingFloatingMonitor
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] isVisible in
                self?.setVisible(isVisible)
            }
            .store(in: &cancellables)

        settingsStore.$floatingMonitorOpacity
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] opacity in
                self?.panel?.alphaValue = CGFloat(
                    SettingsStore.normalizedFloatingMonitorOpacity(opacity)
                )
            }
            .store(in: &cancellables)

        settingsStore.$interfaceLanguage
            .removeDuplicates()
            .receive(on: RunLoop.main)
            .sink { [weak self] language in
                self?.panel?.title = AppLocalization.text(
                    "Hitomi Badayo Floating Monitor",
                    language: language
                )
            }
            .store(in: &cancellables)

        if presentation.showingFloatingMonitor {
            setVisible(true)
        }
    }

    private func setVisible(_ isVisible: Bool) {
        if isVisible {
            show()
        } else {
            panel?.orderOut(nil)
        }
    }

    private func show() {
        let panel = panel ?? makePanel()
        self.panel = panel
        panel.alphaValue = CGFloat(settingsStore.floatingMonitorOpacity)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let panel = NSPanel(
            contentRect: FloatingMonitorPlacement.defaultFrame(in: screenFrame),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = AppLocalization.text(
            "Hitomi Badayo Floating Monitor",
            language: settingsStore.interfaceLanguage
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.setFrameAutosaveName("HitomiBadayoFloatingMonitor")
        panel.contentView = NSHostingView(
            rootView: FloatingMonitorView(
                manager: manager,
                settingsStore: settingsStore,
                queueStore: queueStore
            )
                .environment(
                    \.appNavigationCommands,
                    navigationCommands
                )
                .environment(
                    \.queueControlCommands,
                    queueControlCommands
                )
                .environment(\.locale, settingsStore.interfaceLanguage.locale)
        )
        return panel
    }
}

struct FloatingMonitorView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @Environment(\.queueControlCommands) private var queueCommands
    @ObservedObject var settingsStore: SettingsStore
    @ObservedObject var queueStore: QueueStore

    private var snapshot: FloatingMonitorSnapshot {
        manager.floatingMonitorSnapshot()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            Text(snapshot.statusLine)
                .font(.headline.monospacedDigit())
                .lineLimit(1)

            ProgressView(value: snapshot.progressFraction)
                .progressViewStyle(.linear)
                .help("\(snapshot.completedUnits)/\(max(1, snapshot.totalUnits))")

            HStack(spacing: 12) {
                Label(FloatingMonitorFormatter.speedText(snapshot.downloadSpeedBytesPerSecond), systemImage: "arrow.down.circle")
                Label(
                    AppLocalization.format(
                        "%@ active",
                        language: settingsStore.interfaceLanguage,
                        String(snapshot.activeJobs)
                    ),
                    systemImage: "bolt"
                )
                Label(
                    AppLocalization.format(
                        "%@ failed",
                        language: settingsStore.interfaceLanguage,
                        String(snapshot.failedJobs)
                    ),
                    systemImage: "exclamationmark.triangle"
                )
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            controls
        }
        .padding(12)
        .frame(width: FloatingMonitorPlacement.defaultSize.width, height: FloatingMonitorPlacement.defaultSize.height, alignment: .topLeading)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: queueStore.isRunning ? "arrow.down.circle.fill" : "arrow.down.circle")
                .foregroundStyle(queueStore.isRunning ? Color.accentColor : Color.secondary)

            VStack(alignment: .leading, spacing: 1) {
                Text("Hitomi Badayo")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(snapshot.stateLabel)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text("\(snapshot.percent)%")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                navigation.setFloatingMonitorVisible(false)
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(AppLocalization.text("Hide floating monitor", language: settingsStore.interfaceLanguage))
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button {
                queueCommands.start()
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(queueStore.isRunning)
            .help(AppLocalization.text("Start queue", language: settingsStore.interfaceLanguage))

            Button {
                queueCommands.cancel()
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(!queueStore.isRunning)
            .help(AppLocalization.text("Cancel queue", language: settingsStore.interfaceLanguage))

            Button {
                navigation.openProgress()
            } label: {
                Image(systemName: "gauge")
            }
            .help(AppLocalization.text("Open progress window", language: settingsStore.interfaceLanguage))

            Spacer(minLength: 0)

            Text(FloatingMonitorFormatter.speedText(snapshot.uploadSpeedBytesPerSecond))
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .help(AppLocalization.text("Upload speed", language: settingsStore.interfaceLanguage))
        }
    }
}

enum FloatingMonitorFormatter {
    static func speedText(_ byteCount: Int64?) -> String {
        guard let byteCount, byteCount > 0 else { return "0 B/s" }
        return "\(ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file))/s"
    }
}
