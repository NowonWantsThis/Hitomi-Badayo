import AppKit
import Combine
import Foundation
import ImageIO

@MainActor
final class QueueThumbnailLoader: ObservableObject {
    @Published private(set) var image: NSImage?

    private var identity = ""

    func load(job: DownloadJob, destinationPath: String) async {
        let requestedIdentity = QueueThumbnailProvider.cacheIdentity(
            for: job,
            destinationPath: destinationPath
        )
        if identity != requestedIdentity {
            image = nil
        }
        identity = requestedIdentity
        let loaded = await QueueThumbnailProvider.image(
            for: job,
            destinationPath: destinationPath
        )
        guard !Task.isCancelled, identity == requestedIdentity else { return }
        image = loaded
    }
}

actor QueueThumbnailWorkCoordinator {
    private struct Waiter {
        let id: UUID
        let continuation: CheckedContinuation<Bool, Never>
    }

    static let realtime = QueueThumbnailWorkCoordinator(limit: 8)

    private var available: Int
    private var waiters: [Waiter] = []
    private var activeIDs: Set<UUID> = []
    private var preCancelledIDs: Set<UUID> = []

    init(limit: Int) {
        available = max(1, limit)
    }

    nonisolated func perform<T: Sendable>(
        _ operation: @escaping @Sendable () async -> T
    ) async -> T? {
        let id = UUID()
        let admitted = await withTaskCancellationHandler {
            await acquire(id)
        } onCancel: {
            Task { await self.cancel(id) }
        }
        guard admitted else { return nil }
        guard !Task.isCancelled else {
            await release(id)
            return nil
        }

        let result = await operation()
        await release(id)
        return result
    }

    private func acquire(_ id: UUID) async -> Bool {
        if Task.isCancelled || preCancelledIDs.remove(id) != nil {
            return false
        }
        if available > 0 {
            available -= 1
            activeIDs.insert(id)
            return true
        }
        return await withCheckedContinuation { continuation in
            if preCancelledIDs.remove(id) != nil {
                continuation.resume(returning: false)
            } else {
                waiters.append(Waiter(id: id, continuation: continuation))
            }
        }
    }

    private func cancel(_ id: UUID) {
        if let index = waiters.firstIndex(where: { $0.id == id }) {
            let waiter = waiters.remove(at: index)
            waiter.continuation.resume(returning: false)
        } else if !activeIDs.contains(id) {
            preCancelledIDs.insert(id)
        }
    }

    private func release(_ id: UUID) {
        guard activeIDs.remove(id) != nil else { return }
        while !waiters.isEmpty {
            let waiter = waiters.removeFirst()
            if preCancelledIDs.remove(waiter.id) != nil {
                waiter.continuation.resume(returning: false)
                continue
            }
            activeIDs.insert(waiter.id)
            waiter.continuation.resume(returning: true)
            return
        }
        available += 1
    }

#if TESTING
    func testingCounts() -> (active: Int, pending: Int) {
        (activeIDs.count, waiters.count)
    }
#endif
}

enum QueueThumbnailProvider {
    static let customThumbnailMetadataKey = "custom_thumbnail_path"

    private enum LocalCandidate {
        case imageData(Data)
        case video(URL)
    }

    private struct RemoteRequest {
        var url: URL
        var referer: String?
        var userAgent: String?
    }

    private final class RelocationIndexEntry: NSObject {
        let createdAt: Date
        let pathsByName: [String: [String]]

        init(createdAt: Date, pathsByName: [String: [String]]) {
            self.createdAt = createdAt
            self.pathsByName = pathsByName
        }
    }

    private final class RelocationMissEntry: NSObject {
        let createdAt: Date

