import Foundation

struct LocalAPIInputToken: Equatable {
    var raw: String
    var normalized: String
}

@MainActor
struct LocalAPITaskMetadataService {
    private let requestDecoder: LocalAPIRequestDecoder

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder()
    ) {
        self.requestDecoder = requestDecoder
    }

    func namesResponse(
        request: LocalHTTPRequest,
        originalShape: Bool,
        jobs: [DownloadJob],
        selectedJobIndex: Int?,
        outputFiles: (DownloadJob) -> [OutputContentFile]
    ) -> LocalHTTPResponse {
        if originalShape,
           let selectedJobIndex,
           jobs.indices.contains(selectedJobIndex),
           !namesWantsObjectResponse(request) {
            return LocalHTTPResponse.jsonObject(
                outputFiles(jobs[selectedJobIndex])
                    .map(\.relativePath)
            )
        }

        return LocalHTTPResponse.jsonObject(
            namesObject(
                jobs: jobs,
                selectedJobIndex: selectedJobIndex,
                outputFiles: outputFiles
            )
        )
    }

    func typesObject(
        request: LocalHTTPRequest?,
        jobs: [DownloadJob],
        outputFiles: (DownloadJob) -> [OutputContentFile],
        quickSearchURL: (String) -> String?,
        classify:
            (String, URL?) -> SourceInputClassification
    ) -> [String: Any] {
        var statusCounts: [String: Int] = [:]
        var mediaCounts: [String: Int] = [:]

        let items: [[String: Any]] = jobs.enumerated().map {
            index,
            job in
            statusCounts[job.status.rawValue, default: 0] += 1
            let files = outputFiles(job)
            var outputTypes: [String: Int] = [:]
            for file in files {
                let type =
                    SourceInputClassificationService
                    .mediaType(for: file.url)
                outputTypes[type, default: 0] += 1
                mediaCounts[type, default: 0] += 1
            }

            let sourceURL = URL(string: job.source)
            return [
                "index": index,
                "id": job.id.uuidString,
                "title": job.title,
                "status": job.status.rawValue,
                "comment": job.comment,
                "range": job.rangeExpression,
                "pinned": job.isPinned,
                "locked": job.isLocked,
                "source": job.source,
                "scheme": sourceURL?.scheme ?? "",
                "host": sourceURL?.host ?? "",
                "outputTypes": outputTypes,
                "fileCount": files.count
            ] as [String: Any]
        }

        var result: [String: Any] = [
            "count": jobs.count,
            "statuses": statusCounts,
            "mediaTypes": mediaCounts,
            "supportedMediaTypes": [
                "image",
                "video",
                "audio",
                "document",
                "file"
            ],
            "items": items
        ]

        if let request,
           let input = typeInput(from: request)?.trimmed,
           !input.isEmpty {
            let inputTypes = inputTypeObjects(
                from: input,
                quickSearchURL: quickSearchURL,
                classify: classify
            )
            var seenTypes = Set<String>()
            let types = inputTypes
                .compactMap { $0["type"] as? String }
                .filter { type in
                    guard !type.isEmpty,
                          !seenTypes.contains(type) else {
                        return false
                    }
                    seenTypes.insert(type)
                    return true
                }
            result["input"] = input
            result["types"] = types
            result["inputTypes"] = inputTypes
        }

        return result
    }

    func headersObject(
        request: LocalHTTPRequest,
        port: String,
        password: String
    ) -> [String: Any] {
        let headerItems: [[String: Any]] =
            request.headers.keys.sorted().map { key in
                [
                    "key": key,
                    "name": key,
                    "value": request.headers[key] ?? ""
                ]
            }
        var requestHeaders: [String: Any] = [
            "method": request.method,
            "path": request.path,
            "contentType":
                request.headers["content-type"] ?? "",
            "userAgent":
                request.headers["user-agent"] ?? "",
            "accept":
                request.headers["accept"] ?? "",
            "hasAuthorization":
                request.headers["authorization"] != nil,
            "hasPasswordHeader":
                request.headers["x-hitomi-password"] != nil
        ]

        if let range = request.headers["range"], !range.isEmpty {
            requestHeaders["range"] = range
        }

        return [
            "headers": request.headers,
            "items": headerItems,
            "count": headerItems.count,
            "request": requestHeaders,
            "response": [
                "contentType":
                    "application/json; charset=utf-8",
                "cors": "http://127.0.0.1:\(port)"
            ],
            "auth": [
                "passwordRequired": !password.trimmed.isEmpty,
                "acceptedQueryKeys": ["pw", "password"],
                "acceptedHeaders": [
                    "X-Hitomi-Password",
                    "Authorization: Bearer <password>"
                ]
            ]
        ]
    }

    func inputTokens(
        from input: String,
        quickSearchURL: (String) -> String?
    ) -> [LocalAPIInputToken] {
        input
            .components(separatedBy: .newlines)
            .flatMap { line -> [LocalAPIInputToken] in
                let trimmedLine = line.trimmed
                guard !trimmedLine.isEmpty else { return [] }
                if let hitomiURL =
                    SourceInputNormalizer.hitomiCustomURIString(
                        from:
                            SourceInputNormalizer.cleanedToken(
                                trimmedLine
                            )
                    ) {
                    return [
                        LocalAPIInputToken(
                            raw: trimmedLine,
                            normalized: hitomiURL
                        )
                    ]
                }
                if let sankakuURL =
                    SourceInputNormalizer
                    .sankakuTagInputURLString(from: trimmedLine) {
                    return [
                        LocalAPIInputToken(
                            raw: trimmedLine,
                            normalized: sankakuURL
                        )
                    ]
                }
                if let booruURL =
                    SourceInputNormalizer
                    .booruTagInputURLString(from: trimmedLine) {
                    return [
                        LocalAPIInputToken(
                            raw: trimmedLine,
                            normalized: booruURL
                        )
                    ]
                }
                if let searchURL = quickSearchURL(trimmedLine) {
                    return [
                        LocalAPIInputToken(
                            raw: trimmedLine,
                            normalized: searchURL
                        )
                    ]
                }
                return trimmedLine
                    .components(
                        separatedBy: .whitespacesAndNewlines
                    )
                    .map {
                        LocalAPIInputToken(
                            raw: $0,
                            normalized:
                                SourceInputNormalizer
                                .normalizedToken($0)
                        )
                    }
            }
            .filter { !$0.normalized.isEmpty }
    }

    private func namesObject(
        jobs: [DownloadJob],
        selectedJobIndex: Int?,
        outputFiles: (DownloadJob) -> [OutputContentFile]
    ) -> [String: Any] {
        guard let selectedJobIndex,
              jobs.indices.contains(selectedJobIndex) else {
            return [
                "count": jobs.count,
                "names": jobs.enumerated().map { index, job in
                    [
                        "index": index,
                        "id": job.id.uuidString,
                        "title": job.title,
                        "source": job.source,
                        "status": job.status.rawValue,
                        "comment": job.comment,
                        "range": job.rangeExpression,
                        "pinned": job.isPinned,
                        "locked": job.isLocked
                    ] as [String: Any]
                }
            ]
        }

        let job = jobs[selectedJobIndex]
        let files = outputFiles(job)
        let fileObjects: [[String: Any]] = files.map { file in
            var object = [
                "index": file.originalIndex,
                "name":
                    OutputContentFileService.displayName(file),
                "relativePath": file.relativePath,
                "path":
                    OutputContentFileService.displayPath(file),
                "type":
                    SourceInputClassificationService
                    .mediaType(for: file.url)
            ] as [String: Any]
            if let archiveURL = file.archiveURL {
                object["archivePath"] = archiveURL.path
                object["archiveEntry"] = file.relativePath
            }
            return object
        }

        return [
            "index": selectedJobIndex,
            "id": job.id.uuidString,
            "title": job.title,
            "source": job.source,
            "count": files.count,
            "names": files.map(\.relativePath),
            "files": fileObjects
        ]
    }

    private func namesWantsObjectResponse(
        _ request: LocalHTTPRequest
    ) -> Bool {
        let parameters = requestDecoder.parameters(from: request)
        let shape = (
            parameters["format"] ??
            parameters["shape"] ??
            parameters["response"] ??
            parameters["mode"] ??
            ""
        ).trimmed.lowercased()
        if ["object", "dict", "map", "full", "detail", "details"]
            .contains(shape) {
            return true
        }
        return LocalAPIRequestDecoder.truthy(
            parameters["object"]
        ) ||
            LocalAPIRequestDecoder.truthy(
                parameters["details"]
            ) ||
            LocalAPIRequestDecoder.truthy(
                parameters["files"]
            )
    }

    private func typeInput(
        from request: LocalHTTPRequest
    ) -> String? {
        let parameters = requestDecoder.parameters(from: request)
        if let input =
            parameters["input"] ??
            parameters["url"] ??
            parameters["urls"],
           !input.trimmed.isEmpty {
            return input
        }

        let bodyText = request.bodyText.trimmed
        return bodyText.isEmpty ? nil : bodyText
    }

    func inputTypeObjects(
        from input: String,
        quickSearchURL: (String) -> String?,
        classify:
            (String, URL?) -> SourceInputClassification
    ) -> [[String: Any]] {
        var seen = Set<String>()
        return inputTokens(
            from: input,
            quickSearchURL: quickSearchURL
        ).compactMap { token -> [String: Any]? in
            let normalized = token.normalized.trimmed
            guard !normalized.isEmpty else { return nil }
            let identity = normalized.lowercased()
            guard !seen.contains(identity) else { return nil }
            seen.insert(identity)

            let url = URL(string: normalized)
            let classification = classify(normalized, url)
            var object: [String: Any] = [
                "raw": token.raw,
                "normalized": normalized,
                "type": classification.type,
                "resolver": classification.resolver,
                "valid": classification.valid
            ]

            if let url {
                object["scheme"] =
                    url.scheme?.lowercased() ?? ""
                object["host"] =
                    url.host?.lowercased() ?? ""
                object["pathExtension"] =
                    url.pathExtension.lowercased()
                object["mediaType"] =
                    SourceInputClassificationService
                    .mediaType(for: url)
            } else {
                object["scheme"] = ""
                object["host"] = ""
                object["pathExtension"] = ""
                object["mediaType"] = ""
            }

            return object
        }
    }
}
