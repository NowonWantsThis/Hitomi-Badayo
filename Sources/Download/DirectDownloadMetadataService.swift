import CoreFoundation
import Foundation

enum DirectDownloadMetadataService {
    static func filename(
        for url: URL,
        response: HTTPURLResponse? = nil
    ) -> String {
        if let headerName =
            responseFilename(from: response) {
            return filenameByAppendingContentTypeExtensionIfNeeded(
                headerName,
                response: response
            )
        }
        if let hint = queryFilenameHint(from: url) {
            return filenameByAppendingContentTypeExtensionIfNeeded(
                hint,
                response: response
            )
        }
        let last = url.lastPathComponent.trimmed
        if last.isEmpty || last == "/" {
            return filenameByAppendingContentTypeExtensionIfNeeded(
                "download",
                response: response
            )
        }
        return filenameByAppendingContentTypeExtensionIfNeeded(
            last,
            response: response
        )
    }

    static func metadata(
        for url: URL,
        filename: String,
        response: HTTPURLResponse? = nil,
        byteCount: Int? = nil,
        splitSegmentCount: Int? = nil
    ) -> [String: String] {
        let ext =
            (filename as NSString)
            .pathExtension
            .lowercased()
        let basename =
            (filename as NSString)
            .deletingPathExtension
        let host = url.host ?? ""
        let contentType =
            response?
            .value(
                forHTTPHeaderField:
                    "Content-Type"
            )?
            .components(separatedBy: ";")
            .first?
            .trimmed ?? ""
        let contentLength =
            response?
            .value(
                forHTTPHeaderField:
                    "Content-Length"
            )?
            .trimmed
        let effectiveByteCount =
            byteCount.map(String.init) ??
            contentLength ??
            ""
        let segmentCount =
            splitSegmentCount.map(String.init) ??
            ""
        return DownloadMetadata.clean([
            "series": basename,
            "category":
                DownloadContentClassifier.category(
                    forExtension: ext,
                    contentType: contentType
                ),
            "type": "direct",
            "download_mode":
                (splitSegmentCount ?? 1) > 1
                ? "split"
                : "single",
            "segment_count": segmentCount,
            "format": ext,
            "host": host,
            "site": host,
            "filename": filename,
            "basename": basename,
            "ext": ext,
            "slug":
                sourceSlug(
                    from: url,
                    fallback: basename
                ),
            "path": url.path,
            "query": url.query ?? "",
            "url": url.absoluteString,
            "content_type": contentType,
            "content_length":
                contentLength ?? "",
            "byte_count":
                effectiveByteCount,
            "title": basename
        ])
    }

    static func sourceSlug(
        from url: URL,
        fallback: String
    ) -> String {
        let last =
            url.deletingPathExtension()
            .lastPathComponent
        if !last.trimmed.isEmpty {
            return last.sanitizedFilename(
                maxLength: 120
            )
        }
        return fallback.sanitizedFilename(
            maxLength: 120
        )
    }

    private static func filenameByAppendingContentTypeExtensionIfNeeded(
        _ filename: String,
        response: HTTPURLResponse?
    ) -> String {
        let trimmed = filename.trimmed
        guard !trimmed.isEmpty,
              (trimmed as NSString)
                .pathExtension
                .trimmed
                .isEmpty,
              let ext =
                directDownloadExtension(
                    forContentType:
                        response?
                        .value(
                            forHTTPHeaderField:
                                "Content-Type"
                        )
                ) else {
            return trimmed
        }
        return "\(trimmed).\(ext)"
    }

