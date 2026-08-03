import AppKit
import SwiftUI

func queueDragTrace(_ message: String) {
    guard ProcessInfo.processInfo.environment["HITOMI_NATIVE_UI_TEST_DRAG_TRACE"] == "1" else {
        return
    }
    FileHandle.standardError.write(Data("QUEUE_DRAG \(message)\n".utf8))
}

struct QueueSelectionScrollSnapshot: Equatable {
    let targetID: UUID?
    let visibleJobIDs: [UUID]
    let layoutSignature: String
}

enum QueueGridBlock: Identifiable {
    enum ID: Hashable {
        case group(UUID)
        case jobs(UUID)
    }

    case group(QueueGroup)
    case jobs([DownloadJob])

    var id: ID {
        switch self {
        case .group(let group):
            return .group(group.id)
        case .jobs(let jobs):
            return .jobs(jobs[0].id)
        }
    }
}

struct QueueJobDropDelegate: DropDelegate {
    let targetID: UUID
    @Binding var draggedIDs: Set<UUID>
    @Binding var activeTarget: QueueJobDropTarget?
    let move: (Set<UUID>, UUID, Bool) -> Bool

    func validateDrop(info: DropInfo) -> Bool {
        let accepted = !draggedIDs.isEmpty && info.hasItemsConforming(
            to: QueueDropTypes.internalTypeIdentifiers
        )
        queueDragTrace("destination validate target=\(targetID) accepted=\(accepted)")
        return accepted
    }

    func dropEntered(info: DropInfo) {
        queueDragTrace("destination enter target=\(targetID)")
        updateTarget(info)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        updateTarget(info)
        return DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if activeTarget?.jobID == targetID {
            activeTarget = nil
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let placeAfter = info.location.y >= 42
        let ids = draggedIDs
        queueDragTrace("destination drop target=\(targetID) moving=\(ids.count) after=\(placeAfter)")
        activeTarget = nil
        draggedIDs = []
        return move(ids, targetID, placeAfter)
    }

    private func updateTarget(_ info: DropInfo) {
        activeTarget = QueueJobDropTarget(
            jobID: targetID,
            placeAfter: info.location.y >= 42
        )
    }
}

struct QueueRowDragModifier: ViewModifier {
    let jobID: UUID
    @Binding var draggedIDs: Set<UUID>
    @Binding var activeTarget: QueueJobDropTarget?
    let move: (Set<UUID>, UUID, Bool) -> Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: indicatorAlignment) {
                if activeTarget?.jobID == jobID {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 3)
                        .allowsHitTesting(false)
                }
            }
            .onDrop(
                of: QueueDropTypes.internalTypeIdentifiers,
                delegate: QueueJobDropDelegate(
                    targetID: jobID,
                    draggedIDs: $draggedIDs,
                    activeTarget: $activeTarget,
                    move: move
                )
            )
    }

    private var indicatorAlignment: Alignment {
        activeTarget?.placeAfter == true ? .bottom : .top
    }
}

struct QueueReorderDragSource: NSViewRepresentable {
    let isEnabled: Bool
    let begin: () -> NSPasteboardItem
    let end: () -> Void

    func makeNSView(context: Context) -> DragSourceView {
        let view = DragSourceView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: DragSourceView, context: Context) {
        update(nsView)
    }

    private func update(_ view: DragSourceView) {
        view.isDragEnabled = isEnabled
        view.beginDrag = begin
        view.endDrag = end
    }

    final class DragSourceView: NSView, NSDraggingSource {
        var beginDrag: (() -> NSPasteboardItem)?
        var endDrag: (() -> Void)?
        var isDragEnabled = false {
            didSet {
                window?.invalidateCursorRects(for: self)
            }
        }

        private var hasActiveSession = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setAccessibilityElement(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            isDragEnabled && bounds.contains(point) ? self : nil
        }

        override func resetCursorRects() {
            addCursorRect(bounds, cursor: isDragEnabled ? .openHand : .arrow)
        }

        override func mouseDown(with event: NSEvent) {
            guard isDragEnabled else {
                super.mouseDown(with: event)
                return
            }
        }

