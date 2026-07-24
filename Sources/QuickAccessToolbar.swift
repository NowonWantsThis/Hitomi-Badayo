import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum QuickAccessCommand: String, CaseIterable, Codable, Identifiable {
    case save
    case group
    case view
    case random
    case top
    case darkMode = "darkmode"
    case loadCookie = "load_cookie"
    case webBrowser = "webbrowser"

    var id: String { rawValue }

    var label: String {
        localizedLabel(language: AppLocalization.currentLanguage())
    }

    func localizedLabel(language: AppInterfaceLanguage) -> String {
        AppLocalization.text(labelKey, language: language)
    }

    private var labelKey: String {
        switch self {
        case .save: return "Save"
        case .group: return "New Group"
        case .view: return "View"
        case .random: return "Pick One at Random"
        case .top: return "Always on top"
        case .darkMode: return "Dark Mode"
        case .loadCookie: return "Load Cookies..."
        case .webBrowser: return "Built-in Web Browser"
        }
    }

    var systemImage: String {
        switch self {
        case .save: return "externaldrive.fill"
        case .group: return "folder.badge.plus"
        case .view: return "eye"
        case .random: return "sparkles"
        case .top: return "pin.fill"
        case .darkMode: return "moon.stars.fill"
        case .loadCookie: return "key.fill"
        case .webBrowser: return "globe"
        }
    }
}

struct QuickAccessItem: Codable, Equatable, Identifiable {
    var command: QuickAccessCommand
    var isEnabled: Bool

    var id: QuickAccessCommand { command }
}

enum QuickAccessConfiguration {
    static let storageKey = "quickAccessItems"
    static let originalStorageKey = "ORDER_QA"

    static let defaultItems = QuickAccessCommand.allCases.map {
        QuickAccessItem(command: $0, isEnabled: false)
    }

    static func normalized(_ items: [QuickAccessItem]) -> [QuickAccessItem] {
        var seen = Set<QuickAccessCommand>()
        var result: [QuickAccessItem] = []

        for item in items where seen.insert(item.command).inserted {
            result.append(item)
        }
        for command in QuickAccessCommand.allCases where !seen.contains(command) {
            result.append(QuickAccessItem(command: command, isEnabled: false))
        }
        return result
    }

    static func load(defaults: UserDefaults = .standard) -> [QuickAccessItem] {
        if let items = decodeNative(defaults.object(forKey: storageKey)) {
            return normalized(items)
        }
        if let items = decodeOriginal(defaults.object(forKey: originalStorageKey)) {
            return normalized(items)
        }
        return defaultItems
    }

    static func save(_ items: [QuickAccessItem], defaults: UserDefaults = .standard) {
        let normalizedItems = normalized(items)
        if let data = try? JSONEncoder().encode(normalizedItems) {
            defaults.set(data, forKey: storageKey)
        }

        let originalItems: [[Any]] = normalizedItems.map {
            [$0.isEnabled, $0.command.rawValue]
        }
        if let data = try? JSONSerialization.data(withJSONObject: originalItems),
           let text = String(data: data, encoding: .utf8) {
            defaults.set(text, forKey: originalStorageKey)
        }
    }

    private static func decodeNative(_ object: Any?) -> [QuickAccessItem]? {
        let data: Data?
        if let object = object as? Data {
            data = object
        } else if let object = object as? String {
            data = object.data(using: .utf8)
        } else {
            data = nil
        }
        guard let data else { return nil }
        return try? JSONDecoder().decode([QuickAccessItem].self, from: data)
    }

    private static func decodeOriginal(_ object: Any?) -> [QuickAccessItem]? {
        let jsonObject: Any
        if let data = object as? Data,
           let decoded = try? JSONSerialization.jsonObject(with: data) {
            jsonObject = decoded
        } else if let text = object as? String,
                  let data = text.data(using: .utf8),
                  let decoded = try? JSONSerialization.jsonObject(with: data) {
            jsonObject = decoded
        } else if let object, JSONSerialization.isValidJSONObject(object) {
            jsonObject = object
        } else {
            return nil
        }

        guard let rows = jsonObject as? [Any] else { return nil }
        var result: [QuickAccessItem] = []
        for row in rows {
            guard let pair = row as? [Any],
                  pair.count >= 2,
                  let rawCommand = pair[1] as? String,
                  let command = QuickAccessCommand(rawValue: rawCommand) else {
                continue
            }
            let enabled: Bool
            if let value = pair[0] as? Bool {
                enabled = value
            } else if let value = pair[0] as? NSNumber {
                enabled = value.boolValue
            } else {
                continue
            }
            result.append(QuickAccessItem(command: command, isEnabled: enabled))
        }
        return result.isEmpty ? nil : result
    }
}

