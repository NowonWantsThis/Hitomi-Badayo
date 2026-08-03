import Combine
import Foundation

@MainActor
final class ExternalToolStore: ObservableObject {
    @Published var ytdlpPath: String
    @Published var denoPath: String
    @Published var ffmpegPath: String
    @Published var pythonPath: String
    @Published var aria2Path: String
    @Published var ffmpegTranscodeEnabled: Bool
    @Published var ffmpegVideoCodec: String
    @Published var ffmpegAudioCodec: String
    @Published var ffmpegVideoBitrate: String
    @Published var ffmpegAudioBitrate: String
    @Published var ffmpegCRF: String
    @Published var ffmpegPreset: String
    @Published private(set) var isInstalling: Bool
    @Published private(set) var installStatus: String

    init(
        defaults: UserDefaults = .standard,
        isInstalling: Bool = false,
        installStatus: String = "Tool Manager Ready"
    ) {
        ytdlpPath = ExternalToolSettings.path(
            for: .ytdlp,
            defaults: defaults
        )
        denoPath = ExternalToolSettings.path(
            for: .deno,
            defaults: defaults
        )
        ffmpegPath = ExternalToolSettings.path(
            for: .ffmpeg,
            defaults: defaults
        )
        pythonPath = defaults.string(
            forKey: "pythonScriptPythonPath"
        ) ?? ""
        aria2Path = ExternalToolSettings.path(
            for: .aria2c,
            defaults: defaults
        )
        ffmpegTranscodeEnabled = defaults.object(
            forKey: "ffmpegTranscodeEnabled"
        ) as? Bool ?? false
        ffmpegVideoCodec = defaults.string(
            forKey: "ffmpegVideoCodec"
        ) ?? FFmpegTranscodeOptions.defaults.videoCodec
        ffmpegAudioCodec = defaults.string(
            forKey: "ffmpegAudioCodec"
        ) ?? FFmpegTranscodeOptions.defaults.audioCodec
        ffmpegVideoBitrate = defaults.string(
            forKey: "ffmpegVideoBitrate"
        ) ?? FFmpegTranscodeOptions.defaults.videoBitrate
        ffmpegAudioBitrate = defaults.string(
            forKey: "ffmpegAudioBitrate"
        ) ?? FFmpegTranscodeOptions.defaults.audioBitrate
        ffmpegCRF = defaults.string(
            forKey: "ffmpegCRF"
        ) ?? FFmpegTranscodeOptions.defaults.crf
        ffmpegPreset = defaults.string(
            forKey: "ffmpegPreset"
        ) ?? FFmpegTranscodeOptions.defaults.preset
        self.isInstalling = isInstalling
        self.installStatus = installStatus
    }

    func setInstalling(_ isInstalling: Bool) {
        self.isInstalling = isInstalling
    }

    func setInstallStatus(_ status: String) {
        installStatus = status
    }
}
