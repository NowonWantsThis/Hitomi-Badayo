import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct DuplicateImageFinderWindowView: View {
    let manager: DownloadManager
    @Environment(\.appNavigationCommands) private var navigation
    @EnvironmentObject private var settingsStore: SettingsStore
    @EnvironmentObject private var duplicateImageStore: DuplicateImageStore

    private var duplicateFileCount: Int {
        duplicateImageStore.duplicateFileCount
    }

    private var selectedPathText: String {
        duplicateImageStore.selectedPath.trimmed.isEmpty
            ? "No image selected"
            : duplicateImageStore.selectedPath
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
                .disabled(duplicateImageStore.isScanning)

                Button {
                    manager.clearDuplicateImageFolders()
                } label: {
                    Image(systemName: "house")
                }
                .disabled(
                    settingsStore.duplicateImageFolderPaths.isEmpty ||
                        duplicateImageStore.isScanning
                )
                .help("Use save folder")
            }

            if settingsStore.duplicateImageFolderPaths.isEmpty {
                scanFolderRow(path: settingsStore.destinationPath, isDefault: true)
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(settingsStore.duplicateImageFolderPaths, id: \.self) { path in
                            scanFolderRow(path: path, isDefault: false)
                        }
                    }
                }
            }

            Spacer(minLength: 12)

            Text(settingsStore.duplicateImageScanFolderSummary)
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
                Text(
                    "\(duplicateImageStore.groups.count) groups · \(duplicateFileCount) extra files"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Spacer()

            Button {
                navigation.closeDuplicateImageFinder()
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
                        duplicateImageStore.isScanning ? "Scanning" : "Scan",
                        systemImage: duplicateImageStore.isScanning
                            ? "hourglass"
                            : "arrow.clockwise"
                    )
                }
                .disabled(duplicateImageStore.isScanning)

                Button {
                    manager.clearDuplicateImageResults()
                } label: {
                    Label("Clear", systemImage: "xmark.circle")
                }
                .disabled(
                    duplicateImageStore.groups.isEmpty &&
                        duplicateImageStore.summary.isEmpty
                )

                Button {
                    manager.openSelectedDuplicateImageFolder()
                } label: {
                    Label("Open Folder", systemImage: "folder")
                }
                .disabled(duplicateImageStore.selectedPath.trimmed.isEmpty)

                Spacer()

                if duplicateImageStore.isScanning {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            HStack(spacing: 14) {
                Toggle("Thumbnails", isOn: Binding(
                    get: { settingsStore.showDuplicateImageThumbnails },
                    set: { manager.setDuplicateImageThumbnails($0) }
                ))
                .toggleStyle(.switch)
                .disabled(settingsStore.lowPowerMode)
                .help(settingsStore.lowPowerMode ? "Low Power Mode hides duplicate image thumbnails" : "Show duplicate image thumbnails")

                Toggle("Exclude Same Source", isOn: Binding(
                    get: { settingsStore.duplicateImageExcludeSameSource },
                    set: { manager.setDuplicateImageExcludeSameSource($0) }
                ))
                .toggleStyle(.switch)

                Stepper(value: Binding(
                    get: { settingsStore.duplicateImageSimilarityPercent },
                    set: { manager.setDuplicateImageSimilarityPercent($0) }
                ), in: 80...100) {
                    Text("Similarity \(settingsStore.duplicateImageSimilarityPercent)%")
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

            if !duplicateImageStore.summary.isEmpty {
                Text(duplicateImageStore.summary)
                    .font(.caption)
                    .foregroundStyle(
                        duplicateImageStore.summary.lowercased()
                            .contains("failed")
                            ? .orange
                            : .secondary
                    )
                    .lineLimit(2)
            }
        }
        .padding(14)
    }

    private var results: some View {
        Group {
            if duplicateImageStore.groups.isEmpty {
                VStack(spacing: 10) {
                    Image(
                        systemName: duplicateImageStore.isScanning
                            ? "hourglass"
                            : "photo.stack"
                    )
                        .font(.system(size: 34))
                        .foregroundStyle(.secondary)
                    Text(
                        duplicateImageStore.isScanning
                            ? "Scanning images..."
                            : "No duplicate groups"
                    )
                        .font(.headline)
                    Text(
                        duplicateImageStore.isScanning
                            ? settingsStore.duplicateImageScanFolderSummary
                            : "Run a scan to populate duplicate image groups."
                    )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(duplicateImageStore.groups) { group in
                        DuplicateImageGroupRow(
                            group: group,
                            showsThumbnails: settingsStore.effectiveDuplicateImageThumbnails,
                            selectedPath: duplicateImageStore.selectedPath,
                            autoSelectedPath: duplicateImageStore.autoSelectedPath,
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
                .disabled(duplicateImageStore.isScanning)
                .help("Remove scan folder")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
