# Bundled aria2

Hitomi Badayo bundles a command-line build of aria2 1.37.0 for Apple Silicon
Macs. The included `aria2-apple-tls-no-keychain.patch` disables AppleTLS client
certificate fingerprint lookup so the helper cannot query macOS Keychain.

- Upstream: https://github.com/aria2/aria2
- Source archive: `aria2-1.37.0.tar.xz`
- Source SHA-256: `60a420ad7085eb616cb6e2bdf0a7206d68ff3d37fb5a956dc44242eb2f79b66b`
- License: GPL-2.0-or-later; see `aria2-COPYING.txt`
- Deployment target: macOS 14.0, arm64
- TLS backend: AppleTLS, with Keychain identity lookup disabled

Run `Scripts/build-aria2.sh` from a source checkout to reproduce
`Resources/Tools/aria2c`. A release app also carries the same script beside
this document as `build-aria2.sh`. The build requires macOS with Xcode Command
Line Tools and disables optional third-party dependencies that Hitomi Badayo
does not use. BitTorrent, HTTPS, message digests, PKCS#12 client certificates,
and the local JSON-RPC server remain enabled.