        override func mouseDragged(with event: NSEvent) {
            guard isDragEnabled,
                  !hasActiveSession,
                  let provider = beginDrag?() else {
                return
            }

            hasActiveSession = true
            queueDragTrace("source begin")
            let item = NSDraggingItem(pasteboardWriter: provider)
            let image = NSImage(
                systemSymbolName: "equal",
                accessibilityDescription: "Reorder"
            )?.withSymbolConfiguration(.init(pointSize: 17, weight: .semibold))
            item.setDraggingFrame(bounds, contents: image)

            let session = beginDraggingSession(with: [item], event: event, source: self)
            session.animatesToStartingPositionsOnCancelOrFail = true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .move
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        func draggingSession(
            _ session: NSDraggingSession,
            endedAt screenPoint: NSPoint,
            operation: NSDragOperation
        ) {
            hasActiveSession = false
            queueDragTrace("source end operation=\(operation.rawValue)")
            endDrag?()
        }
    }
}

final class QueueActionMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(
        title: String,
        systemImage: String,
        enabled: Bool = true,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [],
        handler: @escaping () -> Void
    ) {
        self.handler = handler
        let localizedTitle = AppLocalization.text(title)
        super.init(title: localizedTitle, action: nil, keyEquivalent: keyEquivalent)
        target = self
        action = #selector(invoke(_:))
        isEnabled = enabled
        keyEquivalentModifierMask = modifierMask
        image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: localizedTitle
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        image?.isTemplate = true
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke(_ sender: Any?) {
        QueueMenuActionDispatcher.invoke(from: menu, handler: handler)
    }
}

enum QueueMenuActionDispatcher {
    static func invoke(from menu: NSMenu?, handler: @escaping () -> Void) {
        menu?.cancelTrackingWithoutAnimation()
        DispatchQueue.main.async(execute: handler)
    }
}

struct QueueMenuToolbarAction {
    let title: String
    let systemImage: String
    let tintColor: NSColor?
    let isEnabled: Bool
    let handler: () -> Void

    init(
        title: String,
        systemImage: String,
        tintColor: NSColor? = nil,
        isEnabled: Bool = true,
        handler: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tintColor = tintColor
        self.isEnabled = isEnabled
        self.handler = handler
    }
}

final class QueueMenuToolbarView: NSView {
    private let actions: [QueueMenuToolbarAction]

    init(actions: [QueueMenuToolbarAction], width: CGFloat = 242) {
        self.actions = actions
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 42))

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fillEqually
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])

        for (index, action) in actions.enumerated() {
            let localizedTitle = AppLocalization.text(action.title)
            let button = NSButton()
            button.tag = index
            button.target = self
            button.action = #selector(invoke(_:))
            button.bezelStyle = .inline
            button.isBordered = false
            button.imagePosition = .imageOnly
            button.imageScaling = .scaleProportionallyDown
            button.image = NSImage(
                systemSymbolName: action.systemImage,
                accessibilityDescription: localizedTitle
            )?.withSymbolConfiguration(.init(pointSize: 18, weight: .medium))
            button.contentTintColor = action.tintColor ?? .secondaryLabelColor
            button.isEnabled = action.isEnabled
            button.toolTip = localizedTitle
            button.setAccessibilityLabel(localizedTitle)
            stack.addArrangedSubview(button)
        }
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @objc private func invoke(_ sender: NSButton) {
        guard actions.indices.contains(sender.tag), actions[sender.tag].isEnabled else {
            return
        }
        let handler = actions[sender.tag].handler
        QueueMenuActionDispatcher.invoke(
            from: enclosingMenuItem?.menu,
            handler: handler
        )
    }
}

struct QueueNativeContextMenuBridge: NSViewRepresentable {
    let prepare: () -> Void
    let makeMenu: () -> NSMenu

    func makeNSView(context: Context) -> ContextMenuView {
        let view = ContextMenuView()
        update(view)
        return view
    }

    func updateNSView(_ nsView: ContextMenuView, context: Context) {
        update(nsView)
    }

    private func update(_ view: ContextMenuView) {
        view.prepare = prepare
        view.makeMenu = makeMenu
    }

    final class ContextMenuView: NSView {
        var prepare: (() -> Void)?
        var makeMenu: (() -> NSMenu)?

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            setAccessibilityElement(false)
        }

        required init?(coder: NSCoder) {
            super.init(coder: coder)
            setAccessibilityElement(false)
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard bounds.contains(point), let event = NSApp.currentEvent else {
                return nil
            }
            if event.type == .rightMouseDown ||
                (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
                return self
            }
            return nil
        }

        override func menu(for event: NSEvent) -> NSMenu? {
            prepare?()
            return makeMenu?()
        }
    }
}

enum QueueSelectionScroll {
    static func targetID(selectedIDs: Set<UUID>, visibleJobs: [DownloadJob]) -> UUID? {
        guard !selectedIDs.isEmpty else { return nil }
        return visibleJobs.first { selectedIDs.contains($0.id) }?.id
    }

    static func snapshot(
        selectedIDs: Set<UUID>,
        visibleJobs: [DownloadJob],
        layoutSignature: String
    ) -> QueueSelectionScrollSnapshot {
        QueueSelectionScrollSnapshot(
            targetID: targetID(selectedIDs: selectedIDs, visibleJobs: visibleJobs),
            visibleJobIDs: visibleJobs.map(\.id),
            layoutSignature: layoutSignature
        )
    }
}
