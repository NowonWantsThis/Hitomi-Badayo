import AppKit
import Foundation
import SwiftUI

enum MainWindowIdentity {
    static let identifier = NSUserInterfaceItemIdentifier("HitomiBadayo.MainWindow")

    static func acceptsGlobalPaste(_ window: NSWindow?) -> Bool {
        guard let window else { return false }
        return acceptsGlobalPaste(
            identifier: window.identifier,
            hasAttachedSheet: window.attachedSheet != nil,
            hasSheetParent: window.sheetParent != nil
        )
    }

    static func hasEditableTextFirstResponder(_ window: NSWindow?) -> Bool {
        isEditableTextResponder(window?.firstResponder)
    }

    static func isEditableTextResponder(_ responder: NSResponder?) -> Bool {
        if let textView = responder as? NSTextView {
            return textView.isEditable
        }
        if let textField = responder as? NSTextField {
            return textField.isEnabled && textField.isEditable
        }
        return false
    }

    static func acceptsGlobalPaste(
        identifier: NSUserInterfaceItemIdentifier?,
        hasAttachedSheet: Bool,
        hasSheetParent: Bool
    ) -> Bool {
        identifier == self.identifier && !hasAttachedSheet && !hasSheetParent
    }
}

enum MainWindowAppearance {
    static let minimumOpacity = 0.35
    static let defaultOpacity = 1.0

    static func normalizedOpacity(_ value: Double) -> Double {
        guard value.isFinite else { return defaultOpacity }
        return min(1, max(minimumOpacity, value))
    }
}

enum MainWindowFramePersistence {
    static let storageKey = "mainWindowFrame"
    static let minimumSize = NSSize(width: 920, height: 620)

    static func storedFrame(defaults: UserDefaults = .standard) -> NSRect? {
        guard let raw = defaults.string(forKey: storageKey) else { return nil }
        return decodeFrame(raw)
    }

    static func save(_ frame: NSRect, defaults: UserDefaults = .standard) {
        guard frame.isFinite,
              frame.width > 0,
              frame.height > 0 else {
            return
        }
        defaults.set(encodeFrame(frame), forKey: storageKey)
    }

    static func encodeFrame(_ frame: NSRect) -> String {
        [
            frame.origin.x,
            frame.origin.y,
            frame.size.width,
            frame.size.height
        ]
        .map { String(format: "%.0f", Double($0.rounded())) }
        .joined(separator: ",")
    }

    static func decodeFrame(_ raw: String) -> NSRect? {
        let values = raw
            .split(separator: ",", omittingEmptySubsequences: false)
            .map { Double(String($0).trimmed) }
        guard values.count == 4,
              let x = values[0],
              let y = values[1],
              let width = values[2],
              let height = values[3],
              x.isFinite,
              y.isFinite,
              width.isFinite,
              height.isFinite,
              width > 0,
              height > 0 else {
            return nil
        }
        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func restoredFrame(_ frame: NSRect, visibleFrames: [NSRect]) -> NSRect {
        guard frame.isFinite else {
            return frameWithMinimumSize(frame)
        }
        let sized = frameWithMinimumSize(frame)
        guard let target = bestVisibleFrame(for: sized, visibleFrames: visibleFrames) else {
            return sized
        }

        let width = min(sized.width, target.width)
        let height = min(sized.height, target.height)
        var x = sized.origin.x
        var y = sized.origin.y

        let maxX = target.maxX - width
        let maxY = target.maxY - height
        if x < target.minX { x = target.minX }
        if y < target.minY { y = target.minY }
        if x > maxX { x = maxX }
        if y > maxY { y = maxY }

        return NSRect(x: x, y: y, width: width, height: height)
    }

    static func restoredFrameForCurrentScreens(_ frame: NSRect) -> NSRect {
        restoredFrame(frame, visibleFrames: NSScreen.screens.map(\.visibleFrame))
    }

    private static func frameWithMinimumSize(_ frame: NSRect) -> NSRect {
        NSRect(
            x: frame.origin.x,
            y: frame.origin.y,
            width: max(minimumSize.width, frame.width),
            height: max(minimumSize.height, frame.height)
        )
    }

    private static func bestVisibleFrame(for frame: NSRect, visibleFrames: [NSRect]) -> NSRect? {
        let candidates = visibleFrames.filter { $0.width > 0 && $0.height > 0 }
        guard !candidates.isEmpty else { return nil }

        let center = NSPoint(x: frame.midX, y: frame.midY)
        if let containing = candidates.first(where: { $0.contains(center) }) {
            return containing
        }

        return candidates.max { left, right in
            left.intersection(frame).area < right.intersection(frame).area
        } ?? candidates.first
    }
}

private extension NSRect {
    var isFinite: Bool {
        origin.x.isFinite &&
            origin.y.isFinite &&
            size.width.isFinite &&
            size.height.isFinite
    }

    var area: CGFloat {
        guard !isNull else { return 0 }
        return max(0, width) * max(0, height)
    }
}

#if !TESTING
struct MainWindowFrameRestorer: NSViewRepresentable {
    let opacity: Double
    let alwaysOnTop: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            context.coordinator.update(
                window: view.window,
                opacity: opacity,
                alwaysOnTop: alwaysOnTop
            )
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.update(
                window: nsView.window,
                opacity: opacity,
                alwaysOnTop: alwaysOnTop
            )
        }
    }

    final class Coordinator {
        private weak var window: NSWindow?
        private var tokens: [NSObjectProtocol] = []
        private var restoredWindowIDs = Set<Int>()
        private var terminationRequested = false

        deinit {
            detach()
        }

        func update(window newWindow: NSWindow?, opacity: Double, alwaysOnTop: Bool) {
            guard let newWindow else { return }
            newWindow.identifier = MainWindowIdentity.identifier
            if window !== newWindow {
                detach()
                window = newWindow
                terminationRequested = false
                restoreIfNeeded(newWindow)
                observe(newWindow)
            }
            newWindow.alphaValue = CGFloat(MainWindowAppearance.normalizedOpacity(opacity))
            newWindow.level = alwaysOnTop ? .floating : .normal
        }

        private func restoreIfNeeded(_ window: NSWindow) {
            let key = ObjectIdentifier(window).hashValue
            guard !restoredWindowIDs.contains(key),
                  let frame = MainWindowFramePersistence.storedFrame() else {
                return
            }
            restoredWindowIDs.insert(key)
            window.setFrame(MainWindowFramePersistence.restoredFrameForCurrentScreens(frame), display: true)
        }

        private func observe(_ window: NSWindow) {
            let center = NotificationCenter.default
            let notifications: [NSNotification.Name] = [
                NSWindow.didMoveNotification,
                NSWindow.didEndLiveResizeNotification,
                NSWindow.didResizeNotification
            ]
            tokens = notifications.map { name in
                center.addObserver(forName: name, object: window, queue: .main) { notification in
                    guard let observed = notification.object as? NSWindow else { return }
                    MainWindowFramePersistence.save(observed.frame)
                }
            }
            tokens.append(center.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.terminationRequested else { return }
                    self.terminationRequested = true
                    AppTerminationCoordinator.terminate()
                }
            })
        }

        private func detach() {
            for token in tokens {
                NotificationCenter.default.removeObserver(token)
            }
            tokens.removeAll()
            window = nil
        }
    }
}
#endif
