import AppKit
import SwiftUI

struct OutputPreviewWindowView: View {
    let manager: DownloadManager
    @ObservedObject var presentation: AppPresentationStore
    @ObservedObject var queueStore: QueueStore
    let requestClose: () -> Void

    private var previewPresentation: OutputPreviewPresentationSnapshot {
        OutputPreviewPresentationService.snapshot(
            jobs: queueStore.jobs,
            selectedJobID: presentation.outputPreviewJobID,
            files: presentation.outputPreviewFiles,
            selectedFileIndex: presentation.outputPreviewSelectedFileIndex,
            isLoading: presentation.outputPreviewIsLoading
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if presentation.outputPreviewIsLoading && presentation.outputPreviewFiles.isEmpty {
                loadingState
            } else if presentation.outputPreviewFiles.isEmpty {
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
        HStack(spacing: 8) {
            previewActionButtons
            Spacer(minLength: 4)
            previewSummary
            if presentation.outputPreviewIsLoading {
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
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.bar)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var previewActionButtons: some View {
        HStack(spacing: 5) {
            Button {
                manager.selectAdjacentOutputPreviewImage(direction: -1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(width: 22, height: 22)
            }
            .disabled(!manager.canSelectAdjacentOutputPreviewImage(direction: -1))
            .help("Previous image")
            .accessibilityLabel("Previous image")

            Button {
                manager.selectAdjacentOutputPreviewImage(direction: 1)
            } label: {
                Image(systemName: "chevron.down")
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
            .disabled(previewPresentation.selectedFile == nil)
            .help("Open selected file")
            .accessibilityLabel("Open selected file")

            Button {
                if let file = previewPresentation.selectedFile {
                    manager.revealOutputPreviewFile(file)
                }
            } label: {
                Image(systemName: "folder")
                    .frame(width: 22, height: 22)
            }
            .disabled(previewPresentation.selectedFile == nil)
            .help(
                previewPresentation.selectedFile?.isArchiveEntry == true
                    ? "Reveal archive"
                    : "Reveal selected file"
            )
            .accessibilityLabel(
                previewPresentation.selectedFile?.isArchiveEntry == true
                    ? "Reveal archive"
                    : "Reveal selected file"
            )

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
                .disabled(previewPresentation.selectedFile == nil)

                Divider()

                Button {
                    manager.createPDFForOutputPreview()
                } label: {
                    Label("Create PDF", systemImage: "doc.richtext")
                }
                .disabled(previewPresentation.imageFiles.isEmpty)
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
        Text(previewPresentation.summary)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .truncationMode(.middle)
    }

    private var fileList: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Label("\(presentation.outputPreviewFiles.count)", systemImage: "list.bullet")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(
                    "\(previewPresentation.imageFiles.count)",
                    systemImage: "photo"
                )
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(presentation.outputPreviewFiles) { file in
                            OutputPreviewFileRow(
                                file: file,
                                selected: file.originalIndex == presentation.outputPreviewSelectedFileIndex,
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
                    proxy.scrollTo(presentation.outputPreviewSelectedFileIndex, anchor: .center)
                }
                .onChange(of: presentation.outputPreviewSelectedFileIndex) { _, index in
                    proxy.scrollTo(index, anchor: .center)
                }
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }

    private var previewPane: some View {
        scrollPreview
    }

    private var scrollPreview: some View {
        GeometryReader { proxy in
            let contentWidth = max(1, proxy.size.width - 36)
            ScrollView {
                LazyVStack(spacing: 18) {
                    ForEach(previewPresentation.imageFiles) { file in
                        OutputPreviewScrollImage(
                            manager: manager,
                            file: file,
                            contentWidth: contentWidth
                        )
                        .id(file.originalIndex)
                    }
                }
                .scrollTargetLayout()
                .padding(18)
                .frame(maxWidth: .infinity)
            }
            .scrollPosition(id: outputPreviewScrollPosition, anchor: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var outputPreviewScrollPosition: Binding<Int?> {
        Binding(
            get: {
                let selected = presentation.outputPreviewSelectedFileIndex
                return previewPresentation.imageFiles.contains {
                    $0.originalIndex == selected
                } ? selected : nil
            },
            set: { index in
                guard let index,
                      index != presentation.outputPreviewSelectedFileIndex,
                      let file = previewPresentation.imageFiles.first(where: {
                          $0.originalIndex == index
                      }) else { return }
                manager.selectOutputPreviewFile(file)
            }
        )
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No Previewable Output")
                .font(.headline)
            Text(
                previewPresentation.job == nil
                    ? "Select a finished task."
                    : "No output files were found."
            )
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

private struct OutputPreviewScrollImage: View {
    let manager: DownloadManager
    let file: OutputPreviewFile
    let contentWidth: CGFloat

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            if file.isImage {
                OutputPreviewAsyncImage(
                    file: file,
                    contentWidth: contentWidth
                )
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

private struct OutputPreviewAsyncImage: View {
    let file: OutputPreviewFile
    let contentWidth: CGFloat

    @StateObject private var loader = OutputPreviewImageLoader()

    var body: some View {
        let displaySize = OutputPreviewLayoutPolicy.scrollingImageSize(
            imageSize: loader.image?.size,
            contentWidth: contentWidth
        )
        content
            .frame(width: displaySize.width, height: displaySize.height)
            .frame(width: max(1, contentWidth), height: displaySize.height)
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
