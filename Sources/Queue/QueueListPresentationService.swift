import Foundation

enum QueueListPresentationService {
    typealias DuplicateKey = (DownloadJob) -> String
    typealias GroupID = (DownloadJob) -> UUID?

    static func filteredJobs(
        orderedJobs: [DownloadJob],
        query: String,
        sortMode: QueueSortMode,
        descending: Bool,
        duplicateKey: DuplicateKey
    ) -> [DownloadJob] {
        let filtered = QueueFilterEngine.filteredJobs(
            orderedJobs,
            query: query,
            duplicateKey: duplicateKey
        )
        return sortedJobs(
            filtered,
            mode: sortMode,
            descending: descending
        )
    }

    static func listEntries(
        orderedJobs: [DownloadJob],
        groups: [QueueGroup],
        query: String,
        sortMode: QueueSortMode,
        descending: Bool,
        duplicateKey: DuplicateKey,
        groupID: GroupID
    ) -> [QueueListEntry] {
        let filteredForGroups = QueueFilterEngine.filteredJobs(
            orderedJobs,
            query: query,
            duplicateKey: duplicateKey
        )
        let visibleJobs = sortedJobs(
            filteredForGroups,
            mode: sortMode,
            descending: descending,
            prioritizingPins: false
        )
        let allDisplayJobs = sortedJobs(
            orderedJobs,
            mode: sortMode,
            descending: descending,
            prioritizingPins: false
        )
        let filterText = query.trimmed.lowercased()
        let filterActive = !filterText.isEmpty
        let groupsByID = Dictionary(
            uniqueKeysWithValues: groups.map { ($0.id, $0) }
        )

        var membersByGroupID: [UUID: [DownloadJob]] = [:]
        var visibleGroupIDs = Set<UUID>()
        for group in groups {
            let groupMatchesFilter = filterActive &&
                "\(group.name) \(group.comment)"
                    .lowercased()
                    .contains(filterText)
            let sourceJobs = groupMatchesFilter ? allDisplayJobs : visibleJobs
            let members = sourceJobs.filter { groupID($0) == group.id }
            membersByGroupID[group.id] = members
            if !members.isEmpty || groupMatchesFilter || !filterActive {
                visibleGroupIDs.insert(group.id)
            }
        }

        var units: [(isPinned: Bool, entries: [QueueListEntry])] = []
        var emittedGroupIDs = Set<UUID>()
        var emittedJobIDs = Set<UUID>()

        func emit(_ group: QueueGroup) {
            guard visibleGroupIDs.contains(group.id),
                  emittedGroupIDs.insert(group.id).inserted else {
                return
            }
            let members = membersByGroupID[group.id] ?? []
            emittedJobIDs.formUnion(members.map(\.id))
            var entries: [QueueListEntry] = [.group(group)]
            if group.isExpanded {
                let orderedMembers = members.filter(\.isPinned) +
                    members.filter { !$0.isPinned }
                entries.append(contentsOf: orderedMembers.map(QueueListEntry.job))
            }
            units.append((isPinned: group.isPinned, entries: entries))
        }

        for job in visibleJobs {
            for group in groups where group.anchorJobID == job.id {
                emit(group)
            }
            if emittedJobIDs.contains(job.id) {
                continue
            }
            if let jobGroupID = groupID(job),
               let group = groupsByID[jobGroupID] {
                emit(group)
                continue
            }
            emittedJobIDs.insert(job.id)
            units.append((isPinned: job.isPinned, entries: [.job(job)]))
        }

        for group in groups {
            emit(group)
        }
        let orderedUnits = units.filter(\.isPinned) +
            units.filter { !$0.isPinned }
        return orderedUnits.flatMap(\.entries)
    }

    static func statusSummaryText(
        jobs: [DownloadJob],
        filteredJobs: [DownloadJob],
        filterActive: Bool
    ) -> String {
        let totalCounts = Dictionary(grouping: jobs, by: \.status)
            .mapValues(\.count)
        let filteredCounts = Dictionary(grouping: filteredJobs, by: \.status)
            .mapValues(\.count)
        return statusGroupOrder.compactMap { status -> String? in
            let total = totalCounts[status, default: 0]
            guard total > 0 else { return nil }
            if filterActive {
                return "\(status.label) \(filteredCounts[status, default: 0])/\(total)"
            }
            return "\(status.label) \(total)"
        }.joined(separator: " · ")
    }

    static func sortedJobs(
        _ jobs: [DownloadJob],
        mode: QueueSortMode,
        descending: Bool,
        prioritizingPins: Bool = true
    ) -> [DownloadJob] {
        guard mode != .manual || descending else { return jobs }
        let indexed = jobs.enumerated().map {
            (index: $0.offset, job: $0.element)
        }
        return indexed.sorted { lhs, rhs in
            if prioritizingPins, lhs.job.isPinned != rhs.job.isPinned {
                return lhs.job.isPinned && !rhs.job.isPinned
            }

            let result = comparison(lhs.job, rhs.job, mode: mode)
            if result == .orderedSame {
                return descending ? lhs.index > rhs.index : lhs.index < rhs.index
            }
            return descending
                ? result == .orderedDescending
                : result == .orderedAscending
        }.map(\.job)
    }

    private static func comparison(
        _ lhs: DownloadJob,
        _ rhs: DownloadJob,
        mode: QueueSortMode
    ) -> ComparisonResult {
        switch mode {
        case .manual:
            return .orderedSame
        case .title:
            return lhs.title.localizedStandardCompare(rhs.title)
        case .status:
            let lhsRank = statusSortRank(lhs.status)
            let rhsRank = statusSortRank(rhs.status)
            if lhsRank != rhsRank {
                return lhsRank < rhsRank
                    ? .orderedAscending
                    : .orderedDescending
            }
            return lhs.status.rawValue.localizedStandardCompare(
                rhs.status.rawValue
            )
        case .site:
            let result = QueueFilterEngine.host(for: lhs)
                .localizedStandardCompare(QueueFilterEngine.host(for: rhs))
            return result == .orderedSame
                ? lhs.source.localizedStandardCompare(rhs.source)
                : result
        case .progress:
            if lhs.progress != rhs.progress {
                return lhs.progress < rhs.progress
                    ? .orderedAscending
                    : .orderedDescending
            }
            if lhs.completed != rhs.completed {
                return lhs.completed < rhs.completed
                    ? .orderedAscending
                    : .orderedDescending
            }
            return lhs.title.localizedStandardCompare(rhs.title)
        case .output:
            return lhs.outputPath.localizedStandardCompare(rhs.outputPath)
        }
    }

    private static func statusSortRank(_ status: JobStatus) -> Int {
        switch status {
        case .queued: return 0
        case .resolving: return 1
        case .downloading: return 2
        case .failed: return 3
        case .cancelled: return 4
        case .finished: return 5
        }
    }

    private static let statusGroupOrder: [JobStatus] = [
        .queued,
        .resolving,
        .downloading,
        .finished,
        .failed,
        .cancelled
    ]
}
