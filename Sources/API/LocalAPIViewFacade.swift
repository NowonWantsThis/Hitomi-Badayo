import Foundation

@MainActor
struct LocalAPIViewFacade {
    private let selectionService: OutputViewSelectionService
    private let pageRenderer: LocalAPIViewPageRenderer

    init(
        selectionService: OutputViewSelectionService =
            OutputViewSelectionService(),
        pageRenderer: LocalAPIViewPageRenderer =
            LocalAPIViewPageRenderer()
    ) {
        self.selectionService = selectionService
        self.pageRenderer = pageRenderer
    }

    func response(
        for request: LocalHTTPRequest,
        jobs: [DownloadJob],
        jobIndexes: [Int],
        orderedJobIndices: [Int],
        lazyLoadingDefault: Bool,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> LocalHTTPResponse {
        guard let jobIndex = jobIndexes.first,
              jobs.indices.contains(jobIndex) else {
            return LocalHTTPResponse.html(
                messagePage(
                    title: "Task not found",
                    message: "uid is required."
                ),
                status: 404
            )
        }

        let preferences = APIViewPreferences(query: request.query)
        if jobIndexes.count > 1, request.query["index"] == nil {
            return LocalHTTPResponse.html(
                multiViewPage(
                    jobIndexes: jobIndexes,
                    request: request,
                    preferences: preferences,
                    jobs: jobs,
                    lazyLoadingDefault: lazyLoadingDefault,
                    outputFiles: outputFiles,
                    authQuery: authQuery
                )
            )
        }

        let job = jobs[jobIndex]
        let allFiles = outputFiles(job)
        let files = sortedFiles(
            selectedFiles(allFiles, query: request.query),
            preferences: preferences
        )
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        let auth = authQuery(password)
        let displayTitle = viewTitle(for: job, request: request)
        let viewOptions = viewOptionQuery(from: request)
        let preferenceOptions = preferenceOptionQuery(from: request)
        let mode = viewMode(from: request)
        let previousID = adjacentJobIndex(
            from: jobIndex,
            direction: -1,
            jobs: jobs,
            orderedJobIndices: orderedJobIndices,
            outputFiles: outputFiles
        ).map { jobs[$0].id }
        let nextID = adjacentJobIndex(
            from: jobIndex,
            direction: 1,
            jobs: jobs,
            orderedJobIndices: orderedJobIndices,
            outputFiles: outputFiles
        ).map { jobs[$0].id }

        if mode == "scroll" || mode == "reader" ||
            (mode.isEmpty &&
                LocalAPIRequestDecoder.truthy(request.query["scroll"])) {
            return LocalHTTPResponse.html(
                scrollViewPage(
                    job: job,
                    files: files,
                    previousTaskID: previousID,
                    nextTaskID: nextID,
                    auth: auth,
                    viewOptions: viewOptions,
                    preferenceOptions: preferenceOptions,
                    displayTitle: displayTitle,
                    preferences: preferences,
                    lazyLoadingDefault: lazyLoadingDefault
                )
            )
        }

        if mode == "book" ||
            LocalAPIRequestDecoder.truthy(request.query["single"]) {
            return LocalHTTPResponse.html(
                bookViewPage(
                    job: job,
                    files: files,
                    pageText: readerPageText(from: request),
                    previousTaskID: previousID,
                    nextTaskID: nextID,
                    auth: auth,
                    viewOptions: viewOptions,
                    preferenceOptions: preferenceOptions,
                    displayTitle: displayTitle,
                    preferences: preferences,
                    lazyLoadingDefault: lazyLoadingDefault
                )
            )
        }

        if let indexText = fileIndexText(from: request) {
            guard let selectedIndex = Int(indexText),
                  let selectedPosition = files.firstIndex(where: {
                      $0.originalIndex == selectedIndex
                  }) else {
                return LocalHTTPResponse.html(
                    messagePage(
                        title: "File not found",
                        message: "index is out of range."
                    ),
                    status: 404
                )
            }
            return LocalHTTPResponse.html(
                fileViewPage(
                    job: job,
                    files: files,
                    selectedPosition: selectedPosition,
                    auth: auth,
                    viewOptions: viewOptions,
                    displayTitle: displayTitle,
                    preferences: preferences,
                    lazyLoadingDefault: lazyLoadingDefault
                )
            )
        }

        let chapterGroups = selectionService.chapterGroups(in: allFiles)
        return LocalHTTPResponse.html(
            pageRenderer.overviewPage(
                id: job.id,
                title: displayTitle,
                source: job.source,
                files: viewFileItems(files),
                chapters: chapterGroups.map {
                    LocalAPIViewChapterItem(
                        title: $0.title,
                        indexes: $0.indexes
                    )
                },
                selectedChapterIndex: selectedChapterIndex(
                    in: allFiles,
                    query: request.query
                ),
                previousTaskID: previousID,
                nextTaskID: nextID,
                auth: auth,
                viewOptions: viewOptions,
                preferenceOptions: preferenceOptions,
                preferences: preferences,
                lazyLoadingDefault: lazyLoadingDefault
            )
        )
    }

    func selectedFiles(
        _ files: [APIOutputFile],
        query: [String: String]
    ) -> [APIOutputFile] {
        selectionService.selectedFiles(in: files, query: query)
    }

    func sortedFiles(
        _ files: [APIOutputFile],
        preferences: APIViewPreferences
    ) -> [APIOutputFile] {
        selectionService.sortedFiles(
            files,
            sort: preferences.sort,
            descending: preferences.descending
        )
    }

    func selectedChapterIndex(
        in files: [APIOutputFile],
        query: [String: String]
    ) -> Int? {
        selectionService.selectedChapterIndex(in: files, query: query)
    }

    func fileIndexText(from request: LocalHTTPRequest) -> String? {
        if isViewPath(request.path),
           request.query["uid"] == nil,
           request.query["id"] == nil,
           request.query["uids"] == nil,
           request.query["job"] == nil,
           request.query["index"] != nil {
            return nil
        }
        let isThumbPath = ["/thumb", "/api/thumb"]
            .contains(request.path.lowercased())
        if isThumbPath,
           request.query["uid"] == nil,
           request.query["id"] == nil,
           request.query["uids"] == nil,
           request.query["job"] == nil,
           request.query["index"] != nil {
            return nil
        }
        return LocalAPIRequestDecoder.firstParameterValue(
            in: request.query,
            keys: ["index", "idx", "i", "file_index", "fileindex"]
        )
    }

    private func multiViewPage(
        jobIndexes: [Int],
        request: LocalHTTPRequest,
        preferences: APIViewPreferences,
        jobs: [DownloadJob],
        lazyLoadingDefault: Bool,
        outputFiles: (DownloadJob) -> [APIOutputFile],
        authQuery: (String) -> String
    ) -> String {
        let password = request.query["pw"] ??
            request.query["password"] ?? ""
        let auth = authQuery(password)
        let options = viewOptionQuery(from: request)
        let requestedTitle = request.query["title"]?.trimmed ?? ""
        let title = requestedTitle.isEmpty
            ? "\(jobIndexes.count) Tasks"
            : requestedTitle
        let tasks = jobIndexes.compactMap { jobIndex -> LocalAPIMultiViewTaskItem? in
            guard jobs.indices.contains(jobIndex) else { return nil }
            let job = jobs[jobIndex]
            let files = sortedFiles(
                selectedFiles(
                    outputFiles(job),
                    query: request.query
                ),
                preferences: preferences
            )
            return LocalAPIMultiViewTaskItem(
                id: job.id,
                title: job.title,
                source: job.source,
                files: viewFileItems(files)
            )
        }
        return pageRenderer.multiViewPage(
            title: title,
            tasks: tasks,
            auth: auth,
            viewOptions: options,
            preferences: preferences,
            lazyLoadingDefault: lazyLoadingDefault
        )
    }

    private func scrollViewPage(
        job: DownloadJob,
        files: [APIOutputFile],
        previousTaskID: UUID?,
        nextTaskID: UUID?,
        auth: String,
        viewOptions: String,
        preferenceOptions: String,
        displayTitle: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        let imageFiles = files.enumerated().filter {
            OutputContentFileService.imageExtensions.contains(
                $0.element.url.pathExtension.lowercased()
            )
        }
        return pageRenderer.scrollViewPage(
            id: job.id,
            title: displayTitle,
            images: imageFiles.map {
                LocalAPIScrollViewImageItem(
                    position: $0.offset,
                    originalIndex: $0.element.originalIndex,
                    relativePath: $0.element.relativePath
                )
            },
            previousTaskID: previousTaskID,
            nextTaskID: nextTaskID,
            auth: auth,
            viewOptions: viewOptions,
            preferenceOptions: preferenceOptions,
            preferences: preferences,
            lazyLoadingDefault: lazyLoadingDefault
        )
    }

    private func bookViewPage(
        job: DownloadJob,
        files: [APIOutputFile],
        pageText: String?,
        previousTaskID: UUID?,
        nextTaskID: UUID?,
        auth: String,
        viewOptions: String,
        preferenceOptions: String,
        displayTitle: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        let images = files.filter {
            OutputContentFileService.imageExtensions.contains(
                $0.url.pathExtension.lowercased()
            )
        }.map {
            LocalAPIViewFileItem(
                originalIndex: $0.originalIndex,
                relativePath: $0.relativePath,
                mediaType: "image"
            )
        }
        return pageRenderer.bookViewPage(
            id: job.id,
            title: displayTitle,
            images: images,
            pageText: pageText,
            previousTaskID: previousTaskID,
            nextTaskID: nextTaskID,
            auth: auth,
            viewOptions: viewOptions,
            preferenceOptions: preferenceOptions,
            preferences: preferences,
            lazyLoadingDefault: lazyLoadingDefault
        )
    }

    private func fileViewPage(
        job: DownloadJob,
        files: [APIOutputFile],
        selectedPosition: Int,
        auth: String,
        viewOptions: String,
        displayTitle: String,
        preferences: APIViewPreferences,
        lazyLoadingDefault: Bool
    ) -> String {
        pageRenderer.fileViewPage(
            id: job.id,
            title: displayTitle,
            files: viewFileItems(files),
            selectedPosition: selectedPosition,
            auth: auth,
            viewOptions: viewOptions,
            preferences: preferences,
            lazyLoadingDefault: lazyLoadingDefault
        )
    }

    private func viewFileItems(
        _ files: [APIOutputFile]
    ) -> [LocalAPIViewFileItem] {
        files.map {
            LocalAPIViewFileItem(
                originalIndex: $0.originalIndex,
                relativePath: $0.relativePath,
                mediaType: SourceInputClassificationService.mediaType(
                    for: $0.url
                )
            )
        }
    }

    private func adjacentJobIndex(
        from index: Int,
        direction: Int,
        jobs: [DownloadJob],
        orderedJobIndices: [Int],
        outputFiles: (DownloadJob) -> [APIOutputFile]
    ) -> Int? {
        guard direction != 0,
              let logicalIndex = orderedJobIndices.firstIndex(of: index) else {
            return nil
        }
        var candidate = logicalIndex + direction
        while orderedJobIndices.indices.contains(candidate) {
            let physicalIndex = orderedJobIndices[candidate]
            if jobs.indices.contains(physicalIndex),
               !outputFiles(jobs[physicalIndex]).isEmpty {
                return physicalIndex
            }
            candidate += direction
        }
        return nil
    }

    private func viewTitle(
        for job: DownloadJob,
        request: LocalHTTPRequest
    ) -> String {
        if let title = request.query["title"]?.trimmed, !title.isEmpty {
            return title
        }
        return job.title.isEmpty ? job.source : job.title
    }

    private func viewOptionQuery(
        from request: LocalHTTPRequest
    ) -> String {
        let passthrough: [(String, [String])] = [
            ("start", ["start"]),
            ("end", ["end"]),
            ("chapter", ["chapter"]),
            ("start_chapter", ["start_chapter", "chapter_start"]),
            ("end_chapter", ["end_chapter", "chapter_end"]),
            ("title", ["title"])
        ]
        var items = passthrough.compactMap {
            canonical,
            aliases -> (String, String)? in
            guard let value = LocalAPIRequestDecoder.firstParameterValue(
                in: request.query,
                keys: aliases
            ), !value.isEmpty else {
                return nil
            }
            return (canonical, value)
        }
        items.append(
            contentsOf: APIViewPreferences(query: request.query).queryItems
        )
        return queryString(items)
    }

    private func preferenceOptionQuery(
        from request: LocalHTTPRequest
    ) -> String {
        queryString(APIViewPreferences(query: request.query).queryItems)
    }

    private func queryString(
        _ items: [(String, String)]
    ) -> String {
        let parts = items.map {
            "\($0.0)=\(Self.queryComponent($0.1))"
        }
        return parts.isEmpty ? "" : "&" + parts.joined(separator: "&")
    }

    private func viewMode(from request: LocalHTTPRequest) -> String {
        let raw = LocalAPIRequestDecoder.firstParameterValue(
            in: request.query,
            keys: [
                "mode", "view", "viewer", "reader", "view_mode",
                "viewmode", "viewer_mode", "viewermode", "page_mode",
                "pagemode", "reader_mode", "readermode"
            ]
        )?.lowercased() ?? ""

        switch raw {
        case "book", "page", "paged", "reader", "single",
             "clip_viewer", "clip-viewer", "clipviewer", "image_reader",
             "image-reader", "imagereader", "image_viewer",
             "image-viewer", "imageviewer", "page_viewer",
             "page-viewer", "pageviewer", "one_page", "one-page",
             "onepage", "single_page", "single-page", "singlepage":
            return "book"
        case "all", "files", "file", "file_viewer", "file-viewer",
             "fileviewer", "gallery", "list", "browser", "file_browser",
             "file-browser", "filebrowser":
            return "files"
        case "scroll", "scroller", "continuous", "long", "vertical",
             "photo_scroller", "photo-scroller", "photoscroller",
             "long_strip", "long-strip", "longstrip", "webtoon":
            return "scroll"
        default:
            return raw
        }
    }

    private func readerPageText(
        from request: LocalHTTPRequest
    ) -> String? {
        LocalAPIRequestDecoder.firstParameterValue(
            in: request.query,
            keys: ["page", "p", "page_index", "pageindex"]
        )
    }

    private func isViewPath(_ path: String) -> Bool {
        switch path.lowercased() {
        case "/view", "/api/view", "/viewer", "/api/viewer",
             "/reader", "/api/reader":
            return true
        default:
            return false
        }
    }

    private func messagePage(title: String, message: String) -> String {
        pageRenderer.messagePage(title: title, message: message)
    }

    private static func queryComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return value.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? value
    }
}
