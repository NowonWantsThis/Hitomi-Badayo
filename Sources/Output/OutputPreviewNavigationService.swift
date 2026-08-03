import Foundation

enum OutputPreviewNavigationService {
    static func adjacentImageIndex(
        files: [OutputPreviewFile],
        selectedFileIndex: Int,
        direction: Int
    ) -> Int? {
        guard direction != 0 else { return nil }
        let step = direction > 0 ? 1 : -1

        guard let selectedOffset = files.firstIndex(where: {
            $0.originalIndex == selectedFileIndex
        }) else {
            let images = files.filter(\.isImage)
            return direction > 0
                ? images.first?.originalIndex
                : images.last?.originalIndex
        }

        var offset = selectedOffset + step
        while files.indices.contains(offset) {
            if files[offset].isImage {
                return files[offset].originalIndex
            }
            offset += step
        }
        return nil
    }
}
