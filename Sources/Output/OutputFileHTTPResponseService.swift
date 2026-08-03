import Foundation

struct OutputFileHTTPResponseService {
    func response(
        for file: OutputContentFile,
        request: LocalHTTPRequest,
        parameters: [String: String]
    ) -> LocalHTTPResponse {
        do {
            let contentType = Self.mimeType(
                for: file.url
            )
            let requestedFilename =
                Self.parameterValue(
                    in: parameters,
                    keys: [
                        "filename",
                        "download_name",
                        "downloadname",
                        "name"
                    ]
                )
            let filename = (
                requestedFilename ??
                    OutputContentFileService
                    .displayName(file)
            ).sanitizedFilename(maxLength: 180)
            let size = OutputContentFileService
                .fileSize(file)
            let modifiedAt =
                OutputContentFileService
                .modifiedDate(file)
            let etag = Self.etag(
                for: file,
                size: size,
                modifiedAt: modifiedAt
            )
            var headers = [
                "Accept-Ranges": "bytes",
                "Content-Disposition":
                    Self.contentDisposition(
                        disposition(
                            for: request,
                            parameters: parameters
                        ),
                        filename: filename
                    ),
                "ETag": etag,
                "X-Content-Type-Options":
                    "nosniff"
            ]
            if let modifiedAt {
                headers["Last-Modified"] =
                    Self.httpDateString(modifiedAt)
            }

            if Self.isNotModified(
                request,
                etag: etag,
                modifiedAt: modifiedAt
            ) {
                return LocalHTTPResponse.data(
                    Data(),
                    contentType: contentType,
                    status: 304,
                    headers: headers
                )
            }

            if request.method == "HEAD" {
                return Self.headResponse(
                    rangeHeader:
                        request.headers["range"],
                    size: size,
                    contentType: contentType,
                    headers: headers
                )
            }

            let data = try OutputContentFileService
                .data(for: file)
            return Self.dataResponse(
                data,
                rangeHeader:
                    request.headers["range"],
                contentType: contentType,
                headers: headers
            )
        } catch {
            return LocalHTTPResponse.jsonObject(
                [
                    "error":
                        "File could not be read"
                ],
                status: 404
            )
        }
    }

    static func mimeType(
        for url: URL
    ) -> String {
        switch url.pathExtension.lowercased() {
        case "jpg", "jpeg":
            return "image/jpeg"
        case "png":
            return "image/png"
        case "gif":
            return "image/gif"
        case "webp":
            return "image/webp"
        case "avif":
            return "image/avif"
        case "bmp":
            return "image/bmp"
        case "heic":
            return "image/heic"
        case "heif":
            return "image/heif"
        case "mp4", "m4v":
            return "video/mp4"
        case "mov":
            return "video/quicktime"
        case "webm":
            return "video/webm"
        case "mkv":
            return "video/x-matroska"
        case "avi":
            return "video/x-msvideo"
        case "wmv":
            return "video/x-ms-wmv"
        case "flv":
            return "video/x-flv"
        case "ts":
            return "video/mp2t"
        case "mp3":
            return "audio/mpeg"
        case "m4a", "aac":
            return "audio/aac"
        case "wav":
            return "audio/wav"
        case "flac":
            return "audio/flac"
        case "ogg", "opus":
            return "audio/ogg"
        case "html", "htm":
            return "text/html; charset=utf-8"
        case "txt", "log":
            return "text/plain; charset=utf-8"
        case "json":
            return "application/json"
        case "pdf":
            return "application/pdf"
        case "zip", "cbz":
            return "application/zip"
        default:
            return "application/octet-stream"
        }
    }

    private func disposition(
        for request: LocalHTTPRequest,
        parameters: [String: String]
    ) -> String {
        if let disposition = Self.parameterValue(
            in: parameters,
            keys: [
                "disposition",
                "content_disposition",
                "contentdisposition"
            ]
        )?.lowercased() {
            if [
                "attachment",
                "download",
                "save"
            ].contains(disposition) {
                return "attachment"
            }
            if [
                "inline",
                "view",
                "preview"
            ].contains(disposition) {
                return "inline"
            }
        }
        if Self.isTruthy(parameters["inline"]) {
            return "inline"
        }
        if Self.isTruthy(parameters["download"]) ||
            Self.isTruthy(
                parameters["attachment"]
            ) ||
            Self.isTruthy(parameters["save"]) {
            return "attachment"
        }
        return request.path.lowercased()
            .contains("download_file")
            ? "attachment"
            : "inline"
    }