    private static func directDownloadExtension(
        forContentType rawContentType:
            String?
    ) -> String? {
        let contentType =
            rawContentType?
            .components(separatedBy: ";")
            .first?
            .trimmed
            .lowercased() ?? ""
        guard !contentType.isEmpty else {
            return nil
        }

        let exact: [String: String] = [
            "image/jpeg": "jpg",
            "image/jpg": "jpg",
            "image/png": "png",
            "image/gif": "gif",
            "image/webp": "webp",
            "image/avif": "avif",
            "image/bmp": "bmp",
            "image/svg+xml": "svg",
            "video/mp4": "mp4",
            "video/mpeg": "mpg",
            "video/webm": "webm",
            "video/quicktime": "mov",
            "video/x-matroska": "mkv",
            "video/x-msvideo": "avi",
            "audio/mpeg": "mp3",
            "audio/mp3": "mp3",
            "audio/mp4": "m4a",
            "audio/aac": "aac",
            "audio/flac": "flac",
            "audio/wav": "wav",
            "audio/x-wav": "wav",
            "audio/ogg": "ogg",
            "application/pdf": "pdf",
            "application/epub+zip": "epub",
            "application/x-mobipocket-ebook":
                "mobi",
            "application/vnd.amazon.ebook":
                "azw",
            "application/msword": "doc",
            "application/vnd.openxmlformats-officedocument.wordprocessingml.document":
                "docx",
            "application/vnd.ms-excel":
                "xls",
            "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet":
                "xlsx",
            "application/vnd.ms-powerpoint":
                "ppt",
            "application/vnd.openxmlformats-officedocument.presentationml.presentation":
                "pptx",
            "application/vnd.oasis.opendocument.text":
                "odt",
            "application/vnd.oasis.opendocument.spreadsheet":
                "ods",
            "application/vnd.oasis.opendocument.presentation":
                "odp",
            "application/rtf": "rtf",
            "text/csv": "csv",
            "application/zip": "zip",
            "application/x-zip-compressed":
                "zip",
            "application/vnd.comicbook+zip":
                "cbz",
            "application/vnd.comicbook-rar":
                "cbr",
            "application/x-cbz": "cbz",
            "application/x-cbr": "cbr",
            "application/x-comicbook+zip":
                "cbz",
            "application/x-comicbook-rar":
                "cbr",
            "application/vnd.rar": "rar",
            "application/x-rar-compressed":
                "rar",
            "application/x-7z-compressed":
                "7z",
            "application/gzip": "gz",
            "application/x-gzip": "gz",
            "application/x-tar": "tar",
            "application/x-gtar": "tar",
            "application/x-gtar-compressed":
                "tgz",
            "application/tar+gzip": "tgz",
            "application/x-compressed-tar":
                "tgz",
            "application/x-bzip2": "bz2",
            "application/x-xz": "xz",
            "application/zstd": "zst",
            "application/x-zstd": "zst",
            "application/json": "json",
            "text/plain": "txt",
            "text/html": "html",
            "application/xhtml+xml":
                "xhtml"
        ]
        if let ext = exact[contentType] {
            return ext
        }
        if contentType.hasSuffix("+json") {
            return "json"
        }
        if contentType.hasSuffix("+zip") {
            return "zip"
        }
        if contentType.hasPrefix("text/") {
            return "txt"
        }
        return nil
    }

    private static func responseFilename(
        from response: HTTPURLResponse?
    ) -> String? {
        guard let response,
              let disposition =
                response
                .value(
                    forHTTPHeaderField:
                        "Content-Disposition"
                )?
                .trimmed,
              !disposition.isEmpty else {
            return nil
        }
        return contentDispositionFilename(
            from: disposition
        )
    }

    private static func contentDispositionFilename(
        from disposition: String
    ) -> String? {
        let parts =
            contentDispositionParts(
                disposition
            )
        var fallback: String?
        var continuations:
            [
                Int:
                    (
                        value: String,
                        encoded: Bool
                    )
            ] = [:]
        for rawPart in parts.dropFirst() {
            let part = rawPart.trimmed
            guard let separator =
                    part.firstIndex(of: "=") else {
                continue
            }
            let key =
                String(part[..<separator])
                .trimmed
                .lowercased()
            var value =
                String(
                    part[
                        part.index(
                            after: separator
                        )...
                    ]
                )
                .trimmed
            value =
                unquotedContentDispositionValue(
                    value
                )

            if key == "filename*" {
                if let decoded =
                        decodeRFC5987Filename(
                            value
                        ),
                   !decoded.isEmpty {
                    return filenameComponent(
                        decoded,
                        decodeLooseHeaderValue:
                            false
                    )
                }
            } else if key == "filename" {
                fallback =
                    filenameComponent(value)
            } else if let continuation =
                filenameContinuationKey(key) {
                continuations[
                    continuation.index
                ] = (
                    value,
                    continuation.encoded
                )
            }
        }
        if let continued =
            filenameContinuationValue(
                continuations
            ) {
            return continued
        }
        return fallback?.isEmpty == false
            ? fallback
            : nil
    }

