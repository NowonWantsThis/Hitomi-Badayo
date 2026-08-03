import Foundation
import SwiftUI

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
