import AppKit
import SwiftUI

struct EditablePresetComboBox: NSViewRepresentable {
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

struct SourceFolderPopUpButton: NSViewRepresentable {
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

struct YouTubeCodecPriorityMenu: View {
    let codecPriority: [YouTubeVideoCodec]
    let language: AppInterfaceLanguage
    let onSelect: ([YouTubeVideoCodec]) -> Void

    private var priority: [YouTubeVideoCodec] {
        YouTubeVideoCodec.normalizedPriority(codecPriority)
    }

    private var label: String {
        YouTubeVideoCodec.priorityLabel(priority)
    }

    var body: some View {
        Menu {
            ForEach(YouTubeVideoCodec.allPriorityOrders, id: \.self) { option in
                Button {
                    onSelect(option)
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
        .help(AppLocalization.text("Preferred YouTube video codec order", language: language))
        .accessibilityLabel(AppLocalization.text("YouTube Codec Priority", language: language))
        .accessibilityValue(label)
        .accessibilityIdentifier("settings.youtube-codec-priority")
    }
}
