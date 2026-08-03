import Combine
import Foundation

@MainActor
final class OutputOperationStore: ObservableObject {
    @Published private(set) var imageConversionJobIDs: Set<UUID>
    @Published private(set) var isCopyingGalleryNumbers: Bool

    init(
        imageConversionJobIDs: Set<UUID> = [],
        isCopyingGalleryNumbers: Bool = false
    ) {
        self.imageConversionJobIDs = imageConversionJobIDs
        self.isCopyingGalleryNumbers = isCopyingGalleryNumbers
    }

    func beginImageConversions(jobIDs: [UUID]) {
        imageConversionJobIDs.formUnion(jobIDs)
    }

    func finishImageConversion(jobID: UUID) {
        imageConversionJobIDs.remove(jobID)
    }

    func setCopyingGalleryNumbers(_ isCopying: Bool) {
        isCopyingGalleryNumbers = isCopying
    }
}