        init(createdAt: Date) {
            self.createdAt = createdAt
        }
    }

    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "gif", "webp", "avif", "bmp",
        "tif", "tiff", "heic", "heif"
    ]
    private static let archiveExtensions: Set<String> = ["zip", "cbz"]
    private static let recoverableArchiveExtensions = ["zip", "cbz", "rar", "7z"]
    private static let remoteMetadataKeys = [
        "thumbnail", "thumbnail_url", "thumb", "cover", "cover_url", "poster"
    ]
    private static let cache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 256
        cache.totalCostLimit = 96 * 1_024 * 1_024
        return cache
    }()
    private static let relocationIndexCache: NSCache<NSString, RelocationIndexEntry> = {
        let cache = NSCache<NSString, RelocationIndexEntry>()
        cache.countLimit = 8
        return cache
    }()
    private static let relocationIndexLock = NSLock()
    private static let relocationMissCache: NSCache<NSString, RelocationMissEntry> = {
        let cache = NSCache<NSString, RelocationMissEntry>()
        cache.countLimit = 512
        return cache
    }()

    static func cacheIdentity(for job: DownloadJob, destinationPath: String) -> String {
        let remote = remoteMetadataKeys.compactMap { job.metadata[$0]?.trimmed }.first ?? ""
        let custom = job.metadata[customThumbnailMetadataKey]?.trimmed ?? ""
        return [
            job.id.uuidString,
            job.outputPath,
            destinationPath,
            job.status.rawValue,
            job.completed > 0 ? "has-output" : "no-output",
            custom,
            remote
        ].joined(separator: "|")
    }

    static func image(
        for job: DownloadJob,
        destinationPath: String,
        includeCustomOverride: Bool = true
    ) async -> NSImage? {
        let identity = cacheIdentity(for: job, destinationPath: destinationPath)
        if includeCustomOverride,
           let cached = cache.object(forKey: identity as NSString) {
            return cached
        }

        guard let scheduled = await QueueThumbnailWorkCoordinator.realtime.perform({
            await loadImage(
                for: job,
                destinationPath: destinationPath,
                includeCustomOverride: includeCustomOverride,
                identity: identity
            )
        }) else {
            return nil
        }
        return scheduled
    }

    private static func loadImage(
        for job: DownloadJob,
        destinationPath: String,
        includeCustomOverride: Bool,
        identity: String
    ) async -> NSImage? {
        guard !Task.isCancelled else { return nil }
        if includeCustomOverride,
           let cached = cache.object(forKey: identity as NSString) {
            return cached
        }

        if includeCustomOverride,
           let customURL = customThumbnailURL(for: job),
           let data = await detachedUtilityValue({
               try? Data(contentsOf: customURL, options: [.mappedIfSafe])
           }),
           !Task.isCancelled,
           let image = thumbnailImage(from: data) {
            cache.setObject(image, forKey: identity as NSString, cost: imageCost(image))
            return image
        }

        let outputPath = job.outputPath
        let resolvedFilenames = job.resolvedFilenames
        let local = await detachedUtilityValue {
            localCandidate(
                forOutputPath: outputPath,
                destinationPath: destinationPath,
                preferredFilenames: resolvedFilenames
            )
        }

        if !Task.isCancelled, let local, let image = await image(from: local) {
            cache.setObject(image, forKey: identity as NSString, cost: imageCost(image))
            return image
        }

        guard !Task.isCancelled else { return nil }
        guard let request = remoteRequest(for: job) else { return nil }
        do {
            let data = try await HTTPClient.shared.data(
                from: request.url,
                referer: request.referer,
                userAgent: request.userAgent
            )
            guard !Task.isCancelled, let image = thumbnailImage(from: data) else { return nil }
            cache.setObject(image, forKey: identity as NSString, cost: imageCost(image))
            return image
        } catch {
            return nil
        }
    }

    private static func detachedUtilityValue<T: Sendable>(
        _ operation: @escaping @Sendable () -> T
    ) async -> T {
        let task = Task.detached(priority: .utility, operation: operation)
        return await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    static func customThumbnailURL(for job: DownloadJob) -> URL? {
        guard let raw = job.metadata[customThumbnailMetadataKey]?.trimmed,
              !raw.isEmpty else {
            return nil
        }
        if let url = URL(string: raw), url.isFileURL {
            return url.standardizedFileURL
        }
        return URL(
            fileURLWithPath: (raw as NSString).expandingTildeInPath
        ).standardizedFileURL
    }

    static func metadataByAddingThumbnail(
        _ metadata: [String: String],
        assets: [ResolvedAsset]
    ) -> [String: String] {
        var updated = metadata
        let existingThumbnail = remoteMetadataKeys
            .compactMap { updated[$0]?.trimmed }
            .first { !$0.isEmpty }

        let supportingAsset = assets.first { asset in
            if let existingThumbnail {
                return asset.remoteURL.absoluteString == existingThumbnail ||
                    remoteMetadataKeys.contains { asset.metadata[$0]?.trimmed == existingThumbnail }
            }
            return thumbnailURLString(for: asset) != nil
        }

        if existingThumbnail == nil,
           let supportingAsset,
           let thumbnail = thumbnailURLString(for: supportingAsset) {
            updated["thumbnail"] = thumbnail
        }
        let disablesThumbnailReferer = updated["thumbnail_referer_disabled"]?.trimmed.lowercased() == "true"
        if !disablesThumbnailReferer,
           updated["thumbnail_referer"]?.trimmed.isEmpty != false,
           let referer = supportingAsset?.referer?.trimmed,
           !referer.isEmpty {
            updated["thumbnail_referer"] = referer
        }
        if updated["thumbnail_user_agent"]?.trimmed.isEmpty != false,
           let userAgent = supportingAsset?.userAgent?.trimmed,
           !userAgent.isEmpty {
            updated["thumbnail_user_agent"] = userAgent
        }
        return DownloadMetadata.clean(updated)
    }

    static func existingOutputURL(
        forOutputPath outputPath: String,
        destinationPath: String,
        searchRelocatedOutputs: Bool = true,
        fileManager: FileManager = .default
    ) -> URL? {
        guard !Task.isCancelled else { return nil }
        let value = outputPath.trimmed
        guard !value.isEmpty else { return nil }

        let original = URL(fileURLWithPath: (value as NSString).expandingTildeInPath)
        var candidates = [original]
        let destination = destinationPath.trimmed
        if !destination.isEmpty, !original.lastPathComponent.isEmpty {
            let destinationURL = URL(
                fileURLWithPath: (destination as NSString).expandingTildeInPath,
                isDirectory: true
            )

            func appendCandidate(_ candidate: URL) {
                let standardized = candidate.standardizedFileURL
                guard !candidates.contains(where: { $0.standardizedFileURL == standardized }) else {
                    return
                }
                candidates.append(candidate)
            }

            appendCandidate(destinationURL.appendingPathComponent(original.lastPathComponent))

            let originalParentName = original.deletingLastPathComponent().lastPathComponent
            if !originalParentName.isEmpty, originalParentName != "/" {
                appendCandidate(
                    destinationURL
                        .appendingPathComponent(originalParentName, isDirectory: true)
                        .appendingPathComponent(original.lastPathComponent)
                )
            }
        }

        for candidate in candidates {
            guard !Task.isCancelled else { return nil }
            if let existing = existingOutputVariant(for: candidate, fileManager: fileManager) {
                return existing
            }
        }

        guard searchRelocatedOutputs, !destination.isEmpty else { return nil }
        let destinationURL = URL(
            fileURLWithPath: (destination as NSString).expandingTildeInPath,
            isDirectory: true
        )
        return relocatedOutputURL(
            matching: original,
            under: destinationURL,
            fileManager: fileManager
        )
    }

    private static func existingOutputVariant(
        for candidate: URL,
        fileManager: FileManager
    ) -> URL? {
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        if recoverableArchiveExtensions.contains(candidate.pathExtension.lowercased()) {
            let folder = candidate.deletingPathExtension()
            return fileManager.fileExists(atPath: folder.path) ? folder : nil
        }

        for ext in recoverableArchiveExtensions {
            let archive = candidate.appendingPathExtension(ext)
            if fileManager.fileExists(atPath: archive.path) {
                return archive
            }
        }
        return nil
    }

    private static func relocatedOutputURL(
        matching original: URL,
        under destination: URL,
        fileManager: FileManager
    ) -> URL? {
        guard !Task.isCancelled else { return nil }
        var destinationIsDirectory = ObjCBool(false)
        guard fileManager.fileExists(
            atPath: destination.path,
            isDirectory: &destinationIsDirectory
        ), destinationIsDirectory.boolValue else {
            return nil
        }

        let originalName = original.lastPathComponent
        guard !originalName.isEmpty else { return nil }

        var expectedNames = [originalName]
        if recoverableArchiveExtensions.contains(original.pathExtension.lowercased()) {
            expectedNames.append(original.deletingPathExtension().lastPathComponent)
        } else {
            expectedNames.append(contentsOf: recoverableArchiveExtensions.map {
                "\(originalName).\($0)"
            })
        }
        let priorities = Dictionary(uniqueKeysWithValues: expectedNames.enumerated().map {
            (normalizedOutputName($0.element), $0.offset)
        })

        let resolvedDestination = destination
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let index = relocationIndex(
            under: resolvedDestination,
            fileManager: fileManager
        )
        if let match = relocatedMatch(
            in: index,
            priorities: priorities,
            fileManager: fileManager
        ) {
            return match
        }

        guard !Task.isCancelled else { return nil }
        let missKey = "\(resolvedDestination.path)\u{0}\(original.standardizedFileURL.path)" as NSString
        if let miss = relocationMissCache.object(forKey: missKey),
           Date().timeIntervalSince(miss.createdAt) < 2 {
            return nil
        }
        let refreshedIndex = relocationIndex(
            under: resolvedDestination,
            fileManager: fileManager,
            forceRefresh: true
        )
        if let match = relocatedMatch(
            in: refreshedIndex,
            priorities: priorities,
            fileManager: fileManager
        ) {
            relocationMissCache.removeObject(forKey: missKey)
            return match
        }
        relocationMissCache.setObject(RelocationMissEntry(createdAt: Date()), forKey: missKey)
        return nil
    }

    private static func relocatedMatch(
        in index: RelocationIndexEntry,
        priorities: [String: Int],
        fileManager: FileManager
    ) -> URL? {
        var matches: [(priority: Int, url: URL)] = []
        for (name, priority) in priorities {
            for path in index.pathsByName[name] ?? [] where fileManager.fileExists(atPath: path) {
                let url = URL(fileURLWithPath: path)
                matches.append((priority, url))
            }
        }
        return matches.sorted(by: {
            if $0.priority != $1.priority {
                return $0.priority < $1.priority
            }
            return $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending
        }).first?.url
    }

    private static func relocationIndex(
        under resolvedDestination: URL,
        fileManager: FileManager,
        forceRefresh: Bool = false
    ) -> RelocationIndexEntry {
        relocationIndexLock.lock()
        defer { relocationIndexLock.unlock() }

        let cacheKey = resolvedDestination.path as NSString
        let now = Date()
        if let cached = relocationIndexCache.object(forKey: cacheKey) {
            let age = now.timeIntervalSince(cached.createdAt)
            if (!forceRefresh && age < 10) || (forceRefresh && age < 2) {
                return cached
            }
        }

        let rootPath = resolvedDestination.path
        guard let enumerator = fileManager.enumerator(atPath: rootPath) else {
            return RelocationIndexEntry(createdAt: now, pathsByName: [:])
        }
        var pathsByName: [String: [String]] = [:]

        while let relativePath = enumerator.nextObject() as? String {
            guard !Task.isCancelled else {
                return RelocationIndexEntry(createdAt: now, pathsByName: [:])
            }
            let name = (relativePath as NSString).lastPathComponent
            guard !name.isEmpty, !name.hasPrefix(".") else {
                enumerator.skipDescendants()
                continue
            }

            let depth = relativePath.reduce(into: 1) { count, character in
                if character == "/" { count += 1 }
            }
            guard depth <= 5 else {
                enumerator.skipDescendants()
                continue
            }
            if depth == 5 {
                enumerator.skipDescendants()
            }

            let path = (rootPath as NSString).appendingPathComponent(relativePath)
            pathsByName[normalizedOutputName(name), default: []].append(path)
        }

        let entry = RelocationIndexEntry(createdAt: Date(), pathsByName: pathsByName)
        relocationIndexCache.setObject(entry, forKey: cacheKey)
        return entry
    }

    private static func normalizedOutputName(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
    }

    private static func localCandidate(
        forOutputPath outputPath: String,
        destinationPath: String,
        preferredFilenames: [String] = [],
        fileManager: FileManager = .default
    ) -> LocalCandidate? {
        guard !Task.isCancelled else { return nil }
        guard let output = existingOutputURL(
            forOutputPath: outputPath,
            destinationPath: destinationPath,
            searchRelocatedOutputs: false,
            fileManager: fileManager
        ) else {
            return nil
        }

        var isDirectory = ObjCBool(false)
        guard fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) else {
            return nil
        }
        if !isDirectory.boolValue {
            return localFileCandidate(output)
        }

        let standardizedOutput = output.resolvingSymlinksInPath().standardizedFileURL
        let outputPrefix = standardizedOutput.path.hasSuffix("/")
            ? standardizedOutput.path
            : standardizedOutput.path + "/"
        for filename in preferredFilenames {
            guard !Task.isCancelled else { return nil }
            let relativePath = filename.trimmed
            guard !relativePath.isEmpty else { continue }
            let candidate = standardizedOutput
                .appendingPathComponent(relativePath)
                .resolvingSymlinksInPath()
                .standardizedFileURL
            guard candidate.path.hasPrefix(outputPrefix),
                  let local = localFileCandidate(candidate) else {
                continue
            }
            return local
        }

        guard let enumerator = fileManager.enumerator(atPath: output.path) else {
            return nil
        }

        while let relativePath = enumerator.nextObject() as? String {
            guard !Task.isCancelled else { return nil }
            let name = (relativePath as NSString).lastPathComponent
            guard !name.isEmpty, !name.hasPrefix(".") else {
                enumerator.skipDescendants()
                continue
            }
            let fileType = enumerator.fileAttributes?[.type] as? FileAttributeType
            if fileType == .typeSymbolicLink {
                enumerator.skipDescendants()
                continue
            }
            guard fileType == .typeRegular else {
                continue
            }
            let candidate = URL(
                fileURLWithPath: (output.path as NSString).appendingPathComponent(relativePath)
            )
            if let local = localFileCandidate(candidate) {
                return local
            }
        }
        return nil
    }

    private static func localFileCandidate(_ file: URL) -> LocalCandidate? {
        let ext = file.pathExtension.lowercased()
        if imageExtensions.contains(ext),
           let data = try? Data(contentsOf: file, options: [.mappedIfSafe]) {
            return .imageData(data)
        }
        if MediaFileMetadataReader.supportedThumbnailExtensions.contains(ext) {
            return .video(file)
        }
        if archiveExtensions.contains(ext),
           let entries = try? ZipArchiveReader.entries(in: file),
           let first = entries
            .filter({ imageExtensions.contains(URL(fileURLWithPath: $0.name).pathExtension.lowercased()) })
            .sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
            .first,
           let data = try? ZipArchiveReader.data(for: first, in: file) {
            return .imageData(data)
        }
        return nil
    }

    private static func image(from candidate: LocalCandidate) async -> NSImage? {
        switch candidate {
        case .imageData(let data):
            return thumbnailImage(from: data)
        case .video(let url):
            guard let data = await MediaFileMetadataReader.thumbnailJPEGData(
                for: url,
                maxPixelSize: 320
            ) else {
                return nil
            }
            return thumbnailImage(from: data)
        }
    }

    private static func remoteRequest(for job: DownloadJob) -> RemoteRequest? {
        for key in remoteMetadataKeys {
            guard let raw = job.metadata[key]?.trimmed,
                  let url = URL(string: raw),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }
            let referer = job.metadata["thumbnail_referer_disabled"]?.trimmed.lowercased() == "true"
                ? nil
                : firstMetadataValue(
                    job.metadata,
                    keys: ["thumbnail_referer", "referer", "page_url"]
                )
            let userAgent = firstMetadataValue(
                job.metadata,
                keys: ["thumbnail_user_agent", "user_agent", "user-agent"]
            )
            return RemoteRequest(url: url, referer: referer, userAgent: userAgent)
        }
        return nil
    }

    private static func thumbnailURLString(for asset: ResolvedAsset) -> String? {
        for key in remoteMetadataKeys {
            if let value = asset.metadata[key]?.trimmed,
               let url = URL(string: value),
               let scheme = url.scheme?.lowercased(),
               scheme == "http" || scheme == "https" {
                return url.absoluteString
            }
        }

        let type = (asset.metadata["media_type"] ?? asset.metadata["type"] ?? "").lowercased()
        let ext = asset.remoteURL.pathExtension.lowercased()
        guard type.contains("image") || imageExtensions.contains(ext) else { return nil }
        return asset.remoteURL.absoluteString
    }

    private static func thumbnailImage(from data: Data) -> NSImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 320,
            kCGImageSourceShouldCacheImmediately: true
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    private static func imageCost(_ image: NSImage) -> Int {
        let pixels = max(1, Int(image.size.width * image.size.height))
        return min(Int.max / 4, pixels * 4)
    }

    private static func firstMetadataValue(
        _ metadata: [String: String],
        keys: [String]
    ) -> String? {
        keys.compactMap { metadata[$0]?.trimmed }.first { !$0.isEmpty }
    }

}
