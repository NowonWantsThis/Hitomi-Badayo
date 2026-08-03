import AppKit
import SwiftUI

struct QueueThumbnailView: View {
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
