# Hitomi Badayo

Hitomi Badayo is a native download manager for Apple silicon Macs. It combines
a queue-oriented macOS interface with source-specific naming, folders,
authentication, previews, archiving, and media download workflows.

The application is an independent native implementation informed by observed
behavior from an existing desktop downloader. No original executable or
decompiled bytecode is included in this repository.

Version 0.4.0 is a beta test release.

## Highlights

- Native SwiftUI and AppKit interface for macOS
- Concurrent queue with reordering, cancellation, retry, and per-item progress
- Hitomi, YouTube, and other supported site handlers
- Source-specific output folders, naming templates, ZIP and CBZ options
- Embedded login windows and local cookie storage for sources that require them
- Optional browser DPI bypass through a loopback-only SpoofDPI proxy
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

The beta build is ad-hoc signed, not Developer ID signed or notarized.
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
helper processes with their license information. yt-dlp, FFmpeg, and ffprobe
are optional and are downloaded only after the user requests managed-tool
installation. See [THIRD_PARTY_NOTICES.md](docs/THIRD_PARTY_NOTICES.md).

## Browser DPI bypass

The optional control is under **Settings > Network > Browser DPI Bypass**.
Turning it on starts a proxy bound only to `127.0.0.1` and opens macOS Network
settings. Set both **Web Proxy (HTTP)** and **Secure Web Proxy (HTTPS)** to the
address shown by the app. The status updates when macOS applies or removes
those settings. Turn both system proxies off when disabling the feature or
before quitting the app; if they remain connected, the app opens Network
settings during shutdown so they can be removed.

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
