import AppKit
import SwiftUI

extension TaskTagColor {
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