    private static func filenameContinuationKey(
        _ key: String
    ) -> (
        index: Int,
        encoded: Bool
    )? {
        let prefix = "filename*"
        guard key.hasPrefix(prefix),
              key.count > prefix.count else {
            return nil
        }
        let suffixStart =
            key.index(
                key.startIndex,
                offsetBy: prefix.count
            )
        var suffix =
            String(key[suffixStart...])
        let encoded =
            suffix.hasSuffix("*")
        if encoded {
            suffix.removeLast()
        }
        guard let index = Int(suffix),
              index >= 0 else {
            return nil
        }
        return (index, encoded)
    }

    private static func filenameContinuationValue(
        _ continuations:
            [
                Int:
                    (
                        value: String,
                        encoded: Bool
                    )
            ]
    ) -> String? {
        guard !continuations.isEmpty,
              let first =
                continuations[0] else {
            return nil
        }

        var values = [first.value]
        var hasEncodedPart =
            first.encoded
        var index = 1
        while let part =
            continuations[index] {
            values.append(part.value)
            hasEncodedPart =
                hasEncodedPart ||
                part.encoded
            index += 1
        }

        let joined = values.joined()
        let decoded: String
        if hasEncodedPart {
            decoded =
                decodeRFC5987Filename(
                    joined
                ) ??
                joined.removingPercentEncoding ??
                joined
        } else {
            decoded = joined
        }

        let filename =
            filenameComponent(
                decoded,
                decodeLooseHeaderValue:
                    !hasEncodedPart
            )
        return filename.isEmpty
            ? nil
            : filename
    }

    private static func contentDispositionParts(
        _ disposition: String
    ) -> [String] {
        var parts: [String] = []
        var current = ""
        var inQuotes = false
        var escaped = false

        for character in disposition {
            if escaped {
                current.append(character)
                escaped = false
                continue
            }
            if character == "\\" &&
                inQuotes {
                current.append(character)
                escaped = true
                continue
            }
            if character == "\"" {
                inQuotes.toggle()
                current.append(character)
                continue
            }
            if character == ";",
               !inQuotes {
                parts.append(current)
                current.removeAll(
                    keepingCapacity: true
                )
                continue
            }
            current.append(character)
        }
        parts.append(current)
        return parts
    }

    private static func unquotedContentDispositionValue(
        _ value: String
    ) -> String {
        var text = value.trimmed
        if text.count >= 2,
           text.first == "\"",
           text.last == "\"" {
            text.removeFirst()
            text.removeLast()
            var output = ""
            var escaped = false
            for character in text {
                if escaped {
                    output.append(character)
                    escaped = false
                } else if character == "\\" {
                    escaped = true
                } else {
                    output.append(character)
                }
            }
            if escaped {
                output.append("\\")
            }
            return output
        }
        if text.count >= 2,
           text.first == "'",
           text.last == "'" {
            text.removeFirst()
            text.removeLast()
        }
        return text
    }

    private static func decodeRFC5987Filename(
        _ value: String
    ) -> String? {
        let pieces =
            value.split(
                separator: "'",
                maxSplits: 2,
                omittingEmptySubsequences:
                    false
            )
            .map(String.init)
        let charset =
            pieces.count == 3
            ? pieces[0]
            : "UTF-8"
        let encoded =
            pieces.count == 3
            ? pieces[2]
            : value
        guard let data =
                percentDecodedHeaderData(
                    encoded
                ),
              let stringEncoding =
                headerStringEncoding(
                    for: charset
                ),
              let decoded =
                String(
                    data: data,
                    encoding:
                        stringEncoding
                ) else {
            return encoded
                .removingPercentEncoding ??
                encoded
        }
        return decoded
    }

    private static func percentDecodedHeaderData(
        _ value: String
    ) -> Data? {
        let bytes = Array(value.utf8)
        var output = Data()
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == 37,
               index + 2 < bytes.count,
               let high =
                    hexValue(
                        bytes[index + 1]
                    ),
               let low =
                    hexValue(
                        bytes[index + 2]
                    ) {
                output.append(
                    high << 4 | low
                )
                index += 3
                continue
            }
            output.append(byte)
            index += 1
        }

