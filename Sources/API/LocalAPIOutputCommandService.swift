import Foundation

struct LocalAPIOutputCommandService {
    typealias PDFCreator =
        (_ outputPath: String, _ title: String) throws -> URL
    typealias ArchiveCreator =
        (_ source: URL, _ destination: URL, _ deleteOriginal: Bool) throws -> URL
    typealias PDFStateRecorder =
        (_ job: DownloadJob, _ pdfURL: URL, _ createdAt: String) -> DownloadJob
    typealias ArchiveStateRecorder =
        (
            _ job: DownloadJob,
            _ archiveURL: URL,
            _ format: ArchiveFileFormat,
            _ created: Bool,
            _ deletedOriginal: Bool,
            _ createdAt: String
        ) -> DownloadJob
    typealias DataLoader = (URL) throws -> Data

    private let requestDecoder: LocalAPIRequestDecoder
    private let pdfCreator: PDFCreator
    private let archiveCreator: ArchiveCreator
    private let pdfStateRecorder: PDFStateRecorder
    private let archiveStateRecorder: ArchiveStateRecorder
    private let dataLoader: DataLoader
    private let dateProvider: () -> Date

    init(
        requestDecoder: LocalAPIRequestDecoder = LocalAPIRequestDecoder(),
        pdfCreator: @escaping PDFCreator = { outputPath, title in
            try PDFOutputService().createPDF(
                fromOutputPath: outputPath,
                title: title
            )
        },
        archiveCreator: @escaping ArchiveCreator = {
            source,
            destination,
            deleteOriginal in
            try OutputService().archiveCompletedFolder(
                source,
                to: destination,
                deleteOriginal: deleteOriginal
            )
        },
        pdfStateRecorder: @escaping PDFStateRecorder = {
            job,
            pdfURL,
            createdAt in
            PDFJobStateService().recordingCreatedPDF(
                job,
                pdfURL: pdfURL,
                createdAt: createdAt
            )
        },
        archiveStateRecorder: @escaping ArchiveStateRecorder = {
            job,
            archiveURL,
            format,
            created,
            deletedOriginal,
            createdAt in
            ArchiveJobStateService().recordingAPIArchive(
                job,
                archive: archiveURL,
                format: format,
                created: created,
                deletedOriginal: deletedOriginal,
                createdAt: createdAt
            )
        },
        dataLoader: @escaping DataLoader = {
            try Data(contentsOf: $0)
        },
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.requestDecoder = requestDecoder
        self.pdfCreator = pdfCreator
        self.archiveCreator = archiveCreator
        self.pdfStateRecorder = pdfStateRecorder
        self.archiveStateRecorder = archiveStateRecorder
        self.dataLoader = dataLoader
        self.dateProvider = dateProvider
    }

    func pdfResponse(
        for request: LocalHTTPRequest,
        job: DownloadJob?,
        index: Int?,
        commit: (DownloadJob) -> Void
    ) -> LocalHTTPResponse {
        guard let job, let index else {
            return Self.taskNotFoundResponse()
        }

        let parameters = requestDecoder.parameters(from: request)
        let requestedTitle = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["title", "name", "filename"]
        )
        let title = requestedTitle ?? job.title

