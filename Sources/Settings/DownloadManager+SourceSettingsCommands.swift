import Foundation

extension DownloadManager {
    func saveYouTubePreferredLanguage() {
        settingsStore.persistYouTubePreferredLanguage()
        appStatusStore.setSummary(
            settingsStore.youtubePreferredLanguage.isEmpty
                ? "YouTube language cleared"
                : "YouTube language saved"
        )
    }

    func setYouTubeDownloadThumbnail(_ enabled: Bool) {
        settingsStore.youtubeDownloadThumbnail = enabled
        settingsStore.persistYouTubeDownloadThumbnail()
        appStatusStore.setSummary(
            enabled ? "YouTube thumbnail on" : "YouTube thumbnail off"
        )
    }

    func setYouTubeReversePlaylist(_ enabled: Bool) {
        settingsStore.youtubeReversePlaylist = enabled
        settingsStore.persistYouTubeReversePlaylist()
        appStatusStore.setSummary(
            enabled
                ? "YouTube reverse playlist on"
                : "YouTube reverse playlist off"
        )
    }

    func setYouTubeUseUploadDateForFileModificationTime(_ enabled: Bool) {
        settingsStore.youtubeUseUploadDateForFileModificationTime = enabled
        settingsStore.persistYouTubeUploadDatePreference()
        appStatusStore.setSummary(
            enabled
                ? "YouTube upload-date file time on"
                : "YouTube upload-date file time off"
        )
    }

    func setYouTubeDownloadAutoSubtitles(_ enabled: Bool) {
        settingsStore.youtubeDownloadAutoSubtitles = enabled
        settingsStore.persistYouTubeSubtitles()
        appStatusStore.setSummary(
            enabled
                ? "YouTube auto subtitles on"
                : "YouTube auto subtitles off"
        )
    }

    func saveYouTubeSubtitleSettings() {
        settingsStore.persistYouTubeSubtitles()
        appStatusStore.setSummary(
            settingsStore.youtubeDownloadAutoSubtitles
                ? "YouTube subtitles saved"
                : "YouTube subtitles off"
        )
    }

    func setYouTubeEmbedChapters(_ enabled: Bool) {
        settingsStore.youtubeEmbedChapters = enabled
        settingsStore.persistYouTubeEmbedChapters()
        appStatusStore.setSummary(
            enabled ? "YouTube chapters on" : "YouTube chapters off"
        )
    }

    func setYouTubePreferEnhancedBitrate(_ enabled: Bool) {
        settingsStore.youtubePreferEnhancedBitrate = enabled
        settingsStore.persistYouTubeEnhancedBitrate()
        appStatusStore.setSummary(
            enabled
                ? "YouTube enhanced bitrate on"
                : "YouTube enhanced bitrate off"
        )
    }

    func setInstagramIncludeStories(_ enabled: Bool) {
        settingsStore.instagramIncludeStories = enabled
        settingsStore.persistInstagramIncludeStories()
        appStatusStore.setSummary(
            enabled
                ? "Instagram profile stories on"
                : "Instagram profile stories off"
        )
    }

    func saveYouTubeVideoCodecSort() {
        settingsStore.youtubeVideoCodecPriority = YouTubeVideoCodec.priority(fromLegacySort: settingsStore.youtubeVideoCodecSort)
        settingsStore.persistYouTubeCodecPriority()
        appStatusStore.setSummary(
            "YouTube codec priority: \(YouTubeVideoCodec.priorityLabel(settingsStore.youtubeVideoCodecPriority))"
        )
    }

    func setYouTubeVideoCodecPriority(_ priority: [YouTubeVideoCodec]) {
        settingsStore.youtubeVideoCodecPriority = YouTubeVideoCodec.normalizedPriority(priority)
        settingsStore.persistYouTubeCodecPriority()
        appStatusStore.setSummary(
            "YouTube codec priority: \(YouTubeVideoCodec.priorityLabel(settingsStore.youtubeVideoCodecPriority))"
        )
    }

    func saveYouTubePreferredResolution() {
        settingsStore.persistYouTubePreferredResolution()
        appStatusStore.setSummary(
            settingsStore.youtubePreferredResolution.isEmpty
                ? "YouTube resolution cleared"
                : "YouTube resolution saved"
        )
    }

