# Installation

## Requirements

- Apple Silicon Mac (arm64)
- macOS 14 Sonoma or later
- An internet connection for online sources and optional helper-tool setup

The beta release does not support Intel Macs.

## Install

1. Unzip `Hitomi-Badayo-macOS.zip`.
2. Move `Hitomi Badayo.app` to the Applications folder if desired.
3. Control-click the app and choose **Open** for the first launch.
4. If macOS still blocks it, open **System Settings > Privacy & Security** and
   choose **Open Anyway** for Hitomi Badayo.

This release is ad-hoc signed for bundle integrity, but it is not signed with an
Apple Developer ID and is not notarized. Do not disable Gatekeeper globally.

## First-Run Data

The app creates its own files when first launched. No existing downloader
installation is needed.

- Queue, history, cookies, and managed tools:
  `~/Library/Application Support/Hitomi Badayo/`
- Preferences: the macOS preferences domain for
  `io.github.nowonwantsthis.HitomiBadayo`
- Default output: the current user's Downloads folder, separated into
  source-named subfolders created on demand. Hitomi/E(x)Hentai uses
  `hitomi_downloaded`; other examples include `youtube_downloaded`,
  `pixiv_downloaded`, and `local_downloaded`.

The distributed app archive contains no preconfigured queue, settings, cookies,
account data, or downloaded files.

## Optional Helper Tools

Core native downloads work without extra tools. Some video fallbacks, full
YouTube extraction, live recording finalization, conversion, and torrent
workflows need yt-dlp, Deno, FFmpeg, or aria2c.

Open **Options > Settings > Advanced > External Tools** and use the managed-tool
install action. aria2c is copied from the app bundle. yt-dlp, Deno, FFmpeg, and
ffprobe are downloaded over HTTPS and verified against their published SHA-256
values before installation. Hitomi Badayo supplies Deno's absolute path to
yt-dlp, so Finder-launched apps do not depend on the shell `PATH`.

Python-based compatibility plugins require a separate Python 3 installation;
the native download handlers do not require Python.

Only download material that you are authorized to access and retain.
