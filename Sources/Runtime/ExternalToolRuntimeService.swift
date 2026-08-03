import Foundation

enum ExternalToolRuntimeKind: CaseIterable, Hashable {
    case aria2
    case ffmpeg
    case ytdlp
}

final class ExternalToolRuntimeService {
    let ytdlpBridge: YTDLPBridge
    let ffmpegBridge: FFmpegBridge
    let ffmpegExecutionService: FFmpegExecutionService
    let aria2Bridge: Aria2Bridge
    let customCommandBridge: CustomCommandBridge
    @MainActor let browserDPIBypassService: BrowserDPIBypassService

    private let aria2RPCSessionFactory: () -> Aria2RPCSession?
    private let lock = NSLock()
    private var processControls: [ExternalToolRuntimeKind: [UUID: ExternalProcessControl]] = [:]
    private var aria2RPCSessions: [UUID: Aria2RPCSession] = [:]

    @MainActor
    init(
        ytdlpBridge: YTDLPBridge = YTDLPBridge(),
        ffmpegBridge: FFmpegBridge = FFmpegBridge(),
        ffmpegExecutionService: FFmpegExecutionService? = nil,
        aria2Bridge: Aria2Bridge = Aria2Bridge(),
        customCommandBridge: CustomCommandBridge = CustomCommandBridge(),
        browserDPIBypassService: BrowserDPIBypassService? = nil,
        aria2RPCSessionFactory: @escaping () -> Aria2RPCSession? = {
            Aria2RPCSession.make()
        }
    ) {
        self.ytdlpBridge = ytdlpBridge
        self.ffmpegBridge = ffmpegBridge
        self.ffmpegExecutionService = ffmpegExecutionService
            ?? FFmpegExecutionService(bridge: ffmpegBridge)
        self.aria2Bridge = aria2Bridge
        self.customCommandBridge = customCommandBridge
        self.browserDPIBypassService = browserDPIBypassService ?? BrowserDPIBypassService()
        self.aria2RPCSessionFactory = aria2RPCSessionFactory
    }

    @MainActor
    func withProcessExecution<Result>(
        for jobID: UUID,
        kind: ExternalToolRuntimeKind,
        operation: (ExternalProcessControl) async throws -> Result
    ) async rethrows -> Result {
        let processControl = ExternalProcessControl()
        registerProcessControl(processControl, for: jobID, kind: kind)
        defer {
            removeProcessControl(for: jobID, kind: kind)
        }
        return try await operation(processControl)
    }

    @MainActor
    func withAria2Execution<Result>(
        for jobID: UUID,
        operation: (ExternalProcessControl, Aria2RPCSession?) async throws -> Result
    ) async rethrows -> Result {
        let processControl = ExternalProcessControl()
        let rpcSession = aria2RPCSessionFactory()
        registerProcessControl(processControl, for: jobID, kind: .aria2)
        if let rpcSession {
            registerAria2RPCSession(rpcSession, for: jobID)
        }
        defer {
            removeAria2RuntimeState(for: jobID)
        }
        return try await operation(processControl, rpcSession)
    }

    func executeYTDLPDownload(
        url: URL,
        root: URL,
        headers: HTTPRequestOptions,
        youtubePreferredLanguage: String,
        youtubePreferredResolution: String,
        youtubePreferredAudioLanguage: String,
        soopPreferredResolution: String,
        extractAudioFormat: String?,
        writeYouTubeThumbnail: Bool,
        reverseYouTubePlaylist: Bool,
        numberPlaylistFiles: Bool,
        writeYouTubeAutoSubtitles: Bool,
        youtubeSubtitleLanguages: String,
        embedYouTubeChapters: Bool,
        youtubeVideoCodecSort: String,
        preferYouTubeEnhancedBitrate: Bool,
        useYouTubeUploadDateForFileModificationTime: Bool,
        processControl: ExternalProcessControl,
        progressHandler: (@Sendable (YTDLPRuntimeUpdate) -> Void)?
    ) async throws -> YTDLPResult {
        try await ytdlpBridge.download(
            url: url,
            to: root,
            headers: headers,
            youtubePreferredLanguage: youtubePreferredLanguage,
            youtubePreferredResolution: youtubePreferredResolution,
            youtubePreferredAudioLanguage: youtubePreferredAudioLanguage,
            soopPreferredResolution: soopPreferredResolution,
            extractAudioFormat: extractAudioFormat,
            writeYouTubeThumbnail: writeYouTubeThumbnail,
            reverseYouTubePlaylist: reverseYouTubePlaylist,
            numberPlaylistFiles: numberPlaylistFiles,
            writeYouTubeAutoSubtitles: writeYouTubeAutoSubtitles,
            youtubeSubtitleLanguages: youtubeSubtitleLanguages,
            embedYouTubeChapters: embedYouTubeChapters,
            youtubeVideoCodecSort: youtubeVideoCodecSort,
            preferYouTubeEnhancedBitrate: preferYouTubeEnhancedBitrate,
            useYouTubeUploadDateForFileModificationTime: useYouTubeUploadDateForFileModificationTime,
            processControl: processControl,
            progressHandler: progressHandler
        )
    }