    private static func headResponse(
        rangeHeader: String?,
        size: Int,
        contentType: String,
        headers: [String: String]
    ) -> LocalHTTPResponse {
        switch byteRange(
            from: rangeHeader,
            size: size
        ) {
        case .valid(let range):
            var partialHeaders = headers
            partialHeaders["Content-Range"] =
                "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(size)"
            partialHeaders["Content-Length"] =
                String(range.count)
            return LocalHTTPResponse.data(
                Data(),
                contentType: contentType,
                status: 206,
                headers: partialHeaders
            )
        case .invalid:
            var invalidHeaders = headers
            invalidHeaders["Content-Range"] =
                "bytes */\(size)"
            invalidHeaders["Content-Length"] = "0"
            return LocalHTTPResponse.data(
                Data(),
                contentType:
                    "text/plain; charset=utf-8",
                status: 416,
                headers: invalidHeaders
            )
        case .none:
            var fullHeaders = headers
            fullHeaders["Content-Length"] =
                String(size)
            return LocalHTTPResponse.data(
                Data(),
                contentType: contentType,
                headers: fullHeaders
            )
        }
    }

    private static func dataResponse(
        _ data: Data,
        rangeHeader: String?,
        contentType: String,
        headers: [String: String]
    ) -> LocalHTTPResponse {
        switch byteRange(
            from: rangeHeader,
            size: data.count
        ) {
        case .valid(let range):
            let sliced = data.subdata(in: range)
            var partialHeaders = headers
            partialHeaders["Content-Range"] =
                "bytes \(range.lowerBound)-\(range.upperBound - 1)/\(data.count)"
            return LocalHTTPResponse.data(
                sliced,
                contentType: contentType,
                status: 206,
                headers: partialHeaders
            )
        case .invalid:
            var invalidHeaders = headers
            invalidHeaders["Content-Range"] =
                "bytes */\(data.count)"
            return LocalHTTPResponse.data(
                Data(
                    "Requested Range Not Satisfiable"
                        .utf8
                ),
                contentType:
                    "text/plain; charset=utf-8",
                status: 416,
                headers: invalidHeaders
            )
        case .none:
            return LocalHTTPResponse.data(
                data,
                contentType: contentType,
                headers: headers
            )
        }
    }

    private static func contentDisposition(
        _ disposition: String,
        filename: String
    ) -> String {
        let mode =
            disposition == "attachment"
            ? "attachment"
            : "inline"
        let fallback =
            fallbackFilename(filename)
        let encoded = rfc5987Encode(filename)
        return
            "\(mode); filename=\"\(fallback)\"; filename*=UTF-8''\(encoded)"
    }

    private static func fallbackFilename(
        _ filename: String
    ) -> String {
        let safe = filename.sanitizedFilename(
            maxLength: 180
        )
        let ascii = String(
            safe.unicodeScalars.map {
                scalar -> Character in
                if scalar.value >= 0x20,
                   scalar.value < 0x7f,
                   scalar.value != 0x22,
                   scalar.value != 0x5c {
                    return Character(scalar)
                }
                return "_"
            }
        )
        let fallback = ascii.trimmed
        return fallback.isEmpty
            ? "download"
            : fallback
    }

    private static func rfc5987Encode(
        _ value: String
    ) -> String {
        let allowed = Set(
            "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$&+-.^_`|~"
                .utf8
        )
        return value.utf8.map { byte in
            if allowed.contains(byte) {
                return String(
                    UnicodeScalar(Int(byte))!
                )
            }
            return String(
                format: "%%%02X",
                byte
            )
        }.joined()
    }