        do {
            let pdfURL = try pdfCreator(job.outputPath, title)
            let createdAt = Self.dateString(dateProvider())
            let updatedJob = pdfStateRecorder(
                job,
                pdfURL,
                createdAt
            )
            commit(updatedJob)

            if pdfWantsFile(parameters) {
                return try fileResponse(
                    at: pdfURL,
                    contentType: "application/pdf",
                    parameters: parameters
                )
            }

            let auth = authQuery(
                request.query["pw"] ??
                    request.query["password"] ?? ""
            )
            return LocalHTTPResponse.jsonObject([
                "ok": true,
                "res": "ok",
                "created": true,
                "id": updatedJob.id.uuidString,
                "index": index,
                "path": pdfURL.path,
                "filename": pdfURL.lastPathComponent,
                "pdfPath": pdfURL.path,
                "pdfCreatedAt": createdAt,
                "download":
                    "/pdf?uid=\(updatedJob.id.uuidString)&download=1\(auth)"
            ])
        } catch {
            return Self.errorResponse(error)
        }
    }

    func archiveResponse(
        for request: LocalHTTPRequest,
        job: DownloadJob?,
        index: Int?,
        commit: (DownloadJob) -> Void
    ) -> LocalHTTPResponse {
        guard var job, let index else {
            return Self.taskNotFoundResponse()
        }

        let parameters = requestDecoder.parameters(from: request)
        let defaultFormat: ArchiveFileFormat =
            request.path.lowercased().contains("cbz")
            ? .cbz
            : .zip
        let requestedFormat = archiveFormat(
            parameters,
            defaultFormat: defaultFormat
        )

        do {
            let result = try createArchive(
                job: &job,
                format: requestedFormat,
                parameters: parameters
            )
            let createdAt = Self.dateString(dateProvider())
            let updatedJob = archiveStateRecorder(
                job,
                result.url,
                result.format,
                result.created,
                result.deletedOriginal,
                createdAt
            )
            commit(updatedJob)

            if archiveWantsFile(
                parameters,
                format: result.format
            ) {
                return try fileResponse(
                    at: result.url,
                    contentType: "application/zip",
                    parameters: parameters
                )
            }

            let auth = authQuery(
                request.query["pw"] ??
                    request.query["password"] ?? ""
            )
            let path = result.format == .cbz ? "/cbz" : "/zip"
            return LocalHTTPResponse.jsonObject([
                "ok": true,
                "res": "ok",
                "created": result.created,
                "id": updatedJob.id.uuidString,
                "index": index,
                "path": result.url.path,
                "filename": result.url.lastPathComponent,
                "archivePath": result.url.path,
                "archiveFormat": result.format.rawValue,
                "archiveCreatedAt": createdAt,
                "deletedOriginal": result.deletedOriginal,
                "download":
                    "\(path)?uid=\(updatedJob.id.uuidString)&download=1\(auth)"
            ])
        } catch {
            return Self.errorResponse(error)
        }
    }

    func pdfWantsFile(_ parameters: [String: String]) -> Bool {
        if LocalAPIRequestDecoder.truthy(parameters["download"]) ||
            LocalAPIRequestDecoder.truthy(parameters["file"]) ||
            LocalAPIRequestDecoder.truthy(parameters["inline"]) ||
            LocalAPIRequestDecoder.truthy(parameters["raw"]) {
            return true
        }
        let format = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["format", "response", "type"]
        )?.lowercased()
        return ["pdf", "file", "download", "binary", "raw"]
            .contains(format ?? "")
    }

    func archiveFormat(
        _ parameters: [String: String],
        defaultFormat: ArchiveFileFormat
    ) -> ArchiveFileFormat {
        let raw = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: [
                "format",
                "archive_format",
                "archiveFormat",
                "ext",
                "extension",
                "type",
                "mode",
                "action",
                "cmd",
                "command",
                "function",
                "name"
            ]
        )?.trimmed.lowercased() ?? ""
        switch raw {
        case
            "cbz",
            ".cbz",
            "create_cbz",
            "createcbz",
            "make_cbz",
            "makecbz",
            "comic",
            "comicbook",
            "comic_book",
            "comic-book":
            return .cbz
        case
            "zip",
            ".zip",
            "create_zip",
            "createzip",
            "make_zip",
            "makezip",
            "archive":
            return .zip
        default:
            return defaultFormat
        }
    }

    func archiveFilename(
        _ raw: String?,
        fallbackBaseName: String,
        format: ArchiveFileFormat
    ) -> String {
        let fallback =
            "\(fallbackBaseName).\(format.fileExtension)"
        var filename = (
            raw?.trimmed.isEmpty == false
            ? raw!.trimmed
            : fallback
        ).sanitizedFilename(maxLength: 180)
        let suffix = ".\(format.fileExtension)"
        if filename.lowercased().hasSuffix(".zip") ||
            filename.lowercased().hasSuffix(".cbz") {
            filename = String(filename.dropLast(4))
        }
        return filename.isEmpty
            ? fallback
            : "\(filename)\(suffix)"
    }

    func archiveDeletesOriginal(
        _ parameters: [String: String]
    ) -> Bool {
        LocalAPIRequestDecoder.truthy(
            LocalAPIRequestDecoder.firstParameterValue(
                in: parameters,
                keys: [
                    "delete",
                    "delete_original",
                    "deleteOriginal",
                    "remove_original",
                    "removeOriginal",
                    "delete_folder",
                    "deleteFolder"
                ]
            )
        )
    }

    func archiveWantsFile(
        _ parameters: [String: String],
        format: ArchiveFileFormat
    ) -> Bool {
        if LocalAPIRequestDecoder.truthy(parameters["download"]) ||
            LocalAPIRequestDecoder.truthy(parameters["file"]) ||
            LocalAPIRequestDecoder.truthy(parameters["inline"]) ||
            LocalAPIRequestDecoder.truthy(parameters["raw"]) {
            return true
        }
        let response = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["response", "return", "output"]
        )?.lowercased()
        if ["file", "download", "binary", "raw", "archive"]
            .contains(response ?? "") {
            return true
        }
        let type = LocalAPIRequestDecoder.firstParameterValue(
            in: parameters,
            keys: ["type"]
        )?.lowercased()
        return type == format.fileExtension
    }

    nonisolated static func canArchiveOutputPath(
        _ path: String,
        fileManager: FileManager = .default
    ) -> Bool {
        let value = path.trimmed
        guard !value.isEmpty else { return false }
        let output = URL(fileURLWithPath: value)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(
            atPath: output.path,
            isDirectory: &isDirectory
        ) {
            return isDirectory.boolValue ||
                ["zip", "cbz"].contains(
                    output.pathExtension.lowercased()
                )
        }
        return OutputOpenService(
            fileManager: fileManager
        ).archiveSiblingURL(forMissingOutput: output) != nil
    }

    private func createArchive(
        job: inout DownloadJob,
        format: ArchiveFileFormat,
        parameters: [String: String]
    ) throws -> (
        url: URL,
        format: ArchiveFileFormat,
        created: Bool,
        deletedOriginal: Bool
    ) {
        let source = URL(fileURLWithPath: job.outputPath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(
            atPath: source.path,
            isDirectory: &isDirectory
        )

        if exists,
           !isDirectory.boolValue,
           ["zip", "cbz"].contains(
               source.pathExtension.lowercased()
           ) {
            let existingFormat =
                ArchiveFileFormat(
                    rawValue: source.pathExtension.lowercased()
                ) ?? format
            return (
                source,
                existingFormat,
                false,
                false
            )
        }

        guard exists, isDirectory.boolValue else {
            throw NativeDownloadError.unsupported(
                "Output folder was not found."
            )
        }

        let requestedName =
            LocalAPIRequestDecoder.firstParameterValue(
                in: parameters,
                keys: [
                    "filename",
                    "download_name",
                    "downloadname",
                    "name",
                    "title"
                ]
            )
        let filename = archiveFilename(
            requestedName,
            fallbackBaseName: source.lastPathComponent,
            format: format
        )
        let destination = AppPaths.uniqueFileURL(
            in: source.deletingLastPathComponent(),
            filename: filename
        )
        let deleteOriginal = archiveDeletesOriginal(parameters)
        let archived = try archiveCreator(
            source,
            destination,
            deleteOriginal
        )
        if deleteOriginal ||
            LocalAPIRequestDecoder.truthy(parameters["replace"]) ||
            LocalAPIRequestDecoder.truthy(parameters["set_output"]) ||
            LocalAPIRequestDecoder.truthy(parameters["setOutput"]) {
            job.outputPath = archived.path
        }
        return (
            archived,
            format,
            true,
            deleteOriginal
        )
    }

    private func fileResponse(
        at url: URL,
        contentType: String,
        parameters: [String: String]
    ) throws -> LocalHTTPResponse {
        let data = try dataLoader(url)
        let disposition =
            LocalAPIRequestDecoder.truthy(parameters["attachment"])
            ? "attachment"
            : "inline"
        let filename = url.lastPathComponent
            .replacingOccurrences(of: "\"", with: "")
        return LocalHTTPResponse.data(
            data,
            contentType: contentType,
            headers: [
                "Content-Disposition":
                    "\(disposition); filename=\"\(filename)\""
            ]
        )
    }

    private func authQuery(_ password: String) -> String {
        guard !password.isEmpty,
              let encoded = password.addingPercentEncoding(
                  withAllowedCharacters: .urlQueryAllowed
              ) else {
            return ""
        }
        return "&pw=\(encoded)"
    }

    private static func taskNotFoundResponse() -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject(
            ["error": "Task not found"],
            status: 404
        )
    }

    private static func errorResponse(
        _ error: Error
    ) -> LocalHTTPResponse {
        LocalHTTPResponse.jsonObject(
            [
                "ok": false,
                "error": AppLocalization.errorText(error),
                "res": "error"
            ],
            status: 400
        )
    }

    private nonisolated static func dateString(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
