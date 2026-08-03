import AppKit
import Foundation
import SwiftUI

struct FontSettingsView: View {
    let manager: DownloadManager
    @ObservedObject var presentation: AppPresentationStore
    @EnvironmentObject private var settingsStore: SettingsStore
    @Environment(\.dismiss) private var dismiss

    private let defaultSampleKey = "Sekiya Asami / 1234567890 / Download queue"

    private var fontFamilySelection: Binding<String> {
        Binding(
            get: {
                settingsStore.interfaceFontFamily.isEmpty ? "System" : settingsStore.interfaceFontFamily
            },
            set: { value in
                manager.setInterfaceFontFamily(value == "System" ? "" : value)
            }
        )
    }

    private var previewFont: Font {
        settingsStore.interfaceFont ?? .system(size: CGFloat(settingsStore.interfaceFontSize.pointSize))
    }

    private var sampleText: String {
        localizedFontPreviewText(presentation.fontPreviewText)
    }

    private var fontPreviewText: Binding<String> {
        Binding(
            get: { localizedFontPreviewText(presentation.fontPreviewText) },
            set: { presentation.fontPreviewText = $0 }
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
                        ForEach(settingsStore.interfaceFontFamilyOptions, id: \.self) { family in
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
                        get: { settingsStore.interfaceFontSize },
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

                    Text(settingsStore.interfaceFontSummary)
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
        AppLocalization.text(key, language: settingsStore.interfaceLanguage)
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
    let manager: DownloadManager
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var settingsStore: SettingsStore

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
                        get: { settingsStore.statusColorOnlyWebColors },
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
                .foregroundStyle(JobStatusStyle.color(
                    for: status,
                    palette: presentation.statusColorDraftPalette
                ))

            colorSwatch(settingsStore.jobStatusColorPalette.hex(for: status))
                .frame(width: 64, alignment: .leading)

            colorSwatch(presentation.statusColorDraftPalette.hex(for: status))
                .frame(width: 64, alignment: .leading)

            TextField("#RRGGBB", text: Binding(
                get: {
                    presentation.statusColorDraftPalette.hex(for: status)
                },
                set: { manager.setDraftStatusColor($0, for: status) }
            ))
            .font(.system(.body, design: .monospaced))
            .textFieldStyle(.roundedBorder)
            .frame(width: 104)

            ColorPicker("", selection: Binding(
                get: {
                    JobStatusStyle.color(
                        for: status,
                        palette: presentation.statusColorDraftPalette
                    )
                },
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
