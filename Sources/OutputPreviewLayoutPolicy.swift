import CoreGraphics

enum OutputPreviewLayoutPolicy {
    static let horizontalBreakpoint: CGFloat = 600
    static let minimumContentSize = CGSize(width: 480, height: 420)
    static let minimumSidebarWidth: CGFloat = 220
    static let maximumSidebarWidth: CGFloat = 300
    static let scrollingPlaceholderHeight: CGFloat = 180
    static let maximumScrollingImageHeight: CGFloat = 2_400

    static func windowSize(for visibleSize: CGSize) -> CGSize {
        let availableWidth = max(280, visibleSize.width - 96)
        let availableHeight = max(240, visibleSize.height - 180)
        return CGSize(
            width: min(900, availableWidth),
            height: min(640, availableHeight)
        )
    }

    static func centeredFrame(size: CGSize, in visibleFrame: CGRect) -> CGRect {
        let fittedSize = CGSize(
            width: min(max(1, size.width), visibleFrame.width),
            height: min(max(1, size.height), visibleFrame.height)
        )
        return CGRect(
            x: visibleFrame.midX - fittedSize.width / 2,
            y: visibleFrame.midY - fittedSize.height / 2,
            width: fittedSize.width,
            height: fittedSize.height
        )
    }

    static func usesVerticalLayout(contentWidth: CGFloat) -> Bool {
        contentWidth < horizontalBreakpoint
    }

    static func sidebarWidth(contentWidth: CGFloat) -> CGFloat {
        min(maximumSidebarWidth, max(minimumSidebarWidth, contentWidth * 0.32))
    }

    static func fileListHeight(contentHeight: CGFloat) -> CGFloat {
        min(140, max(64, contentHeight * 0.22))
    }

    static func scrollingImageSize(imageSize: CGSize?, contentWidth: CGFloat) -> CGSize {
        let safeWidth = contentWidth.isFinite ? max(1, contentWidth) : 1
        guard let imageSize,
              imageSize.width.isFinite,
              imageSize.height.isFinite,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return CGSize(width: safeWidth, height: scrollingPlaceholderHeight)
        }

        let scale = min(
            safeWidth / imageSize.width,
            maximumScrollingImageHeight / imageSize.height
        )
        guard scale.isFinite, scale > 0 else {
            return CGSize(width: safeWidth, height: scrollingPlaceholderHeight)
        }
        return CGSize(
            width: max(1, imageSize.width * scale),
            height: max(1, imageSize.height * scale)
        )
    }
}
