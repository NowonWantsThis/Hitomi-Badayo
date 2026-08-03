import Foundation

struct LocalAPIPageSelectorCandidate {
    var index: Int
    var title: String
    var detail: String
    var type: String
    var file: APIOutputFile?
}

@MainActor
struct LocalAPIPageSelectorFacade {
    private let requestDecoder: LocalAPIRequestDecoder
    private let pageRenderer: LocalAPIPageSelectorPageRenderer

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder(),
        pageRenderer: LocalAPIPageSelectorPageRenderer =
            LocalAPIPageSelectorPageRenderer()
    ) {
        self.requestDecoder = requestDecoder
        self.pageRenderer = pageRenderer
    }

    func object(
        for request: LocalHTTPRequest,
        jobs: [DownloadJob],
        selectedJobIndex: Int?,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> [String: Any] {
        guard let selectedJobIndex,
              jobs.indices.contains(selectedJobIndex) else {
            return indexObject(
                request: request,
                jobs: jobs,
                outputFiles: outputFiles,
                authQuery: authQuery
            )
        }
        return jobObject(
            jobIndex: selectedJobIndex,
            request: request,
            jobs: jobs,
            updated: false,
            outputFiles: outputFiles,
            authQuery: authQuery
        )
    }

    func page(
        for request: LocalHTTPRequest,
        jobs: [DownloadJob],
        selectedJobIndex: Int?,
        outputFiles: (DownloadJob) -> [APIOutputFile]
    ) -> String {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        guard let selectedJobIndex,
              jobs.indices.contains(selectedJobIndex) else {
            let items = jobs.map { job in
                let total = pageTotal(for: job, outputFiles: outputFiles)
                let selected = selectedIndexes(
                    range: job.rangeExpression,
                    total: total
                )
                return LocalAPIPageSelectorIndexItem(
                    id: job.id,
                    title: job.title,
                    source: job.source,
                    status: job.status.rawValue,
                    range: job.rangeExpression.trimmed.isEmpty
                        ? "All"
                        : job.rangeExpression,
                    selectedCount: selected.count,
                    totalCount: total
                )
            }
            return pageRenderer.indexPage(
                password: password,
                items: items
            )
        }

        let job = jobs[selectedJobIndex]
        let candidates = candidates(for: job, outputFiles: outputFiles)
        let total = pageTotal(
            for: job,
            candidateCount: candidates.count,
            outputFiles: outputFiles
        )
        let selected = selectedIndexes(
            range: job.rangeExpression,
            total: total
        )
        let selectedSet = Set(selected)
        let visible = Array(candidates.prefix(itemLimit(from: request)))
        return pageRenderer.jobPage(
            password: password,
            state: LocalAPIPageSelectorJobPageState(
                id: job.id,
                title: job.title,
                source: job.source,
                range: job.rangeExpression,
                isActive: isActive(job.status),
                selectedCount: selected.count,
                totalCount: total,
                candidateCount: candidates.count,
                candidates: visible.map { candidate in
                    LocalAPIPageSelectorCandidateItem(
                        index: candidate.index,
                        title: candidate.title,
                        detail: candidate.detail,
                        isSelected: selectedSet.contains(candidate.index),
                        showsThumbnail: candidate.file.map {
                            OutputContentFileService.imageExtensions.contains(
                                $0.url.pathExtension.lowercased()
                            )
                        } ?? false
                    )
                }
            )
        )
    }

    func updateResponse(
        for request: LocalHTTPRequest,
        jobs: [DownloadJob],
        selectedJobIndex: Int?,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String,
        update: (Int, String) -> Void
    ) -> LocalHTTPResponse {
        guard let selectedJobIndex,
              jobs.indices.contains(selectedJobIndex) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Task not found"],
                status: 404
            )
        }
        guard !isActive(jobs[selectedJobIndex].status) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Active task range cannot be edited"],
                status: 400
            )
        }
        let parameters = requestDecoder.parameters(from: request)
        guard let requestedRange = requestedRange(from: parameters) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Missing range"],
                status: 400
            )
        }
        let range = requestedRange.trimmed
        guard ResolvedDownloadRangeService
            .isValidAssetRangeExpression(range) else {
            return LocalHTTPResponse.jsonObject(
                ["error": "Invalid range"],
                status: 400
            )
        }
        let total = pageTotal(
            for: jobs[selectedJobIndex],
            outputFiles: outputFiles
        )
        if total > 0, !range.isEmpty {
            do {
                _ = try ResolvedDownloadRangeService.assetIndexes(
                    forRangeExpression: range,
                    total: total
                )
            } catch {
                return LocalHTTPResponse.jsonObject(
                    ["error": AppLocalization.errorText(error)],
                    status: 400
                )
            }
        }

        update(selectedJobIndex, range)
        var updatedJobs = jobs
        updatedJobs[selectedJobIndex].rangeExpression = range
        return LocalHTTPResponse.jsonObject(
            jobObject(
                jobIndex: selectedJobIndex,
                request: request,
                jobs: updatedJobs,
                updated: true,
                outputFiles: outputFiles,
                authQuery: authQuery
            )
        )
    }

    private func indexObject(
        request: LocalHTTPRequest,
        jobs: [DownloadJob],
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> [String: Any] {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        let auth = authQuery(password)
        let items = jobs.indices.map { index -> [String: Any] in
            let job = jobs[index]
            let total = pageTotal(for: job, outputFiles: outputFiles)
            let selected = selectedIndexes(
                range: job.rangeExpression,
                total: total
            )
            let uid = job.id.uuidString
            return [
                "index": index,
                "id": uid,
                "source": job.source,
                "title": job.title,
                "status": job.status.rawValue,
                "range": job.rangeExpression,
                "rangeExpression": job.rangeExpression,
                "total": total,
                "selectedCount": selected.count,
                "selectedRange": ResolvedDownloadRangeService
                    .compactRangeDescription(
                        fromZeroBasedIndexes: selected
                    ),
                "selector": "/page_selector?uid=\(uid)\(auth)",
                "api": "/api/page_selector?uid=\(uid)\(auth)"
            ]
        }
        return ["ok": true, "count": items.count, "items": items]
    }

    private func jobObject(
        jobIndex: Int,
        request: LocalHTTPRequest,
        jobs: [DownloadJob],
        updated: Bool,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> [String: Any] {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        let auth = authQuery(password)
        let job = jobs[jobIndex]
        let uid = job.id.uuidString
        let candidates = candidates(for: job, outputFiles: outputFiles)
        let total = pageTotal(
            for: job,
            candidateCount: candidates.count,
            outputFiles: outputFiles
        )
        let selected = selectedIndexes(
            range: job.rangeExpression,
            total: total
        )
        let selectedSet = Set(selected)
        let items = candidates.prefix(itemLimit(from: request)).map {
            candidate -> [String: Any] in
            var object: [String: Any] = [
                "index": candidate.index,
                "page": candidate.index + 1,
                "title": candidate.title,
                "detail": candidate.detail,
                "type": candidate.type,
                "selected": selectedSet.contains(candidate.index)
            ]
            if let file = candidate.file {
                object["relativePath"] = file.relativePath
                object["filename"] =
                    OutputContentFileService.displayName(file)
                object["path"] = OutputContentFileService.displayPath(file)
                object["size"] = OutputContentFileService.fileSize(file)
                object["mimeType"] =
                    OutputFileHTTPResponseService.mimeType(for: file.url)
                object["file"] =
                    "/file?uid=\(uid)&index=\(file.originalIndex)\(auth)"
                object["view"] =
                    "/view?uid=\(uid)&index=\(file.originalIndex)\(auth)"
                let ext = file.url.pathExtension.lowercased()
                if OutputContentFileService.imageExtensions.contains(ext) ||
                    OutputContentFileService.videoExtensions.contains(ext) {
                    object["thumb"] =
                        "/thumb?uid=\(uid)&index=\(file.originalIndex)\(auth)"
                }
            }
            return object
        }

        return [
            "ok": true,
            "updated": updated,
            "index": jobIndex,
            "id": uid,
            "source": job.source,
            "title": job.title,
            "status": job.status.rawValue,
            "message": job.message,
            "comment": job.comment,
            "range": job.rangeExpression,
            "rangeExpression": job.rangeExpression,
            "total": total,
            "itemCount": items.count,
            "truncated": candidates.count > items.count,
            "selectedIndexes": selected,
            "selectedPages": selected.map { $0 + 1 },
            "selectedCount": selected.count,
            "selectedRange": ResolvedDownloadRangeService
                .compactRangeDescription(fromZeroBasedIndexes: selected),
            "items": Array(items),
            "selector": "/page_selector?uid=\(uid)\(auth)",
            "api": "/api/page_selector?uid=\(uid)\(auth)",
            "info": "/info?uid=\(uid)\(auth)",
            "view": "/view?uid=\(uid)\(auth)"
        ]
    }

    func candidates(
        for job: DownloadJob,
        outputFiles: (DownloadJob) -> [APIOutputFile]
    ) -> [LocalAPIPageSelectorCandidate] {
        let files = outputFiles(job)
        if !files.isEmpty {
            return files.map { file in
                let type = SourceInputClassificationService.mediaType(
                    for: file.url
                )
                return LocalAPIPageSelectorCandidate(
                    index: file.originalIndex,
                    title: file.relativePath,
                    detail: type,
                    type: type,
                    file: file
                )
            }
        }
        let total = pageTotal(
            for: job,
            candidateCount: 0,
            outputFiles: outputFiles
        )
        guard total > 0 else { return [] }
        return (0..<min(total, 2_000)).map { index in
            LocalAPIPageSelectorCandidate(
                index: index,
                title: String(format: "Page %02d", index + 1),
                detail: "",
                type: "page",
                file: nil
            )
        }
    }

    func pageTotal(
        for job: DownloadJob,
        candidateCount: Int? = nil,
        outputFiles: (DownloadJob) -> [APIOutputFile]
    ) -> Int {
        if let candidateCount, candidateCount > 0 {
            return candidateCount
        }
        let outputCount = outputFiles(job).count
        if outputCount > 0 { return outputCount }
        let metadataCount = [
            "range_total", "page_count", "pages", "total_pages",
            "file_count", "files", "total"
        ].compactMap { job.metadata[$0].flatMap(Int.init) }.max() ?? 0
        return max(job.total, job.completed, metadataCount)
    }

    func selectedIndexes(
        range: String,
        total: Int
    ) -> [Int] {
        guard total > 0 else { return [] }
        let trimmed = range.trimmed
        guard !trimmed.isEmpty else { return Array(0..<total) }
        return (
            try? ResolvedDownloadRangeService.assetIndexes(
                forRangeExpression: trimmed,
                total: total
            )
        ) ?? []
    }

    private func itemLimit(from request: LocalHTTPRequest) -> Int {
        let parameters = requestDecoder.parameters(from: request)
        let value = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["limit", "max", "count"]
        ).flatMap(Int.init) ?? 500
        return max(1, min(5_000, value))
    }

    private func requestedRange(
        from parameters: [String: String]
    ) -> String? {
        if LocalAPIRequestDecoder.truthy(
            LocalAPIRequestDecoder.parameterValueAllowingEmpty(
                in: parameters,
                keys: ["all", "select_all", "selectAll"]
            ) ?? ""
        ) {
            return ""
        }
        if LocalAPIRequestDecoder.truthy(
            LocalAPIRequestDecoder.parameterValueAllowingEmpty(
                in: parameters,
                keys: ["clear", "reset", "none"]
            ) ?? ""
        ) {
            return ""
        }
        guard let raw = LocalAPIRequestDecoder.parameterValueAllowingEmpty(
            in: parameters,
            keys: [
                "range", "range_expression", "rangeExpression", "pages",
                "page", "selection", "selected", "indexes", "indices",
                "items", "value"
            ]
        ) else {
            return nil
        }
        return raw
            .replacingOccurrences(of: "\r\n", with: ",")
            .replacingOccurrences(of: "\n", with: ",")
            .replacingOccurrences(of: "\r", with: ",")
            .trimmed
    }

    private func isActive(_ status: JobStatus) -> Bool {
        status == .resolving || status == .downloading
    }
}
