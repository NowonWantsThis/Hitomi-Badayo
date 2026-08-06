# Hitomi Badayo

<p align="center">
  <strong><a href="README.md"><kbd>English</kbd></a></strong>
  <a href="README.ja.md"><kbd>日本語</kbd></a>
  <a href="README.zh-Hans.md"><kbd>简体中文</kbd></a>
  <a href="README.zh-Hant.md"><kbd>繁體中文</kbd></a>
  <a href="README.ko.md"><kbd>한국어</kbd></a>
</p>

<p>
<img width="687" height="431" alt="sc" src="https://github.com/user-attachments/assets/7105eceb-33c9-441b-976b-b40a1492f79e" />
</p>

Hitomi Badayo is a native download manager for Apple silicon Macs. It combines
a queue-oriented macOS interface with source-specific naming, folders,
authentication, previews, archiving, and media download workflows.

The application is an independent native implementation informed by observed
behavior from an existing desktop downloader. No original executable or
decompiled bytecode is included in this repository.

Version 0.5.0 completes the maintainability refactor while preserving the
user-facing behavior, settings, saved data, and download output of version
0.4.2.

## Highlights

- Native SwiftUI and AppKit interface for macOS
- Concurrent queue with reordering, cancellation, retry, and per-item progress
- Hitomi, Pixiv, YouTube, Kemono-style archives, Booru sites, and other
  supported source handlers
- Source-specific output folders, naming templates, ZIP and CBZ options
- Embedded login windows and local cookie storage for sources that require them
- Optional app-only or app-and-browser DPI bypass through a loopback-only SpoofDPI proxy
- Thumbnail previews, output opening, graceful live-recording stop, and cleanup
- English, Japanese, Simplified Chinese, Traditional Chinese, and Korean UI

Site behavior changes over time. A handler that works in one release may need
maintenance when its source site changes.

## Requirements

- Apple silicon Mac (arm64)
- macOS 14 Sonoma or later
- Internet access for online sources and optional helper installation

## Install a release

1. Download `Hitomi-Badayo-macOS.zip` from the matching GitHub Release.
2. Unzip it and move `Hitomi Badayo.app` to Applications if desired.
3. Control-click the app and choose **Open** on first launch.
4. If macOS still blocks it, use **System Settings > Privacy & Security > Open
   Anyway**.

The distributed build is ad-hoc signed, not Developer ID signed or notarized.
Do not disable Gatekeeper globally. See [INSTALLATION.md](docs/INSTALLATION.md) for
data locations and first-run details.

## Build from source

Install the Xcode command-line tools, then run:

```sh
xcode-select --install
./build.sh
```

The app is written to `Build/Hitomi Badayo.app`. To choose another output
directory:

```sh
./build.sh Build-Local
```

The build uses the system macOS SDK and does not require an Xcode project.

## External tools

Apple-silicon builds of aria2 1.37.0 and SpoofDPI 1.5.3 are bundled as separate
helper processes with their license information. yt-dlp, Deno, FFmpeg, and
ffprobe are optional and are downloaded only after the user requests
managed-tool installation. Deno is passed directly to yt-dlp for YouTube's
JavaScript challenges. See
[THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).

## DPI bypass

The optional control is under **Settings > Network > DPI Bypass** and defaults
to **Off**. **App Only** starts SpoofDPI on `127.0.0.1` for supported Hitomi
Badayo downloads without changing macOS proxy settings or requesting
administrator permission. **App & Browsers** also configures the active macOS
Web Proxy (HTTP) and Secure Web Proxy (HTTPS), which requires administrator
approval. The app saves the previous system proxy values and restores them
when that mode is disabled or the app quits.

Manual proxy preferences are stored separately. When DPI bypass and a manual
proxy are both enabled, the local SpoofDPI route takes priority; the manual
proxy is preserved and becomes active again after DPI bypass is turned off.

## Data and privacy

Queue state, settings, login cookies, helper tools, and downloads stay on the
user's Mac. The app has no project-operated telemetry service. Network requests
still go to the source sites and optional tool providers selected by the user.
See [PRIVACY.md](docs/PRIVACY.md) for exact locations and limitations.

## Responsible use

Use the application only for material that you are authorized to access and
retain. Users are responsible for copyright, account, subscription, and source
site terms that apply to their downloads. The project is not affiliated with
the supported websites, and site names or marks remain the property of their
respective owners.

## Project documents

- [INSTALLATION.md](docs/INSTALLATION.md): installation and first-run behavior
- [CHANGELOG.md](docs/CHANGELOG.md): release history
- [PRIVACY.md](docs/PRIVACY.md): local data and network behavior
- [SECURITY.md](docs/SECURITY.md): vulnerability reporting guidance
- [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md): bundled and optional tools

## License

Hitomi Badayo project source is licensed under the [MIT License](LICENSE).
Bundled and optional external components retain the licenses recorded in
[THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).
