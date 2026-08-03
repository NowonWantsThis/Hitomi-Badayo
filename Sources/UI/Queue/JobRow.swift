import AppKit
import Foundation
import SwiftUI

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
    let actions: JobRowActions

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
                prepare: actions.selectForContextMenu,
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
                            .help(AppLocalization.format("%@ Tag", actions.tagName(tag)))
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
            actions.openFirstOutput()
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
                    actions.selectForContextMenu()
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
            if actions.canStopLiveRecording() {
                hoverActionButton(
                    title: "Stop Recording",
                    systemImage: "stop.fill",
                    enabled: true,
                    action: actions.stopLiveRecording
                )
            } else {
                hoverActionButton(
                    title: "Preview",
                    systemImage: "eye.fill",
                    enabled: actions.canPreviewOutput(),
                    action: actions.previewOutput
                )
            }
            hoverActionButton(
                title: "Open Output Folder",
                systemImage: "folder.fill",
                enabled: actions.canRevealSelectedOutputs(),
                action: actions.reveal
            )
            hoverActionButton(
                title: "Delete Task and Downloaded Files",
                systemImage: "trash.fill",
                enabled: actions.canDeleteSelectedJobsAndOutput(),
                action: actions.deleteJobAndOutput
            )
            reorderHandle

            hoverActionMenu

            hoverActionButton(
                title: "Remove from List Only",
                systemImage: "xmark",
                enabled: actions.canRemoveSelectedJobs(),
                action: actions.remove
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

        if actions.canStopLiveRecording() {
            addNativeAction(
                to: menu,
                title: "Stop Recording",
                systemImage: "stop.circle.fill",
                action: actions.stopLiveRecording
            )
            menu.addItem(.separator())
        }

        if actions.canDirectDownload() {
            addNativeAction(
                to: menu,
                title: "Direct Download",
                systemImage: "arrow.down.circle",
                action: actions.directDownload
            )
            menu.addItem(.separator())
        }

        addNativeAction(
            to: menu,
            title: "Open First File (O)",
            systemImage: "doc.viewfinder",
            enabled: actions.canOpenFirstSelectedOutputs(),
            keyEquivalent: "\r",
            action: actions.openFirstSelectedOutputs
        )

        addNativeAction(
            to: menu,
            title: "Preview (P)",
            systemImage: "eye",
            enabled: actions.canPreviewOutput(),
            keyEquivalent: "v",
            action: actions.previewOutput
        )
        addNativeAction(
            to: menu,
            title: "View in Browser (B)",
            systemImage: "safari",
            enabled: actions.canViewOutputInBrowser(),
            keyEquivalent: "\r",
            modifierMask: .shift,
            action: actions.viewOutputInBrowser
        )
        menu.addItem(.separator())

        addNativeAction(
            to: menu,
            title: "Copy Link Address (C)",
            systemImage: "doc.on.doc",
            keyEquivalent: "c",
            modifierMask: .command,
            action: actions.copySource
        )
        addNativeAction(to: menu, title: "Copy Artist Name (A)", systemImage: "person.text.rectangle", enabled: actions.canCopyArtist(), action: actions.copyArtist)
        menu.addItem(.separator())

        addNativeAction(to: menu, title: "Restart (S)", systemImage: "arrow.clockwise", enabled: actions.canRetrySelectedJobs(), action: actions.retry)
        addNativeAction(
            to: menu,
            title: "Restart All Incomplete Tasks",
            systemImage: "arrow.triangle.2.circlepath",
            enabled: actions.canRetryIncomplete(),
            action: actions.retryIncomplete
        )
        addNativeAction(
            to: menu,
            title: "Remove All Completed Tasks",
            systemImage: "xmark.circle",
            enabled: actions.canClearCompleted(),
            action: actions.clearCompleted
        )
        addNativeAction(to: menu, title: "Mark as Completed (D)", systemImage: "checkmark", enabled: actions.canMarkFinished(), action: actions.markFinished)
        menu.addItem(.separator())

        addNativeAction(
            to: menu,
            title: actions.lockActionWillLock() ? "Lock (L)" : "Unlock (L)",
            systemImage: actions.lockActionWillLock() ? "lock" : "lock.open",
            keyEquivalent: "q",
            modifierMask: .control,
            action: actions.toggleLock
        )
        addNativeAction(
            to: menu,
            title: actions.pinActionWillPin() ? "Pin" : "Unpin",
            systemImage: actions.pinActionWillPin() ? "pin" : "pin.slash",
            enabled: actions.canToggleSelectedPins(),
            keyEquivalent: "p",
            modifierMask: .control,
            action: actions.togglePin
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
            action: actions.edit
        )
        addNativeAction(
            to: menu,
            title: "Edit Comment...",
            systemImage: job.comment.trimmed.isEmpty ? "text.bubble" : "text.bubble.fill",
            keyEquivalent: "c",
            action: actions.comment
        )
        addNativeAction(to: menu, title: "Move Folder...", systemImage: "folder.badge.plus", enabled: actions.canMoveOutput(), action: actions.moveOutput)
        addNativeAction(
            to: menu,
            title: "Convert Image Format...",
            systemImage: "photo.badge.arrow.down",
            enabled: actions.canConvertImages(),
            action: actions.convertImages
        )

        let groupMenu = nativeMenu(title: "Move to Group")
        addNativeAction(to: groupMenu, title: "New Group...", systemImage: "folder.badge.plus", action: actions.moveToNewGroup)
        if !groupOptions.isEmpty {
            groupMenu.addItem(.separator())
            for group in groupOptions {
                addNativeAction(
                    to: groupMenu,
                    title: group.name,
                    systemImage: currentGroupID == group.id ? "checkmark" : "folder"
                ) {
                    actions.moveToGroup(group.id)
                }
            }
        }
        groupMenu.addItem(.separator())
        addNativeAction(
            to: groupMenu,
            title: "No Group",
            systemImage: currentGroupID == nil ? "checkmark" : "folder.badge.minus"
        ) {
            actions.moveToGroup(nil)
        }
        addNativeSubmenu(
            to: menu,
            title: "Move to Group",
            systemImage: "folder",
            submenu: groupMenu,
            enabled: actions.canMoveToGroup()
        )
        addNativeAction(
            to: menu,
            title: "Task Information... (I)",
            systemImage: "info.circle",
            keyEquivalent: "a",
            action: actions.info
        )

        if hasAria2ContextActions {
            menu.addItem(.separator())
            let ariaMenu = nativeMenu(title: "aria2 Actions")
            addNativeAction(to: ariaMenu, title: "Pause aria2c", systemImage: "pause.circle", enabled: actions.canPauseAria2(), action: actions.pauseAria2)
            addNativeAction(to: ariaMenu, title: "Resume aria2c", systemImage: "play.circle", enabled: actions.canResumeAria2(), action: actions.resumeAria2)
            addNativeAction(to: ariaMenu, title: "Apply aria2 Limits", systemImage: "speedometer", enabled: actions.canApplyAria2Limits(), action: actions.applyAria2Limits)
            addNativeAction(to: ariaMenu, title: "Apply aria2 Files", systemImage: "list.bullet.rectangle", enabled: actions.canApplyAria2Files(), action: actions.applyAria2Files)
            addNativeAction(to: ariaMenu, title: "Apply aria2 Seeding", systemImage: "leaf", enabled: actions.canApplyAria2Seeding(), action: actions.applyAria2Seeding)
            addNativeAction(to: ariaMenu, title: "List aria2 Files", systemImage: "list.bullet.rectangle.portrait", enabled: actions.canPreviewAria2Files(), action: actions.previewAria2Files)
            addNativeAction(to: ariaMenu, title: "Show aria2 Peers", systemImage: "person.2", enabled: actions.canRefreshAria2Peers(), action: actions.refreshAria2Peers)
            addNativeSubmenu(to: menu, title: "aria2 Actions", systemImage: "bolt.horizontal", submenu: ariaMenu)
        }
        return menu
    }

    private func addNativeActionToolbar(to menu: NSMenu) {
        let item = NSMenuItem()
        item.view = QueueMenuToolbarView(actions: [
            QueueMenuToolbarAction(
                title: actions.canStopLiveRecording() ? "Stop Recording" : "Preview",
                systemImage: actions.canStopLiveRecording() ? "stop.fill" : "eye.fill",
                isEnabled: actions.canStopLiveRecording() || actions.canPreviewOutput(),
                handler: actions.canStopLiveRecording() ? actions.stopLiveRecording : actions.previewOutput
            ),
            QueueMenuToolbarAction(
                title: "Open Output Folder",
                systemImage: "folder.fill",
                isEnabled: actions.canRevealSelectedOutputs(),
                handler: actions.reveal
            ),
            QueueMenuToolbarAction(
                title: "Delete Task and Downloaded Files",
                systemImage: "trash.fill",
                isEnabled: actions.canDeleteSelectedJobsAndOutput(),
                handler: actions.deleteJobAndOutput
            ),
            QueueMenuToolbarAction(
                title: "Remove from List Only",
                systemImage: "xmark",
                isEnabled: actions.canRemoveSelectedJobs(),
                handler: actions.remove
            )
        ])
        menu.addItem(item)
    }

    private func addNativeTagToolbar(to menu: NSMenu) {
        var toolbarActions = TaskTagColor.allCases.map { tag in
            let checked = actions.isTagChecked(tag)
            let name = actions.tagName(tag)
            let title = checked
                ? AppLocalization.format("Remove %@ Tag", name)
                : AppLocalization.format("%@ Tag", name)
            return QueueMenuToolbarAction(
                title: title,
                systemImage: checked ? "circle.inset.filled" : "circle",
                tintColor: tag.nativeColor
            ) {
                actions.toggleTag(tag)
            }
        }
        toolbarActions.append(QueueMenuToolbarAction(
            title: "Tag Settings...",
            systemImage: "gearshape.fill",
            handler: actions.openTagSettings
        ))

        let item = NSMenuItem()
        item.view = QueueMenuToolbarView(actions: toolbarActions)
        menu.addItem(item)
    }

    private var hasAria2ContextActions: Bool {
        actions.canPauseAria2() || actions.canResumeAria2() || actions.canApplyAria2Limits() ||
            actions.canApplyAria2Files() || actions.canApplyAria2Seeding() ||
            actions.canPreviewAria2Files() || actions.canRefreshAria2Peers()
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
        if actions.canBeginReorder() {
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
                        return actions.beginReorder()
                    },
                    end: {
                        var transaction = Transaction(animation: nil)
                        transaction.disablesAnimations = true
                        withTransaction(transaction) {
                            hoverState.setDragging(false)
                        }
                        actions.endReorder()
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
                actions.previewOutput()
            } label: {
                Label("Preview", systemImage: "eye")
            }
            .disabled(!actions.canPreviewOutput())

            Button {
                actions.viewOutputInBrowser()
            } label: {
                Label("View in Browser", systemImage: "safari")
            }
            .disabled(!actions.canViewOutputInBrowser())

            Button {
                actions.reveal()
            } label: {
                Label("Open Output Folder", systemImage: "folder")
            }
            .disabled(!actions.canRevealSelectedOutputs())

            Button(role: .destructive) {
                actions.deleteOutput()
            } label: {
                Label("Move Output to Trash", systemImage: "trash")
            }
            .disabled(!actions.canDeleteOutput())

            Button(role: .destructive) {
                actions.remove()
            } label: {
                Label("Remove Task", systemImage: "xmark")
            }
            .disabled(!actions.canRemoveSelectedJobs())

            Divider()

            Button {
                actions.copySource()
            } label: {
                Label("Copy Link Address", systemImage: "doc.on.doc")
            }
            .keyboardShortcut("c", modifiers: .command)

            Button {
                actions.copyArtist()
            } label: {
                Label("Copy Artist Name", systemImage: "person.text.rectangle")
            }
            .disabled(!actions.canCopyArtist())

            Divider()

            Button {
                actions.retry()
            } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .disabled(!actions.canRetrySelectedJobs())

            Button {
                actions.retryIncomplete()
            } label: {
                Label("Restart All Incomplete Tasks", systemImage: "arrow.triangle.2.circlepath")
            }
            .disabled(!actions.canRetryIncomplete())

            Button(role: .destructive) {
                actions.clearCompleted()
            } label: {
                Label("Remove All Completed Tasks", systemImage: "xmark.circle")
            }
            .disabled(!actions.canClearCompleted())

            Button {
                actions.markFinished()
            } label: {
                Label("Mark as Completed", systemImage: "checkmark")
            }
            .disabled(!actions.canMarkFinished())

            Divider()

            Button {
                actions.toggleLock()
            } label: {
                Label(
                    actions.lockActionWillLock() ? "Lock" : "Unlock",
                    systemImage: actions.lockActionWillLock() ? "lock" : "lock.open"
                )
            }

            Button {
                actions.togglePin()
            } label: {
                Label(
                    actions.pinActionWillPin() ? "Pin" : "Unpin",
                    systemImage: actions.pinActionWillPin() ? "pin" : "pin.slash"
                )
            }
            .disabled(!actions.canToggleSelectedPins())

            Menu {
                ForEach(TaskTagColor.allCases) { tag in
                    Button {
                        actions.toggleTag(tag)
                    } label: {
                        Label(
                            actions.tagName(tag),
                            systemImage: actions.isTagChecked(tag) ? "checkmark.circle.fill" : "circle"
                        )
                    }
                }
                Divider()
                Button {
                    actions.openTagSettings()
                } label: {
                    Label("Tag Settings...", systemImage: "gearshape")
                }
            } label: {
                Label("Tag", systemImage: "tag")
            }

            Divider()

            Button {
                actions.edit()
            } label: {
                Label("Edit Task...", systemImage: "pencil")
            }
            .disabled(!canEdit)

            Button {
                actions.comment()
            } label: {
                Label("Edit Comment...", systemImage: job.comment.trimmed.isEmpty ? "text.bubble" : "text.bubble.fill")
            }

            Button {
                actions.moveOutput()
            } label: {
                Label("Move Folder...", systemImage: "folder.badge.plus")
            }
            .disabled(!actions.canMoveOutput())

            Button {
                actions.convertImages()
            } label: {
                Label("Convert Image Format...", systemImage: "photo.badge.arrow.down")
            }
            .disabled(!actions.canConvertImages())

            Menu {
                Button {
                    actions.moveToNewGroup()
                } label: {
                    Label("New Group...", systemImage: "folder.badge.plus")
                }
                if !groupOptions.isEmpty {
                    Divider()
                    ForEach(groupOptions) { group in
                        Button {
                            actions.moveToGroup(group.id)
                        } label: {
                            Label(group.name, systemImage: currentGroupID == group.id ? "checkmark" : "folder")
                        }
                    }
                }
                Divider()
                Button {
                    actions.moveToGroup(nil)
                } label: {
                    Label("No Group", systemImage: currentGroupID == nil ? "checkmark" : "folder.badge.minus")
                }
            } label: {
                Label("Move to Group", systemImage: "folder")
            }
            .disabled(!actions.canMoveToGroup())

            Button {
                actions.info()
            } label: {
                Label("Task Information...", systemImage: "info.circle")
            }

            Divider()

            Menu {
                Button {
                    actions.pages()
                } label: {
                    Label("Pages...", systemImage: "checklist")
                }
                .disabled(!actions.canOpenPageSelector())

                Button {
                    actions.openFirstSelectedOutputs()
                } label: {
                    Label("Open First Output File", systemImage: "doc.viewfinder")
                }
                .disabled(!actions.canOpenFirstSelectedOutputs())

                Button {
                    actions.viewOutputInBrowser()
                } label: {
                    Label("View Downloaded Output in Browser", systemImage: "eye")
                }
                .disabled(!actions.canViewOutputInBrowser())

                Button {
                    actions.createPDF()
                } label: {
                    Label("Create PDF from Images", systemImage: "doc.richtext")
                }
                .disabled(!actions.canCreatePDF())

                Divider()

                Button {
                    actions.moveUp()
                } label: {
                    Label("Move Up", systemImage: "chevron.up")
                }
                .disabled(!actions.canMoveUp())

                Button {
                    actions.moveDown()
                } label: {
                    Label("Move Down", systemImage: "chevron.down")
                }
                .disabled(!actions.canMoveDown())

                Divider()

                Button {
                    actions.pauseAria2()
                } label: {
                    Label("Pause aria2c", systemImage: "pause.circle")
                }
                .disabled(!actions.canPauseAria2())

                Button {
                    actions.resumeAria2()
                } label: {
                    Label("Resume aria2c", systemImage: "play.circle")
                }
                .disabled(!actions.canResumeAria2())

                Button {
                    actions.applyAria2Limits()
                } label: {
                    Label("Apply aria2 Limits", systemImage: "speedometer")
                }
                .disabled(!actions.canApplyAria2Limits())

                Button {
                    actions.applyAria2Files()
                } label: {
                    Label("Apply aria2 Files", systemImage: "list.bullet.rectangle")
                }
                .disabled(!actions.canApplyAria2Files())

                Button {
                    actions.applyAria2Seeding()
                } label: {
                    Label("Apply aria2 Seeding", systemImage: "leaf")
                }
                .disabled(!actions.canApplyAria2Seeding())

                Button {
                    actions.previewAria2Files()
                } label: {
                    Label("List aria2 Files", systemImage: "list.bullet.rectangle.portrait")
                }
                .disabled(!actions.canPreviewAria2Files())

                Button {
                    actions.refreshAria2Peers()
                } label: {
                    Label("Show aria2 Peers", systemImage: "person.2")
                }
                .disabled(!actions.canRefreshAria2Peers())
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
            Button(action: actions.openSource) {
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
        return Button(action: actions.openArchive) {
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
        Button(action: actions.openAccessHelp) {
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
