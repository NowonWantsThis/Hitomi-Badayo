import Foundation

enum QueueGroupNormalizationService {
    static func normalizedGroups(
        _ storedGroups: [QueueGroup],
        jobs: inout [DownloadJob],
        groupIDMetadataKey: String
    ) -> [QueueGroup] {
        var groups: [QueueGroup] = []
        var seenGroupIDs = Set<UUID>()

        for stored in storedGroups {
            var group = stored
            group.name = group.name.trimmed.isEmpty
                ? "Group"
                : group.name.trimmed
            group.comment = group.comment.trimmed
            group.tags = TaskTagColor.normalizedRawValues(group.tags)
            if !seenGroupIDs.insert(group.id).inserted {
                group.id = UUID()
                seenGroupIDs.insert(group.id)
            }
            group.originalUID = group.originalUID.trimmed
            if group.originalUID.isEmpty {
                group.originalUID = group.id.uuidString
            }
            groups.append(group)
        }

        func boolValue(
            _ raw: String?,
            default defaultValue: Bool
        ) -> Bool {
            guard let value = raw?.trimmed.lowercased(), !value.isEmpty else {
                return defaultValue
            }
            if ["1", "true", "yes", "on"].contains(value) { return true }
            if ["0", "false", "no", "off"].contains(value) { return false }
            return defaultValue
        }

        for jobIndex in jobs.indices {
            let metadata = jobs[jobIndex].metadata
            let explicitID = metadata[groupIDMetadataKey]
                .flatMap { UUID(uuidString: $0.trimmed) }
            let legacyName = (
                metadata["group"] ?? metadata["group_name"] ?? ""
            ).trimmed

            var groupIndex = explicitID.flatMap { id in
                groups.firstIndex { $0.id == id }
            }
            if groupIndex == nil, !legacyName.isEmpty {
                groupIndex = groups.firstIndex {
                    $0.name.caseInsensitiveCompare(legacyName) == .orderedSame
                }
            }

            if groupIndex == nil, explicitID != nil || !legacyName.isEmpty {
                let id: UUID
                if let explicitID, seenGroupIDs.insert(explicitID).inserted {
                    id = explicitID
                } else {
                    id = UUID()
                    seenGroupIDs.insert(id)
                }
                let originalUID = (metadata["hdt_group_uid"] ?? "").trimmed
                let tags = TaskTagColor.normalizedRawValues(
                    (
                        metadata["group_tags"]
                            ?? metadata["hdt_group_tags"]
                            ?? ""
                    )
                    .split(separator: ",")
                    .map(String.init)
                )
                let group = QueueGroup(
                    id: id,
                    name: legacyName.isEmpty ? "Group" : legacyName,
                    comment: metadata["group_comment"] ?? "",
                    isExpanded: boolValue(
                        metadata["hdt_group_expanded"],
                        default: true
                    ),
                    anchorJobID: jobs[jobIndex].id,
                    originalUID: originalUID.isEmpty
                        ? id.uuidString
                        : originalUID,
                    isPinned: boolValue(
                        metadata["hdt_group_pinned"],
                        default: false
                    ),
                    tags: tags
                )
                groups.append(group)
                groupIndex = groups.index(before: groups.endIndex)
            }

            guard let groupIndex else {
                jobs[jobIndex].metadata.removeValue(
                    forKey: groupIDMetadataKey
                )
                continue
            }

            let group = groups[groupIndex]
            jobs[jobIndex].metadata[groupIDMetadataKey] = group.id.uuidString
            jobs[jobIndex].metadata["group"] = group.name
            jobs[jobIndex].metadata.removeValue(forKey: "group_name")
            jobs[jobIndex].metadata["hdt_group_uid"] = group.originalUID
            jobs[jobIndex].metadata["hdt_group_expanded"] = group.isExpanded
                ? "true"
                : "false"
            jobs[jobIndex].metadata["hdt_group_pinned"] = group.isPinned
                ? "true"
                : "false"
            if group.tags.isEmpty {
                jobs[jobIndex].metadata.removeValue(forKey: "group_tags")
                jobs[jobIndex].metadata.removeValue(forKey: "hdt_group_tags")
            } else {
                jobs[jobIndex].metadata["group_tags"] = group.tags.joined(
                    separator: ","
                )
                jobs[jobIndex].metadata.removeValue(forKey: "hdt_group_tags")
            }
            if group.comment.isEmpty {
                jobs[jobIndex].metadata.removeValue(forKey: "group_comment")
            } else {
                jobs[jobIndex].metadata["group_comment"] = group.comment
            }
        }

        let existingJobIDs = Set(jobs.map(\.id))
        for groupIndex in groups.indices {
            let firstMember = jobs.first(where: {
                $0.metadata[groupIDMetadataKey] == groups[groupIndex].id.uuidString
            })
            if groups[groupIndex].anchorJobID == nil
                || !existingJobIDs.contains(groups[groupIndex].anchorJobID!) {
                groups[groupIndex].anchorJobID = firstMember?.id
            }
        }
        return groups
    }
}
