import AppKit
import SwiftUI

struct ShortcutSettingsView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var settingsStore: SettingsStore

    private var selectedCommand: AppShortcutCommand {
        presentation.shortcutEditorCommand
    }

    private var conflictCommand: AppShortcutCommand? {
        settingsStore.shortcutConflict(
            for: selectedCommand,
            shortcut: presentation.shortcutEditorDraft
        )
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
            manager.beginEditingShortcut(presentation.shortcutEditorCommand)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Label("Shortcuts", systemImage: "keyboard")
                .font(.headline)

            Spacer()

            Button {
                navigation.closeShortcuts()
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
                            shortcutText: settingsStore.shortcutDisplay(
                                for: command
                            ),
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
                labeledShortcutValue(
                    "Current",
                    settingsStore.shortcutDisplay(for: selectedCommand)
                )
                labeledShortcutValue("Default", selectedCommand.defaultShortcut.displayText)
                labeledShortcutValue(
                    "Draft",
                    presentation.shortcutEditorDraft.displayText
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Recorder")
                    .font(.subheadline)
                    .fontWeight(.semibold)

                ShortcutRecorderField(
                    shortcutText: presentation.shortcutEditorDraft.displayText,
                    hasConflict: conflictCommand != nil
                ) { event in
                    manager.recordShortcutDraft(
                        from:
                            AppShortcut
                            .fromKeyEvent(event)
                    )
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
                    get: { presentation.shortcutEditorDraft.key },
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
                            get: {
                                presentation.shortcutEditorDraft.modifiers
                                    .contains(modifier)
                            },
                            set: { manager.setShortcutDraftModifier(modifier, enabled: $0) }
                        ))
                        .toggleStyle(.checkbox)
                        .disabled(presentation.shortcutEditorDraft.key == .none)
                    }
                }
            }

            if let conflict = conflictCommand {
                Label("Conflicts with \(conflict.label)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.caption)
            } else if !presentation.shortcutEditorMessage.isEmpty {
                Text(presentation.shortcutEditorMessage)
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
                .disabled(conflictCommand != nil)
                .keyboardShortcut(.defaultAction)

                Button("Done") {
                    navigation.closeShortcuts()
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