private struct QuickAccessItemDropDelegate: DropDelegate {
    let target: QuickAccessCommand
    @Binding var dragged: QuickAccessCommand?
    let move: (QuickAccessCommand, QuickAccessCommand) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        dragged != nil && info.hasItemsConforming(to: [UTType.utf8PlainText.identifier])
    }

    func dropEntered(info: DropInfo) {
        guard let dragged, dragged != target else { return }
        move(dragged, target)
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        dragged = nil
        return true
    }
}

private final class QuickAccessDragState: ObservableObject {
    @Published var command: QuickAccessCommand?
}

struct QuickAccessCustomizationView: View {
    @ObservedObject var manager: DownloadManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var dragState = QuickAccessDragState()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(AppLocalization.text(
                    "Customize Quick Access Toolbar",
                    language: manager.interfaceLanguage
                ))
                    .font(.headline)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text("Close", language: manager.interfaceLanguage))
                .accessibilityIdentifier("quick-access.close")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text(AppLocalization.text(
                    "Drag and drop to reorder:",
                    language: manager.interfaceLanguage
                ))
                    .font(.title3)
                    .fontWeight(.medium)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(manager.quickAccessItems) { item in
                            quickAccessRow(item)
                        }
                    }
                    .background(Color.primary.opacity(0.035))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.accentColor.opacity(0.55), lineWidth: 1)
                    }
                }
            }
            .padding(16)

            Divider()

            HStack(spacing: 12) {
                Button {
                    manager.toggleAllQuickAccessCommands()
                } label: {
                    Image(systemName: manager.areAllQuickAccessCommandsEnabled
                        ? "checkmark.square.fill"
                        : "checkmark.square")
                        .font(.system(size: 20))
                        .frame(width: 32, height: 30)
                }
                .buttonStyle(.plain)
                .help(AppLocalization.text(
                    manager.areAllQuickAccessCommandsEnabled ? "Clear Selection" : "Select All",
                    language: manager.interfaceLanguage
                ))
                .accessibilityIdentifier("quick-access.toggle-all")

                Button {
                    dismiss()
                } label: {
                    Text(AppLocalization.text("OK", language: manager.interfaceLanguage))
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .frame(height: 32)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .accessibilityIdentifier("quick-access.confirm")
            }
            .padding(14)
        }
        .frame(width: 440, height: 560)
        .interactiveDismissDisabled()
    }

    private func quickAccessRow(_ item: QuickAccessItem) -> some View {
        let commandLabel = item.command.localizedLabel(language: manager.interfaceLanguage)
        return HStack(spacing: 12) {
            Button {
                manager.setQuickAccessCommand(item.command, enabled: !item.isEnabled)
            } label: {
                Image(systemName: item.isEnabled ? "checkmark.square.fill" : "square")
                    .font(.system(size: 19))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(commandLabel)
            .accessibilityValue(AppLocalization.text(
                item.isEnabled ? "On" : "Off",
                language: manager.interfaceLanguage
            ))
            .accessibilityIdentifier("quick-access.toggle.\(item.command.rawValue)")

            Image(systemName: item.command.systemImage)
                .font(.system(size: 18))
                .frame(width: 24)

            Text(commandLabel)
                .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
        .contentShape(Rectangle())
        .background(dragState.command == item.command ? Color.accentColor.opacity(0.12) : Color.clear)
        .overlay(alignment: .bottom) {
            Divider()
                .padding(.leading, 48)
        }
        .onDrag {
            dragState.command = item.command
            return NSItemProvider(object: item.command.rawValue as NSString)
        }
        .onDrop(
            of: [UTType.utf8PlainText.identifier],
            delegate: QuickAccessItemDropDelegate(
                target: item.command,
                dragged: $dragState.command,
                move: manager.moveQuickAccessCommand
            )
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("quick-access.row.\(item.command.rawValue)")
    }
}
