import Foundation

struct LocalAPITaskSelectionService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder =
            LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func indexes(
        from request: LocalHTTPRequest,
        jobs: [DownloadJob],
        visibleOrderedJobIndices: [Int],
        isPendingRemoval: (DownloadJob) -> Bool
    ) -> [Int] {
        let parameters = requestDecoder.parameters(from: request)
        if let uids = parameters["uids"] {
            var indexes: [Int] = []
            var seen = Set<Int>()
            for token in requestDecoder.listValues(from: uids) {
                guard let index = index(
                    fromToken: token,
                    jobs: jobs,
                    visibleOrderedJobIndices:
                        visibleOrderedJobIndices,
                    isPendingRemoval: isPendingRemoval
                ), !seen.contains(index) else {
                    continue
                }
                indexes.append(index)
                seen.insert(index)
            }
            return indexes
        }

        if let uid = parameters["uid"] ?? parameters["id"] {
            return index(
                fromToken: uid,
                jobs: jobs,
                visibleOrderedJobIndices: visibleOrderedJobIndices,
                isPendingRemoval: isPendingRemoval
            ).map { [$0] } ?? []
        }

        if let indexToken = parameters["job"],
           let logicalIndex = Int(indexToken),
           let physicalIndex = physicalIndex(
               forLogicalIndex: logicalIndex,
               visibleOrderedJobIndices: visibleOrderedJobIndices
           ) {
            return [physicalIndex]
        }

        if allowsIndexAlias(request),
           let indexToken = parameters["index"],
           let logicalIndex = Int(indexToken),
           let physicalIndex = physicalIndex(
               forLogicalIndex: logicalIndex,
               visibleOrderedJobIndices: visibleOrderedJobIndices
           ) {
            return [physicalIndex]
        }

        return []
    }

    func allowsIndexAlias(_ request: LocalHTTPRequest) -> Bool {
        switch request.path.lowercased() {
        case "/file", "/api/file", "/delete_file",
             "/api/delete_file":
            return false
        default:
            return true
        }
    }

    private func index(
        fromToken token: String,
        jobs: [DownloadJob],
        visibleOrderedJobIndices: [Int],
        isPendingRemoval: (DownloadJob) -> Bool
    ) -> Int? {
        let value = token.trimmed
        guard !value.isEmpty else { return nil }
        if let uuid = UUID(uuidString: value) {
            return jobs.firstIndex {
                $0.id == uuid && !isPendingRemoval($0)
            }
        }
        if let logicalIndex = Int(value) {
            return physicalIndex(
                forLogicalIndex: logicalIndex,
                visibleOrderedJobIndices: visibleOrderedJobIndices
            )
        }
        return nil
    }

    private func physicalIndex(
        forLogicalIndex index: Int,
        visibleOrderedJobIndices: [Int]
    ) -> Int? {
        guard visibleOrderedJobIndices.indices.contains(index) else {
            return nil
        }
        return visibleOrderedJobIndices[index]
    }
}
