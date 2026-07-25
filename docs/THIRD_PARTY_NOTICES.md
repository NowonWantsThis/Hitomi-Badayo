# Third-Party Notices

Hitomi Badayo project source is licensed under the MIT License in the root
`LICENSE` file. The components identified below retain their own copyright and
licensing terms.

## aria2 1.37.0

Hitomi Badayo bundles an arm64 `aria2c` command-line executable as a separate
helper process.

- Project: https://github.com/aria2/aria2
- License: GNU General Public License version 2 or later
- License text: `Resources/ThirdParty/aria2-COPYING.txt`
- Corresponding source: `Resources/ThirdParty/aria2-1.37.0.tar.xz`
- Local patch and build record: `Resources/ThirdParty/`

The source archive SHA-256 is
`60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b`.

## SpoofDPI 1.5.3

Hitomi Badayo bundles the official arm64 macOS `spoofdpi` executable as a
separate local HTTP proxy helper process for the optional app and browser DPI
bypass.

- Project: https://github.com/xvzc/SpoofDPI
- License: Apache License 2.0
- License text: `LICENSES/spoofdpi-Apache-2.0.txt`
- Upstream release: https://github.com/xvzc/SpoofDPI/releases/tag/v1.5.3

The upstream `spoofdpi_1.5.3_darwin_arm64.tar.gz` archive SHA-256 is
`4226058c15516f071e5d4495ab7bf6da14c6ead4a16c4c7bc96dd1a720aad295`.

## ratelimit 2.2.1 compatibility code

`Resources/Python/hitomi_compat_runner.py` contains code adapted from the
fixed-window decorator API and implementation in Tomas Basham's `ratelimit`
2.2.1.

- Project: https://github.com/tomasbasham/ratelimit
- License: MIT
- License text: `LICENSES/ratelimit-MIT.txt`

## SaidBySolo extractor implementations

The native Talk OP.GG, Naver Post, and Discord Emoji resolvers were developed
with reference to MIT-licensed extractor implementations by SaidBySolo.

- Copyright: Copyright (c) 2020 SaidBySolo
- License: MIT
- License text: `LICENSES/saidbysolo-MIT.txt`

## yt-dlp

yt-dlp is not bundled in the source tree or initial app archive. The user may
request installation of the official `yt-dlp_macos` release binary.

- Project: https://github.com/yt-dlp/yt-dlp
- Source license: Unlicense
- Release binary note: the official macOS executable contains third-party
  components under the licenses recorded by upstream
- Upstream third-party licenses:
  https://github.com/yt-dlp/yt-dlp/blob/master/THIRD_PARTY_LICENSES.txt

The app retrieves the upstream SHA-256 list before installing the binary.

## FFmpeg and ffprobe

FFmpeg and ffprobe are optional and are not bundled in the source tree or app
archive. The managed installer obtains current Apple-silicon macOS builds from
`ffmpeg.martin-riedl.de`. FFmpeg is primarily LGPL-2.1-or-later, but enabling
GPL components changes the applicable license for a particular build. The
provider's license and build information should be reviewed whenever the
managed build changes.

- Project: https://ffmpeg.org/
- License guidance: https://ffmpeg.org/legal.html
- Build provider: https://ffmpeg.martin-riedl.de/

The app downloads these tools directly from the named provider only after the
user requests managed-tool installation.