        return output
    }

    private static func filenameComponent(
        _ value: String,
        decodeLooseHeaderValue: Bool = true
    ) -> String {
        let decoded =
            decodeLooseHeaderValue
            ? looseDecodedHeaderFilename(
                value
            )
            : value
        let normalized =
            decoded.replacingOccurrences(
                of: "\\",
                with: "/"
            )
        let last =
            normalized
            .split(
                separator: "/",
                omittingEmptySubsequences:
                    true
            )
            .last
            .map(String.init) ??
            normalized
        return last.trimmed
    }

    private static func looseDecodedHeaderFilename(
        _ value: String
    ) -> String {
        let percentDecoded =
            value.removingPercentEncoding ??
            value
        return decodeRFC2047EncodedWords(
            in: percentDecoded
        ) ?? percentDecoded
    }

    private static func decodeRFC2047EncodedWords(
        in value: String
    ) -> String? {
        guard value.contains("=?"),
              let regex =
                try? NSRegularExpression(
                    pattern:
                        #"=\?([^?]+)\?([bBqQ])\?([^?]*)\?="#
                ) else {
            return nil
        }
        let matches =
            regex.matches(
                in: value,
                range:
                    NSRange(
                        value.startIndex..<value.endIndex,
                        in: value
                    )
            )
        guard !matches.isEmpty else {
            return nil
        }

        var output = ""
        var cursor = value.startIndex
        var decodedAny = false
        var previousDecodedWord = false

        for match in matches {
            guard let fullRange =
                Range(
                    match.range(at: 0),
                    in: value
                ) else {
                continue
            }
            let separator =
                value[cursor..<fullRange.lowerBound]
            let original =
                String(value[fullRange])
            if let charsetRange =
                    Range(
                        match.range(at: 1),
                        in: value
                    ),
               let encodingRange =
                    Range(
                        match.range(at: 2),
                        in: value
                    ),
               let payloadRange =
                    Range(
                        match.range(at: 3),
                        in: value
                    ),
               let decoded =
                    decodeRFC2047Word(
                        charset:
                            String(
                                value[
                                    charsetRange
                                ]
                            ),
                        encoding:
                            String(
                                value[
                                    encodingRange
                                ]
                            ),
                        payload:
                            String(
                                value[
                                    payloadRange
                                ]
                            )
                    ) {
                if !(
                    previousDecodedWord &&
                    isRFC2047LinearWhitespace(
                        separator
                    )
                ) {
                    output +=
                        String(separator)
                }
                output += decoded
                decodedAny = true
                previousDecodedWord = true
            } else {
                output += String(separator)
                output += original
                previousDecodedWord = false
            }
            cursor = fullRange.upperBound
        }

        output += String(value[cursor...])
        return decodedAny ? output : nil
    }

    private static func isRFC2047LinearWhitespace(
        _ value: Substring
    ) -> Bool {
        value.allSatisfy { character in
            character == " " ||
                character == "\t" ||
                character == "\r" ||
                character == "\n"
        }
    }

    private static func decodeRFC2047Word(
        charset: String,
        encoding: String,
        payload: String
    ) -> String? {
        let data: Data?
        if encoding.caseInsensitiveCompare(
            "B"
        ) == .orderedSame {
            data = Data(
                base64Encoded: payload
            )
        } else if encoding
            .caseInsensitiveCompare(
                "Q"
            ) == .orderedSame {
            data =
                decodeRFC2047QPayload(
                    payload
                )
        } else {
            data = nil
        }
        guard let data else {
            return nil
        }

        let normalizedCharset =
            charset
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .lowercased()
            .replacingOccurrences(
                of: "_",
                with: "-"
            )
        guard let stringEncoding =
            headerStringEncoding(
                forNormalizedCharset:
                    normalizedCharset
            ) else {
            return nil
        }
        return String(
            data: data,
            encoding: stringEncoding
        )
    }

    private static func headerStringEncoding(
        for charset: String
    ) -> String.Encoding? {
        let normalizedCharset =
            charset
            .trimmingCharacters(
                in:
                    .whitespacesAndNewlines
            )
            .lowercased()
            .replacingOccurrences(
                of: "_",
                with: "-"
            )
        return headerStringEncoding(
            forNormalizedCharset:
                normalizedCharset
        )
    }

    private static func headerStringEncoding(
        forNormalizedCharset
            normalizedCharset: String
    ) -> String.Encoding? {
        switch normalizedCharset {
        case "utf-8", "utf8":
            return .utf8
        case "us-ascii", "ascii":
            return .ascii
        case "iso-8859-1",
             "latin-1",
             "latin1":
            return .isoLatin1
        case "windows-1252", "cp1252":
            return .windowsCP1252
        case "shift-jis",
             "sjis",
             "shiftjis",
             "windows-31j",
             "cp932",
             "ms932":
            return .shiftJIS
        case "euc-jp", "eucjp":
            return coreFoundationHeaderStringEncoding(
                CFStringEncoding(
                    CFStringEncodings
                        .EUC_JP
                        .rawValue
                )
            )
        case "euc-kr",
             "euckr",
             "ks-c-5601-1987",
             "ks-c5601",
             "ksc5601":
            return coreFoundationHeaderStringEncoding(
                CFStringEncoding(
                    CFStringEncodings
                        .EUC_KR
                        .rawValue
                )
            )
        case "cp949",
             "ms949",
             "windows-949",
             "uhc":
            return coreFoundationHeaderStringEncoding(
                CFStringEncoding(0x0422)
            )
        default:
            return nil
        }
    }

    private static func coreFoundationHeaderStringEncoding(
        _ encoding: CFStringEncoding
    ) -> String.Encoding {
        String.Encoding(
            rawValue:
                CFStringConvertEncodingToNSStringEncoding(
                    encoding
                )
        )
    }

    private static func decodeRFC2047QPayload(
        _ payload: String
    ) -> Data {
        let bytes = Array(payload.utf8)
        var output = Data()
        var index = 0

        while index < bytes.count {
            let byte = bytes[index]
            if byte == 95 {
                output.append(32)
                index += 1
                continue
            }
            if byte == 61,
               index + 2 < bytes.count,
               let high =
                    hexValue(
                        bytes[index + 1]
                    ),
               let low =
                    hexValue(
                        bytes[index + 2]
                    ) {
                output.append(
                    high << 4 | low
                )
                index += 3
                continue
            }
            output.append(byte)
            index += 1
        }

        return output
    }

    private static func hexValue(
        _ byte: UInt8
    ) -> UInt8? {
        switch byte {
        case 48...57:
            return byte - 48
        case 65...70:
            return byte - 55
        case 97...102:
            return byte - 87
        default:
            return nil
        }
    }

    private static func queryFilenameHint(
        from url: URL
    ) -> String? {
        let items =
            URLComponents(
                url: url,
                resolvingAgainstBaseURL:
                    false
            )?
            .queryItems ?? []
        for key in [
            "response-content-disposition",
            "content-disposition",
            "content_disposition"
        ] {
            guard let value =
                    items
                    .first(
                        where: {
                            $0.name
                                .lowercased() ==
                                key
                        }
                    )?
                    .value?
                    .trimmed,
                  !value.isEmpty,
                  let filename =
                    contentDispositionFilename(
                        from: value
                    ),
                  !filename.isEmpty else {
                continue
            }
            return filename
        }

        for key in [
            "filename",
            "file",
            "download",
            "name",
            "title",
            "fn"
        ] {
            guard let value =
                    items
                    .first(
                        where: {
                            $0.name
                                .lowercased() ==
                                key
                        }
                    )?
                    .value?
                    .trimmed,
                  !value.isEmpty else {
                continue
            }

            let clean =
                queryFilenameCandidate(
                    from: value
                )
            if !clean.isEmpty {
                return clean
            }
        }
        return nil
    }

    private static func queryFilenameCandidate(
        from value: String
    ) -> String {
        let normalizedValue =
            value.replacingOccurrences(
                of: "\\",
                with: "/"
            )
        let candidate: String
        if let nested =
                URL(string: normalizedValue),
           nested.scheme != nil,
           !nested.lastPathComponent
            .trimmed
            .isEmpty {
            candidate =
                nested.lastPathComponent
        } else if normalizedValue
            .contains("/") {
            candidate =
                normalizedValue
                .split(
                    separator: "/",
                    omittingEmptySubsequences:
                        true
                )
                .last
                .map(String.init) ??
                normalizedValue
        } else {
            candidate = normalizedValue
        }

        return candidate
            .split(
                separator: "?",
                maxSplits: 1,
                omittingEmptySubsequences:
                    true
            )
            .first
            .map(String.init)?
            .split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences:
                    true
            )
            .first
            .map(String.init)?
            .trimmed ?? ""
    }
}