    func saveYouTubePreferredAudioLanguage() {
        settingsStore.persistYouTubePreferredAudioLanguage()
        appStatusStore.setSummary(
            settingsStore.youtubePreferredAudioLanguage.isEmpty
                ? "YouTube audio track cleared"
                : "YouTube audio track saved"
        )
    }

    func saveSOOPPreferredResolution() {
        settingsStore.persistSOOPPreferredResolution()
        appStatusStore.setSummary(
            settingsStore.soopPreferredResolution.isEmpty
                ? "SOOP resolution cleared"
                : "SOOP resolution saved"
        )
    }

    func savePixivUgoiraFileFormat() {
        settingsStore.persistPixivUgoira()
        appStatusStore.setSummary("Pixiv ugoira settings saved")
    }

    func addPawchiveSiteAddress() {
        let draft = presentation.settingsWindow
        guard let normalized = PawchiveResolver.normalizedSiteAddress(
            draft.pawchiveSiteAddressDraft
        ) else {
            appStatusStore.setSummary("Enter a valid Pawchive site address")
            return
        }
        var addresses = settingsStore.pawchiveSiteAddresses
        guard !addresses.contains(where: { $0.caseInsensitiveCompare(normalized) == .orderedSame }) else {
            draft.pawchiveSiteAddressDraft = ""
            appStatusStore.setSummary("Pawchive site address already added")
            return
        }
        addresses.append(normalized)
        settingsStore.pawchiveSiteAddresses = PawchiveResolver.normalizedSiteAddresses(addresses)
        draft.pawchiveSiteAddressDraft = ""
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Pawchive site address added")
    }

    func removePawchiveSiteAddress(_ address: String) {
        settingsStore.pawchiveSiteAddresses.removeAll {
            $0.caseInsensitiveCompare(address) == .orderedSame
        }
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Pawchive site address removed")
    }

    func resetPawchiveSiteAddresses() {
        settingsStore.pawchiveSiteAddresses = PawchiveResolver.defaultSiteAddresses
        presentation.settingsWindow.pawchiveSiteAddressDraft = ""
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Pawchive site addresses restored")
    }

    func setPawchiveDownloadLargeOriginalFiles(_ enabled: Bool) {
        settingsStore.pawchiveDownloadLargeOriginalFiles = enabled
        settingsStore.persistPawchive()
        appStatusStore.setSummary(
            enabled
                ? "Pawchive PSD originals enabled"
                : "Pawchive PSD originals disabled"
        )
    }

    func setPawchiveDownloadImages(_ enabled: Bool) {
        settingsStore.pawchiveDownloadImages = enabled
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Kemono friends file types saved")
    }

    func setPawchiveDownloadVideos(_ enabled: Bool) {
        settingsStore.pawchiveDownloadVideos = enabled
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Kemono friends file types saved")
    }

    func setPawchiveDownloadHTML(_ enabled: Bool) {
        settingsStore.pawchiveDownloadHTML = enabled
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Kemono friends file types saved")
    }

    func setPawchiveDownloadOtherFiles(_ enabled: Bool) {
        settingsStore.pawchiveDownloadOtherFiles = enabled
        settingsStore.persistPawchive()
        appStatusStore.setSummary("Kemono friends file types saved")
    }

    var pawchiveFileTypeSelection: PawchiveFileTypeSelection {
        PawchiveFileTypeSelection(
            images: settingsStore.pawchiveDownloadImages,
            videos: settingsStore.pawchiveDownloadVideos,
            html: settingsStore.pawchiveDownloadHTML,
            other: settingsStore.pawchiveDownloadOtherFiles
        )
    }

    func saveM3U8RemuxSetting() {
        let delay = settingsStore.persistHLS()
        var options: [String] = []
        if settingsStore.remuxM3U8ToMP4 { options.append("MP4 remux") }
        if settingsStore.hlsContinueOnSegmentFailure { options.append("skip bad segments") }
        if delay > 0 { options.append("\(delay) ms delay") }
        appStatusStore.setSummary(
            options.isEmpty
                ? "HLS settings off"
                : "HLS settings saved: \(options.joined(separator: ", "))"
        )
    }
}
