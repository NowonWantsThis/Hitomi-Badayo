import Foundation

@MainActor
struct LocalAPITextFacade {
    private let requestDecoder: LocalAPIRequestDecoder
    private let contentFileService: OutputContentFileService
    private let pageRenderer: LocalAPITextPageRenderer
    private let viewPageRenderer: LocalAPIViewPageRenderer

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder(),
        contentFileService: OutputContentFileService = OutputContentFileService(),
        pageRenderer: LocalAPITextPageRenderer = LocalAPITextPageRenderer(),
        viewPageRenderer: LocalAPIViewPageRenderer = LocalAPIViewPageRenderer()
    ) {
        self.requestDecoder = requestDecoder
        self.contentFileService = contentFileService
        self.pageRenderer = pageRenderer
        self.viewPageRenderer = viewPageRenderer
    }

    func response(
        for request: LocalHTTPRequest,
        jobs: [DownloadJob],
        selectJobIndex: (LocalHTTPRequest) -> Int?,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> LocalHTTPResponse {
        guard hasJobSelector(request) else {
            return LocalHTTPResponse.jsonObject(
                indexObject(
                    request: request,
                    jobs: jobs,
                    outputFiles: outputFiles,
                    authQuery: authQuery
                )
            )
        }
        do {
            guard let selection = try selection(
                from: request,
                jobs: jobs,
                selectJobIndex: selectJobIndex,
                outputFiles: outputFiles
            ) else {
                return LocalHTTPResponse.jsonObject(
                    ["error": "Task not found"],
                    status: 404
                )
            }
            return LocalHTTPResponse.jsonObject(
                object(
                    selection: selection,
                    request: request,
                    outputFiles: outputFiles,
                    authQuery: authQuery
                )
            )
        } catch {
            return LocalHTTPResponse.jsonObject(
                ["error": AppLocalization.errorText(error)],
                status: 400
            )
        }
    }

    func page(
        for request: LocalHTTPRequest,
        jobs: [DownloadJob],
        selectJobIndex: (LocalHTTPRequest) -> Int?,
        outputFiles: (DownloadJob) -> [APIOutputFile]
    ) -> String {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        guard hasJobSelector(request) else {
            let items = jobs.compactMap { job -> LocalAPITextIndexPageItem? in
                let files = candidateFiles(in: outputFiles(job))
                let hasMessage = !job.message.trimmed.isEmpty ||
                    !job.comment.trimmed.isEmpty
                guard !files.isEmpty || hasMessage else { return nil }
                return LocalAPITextIndexPageItem(
                    id: job.id,
                    title: job.title,
                    source: job.source,
                    message: job.message,
                    hasMessage: hasMessage,
                    files: files.map {
                        LocalAPITextPageFileItem(
                            index: $0.originalIndex,
                            relativePath: $0.relativePath
                        )
                    }
                )
            }
            return pageRenderer.indexPage(
                password: password,
                items: items
            )
        }

        do {
            guard let selection = try selection(
                from: request,
                jobs: jobs,
                selectJobIndex: selectJobIndex,
                outputFiles: outputFiles
            ) else {
                return messagePage(
                    title: "Task not found",
                    message: "uid or job is required."
                )
            }
            return pageRenderer.detailPage(
                password: password,
                state: LocalAPITextDetailPageState(
                    id: selection.job.id,
                    title: selection.job.title,
                    source: selection.job.source,
                    filename: selection.file?.relativePath ??
                        "Task Messages",
                    selectedFileIndex: selection.file?.originalIndex,
                    text: selection.text,
                    bytesRead: selection.bytesRead,
                    byteCount: selection.byteCount,
                    isTruncated: selection.truncated,
                    message: selection.job.message,
                    comment: selection.job.comment,
                    files: candidateFiles(
                        in: outputFiles(selection.job)
                    ).map {
                        LocalAPITextPageFileItem(
                            index: $0.originalIndex,
                            relativePath: $0.relativePath
                        )
                    }
                )
            )
        } catch {
            return messagePage(
                title: "Text could not be read",
                message: AppLocalization.errorText(error)
            )
        }
    }

    func candidateFiles(
        in files: [APIOutputFile]
    ) -> [APIOutputFile] {
        contentFileService.textCandidateFiles(in: files)
    }

    func isTextFile(_ file: APIOutputFile) -> Bool {
        contentFileService.isTextFile(file)
    }

    func readTextFile(
        _ file: APIOutputFile,
        limit: Int
    ) throws -> APITextReadResult {
        try contentFileService.readTextFile(file, limit: limit)
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
        let items = jobs.indices.compactMap { index -> [String: Any]? in
            let job = jobs[index]
            let files = candidateFiles(in: outputFiles(job))
            let hasMessage = !job.message.trimmed.isEmpty ||
                !job.comment.trimmed.isEmpty
            guard !files.isEmpty || hasMessage else { return nil }
            let uid = job.id.uuidString
            let firstFile = files.first
            let textLink = firstFile.map {
                "/text?uid=\(uid)&index=\($0.originalIndex)\(auth)"
            } ?? "/text?uid=\(uid)\(auth)"
            return [
                "id": uid,
                "job": index,
                "source": job.source,
                "title": job.title,
                "status": job.status.rawValue,
                "message": job.message,
                "comment": job.comment,
                "textFileCount": files.count,
                "firstTextFile": firstFile?.relativePath ?? "",
                "text": textLink,
                "api": firstFile.map {
                    "/api/text?uid=\(uid)&index=\($0.originalIndex)\(auth)"
                } ?? "/api/text?uid=\(uid)\(auth)",
                "files": files.map {
                    fileObject($0, jobID: uid, auth: auth)
                }
            ]
        }
        return [
            "ok": true,
            "count": items.count,
            "total": jobs.count,
            "items": items
        ]
    }

    private func selection(
        from request: LocalHTTPRequest,
        jobs: [DownloadJob],
        selectJobIndex: (LocalHTTPRequest) -> Int?,
        outputFiles: (DownloadJob) -> [APIOutputFile]
    ) throws -> APITextSelection? {
        guard let jobIndex = selectJobIndex(request),
              jobs.indices.contains(jobIndex) else {
            return nil
        }
        let job = jobs[jobIndex]
        let allFiles = outputFiles(job)
        let textFiles = candidateFiles(in: allFiles)
        let selectedFile: APIOutputFile?

        if let fileIndexText = fileIndexText(from: request) {
            guard let fileIndex = Int(fileIndexText),
                  allFiles.indices.contains(fileIndex) else {
                throw NSError(
                    domain: "HitomiBadayo.APIText",
                    code: 1,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "File index is out of range."
                    ]
                )
            }
            let requested = allFiles[fileIndex]
            guard isTextFile(requested) else {
                throw NSError(
                    domain: "HitomiBadayo.APIText",
                    code: 2,
                    userInfo: [
                        NSLocalizedDescriptionKey:
                            "Selected output file is not a supported text document."
                    ]
                )
            }
            selectedFile = requested
        } else {
            selectedFile = textFiles.first
        }

        if let selectedFile {
            let read = try readTextFile(
                selectedFile,
                limit: textLimit(from: request)
            )
            return APITextSelection(
                jobIndex: jobIndex,
                job: job,
                file: selectedFile,
                text: read.text,
                bytesRead: read.bytesRead,
                byteCount: OutputContentFileService.fileSize(selectedFile),
                truncated: read.truncated,
                source: "file"
            )
        }

        let fallbackText = [
            job.message.trimmed.isEmpty
                ? nil
                : "Message: \(job.message.trimmed)",
            job.comment.trimmed.isEmpty
                ? nil
                : "Comment: \(job.comment.trimmed)"
        ].compactMap { $0 }.joined(separator: "\n\n")
        return APITextSelection(
            jobIndex: jobIndex,
            job: job,
            file: nil,
            text: fallbackText,
            bytesRead: fallbackText.utf8.count,
            byteCount: fallbackText.utf8.count,
            truncated: false,
            source: fallbackText.isEmpty ? "job" : "message"
        )
    }

    private func object(
        selection: APITextSelection,
        request: LocalHTTPRequest,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> [String: Any] {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        let auth = authQuery(password)
        let uid = selection.job.id.uuidString
        let file = selection.file
        let fileObject: Any = file.map {
            self.fileObject($0, jobID: uid, auth: auth)
        } ?? NSNull()
        let fileIndex: Any = file.map(\.originalIndex) ?? NSNull()
        let filename = file.map(OutputContentFileService.displayName) ?? ""
        let download = file.map {
            "/file?uid=\(uid)&index=\($0.originalIndex)\(auth)"
        } ?? ""
        return [
            "ok": true,
            "id": uid,
            "job": selection.jobIndex,
            "source": selection.job.source,
            "title": selection.job.title,
            "status": selection.job.status.rawValue,
            "message": selection.job.message,
            "comment": selection.job.comment,
            "textSource": selection.source,
            "text": selection.text,
            "bytes": selection.bytesRead,
            "size": selection.byteCount,
            "truncated": selection.truncated,
            "index": fileIndex,
            "filename": filename,
            "relativePath": file?.relativePath ?? "",
            "mimeType": file.map {
                OutputFileHTTPResponseService.mimeType(for: $0.url)
            } ?? "text/plain; charset=utf-8",
            "file": fileObject,
            "files": candidateFiles(
                in: outputFiles(selection.job)
            ).map {
                self.fileObject($0, jobID: uid, auth: auth)
            },
            "download": download,
            "view": "/text?uid=\(uid)\(file.map { "&index=\($0.originalIndex)" } ?? "")\(auth)",
            "allFiles": "/view?uid=\(uid)\(auth)"
        ]
    }

    private func fileObject(
        _ file: APIOutputFile,
        jobID: String,
        auth: String
    ) -> [String: Any] {
        [
            "index": file.originalIndex,
            "relativePath": file.relativePath,
            "filename": OutputContentFileService.displayName(file),
            "path": OutputContentFileService.displayPath(file),
            "size": OutputContentFileService.fileSize(file),
            "mediaType": SourceInputClassificationService.mediaType(
                for: file.url
            ),
            "mimeType": OutputFileHTTPResponseService.mimeType(
                for: file.url
            ),
            "text": "/text?uid=\(jobID)&index=\(file.originalIndex)\(auth)",
            "api": "/api/text?uid=\(jobID)&index=\(file.originalIndex)\(auth)",
            "download": "/file?uid=\(jobID)&index=\(file.originalIndex)\(auth)"
        ]
    }

    private func hasJobSelector(_ request: LocalHTTPRequest) -> Bool {
        let parameters = requestDecoder.parameters(from: request)
        return parameters["uid"] != nil ||
            parameters["id"] != nil ||
            parameters["uids"] != nil ||
            parameters["job"] != nil ||
            parameters["index"] != nil
    }

    private func fileIndexText(
        from request: LocalHTTPRequest
    ) -> String? {
        let query = request.query
        let hasExplicitJob = query["uid"] != nil ||
            query["id"] != nil ||
            query["uids"] != nil ||
            query["job"] != nil
        if !hasExplicitJob, query["index"] != nil {
            return LocalAPIRequestDecoder.firstParameterValue(
                in: query,
                keys: ["idx", "i", "file_index", "fileindex"]
            )
        }
        return LocalAPIRequestDecoder.firstParameterValue(
            in: query,
            keys: ["index", "idx", "i", "file_index", "fileindex"]
        )
    }

    private func textLimit(from request: LocalHTTPRequest) -> Int {
        let parameters = requestDecoder.parameters(from: request)
        let defaultLimit = 1_048_576
        let maxLimit = 10_485_760
        guard let token = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["limit", "max", "bytes", "max_bytes", "maxbytes"]
        ), let value = Int(token) else {
            return defaultLimit
        }
        return max(1, min(maxLimit, value))
    }

    private func messagePage(title: String, message: String) -> String {
        viewPageRenderer.messagePage(title: title, message: message)
    }
}
