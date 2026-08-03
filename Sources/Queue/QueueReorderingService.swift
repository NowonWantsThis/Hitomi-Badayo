import Foundation

enum QueueReorderingService {
    static func canMoveSelectedJobs(
        _ jobs: [DownloadJob],
        selectedIDs: Set<UUID>,
        offset: Int
    ) -> Bool {
        jobsByMovingSelectedJobs(
            jobs,
            selectedIDs: selectedIDs,
            offset: offset
        ).map(\.id) != jobs.map(\.id)
    }

    static func jobsByMovingSelectedJobs(
        _ jobs: [DownloadJob],
        selectedIDs: Set<UUID>,
        offset: Int
    ) -> [DownloadJob] {
        guard !jobs.isEmpty,
              !selectedIDs.isEmpty,
              offset == -1 || offset == 1 else {
            return jobs
        }

        var reordered = jobs
        if offset < 0 {
            var index = 1
            while index < reordered.count {
                let current = reordered[index]
                let previous = reordered[index - 1]
                if selectedIDs.contains(current.id),
                   !selectedIDs.contains(previous.id),
                   current.isPinned == previous.isPinned {
                    reordered.swapAt(index, index - 1)
                }
                index += 1
            }
        } else {
            var index = reordered.count - 2
            while index >= 0 {
                let current = reordered[index]
                let next = reordered[index + 1]
                if selectedIDs.contains(current.id),
                   !selectedIDs.contains(next.id),
                   current.isPinned == next.isPinned {
                    reordered.swapAt(index, index + 1)
                }
                index -= 1
            }
        }

        return reordered
    }

    static func jobsByMoving(
        _ jobs: [DownloadJob],
        movingIDs: Set<UUID>,
        relativeTo targetID: UUID,
        placeAfter: Bool
    ) -> [DownloadJob]? {
        guard !jobs.isEmpty,
              !movingIDs.isEmpty,
              !movingIDs.contains(targetID),
              jobs.contains(where: { $0.id == targetID }) else {
            return nil
        }

        let moving = jobs.filter { movingIDs.contains($0.id) }
        guard moving.count == movingIDs.count else { return nil }

        var remaining = jobs.filter { !movingIDs.contains($0.id) }
        guard let targetIndex = remaining.firstIndex(where: {
            $0.id == targetID
        }) else {
            return nil
        }
        let insertionIndex = targetIndex + (placeAfter ? 1 : 0)
        remaining.insert(contentsOf: moving, at: insertionIndex)
        return remaining
    }

    static func blockedSummary(
        jobIDs: Set<UUID>,
        offset: Int,
        orderedJobs: [DownloadJob]
    ) -> String {
        let indexes = orderedJobs.indices.filter {
            jobIDs.contains(orderedJobs[$0].id)
        }
        guard !indexes.isEmpty else { return "Select jobs to move" }

        for index in indexes {
            let destination = index + offset
            guard orderedJobs.indices.contains(destination),
                  !jobIDs.contains(orderedJobs[destination].id),
                  orderedJobs[index].isPinned
                    != orderedJobs[destination].isPinned else {
                continue
            }
            return orderedJobs[index].isPinned
                ? "Pinned jobs stay above unpinned jobs"
                : "Pin job before moving above pinned jobs"
        }

        return "Selected jobs cannot move further"
    }
}
