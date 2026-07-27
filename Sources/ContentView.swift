import AppKit
import SwiftUI
import UniformTypeIdentifiers

private struct EditablePresetComboBox: NSViewRepresentable {
    let placeholder: String
    @Binding var text: String
    let presets: [String]
    let accessibilityIdentifier: String
    let onPreset: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSComboBox {
        let comboBox = NSComboBox()
        comboBox.delegate = context.coordinator
        comboBox.usesDataSource = false
        comboBox.isEditable = true
        comboBox.completes = false
        comboBox.hasVerticalScroller = true
        comboBox.numberOfVisibleItems = min(12, max(3, presets.count))
        comboBox.placeholderString = AppLocalization.text(placeholder)
        comboBox.controlSize = .regular
        comboBox.font = .systemFont(ofSize: NSFont.systemFontSize)
        comboBox.setAccessibilityLabel(AppLocalization.text("Editable Naming Format"))
        comboBox.setAccessibilityIdentifier(accessibilityIdentifier)
        synchronize(comboBox, coordinator: context.coordinator)
        return comboBox
    }

    func updateNSView(_ comboBox: NSComboBox, context: Context) {
        context.coordinator.parent = self
        comboBox.placeholderString = AppLocalization.text(placeholder)
        comboBox.setAccessibilityLabel(AppLocalization.text("Editable Naming Format"))
        comboBox.setAccessibilityIdentifier(accessibilityIdentifier)
        synchronize(comboBox, coordinator: context.coordinator)
    }

    private func synchronize(_ comboBox: NSComboBox, coordinator: Coordinator) {
        coordinator.isUpdating = true
        defer { coordinator.isUpdating = false }

        let currentItems = (0..<comboBox.numberOfItems).compactMap {
            comboBox.itemObjectValue(at: $0) as? String
        }
        if currentItems != presets {
            comboBox.removeAllItems()
            comboBox.addItems(withObjectValues: presets)
        }
        if comboBox.stringValue != text {
            comboBox.stringValue = text
        }
        if let index = presets.firstIndex(of: text) {
            if comboBox.indexOfSelectedItem != index {
                comboBox.selectItem(at: index)
            }
        } else if comboBox.indexOfSelectedItem >= 0 {
            comboBox.deselectItem(at: comboBox.indexOfSelectedItem)
        }
    }

    final class Coordinator: NSObject, NSComboBoxDelegate {
        var parent: EditablePresetComboBox
        var isUpdating = false

        init(parent: EditablePresetComboBox) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard !isUpdating, let comboBox = notification.object as? NSComboBox else { return }
            parent.text = comboBox.stringValue
        }

        func comboBoxSelectionDidChange(_ notification: Notification) {
            guard !isUpdating,
                  let comboBox = notification.object as? NSComboBox,
                  comboBox.indexOfSelectedItem >= 0,
                  let preset = comboBox.objectValueOfSelectedItem as? String else {
                return
            }
            parent.text = preset
            parent.onPreset(preset)
        }
    }
}

private struct SourceFolderPopUpButton: NSViewRepresentable {
    let profiles: [DownloadSourceFolderProfile]
    let selectedID: String
    let language: AppInterfaceLanguage
    let onSelect: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .regular
        button.lineBreakMode = .byTruncatingTail
        button.target = context.coordinator
        button.action = #selector(Coordinator.selectionChanged(_:))
        button.setContentHuggingPriority(.defaultLow, for: .horizontal)
        synchronize(button, coordinator: context.coordinator)
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        synchronize(button, coordinator: context.coordinator)
    }

    private func synchronize(_ button: NSPopUpButton, coordinator: Coordinator) {
        let signature = profiles.map {
            "\($0.id)|\($0.displayName)|\($0.faviconKey)"
        }
        if coordinator.profileSignature != signature {
            button.removeAllItems()
            for profile in profiles {
                button.addItem(withTitle: profile.displayName)
                guard let item = button.lastItem else { continue }
                item.representedObject = profile.id
                if let source = SiteFaviconCatalog.image(resourceKey: profile.faviconKey),
                   let image = source.copy() as? NSImage {
                    image.size = NSSize(width: 18, height: 18)
                    item.image = image
                }
            }
            coordinator.profileSignature = signature
        }

        if let selectedIndex = button.itemArray.firstIndex(where: {
            ($0.representedObject as? String) == selectedID
        }), button.indexOfSelectedItem != selectedIndex {
            button.selectItem(at: selectedIndex)
        }
        button.setAccessibilityLabel(AppLocalization.text(
            "Download Source",
            language: language
        ))
        button.setAccessibilityValue(
            profiles.first(where: { $0.id == selectedID })?.displayName ?? ""
        )
        button.setAccessibilityIdentifier("settings.source-folder-menu")
    }

    final class Coordinator: NSObject {
        var parent: SourceFolderPopUpButton
        var profileSignature: [String] = []

        init(parent: SourceFolderPopUpButton) {
            self.parent = parent
        }

        @objc func selectionChanged(_ sender: NSPopUpButton) {
            guard let selectedID = sender.selectedItem?.representedObject as? String else {
                return
            }
            parent.onSelect(selectedID)
        }
    }
}

private func queueDragTrace(_ message: String) {
    guard ProcessInfo.processInfo.environment["HITOMI_NATIVE_UI_TEST_DRAG_TRACE"] == "1" else {
        return
    }
    FileHandle.standardError.write(Data("QUEUE_DRAG \(message)\n".utf8))
}

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

struct QueueSelectionScrollSnapshot: Equatable {
    let targetID: UUID?
    let visibleJobIDs: [UUID]
    let layoutSignature: String
}

private enum QueueGridBlock: Identifiable {
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

private struct QueueJobDropDelegate: DropDelegate {
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

private struct QueueRowDragModifier: ViewModifier {
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

private struct QueueReorderDragSource: NSViewRepresentable {
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

private final class QueueActionMenuItem: NSMenuItem {
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
        handler()
    }
}

private struct QueueMenuToolbarAction {
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

private final class QueueMenuToolbarView: NSView {
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
        enclosingMenuItem?.menu?.cancelTracking()
        DispatchQueue.main.async(execute: handler)
    }
}

private struct QueueNativeContextMenuBridge: NSViewRepresentable {
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

    static func snapshot(selectedIDs: Set<UUID>, visibleJobs: [DownloadJob], layoutSignature: String) -> QueueSelectionScrollSnapshot {
        QueueSelectionScrollSnapshot(
            targetID: targetID(selectedIDs: selectedIDs, visibleJobs: visibleJobs),
            visibleJobIDs: visibleJobs.map(\.id),
            layoutSignature: layoutSignature
        )
    }
}

private struct MainUIScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1
}

private extension EnvironmentValues {
    var mainUIScale: CGFloat {
        get { self[MainUIScaleKey.self] }
        set { self[MainUIScaleKey.self] = min(2, max(0.5, newValue)) }
    }
}

private struct UIScaledRoot<Content: View>: View {
    let scale: Double
    @ViewBuilder var content: () -> Content

    private var effectiveScale: CGFloat {
        min(2, max(0.5, CGFloat(scale)))
    }

    var body: some View {
        content()
            .environment(\.mainUIScale, effectiveScale)
    }
}

private struct CompactLinearProgress: View {
    let value: Double
    var color: Color = .accentColor
    @Environment(\.mainUIScale) private var uiScale

    var body: some View {
        GeometryReader { geometry in
            let fraction = min(1, max(0, value))
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.2))
                Capsule()
                    .fill(color)
                    .frame(width: geometry.size.width * fraction)
            }
        }
        .frame(height: 4 * uiScale)
        .accessibilityValue("\(Int(min(1, max(0, value)) * 100)) percent")
    }
}

private struct ClockwiseDownloadIndicator: View {
    var color: Color
    var size: CGFloat
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: reduceMotion)) { context in
            let cycle = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: 1.8) / 1.8
            Image(systemName: "arrow.triangle.2.circlepath")
                .symbolRenderingMode(.monochrome)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(color)
                .rotationEffect(.degrees(reduceMotion ? 0 : cycle * 360))
        }
        .accessibilityLabel(AppLocalization.text("Downloading"))
    }
}

private struct DuplicateJobConfirmationView: View {
    let message: String
    let confirm: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 54, height: 54)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Duplicate Tasks")
                        .font(.headline)
                    Text(message)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
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

struct ContentView: View {
    @EnvironmentObject private var manager: DownloadManager

    private var mainUIScale: CGFloat {
        CGFloat(manager.uiScale.factor)
    }

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * mainUIScale
    }

    private var scaledInterfaceFont: Font {
        let size = CGFloat(manager.interfaceFontSize.pointSize) * mainUIScale
        let family = manager.interfaceFontFamily.trimmed
        return family.isEmpty ? .system(size: size) : .custom(family, size: size)
    }

    private var rootFontSettingsPresentation: Binding<Bool> {
        Binding(
            get: {
                manager.showingFontSettings && !manager.showingSettingsWindow
            },
            set: { manager.showingFontSettings = $0 }
        )
    }

    var body: some View {
        GeometryReader { geometry in
            content(hostSize: geometry.size)
                .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }

    private func content(hostSize: CGSize) -> some View {
        scaledContent
        .sheet(item: $manager.infoJob) { job in
            jobInfoView(for: job)
        }
        .sheet(item: $manager.editingJob) { _ in
            JobEditSheet(
                title: $manager.jobEditTitle,
                source: $manager.jobEditSource,
                input: $manager.jobEditInput,
                outputPath: $manager.jobEditOutputPath,
                artist: $manager.jobEditArtist,
                zipFile: $manager.jobEditZipFile,
                status: $manager.jobEditStatus,
                type: $manager.jobEditType,
                site: $manager.jobEditSite,
                date: $manager.jobEditDate,
                range: $manager.jobEditRange,
                names: manager.jobEditNamesText,
                comment: $manager.jobEditComment,
                thumbnailImage: manager.jobEditThumbnailImage,
                thumbnailIsCustom: manager.jobEditThumbnailIsCustom,
                thumbnailMessage: manager.jobEditThumbnailMessage,
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
        .sheet(item: $manager.pageSelectorJob) { _ in
            PageSelectorSheet(manager: manager)
        }
        .sheet(item: $manager.editingBookmark) { bookmark in
            BookmarkEditSheet(
                url: bookmark.url,
                title: $manager.bookmarkEditTitle,
                tags: $manager.bookmarkEditTags,
                note: $manager.bookmarkEditNote
            ) {
                manager.cancelEditingBookmark()
            } save: {
                manager.saveEditingBookmark()
            }
        }
        .sheet(item: $manager.editingCommentJob) { job in
            JobCommentSheet(
                title: manager.editingCommentJobIDs.count > 1
                    ? "\(manager.editingCommentJobIDs.count) Selected Jobs"
                    : job.title,
                source: manager.editingCommentJobIDs.count > 1
                    ? "Apply the comment to all selected jobs."
                    : job.source,
                comment: $manager.jobCommentText
            ) {
                manager.cancelEditingJobComment()
            } save: {
                manager.saveEditingJobComment()
            }
        }
        .sheet(isPresented: $manager.showingSettingsWindow) {
            SettingsWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingQuickAccessCustomization) {
            QuickAccessCustomizationView(manager: manager)
        }
        .sheet(isPresented: rootFontSettingsPresentation) {
            FontSettingsView(manager: manager)
        }
        .sheet(isPresented: $manager.showingShortcutSettings) {
            ShortcutSettingsView(manager: manager)
        }
        .sheet(isPresented: $manager.showingStatistics) {
            StatisticsView(manager: manager)
        }
        .sheet(isPresented: $manager.showingActivityLog) {
            ActivityLogView(manager: manager)
        }
        .sheet(isPresented: $manager.showingHistoryWindow) {
            HistoryWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingSearcher) {
            SearcherWindowView(manager: manager, hostSize: hostSize)
        }
        .sheet(isPresented: $manager.showingDirectories) {
            DirectoriesView(manager: manager)
        }
        .sheet(isPresented: $manager.showingMetadataFinder) {
            MetadataFinderView(manager: manager)
        }
        .sheet(isPresented: $manager.showingMetadataAnalysis) {
            MetadataAnalysisView(manager: manager)
        }
        .sheet(isPresented: $manager.showingDuplicateImageFinder) {
            DuplicateImageFinderWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingClipboardViewer) {
            ClipboardViewerWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingBrowserWindow) {
            BrowserWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingTextViewer) {
            TextViewerWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingProgressWindow) {
            ProgressWindowView(manager: manager)
        }
        .sheet(isPresented: $manager.showingAbout) {
            AboutView(manager: manager)
        }
        .sheet(isPresented: $manager.showingHelp) {
            HelpView()
        }
        .sheet(isPresented: $manager.showingStatusColorPicker) {
            StatusColorPickerView(manager: manager)
        }
        .sheet(isPresented: $manager.showingArtistRecommendations) {
            ArtistRecommendationsView()
                .environmentObject(manager)
        }
        .sheet(isPresented: $manager.showingHitomiTaster) {
            HitomiTasterWizardView(manager: manager)
        }
        .sheet(isPresented: $manager.showingDuplicateAdditionConfirmation) {
            DuplicateJobConfirmationView(message: manager.duplicateAdditionMessage) {
                manager.confirmDuplicateAddition()
            } cancel: {
                manager.cancelDuplicateAddition()
            }
        }
        .alert("Storage Warning", isPresented: $manager.showingStorageWarning) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(manager.storageWarningText)
        }
        .alert(manager.queueGroupPromptTitle, isPresented: $manager.showingJobGroupPrompt) {
            TextField("Group Name", text: $manager.jobGroupNameDraft)
            Button(manager.queueGroupPromptButtonTitle) {
                manager.savePendingJobGroup()
            }
            .disabled(manager.jobGroupNameDraft.trimmed.isEmpty)
            Button("Cancel", role: .cancel) {
                manager.cancelPendingJobGroup()
            }
        } message: {
            Text(manager.queueGroupPromptMessage)
        }
        .alert("Remove this group?", isPresented: $manager.showingQueueGroupRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                manager.removePendingQueueGroup()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingQueueGroupRemoval()
            }
        } message: {
            let group = manager.queueGroupPendingRemoval
            let count = group.map { manager.jobs(in: $0).count } ?? 0
            Text(AppLocalization.format(
                "Only \"%@\" will be removed. Its %@ tasks and downloaded files will be kept.",
                language: manager.interfaceLanguage,
                group?.name ?? AppLocalization.text("This Group", language: manager.interfaceLanguage),
                String(count)
            ))
        }
        .alert("Restart tasks in this group?", isPresented: $manager.showingQueueGroupRetryConfirmation) {
            Button("Restart") {
                manager.retryPendingQueueGroup()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingQueueGroupRetry()
            }
        } message: {
            let group = manager.queueGroupPendingRetry
            let count = group.map { manager.jobs(in: $0).count } ?? 0
            Text(AppLocalization.format(
                "Restart %@ tasks.",
                language: manager.interfaceLanguage,
                String(count)
            ))
        }
        .alert("Remove from the list?", isPresented: $manager.showingJobRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                manager.removePendingJobs()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingJobRemoval()
            }
        } message: {
            Text(manager.jobRemovalConfirmationMessage)
        }
        .alert("Clear Finished Items?", isPresented: $manager.showingClearFinishedConfirmation) {
            Button("Clear", role: .destructive) {
                manager.clearFinished()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(manager.removableFinishedJobCount) finished, failed, or cancelled queue item(s)? Downloaded files will not be deleted.")
        }
        .alert("Clear Bookmarks?", isPresented: $manager.showingClearBookmarksConfirmation) {
            Button("Clear", role: .destructive) {
                manager.clearBookmarks()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove \(manager.bookmarks.count) bookmark(s)? Queued jobs and downloaded files will not be deleted.")
        }
        .alert("Restart incomplete tasks?", isPresented: $manager.showingRetryIncompleteJobsConfirmation) {
            Button("Restart") {
                manager.retryPendingIncompleteJobs()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingIncompleteJobRetry()
            }
        } message: {
            Text(manager.retryIncompleteJobsConfirmationMessage)
        }
        .alert("Remove completed tasks?", isPresented: $manager.showingCompletedJobsRemovalConfirmation) {
            Button("Remove", role: .destructive) {
                manager.removePendingCompletedJobs()
            }
            Button("Cancel", role: .cancel) {
                manager.cancelPendingCompletedJobRemoval()
            }
        } message: {
            Text(manager.completedJobsRemovalConfirmationMessage)
        }
        .confirmationDialog(
            outputDeletionConfirmationTitle,
            isPresented: $manager.showingOutputDeletionConfirmation,
            titleVisibility: .visible
        ) {
            if manager.removeJobAfterOutputDeletion {
                Button(
                    outputDeletionDestructiveTitle,
                    role: .destructive
                ) {
                    manager.trashOutputCandidates(Set(manager.outputDeletionCandidates.map(\.id)))
                }
            } else {
                ForEach(manager.outputDeletionCandidates) { candidate in
                    Button(candidate.displayLabel, role: .destructive) {
                        manager.trashOutputCandidates([candidate.id])
                    }
                }
                if manager.outputDeletionCandidates.count > 1 {
                    Button("All Downloaded Output", role: .destructive) {
                        manager.trashOutputCandidates(Set(manager.outputDeletionCandidates.map(\.id)))
                    }
                }
            }
            Button("Cancel", role: .cancel) {
                manager.cancelDeletingOutput()
            }
        } message: {
            Text(manager.outputDeletionConfirmationMessage)
        }
        .task {
            await configureUITestFixtures()
        }
    }

    private var outputDeletionConfirmationTitle: String {
        guard manager.removeJobAfterOutputDeletion else {
            return AppLocalization.text(
                "Move downloaded output to the Trash?",
                language: manager.interfaceLanguage
            )
        }
        return manager.pendingOutputDeletionJobCount > 1
            ? AppLocalization.format(
                "Delete %@ tasks and their downloaded files?",
                language: manager.interfaceLanguage,
                String(manager.pendingOutputDeletionJobCount)
            )
            : AppLocalization.text(
                "Delete the task and downloaded files?",
                language: manager.interfaceLanguage
            )
    }

    private var outputDeletionDestructiveTitle: String {
        return manager.pendingOutputDeletionJobCount > 1
            ? AppLocalization.format(
                "Delete %@ Tasks and All Downloaded Files",
                language: manager.interfaceLanguage,
                String(manager.pendingOutputDeletionJobCount)
            )
            : AppLocalization.text(
                "Delete Task and All Downloaded Files",
                language: manager.interfaceLanguage
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
                manager.jobs = [fixture, active]
                manager.isRunning = true
            } else {
                manager.jobs = [fixture]
            }
            manager.selectedJobIDs = [fixture.id]
            if environment["HITOMI_NATIVE_UI_TEST_OUTPUT_PREVIEW"] == "1" {
                await Task.yield()
                manager.openOutputPreview(for: fixture)
            } else if environment["HITOMI_NATIVE_UI_TEST_JOB_INFO"] == "1" {
                await Task.yield()
                manager.infoJob = fixture
            }
        }
        if environment["HITOMI_NATIVE_UI_TEST_DUPLICATE"] == "1",
           let source = manager.jobs.first?.source {
            manager.skipDuplicates = true
            manager.setInputText(source)
            manager.addURLs(fallbackText: nil)
        }
        if let maintenanceAction = environment["HITOMI_NATIVE_UI_TEST_QUEUE_MAINTENANCE"]?.trimmed.lowercased(),
           maintenanceAction == "retry" || maintenanceAction == "clear" {
            manager.pauseQueue()
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
            manager.jobs = [failed, incomplete, completed, lockedCompleted]
            manager.selectedJobIDs = []
            await Task.yield()
            if maintenanceAction == "retry" {
                manager.beginRetryIncompleteJobs()
            } else {
                manager.beginRemovingCompletedJobs()
            }
        }
        if let accessReaction = environment["HITOMI_NATIVE_UI_TEST_ACCESS_REACTION"]?.trimmed.lowercased(),
           accessReaction == "login" || accessReaction == "cookie" {
            manager.pauseQueue()
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
            manager.jobs = [ordinary, attention]
            manager.selectedJobIDs = []
        }
        if environment["HITOMI_NATIVE_UI_TEST_TASK_REACTION"]?.trimmed.lowercased() == "disgusting" {
            manager.pauseQueue()
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
            manager.jobs = [ordinary, reaction]
            manager.selectedJobIDs = [reaction.id]
        }
        if environment["HITOMI_NATIVE_UI_TEST_DELAYED_RETRY"] == "1" {
            manager.pauseQueue()
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
            manager.jobs = [retry]
            manager.selectedJobIDs = []
            manager.restoreScheduledRetries()
        }
        if environment["HITOMI_NATIVE_UI_TEST_QUEUE_GROUPS"] == "1" {
            configureQueueGroupUITestFixture()
        }
        if let rawViewMode = environment["HITOMI_NATIVE_UI_TEST_QUEUE_VIEW"],
           let viewMode = QueueViewMode(rawValue: rawViewMode.lowercased()) {
            manager.queueViewMode = viewMode
        }
        if environment["HITOMI_NATIVE_UI_TEST_HIDE_QUEUE_THUMBNAILS"] == "1" {
            manager.queueThumbnailsHidden = true
        }
        if let rawScale = environment["HITOMI_NATIVE_UI_TEST_QUEUE_THUMBNAIL_SCALE"],
           let thumbnailScale = queueThumbnailScale(fromTestValue: rawScale) {
            manager.queueThumbnailScale = thumbnailScale
        }
        if environment["HITOMI_NATIVE_UI_TEST_GENERAL_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .general)
        } else if environment["HITOMI_NATIVE_UI_TEST_NETWORK_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .network)
        } else if environment["HITOMI_NATIVE_UI_TEST_YOUTUBE_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .youtube)
        } else if environment["HITOMI_NATIVE_UI_TEST_HITOMI_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .hitomi)
        } else if environment["HITOMI_NATIVE_UI_TEST_PIXIV_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .pixiv)
        } else if environment["HITOMI_NATIVE_UI_TEST_KEMONO_FRIENDS_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .kemonoFriends)
        } else if environment["HITOMI_NATIVE_UI_TEST_SOCIAL_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .social)
        } else if environment["HITOMI_NATIVE_UI_TEST_THEME_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .theme)
        } else if environment["HITOMI_NATIVE_UI_TEST_ARCHIVE_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .archive)
        } else if environment["HITOMI_NATIVE_UI_TEST_SETTINGS"] == "1" {
            await Task.yield()
            manager.openSettingsWindow(category: .advanced)
        }
        if environment["HITOMI_NATIVE_UI_TEST_ABOUT"] == "1" {
            await Task.yield()
            manager.showingAbout = true
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
        manager.jobs = [fixture]
        manager.history = [
            DownloadHistoryEntry(
                source: source,
                normalizedSource: source,
                title: fixture.title,
                outputPath: fixtureOutputPath,
                completedAt: completedAt,
                metadata: metadata
            )
        ]
        manager.activityLog = [
            ActivityLogEntry(
                timestamp: completedAt,
                category: "Download",
                message: "Done"
            )
        ]

        switch window {
        case "font":
            manager.showingFontSettings = true
        case "statistics":
            manager.showingStatistics = true
        case "activity":
            manager.showingActivityLog = true
        case "history":
            manager.showingHistoryWindow = true
        case "directories":
            manager.showingDirectories = true
        case "artists":
            manager.showingArtistRecommendations = true
        default:
            break
        }
    }

    private func jobInfoView(for job: DownloadJob) -> JobInfoView {
        let current = manager.jobs.first(where: { $0.id == job.id }) ?? job
        let queueIndex = manager.queueOrderIndex(for: current)
        let groupName = manager.jobGroupName(for: current)
        return JobInfoView(job: current, queueIndex: queueIndex, groupName: groupName)
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
        manager.jobs = [
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
        ]
        manager.queueGroups = [
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
        ]
        manager.queueSortMode = .manual
        manager.queueSortDescending = false
        manager.queueFilter = ""
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
        UIScaledRoot(scale: manager.uiScale.factor) {
            VStack(spacing: 0) {
                compactMenuBar
                Divider()
                compactToolbar
                Divider()
                queuePane
            }
        }
        .font(scaledInterfaceFont)
        .foregroundStyle(manager.activeThemeForegroundColor ?? Color.primary)
        .background(manager.activeThemeBackgroundColor ?? Color(nsColor: .windowBackgroundColor))
        .onDrop(
            of: QueueDropTypes.externalTypeIdentifiers,
            isTargeted: $manager.isExternalDropTargeted,
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
        manager.isExternalDropTargeted
            || ProcessInfo.processInfo.environment["HITOMI_NATIVE_UI_TEST_DROP_OVERLAY"] == "1"
    }

    private var statusColorSummary: String {
        manager.jobStatusColorPalette == .defaultPalette ? "Default Palette" : "Custom Palette"
    }

    private var canStartQueue: Bool {
        !manager.inputText.trimmed.isEmpty || manager.jobs.contains { $0.status == .queued }
    }

    private var completedQueueJobCount: Int {
        manager.jobs.filter {
            $0.status == .finished || $0.status == .failed || $0.status == .cancelled
        }.count
    }

    private var overallQueueProgress: Double {
        guard !manager.jobs.isEmpty else { return 0 }
        let total = manager.jobs.reduce(0.0) { partial, job in
            switch job.status {
            case .finished, .failed, .cancelled:
                return partial + 1
            case .resolving, .downloading:
                return partial + min(1, max(0, job.progress))
            case .queued:
                return partial
            }
        }
        return total / Double(manager.jobs.count)
    }

    private var knownQueueByteCount: Int64 {
        let keys = ["byte_count", "content_length", "filesize", "file_size", "total_bytes", "expected_bytes", "size"]
        return manager.jobs.reduce(0) { partial, job in
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
        manager.inputAutocompleteSuggestions
    }

    private var compactMenuFontSize: CGFloat {
        max(9, CGFloat(manager.interfaceFontSize.pointSize) + 1)
    }

    private func compactMenuTitle(_ key: String) -> some View {
        Text(AppLocalization.text(key, language: manager.interfaceLanguage))
            .font(.system(size: compactMenuFontSize, weight: .regular))
            .fontWeight(.regular)
            .lineLimit(1)
            .fixedSize()
    }

    private var compactMenuBar: some View {
        HStack(spacing: scaled(26)) {
            Menu {
                Button {
                    manager.startQueue()
                } label: {
                    Label("Start Queue", systemImage: "play.fill")
                }
                .disabled(manager.isRunning || !canStartQueue)

                Button {
                    manager.cancelQueue()
                } label: {
                    Label("Stop Queue", systemImage: "stop.fill")
                }
                .disabled(!manager.isRunning)

                Divider()
                Button {
                    manager.pasteAndDownloadURLs()
                } label: {
                    Label("Paste and Add", systemImage: "doc.on.clipboard")
                }
                Button {
                    manager.addLocalFilesAndFolders()
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
                    (manager.jobs.isEmpty && manager.queueGroups.isEmpty) ||
                    (!manager.queueFilter.trimmed.isEmpty &&
                        manager.filteredJobs.isEmpty &&
                        manager.selectedJobIDs.isEmpty)
                )

                Divider()
                Button {
                    requestClearFinished()
                } label: {
                    Label("Remove All Completed Tasks", systemImage: "checkmark.circle")
                }
                .disabled(manager.removableFinishedJobCount == 0)
            } label: {
                compactMenuTitle("Task")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Menu {
                Button {
                    manager.showingSearcher = true
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
                    manager.openDuplicateImageFinder()
                } label: {
                    Label("Find Duplicate Images...", systemImage: "photo.on.rectangle")
                }
                .accessibilityIdentifier("tools.duplicate-image-finder")

                Button {
                    manager.showingArtistRecommendations = true
                } label: {
                    Label("Artist Recommendations...", systemImage: "person.2")
                }
                .accessibilityIdentifier("tools.artist-recommendations")

                Button {
                    manager.selectRandomVisibleJob()
                } label: {
                    Label("Pick One at Random", systemImage: "dice")
                }
                .disabled(!manager.canSelectRandomVisibleJob)
                .accessibilityIdentifier("tools.select-random-job")

                Button {
                    manager.copyGalleryNumbersInSaveFolder()
                } label: {
                    Label("Copy All Gallery IDs in Save Folder", systemImage: "number.square")
                }
                .disabled(manager.isCopyingGalleryNumbers)
                .accessibilityIdentifier("tools.copy-gallery-ids")

                Divider()
                Button {
                    manager.showingHistoryWindow = true
                } label: {
                    Label("History...", systemImage: "clock.arrow.circlepath")
                }
                Button {
                    manager.showingStatistics = true
                } label: {
                    Label("Info & Statistics...", systemImage: "chart.bar.xaxis")
                }
                Button {
                    manager.showingActivityLog = true
                } label: {
                    Label("Activity Log...", systemImage: "doc.text.magnifyingglass")
                }
                Button {
                    manager.showingDirectories = true
                } label: {
                    Label("Download Folder...", systemImage: "folder")
                }
            } label: {
                compactMenuTitle("Tools")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            CompactOptionsMenuButton(
                fontSize: compactMenuFontSize,
                interfaceLanguage: manager.interfaceLanguage,
                queueViewMode: manager.queueViewMode,
                queueThumbnailsHidden: manager.queueThumbnailsHidden,
                queueThumbnailScale: manager.queueThumbnailScale,
                appearanceMode: manager.appAppearanceMode,
                setQueueViewMode: manager.setQueueViewMode,
                toggleQueueViewMode: manager.toggleQueueViewMode,
                setQueueThumbnailsHidden: manager.setQueueThumbnailsHidden,
                setQueueThumbnailScale: manager.setQueueThumbnailScale,
                openSettings: { manager.openSettingsWindow() },
                openFontSettings: manager.openFontSettings,
                openShortcutSettings: manager.openShortcutSettings,
                setAppearanceMode: manager.setAppAppearanceMode
            )
            .fixedSize()

            Menu {
                Button {
                    manager.showingHelp = true
                } label: {
                    Label("Help", systemImage: "questionmark.circle")
                }
                Button {
                    manager.showingAbout = true
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

            if !manager.enabledQuickAccessItems.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: scaled(2)) {
                        ForEach(manager.enabledQuickAccessItems) { item in
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
                            .help(item.command.localizedLabel(language: manager.interfaceLanguage))
                            .accessibilityLabel(item.command.localizedLabel(language: manager.interfaceLanguage))
                            .accessibilityIdentifier("quick-access.action.\(item.command.rawValue)")
                        }
                    }
                }
                .frame(
                    width: min(
                        120,
                        scaled(CGFloat(manager.enabledQuickAccessItems.count) * 28)
                    ),
                    height: scaled(28)
                )
            }

            Button {
                manager.showQuickAccessCustomization()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.system(size: scaled(10), weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: scaled(22), height: scaled(26))
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text("Customize Quick Access Toolbar", language: manager.interfaceLanguage))
            .accessibilityLabel(AppLocalization.text("Customize Quick Access Toolbar", language: manager.interfaceLanguage))
            .accessibilityIdentifier("quick-access.customize")

            FlatOpacitySlider(value: Binding(
                get: { manager.mainWindowOpacity },
                set: { manager.setMainWindowOpacity($0) }
            ), range: MainWindowAppearance.minimumOpacity...1, step: 0.01)
            .frame(width: scaled(92), height: scaled(18))
            .offset(y: scaled(-2))
            .help(AppLocalization.format(
                "Window Opacity: %@",
                language: manager.interfaceLanguage,
                manager.mainWindowOpacityPercentText
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
                manager.toggleQueueEnabled()
            } label: {
                ZStack {
                    Circle()
                        .fill(manager.isQueueEnabled ? Color.accentColor : Color.red)
                    Circle()
                        .fill(Color.white.opacity(0.92))
                        .frame(width: scaled(34), height: scaled(34))
                    Image(systemName: manager.isQueueEnabled ? "play.fill" : "pause.fill")
                        .font(.system(size: scaled(17), weight: .bold))
                        .foregroundStyle(manager.isQueueEnabled ? Color.accentColor : Color.red)
                        .offset(x: manager.isQueueEnabled ? scaled(1) : 0)
                }
                .frame(width: scaled(54), height: scaled(54))
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text(
                manager.isQueueEnabled ? "Pause Queue" : "Resume Queue",
                language: manager.interfaceLanguage
            ))

            HStack(spacing: scaled(8)) {
                Button {
                    manager.pasteAndDownloadURLs()
                } label: {
                    Image(systemName: "link")
                        .foregroundStyle(.secondary)
                        .font(.system(size: scaled(20), weight: .medium))
                        .frame(width: scaled(32), height: scaled(38))
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text("Paste and Add", language: manager.interfaceLanguage))
                .contextMenu {
                    Button {
                        manager.pasteURLs()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    Button {
                        manager.pasteAndDownloadURLs()
                    } label: {
                        Label("Paste and Add", systemImage: "text.badge.plus")
                    }
                    Divider()
                    Button {
                        manager.addLocalFilesAndFolders()
                    } label: {
                        Label("Add Files or Folders...", systemImage: "folder.badge.plus")
                    }
                    Button {
                        manager.importURLList()
                    } label: {
                        Label("Import URL List...", systemImage: "square.and.arrow.down")
                    }
                }

                OriginalURLTextField(text: Binding(
                    get: { manager.inputText },
                    set: { manager.setInputText($0) }
                ), cursorUTF16Offset: manager.inputCursorUTF16Offset,
                placeholder: "Enter a URL", fontSize: scaled(15), onFocusChange: {
                    manager.setURLInputFocused($0)
                }, onCursorChange: {
                    manager.setInputCursorUTF16Offset($0)
                }, onMoveCompletion: {
                    let delta = $0
                    guard !manager.inputAutocompleteSuggestions.isEmpty else { return false }
                    DispatchQueue.main.async {
                        manager.moveInputAutocompleteSelection(by: delta)
                    }
                    return true
                }, onAcceptCompletion: {
                    guard !manager.inputAutocompleteSuggestions.isEmpty else { return false }
                    DispatchQueue.main.async {
                        manager.acceptInputAutocompleteSuggestion()
                    }
                    return true
                }, onDismissCompletion: {
                    guard !manager.inputAutocompleteSuggestions.isEmpty else { return false }
                    DispatchQueue.main.async {
                        manager.dismissInputAutocomplete()
                    }
                    return true
                }) {
                    manager.addURLs()
                }
                .frame(maxWidth: .infinity, minHeight: scaled(38))
                .overlay(alignment: .bottomLeading) {
                    if !inputAutocompleteSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(inputAutocompleteSuggestions.enumerated()), id: \.element) { index, suggestion in
                                Button {
                                    manager.acceptInputAutocompleteSuggestion(suggestion)
                                } label: {
                                    Text(suggestion)
                                        .font(.system(size: scaled(14)))
                                        .foregroundStyle(
                                            index == manager.inputAutocompleteSelectionIndex
                                                ? Color.white
                                                : Color.primary
                                        )
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.horizontal, scaled(10))
                                        .padding(.vertical, scaled(5))
                                        .background(
                                            index == manager.inputAutocompleteSelectionIndex
                                                ? Color.accentColor
                                                : Color.clear
                                        )
                                }
                                .buttonStyle(.plain)
                                .focusable(false)
                                .onHover { hovering in
                                    if hovering {
                                        manager.setInputAutocompleteSelection(index)
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
                manager.addURLs()
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
            .help(AppLocalization.text("Add to Queue", language: manager.interfaceLanguage))
            .contextMenu {
                Button {
                    manager.addMP3AudioURLs()
                } label: {
                    Label("Add as MP3 Audio", systemImage: "music.note")
                }
                Button {
                    manager.bookmarkInputURLs()
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

    private var toolbar: some View {
        HStack(spacing: 8) {
            Button {
                manager.startQueue()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(manager.isRunning)

            Button {
                manager.cancelQueue()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
            .disabled(!manager.isRunning)

            Button {
                requestClearFinished()
            } label: {
                Label("Clear", systemImage: "checkmark.circle")
            }

            Button {
                manager.openSettingsWindow()
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")

            Button {
                manager.openProgressWindow()
            } label: {
                Image(systemName: "gauge")
            }
            .help("Progress")

            Button {
                manager.showingStatistics = true
            } label: {
                Image(systemName: "chart.bar.xaxis")
            }
            .help("Info & Statistics")

            Button {
                manager.showingActivityLog = true
            } label: {
                Image(systemName: "doc.text.magnifyingglass")
            }
            .help("Log")

            Button {
                manager.showingHistoryWindow = true
            } label: {
                Image(systemName: "clock.arrow.circlepath")
            }
            .help("History")

            Button {
                manager.showingDirectories = true
            } label: {
                Image(systemName: "folder")
            }
            .help("Dirs")

            Button {
                manager.showingMetadataFinder = true
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Finder")

            Button {
                manager.showingMetadataAnalysis = true
            } label: {
                Image(systemName: "chart.pie")
            }
            .help("Analysis")

            Button {
                manager.showingSearcher = true
            } label: {
                Image(systemName: "text.magnifyingglass")
            }
            .help("Searcher")

            Button {
                manager.openBrowserWindow()
            } label: {
                Image(systemName: "safari")
            }
            .help("Browser")

            Button {
                manager.openTextViewer()
            } label: {
                Image(systemName: "doc.plaintext")
            }
            .help("Text Viewer")

            Button {
                manager.openOutputPreviewForSelectedJobs()
            } label: {
                Image(systemName: "photo")
            }
            .help("Output Preview")

            Button {
                manager.beginEditingStatusColors()
            } label: {
                Image(systemName: "paintpalette")
            }
            .help("Status Colors")

            Button {
                manager.showingArtistRecommendations = true
            } label: {
                Image(systemName: "person.2")
            }
            .help("Artist Recommendations")

            Button {
                manager.openHitomiTaster()
            } label: {
                Image(systemName: "brain.head.profile")
            }
            .help("Hitomi Taster")

            Button {
                manager.openDuplicateImageFinder()
            } label: {
                Image(systemName: "photo.on.rectangle")
            }
            .help("Duplicate Image Finder")

            Button {
                manager.openClipboardViewer()
            } label: {
                Image(systemName: "doc.on.clipboard")
            }
            .help("Clipboard Viewer")

            Spacer(minLength: 16)

            Button {
                manager.importCookies()
            } label: {
                Image(systemName: "key")
            }
            .help("Import cookies.txt or Cookie header")

            Button {
                manager.importBrowserCookies()
            } label: {
                Image(systemName: "globe")
            }
            .help("Import Firefox or Chromium browser cookies")

            Button {
                manager.importDetectedBrowserCookies()
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .help("Find installed browser cookie databases")

            Button {
                manager.openLoginBrowser()
            } label: {
                Image(systemName: "person.crop.circle.badge.key")
            }
            .help("Open login browser and save cookies")

            Button {
                manager.clearCookies()
            } label: {
                Label("Delete Cookies and Login Sessions", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .disabled(manager.isClearingCookies)
            .help(AppLocalization.text(
                "Delete app cookies and embedded-browser login sessions",
                language: manager.interfaceLanguage
            ))
            .accessibilityIdentifier("toolbar.clear-cookies")

            Text(AppLocalization.statusText(
                manager.cookieSummary,
                language: manager.interfaceLanguage
            ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: 100, alignment: .leading)

            Stepper(value: $manager.jobConcurrency, in: 1...12) {
                Text("Tasks \(manager.jobConcurrency)")
                    .monospacedDigit()
            }
            .frame(width: 120)
            .help("Maximum queue tasks to run at the same time.")

            Stepper(value: $manager.concurrency, in: 1...24) {
                Text("Threads \(manager.concurrency)")
                    .monospacedDigit()
            }
            .frame(width: 140)
            .help("Maximum file downloads inside each task.")

            Toggle("WebP", isOn: $manager.preferWebP)
                .toggleStyle(.switch)
                .help("Prefer Hitomi WebP image URLs when available.")

            Toggle("Info TXT", isOn: $manager.saveHitomiGalleryInfoText)
                .toggleStyle(.switch)
                .help("Save Hitomi gallery metadata as gallery-info.txt.")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var inputPane: some View {
        ScrollViewReader { proxy in
        ScrollView {
        VStack(alignment: .leading, spacing: 12) {
            settingsSearchBox(proxy: proxy)

            settingsSectionAnchor(.urls)
            Text("URLs")
                .font(.headline)

            TextEditor(text: Binding(
                get: { manager.inputText },
                set: { manager.setInputText($0) }
            ))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .frame(minHeight: 140)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Button {
                        manager.pasteURLs()
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .contextMenu {
                        Button {
                            manager.pasteAndDownloadURLs()
                        } label: {
                            Label("Paste and Add", systemImage: "text.badge.plus")
                        }
                    }

                    Button {
                        manager.addURLs()
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .contextMenu {
                        Button {
                            manager.addMP3AudioURLs()
                        } label: {
                            Label("Add as MP3 Audio", systemImage: "music.note")
                        }
                    }

                    Button {
                        manager.bookmarkInputURLs()
                    } label: {
                        Image(systemName: "star")
                    }
                    .help("Bookmark entered URLs")
                }

                HStack(spacing: 8) {
                    Button {
                        manager.addLocalFilesAndFolders()
                    } label: {
                        Image(systemName: "folder.badge.plus")
                    }
                    .help("Add local files or folders")

                    Button {
                        manager.importURLList()
                    } label: {
                        Image(systemName: "square.and.arrow.down")
                    }
                    .help("Import URL list")

                    Button {
                        manager.exportQueueURLs()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .disabled(manager.jobs.isEmpty || (manager.filteredJobs.isEmpty && manager.selectedJobIDs.isEmpty))
                    .help("Export selected, filtered, or all queued URLs")

                    Button {
                        manager.importQueueJobs()
                    } label: {
                        Image(systemName: "tray.and.arrow.down")
                    }
                    .help("Import native JSON or original HDT tasks")

                    Button {
                        manager.exportQueueJobs()
                    } label: {
                        Image(systemName: "tray.and.arrow.up")
                    }
                    .disabled(
                        (manager.jobs.isEmpty && manager.queueGroups.isEmpty) ||
                        (!manager.queueFilter.trimmed.isEmpty &&
                            manager.filteredJobs.isEmpty &&
                            manager.selectedJobIDs.isEmpty)
                    )
                    .help("Export selected, filtered, or all jobs as original HDT or native JSON")
                }
            }

            Toggle("Skip duplicates", isOn: $manager.skipDuplicates)
                .toggleStyle(.checkbox)

            Toggle("Low Power Mode", isOn: Binding(
                get: { manager.lowPowerMode },
                set: { manager.setLowPowerMode($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Reduce expensive previews and visual work on slower Macs")

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Picker("Appearance", selection: Binding(
                        get: { manager.appAppearanceMode },
                        set: { manager.setAppAppearanceMode($0) }
                    )) {
                        ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 260)
                    .help("Use system appearance or force light/dark mode")

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Picker("Scale", selection: Binding(
                        get: { manager.uiScale },
                        set: { manager.setUIScale($0) }
                    )) {
                        ForEach(AppUIScale.allCases, id: \.self) { scale in
                            Text(scale.label).tag(scale)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 320)
                    .help("Adjust the native UI scale")

                    Spacer(minLength: 0)
                }

                HStack(spacing: 8) {
                    Button {
                        manager.beginEditingStatusColors()
                    } label: {
                        Label("Status Colors", systemImage: "paintpalette")
                    }
                    .help("Customize queue status colors")

                    Text(statusColorSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
            }

            Toggle("Auto Remove Finished", isOn: Binding(
                get: { manager.autoRemoveFinishedJobs },
                set: { manager.setAutoRemoveFinishedJobs($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Remove finished jobs from the queue after recording them in history")

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    TextField("auto-remove hook {url} {output}", text: $manager.autoRemoveHookCommand)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        manager.saveAutoRemoveHookCommand()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save auto-remove hook")
                }

                Text(manager.autoRemoveHookStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Toggle("Show Download Date", isOn: Binding(
                get: { manager.showDownloadDate },
                set: { manager.setShowDownloadDate($0) }
            ))
            .toggleStyle(.checkbox)

            Toggle("Number Playlist Files", isOn: Binding(
                get: { manager.numberPlaylistFiles },
                set: { manager.setNumberPlaylistFiles($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Prefix playlist downloads with the playlist index")

            Toggle("Watch Clipboard", isOn: Binding(
                get: { manager.clipboardMonitorEnabled },
                set: { manager.setClipboardMonitorEnabled($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Automatically add URLs copied by other applications. Off by default.")

            Toggle("Start downloads when pasted", isOn: Binding(
                get: { manager.startDownloadsOnPaste },
                set: { manager.setStartDownloadsOnPaste($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Command-V in the main window adds clipboard URLs and starts the queue")

            Toggle("Launch at Login", isOn: Binding(
                get: { manager.launchAtLoginEnabled },
                set: { manager.setLaunchAtLoginEnabled($0) }
            ))
            .toggleStyle(.checkbox)

            Toggle("Prevent Sleep", isOn: Binding(
                get: { manager.preventSleepWhileDownloading },
                set: { manager.setPreventSleepWhileDownloading($0) }
            ))
            .toggleStyle(.checkbox)
            .help("Keep macOS awake while the queue is running")

            settingsSectionAnchor(.alerts)
            VStack(alignment: .leading, spacing: 6) {
                Text("Alerts")
                    .font(.headline)

                Toggle("Notify finished jobs", isOn: Binding(
                    get: { manager.notifyWhenJobCompletes },
                    set: { manager.setNotifyWhenJobCompletes($0) }
                ))
                .toggleStyle(.checkbox)

                Toggle("Notify queue complete", isOn: Binding(
                    get: { manager.notifyWhenQueueCompletes },
                    set: { manager.setNotifyWhenQueueCompletes($0) }
                ))
                .toggleStyle(.checkbox)

                Toggle("Sound on finished jobs", isOn: Binding(
                    get: { manager.playSoundWhenJobCompletes },
                    set: { manager.setPlaySoundWhenJobCompletes($0) }
                ))
                .toggleStyle(.checkbox)

                Toggle("Sound on clipboard add", isOn: Binding(
                    get: { manager.playSoundOnClipboardAdd },
                    set: { manager.setPlaySoundOnClipboardAdd($0) }
                ))
                .toggleStyle(.checkbox)

                Picker("After queue complete", selection: Binding(
                    get: { manager.queueCompletionAction },
                    set: { manager.setQueueCompletionAction($0) }
                )) {
                    ForEach(QueueCompletionAction.allCases, id: \.self) { action in
                        Text(action.label).tag(action)
                    }
                }

                Text(AppLocalization.statusText(
                    manager.queueCompletionActionStatus,
                    language: manager.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !manager.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    manager.addSummary,
                    language: manager.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if !manager.storageWarningText.isEmpty {
                Text(manager.storageWarningText)
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(3)
            }

            Divider()

            settingsSectionAnchor(.saveTo)
            Text("Save To")
                .font(.headline)

            HStack(spacing: 8) {
                Text(manager.destinationPath)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    manager.chooseDestination()
                } label: {
                    Image(systemName: "folder")
                }
                .help("Choose download folder")
            }

            HStack(spacing: 8) {
                Text("Group")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { manager.outputSubfolderMode },
                    set: { manager.setOutputSubfolderMode($0) }
                )) {
                    ForEach(OutputSubfolderMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
            }

            HStack(spacing: 8) {
                Text("Images")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { manager.imageConversionFormat },
                    set: { manager.setImageConversionFormat($0) }
                )) {
                    ForEach(ImageConversionFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 160)
                .help("Convert downloaded image files")
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    TextField("folder {title}", text: $manager.folderNameTemplate)
                        .textFieldStyle(.roundedBorder)
                        .help(nameTokenHelp(NameTemplate.folderTokenSuggestions))
                    tokenMenu(NameTemplate.folderTokenSuggestions) { token in
                        manager.insertFolderNameToken(token)
                    }
                    Button {
                        manager.saveNameTemplates()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save name formats")
                }

                tokenAutocompleteRow(manager.folderNameTemplateAutocompleteSuggestions) { token in
                    manager.completeFolderNameToken(token)
                }

                HStack(spacing: 6) {
                    TextField("file {index:04}-{basename}", text: $manager.fileNameTemplate)
                        .textFieldStyle(.roundedBorder)
                        .help(nameTokenHelp(NameTemplate.fileTokenSuggestions))
                    tokenMenu(NameTemplate.fileTokenSuggestions) { token in
                        manager.insertFileNameToken(token)
                    }
                }

                tokenAutocompleteRow(manager.fileNameTemplateAutocompleteSuggestions) { token in
                    manager.completeFileNameToken(token)
                }

                HStack(spacing: 6) {
                    TextField("recording {date}-{title}", text: $manager.recordingFileNameTemplate)
                        .textFieldStyle(.roundedBorder)
                        .help(nameTokenHelp(NameTemplate.fileTokenSuggestions))
                    tokenMenu(NameTemplate.fileTokenSuggestions) { token in
                        manager.insertRecordingFileNameToken(token)
                    }
                }

                tokenAutocompleteRow(manager.recordingFileNameTemplateAutocompleteSuggestions) { token in
                    manager.completeRecordingFileNameToken(token)
                }
            }

            Divider()

            settingsSectionAnchor(.tools)
            HStack {
                Text("Tools")
                    .font(.headline)
                Spacer()
                if !manager.duplicateImageGroups.isEmpty {
                    Text("\(manager.duplicateImageGroups.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            HStack(spacing: 8) {
                Button {
                    manager.scanDuplicateImages()
                } label: {
                    Label("Duplicate Images", systemImage: "photo.on.rectangle")
                }
                .disabled(manager.isScanningDuplicateImages)

                Button {
                    manager.addDuplicateImageFolder()
                } label: {
                    Image(systemName: "folder.badge.plus")
                }
                .disabled(manager.isScanningDuplicateImages)
                .help("Add duplicate scan folder")

                duplicateImageFolderMenu

                Button {
                    manager.copyGalleryNumbersInSaveFolder()
                } label: {
                    Label("Copy Gallery IDs", systemImage: "number.square")
                }
                .disabled(manager.isCopyingGalleryNumbers)
                .help("Copy Hitomi gallery numbers from the save folder")
            }

            HStack(spacing: 8) {
                Button {
                    manager.clearDuplicateImageResults()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(manager.duplicateImageGroups.isEmpty && manager.duplicateImageSummary.isEmpty)
                .help("Clear duplicate image results")

                Toggle("Thumbnails", isOn: Binding(
                    get: { manager.showDuplicateImageThumbnails },
                    set: { manager.setDuplicateImageThumbnails($0) }
                ))
                .toggleStyle(.checkbox)
                .disabled(manager.lowPowerMode)
                .help(manager.lowPowerMode ? "Low Power Mode hides duplicate image thumbnails" : "Show duplicate image thumbnails")

                Toggle("Exclude Same Source", isOn: Binding(
                    get: { manager.duplicateImageExcludeSameSource },
                    set: { manager.setDuplicateImageExcludeSameSource($0) }
                ))
                .toggleStyle(.checkbox)
                .help("Only show duplicate matches across different output folders")

                Stepper(value: Binding(
                    get: { manager.duplicateImageSimilarityPercent },
                    set: { manager.setDuplicateImageSimilarityPercent($0) }
                ), in: 80...100) {
                    Text("Similarity \(manager.duplicateImageSimilarityPercent)%")
                        .monospacedDigit()
                }
                .frame(width: 150)
                .help("Lower values include visually similar images.")
            }

            if !manager.duplicateImageSummary.isEmpty {
                Text(manager.duplicateImageSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if !manager.duplicateImageGroups.isEmpty {
                List {
                    ForEach(Array(manager.duplicateImageGroups.prefix(20))) { group in
                        DuplicateImageGroupRow(
                            group: group,
                            showsThumbnails: manager.effectiveDuplicateImageThumbnails,
                            selectedPath: manager.selectedDuplicateImagePath,
                            autoSelectedPath: manager.autoSelectedDuplicateImagePath,
                            select: { path in
                                manager.selectDuplicateImage(path)
                            },
                            reveal: { path in
                                manager.revealDuplicateImage(path)
                            },
                            openFolder: { path in
                                manager.openDuplicateImageFolder(path)
                            }
                        )
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 120)
            }

            Divider()

            settingsSectionAnchor(.network)
            Text("Network")
                .font(.headline)

            Toggle("Proxy", isOn: $manager.proxyEnabled)
                .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                TextField("http://127.0.0.1:8080", text: $manager.proxyURLString)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!manager.proxyEnabled)
                Button {
                    manager.saveProxySettings()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save proxy settings")
            }

            TextField("proxy bypass: example.com, *.internal.test", text: $manager.proxyBypassList)
                .textFieldStyle(.roundedBorder)
                .disabled(!manager.proxyEnabled)
                .help("Hosts that should ignore the proxy")

            HStack(spacing: 6) {
                Button {
                    manager.refreshPublicIP()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(manager.isRefreshingPublicIP)
                .help("Check public IP")

                Text(manager.publicIPStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            settingsSectionAnchor(.youtube)
            HStack(spacing: 6) {
                Text("YouTube")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                TextField("language", text: $manager.youtubePreferredLanguage)
                    .textFieldStyle(.roundedBorder)
                Toggle("Thumbnail", isOn: Binding(
                    get: { manager.youtubeDownloadThumbnail },
                    set: { manager.setYouTubeDownloadThumbnail($0) }
                ))
                .toggleStyle(.checkbox)
                Button {
                    manager.saveYouTubePreferredLanguage()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save YouTube language")
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                Toggle("Reverse playlist", isOn: Binding(
                    get: { manager.youtubeReversePlaylist },
                    set: { manager.setYouTubeReversePlaylist($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                Toggle("Use upload date as file modification date", isOn: Binding(
                    get: { manager.youtubeUseUploadDateForFileModificationTime },
                    set: { manager.setYouTubeUseUploadDateForFileModificationTime($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                Toggle("Chapters", isOn: Binding(
                    get: { manager.youtubeEmbedChapters },
                    set: { manager.setYouTubeEmbedChapters($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                Toggle("Enhanced bitrate", isOn: Binding(
                    get: { manager.youtubePreferEnhancedBitrate },
                    set: { manager.setYouTubePreferEnhancedBitrate($0) }
                ))
                .toggleStyle(.checkbox)
                Spacer(minLength: 0)
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                Spacer(minLength: 0)
                YouTubeCodecPriorityMenu(manager: manager)
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                TextField("1080p", text: $manager.youtubePreferredResolution)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.saveYouTubePreferredResolution()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save YouTube resolution")
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                TextField("audio lang", text: $manager.youtubePreferredAudioLanguage)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.saveYouTubePreferredAudioLanguage()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save YouTube audio track")
            }

            HStack(spacing: 6) {
                Text("")
                    .frame(width: 58, alignment: .leading)
                Toggle("Auto subtitles", isOn: Binding(
                    get: { manager.youtubeDownloadAutoSubtitles },
                    set: { manager.setYouTubeDownloadAutoSubtitles($0) }
                ))
                .toggleStyle(.checkbox)
                TextField("all", text: $manager.youtubeSubtitleLanguages)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 74)
                Button {
                    manager.saveYouTubeSubtitleSettings()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save YouTube subtitles")
            }

            settingsSectionAnchor(.soop)
            HStack(spacing: 6) {
                Text("SOOP")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                TextField("720p", text: $manager.soopPreferredResolution)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.saveSOOPPreferredResolution()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save SOOP/Afreeca resolution")
            }

            settingsSectionAnchor(.pixiv)
            HStack(spacing: 6) {
                Text("Pixiv")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Picker("", selection: $manager.pixivUgoiraFileFormat) {
                    ForEach(PixivUgoiraFileFormat.allCases, id: \.self) { format in
                        Text(format.label).tag(format)
                    }
                }
                .labelsHidden()
                Toggle("Dither", isOn: $manager.pixivUgoiraDither)
                    .toggleStyle(.checkbox)
                    .disabled(manager.pixivUgoiraFileFormat != .gif)
                Stepper("\(manager.pixivUgoiraQuality)", value: $manager.pixivUgoiraQuality, in: 1...100)
                    .frame(width: 78)
                    .disabled(!manager.pixivUgoiraFileFormat.requiresFFmpeg)
                Button {
                    manager.savePixivUgoiraFileFormat()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save Pixiv ugoira format")
            }

            settingsSectionAnchor(.hls)
            HStack(spacing: 6) {
                Text("HLS")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 58, alignment: .leading)
                Toggle("MP4 remux", isOn: $manager.remuxM3U8ToMP4)
                    .toggleStyle(.checkbox)
                Toggle("Skip Bad", isOn: $manager.hlsContinueOnSegmentFailure)
                    .toggleStyle(.checkbox)
                    .help("Continue HLS downloads when an individual media segment fails")
                TextField("delay ms", text: $manager.m3u8SegmentDelayMillisecondsString)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 76)
                    .help("Delay between HLS segment requests in milliseconds")
                Spacer(minLength: 0)
                Button {
                    manager.saveM3U8RemuxSetting()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save HLS settings")
            }

            settingsSectionAnchor(.record)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Record")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Toggle("Auto", isOn: Binding(
                        get: { manager.autoRecordEnabled },
                        set: { manager.setAutoRecordEnabled($0) }
                    ))
                    .toggleStyle(.checkbox)
                    Toggle("Pause", isOn: Binding(
                        get: { manager.autoRecordPaused },
                        set: { manager.setAutoRecordPaused($0) }
                    ))
                    .toggleStyle(.checkbox)
                    .disabled(!manager.autoRecordEnabled)
                    TextField("min", text: $manager.autoRecordIntervalMinutesString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 48)
                        .help("Refresh interval; accepts minutes, 90s, 1:30, or 2h")
                    Button {
                        manager.checkAutoRecordNow()
                    } label: {
                        Image(systemName: manager.isAutoRecordChecking ? "hourglass" : "arrow.clockwise")
                    }
                    .disabled(manager.isAutoRecordChecking || manager.autoRecordPaused)
                    .help("Check auto record sources")
                    Button {
                        manager.saveAutoRecordSettings()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save auto record settings")
                }

                TextEditor(text: $manager.autoRecordURLsText)
                    .font(.caption)
                    .frame(minHeight: 48, maxHeight: 72)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(.separator, lineWidth: 1)
                    )
                    .help("One live or recording URL per line")

                Text(AppLocalization.statusText(
                    manager.autoRecordStatus,
                    language: manager.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            settingsSectionAnchor(.externalTools)
            VStack(spacing: 6) {
                TextField("yt-dlp path", text: $manager.ytdlpPath)
                    .textFieldStyle(.roundedBorder)
                    .help("Accepts absolute, ~/..., file://, or quoted paths")
                TextField("ffmpeg path", text: $manager.ffmpegPath)
                    .textFieldStyle(.roundedBorder)
                    .help("Accepts absolute, ~/..., file://, or quoted paths")
                HStack(spacing: 6) {
                    TextField("aria2c path", text: $manager.aria2Path)
                        .textFieldStyle(.roundedBorder)
                        .help("Accepts absolute, ~/..., file://, or quoted paths")
                    Button {
                        manager.saveExternalToolPaths()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save external tool paths")
                }
            }

            settingsSectionAnchor(.ffmpeg)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("ffmpeg")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    Toggle("Transcode", isOn: $manager.ffmpegTranscodeEnabled)
                        .toggleStyle(.checkbox)
                    Spacer(minLength: 0)
                    Button {
                        manager.saveFFmpegTranscodeOptions()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save ffmpeg transcode options")
                }

                HStack(spacing: 6) {
                    TextField("video codec", text: $manager.ffmpegVideoCodec)
                        .textFieldStyle(.roundedBorder)
                    TextField("audio codec", text: $manager.ffmpegAudioCodec)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!manager.ffmpegTranscodeEnabled)

                HStack(spacing: 6) {
                    TextField("video bitrate", text: $manager.ffmpegVideoBitrate)
                        .textFieldStyle(.roundedBorder)
                    TextField("audio bitrate", text: $manager.ffmpegAudioBitrate)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!manager.ffmpegTranscodeEnabled)

                HStack(spacing: 6) {
                    TextField("CRF", text: $manager.ffmpegCRF)
                        .textFieldStyle(.roundedBorder)
                    TextField("preset", text: $manager.ffmpegPreset)
                        .textFieldStyle(.roundedBorder)
                }
                .disabled(!manager.ffmpegTranscodeEnabled)
            }

            settingsSectionAnchor(.aria2)
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("aria2")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    TextField("files 1,3-5", text: $manager.aria2SelectedFiles)
                        .textFieldStyle(.roundedBorder)
                    TextField("seed min", text: $manager.aria2SeedTimeMinutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Button {
                        manager.previewAria2Files()
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                    .help("List torrent files")
                    Button {
                        manager.saveAria2Options()
                    } label: {
                        Image(systemName: "checkmark")
                    }
                    .help("Save aria2 options")
                }

                HStack(spacing: 6) {
                    Text("limit")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    TextField("down 2M", text: $manager.aria2MaxDownloadLimit)
                        .textFieldStyle(.roundedBorder)
                    TextField("up 512K", text: $manager.aria2MaxUploadLimit)
                        .textFieldStyle(.roundedBorder)
                    TextField("ratio", text: $manager.aria2SeedRatio)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 72)
                    Toggle("anon", isOn: $manager.aria2AnonymousMode)
                        .toggleStyle(.checkbox)
                }

                HStack(spacing: 6) {
                    Text("tracker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .leading)
                    TextField("udp://tracker.example/announce", text: $manager.aria2Trackers)
                        .textFieldStyle(.roundedBorder)
                }

                if !manager.aria2FileListSummary.isEmpty {
                    Text(manager.aria2FileListSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Button {
                            manager.useSelectedAria2PreviewFiles()
                        } label: {
                            Image(systemName: "checkmark.circle")
                        }
                        .help("Use selected torrent files")

                        Button {
                            manager.useAllAria2PreviewFiles()
                        } label: {
                            Image(systemName: "checkmark.square")
                        }
                        .help("Use all listed torrent files")

                        Button {
                            manager.clearAria2FileSelection()
                        } label: {
                            Image(systemName: "xmark.circle")
                        }
                        .help("Clear torrent file selection")

                        Spacer()
                    }
                }

                if !manager.aria2PeerSummary.isEmpty {
                    Text(manager.aria2PeerSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    ForEach(Array(manager.aria2PeerEntries.prefix(6))) { peer in
                        Text(peer.summary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            settingsSectionAnchor(.httpAPI)
            Toggle("HTTP API", isOn: Binding(
                get: { manager.httpAPIEnabled },
                set: { manager.setHTTPAPIEnabled($0) }
            ))
            .toggleStyle(.checkbox)

            Toggle("Lazy-load HTTP viewer images", isOn: Binding(
                get: { manager.httpViewerLazyLoading },
                set: { manager.setHTTPViewerLazyLoading($0) }
            ))
            .toggleStyle(.checkbox)

            HStack(spacing: 6) {
                TextField("8110", text: $manager.httpAPIPortString)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 78)
                    .disabled(!manager.httpAPIEnabled)
                SecureField("password", text: $manager.httpAPIPassword)
                    .textFieldStyle(.roundedBorder)
                    .disabled(!manager.httpAPIEnabled)
                Button {
                    manager.saveHTTPAPISettings()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save HTTP API")
            }

            Text(manager.httpAPIStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Divider()

            settingsSectionAnchor(.search)
            HStack {
                Text("Search")
                    .font(.headline)
                Spacer()
                Text("\(manager.searchProviders.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Menu {
                    Button {
                        manager.importSearchProviders()
                    } label: {
                        Label("Import Providers", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        manager.exportSearchProviders()
                    } label: {
                        Label("Export Providers", systemImage: "square.and.arrow.up")
                    }
                    .disabled(manager.searchProviders.isEmpty)
                    Divider()
                    Button {
                        manager.importSearchBookmarks()
                    } label: {
                        Label("Import Saved Searches", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        manager.exportSearchBookmarks()
                    } label: {
                        Label("Export Saved Searches", systemImage: "square.and.arrow.up")
                    }
                    .disabled(manager.searchBookmarks.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .help("Search import and export")
            }

            HStack(spacing: 6) {
                Picker("", selection: $manager.selectedSearchProviderID) {
                    ForEach(manager.searchProviders) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                .disabled(manager.searchProviders.isEmpty)

                TextField("Query", text: $manager.searchQuery)
                    .textFieldStyle(.roundedBorder)

                Button {
                    manager.openSearchURL()
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open search URL")

                Button {
                    manager.enqueueSearchURL()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add search URL to queue")

                Button {
                    manager.saveCurrentSearchBookmark()
                } label: {
                    Image(systemName: "bookmark")
                }
                .disabled(manager.searchQuery.trimmed.isEmpty || manager.searchProviders.isEmpty)
                .help("Save search bookmark")

                Button {
                    manager.fetchSearchResults()
                } label: {
                    Image(systemName: "list.bullet.rectangle")
                }
                .disabled(manager.isSearching)
                .help("Fetch links from search results")
            }

            HStack(spacing: 10) {
                Toggle("Dedup", isOn: Binding(
                    get: { manager.searchDeduplicateResults },
                    set: { manager.setSearchDeduplicateResults($0) }
                ))
                .toggleStyle(.checkbox)
                .help("Remove duplicate search result URLs.")

                Toggle("Hide Done", isOn: Binding(
                    get: { manager.searchHideKnownResults },
                    set: { manager.setSearchHideKnownResults($0) }
                ))
                .toggleStyle(.checkbox)
                .help("Hide results already in the queue or history.")
            }

            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Hitomi excluded tags", text: $manager.hitomiExcludedTagsText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.saveHitomiExcludedTags()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save Hitomi excluded tags")
                Button {
                    manager.clearHitomiExcludedTags()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(manager.hitomiExcludedTagsText.trimmed.isEmpty)
                .help("Clear Hitomi excluded tags")
            }

            HStack(spacing: 6) {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Translate tag", text: $manager.searchTagTranslationInput)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.translateSearchTagInput()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Translate search tag")
                Button {
                    manager.insertTranslatedSearchTag()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Insert translated tag")
                Button {
                    manager.replaceSearchQueryWithTranslatedTag()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Replace query with translated tag")
                Button {
                    manager.clearSearchTagTranslation()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(manager.searchTagTranslationInput.trimmed.isEmpty && manager.searchTagTranslationOutput.trimmed.isEmpty)
                .help("Clear tag translation")
            }

            if !manager.searchTagTranslationOutput.trimmed.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    Text(manager.searchTagTranslationOutput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                }
            }

            if !manager.searchTagAutocompleteSuggestions.isEmpty {
                VStack(spacing: 3) {
                    ForEach(manager.searchTagAutocompleteSuggestions.prefix(5)) { suggestion in
                        HStack(spacing: 6) {
                            Image(systemName: "text.badge.checkmark")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(suggestion.title)
                                    .font(.caption)
                                    .lineLimit(1)
                                Text(suggestion.token)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                manager.applySearchTagSuggestion(suggestion)
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Use suggestion")
                            Button {
                                manager.insertSearchTagSuggestion(suggestion)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Insert suggestion")
                        }
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Provider", text: $manager.newSearchProviderName)
                    .textFieldStyle(.roundedBorder)
                TextField("https://site/search?q={query}", text: $manager.newSearchProviderTemplate)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.addSearchProvider()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Save search provider")
                Button {
                    manager.resetSearchProviders()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset search providers")
            }

            if !manager.searchProviders.isEmpty {
                List {
                    ForEach(Array(manager.searchProviders.enumerated()), id: \.element.id) { index, provider in
                        SearchProviderRow(
                            provider: provider,
                            canMoveUp: index > 0,
                            canMoveDown: index < manager.searchProviders.count - 1,
                            moveUp: {
                                manager.moveSearchProvider(provider, by: -1)
                            },
                            moveDown: {
                                manager.moveSearchProvider(provider, by: 1)
                            },
                            remove: {
                                manager.removeSearchProvider(provider)
                            }
                        )
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 84)
            }

            if !manager.searchBookmarks.isEmpty {
                HStack {
                    Text("Saved Searches")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text("\(manager.searchBookmarks.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }

                List {
                    ForEach(manager.searchBookmarks) { bookmark in
                        SearchBookmarkRow(
                            bookmark: bookmark,
                            apply: {
                                manager.applySearchBookmark(bookmark)
                            },
                            enqueue: {
                                manager.enqueueSearchBookmark(bookmark)
                            },
                            remove: {
                                manager.removeSearchBookmark(bookmark)
                            }
                        )
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 84)
            }

            if !manager.searchResults.isEmpty {
                let visibleSearchResults = manager.filteredSearchResults
                let knownState = manager.searchResultKnownState

                HStack(spacing: 6) {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    TextField("Filter results", text: $manager.searchResultFilter)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        manager.searchResultFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .disabled(manager.searchResultFilter.trimmed.isEmpty)
                    .help("Clear result filter")
                    Picker("", selection: Binding(
                        get: { manager.searchResultKnownFilter },
                        set: { manager.setSearchResultKnownFilter($0) }
                    )) {
                        ForEach(SearchResultKnownFilter.allCases, id: \.self) { filter in
                            Text(filter.label).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 105)
                    .help("Downloaded result filter")
                    Picker("", selection: Binding(
                        get: { manager.searchResultSortMode },
                        set: { manager.setSearchResultSortMode($0) }
                    )) {
                        ForEach(SearchResultSortMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 110)
                    .help("Sort results")
                    Button {
                        manager.setSearchResultSortDescending(!manager.searchResultSortDescending)
                    } label: {
                        Image(systemName: manager.searchResultSortDescending ? "arrow.down" : "arrow.up")
                    }
                    .help(manager.searchResultSortDescending ? "Descending order" : "Ascending order")
                }

                HStack {
                    Text("Results")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    Text((manager.searchResultFilter.trimmed.isEmpty && manager.searchResultKnownFilter == .all) ? "\(manager.searchResults.count)" : "\(visibleSearchResults.count)/\(manager.searchResults.count)")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Button {
                        manager.enqueueAllSearchResults()
                    } label: {
                        Image(systemName: "plus.square.on.square")
                    }
                    .disabled(visibleSearchResults.isEmpty)
                    .help("Add all search results to queue")
                }

                List {
                    ForEach(visibleSearchResults) { result in
                        SearchResultRow(
                            result: result,
                            galleryID: DownloadManager.searchResultGalleryID(for: result),
                            metadataCopies: DownloadManager.searchResultMetadataCopies(for: result),
                            dateText: DownloadManager.searchResultDateText(for: result),
                            pageCountText: DownloadManager.searchResultPageCountText(for: result),
                            isDone: DownloadManager.searchResultIsKnown(result, knownState: knownState),
                            canOpenFirstOutput: DownloadManager.searchResultFirstOutputOpenURL(for: result, knownState: knownState) != nil,
                            enqueue: {
                                manager.enqueueSearchResult(result)
                            },
                            openSource: {
                                manager.openSearchResult(result)
                            },
                            copyURL: {
                                manager.copySearchResultURL(result)
                            },
                            copyTitle: {
                                manager.copySearchResultTitle(result)
                            },
                            copyMetadata: {
                                manager.copySearchResultMetadata($0)
                            },
                            openFirstOutput: {
                                manager.openFirstOutputFile(forSearchResult: result)
                            },
                            copyGalleryID: {
                                manager.copySearchResultGalleryID(result)
                            }
                        )
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 110)
            }

            Divider()

            settingsSectionAnchor(.bookmarks)
            HStack {
                Text("Bookmarks")
                    .font(.headline)
                Spacer()
                Text(bookmarkCountText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    manager.sortBookmarksByTitle()
                } label: {
                    Image(systemName: "textformat.abc")
                }
                .buttonStyle(.borderless)
                .disabled(manager.bookmarks.count < 2)
                .help("Sort bookmarks by name")

                Button {
                    requestClearBookmarks()
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .disabled(manager.bookmarks.isEmpty)
                .help("Clear bookmarks")

                Button {
                    manager.importBookmarks()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Import bookmarks")

                Button {
                    manager.exportBookmarks()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .disabled(manager.filteredBookmarks.isEmpty)
                .help("Export bookmarks")
            }

            if manager.bookmarks.isEmpty {
                Text("No bookmarks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                        .frame(width: 18)
                    TextField("Filter bookmarks", text: $manager.bookmarkFilter)
                        .textFieldStyle(.roundedBorder)
                    if !manager.bookmarkFilter.trimmed.isEmpty {
                        Button {
                            manager.bookmarkFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help("Clear bookmark filter")
                    }
                }

                if manager.filteredBookmarks.isEmpty {
                    Text("No matching bookmarks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                List {
                    ForEach(manager.filteredBookmarks) { bookmark in
                        BookmarkRow(bookmark: bookmark) {
                            manager.enqueueBookmark(bookmark)
                        } edit: {
                            manager.beginEditingBookmark(bookmark)
                        } remove: {
                            manager.removeBookmark(bookmark)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 100)
            }

            Divider()

            settingsSectionAnchor(.history)
            HStack {
                Text("History")
                    .font(.headline)
                Spacer()
                Text("\(manager.history.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            HStack(spacing: 8) {
                Toggle("Keep History", isOn: Binding(
                    get: { manager.historyEnabled },
                    set: { manager.setHistoryEnabled($0) }
                ))
                .toggleStyle(.checkbox)

                TextField("1000", text: $manager.historyLimitString)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 64)

                Button {
                    manager.saveHistorySettings()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save history settings")
            }

            if manager.history.isEmpty {
                Text("No history")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(manager.history.prefix(50)) { entry in
                        HistoryRow(entry: entry) {
                            manager.enqueueHistoryEntry(entry)
                        } reveal: {
                            manager.revealHistoryOutput(entry)
                        } remove: {
                            manager.removeHistoryEntry(entry)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 110)
            }

            Button {
                manager.clearHistory()
            } label: {
                Label("Clear History", systemImage: "clock.arrow.circlepath")
            }
            .controlSize(.small)

            Divider()

            settingsSectionAnchor(.siteRules)
            HStack {
                Text("Site Rules")
                    .font(.headline)
                Spacer()
                Text("\(manager.siteRules.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button {
                    manager.importSiteRules()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.borderless)
                .help("Import site rules")
                Button {
                    manager.exportSiteRules()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.borderless)
                .help("Export site rules")
            }

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    TextField("Name", text: $manager.newSiteRuleName)
                        .textFieldStyle(.roundedBorder)
                    TextField("host.com", text: $manager.newSiteRuleHost)
                        .textFieldStyle(.roundedBorder)
                    Button {
                        manager.addSiteRule()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .help("Save site rule")
                }

                TextField("/path/* or /view?id=*", text: $manager.newSiteRuleURLPattern)
                    .textFieldStyle(.roundedBorder)
                    .help("Optional path/query wildcard pattern for this host.")

                TextField("command {url} {output}", text: $manager.newSiteRuleCommand)
                    .textFieldStyle(.roundedBorder)
                    .help("Leave empty for yt-dlp, or for a headers-only rule when headers are filled. Supports {url}, {output}, {host}, {path}, {query}, {referer}, and {userAgent}.")

                HStack(spacing: 6) {
                    TextField("referer {url}", text: $manager.newSiteRuleReferer)
                        .textFieldStyle(.roundedBorder)
                        .help("Optional Referer header. Supports {url}, {host}, {origin}, {scheme}, {path}, and {query}.")
                    TextField("user agent", text: $manager.newSiteRuleUserAgent)
                        .textFieldStyle(.roundedBorder)
                        .help("Optional User-Agent header for this host.")
                }

                HStack(spacing: 6) {
                    Picker("Archive", selection: $manager.newSiteRuleArchiveMode) {
                        ForEach(SiteArchiveMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 120)
                    .help("Override the global archive setting for this host.")

                    Toggle("Delete folder after archive", isOn: $manager.newSiteRuleDeleteOriginalAfterArchiving)
                        .toggleStyle(.checkbox)
                        .disabled(!manager.newSiteRuleArchiveMode.archives)
                }
            }

            if manager.siteRules.isEmpty {
                Text("No site rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                List {
                    ForEach(manager.siteRules) { rule in
                        SiteRuleRow(rule: rule) { enabled in
                            manager.setSiteRuleEnabled(rule, enabled: enabled)
                        } remove: {
                            manager.removeSiteRule(rule)
                        }
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 84)
            }
        }
        .padding(14)
        }
        }
    }

    private var settingsSearchResults: [SettingsSearchResult] {
        SettingsSearchIndex.matches(for: manager.settingsSearchText, limit: 8)
    }

    private var hasSettingsSearchQuery: Bool {
        SettingsSearchIndex.hasQuery(manager.settingsSearchText)
    }

    private func settingsSearchBox(proxy: ScrollViewProxy) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Search settings", text: $manager.settingsSearchText)
                    .textFieldStyle(.roundedBorder)
                if hasSettingsSearchQuery {
                    Button {
                        manager.settingsSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear settings search")
                }
            }

            if hasSettingsSearchQuery {
                if settingsSearchResults.isEmpty {
                    Text("No settings found")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    VStack(spacing: 4) {
                        ForEach(settingsSearchResults) { result in
                            Button {
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    proxy.scrollTo(result.section.rawValue, anchor: .top)
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(result.title)
                                            .font(.caption)
                                            .fontWeight(.semibold)
                                            .lineLimit(1)
                                        Text(result.detail)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.tail)
                                    }
                                    Spacer(minLength: 8)
                                    Image(systemName: "arrow.down.forward")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 6)
                                .background(Color(nsColor: .controlBackgroundColor))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func settingsSectionAnchor(_ section: SettingsSectionID) -> some View {
        Color.clear
            .frame(height: 1)
            .id(section.rawValue)
            .accessibilityHidden(true)
    }

    private var bookmarkCountText: String {
        guard !manager.bookmarkFilter.trimmed.isEmpty else {
            return "\(manager.bookmarks.count)"
        }
        return "\(manager.filteredBookmarks.count) / \(manager.bookmarks.count)"
    }

    private var selectedQueueJobs: [DownloadJob] {
        let ids = manager.selectedJobIDs
        guard !ids.isEmpty else { return [] }
        return manager.jobs.filter { ids.contains($0.id) }
    }

    private var selectedQueueOutputSummary: String {
        DownloadManager.outputSummaryText(for: selectedQueueJobs)
    }

    private var queueScrollSnapshot: QueueSelectionScrollSnapshot {
        QueueSelectionScroll.snapshot(
            selectedIDs: manager.selectedJobIDs,
            visibleJobs: manager.filteredJobs,
            layoutSignature: [
                "downloadDate=\(manager.showDownloadDate)",
                "view=\(manager.queueViewMode.rawValue)",
                "thumbsHidden=\(manager.queueThumbnailsHidden)",
                "thumbScale=\(manager.queueThumbnailScale.rawValue)"
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

        for entry in manager.queueListEntries {
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
            if manager.showingQueueControls ||
                !manager.queueFilter.trimmed.isEmpty {
                compactQueueControls
                Divider()
            }

            if manager.jobs.isEmpty && manager.queueGroups.isEmpty {
                emptyState
            } else if manager.queueListEntries.isEmpty {
                noMatchesState
            } else if manager.queueViewMode == .icon {
                iconQueueContent
            } else {
                ScrollViewReader { proxy in
                    List(selection: Binding(
                        get: { manager.selectedJobIDs },
                        set: { manager.setSelectedJobIDs($0) }
                    )) {
                        ForEach(Array(manager.queueListEntries.enumerated()), id: \.element.id) { index, entry in
                            switch entry {
                            case .group(let group):
                                QueueGroupRow(
                                    group: group,
                                    jobs: manager.jobs(in: group),
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
                                        manager.taskTagDisplayName(tag)
                                    },
                                    openTagSettings: {
                                        manager.openSettingsWindow(category: .theme)
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
                                JobRow(
                                job: job,
                                isSelected: manager.selectedJobIDs.contains(job.id),
                                queueIsPaused: !manager.isQueueEnabled,
                                showsDownloadDate: manager.showDownloadDate,
                                statusColorPalette: manager.jobStatusColorPalette,
                                groupOptions: manager.queueGroupOptions,
                                currentGroupID: manager.jobGroupID(for: job),
                                destinationPath: manager.destinationPath,
                                viewMode: .list,
                                showsThumbnail: !manager.queueThumbnailsHidden,
                                thumbnailScale: manager.queueThumbnailScale,
                                hideArchiveIndicatorWhenFileMissing: manager.hideArchiveIndicatorWhenFileMissing
                            ) {
                                manager.revealOutputs(startingAt: job)
                            } openFirstOutput: {
                                manager.openFirstOutputFile(for: job)
                            } openArchive: {
                                manager.openArchiveOutput(for: job)
                            } openFirstSelectedOutputs: {
                                manager.openFirstOutputFiles(startingAt: job)
                            } viewOutputInBrowser: {
                                manager.openOutputBrowserView(startingAt: job)
                            } previewOutput: {
                                manager.openOutputPreview(for: job)
                            } createPDF: {
                                manager.createPDF(for: job)
                            } retry: {
                                manager.retryJobs(startingAt: job)
                            } directDownload: {
                                manager.directDownloadJobs(startingAt: job)
                            } stopLiveRecording: {
                                manager.stopLiveRecording(for: job)
                            } pauseAria2: {
                                manager.pauseAria2(for: job)
                            } resumeAria2: {
                                manager.resumeAria2(for: job)
                            } applyAria2Limits: {
                                manager.applyCurrentAria2RuntimeLimits(for: job)
                            } applyAria2Files: {
                                manager.applyCurrentAria2RuntimeFileSelection(for: job)
                            } applyAria2Seeding: {
                                manager.applyCurrentAria2RuntimeSeeding(for: job)
                            } previewAria2Files: {
                                manager.previewAria2Files(for: job)
                            } refreshAria2Peers: {
                                manager.refreshAria2Peers(for: job)
                            } markFinished: {
                                manager.markJobsFinished(startingAt: job)
                            } moveUp: {
                                manager.moveJobUp(job)
                            } moveDown: {
                                manager.moveJobDown(job)
                            } moveOutput: {
                                manager.beginMovingOutputs(startingAt: job)
                            } deleteJobAndOutput: {
                                manager.beginDeletingOutputs(startingAt: job)
                            } deleteOutput: {
                                manager.beginDeletingOutput(for: job)
                            } remove: {
                                requestRemoveJob(job)
                            } copySource: {
                                manager.copySource(for: job)
                            } copyArtist: {
                                manager.copyArtistName(for: job)
                            } openSource: {
                                manager.openSource(for: job)
                            } openAccessHelp: {
                                manager.openAccessHelp(for: job)
                            } info: {
                                manager.infoJob = job
                            } selectForContextMenu: {
                                if !manager.selectedJobIDs.contains(job.id) {
                                    manager.setSelectedJobIDs([job.id])
                                }
                            } edit: {
                                manager.beginEditingJob(job)
                            } pages: {
                                manager.beginPageSelector(for: job)
                            } comment: {
                                manager.beginEditingJobComment(job)
                            } togglePin: {
                                manager.toggleJobPins(startingAt: job)
                            } toggleLock: {
                                manager.toggleJobLocks(startingAt: job)
                            } pinActionWillPin: {
                                manager.jobPinActionWillPin(startingAt: job)
                            } lockActionWillLock: {
                                manager.jobLockActionWillLock(startingAt: job)
                            } canToggleSelectedPins: {
                                manager.canToggleJobPins(startingAt: job)
                            } retryIncomplete: {
                                manager.beginRetryIncompleteJobs()
                            } clearCompleted: {
                                manager.beginRemovingCompletedJobs()
                            } isTagChecked: { tag in
                                manager.isJobTagChecked(tag, for: job)
                            } toggleTag: { tag in
                                manager.toggleJobTag(tag, for: job)
                            } tagName: { tag in
                                manager.taskTagDisplayName(tag)
                            } openTagSettings: {
                                manager.openSettingsWindow(category: .theme)
                            } convertImages: {
                                manager.beginConvertingImages(startingAt: job)
                            } moveToGroup: { groupID in
                                let ids = manager.selectedJobIDs.contains(job.id)
                                    ? manager.selectedJobIDs
                                    : Set([job.id])
                                _ = manager.moveJobs(ids, toQueueGroup: groupID)
                            } moveToNewGroup: {
                                manager.beginMovingJobToNewGroup(job)
                            } beginReorder: {
                                let ids = manager.queueJobIDsForDrag(startingAt: job.id)
                                manager.draggedQueueJobIDs = ids
                                return QueueDropTypes.jobPasteboardItem(for: job.id)
                            } endReorder: {
                                manager.endQueueDrag()
                            } canBeginReorder: {
                                manager.queueSortMode == .manual &&
                                    manager.queueFilter.trimmed.isEmpty &&
                                    manager.jobs.filter { $0.isPinned == job.isPinned }.count > 1
                            } canMoveToGroup: {
                                manager.queueSortMode == .manual &&
                                    !manager.isRunning &&
                                    job.status != .resolving &&
                                    job.status != .downloading
                            } canMoveUp: {
                                manager.canMoveJobUp(job)
                            } canMoveDown: {
                                manager.canMoveJobDown(job)
                            } canPauseAria2: {
                                manager.canPauseAria2(for: job)
                            } canResumeAria2: {
                                manager.canResumeAria2(for: job)
                            } canApplyAria2Limits: {
                                manager.canApplyAria2RuntimeLimits(for: job)
                            } canApplyAria2Files: {
                                manager.canApplyAria2RuntimeFileSelection(for: job)
                            } canApplyAria2Seeding: {
                                manager.canApplyAria2RuntimeSeeding(for: job)
                            } canPreviewAria2Files: {
                                manager.canPreviewAria2Files(for: job)
                            } canRefreshAria2Peers: {
                                manager.canRefreshAria2Peers(for: job)
                            } canMarkFinished: {
                                manager.canMarkJobsFinished(startingAt: job)
                            } canOpenPageSelector: {
                                manager.canOpenPageSelector(for: job)
                            } canDeleteOutput: {
                                manager.canDeleteOutput(for: job)
                            } canOpenFirstOutput: {
                                manager.canOpenFirstOutputFile(for: job)
                            } canOpenFirstSelectedOutputs: {
                                manager.canOpenFirstOutputFiles(startingAt: job)
                            } canViewOutputInBrowser: {
                                manager.canOpenOutputBrowserView(startingAt: job)
                            } canPreviewOutput: {
                                manager.canOpenOutputPreview(for: job)
                            } canCreatePDF: {
                                manager.canCreatePDF(for: job)
                            } canDirectDownload: {
                                manager.canDirectDownloadJobs(startingAt: job)
                            } canStopLiveRecording: {
                                manager.canStopLiveRecording(for: job)
                            } canMoveOutput: {
                                manager.canMoveOutputs(startingAt: job)
                            } canConvertImages: {
                                manager.canConvertJobImages(startingAt: job)
                            } canCopyArtist: {
                                manager.artistName(for: job) != nil
                            } canRetryIncomplete: {
                                manager.retryableIncompleteJobCount > 0
                            } canClearCompleted: {
                                manager.removableCompletedJobCount > 0
                            } canRevealSelectedOutputs: {
                                manager.canRevealOutputs(startingAt: job)
                            } canDeleteSelectedJobsAndOutput: {
                                manager.canDeleteOutputsAndJobs(startingAt: job)
                            } canRemoveSelectedJobs: {
                                manager.canRemoveJobs(startingAt: job)
                            } canRetrySelectedJobs: {
                                manager.canRetryJobs(startingAt: job)
                            }
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
                                    draggedIDs: $manager.draggedQueueJobIDs,
                                    activeTarget: $manager.queueJobDropTarget,
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
        let cellWidth = scaled(88 * CGFloat(manager.queueThumbnailScale.factor))
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
            jobs: manager.jobs(in: group),
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
                manager.taskTagDisplayName(tag)
            },
            openTagSettings: {
                manager.openSettingsWindow(category: .theme)
            },
            removeGroup: {
                manager.beginRemovingQueueGroup(group)
            }
        )
    }

    private func queueJobRow(_ job: DownloadJob, viewMode: QueueViewMode) -> some View {
        JobRow(
            job: job,
            isSelected: manager.selectedJobIDs.contains(job.id),
            queueIsPaused: !manager.isQueueEnabled,
            showsDownloadDate: manager.showDownloadDate,
            statusColorPalette: manager.jobStatusColorPalette,
            groupOptions: manager.queueGroupOptions,
            currentGroupID: manager.jobGroupID(for: job),
            destinationPath: manager.destinationPath,
            viewMode: viewMode,
            showsThumbnail: !manager.queueThumbnailsHidden,
            thumbnailScale: manager.queueThumbnailScale,
            hideArchiveIndicatorWhenFileMissing: manager.hideArchiveIndicatorWhenFileMissing
        ) {
            manager.revealOutputs(startingAt: job)
        } openFirstOutput: {
            manager.openFirstOutputFile(for: job)
        } openArchive: {
            manager.openArchiveOutput(for: job)
        } openFirstSelectedOutputs: {
            manager.openFirstOutputFiles(startingAt: job)
        } viewOutputInBrowser: {
            manager.openOutputBrowserView(startingAt: job)
        } previewOutput: {
            manager.openOutputPreview(for: job)
        } createPDF: {
            manager.createPDF(for: job)
        } retry: {
            manager.retryJobs(startingAt: job)
        } directDownload: {
            manager.directDownloadJobs(startingAt: job)
        } stopLiveRecording: {
            manager.stopLiveRecording(for: job)
        } pauseAria2: {
            manager.pauseAria2(for: job)
        } resumeAria2: {
            manager.resumeAria2(for: job)
        } applyAria2Limits: {
            manager.applyCurrentAria2RuntimeLimits(for: job)
        } applyAria2Files: {
            manager.applyCurrentAria2RuntimeFileSelection(for: job)
        } applyAria2Seeding: {
            manager.applyCurrentAria2RuntimeSeeding(for: job)
        } previewAria2Files: {
            manager.previewAria2Files(for: job)
        } refreshAria2Peers: {
            manager.refreshAria2Peers(for: job)
        } markFinished: {
            manager.markJobsFinished(startingAt: job)
        } moveUp: {
            manager.moveJobUp(job)
        } moveDown: {
            manager.moveJobDown(job)
        } moveOutput: {
            manager.beginMovingOutputs(startingAt: job)
        } deleteJobAndOutput: {
            manager.beginDeletingOutputs(startingAt: job)
        } deleteOutput: {
            manager.beginDeletingOutput(for: job)
        } remove: {
            requestRemoveJob(job)
        } copySource: {
            manager.copySource(for: job)
        } copyArtist: {
            manager.copyArtistName(for: job)
        } openSource: {
            manager.openSource(for: job)
        } openAccessHelp: {
            manager.openAccessHelp(for: job)
        } info: {
            manager.infoJob = job
        } selectForContextMenu: {
            let eventType = NSApp.currentEvent?.type
            if viewMode == .icon && (eventType == .leftMouseDown || eventType == .leftMouseUp) {
                selectQueueGridJob(job)
            } else if !manager.selectedJobIDs.contains(job.id) {
                manager.setSelectedJobIDs([job.id])
            }
        } edit: {
            manager.beginEditingJob(job)
        } pages: {
            manager.beginPageSelector(for: job)
        } comment: {
            manager.beginEditingJobComment(job)
        } togglePin: {
            manager.toggleJobPins(startingAt: job)
        } toggleLock: {
            manager.toggleJobLocks(startingAt: job)
        } pinActionWillPin: {
            manager.jobPinActionWillPin(startingAt: job)
        } lockActionWillLock: {
            manager.jobLockActionWillLock(startingAt: job)
        } canToggleSelectedPins: {
            manager.canToggleJobPins(startingAt: job)
        } retryIncomplete: {
            manager.beginRetryIncompleteJobs()
        } clearCompleted: {
            manager.beginRemovingCompletedJobs()
        } isTagChecked: { tag in
            manager.isJobTagChecked(tag, for: job)
        } toggleTag: { tag in
            manager.toggleJobTag(tag, for: job)
        } tagName: { tag in
            manager.taskTagDisplayName(tag)
        } openTagSettings: {
            manager.openSettingsWindow(category: .theme)
        } convertImages: {
            manager.beginConvertingImages(startingAt: job)
        } moveToGroup: { groupID in
            let ids = manager.selectedJobIDs.contains(job.id)
                ? manager.selectedJobIDs
                : Set([job.id])
            _ = manager.moveJobs(ids, toQueueGroup: groupID)
        } moveToNewGroup: {
            manager.beginMovingJobToNewGroup(job)
        } beginReorder: {
            let ids = manager.queueJobIDsForDrag(startingAt: job.id)
            manager.draggedQueueJobIDs = ids
            return QueueDropTypes.jobPasteboardItem(for: job.id)
        } endReorder: {
            manager.endQueueDrag()
        } canBeginReorder: {
            viewMode == .list &&
                manager.queueSortMode == .manual &&
                manager.queueFilter.trimmed.isEmpty &&
                manager.jobs.filter { $0.isPinned == job.isPinned }.count > 1
        } canMoveToGroup: {
            manager.queueSortMode == .manual &&
                !manager.isRunning &&
                job.status != .resolving &&
                job.status != .downloading
        } canMoveUp: {
            manager.canMoveJobUp(job)
        } canMoveDown: {
            manager.canMoveJobDown(job)
        } canPauseAria2: {
            manager.canPauseAria2(for: job)
        } canResumeAria2: {
            manager.canResumeAria2(for: job)
        } canApplyAria2Limits: {
            manager.canApplyAria2RuntimeLimits(for: job)
        } canApplyAria2Files: {
            manager.canApplyAria2RuntimeFileSelection(for: job)
        } canApplyAria2Seeding: {
            manager.canApplyAria2RuntimeSeeding(for: job)
        } canPreviewAria2Files: {
            manager.canPreviewAria2Files(for: job)
        } canRefreshAria2Peers: {
            manager.canRefreshAria2Peers(for: job)
        } canMarkFinished: {
            manager.canMarkJobsFinished(startingAt: job)
        } canOpenPageSelector: {
            manager.canOpenPageSelector(for: job)
        } canDeleteOutput: {
            manager.canDeleteOutput(for: job)
        } canOpenFirstOutput: {
            manager.canOpenFirstOutputFile(for: job)
        } canOpenFirstSelectedOutputs: {
            manager.canOpenFirstOutputFiles(startingAt: job)
        } canViewOutputInBrowser: {
            manager.canOpenOutputBrowserView(startingAt: job)
        } canPreviewOutput: {
            manager.canOpenOutputPreview(for: job)
        } canCreatePDF: {
            manager.canCreatePDF(for: job)
        } canDirectDownload: {
            manager.canDirectDownloadJobs(startingAt: job)
        } canStopLiveRecording: {
            manager.canStopLiveRecording(for: job)
        } canMoveOutput: {
            manager.canMoveOutputs(startingAt: job)
        } canConvertImages: {
            manager.canConvertJobImages(startingAt: job)
        } canCopyArtist: {
            manager.artistName(for: job) != nil
        } canRetryIncomplete: {
            manager.retryableIncompleteJobCount > 0
        } canClearCompleted: {
            manager.removableCompletedJobCount > 0
        } canRevealSelectedOutputs: {
            manager.canRevealOutputs(startingAt: job)
        } canDeleteSelectedJobsAndOutput: {
            manager.canDeleteOutputsAndJobs(startingAt: job)
        } canRemoveSelectedJobs: {
            manager.canRemoveJobs(startingAt: job)
        } canRetrySelectedJobs: {
            manager.canRetryJobs(startingAt: job)
        }
    }

    private func selectQueueGridJob(_ job: DownloadJob) {
        let modifiers = NSApp.currentEvent?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        if modifiers.contains(.command) {
            var selection = manager.selectedJobIDs
            if selection.contains(job.id) {
                selection.remove(job.id)
            } else {
                selection.insert(job.id)
            }
            manager.setSelectedJobIDs(selection)
            return
        }

        if modifiers.contains(.shift), !manager.selectedJobIDs.isEmpty {
            let visibleIDs = manager.queueListEntries.compactMap { entry -> UUID? in
                guard case .job(let visibleJob) = entry else { return nil }
                return visibleJob.id
            }
            if let anchor = visibleIDs.first(where: manager.selectedJobIDs.contains),
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

            TextField("Filter Queue", text: $manager.queueFilter)
                .textFieldStyle(.plain)
                .frame(maxWidth: scaled(230))

            queueFilterBookmarkMenu

            Spacer(minLength: scaled(8))

            Text(selectedQueueJobs.isEmpty
                ? "\(manager.filteredJobs.count) / \(manager.jobs.count)"
                : AppLocalization.format(
                    "%@ selected · %@ / %@",
                    language: manager.interfaceLanguage,
                    String(selectedQueueJobs.count),
                    String(manager.filteredJobs.count),
                    String(manager.jobs.count)
                ))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)

            Menu {
                Picker("Sort", selection: Binding(
                    get: { manager.queueSortMode },
                    set: { manager.setQueueSortMode($0) }
                )) {
                    ForEach(QueueSortMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }

                Button {
                    manager.setQueueSortDescending(!manager.queueSortDescending)
                } label: {
                    Label(
                        manager.queueSortDescending ? "Descending" : "Ascending",
                        systemImage: manager.queueSortDescending ? "arrow.down" : "arrow.up"
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
                .disabled(manager.removableFinishedJobCount == 0)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(selectedQueueJobs.isEmpty
                ? AppLocalization.text("Queue Options", language: manager.interfaceLanguage)
                : AppLocalization.format(
                    "%@ selected",
                    language: manager.interfaceLanguage,
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
                    manager.showingQueueControls.toggle()
                } label: {
                    Image(systemName: "line.3.horizontal.decrease")
                        .frame(width: scaled(24), height: scaled(24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(manager.queueFilter.trimmed.isEmpty ? Color.secondary : Color.accentColor)
                .help(AppLocalization.text("Filter and Sort", language: manager.interfaceLanguage))

                Button {
                    manager.showingSearcher = true
                } label: {
                    Image(systemName: "magnifyingglass")
                        .frame(width: scaled(24), height: scaled(24))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(AppLocalization.text("Search", language: manager.interfaceLanguage))

                CompactLinearProgress(value: overallQueueProgress)
                    .frame(maxWidth: .infinity)

                Text(selectedQueueJobs.isEmpty
                    ? "\(completedQueueJobCount) / \(manager.jobs.count)"
                    : AppLocalization.format(
                        "%@ selected · %@ / %@",
                        language: manager.interfaceLanguage,
                        String(selectedQueueJobs.count),
                        String(completedQueueJobCount),
                        String(manager.jobs.count)
                    ))
                    .font(.system(size: scaled(12)))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
                    .help(knownQueueSizeText.isEmpty ? "Queue Progress" : knownQueueSizeText)
            }

            HStack(spacing: scaled(12)) {
                Spacer()

                Menu {
                    Button {
                        manager.openDownloadDirectory()
                    } label: {
                        Label("Open Download Folder", systemImage: "folder")
                    }

                    Button {
                        manager.showingDirectories = true
                    } label: {
                        Label("Known Output Folders...", systemImage: "list.bullet.rectangle")
                    }
                } label: {
                    Image(systemName: "folder.fill")
                        .frame(width: scaled(24), height: scaled(24))
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .foregroundStyle(.secondary)
                .help(AppLocalization.text("Folder Shortcuts", language: manager.interfaceLanguage))
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
            .disabled(manager.queueFilter.trimmed.isEmpty)

            if !manager.queueFilterBookmarks.isEmpty {
                Divider()
                ForEach(manager.queueFilterBookmarks) { bookmark in
                    Button {
                        manager.applyQueueFilterBookmark(bookmark)
                    } label: {
                        Label(bookmark.title, systemImage: "line.3.horizontal.decrease.circle")
                    }
                }

                Menu {
                    ForEach(manager.queueFilterBookmarks) { bookmark in
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
            .disabled(manager.queueFilterBookmarks.isEmpty)
        } label: {
            Image(systemName: manager.queueFilterBookmarks.isEmpty ? "bookmark" : "bookmark.fill")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(AppLocalization.text("Filter Bookmarks", language: manager.interfaceLanguage))
    }

    private var duplicateImageFolderMenu: some View {
        Menu {
            Button {
                manager.clearDuplicateImageFolders()
            } label: {
                Text("Use Save Folder")
            }
            .disabled(manager.duplicateImageFolderPaths.isEmpty)

            if !manager.duplicateImageFolderPaths.isEmpty {
                Divider()
                ForEach(manager.duplicateImageFolderPaths, id: \.self) { path in
                    Button(role: .destructive) {
                        manager.removeDuplicateImageFolder(path)
                    } label: {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                    }
                }
            }
        } label: {
            Label(manager.duplicateImageScanFolderSummary, systemImage: "folder")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Manage duplicate scan folders")
    }

    private func requestRemoveJob(_ job: DownloadJob) {
        manager.beginRemovingJobs(startingAt: job)
    }

    private func requestClearFinished() {
        guard manager.removableFinishedJobCount > 0 else {
            manager.clearFinished()
            return
        }
        manager.showingClearFinishedConfirmation = true
    }

    private func requestClearBookmarks() {
        guard !manager.bookmarks.isEmpty else {
            manager.clearBookmarks()
            return
        }
        manager.showingClearBookmarksConfirmation = true
    }

    private func tokenMenu(_ tokens: [NameTemplateToken], insert: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(tokens) { token in
                Button(token.menuTitle) {
                    insert(token.value)
                }
            }
        } label: {
            Image(systemName: "curlybraces")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Insert name token")
    }

    @ViewBuilder
    private func tokenAutocompleteRow(_ tokens: [NameTemplateToken], complete: @escaping (String) -> Void) -> some View {
        if !tokens.isEmpty {
            HStack(spacing: 6) {
                ForEach(tokens) { token in
                    Button {
                        complete(token.value)
                    } label: {
                        Text(token.value)
                            .font(.caption.monospaced())
                    }
                    .buttonStyle(.borderless)
                    .help(token.title)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private func nameTokenHelp(_ tokens: [NameTemplateToken]) -> String {
        "Tokens: " + tokens.map(\.value).joined(separator: ", ")
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

struct YouTubeCodecPriorityMenu: View {
    @ObservedObject var manager: DownloadManager

    private var priority: [YouTubeVideoCodec] {
        YouTubeVideoCodec.normalizedPriority(manager.youtubeVideoCodecPriority)
    }

    private var label: String {
        YouTubeVideoCodec.priorityLabel(priority)
    }

    var body: some View {
        Menu {
            ForEach(YouTubeVideoCodec.allPriorityOrders, id: \.self) { option in
                Button {
                    manager.setYouTubeVideoCodecPriority(option)
                } label: {
                    if option == priority {
                        Label(YouTubeVideoCodec.priorityLabel(option), systemImage: "checkmark")
                    } else {
                        Text(YouTubeVideoCodec.priorityLabel(option))
                    }
                }
            }
        } label: {
            Text(label)
                .lineLimit(1)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(AppLocalization.text("Preferred YouTube video codec order", language: manager.interfaceLanguage))
        .accessibilityLabel(AppLocalization.text("YouTube Codec Priority", language: manager.interfaceLanguage))
        .accessibilityValue(label)
        .accessibilityIdentifier("settings.youtube-codec-priority")
    }
}

struct SettingsWindowView: View {
    @ObservedObject var manager: DownloadManager
    @ObservedObject private var presentation: SettingsWindowPresentationState

    init(manager: DownloadManager) {
        self.manager = manager
        presentation = manager.settingsWindowPresentation
    }

    private enum SettingsRowDetailPlacement: Equatable {
        case label
        case fullWidth
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }

    private func localizedStatus(_ value: String) -> String {
        AppLocalization.statusText(value, language: manager.interfaceLanguage)
    }

    private var visibleCategories: [SettingsWindowCategory] {
        let query = presentation.filter.trimmed.lowercased()
        guard !query.isEmpty else { return SettingsWindowCategory.allCases }
        return SettingsWindowCategory.allCases.filter {
            $0.searchText.lowercased().contains(query)
        }
    }

    private var statusColorSummary: String {
        localized(
            manager.jobStatusColorPalette == .defaultPalette ? "Default Palette" : "Custom Palette"
        )
    }

    private var filteredArchiveSourceProfiles: [DownloadSourceFolderProfile] {
        let query = presentation.archiveFilter.trimmed.lowercased()
        guard !query.isEmpty else { return manager.sourceFolderProfiles }
        return manager.sourceFolderProfiles.filter {
            $0.displayName.lowercased().contains(query) || $0.id.lowercased().contains(query)
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                header

                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 18) {
                        selectedCategoryContent

                        if !manager.addSummary.isEmpty {
                            Text(localizedStatus(manager.addSummary))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.leading, 18)
                    .padding(.trailing, 10)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .id(manager.interfaceLanguage)
        .frame(
            minWidth: 620,
            idealWidth: 920,
            maxWidth: .infinity,
            minHeight: 540,
            idealHeight: 660,
            maxHeight: .infinity
        )
        .environment(\.locale, manager.interfaceLanguage.locale)
        .sheet(isPresented: $manager.showingFontSettings) {
            FontSettingsView(manager: manager)
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localized("Settings"))
                .font(.headline)

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField(localized("Search"), text: $presentation.filter)
                    .textFieldStyle(.roundedBorder)
                if !presentation.filter.trimmed.isEmpty {
                    Button {
                        presentation.filter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(AppLocalization.text("Clear Search", language: manager.interfaceLanguage))
                }
            }

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(visibleCategories) { category in
                        SettingsCategorySidebarButton(
                            category: category,
                            isSelected: presentation.category == category
                        ) {
                            presentation.category = category
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(width: 190, alignment: .topLeading)
        .background(.bar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            SettingsCategoryIcon(category: presentation.category, size: 18)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.category.label)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(presentation.category.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.showingSettingsWindow = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help(AppLocalization.text("Close Settings", language: manager.interfaceLanguage))
            .accessibilityIdentifier("settings.close")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    @ViewBuilder
    private var selectedCategoryContent: some View {
        switch presentation.category {
        case .general:
            generalSettings
        case .network:
            networkSettings
        case .live:
            liveSettings
        case .theme:
            themeSettings
        case .archive:
            archiveSettings
        case .plugins:
            pluginSettings
        case .advanced:
            advancedSettings
        case .hitomi:
            hitomiSettings
        case .pixiv:
            pixivSettings
        case .kemonoFriends:
            kemonoFriendsSettings
        case .youtube:
            youtubeSettings
        case .social:
            socialSettings
        case .torrent:
            torrentSettings
        }
    }

    private var generalSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Language", systemImage: "globe") {
                settingsRow("Display Language") {
                    trailingSettingsControl {
                        Picker("", selection: Binding(
                            get: { manager.interfaceLanguage },
                            set: { manager.setInterfaceLanguage($0) }
                        )) {
                            ForEach(AppInterfaceLanguage.allCases) { language in
                                Text(language.displayName).tag(language)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel(AppLocalization.text("Display Language", language: manager.interfaceLanguage))
                        .accessibilityIdentifier("settings.interface-language")
                    }
                }
            }

            settingsSection("Save Folder", systemImage: "folder") {
                settingsRow("Save Location") {
                    HStack(spacing: 8) {
                        Text(manager.destinationPath)
                            .font(.caption)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        iconButton("folder", help: "Choose Download Folder") {
                            manager.chooseDestination()
                        }
                    }
                }

                settingsRow("Folders by Source") {
                    VStack(alignment: .trailing, spacing: 5) {
                        sourceFolderProfileMenu

                        HStack(spacing: 6) {
                            TextField(
                                DownloadSourceFolderProfile.defaultFolderName(
                                    for: manager.selectedSourceFolderID
                                ),
                                text: Binding(
                                    get: {
                                        manager.sourceFolderName(
                                            for: manager.selectedSourceFolderID
                                        )
                                    },
                                    set: {
                                        manager.setSourceFolderName(
                                            $0,
                                            for: manager.selectedSourceFolderID
                                        )
                                    }
                                )
                            )
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 186)
                            .accessibilityLabel(AppLocalization.text("Source Folder Name", language: manager.interfaceLanguage))
                            .accessibilityIdentifier("settings.source-folder-name")

                            iconButton("arrow.counterclockwise", help: "Reset Source Folder Name") {
                                manager.resetSourceFolderName(
                                    for: manager.selectedSourceFolderID
                                )
                            }
                            .accessibilityIdentifier("settings.source-folder-reset")
                        }
                        .frame(width: 220, alignment: .trailing)

                        Text(manager.selectedSourceFolderPreviewPath)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(width: 220, alignment: .trailing)
                            .accessibilityIdentifier("settings.source-folder-preview")
                    }
                    .frame(width: 220, alignment: .trailing)
                }

                settingsRow("Folder Layout") {
                    trailingSettingsControl {
                        Picker("", selection: Binding(
                            get: { manager.outputSubfolderMode },
                            set: { manager.setOutputSubfolderMode($0) }
                        )) {
                            ForEach(OutputSubfolderMode.allCases, id: \.self) { mode in
                                Text(mode.label(language: manager.interfaceLanguage)).tag(mode)
                            }
                        }
                        .id("output-folder-layout-\(manager.interfaceLanguage.rawValue)")
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize()
                        .accessibilityLabel(AppLocalization.text("Download Folder Layout", language: manager.interfaceLanguage))
                        .accessibilityIdentifier("settings.output-folder-layout")
                    }
                }
            }

            settingsSection("Queue", systemImage: "list.bullet.rectangle") {
                settingsRow("Concurrent Tasks") {
                    Stepper(value: $manager.jobConcurrency, in: 1...12) {
                        Text("\(manager.jobConcurrency)")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 150, alignment: .trailing)
                }

                settingsRow("Threads per Task") {
                    Stepper(value: $manager.concurrency, in: 1...24) {
                        Text("\(manager.concurrency)")
                            .monospacedDigit()
                    }
                    .frame(maxWidth: 150, alignment: .trailing)
                }

                settingsRow("Retry Incomplete") {
                    trailingSettingsControl {
                        HStack(spacing: 10) {
                            incompleteRetryDelayMenu

                            Toggle("", isOn: Binding(
                                get: { manager.retryIncompleteAutomatically },
                                set: { manager.setRetryIncompleteAutomatically($0) }
                            ))
                            .labelsHidden()
                            .toggleStyle(.switch)
                            .fixedSize(horizontal: true, vertical: false)
                            .accessibilityLabel(AppLocalization.text("Automatically retry incomplete downloads", language: manager.interfaceLanguage))
                            .accessibilityIdentifier("settings.incomplete-retry-toggle")
                        }
                    }
                }

                settingsRow("Skip Duplicate URLs") {
                    settingsSwitch("Skip Duplicate URLs", isOn: Binding(
                        get: { manager.skipDuplicates },
                        set: { manager.setSkipDuplicates($0) }
                    ))
                    .accessibilityIdentifier("settings.skip-duplicates")
                }

                settingsRow("Automatically remove completed tasks") {
                    settingsSwitch("Automatically remove completed tasks", isOn: Binding(
                        get: { manager.autoRemoveFinishedJobs },
                        set: { manager.setAutoRemoveFinishedJobs($0) }
                    ))
                    .accessibilityIdentifier("settings.auto-remove-finished")
                }

                settingsRow("Show download date") {
                    settingsSwitch("Show download date", isOn: Binding(
                        get: { manager.showDownloadDate },
                        set: { manager.setShowDownloadDate($0) }
                    ))
                    .accessibilityIdentifier("settings.show-download-date")
                }

                settingsRow("Number playlist files") {
                    settingsSwitch("Number playlist files", isOn: Binding(
                        get: { manager.numberPlaylistFiles },
                        set: { manager.setNumberPlaylistFiles($0) }
                    ))
                    .accessibilityIdentifier("settings.number-playlist-files")
                }
            }

            settingsSection("Naming", systemImage: "textformat") {
                settingsRow("Work Folder") {
                    editableTemplatePicker(
                        placeholder: DownloadSourceFolderProfile.originalDefaultFolderTemplate,
                        text: Binding(
                            get: { manager.folderNameTemplate },
                            set: { manager.setFolderNameTemplate($0) }
                        ),
                        presets: NameTemplate.originalFolderPresets,
                        accessibilityPrefix: "settings.folder-template"
                    ) {
                        manager.applyFolderNamePreset($0)
                    }
                }

                settingsRow("Individual Files") {
                    if DownloadSourceFolderProfile.normalizedSourceID(
                        manager.selectedSourceFolderID
                    ) == "hitomi" && manager.usesOriginalHitomiFilenameMode {
                        hitomiFilenameTypePicker
                    } else {
                        editableTemplatePicker(
                            placeholder: NameTemplate.originalFileDefault(
                                for: manager.selectedSourceFolderID
                            ) ?? "{index:04}-{basename}",
                            text: Binding(
                                get: { manager.selectedSourceFileNameTemplate },
                                set: { manager.setSelectedSourceFileNameTemplate($0) }
                            ),
                            presets: manager.selectedSourceFileNamePresets,
                            accessibilityPrefix: "settings.file-template"
                        ) {
                            manager.applySelectedSourceFileNamePreset($0)
                        }
                    }
                }

                settingsRow("Recording File") {
                    trailingSettingsControl {
                        HStack(spacing: 8) {
                            editableTemplatePicker(
                                placeholder: "[artist] date:%Y-%m-%d %H:%M; title",
                                text: Binding(
                                    get: { manager.recordingFileNameTemplate },
                                    set: { manager.setRecordingFileNameTemplate($0) }
                                ),
                                presets: NameTemplate.originalRecordingPresets,
                                accessibilityPrefix: "settings.recording-template"
                            ) {
                                manager.applyRecordingFileNamePreset($0)
                            }
                        }
                    }
                }
            }
        }
    }

    private var networkSettings: some View {
        VStack(alignment: .leading, spacing: 14) {
            settingsSection("DPI Bypass", systemImage: "checkmark.shield") {
                settingsRow(
                    "Mode",
                    detail: manager.dpiBypassMode.detailLocalizationKey,
                    detailPlacement: .fullWidth
                ) {
                    HStack(spacing: 10) {
                        Image(systemName: manager.browserDPIBypassSnapshot.phase.systemImage)
                            .foregroundStyle(browserDPIBypassStatusColor(
                                manager.browserDPIBypassSnapshot.phase
                            ))
                            .frame(width: 18, height: 18)
                            .help(browserDPIBypassStatusHelp)
                            .accessibilityLabel(localized(
                                manager.browserDPIBypassSnapshot.phase.localizationKey
                            ))
                            .accessibilityValue(browserDPIBypassStatusHelp)
                            .accessibilityIdentifier("settings.browser-dpi-status")

                        Picker("", selection: Binding(
                            get: { manager.dpiBypassMode },
                            set: { manager.setDPIBypassMode($0) }
                        )) {
                            ForEach(DPIBypassMode.allCases) { mode in
                                Text(localized(mode.localizationKey))
                                    .tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .fixedSize(horizontal: true, vertical: false)
                        .accessibilityLabel(localized("DPI Bypass Mode"))
                        .accessibilityIdentifier("settings.browser-dpi-mode")
                        .disabled(manager.browserDPIBypassSnapshot.phase.isBusy)
                    }
                }

                if !manager.browserDPIBypassSnapshot.diagnostic.isEmpty {
                    Label {
                        Text(localizedStatus(manager.browserDPIBypassSnapshot.diagnostic))
                            .fixedSize(horizontal: false, vertical: true)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityIdentifier("settings.browser-dpi-diagnostic")
                }

                if manager.browserDPIBypassSnapshot.hasRestorableProxySettings {
                    settingsRow("Saved Network Settings") {
                        Button {
                            manager.restoreBrowserDPIProxySettings()
                        } label: {
                            Label(localized("Restore"), systemImage: "arrow.uturn.backward")
                        }
                        .buttonStyle(.bordered)
                        .disabled(manager.browserDPIBypassSnapshot.phase.isBusy)
                        .accessibilityIdentifier("settings.browser-dpi-restore")
                    }
                }

                Button {
                    manager.browserDPIAdvancedExpanded.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: manager.browserDPIAdvancedExpanded ? "chevron.down" : "chevron.right")
                            .font(.caption.weight(.semibold))
                            .frame(width: 14)
                        Label(localized("Advanced"), systemImage: "slider.horizontal.3")
                        Spacer(minLength: 0)
                    }
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .accessibilityLabel(localized("Advanced"))
                .accessibilityValue(localized(manager.browserDPIAdvancedExpanded ? "On" : "Off"))
                .accessibilityIdentifier("settings.browser-dpi-advanced")

                if manager.browserDPIAdvancedExpanded {
                    settingsRow("Proxy Address") {
                        HStack(spacing: 8) {
                            Text(manager.browserDPIBypassSnapshot.endpoint.displayValue)
                                .font(.caption.monospaced())
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                                .textSelection(.enabled)
                                .layoutPriority(1)
                                .accessibilityIdentifier("settings.browser-dpi-address")
                            iconButton("doc.on.doc", help: "Copy Proxy Address") {
                                manager.copyBrowserDPIProxyAddress()
                            }
                            .accessibilityIdentifier("settings.browser-dpi-copy")
                            iconButton("arrow.clockwise", help: "Refresh Proxy Status") {
                                manager.refreshBrowserDPIBypassStatus()
                            }
                            .accessibilityIdentifier("settings.browser-dpi-refresh")
                            iconButton("gearshape", help: "Open macOS Proxy Settings") {
                                manager.openBrowserDPIProxySettings()
                            }
                            .accessibilityIdentifier("settings.browser-dpi-open-settings")
                        }
                        .controlSize(.small)
                    }
                    .padding(.top, 8)
                }
            }

            settingsSection("Proxy", systemImage: "network") {
                settingsRow(
                    "Use Proxy",
                    detail: manager.proxyEnabled && manager.dpiBypassMode.usesLocalProxy
                        ? "DPI bypass first; saved proxy resumes when off"
                        : "Manual proxy for supported downloads"
                ) {
                    settingsSwitch("Use Proxy", isOn: Binding(
                        get: { manager.proxyEnabled },
                        set: { enabled in
                            manager.proxyEnabled = enabled
                            if !enabled {
                                manager.saveProxySettings()
                            }
                        }
                    ))
                }

                settingsRow("URL") {
                    HStack(spacing: 8) {
                        TextField("http://127.0.0.1:8080", text: $manager.proxyURLString)
                            .textFieldStyle(.roundedBorder)
                            .disabled(!manager.proxyEnabled)
                        iconButton("checkmark", help: "Save Proxy Settings") {
                            manager.saveProxySettings()
                        }
                        .disabled(!manager.proxyEnabled)
                    }
                }

                settingsRow("Bypass Addresses") {
                    TextField("example.com, *.internal.test", text: $manager.proxyBypassList)
                        .textFieldStyle(.roundedBorder)
                        .disabled(!manager.proxyEnabled)
                }

                settingsRow("Public IP") {
                    HStack(spacing: 8) {
                        iconButton(manager.isRefreshingPublicIP ? "hourglass" : "arrow.clockwise", help: "Check Public IP") {
                            manager.refreshPublicIP()
                        }
                        .disabled(manager.isRefreshingPublicIP)
                        Text(localizedStatus(manager.publicIPStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            settingsSection("Cookies", systemImage: "key") {
                settingsRow("Import") {
                    HStack(spacing: 8) {
                        iconButton("key", help: "Import cookies.txt or a Cookie header") {
                            manager.importCookies()
                        }
                        iconButton("globe", help: "Import Browser Cookies") {
                            manager.importBrowserCookies()
                        }
                        iconButton("magnifyingglass", help: "Locate Browser Cookie Database") {
                            manager.importDetectedBrowserCookies()
                        }
                        iconButton("person.crop.circle.badge.key", help: "Open Login Browser") {
                            manager.openLoginBrowser()
                        }
                        cookieClearButton()
                        Text(localizedStatus(manager.cookieSummary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }

            settingsSection("HTTP API", systemImage: "server.rack") {
                settingsRow("HTTP API") {
                    settingsSwitch("HTTP API", isOn: Binding(
                        get: { manager.httpAPIEnabled },
                        set: { manager.setHTTPAPIEnabled($0) }
                    ))
                }

                if manager.httpAPIEnabled {
                    settingsRow("Lazy-load images") {
                        settingsSwitch("Lazy-load images", isOn: Binding(
                            get: { manager.httpViewerLazyLoading },
                            set: { manager.setHTTPViewerLazyLoading($0) }
                        ))
                    }

                    settingsRow("Port") {
                        HStack(spacing: 8) {
                            TextField("8110", text: $manager.httpAPIPortString)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 90)
                            SecureField(localized("Password"), text: $manager.httpAPIPassword)
                                .textFieldStyle(.roundedBorder)
                            iconButton("checkmark", help: "Save HTTP API Settings") {
                                manager.saveHTTPAPISettings()
                            }
                        }
                    }

                    settingsRow("Status") {
                        Text(localizedStatus(manager.httpAPIStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private func browserDPIBypassStatusColor(_ phase: BrowserDPIBypassPhase) -> Color {
        switch phase {
        case .active:
            return .green
        case .failed, .conflictingSystemProxy, .restoreRequired:
            return .red
        case .starting, .detectingNetwork, .configuringSystemProxy,
             .restoringSystemProxy, .waitingForSystemProxy,
             .partiallyConfigured, .waitingForProxyRemoval:
            return .orange
        case .off:
            return .secondary
        }
    }

    private var browserDPIBypassStatusHelp: String {
        let snapshot = manager.browserDPIBypassSnapshot
        let diagnostic = snapshot.diagnostic.trimmed
        return [
            localized(snapshot.phase.localizationKey),
            snapshot.networkService.trimmed,
            diagnostic.isEmpty ? "" : localizedStatus(diagnostic)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n")
    }

    private var liveSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Automatic Recording", systemImage: "record.circle") {
                settingsRow("Enable Automatic Recording") {
                    settingsSwitch("Enable Automatic Recording", isOn: Binding(
                        get: { manager.autoRecordEnabled },
                        set: { manager.setAutoRecordEnabled($0) }
                    ))
                }

                settingsRow("Automatic Recording Paused") {
                    settingsSwitch("Automatic Recording Paused", isOn: Binding(
                        get: { manager.autoRecordPaused },
                        set: { manager.setAutoRecordPaused($0) }
                    ))
                    .disabled(!manager.autoRecordEnabled)
                }

                settingsRow("Check Interval") {
                    HStack(spacing: 8) {
                        TextField("10", text: $manager.autoRecordIntervalMinutesString)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                        iconButton(manager.isAutoRecordChecking ? "hourglass" : "arrow.clockwise", help: "Check Automatic Recording Sources Now") {
                            manager.checkAutoRecordNow()
                        }
                        .disabled(manager.isAutoRecordChecking || manager.autoRecordPaused)
                        iconButton("checkmark", help: "Save Automatic Recording Settings") {
                            manager.saveAutoRecordSettings()
                        }
                    }
                }

                settingsRow("Source") {
                    TextEditor(text: $manager.autoRecordURLsText)
                        .font(.caption)
                        .frame(minHeight: 90)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.separator, lineWidth: 1)
                        )
                }

                settingsRow("Status") {
                    Text(localizedStatus(manager.autoRecordStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            settingsSection("HLS", systemImage: "film.stack") {
                settingsRow("Remux to MP4") {
                    settingsSwitch("Remux to MP4", isOn: $manager.remuxM3U8ToMP4)
                }

                settingsRow("Skip failed items") {
                    settingsSwitch("Skip failed items", isOn: $manager.hlsContinueOnSegmentFailure)
                }

                settingsRow("Delay") {
                    HStack(spacing: 8) {
                        TextField(localized("Delay (ms)"), text: $manager.m3u8SegmentDelayMillisecondsString)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 100)
                        iconButton("checkmark", help: "Save HLS Settings") {
                            manager.saveM3U8RemuxSetting()
                        }
                    }
                }

                settingsRow("Prevent sleep while downloading") {
                    settingsSwitch("Prevent sleep while downloading", isOn: Binding(
                        get: { manager.preventSleepWhileDownloading },
                        set: { manager.setPreventSleepWhileDownloading($0) }
                    ))
                }
            }
        }
    }

    private var themeSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsGroup {
                settingsRow("Theme") {
                    trailingSettingsControl {
                        HStack(spacing: 8) {
                            Picker("", selection: Binding(
                                get: { manager.selectedPythonThemeKey },
                                set: { manager.setSelectedPythonThemeKey($0) }
                            )) {
                                Text(localized("Default")).tag("")
                                ForEach(manager.availablePythonThemes) { theme in
                                    Text(theme.displayName).tag(theme.key)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.menu)
                            .frame(width: 174, alignment: .trailing)
                            .accessibilityLabel(localized("Theme"))
                            .accessibilityIdentifier("settings.theme-picker")

                            iconButton("puzzlepiece.extension", help: "Open Theme Plugin") {
                                manager.openSettingsWindow(category: .plugins)
                            }
                            .frame(width: 38)
                            .accessibilityIdentifier("settings.theme-plugin")
                        }
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                settingsRow("Appearance") {
                    trailingSettingsControl {
                        Picker("", selection: Binding(
                            get: { manager.appAppearanceMode },
                            set: { manager.setAppAppearanceMode($0) }
                        )) {
                            ForEach(AppAppearanceMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220, alignment: .trailing)
                        .disabled(manager.activePythonTheme?.appearance != nil && manager.activePythonTheme?.appearance != .system)
                        .accessibilityLabel(localized("Appearance"))
                        .accessibilityIdentifier("settings.appearance")
                    }
                }

                settingsRow("UI Scale") {
                    trailingSettingsControl {
                        uiScaleSelector
                            .frame(width: 110, alignment: .trailing)
                    }
                }

                settingsRow("Font") {
                    trailingSettingsControl {
                        HStack(spacing: 10) {
                            Text(manager.interfaceFontSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button {
                                manager.openFontSettings()
                            } label: {
                                Label(localized("Edit"), systemImage: "textformat.size")
                            }
                            .accessibilityIdentifier("settings.font-edit")
                        }
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                settingsRow("Low Power Mode") {
                    trailingSettingsControl {
                        settingsSwitch("Low Power Mode", isOn: Binding(
                            get: { manager.lowPowerMode },
                            set: { manager.setLowPowerMode($0) }
                        ))
                    }
                }

                settingsRow("Launch at Login") {
                    trailingSettingsControl {
                        settingsSwitch("Launch at Login", isOn: Binding(
                            get: { manager.launchAtLoginEnabled },
                            set: { manager.setLaunchAtLoginEnabled($0) }
                        ))
                    }
                }
            }

            settingsSection("Queue Colors", systemImage: "paintpalette") {
                settingsRow("Status Colors") {
                    trailingSettingsControl {
                        HStack(spacing: 10) {
                            Text(statusColorSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            Button {
                                manager.beginEditingStatusColors()
                            } label: {
                                Label(localized("Edit"), systemImage: "paintpalette")
                            }
                            .accessibilityIdentifier("settings.status-colors-edit")
                        }
                        .frame(width: 220, alignment: .trailing)
                    }
                }

                settingsRow("Duplicate Preview") {
                    trailingSettingsControl {
                        settingsSwitch("Show Thumbnails in Duplicate Image Preview", isOn: Binding(
                            get: { manager.showDuplicateImageThumbnails },
                            set: { manager.setDuplicateImageThumbnails($0) }
                        ))
                        .disabled(manager.lowPowerMode)
                    }
                }

                settingsRow("Similarity") {
                    trailingSettingsControl {
                        Stepper(value: Binding(
                            get: { manager.duplicateImageSimilarityPercent },
                            set: { manager.setDuplicateImageSimilarityPercent($0) }
                        ), in: 70...100) {
                            Text("\(manager.duplicateImageSimilarityPercent)%")
                                .monospacedDigit()
                        }
                        .frame(maxWidth: 170, alignment: .trailing)
                    }
                }
            }

            settingsSection("Task Tags", systemImage: "tag") {
                ForEach(TaskTagColor.allCases) { tag in
                    settingsRow(tag.label) {
                        trailingSettingsControl {
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(tag.color)
                                    .frame(width: 12, height: 12)
                                    .accessibilityHidden(true)
                                TextField(tag.label, text: Binding(
                                    get: { manager.taskTagNames[tag.rawValue] ?? tag.label },
                                    set: { manager.setTaskTagName($0, for: tag) }
                                ))
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 170)
                                .accessibilityLabel(AppLocalization.format(
                                    "%@ Tag Name",
                                    language: manager.interfaceLanguage,
                                    AppLocalization.text(tag.label, language: manager.interfaceLanguage)
                                ))
                                .accessibilityIdentifier("settings.task-tag-name.\(tag.rawValue)")

                                taskTagRestartTimerMenu(tag)
                            }
                            .fixedSize(horizontal: true, vertical: false)
                        }
                    }
                }

                settingsRow("Reset") {
                    trailingSettingsControl {
                        iconButton("arrow.counterclockwise", help: "Reset Task Tag Names") {
                            manager.resetTaskTagNames()
                        }
                        .accessibilityIdentifier("settings.task-tag-reset")
                    }
                }
            }
        }
    }

    private func trailingSettingsControl<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 0) {
            content()
        }
        .fixedSize(horizontal: true, vertical: false)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var sourceFolderProfileMenu: some View {
        SourceFolderPopUpButton(
            profiles: manager.sourceFolderProfiles,
            selectedID: manager.selectedSourceFolderID,
            language: manager.interfaceLanguage
        ) {
            manager.selectSourceFolder($0)
        }
        .frame(width: 220, height: 24)
    }

    private func editableTemplatePicker(
        placeholder: String,
        text: Binding<String>,
        presets: [String],
        accessibilityPrefix: String,
        apply: @escaping (String) -> Void
    ) -> some View {
        EditablePresetComboBox(
            placeholder: placeholder,
            text: text,
            presets: presets,
            accessibilityIdentifier: accessibilityPrefix,
            onPreset: apply
        )
        .frame(width: 220, height: 26)
        .help(AppLocalization.text(
            "Choose a preset or edit the format directly",
            language: manager.interfaceLanguage
        ))
    }

    private var hitomiFilenameTypePicker: some View {
        Picker("", selection: Binding(
            get: { manager.selectedHitomiFilenameTypeNumber },
            set: { manager.setHitomiFilenameTypeNumber($0) }
        )) {
            Text(localized("Original Filename")).tag(0)
            Text(localized("Four-Digit Number (0000)")).tag(1)
            Text(localized("Four-Digit Number + Original Filename")).tag(2)
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 220, alignment: .trailing)
        .accessibilityLabel(AppLocalization.text(
            "Hitomi Filename Format",
            language: manager.interfaceLanguage
        ))
        .accessibilityValue(manager.selectedSourceFileNameTemplate)
        .accessibilityIdentifier("settings.file-template")
    }

    private func settingsFavicon(resourceKey: String) -> NSImage? {
        guard let source = SiteFaviconCatalog.image(resourceKey: resourceKey),
              let image = source.copy() as? NSImage else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        return image
    }

    private func taskTagRestartTimerMenu(_ tag: TaskTagColor) -> some View {
        let selected = manager.taskTagRestartDelay(for: tag)
        let description = manager.taskTagRestartTimerDescription(for: tag)
        return Menu {
            ForEach(TaskTagRestartDelay.allCases) { delay in
                Button {
                    manager.setTaskTagRestartDelay(delay, for: tag)
                } label: {
                    if selected == delay {
                        Label(delay.label, systemImage: "checkmark")
                    } else {
                        Text(delay.label)
                    }
                }
            }
        } label: {
            Image(systemName: selected == .off ? "clock" : "clock.fill")
                .foregroundStyle(selected == .off ? Color.secondary : Color.accentColor)
                .frame(width: 24, height: 24, alignment: .trailing)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(AppLocalization.format(
            "After completion: %@",
            language: manager.interfaceLanguage,
            description
        ))
        .accessibilityLabel(AppLocalization.format(
            "%@ Tag Restart Timer",
            language: manager.interfaceLanguage,
            AppLocalization.text(tag.label, language: manager.interfaceLanguage)
        ))
        .accessibilityValue(description)
        .accessibilityIdentifier("settings.task-tag-timer.\(tag.rawValue)")
    }

    private var uiScaleSelector: some View {
        Picker(localized("UI Scale"), selection: Binding(
            get: { manager.uiScale },
            set: { manager.setUIScale($0) }
        )) {
            ForEach(AppUIScale.allCases, id: \.self) { scale in
                Text(scale.label)
                    .tag(scale)
                    .accessibilityIdentifier("settings.ui-scale.\(scale.rawValue)")
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .fixedSize()
        .accessibilityLabel(AppLocalization.text("UI Scale", language: manager.interfaceLanguage))
        .accessibilityIdentifier("settings.ui-scale-selector")
    }

    private var incompleteRetryDelayMenu: some View {
        Picker("", selection: Binding(
            get: { manager.incompleteRetryDelay },
            set: { manager.setIncompleteRetryDelay($0) }
        )) {
            ForEach(IncompleteRetryDelay.allCases) { delay in
                Text(delay.label(language: manager.interfaceLanguage))
                    .tag(delay)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .frame(width: 100, alignment: .trailing)
        .fixedSize(horizontal: true, vertical: false)
        .disabled(!manager.retryIncompleteAutomatically)
        .accessibilityLabel(AppLocalization.text(
            "Incomplete retry delay",
            language: manager.interfaceLanguage
        ))
        .accessibilityValue(manager.incompleteRetryDelay.label(language: manager.interfaceLanguage))
        .accessibilityIdentifier("settings.incomplete-retry-delay")
    }

    private var archiveSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Images", systemImage: "photo") {
                settingsRow("Format Conversion") {
                    Picker("", selection: Binding(
                        get: { manager.imageConversionFormat },
                        set: { manager.setImageConversionFormat($0) }
                    )) {
                        ForEach(ImageConversionFormat.allCases, id: \.self) { format in
                            Text(format.label).tag(format)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170, alignment: .trailing)
                }
            }

            settingsSection("Archive Icon", systemImage: "archivebox.fill") {
                settingsRow("Hide Missing Archive Icons") {
                    settingsSwitch(
                        "Hide Missing Archive Icons",
                        isOn: Binding(
                            get: { manager.hideArchiveIndicatorWhenFileMissing },
                            set: { manager.setHideArchiveIndicatorWhenFileMissing($0) }
                        )
                    )
                    .accessibilityIdentifier("settings.hide-missing-archive-indicator")
                }
            }

            settingsSection("Archive by Source", systemImage: "archivebox") {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField(localized("Search Sources"), text: $presentation.archiveFilter)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("settings.archive-source-filter")
                    if !presentation.archiveFilter.trimmed.isEmpty {
                        Button {
                            presentation.archiveFilter = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .help(AppLocalization.text("Clear Source Search", language: manager.interfaceLanguage))
                    }
                }

                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(filteredArchiveSourceProfiles.enumerated()), id: \.element.id) { index, profile in
                        archiveSourceRow(profile)
                        if index < filteredArchiveSourceProfiles.count - 1 {
                            Divider()
                        }
                    }
                }
            }
        }
    }

    private func archiveSourceRow(_ profile: DownloadSourceFolderProfile) -> some View {
        HStack(spacing: 10) {
            Group {
                if let image = settingsFavicon(resourceKey: profile.faviconKey) {
                    Image(nsImage: image)
                        .frame(width: 18, height: 18)
                } else {
                    Image(systemName: "questionmark.square")
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
            }

            Text(profile.displayName)
                .font(.subheadline)
                .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)

            if profile.supportsFolderArchive {
                Picker("", selection: Binding(
                    get: { manager.sourceArchiveMode(for: profile.id) },
                    set: { manager.setSourceArchiveMode($0, for: profile.id) }
                )) {
                    ForEach(SourceArchiveMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .controlSize(.small)
                .frame(width: 88, alignment: .trailing)
                .accessibilityLabel(AppLocalization.format(
                    "%@ Archive Format",
                    language: manager.interfaceLanguage,
                    profile.displayName
                ))
                .accessibilityIdentifier("settings.archive-mode.\(profile.id)")

                settingsSwitch(
                    "Delete Original Files",
                    isOn: Binding(
                    get: { manager.sourceArchiveDeletesOriginal(for: profile.id) },
                    set: { manager.setSourceArchiveDeleteOriginal($0, for: profile.id) }
                ))
                .controlSize(.small)
                .disabled(manager.sourceArchiveMode(for: profile.id) == .pass)
                .accessibilityLabel(AppLocalization.format(
                    "%@ Delete Original Folder",
                    language: manager.interfaceLanguage,
                    profile.displayName
                ))
                .accessibilityIdentifier("settings.archive-delete.\(profile.id)")
            } else {
                Text(localized("Single File"))
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .frame(width: 144, alignment: .trailing)
                    .accessibilityIdentifier("settings.archive-single.\(profile.id)")
            }
        }
        .frame(minHeight: 28)
        .opacity(profile.supportsFolderArchive ? 1 : 0.55)
    }

    private var pluginSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Python Scripts", systemImage: "terminal") {
                settingsRow("Runtime") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            TextField(localized("Automatically Select Python 3"), text: $manager.pythonPath)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    manager.savePythonPath()
                                }
                            iconButton("folder", help: "Choose Python 3 Executable") {
                                manager.choosePythonExecutable()
                            }
                            iconButton("checkmark", help: "Save Python Path") {
                                manager.savePythonPath()
                            }
                        }
                        Text(localizedStatus(manager.pythonScriptStatus))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }

                settingsRow("Scripts") {
                    HStack(spacing: 8) {
                        iconButton("doc.badge.plus", help: "Import Script into Current Session") {
                            manager.importPythonScript()
                        }
                        iconButton("plus", help: "Install Python Plugin") {
                            manager.installPythonPlugin()
                        }
                        iconButton("arrow.clockwise", help: "Reload Python Scripts") {
                            manager.reloadPythonScriptPlugins()
                        }
                        .disabled(manager.isReloadingPythonScripts)
                        iconButton("folder", help: "Show Python Plugin Folder") {
                            manager.revealPythonPluginFolder()
                        }
                        Text("\(manager.pythonScriptPlugins.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                settingsRow("Hook Status") {
                    Text(localizedStatus(manager.pythonHookStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                settingsRow("Theme Status") {
                    Text(localizedStatus(manager.pythonThemeStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if manager.pythonScriptPlugins.isEmpty {
                    Text(localized("No Python scripts"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(manager.pythonScriptPlugins) { plugin in
                            PythonScriptPluginRow(plugin: plugin) { enabled in
                                manager.setPythonScriptPluginEnabled(plugin, enabled: enabled)
                            } remove: {
                                manager.removePythonScriptPlugin(plugin)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120, maxHeight: 220)
                }
            }

            settingsSection("Site Rules", systemImage: "puzzlepiece.extension") {
                settingsRow("Import / Export") {
                    HStack(spacing: 8) {
                        iconButton("square.and.arrow.down", help: "Import Site Rules") {
                            manager.importSiteRules()
                        }
                        iconButton("square.and.arrow.up", help: "Export Site Rules") {
                            manager.exportSiteRules()
                        }
                        Text("\(manager.siteRules.count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                settingsRow("Rules") {
                    HStack(spacing: 8) {
                        TextField(localized("Name"), text: $manager.newSiteRuleName)
                            .textFieldStyle(.roundedBorder)
                        TextField("host.com", text: $manager.newSiteRuleHost)
                            .textFieldStyle(.roundedBorder)
                        iconButton("plus", help: "Save Site Rule") {
                            manager.addSiteRule()
                        }
                    }
                }

                settingsRow("Address Pattern") {
                    TextField(localized("/path/* or /view?id=*"), text: $manager.newSiteRuleURLPattern)
                        .textFieldStyle(.roundedBorder)
                }

                settingsRow("Command") {
                    TextField(localized("Command {url} {output}"), text: $manager.newSiteRuleCommand)
                        .textFieldStyle(.roundedBorder)
                }

                settingsRow("Headers") {
                    HStack(spacing: 8) {
                        TextField("referer {url}", text: $manager.newSiteRuleReferer)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("User Agent"), text: $manager.newSiteRuleUserAgent)
                            .textFieldStyle(.roundedBorder)
                    }
                }

                settingsRow("Archive") {
                    Picker("", selection: $manager.newSiteRuleArchiveMode) {
                        ForEach(SiteArchiveMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 130, alignment: .trailing)
                }

                settingsRow("Delete Original After Archiving") {
                    settingsSwitch(
                        "Delete Original After Archiving",
                        isOn: $manager.newSiteRuleDeleteOriginalAfterArchiving
                    )
                    .disabled(!manager.newSiteRuleArchiveMode.archives)
                }

                if manager.siteRules.isEmpty {
                    Text(localized("No site rules"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    List {
                        ForEach(manager.siteRules) { rule in
                            SiteRuleRow(rule: rule) { enabled in
                                manager.setSiteRuleEnabled(rule, enabled: enabled)
                            } remove: {
                                manager.removeSiteRule(rule)
                            }
                        }
                    }
                    .listStyle(.inset)
                    .frame(minHeight: 120)
                }
            }
        }
    }

    private var advancedSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Notifications", systemImage: "bell") {
                settingsRow("Task Notifications") {
                    settingsSwitch("Task Notifications", isOn: Binding(
                        get: { manager.notifyWhenJobCompletes },
                        set: { manager.setNotifyWhenJobCompletes($0) }
                    ))
                    .accessibilityIdentifier("settings.notify-job")
                }

                settingsRow("Queue Completion Notification") {
                    settingsSwitch("Queue Completion Notification", isOn: Binding(
                        get: { manager.notifyWhenQueueCompletes },
                        set: { manager.setNotifyWhenQueueCompletes($0) }
                    ))
                    .accessibilityIdentifier("settings.notify-queue")
                }

                settingsRow("Task Completion Sound") {
                    settingsSwitch("Task Completion Sound", isOn: Binding(
                        get: { manager.playSoundWhenJobCompletes },
                        set: { manager.setPlaySoundWhenJobCompletes($0) }
                    ))
                    .accessibilityIdentifier("settings.sound-job")
                }

                settingsRow("Clipboard Add Sound") {
                    settingsSwitch("Clipboard Add Sound", isOn: Binding(
                        get: { manager.playSoundOnClipboardAdd },
                        set: { manager.setPlaySoundOnClipboardAdd($0) }
                    ))
                    .accessibilityIdentifier("settings.sound-clipboard")
                }

                settingsRow("After Completion") {
                    Picker("", selection: Binding(
                        get: { manager.queueCompletionAction },
                        set: { manager.setQueueCompletionAction($0) }
                    )) {
                        ForEach(QueueCompletionAction.allCases, id: \.self) { action in
                            Text(action.label).tag(action)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 170, alignment: .trailing)
                }
            }

            settingsSection("Automation", systemImage: "bolt") {
                settingsRow("Monitor Clipboard") {
                    settingsSwitch("Monitor Clipboard", isOn: Binding(
                        get: { manager.clipboardMonitorEnabled },
                        set: { manager.setClipboardMonitorEnabled($0) }
                    ))
                    .accessibilityIdentifier("settings.clipboard-monitor")
                }

                settingsRow("Start Immediately When Pasted") {
                    settingsSwitch("Start Immediately When Pasted", isOn: Binding(
                        get: { manager.startDownloadsOnPaste },
                        set: { manager.setStartDownloadsOnPaste($0) }
                    ))
                    .accessibilityIdentifier("settings.start-on-paste")
                    .help(AppLocalization.text(
                        "Press Command-V in the main window to add clipboard URLs and start the queue",
                        language: manager.interfaceLanguage
                    ))
                }

                settingsRow("Auto-remove Hook") {
                    HStack(spacing: 8) {
                        TextField("auto-remove hook {url} {output}", text: $manager.autoRemoveHookCommand)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save Auto-remove Hook") {
                            manager.saveAutoRemoveHookCommand()
                        }
                    }
                }

                settingsRow("Hook Status") {
                    Text(localizedStatus(manager.autoRemoveHookStatus))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                settingsRow("Shortcuts") {
                    HStack(spacing: 10) {
                        Button {
                            manager.openShortcutSettings()
                        } label: {
                            Label(localized("Edit"), systemImage: "keyboard")
                        }
                        Text(localizedStatus(manager.shortcutSummary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                settingsRow("Floating Monitor") {
                    HStack(spacing: 10) {
                        settingsSwitch("Show Floating Monitor", isOn: Binding(
                            get: { manager.showingFloatingMonitor },
                            set: { $0 ? manager.openFloatingMonitor() : manager.closeFloatingMonitor() }
                        ))
                        .help(AppLocalization.text("Show Floating Monitor", language: manager.interfaceLanguage))

                        Slider(value: Binding(
                            get: { manager.floatingMonitorOpacity },
                            set: { manager.setFloatingMonitorOpacity($0) }
                        ), in: 0.45...1)
                        .frame(maxWidth: 150)
                        .help(AppLocalization.text("Floating Monitor Opacity", language: manager.interfaceLanguage))

                        Text(manager.floatingMonitorOpacityPercentText)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 38, alignment: .trailing)
                    }
                }
            }

            settingsSection("External Tools", systemImage: "terminal") {
                settingsRow("Status") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            if manager.isInstallingExternalTools {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(localizedStatus(manager.externalToolInstallStatus))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Text(localizedStatus(manager.externalToolAvailabilitySummary))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                settingsRow("yt-dlp") {
                    HStack(spacing: 8) {
                        TextField(localized("yt-dlp Path"), text: $manager.ytdlpPath)
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.ytdlp)
                        iconButton("square.and.arrow.down", help: "Install or Update yt-dlp") {
                            manager.installManagedExternalTool(.ytdlp)
                        }
                        .disabled(manager.isInstallingExternalTools)
                    }
                }

                settingsRow("Deno") {
                    HStack(spacing: 8) {
                        TextField(localized("Deno Path"), text: $manager.denoPath)
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.deno)
                        iconButton("square.and.arrow.down", help: "Install or Update Deno") {
                            manager.installManagedExternalTool(.deno)
                        }
                        .disabled(manager.isInstallingExternalTools)
                    }
                }

                settingsRow("ffmpeg") {
                    HStack(spacing: 8) {
                        TextField(localized("ffmpeg Path"), text: $manager.ffmpegPath)
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.ffmpeg)
                        iconButton("square.and.arrow.down", help: "Install or Update FFmpeg and ffprobe") {
                            manager.installManagedExternalTool(.ffmpeg)
                        }
                        .disabled(manager.isInstallingExternalTools)
                    }
                }

                settingsRow("aria2c") {
                    HStack(spacing: 8) {
                        TextField(localized("aria2c Path"), text: $manager.aria2Path)
                            .textFieldStyle(.roundedBorder)
                        toolAvailabilityIcon(.aria2c)
                        iconButton("arrow.clockwise", help: "Restore Bundled aria2c") {
                            manager.installManagedExternalTool(.aria2c)
                        }
                        .disabled(manager.isInstallingExternalTools)
                    }
                }

                settingsRow("Manage") {
                    HStack(spacing: 10) {
                        Button {
                            manager.installAllManagedExternalTools()
                        } label: {
                            Label(localized("Install All"), systemImage: "square.and.arrow.down")
                        }
                        .disabled(manager.isInstallingExternalTools)

                        iconButton("checkmark", help: "Save External Tool Paths") {
                            manager.saveExternalToolPaths()
                        }

                        if manager.isInstallingExternalTools {
                            iconButton("xmark", help: "Cancel Tool Installation") {
                                manager.cancelManagedExternalToolInstallation()
                            }
                        }

                        iconButton("folder", help: "Show Managed Tools Folder") {
                            manager.revealManagedExternalTools()
                        }

                        iconButton("trash", help: "Remove Downloaded Managed Tools") {
                            manager.removeManagedExternalTools()
                        }
                        .disabled(manager.isInstallingExternalTools)
                    }
                }
            }

            settingsSection("ffmpeg", systemImage: "wand.and.stars") {
                settingsRow("Enable Transcoding") {
                    settingsSwitch("Enable Transcoding", isOn: $manager.ffmpegTranscodeEnabled)
                }

                settingsRow("Codec") {
                    HStack(spacing: 8) {
                        TextField(localized("Video Codec"), text: $manager.ffmpegVideoCodec)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("Audio Codec"), text: $manager.ffmpegAudioCodec)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(!manager.ffmpegTranscodeEnabled)
                }

                settingsRow("Quality") {
                    HStack(spacing: 8) {
                        TextField(localized("Video Bitrate"), text: $manager.ffmpegVideoBitrate)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("Audio Bitrate"), text: $manager.ffmpegAudioBitrate)
                            .textFieldStyle(.roundedBorder)
                    }
                    .disabled(!manager.ffmpegTranscodeEnabled)
                }

                settingsRow("Preset") {
                    HStack(spacing: 8) {
                        TextField("CRF", text: $manager.ffmpegCRF)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("Preset"), text: $manager.ffmpegPreset)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save FFmpeg Transcoding Options") {
                            manager.saveFFmpegTranscodeOptions()
                        }
                    }
                    .disabled(!manager.ffmpegTranscodeEnabled)
                }
            }
        }
    }

    private var hitomiSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Hitomi", systemImage: "photo.on.rectangle") {
                settingsRow("Prefer WebP") {
                    settingsSwitch("Prefer WebP", isOn: Binding(
                        get: { manager.preferWebP },
                        set: { manager.setPreferWebP($0) }
                    ))
                }

                settingsRow("Save Info TXT") {
                    settingsSwitch("Save Info TXT", isOn: Binding(
                        get: { manager.saveHitomiGalleryInfoText },
                        set: { manager.setSaveHitomiGalleryInfoText($0) }
                    ))
                }

                settingsRow("E-Hentai Source") {
                    Picker("", selection: Binding(
                        get: { manager.eHentaiSourceMode },
                        set: { manager.setEHentaiSourceMode($0) }
                    )) {
                        ForEach(EHentaiSourceMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .fixedSize(horizontal: true, vertical: false)
                    .help(manager.eHentaiSourceMode.helpText)
                    .accessibilityLabel(AppLocalization.text("E-Hentai Source", language: manager.interfaceLanguage))
                    .accessibilityIdentifier("settings.ehentai-source-mode")
                }

                settingsRow("Prefer Original Size") {
                    settingsSwitch("Prefer Original Size", isOn: Binding(
                        get: { manager.preferOriginalEHentaiImages },
                        set: { manager.setPreferOriginalEHentaiImages($0) }
                    ))
                    .help(AppLocalization.text(
                        "Use original-size E-Hentai and ExHentai files when available",
                        language: manager.interfaceLanguage
                    ))
                }

                settingsRow("Use Japanese title when available") {
                    settingsSwitch("Use Japanese title when available", isOn: Binding(
                        get: { manager.preferJapaneseEHentaiTitle },
                        set: { manager.setPreferJapaneseEHentaiTitle($0) }
                    ))
                    .help(AppLocalization.text(
                        "Prefer Japanese titles for E-Hentai and ExHentai save names when available",
                        language: manager.interfaceLanguage
                    ))
                    .accessibilityLabel(AppLocalization.text(
                        "Use Japanese title when available",
                        language: manager.interfaceLanguage
                    ))
                    .accessibilityIdentifier("settings.ehentai-japanese-title")
                }

                settingsRow("Excluded Tags") {
                    HStack(spacing: 8) {
                        TextField("female:example, male:example", text: $manager.hitomiExcludedTagsText)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save Hitomi Excluded Tags") {
                            manager.saveHitomiExcludedTags()
                        }
                        iconButton("xmark.circle", help: "Clear Hitomi Excluded Tags") {
                            manager.clearHitomiExcludedTags()
                        }
                        .disabled(manager.hitomiExcludedTagsText.trimmed.isEmpty)
                    }
                }

                settingsRow("Tag Translation") {
                    HStack(spacing: 8) {
                        TextField(localized("Tag"), text: $manager.searchTagTranslationInput)
                            .textFieldStyle(.roundedBorder)
                        iconButton("arrow.triangle.2.circlepath", help: "Translate Search Tags") {
                            manager.translateSearchTagInput()
                        }
                        iconButton("plus", help: "Insert Translated Tags") {
                            manager.insertTranslatedSearchTag()
                        }
                        iconButton("arrow.left.arrow.right", help: "Replace Search Terms with Translated Tags") {
                            manager.replaceSearchQueryWithTranslatedTag()
                        }
                    }
                }

                if !manager.searchTagTranslationOutput.trimmed.isEmpty {
                    Text(manager.searchTagTranslationOutput)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var pixivSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Pixiv", systemImage: "p.circle") {
                settingsRow("Ugoira") {
                    HStack(spacing: 8) {
                        Picker("", selection: $manager.pixivUgoiraFileFormat) {
                            ForEach(PixivUgoiraFileFormat.allCases, id: \.self) { format in
                                Text(format.label).tag(format)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 130, alignment: .trailing)
                        iconButton("checkmark", help: "Save Pixiv Ugoira Format") {
                            manager.savePixivUgoiraFileFormat()
                        }
                    }
                }
                settingsRow("GIF palette dithering", detail: "Reduce GIF color banding") {
                    settingsSwitch("GIF palette dithering", isOn: $manager.pixivUgoiraDither)
                        .disabled(manager.pixivUgoiraFileFormat != .gif)
                }
                settingsRow("Quality") {
                    HStack(spacing: 10) {
                        Slider(
                            value: Binding(
                                get: { Double(manager.pixivUgoiraQuality) },
                                set: { manager.pixivUgoiraQuality = Int($0.rounded()) }
                            ),
                            in: 1...100
                        )
                        .frame(minWidth: 180, idealWidth: 320, maxWidth: 420)
                        .accessibilityLabel(localized("Quality"))
                        .accessibilityValue("\(manager.pixivUgoiraQuality)")
                        .accessibilityIdentifier("settings.pixiv-quality")
                        Text("\(manager.pixivUgoiraQuality)")
                            .monospacedDigit()
                            .frame(width: 34, alignment: .trailing)
                    }
                    .frame(maxWidth: 464, alignment: .trailing)
                    .disabled(!manager.pixivUgoiraFileFormat.requiresFFmpeg)
                }
            }
        }
    }

    private var kemonoFriendsSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Kemono friends", systemImage: "network") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Archive Addresses"))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    pawchiveSiteAddressList
                }

                settingsRow("PSD Originals") {
                    trailingSettingsControl {
                        settingsSwitch("Download PSD Originals", isOn: Binding(
                            get: { manager.pawchiveDownloadLargeOriginalFiles },
                            set: { manager.setPawchiveDownloadLargeOriginalFiles($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-large-originals")
                    }
                }
            }

            settingsSection("File Types to Download", systemImage: "line.3.horizontal.decrease.circle") {
                settingsRow("Image Files", detail: "JPEG, PNG, GIF") {
                    trailingSettingsControl {
                        settingsSwitch("Image Files", isOn: Binding(
                            get: { manager.pawchiveDownloadImages },
                            set: { manager.setPawchiveDownloadImages($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-images")
                    }
                }

                settingsRow("Video Files", detail: "MP4, MKV") {
                    trailingSettingsControl {
                        settingsSwitch("Video Files", isOn: Binding(
                            get: { manager.pawchiveDownloadVideos },
                            set: { manager.setPawchiveDownloadVideos($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-videos")
                    }
                }

                settingsRow("HTML Files", detail: "Save posts as HTML") {
                    trailingSettingsControl {
                        settingsSwitch("HTML Files", isOn: Binding(
                            get: { manager.pawchiveDownloadHTML },
                            set: { manager.setPawchiveDownloadHTML($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-html")
                    }
                }

                settingsRow("Other Files", detail: "Archives and attachments") {
                    trailingSettingsControl {
                        settingsSwitch("Other Files", isOn: Binding(
                            get: { manager.pawchiveDownloadOtherFiles },
                            set: { manager.setPawchiveDownloadOtherFiles($0) }
                        ))
                        .accessibilityIdentifier("settings.pawchive-file-other")
                    }
                }
            }
        }
    }

    private var pawchiveSiteAddressList: some View {
        VStack(spacing: 0) {
            if manager.pawchiveSiteAddresses.isEmpty && !manager.isAddingPawchiveSiteAddress {
                Text(localized("No addresses added"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 44)
            } else {
                ForEach(Array(manager.pawchiveSiteAddresses.enumerated()), id: \.element) { index, address in
                    if index > 0 {
                        Divider()
                            .padding(.leading, 38)
                    }

                    Button {
                        manager.pawchiveSelectedSiteAddress = address
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "globe")
                                .foregroundStyle(.secondary)
                                .frame(width: 18)
                            Text(address)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .background(
                            manager.pawchiveSelectedSiteAddress == address
                                ? Color.accentColor.opacity(0.18)
                                : Color.clear
                        )
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(address)
                    .accessibilityIdentifier("settings.pawchive-address.row")
                }

                if manager.isAddingPawchiveSiteAddress {
                    if !manager.pawchiveSiteAddresses.isEmpty {
                        Divider()
                            .padding(.leading, 38)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "globe")
                            .foregroundStyle(.secondary)
                            .frame(width: 18)
                        TextField(
                            localized("Enter an archive address"),
                            text: $manager.pawchiveSiteAddressDraft
                        )
                        .textFieldStyle(.plain)
                        .onSubmit(commitPawchiveSiteAddress)
                        .accessibilityIdentifier("settings.pawchive-address.input")

                        iconButton("checkmark", help: "Add archive address") {
                            commitPawchiveSiteAddress()
                        }
                        .disabled(manager.pawchiveSiteAddressDraft.trimmed.isEmpty)

                        iconButton("xmark", help: "Cancel") {
                            cancelAddingPawchiveSiteAddress()
                        }
                    }
                    .padding(.horizontal, 10)
                    .frame(minHeight: 40)
                }
            }

            Divider()

            HStack(spacing: 0) {
                Button {
                    beginAddingPawchiveSiteAddress()
                } label: {
                    Image(systemName: "plus")
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(manager.isAddingPawchiveSiteAddress)
                .help(localized("Add archive address"))
                .accessibilityIdentifier("settings.pawchive-address.add")

                Divider()
                    .frame(height: 18)

                Button {
                    removeSelectedPawchiveSiteAddress()
                } label: {
                    Image(systemName: "minus")
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(manager.pawchiveSelectedSiteAddress.isEmpty)
                .help(localized("Remove archive address"))
                .accessibilityIdentifier("settings.pawchive-address.remove")

                Spacer(minLength: 8)

                Button {
                    manager.resetPawchiveSiteAddresses()
                    manager.pawchiveSelectedSiteAddress = manager.pawchiveSiteAddresses.first ?? ""
                    cancelAddingPawchiveSiteAddress()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 32, height: 26)
                }
                .buttonStyle(.plain)
                .disabled(manager.pawchiveSiteAddresses == PawchiveResolver.defaultSiteAddresses)
                .help(localized("Restore default archive addresses"))
                .accessibilityIdentifier("settings.pawchive-address.reset")
            }
            .padding(.horizontal, 4)
        }
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        }
        .frame(maxWidth: .infinity)
    }

    private func beginAddingPawchiveSiteAddress() {
        manager.pawchiveSiteAddressDraft = ""
        manager.isAddingPawchiveSiteAddress = true
    }

    private func commitPawchiveSiteAddress() {
        let normalized = PawchiveResolver.normalizedSiteAddress(manager.pawchiveSiteAddressDraft)
        manager.addPawchiveSiteAddress()
        guard let normalized,
              manager.pawchiveSiteAddresses.contains(where: {
                  $0.caseInsensitiveCompare(normalized) == .orderedSame
              }) else {
            return
        }
        manager.pawchiveSelectedSiteAddress = normalized
        manager.isAddingPawchiveSiteAddress = false
    }

    private func cancelAddingPawchiveSiteAddress() {
        manager.pawchiveSiteAddressDraft = ""
        manager.isAddingPawchiveSiteAddress = false
    }

    private func removeSelectedPawchiveSiteAddress() {
        let selected = manager.pawchiveSelectedSiteAddress
        guard !selected.isEmpty else { return }
        manager.removePawchiveSiteAddress(selected)
        manager.pawchiveSelectedSiteAddress = manager.pawchiveSiteAddresses.first ?? ""
    }

    private var youtubeSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("YouTube", systemImage: "play.rectangle") {
                settingsRow("Language") {
                    HStack(spacing: 8) {
                        TextField(localized("Language"), text: $manager.youtubePreferredLanguage)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save YouTube Language") {
                            manager.saveYouTubePreferredLanguage()
                        }
                    }
                }

                settingsRow("Download Thumbnail") {
                    trailingSettingsControl {
                        settingsSwitch("Download Thumbnail", isOn: Binding(
                            get: { manager.youtubeDownloadThumbnail },
                            set: { manager.setYouTubeDownloadThumbnail($0) }
                        ))
                    }
                }

                settingsRow("Reverse Playlist", detail: "Last item first") {
                    trailingSettingsControl {
                        settingsSwitch("Reverse Playlist", isOn: Binding(
                            get: { manager.youtubeReversePlaylist },
                            set: { manager.setYouTubeReversePlaylist($0) }
                        ))
                    }
                }

                settingsRow("Use Upload Date as File Modification Date") {
                    trailingSettingsControl {
                        settingsSwitch("Use Upload Date as File Modification Date", isOn: Binding(
                            get: { manager.youtubeUseUploadDateForFileModificationTime },
                            set: { manager.setYouTubeUseUploadDateForFileModificationTime($0) }
                        ))
                        .accessibilityLabel(AppLocalization.text(
                            "Set file modification date to upload date",
                            language: manager.interfaceLanguage
                        ))
                        .accessibilityIdentifier("settings.youtube-upload-date-mtime")
                    }
                }

                settingsRow("Embed Chapters") {
                    trailingSettingsControl {
                        settingsSwitch("Embed Chapters", isOn: Binding(
                            get: { manager.youtubeEmbedChapters },
                            set: { manager.setYouTubeEmbedChapters($0) }
                        ))
                    }
                }

                settingsRow("Enhanced Bitrate") {
                    trailingSettingsControl {
                        settingsSwitch("Enhanced Bitrate", isOn: Binding(
                            get: { manager.youtubePreferEnhancedBitrate },
                            set: { manager.setYouTubePreferEnhancedBitrate($0) }
                        ))
                    }
                }

                settingsRow("Resolution") {
                    HStack(spacing: 8) {
                        TextField("1080p", text: $manager.youtubePreferredResolution)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save YouTube Resolution") {
                            manager.saveYouTubePreferredResolution()
                        }
                    }
                }

                settingsRow("Audio") {
                    HStack(spacing: 8) {
                        TextField(localized("Audio Language"), text: $manager.youtubePreferredAudioLanguage)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save YouTube Audio Tracks") {
                            manager.saveYouTubePreferredAudioLanguage()
                        }
                    }
                }

                settingsRow("Subtitles", detail: "Include auto-generated subtitles") {
                    trailingSettingsControl {
                        HStack(spacing: 8) {
                            settingsSwitch("Include automatically generated subtitles", isOn: Binding(
                                get: { manager.youtubeDownloadAutoSubtitles },
                                set: { manager.setYouTubeDownloadAutoSubtitles($0) }
                            ))
                            TextField("all", text: $manager.youtubeSubtitleLanguages)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 90)
                            iconButton("checkmark", help: "Save YouTube Subtitle Settings") {
                                manager.saveYouTubeSubtitleSettings()
                            }
                        }
                    }
                }

                settingsRow("Codec Priority") {
                    trailingSettingsControl {
                        YouTubeCodecPriorityMenu(manager: manager)
                    }
                }
            }
        }
    }

    private var socialSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("Browser Login", systemImage: "person.crop.circle.badge.key") {
                settingsRow("Cookies") {
                    HStack(spacing: 8) {
                        iconButton("person.crop.circle.badge.key", help: "Open Login Browser") {
                            manager.openLoginBrowser()
                        }
                        iconButton("globe", help: "Import Browser Cookies") {
                            manager.importBrowserCookies()
                        }
                        cookieClearButton()
                        Text(localizedStatus(manager.cookieSummary))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            settingsSection("Instagram", systemImage: "camera") {
                settingsRow("Include active stories") {
                    settingsSwitch("Include active stories", isOn: Binding(
                        get: { manager.instagramIncludeStories },
                        set: { manager.setInstagramIncludeStories($0) }
                    ))
                }
            }

            settingsSection("SOOP / Afreeca", systemImage: "antenna.radiowaves.left.and.right") {
                settingsRow("Resolution") {
                    HStack(spacing: 8) {
                        TextField("720p", text: $manager.soopPreferredResolution)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save SOOP/Afreeca Resolution") {
                            manager.saveSOOPPreferredResolution()
                        }
                    }
                }
            }

            settingsSection("Search Tools", systemImage: "text.magnifyingglass") {
                settingsRow("Searcher") {
                    HStack(spacing: 8) {
                        Button {
                            manager.showingSearcher = true
                        } label: {
                            Label(localized("Open"), systemImage: "text.magnifyingglass")
                        }
                        Button {
                            manager.showingHistoryWindow = true
                        } label: {
                            Label(localized("History"), systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
        }
    }

    private var torrentSettings: some View {
        VStack(alignment: .leading, spacing: 18) {
            settingsSection("aria2", systemImage: "arrow.down.circle") {
                settingsRow("Files") {
                    HStack(spacing: 8) {
                        TextField(localized("Files 1,3-5"), text: $manager.aria2SelectedFiles)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("Seed time (min)"), text: $manager.aria2SeedTimeMinutes)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                        iconButton("list.bullet.rectangle", help: "Show Torrent File List") {
                            manager.previewAria2Files()
                        }
                    }
                }

                settingsRow("Speed Limits") {
                    HStack(spacing: 8) {
                        TextField(localized("Down 2M"), text: $manager.aria2MaxDownloadLimit)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("Up 512K"), text: $manager.aria2MaxUploadLimit)
                            .textFieldStyle(.roundedBorder)
                        TextField(localized("Seed ratio"), text: $manager.aria2SeedRatio)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 90)
                    }
                }

                settingsRow("Anonymous Mode") {
                    settingsSwitch("Anonymous Mode", isOn: $manager.aria2AnonymousMode)
                }

                settingsRow("Trackers") {
                    HStack(spacing: 8) {
                        TextField("udp://tracker.example/announce", text: $manager.aria2Trackers)
                            .textFieldStyle(.roundedBorder)
                        iconButton("checkmark", help: "Save aria2 Options") {
                            manager.saveAria2Options()
                        }
                    }
                }

                if !manager.aria2FileListSummary.isEmpty {
                    Text(localizedStatus(manager.aria2FileListSummary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                if !manager.aria2PeerSummary.isEmpty {
                    Text(localizedStatus(manager.aria2PeerSummary))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)

                    ForEach(Array(manager.aria2PeerEntries.prefix(6))) { peer in
                        Text(peer.summary)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label {
                Text(AppLocalization.text(title, language: manager.interfaceLanguage))
            } icon: {
                Image(systemName: systemImage)
            }
                .font(.system(size: 15, weight: .semibold))

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsGroup<Content: View>(
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Divider()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsRow<Content: View>(
        _ title: String,
        detail: String? = nil,
        detailPlacement: SettingsRowDetailPlacement = .label,
        @ViewBuilder control: () -> Content
    ) -> some View {
        let localizedTitle = AppLocalization.text(title, language: manager.interfaceLanguage)
        let localizedDetail = detail.map {
            AppLocalization.text($0, language: manager.interfaceLanguage)
        }
        let hasInlineDetail = detailPlacement == .label && localizedDetail != nil

        return VStack(
            alignment: .leading,
            spacing: detailPlacement == .fullWidth && localizedDetail != nil ? 5 : 0
        ) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 14) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedTitle)
                            .font(.system(
                                size: NSFont.systemFontSize + 1,
                                weight: .semibold
                            ))
                            .fixedSize(horizontal: false, vertical: true)

                        if detailPlacement == .label, let localizedDetail {
                            Text(localizedDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(localizedDetail)
                        }
                    }
                    .frame(
                        minHeight: hasInlineDetail ? nil : 28,
                        alignment: .leading
                    )
                    .frame(
                        minWidth: 132,
                        idealWidth: 132,
                        maxWidth: 220,
                        alignment: .leading
                    )

                    control()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .layoutPriority(1)
                }
                .frame(minWidth: 340, maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(localizedTitle)
                            .font(.system(
                                size: NSFont.systemFontSize + 1,
                                weight: .semibold
                            ))
                            .fixedSize(horizontal: false, vertical: true)

                        if detailPlacement == .label, let localizedDetail {
                            Text(localizedDetail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .help(localizedDetail)
                        }
                    }
                    .frame(
                        minHeight: hasInlineDetail ? nil : 28,
                        alignment: .leading
                    )

                    control()
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            if detailPlacement == .fullWidth, let localizedDetail {
                Text(localizedDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .help(localizedDetail)
            }
        }
        .padding(.vertical, 2)
        .frame(minHeight: 34, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func settingsSwitch(
        _ accessibilityTitle: String,
        isOn: Binding<Bool>
    ) -> some View {
        Toggle("", isOn: isOn)
            .labelsHidden()
            .toggleStyle(.switch)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel(AppLocalization.text(
                accessibilityTitle,
                language: manager.interfaceLanguage
            ))
    }

    private func toolAvailabilityIcon(_ kind: ExternalToolKind) -> some View {
        let available = manager.isExternalToolAvailable(kind)
        let path = manager.resolvedExternalToolPath(kind)
        return Image(systemName: available ? "checkmark.circle.fill" : "exclamationmark.circle")
            .foregroundColor(available ? .green : .secondary)
            .help(
                available
                    ? AppLocalization.format(
                        "In use: %@",
                        language: manager.interfaceLanguage,
                        path
                    )
                    : AppLocalization.format(
                        "%@ is unavailable",
                        language: manager.interfaceLanguage,
                        kind.displayName
                    )
            )
    }

    private func iconButton(
        _ systemImage: String,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
        }
        .help(AppLocalization.text(help, language: manager.interfaceLanguage))
    }

    private func cookieClearButton() -> some View {
        Button {
            manager.clearCookies()
        } label: {
            Label(localized("Delete Cookies and Login Sessions"), systemImage: "trash")
                .labelStyle(.iconOnly)
        }
        .disabled(manager.isClearingCookies)
        .help(AppLocalization.text(
            "Delete app cookies and embedded-browser login sessions",
            language: manager.interfaceLanguage
        ))
        .accessibilityIdentifier("settings.clear-cookies")
    }
}

struct SettingsCategorySidebarButton: View {
    let category: SettingsWindowCategory
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                SettingsCategoryIcon(category: category, size: 17)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? .primary : .secondary)

                Text(category.label)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.16) : Color.primary.opacity(0.001))
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .overlay {
            Rectangle()
                .fill(Color.primary.opacity(0.001))
                .contentShape(Rectangle())
                .onTapGesture(perform: action)
                .accessibilityHidden(true)
        }
        .help(category.label)
        .accessibilityLabel(category.label)
        .accessibilityHint(category.detail)
        .accessibilityIdentifier("settings.category.\(category.rawValue)")
    }
}

struct SettingsCategoryIcon: View {
    let category: SettingsWindowCategory
    let size: CGFloat

    @ViewBuilder
    var body: some View {
        if let letter = category.iconLetter {
            ZStack {
                Circle()
                    .strokeBorder(lineWidth: max(1, size * 0.075))
                Text(letter)
                    .font(.system(size: size * 0.64, weight: .semibold, design: .rounded))
            }
            .frame(width: size, height: size)
        } else {
            Image(systemName: category.systemImage)
                .font(.system(size: size))
        }
    }
}

struct ShortcutSettingsView: View {
    @ObservedObject var manager: DownloadManager

    private var selectedCommand: AppShortcutCommand {
        manager.shortcutEditorCommand
    }

    var body: some View {
        VStack(spacing: 0) {
            header

            HStack(spacing: 0) {
                commandList
                    .frame(width: 270)

                Divider()

                editor
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(width: 760, height: 540)
        .onAppear {
            manager.beginEditingShortcut(manager.shortcutEditorCommand)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Shortcuts", systemImage: "keyboard")
                .font(.headline)

            Spacer()

            Button {
                manager.showingShortcutSettings = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close shortcut settings")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var commandList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Commands")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(AppShortcutCommand.allCases) { command in
                        ShortcutCommandRow(
                            command: command,
                            shortcutText: manager.shortcutDisplay(for: command),
                            isSelected: selectedCommand == command
                        ) {
                            manager.beginEditingShortcut(command)
                        }
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }
        }
        .background(.bar)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCommand.label)
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(selectedCommand.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 18) {
                labeledShortcutValue("Current", manager.shortcutDisplay(for: selectedCommand))
                labeledShortcutValue("Default", selectedCommand.defaultShortcut.displayText)
                labeledShortcutValue("Draft", manager.shortcutEditorDraft.displayText)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recorder")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ShortcutRecorderField(
                    shortcutText: manager.shortcutEditorDraft.displayText,
                    hasConflict: manager.shortcutEditorConflictCommand != nil
                ) { event in
                    manager.recordShortcutDraft(from: event)
                } clear: {
                    manager.clearShortcutDraft()
                }
                .frame(width: 280, height: 46)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Key")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                Picker("", selection: Binding(
                    get: { manager.shortcutEditorDraft.key },
                    set: { manager.setShortcutDraftKey($0) }
                )) {
                    ForEach(AppShortcutKey.allCases) { key in
                        Text(key.label).tag(key)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Modifiers")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                HStack(spacing: 12) {
                    ForEach(AppShortcutModifier.displayOrder) { modifier in
                        Toggle(modifier.label, isOn: Binding(
                            get: { manager.shortcutEditorDraft.modifiers.contains(modifier) },
                            set: { manager.setShortcutDraftModifier(modifier, enabled: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .disabled(manager.shortcutEditorDraft.key == .none)
                    }
                }
            }

            if let conflict = manager.shortcutEditorConflictCommand {
                Label("Conflicts with \(conflict.label)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if !manager.shortcutEditorMessage.isEmpty {
                Text(manager.shortcutEditorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Choose None to remove a shortcut from a command.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 10) {
                Button {
                    manager.resetShortcutDraft()
                } label: {
                    Label("Default", systemImage: "arrow.counterclockwise")
                }

                Button {
                    manager.resetAllShortcuts()
                } label: {
                    Label("Reset All", systemImage: "gobackward")
                }

                Spacer()

                Button("Apply") {
                    manager.saveShortcutDraft()
                }
                .disabled(manager.shortcutEditorConflictCommand != nil)
                .keyboardShortcut(.defaultAction)

                Button("Done") {
                    manager.showingShortcutSettings = false
                }
            }
        }
        .padding(18)
    }

    private func labeledShortcutValue(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .lineLimit(1)
                .frame(minWidth: 86, alignment: .leading)
        }
    }
}

struct ShortcutRecorderField: NSViewRepresentable {
    var shortcutText: String
    var hasConflict: Bool
    var record: (NSEvent) -> Void
    var clear: () -> Void

    func makeNSView(context: Context) -> ShortcutRecorderNSView {
        let view = ShortcutRecorderNSView()
        view.onRecord = record
        view.onClear = clear
        return view
    }

    func updateNSView(_ nsView: ShortcutRecorderNSView, context: Context) {
        nsView.shortcutText = shortcutText
        nsView.hasConflict = hasConflict
        nsView.onRecord = record
        nsView.onClear = clear
        nsView.needsDisplay = true
    }
}

final class ShortcutRecorderNSView: NSView {
    var shortcutText = "None"
    var hasConflict = false
    var onRecord: ((NSEvent) -> Void)?
    var onClear: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        needsDisplay = true
    }

    override func keyDown(with event: NSEvent) {
        onRecord?(event)
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        needsDisplay = true
        return super.resignFirstResponder()
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let clearItem = NSMenuItem(
            title: AppLocalization.text("Clear Shortcut"),
            action: #selector(clearShortcut),
            keyEquivalent: ""
        )
        clearItem.target = self
        menu.addItem(clearItem)
        return menu
    }

    @objc private func clearShortcut() {
        onClear?()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let focused = window?.firstResponder === self
        let bounds = bounds.insetBy(dx: 1, dy: 1)
        let radius: CGFloat = 7
        let background = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        NSColor.controlBackgroundColor.setFill()
        background.fill()

        let strokeColor: NSColor
        if hasConflict {
            strokeColor = .systemOrange
        } else if focused {
            strokeColor = .controlAccentColor
        } else {
            strokeColor = .separatorColor
        }
        strokeColor.setStroke()
        background.lineWidth = focused ? 2 : 1
        background.stroke()

        let text = focused ? "Recording: \(shortcutText)" : shortcutText
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 15, weight: .semibold),
            .foregroundColor: hasConflict ? NSColor.systemOrange : NSColor.labelColor,
            .paragraphStyle: paragraph
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        let textRect = NSRect(x: bounds.minX + 10, y: bounds.midY - 10, width: bounds.width - 20, height: 22)
        attributed.draw(in: textRect)
    }
}

struct ShortcutCommandRow: View {
    let command: AppShortcutCommand
    let shortcutText: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(command.label)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                    Text(command.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                Text(shortcutText)
                    .font(.caption.monospaced())
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }
}

struct DuplicateImageFinderWindowView: View {
    @ObservedObject var manager: DownloadManager

    private var duplicateFileCount: Int {
        manager.duplicateImageGroups.reduce(0) { $0 + max(0, $1.files.count - 1) }
    }

    private var selectedPathText: String {
        manager.selectedDuplicateImagePath.trimmed.isEmpty
            ? "No image selected"
            : manager.selectedDuplicateImagePath
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar

            Divider()

            VStack(spacing: 0) {
                header
                Divider()
                controls
                Divider()
                results
            }
        }
        .frame(width: 940, height: 660)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Scan Folders", systemImage: "folder")
                .font(.headline)

            HStack(spacing: 8) {
                Button {
                    manager.addDuplicateImageFolder()
                } label: {
                    Label("Add", systemImage: "folder.badge.plus")
                }
                .disabled(manager.isScanningDuplicateImages)

                Button {
                    manager.clearDuplicateImageFolders()
                } label: {
                    Image(systemName: "house")
                }
                .disabled(manager.duplicateImageFolderPaths.isEmpty || manager.isScanningDuplicateImages)
                .help("Use save folder")
            }

            if manager.duplicateImageFolderPaths.isEmpty {
                scanFolderRow(path: manager.destinationPath, isDefault: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(manager.duplicateImageFolderPaths, id: \.self) { path in
                            scanFolderRow(path: path, isDefault: false)
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            Text(manager.duplicateImageScanFolderSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .frame(width: 240, alignment: .topLeading)
        .background(.bar)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "photo.on.rectangle")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Duplicate Image Finder")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(manager.duplicateImageGroups.count) groups · \(duplicateFileCount) extra files")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                manager.showingDuplicateImageFinder = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close duplicate finder")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    manager.scanDuplicateImages()
                } label: {
                    Label(
                        manager.isScanningDuplicateImages ? "Scanning" : "Scan",
                        systemImage: manager.isScanningDuplicateImages ? "hourglass" : "arrow.clockwise"
                    )
                }
                .disabled(manager.isScanningDuplicateImages)

                Button {
                    manager.clearDuplicateImageResults()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(manager.duplicateImageGroups.isEmpty && manager.duplicateImageSummary.isEmpty)

                Button {
                    manager.openSelectedDuplicateImageFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .disabled(manager.selectedDuplicateImagePath.trimmed.isEmpty)

                Spacer()

                if manager.isScanningDuplicateImages {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 14) {
                Toggle("Thumbnails", isOn: Binding(
                    get: { manager.showDuplicateImageThumbnails },
                    set: { manager.setDuplicateImageThumbnails($0) }
                ))
                .toggleStyle(.switch)
                .disabled(manager.lowPowerMode)
                .help(manager.lowPowerMode ? "Low Power Mode hides duplicate image thumbnails" : "Show duplicate image thumbnails")

                Toggle("Exclude Same Source", isOn: Binding(
                    get: { manager.duplicateImageExcludeSameSource },
                    set: { manager.setDuplicateImageExcludeSameSource($0) }
                ))
                .toggleStyle(.switch)

                Stepper(value: Binding(
                    get: { manager.duplicateImageSimilarityPercent },
                    set: { manager.setDuplicateImageSimilarityPercent($0) }
                ), in: 80...100) {
                    Text("Similarity \(manager.duplicateImageSimilarityPercent)%")
                        .monospacedDigit()
                }
                .frame(width: 170)
            }
            .controlSize(.small)

            HStack(spacing: 8) {
                Image(systemName: "target")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text(selectedPathText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(selectedPathText)
            }

            if !manager.duplicateImageSummary.isEmpty {
                Text(manager.duplicateImageSummary)
                    .font(.caption)
                    .foregroundStyle(manager.duplicateImageSummary.lowercased().contains("failed") ? .orange : .secondary)
                    .lineLimit(2)
            }
        }
        .padding(14)
    }

    private var results: some View {
        Group {
            if manager.duplicateImageGroups.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: manager.isScanningDuplicateImages ? "hourglass" : "photo.stack")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(manager.isScanningDuplicateImages ? "Scanning images..." : "No duplicate groups")
                        .font(.headline)
                    Text(manager.isScanningDuplicateImages ? manager.duplicateImageScanFolderSummary : "Run a scan to populate duplicate image groups.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.duplicateImageGroups) { group in
                        DuplicateImageGroupRow(
                            group: group,
                            showsThumbnails: manager.effectiveDuplicateImageThumbnails,
                            selectedPath: manager.selectedDuplicateImagePath,
                            autoSelectedPath: manager.autoSelectedDuplicateImagePath,
                            select: { path in
                                manager.selectDuplicateImage(path)
                            },
                            reveal: { path in
                                manager.revealDuplicateImage(path)
                            },
                            openFolder: { path in
                                manager.openDuplicateImageFolder(path)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func scanFolderRow(path: String, isDefault: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: isDefault ? "house" : "folder")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(isDefault ? "Save Folder" : URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(path)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            if !isDefault {
                Button(role: .destructive) {
                    manager.removeDuplicateImageFolder(path)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.borderless)
                .disabled(manager.isScanningDuplicateImages)
                .help("Remove scan folder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

struct ClipboardViewerWindowView: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            HSplitView {
                editorPane
                    .frame(minWidth: 360, idealWidth: 440)

                candidatePane
                    .frame(minWidth: 360)
            }

            Divider()
            footer
        }
        .frame(width: 860, height: 600)
        .onAppear {
            manager.refreshClipboardViewer()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Clipboard Viewer")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("\(manager.clipboardViewerSource) · change \(manager.clipboardViewerChangeCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                manager.refreshClipboardViewer()
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
            }

            Button {
                manager.showingClipboardViewer = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close clipboard viewer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var editorPane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Clipboard Text")
                    .font(.headline)
                Spacer()
                Text("\(manager.clipboardViewerText.count) chars")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            TextEditor(text: Binding(
                get: { manager.clipboardViewerText },
                set: { manager.setClipboardViewerText($0) }
            ))
            .font(.system(.body, design: .monospaced))
            .scrollContentBackground(.hidden)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            }

            HStack(spacing: 8) {
                Button {
                    manager.useClipboardViewerAsInput()
                } label: {
                    Label("Use as Input", systemImage: "text.badge.plus")
                }
                .disabled(manager.clipboardViewerText.trimmed.isEmpty)

                Button {
                    manager.setClipboardViewerText("")
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(manager.clipboardViewerText.isEmpty)
                .help("Clear text")
            }
        }
        .padding(14)
    }

    private var candidatePane: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Candidate URLs")
                    .font(.headline)
                Spacer()
                Text("\(manager.clipboardViewerURLs.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            if manager.clipboardViewerURLs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "link.badge.plus")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("No URLs found")
                        .font(.headline)
                    Text("Refresh the clipboard or edit the text to inspect candidates.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(manager.clipboardViewerURLs.enumerated()), id: \.offset) { index, url in
                        ClipboardCandidateRow(index: index + 1, url: url)
                    }
                }
                .listStyle(.inset)
            }

            HStack(spacing: 8) {
                Button {
                    _ = manager.queueClipboardViewerURLs()
                } label: {
                    Label("Queue", systemImage: "plus")
                }
                .disabled(manager.clipboardViewerURLs.isEmpty)

                Button {
                    _ = manager.queueClipboardViewerURLs(start: true)
                } label: {
                    Label("Queue & Start", systemImage: "play.fill")
                }
                .disabled(manager.clipboardViewerURLs.isEmpty || manager.isRunning)
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Toggle("Watch Clipboard", isOn: Binding(
                get: { manager.clipboardMonitorEnabled },
                set: { manager.setClipboardMonitorEnabled($0) }
            ))
            .toggleStyle(.switch)

            Toggle("Sound", isOn: Binding(
                get: { manager.playSoundOnClipboardAdd },
                set: { manager.setPlaySoundOnClipboardAdd($0) }
            ))
            .toggleStyle(.switch)
            .disabled(!manager.clipboardMonitorEnabled)

            Spacer()

            if !manager.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    manager.addSummary,
                    language: manager.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct ClipboardCandidateRow: View {
    let index: Int
    let url: String

    private var hostText: String {
        URL(string: url)?.host ?? URL(fileURLWithPath: url).lastPathComponent
    }

    var body: some View {
        HStack(spacing: 8) {
            Text("\(index)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 28, alignment: .trailing)

            Image(systemName: url.lowercased().hasPrefix("file://") ? "doc" : "link")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(hostText.isEmpty ? url : hostText)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 3)
        .help(url)
    }
}

struct BrowserWindowView: View {
    @ObservedObject var manager: DownloadManager

    private var targetURL: URL? {
        manager.browserWindowTargetURL()
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 660, height: 360)
        .onAppear {
            if manager.browserWindowURLText.trimmed.isEmpty {
                manager.refreshBrowserWindowURL()
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "safari")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Browser")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text("Open a native WKWebView login browser and save cookies.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.showingBrowserWindow = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close browser helper")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("URL")
                    .font(.headline)

                HStack(spacing: 8) {
                    TextField("https://example.com/login", text: Binding(
                        get: { manager.browserWindowURLText },
                        set: { manager.setBrowserWindowURLText($0) }
                    ))
                    .textFieldStyle(.roundedBorder)

                    Button {
                        manager.refreshBrowserWindowURL()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                    .help("Use inferred URL")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                BrowserInfoRow(title: "Target", value: manager.browserWindowTargetSummary(), systemImage: "link")
                BrowserInfoRow(
                    title: "Cookies",
                    value: AppLocalization.statusText(
                        manager.cookieSummary,
                        language: manager.interfaceLanguage
                    ),
                    systemImage: "key"
                )
            }

            HStack(spacing: 8) {
                Button {
                    manager.openBrowserWindowLogin()
                } label: {
                    Label("Open Login Browser", systemImage: "person.crop.circle.badge.key")
                }
                .disabled(targetURL == nil)

                Button {
                    manager.openBrowserWindowHTTPPage()
                } label: {
                    Label("HTTP Page", systemImage: "network")
                }
                .disabled(targetURL == nil)

                Button {
                    manager.clearCookies()
                } label: {
                    Label("Delete Cookies and Login Sessions", systemImage: "trash")
                }
                .disabled(manager.isClearingCookies)
                .help(AppLocalization.text(
                    "Delete app cookies and embedded-browser login sessions",
                    language: manager.interfaceLanguage
                ))
                .accessibilityIdentifier("browser.clear-cookies")
            }

            Spacer(minLength: 0)
        }
        .padding(18)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                manager.importCookies()
            } label: {
                Label("Import Text", systemImage: "key")
            }

            Button {
                manager.importBrowserCookies()
            } label: {
                Label("Import Browser", systemImage: "globe")
            }

            Button {
                manager.importDetectedBrowserCookies()
            } label: {
                Label("Detect", systemImage: "magnifyingglass")
            }

            Spacer()

            if !manager.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    manager.addSummary,
                    language: manager.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct BrowserInfoRow: View {
    let title: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 18)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.caption)
                .lineLimit(2)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct OutputPreviewWindowView: View {
    @ObservedObject var manager: DownloadManager
    let requestClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if manager.outputPreviewIsLoading && manager.outputPreviewFiles.isEmpty {
                loadingState
            } else if manager.outputPreviewFiles.isEmpty {
                emptyState
            } else {
                GeometryReader { proxy in
                    if !OutputPreviewLayoutPolicy.usesVerticalLayout(contentWidth: proxy.size.width) {
                        HStack(spacing: 0) {
                            fileList
                                .frame(width: OutputPreviewLayoutPolicy.sidebarWidth(contentWidth: proxy.size.width))
                            Divider()
                            previewPane
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    } else {
                        VStack(spacing: 0) {
                            fileList
                                .frame(height: OutputPreviewLayoutPolicy.fileListHeight(contentHeight: proxy.size.height))
                            Divider()
                            previewPane
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onExitCommand {
            requestClose()
        }
    }

    private var header: some View {
        VStack(spacing: 7) {
            HStack(spacing: 8) {
                previewModePicker
                    .frame(minWidth: 150, idealWidth: 220, maxWidth: 250)
                Spacer()
                if manager.outputPreviewIsLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Button {
                    requestClose()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("Close preview")
                .accessibilityLabel("Close preview")
                .fixedSize()
                .zIndex(1)
            }

            previewActionRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var previewModePicker: some View {
        Picker("View", selection: Binding(
            get: { manager.outputPreviewMode },
            set: { mode in
                guard manager.outputPreviewMode != mode else { return }
                DispatchQueue.main.async {
                    manager.setOutputPreviewMode(mode)
                }
            }
        )) {
            ForEach(OutputPreviewMode.allCases) { mode in
                Label(mode.label, systemImage: mode.systemImage)
                    .tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var previewActionRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                previewActionButtons
                Spacer(minLength: 4)
                previewSummary
                    .fixedSize(horizontal: true, vertical: false)
            }

            HStack(spacing: 4) {
                previewActionButtons
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var previewActionButtons: some View {
        HStack(spacing: 5) {
            Button {
                manager.selectAdjacentOutputPreviewImage(direction: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 22, height: 22)
            }
            .disabled(!manager.canSelectAdjacentOutputPreviewImage(direction: -1))
            .help("Previous image")
            .accessibilityLabel("Previous image")

            Button {
                manager.selectAdjacentOutputPreviewImage(direction: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 22, height: 22)
            }
            .disabled(!manager.canSelectAdjacentOutputPreviewImage(direction: 1))
            .help("Next image")
            .accessibilityLabel("Next image")

            Divider()
                .frame(height: 18)

            Button {
                manager.refreshOutputPreview()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .frame(width: 22, height: 22)
            }
            .help("Refresh output list")
            .accessibilityLabel("Refresh output list")

            Button {
                manager.openSelectedOutputPreviewFile()
            } label: {
                Image(systemName: "arrow.up.forward.app")
                    .frame(width: 22, height: 22)
            }
            .disabled(manager.outputPreviewSelectedFile == nil)
            .help("Open selected file")
            .accessibilityLabel("Open selected file")

            Button {
                if let file = manager.outputPreviewSelectedFile {
                    manager.revealOutputPreviewFile(file)
                }
            } label: {
                Image(systemName: "folder")
                    .frame(width: 22, height: 22)
            }
            .disabled(manager.outputPreviewSelectedFile == nil)
            .help(manager.outputPreviewSelectedFile?.isArchiveEntry == true ? "Reveal archive" : "Reveal selected file")
            .accessibilityLabel(manager.outputPreviewSelectedFile?.isArchiveEntry == true ? "Reveal archive" : "Reveal selected file")

            Menu {
                Button {
                    manager.openOutputPreviewInBrowser()
                } label: {
                    Label("Open Browser View", systemImage: "safari")
                }

                Button {
                    manager.openOutputPreviewFileInBrowser()
                } label: {
                    Label("Open Selected File in Browser", systemImage: "eye")
                }
                .disabled(manager.outputPreviewSelectedFile == nil)

                Divider()

                Button {
                    manager.createPDFForOutputPreview()
                } label: {
                    Label("Create PDF", systemImage: "doc.richtext")
                }
                .disabled(manager.outputPreviewImageFiles.isEmpty)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .help("More preview actions")
            .accessibilityLabel("More preview actions")
        }
        .buttonStyle(.borderless)
        .fixedSize(horizontal: true, vertical: false)
    }

    private var previewSummary: some View {
        Text(manager.outputPreviewSummary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("\(manager.outputPreviewFiles.count)", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label("\(manager.outputPreviewImageFiles.count)", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.outputPreviewFiles) { file in
                            OutputPreviewFileRow(
                                file: file,
                                selected: file.originalIndex == manager.outputPreviewSelectedFileIndex,
                                byteText: byteText(file.byteCount)
                            ) {
                                manager.selectOutputPreviewFile(file)
                            } openInBrowser: {
                                manager.openOutputPreviewFileInBrowser(file)
                            } reveal: {
                                manager.revealOutputPreviewFile(file)
                            }
                            .id(file.originalIndex)
                            Divider()
                        }
                    }
                }
                .onAppear {
                    proxy.scrollTo(manager.outputPreviewSelectedFileIndex, anchor: .center)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    @ViewBuilder
    private var previewPane: some View {
        switch manager.outputPreviewMode {
        case .paged:
            pagedPreview
        case .scroll:
            scrollPreview
        case .files:
            filesPreview
        }
    }

    private var pagedPreview: some View {
        VStack(spacing: 0) {
            if let file = manager.outputPreviewSelectedFile {
                OutputPreviewStage(manager: manager, file: file)
            } else {
                emptyState
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var scrollPreview: some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - 36)
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(manager.outputPreviewImageFiles) { file in
                        OutputPreviewScrollImage(
                            manager: manager,
                            file: file,
                            contentWidth: contentWidth
                        )
                        .id(file.originalIndex)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var filesPreview: some View {
        ScrollView {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)],
                spacing: 12
            ) {
                ForEach(manager.outputPreviewFiles) { file in
                    OutputPreviewFileTile(
                        manager: manager,
                        file: file,
                        selected: file.originalIndex == manager.outputPreviewSelectedFileIndex,
                        byteText: byteText(file.byteCount)
                    )
                }
            }
            .padding(18)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No Previewable Output")
                .font(.headline)
            Text(manager.outputPreviewJob == nil ? "Select a finished task." : "No output files were found.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)
            Text("Scanning Output...")
                .font(.headline)
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func byteText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, byteCount)), countStyle: .file)
    }
}

private struct OutputPreviewFileRow: View {
    let file: OutputPreviewFile
    let selected: Bool
    let byteText: String
    let select: () -> Void
    let openInBrowser: () -> Void
    let reveal: () -> Void

    var body: some View {
        Button(action: select) {
            HStack(spacing: 9) {
                Image(systemName: file.mediaType.systemImage)
                    .frame(width: 20)
                    .foregroundStyle(selected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    Text(file.relativePath)
                        .font(.caption)
                        .lineLimit(2)
                        .truncationMode(.middle)
                    HStack(spacing: 6) {
                        Text(file.mediaType.label)
                        Text(byteText)
                        if file.isArchiveEntry {
                            Text("Archive")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear)
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(action: openInBrowser) {
                Label("Open in Browser", systemImage: "eye")
            }
            Button(action: reveal) {
                Label(file.isArchiveEntry ? "Reveal Archive" : "Reveal File", systemImage: "folder")
            }
        }
    }
}

private struct OutputPreviewStage: View {
    @ObservedObject var manager: DownloadManager
    let file: OutputPreviewFile

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Color.black.opacity(0.88)
                if file.isImage {
                    OutputPreviewAsyncImage(file: file)
                        .padding(12)
                } else {
                    OutputPreviewPlaceholder(file: file)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            .layoutPriority(1)

            HStack(spacing: 8) {
                Label(file.filename, systemImage: file.mediaType.systemImage)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text("\(file.originalIndex + 1) / \(manager.outputPreviewFiles.count)")
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }
}

private struct OutputPreviewScrollImage: View {
    @ObservedObject var manager: DownloadManager
    let file: OutputPreviewFile
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if file.isImage {
                OutputPreviewAsyncImage(file: file, layout: .scrolling(contentWidth: contentWidth))
                    .frame(maxWidth: .infinity)
                    .background(Color.black.opacity(0.9))
                    .onTapGesture {
                        manager.selectOutputPreviewFile(file)
                    }
            } else {
                OutputPreviewPlaceholder(file: file)
                    .frame(height: 220)
            }
            Text(file.relativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

private struct OutputPreviewFileTile: View {
    @ObservedObject var manager: DownloadManager
    let file: OutputPreviewFile
    let selected: Bool
    let byteText: String

    var body: some View {
        Button {
            manager.selectOutputPreviewFile(file)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color.black.opacity(file.isImage ? 0.86 : 0.08)
                    if file.isImage {
                        OutputPreviewAsyncImage(file: file, compactPlaceholder: true)
                            .padding(4)
                    } else {
                        Image(systemName: file.mediaType.systemImage)
                            .font(.system(size: 30))
                            .foregroundStyle(.secondary)
                    }
                }
                .aspectRatio(1.2, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Text(file.relativePath)
                    .font(.caption)
                    .lineLimit(2)
                    .truncationMode(.middle)
                HStack {
                    Text(file.mediaType.label)
                    Spacer()
                    Text(byteText)
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(8)
            .background(selected ? Color.accentColor.opacity(0.12) : Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(selected ? Color.accentColor : Color.secondary.opacity(0.18), lineWidth: selected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                manager.openOutputPreviewFileInBrowser(file)
            } label: {
                Label("Open in Browser", systemImage: "eye")
            }
            Button {
                manager.revealOutputPreviewFile(file)
            } label: {
                Label(file.isArchiveEntry ? "Reveal Archive" : "Reveal File", systemImage: "folder")
            }
        }
    }
}

private enum OutputPreviewImageLayout {
    case bounded
    case scrolling(contentWidth: CGFloat)
}

private struct OutputPreviewAsyncImage: View {
    let file: OutputPreviewFile
    var compactPlaceholder = false
    var layout: OutputPreviewImageLayout = .bounded

    @StateObject private var loader = OutputPreviewImageLoader()

    var body: some View {
        Group {
            switch layout {
            case .bounded:
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .scrolling(let contentWidth):
                let displaySize = OutputPreviewLayoutPolicy.scrollingImageSize(
                    imageSize: loader.image?.size,
                    contentWidth: contentWidth
                )
                content
                    .frame(width: displaySize.width, height: displaySize.height)
                    .frame(width: max(1, contentWidth), height: displaySize.height)
            }
        }
        .clipped()
        .task(id: OutputPreviewImageProvider.cacheIdentity(for: file)) {
            await loader.load(file)
        }
        .onDisappear {
            loader.unloadAfterViewUpdate()
        }
    }

    @ViewBuilder
    private var content: some View {
        ZStack {
            if let image = loader.image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else if loader.isLoading {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if compactPlaceholder {
                Image(systemName: "photo.badge.exclamationmark")
                    .font(.system(size: 28))
                    .foregroundStyle(.secondary)
            } else {
                OutputPreviewPlaceholder(file: file)
            }
        }
    }
}

private struct OutputPreviewPlaceholder: View {
    let file: OutputPreviewFile

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: file.mediaType.systemImage)
                .font(.system(size: 42))
            Text(file.filename)
                .font(.headline)
                .lineLimit(2)
                .truncationMode(.middle)
            Text(file.mediaType.label)
                .font(.caption)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct TextViewerWindowView: View {
    @ObservedObject var manager: DownloadManager

    private var entries: [TextViewerEntry] {
        manager.visibleTextViewerEntries
    }

    private var selectedDocument: TextViewerDocument {
        manager.selectedTextViewerDocument()
    }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)

            detail
                .frame(minWidth: 520)
        }
        .frame(width: 900, height: 620)
        .onAppear {
            manager.ensureTextViewerSelection()
        }
        .onChange(of: manager.textViewerFilter) {
            manager.ensureTextViewerSelection()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Label("Text Viewer", systemImage: "doc.text.magnifyingglass")
                    .font(.headline)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
                TextField("Filter", text: $manager.textViewerFilter)
                    .textFieldStyle(.roundedBorder)
                if !manager.textViewerFilter.trimmed.isEmpty {
                    Button {
                        manager.textViewerFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filter")
                }
            }

            if entries.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 30))
                        .foregroundStyle(.secondary)
                    Text("No text output")
                        .font(.headline)
                    Text("Completed text, log, JSON, XML, CSV, HTML, Markdown files, messages, and comments appear here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(entries) { entry in
                            TextViewerEntryRow(
                                entry: entry,
                                isSelected: manager.textViewerSelectedEntryID == entry.id
                            ) {
                                manager.selectTextViewerEntry(entry)
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var detail: some View {
        let document = selectedDocument
        return VStack(alignment: .leading, spacing: 0) {
            detailHeader(document)
            Divider()
            detailBody(document)
            Divider()
            detailFooter(document)
        }
    }

    private func detailHeader(_ document: TextViewerDocument) -> some View {
        HStack(spacing: 12) {
            Image(systemName: document.entry?.kind == .message ? "text.bubble" : "doc.text")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(document.entry?.displayName ?? "Text Viewer")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(document.entry?.title ?? "No text selected")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button {
                manager.copySelectedTextViewerDocument()
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .disabled(document.text.isEmpty && document.errorMessage == nil)

            Button {
                manager.openSelectedTextViewerRawFile()
            } label: {
                Image(systemName: "doc")
            }
            .disabled(!manager.canOpenSelectedTextViewerRawFile())
            .help("Open raw text file")

            Button {
                manager.openSelectedTextViewerInBrowser()
            } label: {
                Image(systemName: "safari")
            }
            .disabled(document.entry == nil)
            .help("Open in local text browser")

            Button {
                manager.showingTextViewer = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close text viewer")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private func detailBody(_ document: TextViewerDocument) -> some View {
        Group {
            if let error = document.errorMessage {
                VStack(spacing: 10) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 34))
                        .foregroundStyle(.orange)
                    Text("Text could not be read")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if document.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No text selected")
                        .font(.headline)
                    Text("Choose a text-capable queue item on the left.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                TextEditor(text: .constant(document.text))
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(Color(nsColor: .textBackgroundColor))
                    .padding(12)
            }
        }
    }

    private func detailFooter(_ document: TextViewerDocument) -> some View {
        HStack(spacing: 12) {
            if let entry = document.entry {
                Label(entry.kind.label, systemImage: entry.kind == .message ? "text.bubble" : "doc.text")
                Label(entry.status.label, systemImage: JobStatusStyle.iconName(for: entry.status))
                Label(byteText(document.byteCount), systemImage: "externaldrive")
                if document.truncated {
                    Label("Truncated at \(byteText(document.bytesRead))", systemImage: "scissors")
                        .foregroundStyle(.orange)
                }
            } else {
                Text("No text output files or task messages.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if !manager.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    manager.addSummary,
                    language: manager.interfaceLanguage
                ))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .font(.caption)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func byteText(_ byteCount: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(max(0, byteCount)), countStyle: .file)
    }
}

struct TextViewerEntryRow: View {
    let entry: TextViewerEntry
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: entry.kind == .message ? "text.bubble" : "doc.text")
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.displayName)
                        .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(entry.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .help(entry.detail)
    }
}

struct ProgressWindowView: View {
    @ObservedObject var manager: DownloadManager

    private var visibleJobs: [DownloadJob] {
        let jobs = manager.progressWindowVisibleJobs
        return jobs.isEmpty ? Array(manager.jobs.prefix(12)) : jobs
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            summary
            Divider()
            jobList
            Divider()
            footer
        }
        .frame(width: 720, height: 520)
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "gauge")
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text("Progress")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(manager.isRunning ? "Queue running" : "Queue idle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                manager.showingProgressWindow = false
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.borderless)
            .help("Close progress")
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(.bar)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(manager.progressWindowStatusText)
                    .font(.headline.monospacedDigit())
                Spacer()
                Text("\(Int((manager.progressWindowFraction * 100).rounded()))%")
                    .font(.title2.monospacedDigit())
                    .fontWeight(.semibold)
            }

            ProgressView(value: manager.progressWindowFraction)
                .progressViewStyle(.linear)
                .help("\(manager.progressWindowCompletedUnits)/\(manager.progressWindowTotalUnits)")

            HStack(spacing: 10) {
                Label("\(manager.jobs.count) tasks", systemImage: "list.bullet.rectangle")
                Label("\(manager.progressWindowActiveJobs.count) active", systemImage: "bolt")
                Label("\(manager.progressWindowCompletedUnits)/\(manager.progressWindowTotalUnits)", systemImage: "number")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(18)
    }

    private var jobList: some View {
        Group {
            if visibleJobs.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "progress.indicator")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text("No tasks")
                        .font(.headline)
                    Text("Add URLs to the queue, then start downloads to see progress here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleJobs) { job in
                        ProgressWindowJobRow(job: job)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                manager.startQueue()
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(manager.isRunning)

            Button {
                manager.cancelQueue()
            } label: {
                Label("Cancel", systemImage: "stop.fill")
            }
            .disabled(!manager.isRunning)

            Button {
                _ = manager.clearFinished()
            } label: {
                Label("Clear", systemImage: "checkmark.circle")
            }
            .disabled(manager.removableFinishedJobCount == 0 || manager.isRunning)

            Spacer()

            if !manager.addSummary.isEmpty {
                Text(AppLocalization.statusText(
                    manager.addSummary,
                    language: manager.interfaceLanguage
                ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

struct ProgressWindowJobRow: View {
    let job: DownloadJob

    private var units: (completed: Int, total: Int) {
        DownloadManager.progressWindowUnits(for: job)
    }

    private var fraction: Double {
        guard units.total > 0 else { return 0 }
        return min(1, max(0, Double(units.completed) / Double(units.total)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: iconName)
                    .foregroundStyle(statusColor)
                    .frame(width: 18)

                Text(job.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(Int((fraction * 100).rounded()))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: fraction)
                .progressViewStyle(.linear)

            HStack(spacing: 8) {
                if let summary = job.partialFailureSummary() {
                    Text(summary)
                } else {
                    Text(job.statusDisplayText())
                    Text("\(units.completed)/\(units.total)")
                }
                if !job.message.trimmed.isEmpty {
                    Text(AppLocalization.statusText(job.message))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        }
        .padding(.vertical, 4)
        .help(job.source)
    }

    private var iconName: String {
        JobStatusStyle.iconName(for: job)
    }

    private var statusColor: Color {
        JobStatusStyle.color(for: job)
    }
}

struct StatisticsView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    private var language: AppInterfaceLanguage { manager.interfaceLanguage }

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { _ in
            let statistics = manager.statisticsSnapshot()
            content(statistics)
        }
    }

    private func content(_ statistics: AppStatistics) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label(localized("Info & Statistics"), systemImage: "chart.bar.xaxis")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text(dateText(statistics.generatedAt, dateStyle: .none, timeStyle: .medium))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            StatisticsMonitorPanel(statistics: statistics, language: language)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    section("App") {
                        statRow("Name", statistics.appName)
                        statRow("Version", "\(statistics.appVersion) (\(statistics.appBuild))")
                        statRow("Bundle ID", statistics.bundleIdentifier)
                        statRow("Requires macOS", statistics.minimumSystemVersion)
                        statRow("Running On", operatingSystemText(statistics.operatingSystemVersion))
                    }

                    section("Paths") {
                        statRow("Downloads", statistics.outputRootPath.isEmpty ? localized("Not set") : statistics.outputRootPath)
                        statRow("App Support", statistics.applicationSupportPath)
                        statRow("User Data", statistics.userDataPath)
                    }

                    section("Tools") {
                        ForEach(statistics.externalTools) { tool in
                            statRow(tool.name, toolStatusText(tool))
                        }
                    }

                    section("Queue") {
                        statRow("Total", "\(statistics.totalJobs)")
                        statRow("Active", "\(statistics.activeJobs)")
                        statRow("Queued", "\(statistics.queuedJobs)")
                        statRow("Resolving", "\(statistics.resolvingJobs)")
                        statRow("Downloading", "\(statistics.downloadingJobs)")
                        statRow("Finished", "\(statistics.finishedJobs)")
                        statRow("Failed", "\(statistics.failedJobs)")
                        statRow("Cancelled", "\(statistics.cancelledJobs)")
                        statRow("Pinned", "\(statistics.pinnedJobs)")
                        statRow("Locked", "\(statistics.lockedJobs)")
                        statRow("Task Slots", "\(statistics.jobConcurrency)")
                        statRow("File Threads", "\(statistics.fileConcurrency)")
                        statRow("UI Scale", statistics.uiScale)
                    }

                    section("Runtime") {
                        statRow("Started", dateText(statistics.appStartedAt, dateStyle: .medium, timeStyle: .medium))
                        statRow("Elapsed", elapsedText(statistics.appUptimeSeconds))
                        statRow("Download Speed", transferSpeedText(statistics.downloadSpeedBytesPerSecond))
                        statRow("Upload Speed", transferSpeedText(statistics.uploadSpeedBytesPerSecond))
                        statRow("Downloaded Since Launch", optionalByteText(statistics.downloadedSinceLaunchByteCount))
                    }

                    section("Library") {
                        statRow("History", "\(statistics.historyCount)")
                        statRow("Bookmarks", "\(statistics.bookmarkCount)")
                        statRow("Filter Bookmarks", "\(statistics.queueFilterBookmarkCount)")
                        statRow(
                            "Site Rules",
                            AppLocalization.format(
                                "%@ / %@ enabled",
                                language: language,
                                String(statistics.enabledSiteRuleCount),
                                String(statistics.siteRuleCount)
                            )
                        )
                        statRow("Search Providers", "\(statistics.searchProviderCount)")
                        statRow("Duplicate Groups", "\(statistics.duplicateGroupCount)")
                        statRow("Duplicate Extras", "\(statistics.duplicateExtraFileCount)")
                    }

                    section("Output") {
                        statRow("Available", statistics.destinationPathAnalysisSkipped ? localized("Skipped") : optionalByteText(statistics.destinationAvailableByteCount))
                        statRow("Volume Size", statistics.destinationPathAnalysisSkipped ? localized("Skipped") : optionalByteText(statistics.destinationTotalByteCount))
                        statRow("Known Queue Size", byteText(statistics.estimatedQueuedByteCount))
                        statRow("Known Paths", "\(statistics.outputPathCount)")
                        statRow("Files", countedText(statistics.outputFileCount, partial: statistics.outputPathAnalysisSkippedCount > 0))
                        statRow("Folders", countedText(statistics.outputDirectoryCount, partial: statistics.outputPathAnalysisSkippedCount > 0))
                        statRow("Total Size", byteText(statistics.outputByteCount, partial: statistics.outputPathAnalysisSkippedCount > 0))
                        if statistics.outputPathAnalysisSkippedCount > 0 {
                            statRow("Skipped Paths", "\(statistics.outputPathAnalysisSkippedCount)")
                        }
                        statRow("Auto Remove Finished", onOff(statistics.autoRemoveFinishedJobs))
                        statRow("Auto Remove Hook", optionText(statistics.autoRemoveHookCommand))
                        statRow("Auto Remove Hook Status", AppLocalization.statusText(statistics.autoRemoveHookStatus, language: language))
                        statRow("Download Date", onOff(statistics.showDownloadDate))
                        if !statistics.diskSpaceWarning.isEmpty {
                            statRow("Warning", AppLocalization.statusText(statistics.diskSpaceWarning, language: language))
                        }
                    }

                    section("aria2 / Network") {
                        statRow("Download Limit", optionText(statistics.aria2MaxDownloadLimit))
                        statRow("Upload Limit", optionText(statistics.aria2MaxUploadLimit))
                        statRow("Seed Time", seedTimeText(statistics))
                        statRow("Seed Ratio", optionText(statistics.aria2SeedRatio))
                        statRow("Anonymous Mode", onOff(statistics.aria2AnonymousMode))
                        statRow("HTTP API", onOff(statistics.httpAPIEnabled))
                        statRow("Public IP", AppLocalization.statusText(statistics.publicIPStatus, language: language))
                        statRow("Clipboard Watch", onOff(statistics.clipboardMonitorEnabled))
                        statRow("YouTube Thumbnail", onOff(statistics.youtubeDownloadThumbnail))
                        statRow("YouTube Reverse Playlist", onOff(statistics.youtubeReversePlaylist))
                        statRow("YouTube Upload Date File Time", onOff(statistics.youtubeUseUploadDateForFileModificationTime))
                        statRow("YouTube Auto Subtitles", onOff(statistics.youtubeDownloadAutoSubtitles))
                        statRow("YouTube Subtitle Languages", optionText(statistics.youtubeSubtitleLanguages))
                        statRow("YouTube Chapters", onOff(statistics.youtubeEmbedChapters))
                        statRow("YouTube Codec Priority", optionText(statistics.youtubeVideoCodecSort))
                        statRow("YouTube Enhanced Bitrate", onOff(statistics.youtubePreferEnhancedBitrate))
                        statRow("YouTube Resolution", optionText(statistics.youtubePreferredResolution))
                        statRow("YouTube Audio Track", optionText(statistics.youtubePreferredAudioLanguage))
                        statRow("History", onOff(statistics.historyEnabled))
                        statRow("Prevent Sleep", onOff(statistics.preventSleepWhileDownloading))
                        statRow("Sleep Assertion", localized(statistics.sleepPreventionActive ? "Active" : "Inactive"))
                    }

                    section("Alerts") {
                        statRow("Finished Job Notification", onOff(statistics.notifyWhenJobCompletes))
                        statRow("Queue Complete Notification", onOff(statistics.notifyWhenQueueCompletes))
                        statRow("Finished Job Sound", onOff(statistics.playSoundWhenJobCompletes))
                        statRow("Clipboard Add Sound", onOff(statistics.playSoundOnClipboardAdd))
                        statRow("After Queue Complete", AppLocalization.statusText(statistics.queueCompletionAction, language: language))
                        statRow("After Complete Status", AppLocalization.statusText(statistics.queueCompletionActionStatus, language: language))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 520)
        .frame(minHeight: 560)
        .accessibilityIdentifier("auxiliary.statistics")
    }

    private func seedTimeText(_ statistics: AppStatistics) -> String {
        let value = statistics.aria2SeedTimeMinutes.trimmed
        if value.isEmpty || value == "0" {
            return localized("Off")
        }
        return AppLocalization.format("%@ min", language: language, value)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localized(title))
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 18, verticalSpacing: 6) {
                content()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statRow(_ title: String, _ value: String) -> some View {
        GridRow {
            Text(localized(title))
                .foregroundStyle(.secondary)
            Text(value)
                .monospacedDigit()
                .lineLimit(2)
                .truncationMode(.middle)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func byteText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func byteText(_ byteCount: Int64, partial: Bool) -> String {
        let text = byteText(byteCount)
        return partial ? AppLocalization.format("%@ counted", language: language, text) : text
    }

    private func countedText(_ count: Int, partial: Bool) -> String {
        partial ? AppLocalization.format("%@ counted", language: language, String(count)) : String(count)
    }

    private func optionalByteText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Unknown") }
        return byteText(byteCount)
    }

    private func transferSpeedText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Measuring") }
        return "\(byteText(byteCount))/s"
    }

    private func elapsedText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remaining = totalSeconds % 60
        if hours > 0 {
            return AppLocalization.format(
                "%@h %@m %@s",
                language: language,
                String(hours),
                String(minutes),
                String(remaining)
            )
        }
        if minutes > 0 {
            return AppLocalization.format(
                "%@m %@s",
                language: language,
                String(minutes),
                String(remaining)
            )
        }
        return AppLocalization.format("%@s", language: language, String(remaining))
    }

    private func optionText(_ value: String) -> String {
        value.trimmed.isEmpty
            ? localized("Not set")
            : AppLocalization.statusText(value.trimmed, language: language)
    }

    private func onOff(_ enabled: Bool) -> String {
        localized(enabled ? "On" : "Off")
    }

    private func toolStatusText(_ tool: ExternalToolStatus) -> String {
        guard tool.isAvailable else {
            return tool.configuredPath.isEmpty
                ? localized("Not found")
                : AppLocalization.format("Missing: %@", language: language, tool.configuredPath)
        }
        if tool.configuredPath.isEmpty {
            return AppLocalization.format("Found: %@", language: language, tool.resolvedPath)
        }
        return AppLocalization.format("Configured: %@", language: language, tool.resolvedPath)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }

    private func dateText(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        timeStyle: DateFormatter.Style
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = dateStyle
        formatter.timeStyle = timeStyle
        return formatter.string(from: date)
    }

    private func operatingSystemText(_ rawValue: String) -> String {
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let components = [version.majorVersion, version.minorVersion, version.patchVersion]
        let lastIndex = version.patchVersion == 0 ? 1 : 2
        let versionText = components[0...lastIndex].map(String.init).joined(separator: ".")
        if let buildRange = rawValue.range(
            of: #"[0-9]{2}[A-Za-z][A-Za-z0-9]+"#,
            options: .regularExpression
        ) {
            return AppLocalization.format(
                "Version %@ (Build %@)",
                language: language,
                versionText,
                String(rawValue[buildRange])
            )
        }
        return AppLocalization.format("Version %@", language: language, versionText)
    }
}

private struct StatisticsMonitorPanel: View {
    let statistics: AppStatistics
    let language: AppInterfaceLanguage

    private var downloadFraction: Double {
        AppStatistics.speedFraction(statistics.downloadSpeedBytesPerSecond)
    }

    private var uploadFraction: Double {
        AppStatistics.speedFraction(statistics.uploadSpeedBytesPerSecond)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 16) {
                usageColumn(
                    title: localized("Download"),
                    value: transferSpeedText(statistics.downloadSpeedBytesPerSecond),
                    fraction: downloadFraction,
                    color: .accentColor
                )

                usageColumn(
                    title: localized("Upload"),
                    value: transferSpeedText(statistics.uploadSpeedBytesPerSecond),
                    fraction: uploadFraction,
                    color: .orange
                )
            }

            StatisticsPlotView(values: [
                (label: "DL", fraction: downloadFraction, color: .accentColor),
                (label: "UL", fraction: uploadFraction, color: .orange),
                (label: localized("Active"), fraction: statistics.queueActiveFraction, color: .blue),
                (label: localized("Done"), fraction: statistics.queueCompletedFraction, color: .green),
                (label: localized("Disk"), fraction: statistics.destinationUsedFraction ?? 0, color: .purple)
            ])
            .frame(height: 78)

            HStack(spacing: 14) {
                Label(optionalByteText(statistics.downloadedSinceLaunchByteCount), systemImage: "arrow.down.circle")
                    .help(localized("Downloaded since launch"))
                Label(elapsedText(statistics.appUptimeSeconds), systemImage: "timer")
                    .help(localized("Elapsed time"))
                Label(
                    AppLocalization.format("%@ active", language: language, String(statistics.activeJobs)),
                    systemImage: "bolt"
                )
                    .help(localized("Resolving and downloading jobs"))
                Spacer()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(12)
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color(nsColor: .separatorColor))
        )
    }

    private func usageColumn(title: String, value: String, fraction: Double, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(value)
                    .font(.caption.monospacedDigit())
                    .lineLimit(1)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    RoundedRectangle(cornerRadius: 4)
                        .fill(color)
                        .frame(width: max(2, geometry.size.width * CGFloat(min(1, max(0, fraction)))))
                }
            }
            .frame(height: 10)
        }
    }

    private func byteText(_ byteCount: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    private func optionalByteText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Downloaded unknown") }
        return AppLocalization.format("%@ downloaded", language: language, byteText(byteCount))
    }

    private func transferSpeedText(_ byteCount: Int64?) -> String {
        guard let byteCount else { return localized("Measuring") }
        return "\(byteText(byteCount))/s"
    }

    private func elapsedText(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let remaining = totalSeconds % 60
        if hours > 0 {
            return AppLocalization.format(
                "%@h %@m %@s",
                language: language,
                String(hours),
                String(minutes),
                String(remaining)
            )
        }
        if minutes > 0 {
            return AppLocalization.format(
                "%@m %@s",
                language: language,
                String(minutes),
                String(remaining)
            )
        }
        return AppLocalization.format("%@s", language: language, String(remaining))
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }
}

private struct StatisticsPlotView: View {
    let values: [(label: String, fraction: Double, color: Color)]

    var body: some View {
        GeometryReader { geometry in
            let barWidth = max(6, geometry.size.width / CGFloat(max(values.count, 1)) - 14)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, value in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 3)
                                .fill(Color(nsColor: .controlBackgroundColor))
                            RoundedRectangle(cornerRadius: 3)
                                .fill(value.color)
                                .frame(height: max(2, (geometry.size.height - 20) * CGFloat(min(1, max(0, value.fraction)))))
                        }
                        .frame(width: barWidth, height: max(28, geometry.size.height - 20))

                        Text(value.label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
    }
}

struct ActivityLogView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(localized("Log"), systemImage: "doc.text.magnifyingglass")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Toggle(localized("Auto Refresh && Scroll"), isOn: $manager.activityLogAutoRefreshAndScroll)
                    .toggleStyle(.checkbox)
                Button(localized("Clear")) {
                    manager.clearActivityLog()
                }
                .disabled(manager.activityLog.isEmpty)
                .accessibilityLabel(localized("Clear"))
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if manager.activityLog.isEmpty {
                            Text(localized("No log entries"))
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else {
                            ForEach(manager.activityLog) { entry in
                                ActivityLogRow(entry: entry, language: manager.interfaceLanguage)
                            }
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("activity-log-bottom")
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
                .onAppear {
                    scrollToBottom(proxy)
                }
                .onChange(of: manager.activityLog.count) { _, _ in
                    scrollToBottom(proxy)
                }
            }
        }
        .padding(20)
        .frame(width: 680)
        .frame(minHeight: 520)
        .accessibilityIdentifier("auxiliary.activity-log")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        guard manager.activityLogAutoRefreshAndScroll else { return }
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                proxy.scrollTo("activity-log-bottom", anchor: .bottom)
            }
        }
    }
}

private struct ActivityLogRow: View {
    var entry: ActivityLogEntry
    var language: AppInterfaceLanguage

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(formattedTimestamp)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)
            Text(AppLocalization.text(entry.category, language: language))
                .foregroundStyle(.secondary)
                .frame(width: 76, alignment: .leading)
            Text(AppLocalization.statusText(entry.message, language: language))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.system(.caption, design: .monospaced))
        .textSelection(.enabled)
    }

    private var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.locale = language.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: entry.timestamp)
    }
}

struct DirectoriesView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = manager.outputDirectoryEntries()
        let text = manager.outputDirectoriesText(entries: entries, language: manager.interfaceLanguage)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(localized("Dirs"), systemImage: "folder")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(localized("Copy")) {
                    copy(text)
                }
                .disabled(entries.isEmpty)
                .accessibilityLabel(localized("Copy"))
                Button(localized("Open First")) {
                    openFirstDirectory(entries)
                }
                .disabled(firstOpenableDirectory(entries) == nil)
                .accessibilityLabel(localized("Open First"))
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            ScrollView {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .padding(20)
        .frame(width: 680)
        .frame(minHeight: 480)
        .accessibilityIdentifier("auxiliary.directories")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func openFirstDirectory(_ entries: [OutputDirectoryEntry]) {
        guard let path = firstOpenableDirectory(entries) else { return }
        NSWorkspace.shared.open(URL(fileURLWithPath: path, isDirectory: true))
    }

    private func firstOpenableDirectory(_ entries: [OutputDirectoryEntry]) -> String? {
        entries.first { $0.exists && $0.isDirectory }?.path
    }
}

struct HistoryWindowView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let text = manager.historyPlainText(language: manager.interfaceLanguage)

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label(localized("History"), systemImage: "clock.arrow.circlepath")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(manager.history.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(localized("Copy")) {
                    copy(text)
                }
                .disabled(manager.history.isEmpty)
                .accessibilityLabel(localized("Copy"))
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            TextEditor(text: .constant(text))
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
        }
        .padding(20)
        .frame(width: 720)
        .frame(minHeight: 520)
        .accessibilityIdentifier("auxiliary.history")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

struct SearcherWindowView: View {
    @ObservedObject var manager: DownloadManager
    let hostSize: CGSize
    @Environment(\.dismiss) private var dismiss

    private var layout: SearcherLayoutMetrics {
        SearcherLayoutPolicy.metrics(forHostSize: hostSize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Searcher", systemImage: "text.magnifyingglass")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(manager.searchProviders.count) providers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") {
                    manager.cancelSearchResultsFetch()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            searchBar

            TabView {
                resultsTab
                    .tabItem {
                        Label("Results", systemImage: "list.bullet.rectangle")
                    }

                savedSearchesTab
                    .tabItem {
                        Label("Saved", systemImage: "bookmark")
                    }

                providersTab
                    .tabItem {
                        Label("Providers", systemImage: "magnifyingglass.circle")
                    }

                tagsTab
                    .tabItem {
                        Label("Tags", systemImage: "tag")
                    }
            }
        }
        .padding(20)
        .frame(width: layout.width, height: layout.height)
        .onDisappear {
            manager.cancelSearchResultsFetch()
        }
    }

    private var searchBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Picker("", selection: $manager.selectedSearchProviderID) {
                    ForEach(manager.searchProviders) { provider in
                        Text(provider.name).tag(provider.id)
                    }
                }
                .labelsHidden()
                .frame(width: layout.usesCompactControls ? 132 : 180)
                .disabled(manager.searchProviders.isEmpty)
                .accessibilityIdentifier("searcher.provider")

                TextField("Query", text: $manager.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("searcher.query")
                    .onSubmit {
                        manager.fetchSearchResults()
                    }

                Button {
                    manager.openSearchURL()
                } label: {
                    Image(systemName: "safari")
                }
                .help("Open search URL")

                Button {
                    manager.enqueueSearchURL()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Add search URL to queue")

                Button {
                    manager.saveCurrentSearchBookmark()
                } label: {
                    Image(systemName: "bookmark")
                }
                .disabled(manager.searchQuery.trimmed.isEmpty || manager.searchProviders.isEmpty)
                .help("Save search")

                Button {
                    if manager.isSearching {
                        manager.cancelSearchResultsFetch()
                    } else {
                        manager.fetchSearchResults()
                    }
                } label: {
                    Image(systemName: manager.isSearching ? "xmark" : "arrow.clockwise")
                }
                .help(manager.isSearching ? "Cancel search" : "Fetch results")
                .accessibilityIdentifier("searcher.fetch")
            }

            hitomiAdvancedSearchBuilder

            HStack(spacing: 12) {
                Toggle("Dedup", isOn: Binding(
                    get: { manager.searchDeduplicateResults },
                    set: { manager.setSearchDeduplicateResults($0) }
                ))
                .toggleStyle(.checkbox)

                Toggle("Hide Done", isOn: Binding(
                    get: { manager.searchHideKnownResults },
                    set: { manager.setSearchHideKnownResults($0) }
                ))
                .toggleStyle(.checkbox)

                if !manager.addSummary.trimmed.isEmpty {
                    Text(AppLocalization.statusText(
                        manager.addSummary,
                        language: manager.interfaceLanguage
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    private var hitomiAdvancedSearchBuilder: some View {
        let columns = Array(
            repeating: GridItem(.flexible(minimum: 108), spacing: 8),
            count: layout.usesCompactControls ? 2 : 4
        )

        return DisclosureGroup(isExpanded: Binding(
            get: { manager.hitomiAdvancedSearchExpanded },
            set: { manager.hitomiAdvancedSearchExpanded = $0 }
        )) {
            VStack(alignment: .leading, spacing: 8) {
                LazyVGrid(columns: columns, spacing: 8) {
                    TextField("Title", text: $manager.hitomiAdvancedTitle)
                        .textFieldStyle(.roundedBorder)
                    TextField("Artist", text: $manager.hitomiAdvancedArtist)
                        .textFieldStyle(.roundedBorder)
                    TextField("Group", text: $manager.hitomiAdvancedGroup)
                        .textFieldStyle(.roundedBorder)
                    TextField("Series", text: $manager.hitomiAdvancedSeries)
                        .textFieldStyle(.roundedBorder)
                    TextField("Character", text: $manager.hitomiAdvancedCharacter)
                        .textFieldStyle(.roundedBorder)
                    TextField("Tag", text: $manager.hitomiAdvancedTag)
                        .textFieldStyle(.roundedBorder)
                    TextField("Language", text: $manager.hitomiAdvancedLanguage)
                        .textFieldStyle(.roundedBorder)
                    Picker("", selection: $manager.hitomiAdvancedLanguagePreset) {
                        ForEach(HitomiAdvancedLanguagePreset.allCases) { preset in
                            Text(preset.label).tag(preset)
                        }
                    }
                    .labelsHidden()
                }

                if layout.usesCompactControls {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 104), spacing: 8)],
                        alignment: .leading,
                        spacing: 6
                    ) {
                        advancedSearchTypeToggles
                        Toggle("No Webtoon", isOn: $manager.hitomiAdvancedExcludeWebtoon)
                            .toggleStyle(.checkbox)
                    }
                    HStack(spacing: 8) {
                        Spacer()
                        advancedSearchActionButtons
                    }
                } else {
                    HStack(spacing: 10) {
                        advancedSearchTypeToggles
                        Toggle("No Webtoon", isOn: $manager.hitomiAdvancedExcludeWebtoon)
                            .toggleStyle(.checkbox)
                        Spacer(minLength: 8)
                        advancedSearchActionButtons
                    }
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Hitomi Advanced", systemImage: "slider.horizontal.3")
                .font(.caption)
        }
        .accessibilityIdentifier("searcher.advanced")
    }

    @ViewBuilder
    private var advancedSearchTypeToggles: some View {
        ForEach(HitomiAdvancedSearchType.allCases) { type in
            Toggle(type.label, isOn: Binding(
                get: { manager.hitomiAdvancedTypes.contains(type) },
                set: { manager.setHitomiAdvancedSearchType(type, enabled: $0) }
            ))
            .toggleStyle(.checkbox)
        }
    }

    private var advancedSearchActionButtons: some View {
        HStack(spacing: 8) {
            Button {
                manager.applyHitomiAdvancedSearchQuery()
            } label: {
                Image(systemName: "checkmark.circle")
            }
            .help("Apply Hitomi advanced query")

            Button {
                manager.appendHitomiAdvancedSearchQuery()
            } label: {
                Image(systemName: "plus.circle")
            }
            .help("Append Hitomi advanced query")

            Button {
                manager.clearHitomiAdvancedSearchFields()
            } label: {
                Image(systemName: "xmark.circle")
            }
            .help("Clear Hitomi advanced fields")
        }
    }

    private var resultsTab: some View {
        let visibleResults = manager.filteredSearchResults
        let knownState = manager.searchResultKnownState

        return VStack(alignment: .leading, spacing: 10) {
            if layout.usesCompactControls {
                VStack(spacing: 6) {
                    resultFilterField
                    HStack(spacing: 6) {
                        resultFilterControls
                        Spacer(minLength: 4)
                        resultCountAndActions(visibleResults: visibleResults)
                    }
                }
            } else {
                HStack(spacing: 6) {
                    resultFilterField
                    resultFilterControls
                    Spacer()
                    resultCountAndActions(visibleResults: visibleResults)
                }
            }

            if visibleResults.isEmpty {
                Text(manager.searchResults.isEmpty ? "No search results" : "No matching results")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(visibleResults) { result in
                        SearchResultRow(
                            result: result,
                            galleryID: DownloadManager.searchResultGalleryID(for: result),
                            metadataCopies: DownloadManager.searchResultMetadataCopies(for: result),
                            dateText: DownloadManager.searchResultDateText(for: result),
                            pageCountText: DownloadManager.searchResultPageCountText(for: result),
                            isDone: DownloadManager.searchResultIsKnown(result, knownState: knownState),
                            canOpenFirstOutput: DownloadManager.searchResultFirstOutputOpenURL(for: result, knownState: knownState) != nil,
                            enqueue: {
                                manager.enqueueSearchResult(result)
                            },
                            openSource: {
                                manager.openSearchResult(result)
                            },
                            copyURL: {
                                manager.copySearchResultURL(result)
                            },
                            copyTitle: {
                                manager.copySearchResultTitle(result)
                            },
                            copyMetadata: {
                                manager.copySearchResultMetadata($0)
                            },
                            openFirstOutput: {
                                manager.openFirstOutputFile(forSearchResult: result)
                            },
                            copyGalleryID: {
                                manager.copySearchResultGalleryID(result)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }

    private var resultFilterField: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)
            TextField("Filter results", text: $manager.searchResultFilter)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("searcher.result-filter")
            Button {
                manager.searchResultFilter = ""
            } label: {
                Image(systemName: "xmark.circle")
            }
            .disabled(manager.searchResultFilter.trimmed.isEmpty)
            .help("Clear filter")
        }
    }

    private var resultFilterControls: some View {
        HStack(spacing: 6) {
            Picker("", selection: Binding(
                get: { manager.searchResultKnownFilter },
                set: { manager.setSearchResultKnownFilter($0) }
            )) {
                ForEach(SearchResultKnownFilter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 105)
            .help("Downloaded result filter")
            .accessibilityIdentifier("searcher.known-filter")

            Picker("", selection: Binding(
                get: { manager.searchResultSortMode },
                set: { manager.setSearchResultSortMode($0) }
            )) {
                ForEach(SearchResultSortMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .labelsHidden()
            .frame(width: layout.usesCompactControls ? 104 : 120)
            .accessibilityIdentifier("searcher.sort")

            Button {
                manager.setSearchResultSortDescending(!manager.searchResultSortDescending)
            } label: {
                Image(systemName: manager.searchResultSortDescending ? "arrow.down" : "arrow.up")
            }
            .help(manager.searchResultSortDescending ? "Descending order" : "Ascending order")
        }
    }

    private func resultCountAndActions(visibleResults: [SearchResultLink]) -> some View {
        HStack(spacing: 6) {
            Text((manager.searchResultFilter.trimmed.isEmpty && manager.searchResultKnownFilter == .all) ? "\(manager.searchResults.count)" : "\(visibleResults.count)/\(manager.searchResults.count)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            Button {
                manager.enqueueAllSearchResults()
            } label: {
                Image(systemName: "plus.square.on.square")
            }
            .disabled(visibleResults.isEmpty)
            .help("Add all visible results")

            Button {
                manager.cancelSearchResultsFetch()
                manager.searchResults.removeAll()
                manager.searchResultFilter = ""
                manager.setSearchResultKnownFilter(.all)
            } label: {
                Image(systemName: "trash")
            }
            .disabled(manager.searchResults.isEmpty)
            .help("Clear results")
        }
    }

    private var savedSearchesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Saved Searches")
                    .font(.headline)
                Spacer()
                Text("\(manager.searchBookmarks.count)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Menu {
                    Button {
                        manager.importSearchBookmarks()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        manager.exportSearchBookmarks()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(manager.searchBookmarks.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            if manager.searchBookmarks.isEmpty {
                Text("No saved searches")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.searchBookmarks) { bookmark in
                        SearchBookmarkRow(
                            bookmark: bookmark,
                            apply: {
                                manager.applySearchBookmark(bookmark)
                            },
                            enqueue: {
                                manager.enqueueSearchBookmark(bookmark)
                            },
                            remove: {
                                manager.removeSearchBookmark(bookmark)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }

    private var providersTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("Provider", text: $manager.newSearchProviderName)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: layout.usesCompactControls ? 132 : 180)
                TextField("https://site/search?q={query}", text: $manager.newSearchProviderTemplate)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.addSearchProvider()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Save provider")
                Button {
                    manager.resetSearchProviders()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset providers")
                Menu {
                    Button {
                        manager.importSearchProviders()
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    Button {
                        manager.exportSearchProviders()
                    } label: {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                    .disabled(manager.searchProviders.isEmpty)
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
            }

            if manager.searchProviders.isEmpty {
                Text("No search providers")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(manager.searchProviders.enumerated()), id: \.element.id) { index, provider in
                        SearchProviderRow(
                            provider: provider,
                            canMoveUp: index > 0,
                            canMoveDown: index < manager.searchProviders.count - 1,
                            moveUp: {
                                manager.moveSearchProvider(provider, by: -1)
                            },
                            moveDown: {
                                manager.moveSearchProvider(provider, by: 1)
                            },
                            remove: {
                                manager.removeSearchProvider(provider)
                            }
                        )
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }

    private var tagsTab: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Hitomi excluded tags", text: $manager.hitomiExcludedTagsText)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.saveHitomiExcludedTags()
                } label: {
                    Image(systemName: "checkmark")
                }
                .help("Save excluded tags")
                Button {
                    manager.clearHitomiExcludedTags()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(manager.hitomiExcludedTagsText.trimmed.isEmpty)
                .help("Clear excluded tags")
            }

            HStack(spacing: 6) {
                Image(systemName: "character.book.closed")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Translate tag", text: $manager.searchTagTranslationInput)
                    .textFieldStyle(.roundedBorder)
                Button {
                    manager.translateSearchTagInput()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .help("Translate tag")
                Button {
                    manager.insertTranslatedSearchTag()
                } label: {
                    Image(systemName: "plus")
                }
                .help("Insert translated tag")
                Button {
                    manager.replaceSearchQueryWithTranslatedTag()
                } label: {
                    Image(systemName: "arrow.left.arrow.right")
                }
                .help("Replace query")
                Button {
                    manager.clearSearchTagTranslation()
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .disabled(manager.searchTagTranslationInput.trimmed.isEmpty && manager.searchTagTranslationOutput.trimmed.isEmpty)
                .help("Clear translation")
            }

            if !manager.searchTagTranslationOutput.trimmed.isEmpty {
                Text(manager.searchTagTranslationOutput)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            if manager.searchTagAutocompleteSuggestions.isEmpty {
                Text("No tag suggestions")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(manager.searchTagAutocompleteSuggestions.prefix(50)) { suggestion in
                        HStack(spacing: 8) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(suggestion.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .lineLimit(1)
                                Text(suggestion.token)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Button {
                                manager.applySearchTagSuggestion(suggestion)
                            } label: {
                                Image(systemName: "checkmark.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Use suggestion")
                            Button {
                                manager.insertSearchTagSuggestion(suggestion)
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .help("Insert suggestion")
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(.top, 10)
    }
}

struct MetadataFinderView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let results = manager.metadataFinderResults()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Finder", systemImage: "magnifyingglass")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(results.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            VStack(alignment: .leading, spacing: 10) {
                Picker("Field", selection: $manager.metadataFinderField) {
                    ForEach(MetadataFinderField.allCases) { field in
                        Text(field.label).tag(field)
                    }
                }
                .pickerStyle(.segmented)

                HStack(spacing: 8) {
                    TextField("Search \(manager.metadataFinderField.label.lowercased())", text: $manager.metadataFinderQuery)
                        .textFieldStyle(.roundedBorder)
                    Picker("Mode", selection: $manager.metadataFinderMode) {
                        ForEach(MetadataFinderMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .frame(width: 140)
                }
            }

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if results.isEmpty {
                        Text("No matches")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        ForEach(results) { result in
                            MetadataFinderResultRow(result: result) {
                                copy(DownloadManager.metadataFinderSearchToken(result))
                            } apply: {
                                manager.applyMetadataFinderResult(result)
                            }
                        }
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .padding(20)
        .frame(width: 760)
        .frame(minHeight: 540)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MetadataFinderResultRow: View {
    var result: MetadataFinderResult
    var copy: () -> Void
    var apply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.value)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.medium)
                    Text("\(result.totalCount)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                copy()
            } label: {
                Image(systemName: "doc.on.doc")
            }
            .help("Copy search token")
            Button {
                apply()
            } label: {
                Image(systemName: "arrow.turn.down.left")
            }
            .help("Use in search")
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .textSelection(.enabled)
    }

    private var detailText: String {
        let pieces = [
            result.queueCount > 0 ? "\(result.queueCount) queue" : nil,
            result.historyCount > 0 ? "\(result.historyCount) history" : nil,
            result.score.map { "score \($0)" },
            result.sampleTitle.trimmed.isEmpty ? nil : result.sampleTitle
        ].compactMap { $0 }
        return pieces.joined(separator: " · ")
    }
}

struct MetadataAnalysisView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let entries = manager.metadataAnalysisEntries()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Label("Analysis", systemImage: "chart.pie")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(entries.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Picker("Field", selection: $manager.metadataAnalysisField) {
                ForEach(MetadataAnalysisField.allCases) { field in
                    Text(field.label).tag(field)
                }
            }
            .pickerStyle(.segmented)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Text("Value")
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Total")
                        .frame(width: 56, alignment: .trailing)
                    Text("Queue")
                        .frame(width: 56, alignment: .trailing)
                    Text("History")
                        .frame(width: 64, alignment: .trailing)
                    Text("Token")
                        .frame(width: 92, alignment: .center)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(nsColor: .controlBackgroundColor))

                Divider()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        if entries.isEmpty {
                            Text("No metadata")
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            ForEach(entries) { entry in
                                MetadataAnalysisEntryRow(entry: entry) {
                                    copy(DownloadManager.metadataAnalysisSearchToken(entry))
                                } apply: {
                                    manager.applyMetadataAnalysisEntry(entry)
                                }
                                Divider()
                            }
                        }
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor))
            )
        }
        .padding(20)
        .frame(width: 820)
        .frame(minHeight: 560)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct MetadataAnalysisEntryRow: View {
    var entry: MetadataAnalysisEntry
    var copy: () -> Void
    var apply: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(entry.value)
                    .font(.system(.body, design: .rounded))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(detailText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text("\(entry.totalCount)")
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
            Text("\(entry.queueCount)")
                .frame(width: 56, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text("\(entry.historyCount)")
                .frame(width: 64, alignment: .trailing)
                .monospacedDigit()
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Button {
                    copy()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .help("Copy search token")

                Button {
                    apply()
                } label: {
                    Image(systemName: "arrow.turn.down.left")
                }
                .help("Use in search")
            }
            .buttonStyle(.borderless)
            .frame(width: 92)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .textSelection(.enabled)
    }

    private var detailText: String {
        let pieces = [
            entry.sampleTitle.trimmed.isEmpty ? nil : entry.sampleTitle,
            entry.sampleSource.trimmed.isEmpty ? nil : entry.sampleSource
        ].compactMap { $0 }
        return pieces.isEmpty ? DownloadManager.metadataAnalysisSearchToken(entry) : pieces.joined(separator: " · ")
    }
}

struct AboutView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let about = DownloadManager.appAboutInfo()

        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(nsColor: .labelColor))
                    Text("H")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                }
                .frame(width: 64, height: 64)

                VStack(alignment: .leading, spacing: 4) {
                    Text(about.displayName)
                        .font(.title2)
                        .fontWeight(.semibold)
                    Text(AppLocalization.format(
                        "Current: %@",
                        language: manager.interfaceLanguage,
                        about.currentVersionText
                    ))
                        .font(.subheadline)
                    Text(AppLocalization.format(
                        "Latest: %@",
                        language: manager.interfaceLanguage,
                        localized(about.latestVersionText)
                    ))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    AboutPanel(title: localized("About")) {
                        Text(localized(about.developedBy))
                        Text("\(about.architecture) · macOS \(about.minimumSystemVersion)+")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }

                    AboutPanel(title: localized("Licenses")) {
                        Text(localized(about.licenseSummary))
                    }

                    AboutPanel(title: localized("History")) {
                        Text(localized(about.historySummary))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Button {
                    copy(about.currentVersionText)
                } label: {
                    Label(localized("Copy Version"), systemImage: "doc.on.doc")
                }
                .accessibilityLabel(localized("Copy Version"))
                Spacer()
            }
        }
        .padding(20)
        .frame(width: 620, height: 620)
        .environment(\.locale, manager.interfaceLanguage.locale)
        .accessibilityIdentifier("auxiliary.about")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct AboutPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Help", systemImage: "questionmark.circle")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    HelpPanel(title: "Add URLs") {
                        Text("Paste URLs into the main input and use Add or Start Queue. Empty Add can read supported URLs from the clipboard.")
                        Text("Task rows expose Info, Edit, Comment, Retry, PDF, ZIP/CBZ, Move, Delete, and browser viewing actions.")
                    }

                    HelpPanel(title: "Original-Style Helper Windows") {
                        Text("Use Log, Dirs, Finder, Analysis, History, Search, Clipboard, Browser, Text, and Pages from the toolbar, app menu, or local WebUI.")
                    }

                    HelpPanel(title: "HTTP API") {
                        Text("Enable the local HTTP API to use /webui, /docs, /about, /help, and JSON routes such as /api/about and /api/help.")
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .frame(width: 620, height: 520)
    }
}

private struct HelpPanel<Content: View>: View {
    var title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            content()
                .font(.system(size: 13))
                .foregroundStyle(.primary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ArtistRecommendationsView: View {
    @EnvironmentObject private var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let recommendations = manager.visibleArtistRecommendations()

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label(localized("Artist Recommendations"), systemImage: "person.2")
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Text("\(recommendations.count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button(localized("Done")) {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .accessibilityLabel(localized("Done"))
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField(localized("Filter artists"), text: $manager.artistRecommendationFilter)
                    .textFieldStyle(.roundedBorder)
                if !manager.artistRecommendationFilter.trimmed.isEmpty {
                    Button {
                        manager.clearArtistRecommendationFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help(localized("Clear filter"))
                }
                Button {
                    manager.clearHiddenArtistRecommendations()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(manager.hiddenArtistRecommendationIDs.isEmpty)
                .help(localized("Restore hidden artists"))
            }

            Divider()

            if recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("No artist signals yet"))
                        .font(.headline)
                    if !manager.artistRecommendationFilter.trimmed.isEmpty || !manager.hiddenArtistRecommendationIDs.isEmpty {
                        Text(localized("Clear the filter or restore hidden artists to show more recommendations."))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                List {
                    ForEach(recommendations) { recommendation in
                        ArtistRecommendationRow(
                            recommendation: recommendation,
                            language: manager.interfaceLanguage
                        ) {
                            manager.applyArtistRecommendation(recommendation)
                            dismiss()
                        } copy: {
                            manager.copyArtistRecommendation(recommendation)
                        } hide: {
                            manager.hideArtistRecommendation(recommendation)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .frame(width: 640, height: 560)
        .accessibilityIdentifier("auxiliary.artist-recommendations")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }
}

struct HitomiTasterWizardView: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        let results = manager.visibleHitomiTasterResults()

        VStack(spacing: 0) {
            header(results: results)
            Divider()
            HSplitView {
                trainingPane
                    .frame(minWidth: 310, idealWidth: 360)
                resultsPane(results: results)
                    .frame(minWidth: 560)
            }
        }
        .frame(width: 980, height: 660)
        .onAppear {
            manager.hitomiTasterReferenceCount = DownloadManager.hitomiTasterReferenceCount(
                jobs: manager.jobs,
                history: manager.history,
                bookmarks: manager.bookmarks
            )
        }
    }

    private func header(results: [HitomiTasterResult]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label("Hitomi Taster", systemImage: "brain.head.profile")
                    .font(.headline)
                Text(manager.hitomiTasterModel.originalLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    manager.showingHitomiTaster = false
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("Close Hitomi Taster")
            }

            HStack(spacing: 8) {
                Picker("Model", selection: $manager.hitomiTasterModel) {
                    ForEach(HitomiTasterModel.allCases) { model in
                        Text(model.label)
                            .tag(model)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 210)

                Button {
                    manager.trainHitomiTaster()
                } label: {
                    Label("Train", systemImage: "play.fill")
                }
                .disabled(manager.hitomiTasterReferenceCount < manager.hitomiTasterModel.minimumReferenceCount)

                Button {
                    manager.exportHitomiTasterResults()
                } label: {
                    Image(systemName: "square.and.arrow.down")
                }
                .disabled(manager.hitomiTasterResults.isEmpty)
                .help("Save results as XLSX")

                Button {
                    manager.showingHitomiTaster = false
                    manager.showingArtistRecommendations = true
                } label: {
                    Image(systemName: "person.2")
                }
                .help("Open artist recommendations")

                Spacer()
                Label("\(manager.hitomiTasterReferenceCount)", systemImage: "books.vertical")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label("\(results.count)", systemImage: "person.3")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Label(accuracyText, systemImage: "target")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(.bar)
    }

    private var trainingPane: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Model")
                    .font(.headline)
                Text(manager.hitomiTasterModel.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Needs \(manager.hitomiTasterModel.minimumReferenceCount) reference works.")
                    .font(.caption2)
                    .foregroundStyle(referenceColor)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(manager.hitomiTasterStatus)
                        .font(.subheadline)
                    Spacer()
                    Text("\(Int((manager.hitomiTasterProgress * 100).rounded()))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                ProgressView(value: manager.hitomiTasterProgress)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Training Log")
                    .font(.headline)
                ScrollView {
                    VStack(alignment: .leading, spacing: 5) {
                        if manager.hitomiTasterTrainingLog.isEmpty {
                            Text("Choose a model and train from local queue, history, and artist-tagged bookmarks.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(manager.hitomiTasterTrainingLog.enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .foregroundStyle(line.hasPrefix("[ERROR]") ? .red : .primary)
                            }
                        }
                    }
                    .font(.system(size: 12, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                }
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }

            Spacer()
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
    }

    private func resultsPane(results: [HitomiTasterResult]) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                TextField("Filter results", text: $manager.hitomiTasterFilter)
                    .textFieldStyle(.roundedBorder)
                if !manager.hitomiTasterFilter.trimmed.isEmpty {
                    Button {
                        manager.clearHitomiTasterFilter()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.borderless)
                    .help("Clear filter")
                }
                Button {
                    manager.clearHiddenArtistRecommendations()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .disabled(manager.hiddenArtistRecommendationIDs.isEmpty)
                .help("Restore hidden artists")
            }
            .padding(12)

            Divider()

            if results.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "brain")
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(manager.hitomiTasterResults.isEmpty ? "No Results Yet" : "No Matching Artists")
                        .font(.headline)
                    Text(manager.hitomiTasterResults.isEmpty ? "Train the model to classify candidate artists." : "Clear the filter or restore hidden artists.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(results) { result in
                        HitomiTasterResultRow(result: result) {
                            manager.applyHitomiTasterResult(result)
                            manager.showingHitomiTaster = false
                        } copy: {
                            manager.copyHitomiTasterResult(result)
                        } hide: {
                            manager.hideHitomiTasterResult(result)
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var referenceColor: Color {
        manager.hitomiTasterReferenceCount >= manager.hitomiTasterModel.minimumReferenceCount ? .secondary : .orange
    }

    private var accuracyText: String {
        manager.hitomiTasterAccuracy > 0 ? "\(String(format: "%.1f", manager.hitomiTasterAccuracy))%" : "Not trained"
    }
}

struct HitomiTasterResultRow: View {
    let result: HitomiTasterResult
    let apply: () -> Void
    let copy: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text("\(result.rank)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 28, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(result.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(scoreText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(confidenceText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(signalText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !result.relatedTerms.isEmpty {
                    Text(result.relatedTerms.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !result.exampleTitle.isEmpty {
                    Text(result.exampleTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help("Copy artist")

            Button(action: apply) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Use as search query")

            Button(action: hide) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Hide result")
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                apply()
            } label: {
                Label("Use as Search Query", systemImage: "magnifyingglass")
            }
            Button {
                copy()
            } label: {
                Label("Copy Artist", systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                hide()
            } label: {
                Label("Hide", systemImage: "xmark.circle")
            }
        }
    }

    private var scoreText: String {
        "score \(String(format: "%.2f", result.adjustedScore))"
    }

    private var confidenceText: String {
        "acc \(String(format: "%.1f", result.confidence))%"
    }

    private var signalText: String {
        [
            result.jobCount > 0 ? "\(result.jobCount) jobs" : nil,
            result.historyCount > 0 ? "\(result.historyCount) history" : nil,
            result.bookmarkCount > 0 ? "\(result.bookmarkCount) bookmarks" : nil,
            result.queryToken
        ].compactMap { $0 }.joined(separator: " - ")
    }
}

struct ArtistRecommendationRow: View {
    let recommendation: ArtistRecommendation
    let language: AppInterfaceLanguage
    let apply: () -> Void
    let copy: () -> Void
    let hide: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(recommendation.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text(scoreText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Text(countText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if !recommendation.relatedTerms.isEmpty {
                    Text(recommendation.relatedTerms.joined(separator: " / "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if !recommendation.exampleTitle.isEmpty {
                    Text(recommendation.exampleTitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Button(action: copy) {
                Image(systemName: "doc.on.doc")
            }
            .buttonStyle(.borderless)
            .help(localized("Copy artist"))

            Button(action: apply) {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help(localized("Use as search query"))

            Button(action: hide) {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help(localized("Hide recommendation"))
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button {
                apply()
            } label: {
                Label(localized("Use as Search Query"), systemImage: "magnifyingglass")
            }
            Button {
                copy()
            } label: {
                Label(localized("Copy Artist"), systemImage: "doc.on.doc")
            }
            Button(role: .destructive) {
                hide()
            } label: {
                Label(localized("Hide"), systemImage: "xmark.circle")
            }
        }
    }

    private var scoreText: String {
        String(format: "%.1f", recommendation.score)
    }

    private var countText: String {
        let parts = [
            recommendation.jobCount > 0
                ? AppLocalization.format("%@ jobs", language: language, String(recommendation.jobCount))
                : nil,
            recommendation.historyCount > 0
                ? AppLocalization.format("%@ history", language: language, String(recommendation.historyCount))
                : nil,
            recommendation.bookmarkCount > 0
                ? AppLocalization.format("%@ bookmarks", language: language, String(recommendation.bookmarkCount))
                : nil
        ].compactMap { $0 }
        return parts.isEmpty ? recommendation.queryToken : parts.joined(separator: " - ")
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: language)
    }
}

struct BookmarkRow: View {
    let bookmark: URLBookmark
    let enqueue: () -> Void
    let edit: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add bookmark to queue")

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(bookmark.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if !metadataText.isEmpty {
                    Text(metadataText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            Spacer()

            Button(action: edit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("Edit bookmark")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove bookmark")
        }
        .padding(.vertical, 4)
    }

    private var metadataText: String {
        let tags = bookmark.tags.map { "#\($0)" }.joined(separator: " ")
        let note = bookmark.note.trimmed
        if tags.isEmpty { return note }
        if note.isEmpty { return tags }
        return "\(tags) - \(note)"
    }
}

struct BookmarkEditSheet: View {
    let url: String
    @Binding var title: String
    @Binding var tags: String
    @Binding var note: String
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Bookmark")
                .font(.headline)

            Text(url)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            TextField("Title", text: $title)
                .textFieldStyle(.roundedBorder)

            TextField("Tags", text: $tags)
                .textFieldStyle(.roundedBorder)

            TextEditor(text: $note)
                .font(.system(size: 12))
                .frame(minHeight: 90)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 440)
    }
}

struct JobEditSheet: View {
    @Binding var title: String
    @Binding var source: String
    @Binding var input: String
    @Binding var outputPath: String
    @Binding var artist: String
    @Binding var zipFile: String
    @Binding var status: JobStatus
    @Binding var type: String
    @Binding var site: String
    @Binding var date: String
    @Binding var range: String
    let names: String
    @Binding var comment: String
    let thumbnailImage: NSImage?
    let thumbnailIsCustom: Bool
    let thumbnailMessage: String
    let selectThumbnail: () -> Void
    let saveThumbnail: () -> Void
    let resetThumbnail: () -> Void
    let cancel: () -> Void
    let save: () -> Void

    private let statusOptions: [JobStatus] = [.queued, .finished, .failed, .cancelled]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Edit Job")
                    .font(.headline)
                Spacer()
                Picker("Status", selection: $status) {
                    ForEach(statusOptions, id: \.self) { option in
                        Text(option.rawValue).tag(option)
                    }
                }
                .frame(width: 190)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    GroupBox("Thumbnail") {
                        HStack(spacing: 12) {
                            Button(action: selectThumbnail) {
                                JobEditThumbnailPreview(image: thumbnailImage)
                            }
                            .buttonStyle(.plain)
                            .help("Select thumbnail")
                            .accessibilityLabel("Select thumbnail")
                            .contextMenu {
                                Button(action: selectThumbnail) {
                                    Label("Select Thumbnail...", systemImage: "photo.badge.plus")
                                }
                                Button(action: saveThumbnail) {
                                    Label("Save Thumbnail As...", systemImage: "square.and.arrow.down")
                                }
                                .disabled(thumbnailImage == nil)
                                Button(action: resetThumbnail) {
                                    Label("Use Automatic Thumbnail", systemImage: "arrow.counterclockwise")
                                }
                                .disabled(!thumbnailIsCustom)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Label(
                                    thumbnailMessage,
                                    systemImage: thumbnailIsCustom ? "pin.fill" : "photo"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                                HStack(spacing: 6) {
                                    Button(action: selectThumbnail) {
                                        Image(systemName: "photo.badge.plus")
                                            .frame(width: 24, height: 22)
                                    }
                                    .help("Select thumbnail")
                                    .accessibilityLabel("Select thumbnail")

                                    Button(action: saveThumbnail) {
                                        Image(systemName: "square.and.arrow.down")
                                            .frame(width: 24, height: 22)
                                    }
                                    .disabled(thumbnailImage == nil)
                                    .help("Save thumbnail as")
                                    .accessibilityLabel("Save thumbnail as")

                                    Button(action: resetThumbnail) {
                                        Image(systemName: "arrow.counterclockwise")
                                            .frame(width: 24, height: 22)
                                    }
                                    .disabled(!thumbnailIsCustom)
                                    .help("Use automatic thumbnail")
                                    .accessibilityLabel("Use automatic thumbnail")
                                }
                                .buttonStyle(.borderless)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.top, 2)
                    }

                    GroupBox("Source") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Input", text: $input)
                                .textFieldStyle(.roundedBorder)
                            TextField("URL", text: $source)
                                .textFieldStyle(.roundedBorder)
                            TextField("Folder", text: $outputPath)
                                .textFieldStyle(.roundedBorder)
                        }
                        .padding(.top, 2)
                    }

                    GroupBox("Metadata") {
                        Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 8) {
                            GridRow {
                                Text("Title")
                                    .foregroundStyle(.secondary)
                                TextField("Title", text: $title)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Artist")
                                    .foregroundStyle(.secondary)
                                TextField("Artist", text: $artist)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Zip")
                                    .foregroundStyle(.secondary)
                                TextField("Zip file", text: $zipFile)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Type")
                                    .foregroundStyle(.secondary)
                                TextField("Type", text: $type)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Site")
                                    .foregroundStyle(.secondary)
                                TextField("Site", text: $site)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Date")
                                    .foregroundStyle(.secondary)
                                TextField("Date", text: $date)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("Range")
                                    .foregroundStyle(.secondary)
                                TextField("Range", text: $range)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 2)
                    }

                    GroupBox("Names") {
                        TextEditor(text: .constant(names.isEmpty ? "No output names" : names))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(names.isEmpty ? .secondary : .primary)
                            .frame(minHeight: 84)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.18))
                            )
                    }

                    GroupBox("Comment") {
                        TextEditor(text: $comment)
                            .font(.system(size: 12))
                            .frame(minHeight: 110)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.secondary.opacity(0.25))
                            )
                    }
                }
            }
            .frame(minHeight: 420)

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 620, height: 640)
    }
}

private struct JobEditThumbnailPreview: View {
    let image: NSImage?

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)

            if let image {
                GeometryReader { proxy in
                    ZStack {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .scaleEffect(1.14)
                            .blur(radius: 10, opaque: true)
                            .opacity(0.62)

                        Color.black.opacity(0.08)

                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                }
            } else {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(width: 112, height: 72)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(
            RoundedRectangle(cornerRadius: 5)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }
}

struct PageSelectorSheet: View {
    @ObservedObject var manager: DownloadManager

    private var title: String {
        manager.pageSelectorJob?.title ?? "Pages"
    }

    private var source: String {
        manager.pageSelectorJob?.source ?? ""
    }

    private var canEdit: Bool {
        guard let status = manager.pageSelectorJob?.status else { return false }
        return status != .resolving && status != .downloading
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Pages", systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Text(manager.pageSelectorMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 8) {
                TextField("1-3,5", text: Binding(
                    get: { manager.pageSelectorRangeText },
                    set: { manager.setPageSelectorRangeText($0) }
                ))
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .disabled(!canEdit)

                Button {
                    manager.selectAllPageSelectorItems()
                } label: {
                    Label("All", systemImage: "checkmark.circle")
                }
                .disabled(!canEdit)
            }

            if manager.pageSelectorItems.isEmpty {
                Text("No pages")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                List {
                    ForEach(manager.pageSelectorItems) { item in
                        Toggle(isOn: Binding(
                            get: { manager.pageSelectorSelectedIndexes.contains(item.index) },
                            set: { manager.setPageSelectorItem(item.index, selected: $0) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("[ \(String(format: "%02d", item.page)) ] \(item.title)")
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                if !item.detail.trimmed.isEmpty {
                                    Text(item.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                }
                            }
                        }
                        .toggleStyle(.checkbox)
                        .disabled(!canEdit)
                    }
                }
                .listStyle(.inset)
                .frame(minHeight: 320)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    manager.cancelPageSelector()
                }
                .keyboardShortcut(.cancelAction)
                Button("OK") {
                    manager.savePageSelector()
                }
                .disabled(!canEdit)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 580, height: 620)
    }
}

struct JobCommentSheet: View {
    let title: String
    let source: String
    @Binding var comment: String
    let cancel: () -> Void
    let save: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Job Comment")
                .font(.headline)

            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(source)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)

            TextEditor(text: $comment)
                .font(.system(size: 12))
                .frame(minHeight: 130)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.25))
                )

            HStack {
                Spacer()
                Button("Cancel", action: cancel)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(16)
        .frame(width: 420)
    }
}

enum JobDisplayMetadata {
    static func durationText(for job: DownloadJob) -> String? {
        guard let seconds = durationSeconds(for: job), seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return formattedDuration(seconds)
    }

    static func byteCountText(for job: DownloadJob) -> String? {
        guard let byteCount = byteCount(for: job), byteCount > 0 else {
            return nil
        }
        return ByteCountFormatter.string(fromByteCount: byteCount, countStyle: .file)
    }

    static func etaText(for job: DownloadJob) -> String? {
        guard job.status == .queued || job.status == .resolving || job.status == .downloading else {
            return nil
        }
        guard let seconds = etaSeconds(for: job), seconds.isFinite, seconds >= 0 else {
            return nil
        }
        return "ETA \(formattedDuration(seconds))"
    }

    static func transferProgressText(for job: DownloadJob) -> String? {
        guard job.status == .downloading else { return nil }
        let metadata = lowercasedMetadata(for: job)
        let isIndeterminateLive = ["live_active", "live_polling"].contains { key in
            ["1", "true", "yes", "on"].contains(metadata[key]?.trimmed.lowercased() ?? "")
        }
        let hasActiveByteTransfer = ["1", "true", "yes", "on"].contains(
            metadata["transfer_active"]?.trimmed.lowercased() ?? ""
        )
        guard hasActiveByteTransfer || job.progress > 0 else {
            return nil
        }

        var parts: [String] = []
        let itemIndex = Int(metadata["transfer_item_index"] ?? "") ?? 1
        let itemCount = Int(metadata["transfer_item_count"] ?? "") ?? 1
        if !isIndeterminateLive, itemCount > 1 {
            parts.append("\(min(itemCount, max(1, itemIndex)))/\(itemCount)")
        } else if !isIndeterminateLive, job.total > 1 {
            parts.append("\(min(job.total, max(0, job.completed)))/\(job.total)")
        }

        let transferFraction = metadata["transfer_fraction"].flatMap(Double.init)
        let total = byteCount(for: job)
        let downloaded = downloadedByteCount(from: metadata)
        let fraction: Double?
        if let transferFraction {
            fraction = transferFraction
        } else if let downloaded, let total, total > 0 {
            fraction = Double(downloaded) / Double(total)
        } else if !isIndeterminateLive {
            fraction = job.progress > 0 ? job.progress : nil
        } else {
            fraction = nil
        }
        if let fraction, fraction.isFinite {
            parts.append(String(format: "%.0f%%", min(1, max(0, fraction)) * 100))
        }

        if let downloaded, downloaded >= 0 {
            let downloadedText = ByteCountFormatter.string(fromByteCount: downloaded, countStyle: .file)
            if let total, total > 0 {
                let totalText = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
                parts.append("\(downloadedText) / \(totalText)")
            } else {
                parts.append(downloadedText)
            }
        }

        if let speed = speedBytesPerSecond(from: metadata), speed.isFinite, speed > 0 {
            let speedText = ByteCountFormatter.string(
                fromByteCount: Int64(min(Double(Int64.max), speed)),
                countStyle: .file
            )
            parts.append("\(speedText)/s")
        }
        if let seconds = etaSeconds(for: job), seconds.isFinite, seconds >= 0 {
            parts.append("ETA \(formattedDuration(seconds))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    static func downloadDateText(for job: DownloadJob) -> String? {
        guard job.status == .finished,
              let date = completionDate(for: job) else {
            return nil
        }
        return DateFormatter.localizedString(from: date, dateStyle: .short, timeStyle: .short)
    }

    static func completionDate(for job: DownloadJob) -> Date? {
        let keys = ["download_completed_at", "manual_completed_at", "completed_at"]
        let isoFormatter = ISO8601DateFormatter()
        for key in keys {
            guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { continue }
            if let date = isoFormatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func byteCount(for job: DownloadJob) -> Int64? {
        let metadata = lowercasedMetadata(for: job)
        let keys = [
            "byte_count",
            "content_length",
            "filesize",
            "file_size",
            "total_bytes",
            "expected_bytes",
            "size"
        ]
        for key in keys {
            if let value = metadata[key].flatMap(byteCount(from:)) {
                return value
            }
        }
        return nil
    }

    private static func etaSeconds(for job: DownloadJob) -> Double? {
        let metadata = lowercasedMetadata(for: job)
        for key in ["eta_seconds", "eta", "remaining_seconds", "remaining", "time_remaining"] {
            if let value = metadata[key].flatMap(durationSeconds) {
                return value
            }
        }
        if let raw = metadata["eta_ms"]?.trimmed,
           let milliseconds = Double(raw),
           milliseconds >= 0 {
            return milliseconds / 1000
        }

        guard let byteCount = byteCount(for: job),
              let bytesPerSecond = speedBytesPerSecond(from: metadata),
              bytesPerSecond > 0 else {
            return nil
        }

        if let downloaded = downloadedByteCount(from: metadata), downloaded >= 0 {
            return max(0, Double(byteCount - min(byteCount, downloaded)) / bytesPerSecond)
        }

        guard job.progress > 0, job.progress < 1 else {
            return nil
        }
        return Double(byteCount) * max(0, 1 - job.progress) / bytesPerSecond
    }

    private static func downloadedByteCount(from metadata: [String: String]) -> Int64? {
        for key in ["downloaded_bytes", "downloaded", "completed_bytes", "received_bytes"] {
            if let value = metadata[key].flatMap(byteCount(from:)) {
                return value
            }
        }
        return nil
    }

    private static func speedBytesPerSecond(from metadata: [String: String]) -> Double? {
        for key in ["speed_bytes_per_second", "bytes_per_second", "download_speed", "speed", "bps"] {
            if let raw = metadata[key]?.trimmed,
               let byteCount = byteCount(from: raw) {
                return Double(byteCount)
            }
        }
        return nil
    }

    private static func byteCount(from raw: String) -> Int64? {
        var value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }
        value = value.replacingOccurrences(of: ",", with: "")
        if let direct = Int64(value), direct >= 0 {
            return direct
        }

        guard let regex = try? NSRegularExpression(
            pattern: #"^\s*([0-9]+(?:\.[0-9]+)?)\s*([kmgtp]?i?b|bytes?|[kmgtp])?"#,
            options: [.caseInsensitive]
        ) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              let numberRange = Range(match.range(at: 1), in: value),
              let number = Double(value[numberRange]),
              number >= 0 else {
            return nil
        }
        let unit = Range(match.range(at: 2), in: value).map { String(value[$0]) } ?? ""
        let multiplier: Double
        switch unit {
        case "", "b", "byte", "bytes":
            multiplier = 1
        case "k", "kb":
            multiplier = 1_000
        case "m", "mb":
            multiplier = 1_000_000
        case "g", "gb":
            multiplier = 1_000_000_000
        case "t", "tb":
            multiplier = 1_000_000_000_000
        case "p", "pb":
            multiplier = 1_000_000_000_000_000
        case "kib":
            multiplier = 1_024
        case "mib":
            multiplier = 1_048_576
        case "gib":
            multiplier = 1_073_741_824
        case "tib":
            multiplier = 1_099_511_627_776
        case "pib":
            multiplier = 1_125_899_906_842_624
        default:
            return nil
        }
        let bytes = number * multiplier
        guard bytes <= Double(Int64.max) else {
            return nil
        }
        return Int64(bytes.rounded())
    }

    private static func durationSeconds(for job: DownloadJob) -> Double? {
        let metadata = lowercasedMetadata(for: job)
        let isLive = ["live", "is_live", "was_live"].contains { key in
            ["1", "true", "yes", "on"].contains(metadata[key]?.trimmed.lowercased() ?? "")
        }
        if isLive,
           let value = metadata["live_recorded_duration"].flatMap(durationSeconds) {
            return value
        }
        if let value = metadata["duration_seconds"].flatMap(durationSeconds) {
            return value
        }
        if let value = metadata["duration"].flatMap(durationSeconds) {
            return value
        }
        if let value = metadata["duration_string"].flatMap(durationSeconds) {
            return value
        }
        if let raw = metadata["duration_ms"]?.trimmed,
           let milliseconds = Double(raw),
           milliseconds >= 0 {
            return milliseconds / 1000
        }
        return nil
    }

    private static func lowercasedMetadata(for job: DownloadJob) -> [String: String] {
        var metadata: [String: String] = [:]
        for (key, value) in job.metadata {
            metadata[key.lowercased()] = value
        }
        return metadata
    }

    private static func durationSeconds(from raw: String) -> Double? {
        let value = raw.trimmed.lowercased()
        guard !value.isEmpty else { return nil }

        if value.contains(":") {
            let parts = value.split(separator: ":").map(String.init)
            guard parts.count >= 2, parts.count <= 3 else { return nil }
            var multiplier: Double = 1
            var total: Double = 0
            for part in parts.reversed() {
                guard let component = Double(part.trimmed), component >= 0 else { return nil }
                total += component * multiplier
                multiplier *= 60
            }
            return total
        }

        if let seconds = compoundDurationSeconds(from: value) {
            return seconds
        }

        if let number = Double(value), number >= 0 {
            return number
        }
        return nil
    }

    private static func compoundDurationSeconds(from value: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: #"([0-9]+(?:\.[0-9]+)?)\s*(ms|h|m|s)"#) else {
            return nil
        }
        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        let matches = regex.matches(in: value, range: range)
        guard !matches.isEmpty else { return nil }

        var consumed = ""
        var total: Double = 0
        for match in matches {
            guard let numberRange = Range(match.range(at: 1), in: value),
                  let unitRange = Range(match.range(at: 2), in: value),
                  let wholeRange = Range(match.range, in: value),
                  let number = Double(String(value[numberRange])) else {
                return nil
            }
            consumed += String(value[wholeRange])
            switch String(value[unitRange]) {
            case "ms":
                total += number / 1000
            case "h":
                total += number * 3600
            case "m":
                total += number * 60
            case "s":
                total += number
            default:
                return nil
            }
        }

        let compactValue = value.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        let compactConsumed = consumed.replacingOccurrences(of: "\\s+", with: "", options: .regularExpression)
        return compactConsumed == compactValue ? total : nil
    }

    private static func formattedDuration(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded()))
        let hours = total / 3_600
        let minutes = (total % 3_600) / 60
        let remaining = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remaining)
        }
        return String(format: "%d:%02d", minutes, remaining)
    }
}

struct HistoryRow: View {
    let entry: DownloadHistoryEntry
    let enqueue: () -> Void
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add history item to queue")

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(entry.source)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: reveal) {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .disabled(entry.outputPath.isEmpty)
            .help("Reveal history output")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove history item")
        }
        .padding(.vertical, 4)
    }
}

struct DuplicateImageGroupRow: View {
    let group: DuplicateImageGroup
    let showsThumbnails: Bool
    let selectedPath: String
    let autoSelectedPath: String
    let select: (String) -> Void
    let reveal: (String) -> Void
    let openFolder: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Image(systemName: "photo.on.rectangle")
                    .foregroundStyle(.secondary)
                    .frame(width: 18)
                Text("\(group.files.count) files")
                    .font(.system(size: 12, weight: .semibold))
                Text(byteCountText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if !resolutionText.isEmpty {
                    Text(resolutionText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let similarityText {
                    Text(similarityText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(String(group.hash.prefix(10)))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }

            if showsThumbnails {
                HStack(spacing: 6) {
                    ForEach(Array(group.files.prefix(3)), id: \.self) { path in
                        DuplicateImageThumbnail(path: path) {
                            select(path)
                            reveal(path)
                        }
                    }
                }
            }

            ForEach(Array(group.files.prefix(3)), id: \.self) { path in
                HStack(spacing: 6) {
                    if isMarked(path) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(markerColor(for: path))
                            .frame(width: 14)
                            .help(markerHelp(for: path))
                    } else {
                        Image(systemName: "circle")
                            .foregroundStyle(.tertiary)
                            .frame(width: 14)
                    }
                    Text(URL(fileURLWithPath: path).lastPathComponent)
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(path)
                    Spacer()
                    Button {
                        select(path)
                        reveal(path)
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .buttonStyle(.borderless)
                    .help("Reveal image")

                    Button {
                        select(path)
                        openFolder(path)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Open containing folder")
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    select(path)
                }
                .onTapGesture(count: 2) {
                    select(path)
                    openFolder(path)
                }
            }

            if group.files.count > 3 {
                Text("+\(group.files.count - 3) more")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if let first = group.files.first {
                Button {
                    select(first)
                    openFolder(first)
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                Button {
                    select(first)
                    reveal(first)
                } label: {
                    Label("Reveal Image", systemImage: "magnifyingglass")
                }
            }
        }
    }

    private var byteCountText: String {
        let minimum = group.minByteCount ?? group.byteCount
        let maximum = group.maxByteCount ?? group.byteCount
        if minimum > 0, maximum > 0, minimum != maximum {
            let low = ByteCountFormatter.string(fromByteCount: minimum, countStyle: .file)
            let high = ByteCountFormatter.string(fromByteCount: maximum, countStyle: .file)
            return "\(low) to \(high)"
        }
        return ByteCountFormatter.string(fromByteCount: group.byteCount, countStyle: .file)
    }

    private func isMarked(_ path: String) -> Bool {
        selectedPath == path || autoSelectedPath == path
    }

    private func markerColor(for path: String) -> Color {
        autoSelectedPath == path ? .red : .accentColor
    }

    private func markerHelp(for path: String) -> String {
        autoSelectedPath == path ? "Auto-selected duplicate candidate" : "Selected duplicate image"
    }

    private var resolutionText: String {
        guard let width = group.width,
              let height = group.height,
              width > 0,
              height > 0 else {
            return ""
        }
        return "\(width)x\(height)"
    }

    private var similarityText: String? {
        guard let similarity = group.similarityPercent,
              similarity < 100 else {
            return nil
        }
        return "~\(similarity)%"
    }
}

private struct DuplicateImageThumbnail: View {
    let path: String
    let reveal: () -> Void

    var body: some View {
        Button(action: reveal) {
            ZStack {
                if let image = NSImage(contentsOfFile: path) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 18))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 44, height: 44)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(.quaternary, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .help(URL(fileURLWithPath: path).lastPathComponent)
    }
}

struct SearchProviderRow: View {
    let provider: SearchProvider
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass.circle")
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(provider.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(provider.urlTemplate)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: moveUp) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveUp)
            .help("Move search provider up")

            Button(action: moveDown) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(!canMoveDown)
            .help("Move search provider down")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove search provider")
        }
        .padding(.vertical, 4)
    }
}

struct SearchBookmarkRow: View {
    let bookmark: SearchBookmark
    let apply: () -> Void
    let enqueue: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: apply) {
                Image(systemName: "magnifyingglass.circle")
            }
            .buttonStyle(.borderless)
            .help("Apply search bookmark")

            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add bookmarked search to queue")

            VStack(alignment: .leading, spacing: 3) {
                Text(bookmark.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text("\(bookmark.providerName) · \(bookmark.query)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove search bookmark")
        }
        .padding(.vertical, 4)
    }
}

struct SearchResultRow: View {
    let result: SearchResultLink
    let galleryID: String?
    let metadataCopies: [DownloadManager.SearchResultMetadataCopy]
    let dateText: String?
    let pageCountText: String?
    let isDone: Bool
    let canOpenFirstOutput: Bool
    let enqueue: () -> Void
    let openSource: () -> Void
    let copyURL: () -> Void
    let copyTitle: () -> Void
    let copyMetadata: (DownloadManager.SearchResultMetadataCopy) -> Void
    let openFirstOutput: () -> Void
    let copyGalleryID: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: enqueue) {
                Image(systemName: "plus.circle")
            }
            .buttonStyle(.borderless)
            .help("Add result to queue")

            Button(action: openSource) {
                Image(systemName: "safari")
            }
            .buttonStyle(.borderless)
            .help("Open result link")

            VStack(alignment: .leading, spacing: 3) {
                Text(result.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(result.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hasSecondaryMetadata {
                    HStack(spacing: 8) {
                        if let dateText, !dateText.trimmed.isEmpty {
                            Label(dateText, systemImage: "calendar")
                                .lineLimit(1)
                        }
                        if let pageCountText, !pageCountText.trimmed.isEmpty {
                            Label(pageCountText, systemImage: "doc.text")
                                .lineLimit(1)
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button(action: copyTitle) {
                Image(systemName: "textformat")
            }
            .buttonStyle(.borderless)
            .help("Copy result title")

            Button(action: copyURL) {
                Image(systemName: "link")
            }
            .buttonStyle(.borderless)
            .help("Copy result URL")

            if !metadataCopies.isEmpty {
                Menu {
                    ForEach(metadataCopies) { item in
                        Button("\(item.label): \(item.value)") {
                            copyMetadata(item)
                        }
                    }
                } label: {
                    Image(systemName: "person.text.rectangle")
                }
                .menuStyle(.borderlessButton)
                .help("Copy result metadata")
            }

            if let galleryID {
                Text("#\(galleryID)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Button(action: copyGalleryID) {
                    Image(systemName: "number.circle")
                }
                .buttonStyle(.borderless)
                .help("Copy gallery ID")
            }

            if isDone {
                Label("Done", systemImage: "checkmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.green)
                    .help("Already in queue, history, or saved output")
            }

            Button(action: openFirstOutput) {
                Image(systemName: "doc.viewfinder")
            }
            .buttonStyle(.borderless)
            .disabled(!canOpenFirstOutput)
            .help("Open first output file")
        }
        .padding(.vertical, 4)
    }

    private var hasSecondaryMetadata: Bool {
        !(dateText?.trimmed.isEmpty ?? true) || !(pageCountText?.trimmed.isEmpty ?? true)
    }
}

enum JobStatusStyle {
    static func iconName(for job: DownloadJob) -> String {
        job.partialFailureCounts == nil ? iconName(for: job.status) : "exclamationmark.triangle.fill"
    }

    static func iconName(for status: JobStatus) -> String {
        switch status {
        case .queued: return "clock"
        case .resolving: return "magnifyingglass"
        case .downloading: return "arrow.down"
        case .finished: return "checkmark.circle.fill"
        case .failed: return "xmark.octagon.fill"
        case .cancelled: return "minus.circle.fill"
        }
    }

    static func colorName(for status: JobStatus) -> String {
        switch status {
        case .queued: return "secondary"
        case .resolving: return "blue"
        case .downloading: return "accent"
        case .finished: return "green"
        case .failed: return "red"
        case .cancelled: return "orange"
        }
    }

    static func color(for status: JobStatus) -> Color {
        switch status {
        case .queued: return .secondary
        case .resolving: return .blue
        case .downloading: return .accentColor
        case .finished: return .green
        case .failed: return .red
        case .cancelled: return .orange
        }
    }

    static func color(for job: DownloadJob) -> Color {
        job.partialFailureCounts == nil ? color(for: job.status) : .orange
    }

    static func color(for status: JobStatus, palette: JobStatusColorPalette) -> Color {
        Color(hexRGB: palette.hex(for: status)) ?? color(for: status)
    }

    static func color(for job: DownloadJob, palette: JobStatusColorPalette) -> Color {
        job.partialFailureCounts == nil ? color(for: job.status, palette: palette) : .orange
    }
}

struct FontSettingsView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss

    private let defaultSampleKey = "Sekiya Asami / 1234567890 / Download queue"

    private var fontFamilySelection: Binding<String> {
        Binding(
            get: {
                manager.interfaceFontFamily.isEmpty ? "System" : manager.interfaceFontFamily
            },
            set: { value in
                manager.setInterfaceFontFamily(value == "System" ? "" : value)
            }
        )
    }

    private var previewFont: Font {
        manager.interfaceFont ?? .system(size: CGFloat(manager.interfaceFontSize.pointSize))
    }

    private var sampleText: String {
        localizedFontPreviewText(manager.fontPreviewText)
    }

    private var fontPreviewText: Binding<String> {
        Binding(
            get: { localizedFontPreviewText(manager.fontPreviewText) },
            set: { manager.fontPreviewText = $0 }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Label(localized("Font"), systemImage: "textformat.size")
                    .font(.headline)
                    .accessibilityIdentifier("font-settings.view")

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(localized("Close font settings"))
                .accessibilityIdentifier("font-settings.close")
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .background(.bar)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(localized("Family"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(width: 90, alignment: .leading)

                    Picker("", selection: fontFamilySelection) {
                        ForEach(manager.interfaceFontFamilyOptions, id: \.self) { family in
                            Text(family == "System" ? localized("System") : family).tag(family)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(maxWidth: 300)
                }

                HStack(alignment: .firstTextBaseline, spacing: 14) {
                    Text(localized("Size"))
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(width: 90, alignment: .leading)

                    Picker("", selection: Binding(
                        get: { manager.interfaceFontSize },
                        set: { manager.setInterfaceFontSize($0) }
                    )) {
                        ForEach(AppInterfaceFontSize.allCases, id: \.self) { size in
                            Text(size.label).tag(size)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 330)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text(localized("Sample"))
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    TextEditor(text: fontPreviewText)
                        .font(previewFont)
                        .frame(minHeight: 78)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(.separator, lineWidth: 1)
                        )

                    Text(sampleText)
                        .font(previewFont)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                HStack {
                    Button {
                        manager.resetInterfaceFont()
                    } label: {
                        Label(localized("Reset"), systemImage: "arrow.counterclockwise")
                    }
                    .accessibilityLabel(localized("Reset"))

                    Spacer()

                    Text(manager.interfaceFontSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Button(localized("Done")) {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                    .accessibilityLabel(localized("Done"))
                }
            }
            .padding(18)
        }
        .frame(width: 560, height: 390)
    }

    private func localized(_ key: String) -> String {
        AppLocalization.text(key, language: manager.interfaceLanguage)
    }

    private func localizedFontPreviewText(_ rawValue: String) -> String {
        let value = rawValue.trimmed
        let defaultSamples = Set(
            AppInterfaceLanguage.allCases.map {
                AppLocalization.text(defaultSampleKey, language: $0)
            }
        )
        guard value.isEmpty || defaultSamples.contains(value) else { return rawValue }
        return localized(defaultSampleKey)
    }
}

struct StatusColorPickerView: View {
    @ObservedObject var manager: DownloadManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("Color Picker", systemImage: "paintpalette")
                    .font(.headline)

                Spacer()

                Button {
                    manager.cancelEditingStatusColors()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Close")
            }
            .padding(14)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("Status")
                        .frame(width: 132, alignment: .leading)
                    Text("Current")
                        .frame(width: 64, alignment: .leading)
                    Text("New")
                        .frame(width: 64, alignment: .leading)
                    Text("HEX")
                        .frame(width: 104, alignment: .leading)
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(JobStatus.allCases, id: \.self) { status in
                        statusRow(status)
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Toggle("Only Web Colors", isOn: Binding(
                        get: { manager.statusColorOnlyWebColors },
                        set: { manager.setStatusColorOnlyWebColors($0) }
                    ))
                    .toggleStyle(.checkbox)

                    Spacer()

                    Button("Reset") {
                        manager.resetStatusColorDrafts()
                    }

                    Button("Cancel") {
                        manager.cancelEditingStatusColors()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button("OK") {
                        manager.saveStatusColors()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(14)
        }
        .frame(minWidth: 540)
    }

    private func statusRow(_ status: JobStatus) -> some View {
        HStack(spacing: 12) {
            Label(status.label, systemImage: JobStatusStyle.iconName(for: status))
                .frame(width: 132, alignment: .leading)
                .foregroundStyle(JobStatusStyle.color(for: status, palette: manager.statusColorDraftPalette))

            colorSwatch(manager.jobStatusColorPalette.hex(for: status))
                .frame(width: 64, alignment: .leading)

            colorSwatch(manager.statusColorDraftPalette.hex(for: status))
                .frame(width: 64, alignment: .leading)

            TextField("#RRGGBB", text: Binding(
                get: { manager.statusColorDraftPalette.hex(for: status) },
                set: { manager.setDraftStatusColor($0, for: status) }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: 104)

            ColorPicker("", selection: Binding(
                get: { JobStatusStyle.color(for: status, palette: manager.statusColorDraftPalette) },
                set: { color in
                    if let hex = color.hexRGBString {
                        manager.setDraftStatusColor(hex, for: status)
                    }
                }
            ), supportsOpacity: false)
            .labelsHidden()
            .frame(width: 34)
            .help("Open macOS color picker")

            Spacer(minLength: 0)
        }
    }

    private func colorSwatch(_ hex: String) -> some View {
        let color = Color(hexRGB: hex) ?? .secondary
        return RoundedRectangle(cornerRadius: 4)
            .fill(color)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color(nsColor: .separatorColor))
            )
            .frame(width: 42, height: 22)
            .help(hex)
    }
}

private extension Color {
    init?(hexRGB: String) {
        let normalized = JobStatusColorPalette.normalizedHex(hexRGB, fallback: "")
        guard normalized.count == 7 else { return nil }
        let raw = String(normalized.dropFirst())
        guard let red = Int(raw.prefix(2), radix: 16),
              let green = Int(raw.dropFirst(2).prefix(2), radix: 16),
              let blue = Int(raw.dropFirst(4).prefix(2), radix: 16) else {
            return nil
        }
        self = Color(nsColor: NSColor(
            calibratedRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        ))
    }

    var hexRGBString: String? {
        let color = NSColor(self)
        guard let rgb = color.usingColorSpace(.deviceRGB) else {
            return nil
        }
        let red = max(0, min(255, Int((rgb.redComponent * 255).rounded())))
        let green = max(0, min(255, Int((rgb.greenComponent * 255).rounded())))
        let blue = max(0, min(255, Int((rgb.blueComponent * 255).rounded())))
        return String(format: "#%02X%02X%02X", red, green, blue)
    }
}

struct JobInfoEntry: Identifiable, Equatable {
    let key: String
    let value: String

    var id: String { key }
    var label: String { JobInfoExtras.label(for: key) }
}

enum JobInfoExtras {
    static let preferredExtraKeys = [
        "last_error",
        "failed_segment_index",
        "failed_segment_total",
        "failed_segment_filename",
        "failed_segment_url",
        "skipped_segment_count",
        "skipped_segment_total",
        "skipped_segment_indexes",
        "skipped_segment_filenames",
        "skipped_segment_urls",
        "segment_count",
        "total_segments",
        "media_count",
        "map_count",
        "encrypted_count",
        "encrypted",
        "playlist_url",
        "manifest_url",
        "package_mode",
        "duration_seconds",
        "representation_id",
        "video_representation_id",
        "audio_representation_id",
        "bandwidth",
        "torrent_piece_count",
        "torrent_piece_size",
        "torrent_total_size"
    ]

    private static var preferredExtraKeySet: Set<String> {
        Set(preferredExtraKeys)
    }

    static func summaryEntries(for job: DownloadJob) -> [JobInfoEntry] {
        var entries = [
            JobInfoEntry(key: "status", value: job.statusDisplayText()),
            JobInfoEntry(key: "progress", value: String(format: "%.0f%%", job.progress * 100)),
            JobInfoEntry(key: "completed", value: "\(job.completed) / \(job.total)"),
            JobInfoEntry(key: "pinned", value: job.isPinned ? "Yes" : "No"),
            JobInfoEntry(key: "locked", value: job.isLocked ? "Yes" : "No"),
            JobInfoEntry(key: "message", value: AppLocalization.statusText(job.message)),
            JobInfoEntry(key: "comment", value: job.comment),
            JobInfoEntry(key: "range", value: job.rangeExpression),
            JobInfoEntry(key: "output_path", value: job.outputPath),
            JobInfoEntry(key: "source", value: job.source)
        ]
        if let counts = job.partialFailureCounts {
            entries.insert(
                JobInfoEntry(key: "successful_files", value: "\(counts.succeeded) / \(counts.total)"),
                at: 3
            )
            entries.insert(JobInfoEntry(key: "failed_files", value: String(counts.failed)), at: 4)
        }
        if let size = JobDisplayMetadata.byteCountText(for: job) {
            entries.insert(JobInfoEntry(key: "known_size", value: size), at: 3)
        }
        if let eta = JobDisplayMetadata.etaText(for: job) {
            entries.insert(JobInfoEntry(key: "eta", value: eta), at: 4)
        }
        return entries.filter { !$0.value.trimmed.isEmpty }
    }

    static func extraEntries(for job: DownloadJob) -> [JobInfoEntry] {
        let preferred = preferredExtraKeys.compactMap { key -> JobInfoEntry? in
            guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { return nil }
            return JobInfoEntry(key: key, value: value)
        }

        let dynamic = job.metadata.keys
            .filter { !preferredExtraKeySet.contains($0) && isExtraKey($0) }
            .sorted()
            .compactMap { key -> JobInfoEntry? in
                guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { return nil }
                return JobInfoEntry(key: key, value: value)
            }

        return preferred + dynamic
    }

    static func metadataEntries(for job: DownloadJob) -> [JobInfoEntry] {
        let extraKeys = Set(extraEntries(for: job).map(\.key))
        return job.metadata.keys
            .filter { !extraKeys.contains($0) }
            .sorted()
            .compactMap { key -> JobInfoEntry? in
                guard let value = job.metadata[key]?.trimmed, !value.isEmpty else { return nil }
                return JobInfoEntry(key: key, value: value)
            }
    }

    static func label(for key: String) -> String {
        switch key {
        case "known_size": return "Known Size"
        case "eta": return "ETA"
        case "last_error": return "Last Error"
        case "failed_segment_index": return "Failed Segment"
        case "failed_segment_total": return "Failed Segment Total"
        case "failed_segment_filename": return "Failed Segment File"
        case "failed_segment_url": return "Failed Segment URL"
        case "skipped_segment_count": return "Skipped Segments"
        case "skipped_segment_total": return "Skipped Segment Total"
        case "skipped_segment_indexes": return "Skipped Segment Indexes"
        case "skipped_segment_filenames": return "Skipped Segment Files"
        case "skipped_segment_urls": return "Skipped Segment URLs"
        case "successful_files": return "Successful Files / Total"
        case "failed_files": return "Failed Files"
        case "segment_count": return "Segments"
        case "total_segments": return "Total Segments"
        case "media_count": return "Media"
        case "map_count": return "Init Maps"
        case "encrypted_count": return "Encrypted Segments"
        case "playlist_url": return "Playlist URL"
        case "manifest_url": return "Manifest URL"
        case "package_mode": return "Package Mode"
        case "duration_seconds": return "Duration"
        case "representation_id": return "Representation"
        case "video_representation_id": return "Video Representation"
        case "audio_representation_id": return "Audio Representation"
        case "torrent_piece_count": return "Pieces"
        case "torrent_piece_size": return "Piece Size"
        case "torrent_total_size": return "Torrent Size"
        case "torrent_piece_length": return "Piece Length Bytes"
        case "torrent_total_length": return "Torrent Size Bytes"
        case "output_path": return "Output"
        case "pinned": return "Pinned"
        case "locked": return "Locked"
        case "comment": return "Comment"
        default:
            return key
                .split(separator: "_")
                .map { part in
                    part.prefix(1).uppercased() + part.dropFirst()
                }
                .joined(separator: " ")
        }
    }

    private static func isExtraKey(_ key: String) -> Bool {
        key.hasSuffix("_count") ||
            key.hasSuffix("_url") ||
            key.hasSuffix("_seconds") ||
            key.contains("segment") ||
            key.contains("playlist") ||
            key.contains("manifest") ||
            key.contains("representation")
    }
}

struct JobInfoView: View {
    let job: DownloadJob
    let queueIndex: Int?
    let groupName: String?
    @Environment(\.dismiss) private var dismiss
    @StateObject private var loader = OriginalJobInfoLoader()

    private var document: OriginalJobInfoDocument {
        OriginalJobInfoDocument.make(
            job: job,
            queueIndex: queueIndex,
            groupName: groupName,
            outputFiles: loader.outputFiles
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(job.title)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(job.id.uuidString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(document.plainText, forType: .string)
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help(AppLocalization.text("Copy task information"))

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help(AppLocalization.text("Close"))
            }
            .padding(14)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    diagnosticText(document.propertyLines.joined(separator: "\n"))

                    if !document.galleryLines.isEmpty {
                        infoSection("Gallery") {
                            diagnosticText(document.galleryLines.joined(separator: "\n"))
                        }
                    }

                    infoSection("File Names") {
                        if document.files.isEmpty {
                            diagnosticText("(empty)")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(document.files) { file in
                                diagnosticText(file.displayText)
                                    .foregroundStyle(file.isAvailable ? Color.primary : Color.red)
                            }
                        }
                    }

                    infoSection("URLs") {
                        if document.urls.isEmpty {
                            diagnosticText("(empty)")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(Array(document.urls.enumerated()), id: \.offset) { offset, url in
                                diagnosticText(numbered(offset, url))
                            }
                        }
                    }

                    if !document.messages.isEmpty {
                        infoSection("Messages") {
                            ForEach(Array(document.messages.enumerated()), id: \.offset) { offset, message in
                                diagnosticText(numbered(offset, message))
                            }
                        }
                    }
                }
                .padding(16)
            }
        }
        .frame(minWidth: 700, minHeight: 580)
        .task(id: job.outputPath) {
            await loader.load(outputPath: job.outputPath)
        }
    }

    private func infoSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("[\(title)]")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            content()
        }
        .padding(.top, 22)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func diagnosticText(_ value: String) -> some View {
        Text(value)
            .font(.system(size: 11, design: .monospaced))
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func numbered(_ offset: Int, _ value: String) -> String {
        String(format: "[%04d] %@", offset + 1, value)
    }
}

struct PythonScriptPluginRow: View {
    let plugin: PythonScriptPlugin
    let setEnabled: (Bool) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: plugin.isSession
                ? "doc.badge.clock"
                : (plugin.registeredThemes.isEmpty ? "terminal" : "paintbrush"))
                .foregroundStyle(plugin.lastError == nil ? .secondary : Color.orange)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(plugin.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(plugin.statusSummary)
                    .font(.caption)
                    .foregroundStyle(plugin.lastError == nil ? .secondary : Color.orange)
                    .lineLimit(1)
                Text(plugin.patternSummary)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { plugin.isEnabled },
                set: setEnabled
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .disabled(!plugin.hasCompatibleEntryPoints)
            .help(plugin.isEnabled ? "Disable Python script" : "Enable Python script")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help(plugin.isSession ? "Remove session script" : "Uninstall Python plugin")
        }
        .padding(.vertical, 4)
        .opacity(plugin.isEnabled ? 1 : 0.65)
    }
}

struct SiteRuleRow: View {
    let rule: SiteRule
    let setEnabled: (Bool) -> Void
    let remove: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .foregroundStyle(.secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(rule.name)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { rule.isEnabled },
                set: setEnabled
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .help(rule.isEnabled ? "Disable site rule" : "Enable site rule")

            Button(action: remove) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Remove site rule")
        }
        .padding(.vertical, 4)
        .opacity(rule.isEnabled ? 1 : 0.55)
    }

    private var iconName: String {
        switch rule.handler {
        case .customCommand:
            return "terminal"
        case .headers:
            return "text.badge.checkmark"
        case .ytdlp:
            return "puzzlepiece.extension"
        }
    }

    private var detail: String {
        var parts = [rule.handler.rawValue]
        if !rule.isEnabled {
            parts.insert("off", at: 0)
        }
        if !(rule.urlPattern?.trimmed.isEmpty ?? true) {
            parts.append(rule.urlPattern ?? "")
        }
        if !(rule.refererTemplate?.trimmed.isEmpty ?? true) {
            parts.append("referer")
        }
        if !(rule.userAgent?.trimmed.isEmpty ?? true) {
            parts.append("user-agent")
        }
        switch rule.archiveMode {
        case .default:
            break
        case .zip:
            parts.append(rule.deleteOriginalAfterArchiving ? "zip+delete" : "zip")
        case .cbz:
            parts.append(rule.deleteOriginalAfterArchiving ? "cbz+delete" : "cbz")
        case .none:
            parts.append("no archive")
        }
        return "\(rule.hostSuffix) -> \(parts.joined(separator: ", "))"
    }
}

private struct QueueThumbnailView: View {
    let job: DownloadJob
    let destinationPath: String
    let width: CGFloat
    let height: CGFloat

    @StateObject private var loader = QueueThumbnailLoader()
    @Environment(\.mainUIScale) private var uiScale

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    var body: some View {
        thumbnail
            .frame(width: scaled(width), height: scaled(height))
            .background(Color.primary.opacity(0.035))
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: scaled(5)))
            .task(id: QueueThumbnailProvider.cacheIdentity(for: job, destinationPath: destinationPath)) {
                await loader.load(job: job, destinationPath: destinationPath)
            }
    }

    @ViewBuilder
    private var thumbnail: some View {
        if let image = loader.image {
            fittedThumbnail(Image(nsImage: image))
        } else {
            placeholder
        }
    }

    private func fittedThumbnail(_ image: Image) -> some View {
        GeometryReader { proxy in
            ZStack {
                image
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .scaleEffect(1.14)
                    .blur(radius: scaled(10), opaque: true)
                    .opacity(0.62)

                Color.black.opacity(0.08)

                image
                    .resizable()
                    .scaledToFit()
                    .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
    }

    private var placeholder: some View {
        ZStack {
            Color.primary.opacity(0.035)
            Image(systemName: placeholderIcon)
                .font(.system(size: scaled(20), weight: .regular))
                .foregroundStyle(.tertiary)
        }
    }

    private var placeholderIcon: String {
        let type = job.metadata["type"]?.lowercased() ?? ""
        if type.contains("video") || type.contains("live") {
            return "play.rectangle"
        }
        if type.contains("audio") {
            return "music.note"
        }
        if job.total > 1 {
            return "photo.stack"
        }
        return "photo"
    }
}

private extension TaskTagColor {
    var nativeColor: NSColor {
        let value = rgb
        return NSColor(
            calibratedRed: CGFloat(value.red) / 255,
            green: CGFloat(value.green) / 255,
            blue: CGFloat(value.blue) / 255,
            alpha: 1
        )
    }

    var color: Color {
        Color(nsColor: nativeColor)
    }
}

@MainActor
struct QueueGroupRow: View {
    let group: QueueGroup
    let jobs: [DownloadJob]
    let toggleExpanded: () -> Void
    let rename: () -> Void
    let retryAll: () -> Void
    let togglePin: () -> Void
    let toggleTag: (TaskTagColor) -> Void
    let tagName: (TaskTagColor) -> String
    let openTagSettings: () -> Void
    let removeGroup: () -> Void

    @Environment(\.mainUIScale) private var uiScale

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    var body: some View {
        HStack(spacing: scaled(8)) {
            Button(action: toggleExpanded) {
                Image(systemName: group.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: scaled(12), weight: .semibold))
                    .frame(width: scaled(24), height: scaled(28))
            }
            .buttonStyle(.plain)
            .help(AppLocalization.text(group.isExpanded ? "Collapse Group" : "Expand Group"))
            .accessibilityIdentifier("queue.group.toggle.\(group.id.uuidString)")

            Image(systemName: "folder.fill")
                .font(.system(size: scaled(20), weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: scaled(28))

            VStack(alignment: .leading, spacing: scaled(3)) {
                HStack(spacing: scaled(5)) {
                    if group.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: scaled(10), weight: .semibold))
                            .foregroundStyle(.secondary)
                            .help(AppLocalization.text("Pinned Group"))
                    }
                    ForEach(selectedTagColors) { tag in
                        Circle()
                            .fill(tag.color)
                            .frame(width: scaled(8), height: scaled(8))
                            .help(AppLocalization.format("%@ Tag", tagName(tag)))
                    }
                    Text(group.name)
                        .font(.system(size: scaled(14), weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(groupDetail)
                    .font(.system(size: scaled(11)))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: scaled(8))

            Text(groupProgress)
                .font(.system(size: scaled(12)))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Button(action: showNativeGroupActionMenu) {
                Image(systemName: "ellipsis")
                    .font(.system(size: scaled(17), weight: .semibold))
                    .frame(width: scaled(30), height: scaled(30))
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help(AppLocalization.text("Group Actions"))
            .accessibilityIdentifier("queue.group.menu.\(group.id.uuidString)")
        }
        .padding(.horizontal, scaled(8))
        .padding(.vertical, scaled(6))
        .frame(minHeight: scaled(54))
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: toggleExpanded)
        .overlay {
            QueueNativeContextMenuBridge(
                prepare: {},
                makeMenu: makeNativeGroupActionMenu
            )
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("queue.group.\(group.id.uuidString)")
    }

    private var selectedTagColors: [TaskTagColor] {
        let values = Set(TaskTagColor.normalizedRawValues(group.tags))
        return TaskTagColor.allCases.filter { values.contains($0.rawValue) }
    }

    private func showNativeGroupActionMenu() {
        let menu = makeNativeGroupActionMenu()
        guard let contentView = NSApp.currentEvent?.window?.contentView ?? NSApp.keyWindow?.contentView else {
            return
        }
        let location: NSPoint
        if let event = NSApp.currentEvent, event.window === contentView.window {
            location = contentView.convert(event.locationInWindow, from: nil)
        } else {
            location = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        }
        DispatchQueue.main.async {
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: location.x - 16, y: location.y - 8),
                in: contentView
            )
        }
    }

    private func makeNativeGroupActionMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        addNativeAction(to: menu, title: "Rename...", systemImage: "pencil", action: rename)
        menu.addItem(.separator())
        addNativeAction(
            to: menu,
            title: "Restart All Tasks in Group (S)",
            systemImage: "arrow.clockwise",
            enabled: !jobs.isEmpty,
            action: retryAll
        )
        menu.addItem(.separator())
        addNativeAction(
            to: menu,
            title: group.isPinned ? "Unpin" : "Pin",
            systemImage: group.isPinned ? "pin.slash" : "pin",
            action: togglePin
        )
        menu.addItem(.separator())
        addNativeTagToolbar(to: menu)
        menu.addItem(.separator())
        addNativeAction(to: menu, title: "Remove from List (R)", systemImage: "xmark", action: removeGroup)
        return menu
    }

    private func addNativeTagToolbar(to menu: NSMenu) {
        let selected = Set(selectedTagColors)
        var actions = TaskTagColor.allCases.map { tag in
            let name = tagName(tag)
            let title = selected.contains(tag)
                ? AppLocalization.format("Remove %@ Tag", name)
                : AppLocalization.format("%@ Tag", name)
            return QueueMenuToolbarAction(
                title: title,
                systemImage: selected.contains(tag) ? "circle.inset.filled" : "circle",
                tintColor: tag.nativeColor
            ) {
                toggleTag(tag)
            }
        }
        actions.append(QueueMenuToolbarAction(
            title: "Tag Settings...",
            systemImage: "gearshape.fill",
            handler: openTagSettings
        ))
        let item = NSMenuItem()
        item.view = QueueMenuToolbarView(actions: actions, width: 270)
        menu.addItem(item)
    }

    private func addNativeAction(
        to menu: NSMenu,
        title: String,
        systemImage: String,
        enabled: Bool = true,
        action: @escaping () -> Void
    ) {
        menu.addItem(QueueActionMenuItem(
            title: title,
            systemImage: systemImage,
            enabled: enabled,
            handler: action
        ))
    }

    private var groupDetail: String {
        let comment = group.comment.trimmed
        if !comment.isEmpty {
            return comment
        }
        if jobs.isEmpty {
            return AppLocalization.text("Empty Group")
        }
        return AppLocalization.format("%@ tasks", String(jobs.count))
    }

    private var groupProgress: String {
        guard !jobs.isEmpty else { return "0" }
        let finished = jobs.filter { $0.status == .finished }.count
        return "\(finished) / \(jobs.count)"
    }
}

@MainActor
private final class JobRowHoverState: ObservableObject {
    @Published private(set) var isHovering = false
    @Published private(set) var isDragging = false

    func setHovering(_ value: Bool) {
        guard isHovering != value else { return }
        isHovering = value
    }

    func setDragging(_ value: Bool) {
        guard isDragging != value else { return }
        isDragging = value
    }
}

struct JobRow: View {
    let job: DownloadJob
    let isSelected: Bool
    let queueIsPaused: Bool
    let showsDownloadDate: Bool
    let statusColorPalette: JobStatusColorPalette
    let groupOptions: [QueueGroup]
    let currentGroupID: UUID?
    let destinationPath: String
    let viewMode: QueueViewMode
    let showsThumbnail: Bool
    let thumbnailScale: QueueThumbnailScale
    let hideArchiveIndicatorWhenFileMissing: Bool
    let reveal: () -> Void
    let openFirstOutput: () -> Void
    let openArchive: () -> Void
    let openFirstSelectedOutputs: () -> Void
    let viewOutputInBrowser: () -> Void
    let previewOutput: () -> Void
    let createPDF: () -> Void
    let retry: () -> Void
    let directDownload: () -> Void
    let stopLiveRecording: () -> Void
    let pauseAria2: () -> Void
    let resumeAria2: () -> Void
    let applyAria2Limits: () -> Void
    let applyAria2Files: () -> Void
    let applyAria2Seeding: () -> Void
    let previewAria2Files: () -> Void
    let refreshAria2Peers: () -> Void
    let markFinished: () -> Void
    let moveUp: () -> Void
    let moveDown: () -> Void
    let moveOutput: () -> Void
    let deleteJobAndOutput: () -> Void
    let deleteOutput: () -> Void
    let remove: () -> Void
    let copySource: () -> Void
    let copyArtist: () -> Void
    let openSource: () -> Void
    let openAccessHelp: () -> Void
    let info: () -> Void
    let selectForContextMenu: () -> Void
    let edit: () -> Void
    let pages: () -> Void
    let comment: () -> Void
    let togglePin: () -> Void
    let toggleLock: () -> Void
    let pinActionWillPin: () -> Bool
    let lockActionWillLock: () -> Bool
    let canToggleSelectedPins: () -> Bool
    let retryIncomplete: () -> Void
    let clearCompleted: () -> Void
    let isTagChecked: (TaskTagColor) -> Bool
    let toggleTag: (TaskTagColor) -> Void
    let tagName: (TaskTagColor) -> String
    let openTagSettings: () -> Void
    let convertImages: () -> Void
    let moveToGroup: (UUID?) -> Void
    let moveToNewGroup: () -> Void
    let beginReorder: () -> NSPasteboardItem
    let endReorder: () -> Void
    let canBeginReorder: () -> Bool
    let canMoveToGroup: () -> Bool
    let canMoveUp: () -> Bool
    let canMoveDown: () -> Bool
    let canPauseAria2: () -> Bool
    let canResumeAria2: () -> Bool
    let canApplyAria2Limits: () -> Bool
    let canApplyAria2Files: () -> Bool
    let canApplyAria2Seeding: () -> Bool
    let canPreviewAria2Files: () -> Bool
    let canRefreshAria2Peers: () -> Bool
    let canMarkFinished: () -> Bool
    let canOpenPageSelector: () -> Bool
    let canDeleteOutput: () -> Bool
    let canOpenFirstOutput: () -> Bool
    let canOpenFirstSelectedOutputs: () -> Bool
    let canViewOutputInBrowser: () -> Bool
    let canPreviewOutput: () -> Bool
    let canCreatePDF: () -> Bool
    let canDirectDownload: () -> Bool
    let canStopLiveRecording: () -> Bool
    let canMoveOutput: () -> Bool
    let canConvertImages: () -> Bool
    let canCopyArtist: () -> Bool
    let canRetryIncomplete: () -> Bool
    let canClearCompleted: () -> Bool
    let canRevealSelectedOutputs: () -> Bool
    let canDeleteSelectedJobsAndOutput: () -> Bool
    let canRemoveSelectedJobs: () -> Bool
    let canRetrySelectedJobs: () -> Bool

    @StateObject private var hoverState = JobRowHoverState()
    @Environment(\.mainUIScale) private var uiScale

    private func scaled(_ value: CGFloat) -> CGFloat {
        value * uiScale
    }

    var body: some View {
        Group {
            if viewMode == .icon {
                iconContent
            } else {
                listContent
            }
        }
        .contentShape(Rectangle())
        .overlay {
            QueueNativeContextMenuBridge(
                prepare: selectForContextMenu,
                makeMenu: makeNativeJobActionMenu
            )
        }
        .overlay(alignment: .topTrailing) {
            if viewMode == .list {
                hoverActionBar
                    .padding(.top, scaled(9))
                    .padding(.trailing, scaled(9))
                    .opacity(showsHoverActionBar ? 1 : 0)
                    .allowsHitTesting(showsHoverActionBar)
                    .accessibilityHidden(!showsHoverActionBar)
                    .animation(nil, value: showsHoverActionBar)
            }
        }
        .onHover { hovering in
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hoverState.setHovering(hovering)
            }
        }
    }

    private var thumbnailFactor: CGFloat {
        CGFloat(thumbnailScale.factor)
    }

    private var thumbnailWidth: CGFloat {
        88 * thumbnailFactor
    }

    private var thumbnailHeight: CGFloat {
        62 * thumbnailFactor
    }

    private var iconCellWidth: CGFloat {
        88 * thumbnailFactor
    }

    private var iconCellHeight: CGFloat {
        90 * thumbnailFactor
    }

    private var listContent: some View {
        HStack(spacing: scaled(8)) {
            if showsThumbnail {
                thumbnailButton(width: thumbnailWidth, height: thumbnailHeight)
            }

            VStack(alignment: .leading, spacing: scaled(5)) {
                HStack(spacing: scaled(6)) {
                    ForEach(selectedTagColors) { tag in
                        Circle()
                            .fill(tag.color)
                            .frame(width: scaled(8), height: scaled(8))
                            .help(AppLocalization.format("%@ Tag", tagName(tag)))
                    }
                    if job.isPinned {
                        Image(systemName: "pin.fill")
                            .font(.system(size: scaled(10)))
                            .foregroundStyle(.secondary)
                            .help(AppLocalization.text("Pinned job"))
                    }
                    if job.isLocked {
                        Image(systemName: "lock.fill")
                            .font(.system(size: scaled(10)))
                            .foregroundStyle(.secondary)
                            .help(AppLocalization.text("Locked job"))
                    }
                    Text(job.title)
                        .font(.system(size: scaled(14), weight: .medium))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .accessibilityIdentifier("queue.title.\(job.id.uuidString)")

                    Spacer(minLength: scaled(4))
                }
                .padding(.trailing, scaled(listTitleToolbarReservation))

                if job.status == .resolving || job.status == .downloading {
                    CompactLinearProgress(value: job.progress, color: isSelected ? .white : .accentColor)
                }

                HStack(spacing: scaled(5)) {
                    siteBadge

                    if let archiveArtifact {
                        archiveBadge(archiveArtifact)
                    } else if pageCount != nil {
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: scaled(11), weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: scaled(23), height: scaled(23))
                            .background(
                                RoundedRectangle(cornerRadius: scaled(4))
                                    .fill(Color.secondary.opacity(0.75))
                            )
                            .help("Image collection")
                    }

                    if job.status == .resolving || job.status == .downloading || job.status == .failed || job.status == .cancelled {
                        statusIcon
                            .frame(width: scaled(22), height: scaled(22))
                            .help(statusHelpText)
                            .accessibilityIdentifier("queue.status-indicator.\(job.id.uuidString)")
                    }

                    if let displayReaction {
                        displayReactionIcon(displayReaction)
                    }

                    if let accessReaction {
                        accessReactionButton(accessReaction)
                    }

                    Spacer()

                    HStack(spacing: scaled(10)) {
                        if let pageCount {
                            Label("\(pageCount)p", systemImage: "photo.on.rectangle")
                                .help("Pages")
                        }

                        if let duration = JobDisplayMetadata.durationText(for: job) {
                            Label(duration, systemImage: "clock")
                                .help("Duration")
                        }

                        if let size = JobDisplayMetadata.byteCountText(for: job) {
                            Label(size, systemImage: "externaldrive")
                                .help("Known final size")
                        }

                        if let secondaryStatusText,
                           job.status == .resolving || job.status == .downloading || job.status == .failed || job.status == .cancelled {
                            Text(secondaryStatusText)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                }
                .font(.system(size: scaled(12)))
                .foregroundStyle(.secondary)
            }

        }
        .padding(.horizontal, scaled(8))
        .padding(.vertical, scaled(6))
        .padding(.leading, groupName == nil ? 0 : scaled(18))
        .frame(minHeight: scaled(max(62, thumbnailHeight + 12)))
        .overlay(alignment: .leading) {
            if groupName != nil {
                Rectangle()
                    .fill(Color.secondary.opacity(0.24))
                    .frame(width: scaled(2))
                    .padding(.leading, scaled(8))
                    .padding(.vertical, scaled(8))
            }
        }
    }

    private var iconContent: some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                if showsThumbnail {
                    thumbnailButton(width: thumbnailWidth, height: thumbnailHeight)
                }

                Text(job.title)
                    .font(.system(size: scaled(11), weight: .semibold))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(showsThumbnail ? 2 : nil)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                    .padding(.horizontal, scaled(3))
                    .padding(.vertical, scaled(2))
                    .accessibilityIdentifier("queue.title.\(job.id.uuidString)")
            }
            .frame(width: scaled(iconCellWidth), height: scaled(iconCellHeight), alignment: .top)

            if showsThumbnail {
                HStack(spacing: scaled(3)) {
                    siteBadge
                        .scaleEffect(min(1, thumbnailFactor), anchor: .topLeading)
                        .opacity(hoverState.isHovering ? 1 : 0)
                        .allowsHitTesting(hoverState.isHovering)
                    if let archiveArtifact {
                        archiveBadge(archiveArtifact)
                    }

                    if job.status == .downloading {
                        downloadActivityIcon
                        .frame(width: scaled(20), height: scaled(20))
                        .help(AppLocalization.statusText(job.message))
                        .accessibilityIdentifier("queue.status-indicator.\(job.id.uuidString)")
                    } else if job.status == .failed || job.status == .cancelled {
                        statusIcon
                            .frame(width: scaled(20), height: scaled(20))
                            .help(statusHelpText)
                            .accessibilityIdentifier("queue.status-indicator.\(job.id.uuidString)")
                    }

                    Spacer(minLength: 0)

                    if let displayReaction {
                        displayReactionIcon(displayReaction)
                    }

                    if let accessReaction {
                        accessReactionButton(accessReaction)
                    }

                    if let pageCount {
                        Text("\(pageCount)p")
                            .font(.system(size: scaled(9), weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, scaled(4))
                            .padding(.vertical, scaled(2))
                            .background(Color.black.opacity(0.58))
                            .clipShape(RoundedRectangle(cornerRadius: scaled(3)))
                    }
                }
                .frame(width: scaled(iconCellWidth - 6))
                .padding(scaled(3))
            } else {
                HStack(spacing: scaled(3)) {
                    siteBadge
                        .opacity(hoverState.isHovering ? 1 : 0)
                        .allowsHitTesting(hoverState.isHovering)
                    if let archiveArtifact {
                        archiveBadge(archiveArtifact)
                    }

                    if job.status == .downloading {
                        downloadActivityIcon
                        .frame(width: scaled(20), height: scaled(20))
                        .help(AppLocalization.statusText(job.message))
                        .accessibilityIdentifier("queue.status-indicator.\(job.id.uuidString)")
                    } else if job.status == .failed || job.status == .cancelled {
                        statusIcon
                            .frame(width: scaled(20), height: scaled(20))
                            .help(statusHelpText)
                            .accessibilityIdentifier("queue.status-indicator.\(job.id.uuidString)")
                    }

                    Spacer(minLength: 0)

                    if let displayReaction {
                        displayReactionIcon(displayReaction)
                    }

                    if let accessReaction {
                        accessReactionButton(accessReaction)
                    }
                }
                .frame(width: scaled(iconCellWidth - 8))
                .padding(scaled(4))
            }

            if job.status == .resolving || job.status == .downloading {
                CompactLinearProgress(value: job.progress, color: isSelected ? .white : .accentColor)
                    .padding(.horizontal, scaled(4))
                    .padding(.bottom, scaled(3))
                    .frame(width: scaled(iconCellWidth), height: scaled(iconCellHeight), alignment: .bottom)
            }
        }
        .frame(width: scaled(iconCellWidth), height: scaled(iconCellHeight))
        .background(
            RoundedRectangle(cornerRadius: scaled(5))
                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.035))
        )
        .clipShape(RoundedRectangle(cornerRadius: scaled(5)))
        .overlay(
            RoundedRectangle(cornerRadius: scaled(5))
                .stroke(isSelected ? Color.white.opacity(0.4) : Color.primary.opacity(0.08), lineWidth: scaled(0.5))
        )
    }

    private func thumbnailButton(width: CGFloat, height: CGFloat) -> some View {
        Button {
            guard !job.outputPath.trimmed.isEmpty else { return }
            openFirstOutput()
        } label: {
            QueueThumbnailView(
                job: job,
                destinationPath: destinationPath,
                width: width,
                height: height
            )
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            TapGesture().onEnded {
                if viewMode == .icon {
                    selectForContextMenu()
                }
            }
        )
        .help(job.outputPath.trimmed.isEmpty ? "No downloaded file" : "Open downloaded file")
        .accessibilityLabel("Open downloaded file")
    }

    private var showsHoverActionBar: Bool {
        hoverState.isHovering ||
            hoverState.isDragging ||
            ProcessInfo.processInfo.environment["HITOMI_NATIVE_UI_TEST_SELECTED_HOVER"] == "1"
    }

    private var hoverActionBarWidth: CGFloat {
        viewMode == .icon ? min(206, max(60, iconCellWidth - 4)) : 206
    }

    private var listTitleToolbarReservation: CGFloat {
        hoverActionBarWidth + 14
    }

    private var hoverActionButtonWidth: CGFloat {
        viewMode == .icon ? hoverActionBarWidth / 6 : 32
    }

    private var hoverActionIconSize: CGFloat {
        viewMode == .icon ? min(17, max(9, hoverActionButtonWidth - 4)) : 17
    }

    private var hoverActionBar: some View {
        HStack(spacing: scaled(viewMode == .icon ? 0 : 2)) {
            if canStopLiveRecording() {
                hoverActionButton(
                    title: "Stop Recording",
                    systemImage: "stop.fill",
                    enabled: true,
                    action: stopLiveRecording
                )
            } else {
                hoverActionButton(
                    title: "Preview",
                    systemImage: "eye.fill",
                    enabled: canPreviewOutput(),
                    action: previewOutput
                )
            }
            hoverActionButton(
                title: "Open Output Folder",
                systemImage: "folder.fill",
                enabled: canRevealSelectedOutputs(),
                action: reveal
            )
            hoverActionButton(
                title: "Delete Task and Downloaded Files",
                systemImage: "trash.fill",
                enabled: canDeleteSelectedJobsAndOutput(),
                action: deleteJobAndOutput
            )
            reorderHandle

            hoverActionMenu

            hoverActionButton(
                title: "Remove from List Only",
                systemImage: "xmark",
                enabled: canRemoveSelectedJobs(),
                action: remove
            )
        }
        .padding(.horizontal, scaled(viewMode == .icon ? 0 : 2))
        .frame(width: scaled(hoverActionBarWidth), height: scaled(30))
        .clipped()
        .accessibilityElement(children: .contain)
        .transaction { transaction in
            transaction.animation = nil
            transaction.disablesAnimations = true
        }
    }

    private func hoverActionButton(
        title: String,
        systemImage: String,
        enabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            hoverActionIcon(systemImage: systemImage)
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(AppLocalization.text(title))
        .accessibilityLabel(AppLocalization.text(title))
    }

    private func hoverActionIcon(systemImage: String) -> some View {
        Image(systemName: systemImage)
            .symbolRenderingMode(.monochrome)
            .font(.system(size: scaled(hoverActionIconSize), weight: .semibold))
            .foregroundStyle(isSelected ? Color.white.opacity(0.9) : Color(nsColor: .secondaryLabelColor))
            .frame(width: scaled(hoverActionButtonWidth), height: scaled(30))
            .contentShape(Rectangle())
    }

    private var hoverActionMenu: some View {
        Button(action: showNativeJobActionMenu) {
            hoverActionIcon(systemImage: "ellipsis")
        }
        .buttonStyle(.plain)
        .frame(width: scaled(hoverActionButtonWidth), height: scaled(30))
        .contentShape(Rectangle())
        .help(AppLocalization.text("More"))
        .accessibilityLabel(AppLocalization.text("More"))
    }

    private func showNativeJobActionMenu() {
        let menu = makeNativeJobActionMenu()
        guard let contentView = NSApp.currentEvent?.window?.contentView ?? NSApp.keyWindow?.contentView else {
            return
        }
        let location: NSPoint
        if let event = NSApp.currentEvent, event.window === contentView.window {
            location = contentView.convert(event.locationInWindow, from: nil)
        } else {
            location = NSPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
        }
        DispatchQueue.main.async {
            queueDragTrace("detail menu open items=\(menu.items.count)")
            menu.popUp(
                positioning: nil,
                at: NSPoint(x: location.x - 16, y: location.y - 8),
                in: contentView
            )
            queueDragTrace("detail menu closed")
        }
    }

    private func makeNativeJobActionMenu() -> NSMenu {
        let menu = nativeMenu()
        addNativeActionToolbar(to: menu)
        menu.addItem(.separator())

        if canStopLiveRecording() {
            addNativeAction(
                to: menu,
                title: "Stop Recording",
                systemImage: "stop.circle.fill",
                action: stopLiveRecording
            )
            menu.addItem(.separator())
        }

        if canDirectDownload() {
            addNativeAction(
                to: menu,
                title: "Direct Download",
                systemImage: "arrow.down.circle",
                action: directDownload
            )
            menu.addItem(.separator())
        }

        addNativeAction(
            to: menu,
            title: "Open First File (O)",
            systemImage: "doc.viewfinder",
            enabled: canOpenFirstSelectedOutputs(),
            keyEquivalent: "\r",
            action: openFirstSelectedOutputs
        )

        addNativeAction(
            to: menu,
            title: "Preview (P)",
            systemImage: "eye",
            enabled: canPreviewOutput(),
            keyEquivalent: "v",
            action: previewOutput
        )
        addNativeAction(
            to: menu,
            title: "View in Browser (B)",
            systemImage: "safari",
            enabled: canViewOutputInBrowser(),
            keyEquivalent: "\r",
            modifierMask: .shift,
            action: viewOutputInBrowser
        )
        menu.addItem(.separator())

        addNativeAction(
            to: menu,
            title: "Copy Link Address (C)",
            systemImage: "doc.on.doc",
            keyEquivalent: "c",
            modifierMask: .command,
            action: copySource
        )
        addNativeAction(to: menu, title: "Copy Artist Name (A)", systemImage: "person.text.rectangle", enabled: canCopyArtist(), action: copyArtist)
        menu.addItem(.separator())

        addNativeAction(to: menu, title: "Restart (S)", systemImage: "arrow.clockwise", enabled: canRetrySelectedJobs(), action: retry)
        addNativeAction(
            to: menu,
            title: "Restart All Incomplete Tasks",
            systemImage: "arrow.triangle.2.circlepath",
            enabled: canRetryIncomplete(),
            action: retryIncomplete
        )
        addNativeAction(
            to: menu,
            title: "Remove All Completed Tasks",
            systemImage: "xmark.circle",
            enabled: canClearCompleted(),
            action: clearCompleted
        )
        addNativeAction(to: menu, title: "Mark as Completed (D)", systemImage: "checkmark", enabled: canMarkFinished(), action: markFinished)
        menu.addItem(.separator())

        addNativeAction(
            to: menu,
            title: lockActionWillLock() ? "Lock (L)" : "Unlock (L)",
            systemImage: lockActionWillLock() ? "lock" : "lock.open",
            keyEquivalent: "q",
            modifierMask: .control,
            action: toggleLock
        )
        addNativeAction(
            to: menu,
            title: pinActionWillPin() ? "Pin" : "Unpin",
            systemImage: pinActionWillPin() ? "pin" : "pin.slash",
            enabled: canToggleSelectedPins(),
            keyEquivalent: "p",
            modifierMask: .control,
            action: togglePin
        )
        menu.addItem(.separator())
        addNativeTagToolbar(to: menu)
        menu.addItem(.separator())

        addNativeAction(
            to: menu,
            title: "Edit Task...",
            systemImage: "pencil",
            enabled: canEdit,
            keyEquivalent: String(UnicodeScalar(0xF705)!),
            action: edit
        )
        addNativeAction(
            to: menu,
            title: "Edit Comment...",
            systemImage: job.comment.trimmed.isEmpty ? "text.bubble" : "text.bubble.fill",
            keyEquivalent: "c",
            action: comment
        )
        addNativeAction(to: menu, title: "Move Folder...", systemImage: "folder.badge.plus", enabled: canMoveOutput(), action: moveOutput)
        addNativeAction(
            to: menu,
            title: "Convert Image Format...",
            systemImage: "photo.badge.arrow.down",
            enabled: canConvertImages(),
            action: convertImages
        )

        let groupMenu = nativeMenu(title: "Move to Group")
        addNativeAction(to: groupMenu, title: "New Group...", systemImage: "folder.badge.plus", action: moveToNewGroup)
        if !groupOptions.isEmpty {
            groupMenu.addItem(.separator())
            for group in groupOptions {
                addNativeAction(
                    to: groupMenu,
                    title: group.name,
                    systemImage: currentGroupID == group.id ? "checkmark" : "folder"
                ) {
                    moveToGroup(group.id)
                }
            }
        }
        groupMenu.addItem(.separator())
        addNativeAction(
            to: groupMenu,
            title: "No Group",
            systemImage: currentGroupID == nil ? "checkmark" : "folder.badge.minus"
        ) {
            moveToGroup(nil)
        }
        addNativeSubmenu(
            to: menu,
            title: "Move to Group",
            systemImage: "folder",
            submenu: groupMenu,
            enabled: canMoveToGroup()
        )
        addNativeAction(
            to: menu,
            title: "Task Information... (I)",
            systemImage: "info.circle",
            keyEquivalent: "a",
            action: info
        )

        if hasAria2ContextActions {
            menu.addItem(.separator())
            let ariaMenu = nativeMenu(title: "aria2 Actions")
            addNativeAction(to: ariaMenu, title: "Pause aria2c", systemImage: "pause.circle", enabled: canPauseAria2(), action: pauseAria2)
            addNativeAction(to: ariaMenu, title: "Resume aria2c", systemImage: "play.circle", enabled: canResumeAria2(), action: resumeAria2)
            addNativeAction(to: ariaMenu, title: "Apply aria2 Limits", systemImage: "speedometer", enabled: canApplyAria2Limits(), action: applyAria2Limits)
            addNativeAction(to: ariaMenu, title: "Apply aria2 Files", systemImage: "list.bullet.rectangle", enabled: canApplyAria2Files(), action: applyAria2Files)
            addNativeAction(to: ariaMenu, title: "Apply aria2 Seeding", systemImage: "leaf", enabled: canApplyAria2Seeding(), action: applyAria2Seeding)
            addNativeAction(to: ariaMenu, title: "List aria2 Files", systemImage: "list.bullet.rectangle.portrait", enabled: canPreviewAria2Files(), action: previewAria2Files)
            addNativeAction(to: ariaMenu, title: "Show aria2 Peers", systemImage: "person.2", enabled: canRefreshAria2Peers(), action: refreshAria2Peers)
            addNativeSubmenu(to: menu, title: "aria2 Actions", systemImage: "bolt.horizontal", submenu: ariaMenu)
        }
        return menu
    }

    private func addNativeActionToolbar(to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = QueueMenuToolbarView(actions: [
            QueueMenuToolbarAction(
                title: canStopLiveRecording() ? "Stop Recording" : "Preview",
                systemImage: canStopLiveRecording() ? "stop.fill" : "eye.fill",
                isEnabled: canStopLiveRecording() || canPreviewOutput(),
                handler: canStopLiveRecording() ? stopLiveRecording : previewOutput
            ),
            QueueMenuToolbarAction(
                title: "Open Output Folder",
                systemImage: "folder.fill",
                isEnabled: canRevealSelectedOutputs(),
                handler: reveal
            ),
            QueueMenuToolbarAction(
                title: "Delete Task and Downloaded Files",
                systemImage: "trash.fill",
                isEnabled: canDeleteSelectedJobsAndOutput(),
                handler: deleteJobAndOutput
            ),
            QueueMenuToolbarAction(
                title: "Remove from List Only",
                systemImage: "xmark",
                isEnabled: canRemoveSelectedJobs(),
                handler: remove
            )
        ])
        menu.addItem(item)
    }

    private func addNativeTagToolbar(to menu: NSMenu) {
        var actions = TaskTagColor.allCases.map { tag in
            let checked = isTagChecked(tag)
            let name = tagName(tag)
            let title = checked
                ? AppLocalization.format("Remove %@ Tag", name)
                : AppLocalization.format("%@ Tag", name)
            return QueueMenuToolbarAction(
                title: title,
                systemImage: checked ? "circle.inset.filled" : "circle",
                tintColor: tag.nativeColor
            ) {
                toggleTag(tag)
            }
        }
        actions.append(QueueMenuToolbarAction(
            title: "Tag Settings...",
            systemImage: "gearshape.fill",
            handler: openTagSettings
        ))

        let item = NSMenuItem()
        item.view = QueueMenuToolbarView(actions: actions)
        menu.addItem(item)
    }

    private var hasAria2ContextActions: Bool {
        canPauseAria2() || canResumeAria2() || canApplyAria2Limits() ||
            canApplyAria2Files() || canApplyAria2Seeding() ||
            canPreviewAria2Files() || canRefreshAria2Peers()
    }

    private func nativeMenu(title: String = "") -> NSMenu {
        let menu = NSMenu(title: AppLocalization.text(title))
        menu.autoenablesItems = false
        return menu
    }

    private func addNativeAction(
        to menu: NSMenu,
        title: String,
        systemImage: String,
        enabled: Bool = true,
        keyEquivalent: String = "",
        modifierMask: NSEvent.ModifierFlags = [],
        action: @escaping () -> Void
    ) {
        menu.addItem(QueueActionMenuItem(
            title: title,
            systemImage: systemImage,
            enabled: enabled,
            keyEquivalent: keyEquivalent,
            modifierMask: modifierMask,
            handler: action
        ))
    }

    private func addNativeSubmenu(
        to menu: NSMenu,
        title: String,
        systemImage: String,
        submenu: NSMenu,
        enabled: Bool = true
    ) {
        let localizedTitle = AppLocalization.text(title)
        let item = NSMenuItem(title: localizedTitle, action: nil, keyEquivalent: "")
        item.image = NSImage(
            systemSymbolName: systemImage,
            accessibilityDescription: localizedTitle
        )?.withSymbolConfiguration(.init(pointSize: 13, weight: .regular))
        item.image?.isTemplate = true
        item.isEnabled = enabled
        item.submenu = submenu
        menu.addItem(item)
    }

    @ViewBuilder
    private var reorderHandle: some View {
        if canBeginReorder() {
            ZStack {
                hoverActionIcon(systemImage: "equal")
                QueueReorderDragSource(
                    isEnabled: true,
                    begin: {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            hoverState.setDragging(true)
                        }
                        return beginReorder()
                    },
                    end: {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            hoverState.setDragging(false)
                        }
                        endReorder()
                    }
                )
                .frame(width: scaled(32), height: scaled(30))
            }
            .frame(width: scaled(32), height: scaled(30))
            .help(AppLocalization.text("Reorder"))
            .accessibilityLabel(AppLocalization.text("Reorder"))
            .accessibilityAddTraits(.isButton)
        } else {
            hoverActionIcon(systemImage: "equal")
                .opacity(0.35)
                .help(AppLocalization.text("Reordering is available in manual sort"))
                .accessibilityLabel(AppLocalization.text("Reordering unavailable"))
        }
    }

    @ViewBuilder
    private var jobActionMenu: some View {
        Button {
                previewOutput()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .disabled(!canPreviewOutput())

            Button {
                viewOutputInBrowser()
            } label: {
                Label("View in Browser", systemImage: "safari")
            }
            .disabled(!canViewOutputInBrowser())

            Button {
                reveal()
            } label: {
                Label("Open Output Folder", systemImage: "folder")
            }
            .disabled(!canRevealSelectedOutputs())

            Button(role: .destructive) {
                deleteOutput()
            } label: {
                Label("Move Output to Trash", systemImage: "trash")
            }
            .disabled(!canDeleteOutput())

            Button(role: .destructive) {
                remove()
            } label: {
                Label("Remove Task", systemImage: "xmark")
            }
            .disabled(!canRemoveSelectedJobs())

            Divider()

            Button {
                copySource()
            } label: {
                Label("Copy Link Address", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)

            Button {
                copyArtist()
            } label: {
                Label("Copy Artist Name", systemImage: "person.text.rectangle")
            }
            .disabled(!canCopyArtist())

            Divider()

            Button {
                retry()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .disabled(!canRetrySelectedJobs())

            Button {
                retryIncomplete()
            } label: {
                Label("Restart All Incomplete Tasks", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!canRetryIncomplete())

            Button(role: .destructive) {
                clearCompleted()
            } label: {
                Label("Remove All Completed Tasks", systemImage: "xmark.circle")
            }
            .disabled(!canClearCompleted())

            Button {
                markFinished()
            } label: {
                Label("Mark as Completed", systemImage: "checkmark")
            }
            .disabled(!canMarkFinished())

            Divider()

            Button {
                toggleLock()
            } label: {
                Label(
                    lockActionWillLock() ? "Lock" : "Unlock",
                    systemImage: lockActionWillLock() ? "lock" : "lock.open"
                )
            }

            Button {
                togglePin()
            } label: {
                Label(
                    pinActionWillPin() ? "Pin" : "Unpin",
                    systemImage: pinActionWillPin() ? "pin" : "pin.slash"
                )
            }
            .disabled(!canToggleSelectedPins())

            Menu {
                ForEach(TaskTagColor.allCases) { tag in
                    Button {
                        toggleTag(tag)
                    } label: {
                        Label(
                            tagName(tag),
                            systemImage: isTagChecked(tag) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
                Divider()
                Button {
                    openTagSettings()
                } label: {
                    Label("Tag Settings...", systemImage: "gearshape")
                }
            } label: {
                Label("Tag", systemImage: "tag")
            }

            Divider()

            Button {
                edit()
            } label: {
                Label("Edit Task...", systemImage: "pencil")
            }
            .disabled(!canEdit)

            Button {
                comment()
            } label: {
                Label("Edit Comment...", systemImage: job.comment.trimmed.isEmpty ? "text.bubble" : "text.bubble.fill")
            }

            Button {
                moveOutput()
            } label: {
                Label("Move Folder...", systemImage: "folder.badge.plus")
            }
            .disabled(!canMoveOutput())

            Button {
                convertImages()
            } label: {
                Label("Convert Image Format...", systemImage: "photo.badge.arrow.down")
            }
            .disabled(!canConvertImages())

            Menu {
                Button {
                    moveToNewGroup()
                } label: {
                    Label("New Group...", systemImage: "folder.badge.plus")
                }
                if !groupOptions.isEmpty {
                    Divider()
                    ForEach(groupOptions) { group in
                        Button {
                            moveToGroup(group.id)
                        } label: {
                            Label(group.name, systemImage: currentGroupID == group.id ? "checkmark" : "folder")
                        }
                    }
                }
                Divider()
                Button {
                    moveToGroup(nil)
                } label: {
                    Label("No Group", systemImage: currentGroupID == nil ? "checkmark" : "folder.badge.minus")
                }
            } label: {
                Label("Move to Group", systemImage: "folder")
            }
            .disabled(!canMoveToGroup())

            Button {
                info()
            } label: {
                Label("Task Information...", systemImage: "info.circle")
            }

            Divider()

            Menu {
                Button {
                    pages()
                } label: {
                    Label("Pages...", systemImage: "checklist")
                }
                .disabled(!canOpenPageSelector())

                Button {
                    openFirstSelectedOutputs()
                } label: {
                    Label("Open First Output File", systemImage: "doc.viewfinder")
                }
                .disabled(!canOpenFirstSelectedOutputs())

                Button {
                    viewOutputInBrowser()
                } label: {
                    Label("View Downloaded Output in Browser", systemImage: "eye")
                }
                .disabled(!canViewOutputInBrowser())

                Button {
                    createPDF()
                } label: {
                    Label("Create PDF from Images", systemImage: "doc.richtext")
                }
                .disabled(!canCreatePDF())

                Divider()

                Button {
                    moveUp()
                } label: {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .disabled(!canMoveUp())

                Button {
                    moveDown()
                } label: {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .disabled(!canMoveDown())

                Divider()

                Button {
                    pauseAria2()
                } label: {
                    Label("Pause aria2c", systemImage: "pause.circle")
                }
                .disabled(!canPauseAria2())

                Button {
                    resumeAria2()
                } label: {
                    Label("Resume aria2c", systemImage: "play.circle")
                }
                .disabled(!canResumeAria2())

                Button {
                    applyAria2Limits()
                } label: {
                    Label("Apply aria2 Limits", systemImage: "speedometer")
                }
                .disabled(!canApplyAria2Limits())

                Button {
                    applyAria2Files()
                } label: {
                    Label("Apply aria2 Files", systemImage: "list.bullet.rectangle")
                }
                .disabled(!canApplyAria2Files())

                Button {
                    applyAria2Seeding()
                } label: {
                    Label("Apply aria2 Seeding", systemImage: "leaf")
                }
                .disabled(!canApplyAria2Seeding())

                Button {
                    previewAria2Files()
                } label: {
                    Label("List aria2 Files", systemImage: "list.bullet.rectangle.portrait")
                }
                .disabled(!canPreviewAria2Files())

                Button {
                    refreshAria2Peers()
                } label: {
                    Label("Show aria2 Peers", systemImage: "person.2")
                }
                .disabled(!canRefreshAria2Peers())
            } label: {
                Label("More Actions", systemImage: "ellipsis.circle")
            }
    }

    private var pageCount: Int? {
        if isVideoSite {
            return nil
        }
        if job.total > 0 {
            return job.total
        }
        for key in ["page_count", "pages", "asset_count", "file_count"] {
            if let raw = job.metadata[key]?.trimmed,
               let value = Int(raw),
               value > 0 {
                return value
            }
        }
        return nil
    }

    private var isVideoSite: Bool {
        let type = job.metadata["type"]?.lowercased() ?? ""
        if type.contains("video") || type.contains("audio") || type.contains("live") {
            return true
        }
        let lower = siteLabel.lowercased()
        return lower.contains("youtube") || lower.contains("bilibili") || lower.contains("twitch") || lower.contains("niconico")
    }

    @ViewBuilder
    private var siteBadge: some View {
        if DownloadManager.browserSourceURL(for: job.source) != nil {
            Button(action: openSource) {
                siteBadgeContent
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Open \(siteLabel) in the default browser\n\(job.source)")
            .accessibilityLabel("Open \(siteLabel) source in the default browser")
            .accessibilityIdentifier("queue.site-indicator.\(job.id.uuidString)")
        } else {
            siteBadgeContent
                .help("\(siteLabel): \(job.source)")
                .accessibilityIdentifier("queue.site-indicator.\(job.id.uuidString)")
        }
    }

    private var archiveArtifact: JobArchiveArtifact? {
        if hideArchiveIndicatorWhenFileMissing {
            return JobArchiveArtifact.existing(for: job)
        }
        return JobArchiveArtifact.recorded(for: job)
    }

    private func archiveBadge(_ artifact: JobArchiveArtifact) -> some View {
        let actionLabel = AppLocalization.format("Open %@ archive", artifact.format.label)
        return Button(action: openArchive) {
            Image(systemName: "archivebox.fill")
                .font(.system(size: scaled(12), weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: scaled(23), height: scaled(23))
                .background(
                    RoundedRectangle(cornerRadius: scaled(4))
                        .fill(
                            isSelected
                                ? Color.white.opacity(0.24)
                                : Color.secondary.opacity(0.75)
                        )
                )
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .help(actionLabel)
        .accessibilityLabel(actionLabel)
        .accessibilityIdentifier("queue.archive-indicator.\(job.id.uuidString)")
    }

    private var siteBadgeContent: some View {
        let resourceKey = SiteFaviconCatalog.resourceKey(source: job.source, metadata: job.metadata)
        return ZStack {
            RoundedRectangle(cornerRadius: scaled(4))
                .fill(siteBadgeColor)

            if let favicon = SiteFaviconCatalog.image(resourceKey: resourceKey) {
                Image(nsImage: favicon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .scaleEffect(SiteFaviconCatalog.displayScale(resourceKey: resourceKey))
            } else {
                Image(systemName: siteBadgeIcon)
                    .font(.system(size: scaled(12), weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: scaled(23), height: scaled(23))
        .clipShape(RoundedRectangle(cornerRadius: scaled(4)))
        .overlay(
            RoundedRectangle(cornerRadius: scaled(4))
                .stroke(Color.secondary.opacity(0.28), lineWidth: max(0.5, scaled(0.5)))
        )
    }

    private var siteBadgeIcon: String {
        let lower = siteLabel.lowercased()
        if lower.contains("youtube") || lower.contains("bilibili") || lower.contains("twitch") || lower.contains("niconico") {
            return "play.fill"
        }
        if lower.contains("instagram") {
            return "camera.fill"
        }
        if lower.contains("twitter") || lower == "x" || lower.contains("facebook") {
            return "person.crop.square.fill"
        }
        if lower == "local" {
            return "folder.fill"
        }
        return siteIcon
    }

    private var siteBadgeColor: Color {
        let lower = siteLabel.lowercased()
        if lower.contains("youtube") { return .red }
        if lower.contains("chzzk") { return .black }
        if lower.contains("bilibili") { return .pink }
        if lower.contains("twitch") { return Color(red: 0.45, green: 0.25, blue: 0.8) }
        if lower.contains("hitomi") { return .black }
        if lower.contains("pixiv") { return Color(red: 0.0, green: 0.58, blue: 0.95) }
        if lower.contains("twitter") || lower == "x" { return Color(red: 0.0, green: 0.68, blue: 0.95) }
        if lower.contains("instagram") { return .pink }
        if lower.contains("facebook") { return Color(red: 0.1, green: 0.38, blue: 0.75) }
        if lower == "local" { return .secondary }
        return .accentColor
    }

    private var siteLabel: String {
        if let site = job.metadata["site"]?.trimmed, !site.isEmpty {
            return site
        }
        guard let url = URL(string: job.source),
              let host = url.host?.lowercased() else {
            return job.source.hasPrefix("/") || job.source.hasPrefix("file:") ? "Local" : "Link"
        }
        let normalized = host
            .replacingOccurrences(of: "^www\\.", with: "", options: .regularExpression)
            .replacingOccurrences(of: "^m\\.", with: "", options: .regularExpression)
        let knownNames: [(String, String)] = [
            ("hitomi", "Hitomi"),
            ("pixiv", "Pixiv"),
            ("twitter", "Twitter"),
            ("x.com", "X"),
            ("youtube", "YouTube"),
            ("youtu.be", "YouTube"),
            ("bilibili", "Bilibili"),
            ("instagram", "Instagram"),
            ("facebook", "Facebook"),
            ("twitch", "Twitch"),
            ("niconico", "Niconico")
        ]
        return knownNames.first(where: { normalized.contains($0.0) })?.1
            ?? normalized.split(separator: ".").first.map(String.init)?.capitalized
            ?? normalized
    }

    private var siteIcon: String {
        let lower = siteLabel.lowercased()
        if lower == "local" { return "folder" }
        if lower.contains("youtube") || lower.contains("bilibili") || lower.contains("twitch") || lower.contains("niconico") {
            return "play.rectangle"
        }
        if lower.contains("hitomi") || lower.contains("pixiv") {
            return "photo.on.rectangle"
        }
        if lower.contains("twitter") || lower == "x" || lower.contains("instagram") || lower.contains("facebook") {
            return "person.crop.square"
        }
        return "link"
    }

    private var secondaryStatusText: String? {
        if queueIsPaused && (job.status == .resolving || job.status == .downloading) {
            return AppLocalization.text("Pause")
        }
        if let partialFailureSummary = job.partialFailureSummary() {
            return partialFailureSummary
        }
        if showsDownloadDate,
           let date = JobDisplayMetadata.downloadDateText(for: job) {
            return date
        }
        if let transferProgress = JobDisplayMetadata.transferProgressText(for: job) {
            return transferProgress
        }
        if job.status == .resolving || job.status == .downloading || job.status == .failed || job.status == .cancelled {
            let message = job.message.trimmed
            return message.isEmpty ? job.status.label : AppLocalization.statusText(message)
        }
        if let eta = JobDisplayMetadata.etaText(for: job) {
            return eta
        }
        return nil
    }

    @ViewBuilder
    private var statusIcon: some View {
        if job.status == .downloading {
            downloadActivityIcon
        } else {
            Image(systemName: iconName)
                .font(.system(size: scaled(11), weight: .semibold))
                .foregroundStyle(isSelected ? Color.white.opacity(0.9) : statusColor)
        }
    }

    @ViewBuilder
    private var downloadActivityIcon: some View {
        if queueIsPaused {
            Image(systemName: "pause.circle.fill")
                .font(.system(size: scaled(12), weight: .semibold))
                .foregroundStyle(isSelected ? Color.white : statusColor)
                .accessibilityLabel(AppLocalization.text("Pause"))
        } else {
            ClockwiseDownloadIndicator(
                color: isSelected ? .white : statusColor,
                size: scaled(12)
            )
        }
    }

    private func accessReactionButton(_ reaction: JobAccessReaction) -> some View {
        Button(action: openAccessHelp) {
            Image(systemName: reaction.systemImage)
                .font(.system(size: scaled(11), weight: .semibold))
                .foregroundStyle(reactionColor(reaction))
                .frame(width: scaled(22), height: scaled(22))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(reaction.helpText)
        .accessibilityLabel(reaction.helpText)
        .accessibilityIdentifier("queue.access-reaction.\(job.id.uuidString)")
    }

    @ViewBuilder
    private func displayReactionIcon(_ reaction: JobDisplayReaction) -> some View {
        if let image = Self.displayReactionImage(reaction) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(width: scaled(22), height: scaled(22))
                .accessibilityLabel(reaction.accessibilityText)
                .accessibilityIdentifier("queue.display-reaction.\(job.id.uuidString)")
        }
    }

    private static func displayReactionImage(_ reaction: JobDisplayReaction) -> NSImage? {
        switch reaction {
        case .disgusting:
            return disgustingReactionImage
        }
    }

    private static let disgustingReactionImage: NSImage? = {
        guard let url = Bundle.main.url(
            forResource: JobDisplayReaction.disgusting.resourceName,
            withExtension: "png",
            subdirectory: "ReactionIcons"
        ) else {
            return nil
        }
        return NSImage(contentsOf: url)
    }()

    private func reactionColor(_ reaction: JobAccessReaction) -> Color {
        switch reaction {
        case .cookies: return .red
        case .login: return .orange
        }
    }

    private var accessReaction: JobAccessReaction? {
        DownloadManager.jobAccessReaction(for: job)
    }

    private var displayReaction: JobDisplayReaction? {
        JobDisplayReaction(metadataValue: job.metadata["reaction"])
    }

    private var iconName: String {
        JobStatusStyle.iconName(for: job)
    }

    private var selectedTagColors: [TaskTagColor] {
        let values = Set(TaskTagColor.normalizedRawValues(job.tags))
        return TaskTagColor.allCases.filter { values.contains($0.rawValue) }
    }

    private var groupName: String? {
        let value = (job.metadata["group"] ?? job.metadata["group_name"] ?? "").trimmed
        return value.isEmpty ? nil : value
    }

    private var canEdit: Bool {
        job.status != .resolving && job.status != .downloading
    }

    private var statusColor: Color {
        JobStatusStyle.color(for: job, palette: statusColorPalette)
    }

    private var statusHelpText: String {
        guard let summary = job.partialFailureSummary() else {
            return AppLocalization.statusText(job.message)
        }
        let message = job.message.trimmed
        return message.isEmpty
            ? summary
            : "\(summary)\n\(AppLocalization.statusText(message))"
    }
}