    func executeFFmpegMux(
        video: URL,
        audio: URL,
        output: URL,
        options: FFmpegTranscodeOptions
    ) async throws {
        try await ffmpegExecutionService.execute(
            .mux(
                video: video,
                audio: audio,
                output: output,
                options: options
            )
        )
    }

    func executeFFmpegRemux(
        input: URL,
        output: URL,
        options: FFmpegTranscodeOptions
    ) async throws {
        try await ffmpegExecutionService.execute(
            .remux(
                input: input,
                output: output,
                options: options
            )
        )
    }

    func executeFFmpegLiveRecording(
        videoPlaylist: URL,
        audioPlaylist: URL?,
        output: URL,
        headers: [String: String],
        options: FFmpegTranscodeOptions,
        processControl: ExternalProcessControl
    ) async throws {
        try await ffmpegExecutionService.execute(
            .liveRecording(
                videoPlaylist: videoPlaylist,
                audioPlaylist: audioPlaylist,
                output: output,
                headers: headers,
                options: options,
                processControl: processControl
            )
        )
    }

    func executeCustomCommand(
        url: URL,
        rule: SiteRule,
        root: URL,
        headers: HTTPRequestOptions
    ) async throws -> CustomCommandResult {
        try await customCommandBridge.run(
            url: url,
            rule: rule,
            root: root,
            headers: headers
        )
    }

    func executeAria2Download(
        url: URL,
        root: URL,
        headers: HTTPRequestOptions,
        options: Aria2Options,
        processControl: ExternalProcessControl,
        rpcSession: Aria2RPCSession?
    ) async throws -> Aria2Result {
        try await aria2Bridge.download(
            url: url,
            to: root,
            headers: headers,
            options: options,
            processControl: processControl,
            rpcSession: rpcSession
        )
    }

    func executeAria2FileList(
        url: URL,
        headers: HTTPRequestOptions
    ) async throws -> [Aria2FileEntry] {
        try await aria2Bridge.listFiles(url: url, headers: headers)
    }

    func registerProcessControl(
        _ control: ExternalProcessControl,
        for jobID: UUID,
        kind: ExternalToolRuntimeKind
    ) {
        lock.lock()
        processControls[kind, default: [:]][jobID] = control
        lock.unlock()
    }

    func processControl(
        for jobID: UUID,
        kind: ExternalToolRuntimeKind
    ) -> ExternalProcessControl? {
        lock.lock()
        defer { lock.unlock() }
        return processControls[kind]?[jobID]
    }

    func processIsRunning(
        for jobID: UUID,
        kind: ExternalToolRuntimeKind
    ) -> Bool {
        processControl(for: jobID, kind: kind)?.isRunning == true
    }

    @discardableResult
    func removeProcessControl(
        for jobID: UUID,
        kind: ExternalToolRuntimeKind
    ) -> ExternalProcessControl? {
        lock.lock()
        defer { lock.unlock() }
        return processControls[kind]?.removeValue(forKey: jobID)
    }

    @discardableResult
    func terminateProcesses(for jobID: UUID) -> Int {
        let controls = ExternalToolRuntimeKind.allCases.compactMap {
            processControl(for: jobID, kind: $0)
        }
        controls.forEach { $0.terminate() }
        return controls.count
    }

    @discardableResult
    func terminateAllProcesses(clearState: Bool = false) -> Int {
        lock.lock()
        let controls = processControls.values.flatMap(\.values)
        if clearState {
            processControls.removeAll()
            aria2RPCSessions.removeAll()
        }
        lock.unlock()
        controls.forEach { $0.terminate() }
        return controls.count
    }

    @discardableResult
    func interruptProcess(
        for jobID: UUID,
        kind: ExternalToolRuntimeKind,
        gracePeriod: TimeInterval = 10
    ) -> Bool {
        processControl(for: jobID, kind: kind)?.interrupt(gracePeriod: gracePeriod) ?? false
    }

    func registerAria2RPCSession(_ session: Aria2RPCSession, for jobID: UUID) {
        lock.lock()
        aria2RPCSessions[jobID] = session
        lock.unlock()
    }

    func aria2RPCSession(for jobID: UUID) -> Aria2RPCSession? {
        lock.lock()
        defer { lock.unlock() }
        return aria2RPCSessions[jobID]
    }

    func removeAria2RuntimeState(for jobID: UUID) {
        lock.lock()
        processControls[.aria2]?.removeValue(forKey: jobID)
        aria2RPCSessions.removeValue(forKey: jobID)
        lock.unlock()
    }

    func pauseAllProcessesForQueue() {
        ExternalProcessRunner.pauseAllForQueue()
    }

    func resumeAllProcessesForQueue() {
        ExternalProcessRunner.resumeAllForQueue()
    }

    @MainActor
    func prepareDPIBypassForTermination() {
        browserDPIBypassService.prepareForTermination()
    }

    func processControlCount(for kind: ExternalToolRuntimeKind) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return processControls[kind]?.count ?? 0
    }

    var aria2RPCSessionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return aria2RPCSessions.count
    }
}
