import CoreGraphics

struct SearcherLayoutMetrics: Equatable {
    let width: CGFloat
    let height: CGFloat
    let usesCompactControls: Bool
}

enum SearcherLayoutPolicy {
    static let fallbackHostSize = CGSize(width: 840, height: 880)
    static let horizontalInset: CGFloat = 32
    static let verticalInset: CGFloat = 32
    static let minimumWidth: CGFloat = 520
    static let maximumWidth: CGFloat = 900
    static let minimumHeight: CGFloat = 400
    static let maximumHeight: CGFloat = 680
    static let compactWidthThreshold: CGFloat = 720
    static let compactHeightThreshold: CGFloat = 560

    static func metrics(forHostSize hostSize: CGSize) -> SearcherLayoutMetrics {
        let normalizedHost = normalized(hostSize)
        let width = min(
            maximumWidth,
            max(minimumWidth, normalizedHost.width - horizontalInset)
        )
        let height = min(
            maximumHeight,
            max(minimumHeight, normalizedHost.height - verticalInset)
        )
        return SearcherLayoutMetrics(
            width: width,
            height: height,
            usesCompactControls: width < compactWidthThreshold || height < compactHeightThreshold
        )
    }

    private static func normalized(_ size: CGSize) -> CGSize {
        guard size.width.isFinite,
              size.height.isFinite,
              size.width > 0,
              size.height > 0 else {
            return fallbackHostSize
        }
        return size
    }
}