    private static func httpDateString(
        _ date: Date
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "en_US_POSIX"
        )
        formatter.timeZone =
            TimeZone(secondsFromGMT: 0)
        formatter.dateFormat =
            "EEE, dd MMM yyyy HH:mm:ss 'GMT'"
        return formatter.string(from: date)
    }

    private static func httpDate(
        from value: String?
    ) -> Date? {
        guard let value = value?.trimmed,
              !value.isEmpty else {
            return nil
        }
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss zzz",
            "EEEE, dd-MMM-yy HH:mm:ss zzz",
            "EEE MMM d HH:mm:ss yyyy"
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "en_US_POSIX"
            )
            formatter.timeZone =
                TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            if let date = formatter.date(
                from: value
            ) {
                return date
            }
        }
        return nil
    }

    private static func isNotModified(
        _ request: LocalHTTPRequest,
        etag: String,
        modifiedAt: Date?
    ) -> Bool {
        if let value =
                request.headers[
                    "if-none-match"
                ]?.trimmed,
           !value.isEmpty {
            return etagHeader(
                value,
                matches: etag
            )
        }
        guard let modifiedAt,
              let since = httpDate(
                  from:
                    request.headers[
                        "if-modified-since"
                    ]
              ) else {
            return false
        }
        return modifiedAt.timeIntervalSince1970
            .rounded(.down) <=
            since.timeIntervalSince1970
            .rounded(.down)
    }

    private static func etagHeader(
        _ value: String,
        matches etag: String
    ) -> Bool {
        value
            .split(separator: ",")
            .map {
                $0.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            }
            .contains { candidate in
                candidate == "*" ||
                    candidate == etag ||
                    candidate.replacingOccurrences(
                        of: "W/",
                        with: ""
                    ) ==
                    etag.replacingOccurrences(
                        of: "W/",
                        with: ""
                    )
            }
    }

    private static func etag(
        for file: OutputContentFile,
        size: Int,
        modifiedAt: Date?
    ) -> String {
        let modified = Int64(
            (
                modifiedAt?.timeIntervalSince1970
                    ?? 0
            ).rounded(.down)
        )
        let identity: String
        if let entry = file.archiveEntry {
            identity = [
                file.archiveURL?.path ?? "",
                file.relativePath,
                String(entry.crc32),
                String(entry.compressedSize),
                String(entry.uncompressedSize),
                String(entry.localHeaderOffset)
            ].joined(separator: "|")
        } else {
            identity = [
                file.url.path,
                file.relativePath
            ].joined(separator: "|")
        }
        let hash = fnv1a64(
            "\(identity)|\(size)|\(modified)"
        )
        return String(
            format: #"W/"%016llx""#,
            hash
        )
    }

    private static func fnv1a64(
        _ value: String
    ) -> UInt64 {
        var hash: UInt64 =
            0xcbf29ce484222325
        for byte in value.utf8 {
            hash ^= UInt64(byte)
            hash =
                hash &* 0x100000001b3
        }
        return hash
    }

    private static func parameterValue(
        in parameters: [String: String],
        keys: [String]
    ) -> String? {
        for key in keys {
            if let value =
                    parameters[key]?.trimmed,
               !value.isEmpty {
                return value
            }
            let normalizedKey =
                normalizedParameterKey(key)
            if let pair = parameters.first(
                where: {
                    normalizedParameterKey($0.key)
                        == normalizedKey
                }
            ),
            !pair.value.trimmed.isEmpty {
                return pair.value.trimmed
            }
        }
        return nil
    }

    private static func normalizedParameterKey(
        _ key: String
    ) -> String {
        key.unicodeScalars
            .filter {
                CharacterSet.alphanumerics
                    .contains($0)
            }
            .map {
                String($0).lowercased()
            }
            .joined()
    }

    private static func isTruthy(
        _ value: String?
    ) -> Bool {
        guard let normalized =
                value?.trimmed.lowercased(),
              !normalized.isEmpty else {
            return false
        }
        return ![
            "0",
            "false",
            "no",
            "off",
            "none"
        ].contains(normalized)
    }

    private enum ByteRange {
        case none
        case invalid
        case valid(Range<Int>)
    }

    private static func byteRange(
        from header: String?,
        size: Int
    ) -> ByteRange {
        guard let header,
              header.lowercased()
                .hasPrefix("bytes=") else {
            return .none
        }
        guard size > 0 else {
            return .invalid
        }
        let value = String(
            header.dropFirst("bytes=".count)
        )
        guard !value.contains(",") else {
            return .invalid
        }
        let parts = value.split(
            separator: "-",
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else {
            return .invalid
        }

        if parts[0].isEmpty,
           let suffixLength = Int(parts[1]),
           suffixLength > 0 {
            let start = max(
                0,
                size - suffixLength
            )
            return .valid(start..<size)
        }

        guard let start = Int(parts[0]),
              start >= 0,
              start < size else {
            return .invalid
        }
        let end = parts[1].isEmpty
            ? size - 1
            : min(
                Int(parts[1]) ?? (size - 1),
                size - 1
            )
        guard end >= start else {
            return .invalid
        }
        return .valid(start..<(end + 1))
    }
}
